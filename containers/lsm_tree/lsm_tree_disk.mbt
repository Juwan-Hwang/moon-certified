/// Disk-Based LSM Tree Persistence (Async).
///
/// This module provides async functions for persisting LSM-Tree SSTables
/// to disk using `@async/fs`. This enables the LSM-Tree to survive process
/// restarts and to handle datasets larger than available memory.
///
/// ## File Format
/// Each SSTable is stored as a text file with the following format:
/// ```text
/// ENTRY_COUNT
/// KEY\tVALUE\tDELETED
/// KEY\tVALUE\tDELETED
/// ...
/// ```
/// Where DELETED is 0 (live) or 1 (tombstone).
///
/// The Bloom filter is rebuilt from keys on load, avoiding serialization
/// complexity while maintaining the same lookup performance.
///
/// ## Functions
/// - `flush_to_disk`: Flush the memtable to a new SSTable file on disk.
/// - `persist_to_disk`: Write all in-memory SSTables to disk.
/// - `restore_from_disk`: Create a new LSMTree from SSTable files on disk.
///
/// Requires a backend with file system access (native or wasm target).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Serialization helpers
// ---------------------------------------------------------------------------

///|
/// Serialize an SSTable to a text string.
///
/// Format: first line is entry count, then each entry is
/// `key\tvalue\tdeleted\n`.
fn sstable_to_text(table : SSTable) -> String {
  let sb = StringBuilder::new()
  sb.write_string(table.entries.length().to_string())
  sb.write_string("\n")
  for i = 0; i < table.entries.length(); i = i + 1 {
    let e = table.entries[i]
    sb.write_string(e.key)
    sb.write_string("\t")
    sb.write_string(e.value)
    sb.write_string("\t")
    sb.write_string(if e.deleted { "1" } else { "0" })
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
/// Parse a non-negative integer from a string (digits only).
fn parse_uint(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let mut result = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c < 48 || c > 57 {
      return None
    }
    result = result * 10 + (c - 48)
  }
  Some(result)
}

///|
/// Parse an SSTable from a text string.
///
/// Rebuilds the Bloom filter from the parsed keys.
fn parse_sstable_from_text(text : String) -> SSTable {
  let lines = text.split("\n").to_array()
  let entries : Array[Entry] = []
  // Line 0: entry count (for validation, not strictly needed).
  // Lines 1..n: entries.
  for i = 1; i < lines.length(); i = i + 1 {
    let line = lines[i]
    // Skip empty trailing line.
    if line.length() == 0 {
      continue
    }
    let parts = line.split("\t").to_array()
    if parts.length() >= 3 {
      let key = parts[0].to_owned()
      let value = parts[1].to_owned()
      let deleted = parts[2] == "1"
      entries.push({ key, value, deleted })
    }
  }
  // Rebuild Bloom filter from keys.
  let bloom = bloom_new(entries.length())
  for j = 0; j < entries.length(); j = j + 1 {
    bloom_insert(bloom, entries[j].key)
  }
  { entries, bloom }
}

// ---------------------------------------------------------------------------
// Disk I/O functions
// ---------------------------------------------------------------------------

///|
/// Flush the MemTable to a new SSTable file on disk.
///
/// Sorts the current MemTable entries by key, writes them as an SSTable
/// file to `dir/sstable_N.txt`, and clears the MemTable. This is the disk
/// equivalent of the in-memory `flush`.
///
/// Returns the path of the written file, or `None` if the MemTable was empty.
pub async fn flush_to_disk(tree : LSMTree, dir : String) -> String? {
  if tree.memtable_size == 0 {
    return None
  }
  // Sort entries by key.
  let entries : Array[Entry] = []
  for _k, v in tree.memtable {
    entries.push(v)
  }
  entries.sort_by(fn(a, b) { str_cmp(a.key, b.key) })
  // Build Bloom filter.
  let bloom = bloom_new(entries.length())
  for i = 0; i < entries.length(); i = i + 1 {
    bloom_insert(bloom, entries[i].key)
  }
  let table : SSTable = { entries, bloom }
  // Determine the next file index.
  let existing = @fs.readdir(dir, sort=true)
  let mut max_idx = -1
  for i = 0; i < existing.length(); i = i + 1 {
    let name = existing[i]
    if name.has_prefix("sstable_") && name.has_suffix(".txt") {
      // Extract the numeric index from "sstable_N.txt".
      let num_part = name[8:name.length() - 4].to_owned()
      match parse_uint(num_part) {
        Some(n) => if n > max_idx {
          max_idx = n
        }
        None => ()
      }
    }
  }
  let path = dir + "/sstable_" + (max_idx + 1).to_string() + ".txt"
  @fs.write_file(path, sstable_to_text(table), create_mode=CreateOrTruncate)
  // Reset MemTable.
  tree.memtable = Map([])
  tree.memtable_size = 0
  Some(path)
}

///|
/// Persist all in-memory SSTables (Level 0 and Level 1) to disk.
///
/// Writes each SSTable as a separate file in the given directory.
/// Level 0 tables are named `sstable_L0_N.txt`, Level 1 tables
/// `sstable_L1_N.txt`.
pub async fn persist_to_disk(tree : LSMTree, dir : String) -> Unit {
  // Flush any pending MemTable entries to SSTables first.
  flush(tree)
  if !@fs.exists(dir) {
    @fs.mkdir(dir, recursive=true)
  }
  // Write Level 0 SSTables.
  for i = 0; i < tree.sstables.length(); i = i + 1 {
    let path = dir + "/sstable_L0_" + i.to_string() + ".txt"
    @fs.write_file(path, sstable_to_text(tree.sstables[i]), create_mode=CreateOrTruncate)
  }
  // Write Level 1 SSTables.
  for i = 0; i < tree.level1.length(); i = i + 1 {
    let path = dir + "/sstable_L1_" + i.to_string() + ".txt"
    @fs.write_file(path, sstable_to_text(tree.level1[i]), create_mode=CreateOrTruncate)
  }
}

///|
/// Create a new LSMTree and load all SSTable files from a disk directory.
///
/// Reads all `*.txt` files in the directory, parses them as SSTables,
/// and populates the tree. Level 0 tables (files starting with `sstable_L0_`)
/// are loaded into `sstables`, Level 1 tables (files starting with
/// `sstable_L1_`) into `level1`.
pub async fn restore_from_disk(
  dir : String,
  memtable_capacity : Int,
) -> LSMTree {
  let tree = new(memtable_capacity)
  let files = @fs.readdir(dir, sort=true)
  for i = 0; i < files.length(); i = i + 1 {
    let name = files[i]
    if !name.has_suffix(".txt") {
      continue
    }
    let path = dir + "/" + name
    let data = @fs.read_file(path)
    let text = try data.text() catch {
      _ => ""
    }
    let table = parse_sstable_from_text(text)
    if name.has_prefix("sstable_L0_") {
      tree.sstables.push(table)
    } else if name.has_prefix("sstable_L1_") {
      tree.level1.push(table)
    } else if name.has_prefix("sstable_") {
      // Legacy format: treat as Level 0.
      tree.sstables.push(table)
    }
  }
  // Recompute total_entries from loaded data.
  let mut count = 0
  for i = 0; i < tree.sstables.length(); i = i + 1 {
    for j = 0; j < tree.sstables[i].entries.length(); j = j + 1 {
      if !tree.sstables[i].entries[j].deleted {
        count = count + 1
      }
    }
  }
  for i = 0; i < tree.level1.length(); i = i + 1 {
    for j = 0; j < tree.level1[i].entries.length(); j = j + 1 {
      if !tree.level1[i].entries[j].deleted {
        count = count + 1
      }
    }
  }
  tree.total_entries = count
  tree
}

///|
/// Flush and compact the tree, then persist everything to disk.
///
/// This is a convenience function that:
/// 1. Flushes the MemTable to an in-memory SSTable.
/// 2. Runs compaction to merge all SSTables.
/// 3. Writes the compacted result to disk.
pub async fn checkpoint_to_disk(tree : LSMTree, dir : String) -> Unit {
  flush(tree)
  compact(tree)
  persist_to_disk(tree, dir)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
async test "lsm_disk: flush to disk" {
  let tmpdir = @fs.tmpdir(prefix="lsm_test_")
  let tree = new(100)
  put(tree, "hello", "world")
  put(tree, "foo", "bar")
  let path = flush_to_disk(tree, tmpdir)
  assert_true(path is Some(_))
  assert_eq(memtable_size(tree), 0)
  // Read back the file.
  let p = path.unwrap()
  let data = @fs.read_file(p)
  let text = try data.text() catch {
    _ => ""
  }
  assert_true(text.contains("hello"))
  assert_true(text.contains("world"))
  assert_true(text.contains("foo"))
  assert_true(text.contains("bar"))
  // Cleanup.
  @fs.rmdir(tmpdir, recursive=true)
}

///|
async test "lsm_disk: persist and restore" {
  let tmpdir = @fs.tmpdir(prefix="lsm_test_")
  let tree = new(3)
  put(tree, "a", "1")
  put(tree, "b", "2") // flush
  put(tree, "c", "3")
  put(tree, "d", "4") // flush
  // Persist to disk.
  persist_to_disk(tree, tmpdir)
  // Restore from disk.
  let restored = restore_from_disk(tmpdir, 100)
  // Verify data.
  assert_eq(get(restored, "a"), Some("1"))
  assert_eq(get(restored, "b"), Some("2"))
  assert_eq(get(restored, "c"), Some("3"))
  assert_eq(get(restored, "d"), Some("4"))
  // Cleanup.
  @fs.rmdir(tmpdir, recursive=true)
}

///|
async test "lsm_disk: checkpoint and restore" {
  let tmpdir = @fs.tmpdir(prefix="lsm_test_")
  let tree = new(2)
  put(tree, "key1", "val1")
  put(tree, "key2", "val2") // flush
  put(tree, "key3", "val3")
  put(tree, "key4", "val4") // flush
  put(tree, "key5", "val5")
  put(tree, "key6", "val6") // flush → compaction
  // Checkpoint: flush + compact + persist.
  checkpoint_to_disk(tree, tmpdir)
  // Restore.
  let restored = restore_from_disk(tmpdir, 100)
  for i = 1; i <= 6; i = i + 1 {
    let key = "key" + i.to_string()
    let val = "val" + i.to_string()
    assert_eq(get(restored, key), Some(val))
  }
  assert_eq(entry_count(restored), 6)
  // Cleanup.
  @fs.rmdir(tmpdir, recursive=true)
}

///|
async test "lsm_disk: tombstones persist" {
  let tmpdir = @fs.tmpdir(prefix="lsm_test_")
  let tree = new(2)
  put(tree, "a", "1")
  put(tree, "b", "2") // flush
  delete(tree, "a")
  put(tree, "c", "3") // flush
  persist_to_disk(tree, tmpdir)
  let restored = restore_from_disk(tmpdir, 100)
  // "a" should be deleted (tombstone persisted).
  assert_eq(get(restored, "a"), None)
  assert_eq(get(restored, "b"), Some("2"))
  assert_eq(get(restored, "c"), Some("3"))
  // Cleanup.
  @fs.rmdir(tmpdir, recursive=true)
}

///|
async test "lsm_disk: large dataset roundtrip" {
  let tmpdir = @fs.tmpdir(prefix="lsm_test_")
  let tree = new(10)
  for i = 0; i < 50; i = i + 1 {
    put(tree, "key" + i.to_string(), "val" + i.to_string())
  }
  checkpoint_to_disk(tree, tmpdir)
  let restored = restore_from_disk(tmpdir, 100)
  for i = 0; i < 50; i = i + 1 {
    let key = "key" + i.to_string()
    let val = "val" + i.to_string()
    assert_eq(get(restored, key), Some(val))
  }
  assert_eq(entry_count(restored), 50)
  // Cleanup.
  @fs.rmdir(tmpdir, recursive=true)
}

///|
async test "lsm_disk: flush_to_disk increments file index" {
  let tmpdir = @fs.tmpdir(prefix="lsm_test_")
  let tree = new(100)
  put(tree, "a", "1")
  let path1 = flush_to_disk(tree, tmpdir)
  put(tree, "b", "2")
  let path2 = flush_to_disk(tree, tmpdir)
  // Second file should have a higher index.
  assert_true(path1 is Some(_))
  assert_true(path2 is Some(_))
  assert_not_eq(path1.unwrap(), path2.unwrap())
  // Cleanup.
  @fs.rmdir(tmpdir, recursive=true)
}
