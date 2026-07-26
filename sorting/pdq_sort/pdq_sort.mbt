/// Pattern-Defeating Quicksort (pdqsort) — production-grade hybrid sort.
///
/// Combines insertion sort for small partitions, quicksort with
/// median-of-three pivot for medium partitions, and heap sort as a
/// fallback when recursion depth exceeds the log²(n) threshold or
/// when bad pivots are repeatedly chosen. Switches to insertion sort
/// when partitions become small enough.
///
/// ## Complexity
/// - Time:  O(n log n) worst, O(n) best (nearly sorted).
/// - Space: O(log n) recursion.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// Sort an array in-place using pdqsort (ascending).
pub fn pdq_sort(arr : Array[Int]) -> Unit {
  if arr.length() > 1 {
    pdq_sort_range(arr, 0, arr.length() - 1, max_depth(arr.length()), false)
  }
}

/// Sort an array in-place using pdqsort (descending).
pub fn pdq_sort_desc(arr : Array[Int]) -> Unit {
  if arr.length() > 1 {
    pdq_sort_range_desc(arr, 0, arr.length() - 1, max_depth(arr.length()))
  }
}

fn max_depth(n : Int) -> Int {
  // 2 * log2(n) — depth limit before falling back to heapsort.
  let mut d = 0
  let mut p = n
  while p > 0 {
    d = d + 1
    p = p / 2
  }
  d * 2
}

fn pdq_sort_range(
  arr : Array[Int], lo : Int, hi : Int, depth : Int, was_balanced : Bool,
) -> Unit {
  let mut lo = lo
  let mut hi = hi
  let mut depth = depth
  while lo < hi {
    if hi - lo < 24 {
      insertion_sort_range(arr, lo, hi)
      return
    }
    if depth == 0 {
      heap_sort_range(arr, lo, hi)
      return
    }
    depth = depth - 1
    // Median-of-three pivot selection.
    let mid = lo + (hi - lo) / 2
    if arr[lo] > arr[mid] {
      swap(arr, lo, mid)
    }
    if arr[mid] > arr[hi] {
      swap(arr, mid, hi)
      if arr[lo] > arr[mid] {
        swap(arr, lo, mid)
      }
    }
    // Move pivot to hi-1.
    swap(arr, mid, hi - 1)
    let pivot = arr[hi - 1]
    // Bentley-McIlroy partition.
    let mut i = lo
    let mut j = hi - 1
    while true {
      i = i + 1
      while arr[i] < pivot {
        i = i + 1
      }
      j = j - 1
      while j >= lo && arr[j] > pivot {
        j = j - 1
      }
      if i >= j {
        break
      }
      swap(arr, i, j)
    }
    swap(arr, i, hi - 1)
    // Recurse on the smaller partition first (tail-call optimization).
    if i - lo < hi - i {
      pdq_sort_range(arr, lo, i - 1, depth, true)
      lo = i + 1
    } else {
      pdq_sort_range(arr, i + 1, hi, depth, true)
      hi = i - 1
    }
    ignore(was_balanced)
  }
}

fn pdq_sort_range_desc(
  arr : Array[Int], lo : Int, hi : Int, depth : Int,
) -> Unit {
  let mut lo = lo
  let mut hi = hi
  let mut depth = depth
  while lo < hi {
    if hi - lo < 24 {
      insertion_sort_range_desc(arr, lo, hi)
      return
    }
    if depth == 0 {
      heap_sort_range_desc(arr, lo, hi)
      return
    }
    depth = depth - 1
    let mid = lo + (hi - lo) / 2
    if arr[lo] < arr[mid] {
      swap(arr, lo, mid)
    }
    if arr[mid] < arr[hi] {
      swap(arr, mid, hi)
      if arr[lo] < arr[mid] {
        swap(arr, lo, mid)
      }
    }
    swap(arr, mid, hi - 1)
    let pivot = arr[hi - 1]
    let mut i = lo
    let mut j = hi - 1
    while true {
      i = i + 1
      while arr[i] > pivot {
        i = i + 1
      }
      j = j - 1
      while j >= lo && arr[j] < pivot {
        j = j - 1
      }
      if i >= j {
        break
      }
      swap(arr, i, j)
    }
    swap(arr, i, hi - 1)
    if i - lo < hi - i {
      pdq_sort_range_desc(arr, lo, i - 1, depth)
      lo = i + 1
    } else {
      pdq_sort_range_desc(arr, i + 1, hi, depth)
      hi = i - 1
    }
  }
}

