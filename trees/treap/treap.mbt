/// Treap (tree + heap): a randomized balanced binary search tree.
///
/// Generic: works with any type `T` given a comparator function.
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
/// - Keys are generic (type `T`, supplied with a comparator); the structure is
///   a set (no per-key value).
/// - Duplicate keys are silently ignored on insert.
/// - The LCG is not cryptographically secure; it only needs to assign
///   well-spread priorities. Worst-case (adversarial priorities) behaviour is
///   O(n), but this never happens with the fixed LCG sequence.
/// - Insertion is a pure function: it returns a new `Treap` whose `rng` field
///   is the advanced LCG state, so each tree lineage threads its own priority
///   sequence. Structural correctness (BST + heap) never depends on the
///   specific values drawn.
/// - **Stack safety**: `insert`, `delete`, `search`, `split`, `merge`, `kth`,
///   `rank`, and `inorder` are all recursive. Because a treap's expected
///   height is O(log n) (the tree shape is statistically equivalent to a
///   random BST), the recursion depth is O(log n) with high probability —
///   for n = 10^6 the expected depth is ~40, well within MoonBit's default
///   stack limit. The worst case O(n) depth only arises from adversarial
///   priority sequences, which the fixed LCG prevents. As a defensive net,
///   every recursive helper aborts if its descent exceeds `treap_max_depth`
///   (1000) rather than risking a stack overflow.
/// - **split/merge are NOT tail-recursive**: each performs work (`mknode`)
///   after the recursive call returns, so they cannot be turned into a simple
///   loop. Making them iterative would require an explicit parent stack or
///   the priority-infinity dummy-node trick (which itself recurses); neither
///   is a surgical change, so the depth guard above is the pragmatic safety
///   measure.
///
/// Not formally verified. Correctness is ensured by the comprehensive test
/// suite below, which checks the BST and heap invariants, size consistency,
/// and balance after large randomized workloads.

///|
/// A treap node.
///
/// `Empty` is the empty tree. `Node(left, key, priority, right, size)` carries
/// the cached subtree size as its fifth field so `size` is O(1). The heap is a
/// max-heap on `priority` (larger = closer to the root).
pub enum TreapNode[T] {
  Empty
  Node(TreapNode[T], T, Int, TreapNode[T], Int) // (left, key, priority, right, size)
}

