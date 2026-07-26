/// Plug DP (Plug Dynamic Programming / Profile DP with connectivity states).
///
/// Also known as "broken profile DP" or "DP on broken contours", this technique
/// solves problems on grid graphs where the state tracks connectivity between
/// cells on the "frontier" between processed and unprocessed cells.
///
/// ## When to use
///
/// Plug DP is the **only known polynomial algorithm** for several NP-hard grid
/// problems when restricted to small-width grids:
///
/// - **Hamiltonian cycle/path counting** on a grid graph.
/// - **Number of perfect matchings** of a grid graph (domino tilings).
/// - **Number of spanning trees** of a grid graph.
/// - **Maximum/minimum weight closed tour** visiting all cells.
///
/// The complexity is O(n * m * 3^m) where m is the grid width (typically m ≤ 12).
/// For wider grids, this becomes intractable and heuristic or approximation
/// algorithms are needed.
///
/// ## How it works
///
/// The grid is processed cell-by-cell (left to right, top to bottom). The "plug"
/// state at each cell boundary is a partition of the m+1 plug positions into
/// connected components, represented using one of two encodings:
///
/// - **Bracket encoding** (used here): each plug position is labeled:
///   - `0` = no plug (no connection)
///   - `1` = left bracket (start of a component)
///   - `2` = right bracket (end of a component)
///   This is the standard representation that supports up to m/2 nested
///   components (matching parentheses).
///
/// - **Minimal representation**: each plug is labeled with the index of its
///   component's first occurrence. Simpler but requires O(m) relabeling per step.
///
/// We use the **bracket encoding** because it naturally prevents invalid
/// connectivity (e.g., crossing paths) and is the industry standard for
/// competitive programming.
///
/// ## State transitions
///
/// At each cell, we decide whether to place a plug going right, down, both, or
/// neither. The transition depends on the plugs coming from the left (cell above
/// in the contour) and top (cell to the left). The bracket structure is updated
/// to maintain valid parenthesization.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A plug state encoded as an array of bracket values (0=none, 1=left, 2=right).
///
/// The state has m+1 entries, representing the m+1 boundary positions between
/// the processed and unprocessed portions of the grid at any given cell.
pub struct PlugState {
  priv plugs : Array[Int] // 0=none, 1=left bracket, 2=right bracket
  priv n_plugs : Int // number of plug positions = grid_width + 1
}

///|
/// Create a plug state from an array of bracket values.
pub fn PlugState::new(plugs : Array[Int]) -> PlugState {
  { plugs, n_plugs: plugs.length() }
}

///|
/// Number of plug positions in this state.
pub fn PlugState::len(self : PlugState) -> Int {
  self.n_plugs
}

///|
/// Get the bracket value at position `i`.
pub fn PlugState::get(self : PlugState, i : Int) -> Int {
  if i < 0 || i >= self.n_plugs {
    return 0
  }
  self.plugs[i]
}

///|
/// Set the bracket value at position `i`.
pub fn PlugState::set(self : PlugState, i : Int, v : Int) -> Unit {
  if i >= 0 && i < self.n_plugs {
    self.plugs[i] = v
  }
}

///|
/// Clone this plug state (deep copy).
pub fn PlugState::clone(self : PlugState) -> PlugState {
  let new_plugs : Array[Int] = []
  for i = 0; i < self.n_plugs; i = i + 1 {
    new_plugs.push(self.plugs[i])
  }
  { plugs: new_plugs, n_plugs: self.n_plugs }
}

///|
/// Check if this is the empty state (all plugs are 0).
pub fn PlugState::is_empty(self : PlugState) -> Bool {
  for i = 0; i < self.n_plugs; i = i + 1 {
    if self.plugs[i] != 0 {
      return false
    }
  }
  true
}

///|
/// Check if the bracket structure is valid (balanced parentheses).
pub fn PlugState::is_valid(self : PlugState) -> Bool {
  let mut depth = 0
  for i = 0; i < self.n_plugs; i = i + 1 {
    match self.plugs[i] {
      0 => continue
      1 => depth = depth + 1
      2 => {
        depth = depth - 1
        if depth < 0 {
          return false
        }
      }
      _ => return false // invalid value
    }
  }
  depth == 0
}

///|
/// Encode the plug state as a hashable integer (base-3 encoding).
/// Each plug value (0, 1, 2) takes one ternary digit.
pub fn PlugState::encode(self : PlugState) -> Int {
  let mut code = 0
  for i = 0; i < self.n_plugs; i = i + 1 {
    code = code * 3 + self.plugs[i]
  }
  code
}