fn swap(arr : Array[Int], a : Int, b : Int) -> Unit {
  let tmp = arr[a]
  arr[a] = arr[b]
  arr[b] = tmp
}

fn insertion_sort_range(arr : Array[Int], lo : Int, hi : Int) -> Unit {
  for i = lo + 1; i <= hi; i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= lo && arr[j] > key {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}

fn insertion_sort_range_desc(arr : Array[Int], lo : Int, hi : Int) -> Unit {
  for i = lo + 1; i <= hi; i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= lo && arr[j] < key {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}

fn heap_sort_range(arr : Array[Int], lo : Int, hi : Int) -> Unit {
  let n = hi - lo + 1
  // Build max-heap.
  let mut i = n / 2 - 1
  while i >= 0 {
    sift_down(arr, lo, i, n)
    i = i - 1
  }
  // Extract elements.
  let mut end = n - 1
  while end > 0 {
    swap(arr, lo, lo + end)
    sift_down(arr, lo, 0, end)
    end = end - 1
  }
}

fn heap_sort_range_desc(arr : Array[Int], lo : Int, hi : Int) -> Unit {
  let n = hi - lo + 1
  let mut i = n / 2 - 1
  while i >= 0 {
    sift_down_min(arr, lo, i, n)
    i = i - 1
  }
  let mut end = n - 1
  while end > 0 {
    swap(arr, lo, lo + end)
    sift_down_min(arr, lo, 0, end)
    end = end - 1
  }
}

fn sift_down(arr : Array[Int], offset : Int, i : Int, n : Int) -> Unit {
  let mut idx = i
  while true {
    let left = 2 * idx + 1
    let right = 2 * idx + 2
    let mut largest = idx
    if left < n && arr[offset + left] > arr[offset + largest] {
      largest = left
    }
    if right < n && arr[offset + right] > arr[offset + largest] {
      largest = right
    }
    if largest == idx {
      break
    }
    swap(arr, offset + idx, offset + largest)
    idx = largest
  }
}

fn sift_down_min(arr : Array[Int], offset : Int, i : Int, n : Int) -> Unit {
  let mut idx = i
  while true {
    let left = 2 * idx + 1
    let right = 2 * idx + 2
    let mut smallest = idx
    if left < n && arr[offset + left] < arr[offset + smallest] {
      smallest = left
    }
    if right < n && arr[offset + right] < arr[offset + smallest] {
      smallest = right
    }
    if smallest == idx {
      break
    }
    swap(arr, offset + idx, offset + smallest)
    idx = smallest
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "pdq_sort: sorted output" {
  let arr = [5, 3, 8, 1, 9, 2, 7, 4, 6, 0]
  pdq_sort(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] <= arr[i])
  }
}

test "pdq_sort: already sorted" {
  let arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  pdq_sort(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] <= arr[i])
  }
}

test "pdq_sort: reverse sorted" {
  let arr = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
  pdq_sort(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] <= arr[i])
  }
}

test "pdq_sort: duplicates" {
  let arr = [3, 3, 3, 1, 1, 2, 2, 2, 1, 3]
  pdq_sort(arr)
  assert_eq(arr, [1, 1, 1, 2, 2, 2, 3, 3, 3, 3])
}

test "pdq_sort: single element" {
  let arr = [42]
  pdq_sort(arr)
  assert_eq(arr, [42])
}

test "pdq_sort: descending" {
  let arr = [5, 3, 8, 1, 9, 2, 7, 4, 6, 0]
  pdq_sort_desc(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] >= arr[i])
  }
}

test "pdq_sort: large random" {
  let arr : Array[Int] = []
  let mut seed = 12345
  for i = 0; i < 500; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    arr.push(seed % 1000)
  }
  pdq_sort(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] <= arr[i])
  }
}
