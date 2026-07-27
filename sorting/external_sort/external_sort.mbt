/// External Merge Sort — for data larger than memory.
///
/// External sorting handles datasets that don't fit in memory by:
/// 1. **Run generation**: Read chunks of `buffer_size` elements, sort each
///    chunk in memory, and write them as sorted "runs".
/// 2. **K-way merge**: Merge K sorted runs at a time using a binary min-heap,
///    achieving O(n log k) per merge pass (not O(n×k)).
///
/// This in-memory implementation demonstrates the external sort algorithm
/// without actual disk I/O. It operates on `FixedArray` and uses an
/// internal "run list" to simulate disk-based sorted runs.
///
/// For disk-backed external sort, users can implement file-based run
/// management using the algorithm structure shown here.
///
/// ## Complexity
/// - Time: O(n log n) — each merge pass is O(n log k), with ⌈log_k(runs)⌉ passes.
/// - Space: O(buffer_size + k) for in-memory sorting and the merge heap.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// Configuration for external sort.
pub struct ExternalSortConfig {
  priv buffer_size : Int // Size of each in-memory run
  priv merge_arity : Int // Max runs to merge at once (k-way)
}

///|
/// Default buffer size for in-memory runs (elements per run).
const DEFAULT_BUFFER_SIZE : Int = 1024

///|
/// Default merge arity (number of runs merged simultaneously).
const DEFAULT_MERGE_ARITY : Int = 4

///|
/// Create a configuration with the given buffer size and merge arity.
pub fn config(buffer_size : Int, merge_arity : Int) -> ExternalSortConfig {
  let bs = if buffer_size > 0 { buffer_size } else { DEFAULT_BUFFER_SIZE }
  let ma = if merge_arity > 1 { merge_arity } else { DEFAULT_MERGE_ARITY }
  ExternalSortConfig::{ buffer_size: bs, merge_arity: ma }
}

// ---------------------------------------------------------------------------
// External merge sort
// ---------------------------------------------------------------------------

///|
/// Sort an array using external merge sort simulation.
///
/// This function sorts the entire array in-place using the external sort
/// algorithm: it creates sorted runs of `buffer_size` elements, then
/// merges them in `merge_arity`-way passes until a single sorted run remains.
pub fn external_sort(arr : FixedArray[Int], cfg : ExternalSortConfig) -> Unit {
  let n = arr.length()
  if n <= 1 {
    return
  }
  // Phase 1: Create sorted runs.
  let runs : Array[FixedArray[Int]] = []
  let mut start = 0
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
    // Sort the run in memory. Use safe comparison to avoid Int32 overflow
    // when a - b overflows (e.g. Int::MIN and Int::MAX).
    run.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
    runs.push(run)
    start = end
  }
  // Phase 2: K-way merge until one run remains.
  while runs.length() > 1 {
    let next_runs : Array[FixedArray[Int]] = []
    let mut i = 0
    while i < runs.length() {
      let k = if i + cfg.merge_arity < runs.length() {
        cfg.merge_arity
      } else {
        runs.length() - i
      }
      // Merge runs[i..i+k) into one.
      let merged = k_way_merge(runs, i, k)
      next_runs.push(merged)
      i = i + k
    }
    // Replace runs with next_runs.
    runs.clear()
    for j = 0; j < next_runs.length(); j = j + 1 {
      runs.push(next_runs[j])
    }
  }
  // Write back.
  if runs.length() == 1 {
    let sorted = runs[0]
    for i = 0; i < n; i = i + 1 {
      arr[i] = sorted[i]
    }
  }
}

///|
/// K-way merge of sorted runs[start..start+k) using a binary min-heap.
///
/// ## Complexity
/// - Time: O(n log k) where n = total elements, k = number of runs.
/// - Space: O(k) for the heap.
fn k_way_merge(
  runs : Array[FixedArray[Int]],
  start : Int,
  k : Int,
) -> FixedArray[Int] {
  // Calculate total length.
  let mut total = 0
  for i = 0; i < k; i = i + 1 {
    total = total + runs[start + i].length()
  }
  let result = FixedArray::make(total, 0)
  if total == 0 {
    return result
  }
  // Min-heap of (value, run_index), using the generic binary_heap package.
  // Use explicit comparison to avoid Int overflow on subtraction.
  let heap = @binary_heap.HeapG::new(fn(a : (Int, Int), b : (Int, Int)) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  // Pointers into each run (next unmerged index).
  let ptrs = FixedArray::make(k, 0)
  // Initialize: push the first element of each non-empty run.
  for r = 0; r < k; r = r + 1 {
    if ptrs[r] < runs[start + r].length() {
      heap.push((runs[start + r][ptrs[r]], r))
      ptrs[r] = ptrs[r] + 1
    }
  }
  // Extract minimum repeatedly and refill from the same run.
  for pos = 0; pos < total; pos = pos + 1 {
    let (val, run) = heap.pop().unwrap()
    result[pos] = val
    // Refill from the same run if it still has elements.
    if ptrs[run] < runs[start + run].length() {
      heap.push((runs[start + run][ptrs[run]], run))
      ptrs[run] = ptrs[run] + 1
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "external_sort: empty array" {
  let arr = FixedArray::make(0, 0)
  external_sort(arr, config(4, 2))
  assert_eq(arr.length(), 0)
}

///|
test "external_sort: single element" {
  let arr = FixedArray::make(1, 42)
  external_sort(arr, config(4, 2))
  assert_eq(arr[0], 42)
}

///|
test "external_sort: sorted input" {
  let arr = FixedArray::makei(10, fn(i) { i })
  external_sort(arr, config(4, 2))
  for i = 0; i < 10; i = i + 1 {
    assert_eq(arr[i], i)
  }
}

///|
test "external_sort: reverse input" {
  let arr = FixedArray::makei(10, fn(i) { 9 - i })
  external_sort(arr, config(4, 2))
  for i = 0; i < 10; i = i + 1 {
    assert_eq(arr[i], i)
  }
}

///|
test "external_sort: random input" {
  let arr = FixedArray::makei(100, fn(i) { (i * 7 + 13) % 97 })
  external_sort(arr, config(16, 4))
  for i = 0; i < 99; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
test "external_sort: multiple runs" {
  let arr = FixedArray::makei(50, fn(i) { (i * 3 + 7) % 50 })
  external_sort(arr, config(8, 3))
  for i = 0; i < 49; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
test "external_sort: large array" {
  let n = 1000
  let arr = FixedArray::makei(n, fn(i) { (i * 31 + 17) % n })
  external_sort(arr, config(32, 8))
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
  // Verify no elements lost.
  let count = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    count[arr[i]] = count[arr[i]] + 1
  }
  for i = 0; i < n; i = i + 1 {
    assert_eq(count[i], 1)
  }
}

///|
test "external_sort: duplicates" {
  let arr = FixedArray::makei(20, fn(i) { i % 3 })
  external_sort(arr, config(5, 2))
  for i = 0; i < 19; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
test "external_sort: single run" {
  let arr = FixedArray::makei(5, fn(i) { 4 - i })
  external_sort(arr, config(10, 2)) // buffer > n, single run
  for i = 0; i < 5; i = i + 1 {
    assert_eq(arr[i], i)
  }
}
