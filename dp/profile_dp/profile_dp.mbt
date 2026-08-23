/// Profile Dynamic Programming — Bitmask Row-by-Row Grid DP.
///
/// Profile DP (also called "state compression DP" or "contour DP") processes
/// a grid row by row, maintaining a bitmask that encodes the state of the
/// current row's boundary. Unlike Plug DP (which tracks connectivity between
/// cells using bracket encoding), Profile DP uses a simpler bitmask where each
/// bit indicates whether a cell is "occupied" or "blocked."
///
/// ## When to use
///
/// Profile DP is the standard technique for grid problems with small width
/// (typically W ≤ 20) where the state of one row depends only on the previous
/// row:
///
/// - **Domino tiling**: Count the number of ways to tile an H×W grid with
///   1×2 dominoes. Complexity: O(H · 2^W · 2^W) with precomputed transitions,
///   or O(H · 3^W) with the "fill" approach.
/// - **Maximum independent set on grid**: Find the largest set of cells such
///   that no two are adjacent. Complexity: O(H · 3^W).
/// - **Maximum weighted independent set**: Same but with cell weights.
/// - **Minimum dominating set on grid**: Find the smallest set of cells such
///   that every cell is in the set or adjacent to a cell in the set.
///
/// ## State representation
///
/// Each row's state is a bitmask of W bits. Bit i = 1 means cell i in that
/// row is "occupied" (e.g., covered by a domino, selected for independent set).
/// Bit i = 0 means cell i is "free."
///
/// For domino tiling, two adjacent rows' bitmasks must be **compatible**:
/// the free cells in row r (where the bitmask is 0) must be exactly covered
/// by horizontal dominoes within row r or vertical dominoes from row r+1.
///
/// ## Transition precomputation
///
/// The key optimization is to precompute all valid (prev_mask, cur_mask) pairs
/// for each row width W. This avoids recomputing compatibility checks inside
/// the main DP loop.
///
/// ## Complexity
///
/// - Domino tiling: O(H · T(W)) where T(W) is the number of valid transitions,
///   which is O(3^W) in the worst case.
/// - Independent set: O(H · 3^W) since we enumerate all supersets/subsets.
/// - Space: O(2^W) for the DP table (two rows).
///
/// ## References
///
/// - Halim, S. & Halim, F. "Competitive Programming," 4th ed., 2020, §8.4.
/// - Knuth, D. E. "The Art of Computer Programming," Vol. 4, Fascicle 1b,
///   "Binary Decision Diagrams."
/// - Kasteleyn, P. W. "The statistics of dimers on a lattice," Physica, 1961.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Domino Tiling
// ---------------------------------------------------------------------------

///|
/// Count the number of ways to tile an H×W grid with 1×2 dominoes.
///
/// Uses profile DP with row-by-row bitmask transitions. For each row, the
/// bitmask indicates which cells are already covered by vertical dominoes
/// from the previous row. The remaining free cells must be tiled by
/// horizontal dominoes within the current row.
///
/// ## Parameters
///
/// - `h`: Grid height (number of rows).
/// - `w`: Grid width (number of columns).
///
/// ## Returns
///
/// The number of distinct domino tilings as an `Int64`. Returns 0 if the
/// total number of cells is odd (impossible to tile).
///
/// ## Complexity
///
/// O(h · 3^w) time, O(2^w) space.
///
/// ## Known formulas
///
/// - 1×n: 1 if n is even, 0 if n is odd.
/// - 2×n: Fibonacci(n+1).
/// - 4×4: 36.
/// - 8×8: 12988816.
pub fn count_domino_tilings(h : Int, w : Int) -> Int64 {
  if h <= 0 || w <= 0 {
    return 0L
  }
  // Odd number of cells → impossible.
  if h * w % 2 == 1 {
    return 0L
  }
  // Optimize: iterate over the smaller dimension as the "width" for the bitmask.
  let (rows, cols) = if h <= w { (h, w) } else { (w, h) }
  let n_states = 1 << cols
  // dp[mask] = number of ways to tile rows 0..r such that the mask indicates
  // which cells in row r are already occupied (by vertical dominoes from row r-1).
  let dp = Array::make(n_states, 0L)
  let next_dp = Array::make(n_states, 0L)
  // Initial state: row 0 has no cells pre-occupied.
  dp[0] = 1L
  for row = 0; row < rows; row = row + 1 {
    // Clear next_dp.
    for i = 0; i < n_states; i = i + 1 {
      next_dp[i] = 0L
    }
    // For each possible current mask (cells occupied from above).
    for mask = 0; mask < n_states; mask = mask + 1 {
      if dp[mask] == 0L {
        continue
      }
      // Generate all valid "fill" patterns for this row.
      // A fill pattern determines which free cells are covered by horizontal
      // dominoes and which become the start of vertical dominoes.
      fill_row(mask, 0, cols, 0, dp[mask], next_dp)
    }
    // Swap dp and next_dp.
    for i = 0; i < n_states; i = i + 1 {
      dp[i] = next_dp[i]
    }
  }
  // After processing all rows, the answer is dp[0] (no cells hanging over).
  dp[0]
}

