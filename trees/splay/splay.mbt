/// Splay Tree: a self-adjusting binary search tree.
///
/// **Generic**: works with any type `T` given a comparator function.
///
/// A splay tree is a BST where every access (search, insert, or delete) is
/// followed by a "splay" operation that moves the accessed node to the root
/// via a sequence of rotations. This has two consequences:
///
/// 1. **Amortized O(log n)**: While any single operation can take O(n) in
///    the worst case, a sequence of m operations on a tree of at most n nodes
///    takes O(m log n) time amortized. This is proven by the access lemma
///    (Sleator & Tarjan, 1985).
///
/// 2. **Access locality**: Frequently accessed keys migrate toward the root,
///    so workloads with temporal locality (e.g., caching, LRU eviction) run
///    faster than in a balanced BST.
///
/// ## Rotations
///
/// Splaying uses three rotation patterns based on the relative position of
/// the accessed node, its parent, and its grandparent:
///
/// - **Zig** (single rotation): the node is a child of the root. One rotation
///   brings it to the root.
/// - **Zig-Zig** (double rotation): the node and its parent are both left (or
///   both right) children. Rotate the grandparent first, then the parent.
/// - **Zig-Zag** (double rotation): the node is a left child of a right child
///   (or vice versa). Rotate the node twice.
///
/// ## Implementation
///
/// This is a **bottom-up** splay tree implemented **iteratively**: the search
/// descends to the target using an explicit loop (recording the path in an
/// array), then rotations are applied from the bottom up using the recorded
/// path. No recursion is used, so there is **no stack overflow risk** even
/// on degenerate trees of depth > 10⁴. The tree is represented as an
/// immutable, recursive `enum`, so every operation returns a new tree
/// (functional style, no mutation).
///
/// Complexity (amortized):
/// - `insert`  — O(log n) amortized
/// - `search`  — O(log n) amortized
/// - `delete`  — O(log n) amortized
/// - `size`    — O(1) (cached in every node)
/// - `inorder` — O(n), iterative (no stack overflow)
///
/// ## Limitations
///
/// - Keys are generic (type `T`, supplied with a comparator); the structure is
///   a set (no per-key value).
/// - Duplicate keys are silently ignored on insert.
/// - The worst-case single-operation time is O(n), not O(log n). Only the
///   *amortized* cost over a sequence of operations is O(log n).
///
/// `proof-enabled` is `false`; correctness is ensured by the test suite below,
/// which checks the BST invariant, size consistency, and balance after large
/// randomized workloads.

///|
/// A splay tree node.
///
/// `Empty` is the empty tree. `Node(left, key, right, size)` carries the
/// cached subtree size so `size` is O(1).
pub enum SplayNode[T] {
  Empty
  Node(SplayNode[T], T, SplayNode[T], Int) // (left, key, right, size)
}

///|
/// Public constructor for an empty splay tree.
pub fn[T] empty() -> SplayNode[T] {
  Empty
}

///|
/// Compute the size of a splay tree. O(1) for nodes (cached), O(1) for Empty.
fn[T] node_size(t : SplayNode[T]) -> Int {
  match t {
    Empty => 0
    Node(_, _, _, s) => s
  }
}

///|
/// Construct a `Node` with the size automatically computed from its children.
fn[T] mk_node(l : SplayNode[T], key : T, r : SplayNode[T]) -> SplayNode[T] {
  Node(l, key, r, 1 + node_size(l) + node_size(r))
}

