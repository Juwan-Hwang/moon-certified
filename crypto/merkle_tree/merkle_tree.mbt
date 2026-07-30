/// Merkle Tree — Cryptographic Accumulator for Data Integrity Verification.
///
/// A Merkle tree is a hash-based data structure that summarises a potentially
/// large set of data blocks into a single root hash. It enables **O(log n)**
/// inclusion proofs: to prove that a specific leaf belongs to the tree, one
/// only needs to provide the sibling hashes along the path from the leaf to
/// the root.
///
/// ## Construction
///
/// 1. Each data block is hashed to produce a **leaf** node.
/// 2. Consecutive pairs of leaf nodes are concatenated and hashed to produce
///    their **parent**.
/// 3. This process repeats level by level until a single **root** hash remains.
/// 4. If a level has an odd number of nodes, the last node is **duplicated**
///    (Bitcoin convention) so that every internal node has exactly two children.
///
/// ## Inclusion Proof
///
/// An inclusion proof for leaf `i` consists of the sibling hashes at each
/// level of the tree. The verifier recomputes the root from the leaf hash and
/// the proof siblings, then compares against the stored root.
///
/// ## Security
///
/// The security of a Merkle tree reduces to the collision resistance of the
/// underlying hash function (SHA-256 in this implementation). An adversary
/// cannot forge a proof for a non-existent leaf without finding a hash
/// collision.
///
/// ## Domain Separation
///
/// To prevent second-preimage attacks (where an attacker provides an internal
/// node's hash as a leaf), this implementation applies **domain separation**:
/// leaf hashing prepends `0x00`, internal node hashing prepends `0x01`. This
/// follows the recommendation of [RFC 6962 §2.1] and prevents an attacker
/// from passing an internal node as a leaf (or vice versa).
///
/// [RFC 6962]: https://datatracker.ietf.org/doc/html/rfc6962
///
/// ## Complexity
///
/// - Build: **O(n)** hash evaluations.
/// - Proof generation: **O(log n)** hash evaluations.
/// - Proof verification: **O(log n)** hash evaluations.
/// - Space: **O(n)** for the full tree, **O(log n)** for a single proof.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A Merkle tree built from SHA-256.
///
/// Stores all node hashes in a flat array for efficient proof generation.
/// The tree is immutable after construction.
pub struct MerkleTree {
  leaves : Array[Bytes]
  nodes : Array[Bytes]
  num_leaves : Int
  level_offsets : Array[Int]
  level_sizes : Array[Int]
  root : Bytes
}

///|
/// A Merkle inclusion proof for a single leaf.
///
/// Contains the sibling hashes needed to recompute the root from the leaf.
/// Each entry is (sibling_hash, is_right): if `is_right` is true, the sibling
/// is the right node (the leaf is on the left); if false, the sibling is the
/// left node.
pub struct MerkleProof {
  siblings : Array[(Bytes, Bool)]
}

// ---------------------------------------------------------------------------
// Hash helpers
// ---------------------------------------------------------------------------

///|
/// Hash a leaf with domain separation (prepend 0x00).
fn hash_leaf(data : Bytes) -> Bytes {
  let buf : Array[Byte] = Array::make(data.length() + 1, b'\x00')
  for i = 0; i < data.length(); i = i + 1 {
    buf[i + 1] = data[i]
  }
  @sha256.sha256(Bytes::from_array(buf))
}

///|
/// Hash two child nodes with domain separation (prepend 0x01).
fn hash_internal(left : Bytes, right : Bytes) -> Bytes {
  let buf : Array[Byte] = Array::make(left.length() + right.length() + 1, b'\x00')
  buf[0] = b'\x01'
  for i = 0; i < left.length(); i = i + 1 {
    buf[i + 1] = left[i]
  }
  for i = 0; i < right.length(); i = i + 1 {
    buf[i + 1 + left.length()] = right[i]
  }
  @sha256.sha256(Bytes::from_array(buf))
}

// ---------------------------------------------------------------------------
// Tree construction
// ---------------------------------------------------------------------------

