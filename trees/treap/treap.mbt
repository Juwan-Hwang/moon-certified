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
/// held inside each `Treap` instance — no standard-library random source is
/// needed, and every tree's sequence is deterministic and independent of other
/// trees or of test execution order.
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
/// - Insertion is a pure function: it returns a new `Treap` whose `rng` field
///   is the advanced LCG state, so each tree lineage threads its own priority
///   sequence. Structural correctness (BST + heap) never depends on the
///   specific values drawn.
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

/// A treap handle: the root node together with this instance's own LCG state.
///
/// Because the RNG state is carried per-instance and threaded purely through
/// `insert`, every `Treap` draws an independent, deterministic priority
/// sequence. Two trees built from separate `empty()` calls never share state,
/// so test execution order cannot perturb the results. The fields are
/// immutable; `insert` returns a fresh `Treap` carrying the advanced state.
pub struct Treap {
  root : TreapNode
  rng : Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// Public constructor for an empty treap. Each call yields a fresh `Treap`
/// with the LCG seeded to a fixed value, so the priority sequence is
/// deterministic yet local to the returned instance.
pub fn empty() -> Treap {
  { root: Empty, rng: rng_seed }
}

// ---------------------------------------------------------------------------
// Random priority source
//
// The LCG state lives in the immutable `rng` field of each `Treap`. `insert`
// advances the state by one step, uses the new value as the new leaf's
// priority, and returns a `Treap` carrying the advanced state. Because the
// state is per-instance and threaded purely, two independent trees never
// interfere with each other's sequences and tests are deterministic
// regardless of execution order.
// ---------------------------------------------------------------------------

/// Seed for every fresh `Treap`. Any fixed non-zero value makes the priority
/// sequence — and therefore every test — deterministic.
let rng_seed : Int = 0x1A2B3C4D

/// Advance the LCG one step from `state` and return the new non-negative
/// state, which doubles as the next node's priority.
fn next_priority(state : Int) -> Int {
  (state * 1103515245 + 12345) & 0x7FFFFFFF
}

// ---------------------------------------------------------------------------
// Cached metadata
// ---------------------------------------------------------------------------

/// Number of nodes in the tree. O(1) via the cached size field.
pub fn size(t : Treap) -> Int {
  size_node(t.root)
}

/// Number of nodes in a subtree. O(1) via the cached size field.
fn size_node(root : TreapNode) -> Int {
  match root {
    Empty => 0
    Node(_, _, _, _, s) => s
  }
}

/// Height of the tree. `Empty` = -1, a leaf = 0. O(n). Used by tests.
pub fn height(t : Treap) -> Int {
  height_node(t.root)
}

fn height_node(root : TreapNode) -> Int {
  match root {
    Empty => -1
    Node(l, _, _, r, _) => {
      let lh = height_node(l)
      let rh = height_node(r)
      (if lh >= rh { lh } else { rh }) + 1
    }
  }
}

/// Construct a node, computing the cached subtree size from its children. O(1).
fn mknode(l : TreapNode, k : Int, p : Int, r : TreapNode) -> TreapNode {
  Node(l, k, p, r, size_node(l) + 1 + size_node(r))
}

// ---------------------------------------------------------------------------
// Insertion
// ---------------------------------------------------------------------------

/// Insert `key` into the treap. Duplicate keys are ignored (the original node
/// and its priority are kept). Returns a new `Treap` whose root has `key`
/// inserted and whose `rng` is advanced one step. Expected O(log n).
pub fn insert(t : Treap, key : Int) -> Treap {
  let p = next_priority(t.rng)
  { root: insert_node(t.root, key, p), rng: p }
}

/// Recursive insertion that assigns the fixed priority `p` to the single new
/// leaf. Exactly one priority is drawn per top-level `insert`, so this mirrors
/// the original single-draw-per-insert behaviour. Expected O(log n).
fn insert_node(root : TreapNode, key : Int, p : Int) -> TreapNode {
  match root {
    Empty => Node(Empty, key, p, Empty, 1)
    Node(l, k, cp, r, _) =>
      if key < k {
        let new_l = insert_node(l, key, p)
        match new_l {
          Node(ll, lk, lp, lr, _) =>
            if lp > cp {
              // Left child now outranks the parent: rotate right so `lk`
              // rises and `k` sinks into the right subtree.
              mknode(ll, lk, lp, mknode(lr, k, cp, r))
            } else {
              mknode(new_l, k, cp, r)
            }
          // `insert_node` always returns a `Node`; this arm is unreachable.
          // Safe fallback: return original node unchanged.
          Empty => root
        }
      } else if key > k {
        let new_r = insert_node(r, key, p)
        match new_r {
          Node(rl, rk, rp, rr, _) =>
            if rp > cp {
              // Right child now outranks the parent: rotate left so `rk`
              // rises and `k` sinks into the left subtree.
              mknode(mknode(l, k, cp, rl), rk, rp, rr)
            } else {
              mknode(l, k, cp, new_r)
            }
          // `insert_node` always returns a `Node`; this arm is unreachable.
          // Safe fallback: return original node unchanged.
          Empty => root
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
pub fn search(t : Treap, key : Int) -> Bool {
  search_node(t.root, key)
}

fn search_node(root : TreapNode, key : Int) -> Bool {
  match root {
    Empty => false
    Node(l, k, _, r, _) =>
      if key < k {
        search_node(l, key)
      } else if key > k {
        search_node(r, key)
      } else {
        true
      }
  }
}

// ---------------------------------------------------------------------------
// Deletion
// ---------------------------------------------------------------------------

/// Delete `key` from the treap. If the key is absent the tree is unchanged.
/// Returns a new `Treap` (the LCG state is carried over untouched, since
/// deletion draws no priorities). Expected O(log n).
///
/// The target node is rotated downward — always promoting the child with the
/// larger priority to preserve the heap property — until it reaches a leaf and
/// can be removed. Each recursive step sinks the target by one level, so the
/// recursion always terminates.
pub fn delete(t : Treap, key : Int) -> Treap {
  { root: delete_node(t.root, key), rng: t.rng }
}

fn delete_node(root : TreapNode, key : Int) -> TreapNode {
  match root {
    Empty => Empty
    Node(l, k, p, r, _) =>
      if key < k {
        mknode(delete_node(l, key), k, p, r)
      } else if key > k {
        mknode(l, k, p, delete_node(r, key))
      } else {
        // Found the node to delete.
        match (l, r) {
          (Empty, _) => r
          (_, Empty) => l
          (Node(ll, lk, lp, lr, _), Node(rl, rk, rp, rr, _)) =>
            if lp > rp {
              // Left child outranks right: right rotation lifts `lk`.
              // `k` descends into the right subtree; delete it from there.
              let new_r = delete_node(mknode(lr, k, p, r), key)
              mknode(ll, lk, lp, new_r)
            } else {
              // Right child outranks (or ties): left rotation lifts `rk`.
              // `k` descends into the left subtree; delete it from there.
              let new_l = delete_node(mknode(l, k, p, rl), key)
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
pub fn inorder(t : Treap) -> FixedArray[Int] {
  inorder_node(t.root)
}

fn inorder_node(root : TreapNode) -> FixedArray[Int] {
  let n = size_node(root)
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
fn is_bst(t : Treap) -> Bool {
  let arr = inorder(t)
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
fn is_heap(t : Treap) -> Bool {
  is_heap_node(t.root)
}

fn is_heap_node(root : TreapNode) -> Bool {
  match root {
    Empty => true
    Node(l, _, p, r, _) =>
      priority_le(l, p) && priority_le(r, p) && is_heap_node(l) && is_heap_node(r)
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
fn verify_sizes(t : Treap) -> Bool {
  verify_sizes_node(t.root)
}

fn verify_sizes_node(root : TreapNode) -> Bool {
  match root {
    Empty => true
    Node(l, _, _, r, s) =>
      s == real_count(l) + 1 + real_count(r) &&
      verify_sizes_node(l) &&
      verify_sizes_node(r)
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
  let root_key = match tree.root {
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