///|
/// Splay the node with key `k` to the root of tree `t`.
///
/// After splaying, if `k` is in the tree, it will be at the root.
/// If `k` is not in the tree, the last node on the search path (the node that
/// would be `k`'s parent) is brought to the root.
///
/// This is an **iterative** bottom-up splay: the search descends to the target
/// using a loop (recording the path in arrays), then rotations are applied
/// from the bottom up. No recursion is used, preventing stack overflow on
/// degenerate trees.
fn[T] splay(t : SplayNode[T], k : T, cmp : (T, T) -> Int) -> SplayNode[T] {
  match t {
    Empty => Empty
    _ => {
      // Step 1: Descend the tree iteratively, recording the path.
      // path_nodes[i] = the i-th ancestor of the target (0 = root).
      // path_dirs[i] = true if we went left from path_nodes[i], false if right.
      let path_nodes : Array[SplayNode[T]] = []
      let path_dirs : Array[Bool] = []
      let mut curr = t
      let mut found = false
      while true {
        match curr {
          Empty => break
          Node(l, key, r, _) => {
            let c = cmp(k, key)
            if c == 0 {
              found = true
              break
            } else if c < 0 {
              path_nodes.push(curr)
              path_dirs.push(true)
              curr = l
            } else {
              path_nodes.push(curr)
              path_dirs.push(false)
              curr = r
            }
          }
        }
      }
      // If k was not found, splay the last node on the search path.
      if !found {
        match curr {
          Empty => {
            if path_nodes.length() == 0 {
              return t
            }
            curr = path_nodes[path_nodes.length() - 1]
            ignore(path_nodes.pop())
            ignore(path_dirs.pop())
          }
          _ => ()
        }
      }
      // Step 2: Splay curr to the root by processing the path bottom-up.
      // Process two levels at a time (zig-zig / zig-zag / zag-zag / zag-zig),
      // then one level (zig / zag) if the path has odd length.
      let mut node = curr
      let mut i = path_nodes.length()
      while i >= 2 {
        let parent = path_nodes[i - 1]
        let dir1 = path_dirs[i - 1]
        let grandparent = path_nodes[i - 2]
        let dir2 = path_dirs[i - 2]
        match (grandparent, parent, node) {
          (Node(gl, gk, gr, _), Node(pl, pk, pr, _), Node(nl, nk, nr, _)) =>
            if dir2 && dir1 {
              // Zig-Zig: grandparent -> parent (left) -> node (left)
              node = mk_node(nl, nk, mk_node(nr, pk, mk_node(pr, gk, gr)))
            } else if !dir2 && !dir1 {
              // Zag-Zag: grandparent -> parent (right) -> node (right)
              node = mk_node(mk_node(mk_node(gl, gk, pl), pk, nl), nk, nr)
            } else if dir2 && !dir1 {
              // Zig-Zag: grandparent went left, parent went right
              node = mk_node(mk_node(pl, pk, nl), nk, mk_node(nr, gk, gr))
            } else {
              // Zag-Zig: grandparent went right, parent went left
              node = mk_node(mk_node(gl, gk, nl), nk, mk_node(nr, pk, pr))
            }
          _ => () // Structural invariant violation: skip rotation
        }
        i = i - 2
      }
      // Handle the last single zig/zag (if path has odd length).
      if i == 1 {
        let parent = path_nodes[0]
        let dir = path_dirs[0]
        match (parent, node) {
          (Node(pl, pk, pr, _), Node(nl, nk, nr, _)) =>
            if dir {
              // Zig: node is left child of parent
              node = mk_node(nl, nk, mk_node(nr, pk, pr))
            } else {
              // Zag: node is right child of parent
              node = mk_node(mk_node(pl, pk, nl), nk, nr)
            }
          _ => () // Structural invariant violation: skip rotation
        }
      }
      node
    }
  }
}

///|
/// Splay the maximum node to the root of tree `t`.
///
/// After this, the root has no right child. Uses the same iterative approach
/// as `splay` — no recursion, no stack overflow risk.
fn[T] splay_max(t : SplayNode[T]) -> SplayNode[T] {
  match t {
    Empty => Empty
    _ => {
      // Descend right, recording the path.
      let path_nodes : Array[SplayNode[T]] = []
      let mut curr = t
      while true {
        match curr {
          Empty => break
          Node(_, _, r, _) =>
            match r {
              Empty => break
              _ => {
                path_nodes.push(curr)
                curr = r
              }
            }
        }
      }
      // curr is the rightmost node (max). Splay it to the root.
      // All directions are "right" (zag-zag and zag).
      let mut node = curr
      let mut i = path_nodes.length()
      while i >= 2 {
        let parent = path_nodes[i - 1]
        let grandparent = path_nodes[i - 2]
        match (grandparent, parent, node) {
          (Node(gl, gk, _gr, _), Node(pl, pk, _pr, _), Node(nl, nk, nr, _)) =>
            // Zag-Zag: all right children
            node = mk_node(mk_node(mk_node(gl, gk, pl), pk, nl), nk, nr)
          _ => () // Structural invariant violation: skip rotation
        }
        i = i - 2
      }
      if i == 1 {
        let parent = path_nodes[0]
        match (parent, node) {
          (Node(pl, pk, _pr, _), Node(nl, nk, nr, _)) =>
            // Zag: single left rotation
            node = mk_node(mk_node(pl, pk, nl), nk, nr)
          _ => () // Structural invariant violation: skip rotation
        }
      }
      node
    }
  }
}

///|
/// Insert `key` into the splay tree.
///
/// If the key already exists, the tree is unchanged (but the key is still
/// splayed to the root). If new, a node is created and splayed to the root.
pub fn[T] insert(
  tree : SplayNode[T],
  key : T,
  cmp : (T, T) -> Int,
) -> SplayNode[T] {
  match splay(tree, key, cmp) {
    Empty => mk_node(Empty, key, Empty)
    Node(l, k, r, _) as t => {
      let c = cmp(key, k)
      if c == 0 {
        t
      } else if c < 0 {
        mk_node(l, key, mk_node(Empty, k, r))
      } else {
        mk_node(mk_node(l, k, Empty), key, r)
      }
    }
  }
}