///|
/// Recursively fill a row given the current mask of pre-occupied cells.
///
/// - `mask`: Bitmask of cells already occupied (from vertical dominoes above).
/// - `col`: Current column being processed.
/// - `w`: Grid width.
/// - `next_mask`: Accumulating bitmask for cells that will be occupied in the
///   next row (vertical dominoes extending downward).
/// - `count`: Number of ways to reach this state.
/// - `next_dp`: The DP table for the next row.
fn fill_row(
  mask : Int,
  col : Int,
  w : Int,
  next_mask : Int,
  count : Int64,
  next_dp : Array[Int64],
) -> Unit {
  if col == w {
    // All cells processed. Add count to next_dp[next_mask].
    next_dp[next_mask] = next_dp[next_mask] + count
    return
  }
  if (mask & (1 << col)) != 0 {
    // This cell is already occupied (vertical domino from above).
    fill_row(mask, col + 1, w, next_mask, count, next_dp)
  } else {
    // Try placing a horizontal domino (covers col and col+1).
    if col + 1 < w && (mask & (1 << (col + 1))) == 0 {
      fill_row(
        mask | (1 << col) | (1 << (col + 1)),
        col + 2,
        w,
        next_mask,
        count,
        next_dp,
      )
    }
    // Try placing a vertical domino (extends to next row).
    fill_row(
      mask | (1 << col),
      col + 1,
      w,
      next_mask | (1 << col),
      count,
      next_dp,
    )
  }
}

// ---------------------------------------------------------------------------
// Maximum Independent Set on Grid
// ---------------------------------------------------------------------------

///|
/// Find the maximum independent set on an H×W grid graph.
///
/// A grid graph has vertices at each cell, with edges between horizontally
/// and vertically adjacent cells. An independent set is a set of vertices
/// with no two adjacent. The maximum independent set is the largest such set.
///
/// ## Parameters
///
/// - `h`: Grid height.
/// - `w`: Grid width.
///
/// ## Returns
///
/// The size of the maximum independent set.
///
/// ## Complexity
///
/// O(h · 3^w) time, O(2^w) space.
///
/// ## Known formulas
///
/// - For any grid: ceil(h * w / 2) (checkerboard pattern is optimal).
pub fn max_independent_set(h : Int, w : Int) -> Int {
  if h <= 0 || w <= 0 {
    return 0
  }
  let cols = if h <= w { w } else { h }
  let rows = if h <= w { h } else { w }
  let n_states = 1 << cols
  // dp[mask] = max independent set size using rows 0..r-1, where mask is the
  // selection pattern of the previous row.
  let dp = Array::make(n_states, -1)
  let next_dp = Array::make(n_states, -1)
  // Base case: no previous row, all masks are valid with their popcount.
  dp[0] = 0
  for row = 0; row < rows; row = row + 1 {
    for i = 0; i < n_states; i = i + 1 {
      next_dp[i] = -1
    }
    for prev_mask = 0; prev_mask < n_states; prev_mask = prev_mask + 1 {
      if dp[prev_mask] < 0 {
        continue
      }
      // Enumerate all subsets of the "available" cells (those not adjacent
      // to selected cells in the previous row).
      // A cell in the current row can be selected if:
      // 1. It's not directly below a selected cell in the previous row.
      //    (i.e., bit i of prev_mask must be 0)
      // The "available" mask is ~prev_mask (restricted to w bits).
      let available = ((1 << cols) - 1) ^ prev_mask
      // Enumerate all subsets of 'available'.
      enumerate_independent_subsets(available, dp[prev_mask], next_dp)
    }
    for i = 0; i < n_states; i = i + 1 {
      dp[i] = next_dp[i]
    }
  }
  // Answer is max over all masks.
  let mut best = 0
  for mask = 0; mask < n_states; mask = mask + 1 {
    if dp[mask] > best {
      best = dp[mask]
    }
  }
  best
}