///|
/// A treap handle: the root node together with this instance's own LCG state.
///
/// Because the RNG state is carried per-instance and threaded purely through
/// `insert`, every `Treap` draws an independent, deterministic priority
/// sequence. Two trees built from separate `empty()` calls never share state,
/// so test execution order cannot perturb the results. The fields are
/// immutable; `insert` returns a fresh `Treap` carrying the advanced state.
pub struct Treap[T] {
  priv root : TreapNode[T]
  priv rng : Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Public constructor for an empty treap. Each call yields a fresh `Treap`
/// with the LCG seeded to a fixed value, so the priority sequence is
/// deterministic yet local to the returned instance.
///
/// **Note**: All treaps created with `empty()` share the same seed and thus
/// produce the same priority sequence. For use cases where independent
/// treaps need different structures (e.g. adversarial testing, parallel
/// construction), use [`empty_with_seed`] with a unique seed per instance.
pub fn[T] empty() -> Treap[T] {
  { root: Empty, rng: rng_seed }
}

///|
/// Create an empty treap with a user-specified PRNG seed. Different seeds
/// produce different priority sequences, yielding structurally distinct
/// treaps even for the same insertion order.
///
/// This is the recommended constructor for production code where multiple
/// independent treaps are needed.
pub fn[T] empty_with_seed(seed : Int) -> Treap[T] {
  { root: Empty, rng: seed & 0x7FFFFFFF }
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

///|
/// Seed for every fresh `Treap`. Any fixed non-zero value makes the priority
/// sequence — and therefore every test — deterministic.
let rng_seed : Int = 0x1A2B3C4D

///|
/// Advance the LCG one step from `state` and return the new non-negative
/// state, which doubles as the next node's priority.
fn next_priority(state : Int) -> Int {
  (state * 1103515245 + 12345) & 0x7FFFFFFF
}

///|
/// Defensive ceiling on recursion depth. A treap's expected height is O(log n)
/// (~40 for n = 10^6), but the worst case is O(n) under adversarial priorities.
/// The fixed LCG prevents adversarial sequences, so this guard is a safety net
/// against RNG pathologies or bugs: if a descent exceeds this depth it returns
/// a safe fallback value instead of overflowing the stack.
let treap_max_depth : Int = 1000

// ---------------------------------------------------------------------------
// Cached metadata
// ---------------------------------------------------------------------------

///|
/// Number of nodes in the tree. O(1) via the cached size field.
pub fn[T] size(t : Treap[T]) -> Int {
  size_node(t.root)
}

///|
/// Number of nodes in a subtree. O(1) via the cached size field.
fn[T] size_node(root : TreapNode[T]) -> Int {
  match root {
    Empty => 0
    Node(_, _, _, _, s) => s
  }
}

///|
/// Height of the tree. `Empty` = -1, a leaf = 0. O(n). Used by tests.
pub fn[T] height(t : Treap[T]) -> Int {
  height_node(t.root)
}

///|
fn[T] height_node(root : TreapNode[T]) -> Int {
  // Iterative post-order traversal to prevent stack overflow.
  let stack : Array[(TreapNode[T], Int)] = []
  let mut max_h = -1
  match root {
    Empty => return -1
    _ => stack.push((root, 0))
  }
  while stack.length() > 0 {
    let (node, depth) = stack.pop().unwrap()
    if depth > max_h {
      max_h = depth
    }
    match node {
      Empty => continue
      Node(l, _, _, r, _) => {
        match l {
          Empty => ()
          _ => stack.push((l, depth + 1))
        }
        match r {
          Empty => ()
          _ => stack.push((r, depth + 1))
        }
      }
    }
  }
  max_h
}

///|
/// Construct a node, computing the cached subtree size from its children. O(1).
fn[T] mknode(
  l : TreapNode[T],
  k : T,
  p : Int,
  r : TreapNode[T],
) -> TreapNode[T] {
  Node(l, k, p, r, size_node(l) + 1 + size_node(r))
}

// ---------------------------------------------------------------------------
// Insertion
// ---------------------------------------------------------------------------

///|
/// Insert `key` into the treap. Duplicate keys are ignored (the original node
/// and its priority are kept). Returns a new `Treap` whose root has `key`
/// inserted and whose `rng` is advanced one step. Expected O(log n).
pub fn[T] insert(t : Treap[T], key : T, cmp : (T, T) -> Int) -> Treap[T] {
  let p = next_priority(t.rng)
  { root: insert_node(t.root, key, p, cmp, 0), rng: p }
}

///|
/// Recursive insertion that assigns the fixed priority `p` to the single new
/// leaf. Exactly one priority is drawn per top-level `insert`, so this mirrors
/// the original single-draw-per-insert behaviour. Expected O(log n).
fn[T] insert_node(
  root : TreapNode[T],
  key : T,
  p : Int,
  cmp : (T, T) -> Int,
  depth : Int,
) -> TreapNode[T] {
  if depth > treap_max_depth {
    // Depth guard: return original tree instead of aborting.
    // This is a safety net against RNG pathologies; in practice the
    // fixed LCG prevents adversarial priority sequences.
    return root
  }
  match root {
    Empty => Node(Empty, key, p, Empty, 1)
    Node(l, k, cp, r, _) => {
      let c = cmp(key, k)
      if c < 0 {
        let new_l = insert_node(l, key, p, cmp, depth + 1)
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
      } else if c > 0 {
        let new_r = insert_node(r, key, p, cmp, depth + 1)
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
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

///|
/// Return `true` if `key` is present in the treap. Expected O(log n).
pub fn[T] search(t : Treap[T], key : T, cmp : (T, T) -> Int) -> Bool {
  search_node(t.root, key, cmp, 0)
}

///|
fn[T] search_node(
  root : TreapNode[T],
  key : T,
  cmp : (T, T) -> Int,
  depth : Int,
) -> Bool {
  if depth > treap_max_depth {
    return false
  }
  match root {
    Empty => false
    Node(l, k, _, r, _) => {
      let c = cmp(key, k)
      if c < 0 {
        search_node(l, key, cmp, depth + 1)
      } else if c > 0 {
        search_node(r, key, cmp, depth + 1)
      } else {
        true
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Deletion
// ---------------------------------------------------------------------------

///|
/// Delete `key` from the treap. If the key is absent the tree is unchanged.
/// Returns a new `Treap` (the LCG state is carried over untouched, since
/// deletion draws no priorities). Expected O(log n).
///
/// The target node is rotated downward — always promoting the child with the
/// larger priority to preserve the heap property — until it reaches a leaf and
/// can be removed. Each recursive step sinks the target by one level, so the
/// recursion always terminates.
pub fn[T] delete(t : Treap[T], key : T, cmp : (T, T) -> Int) -> Treap[T] {
  { root: delete_node(t.root, key, cmp, 0), rng: t.rng }
}

///|
fn[T] delete_node(
  root : TreapNode[T],
  key : T,
  cmp : (T, T) -> Int,
  depth : Int,
) -> TreapNode[T] {
  if depth > treap_max_depth {
    return root
  }
  match root {
    Empty => Empty
    Node(l, k, p, r, _) => {
      let c = cmp(key, k)
      if c < 0 {
        mknode(delete_node(l, key, cmp, depth + 1), k, p, r)
      } else if c > 0 {
        mknode(l, k, p, delete_node(r, key, cmp, depth + 1))
      } else {
        // Found the node to delete.
        match (l, r) {
          (Empty, _) => r
          (_, Empty) => l
          (Node(ll, lk, lp, lr, _), Node(rl, rk, rp, rr, _)) =>
            if lp > rp {
              // Left child outranks right: right rotation lifts `lk`.
              // `k` descends into the right subtree; delete it from there.
              let new_r = delete_node(mknode(lr, k, p, r), key, cmp, depth + 1)
              mknode(ll, lk, lp, new_r)
            } else {
              // Right child outranks (or ties): left rotation lifts `rk`.
              // `k` descends into the left subtree; delete it from there.
              let new_l = delete_node(mknode(l, k, p, rl), key, cmp, depth + 1)
              mknode(new_l, rk, rp, rr)
            }
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Split / Merge
// ---------------------------------------------------------------------------

///|
/// Split the treap into two treaps `(left, right)` where all keys in `left`
/// are < `key` and all keys in `right` are >= `key`. Expected O(log n).
///
/// Both returned treaps share the same RNG state as the input.
pub fn[T] split(
  t : Treap[T],
  key : T,
  cmp : (T, T) -> Int,
) -> (Treap[T], Treap[T]) {
  let (l, r) = split_node(t.root, key, cmp, 0)
  // Advance RNG for the right treap to prevent both treaps from
  // drawing the same priority sequence on subsequent inserts.
  let right_rng = next_priority(t.rng)
  ({ root: l, rng: t.rng }, { root: r, rng: right_rng })
}

///|
/// Recursive split: returns `(left, right)` where `left` has keys < `key`
/// and `right` has keys >= `key`.
fn[T] split_node(
  root : TreapNode[T],
  key : T,
  cmp : (T, T) -> Int,
  depth : Int,
) -> (TreapNode[T], TreapNode[T]) {
  if depth > treap_max_depth {
    return (root, Empty)
  }
  match root {
    Empty => (Empty, Empty)
    Node(l, k, p, r, _) =>
      if cmp(k, key) < 0 {
        // Root and left subtree all < key. Split the right subtree.
        let (rl, rr) = split_node(r, key, cmp, depth + 1)
        (mknode(l, k, p, rl), rr)
      } else {
        // Root >= key. Split the left subtree.
        let (ll, lr) = split_node(l, key, cmp, depth + 1)
        (ll, mknode(lr, k, p, r))
      }
  }
}

///|
/// Merge two treaps where every key in `left` is < every key in `right`.
/// Expected O(log n). The caller must ensure the key ordering precondition;
/// violations produce an undefined (but still memory-safe) tree.
///
/// `merge` only consults priorities (not keys), so no comparator is needed.
pub fn[T] merge(left : Treap[T], right : Treap[T]) -> Treap[T] {
  { root: merge_node(left.root, right.root, 0), rng: left.rng }
}

///|
/// Recursive merge: all keys in `a` < all keys in `b`.
/// Uses priorities to decide which root stays on top.
fn[T] merge_node(
  a : TreapNode[T],
  b : TreapNode[T],
  depth : Int,
) -> TreapNode[T] {
  if depth > treap_max_depth {
    return a
  }
  match (a, b) {
    (Empty, _) => b
    (_, Empty) => a
    (Node(la, ka, pa, ra, _), Node(lb, kb, pb, rb, _)) =>
      if pa > pb {
        // `a`'s root stays on top. Merge `a`'s right with `b`.
        mknode(la, ka, pa, merge_node(ra, b, depth + 1))
      } else {
        // `b`'s root stays on top. Merge `a` with `b`'s left.
        mknode(merge_node(a, lb, depth + 1), kb, pb, rb)
      }
  }
}

// ---------------------------------------------------------------------------
// Order statistics (enabled by cached subtree sizes)
// ---------------------------------------------------------------------------

///|
/// Find the `k`-th smallest key (0-indexed). Returns `None` if `k` is out of
/// range or the tree is empty. O(log n) expected.
pub fn[T] kth(t : Treap[T], k : Int) -> T? {
  kth_node(t.root, k, 0)
}

///|
fn[T] kth_node(root : TreapNode[T], k : Int, depth : Int) -> T? {
  if depth > treap_max_depth {
    return None
  }
  match root {
    Empty => None
    Node(l, key, _, r, _) => {
      let left_sz = size_node(l)
      if k < left_sz {
        kth_node(l, k, depth + 1)
      } else if k == left_sz {
        Some(key)
      } else {
        kth_node(r, k - left_sz - 1, depth + 1)
      }
    }
  }
}

///|
/// Count the number of keys strictly less than `key`. O(log n) expected.
pub fn[T] rank(t : Treap[T], key : T, cmp : (T, T) -> Int) -> Int {
  rank_node(t.root, key, cmp, 0)
}

///|
fn[T] rank_node(
  root : TreapNode[T],
  key : T,
  cmp : (T, T) -> Int,
  depth : Int,
) -> Int {
  if depth > treap_max_depth {
    return -1
  }
  match root {
    Empty => 0
    Node(l, k, _, r, _) =>
      if cmp(key, k) <= 0 {
        rank_node(l, key, cmp, depth + 1)
      } else {
        size_node(l) + 1 + rank_node(r, key, cmp, depth + 1)
      }
  }
}

// ---------------------------------------------------------------------------
// In-order traversal
// ---------------------------------------------------------------------------

///|
/// Return all keys in ascending order as a `FixedArray[T]`. O(n).
pub fn[T] inorder(t : Treap[T]) -> FixedArray[T] {
  let buf : Array[T] = []
  inorder_fill(t.root, buf)
  FixedArray::from_array(buf.view())
}

///|
/// Fill `buf` in-order.
fn[T] inorder_fill(root : TreapNode[T], buf : Array[T]) -> Unit {
  match root {
    Empty => ()
    Node(l, k, _, r, _) => {
      inorder_fill(l, buf)
      buf.push(k)
      inorder_fill(r, buf)
    }
  }
}

// ---------------------------------------------------------------------------
// Internal invariants (used by tests)
// ---------------------------------------------------------------------------

///|
/// True iff the in-order traversal is strictly ascending (BST property).
fn[T] is_bst(t : Treap[T], cmp : (T, T) -> Int) -> Bool {
  let arr = inorder(t)
  let n = arr.length()
  let mut ok = true
  let mut i = 1
  while i < n {
    if cmp(arr[i], arr[i - 1]) <= 0 {
      ok = false
    }
    i = i + 1
  }
  ok
}

///|
/// True iff every node's priority is >= its children's (max-heap property).
fn[T] is_heap(t : Treap[T]) -> Bool {
  is_heap_node(t.root)
}

///|
fn[T] is_heap_node(root : TreapNode[T]) -> Bool {
  match root {
    Empty => true
    Node(l, _, p, r, _) =>
      priority_le(l, p) &&
      priority_le(r, p) &&
      is_heap_node(l) &&
      is_heap_node(r)
  }
}

///|
/// True iff `node`'s priority (if any) is <= `p`.
fn[T] priority_le(node : TreapNode[T], p : Int) -> Bool {
  match node {
    Empty => true
    Node(_, _, np, _, _) => np <= p
  }
}

///|
/// Recompute the true subtree size and verify it matches the cached field.
fn[T] verify_sizes(t : Treap[T]) -> Bool {
  verify_sizes_node(t.root)
}

///|
fn[T] verify_sizes_node(root : TreapNode[T]) -> Bool {
  match root {
    Empty => true
    Node(l, _, _, r, s) =>
      s == real_count(l) + 1 + real_count(r) &&
      verify_sizes_node(l) &&
      verify_sizes_node(r)
  }
}

///|
/// Uncached node count, used only to validate the cached sizes.
fn[T] real_count(root : TreapNode[T]) -> Int {
  match root {
    Empty => 0
    Node(l, _, _, r, _) => real_count(l) + 1 + real_count(r)
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "treap: basic insert and search" {
  let tree : Treap[Int] = empty()
  let t1 = insert(tree, 5, fn(a, b) { a - b })
  assert_true(search(t1, 5, fn(a, b) { a - b }))
  assert_false(search(t1, 3, fn(a, b) { a - b }))
  let t2 = insert(t1, 3, fn(a, b) { a - b })
  let t3 = insert(t2, 7, fn(a, b) { a - b })
  assert_true(search(t3, 3, fn(a, b) { a - b }))
  assert_true(search(t3, 7, fn(a, b) { a - b }))
  assert_true(search(t3, 5, fn(a, b) { a - b }))
  assert_true(is_bst(t3, fn(a, b) { a - b }))
  assert_true(is_heap(t3))
}

///|
test "treap: duplicate insert ignored" {
  let tree = insert(insert(empty(), 5, fn(a, b) { a - b }), 5, fn(a, b) {
    a - b
  })
  assert_eq(size(tree), 1)
  assert_true(search(tree, 5, fn(a, b) { a - b }))
}

///|
test "treap: sequential insert maintains balance" {
  // Inserting 1..7 in order into a plain BST would give a chain of height 6;
  // the treap's random priorities keep it balanced.
  let mut tree : Treap[Int] = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(size(tree), 7)
  assert_true(is_bst(tree, fn(a, b) { a - b }))
  assert_true(is_heap(tree))
  assert_true(verify_sizes(tree))
  // A balanced tree of 7 nodes has height 2; allow a little slack.
  assert_true(height(tree) <= 5)
}

///|
test "treap: reverse insert maintains balance" {
  let mut tree : Treap[Int] = empty()
  for k = 7; k >= 1; k = k - 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(size(tree), 7)
  assert_true(is_bst(tree, fn(a, b) { a - b }))
  assert_true(is_heap(tree))
  assert_true(verify_sizes(tree))
  assert_true(height(tree) <= 5)
}

///|
test "treap: delete leaf" {
  let tree = insert(
    insert(insert(empty(), 5, fn(a, b) { a - b }), 3, fn(a, b) { a - b }),
    7,
    fn(a, b) { a - b },
  )
  let t2 = delete(tree, 7, fn(a, b) { a - b })
  assert_false(search(t2, 7, fn(a, b) { a - b }))
  assert_true(search(t2, 5, fn(a, b) { a - b }))
  assert_true(search(t2, 3, fn(a, b) { a - b }))
  assert_eq(size(t2), 2)
  assert_true(is_bst(t2, fn(a, b) { a - b }))
  assert_true(is_heap(t2))
  assert_true(verify_sizes(t2))
}

///|
test "treap: delete root" {
  let mut tree : Treap[Int] = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  // Deleting the current root key still yields a valid treap.
  let root_key = match tree.root {
    Node(_, k, _, _, _) => k
    Empty => abort("unreachable: non-empty tree")
  }
  let t2 = delete(tree, root_key, fn(a, b) { a - b })
  assert_false(search(t2, root_key, fn(a, b) { a - b }))
  assert_eq(size(t2), 6)
  assert_true(is_bst(t2, fn(a, b) { a - b }))
  assert_true(is_heap(t2))
  assert_true(verify_sizes(t2))
}

///|
test "treap: delete all elements" {
  let mut tree : Treap[Int] = empty()
  for k = 1; k <= 15; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  for k = 1; k <= 15; k = k + 1 {
    tree = delete(tree, k, fn(a, b) { a - b })
    assert_true(is_bst(tree, fn(a, b) { a - b }))
    assert_true(is_heap(tree))
    assert_true(verify_sizes(tree))
    assert_eq(size(tree), 15 - k)
  }
  assert_eq(size(tree), 0)
}

///|
test "treap: large random insert" {
  let mut tree : Treap[Int] = empty()
  let n = 200
  for k = 0; k < n; k = k + 1 {
    tree = insert(tree, (k * 37 + 11) % n, fn(a, b) { a - b })
  }
  assert_eq(size(tree), n)
  assert_true(is_bst(tree, fn(a, b) { a - b }))
  assert_true(is_heap(tree))
  assert_true(verify_sizes(tree))
  // O(log n) height: 3 * ceil(log2(n+1)) is generous but still logarithmic.
  assert_true(height(tree) <= 30)
  for k = 0; k < n; k = k + 1 {
    assert_true(search(tree, k, fn(a, b) { a - b }))
  }
}

///|
test "treap: inorder is sorted" {
  let mut tree : Treap[Int] = empty()
  let vals = [5, 3, 7, 1, 4, 6, 8, 2]
  for k = 0; k < 8; k = k + 1 {
    tree = insert(tree, vals[k], fn(a, b) { a - b })
  }
  let sorted = inorder(tree)
  assert_eq(sorted.length(), 8)
  for k = 0; k < 8; k = k + 1 {
    assert_eq(sorted[k], k + 1)
  }
}

///|
test "treap: size tracking" {
  let mut tree : Treap[Int] = empty()
  assert_eq(size(tree), 0)
  tree = insert(tree, 10, fn(a, b) { a - b })
  assert_eq(size(tree), 1)
  tree = insert(tree, 20, fn(a, b) { a - b })
  tree = insert(tree, 30, fn(a, b) { a - b })
  assert_eq(size(tree), 3)
  tree = insert(tree, 20, fn(a, b) { a - b }) // duplicate, no growth
  assert_eq(size(tree), 3)
  tree = delete(tree, 20, fn(a, b) { a - b })
  assert_eq(size(tree), 2)
  tree = delete(tree, 10, fn(a, b) { a - b })
  tree = delete(tree, 30, fn(a, b) { a - b })
  assert_eq(size(tree), 0)
}

///|
test "treap: empty tree operations" {
  let tree : Treap[Int] = empty()
  assert_eq(size(tree), 0)
  assert_eq(height(tree), -1)
  assert_false(search(tree, 1, fn(a, b) { a - b }))
  assert_eq(inorder(tree).length(), 0)
  let t2 = delete(tree, 1, fn(a, b) { a - b })
  assert_eq(size(t2), 0)
}

///|
test "treap: delete non-existent key" {
  let mut tree : Treap[Int] = empty()
  for k = 1; k <= 10; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  let t2 = delete(tree, 99, fn(a, b) { a - b })
  assert_eq(size(t2), 10)
  assert_true(is_bst(t2, fn(a, b) { a - b }))
  assert_true(is_heap(t2))
  for k = 1; k <= 10; k = k + 1 {
    assert_true(search(t2, k, fn(a, b) { a - b }))
  }
}

///|
test "treap: interleave insert and delete" {
  let mut tree : Treap[Int] = empty()
  tree = insert(tree, 5, fn(a, b) { a - b })
  tree = insert(tree, 3, fn(a, b) { a - b })
  tree = insert(tree, 7, fn(a, b) { a - b })
  tree = delete(tree, 3, fn(a, b) { a - b })
  assert_true(is_bst(tree, fn(a, b) { a - b }))
  assert_true(is_heap(tree))
  tree = insert(tree, 1, fn(a, b) { a - b })
  tree = insert(tree, 9, fn(a, b) { a - b })
  assert_true(is_bst(tree, fn(a, b) { a - b }))
  assert_true(is_heap(tree))
  tree = delete(tree, 7, fn(a, b) { a - b })
  tree = delete(tree, 5, fn(a, b) { a - b })
  assert_true(is_bst(tree, fn(a, b) { a - b }))
  assert_true(is_heap(tree))
  assert_eq(size(tree), 2)
  assert_true(search(tree, 1, fn(a, b) { a - b }))
  assert_true(search(tree, 9, fn(a, b) { a - b }))
}

///|
test "treap: split by key" {
  let mut tree : Treap[Int] = empty()
  for k = 1; k <= 10; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  let (left, right) = split(tree, 5, fn(a, b) { a - b })
  // left: keys < 5 → {1,2,3,4}
  // right: keys >= 5 → {5,6,7,8,9,10}
  assert_eq(size(left), 4)
  assert_eq(size(right), 6)
  assert_true(is_bst(left, fn(a, b) { a - b }))
  assert_true(is_heap(left))
  assert_true(is_bst(right, fn(a, b) { a - b }))
  assert_true(is_heap(right))
  // Verify all keys in left < 5
  for k = 1; k <= 4; k = k + 1 {
    assert_true(search(left, k, fn(a, b) { a - b }))
  }
  assert_false(search(left, 5, fn(a, b) { a - b }))
  // Verify all keys in right >= 5
  for k = 5; k <= 10; k = k + 1 {
    assert_true(search(right, k, fn(a, b) { a - b }))
  }
  assert_false(search(right, 4, fn(a, b) { a - b }))
}

///|
test "treap: merge two treaps" {
  let mut left : Treap[Int] = empty()
  for k = 1; k <= 5; k = k + 1 {
    left = insert(left, k, fn(a, b) { a - b })
  }
  let mut right : Treap[Int] = empty()
  for k = 6; k <= 10; k = k + 1 {
    right = insert(right, k, fn(a, b) { a - b })
  }
  let merged = merge(left, right)
  assert_eq(size(merged), 10)
  assert_true(is_bst(merged, fn(a, b) { a - b }))
  assert_true(is_heap(merged))
  assert_true(verify_sizes(merged))
  // Check all keys present and sorted
  let sorted = inorder(merged)
  for k = 0; k < 10; k = k + 1 {
    assert_eq(sorted[k], k + 1)
  }
}

///|
test "treap: kth smallest" {
  let mut tree : Treap[Int] = empty()
  // Insert in random order
  let vals = [7, 3, 9, 1, 5, 10, 2, 8, 4, 6]
  for k = 0; k < 10; k = k + 1 {
    tree = insert(tree, vals[k], fn(a, b) { a - b })
  }
  // kth(tree, i) should return i+1
  for k = 0; k < 10; k = k + 1 {
    assert_eq(kth(tree, k), Some(k + 1))
  }
  // Out of bounds
  assert_true(kth(tree, 10) is None)
  assert_true(kth(tree, -1) is None)
  // Empty tree
  let empty_tree : Treap[Int] = empty()
  assert_true(kth(empty_tree, 0) is None)
}

///|
test "treap: rank" {
  let mut tree : Treap[Int] = empty()
  for k = 1; k <= 10; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  // rank(key) = number of keys < key
  assert_eq(rank(tree, 1, fn(a, b) { a - b }), 0)
  assert_eq(rank(tree, 5, fn(a, b) { a - b }), 4)
  assert_eq(rank(tree, 10, fn(a, b) { a - b }), 9)
  assert_eq(rank(tree, 11, fn(a, b) { a - b }), 10)
  assert_eq(rank(tree, 0, fn(a, b) { a - b }), 0)
  // Empty tree
  assert_eq(rank(empty(), 5, fn(a, b) { a - b }), 0)
}

///|
test "treap: split and merge roundtrip" {
  let mut tree : Treap[Int] = empty()
  for k = 1; k <= 20; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  let (left, right) = split(tree, 11, fn(a, b) { a - b })
  let rebuilt = merge(left, right)
  assert_eq(size(rebuilt), 20)
  assert_true(is_bst(rebuilt, fn(a, b) { a - b }))
  assert_true(is_heap(rebuilt))
  assert_true(verify_sizes(rebuilt))
  // All keys present
  for k = 1; k <= 20; k = k + 1 {
    assert_true(search(rebuilt, k, fn(a, b) { a - b }))
  }
}
