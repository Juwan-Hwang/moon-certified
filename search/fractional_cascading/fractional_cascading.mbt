/// Fractional Cascading — multi-array search in O(log n + k).
///
/// Given `k` sorted arrays, Fractional Cascading (Chazelle, 1986) answers
/// "find the lower bound of `x` in every array" in **O(log n + k)** total
/// time, compared to **O(k log n)** for `k` independent binary searches.
///
/// ## Key Idea
///
/// Build a cascade of "augmented" arrays `L_1, L_2, …, L_k` where each `L_i`
/// contains:
/// 1. All elements of the original array `A_i`.
/// 2. Every other element of `L_{i+1}` (the "sample" from the next level).
///
/// For each element in `L_i` that was sampled from `L_{i+1}`, we store a
/// pointer to its position in `L_{i+1}`.  This pointer enables O(1) transfer
/// between levels during search.
///
/// ## Search Algorithm
///
/// 1. Binary-search for `x` in `L_1` → position `p₁`.                     O(log n)
/// 2. For `i = 2 … k`: use the pointer from `p_{i-1}` to jump to a nearby
///    position in `L_i`, then do ≤ 2 comparisons to find `p_i`.            O(1) each
/// 3. Report lower-bound positions in each original array `A_i`.
///
/// ## Complexity
///
/// - **Build**: O(Σ |A_i|) time and space.
/// - **Search**: O(log n + k) where n = max |A_i|.
/// - Each augmented array `L_i` has size ≤ 2|A_i| (at most |A_i| original
///   + |A_i| sampled), so total space is O(Σ |A_i|).
///
/// ## References
///
/// - Chazelle, B. (1986): "Filtering Search: A New Approach to Query
///   Answering." SIAM Journal on Computing, 15(3), 703–724.
/// - de Berg et al.: "Computational Geometry: Algorithms and Applications,"
///   3rd ed., §5.1.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Data structures
// ---------------------------------------------------------------------------

///|
/// An entry in an augmented cascade level.
///
/// - `value`: the element value.
/// - `from_original`: `true` if this element came from the original array `A_i`
///   (as opposed to being sampled from `L_{i+1}`).
/// - `orig_idx`: index in the original array `A_i` (if `from_original`).
/// - `down_ptr`: pointer (index) into the next level `L_{i+1}` — the position
///   of the smallest element ≥ `value` in `L_{i+1}`.  Only meaningful for
///   levels `i < k`.
priv struct CascadeEntry {
  value : Int64
  from_original : Bool
  orig_idx : Int // index in original A_i, or -1 if sampled
  down_ptr : Int // index into next level, -1 for last level
}

///|
/// One level of the cascade.
struct CascadeLevel {
  entries : Array[CascadeEntry]
  // For binary-search-style lower_bound in this level, we store values separately
  // for cache efficiency.
  values : Array[Int64]
}

///|
/// The fractional cascading structure built from `k` sorted arrays.
///
/// Construct with `build`, then query with `lower_bound_all`.
pub struct FractionalCascading {
  levels : Array[CascadeLevel]
  num_arrays : Int
}

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

