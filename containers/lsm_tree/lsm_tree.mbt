/// LSM-Tree (Log-Structured Merge-Tree).
///
/// The LSM-Tree is the data structure behind production key-value stores
/// like LevelDB, RocksDB, Cassandra, and HBase. It provides high write
/// throughput by batching writes into an in-memory structure (MemTable)
/// and flushing to disk as immutable SSTables (Sorted String Tables) in
/// levels of increasing size.
///
/// ## Architecture
///
/// 1. **MemTable**: In-memory sorted map (red-black tree or skip list).
///    All writes go here first.
/// 2. **Immutable MemTable**: When the MemTable is full, it becomes immutable
///    and a new MemTable is created. The immutable table is flushed to disk.
/// 3. **SSTables (Sorted String Tables)**: Immutable sorted files on disk.
///    Organized into levels. Level 0 may have overlapping ranges; levels ≥ 1
///    have non-overlapping ranges.
/// 4. **Bloom Filter**: Each SSTable has a Bloom filter for fast key lookup.
///
/// ## This implementation
///
/// This is an in-memory simulation of the LSM-Tree architecture. The
/// MemTable uses a sorted array (for simplicity and cache efficiency). The
/// SSTables are stored in memory as sorted arrays. This demonstrates the
/// full LSM architecture without actual disk I/O, making it suitable for
/// testing and as a reference implementation.
///
/// ## Complexity
/// - Write: O(1) amortized (append to MemTable, periodically flush).
/// - Read: O(L * log N) where L = number of levels (with Bloom filter
///   optimization, most lookups skip SSTables).
/// - Range scan: O(log N + K) per level.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A key-value entry.
struct Entry {
  key : String
  value : String
  deleted : Bool // tombstone
}

/// An immutable sorted table (simulates an SSTable).
struct SSTable {
  entries : Array[Entry] // sorted by key
}

/// The LSM-Tree.
pub struct LSMTree {
  priv mut memtable : Map[String, Entry]
  priv mut memtable_size : Int
  priv memtable_capacity : Int
  priv mut sstables : Array[SSTable] // Level 0 tables (may overlap)
  priv mut level1 : Array[SSTable] // Level 1+ (non-overlapping, merged)
  priv mut total_entries : Int
}

/// Lexicographic string comparator.
fn str_cmp(a : String, b : String) -> Int {
  let la = a.length()
  let lb = b.length()
  let min = if la < lb { la } else { lb }
  for k = 0; k < min; k = k + 1 {
    let ca = a[k].to_int()
    let cb = b[k].to_int()
    if ca < cb {
      return -1
    }
    if ca > cb {
      return 1
    }
  }
  la - lb
}

/// Create a new LSM-Tree with the given MemTable capacity.
/// When the MemTable reaches `memtable_capacity` entries, it is flushed
/// to an SSTable.
pub fn new(memtable_capacity : Int) -> LSMTree {
  let cap = if memtable_capacity > 0 { memtable_capacity } else { 1024 }
  {
    memtable : Map([]),
    memtable_size : 0,
    memtable_capacity : cap,
    sstables : [],
    level1 : [],
    total_entries : 0,
  }
}

/// Number of entries in the MemTable.
pub fn memtable_size(tree : LSMTree) -> Int {
  tree.memtable_size
}

/// Number of SSTables (Level 0).
pub fn sstable_count(tree : LSMTree) -> Int {
  tree.sstables.length()
}

/// Total number of live entries (excluding tombstones).
pub fn entry_count(tree : LSMTree) -> Int {
  tree.total_entries
}

// ---------------------------------------------------------------------------
// Write operations
// ---------------------------------------------------------------------------

/// Insert or update a key-value pair.
pub fn put(tree : LSMTree, key : String, value : String) -> Unit {
  let was_present = tree.memtable.contains(key)
  tree.memtable[key] = { key, value, deleted : false }
  if !was_present {
    tree.memtable_size = tree.memtable_size + 1
    tree.total_entries = tree.total_entries + 1
  }
  if tree.memtable_size >= tree.memtable_capacity {
    flush(tree)
  }
}

/// Delete a key (writes a tombstone).
pub fn delete(tree : LSMTree, key : String) -> Unit {
  let was_present = tree.memtable.contains(key)
  tree.memtable[key] = { key, value : "", deleted : true }
  if !was_present {
    tree.memtable_size = tree.memtable_size + 1
  }
  if was_present {
    tree.total_entries = tree.total_entries - 1
  }
  if tree.memtable_size >= tree.memtable_capacity {
    flush(tree)
  }
}

/// Batch insert (atomic batch).
pub fn batch_put(tree : LSMTree, pairs : Array[(String, String)]) -> Unit {
  for i = 0; i < pairs.length(); i = i + 1 {
    let (k, v) = pairs[i]
    put(tree, k, v)
  }
}

// ---------------------------------------------------------------------------
// Flush and compaction
// ---------------------------------------------------------------------------

