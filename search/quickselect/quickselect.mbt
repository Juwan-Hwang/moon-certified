/// Quickselect (BFPTR) — k-th smallest element selection.
///
/// Finds the k-th smallest element in an unordered array in expected
/// O(n) time using the Lomuto or Hoare partition scheme. Includes the
/// "median-of-medians" deterministic variant that guarantees O(n) worst-case.
///
/// ## Complexity
/// - Time:  O(n) average (Hoare), O(n) worst (median-of-medians).
/// - Space: O(log n) recursion (Hoare), O(1) iterative.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Find the k-th smallest element (0-indexed) using Hoare partition.
/// Mutates the array (partial sort). Returns `None` if k is out of bounds.
pub fn quickselect(arr : Array[Int], k : Int) -> Int? {
  let n = arr.length()
  if k < 0 || k >= n {
    return None
  }
  let mut lo = 0
  let mut hi = n - 1
  while lo < hi {
    let pivot_idx = partition(arr, lo, hi)
    if pivot_idx == k {
      return Some(arr[k])
    } else if pivot_idx < k {
      lo = pivot_idx + 1
    } else {
      hi = pivot_idx - 1
    }
  }
  Some(arr[lo])
}

///|
/// Deterministic quickselect using median-of-medians (BFPTR algorithm).
/// Guarantees O(n) worst-case time.
pub fn quickselect_deterministic(arr : Array[Int], k : Int) -> Int? {
  let n = arr.length()
  if k < 0 || k >= n {
    return None
  }
  let mut lo = 0
  let mut hi = n - 1
  while lo < hi {
    let pivot = median_of_medians(arr, lo, hi)
    let pivot_idx = partition_around(arr, lo, hi, pivot)
    if pivot_idx == k {
      return Some(arr[k])
    } else if pivot_idx < k {
      lo = pivot_idx + 1
    } else {
      hi = pivot_idx - 1
    }
  }
  Some(arr[lo])
}

///|
/// Find the median of an array (odd length) or lower median (even length).
pub fn median(arr : Array[Int]) -> Int? {
  let n = arr.length()
  if n == 0 {
    return None
  }
  quickselect(arr, n / 2)
}

///|
fn partition(arr : Array[Int], lo : Int, hi : Int) -> Int {
  // Median-of-three pivot.
  let mid = lo + (hi - lo) / 2
  if arr[lo] > arr[mid] {
    @utils.swap_array(arr, lo, mid)
  }
  if arr[mid] > arr[hi] {
    @utils.swap_array(arr, mid, hi)
    if arr[lo] > arr[mid] {
      @utils.swap_array(arr, lo, mid)
    }
  }
  @utils.swap_array(arr, mid, hi)
  let pivot = arr[hi]
  let mut i = lo
  for j = lo; j < hi; j = j + 1 {
    if arr[j] <= pivot {
      @utils.swap_array(arr, i, j)
      i = i + 1
    }
  }
  @utils.swap_array(arr, i, hi)
  i
}

///|
fn partition_around(arr : Array[Int], lo : Int, hi : Int, pivot : Int) -> Int {
  let mut i = lo
  for j = lo; j <= hi; j = j + 1 {
    if arr[j] < pivot {
      @utils.swap_array(arr, i, j)
      i = i + 1
    }
  }
  // Find the first element >= pivot to get the partition index.
  let idx = i
  for j = i; j <= hi; j = j + 1 {
    if arr[j] == pivot {
      @utils.swap_array(arr, idx, j)
      break
    }
  }
  idx
}

///|
fn median_of_medians(arr : Array[Int], lo : Int, hi : Int) -> Int {
  let n = hi - lo + 1
  if n <= 5 {
    // Sort the small group and return median.
    let group : Array[Int] = []
    for i = lo; i <= hi; i = i + 1 {
      group.push(arr[i])
    }
    for i = 1; i < group.length(); i = i + 1 {
      let key = group[i]
      let mut j = i - 1
      while j >= 0 && group[j] > key {
        group[j + 1] = group[j]
        j = j - 1
      }
      group[j + 1] = key
    }
    return group[group.length() / 2]
  }
  // Divide into groups of 5, find median of each.
  let medians : Array[Int] = []
  let mut i = lo
  while i <= hi {
    let end = if i + 4 <= hi { i + 4 } else { hi }
    let group : Array[Int] = []
    for j = i; j <= end; j = j + 1 {
      group.push(arr[j])
    }
    for a = 1; a < group.length(); a = a + 1 {
      let key = group[a]
      let mut b = a - 1
      while b >= 0 && group[b] > key {
        group[b + 1] = group[b]
        b = b - 1
      }
      group[b + 1] = key
    }
    medians.push(group[group.length() / 2])
    i = end + 1
  }
  // Recursively find median of medians.
  let m = medians.length()
  if m <= 5 {
    for i = 1; i < m; i = i + 1 {
      let key = medians[i]
      let mut j = i - 1
      while j >= 0 && medians[j] > key {
        medians[j + 1] = medians[j]
        j = j - 1
      }
      medians[j + 1] = key
    }
    medians[m / 2]
  } else {
    // Copy to a temp and recurse.
    let tmp : Array[Int] = []
    for i = 0; i < m; i = i + 1 {
      tmp.push(medians[i])
    }
    match quickselect_deterministic(tmp, m / 2) {
      Some(v) => v
      None => medians[0]
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "quickselect: k-th smallest" {
  let arr = [7, 10, 4, 3, 20, 15]
  assert_eq(quickselect(arr.copy(), 0), Some(3))
  assert_eq(quickselect(arr.copy(), 1), Some(4))
  assert_eq(quickselect(arr.copy(), 2), Some(7))
  assert_eq(quickselect(arr.copy(), 3), Some(10))
  assert_eq(quickselect(arr.copy(), 4), Some(15))
  assert_eq(quickselect(arr.copy(), 5), Some(20))
}

///|
test "quickselect: out of bounds" {
  let arr = [1, 2, 3]
  assert_eq(quickselect(arr, -1), None)
  assert_eq(quickselect(arr, 3), None)
}

///|
test "quickselect: single element" {
  assert_eq(quickselect([42], 0), Some(42))
}

///|
test "quickselect: duplicates" {
  let arr = [3, 3, 3, 1, 1, 2, 2, 2, 1, 3]
  assert_eq(quickselect(arr.copy(), 0), Some(1))
  assert_eq(quickselect(arr.copy(), 9), Some(3))
}

///|
test "quickselect: deterministic matches hoare" {
  let arr1 = [7, 10, 4, 3, 20, 15, 8, 12, 6, 1]
  let arr2 = arr1.copy()
  for k = 0; k < 10; k = k + 1 {
    assert_eq(
      quickselect(arr1.copy(), k),
      quickselect_deterministic(arr2.copy(), k),
    )
  }
}

///|
test "quickselect: median" {
  let arr = [5, 2, 8, 1, 9, 3, 7]
  assert_eq(median(arr.copy()), Some(5))
}

///|
test "quickselect: large array" {
  let arr : Array[Int] = []
  let mut seed = 99999
  for i = 0; i < 1000; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    arr.push(seed % 10000)
  }
  let sorted = arr.copy()
  // Use introsort-like approach: sort a copy for verification.
  sorted.sort()
  let k = 500
  assert_eq(quickselect(arr.copy(), k), Some(sorted[k]))
}