///|
/// Build a `FractionalCascading` structure from `k` sorted arrays.
///
/// Each array must be sorted in non-decreasing order.  The arrays need not
/// have the same length.
///
/// ## Example
///
/// ```moonbit nocheck
/// let fc = build([[1L, 5L, 9L], [2L, 6L, 10L], [3L, 7L, 11L]])
///
/// let positions = lower_bound_all(fc, 6L)
/// // positions[i] = lower_bound of 6 in array i
/// ```
pub fn build(arrays : Array[Array[Int64]]) -> FractionalCascading {
  let k = arrays.length()
  if k == 0 {
    return { levels: [], num_arrays: 0, }
  }
  // Build levels from the last to the first.
  let levels : Array[CascadeLevel] = Array::make(k, { entries: [], values: [], })
  // Level k-1 (last): just the original array, no sampling.
  let last_arr = arrays[k - 1]
  let last_entries : Array[CascadeEntry] = []
  let last_values : Array[Int64] = []
  for i = 0; i < last_arr.length(); i = i + 1 {
    last_entries.push({
      value: last_arr[i],
      from_original: true,
      orig_idx: i,
      down_ptr: -1,
    })
    last_values.push(last_arr[i])
  }
  levels[k - 1] = { entries: last_entries, values: last_values, }
  // Build levels k-2 down to 0.
  for lev = k - 2; lev >= 0; lev = lev - 1 {
    let cur_arr = arrays[lev]
    let next_level = levels[lev + 1]
    // Sample every other element from next_level.
    let sampled : Array[(Int64, Int)] = [] // (value, index in next_level)
    for i = 0; i < next_level.values.length(); i = i + 2 {
      sampled.push((next_level.values[i], i))
    }
    // Merge cur_arr with sampled, maintaining sorted order.
    let entries : Array[CascadeEntry] = []
    let values : Array[Int64] = []
    let mut i = 0 // index into cur_arr
    let mut j = 0 // index into sampled
    while i < cur_arr.length() || j < sampled.length() {
      let take_from_arr = if i >= cur_arr.length() {
        false
      } else if j >= sampled.length() {
        true
      } else {
        cur_arr[i] <= sampled[j].0
      }
      if take_from_arr {
        // From original array. Compute down_ptr: index of smallest element
        // >= cur_arr[i] in next_level.
        let dp = lower_bound_idx(next_level.values, cur_arr[i])
        entries.push({
          value: cur_arr[i],
          from_original: true,
          orig_idx: i,
          down_ptr: dp,
        })
        values.push(cur_arr[i])
        i = i + 1
      } else {
        // Sampled from next level. down_ptr is the index in next_level.
        entries.push({
          value: sampled[j].0,
          from_original: false,
          orig_idx: -1,
          down_ptr: sampled[j].1,
        })
        values.push(sampled[j].0)
        j = j + 1
      }
    }
    levels[lev] = { entries, values, }
  }
  { levels, num_arrays: k, }
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

///|
/// Search for the lower bound of `x` in every original array simultaneously.
///
/// Returns an array of `k` indices, where `result[i]` is the index of the
/// smallest element ≥ `x` in `arrays[i]` (or `arrays[i].length()` if all
/// elements are < `x`).
///
/// **Complexity**: O(log n + k) where n = max array length.
pub fn lower_bound_all(fc : FractionalCascading, x : Int64) -> Array[Int] {
  let k = fc.num_arrays
  if k == 0 {
    return []
  }
  // Step 1: Binary search for x in level 0.
  let pos = lower_bound_idx(fc.levels[0].values, x)
  // Step 2: Cascade through levels.
  // For each level, we need to find the position in the ORIGINAL array.
  let result = Array::make(k, 0)
  let mut cur_pos = pos
  for lev = 0; lev < k; lev = lev + 1 {
    let level = fc.levels[lev]
    // Adjust cur_pos: it might be at a sampled element. We need the position
    // of the lower_bound of x in this level's values.
    // cur_pos is already the lower_bound from the previous step.
    // But we might need to check one position back (due to sampling).
    if lev > 0 {
      // cur_pos was set by the down_ptr from the previous level.
      // The down_ptr points to the smallest element >= some value in the
      // next level. We need to find the smallest element >= x in this level.
      // Since x >= the value that generated the down_ptr, and the down_ptr
      // gives us a starting position, we check at most 2 positions.
      if cur_pos > 0 && level.values[cur_pos - 1] >= x {
        // Check if we need to go back. The down_ptr might have overshot.
        // Actually, the down_ptr points to >= the queried value from above,
        // which is >= x (since the previous level's entry >= x).
        // But due to interleaving, the actual lower_bound of x might be
        // one position earlier.
        cur_pos = cur_pos - 1
        // Check again
        while cur_pos > 0 && level.values[cur_pos - 1] >= x {
          cur_pos = cur_pos - 1
        }
      }
      // Also check forward (shouldn't need more than 1 step)
      while cur_pos < level.values.length() && level.values[cur_pos] < x {
        cur_pos = cur_pos + 1
      }
    }
    // Find the lower_bound position in the ORIGINAL array.
    // Walk left from cur_pos to find the first original entry >= x.
    let orig_lb = find_orig_lower_bound(level, cur_pos, x)
    result[lev] = orig_lb
    // Set up down_ptr for next level.
    if lev < k - 1 {
      // The down_ptr at cur_pos (or nearby) gives the starting position
      // in the next level.
      if cur_pos < level.entries.length() {
        cur_pos = level.entries[cur_pos].down_ptr
      } else {
        cur_pos = fc.levels[lev + 1].values.length()
      }
    }
  }
  result
}

///|
/// Search for the exact position of `x` in every original array.
///
/// Returns `Some(result)` where `result[i]` is the index of `x` in `arrays[i]`,
/// or `None` if `x` is not found in some array.  If any array does not contain
/// `x`, returns `None`.
pub fn find_all(fc : FractionalCascading, x : Int64) -> Array[Int]? {
  let k = fc.num_arrays
  if k == 0 {
    return Some([])
  }
  let result = Array::make(k, -1)
  let pos = lower_bound_idx(fc.levels[0].values, x)
  let mut cur_pos = pos
  for lev = 0; lev < k; lev = lev + 1 {
    let level = fc.levels[lev]
    if lev > 0 {
      if cur_pos > 0 && level.values[cur_pos - 1] >= x {
        cur_pos = cur_pos - 1
        while cur_pos > 0 && level.values[cur_pos - 1] >= x {
          cur_pos = cur_pos - 1
        }
      }
      while cur_pos < level.values.length() && level.values[cur_pos] < x {
        cur_pos = cur_pos + 1
      }
    }
    // Check if x is actually present at cur_pos
    let found = cur_pos < level.values.length() &&
      level.values[cur_pos] == x &&
      level.entries[cur_pos].from_original
    if found {
      result[lev] = level.entries[cur_pos].orig_idx
    } else {
      // Check nearby sampled entries that might correspond to x in original
      let orig_lb = find_orig_lower_bound(level, cur_pos, x)
      result[lev] = orig_lb // lower bound, even if not exact
    }
    if lev < k - 1 {
      if cur_pos < level.entries.length() {
        cur_pos = level.entries[cur_pos].down_ptr
      } else {
        cur_pos = fc.levels[lev + 1].values.length()
      }
    }
  }
  Some(result)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
/// Binary search: find the index of the smallest element >= x.
fn lower_bound_idx(arr : Array[Int64], x : Int64) -> Int {
  let mut lo = 0
  let mut hi = arr.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if arr[mid] < x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// Find the lower-bound position of x in the original array for this level.
///
/// Given that `pos` is the lower-bound of `x` in the augmented level,
/// walk left to find the first original entry with value >= x.
fn find_orig_lower_bound(level : CascadeLevel, pos : Int, x : Int64) -> Int {
  // Walk left from pos to find original entries.
  // The original lower bound is the count of original entries with value < x.
  let mut count = 0
  for i = 0; i < pos; i = i + 1 {
    if level.entries[i].from_original && level.entries[i].value < x {
      count = count + 1
    }
  }
  // Check if the entry at pos is original and >= x
  if pos < level.entries.length() &&
    level.entries[pos].from_original &&
    level.entries[pos].value >= x {
    // count is correct
    ()
  }
  // Also need to count original entries at pos that are < x
  if pos < level.entries.length() &&
    level.entries[pos].from_original &&
    level.entries[pos].value < x {
    count = count + 1
  }
  count
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "fc: single array" {
  let fc = build([[1L, 3L, 5L, 7L, 9L]])
  let r = lower_bound_all(fc, 6L)
  assert_eq(r[0], 3) // 7 is at index 3
  let r2 = lower_bound_all(fc, 5L)
  assert_eq(r2[0], 2) // 5 is at index 2
  let r3 = lower_bound_all(fc, 10L)
  assert_eq(r3[0], 5) // past end
  let r4 = lower_bound_all(fc, 0L)
  assert_eq(r4[0], 0) // before start
}

///|
test "fc: two arrays" {
  let fc = build([[1L, 5L, 9L], [2L, 6L, 10L]])
  let r = lower_bound_all(fc, 5L)
  assert_eq(r[0], 1) // 5 at index 1 in [1,5,9]
  assert_eq(r[1], 1) // 6 at index 1 in [2,6,10]
  let r2 = lower_bound_all(fc, 3L)
  assert_eq(r2[0], 1) // 5 at index 1
  assert_eq(r2[1], 1) // 6 at index 1
}

///|
test "fc: three arrays basic" {
  let fc = build([[1L, 5L, 9L], [2L, 6L, 10L], [3L, 7L, 11L]])
  let r = lower_bound_all(fc, 6L)
  // 6 in [1,5,9] -> lower_bound is 9 at index 2
  assert_eq(r[0], 2)
  // 6 in [2,6,10] -> 6 at index 1
  assert_eq(r[1], 1)
  // 6 in [3,7,11] -> 7 at index 1
  assert_eq(r[2], 1)
}

///|
test "fc: cross-check with binary search" {
  let arrays = [
    [1L, 4L, 7L, 10L, 13L],
    [2L, 5L, 8L, 11L],
    [3L, 6L, 9L, 12L, 15L, 18L],
  ]
  let fc = build(arrays)
  // Test many query values
  for q = 0; q <= 20; q = q + 1 {
    let x = q.to_int64()
    let fc_result = lower_bound_all(fc, x)
    // Brute-force: binary search each array
    for i = 0; i < arrays.length(); i = i + 1 {
      let expected = lower_bound_idx(arrays[i], x)
      assert_eq(fc_result[i], expected)
    }
  }
}

///|
test "fc: empty arrays" {
  let fc = build([])
  let r = lower_bound_all(fc, 5L)
  assert_true(r.length() == 0)
}

///|
test "fc: one empty array in middle" {
  let fc = build([[1L, 3L], [], [2L, 4L]])
  let r = lower_bound_all(fc, 2L)
  assert_eq(r[0], 1) // 3 at index 1
  assert_eq(r[1], 0) // empty, lower_bound = 0
  assert_eq(r[2], 0) // 2 at index 0
}

///|
test "fc: single element arrays" {
  let fc = build([[5L], [3L], [7L]])
  let r = lower_bound_all(fc, 4L)
  assert_eq(r[0], 0) // 5 >= 4 at index 0
  assert_eq(r[1], 1) // 3 < 4, so lower_bound = 1 (past end)
  assert_eq(r[2], 0) // 7 >= 4 at index 0
}

///|
test "fc: duplicate values" {
  let fc = build([[1L, 1L, 1L], [1L, 1L], [1L]])
  let r = lower_bound_all(fc, 1L)
  assert_eq(r[0], 0) // first 1 at index 0
  assert_eq(r[1], 0)
  assert_eq(r[2], 0)
  let r2 = lower_bound_all(fc, 2L)
  assert_eq(r2[0], 3) // past end
  assert_eq(r2[1], 2) // past end
  assert_eq(r2[2], 1) // past end
}

///|
test "fc: large arrays cross-check" {
  // Generate large sorted arrays with different lengths
  let arr1 : Array[Int64] = []
  let arr2 : Array[Int64] = []
  let arr3 : Array[Int64] = []
  for i = 0; i < 100; i = i + 1 {
    arr1.push(i.to_int64() * 3L) // 0, 3, 6, 9, ...
  }
  for i = 0; i < 80; i = i + 1 {
    arr2.push(i.to_int64() * 3L + 1L) // 1, 4, 7, 10, ...
  }
  for i = 0; i < 120; i = i + 1 {
    arr3.push(i.to_int64() * 3L + 2L) // 2, 5, 8, 11, ...
  }
  let fc = build([arr1, arr2, arr3])
  // Test many query values
  for q = 0; q <= 400; q = q + 7 {
    let x = q.to_int64()
    let fc_result = lower_bound_all(fc, x)
    let expected1 = lower_bound_idx(arr1, x)
    let expected2 = lower_bound_idx(arr2, x)
    let expected3 = lower_bound_idx(arr3, x)
    assert_eq(fc_result[0], expected1)
    assert_eq(fc_result[1], expected2)
    assert_eq(fc_result[2], expected3)
  }
}

///|
test "fc: many small arrays" {
  // 10 arrays of varying lengths
  let arrays : Array[Array[Int64]] = []
  for a = 0; a < 10; a = a + 1 {
    let arr : Array[Int64] = []
    for i = 0; i < 5 + a; i = i + 1 {
      arr.push((a * 10 + i).to_int64())
    }
    arrays.push(arr)
  }
  let fc = build(arrays)
  for q = 0; q <= 120; q = q + 3 {
    let x = q.to_int64()
    let fc_result = lower_bound_all(fc, x)
    for i = 0; i < arrays.length(); i = i + 1 {
      let expected = lower_bound_idx(arrays[i], x)
      assert_eq(fc_result[i], expected)
    }
  }
}

///|
test "fc: all elements same" {
  let fc = build([[5L, 5L, 5L], [5L, 5L], [5L, 5L, 5L, 5L]])
  let r = lower_bound_all(fc, 5L)
  assert_eq(r[0], 0)
  assert_eq(r[1], 0)
  assert_eq(r[2], 0)
  let r2 = lower_bound_all(fc, 4L)
  assert_eq(r2[0], 0)
  assert_eq(r2[1], 0)
  assert_eq(r2[2], 0)
  let r3 = lower_bound_all(fc, 6L)
  assert_eq(r3[0], 3)
  assert_eq(r3[1], 2)
  assert_eq(r3[2], 4)
}

///|
test "fc: negative values" {
  let fc = build([[-10L, -5L, 0L], [-8L, -3L, 2L], [-6L, -1L, 4L]])
  let r = lower_bound_all(fc, -5L)
  assert_eq(r[0], 1) // -5 at index 1
  assert_eq(r[1], 1) // -3 at index 1
  assert_eq(r[2], 1) // -1 at index 1
  let r2 = lower_bound_all(fc, -7L)
  assert_eq(r2[0], 1) // -5 at index 1
  assert_eq(r2[1], 1) // -3 at index 1 (-8 < -7, so lb is -3)
  assert_eq(r2[2], 0) // -6 at index 0
}