// ---------------------------------------------------------------------------
// StateMap: a simple Array-based dictionary for (Int -> Int64) mappings.
//
// MoonBit's built-in Map lacks for_each / get_or in this version, so we
// provide a minimal hash map tailored to Plug DP's access patterns:
// - States are integer codes (base-3 encoded).
// - The number of live states at any step is small (≤ 3^m).
// - We need: insert/lookup/iterate/clear, all O(number_of_live_states).
// ---------------------------------------------------------------------------

///|
/// A simple dictionary mapping Int state codes to Int64 counts.
///
/// Uses open addressing with linear probing. The capacity is always a power
/// of two, and the load factor is kept below 0.75. This gives O(1) amortized
/// lookup/insert for the typical Plug DP workload.
priv struct StateMap {
  mut keys : Array[Int]
  mut vals : Array[Int64]
  mut size : Int
  mut capacity : Int
  mut mask : Int
}

///|
/// Create a StateMap with the given initial capacity (rounded up to power of 2).
fn StateMap::new(initial_cap : Int) -> StateMap {
  let cap = next_pow2(initial_cap.max(16))
  let keys = Array::make(cap, -1)
  let vals = Array::make(cap, 0L)
  { keys, vals, size: 0, capacity: cap, mask: cap - 1 }
}

///|
/// Find the slot index for `key`, or -1 if not found.
fn StateMap::find_slot(self : StateMap, key : Int) -> Int {
  let mut idx = key & self.mask
  if idx < 0 {
    idx = idx + self.capacity
  }
  for i = 0; i < self.capacity; i = i + 1 {
    let k = self.keys[idx]
    if k == -1 || k == key {
      return idx
    }
    idx = (idx + 1) & self.mask
  }
  -1 // table full (should not happen with resize)
}

///|
/// Get the value for `key`, or `default` if not present.
fn StateMap::get_or(self : StateMap, key : Int, default : Int64) -> Int64 {
  let idx = self.find_slot(key)
  if idx < 0 || self.keys[idx] == -1 {
    return default
  }
  self.vals[idx]
}

///|
/// Set `key` to `val`. If the key already exists, its value is replaced.
fn StateMap::set(self : StateMap, key : Int, val : Int64) -> Unit {
  // Resize if load factor exceeds 0.75.
  if (self.size + 1) * 4 > self.capacity * 3 {
    self.resize(self.capacity * 2)
  }
  let idx = self.find_slot(key)
  if idx < 0 {
    return
  }
  if self.keys[idx] == -1 {
    self.size = self.size + 1
  }
  self.keys[idx] = key
  self.vals[idx] = val
}

///|
/// Add `delta` to the value for `key`. If the key does not exist, it is
/// inserted with value `delta`.
fn StateMap::add(self : StateMap, key : Int, delta : Int64) -> Unit {
  // Resize if load factor exceeds 0.75.
  if (self.size + 1) * 4 > self.capacity * 3 {
    self.resize(self.capacity * 2)
  }
  let idx = self.find_slot(key)
  if idx < 0 {
    return
  }
  if self.keys[idx] == -1 {
    self.size = self.size + 1
    self.keys[idx] = key
    self.vals[idx] = delta
  } else {
    self.vals[idx] = self.vals[idx] + delta
  }
}

///|
/// Resize the internal table to `new_cap`.
fn StateMap::resize(self : StateMap, new_cap : Int) -> Unit {
  let cap = next_pow2(new_cap)
  let old_keys = self.keys
  let old_vals = self.vals
  let old_cap = self.capacity
  self.keys = Array::make(cap, -1)
  self.vals = Array::make(cap, 0L)
  self.capacity = cap
  self.mask = cap - 1
  self.size = 0
  for i = 0; i < old_cap; i = i + 1 {
    if old_keys[i] != -1 {
      self.set(old_keys[i], old_vals[i])
    }
  }
}

///|
/// Clear all entries.
fn StateMap::clear(self : StateMap) -> Unit {
  for i = 0; i < self.capacity; i = i + 1 {
    self.keys[i] = -1
  }
  self.size = 0
}

///|
/// Iterate over all (key, val) pairs, calling `f` for each.
fn StateMap::for_each(self : StateMap, f : (Int, Int64) -> Unit) -> Unit {
  for i = 0; i < self.capacity; i = i + 1 {
    if self.keys[i] != -1 {
      f(self.keys[i], self.vals[i])
    }
  }
}

