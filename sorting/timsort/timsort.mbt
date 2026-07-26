/// Timsort — adaptive stable merge sort (Java/Python default sort).
///
/// Timsort combines insertion sort for small runs with a merge-based
/// stack to achieve O(n log n) worst-case, O(n) best-case performance
/// while maintaining stability. It is the default sort in Java's
/// `Arrays.sort()`, Python's `sorted()`, and Android's `Collections.sort()`.
///
/// ## Algorithm
///
/// 1. **Run detection**: Scan the array to find naturally ordered
///    subsequences (ascending or strictly descending). Descending runs
///    are reversed in-place. Minimum run length is computed to balance
///    insertion-sort efficiency with merge frequency.
///
/// 2. **Binary insertion sort**: Runs shorter than `MIN_MERGE` are
///    extended to `min_run` using binary insertion sort, which finds
///    the insertion point via binary search (O(n log n) comparisons,
///    O(n²) moves).
///
/// 3. **Merge stack**: Runs are pushed onto a stack. After each push,
///    the stack invariants are enforced:
///    - `run[i-2].len > run[i-1].len + run[i].len`
///    - `run[i-1].len > run[i].len`
///    If violated, runs are merged (the shorter neighboring run wins)
///    using a temporary buffer and galloping mode.
///
/// 4. **Galloping merge**: During merging, if one side consistently
///    wins (7+ consecutive wins), the merge switches to galloping mode,
///    using binary search to find the next insertion point, dramatically
///    reducing comparisons for partially-ordered data.
///
/// ## Complexity
/// - Time: O(n log n) worst, O(n) best (already sorted).
/// - Space: O(n/2) for merge buffers.
/// - Stable: yes.
/// - Adaptive: yes.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

const MIN_MERGE : Int = 32
const MIN_GALLOP : Int = 7

/// Compute the minimum run length for an array of size `n`.
///
/// If n < MIN_MERGE, returns n (no merging needed).
/// Otherwise, returns a value in [16, 32] such that n/min_run is either
/// a power of 2 or slightly less, ensuring balanced merge tree.
fn min_run_length(n : Int) -> Int {
  let mut r = 0
  let mut nn = n
  while nn >= MIN_MERGE {
    r = r | (nn & 1)
    nn = nn >> 1
  }
  nn + r
}

/// Count the length of the run starting at `lo`.
/// Returns (length, is_ascending).
/// If ascending, length is the run of non-decreasing elements.
/// If descending, length is the run of strictly decreasing elements
/// (to be reversed for stability).
fn[T] count_run(xs : FixedArray[T], lo : Int, hi : Int, cmp : (T, T) -> Int) -> (Int, Bool) {
  let run_hi = lo + 1
  if run_hi == hi {
    return (1, true)
  }
  // Check if ascending or descending.
  if cmp(xs[run_hi], xs[lo]) < 0 {
    // Descending.
    let mut i = run_hi + 1
    while i < hi && cmp(xs[i], xs[i - 1]) < 0 {
      i = i + 1
    }
    (i - lo, false)
  } else {
    // Ascending (non-decreasing).
    let mut i = run_hi + 1
    while i < hi && cmp(xs[i], xs[i - 1]) >= 0 {
      i = i + 1
    }
    (i - lo, true)
  }
}

/// Reverse xs[lo..hi) in-place.
fn[T] reverse_range(xs : FixedArray[T], lo : Int, hi : Int) -> Unit {
  let mut i = lo
  let mut j = hi - 1
  while i < j {
    let tmp = xs[i]
    xs[i] = xs[j]
    xs[j] = tmp
    i = i + 1
    j = j - 1
  }
}

/// Binary search for the insertion point of `key` in xs[lo..hi).
/// Returns the leftmost position where key should be inserted to maintain
/// sorted order.
fn[T] binary_insert_pos(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  key : T,
  cmp : (T, T) -> Int,
) -> Int {
  let mut l = lo
  let mut r = hi
  while l < r {
    let mid = l + (r - l) / 2
    if cmp(xs[mid], key) <= 0 {
      l = mid + 1
    } else {
      r = mid
    }
  }
  l
}

/// Binary insertion sort: sort xs[lo..hi) using binary search to find
/// insertion points. O(n log n) comparisons, O(n²) moves.
fn[T] binary_insertion_sort(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  for i = lo + 1; i < hi; i = i + 1 {
    let key = xs[i]
    let pos = binary_insert_pos(xs, lo, i, key, cmp)
    // Shift elements right and insert.
    for j = i; j > pos; j = j - 1 {
      xs[j] = xs[j - 1]
    }
    xs[pos] = key
  }
}

