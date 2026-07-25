/// Combinatorial game theory: Nim and Sprague–Grundy theorem.
///
/// This module implements the core building blocks of impartial combinatorial
/// game theory:
///
/// - **Nim**: the canonical impartial game. The winner is determined by the
///   XOR of pile sizes (the *Nim-sum*). If the Nim-sum is non-zero, the first
///   player has a winning strategy; otherwise the second player wins.
/// - **Sprague–Grundy theorem**: every impartial game is equivalent to a Nim
///   heap of size `g`, where `g` is the *Grundy number* (or *nimber*) of the
///   position. The Grundy number is the *mex* (minimum excludant) of the
///   Grundy numbers of all positions reachable in one move.
/// - **Game sum**: the Grundy number of a disjunctive sum of games is the XOR
///   of the individual Grundy numbers.
///
/// ## Complexity
///
/// - `nim_sum`          — O(n)
/// - `nim_winner`        — O(n)
/// - `nim_winning_move` — O(n)
/// - `mex`              — O(m) where m = array length
/// - `grundy_dp`        — O(n · m) where m = max transition count
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// ---------------------------------------------------------------------------
/// Nim
/// ---------------------------------------------------------------------------

/// Compute the Nim-sum (XOR) of an array of pile sizes.
///
/// The Nim-sum determines the outcome of a Nim game:
/// - Nim-sum ≠ 0 → first player wins (N-position)
/// - Nim-sum = 0  → second player wins (P-position)
pub fn nim_sum(piles : Array[Int]) -> Int {
  let mut result = 0
  for i = 0; i < piles.length(); i = i + 1 {
    result = result ^ piles[i]
  }
  result
}

/// Determine the winner of a Nim game given pile sizes.
///
/// Returns `0` if the first player wins, `1` if the second player wins.
/// An empty game (no piles or all piles empty) is a second-player win.
pub fn nim_winner(piles : Array[Int]) -> Int {
  if nim_sum(piles) != 0 { 0 } else { 1 }
}

