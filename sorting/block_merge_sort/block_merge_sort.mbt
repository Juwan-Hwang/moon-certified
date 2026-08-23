/// Block Merge Sort — stable, efficient merge sort with block-level optimization.
///
/// This implementation uses a **bottom-up merge sort** with a temporary
/// buffer of size n/2, combined with **block-level insertion sort** for
/// small runs. This approach:
///
/// 1. Divides the array into blocks of size `BLOCK_SIZE` (typically 32–64).
/// 2. Sorts each block with insertion sort (fast for small n, cache-friendly).
/// 3. Merges adjacent sorted runs bottom-up, doubling the run length each pass.
/// 4. Uses a temporary buffer to achieve O(n) space and O(n log n) time.
///
/// This is the same strategy used by Rust's `slice::sort` and the C++ standard
/// library's `std::stable_sort`.
///
/// ## Complexity
///
/// | Case     | Comparisons | Space  | Stable |
/// |----------|-------------|--------|--------|
/// | All      | O(n log n)  | O(n)   | Yes    |
///
/// ## References
///
/// - Knuth, D. E. (1998). *The Art of Computer Programming, Vol. 3:
///   Sorting and Searching*, 2nd ed. Addison-Wesley. §5.2.4 (merge sorting).
/// - Pardo, L. T. (1977). "Stable Sorting and Merging in Optimal Time and
///   Space." *Computer Journal* 20(4), 354–358.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Block size for insertion sort pre-processing.
const BLOCK_SIZE : Int = 32

///|
/// Sort an array of integers in ascending order using block merge sort.
///
/// The input array is sorted **in place**; the algorithm uses O(n) auxiliary
/// storage internally.
pub fn block_merge_sort(arr : Array[Int]) -> Unit {
  let n = arr.length()
  if n <= 1 {
    return
  }
  // Step 1: Sort small blocks with insertion sort
  let mut start = 0
  while start < n {
    let end = if start + BLOCK_SIZE < n { start + BLOCK_SIZE } else { n }
    insertion_sort_range(arr, start, end)
    start = start + BLOCK_SIZE
  }
  // Step 2: Bottom-up merge passes
  let buf : Array[Int] = Array::make(n, 0)
  let mut width = BLOCK_SIZE
  while width < n {
    let mut i = 0
    while i < n {
      let mid = i + width
      let hi = if i + 2 * width < n { i + 2 * width } else { n }
      if mid < hi {
        merge_with_buf(arr, i, mid, hi, buf)
      }
      i = i + 2 * width
    }
    width = width * 2
  }
}

///|
/// Sort an array of doubles using block merge sort.
pub fn block_merge_sort_double(arr : Array[Double]) -> Unit {
  let n = arr.length()
  if n <= 1 {
    return
  }
  let mut start = 0
  while start < n {
    let end = if start + BLOCK_SIZE < n { start + BLOCK_SIZE } else { n }
    insertion_sort_range_double(arr, start, end)
    start = start + BLOCK_SIZE
  }
  let buf : Array[Double] = Array::make(n, 0.0)
  let mut width = BLOCK_SIZE
  while width < n {
    let mut i = 0
    while i < n {
      let mid = i + width
      let hi = if i + 2 * width < n { i + 2 * width } else { n }
      if mid < hi {
        merge_with_buf_double(arr, i, mid, hi, buf)
      }
      i = i + 2 * width
    }
    width = width * 2
  }
}

///|
/// Insertion sort for a range [lo, hi).
fn insertion_sort_range(arr : Array[Int], lo : Int, hi : Int) -> Unit {
  for i = lo + 1; i < hi; i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= lo && arr[j] > key {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}

///|
fn insertion_sort_range_double(arr : Array[Double], lo : Int, hi : Int) -> Unit {
  for i = lo + 1; i < hi; i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= lo && arr[j] > key {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}

///|
/// Stable merge of arr[lo..mid) and arr[mid..hi) using a temporary buffer.
///
/// Copies the left half into `buf`, then merges from buf and the right half
/// back into arr. This is the standard stable merge with O(hi - lo) extra space.
fn merge_with_buf(
  arr : Array[Int],
  lo : Int,
  mid : Int,
  hi : Int,
  buf : Array[Int],
) -> Unit {
  let left_len = mid - lo
  // Copy left half to buffer
  for i = 0; i < left_len; i = i + 1 {
    buf[i] = arr[lo + i]
  }
  let mut i = 0 // index into buffer (left half)
  let mut j = mid // index into right half
  let mut k = lo // output index
  while i < left_len && j < hi {
    if buf[i] <= arr[j] {
      arr[k] = buf[i]
      i = i + 1
    } else {
      arr[k] = arr[j]
      j = j + 1
    }
    k = k + 1
  }
  // Copy remaining left elements
  while i < left_len {
    arr[k] = buf[i]
    i = i + 1
    k = k + 1
  }
  // Right elements are already in place
}

///|
fn merge_with_buf_double(
  arr : Array[Double],
  lo : Int,
  mid : Int,
  hi : Int,
  buf : Array[Double],
) -> Unit {
  let left_len = mid - lo
  for i = 0; i < left_len; i = i + 1 {
    buf[i] = arr[lo + i]
  }
  let mut i = 0
  let mut j = mid
  let mut k = lo
  while i < left_len && j < hi {
    if buf[i] <= arr[j] {
      arr[k] = buf[i]
      i = i + 1
    } else {
      arr[k] = arr[j]
      j = j + 1
    }
    k = k + 1
  }
  while i < left_len {
    arr[k] = buf[i]
    i = i + 1
    k = k + 1
  }
}
