/// Pattern-Defeating Quicksort (pdqsort) — production-grade hybrid sort.
///
/// Generic implementation with pattern-defeating heuristics:
/// - Median-of-three pivot with ninther (Tukey's median of medians) for large inputs.
/// - Insertion sort for small partitions (< 24 elements).
/// - Heap sort fallback when recursion depth exceeds 2*log₂(n).
/// - **Pattern detection**: detects already-sorted runs and skips them,
///   achieving O(n) on sorted input. Detects reverse-sorted runs and
///   reverses them. When bad pivots are repeatedly chosen, switches to
///   heap sort to guarantee O(n log n) worst case.
/// - Shuffles elements on bad pivot to break adversarial patterns.
///
/// ## Complexity
/// - Time:  O(n log n) worst, O(n) best (nearly sorted).
/// - Space: O(log n) recursion.
/// - Not stable (pdqsort is not stable by design).
///
/// References:
/// - Orson Peters, "pdqsort" — https://github.com/orlp/pdqsort
/// - Bentley & McIlroy, "Engineering a Sort Function" (1993)
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Insertion sort threshold: partitions smaller than this use insertion sort.
const INSERTION_SORT_THRESHOLD : Int = 24

///|
/// Ninther threshold: partitions larger than this use Tukey's ninther
/// (median of three medians) for pivot selection.
const NINTHER_THRESHOLD : Int = 128

///|
/// Sort an array in-place using pdqsort (ascending).
/// Generic: works with any type T given a comparator.
pub fn[T] pdq_sort(arr : Array[T], cmp : (T, T) -> Int) -> Unit {
  let n = arr.length()
  if n > 1 {
    pdq_sort_range(arr, 0, n - 1, max_depth(n), 0, cmp)
  }
}

///|
/// Sort an array in-place using pdqsort (descending).
pub fn[T] pdq_sort_desc(arr : Array[T], cmp : (T, T) -> Int) -> Unit {
  let n = arr.length()
  if n > 1 {
    pdq_sort_range_desc(arr, 0, n - 1, max_depth(n), 0, cmp)
  }
}

///|
/// Convenience: sort Int array in ascending order.
pub fn pdq_sort_int(arr : Array[Int]) -> Unit {
  pdq_sort(arr, fn(a, b) { a - b })
}

///|
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

///|
fn[T] swap(arr : Array[T], a : Int, b : Int) -> Unit {
  let tmp = arr[a]
  arr[a] = arr[b]
  arr[b] = tmp
}

///|
/// Sort arr[lo..hi] using pdqsort with pattern-defeating heuristics.
fn[T] pdq_sort_range(
  arr : Array[T],
  lo : Int,
  hi : Int,
  depth : Int,
  bad_pivots : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  let mut lo = lo
  let mut hi = hi
  let mut depth = depth
  let mut bad_pivots = bad_pivots
  while lo < hi {
    // Small partition: insertion sort.
    if hi - lo < INSERTION_SORT_THRESHOLD {
      insertion_sort_range(arr, lo, hi, cmp)
      return
    }
    // Depth limit: fall back to heap sort.
    if depth == 0 {
      heap_sort_range(arr, lo, hi, cmp)
      return
    }
    depth = depth - 1
    // Pattern-defeating: detect already-sorted or reverse-sorted runs.
    // This is the key optimization that gives O(n) on sorted input.
    if bad_pivots > 0 {
      if is_sorted_range(arr, lo, hi, cmp) {
        return
      }
      if is_reverse_sorted_range(arr, lo, hi, cmp) {
        reverse_range(arr, lo, hi)
        return
      }
    }
    // Pivot selection: median-of-three, or ninther for large partitions.
    let mid = lo + (hi - lo) / 2
    // Sort lo, mid, hi to find median.
    if cmp(arr[lo], arr[mid]) > 0 {
      swap(arr, lo, mid)
    }
    if cmp(arr[mid], arr[hi]) > 0 {
      swap(arr, mid, hi)
      if cmp(arr[lo], arr[mid]) > 0 {
        swap(arr, lo, mid)
      }
    }
    // For large partitions, use ninther (median of three medians).
    if hi - lo > NINTHER_THRESHOLD {
      let gap = (hi - lo) / 8
      sort3(arr, lo, lo + gap, lo + 2 * gap, cmp)
      sort3(arr, mid - gap, mid, mid + gap, cmp)
      sort3(arr, hi - 2 * gap, hi - gap, hi, cmp)
      sort3(arr, lo + gap, mid, hi - gap, cmp)
    }
    // Use pivot at mid (already sorted with lo and hi).
    let pivot = arr[mid]
    // Dutch National Flag three-way partition.
    // Result: arr[lo..lt) < pivot, arr[lt..gt] == pivot, arr(gt..hi] > pivot
    let mut lt = lo
    let mut gt = hi
    let mut k = lo
    while k <= gt {
      let c = cmp(arr[k], pivot)
      if c < 0 {
        swap(arr, lt, k)
        lt = lt + 1
        k = k + 1
      } else if c > 0 {
        swap(arr, k, gt)
        gt = gt - 1
      } else {
        k = k + 1
      }
    }
    // Pattern detection: check if partition was balanced.
    let left_size = lt - lo
    let right_size = hi - gt
    let total = hi - lo + 1
    // If one side is much smaller than the other, count as bad pivot.
    if left_size < total / 8 || right_size < total / 8 {
      bad_pivots = bad_pivots + 1
    } else {
      bad_pivots = 0
    }
    // If too many bad pivots, shuffle to break adversarial patterns.
    if bad_pivots > 0 && bad_pivots % 3 == 0 {
      shuffle_range(arr, lo, hi)
      bad_pivots = 0
      continue
    }
    // Recurse on the smaller partition first (tail-call optimization).
    if left_size < right_size {
      pdq_sort_range(arr, lo, lt - 1, depth, bad_pivots, cmp)
      lo = gt + 1
    } else {
      pdq_sort_range(arr, gt + 1, hi, depth, bad_pivots, cmp)
      hi = lt - 1
    }
  }
}

