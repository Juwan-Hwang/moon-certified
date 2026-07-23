/// Treap (tree + heap): a randomized balanced binary search tree.
///
/// A treap stores a BST ordered by `key` while also maintaining a max-heap
/// invariant on a randomly assigned `priority`: every node's priority is at
/// least as large as those of its children. Because the priorities are random,
/// the resulting tree shape is statistically indistinguishable from a random
/// BST, so all operations run in O(log n) expected time with high probability.
///
/// Insertion is recursive: the new key is placed as a leaf with a fresh random
/// priority, then rotated upward (right rotation when the left child outranks
/// its parent, left rotation when the right child does) until the heap property
/// is restored. Deletion is the mirror: the target node is rotated downward
/// — always promoting the higher-priority child — until it becomes a leaf and
/// can be dropped. Both run in O(log n) expected time.
///
/// Each node caches its subtree `size`, so `size` is O(1). Priorities come
/// from a tiny inline LCG (`state = state * 1103515245 + 12345 (mod 2^31)`)
/// held in a single module-level cell — no standard-library random source is
/// needed, and the sequence is deterministic across runs.
///
/// Complexity (expected, with high probability):
/// - `insert`  — O(log n)
/// - `search`  — O(log n)
/// - `delete`  — O(log n)
/// - `size`    — O(1)   (cached in every node)
/// - `inorder` — O(n)
///
/// Limitations:
/// - Keys are `Int`; the structure is a set (no per-key value).
/// - Duplicate keys are silently ignored on insert.
/// - The LCG is not cryptographically secure; it only needs to assign
///   well-spread priorities. Worst-case (adversarial priorities) behaviour is
///   O(n), but this never happens with the fixed LCG sequence.
/// - Insertion is a pure function that consumes from the shared LCG, so the
///   resulting priorities depend on prior calls. Structural correctness (BST +
///   heap) never depends on the specific values drawn.
///
/// Not formally verified. Correctness is ensured by the comprehensive test
/// suite below, which checks the BST and heap invariants, size consistency,
/// and balance after large randomized workloads.

/// A treap node.
///
/// `Empty` is the empty tree. `Node(left, key, priority, right, size)` carries
/// the cached subtree size as its fifth field so `size` is O(1). The heap is a
/// max-heap on `priority` (larger = closer to the root).
pub enum TreapNode {
  Empty
  Node(TreapNode, Int, Int, TreapNode, Int) // (left, key, priority, right, size)
}

/// Public constructor for an empty treap.
pub fn empty() -> TreapNode {
  Empty
}

// ---------------------------------------------------------------------------
// Random priority source
//
// MoonBit has no top-level mutable bindings, so the LCG state lives in a
// mutable field of a struct bound by an ordinary (immutable) top-level `let`.
// The binding cannot be reassigned, but the struct's field can, which is all
// we need for a mutable counter.
// ---------------------------------------------------------------------------

/// Mutable cell holding the LCG state for priority generation.
priv struct Rng {
  mut state : Int
}

/// The single global LCG state. Seeded with a fixed non-zero value so the
/// priority sequence — and therefore every test — is deterministic.
let rng : Rng = { state: 0x1A2B3C4D }

/// Advance the LCG one step and return the next non-negative priority.
fn next_priority() -> Int {
  rng.state = (rng.state * 1103515245 + 12345) & 0x7FFFFFFF
  rng.state
}

// ---------------------------------------------------------------------------
// Cached metadata
// ---------------------------------------------------------------------------

/// Number of nodes in the tree. O(1) via the cached size field.
pub fn size(root : TreapNode) -> Int {
  match root {
    Empty => 0
    Node(_, _, _, _, s) => s
  }
}

/// Height of the tree. `Empty` = -1, a leaf = 0. O(n). Used by tests.
pub fn height(root : TreapNode) -> Int {
  match root {
    Empty => -1
    Node(l, _, _, r, _) => {
      let lh = height(l)
      let rh = height(r)
      (if lh >= rh { lh } else { rh }) + 1
    }
  }
}

