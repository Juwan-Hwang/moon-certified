/// Monte Carlo Tree Search (MCTS) — UCT algorithm.
///
/// MCTS is a heuristic search algorithm for decision processes, most
/// notably used in game playing (Go, Othello, Hex). Unlike alpha-beta
/// which requires an evaluation function, MCTS uses random rollouts to
/// estimate position value.
///
/// ## Algorithm
///
/// 1. **Selection**: Traverse the tree using UCT (Upper Confidence bound
///    for Trees) to balance exploration vs exploitation.
/// 2. **Expansion**: Add a new child node.
/// 3. **Simulation**: Run a random playout from the new node.
/// 4. **Backpropagation**: Update visit counts and win counts along
///    the path to the root.
///
/// ## Complexity
/// - Time:  O(iterations × rollout_length).
/// - Space: O(iterations) for the tree.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A node in the MCTS search tree.
priv struct MCTSNode {
  move_val : Int
  parent : Int
  children : Array[Int]
  mut visits : Int
  mut wins : Double
  untried_moves : Array[Int]
  player_just_moved : Int
}

///|
/// A game state interface for MCTS.
pub trait GameState {
  fn is_terminal(Self) -> Bool
  fn get_moves(Self) -> Array[Int]
  fn make_move(Self, Int) -> Self
  fn get_result(Self, Int) -> Double
  fn random_playout(Self, () -> Int) -> Double
  fn current_player(Self) -> Int
}

///|
/// MCTS search engine.
pub struct MCTS {
  priv nodes : Array[MCTSNode]
  priv mut rng_state : Int64
}

///|
/// Create a new MCTS engine.
pub fn new(seed : Int) -> MCTS {
  // Use SplitMix64 to initialize — higher quality than LCG.
  { nodes: [], rng_state: Int64::from_int(seed) }
}

///|
/// SplitMix64 PRNG — delegates to @utils.splitmix64_next to avoid code
/// duplication. Produces uniformly distributed values with good statistical
/// properties.
fn MCTS::rng(self : MCTS) -> Int {
  let (new_state, z) = @utils.splitmix64_next(self.rng_state)
  self.rng_state = new_state
  // Map to non-negative Int (truncate to 31 bits for portability).
  (z & 0x7FFFFFFFL).to_int()
}

///|
/// UCT selection: pick child maximizing UCB1 value.
fn MCTS::uct_select(self : MCTS, node_idx : Int) -> Int {
  let parent_visits = self.nodes[node_idx].visits
  let mut best_idx = -1
  let mut best_val = -1.0e18
  let children = self.nodes[node_idx].children
  for i = 0; i < children.length(); i = i + 1 {
    let child = self.nodes[children[i]]
    let val = if child.visits == 0 {
      1.0e18
    } else {
      let exploit = child.wins / child.visits.to_double()
      let explore = 2.0 *
        (@math.ln(parent_visits.to_double()) / child.visits.to_double()).sqrt()
      exploit + explore
    }
    if val > best_val {
      best_val = val
      best_idx = children[i]
    }
  }
  best_idx
}

///|
fn MCTS::add_node(
  self : MCTS,
  move_val : Int,
  parent : Int,
  player : Int,
  untried : Array[Int],
) -> Int {
  let idx = self.nodes.length()
  self.nodes.push({
    move_val,
    parent,
    children: [],
    visits: 0,
    wins: 0.0,
    untried_moves: untried,
    player_just_moved: player,
  })
  if parent >= 0 {
    self.nodes[parent].children.push(idx)
  }
  idx
}

///|
/// Run one MCTS iteration from the root state.
fn[T : GameState] MCTS::iterate(
  self : MCTS,
  root_state : T,
  root_idx : Int,
) -> Unit {
  // Phase 1: Selection — traverse tree using UCT.
  let mut state = root_state
  let mut node_idx = root_idx
  while self.nodes[node_idx].untried_moves.length() == 0 &&
        self.nodes[node_idx].children.length() > 0 {
    if state.is_terminal() {
      break
    }
    node_idx = self.uct_select(node_idx)
    state = state.make_move(self.nodes[node_idx].move_val)
  }
  // Phase 2: Expansion — add one child for an untried move.
  if !state.is_terminal() && self.nodes[node_idx].untried_moves.length() > 0 {
    let moves = self.nodes[node_idx].untried_moves
    let pick_idx = self.rng() % moves.length()
    let move_val = moves[pick_idx]
    moves.remove(pick_idx) |> ignore
    state = state.make_move(move_val)
    let child_moves = state.get_moves()
    let player = -state.current_player() // The player who just moved
    node_idx = self.add_node(move_val, node_idx, player, child_moves)
  }
  // Phase 3: Simulation — random playout.
  // random_playout returns result from the perspective of the player about
  // to move (opponent of player_just_moved), so flip it.
  let result = if state.is_terminal() {
    state.get_result(self.nodes[node_idx].player_just_moved)
  } else {
    1.0 - state.random_playout(fn() { self.rng() })
  }
  // Phase 4: Backpropagation — flip result for alternating players.
  let mut idx = node_idx
  let mut r = result
  while idx >= 0 {
    self.nodes[idx].visits = self.nodes[idx].visits + 1
    self.nodes[idx].wins = self.nodes[idx].wins + r
    r = 1.0 - r // Opponent's perspective
    idx = self.nodes[idx].parent
  }
}

