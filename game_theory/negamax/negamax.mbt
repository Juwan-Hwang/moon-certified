/// Negamax search with Alpha-Beta pruning.
///
/// Negamax is a variant of minimax that relies on the zero-sum property:
/// the value of a position to one player is the negative of the value
/// to the opponent. Alpha-beta pruning eliminates branches that cannot
/// affect the final decision.
///
/// ## Performance
///
/// - Without pruning: O(b^d) where b = branching factor, d = depth
/// - With alpha-beta: O(b^(d/2)) best case
///
/// ## References
///
/// - Knuth, D.E. and Moore, R.W. "An Analysis of Alpha-Beta Pruning."
///   Artificial Intelligence, 1975.
///
/// `proof-enabled` is `false`.

///|
/// A game state interface that the negamax algorithm operates on.
/// Users implement this trait for their specific game.
pub trait Game {
  /// Get all legal moves from the current state.
  fn legal_moves(Self) -> Array[Int]

  /// Apply a move and return the new state.
  fn make_move(Self, Int) -> Self

  /// Evaluate the position from the perspective of the player to move.
  /// Positive = good for current player, negative = bad.
  fn evaluate(Self) -> Double

  /// Check if the game is over (terminal state).
  fn is_terminal(Self) -> Bool
}

///|
/// Result of a negamax search.
pub struct SearchResult {
  best_move : Int?
  score : Double
}

///|
/// Negamax search with alpha-beta pruning.
///
/// `depth`: maximum search depth (0 = evaluate immediately)
/// `alpha`: best value for maximizing player (initial: -infinity)
/// `beta`: best value for minimizing player (initial: +infinity)
pub fn[G : Game] negamax(
  state : G,
  depth : Int,
  alpha : Double,
  beta : Double,
) -> SearchResult {
  if depth == 0 || state.is_terminal() {
    return { best_move: None, score: state.evaluate(), }
  }
  let moves = state.legal_moves()
  if moves.length() == 0 {
    return { best_move: None, score: state.evaluate(), }
  }
  let mut best_score = -1.0e18
  let mut best_move : Int? = None
  let mut a = alpha
  for i = 0; i < moves.length(); i = i + 1 {
    let child = state.make_move(moves[i])
    // Negate the score (zero-sum: opponent's gain is our loss)
    let result = negamax(child, depth - 1, -beta, -a)
    let score = -result.score
    if score > best_score {
      best_score = score
      best_move = Some(moves[i])
    }
    if score > a {
      a = score
    }
    if a >= beta {
      break // Beta cutoff
    }
  }
  { best_move, score: best_score, }
}

///|
/// Find the best move using negamax with alpha-beta pruning.
pub fn[G : Game] find_best_move(state : G, depth : Int) -> Int? {
  let result = negamax(state, depth, -1.0e18, 1.0e18)
  result.best_move
}

// ---------------------------------------------------------------------------
// Simple Tic-Tac-Toe for testing
// ---------------------------------------------------------------------------

///|
/// A simple Tic-Tac-Toe game state for testing.
priv struct TTTState {
  board : Array[Int] // 0=empty, 1=X, -1=O
  player : Int // 1 or -1
}

///|
impl Game for TTTState with fn legal_moves(self : TTTState) -> Array[Int] {
  let moves : Array[Int] = []
  for i = 0; i < 9; i = i + 1 {
    if self.board[i] == 0 {
      moves.push(i)
    }
  }
  moves
}

///|
impl Game for TTTState with fn make_move(self : TTTState, mv : Int) -> TTTState {
  let new_board = Array::make(9, 0)
  for i = 0; i < 9; i = i + 1 {
    new_board[i] = self.board[i]
  }
  new_board[mv] = self.player
  { board: new_board, player: -self.player, }
}

///|
impl Game for TTTState with fn evaluate(self : TTTState) -> Double {
  // Check all winning lines
  let lines = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8], // rows
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8], // cols
    [0, 4, 8],
    [2, 4, 6], // diagonals
  ]
  for i = 0; i < lines.length(); i = i + 1 {
    let s = self.board[lines[i][0]] +
      self.board[lines[i][1]] +
      self.board[lines[i][2]]
    if s == 3 || s == -3 {
      // Winner = s/3 (1 for X, -1 for O).
      // Negamax requires evaluation from the perspective of the player to move.
      let winner = s / 3
      return (winner * self.player).to_double() * 100.0
    }
  }
  0.0
}

///|
impl Game for TTTState with fn is_terminal(self : TTTState) -> Bool {
  // Check for win
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
    let s = self.board[lines[i][0]] +
      self.board[lines[i][1]] +
      self.board[lines[i][2]]
    if s == 3 || s == -3 {
      return true
    }
  }
  // Check for draw
  for i = 0; i < 9; i = i + 1 {
    if self.board[i] == 0 {
      return false
    }
  }
  true
}

///|
test "negamax: finds winning move" {
  // X can win by placing at position 2 (top row: X X _)
  let state : TTTState = { board: [1, 1, 0, -1, -1, 0, 0, 0, 0], player: 1, }
  let mv = find_best_move(state, 5)
  match mv {
    Some(m) => assert_eq(m, 2)
    None => assert_true(false)
  }
}

///|
test "negamax: blocks opponent win" {
  // O threatens to win at position 5 (row 1: O O _); X must block
  // X at position 0 prevents O from creating a fork via the center
  let state : TTTState = { board: [1, 0, 0, -1, -1, 0, 0, 0, 0], player: 1, }
  let mv = find_best_move(state, 5)
  match mv {
    Some(m) => assert_eq(m, 5) // Block the row
    None => assert_true(false)
  }
}

///|
test "negamax: empty board returns a move" {
  let state : TTTState = { board: [0, 0, 0, 0, 0, 0, 0, 0, 0], player: 1, }
  let mv = find_best_move(state, 3)
  match mv {
    Some(_) => assert_true(true)
    None => assert_true(false)
  }
}