///|
/// Enumerate all valid independent subsets of `available` mask.
///
/// For each valid subset (no two adjacent bits set), update next_dp.
///
/// - `available`: Bitmask of cells that CAN be selected (not blocked by prev row).
/// - `cols`: Number of columns.
/// - `prev_mask`: Previous row's selection (for adjacency check within row).
/// - `prev_count`: DP value from the previous row.
/// - `next_dp`: The DP table to update.
fn enumerate_independent_subsets(
  available : Int,
  prev_count : Int,
  next_dp : Array[Int],
) -> Unit {
  // Enumerate all subsets of 'available' that have no two adjacent bits.
  // Standard subset enumeration: start from 'available' and go down to 0.
  let mut sub = available
  while true {
    // Check if 'sub' has no two adjacent bits set.
    if (sub & (sub << 1)) == 0 {
      // Valid independent set within the row.
      let pc = popcount(sub)
      let val = prev_count + pc
      if val > next_dp[sub] {
        next_dp[sub] = val
      }
    }
    if sub == 0 {
      break
    }
    sub = (sub - 1) & available
  }
}

///|
/// Count the number of set bits in an integer (population count / Hamming weight).
fn popcount(x : Int) -> Int {
  let mut n = x
  let mut count = 0
  while n != 0 {
    count = count + (n & 1)
    n = n >> 1
  }
  count
}

// ---------------------------------------------------------------------------
// Maximum Weighted Independent Set on Grid
// ---------------------------------------------------------------------------

///|
/// Find the maximum weight independent set on an H×W grid graph.
///
/// Each cell has a weight, and we seek the independent set (no two adjacent
/// cells) with maximum total weight.
///
/// ## Parameters
///
/// - `weights`: Row-major H×W array of cell weights (length h * w).
/// - `h`: Grid height.
/// - `w`: Grid width.
///
/// ## Returns
///
/// The maximum total weight, or `None` if inputs are invalid.
///
/// ## Complexity
///
/// O(h · 3^w) time, O(2^w) space.
pub fn max_weighted_independent_set(
  weights : Array[Double],
  h : Int,
  w : Int,
) -> Double? {
  if h <= 0 || w <= 0 || weights.length() != h * w {
    return None
  }
  let cols = if h <= w { w } else { h }
  let rows = if h <= w { h } else { w }
  let n_states = 1 << cols
  let dp = Array::make(n_states, -1.0e308)
  let next_dp = Array::make(n_states, -1.0e308)
  dp[0] = 0.0
  for row = 0; row < rows; row = row + 1 {
    for i = 0; i < n_states; i = i + 1 {
      next_dp[i] = -1.0e308
    }
    for prev_mask = 0; prev_mask < n_states; prev_mask = prev_mask + 1 {
      if dp[prev_mask] <= -1.0e300 {
        continue
      }
      let available = ((1 << cols) - 1) ^ prev_mask
      // Enumerate all valid (no adjacent) subsets of available.
      let mut sub = available
      while true {
        if (sub & (sub << 1)) == 0 {
          // Compute weight of this subset in the current row.
          let mut w_sum = 0.0
          for c = 0; c < cols; c = c + 1 {
            if (sub & (1 << c)) != 0 {
              // Get weight for (row, c). Note: if we swapped h/w, need to access correctly.
              let idx = if h <= w { row * w + c } else { c * h + row }
              w_sum = w_sum + weights[idx]
            }
          }
          let val = dp[prev_mask] + w_sum
          if val > next_dp[sub] {
            next_dp[sub] = val
          }
        }
        if sub == 0 {
          break
        }
        sub = (sub - 1) & available
      }
    }
    for i = 0; i < n_states; i = i + 1 {
      dp[i] = next_dp[i]
    }
  }
  let mut best = 0.0
  for mask = 0; mask < n_states; mask = mask + 1 {
    if dp[mask] > best {
      best = dp[mask]
    }
  }
  Some(best)
}