///|
/// Compute the next power of 2 ≥ n.
fn next_pow2(n : Int) -> Int {
  let mut p = 1
  while p < n {
    p = p << 1
  }
  p
}

// ---------------------------------------------------------------------------
// Grid solver: count Hamiltonian cycles on a grid graph
// ---------------------------------------------------------------------------

///|
/// Count the number of Hamiltonian cycles on an n×m grid graph.
///
/// A Hamiltonian cycle visits every cell exactly once and returns to the start.
/// This is #P-complete in general, but Plug DP solves it in O(n * m * 3^m) time.
///
/// ## Parameters
/// - `n`, `m`: grid dimensions (rows, columns). `m` should be ≤ 12 for
///   tractable computation.
///
/// ## Returns
/// The number of distinct Hamiltonian cycles. Returns 0 for impossible cases
/// (e.g., grids with odd number of cells, 1×1 grid, etc.).
///
/// ## Limitations
/// - Only works for grid graphs where cells are connected to their 4-neighbors.
/// - For m > 15, the state space becomes too large for practical computation.
/// - The result can overflow Int64 for large grids.
pub fn count_hamiltonian_cycles(n : Int, m : Int) -> Int64 {
  if n <= 0 || m <= 0 {
    return 0L
  }
  if n == 1 && m == 1 {
    return 0L // single cell cannot form a cycle
  }
  if n * m % 2 != 0 {
    return 0L // odd number of cells → no Hamiltonian cycle
  }
  // We process cells left-to-right, top-to-bottom.
  // The contour has m+1 plug positions.
  let n_plugs = m + 1
  // dp[state_code] = number of ways to reach this plug state
  let dp = StateMap::new(256)
  // Initial state: all plugs empty.
  let initial = PlugState::new(Array::make(n_plugs, 0))
  dp.set(initial.encode(), 1L)
  for row = 0; row < n; row = row + 1 {
    for col = 0; col < m; col = col + 1 {
      // For each cell, process all current states and generate new states.
      let new_dp = StateMap::new(256)
      dp.for_each(fn(code, count) {
        if count == 0L {
          return
        }
        let state = decode_state(code, n_plugs)
        // The plugs relevant to this cell:
        // - left_plug: state[col] (plug coming from the cell to the left)
        // - top_plug: state[col + 1] (plug coming from the cell above)
        let left = state.get(col)
        let top = state.get(col + 1)
        // Case 1: Both left and top are 0 — create a new component.
        // Place a left bracket at col and right bracket at col+1.
        if left == 0 && top == 0 {
          if row < n - 1 && col < m - 1 {
            let ns = state.clone()
            ns.set(col, 1)
            ns.set(col + 1, 2)
            new_dp.add(ns.encode(), count)
          }
          // Case 2: left is a plug, top is 0 — extend the plug downward or rightward.
          //
          // Convention: after processing cell (row, col):
          //   state[col]     = bottom plug (goes to next row)
          //   state[col + 1] = right plug (goes to next column)
        } else if left != 0 && top == 0 {
          // Extend downward: the incoming left plug continues to the bottom.
          //   state[col] = left (bottom plug carries the bracket forward)
          //   state[col + 1] = 0  (no right plug)
          if row < n - 1 {
            let ns = state.clone()
            ns.set(col, left)
            ns.set(col + 1, 0)
            new_dp.add(ns.encode(), count)
          }
          // Extend rightward: the incoming left plug continues to the right.
          //   state[col] = 0  (no bottom plug)
          //   state[col + 1] = left (right plug carries the bracket forward)
          if col < m - 1 {
            let ns = state.clone()
            ns.set(col, 0)
            ns.set(col + 1, left)
            new_dp.add(ns.encode(), count)
          }
          // Case 3: left is 0, top is a plug — extend downward or rightward.
        } else if left == 0 && top != 0 {
          // Extend downward: the incoming top plug continues to the bottom.
          //   state[col] = top (bottom plug carries the bracket forward)
          //   state[col + 1] = 0  (no right plug)
          if row < n - 1 {
            let ns = state.clone()
            ns.set(col, top)
            ns.set(col + 1, 0)
            new_dp.add(ns.encode(), count)
          }
          // Extend rightward: the incoming top plug continues to the right.
          //   state[col] = 0  (no bottom plug)
          //   state[col + 1] = top (right plug carries the bracket forward)
          if col < m - 1 {
            let ns = state.clone()
            ns.set(col, 0)
            ns.set(col + 1, top)
            new_dp.add(ns.encode(), count)
          }
          // Case 4: Both left and top are plugs — merge them.
          // Four sub-cases by bracket type:
          //   (1,2) '(' meets ')' — closes a component (only valid at last cell)
          //   (2,1) ')' meets '(' — merges two different components
          //   (1,1) '(' meets '(' — relabel matching ')' of 2nd to '('
          //   (2,2) ')' meets ')' — relabel matching '(' of 1st to ')'
        } else if left != 0 && top != 0 {
          let ns = state.clone()
          ns.set(col, 0)
          ns.set(col + 1, 0)
          if left == 1 && top == 2 {
            // '(' meets ')': closes a component.
            // Only valid at the last cell for a Hamiltonian cycle.
            if row == n - 1 && col == m - 1 {
              if is_empty_except(ns, col, col + 1) {
                new_dp.add(ns.encode(), count)
              }
            }
          } else if left == 2 && top == 1 {
            // ')' meets '(': merge two different components.
            relabel_merge(ns, col, col + 1, n_plugs)
            new_dp.add(ns.encode(), count)
          } else if left == 1 && top == 1 {
            // '(' meets '(': find matching ')' for '(' at col+1, change it to '('.
            let mut depth = 0
            let mut match_pos = -1
            for j = col + 2; j < n_plugs; j = j + 1 {
              if ns.get(j) == 1 {
                depth = depth + 1
              } else if ns.get(j) == 2 {
                if depth == 0 {
                  match_pos = j
                  break
                }
                depth = depth - 1
              }
            }
            if match_pos >= 0 {
              ns.set(match_pos, 1) // ')' → '('
              new_dp.add(ns.encode(), count)
            }
          } else if left == 2 && top == 2 {
            // ')' meets ')': find matching '(' for ')' at col, change it to ')'.
            let mut depth = 0
            let mut match_pos = -1
            for j = col - 1; j >= 0; j = j - 1 {
              if ns.get(j) == 2 {
                depth = depth + 1
              } else if ns.get(j) == 1 {
                if depth == 0 {
                  match_pos = j
                  break
                }
                depth = depth - 1
              }
            }
            if match_pos >= 0 {
              ns.set(match_pos, 2) // '(' → ')'
              new_dp.add(ns.encode(), count)
            }
          }
        }
      })
      // Replace dp with new_dp
      dp.clear()
      new_dp.for_each(fn(k, v) { dp.set(k, v) })
    }
    // Row transition: shift contour for the next row.
    // Position 0 must become 0 (no left plug at start of row).
    // Position i (i>0) becomes old position i-1 (bottom edge → top edge).
    // Old position m must be 0 (no plug going right beyond grid).
    let shifted_dp = StateMap::new(256)
    dp.for_each(fn(code, count) {
      let state = decode_state(code, n_plugs)
      // Reject states with a non-zero plug at the rightmost position.
      if state.get(n_plugs - 1) != 0 {
        return
      }
      let new_plugs : Array[Int] = Array::make(n_plugs, 0)
      new_plugs[0] = 0 // left edge of first cell (no cell to the left)
      for i = 1; i < n_plugs; i = i + 1 {
        new_plugs[i] = state.get(i - 1)
      }
      let ns = PlugState::new(new_plugs)
      shifted_dp.add(ns.encode(), count)
    })
    dp.clear()
    shifted_dp.for_each(fn(k, v) { dp.set(k, v) })
  }
  // The answer is the count for the empty state after processing all cells.
  let empty = PlugState::new(Array::make(n_plugs, 0))
  dp.get_or(empty.encode(), 0L)
}