/// Find a winning move for the first player in Nim.
///
/// Returns `Some((pile_index, new_size))` — the index of the pile to reduce
/// and its new size — if a winning move exists. Returns `None` if the
/// position is a P-position (second player wins, no winning move).
///
/// **Strategy**: Let `x = nim_sum`. Find a pile `i` where `piles[i] ^ x <
/// piles[i]`. Reducing that pile to `piles[i] ^ x` makes the new Nim-sum
/// zero, which is a winning position.
pub fn nim_winning_move(piles : Array[Int]) -> (Int, Int)? {
  let x = nim_sum(piles)
  if x == 0 {
    return None
  }
  for i = 0; i < piles.length(); i = i + 1 {
    let target = piles[i] ^ x
    if target < piles[i] {
      return Some((i, target))
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Sprague–Grundy
// ---------------------------------------------------------------------------

/// Minimum excludant (mex): the smallest non-negative integer **not** in the
/// given array.
///
/// This is the core operation for computing Grundy numbers. The input does
/// not need to be sorted — a boolean presence table is used internally.
///
/// Returns the mex value (always ≥ 0).
pub fn mex(values : Array[Int]) -> Int {
  // Use a presence set. Since mex ≤ values.length(), we only need to track
  // values in [0, n].
  let n = values.length()
  let present = FixedArray::make(n + 1, false)
  for i = 0; i < n; i = i + 1 {
    let v = values[i]
    if v >= 0 && v <= n {
      present[v] = true
    }
  }
  for i = 0; i <= n; i = i + 1 {
    if !present[i] {
      return i
    }
  }
  n + 1
}

/// Compute Grundy numbers for all positions `0..n` using a transition
/// function.
///
/// `transitions(pos)` returns an array of Grundy numbers of all positions
/// reachable from `pos` in one move. The Grundy number of `pos` is the mex
/// of those values.
///
/// Returns a `FixedArray[Int]` of length `n + 1` where index `i` holds the
/// Grundy number of position `i`.
///
/// This is the standard dynamic programming approach for computing Grundy
/// numbers in games like:
/// - Staircase Nim
/// - Subtraction games (remove 1..k stones)
/// - Kayles
/// - Green Hackenbush on paths
pub fn grundy_dp(
  n : Int,
  transitions : (Int) -> Array[Int],
) -> FixedArray[Int] {
  if n < 0 {
    return FixedArray::make(0, 0)
  }
  let g = FixedArray::make(n + 1, 0)
  // Position 0 has Grundy 0 (terminal position, no moves).
  for pos = 1; pos <= n; pos = pos + 1 {
    let reachable = transitions(pos)
    let reach_g = []
    for j = 0; j < reachable.length(); j = j + 1 {
      let next = reachable[j]
      if next >= 0 && next <= n {
        reach_g.push(g[next])
      }
    }
    g[pos] = mex(reach_g)
  }
  g
}

/// Compute the Grundy number of a disjunctive sum of sub-games.
///
/// By the Sprague–Grundy theorem, the combined Grundy number is the XOR of
/// the individual Grundy numbers. This determines whether the combined
/// position is a first-player win (≠ 0) or a second-player win (= 0).
pub fn grundy_sum(grundy_numbers : Array[Int]) -> Int {
  let mut result = 0
  for i = 0; i < grundy_numbers.length(); i = i + 1 {
    result = result ^ grundy_numbers[i]
  }
  result
}

/// Determine the winner of a disjunctive sum of impartial games.
///
/// `grundy_numbers[i]` is the Grundy number of the i-th sub-game.
/// Returns `0` if the first player wins, `1` if the second player wins.
pub fn game_sum_winner(grundy_numbers : Array[Int]) -> Int {
  if grundy_sum(grundy_numbers) != 0 { 0 } else { 1 }
}

// ---------------------------------------------------------------------------
// Classic game Grundy numbers
// ---------------------------------------------------------------------------

/// Grundy number for a single-pile subtraction game: remove 1..k stones per
/// turn. The last player to move wins (normal play).
///
/// Pattern: `g(n) = n mod (k + 1)`.
///
/// Returns a `FixedArray[Int]` of length `n + 1`.
pub fn subtraction_game_grundy(n : Int, k : Int) -> FixedArray[Int] {
  if n < 0 {
    return FixedArray::make(0, 0)
  }
  let g = FixedArray::make(n + 1, 0)
  for i = 1; i <= n; i = i + 1 {
    g[i] = i % (k + 1)
  }
  g
}

/// Grundy number for Kayles: a bowling pins game where a player can knock
/// down one pin or two adjacent pins per turn.
///
/// The pattern is periodic with period 12 for n ≥ 72:
/// `g(n) = g(n - 12)` for n ≥ 72.
///
/// Returns a `FixedArray[Int]` of length `n + 1`.
pub fn kayles_grundy(n : Int) -> FixedArray[Int] {
  if n < 0 {
    return FixedArray::make(0, 0)
  }
  let g = FixedArray::make(n + 1, 0)
  for i = 1; i <= n; i = i + 1 {
    let reachable = []
    // Knock down one pin at position j: splits into left (j-1) and right
    // (i-j). Grundy = g[j-1] ^ g[i-j].
    for j = 1; j <= i; j = j + 1 {
      let left = if j > 1 { g[j - 1] } else { 0 }
      let right = if j < i { g[i - j] } else { 0 }
      reachable.push(left ^ right)
    }
    // Knock down two adjacent pins at positions j, j+1: splits into left
    // (j-1) and right (i-j-1). Grundy = g[j-1] ^ g[i-j-1].
    for j = 1; j < i; j = j + 1 {
      let left = if j > 1 { g[j - 1] } else { 0 }
      let right = if j < i - 1 { g[i - j - 1] } else { 0 }
      reachable.push(left ^ right)
    }
    g[i] = mex(reachable)
  }
  g
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "nim: basic nim-sum" {
  assert_eq(nim_sum([1, 2, 3]), 0)
  assert_eq(nim_sum([1, 2, 4]), 7)
  assert_eq(nim_sum([5]), 5)
  assert_eq(nim_sum([]), 0)
  assert_eq(nim_sum([7, 7]), 0)
}

test "nim: winner" {
  // 1,2,3 → nim-sum = 0, second player wins
  assert_eq(nim_winner([1, 2, 3]), 1)
  // 1,2,4 → nim-sum = 7, first player wins
  assert_eq(nim_winner([1, 2, 4]), 0)
  // Single pile, first player wins
  assert_eq(nim_winner([5]), 0)
  // Empty game, second player wins
  assert_eq(nim_winner([]), 1)
  // All zeros, second player wins
  assert_eq(nim_winner([0, 0, 0]), 1)
}

test "nim: winning move" {
  // 1,2,4 → nim-sum = 7. Pile 2 (size 4): 4^7 = 3 < 4.
  let mv = nim_winning_move([1, 2, 4])
  assert_true(mv is Some(_))
  let (idx, new_size) = mv.unwrap()
  assert_eq(idx, 2)
  assert_eq(new_size, 3)
  // Verify: after move, nim-sum should be 0
  let piles = [1, 2, 3]
  assert_eq(nim_sum(piles), 0)

  // 1,2,3 → nim-sum = 0, no winning move
  assert_true(nim_winning_move([1, 2, 3]) is None)

  // Single pile of 5: winning move is to reduce to 0
  let m2 = nim_winning_move([5])
  assert_true(m2 is Some(_))
  let (i2, s2) = m2.unwrap()
  assert_eq(i2, 0)
  assert_eq(s2, 0)
}

test "mex: basic" {
  assert_eq(mex([0, 1, 2, 3]), 4)
  assert_eq(mex([1, 2, 3]), 0)
  assert_eq(mex([0, 2, 3]), 1)
  assert_eq(mex([0, 1, 3]), 2)
  assert_eq(mex([]), 0)
  assert_eq(mex([0, 1, 2, 3, 4, 5]), 6)
}

test "mex: with negatives and duplicates" {
  assert_eq(mex([-1, 0, 1]), 2)
  assert_eq(mex([0, 0, 1, 1, 2, 2]), 3)
  assert_eq(mex([5, 6, 7]), 0)
}

test "grundy_dp: subtraction game (k=3)" {
  // Subtraction game: remove 1..3 stones. Grundy(n) = n mod 4.
  let g = grundy_dp(20, fn(pos) {
    let result = []
    for k = 1; k <= 3; k = k + 1 {
      if pos - k >= 0 {
        result.push(pos - k)
      }
    }
    result
  })
  for i = 0; i <= 20; i = i + 1 {
    assert_eq(g[i], i % 4)
  }
}

test "grundy_dp: subtraction game (k=2)" {
  // Remove 1..2 stones. Grundy(n) = n mod 3.
  let g = grundy_dp(15, fn(pos) {
    let result = []
    for k = 1; k <= 2; k = k + 1 {
      if pos - k >= 0 {
        result.push(pos - k)
      }
    }
    result
  })
  for i = 0; i <= 15; i = i + 1 {
    assert_eq(g[i], i % 3)
  }
}

test "grundy_sum: xor of Grundy numbers" {
  assert_eq(grundy_sum([0, 0, 0]), 0)
  assert_eq(grundy_sum([1, 2, 3]), 0)
  assert_eq(grundy_sum([5]), 5)
  assert_eq(grundy_sum([3, 3]), 0)
  assert_eq(grundy_sum([1, 2, 4]), 7)
}

test "game_sum_winner: basic" {
  // All zeros → second player
  assert_eq(game_sum_winner([0, 0, 0]), 1)
  // Non-zero xor → first player
  assert_eq(game_sum_winner([1, 0, 0]), 0)
  // 1^2^3 = 0 → second player
  assert_eq(game_sum_winner([1, 2, 3]), 1)
}

test "subtraction_game: pattern" {
  let g = subtraction_game_grundy(20, 3)
  for i = 0; i <= 20; i = i + 1 {
    assert_eq(g[i], i % 4)
  }
  let g2 = subtraction_game_grundy(15, 1)
  for i = 0; i <= 15; i = i + 1 {
    assert_eq(g2[i], i % 2)
  }
}

test "kayles: known values" {
  // Known Grundy values for Kayles (OEIS A071426):
  let expected = [
    0, 1, 2, 3, 1, 4, 3, 2, 1, 4, 2, 6, 4, 1, 2, 7, 1, 4, 3, 2, 1, 4, 6, 7,
    4, 1, 2, 8, 5, 4, 7,
  ]
  let g = kayles_grundy(30)
  for i = 0; i <= 30; i = i + 1 {
    assert_eq(g[i], expected[i])
  }
}

test "kayles: periodicity" {
  // Kayles is periodic with period 12 for n >= 72
  let g = kayles_grundy(90)
  for i = 84; i <= 90; i = i + 1 {
    assert_eq(g[i], g[i - 12])
  }
}

test "nim: misère variant (last player loses)" {
  // In misère Nim, the winning condition is the same as normal Nim,
  // except when all piles have size ≤ 1. In that case, the winner is
  // the OPPOSITE of normal Nim.
  // All piles size 1: if odd count, second player wins (misère).
  // Normal: first player wins (odd non-zero xor).
  // Misère: second player wins.
  let piles = [1, 1, 1] // 3 piles of 1
  let normal = nim_winner(piles)
  // Normal Nim: nim-sum = 1, first player wins
  assert_eq(normal, 0)
  // For misère: when all piles ≤ 1, invert the result
  let mut all_one = true
  for i = 0; i < piles.length(); i = i + 1 {
    if piles[i] > 1 {
      all_one = false
    }
  }
  let misere = if all_one { 1 - normal } else { normal }
  assert_eq(misere, 1)
}