// ---------------------------------------------------------------------------
// Minimum Dominating Set on Grid
// ---------------------------------------------------------------------------

///|
/// Find the minimum dominating set on an H×W grid graph.
///
/// A dominating set is a set of vertices such that every vertex is either in
/// the set or adjacent to a vertex in the set. The minimum dominating set is
/// the smallest such set.
///
/// Uses profile DP with a two-bitmask state: (prev_sel, prev_need).
/// - `prev_sel`: which cells in the previous row were selected.
/// - `prev_need`: which cells in the previous row are still undominated
///   (must be dominated by selecting the cell below in the current row).
///
/// ## Parameters
///
/// - `h`: Grid height.
/// - `w`: Grid width.
///
/// ## Returns
///
/// The size of the minimum dominating set.
///
/// ## Complexity
///
/// O(h · 2^w · 2^w) time, O(2^(2w)) space.
pub fn min_dominating_set(h : Int, w : Int) -> Int {
  if h <= 0 || w <= 0 {
    return 0
  }
  let cols = w
  let rows = h
  let full_mask = (1 << cols) - 1
  let max_state = 1 << (2 * cols)
  // dp[state] = min dominating set size, where state = (prev_sel << cols) | prev_need.
  let dp = Array::make(max_state, -1)
  let next_dp = Array::make(max_state, -1)
  // Initial: no previous row, nothing selected, nothing needs domination.
  dp[0] = 0
  for row = 0; row < rows; row = row + 1 {
    for i = 0; i < max_state; i = i + 1 {
      next_dp[i] = -1
    }
    for prev_state = 0; prev_state < max_state; prev_state = prev_state + 1 {
      if dp[prev_state] < 0 {
        continue
      }
      let prev_sel = prev_state >> cols
      let prev_need = prev_state & full_mask
      // Enumerate all possible selection bitmasks for the current row.
      for cur_sel = 0; cur_sel <= full_mask; cur_sel = cur_sel + 1 {
        // Constraint: every cell in prev_need must have cur_sel bit set
        // (selecting current cell dominates the cell above).
        if (prev_need & cur_sel) != prev_need {
          continue
        }
        // Compute which cells in the current row are dominated.
        // A cell is dominated if:
        // - It is selected (cur_sel)
        // - Its left neighbor is selected (cur_sel >> 1)
        // - Its right neighbor is selected (cur_sel << 1)
        // - The cell above was selected (prev_sel)
        let dominated = cur_sel | (cur_sel << 1) | (cur_sel >> 1) | prev_sel
        let need_cur = full_mask & dominated.lnot()
        // On the last row, all cells must be dominated.
        if row == rows - 1 && need_cur != 0 {
          continue
        }
        let forward_state = (cur_sel << cols) | need_cur
        let new_count = dp[prev_state] + popcount(cur_sel)
        if next_dp[forward_state] < 0 || new_count < next_dp[forward_state] {
          next_dp[forward_state] = new_count
        }
      }
    }
    for i = 0; i < max_state; i = i + 1 {
      dp[i] = next_dp[i]
    }
  }
  // Answer: min dp[state] where need == 0 (all cells in last row dominated).
  let mut best = -1
  for state = 0; state < max_state; state = state + 1 {
    let need = state & full_mask
    if need == 0 && dp[state] >= 0 {
      if best < 0 || dp[state] < best {
        best = dp[state]
      }
    }
  }
  if best < 0 {
    0
  } else {
    best
  }
}