///|
/// Search for the best move.
///
/// Runs `iterations` MCTS iterations from `root_state`, then returns
/// the move with the most visits.
pub fn[T : GameState] MCTS::search(
  self : MCTS,
  root_state : T,
  iterations : Int,
) -> Int {
  if root_state.is_terminal() {
    return -1
  }
  let moves = root_state.get_moves()
  if moves.length() == 0 {
    return -1
  }
  let root_player = root_state.current_player()
  let root_idx = self.add_node(-1, -1, root_player, moves)
  for _ in 0..<iterations {
    self.iterate(root_state, root_idx)
  }
  // Pick most-visited child.
  let mut best_visits = -1
  let mut best_move = -1
  let children = self.nodes[root_idx].children
  for i = 0; i < children.length(); i = i + 1 {
    let child = self.nodes[children[i]]
    if child.visits > best_visits {
      best_visits = child.visits
      best_move = child.move_val
    }
  }
  best_move
}

// ---------------------------------------------------------------------------
// Tic-Tac-Toe test implementation
// ---------------------------------------------------------------------------

///|
priv struct MCTTTT {
  board : FixedArray[Int]
  mut player : Int
}

///|
fn MCTTTT::new() -> MCTTTT {
  { board: FixedArray::make(9, 0), player: 1 }
}

///|
fn MCTTTT::clone(self : MCTTTT) -> MCTTTT {
  let b = FixedArray::make(9, 0)
  for i = 0; i < 9; i = i + 1 {
    b[i] = self.board[i]
  }
  { board: b, player: self.player }
}

///|
fn ttt_check_win(board : FixedArray[Int]) -> Int {
  let wins = [
    (0, 1, 2),
    (3, 4, 5),
    (6, 7, 8),
    (0, 3, 6),
    (1, 4, 7),
    (2, 5, 8),
    (0, 4, 8),
    (2, 4, 6),
  ]
  for i = 0; i < wins.length(); i = i + 1 {
    let (a, b, c) = wins[i]
    if board[a] != 0 && board[a] == board[b] && board[a] == board[c] {
      return board[a]
    }
  }
  0
}

///|
fn ttt_is_full(board : FixedArray[Int]) -> Bool {
  for i = 0; i < 9; i = i + 1 {
    if board[i] == 0 {
      return false
    }
  }
  true
}

///|
impl GameState for MCTTTT with fn is_terminal(self) {
  ttt_check_win(self.board) != 0 || ttt_is_full(self.board)
}

///|
impl GameState for MCTTTT with fn get_moves(self) {
  let m : Array[Int] = []
  for i = 0; i < 9; i = i + 1 {
    if self.board[i] == 0 {
      m.push(i)
    }
  }
  m
}

///|
impl GameState for MCTTTT with fn make_move(self, mv) {
  let n = self.clone()
  n.board[mv] = self.player
  n.player = -self.player
  n
}

///|
impl GameState for MCTTTT with fn get_result(self, player) {
  let w = ttt_check_win(self.board)
  if w == 0 {
    0.5
  } else if w == player {
    1.0
  } else {
    0.0
  }
}

///|
impl GameState for MCTTTT with fn random_playout(self, rng) {
  let mut state = self.clone()
  let player = state.player
  while !state.is_terminal() {
    let moves = state.get_moves()
    let idx = (rng() >> 16) % moves.length()
    state = state.make_move(moves[idx])
  }
  state.get_result(player)
}

///|
impl GameState for MCTTTT with fn current_player(self) {
  self.player
}

///|
extend MCTTTT with GameState::{is_terminal, get_moves, make_move, get_result}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mcts: finds immediate win" {
  let g = MCTTTT::new()
  let g1 = g.make_move(0)
  let g2 = g1.make_move(3)
  let g3 = g2.make_move(1)
  let g4 = g3.make_move(4)
  let mcts = new(42)
  let m = mcts.search(g4, 2000)
  assert_eq(m, 2)
}

///|
test "mcts: blocks opponent win" {
  let g = MCTTTT::new()
  let g1 = g.make_move(4)
  let g2 = g1.make_move(0)
  let g3 = g2.make_move(8)
  let g4 = g3.make_move(1)
  let mcts = new(42)
  let m = mcts.search(g4, 2000)
  assert_eq(m, 2)
}

///|
test "mcts: center is strong opening" {
  let g = MCTTTT::new()
  let mcts = new(42)
  let m = mcts.search(g, 3000)
  assert_true(m == 4 || m == 0 || m == 2 || m == 6 || m == 8)
}

///|
test "mcts: terminal state returns -1" {
  let g = MCTTTT::new()
  let g1 = g.make_move(0)
  let g2 = g1.make_move(3)
  let g3 = g2.make_move(1)
  let g4 = g3.make_move(4)
  let g5 = g4.make_move(2)
  let mcts = new(42)
  assert_eq(mcts.search(g5, 100), -1)
}

///|
test "mcts: deterministic with same seed" {
  let g = MCTTTT::new()
  let m1 = new(42).search(g, 500)
  let m2 = new(42).search(g, 500)
  assert_eq(m1, m2)
}