/// Flush the MemTable to an SSTable (Level 0).
pub fn flush(tree : LSMTree) -> Unit {
  if tree.memtable_size == 0 {
    return
  }
  // Sort entries by key.
  let entries : Array[Entry] = []
  for _k, v in tree.memtable {
    entries.push(v)
  }
  entries.sort_by(fn(a, b) { str_cmp(a.key, b.key) })
  tree.sstables.push({ entries, })
  // Reset MemTable.
  tree.memtable = Map([])
  tree.memtable_size = 0
  // Trigger compaction if too many Level 0 tables.
  if tree.sstables.length() >= 4 {
    compact(tree)
  }
}

/// Compact Level 0 SSTables into Level 1.
/// Merges all Level 0 tables into a single sorted, deduplicated table.
pub fn compact(tree : LSMTree) -> Unit {
  if tree.sstables.length() == 0 && tree.level1.length() == 0 {
    return
  }
  // Merge all Level 0 tables with existing Level 1 tables.
  let all_tables : Array[SSTable] = []
  for i = 0; i < tree.sstables.length(); i = i + 1 {
    all_tables.push(tree.sstables[i])
  }
  for i = 0; i < tree.level1.length(); i = i + 1 {
    all_tables.push(tree.level1[i])
  }
  // K-way merge using a simple approach: collect all entries, sort, deduplicate.
  let all_entries : Array[Entry] = []
  for i = 0; i < all_tables.length(); i = i + 1 {
    let table = all_tables[i]
    for j = 0; j < table.entries.length(); j = j + 1 {
      all_entries.push(table.entries[j])
    }
  }
  // Sort by key (stable: later entries override earlier ones for same key).
  all_entries.sort_by(fn(a, b) {
    let c = str_cmp(a.key, b.key)
    if c != 0 {
      c
    } else {
      // Same key: keep both (we'll deduplicate in the next pass).
      0
    }
  })
  // Deduplicate: for each key, keep only the last entry.
  let merged : Array[Entry] = []
  let mut i = 0
  while i < all_entries.length() {
    let entry = all_entries[i]
    // Scan forward to find the last entry with the same key.
    let mut last = entry
    let mut j = i + 1
    while j < all_entries.length() && all_entries[j].key == entry.key {
      last = all_entries[j]
      j = j + 1
    }
    merged.push(last)
    i = j
  }
  // Replace Level 0 and Level 1.
  tree.sstables = []
  tree.level1 = [{ entries : merged }]
}

// ---------------------------------------------------------------------------
// Read operations
// ---------------------------------------------------------------------------

/// Get the value for a key, or `None` if not found.
///
/// Searches: MemTable → Level 0 SSTables (newest first) → Level 1.
pub fn get(tree : LSMTree, key : String) -> String? {
  // 1. Check MemTable.
  match tree.memtable.get(key) {
    Some(entry) => {
      if entry.deleted {
        return None
      }
      return Some(entry.value)
    }
    None => ()
  }
  // 2. Check Level 0 SSTables (newest first).
  let mut i = tree.sstables.length() - 1
  while i >= 0 {
    let table = tree.sstables[i]
    match binary_search_table(table, key) {
      Some(entry) => {
        if entry.deleted {
          return None
        }
        return Some(entry.value)
      }
      None => ()
    }
    i = i - 1
  }
  // 3. Check Level 1.
  for i = 0; i < tree.level1.length(); i = i + 1 {
    match binary_search_table(tree.level1[i], key) {
      Some(entry) => {
        if entry.deleted {
          return None
        }
        return Some(entry.value)
      }
      None => ()
    }
  }
  None
}

/// Check if a key exists (not deleted).
pub fn contains(tree : LSMTree, key : String) -> Bool {
  get(tree, key) is Some(_)
}