// ---------------------------------------------------------------------------
// Precomputed Transition Table for Domino Tiling
// ---------------------------------------------------------------------------

///|
/// Precompute all valid row-to-row transitions for domino tiling.
///
/// Returns a list of (prev_mask, next_mask) pairs that are compatible.
/// This is useful when you need to apply the same transitions repeatedly
/// (e.g., in matrix exponentiation for very tall grids).
///
/// ## Parameters
///
/// - `w`: Grid width.
///
/// ## Returns
///
/// An array of (prev_mask, next_mask) pairs.
///
/// ## Complexity
///
/// O(3^w) transitions.
pub fn domino_transitions(w : Int) -> Array[(Int, Int)] {
  if w <= 0 {
    return []
  }
  let n_states = 1 << w
  let transitions : Array[(Int, Int)] = []
  for mask = 0; mask < n_states; mask = mask + 1 {
    collect_transitions(mask, mask, 0, w, 0, transitions)
  }
  transitions
}

///|
/// Collect all valid next_mask values for a given prev_mask.
fn collect_transitions(
  orig_mask : Int,
  mask : Int,
  col : Int,
  w : Int,
  next_mask : Int,
  transitions : Array[(Int, Int)],
) -> Unit {
  if col == w {
    transitions.push((orig_mask, next_mask))
    return
  }
  if (mask & (1 << col)) != 0 {
    collect_transitions(orig_mask, mask, col + 1, w, next_mask, transitions)
  } else {
    if col + 1 < w && (mask & (1 << (col + 1))) == 0 {
      collect_transitions(
        orig_mask,
        mask | (1 << col) | (1 << (col + 1)),
        col + 2,
        w,
        next_mask,
        transitions,
      )
    }
    collect_transitions(
      orig_mask,
      mask | (1 << col),
      col + 1,
      w,
      next_mask | (1 << col),
      transitions,
    )
  }
}

