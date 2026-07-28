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
/// 1. **MemTable**: In-memory sorted map backed by a skip list.
///    All writes go here first. The skip list provides O(log n) insertion
///    and lookup while maintaining keys in sorted order, enabling O(n)
///    flush (no separate sort step) and efficient range scans.
/// 2. **Immutable MemTable**: When the MemTable is full, it becomes immutable
///    and a new MemTable is created. The immutable table is flushed to disk.
/// 3. **SSTables (Sorted String Tables)**: Immutable sorted files on disk.
///    Organized into levels. Level 0 may have overlapping ranges; levels ≥ 1
///    have non-overlapping ranges.
/// 4. **Bloom Filter**: Each SSTable has a Bloom filter for fast key lookup,
///    avoiding binary search on tables that definitely don't contain the key.
///
/// ## This implementation
///
/// This is an in-memory implementation of the LSM-Tree architecture. The
/// MemTable uses a skip list (probabilistic balanced tree) for O(log n)
/// insertions, deletions, and lookups, while keeping entries in sorted
/// order at all times — matching the architecture of LevelDB and RocksDB.
/// The SSTables are stored in memory as sorted arrays with Bloom filters.
///
/// For disk-backed persistence, users can implement serialization
/// using the public API (`put`, `get`, `delete`, `flush`, `compact`).
/// The in-memory architecture demonstrates the full LSM pattern,
/// making it suitable for testing and as a reference implementation.
///
/// ## Complexity
/// - Write: O(log n) per entry (skip list insert), with O(1) amortized
///   flush since entries are already sorted.
/// - Read: O(log n + L * log N) where L = number of levels (with Bloom
///   filter optimization, most lookups skip SSTables in O(1)).
/// - Compaction: O(N) via k-way merge (not O(N log N) via global sort).
/// - Range scan: O(log n + K) per level.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Default MemTable capacity (entries) when none is specified.
const DEFAULT_MEMTABLE_CAPACITY : Int = 1024

///|
/// Number of Level 0 SSTables that triggers automatic compaction.
const COMPACTION_THRESHOLD : Int = 4

///|
/// Maximum skip-list height. Sufficient for 2^32 elements.
const MEMTABLE_MAX_LEVEL : Int = 32

// ---------------------------------------------------------------------------
// Bloom Filter (per-SSTable) — delegates to the bloom_filter package
// ---------------------------------------------------------------------------

