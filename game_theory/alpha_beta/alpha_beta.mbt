/// Alpha-Beta Pruning / Negamax — game tree search.
///
/// Alpha-beta pruning is the standard algorithm for two-player zero-sum
/// games (chess, checkers, Othello, Go). It is an optimization of minimax
/// that prunes branches which cannot influence the final decision, often
/// reducing the branching factor from b to √b in the best case.
///
/// ## Algorithm
///
/// Negamax formulation: at each node, the value is the negative of the
/// opponent's best value. Alpha (α) is the best value the maximizer can
/// guarantee; Beta (β) is the best value the minimizer can guarantee.
/// When α ≥ β, the branch is pruned.
///
/// ## Complexity
/// - Time:  O(b^d) worst, O(b^(d/2)) best with perfect move ordering.
/// - Space: O(d) for recursion.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A game state interface for alpha-beta search.
///
/// Marked `pub(open)` so that downstream users can implement it for their
/// own game states.
pub(open) trait Game {
  fn is_terminal(Self) -> Bool
  fn evaluate(Self) -> Int
  fn generate_moves(Self) -> Array[Int]
  fn make_move(Self, Int) -> Self
  fn current_player(Self) -> Int
}

///|
/// Alpha-beta pruning search (negamax formulation).
///
/// Returns the best value from the current player's perspective.
/// `alpha` = lower bound, `beta` = upper bound.
pub fn[T : Game] alpha_beta(
  state : T,
  depth : Int,
  alpha : Int,
  beta : Int,
) -> Int {
  if depth == 0 || state.is_terminal() {
    let v = state.evaluate()
    // Prefer sooner wins / later losses by adding depth bonus.
    if v > 0 {
      return v + depth
    }
    if v < 0 {
      return v - depth
    }
    return 0
  }
  let moves = state.generate_moves()
  if moves.length() == 0 {
    return state.evaluate()
  }
  let mut best = -2147483647
  let mut a = alpha
  for i = 0; i < moves.length(); i = i + 1 {
    let child = state.make_move(moves[i])
    let val = -alpha_beta(child, depth - 1, -beta, -a)
    if val > best {
      best = val
    }
    if best > a {
      a = best
    }
    if best >= beta {
      break
    }
  }
  best
}

///|
/// Find the best move using alpha-beta search.
///
/// Returns the move index that maximizes the current player's value.
pub fn[T : Game] best_move(state : T, depth : Int) -> Int {
  let moves = state.generate_moves()
  if moves.length() == 0 {
    return -1
  }
  let mut best_val = -2147483647
  let mut best_idx = 0
  let mut alpha = -2147483647
  let beta = 2147483647
  for i = 0; i < moves.length(); i = i + 1 {
    let child = state.make_move(moves[i])
    let val = -alpha_beta(child, depth - 1, -beta, -alpha)
    if val > best_val {
      best_val = val
      best_idx = i
    }
    if best_val > alpha {
      alpha = best_val
    }
  }
  moves[best_idx]
}

///|
/// Negamax search without pruning (for comparison/testing).
pub fn[T : Game] negamax(state : T, depth : Int) -> Int {
  if depth == 0 || state.is_terminal() {
    let v = state.evaluate()
    if v > 0 {
      return v + depth
    }
    if v < 0 {
      return v - depth
    }
    return 0
  }
  let moves = state.generate_moves()
  if moves.length() == 0 {
    return state.evaluate()
  }
  let mut best = -2147483647
  for i = 0; i < moves.length(); i = i + 1 {
    let child = state.make_move(moves[i])
    let val = -negamax(child, depth - 1)
    if val > best {
      best = val
    }
  }
  best
}

// ---------------------------------------------------------------------------
// Tic-Tac-Toe test implementation
// ---------------------------------------------------------------------------

///|
priv struct TicTacToe {
  board : FixedArray[Int] // 0=empty, 1=X, -1=O
  mut player : Int // 1 or -1
}

///|
fn TicTacToe::new() -> TicTacToe {
  { board: FixedArray::make(9, 0), player: 1, }
}

///|
fn TicTacToe::clone(self : TicTacToe) -> TicTacToe {
  let b = FixedArray::make(9, 0)
  for i = 0; i < 9; i = i + 1 {
    b[i] = self.board[i]
  }
  { board: b, player: self.player, }
}

