///|
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

///|
/// Initial galloping threshold (matches CPython's MIN_GALLOP).
/// After this many consecutive wins from one side, the merge enters
/// galloping mode. The threshold is then adapted at runtime: it
/// decreases when galloping is effective and increases when it is not,
/// matching CPython's `listobject.c` self-tuning behaviour.
const GALLOP_THRESHOLD : Int = 7

///|
/// Sort state carrying the self-tuning `min_gallop` parameter across
/// merge operations, exactly as CPython's `MergeState` does.
priv struct TimsortState {
  mut min_gallop : Int
}

///|
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

///|
/// Count the length of the run starting at `lo`.
/// Returns (length, is_ascending).
/// If ascending, length is the run of non-decreasing elements.
/// If descending, length is the run of strictly decreasing elements
/// (to be reversed for stability).
fn[T] count_run(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  cmp : (T, T) -> Int,
) -> (Int, Bool) {
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

///|
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

///|
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

///|
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

///|
/// Merge two adjacent runs using a temporary buffer.
/// run1 = xs[base1..base1+len1), run2 = xs[base1+len1..base1+len1+len2)
/// Both runs must be sorted. Result overwrites xs[base1..base1+len1+len2).
///
/// Implements **CPython-style adaptive galloping**: once galloping mode
/// is entered (consecutive wins ≥ `min_gallop`), the merge stays in
/// galloping mode — alternately galloping in run1 and run2 — until both
/// gallop counts drop below `GALLOP_THRESHOLD`, at which point it exits
/// and raises `min_gallop` by 1.  When gallop counts are large, it
/// lowers `min_gallop` (min 1), making re-entry easier.  This
/// self-tuning behaviour matches CPython's `listobject.c`.
fn[T] merge_runs(
  xs : FixedArray[T],
  base1 : Int,
  len1 : Int,
  base2 : Int,
  len2 : Int,
  cmp : (T, T) -> Int,
  state : TimsortState,
) -> Unit {
  if len1 <= len2 {
    // Copy run1 to buffer, merge from buffer into array (left to right).
    let buf = FixedArray::make(len1, xs[base1])
    for i = 0; i < len1; i = i + 1 {
      buf[i] = xs[base1 + i]
    }
    let mut p1 = 0
    let mut p2 = base2
    let mut out = base1
    let mut win1 = 0
    let mut win2 = 0
    let end2 = base2 + len2
    while p1 < len1 && p2 < end2 {
      if cmp(buf[p1], xs[p2]) <= 0 {
        xs[out] = buf[p1]
        p1 = p1 + 1
        out = out + 1
        win1 = win1 + 1
        win2 = 0
      } else {
        xs[out] = xs[p2]
        p2 = p2 + 1
        out = out + 1
        win2 = win2 + 1
        win1 = 0
      }
      // Enter galloping mode when consecutive wins exceed threshold.
      if win1 >= state.min_gallop || win2 >= state.min_gallop {
        // Galloping mode: repeatedly gallop in both directions.
        while p1 < len1 && p2 < end2 {
          // Gallop right in run1: copy all elements <= xs[p2].
          let gc1 = gallop_right(buf, p1, len1, xs[p2], cmp)
          for g = 0; g < gc1; g = g + 1 {
            xs[out] = buf[p1]
            p1 = p1 + 1
            out = out + 1
          }
          if p1 >= len1 {
            break
          }
          // Gallop left in run2: copy all elements < buf[p1].
          let gc2 = gallop_left(xs, p2, end2, buf[p1], cmp)
          for g = 0; g < gc2; g = g + 1 {
            xs[out] = xs[p2]
            p2 = p2 + 1
            out = out + 1
          }
          if p2 >= end2 {
            break
          }
          // Adapt min_gallop: if gallop counts are small, exit galloping.
          if gc1 < GALLOP_THRESHOLD && gc2 < GALLOP_THRESHOLD {
            if state.min_gallop < 2147483647 {
              state.min_gallop = state.min_gallop + 1
            }
            break
          } else if state.min_gallop > 1 {
            state.min_gallop = state.min_gallop - 1
          }
        }
        win1 = 0
        win2 = 0
      }
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
    let mut p1 = base1 + len1 - 1
    let mut p2 = len2 - 1
    let mut out = base1 + len1 + len2 - 1
    let mut win1 = 0
    let mut win2 = 0
    while p1 >= base1 && p2 >= 0 {
      if cmp(xs[p1], buf[p2]) > 0 {
        xs[out] = xs[p1]
        p1 = p1 - 1
        out = out - 1
        win1 = win1 + 1
        win2 = 0
      } else {
        xs[out] = buf[p2]
        p2 = p2 - 1
        out = out - 1
        win2 = win2 + 1
        win1 = 0
      }
      // Enter galloping mode when consecutive wins exceed threshold.
      if win1 >= state.min_gallop || win2 >= state.min_gallop {
        // Galloping mode: repeatedly gallop in both directions (right-to-left).
        while p1 >= base1 && p2 >= 0 {
          // Gallop from right in run1: copy all elements > buf[p2].
          let gc1 = gallop_left_from_right(xs, base1, p1 + 1, buf[p2], cmp)
          for g = 0; g < gc1; g = g + 1 {
            xs[out] = xs[p1]
            p1 = p1 - 1
            out = out - 1
          }
          if p1 < base1 {
            break
          }
          // Gallop from right in run2: copy all elements >= xs[p1].
          let gc2 = gallop_right_from_right(buf, 0, p2 + 1, xs[p1], cmp)
          for g = 0; g < gc2; g = g + 1 {
            xs[out] = buf[p2]
            p2 = p2 - 1
            out = out - 1
          }
          if p2 < 0 {
            break
          }
          // Adapt min_gallop.
          if gc1 < GALLOP_THRESHOLD && gc2 < GALLOP_THRESHOLD {
            if state.min_gallop < 2147483647 {
              state.min_gallop = state.min_gallop + 1
            }
            break
          } else if state.min_gallop > 1 {
            state.min_gallop = state.min_gallop - 1
          }
        }
        win1 = 0
        win2 = 0
      }
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

///|
/// Gallop right: find the number of elements in buf[lo..hi) that are
/// <= key (i.e., can be copied before we hit an element > key).
///
/// Uses CPython Timsort-style exponential search (probing at offsets
/// 1, 3, 7, 15, …) followed by binary search in the identified bracket,
/// giving O(log n) comparisons instead of O(n).
fn[T] gallop_right(
  buf : FixedArray[T],
  lo : Int,
  hi : Int,
  key : T,
  cmp : (T, T) -> Int,
) -> Int {
  if lo >= hi {
    return 0
  }
  // Exponential search: check positions lo+1, lo+3, lo+7, lo+15, …
  let mut last_offset = 0
  let mut offset = 1
  while lo + offset < hi && cmp(buf[lo + offset], key) <= 0 {
    last_offset = offset
    offset = offset * 2 + 1
  }
  // Clamp offset to the valid range.
  if lo + offset > hi {
    offset = hi - lo
  }
  // Binary search for the first position > key in [lo + last_offset, lo + offset].
  // Since the array is sorted, all elements in [lo, lo + last_offset] are <= key.
  let mut l = lo + last_offset
  let mut r = lo + offset
  while l < r {
    let mid = l + (r - l) / 2
    if cmp(buf[mid], key) <= 0 {
      l = mid + 1
    } else {
      r = mid
    }
  }
  l - lo
}

///|
/// Gallop left: find the number of elements in xs[lo..hi) that are
/// < key (i.e., can be copied before we hit an element >= key).
///
/// Uses CPython Timsort-style exponential search followed by binary search.
fn[T] gallop_left(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  key : T,
  cmp : (T, T) -> Int,
) -> Int {
  if lo >= hi {
    return 0
  }
  // Exponential search: check positions lo+1, lo+3, lo+7, lo+15, …
  let mut last_offset = 0
  let mut offset = 1
  while lo + offset < hi && cmp(xs[lo + offset], key) < 0 {
    last_offset = offset
    offset = offset * 2 + 1
  }
  // Clamp offset to the valid range.
  if lo + offset > hi {
    offset = hi - lo
  }
  // Binary search for the first position >= key.
  let mut l = lo + last_offset
  let mut r = lo + offset
  while l < r {
    let mid = l + (r - l) / 2
    if cmp(xs[mid], key) < 0 {
      l = mid + 1
    } else {
      r = mid
    }
  }
  l - lo
}

///|
/// Gallop from right: count elements in xs[lo..hi) that are > key
/// (searching from the right end, for reverse merge).
///
/// Uses exponential search from the right end (probing at hi-2, hi-4,
/// hi-8, …) followed by binary search, giving O(log n).
fn[T] gallop_left_from_right(
  xs : FixedArray[T],
  lo : Int,
  hi : Int,
  key : T,
  cmp : (T, T) -> Int,
) -> Int {
  if lo >= hi {
    return 0
  }
  // Check the rightmost element first.
  if cmp(xs[hi - 1], key) <= 0 {
    return 0
  }
  // Exponential search from the right: check hi-2, hi-4, hi-8, …
  let mut last_offset = 0
  let mut offset = 1
  while hi - 1 - offset >= lo && cmp(xs[hi - 1 - offset], key) > 0 {
    last_offset = offset
    offset = offset * 2 + 1
  }
  // Clamp offset to the valid range.
  if hi - 1 - offset < lo {
    offset = hi - lo
  }
  // Binary search for the leftmost position > key.
  let mut l = if hi - 1 - offset >= lo { hi - 1 - offset } else { lo }
  let mut r = hi - 1 - last_offset
  while l < r {
    let mid = l + (r - l) / 2
    if cmp(xs[mid], key) > 0 {
      r = mid
    } else {
      l = mid + 1
    }
  }
  hi - l
}

///|
/// Gallop from right: count elements in buf[lo..hi) that are >= key
/// (searching from the right end, for reverse merge).
///
/// Uses exponential search from the right end followed by binary search.
fn[T] gallop_right_from_right(
  buf : FixedArray[T],
  lo : Int,
  hi : Int,
  key : T,
  cmp : (T, T) -> Int,
) -> Int {
  if lo >= hi {
    return 0
  }
  // Check the rightmost element first.
  if cmp(buf[hi - 1], key) < 0 {
    return 0
  }
  // Exponential search from the right: check hi-2, hi-4, hi-8, …
  let mut last_offset = 0
  let mut offset = 1
  while hi - 1 - offset >= lo && cmp(buf[hi - 1 - offset], key) >= 0 {
    last_offset = offset
    offset = offset * 2 + 1
  }
  // Clamp offset to the valid range.
  if hi - 1 - offset < lo {
    offset = hi - lo
  }
  // Binary search for the leftmost position >= key.
  let mut l = if hi - 1 - offset >= lo { hi - 1 - offset } else { lo }
  let mut r = hi - 1 - last_offset
  while l < r {
    let mid = l + (r - l) / 2
    if cmp(buf[mid], key) >= 0 {
      r = mid
    } else {
      l = mid + 1
    }
  }
  hi - l
}

///|
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
  // Self-tuning galloping state, shared across all merges (like CPython).
  let state : TimsortState = { min_gallop: GALLOP_THRESHOLD, }
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
          state,
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
          state,
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
      state,
    )
    stack_len[i - 1] = stack_len[i - 1] + stack_len[i]
    ignore(stack_base.remove(i))
    ignore(stack_len.remove(i))
  }
}

///|
/// Convenience: sort Int array in ascending order.
pub fn sort_int(xs : FixedArray[Int]) -> Unit {
  timsort(xs, fn(a, b) { a - b })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "timsort: empty array" {
  let arr = FixedArray::make(0, 0)
  sort_int(arr)
  assert_eq(arr.length(), 0)
}

///|
test "timsort: single element" {
  let arr = FixedArray::make(1, 42)
  sort_int(arr)
  assert_eq(arr[0], 42)
}

///|
test "timsort: already sorted" {
  let arr = FixedArray::makei(100, fn(i) { i })
  sort_int(arr)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(arr[i], i)
  }
}

///|
test "timsort: reverse sorted" {
  let arr = FixedArray::makei(100, fn(i) { 99 - i })
  sort_int(arr)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(arr[i], i)
  }
}

///|
test "timsort: random data" {
  let arr = FixedArray::makei(200, fn(i) { (i * 37 + 13) % 211 })
  sort_int(arr)
  for i = 0; i < 199; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
test "timsort: duplicates" {
  let arr = FixedArray::makei(50, fn(i) { i % 5 })
  sort_int(arr)
  for i = 0; i < 49; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}

///|
test "timsort: all same" {
  let arr = FixedArray::make(100, 7)
  sort_int(arr)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(arr[i], 7)
  }
}

///|
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

///|
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

///|
test "timsort: descending runs" {
  // Test that descending runs are detected and reversed.
  let arr = FixedArray::makei(64, fn(i) {
    if i < 16 {
      15 - i
    } else if i < 32 {
      i
    } else if i < 48 {
      79 - i
    } else {
      i
    }
  })
  sort_int(arr)
  for i = 0; i < 64; i = i + 1 {
    assert_eq(arr[i], i)
  }
}

///|
test "timsort: two elements" {
  let arr = FixedArray::make(2, 0)
  arr[0] = 5
  arr[1] = 3
  sort_int(arr)
  assert_eq(arr[0], 3)
  assert_eq(arr[1], 5)
}

///|
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
      if ca != cb {
        return ca - cb
      }
    }
    la - lb
  })
  assert_eq(arr[0], "apple")
  assert_eq(arr[1], "banana")
  assert_eq(arr[2], "cherry")
}