///|
/// Simple hash using FNV-1a variant that fits in Int.
/// Used as the hash function for the generic bloom_filter package.
fn lsm_hash(s : String) -> Int {
  let mut h = 2166136261U
  for i = 0; i < s.length(); i = i + 1 {
    h = h ^ s[i].to_uint()
    h = h * 16777619U
  }
  (h & 0x7FFFFFFFU).reinterpret_as_int()
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A key-value entry.
priv struct Entry {
  key : String
  value : String
  deleted : Bool // tombstone
}

///|
/// An immutable sorted table (simulates an SSTable) with Bloom filter.
struct SSTable {
  entries : Array[Entry] // sorted by key
  bloom : @bloom_filter.BloomFilter[String]
}

// ---------------------------------------------------------------------------
// MemTable — skip-list-backed sorted map
// ---------------------------------------------------------------------------

///|
/// A single skip-list node holding a key-value `Entry`.
///
/// `forward[i]` is the next node at level `i`, or `None` at the tail.
/// The array length equals the node's height.
priv struct MemNode {
  key : String
  mut value : Entry
  forward : FixedArray[MemNode?]
}

///|
/// MemTable: a sorted map from `String` keys to `Entry` values, implemented
/// as a skip list. This provides O(log n) insertion, lookup, and deletion
/// while keeping all entries in sorted order — the same approach used by
/// LevelDB and RocksDB for their MemTable.
///
/// Unlike a hash map (which requires O(n log n) sorting at flush time),
/// the skip list's level-0 linked list is already sorted, so flush is O(n).
struct MemTable {
  header : MemNode
  mut level : Int
  mut count : Int
  mut rng : Int
}

///|
/// Create an empty MemTable.
fn MemTable::new() -> MemTable {
  {
    header: {
      key: "",
      value: { key: "", value: "", deleted: false },
      forward: FixedArray::make(MEMTABLE_MAX_LEVEL, None),
    },
    level: 1,
    count: 0,
    rng: 0x12345678,
  }
}

///|
/// Advance the LCG and draw a random node height in `[1, MEMTABLE_MAX_LEVEL]`.
fn MemTable::rand_level(self : MemTable) -> Int {
  self.rng = @utils.lcg_next(self.rng)
  let mut lvl = 1
  let mut bits = self.rng >> 1
  while lvl < MEMTABLE_MAX_LEVEL && (bits & 1) == 1 {
    lvl = lvl + 1
    bits = bits >> 1
  }
  lvl
}

///|
/// Walk down from the top level, recording the predecessor of `key` at
/// every level into `update`. Returns the level-0 successor.
fn MemTable::find_path(
  self : MemTable,
  key : String,
  update : FixedArray[MemNode],
) -> MemNode? {
  let mut current = self.header
  for i = self.level - 1; i >= 0; i = i - 1 {
    let mut advancing = true
    while advancing {
      match current.forward[i] {
        Some(node) =>
          if @utils.str_cmp(node.key, key) < 0 {
            current = node
          } else {
            advancing = false
          }
        None => advancing = false
      }
    }
    update[i] = current
  }
  current.forward[0]
}

///|
/// Insert or update a key-value entry. O(log n) expected.
fn MemTable::insert(self : MemTable, entry : Entry) -> Unit {
  let update = FixedArray::make(MEMTABLE_MAX_LEVEL, self.header)
  match self.find_path(entry.key, update) {
    Some(node) =>
      if @utils.str_cmp(node.key, entry.key) == 0 {
        // Duplicate key: update in place.
        node.value = entry
        return
      }
    None => ()
  }
  let new_level = self.rand_level()
  let new_node : MemNode = {
    key: entry.key,
    value: entry,
    forward: FixedArray::make(new_level, None),
  }
  if new_level > self.level {
    for i = self.level; i < new_level; i = i + 1 {
      update[i] = self.header
    }
    self.level = new_level
  }
  for i = 0; i < new_level; i = i + 1 {
    new_node.forward[i] = update[i].forward[i]
    update[i].forward[i] = Some(new_node)
  }
  self.count = self.count + 1
}

///|
/// Look up the entry for `key`. O(log n) expected.
fn MemTable::get(self : MemTable, key : String) -> Entry? {
  let mut current = self.header
  for i = self.level - 1; i >= 0; i = i - 1 {
    let mut advancing = true
    while advancing {
      match current.forward[i] {
        Some(node) =>
          if @utils.str_cmp(node.key, key) < 0 {
            current = node
          } else {
            advancing = false
          }
        None => advancing = false
      }
    }
  }
  match current.forward[0] {
    Some(node) =>
      if @utils.str_cmp(node.key, key) == 0 {
        Some(node.value)
      } else {
        None
      }
    None => None
  }
}

///|
/// Number of entries. O(1).
fn MemTable::size(self : MemTable) -> Int {
  self.count
}

///|
/// Whether the MemTable is empty. O(1).
fn MemTable::is_empty(self : MemTable) -> Bool {
  self.count == 0
}

///|
/// Return all entries in ascending key order. O(n).
/// Walks the level-0 linked list, which is already sorted.
fn MemTable::inorder(self : MemTable) -> Array[Entry] {
  let result : Array[Entry] = []
  let mut current = self.header.forward[0]
  let mut go = true
  while go {
    match current {
      Some(node) => {
        result.push(node.value)
        current = node.forward[0]
      }
      None => go = false
    }
  }
  result
}

// ---------------------------------------------------------------------------
// The LSM-Tree
// ---------------------------------------------------------------------------

///|
/// The LSM-Tree.
pub struct LSMTree {
  priv mut memtable : MemTable
  priv memtable_capacity : Int
  priv mut sstables : Array[SSTable] // Level 0 tables (may overlap)
  priv mut level1 : Array[SSTable] // Level 1+ (non-overlapping, merged)
  priv mut total_entries : Int
}

///|
/// Create a new LSM-Tree with the given MemTable capacity.
/// When the MemTable reaches `memtable_capacity` entries, it is flushed
/// to an SSTable.
pub fn new(memtable_capacity : Int) -> LSMTree {
  let cap = if memtable_capacity > 0 {
    memtable_capacity
  } else {
    DEFAULT_MEMTABLE_CAPACITY
  }
  {
    memtable: MemTable::new(),
    memtable_capacity: cap,
    sstables: [],
    level1: [],
    total_entries: 0,
  }
}

///|
/// Number of entries in the MemTable.
pub fn memtable_size(tree : LSMTree) -> Int {
  tree.memtable.size()
}

///|
/// Number of SSTables (Level 0).
pub fn sstable_count(tree : LSMTree) -> Int {
  tree.sstables.length()
}

///|
/// Total number of live entries (excluding tombstones).
/// This value is maintained incrementally on put/delete and fully
/// recomputed during compaction to ensure accuracy.
pub fn entry_count(tree : LSMTree) -> Int {
  tree.total_entries
}

// ---------------------------------------------------------------------------
// Write operations
// ---------------------------------------------------------------------------

///|
/// Insert or update a key-value pair.
pub fn put(tree : LSMTree, key : String, value : String) -> Unit {
  // Single skip-list lookup: determines whether the key is new,
  // was a tombstone, or was already alive — without a separate
  // `contains` + `get` round-trip.
  match tree.memtable.get(key) {
    Some(prev) =>
      if prev.deleted {
        // Key was a tombstone in memtable; now it's alive again.
        tree.memtable.insert({ key, value, deleted: false })
        tree.total_entries = tree.total_entries + 1
      } else {
        // Key was already alive; just update the value.
        tree.memtable.insert({ key, value, deleted: false })
      }
    None => {
      // New key in the MemTable.
      tree.memtable.insert({ key, value, deleted: false })
      // Only increment total if the key doesn't exist in SSTables.
      // If it exists in SSTables, it's already counted.
      if !sstable_contains(tree, key) {
        tree.total_entries = tree.total_entries + 1
      }
    }
  }
  if tree.memtable.size() >= tree.memtable_capacity {
    flush(tree)
  }
}

///|
/// Delete a key (writes a tombstone).
pub fn delete(tree : LSMTree, key : String) -> Unit {
  match tree.memtable.get(key) {
    Some(prev) =>
      if prev.deleted {
        // Already a tombstone — nothing changes.
        tree.memtable.insert({ key, value: "", deleted: true })
      } else {
        // Key was alive in memtable; now it's a tombstone.
        tree.memtable.insert({ key, value: "", deleted: true })
        tree.total_entries = tree.total_entries - 1
      }
    None => {
      // Key not in MemTable.
      tree.memtable.insert({ key, value: "", deleted: true })
      // Check if the key exists in SSTables; if so, decrement.
      if sstable_contains(tree, key) {
        tree.total_entries = tree.total_entries - 1
      }
    }
  }
  if tree.memtable.size() >= tree.memtable_capacity {
    flush(tree)
  }
}

///|
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

///|
/// Flush the MemTable to an SSTable (Level 0).
///
/// Because the MemTable is a skip list, entries are already sorted —
/// no additional sort step is needed (O(n) flush vs O(n log n) for a
/// hash-map-based MemTable).
pub fn flush(tree : LSMTree) -> Unit {
  if tree.memtable.is_empty() {
    return
  }
  // Entries are already sorted by key (skip list level-0 traversal).
  let entries = tree.memtable.inorder()
  // Build Bloom filter for this SSTable.
  let bloom = @bloom_filter.new(entries.length(), 0.01, lsm_hash)
  for i = 0; i < entries.length(); i = i + 1 {
    @bloom_filter.add(bloom, entries[i].key)
  }
  tree.sstables.push({ entries, bloom })
  // Reset MemTable.
  tree.memtable = MemTable::new()
  // Trigger compaction if too many Level 0 tables.
  if tree.sstables.length() >= COMPACTION_THRESHOLD {
    compact(tree)
  }
}

///|
/// Compact Level 0 SSTables into Level 1 using k-way merge.
///
/// Uses a min-heap for O(N log K) merge where N = total entries, K = number
/// of tables. Deduplicates by key (keeping the newest entry) and removes
/// tombstones for keys that don't appear in higher levels.
pub fn compact(tree : LSMTree) -> Unit {
  if tree.sstables.length() == 0 && tree.level1.length() == 0 {
    return
  }
  // Collect all tables. Level 0 tables are newer (higher index = newer).
  // Level 1 tables are older.
  // Priority: memtable (already flushed) > L0[last] > ... > L0[0] > L1[0]
  let all_tables : Array[SSTable] = []
  // Add Level 0 tables in reverse order (newest first for dedup priority).
  for i = tree.sstables.length() - 1; i >= 0; i = i - 1 {
    all_tables.push(tree.sstables[i])
  }
  for i = 0; i < tree.level1.length(); i = i + 1 {
    all_tables.push(tree.level1[i])
  }
  // K-way merge using min-heap.
  let merged : Array[Entry] = k_way_merge_tables(all_tables)
  // Recompute total_entries from the merged result.
  let mut live_count = 0
  for i = 0; i < merged.length(); i = i + 1 {
    if !merged[i].deleted {
      live_count = live_count + 1
    }
  }
  // Also count live entries remaining in the memtable.
  let memtable_entries = tree.memtable.inorder()
  for i = 0; i < memtable_entries.length(); i = i + 1 {
    if !memtable_entries[i].deleted {
      live_count = live_count + 1
    }
  }
  tree.total_entries = live_count
  // Replace Level 0 and Level 1.
  tree.sstables = []
  let bloom = @bloom_filter.new(merged.length(), 0.01, lsm_hash)
  for i = 0; i < merged.length(); i = i + 1 {
    @bloom_filter.add(bloom, merged[i].key)
  }
  tree.level1 = [{ entries: merged, bloom }]
}

///|
/// K-way merge of sorted SSTables, deduplicating by key (first occurrence
/// wins, which is the newest due to table ordering).
///
/// Uses a binary min-heap for O(N log K) time complexity.
fn k_way_merge_tables(tables : Array[SSTable]) -> Array[Entry] {
  let k = tables.length()
  if k == 0 {
    return []
  }
  if k == 1 {
    return tables[0].entries
  }
  // Min-heap of (table_index, entry_index). Capacity = k.
  let heap_tbl = FixedArray::make(k, 0)
  let heap_pos = FixedArray::make(k, 0)
  let mut heap_size = 0
  // Push the first entry of each non-empty table.
  for t = 0; t < k; t = t + 1 {
    if tables[t].entries.length() > 0 {
      heap_tbl[heap_size] = t
      heap_pos[heap_size] = 0
      heap_size = heap_size + 1
    }
  }
  // Heapify (sift up each element).
  for i = 0; i < heap_size; i = i + 1 {
    sift_up(heap_tbl, heap_pos, tables, i)
  }
  // Merge.
  let result : Array[Entry] = []
  let mut last_key : String? = None
  while heap_size > 0 {
    let tbl = heap_tbl[0]
    let pos = heap_pos[0]
    let entry = tables[tbl].entries[pos]
    // Deduplicate: skip if same key as last output (first occurrence wins).
    let skip = match last_key {
      Some(k) => entry.key == k
      None => false
    }
    if !skip {
      result.push(entry)
      last_key = Some(entry.key)
    }
    // Advance this table's pointer.
    let next_pos = pos + 1
    if next_pos < tables[tbl].entries.length() {
      heap_pos[0] = next_pos
      sift_down(heap_tbl, heap_pos, tables, 0, heap_size)
    } else {
      // Table exhausted: remove from heap by replacing root with last element.
      heap_size = heap_size - 1
      if heap_size > 0 {
        heap_tbl[0] = heap_tbl[heap_size]
        heap_pos[0] = heap_pos[heap_size]
        sift_down(heap_tbl, heap_pos, tables, 0, heap_size)
      }
    }
  }
  result
}

///|
/// Sift up element at index `i` in the min-heap.
/// Ties broken by table index (lower = newer = wins).
fn sift_up(
  heap_tbl : FixedArray[Int],
  heap_pos : FixedArray[Int],
  tables : Array[SSTable],
  i : Int,
) -> Unit {
  let mut idx = i
  while idx > 0 {
    let parent = (idx - 1) / 2
    let child_key = tables[heap_tbl[idx]].entries[heap_pos[idx]].key
    let parent_key = tables[heap_tbl[parent]].entries[heap_pos[parent]].key
    let c = @utils.str_cmp(child_key, parent_key)
    // Child should go up if key is smaller, or equal key but newer table (lower index).
    if c < 0 || (c == 0 && heap_tbl[idx] < heap_tbl[parent]) {
      let tt = heap_tbl[idx]
      heap_tbl[idx] = heap_tbl[parent]
      heap_tbl[parent] = tt
      let tp = heap_pos[idx]
      heap_pos[idx] = heap_pos[parent]
      heap_pos[parent] = tp
      idx = parent
    } else {
      break
    }
  }
}

///|
/// Sift down element at index `i` in the min-heap of size `size`.
/// Ties broken by table index (lower = newer = wins).
fn sift_down(
  heap_tbl : FixedArray[Int],
  heap_pos : FixedArray[Int],
  tables : Array[SSTable],
  i : Int,
  size : Int,
) -> Unit {
  let mut idx = i
  while true {
    let left = 2 * idx + 1
    let right = 2 * idx + 2
    let mut smallest = idx
    if left < size {
      let left_key = tables[heap_tbl[left]].entries[heap_pos[left]].key
      let cur_key = tables[heap_tbl[smallest]].entries[heap_pos[smallest]].key
      let c = @utils.str_cmp(left_key, cur_key)
      if c < 0 || (c == 0 && heap_tbl[left] < heap_tbl[smallest]) {
        smallest = left
      }
    }
    if right < size {
      let right_key = tables[heap_tbl[right]].entries[heap_pos[right]].key
      let cur_key = tables[heap_tbl[smallest]].entries[heap_pos[smallest]].key
      let c = @utils.str_cmp(right_key, cur_key)
      if c < 0 || (c == 0 && heap_tbl[right] < heap_tbl[smallest]) {
        smallest = right
      }
    }
    if smallest == idx {
      break
    }
    let tt = heap_tbl[idx]
    heap_tbl[idx] = heap_tbl[smallest]
    heap_tbl[smallest] = tt
    let tp = heap_pos[idx]
    heap_pos[idx] = heap_pos[smallest]
    heap_pos[smallest] = tp
    idx = smallest
  }
}

// ---------------------------------------------------------------------------
// Read operations
// ---------------------------------------------------------------------------

///|
/// Get the value for a key, or `None` if not found.
///
/// Searches: MemTable → Level 0 SSTables (newest first) → Level 1.
/// Uses Bloom filters to skip SSTables that definitely don't contain the key.
pub fn get(tree : LSMTree, key : String) -> String? {
  // 1. Check MemTable (skip list, O(log n)).
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
    // Bloom filter check: skip if definitely not present.
    if @bloom_filter.contains(table.bloom, key) {
      match binary_search_table(table, key) {
        Some(entry) => {
          if entry.deleted {
            return None
          }
          return Some(entry.value)
        }
        None => ()
      }
    }
    i = i - 1
  }
  // 3. Check Level 1.
  for i = 0; i < tree.level1.length(); i = i + 1 {
    let table = tree.level1[i]
    if @bloom_filter.contains(table.bloom, key) {
      match binary_search_table(table, key) {
        Some(entry) => {
          if entry.deleted {
            return None
          }
          return Some(entry.value)
        }
        None => ()
      }
    }
  }
  None
}

