/// Retrograde Analysis — Backward induction for combinatorial games.
///
/// Retrograde analysis is a technique for solving finite, deterministic,
/// perfect-information games by working *backwards* from terminal positions.
/// It classifies every reachable position as a **Win** (the player to move
/// can force a win), **Loss** (the player to move will lose against optimal
/// play), or **Draw** (neither player can force a win).
///
/// ## Algorithm
///
/// The algorithm is a BFS over the *reverse* game graph:
///
/// 1. **Terminal positions**: positions where no moves are possible are
///    classified as Loss (the player to move has lost) or Win (the player
///    to move has already won, e.g. in misère variants).
/// 2. **Backward propagation**:
///    - A position is a **Win** if *any* successor is a Loss.
///    - A position is a **Loss** if *all* successors are Wins.
///    - A position is a **Draw** if it is neither (e.g., some successor is
///      a Draw, or there is a cycle of undetermined positions).
///
/// We maintain a counter of "losing successors" for each position. When a
/// successor is classified as Loss, the parent gains a winning move. When all
/// successors are classified as Win, the parent is a Loss.
///
/// ## Complexity
///
/// - Time: O(V + E) where V = number of positions, E = number of transitions.
/// - Space: O(V + E) for the reverse adjacency list and counters.
///
/// ## Applications
///
/// - Solving endgame databases (checkers, chess tablebases).
/// - Computing game-theoretic values for small games.
/// - Verifying game-solving results.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Game outcome classification
// ---------------------------------------------------------------------------

///|
/// The game-theoretic value of a position.
pub enum Outcome {
  /// The position has not yet been classified.
  Unknown
  /// The player to move can force a win.
  Win
  /// The player to move will lose against optimal play.
  Lose
  /// Neither player can force a win (draw or infinite play).
  Draw
}

///|
/// Convert outcome to string for display.
pub fn outcome_to_string(o : Outcome) -> String {
  match o {
    Unknown => "Unknown"
    Win => "Win"
    Lose => "Lose"
    Draw => "Draw"
  }
}

///|
/// Check if two outcomes are equal.
pub fn outcome_eq(a : Outcome, b : Outcome) -> Bool {
  match (a, b) {
    (Unknown, Unknown) => true
    (Win, Win) => true
    (Lose, Lose) => true
    (Draw, Draw) => true
    (_, _) => false
  }
}

// ---------------------------------------------------------------------------
// Retrograde analysis solver
// ---------------------------------------------------------------------------

///|
/// Configuration for retrograde analysis.
///
/// The caller provides:
/// - `num_positions`: total number of positions (0 .. num_positions-1).
/// - `get_successors`: function returning the list of positions reachable
///   from a given position in one move.
/// - `is_terminal`: function returning `true` if the position is terminal
///   (no moves possible). Terminal positions are classified as Lose.
/// - `is_winning_terminal`: function returning `true` if the position is a
///   terminal position where the player to move has *won* (e.g. in misère
///   variants or games where reaching a certain state is a win). If this
///   returns `true`, the position is classified as Win instead of Lose.
pub struct RetrogradeConfig {
  num_positions : Int
  get_successors : (Int) -> Array[Int]
  is_terminal : (Int) -> Bool
  is_winning_terminal : (Int) -> Bool
}