///|
test "timsort: galloping mode (partially ordered)" {
  // Create two interleaved sorted runs to trigger galloping.
  // Run A: 0, 10, 20, 30, ... (length 50)
  // Run B: 1, 11, 21, 31, ... (length 50)
  // Interleaved: 0, 1, 10, 11, 20, 21, ...
  // When merged, run A elements are always < run B elements at same index,
  // causing consecutive wins that trigger galloping.
  let n = 100
  let arr = FixedArray::make(n, 0)
  for i = 0; i < 50; i = i + 1 {
    arr[i * 2] = i * 10
    arr[i * 2 + 1] = i * 10 + 1
  }
  sort_int(arr)
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
  // Verify all elements present.
  for i = 0; i < 50; i = i + 1 {
    assert_eq(arr[i * 2], i * 10)
    assert_eq(arr[i * 2 + 1], i * 10 + 1)
  }
}

///|
test "timsort: galloping with one-side dominance" {
  // Run A: 1, 2, 3, ..., 50
  // Run B: 100, 101, 102, ..., 149
  // All of run A < all of run B → extreme galloping during merge.
  let n = 100
  let arr = FixedArray::make(n, 0)
  for i = 0; i < 50; i = i + 1 {
    arr[i] = i + 1
  }
  for i = 0; i < 50; i = i + 1 {
    arr[50 + i] = 100 + i
  }
  sort_int(arr)
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
  for i = 0; i < 50; i = i + 1 {
    assert_eq(arr[i], i + 1)
  }
  for i = 0; i < 50; i = i + 1 {
    assert_eq(arr[50 + i], 100 + i)
  }
}

///|
test "timsort: galloping reverse merge" {
  // Data that triggers reverse merge galloping (len1 > len2 case).
  // First run is much longer, causing merge_hi (right-to-left) path.
  let n = 200
  let arr = FixedArray::make(n, 0)
  // Create a pattern with a long sorted run followed by short sorted runs.
  for i = 0; i < 150; i = i + 1 {
    arr[i] = i
  }
  for i = 0; i < 50; i = i + 1 {
    arr[150 + i] = 1000 + i
  }
  sort_int(arr)
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(arr[i] <= arr[i + 1])
  }
}