///|
/// Build a Merkle tree from an array of data blocks.
///
/// Each data block is hashed (with leaf domain separation) to form a leaf.
/// Leaves are then paired and hashed level by level until a single root
/// remains. Odd nodes at each level are **duplicated** (Bitcoin convention).
///
/// Returns `None` if `data_blocks` is empty.
pub fn build(data_blocks : Array[Bytes]) -> MerkleTree? {
  let n = data_blocks.length()
  if n == 0 {
    return None
  }
  let leaves : Array[Bytes] = Array::make(n, b"")
  for i = 0; i < n; i = i + 1 {
    leaves[i] = hash_leaf(data_blocks[i])
  }
  let nodes : Array[Bytes] = []
  let level_offsets : Array[Int] = []
  let level_sizes : Array[Int] = []
  level_offsets.push(0)
  level_sizes.push(n)
  for i = 0; i < n; i = i + 1 {
    nodes.push(leaves[i])
  }
  let mut current_size = n
  let mut current_offset = 0
  while current_size > 1 {
    let next_level : Array[Bytes] = []
    let next_size = (current_size + 1) / 2
    for i = 0; i < next_size; i = i + 1 {
      let left_idx = current_offset + 2 * i
      let right_idx = current_offset + 2 * i + 1
      let left = nodes[left_idx]
      let right = if right_idx < current_offset + current_size {
        nodes[right_idx]
      } else {
        nodes[left_idx]
      }
      next_level.push(hash_internal(left, right))
    }
    current_offset = nodes.length()
    for i = 0; i < next_level.length(); i = i + 1 {
      nodes.push(next_level[i])
    }
    level_offsets.push(current_offset)
    level_sizes.push(next_size)
    current_size = next_size
  }
  let root = nodes[nodes.length() - 1]
  Some({
    leaves: leaves,
    nodes: nodes,
    num_leaves: n,
    level_offsets: level_offsets,
    level_sizes: level_sizes,
    root: root,
  })
}

///|
/// Return the Merkle root hash.
pub fn root_hash(tree : MerkleTree) -> Bytes {
  tree.root
}

///|
/// Return the number of leaves in the tree.
pub fn leaf_count(tree : MerkleTree) -> Int {
  tree.num_leaves
}

///|
/// Return the leaf hash at index `i`.
pub fn leaf_hash(tree : MerkleTree, index : Int) -> Bytes? {
  if index < 0 || index >= tree.num_leaves {
    return None
  }
  Some(tree.leaves[index])
}

///|
/// Return the tree height (number of levels minus 1).
pub fn height(tree : MerkleTree) -> Int {
  tree.level_offsets.length() - 1
}

// ---------------------------------------------------------------------------
// Proof generation and verification
// ---------------------------------------------------------------------------

///|
/// Generate an inclusion proof for the leaf at `index`.
///
/// Returns `None` if `index` is out of bounds.
pub fn make_proof(tree : MerkleTree, index : Int) -> MerkleProof? {
  if index < 0 || index >= tree.num_leaves {
    return None
  }
  let siblings : Array[(Bytes, Bool)] = []
  let mut idx = index
  for level = 0; level < tree.level_offsets.length() - 1; level = level + 1 {
    let offset = tree.level_offsets[level]
    let size = tree.level_sizes[level]
    let sibling_idx = if idx % 2 == 0 {
      let sib = idx + 1
      if sib < size {
        sib
      } else {
        idx
      }
    } else {
      idx - 1
    }
    let sibling_hash = tree.nodes[offset + sibling_idx]
    let is_right = idx % 2 == 0
    siblings.push((sibling_hash, is_right))
    idx = idx / 2
  }
  Some({ siblings: siblings })
}