///|
/// Count domino tilings using precomputed transitions (alternative implementation).
///
/// This version precomputes all transitions first, then applies them row by row.
/// For very tall grids, this can be combined with matrix exponentiation for
/// O(3^w · log(h)) complexity.
///
/// ## Parameters
///
/// - `h`: Grid height.
/// - `w`: Grid width.
///
/// ## Returns
///
/// The number of distinct domino tilings.
pub fn count_domino_tilings_fast(h : Int, w : Int) -> Int64 {
  if h <= 0 || w <= 0 {
    return 0L
  }
  if h * w % 2 == 1 {
    return 0L
  }
  let (rows, cols) = if h <= w { (h, w) } else { (w, h) }
  let n_states = 1 << cols
  // Precompute transitions.
  let trans = domino_transitions(cols)
  // Group transitions by prev_mask. Use makei to avoid sharing array references.
  let trans_by_prev : Array[Array[Int]] = Array::makei(n_states, fn(_) { [] })
  for i = 0; i < trans.length(); i = i + 1 {
    let (prev, next) = trans[i]
    trans_by_prev[prev].push(next)
  }
  // DP.
  let dp = Array::make(n_states, 0L)
  let next_dp = Array::make(n_states, 0L)
  dp[0] = 1L
  for row = 0; row < rows; row = row + 1 {
    for i = 0; i < n_states; i = i + 1 {
      next_dp[i] = 0L
    }
    for prev_mask = 0; prev_mask < n_states; prev_mask = prev_mask + 1 {
      if dp[prev_mask] == 0L {
        continue
      }
      let nexts = trans_by_prev[prev_mask]
      for j = 0; j < nexts.length(); j = j + 1 {
        let nm = nexts[j]
        next_dp[nm] = next_dp[nm] + dp[prev_mask]
      }
    }
    for i = 0; i < n_states; i = i + 1 {
      dp[i] = next_dp[i]
    }
  }
  dp[0]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "domino_tilings: 1x2 grid" {
  assert_true(count_domino_tilings(1, 2) == 1L)
}

///|
test "domino_tilings: 1x3 grid (odd)" {
  assert_true(count_domino_tilings(1, 3) == 0L)
}

///|
test "domino_tilings: 2x2 grid" {
  assert_true(count_domino_tilings(2, 2) == 2L)
}

///|
test "domino_tilings: 2x3 grid" {
  assert_true(count_domino_tilings(2, 3) == 3L)
}

///|
test "domino_tilings: 3x4 grid" {
  assert_true(count_domino_tilings(3, 4) == 11L)
}

///|
test "domino_tilings: 4x4 grid" {
  assert_true(count_domino_tilings(4, 4) == 36L)
}

///|
test "domino_tilings: 2xn Fibonacci" {
  // 2xn domino tilings follow Fibonacci: F(n+1)
  // F(1)=1, F(2)=2, F(3)=3, F(4)=5, F(5)=8, F(6)=13
  assert_true(count_domino_tilings(2, 1) == 1L)
  assert_true(count_domino_tilings(2, 2) == 2L)
  assert_true(count_domino_tilings(2, 3) == 3L)
  assert_true(count_domino_tilings(2, 4) == 5L)
  assert_true(count_domino_tilings(2, 5) == 8L)
  assert_true(count_domino_tilings(2, 6) == 13L)
}

///|
test "domino_tilings: 4x6 grid" {
  assert_true(count_domino_tilings(4, 6) == 281L)
}

///|
test "domino_tilings: 6x6 grid" {
  assert_true(count_domino_tilings(6, 6) == 6728L)
}

///|
test "domino_tilings: zero dimensions" {
  assert_true(count_domino_tilings(0, 5) == 0L)
  assert_true(count_domino_tilings(5, 0) == 0L)
}

///|
test "domino_tilings_fast: matches basic implementation" {
  // Verify fast version gives same results.
  assert_true(count_domino_tilings_fast(2, 2) == count_domino_tilings(2, 2))
  assert_true(count_domino_tilings_fast(3, 4) == count_domino_tilings(3, 4))
  assert_true(count_domino_tilings_fast(4, 4) == count_domino_tilings(4, 4))
  assert_true(count_domino_tilings_fast(2, 6) == count_domino_tilings(2, 6))
}

///|
test "domino_tilings_fast: 4x6 grid" {
  assert_true(count_domino_tilings_fast(4, 6) == 281L)
}

///|
test "domino_transitions: width 2" {
  let trans = domino_transitions(2)
  // For width 2, transitions should include:
  // mask=0 (00) → next=0 (both horizontal), next=3 (both vertical)
  // mask=1 (01) → next=2 (vertical on col 1)
  // mask=2 (10) → next=1 (vertical on col 0)
  // mask=3 (11) → next=0 (nothing to fill)
  assert_true(trans.length() == 5)
}

///|
test "max_independent_set: 1x1 grid" {
  assert_true(max_independent_set(1, 1) == 1)
}

///|
test "max_independent_set: 1x2 grid" {
  assert_true(max_independent_set(1, 2) == 1)
}

///|
test "max_independent_set: 2x2 grid" {
  assert_true(max_independent_set(2, 2) == 2)
}

///|
test "max_independent_set: 3x3 grid" {
  assert_true(max_independent_set(3, 3) == 5)
}

///|
test "max_independent_set: 4x4 grid" {
  assert_true(max_independent_set(4, 4) == 8)
}

///|
test "max_independent_set: 2x3 grid" {
  assert_true(max_independent_set(2, 3) == 3)
}

///|
test "max_independent_set: zero dimensions" {
  assert_true(max_independent_set(0, 5) == 0)
  assert_true(max_independent_set(5, 0) == 0)
}

///|
test "max_independent_set: checkerboard formula" {
  // ceil(h * w / 2) for various grids
  assert_true(max_independent_set(5, 5) == 13)
  assert_true(max_independent_set(3, 7) == 11)
  assert_true(max_independent_set(4, 7) == 14)
}

///|
test "max_weighted_independent_set: uniform weights" {
  // All weights = 1 → same as max_independent_set
  let w = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
  match max_weighted_independent_set(w, 2, 3) {
    Some(v) => assert_true((v - 3.0).abs() < 1.0e-10)
    None => assert_true(false)
  }
}

///|
test "max_weighted_independent_set: varied weights" {
  // 2x2 grid with weights:
  // [10, 1]
  // [1, 10]
  // Best: pick (0,0) and (1,1) → 20
  let w = [10.0, 1.0, 1.0, 10.0]
  match max_weighted_independent_set(w, 2, 2) {
    Some(v) => assert_true((v - 20.0).abs() < 1.0e-10)
    None => assert_true(false)
  }
}

///|
test "max_weighted_independent_set: single cell" {
  let w = [5.0]
  match max_weighted_independent_set(w, 1, 1) {
    Some(v) => assert_true((v - 5.0).abs() < 1.0e-10)
    None => assert_true(false)
  }
}

///|
test "max_weighted_independent_set: invalid input" {
  let w = [1.0, 2.0]
  assert_true(max_weighted_independent_set(w, 2, 2) is None)
}

///|
test "max_weighted_independent_set: 1x3 grid" {
  // [5, 10, 5] → best: pick middle (10) → 10
  let w = [5.0, 10.0, 5.0]
  match max_weighted_independent_set(w, 1, 3) {
    Some(v) => assert_true((v - 10.0).abs() < 1.0e-10)
    None => assert_true(false)
  }
}

///|
test "min_dominating_set: 1x1 grid" {
  assert_true(min_dominating_set(1, 1) == 1)
}

///|
test "min_dominating_set: 1x2 grid" {
  assert_true(min_dominating_set(1, 2) == 1)
}

///|
test "min_dominating_set: 2x2 grid" {
  // In 2x2, no single cell dominates all 4 (diagonal cells are not adjacent).
  // Need 2 cells (e.g., (0,0) and (1,1)).
  assert_true(min_dominating_set(2, 2) == 2)
}

///|
test "min_dominating_set: 3x3 grid" {
  // Center cell (1,1) dominates 5 cells but not the 4 corners.
  // Minimum is 3, e.g., (1,0), (0,2), (2,2) or similar configurations.
  assert_true(min_dominating_set(3, 3) == 3)
}

///|
test "min_dominating_set: 2x3 grid" {
  // Select (0,1) and (1,1): covers all 6 cells.
  assert_true(min_dominating_set(2, 3) == 2)
}

///|
test "min_dominating_set: 4x4 grid" {
  // 4x4 requires at least 4 cells.
  assert_true(min_dominating_set(4, 4) == 4)
}

///|
test "min_dominating_set: 1xn grid" {
  // 1xn: need ceil(n/3) cells
  assert_true(min_dominating_set(1, 1) == 1)
  assert_true(min_dominating_set(1, 2) == 1)
  assert_true(min_dominating_set(1, 3) == 1)
  assert_true(min_dominating_set(1, 4) == 2)
  assert_true(min_dominating_set(1, 5) == 2)
  assert_true(min_dominating_set(1, 6) == 2)
  assert_true(min_dominating_set(1, 7) == 3)
}

///|
test "min_dominating_set: zero dimensions" {
  assert_true(min_dominating_set(0, 5) == 0)
  assert_true(min_dominating_set(5, 0) == 0)
}