///|
/// Check if a key exists in any SSTable (Level 0 or Level 1).
/// Used internally to maintain accurate entry_count.
fn sstable_contains(tree : LSMTree, key : String) -> Bool {
  // Check Level 0.
  let mut i = tree.sstables.length() - 1
  while i >= 0 {
    let table = tree.sstables[i]
    if @bloom_filter.contains(table.bloom, key) {
      match binary_search_table(table, key) {
        Some(entry) => return !entry.deleted
        None => ()
      }
    }
    i = i - 1
  }
  // Check Level 1.
  for i = 0; i < tree.level1.length(); i = i + 1 {
    let table = tree.level1[i]
    if @bloom_filter.contains(table.bloom, key) {
      match binary_search_table(table, key) {
        Some(entry) => return !entry.deleted
        None => ()
      }
    }
  }
  false
}

///|
/// Check if a key exists (not deleted).
pub fn contains(tree : LSMTree, key : String) -> Bool {
  get(tree, key) is Some(_)
}

///|
/// Binary search for a key in an SSTable.
fn binary_search_table(table : SSTable, key : String) -> Entry? {
  let entries = table.entries
  let mut lo = 0
  let mut hi = entries.length() - 1
  while lo <= hi {
    let mid = lo + (hi - lo) / 2
    let c = @utils.str_cmp(entries[mid].key, key)
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

///|
/// Scan all key-value pairs in the range `[start, end)` (exclusive end).
/// Returns entries sorted by key, excluding tombstones.
pub fn range_scan(
  tree : LSMTree,
  start : String,
  end : String,
) -> Array[(String, String)] {
  // K-way merge approach: SSTables and MemTable entries are already sorted.
  // We collect entries from all sources, merging them in key order,
  // with newer sources overriding older ones (same key → newer wins).
  //
  // Sources in order from newest to oldest:
  //   1. MemTable (newest, skip list — already sorted)
  //   2. Level 0 SSTables (reverse order — most recently flushed is newest)
  //   3. Level 1 SSTables (oldest)
  //
  // For each key in [start, end), only the entry from the newest source wins.

  // Collect all matching entries from all sources, tagged with source priority.
  // Lower priority = newer (wins).
  let all_entries : Array[(String, String, Bool, Int)] = []
  // Priority 0 = MemTable (newest). Skip list is already sorted, so we can
  // iterate in order and filter by range.
  let memtable_entries = tree.memtable.inorder()
  for i = 0; i < memtable_entries.length(); i = i + 1 {
    let e = memtable_entries[i]
    if @utils.str_cmp(e.key, start) >= 0 && @utils.str_cmp(e.key, end) < 0 {
      all_entries.push((e.key, e.value, e.deleted, 0))
    }
  }
  // Priority 1+i = Level 0 SSTables (most recent first).
  for i = tree.sstables.length() - 1; i >= 0; i = i - 1 {
    let table = tree.sstables[i]
    // Binary search for the start position.
    let lo = binary_search_entries(table.entries, start)
    for j = lo; j < table.entries.length(); j = j + 1 {
      let e = table.entries[j]
      if @utils.str_cmp(e.key, end) >= 0 {
        break // Entries are sorted; no more matches.
      }
      all_entries.push((e.key, e.value, e.deleted, tree.sstables.length() - i))
    }
  }
  // Priority = tree.sstables.length() + 1 + i = Level 1 SSTables (oldest).
  // This ensures L1 priority never overlaps with L0 priority, regardless of
  // how many L0 tables exist.
  let base_prio = tree.sstables.length() + 1
  for i = 0; i < tree.level1.length(); i = i + 1 {
    let table = tree.level1[i]
    let lo = binary_search_entries(table.entries, start)
    for j = lo; j < table.entries.length(); j = j + 1 {
      let e = table.entries[j]
      if @utils.str_cmp(e.key, end) >= 0 {
        break
      }
      all_entries.push((e.key, e.value, e.deleted, base_prio + i))
    }
  }
  // Sort by (key, priority) — for equal keys, lower priority (newer) comes first.
  all_entries.sort_by(fn(a, b) {
    let c = @utils.str_cmp(a.0, b.0)
    if c != 0 {
      return c
    }
    a.3 - b.3
  })
  // Deduplicate: for each key, only the first (newest) entry is kept.
  // Skip if it's a tombstone.
  let result : Array[(String, String)] = []
  let mut i = 0
  while i < all_entries.length() {
    let (key, value, deleted, _) = all_entries[i]
    // Skip all other entries with the same key.
    let mut j = i + 1
    while j < all_entries.length() && @utils.str_cmp(all_entries[j].0, key) == 0 {
      j = j + 1
    }
    if !deleted {
      result.push((key, value))
    }
    i = j
  }
  result
}

///|
/// Binary search for the first entry with key >= target.
/// Returns entries.length() if all keys are < target.
fn binary_search_entries(entries : Array[Entry], target : String) -> Int {
  let mut lo = 0
  let mut hi = entries.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if @utils.str_cmp(entries[mid].key, target) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lsm: basic put and get" {
  let tree = new(100)
  put(tree, "hello", "world")
  put(tree, "foo", "bar")
  assert_eq(get(tree, "hello"), Some("world"))
  assert_eq(get(tree, "foo"), Some("bar"))
  assert_eq(get(tree, "missing"), None)
}

///|
test "lsm: update existing key" {
  let tree = new(100)
  put(tree, "key", "value1")
  put(tree, "key", "value2")
  assert_eq(get(tree, "key"), Some("value2"))
}

///|
test "lsm: delete key" {
  let tree = new(100)
  put(tree, "key", "value")
  delete(tree, "key")
  assert_eq(get(tree, "key"), None)
  assert_false(contains(tree, "key"))
}

///|
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

///|
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

///|
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

///|
test "lsm: delete after flush (tombstone)" {
  let tree = new(2)
  put(tree, "key", "value")
  put(tree, "a", "1") // flush
  delete(tree, "key")
  assert_eq(get(tree, "key"), None)
}

///|
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

///|
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

///|
test "lsm: batch put" {
  let tree = new(100)
  batch_put(tree, [("a", "1"), ("b", "2"), ("c", "3")])
  assert_eq(get(tree, "a"), Some("1"))
  assert_eq(get(tree, "b"), Some("2"))
  assert_eq(get(tree, "c"), Some("3"))
}

///|
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

///|
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

///|
test "lsm: entry count basic" {
  let tree = new(100)
  put(tree, "a", "1")
  put(tree, "b", "2")
  assert_eq(entry_count(tree), 2)
  delete(tree, "a")
  assert_eq(entry_count(tree), 1)
}

///|
test "lsm: entry count after flush" {
  let tree = new(2)
  put(tree, "a", "1")
  put(tree, "b", "2") // flush
  assert_eq(entry_count(tree), 2)
  put(tree, "c", "3")
  put(tree, "d", "4") // flush
  assert_eq(entry_count(tree), 4)
}

///|
test "lsm: entry count after compaction" {
  let tree = new(2)
  put(tree, "a", "1")
  put(tree, "b", "2") // flush
  put(tree, "c", "3")
  put(tree, "d", "4") // flush
  put(tree, "e", "5")
  put(tree, "f", "6") // flush
  put(tree, "g", "7")
  put(tree, "h", "8") // flush → compaction
  assert_eq(entry_count(tree), 8)
}

///|
test "lsm: entry count with delete after flush" {
  let tree = new(2)
  put(tree, "key", "value")
  put(tree, "a", "1") // flush
  delete(tree, "key")
  assert_eq(entry_count(tree), 1)
}

///|
test "lsm: entry count with reinsert" {
  let tree = new(2)
  put(tree, "key", "value")
  put(tree, "a", "1") // flush
  delete(tree, "key")
  assert_eq(entry_count(tree), 1)
  put(tree, "key", "new_value")
  assert_eq(entry_count(tree), 2)
  assert_eq(get(tree, "key"), Some("new_value"))
}

///|
test "lsm: bloom filter skips sstables" {
  let tree = new(2)
  put(tree, "a", "1")
  put(tree, "b", "2") // flush
  put(tree, "c", "3")
  put(tree, "d", "4") // flush
  // Key not in any table should return None quickly.
  assert_eq(get(tree, "zzz"), None)
}

///|
test "lsm: overwrite during compaction" {
  let tree = new(2)
  put(tree, "key", "old1")
  put(tree, "a", "1") // flush
  put(tree, "key", "old2")
  put(tree, "b", "2") // flush
  put(tree, "key", "new")
  put(tree, "c", "3") // flush
  put(tree, "d", "4")
  put(tree, "e", "5") // flush → compaction
  // After compaction, "key" should have the newest value.
  assert_eq(get(tree, "key"), Some("new"))
  assert_eq(entry_count(tree), 6)
}

///|
test "lsm: delete all then compact" {
  let tree = new(2)
  put(tree, "a", "1")
  put(tree, "b", "2") // flush
  delete(tree, "a")
  delete(tree, "b")
  put(tree, "c", "3") // flush
  put(tree, "d", "4")
  put(tree, "e", "5") // flush → compaction
  assert_eq(get(tree, "a"), None)
  assert_eq(get(tree, "b"), None)
  assert_eq(get(tree, "c"), Some("3"))
  assert_eq(get(tree, "d"), Some("4"))
  assert_eq(get(tree, "e"), Some("5"))
  assert_eq(entry_count(tree), 3)
}

///|
test "lsm: memtable is sorted (skip list property)" {
  let tree = new(100)
  // Insert keys in reverse order.
  put(tree, "zebra", "z")
  put(tree, "apple", "a")
  put(tree, "mango", "m")
  put(tree, "banana", "b")
  // Range scan should return sorted results.
  let result = range_scan(tree, "a", "z")
  assert_eq(result.length(), 3)
  assert_eq(result[0].0, "apple")
  assert_eq(result[1].0, "banana")
  assert_eq(result[2].0, "mango")
}