///|
/// Run retrograde analysis on a game graph.
///
/// Classifies all positions as Win, Lose, or Draw using backward induction
/// from terminal positions.
///
/// # Parameters
/// - `config`: Game configuration with successor and terminal functions.
///
/// # Returns
/// A `FixedArray[Outcome]` of length `num_positions`, where index `i`
/// contains the classification of position `i`.
///
/// # Algorithm
///
/// 1. Build the reverse adjacency list (predecessors of each position).
/// 2. For each terminal position, classify it as Lose (or Win if
///    `is_winning_terminal` returns true).
/// 3. BFS backwards: when a position is classified as Lose, all its
///    predecessors are Wins (they can move to a losing position).
///    When a position is classified as Win, decrement the "remaining
///    successors" counter for each predecessor; if it reaches zero,
///    the predecessor is a Loss (all successors are Wins).
/// 4. Positions not classified after the BFS are Draws.
pub fn solve(config : RetrogradeConfig) -> FixedArray[Outcome] {
  let n = config.num_positions
  let outcomes = FixedArray::make(n, Unknown)
  if n == 0 {
    return outcomes
  }
  // Build reverse adjacency list and out-degree counter.
  // predecessors[i] = list of positions that can move TO position i.
  let predecessors : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    predecessors.push([])
  }
  // remaining[i] = number of successors not yet classified as Win.
  // A position becomes Lose when remaining reaches 0.
  let remaining = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let succs = (config.get_successors)(i)
    remaining[i] = succs.length()
    for j = 0; j < succs.length(); j = j + 1 {
      let s = succs[j]
      if s >= 0 && s < n {
        predecessors[s].push(i)
      }
    }
  }
  // BFS queue of newly classified positions.
  let queue : Array[Int] = []
  // Classify terminal positions.
  for i = 0; i < n; i = i + 1 {
    if (config.is_terminal)(i) {
      if (config.is_winning_terminal)(i) {
        outcomes[i] = Win
      } else {
        outcomes[i] = Lose
      }
      queue.push(i)
    }
  }
  // Process the queue.
  while queue.length() > 0 {
    let pos = queue[queue.length() - 1]
    ignore(queue.pop()) // Remove last element (used as stack/queue).
    let outcome = outcomes[pos]
    // Propagate to predecessors.
    let preds = predecessors[pos]
    for j = 0; j < preds.length(); j = j + 1 {
      let pred = preds[j]
      // Skip if already classified.
      if outcome_eq(outcomes[pred], Unknown) {
        match outcome {
          Lose => {
            // A successor is a Loss → this position is a Win.
            outcomes[pred] = Win
            queue.push(pred)
          }
          Win => {
            // A successor is a Win → decrement remaining.
            // If all successors are Wins, this position is a Lose.
            remaining[pred] = remaining[pred] - 1
            if remaining[pred] == 0 {
              outcomes[pred] = Lose
              queue.push(pred)
            }
          }
          Draw =>
            // Draw doesn't propagate further in this phase.
            ()
          Unknown =>
            // Shouldn't happen: we only enqueue classified positions.
            ()
        }
      }
    }
  }
  // Positions still Unknown after BFS are Draws (cycles or open-ended).
  for i = 0; i < n; i = i + 1 {
    if outcome_eq(outcomes[i], Unknown) {
      // A position with no successors that wasn't classified as terminal
      // is a Draw (shouldn't normally happen if is_terminal is correct).
      // A position in a cycle with no terminal-reachable path is a Draw.
      outcomes[i] = Draw
    }
  }
  outcomes
}

///|
/// Run retrograde analysis with a simple terminal check: a position is
/// terminal if it has no successors.
///
/// This is a convenience wrapper around [`solve`] for games where terminal
/// positions are exactly those with no legal moves (standard convention).
pub fn solve_simple(
  num_positions : Int,
  get_successors : (Int) -> Array[Int],
) -> FixedArray[Outcome] {
  solve({
    num_positions,
    get_successors,
    is_terminal: fn(pos) {
      let succs = get_successors(pos)
      succs.length() == 0
    },
    is_winning_terminal: fn(_pos) { false },
  })
}

///|
/// Count the number of positions with each outcome.
///
/// Returns `(wins, losses, draws)`.
pub fn count_outcomes(outcomes : FixedArray[Outcome]) -> (Int, Int, Int) {
  let mut wins = 0
  let mut losses = 0
  let mut draws = 0
  for i = 0; i < outcomes.length(); i = i + 1 {
    match outcomes[i] {
      Win => wins = wins + 1
      Lose => losses = losses + 1
      Draw => draws = draws + 1
      Unknown => ()
    }
  }
  (wins, losses, draws)
}

///|
/// Find all positions with a given outcome.
pub fn positions_with_outcome(
  outcomes : FixedArray[Outcome],
  target : Outcome,
) -> Array[Int] {
  let result : Array[Int] = []
  for i = 0; i < outcomes.length(); i = i + 1 {
    if outcome_eq(outcomes[i], target) {
      result.push(i)
    }
  }
  result
}