///|
fn check_win(board : FixedArray[Int]) -> Int {
  let lines = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ]
  for i = 0; i < lines.length(); i = i + 1 {
    let a = lines[i][0]
    let b = lines[i][1]
    let c = lines[i][2]
    if board[a] != 0 && board[a] == board[b] && board[a] == board[c] {
      return board[a]
    }
  }
  0
}

///|
impl Game for TicTacToe with fn is_terminal(self) {
  if check_win(self.board) != 0 {
    return true
  }
  for i = 0; i < 9; i = i + 1 {
    if self.board[i] == 0 {
      return false
    }
  }
  true
}

///|
impl Game for TicTacToe with fn evaluate(self) {
  let w = check_win(self.board)
  if w != 0 {
    return w * self.player * 1000
  }
  // Check for draw (board full, no winner).
  let mut has_empty = false
  for i = 0; i < 9; i = i + 1 {
    if self.board[i] == 0 {
      has_empty = true
      break
    }
  }
  if !has_empty {
    return 0 // Draw
  }
  // Heuristic: center > corners > edges.
  let mut score = 0
  if self.board[4] == self.player {
    score = score + 3
  } else if self.board[4] == -self.player {
    score = score - 3
  }
  let corners = [0, 2, 6, 8]
  for i = 0; i < 4; i = i + 1 {
    if self.board[corners[i]] == self.player {
      score = score + 1
    } else if self.board[corners[i]] == -self.player {
      score = score - 1
    }
  }
  score
}

///|
impl Game for TicTacToe with fn generate_moves(self) {
  let moves : Array[Int] = []
  for i = 0; i < 9; i = i + 1 {
    if self.board[i] == 0 {
      moves.push(i)
    }
  }
  moves
}

///|
impl Game for TicTacToe with fn make_move(self, mv) {
  let next = self.clone()
  next.board[mv] = self.player
  next.player = -self.player
  next
}

///|
impl Game for TicTacToe with fn current_player(self) {
  self.player
}

///|
extend TicTacToe with Game::{make_move, is_terminal, evaluate}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "alpha_beta: tic-tac-toe win detection" {
  let g = TicTacToe::new()
  assert_false(g.is_terminal())
  let g1 = g.make_move(4)
  let g2 = g1.make_move(0)
  let g3 = g2.make_move(8)
  assert_false(g3.is_terminal())
}

///|
test "alpha_beta: alpha-beta finds winning move" {
  let g = TicTacToe::new()
  let g1 = g.make_move(0)
  let g2 = g1.make_move(1)
  let g3 = g2.make_move(4)
  let g4 = g3.make_move(2)
  let m = best_move(g4, 5)
  assert_eq(m, 8)
}

///|
test "alpha_beta: blocks opponent win" {
  let g = TicTacToe::new()
  let g1 = g.make_move(4) // X center
  let g2 = g1.make_move(0) // O corner
  let g3 = g2.make_move(8) // X corner (0-4-8 diagonal, but 0 is taken by O)
  let g4 = g3.make_move(1) // O edge — O threatens 0-1-2
  let m = best_move(g4, 5)
  assert_eq(m, 2)
}

///|
test "alpha_beta: alpha-beta equals negamax" {
  let g = TicTacToe::new()
  let g1 = g.make_move(4)
  let g2 = g1.make_move(0)
  let ab = alpha_beta(g2, 5, -2147483647, 2147483647)
  let nm = negamax(g2, 5)
  assert_eq(ab, nm)
}

///|
test "alpha_beta: terminal draw" {
  let g = TicTacToe::new()
  let g1 = g.make_move(0) // X
  let g2 = g1.make_move(1) // O
  let g3 = g2.make_move(2) // X
  let g4 = g3.make_move(4) // O
  let g5 = g4.make_move(3) // X
  let g6 = g5.make_move(5) // O
  let g7 = g6.make_move(7) // X
  let g8 = g7.make_move(6) // O
  let g9 = g8.make_move(8) // X
  // Board: X O X / X O O / O X X — no winner, full board.
  assert_true(g9.is_terminal())
  assert_eq(g9.evaluate(), 0)
}

///|
test "alpha_beta: center is best opening" {
  let g = TicTacToe::new()
  // With depth 3, heuristic evaluation differentiates center (val 3)
  // from corner (val -1 when opponent takes center).
  let m = best_move(g, 3)
  assert_eq(m, 4)
}