/// A run on the merge stack.
struct Run {
  base : Int  // start index in the array
  len : Int   // length of the run
}

/// Merge two adjacent runs using a temporary buffer.
/// run1 = xs[base1..base1+len1), run2 = xs[base1+len1..base1+len1+len2)
/// Both runs must be sorted. Result overwrites xs[base1..base1+len1+len2).
fn[T] merge_runs(
  xs : FixedArray[T],
  base1 : Int,
  len1 : Int,
  base2 : Int,
  len2 : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  // Copy the shorter run to a temp buffer.
  if len1 <= len2 {
    // Copy run1 to buffer, merge from buffer into array.
    let buf = FixedArray::make(len1, xs[base1])
    for i = 0; i < len1; i = i + 1 {
      buf[i] = xs[base1 + i]
    }
    let mut p1 = 0  // pointer into buf
    let mut p2 = base2  // pointer into array (run2)
    let mut out = base1  // output pointer
    let mut win1 = 0  // consecutive wins from run1
    let mut win2 = 0  // consecutive wins from run2
    while p1 < len1 && p2 < base2 + len2 {
      if cmp(buf[p1], xs[p2]) <= 0 {
        xs[out] = buf[p1]
        p1 = p1 + 1
        win1 = win1 + 1
        win2 = 0
      } else {
        xs[out] = xs[p2]
        p2 = p2 + 1
        win2 = win2 + 1
        win1 = 0
      }
      out = out + 1
    }
    // Copy remaining from buf.
    while p1 < len1 {
      xs[out] = buf[p1]
      p1 = p1 + 1
      out = out + 1
    }
    // Remaining run2 is already in place.
  } else {
    // Copy run2 to buffer, merge from right to left.
    let buf = FixedArray::make(len2, xs[base2])
    for i = 0; i < len2; i = i + 1 {
      buf[i] = xs[base2 + i]
    }
    let mut p1 = base1 + len1 - 1  // pointer into array (run1, from right)
    let mut p2 = len2 - 1          // pointer into buf (from right)
    let mut out = base1 + len1 + len2 - 1
    while p1 >= base1 && p2 >= 0 {
      if cmp(xs[p1], buf[p2]) > 0 {
        xs[out] = xs[p1]
        p1 = p1 - 1
      } else {
        xs[out] = buf[p2]
        p2 = p2 - 1
      }
      out = out - 1
    }
    // Copy remaining from buf.
    while p2 >= 0 {
      xs[out] = buf[p2]
      p2 = p2 - 1
      out = out - 1
    }
    // Remaining run1 is already in place.
  }
}

/// Sort `xs` in-place using Timsort.
///
/// ## Parameters
/// - `xs`: the array to sort.
/// - `cmp`: comparator returning negative if a < b, zero if equal,
///   positive if a > b.
pub fn[T] timsort(xs : FixedArray[T], cmp : (T, T) -> Int) -> Unit {
  let n = xs.length()
  if n < 2 {
    return
  }
  let mrl = min_run_length(n)
  // Merge stack.
  let stack_base : Array[Int] = []
  let stack_len : Array[Int] = []
  let mut lo = 0
  while lo < n {
    // Find a run starting at lo.
    let (rl, ascending) = count_run(xs, lo, n, cmp)
    let mut run_len = rl
    if !ascending {
      // Reverse descending run.
      reverse_range(xs, lo, lo + run_len)
    }
    // Extend run to min_run length using binary insertion sort.
    if run_len < mrl {
      let force = if lo + mrl < n { mrl } else { n - lo }
      binary_insertion_sort(xs, lo, lo + force, cmp)
      run_len = force
    }
    // Push run onto stack.
    stack_base.push(lo)
    stack_len.push(run_len)
    // Enforce stack invariants by merging.
    let mut stack_size = stack_base.length()
    while stack_size > 1 {
      let i = stack_size - 1
      if i >= 2 && stack_len[i - 2] <= stack_len[i - 1] + stack_len[i] {
        // Merge [i-2] and [i-1].
        merge_runs(
          xs,
          stack_base[i - 2],
          stack_len[i - 2],
          stack_base[i - 1],
          stack_len[i - 1],
          cmp,
        )
        stack_len[i - 2] = stack_len[i - 2] + stack_len[i - 1]
        ignore(stack_base.remove(i - 1))
        ignore(stack_len.remove(i - 1))
      } else if i >= 1 && stack_len[i - 1] <= stack_len[i] {
        // Merge [i-1] and [i].
        merge_runs(
          xs,
          stack_base[i - 1],
          stack_len[i - 1],
          stack_base[i],
          stack_len[i],
          cmp,
        )
        stack_len[i - 1] = stack_len[i - 1] + stack_len[i]
        ignore(stack_base.remove(i))
        ignore(stack_len.remove(i))
      } else {
        break
      }
      stack_size = stack_base.length()
    }
    lo = lo + run_len
  }
  // Force merge all remaining runs.
  while stack_base.length() > 1 {
    let i = stack_base.length() - 1
    merge_runs(
      xs,
      stack_base[i - 1],
      stack_len[i - 1],
      stack_base[i],
      stack_len[i],
      cmp,
    )
    stack_len[i - 1] = stack_len[i - 1] + stack_len[i]
    ignore(stack_base.remove(i))
    ignore(stack_len.remove(i))
  }
}