///|
/// Check if all plugs are 0 except possibly at positions `excl1` and `excl2`.
fn is_empty_except(state : PlugState, excl1 : Int, excl2 : Int) -> Bool {
  for i = 0; i < state.n_plugs; i = i + 1 {
    if i == excl1 || i == excl2 {
      continue
    }
    if state.plugs[i] != 0 {
      return false
    }
  }
  true
}

///|
/// Decode a state code back into a PlugState.
fn decode_state(code : Int, n_plugs : Int) -> PlugState {
  let plugs : Array[Int] = Array::make(n_plugs, 0)
  let mut c = code
  for i = n_plugs - 1; i >= 0; i = i - 1 {
    plugs[i] = c % 3
    c = c / 3
  }
  { plugs, n_plugs }
}

///|
/// Relabel brackets when merging two components (right bracket meets left bracket).
fn relabel_merge(
  state : PlugState,
  left_pos : Int,
  right_pos : Int,
  n_plugs : Int,
) -> Unit {
  // The right bracket ')' at left_pos matches some left bracket '(' earlier.
  // The left bracket '(' at right_pos matches some right bracket ')' later.
  // After merging, we need to connect the earlier '(' with the later ')'.
  // Find the matching '(' for the ')' at left_pos (scan left).
  let mut depth = 0
  let mut match_left = -1
  for i = left_pos - 1; i >= 0; i = i - 1 {
    if state.get(i) == 2 {
      depth = depth + 1
    } else if state.get(i) == 1 {
      if depth == 0 {
        match_left = i
        break
      }
      depth = depth - 1
    }
  }
  // Find the matching ')' for the '(' at right_pos (scan right).
  let mut depth2 = 0
  let mut match_right = -1
  for i = right_pos + 1; i < n_plugs; i = i + 1 {
    if state.get(i) == 1 {
      depth2 = depth2 + 1
    } else if state.get(i) == 2 {
      if depth2 == 0 {
        match_right = i
        break
      }
      depth2 = depth2 - 1
    }
  }
  // Relabel: the '(' at match_left becomes the new '(' for the merged component,
  // and the ')' at match_right becomes the new ')'.
  // The positions left_pos and right_pos are already cleared to 0.
  if match_left >= 0 && match_right >= 0 {
    state.set(match_left, 1)
    state.set(match_right, 2)
  }
}