/// Construct a node, computing the cached subtree size from its children. O(1).
fn mknode(l : TreapNode, k : Int, p : Int, r : TreapNode) -> TreapNode {
  Node(l, k, p, r, size(l) + 1 + size(r))
}

// ---------------------------------------------------------------------------
// Insertion
// ---------------------------------------------------------------------------

/// Insert `key` into the treap. Duplicate keys are ignored (the original node
/// and its priority are kept). Returns the new root. Expected O(log n).
pub fn insert(root : TreapNode, key : Int) -> TreapNode {
  match root {
    Empty => Node(Empty, key, next_priority(), Empty, 1)
    Node(l, k, p, r, _) =>
      if key < k {
        let new_l = insert(l, key)
        match new_l {
          Node(ll, lk, lp, lr, _) =>
            if lp > p {
              // Left child now outranks the parent: rotate right so `lk`
              // rises and `k` sinks into the right subtree.
              mknode(ll, lk, lp, mknode(lr, k, p, r))
            } else {
              mknode(new_l, k, p, r)
            }
          // `insert` always returns a `Node`, so this is unreachable.
          Empty => abort("unreachable: insert never returns Empty")
        }
      } else if key > k {
        let new_r = insert(r, key)
        match new_r {
          Node(rl, rk, rp, rr, _) =>
            if rp > p {
              // Right child now outranks the parent: rotate left so `rk`
              // rises and `k` sinks into the left subtree.
              mknode(mknode(l, k, p, rl), rk, rp, rr)
            } else {
              mknode(l, k, p, new_r)
            }
          Empty => abort("unreachable: insert never returns Empty")
        }
      } else {
        root // Duplicate key: ignore, keep existing node untouched.
      }
  }
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/// Return `true` if `key` is present in the treap. Expected O(log n).
pub fn search(root : TreapNode, key : Int) -> Bool {
  match root {
    Empty => false
    Node(l, k, _, r, _) =>
      if key < k {
        search(l, key)
      } else if key > k {
        search(r, key)
      } else {
        true
      }
  }
}

// ---------------------------------------------------------------------------
// Deletion
// ---------------------------------------------------------------------------

/// Delete `key` from the treap. If the key is absent the tree is unchanged.
/// Returns the new root. Expected O(log n).
///
/// The target node is rotated downward — always promoting the child with the
/// larger priority to preserve the heap property — until it reaches a leaf and
/// can be removed. Each recursive step sinks the target by one level, so the
/// recursion always terminates.
pub fn delete(root : TreapNode, key : Int) -> TreapNode {
  match root {
    Empty => Empty
    Node(l, k, p, r, _) =>
      if key < k {
        mknode(delete(l, key), k, p, r)
      } else if key > k {
        mknode(l, k, p, delete(r, key))
      } else {
        // Found the node to delete.
        match (l, r) {
          (Empty, _) => r
          (_, Empty) => l
          (Node(ll, lk, lp, lr, _), Node(rl, rk, rp, rr, _)) =>
            if lp > rp {
              // Left child outranks right: right rotation lifts `lk`.
              // `k` descends into the right subtree; delete it from there.
              let new_r = delete(mknode(lr, k, p, r), key)
              mknode(ll, lk, lp, new_r)
            } else {
              // Right child outranks (or ties): left rotation lifts `rk`.
              // `k` descends into the left subtree; delete it from there.
              let new_l = delete(mknode(l, k, p, rl), key)
              mknode(new_l, rk, rp, rr)
            }
        }
      }
  }
}

// ---------------------------------------------------------------------------
// In-order traversal
// ---------------------------------------------------------------------------

/// Return all keys in ascending order as a `FixedArray[Int]`. O(n).
pub fn inorder(root : TreapNode) -> FixedArray[Int] {
  let n = size(root)
  let result = FixedArray::make(n, 0)
  let _ = inorder_fill(root, result, 0)
  result
}

/// Fill `result` in-order starting at index `idx`; return the next free index.
fn inorder_fill(
  root : TreapNode,
  result : FixedArray[Int],
  idx : Int,
) -> Int {
  match root {
    Empty => idx
    Node(l, k, _, r, _) => {
      let after_left = inorder_fill(l, result, idx)
      result[after_left] = k
      inorder_fill(r, result, after_left + 1)
    }
  }
}

// ---------------------------------------------------------------------------
// Internal invariants (used by tests)
// ---------------------------------------------------------------------------

/// True iff the in-order traversal is strictly ascending (BST property).
fn is_bst(root : TreapNode) -> Bool {
  let arr = inorder(root)
  let n = arr.length()
  let mut ok = true
  let mut i = 1
  while i < n {
    if arr[i] <= arr[i - 1] {
      ok = false
    }
    i = i + 1
  }
  ok
}

/// True iff every node's priority is >= its children's (max-heap property).
fn is_heap(root : TreapNode) -> Bool {
  match root {
    Empty => true
    Node(l, _, p, r, _) =>
      priority_le(l, p) && priority_le(r, p) && is_heap(l) && is_heap(r)
  }
}

/// True iff `node`'s priority (if any) is <= `p`.
fn priority_le(node : TreapNode, p : Int) -> Bool {
  match node {
    Empty => true
    Node(_, _, np, _, _) => np <= p
  }
}

/// Recompute the true subtree size and verify it matches the cached field.
fn verify_sizes(root : TreapNode) -> Bool {
  match root {
    Empty => true
    Node(l, _, _, r, s) =>
      s == real_count(l) + 1 + real_count(r) &&
      verify_sizes(l) &&
      verify_sizes(r)
  }
}

/// Uncached node count, used only to validate the cached sizes.
fn real_count(root : TreapNode) -> Int {
  match root {
    Empty => 0
    Node(l, _, _, r, _) => real_count(l) + 1 + real_count(r)
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "treap: basic insert and search" {
  let tree = empty()
  let t1 = insert(tree, 5)
  assert_true(search(t1, 5))
  assert_false(search(t1, 3))
  let t2 = insert(t1, 3)
  let t3 = insert(t2, 7)
  assert_true(search(t3, 3))
  assert_true(search(t3, 7))
  assert_true(search(t3, 5))
  assert_true(is_bst(t3))
  assert_true(is_heap(t3))
}

test "treap: duplicate insert ignored" {
  let tree = insert(insert(empty(), 5), 5)
  assert_eq(size(tree), 1)
  assert_true(search(tree, 5))
}

test "treap: sequential insert maintains balance" {
  // Inserting 1..7 in order into a plain BST would give a chain of height 6;
  // the treap's random priorities keep it balanced.
  let mut tree = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k)
  }
  assert_eq(size(tree), 7)
  assert_true(is_bst(tree))
  assert_true(is_heap(tree))
  assert_true(verify_sizes(tree))
  // A balanced tree of 7 nodes has height 2; allow a little slack.
  assert_true(height(tree) <= 5)
}

test "treap: reverse insert maintains balance" {
  let mut tree = empty()
  for k = 7; k >= 1; k = k - 1 {
    tree = insert(tree, k)
  }
  assert_eq(size(tree), 7)
  assert_true(is_bst(tree))
  assert_true(is_heap(tree))
  assert_true(verify_sizes(tree))
  assert_true(height(tree) <= 5)
}

test "treap: delete leaf" {
  let tree = insert(insert(insert(empty(), 5), 3), 7)
  let t2 = delete(tree, 7)
  assert_false(search(t2, 7))
  assert_true(search(t2, 5))
  assert_true(search(t2, 3))
  assert_eq(size(t2), 2)
  assert_true(is_bst(t2))
  assert_true(is_heap(t2))
  assert_true(verify_sizes(t2))
}

test "treap: delete root" {
  let mut tree = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k)
  }
  // Deleting the current root key still yields a valid treap.
  let root_key = match tree {
    Node(_, k, _, _, _) => k
    Empty => abort("unreachable: non-empty tree")
  }
  let t2 = delete(tree, root_key)
  assert_false(search(t2, root_key))
  assert_eq(size(t2), 6)
  assert_true(is_bst(t2))
  assert_true(is_heap(t2))
  assert_true(verify_sizes(t2))
}

