/// Disk-Based External Merge Sort (Async).
///
/// This module provides `external_sort_disk`, an async function that
/// performs a true external merge sort using temporary files on disk
/// via `@async/fs`. Unlike the in-memory `external_sort`, this variant
/// persists sorted runs to disk between merge passes, enabling sorting
/// of datasets larger than available memory.
///
/// ## Algorithm
/// 1. **Run generation**: Sort chunks of `buffer_size` elements in memory,
///    serialize to text, and write each to a temp file.
/// 2. **K-way merge passes**: Read `merge_arity` runs from disk, merge using
///    a min-heap, write the merged run back to disk. Repeat until one run.
/// 3. **Final read**: Read the final sorted run from disk into the array.
/// 4. **Cleanup**: Remove all temp files and the temp directory.
///
/// ## File format
/// Each run file contains integers as text, one per line. This is human-
/// readable and easy to debug, at the cost of some space efficiency vs.
/// binary format.
///
/// ## Complexity
/// - Time: O(n log n) — same algorithm as in-memory variant.
/// - Disk I/O: O(n * ceil(log_k(runs))) bytes written/read across all passes.
/// - Memory: O(buffer_size + merge_arity * max_run_size) per merge pass.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Serialization helpers
// ---------------------------------------------------------------------------

///|
/// Serialize a FixedArray[Int] to a newline-separated string.
fn ints_to_text(arr : FixedArray[Int]) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < arr.length(); i = i + 1 {
    if i > 0 {
      sb.write_string("\n")
    }
    sb.write_string(arr[i].to_string())
  }
  sb.to_string()
}

///|
/// Parse a Bytes buffer (text data) into a FixedArray[Int].
///
/// Handles negative numbers. Each integer is separated by a newline.
fn parse_ints_from_bytes(bytes : Bytes) -> FixedArray[Int] {
  let n = bytes.length()
  let result : Array[Int] = []
  let mut current = 0
  let mut negative = false
  let mut has_digit = false
  for i = 0; i < n; i = i + 1 {
    let b = bytes[i].to_int()
    if b == 10 { // '\n'
      if has_digit {
        result.push(if negative { -current } else { current })
      }
      current = 0
      negative = false
      has_digit = false
    } else if b == 45 { // '-'
      negative = true
    } else if b >= 48 && b <= 57 { // '0'..'9'
      current = current * 10 + (b - 48)
      has_digit = true
    }
  }
  if has_digit {
    result.push(if negative { -current } else { current })
  }
  let fa = FixedArray::make(result.length(), 0)
  for i = 0; i < result.length(); i = i + 1 {
    fa[i] = result[i]
  }
  fa
}

// ---------------------------------------------------------------------------
// Disk-based external sort
// ---------------------------------------------------------------------------

///|
/// Sort an array using external merge sort with real disk I/O.
///
/// Writes sorted runs to temporary files, merges them across multiple
/// passes, and reads the final result back into the array. All temporary
/// files are cleaned up after sorting completes.
///
/// This is a true external sort — data is persisted to disk between
/// passes, enabling sorting of datasets larger than available memory.
///
/// Requires a backend with file system access (e.g., JS/Node.js).
pub async fn external_sort_disk(
  arr : FixedArray[Int],
  cfg : ExternalSortConfig,
) -> Unit {
  let n = arr.length()
  if n <= 1 {
    return
  }
  // Create a temp directory for run files.
  let tmpdir = @fs.tmpdir(prefix="ext_sort_")
  // Phase 1: Create sorted runs and write to temp files.
  let run_files : Array[String] = []
  let mut start = 0
  let mut run_idx = 0
  while start < n {
    let end = if start + cfg.buffer_size < n {
      start + cfg.buffer_size
    } else {
      n
    }
    let run_len = end - start
    let run = FixedArray::make(run_len, 0)
    for i = 0; i < run_len; i = i + 1 {
      run[i] = arr[start + i]
    }
    run.sort_by(fn(a, b) { a - b })
    let path = tmpdir + "/run_" + run_idx.to_string()
    @fs.write_file(path, ints_to_text(run), create_mode=CreateOrTruncate)
    run_files.push(path)
    start = end
    run_idx = run_idx + 1
  }
  // Phase 2: K-way merge passes with disk I/O.
  let mut current_files = run_files
  let mut pass = 0
  while current_files.length() > 1 {
    let next_files : Array[String] = []
    let mut i = 0
    while i < current_files.length() {
      let k = if i + cfg.merge_arity < current_files.length() {
        cfg.merge_arity
      } else {
        current_files.length() - i
      }
      // Read k runs from disk.
      let runs : Array[FixedArray[Int]] = []
      for j = 0; j < k; j = j + 1 {
        let data = @fs.read_file(current_files[i + j])
        let bytes = data.binary()
        runs.push(parse_ints_from_bytes(bytes))
      }
      // Merge using the min-heap k-way merge.
      let merged = k_way_merge(runs, 0, k)
      // Write merged run to disk.
      let path = tmpdir + "/p" + pass.to_string() + "_r" + next_files.length().to_string()
      @fs.write_file(path, ints_to_text(merged), create_mode=CreateOrTruncate)
      next_files.push(path)
      i = i + k
    }
    // Delete old run files to save disk space.
    for j = 0; j < current_files.length(); j = j + 1 {
      @fs.remove(current_files[j])
    }
    current_files = next_files
    pass = pass + 1
  }
  // Phase 3: Read final sorted run back into the array.
  if current_files.length() == 1 {
    let data = @fs.read_file(current_files[0])
    let bytes = data.binary()
    let sorted = parse_ints_from_bytes(bytes)
    let copy_len = if n < sorted.length() { n } else { sorted.length() }
    for i = 0; i < copy_len; i = i + 1 {
      arr[i] = sorted[i]
    }
    @fs.remove(current_files[0])
  }
  // Cleanup: remove temp directory.
  @fs.rmdir(tmpdir, recursive=true)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
async test "external_sort_disk: basic" {
  let arr = FixedArray::makei(10, fn(i) { 9 - i })
  external_sort_disk(arr, config(4, 2))
  for i = 0; i < 10; i = i + 1 {
    assert_eq(arr[i], i)
  }
}

///|
async test "external_sort_disk: random input" {
  let arr = FixedArray::makei(100, fn(i) { (i * 7 + 13) % 97 })
  external_sort_disk(arr, config(16, 4))
  for i = 0; i < 99; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
async test "external_sort_disk: negative numbers" {
  let arr = FixedArray::makei(20, fn(i) { i - 10 })
  external_sort_disk(arr, config(5, 3))
  for i = 0; i < 19; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
async test "external_sort_disk: large array" {
  let n = 500
  let arr = FixedArray::makei(n, fn(i) { (i * 31 + 17) % n })
  external_sort_disk(arr, config(32, 8))
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
async test "external_sort_disk: duplicates" {
  let arr = FixedArray::makei(20, fn(i) { i % 3 })
  external_sort_disk(arr, config(5, 2))
  for i = 0; i < 19; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
async test "external_sort_disk: single run" {
  let arr = FixedArray::makei(5, fn(i) { 4 - i })
  external_sort_disk(arr, config(10, 2))
  for i = 0; i < 5; i = i + 1 {
    assert_eq(arr[i], i)
  }
}