// ---------------------------------------------------------------------------
// Simpler application: count perfect matchings of a grid (domino tilings)
// ---------------------------------------------------------------------------

///|
/// Count the number of perfect matchings (domino tilings) of an n×m grid.
///
/// A domino tiling covers every cell of the grid with 1×2 or 2×1 dominoes
/// such that no two dominoes overlap and no cell is uncovered.
///
/// Uses the transfer-matrix method with bitmask DP: process the grid column
/// by column, and at each column the state is a bitmask of which cells in
/// the current column are already covered by a horizontal domino from the
/// previous column.
///
/// Complexity: O(n * m * 2^n). For n ≤ 20 this is tractable.
///
/// ## Parameters
/// - `n`, `m`: grid dimensions.
///
/// ## Returns
/// The number of domino tilings. Returns 0 if n*m is odd.
pub fn count_domino_tilings(n : Int, m : Int) -> Int64 {
  if n <= 0 || m <= 0 {
    return 0L
  }
  if n * m % 2 != 0 {
    return 0L
  }
  // Ensure n is the smaller dimension for efficiency.
  let (rows, cols) = if n <= m { (n, m) } else { (m, n) }
  let full_mask = (1 << rows) - 1
  // dp[mask] = number of ways to tile up to the current column with `mask`
  // indicating which cells in the current column are pre-filled.
  let dp : Array[Int64] = Array::make(1 << rows, 0L)
  dp[0] = 1L
  for col = 0; col < cols; col = col + 1 {
    let new_dp : Array[Int64] = Array::make(1 << rows, 0L)
    for mask = 0; mask <= full_mask; mask = mask + 1 {
      if dp[mask] == 0L {
        continue
      }
      // Try all ways to fill the remaining cells in this column.
      // `mask` tells us which cells are already filled (from horizontal dominoes
      // extending from the previous column). We need to fill the rest with:
      // - vertical dominoes (covering two consecutive rows in this column)
      // - horizontal dominoes (extending to the next column)
      fill_column(mask, 0, rows, full_mask, 0, dp[mask], new_dp)
    }
    for i = 0; i <= full_mask; i = i + 1 {
      dp[i] = new_dp[i]
    }
  }
  dp[0]
}