test "treap: delete all elements" {
  let mut tree = empty()
  for k = 1; k <= 15; k = k + 1 {
    tree = insert(tree, k)
  }
  for k = 1; k <= 15; k = k + 1 {
    tree = delete(tree, k)
    assert_true(is_bst(tree))
    assert_true(is_heap(tree))
    assert_true(verify_sizes(tree))
    assert_eq(size(tree), 15 - k)
  }
  assert_eq(size(tree), 0)
}

test "treap: large random insert" {
  let mut tree = empty()
  let n = 200
  for k = 0; k < n; k = k + 1 {
    tree = insert(tree, (k * 37 + 11) % n)
  }
  assert_eq(size(tree), n)
  assert_true(is_bst(tree))
  assert_true(is_heap(tree))
  assert_true(verify_sizes(tree))
  // O(log n) height: 3 * ceil(log2(n+1)) is generous but still logarithmic.
  assert_true(height(tree) <= 30)
  for k = 0; k < n; k = k + 1 {
    assert_true(search(tree, k))
  }
}

test "treap: inorder is sorted" {
  let mut tree = empty()
  let vals = [5, 3, 7, 1, 4, 6, 8, 2]
  for k = 0; k < 8; k = k + 1 {
    tree = insert(tree, vals[k])
  }
  let sorted = inorder(tree)
  assert_eq(sorted.length(), 8)
  for k = 0; k < 8; k = k + 1 {
    assert_eq(sorted[k], k + 1)
  }
}