///|
/// Check if a specific position is a winning position for the player to move.
pub fn is_winning_position(outcomes : FixedArray[Outcome], pos : Int) -> Bool {
  if pos < 0 || pos >= outcomes.length() {
    return false
  }
  outcome_eq(outcomes[pos], Win)
}

// ---------------------------------------------------------------------------
// Application: Subtraction game
// ---------------------------------------------------------------------------

///|
/// Solve a subtraction game by retrograde analysis.
///
/// In a subtraction game, there is a heap of `n` tokens. On each turn, a
/// player removes `s` tokens where `s` is in the allowed set `subtraction_set`.
/// The player who takes the last token wins. The player who cannot move loses.
///
/// # Parameters
/// - `max_heap`: maximum heap size to analyze (positions 0..max_heap).
/// - `subtraction_set`: allowed moves (number of tokens to remove).
///
/// # Returns
/// A `FixedArray[Outcome]` of length `max_heap + 1`.
pub fn solve_subtraction_game(
  max_heap : Int,
  subtraction_set : Array[Int],
) -> FixedArray[Outcome] {
  let n = max_heap + 1
  solve({
    num_positions: n,
    get_successors: fn(pos) {
      let result : Array[Int] = []
      for i = 0; i < subtraction_set.length(); i = i + 1 {
        let s = subtraction_set[i]
        if s > 0 && pos >= s {
          result.push(pos - s)
        }
      }
      result
    },
    is_terminal: fn(pos) { pos == 0 },
    is_winning_terminal: fn(_pos) { false },
  })
}

///|
/// Solve a subtraction game using the Sprague-Grundy theorem.
///
/// Returns the Grundy number for each heap size 0..max_heap.
/// This serves as a cross-check for the retrograde analysis.
pub fn subtraction_game_grundy(
  max_heap : Int,
  subtraction_set : Array[Int],
) -> FixedArray[Int] {
  let n = max_heap + 1
  let grundy = FixedArray::make(n, 0)
  // Grundy(0) = 0 (terminal, no moves).
  grundy[0] = 0
  for pos = 1; pos < n; pos = pos + 1 {
    // Collect Grundy values of successors.
    let reachable : Array[Int] = []
    for i = 0; i < subtraction_set.length(); i = i + 1 {
      let s = subtraction_set[i]
      if s > 0 && pos >= s {
        reachable.push(grundy[pos - s])
      }
    }
    // mex (minimum excludant).
    grundy[pos] = mex(reachable)
  }
  grundy
}

///|
/// Compute the mex (minimum excludant) of a set of non-negative integers.
///
/// The mex is the smallest non-negative integer not in the set.
fn mex(values : Array[Int]) -> Int {
  // For small sets, just check 0, 1, 2, ... until we find one not in the set.
  let mut candidate = 0
  let mut found = true
  while found {
    found = false
    for i = 0; i < values.length(); i = i + 1 {
      if values[i] == candidate {
        found = true
        break
      }
    }
    if found {
      candidate = candidate + 1
    }
  }
  candidate
}

// ---------------------------------------------------------------------------
// Application: Nim positions
// ---------------------------------------------------------------------------

///|
/// Solve a 2-pile Nim game by retrograde analysis.
///
/// Positions are encoded as (a, b) where a, b are pile sizes.
/// Position index = a * (max_size + 1) + b.
///
/// # Parameters
/// - `max_size`: maximum pile size.
///
/// # Returns
/// A `FixedArray[Outcome]` of length `(max_size + 1)²`.
pub fn solve_nim_2pile(max_size : Int) -> FixedArray[Outcome] {
  let dim = max_size + 1
  let n = dim * dim
  solve({
    num_positions: n,
    get_successors: fn(pos) {
      let a = pos / dim
      let b = pos % dim
      let result : Array[Int] = []
      // Remove from pile a: (a-s, b) for s = 1..a.
      for s = 1; s <= a; s = s + 1 {
        result.push((a - s) * dim + b)
      }
      // Remove from pile b: (a, b-s) for s = 1..b.
      for s = 1; s <= b; s = s + 1 {
        result.push(a * dim + (b - s))
      }
      result
    },
    is_terminal: fn(pos) { pos == 0 },
    is_winning_terminal: fn(_pos) { false },
  })
}