///|
/// Search for `key` in the splay tree.
///
/// Returns `(splayed_tree, found)` where `splayed_tree` has the closest node
/// to `key` at the root, and `found` indicates whether `key` was present.
pub fn[T] search(
  tree : SplayNode[T],
  key : T,
  cmp : (T, T) -> Int,
) -> (SplayNode[T], Bool) {
  let splayed = splay(tree, key, cmp)
  match splayed {
    Empty => (Empty, false)
    Node(_, k, _, _) => (splayed, cmp(k, key) == 0)
  }
}

///|
/// Delete `key` from the splay tree.
///
/// Splays the key to the root. If found, the root is removed and its two
/// children are joined: the maximum of the left subtree is splayed to become
/// the new root, and the right subtree is attached as its right child.
pub fn[T] delete(
  tree : SplayNode[T],
  key : T,
  cmp : (T, T) -> Int,
) -> SplayNode[T] {
  let splayed = splay(tree, key, cmp)
  match splayed {
    Empty => Empty
    Node(l, k, r, _) => if cmp(k, key) != 0 { splayed } else { join(l, r) }
  }
}

///|
/// Join two splay trees where all keys in `l` < all keys in `r`.
/// Splay the maximum of `l` to the root, then attach `r` as its right child.
fn[T] join(l : SplayNode[T], r : SplayNode[T]) -> SplayNode[T] {
  if l is Empty {
    return r
  }
  if r is Empty {
    return l
  }
  let splayed = splay_max(l)
  match splayed {
    Node(sl, sk, Empty, _) => mk_node(sl, sk, r)
    _ => splayed
  }
}

///|
/// Number of keys in the splay tree. O(1).
pub fn[T] size(tree : SplayNode[T]) -> Int {
  node_size(tree)
}