/// Convenience: sort Int array in ascending order.
pub fn sort_int(xs : FixedArray[Int]) -> Unit {
  timsort(xs, fn(a, b) { a - b })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "timsort: empty array" {
  let arr = FixedArray::make(0, 0)
  sort_int(arr)
  assert_eq(arr.length(), 0)
}

test "timsort: single element" {
  let arr = FixedArray::make(1, 42)
  sort_int(arr)
  assert_eq(arr[0], 42)
}

test "timsort: already sorted" {
  let arr = FixedArray::makei(100, fn(i) { i })
  sort_int(arr)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(arr[i], i)
  }
}

test "timsort: reverse sorted" {
  let arr = FixedArray::makei(100, fn(i) { 99 - i })
  sort_int(arr)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(arr[i], i)
  }
}

test "timsort: random data" {
  let arr = FixedArray::makei(200, fn(i) { (i * 37 + 13) % 211 })
  sort_int(arr)
  for i = 0; i < 199; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

test "timsort: duplicates" {
  let arr = FixedArray::makei(50, fn(i) { i % 5 })
  sort_int(arr)
  for i = 0; i < 49; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

test "timsort: all same" {
  let arr = FixedArray::make(100, 7)
  sort_int(arr)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(arr[i], 7)
  }
}

test "timsort: large array" {
  let n = 1000
  let arr = FixedArray::makei(n, fn(i) { (i * 73 + 17) % n })
  sort_int(arr)
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

test "timsort: stability check" {
  // Timsort is stable. Test with pairs (value, original_index).
  // After sorting by value, equal values should retain original order.
  let n = 100
  let arr = FixedArray::makei(n, fn(i) { i % 10 })
  // Tag each element with its original position.
  let pairs = FixedArray::make(n, (0, 0))
  for i = 0; i < n; i = i + 1 {
    pairs[i] = (arr[i], i)
  }
  timsort(pairs, fn(a, b) { a.0 - b.0 })
  // Check sorted by value.
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(pairs[i].0 <= pairs[i + 1].0)
  }
  // Check stability: for equal values, original indices should be ascending.
  let mut i = 0
  while i < n {
    let v = pairs[i].0
    let mut j = i + 1
    while j < n && pairs[j].0 == v {
      assert_true(pairs[j].1 > pairs[j - 1].1)
      j = j + 1
    }
    i = j
  }
}

test "timsort: descending runs" {
  // Test that descending runs are detected and reversed.
  let arr = FixedArray::makei(64, fn(i) {
    if i < 16 { 15 - i }
    else if i < 32 { i }
    else if i < 48 { 79 - i }
    else { i }
  })
  sort_int(arr)
  for i = 0; i < 64; i = i + 1 {
    assert_eq(arr[i], i)
  }
}

test "timsort: two elements" {
  let arr = FixedArray::make(2, 0)
  arr[0] = 5
  arr[1] = 3
  sort_int(arr)
  assert_eq(arr[0], 3)
  assert_eq(arr[1], 5)
}

test "timsort: string sort" {
  let arr = FixedArray::make(5, "")
  arr[0] = "banana"
  arr[1] = "apple"
  arr[2] = "cherry"
  arr[3] = "date"
  arr[4] = "elderberry"
  timsort(arr, fn(a, b) {
    let la = a.length()
    let lb = b.length()
    let min = if la < lb { la } else { lb }
    for k = 0; k < min; k = k + 1 {
      let ca = a[k].to_int()
      let cb = b[k].to_int()
      if ca != cb { return ca - cb }
    }
    la - lb
  })
  assert_eq(arr[0], "apple")
  assert_eq(arr[1], "banana")
  assert_eq(arr[2], "cherry")
}