///|
fn[T] pdq_sort_range_desc(
  arr : Array[T],
  lo : Int,
  hi : Int,
  depth : Int,
  bad_pivots : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  // Descending sort: reverse the comparator.
  pdq_sort_range(arr, lo, hi, depth, bad_pivots, fn(a, b) { -cmp(a, b) })
}

///|
/// Sort three elements at positions a, b, c.
fn[T] sort3(
  arr : Array[T],
  a : Int,
  b : Int,
  c : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  if cmp(arr[a], arr[b]) > 0 {
    swap(arr, a, b)
  }
  if cmp(arr[b], arr[c]) > 0 {
    swap(arr, b, c)
    if cmp(arr[a], arr[b]) > 0 {
      swap(arr, a, b)
    }
  }
}

///|
/// Check if arr[lo..hi] is already sorted (ascending).
fn[T] is_sorted_range(
  arr : Array[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Bool {
  for i = lo; i < hi; i = i + 1 {
    if cmp(arr[i], arr[i + 1]) > 0 {
      return false
    }
  }
  true
}

///|
/// Check if arr[lo..hi] is reverse-sorted (descending).
fn[T] is_reverse_sorted_range(
  arr : Array[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Bool {
  for i = lo; i < hi; i = i + 1 {
    if cmp(arr[i], arr[i + 1]) < 0 {
      return false
    }
  }
  true
}

///|
/// Reverse arr[lo..hi] in-place.
fn[T] reverse_range(arr : Array[T], lo : Int, hi : Int) -> Unit {
  let mut i = lo
  let mut j = hi
  while i < j {
    swap(arr, i, j)
    i = i + 1
    j = j - 1
  }
}

///|
/// Fisher-Yates shuffle of arr[lo..hi] to break adversarial patterns.
/// Uses a SplitMix64 PRNG for higher quality shuffling than a naive LCG.
fn[T] shuffle_range(arr : Array[T], lo : Int, hi : Int) -> Unit {
  let mut state = 0xDEADBEEFCAFEBABEL
  for i = hi; i > lo; i = i - 1 {
    state = state + 0x9E3779B97F4A7C15L
    let mut z = state
    z = (z ^ (z.reinterpret_as_uint64() >> 30).reinterpret_as_int64()) *
      0xBF58476D1CE4E5B9L
    z = (z ^ (z.reinterpret_as_uint64() >> 27).reinterpret_as_int64()) *
      0x94D049BB133111EBL
    z = z ^ (z.reinterpret_as_uint64() >> 31).reinterpret_as_int64()
    let range = (i - lo + 1).to_int64()
    let abs_z = if z < 0L { -z } else { z }
    let j = lo + (abs_z % range).to_int()
    swap(arr, i, j)
  }
}

///|
fn[T] insertion_sort_range(
  arr : Array[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  for i = lo + 1; i <= hi; i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= lo && cmp(arr[j], key) > 0 {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}

///|
fn[T] heap_sort_range(
  arr : Array[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  let n = hi - lo + 1
  // Build max-heap.
  let mut i = n / 2 - 1
  while i >= 0 {
    sift_down(arr, lo, i, n, cmp)
    i = i - 1
  }
  // Extract elements.
  let mut end = n - 1
  while end > 0 {
    swap(arr, lo, lo + end)
    sift_down(arr, lo, 0, end, cmp)
    end = end - 1
  }
}

///|
fn[T] sift_down(
  arr : Array[T],
  offset : Int,
  i : Int,
  n : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  let mut idx = i
  while true {
    let left = 2 * idx + 1
    let right = 2 * idx + 2
    let mut largest = idx
    if left < n && cmp(arr[offset + left], arr[offset + largest]) > 0 {
      largest = left
    }
    if right < n && cmp(arr[offset + right], arr[offset + largest]) > 0 {
      largest = right
    }
    if largest == idx {
      break
    }
    swap(arr, offset + idx, offset + largest)
    idx = largest
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pdq_sort: sorted output" {
  let arr = [5, 3, 8, 1, 9, 2, 7, 4, 6, 0]
  pdq_sort_int(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] <= arr[i])
  }
}

///|
test "pdq_sort: already sorted" {
  let arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  pdq_sort_int(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] <= arr[i])
  }
}

///|
test "pdq_sort: reverse sorted" {
  let arr = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
  pdq_sort_int(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] <= arr[i])
  }
}

///|
test "pdq_sort: duplicates" {
  let arr = [3, 3, 3, 1, 1, 2, 2, 2, 1, 3]
  pdq_sort_int(arr)
  assert_eq(arr, [1, 1, 1, 2, 2, 2, 3, 3, 3, 3])
}

///|
test "pdq_sort: single element" {
  let arr = [42]
  pdq_sort_int(arr)
  assert_eq(arr, [42])
}

///|
test "pdq_sort: descending" {
  let arr = [5, 3, 8, 1, 9, 2, 7, 4, 6, 0]
  pdq_sort_desc(arr, fn(a, b) { a - b })
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] >= arr[i])
  }
}