///|
/// Recursively fill the remaining cells in a column, generating next column's mask.
fn fill_column(
  cur_mask : Int,
  pos : Int,
  rows : Int,
  full_mask : Int,
  next_mask : Int,
  count : Int64,
  new_dp : Array[Int64],
) -> Unit {
  if pos >= rows {
    // All cells in this column are filled. The next column starts with next_mask.
    new_dp[next_mask] = new_dp[next_mask] + count
    return
  }
  // If this cell is already filled (by a horizontal domino from prev column).
  if (cur_mask & (1 << pos)) != 0 {
    fill_column(cur_mask, pos + 1, rows, full_mask, next_mask, count, new_dp)
    return
  }
  // Option 1: place a vertical domino (covers pos and pos+1 in this column).
  if pos + 1 < rows && (cur_mask & (1 << (pos + 1))) == 0 {
    fill_column(
      cur_mask | (1 << pos) | (1 << (pos + 1)),
      pos + 2,
      rows,
      full_mask,
      next_mask,
      count,
      new_dp,
    )
  }
  // Option 2: place a horizontal domino (extends to next column).
  fill_column(
    cur_mask | (1 << pos),
    pos + 1,
    rows,
    full_mask,
    next_mask | (1 << pos),
    count,
    new_dp,
  )
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "PlugState: encode/decode roundtrip" {
  let state = PlugState::new([0, 1, 2, 0, 1, 0, 2, 0])
  let code = state.encode()
  let decoded = decode_state(code, 8)
  assert_eq(decoded.get(0), 0)
  assert_eq(decoded.get(1), 1)
  assert_eq(decoded.get(2), 2)
  assert_eq(decoded.get(3), 0)
  assert_eq(decoded.get(4), 1)
  assert_eq(decoded.get(5), 0)
  assert_eq(decoded.get(6), 2)
  assert_eq(decoded.get(7), 0)
}

///|
test "PlugState: is_valid" {
  assert_true(PlugState::new([0, 0, 0]).is_valid())
  assert_true(PlugState::new([1, 2, 0]).is_valid())
  assert_true(PlugState::new([1, 0, 2]).is_valid())
  assert_true(PlugState::new([1, 2, 1, 2]).is_valid())
  assert_false(PlugState::new([1, 1, 2]).is_valid()) // unbalanced
  assert_false(PlugState::new([2, 1]).is_valid()) // starts with right bracket
}

///|
test "PlugState: is_empty" {
  assert_true(PlugState::new([0, 0, 0, 0]).is_empty())
  assert_false(PlugState::new([0, 1, 0, 0]).is_empty())
}

///|
test "count_domino_tilings: 2×2 grid" {
  // A 2×2 grid has 2 tilings:
  // 1. Two horizontal dominoes
  // 2. Two vertical dominoes
  assert_eq(count_domino_tilings(2, 2), 2L)
}

///|
test "count_domino_tilings: 2×3 grid" {
  // A 2×3 grid has 3 tilings.
  assert_eq(count_domino_tilings(2, 3), 3L)
}

///|
test "count_domino_tilings: 4×4 grid" {
  // A 4×4 grid has 36 tilings.
  assert_eq(count_domino_tilings(4, 4), 36L)
}

///|
test "count_domino_tilings: 1×n" {
  // A 1×n grid has exactly 1 tiling (all horizontal) if n is even, 0 if odd.
  assert_eq(count_domino_tilings(1, 2), 1L)
  assert_eq(count_domino_tilings(1, 4), 1L)
  assert_eq(count_domino_tilings(1, 6), 1L)
  assert_eq(count_domino_tilings(1, 3), 0L) // odd
}

///|
test "count_domino_tilings: odd area" {
  assert_eq(count_domino_tilings(3, 3), 0L) // 9 cells, odd
}

///|
test "count_domino_tilings: 2×5 Fibonacci" {
  // 2×5 grid has 8 tilings (Fibonacci-like: F(6) = 8).
  assert_eq(count_domino_tilings(2, 5), 8L)
}

///|
test "count_domino_tilings: 3×4" {
  // 3×4 grid has 11 tilings.
  assert_eq(count_domino_tilings(3, 4), 11L)
}

///|
test "count_domino_tilings: 4×6" {
  // 4×6 grid has 281 tilings.
  assert_eq(count_domino_tilings(4, 6), 281L)
}

///|
test "count_domino_tilings: zero dimensions" {
  assert_eq(count_domino_tilings(0, 5), 0L)
  assert_eq(count_domino_tilings(5, 0), 0L)
}

///|
test "count_hamiltonian_cycles: 2×2" {
  // A 2×2 grid has 1 Hamiltonian cycle (the perimeter).
  assert_eq(count_hamiltonian_cycles(2, 2), 1L)
}

///|
test "count_hamiltonian_cycles: odd cells" {
  // 3×3 = 9 cells (odd) → no Hamiltonian cycle.
  assert_eq(count_hamiltonian_cycles(3, 3), 0L)
}

///|
test "count_hamiltonian_cycles: 1×n" {
  // 1×n cannot form a cycle.
  assert_eq(count_hamiltonian_cycles(1, 4), 0L)
}