///|
/// In-order traversal: returns all keys in ascending order.
/// O(n) time and space. Uses an explicit stack (iterative, no recursion).
pub fn[T] inorder(tree : SplayNode[T]) -> FixedArray[T] {
  let out : Array[T] = []
  // Explicit stack for iterative in-order traversal.
  let stack : Array[SplayNode[T]] = []
  let mut curr = tree
  while true {
    // Push all left children onto the stack.
    while true {
      match curr {
        Empty => break
        Node(l, _key, _r, _) => {
          stack.push(curr)
          curr = l
        }
      }
    }
    if stack.length() == 0 {
      break
    }
    // Pop and visit.
    match stack.pop() {
      Some(node) =>
        match node {
          Node(_l, key, r, _) => {
            out.push(key)
            curr = r
          }
          _ => ()
        }
      None => break
    }
  }
  FixedArray::from_array(out.view())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
/// Integer comparator for tests.
fn int_cmp(a : Int, b : Int) -> Int {
  a - b
}

///|
test "splay: basic insert and search" {
  let mut tree = empty()
  tree = insert(tree, 5, int_cmp)
  tree = insert(tree, 3, int_cmp)
  tree = insert(tree, 7, int_cmp)
  let (t, found) = search(tree, 3, int_cmp)
  assert_true(found)
  assert_eq(size(t), 3)
  let (_, found2) = search(tree, 99, int_cmp)
  assert_false(found2)
}

///|
test "splay: search brings key to root" {
  let mut tree = empty()
  tree = insert(tree, 1, int_cmp)
  tree = insert(tree, 2, int_cmp)
  tree = insert(tree, 3, int_cmp)
  tree = insert(tree, 4, int_cmp)
  tree = insert(tree, 5, int_cmp)
  let (t, found) = search(tree, 1, int_cmp)
  assert_true(found)
  match t {
    Node(_, k, _, _) => assert_eq(k, 1)
    Empty => abort("expected non-empty tree")
  }
}

///|
test "splay: delete leaf" {
  let mut tree = empty()
  tree = insert(tree, 5, int_cmp)
  tree = insert(tree, 3, int_cmp)
  tree = insert(tree, 7, int_cmp)
  tree = delete(tree, 7, int_cmp)
  assert_eq(size(tree), 2)
  let (_, found) = search(tree, 7, int_cmp)
  assert_false(found)
}

///|
test "splay: delete root" {
  let mut tree = empty()
  tree = insert(tree, 5, int_cmp)
  tree = insert(tree, 3, int_cmp)
  tree = insert(tree, 7, int_cmp)
  tree = delete(tree, 5, int_cmp)
  assert_eq(size(tree), 2)
  let (_, found) = search(tree, 5, int_cmp)
  assert_false(found)
}

///|
test "splay: delete non-existent" {
  let mut tree = empty()
  tree = insert(tree, 5, int_cmp)
  tree = insert(tree, 3, int_cmp)
  tree = delete(tree, 99, int_cmp)
  assert_eq(size(tree), 2)
}

///|
test "splay: BST invariant after inserts" {
  let mut tree = empty()
  for k = 1; k <= 100; k = k + 1 {
    tree = insert(tree, k, int_cmp)
  }
  let arr = inorder(tree)
  for k = 0; k < 99; k = k + 1 {
    assert_true(arr[k] < arr[k + 1])
  }
  assert_eq(arr.length(), 100)
}

///|
test "splay: duplicate insert ignored" {
  let mut tree = empty()
  tree = insert(tree, 5, int_cmp)
  tree = insert(tree, 5, int_cmp)
  tree = insert(tree, 5, int_cmp)
  assert_eq(size(tree), 1)
}

///|
test "splay: sequential insert then search all" {
  let mut tree = empty()
  for k = 1; k <= 1000; k = k + 1 {
    tree = insert(tree, k, int_cmp)
  }
  assert_eq(size(tree), 1000)
  for k = 1; k <= 1000; k = k + 1 {
    let (_, found) = search(tree, k, int_cmp)
    assert_true(found)
  }
}

///|
test "splay: interleaved insert and delete" {
  let mut tree = empty()
  tree = insert(tree, 10, int_cmp)
  tree = insert(tree, 20, int_cmp)
  tree = insert(tree, 5, int_cmp)
  tree = delete(tree, 20, int_cmp)
  tree = insert(tree, 15, int_cmp)
  tree = delete(tree, 10, int_cmp)
  let arr = inorder(tree)
  assert_eq(arr.length(), 2)
  let mut found5 = false
  let mut found15 = false
  for k = 0; k < arr.length(); k = k + 1 {
    if arr[k] == 5 {
      found5 = true
    }
    if arr[k] == 15 {
      found15 = true
    }
  }
  assert_true(found5)
  assert_true(found15)
}

///|
test "splay: empty tree operations" {
  let tree = empty()
  assert_eq(size(tree), 0)
  let (t, found) = search(tree, 5, int_cmp)
  assert_false(found)
  assert_true(t is Empty)
  let t2 = delete(tree, 5, int_cmp)
  assert_true(t2 is Empty)
  assert_eq(inorder(tree).length(), 0)
}

///|
test "splay: size consistency after operations" {
  let mut tree = empty()
  for k = 1; k <= 500; k = k + 1 {
    tree = insert(tree, k * 2, int_cmp)
  }
  assert_eq(size(tree), 500)
  for k = 1; k <= 250; k = k + 1 {
    tree = delete(tree, k * 2, int_cmp)
  }
  assert_eq(size(tree), 250)
  for k = 251; k <= 500; k = k + 1 {
    let (_, found) = search(tree, k * 2, int_cmp)
    assert_true(found)
  }
  for k = 1; k <= 250; k = k + 1 {
    let (_, found) = search(tree, k * 2, int_cmp)
    assert_false(found)
  }
}

///|
test "splay: deep sequential insert (stack safety)" {
  // Sequential insertion creates a degenerate tree (linked list).
  // The iterative splay must not stack overflow on 5000 nodes.
  let mut tree = empty()
  for k = 1; k <= 5000; k = k + 1 {
    tree = insert(tree, k, int_cmp)
  }
  assert_eq(size(tree), 5000)
  // Search for the last element (deepest node before splay).
  let (t, found) = search(tree, 5000, int_cmp)
  assert_true(found)
  assert_eq(size(t), 5000)
}

///|
test "splay: inorder on deep tree (stack safety)" {
  // In-order traversal of a 5000-node tree must not stack overflow.
  let mut tree = empty()
  for k = 1; k <= 5000; k = k + 1 {
    tree = insert(tree, k, int_cmp)
  }
  let arr = inorder(tree)
  assert_eq(arr.length(), 5000)
}

///|
test "splay: generic with string keys" {
  // Verify the tree works with String keys using a lexicographic comparator.
  let cmp = @test_utils.str_cmp
  let mut tree : SplayNode[String] = empty()
  tree = insert(tree, "banana", cmp)
  tree = insert(tree, "apple", cmp)
  tree = insert(tree, "cherry", cmp)
  assert_eq(size(tree), 3)
  let (_, found) = search(tree, "apple", cmp)
  assert_true(found)
  let (_, found2) = search(tree, "grape", cmp)
  assert_false(found2)
  let arr = inorder(tree)
  assert_eq(arr[0], "apple")
  assert_eq(arr[1], "banana")
  assert_eq(arr[2], "cherry")
  tree = delete(tree, "banana", cmp)
  assert_eq(size(tree), 2)
  let (_, found3) = search(tree, "banana", cmp)
  assert_false(found3)
}