///|
/// Verify an inclusion proof.
///
/// Recomputes the root from the leaf hash and the proof siblings, then
/// compares against the expected root using constant-time comparison.
pub fn verify_proof(
  leaf_hash : Bytes,
  proof : MerkleProof,
  expected_root : Bytes,
) -> Bool {
  let mut current = leaf_hash
  for i = 0; i < proof.siblings.length(); i = i + 1 {
    let (sibling, is_right) = proof.siblings[i]
    current = if is_right {
      hash_internal(current, sibling)
    } else {
      hash_internal(sibling, current)
    }
  }
  constant_time_eq_bytes(current, expected_root)
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

///|
/// Constant-time byte comparison to prevent timing side channels.
fn constant_time_eq_bytes(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < a.length(); i = i + 1 {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}

///|
/// Convert a 32-byte hash to a lowercase hex string.
pub fn hash_to_hex(hash : Bytes) -> String {
  let hex_digits : FixedArray[Char] = FixedArray::from_array([
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e',
    'f',
  ])
  let buf = StringBuilder()
  for i = 0; i < hash.length(); i = i + 1 {
    let b = hash[i].to_int()
    buf.write_char(hex_digits[(b >> 4) & 0xF])
    buf.write_char(hex_digits[b & 0xF])
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "build: single leaf" {
  let data = [b"hello"]
  let tree_opt = build(data)
  assert_true(tree_opt is Some(_))
  let t = tree_opt.unwrap()
  assert_eq(leaf_count(t), 1)
  assert_eq(height(t), 0)
  let root = root_hash(t)
  assert_eq(root.length(), 32)
}

test "build: two leaves" {
  let data = [b"a", b"b"]
  let tree = build(data).unwrap()
  assert_eq(leaf_count(tree), 2)
  assert_eq(height(tree), 1)
  let root = root_hash(tree)
  assert_eq(root.length(), 32)
  let leaf_a = leaf_hash(tree, 0).unwrap()
  let leaf_b = leaf_hash(tree, 1).unwrap()
  let buf : Array[Byte] = Array::make(65, b'\x00')
  buf[0] = b'\x01'
  for i = 0; i < 32; i = i + 1 {
    buf[i + 1] = leaf_a[i]
    buf[i + 33] = leaf_b[i]
  }
  let expected = @sha256.sha256(Bytes::from_array(buf))
  assert_true(verify_proof(leaf_a, make_proof(tree, 0).unwrap(), expected))
}

test "build: odd number of leaves" {
  let data = [b"x", b"y", b"z"]
  let tree = build(data).unwrap()
  assert_eq(leaf_count(tree), 3)
  assert_eq(height(tree), 2)
  let root = root_hash(tree)
  assert_eq(root.length(), 32)
}

test "build: empty data returns None" {
  let tree = build([])
  assert_true(tree is None)
}

test "proof: valid proof verifies" {
  let data = [b"block0", b"block1", b"block2", b"block3", b"block4"]
  let tree = build(data).unwrap()
  let root = root_hash(tree)
  for i = 0; i < data.length(); i = i + 1 {
    let proof = make_proof(tree, i).unwrap()
    let lh = leaf_hash(tree, i).unwrap()
    assert_true(verify_proof(lh, proof, root))
  }
}

test "proof: invalid proof rejected" {
  let data = [b"block0", b"block1", b"block2", b"block3"]
  let tree = build(data).unwrap()
  let root = root_hash(tree)
  let proof = make_proof(tree, 0).unwrap()
  let wrong_leaf = leaf_hash(tree, 1).unwrap()
  assert_false(verify_proof(wrong_leaf, proof, root))
}

test "proof: out of bounds returns None" {
  let data = [b"a", b"b"]
  let tree = build(data).unwrap()
  assert_true(make_proof(tree, 5) is None)
  assert_true(make_proof(tree, -1) is None)
}

test "root: deterministic" {
  let data = [b"a", b"b", b"c"]
  let tree1 = build(data).unwrap()
  let tree2 = build(data).unwrap()
  assert_eq(root_hash(tree1), root_hash(tree2))
}

test "root: different data different roots" {
  let d1 = [b"a", b"b"]
  let d2 = [b"a", b"c"]
  let t1 = build(d1).unwrap()
  let t2 = build(d2).unwrap()
  assert_not_eq(root_hash(t1), root_hash(t2))
}

test "root: order matters" {
  let d1 = [b"a", b"b"]
  let d2 = [b"b", b"a"]
  let t1 = build(d1).unwrap()
  let t2 = build(d2).unwrap()
  assert_not_eq(root_hash(t1), root_hash(t2))
}

test "hash_to_hex: correct hex" {
  let data = [b"test"]
  let tree = build(data).unwrap()
  let hex = hash_to_hex(root_hash(tree))
  assert_eq(hex.length(), 64)
  for c in hex {
    let is_hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
    assert_true(is_hex)
  }
}

test "domain separation: leaf vs internal" {
  let data = b"abc"
  let leaf = hash_leaf(data)
  let internal = hash_internal(data, data)
  assert_not_eq(leaf, internal)
}

test "large tree: 100 leaves" {
  let data : Array[Bytes] = []
  for i = 0; i < 100; i = i + 1 {
    data.push(b"block_{i}")
  }
  let tree = build(data).unwrap()
  assert_eq(leaf_count(tree), 100)
  assert_eq(height(tree), 7)
  let root = root_hash(tree)
  for i in [0, 25, 50, 75, 99] {
    let proof = make_proof(tree, i).unwrap()
    let lh = leaf_hash(tree, i).unwrap()
    assert_true(verify_proof(lh, proof, root))
  }
}

test "tampered root: verification fails" {
  let data = [b"a", b"b", b"c", b"d"]
  let tree = build(data).unwrap()
  let root = root_hash(tree)
  let proof = make_proof(tree, 1).unwrap()
  let lh = leaf_hash(tree, 1).unwrap()
  let tampered : Array[Byte] = Array::make(32, b'\x00')
  for i = 0; i < 32; i = i + 1 {
    tampered[i] = root[i]
  }
  tampered[0] = (tampered[0].to_int() ^ 1).to_byte()
  let tampered_root = Bytes::from_array(tampered)
  assert_false(verify_proof(lh, proof, tampered_root))
}