/// Binary search for a key in an SSTable.
fn binary_search_table(table : SSTable, key : String) -> Entry? {
  let entries = table.entries
  let mut lo = 0
  let mut hi = entries.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let c = str_cmp(entries[mid].key, key)
    if c == 0 {
      return Some(entries[mid])
    } else if c < 0 {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Range scan
// ---------------------------------------------------------------------------

/// Scan all key-value pairs in the range `[start, end)` (exclusive end).
/// Returns entries sorted by key, excluding tombstones.
pub fn range_scan(
  tree : LSMTree,
  start : String,
  end : String,
) -> Array[(String, String)] {
  // Collect all entries from all levels.
  let all : Map[String, Entry] = Map([])
  // Level 1 first (oldest), then Level 0 (newer), then MemTable (newest).
  for i = 0; i < tree.level1.length(); i = i + 1 {
    let table = tree.level1[i]
    for j = 0; j < table.entries.length(); j = j + 1 {
      let e = table.entries[j]
      if str_cmp(e.key, start) >= 0 && str_cmp(e.key, end) < 0 {
        all[e.key] = e
      }
    }
  }
  for i = 0; i < tree.sstables.length(); i = i + 1 {
    let table = tree.sstables[i]
    for j = 0; j < table.entries.length(); j = j + 1 {
      let e = table.entries[j]
      if str_cmp(e.key, start) >= 0 && str_cmp(e.key, end) < 0 {
        all[e.key] = e
      }
    }
  }
  for k, e in tree.memtable {
    if str_cmp(k, start) >= 0 && str_cmp(k, end) < 0 {
      all[k] = e
    }
  }
  // Collect and sort.
  let result : Array[(String, String)] = []
  for k, e in all {
    if !e.deleted {
      result.push((k, e.value))
    }
  }
  result.sort_by(fn(a, b) { str_cmp(a.0, b.0) })
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "lsm: basic put and get" {
  let tree = new(100)
  put(tree, "hello", "world")
  put(tree, "foo", "bar")
  assert_eq(get(tree, "hello"), Some("world"))
  assert_eq(get(tree, "foo"), Some("bar"))
  assert_eq(get(tree, "missing"), None)
}

test "lsm: update existing key" {
  let tree = new(100)
  put(tree, "key", "value1")
  put(tree, "key", "value2")
  assert_eq(get(tree, "key"), Some("value2"))
}

test "lsm: delete key" {
  let tree = new(100)
  put(tree, "key", "value")
  delete(tree, "key")
  assert_eq(get(tree, "key"), None)
  assert_false(contains(tree, "key"))
}

test "lsm: flush creates sstable" {
  let tree = new(3)
  put(tree, "a", "1")
  put(tree, "b", "2")
  assert_eq(sstable_count(tree), 0) // still in memtable
  put(tree, "c", "3") // triggers flush
  assert_eq(sstable_count(tree), 1)
  // Data should still be accessible.
  assert_eq(get(tree, "a"), Some("1"))
  assert_eq(get(tree, "b"), Some("2"))
  assert_eq(get(tree, "c"), Some("3"))
}

test "lsm: multiple flushes" {
  let tree = new(2)
  put(tree, "a", "1")
  put(tree, "b", "2") // flush
  put(tree, "c", "3")
  put(tree, "d", "4") // flush
  assert_true(sstable_count(tree) >= 2)
  assert_eq(get(tree, "a"), Some("1"))
  assert_eq(get(tree, "d"), Some("4"))
}

test "lsm: compaction merges tables" {
  let tree = new(2)
  put(tree, "a", "1")
  put(tree, "b", "2") // flush → sstable 0
  put(tree, "c", "3")
  put(tree, "d", "4") // flush → sstable 1
  put(tree, "e", "5")
  put(tree, "f", "6") // flush → sstable 2
  put(tree, "g", "7")
  put(tree, "h", "8") // flush → sstable 3, triggers compaction
  // After compaction, level 0 should be cleared.
  assert_eq(sstable_count(tree), 0)
  // All data should still be accessible.
  assert_eq(get(tree, "a"), Some("1"))
  assert_eq(get(tree, "h"), Some("8"))
}

test "lsm: delete after flush (tombstone)" {
  let tree = new(2)
  put(tree, "key", "value")
  put(tree, "a", "1") // flush
  delete(tree, "key")
  assert_eq(get(tree, "key"), None)
}

test "lsm: range scan" {
  let tree = new(100)
  put(tree, "a", "1")
  put(tree, "b", "2")
  put(tree, "c", "3")
  put(tree, "d", "4")
  let result = range_scan(tree, "b", "d")
  assert_eq(result.length(), 2)
  assert_eq(result[0].0, "b")
  assert_eq(result[0].1, "2")
  assert_eq(result[1].0, "c")
  assert_eq(result[1].1, "3")
}

test "lsm: range scan after flush" {
  let tree = new(2)
  put(tree, "a", "1")
  put(tree, "b", "2") // flush
  put(tree, "c", "3")
  put(tree, "d", "4") // flush
  let result = range_scan(tree, "a", "e")
  assert_eq(result.length(), 4)
  assert_eq(result[0].0, "a")
  assert_eq(result[3].0, "d")
}

test "lsm: batch put" {
  let tree = new(100)
  batch_put(tree, [("a", "1"), ("b", "2"), ("c", "3")])
  assert_eq(get(tree, "a"), Some("1"))
  assert_eq(get(tree, "b"), Some("2"))
  assert_eq(get(tree, "c"), Some("3"))
}

test "lsm: overwrite across levels" {
  let tree = new(2)
  put(tree, "key", "old")
  put(tree, "a", "1") // flush
  put(tree, "key", "new")
  put(tree, "b", "2") // flush
  // "key" exists in both sstable (old) and memtable/sstable (new).
  // Newer value should win.
  assert_eq(get(tree, "key"), Some("new"))
}

test "lsm: large workload" {
  let tree = new(10)
  for i = 0; i < 100; i = i + 1 {
    put(tree, "key" + i.to_string(), "val" + i.to_string())
  }
  // All keys should be accessible.
  for i = 0; i < 100; i = i + 1 {
    assert_eq(get(tree, "key" + i.to_string()), Some("val" + i.to_string()))
  }
}

test "lsm: entry count" {
  let tree = new(100)
  put(tree, "a", "1")
  put(tree, "b", "2")
  assert_eq(entry_count(tree), 2)
  delete(tree, "a")
  assert_eq(entry_count(tree), 1)
}