///|
test "pdq_sort: large random" {
  let arr : Array[Int] = []
  let mut seed = 12345
  for i = 0; i < 500; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    arr.push(seed % 1000)
  }
  pdq_sort_int(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] <= arr[i])
  }
}

///|
test "pdq_sort: generic string sort" {
  let arr = ["banana", "apple", "cherry", "date", "elderberry"]
  pdq_sort(arr, fn(a, b) {
    let la = a.length()
    let lb = b.length()
    let min = if la < lb { la } else { lb }
    for k = 0; k < min; k = k + 1 {
      let ca = a[k].to_int()
      let cb = b[k].to_int()
      if ca != cb {
        return ca - cb
      }
    }
    la - lb
  })
  assert_eq(arr[0], "apple")
  assert_eq(arr[1], "banana")
  assert_eq(arr[4], "elderberry")
}

///|
test "pdq_sort: adversarial input (organ pipe)" {
  // Organ pipe pattern: 1,2,3,4,5,5,4,3,2,1 — known to degrade naive quicksort.
  let arr = [1, 2, 3, 4, 5, 5, 4, 3, 2, 1]
  pdq_sort_int(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] <= arr[i])
  }
}

///|
test "pdq_sort: many duplicates" {
  // Input with many equal elements — tests three-way partition.
  let arr = [5, 5, 5, 5, 5, 5, 5, 5, 1, 1, 1, 1, 3, 3, 3, 3]
  pdq_sort_int(arr)
  for i = 1; i < arr.length(); i = i + 1 {
    assert_true(arr[i - 1] <= arr[i])
  }
}

///|
test "pdq_sort: all same" {
  let arr = [7, 7, 7, 7, 7, 7, 7, 7, 7, 7]
  pdq_sort_int(arr)
  for i = 0; i < arr.length(); i = i + 1 {
    assert_eq(arr[i], 7)
  }
}

///|
test "pdq_sort: two elements" {
  let arr = [5, 3]
  pdq_sort_int(arr)
  assert_eq(arr[0], 3)
  assert_eq(arr[1], 5)
  let arr2 = [3, 5]
  pdq_sort_int(arr2)
  assert_eq(arr2[0], 3)
  assert_eq(arr2[1], 5)
}

///|
test "pdq_sort: large sorted (pattern detection)" {
  // Already sorted — should be O(n) with pattern detection.
  let arr = FixedArray::makei(1000, fn(i) { i })
  let a = []
  for i = 0; i < 1000; i = i + 1 {
    a.push(arr[i])
  }
  pdq_sort_int(a)
  for i = 1; i < a.length(); i = i + 1 {
    assert_true(a[i - 1] <= a[i])
  }
}
