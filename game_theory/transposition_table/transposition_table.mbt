/// Transposition Table for game tree search.
///
/// A transposition table caches evaluated positions to avoid redundant
/// computation when the same position is reached via different move orders.
/// This is essential for strong chess/checker/Go engines.
///
/// ## Implementation
///
/// Uses a hash table with Zobrist hashing for position keys.
/// Supports storing depth, score, best move, and node type (exact, lower, upper).
///
/// ## References
///
/// - Zobrist, A.L. "A New Hashing Method with Application for Game Playing."
///   ICCA Journal, 1970.
/// - Marsland, T.A. "A Review of Game-Tree Pruning." ICCA Journal, 1986.
///
/// `proof-enabled` is `false`.

///|
/// Node type for transposition table entries.
pub enum NodeType {
  Exact // Exact score
  LowerBound // Score is a lower bound (beta cutoff)
  UpperBound // Score is an upper bound (alpha cutoff)
}

///|
/// A transposition table entry.
pub struct TTEntry {
  depth : Int // Search depth when this was stored
  score : Double // Evaluation score
  node_type : NodeType
  best_move : Int? // Best move found
}

///|
/// A transposition table using a Map for storage.
pub struct TranspositionTable {
  priv mut table : Map[Int, TTEntry]
  priv mut hits : Int
  priv mut misses : Int
}

///|
/// Create a new empty transposition table.
pub fn new() -> TranspositionTable {
  { table: {}, hits: 0, misses: 0, }
}

///|
/// Store a position evaluation in the table.
pub fn store(
  tt : TranspositionTable,
  hash : Int,
  depth : Int,
  score : Double,
  node_type : NodeType,
  best_move : Int?,
) -> Unit {
  // Only replace if the new entry has >= depth
  match tt.table.get(hash) {
    Some(existing) =>
      if existing.depth > depth {
        return // Keep the deeper entry
      }
    None => ()
  }
  tt.table.set(hash, { depth, score, node_type, best_move, })
}

///|
/// Look up a position in the table. Returns Some(entry) or None.
pub fn lookup(tt : TranspositionTable, hash : Int) -> TTEntry? {
  match tt.table.get(hash) {
    Some(e) => {
      tt.hits = tt.hits + 1
      Some(e)
    }
    None => {
      tt.misses = tt.misses + 1
      None
    }
  }
}

///|
/// Get the hit count.
pub fn hits(tt : TranspositionTable) -> Int {
  tt.hits
}

///|
/// Get the miss count.
pub fn misses(tt : TranspositionTable) -> Int {
  tt.misses
}

///|
/// Get the table size.
pub fn size(tt : TranspositionTable) -> Int {
  tt.table.length()
}

///|
/// Clear the table.
pub fn clear(tt : TranspositionTable) -> Unit {
  tt.table = {}
  tt.hits = 0
  tt.misses = 0
}

///|
/// Get the hit rate (0.0 to 1.0).
pub fn hit_rate(tt : TranspositionTable) -> Double {
  let total = tt.hits + tt.misses
  if total == 0 {
    return 0.0
  }
  tt.hits.to_double() / total.to_double()
}

///|
test "transposition_table: store and lookup" {
  let tt = new()
  store(tt, 12345, 5, 100.0, Exact, Some(7))
  match lookup(tt, 12345) {
    Some(e) => {
      assert_eq(e.depth, 5)
      assert_eq(e.score, 100.0)
      assert_eq(e.best_move, Some(7))
    }
    None => assert_true(false)
  }
}

///|
test "transposition_table: miss returns None" {
  let tt = new()
  match lookup(tt, 99999) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
  assert_eq(misses(tt), 1)
}

///|
test "transposition_table: deeper entry not replaced" {
  let tt = new()
  store(tt, 100, 5, 50.0, Exact, Some(1))
  store(tt, 100, 3, 99.0, Exact, Some(2))
  match lookup(tt, 100) {
    Some(e) => {
      assert_eq(e.depth, 5) // Deeper entry kept
      assert_eq(e.score, 50.0)
    }
    None => assert_true(false)
  }
}

///|
test "transposition_table: shallower entry replaced" {
  let tt = new()
  store(tt, 200, 2, 10.0, Exact, Some(1))
  store(tt, 200, 4, 20.0, LowerBound, Some(3))
  match lookup(tt, 200) {
    Some(e) => {
      assert_eq(e.depth, 4)
      assert_eq(e.score, 20.0)
    }
    None => assert_true(false)
  }
}

///|
test "transposition_table: hit rate" {
  let tt = new()
  store(tt, 1, 1, 0.0, Exact, None)
  lookup(tt, 1) |> ignore
  lookup(tt, 2) |> ignore
  lookup(tt, 1) |> ignore
  assert_eq(hits(tt), 2)
  assert_eq(misses(tt), 1)
  let rate = hit_rate(tt)
  assert_true(rate > 0.6 && rate < 0.7)
}

///|
test "transposition_table: upper bound entry" {
  let tt = new()
  store(tt, 42, 3, 150.0, UpperBound, Some(7))
  match lookup(tt, 42) {
    Some(e) => {
      match e.node_type {
        UpperBound => assert_true(true)
        _ => assert_true(false)
      }
      assert_eq(e.score, 150.0)
    }
    None => assert_true(false)
  }
}
