///|
/// Zobrist hashing for game-state position encoding.
///
/// Zobrist hashing assigns a random 64-bit key to every (position, piece)
/// pair, then encodes a full board as the XOR of the keys of all occupied
/// squares. The key property is incremental updatability: changing the piece
/// at a single square is a constant-time XOR of two keys, ideal for
/// transposition tables in game-tree search (chess, Go, etc.).
///
/// Convention: piece value 0 denotes an empty square and contributes nothing
/// to the hash. Non-zero piece values must lie in [1, num_piece_types].
let num_piece_types : Int = 256

///|
/// The Zobrist hasher: a table of random Int64 keys indexed by
/// [position][piece].
pub struct ZobristHasher {
  priv table : Array[Array[Int64]]
}

///|
/// Create a hasher for a board with `board_size` positions. The key table
/// is filled with a fixed-seed XorShift64 PRNG (via `@utils`) so hashers
/// are reproducible.
pub fn new(board_size : Int) -> ZobristHasher {
  let rng = @utils.XorShift64::new(0x9E3779B97F4A7C15UL)
  let table = Array::makei(board_size, fn(_i) {
    Array::makei(num_piece_types, fn(_j) {
      let mut k = rng.next_u64().reinterpret_as_int64()
      if k == 0L {
        k = 1L // avoid zero keys (invisible under XOR)
      }
      k
    })
  })
  { table, }
}

///|
/// Full hash of a board position. `pieces[i]` is the piece at square i;
/// 0 means empty (skipped). Returns the XOR of all occupied keys.
pub fn ZobristHasher::hash_position(
  self : ZobristHasher,
  pieces : Array[Int],
) -> Int64 {
  let mut h = 0L
  for i = 0; i < pieces.length(); i = i + 1 {
    let p = pieces[i]
    if p != 0 {
      h = h ^ self.table[i][p]
    }
  }
  h
}

///|
/// Incrementally update a hash when the piece at `pos` changes from
/// `old_piece` to `new_piece`. O(1): XOR out the old key, XOR in the new.
pub fn ZobristHasher::incremental_update(
  self : ZobristHasher,
  hash : Int64,
  pos : Int,
  old_piece : Int,
  new_piece : Int,
) -> Int64 {
  let mut h = hash
  if old_piece != 0 {
    h = h ^ self.table[pos][old_piece]
  }
  if new_piece != 0 {
    h = h ^ self.table[pos][new_piece]
  }
  h
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "zobrist: same position gives same hash (deterministic)" {
  let h = new(64)
  let pos = [1, 2, 0, 3, 0, 0, 1, 0]
  let h1 = h.hash_position(pos)
  let h2 = h.hash_position(pos)
  assert_true(h1 == h2)
}

///|
test "zobrist: different positions give different hashes" {
  let h = new(64)
  let p1 = [1, 2, 3, 0, 0, 0, 0, 0]
  let p2 = [1, 3, 2, 0, 0, 0, 0, 0] // swapped pieces 2 and 3
  let h1 = h.hash_position(p1)
  let h2 = h.hash_position(p2)
  assert_true(h1 != h2)
}

///|
test "zobrist: incremental update matches full rehash" {
  let h = new(64)
  let pieces = [1, 2, 0, 3, 0, 1, 0, 0]
  let full = h.hash_position(pieces)
  // Change square 1 from piece 2 to piece 5.
  let updated = h.incremental_update(full, 1, 2, 5)
  // Rebuild and verify consistency.
  pieces[1] = 5
  let rehash = h.hash_position(pieces)
  assert_true(updated == rehash)
}