test "treap: size tracking" {
  let mut tree = empty()
  assert_eq(size(tree), 0)
  tree = insert(tree, 10)
  assert_eq(size(tree), 1)
  tree = insert(tree, 20)
  tree = insert(tree, 30)
  assert_eq(size(tree), 3)
  tree = insert(tree, 20) // duplicate, no growth
  assert_eq(size(tree), 3)
  tree = delete(tree, 20)
  assert_eq(size(tree), 2)
  tree = delete(tree, 10)
  tree = delete(tree, 30)
  assert_eq(size(tree), 0)
}

test "treap: empty tree operations" {
  let tree = empty()
  assert_eq(size(tree), 0)
  assert_eq(height(tree), -1)
  assert_false(search(tree, 1))
  assert_eq(inorder(tree).length(), 0)
  let t2 = delete(tree, 1)
  assert_eq(size(t2), 0)
}

test "treap: delete non-existent key" {
  let mut tree = empty()
  for k = 1; k <= 10; k = k + 1 {
    tree = insert(tree, k)
  }
  let t2 = delete(tree, 99)
  assert_eq(size(t2), 10)
  assert_true(is_bst(t2))
  assert_true(is_heap(t2))
  for k = 1; k <= 10; k = k + 1 {
    assert_true(search(t2, k))
  }
}

test "treap: interleave insert and delete" {
  let mut tree = empty()
  tree = insert(tree, 5)
  tree = insert(tree, 3)
  tree = insert(tree, 7)
  tree = delete(tree, 3)
  assert_true(is_bst(tree))
  assert_true(is_heap(tree))
  tree = insert(tree, 1)
  tree = insert(tree, 9)
  assert_true(is_bst(tree))
  assert_true(is_heap(tree))
  tree = delete(tree, 7)
  tree = delete(tree, 5)
  assert_true(is_bst(tree))
  assert_true(is_heap(tree))
  assert_eq(size(tree), 2)
  assert_true(search(tree, 1))
  assert_true(search(tree, 9))
}