// ---------------------------------------------------------------------------
// Application: Grid path game (simple DAG game)
// ---------------------------------------------------------------------------

///|
/// Solve a simple grid game where two players alternate moving a token
/// on an H×W grid. On each turn, the token moves right or down by one cell.
/// The player who reaches the bottom-right corner wins.
///
/// Position index = row * W + col.
///
/// # Parameters
/// - `height`: grid height (rows).
/// - `width`: grid width (columns).
///
/// # Returns
/// A `FixedArray[Outcome]` of length `height * width`.
pub fn solve_grid_game(height : Int, width : Int) -> FixedArray[Outcome] {
  let n = height * width
  let target = n - 1 // Bottom-right corner.
  solve({
    num_positions: n,
    get_successors: fn(pos) {
      let row = pos / width
      let col = pos % width
      let result : Array[Int] = []
      // Move right.
      if col + 1 < width {
        result.push(pos + 1)
      }
      // Move down.
      if row + 1 < height {
        result.push(pos + width)
      }
      result
    },
    is_terminal: fn(pos) { pos == target },
    is_winning_terminal: fn(_pos) { true }, // Reaching target = win.
  })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "outcome: equality" {
  assert_true(outcome_eq(Win, Win))
  assert_true(outcome_eq(Lose, Lose))
  assert_true(outcome_eq(Draw, Draw))
  assert_true(outcome_eq(Unknown, Unknown))
  assert_false(outcome_eq(Win, Lose))
  assert_false(outcome_eq(Draw, Win))
  assert_false(outcome_eq(Unknown, Win))
}

///|
test "outcome: to_string" {
  assert_eq(outcome_to_string(Win), "Win")
  assert_eq(outcome_to_string(Lose), "Lose")
  assert_eq(outcome_to_string(Draw), "Draw")
  assert_eq(outcome_to_string(Unknown), "Unknown")
}

///|
test "solve: trivial single terminal position" {
  // Single position, no successors → terminal → Lose.
  let result = solve_simple(1, fn(_pos) { [] })
  assert_true(outcome_eq(result[0], Lose))
}

///|
test "solve: position with one move to terminal" {
  // Position 0 is terminal (Lose). Position 1 can move to 0 → Win.
  let result = solve_simple(2, fn(pos) {
    match pos {
      0 => []
      _ => [0]
    }
  })
  assert_true(outcome_eq(result[0], Lose))
  assert_true(outcome_eq(result[1], Win))
}

///|
test "solve: chain of positions" {
  // Chain: 3 → 2 → 1 → 0 (terminal)
  // 0: Lose (terminal)
  // 1: Win (can move to Lose)
  // 2: Lose (only move is to Win)
  // 3: Win (can move to Lose)
  let result = solve_simple(4, fn(pos) {
    match pos {
      0 => []
      i => [i - 1]
    }
  })
  assert_true(outcome_eq(result[0], Lose))
  assert_true(outcome_eq(result[1], Win))
  assert_true(outcome_eq(result[2], Lose))
  assert_true(outcome_eq(result[3], Win))
}

///|
test "solve: position with two moves, one to terminal" {
  // Position 0: terminal (Lose)
  // Position 1: terminal (Lose)
  // Position 2: can move to 0 or 1 → Win (has a move to Lose)
  let result = solve_simple(3, fn(pos) {
    match pos {
      0 => []
      1 => []
      _ => [0, 1]
    }
  })
  assert_true(outcome_eq(result[0], Lose))
  assert_true(outcome_eq(result[1], Lose))
  assert_true(outcome_eq(result[2], Win))
}

///|
test "solve: position where all moves lead to Win → Lose" {
  // Position 0: terminal (Lose)
  // Position 1: can move to 0 → Win
  // Position 2: can only move to 1 → Lose (all successors are Win)
  // Position 3: can move to 2 → Win
  let result = solve_simple(4, fn(pos) {
    match pos {
      0 => []
      1 => [0]
      2 => [1]
      _ => [2]
    }
  })
  assert_true(outcome_eq(result[0], Lose))
  assert_true(outcome_eq(result[1], Win))
  assert_true(outcome_eq(result[2], Lose))
  assert_true(outcome_eq(result[3], Win))
}

///|
test "solve: cycle results in Draw" {
  // Two positions that can only move to each other (cycle, no terminal).
  // Both should be Draw.
  let result = solve_simple(2, fn(pos) {
    match pos {
      0 => [1]
      _ => [0]
    }
  })
  assert_true(outcome_eq(result[0], Draw))
  assert_true(outcome_eq(result[1], Draw))
}

///|
test "solve: winning terminal (misère-like)" {
  // Position 0: terminal and winning (reaching it = win).
  // Position 1: can move to 0 → since 0 is Win, 1's successor is Win.
  //   Position 1 has only one successor (Win) → 1 is Lose.
  // Position 2: can move to 1 (Lose) → Win.
  let result = solve({
    num_positions: 3,
    get_successors: fn(pos) {
      match pos {
        0 => []
        i => [i - 1]
      }
    },
    is_terminal: fn(pos) { pos == 0 },
    is_winning_terminal: fn(_pos) { true },
  })
  assert_true(outcome_eq(result[0], Win))
  assert_true(outcome_eq(result[1], Lose))
  assert_true(outcome_eq(result[2], Win))
}

///|
test "solve: empty game" {
  let result = solve_simple(0, fn(_pos) { [] })
  assert_eq(result.length(), 0)
}

///|
test "solve: branching game" {
  // Tree:
  //       4
  //      / \
  //     2   3
  //    / \   \
  //   0   1   1
  //  0,1: terminal (Lose)
  //  2: successors [0(Lose), 1(Lose)] → Win
  //  3: successors [1(Lose)] → Win
  //  4: successors [2(Win), 3(Win)] → Lose (all successors Win)
  let result = solve_simple(5, fn(pos) {
    match pos {
      0 => []
      1 => []
      2 => [0, 1]
      3 => [1]
      _ => [2, 3]
    }
  })
  assert_true(outcome_eq(result[0], Lose))
  assert_true(outcome_eq(result[1], Lose))
  assert_true(outcome_eq(result[2], Win))
  assert_true(outcome_eq(result[3], Win))
  assert_true(outcome_eq(result[4], Lose))
}

///|
test "count_outcomes: basic" {
  let outcomes = FixedArray::make(5, Unknown)
  outcomes[0] = Win
  outcomes[1] = Lose
  outcomes[2] = Win
  outcomes[3] = Draw
  outcomes[4] = Win
  let (w, l, d) = count_outcomes(outcomes)
  assert_eq(w, 3)
  assert_eq(l, 1)
  assert_eq(d, 1)
}

///|
test "positions_with_outcome: find all wins" {
  let outcomes = FixedArray::make(5, Unknown)
  outcomes[0] = Win
  outcomes[1] = Lose
  outcomes[2] = Win
  outcomes[3] = Draw
  outcomes[4] = Lose
  let wins = positions_with_outcome(outcomes, Win)
  assert_eq(wins.length(), 2)
  assert_eq(wins[0], 0)
  assert_eq(wins[1], 2)
}

///|
test "is_winning_position: basic checks" {
  let outcomes = FixedArray::make(3, Unknown)
  outcomes[0] = Win
  outcomes[1] = Lose
  outcomes[2] = Draw
  assert_true(is_winning_position(outcomes, 0))
  assert_false(is_winning_position(outcomes, 1))
  assert_false(is_winning_position(outcomes, 2))
  assert_false(is_winning_position(outcomes, 99))
  assert_false(is_winning_position(outcomes, -1))
}

///|
test "subtraction_game: S={1,2} alternating" {
  // With S={1,2}, the pattern alternates: 0=Lose, 1=Win, 2=Win, 3=Lose, ...
  let result = solve_subtraction_game(10, [1, 2])
  // Position 0: terminal, Lose.
  assert_true(outcome_eq(result[0], Lose))
  // Position 1: can take 1 → Lose → Win.
  assert_true(outcome_eq(result[1], Win))
  // Position 2: can take 2 → Lose → Win.
  assert_true(outcome_eq(result[2], Win))
  // Position 3: can take 1→Win or 2→Win → all Win → Lose.
  assert_true(outcome_eq(result[3], Lose))
  // Position 4: can take 1→Lose → Win.
  assert_true(outcome_eq(result[4], Win))
  // Position 6: Lose (pattern: multiples of 3 are Lose).
  assert_true(outcome_eq(result[6], Lose))
}

///|
test "subtraction_game: S={1,3} pattern" {
  // With S={1,3}: 0=Lose, 1=Win, 2=Lose, 3=Win, 4=Win, 5=Lose, ...
  let result = solve_subtraction_game(10, [1, 3])
  assert_true(outcome_eq(result[0], Lose))
  assert_true(outcome_eq(result[1], Win)) // take 1 → Lose
  assert_true(outcome_eq(result[2], Lose)) // take 1→Win, no 3 → all Win
  assert_true(outcome_eq(result[3], Win)) // take 3 → Lose
  // pos 4: take 1→3(Win), take 3→1(Win) → all Win → Lose
  assert_true(outcome_eq(result[4], Lose))
  // pos 5: take 1→4(Lose) → Win
  assert_true(outcome_eq(result[5], Win))
}

///|
test "subtraction_game: grundy cross-check S={1,2}" {
  // Grundy(0)=0 (Lose), Grundy(1)=mex{0}=1 (Win),
  // Grundy(2)=mex{1,0}=2 (Win), Grundy(3)=mex{2,1}=0 (Lose).
  let grundy = subtraction_game_grundy(10, [1, 2])
  assert_eq(grundy[0], 0)
  assert_eq(grundy[1], 1)
  assert_eq(grundy[2], 2)
  assert_eq(grundy[3], 0)
  assert_eq(grundy[4], 1)
  assert_eq(grundy[5], 2)
  assert_eq(grundy[6], 0)
  // Cross-check: Grundy=0 means Lose, Grundy≠0 means Win.
  let outcomes = solve_subtraction_game(10, [1, 2])
  for i = 0; i <= 10; i = i + 1 {
    if grundy[i] == 0 {
      assert_true(outcome_eq(outcomes[i], Lose))
    } else {
      assert_true(outcome_eq(outcomes[i], Win))
    }
  }
}

///|
test "nim_2pile: known values" {
  // In 2-pile Nim, (a,b) is Lose iff a == b (Nim-sum = 0).
  let result = solve_nim_2pile(5)
  let dim = 6
  // (0,0): Lose (terminal).
  assert_true(outcome_eq(result[0 * dim + 0], Lose))
  // (1,0): Win (take 1 from pile 1 → (0,0) Lose).
  assert_true(outcome_eq(result[1 * dim + 0], Win))
  // (1,1): Lose (Nim-sum = 0).
  assert_true(outcome_eq(result[1 * dim + 1], Lose))
  // (2,3): Win (Nim-sum ≠ 0).
  assert_true(outcome_eq(result[2 * dim + 3], Win))
  // (3,3): Lose (Nim-sum = 0).
  assert_true(outcome_eq(result[3 * dim + 3], Lose))
  // (5,5): Lose.
  assert_true(outcome_eq(result[5 * dim + 5], Lose))
  // (5,3): Win.
  assert_true(outcome_eq(result[5 * dim + 3], Win))
}

///|
test "nim_2pile: all Lose positions are diagonal" {
  let max_size = 8
  let result = solve_nim_2pile(max_size)
  let dim = max_size + 1
  for a = 0; a <= max_size; a = a + 1 {
    for b = 0; b <= max_size; b = b + 1 {
      if a == b {
        assert_true(outcome_eq(result[a * dim + b], Lose))
      } else {
        assert_true(outcome_eq(result[a * dim + b], Win))
      }
    }
  }
}

///|
test "grid_game: 1x1 grid" {
  // Single cell: target reached → Win.
  let result = solve_grid_game(1, 1)
  assert_true(outcome_eq(result[0], Win))
}

///|
test "grid_game: 2x2 grid" {
  // Positions: 0=(0,0), 1=(0,1), 2=(1,0), 3=(1,1)=target.
  // 3: terminal, Win.
  // 1: can move to 3(Win) → all successors Win → Lose.
  // 2: can move to 3(Win) → all successors Win → Lose.
  // 0: can move to 1(Lose) or 2(Lose) → Win.
  let result = solve_grid_game(2, 2)
  assert_true(outcome_eq(result[3], Win)) // target
  assert_true(outcome_eq(result[1], Lose)) // (0,1) → only to 3(Win)
  assert_true(outcome_eq(result[2], Lose)) // (1,0) → only to 3(Win)
  assert_true(outcome_eq(result[0], Win)) // (0,0) → to 1(Lose) or 2(Lose)
}

///|
test "grid_game: 3x3 grid" {
  // Position (2,2)=8 is target (Win).
  // (1,2)=7 and (2,1)=5: only move to 8(Win) → Lose.
  // (0,2)=2: move to 5(Lose) → Win. (also right is invalid)
  // Wait: (0,2): row=0, col=2. Right: col+1=3 >= 3, invalid.
  // Down: row+1=1 < 3, so move to (1,2)=5.
  // (1,2)=7 → down to (2,2)=8(Win), right invalid → all Win → Lose.
  // (0,2)=2 → down to (1,2)=7(Lose) → Win.
  // (2,0)=6: right to (2,1)=5(Lose) → Win. Down invalid.
  // (2,1)=5: right to (2,2)=8(Win), down invalid → Lose.
  // (1,1)=4: right to (1,2)=7(Lose) → Win, down to (2,1)=5(Lose) → Win.
  //   Has a successor that is Lose → Win.
  // (0,1)=1: right to (0,2)=2(Win), down to (1,1)=4(Win) → all Win → Lose.
  // (1,0)=3: right to (1,1)=4(Win), down to (2,0)=6(Win) → all Win → Lose.
  // (0,0)=0: right to (0,1)=1(Lose) → Win, down to (1,0)=3(Lose) → Win → Win.
  let result = solve_grid_game(3, 3)
  assert_true(outcome_eq(result[8], Win)) // (2,2) target
  assert_true(outcome_eq(result[7], Lose)) // (1,2)
  assert_true(outcome_eq(result[5], Lose)) // (2,1)
  assert_true(outcome_eq(result[2], Win)) // (0,2)
  assert_true(outcome_eq(result[6], Win)) // (2,0)
  assert_true(outcome_eq(result[4], Win)) // (1,1)
  assert_true(outcome_eq(result[1], Lose)) // (0,1)
  assert_true(outcome_eq(result[3], Lose)) // (1,0)
  assert_true(outcome_eq(result[0], Win)) // (0,0)
}

///|
test "mex: basic values" {
  assert_eq(mex([]), 0)
  assert_eq(mex([0]), 1)
  assert_eq(mex([1]), 0)
  assert_eq(mex([0, 1]), 2)
  assert_eq(mex([0, 2]), 1)
  assert_eq(mex([1, 2]), 0)
  assert_eq(mex([0, 1, 2, 3]), 4)
  assert_eq(mex([0, 1, 3, 4]), 2)
}

///|
test "solve: position with Draw successor" {
  // Position 0: terminal (Lose)
  // Position 1: cycle with 2 (both Draw)
  // Position 3: can move to 0(Lose) → Win, or to 1(Draw)
  // Position 3 has a move to Lose → Win.
  let result = solve({
    num_positions: 4,
    get_successors: fn(pos) {
      match pos {
        0 => []
        1 => [2]
        2 => [1]
        _ => [0, 1]
      }
    },
    is_terminal: fn(pos) { pos == 0 },
    is_winning_terminal: fn(_pos) { false },
  })
  assert_true(outcome_eq(result[0], Lose))
  assert_true(outcome_eq(result[1], Draw))
  assert_true(outcome_eq(result[2], Draw))
  assert_true(outcome_eq(result[3], Win))
}

///|
test "solve: all draws (no terminal)" {
  // Three positions in a cycle with no terminal.
  let result = solve_simple(3, fn(pos) {
    match pos {
      0 => [1]
      1 => [2]
      _ => [0]
    }
  })
  assert_true(outcome_eq(result[0], Draw))
  assert_true(outcome_eq(result[1], Draw))
  assert_true(outcome_eq(result[2], Draw))
}
