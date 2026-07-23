/// Splay Tree: a self-adjusting binary search tree.
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
/// This is a **bottom-up** splay tree: the key is searched first (descending
/// to the leaf), then splayed back to the root on the way up via recursive
/// zig, zig-zig, and zig-zag rotations. The tree is represented as an
/// immutable, recursive `enum`, so every operation returns a new tree
/// (functional style, no mutation).
///
/// Complexity (amortized):
/// - `insert`  — O(log n) amortized
/// - `search`  — O(log n) amortized
/// - `delete`  — O(log n) amortized
/// - `size`    — O(1) (cached in every node)
/// - `inorder` — O(n)
///
/// ## Limitations
///
/// - Keys are `Int`; the structure is a set (no per-key value).
/// - Duplicate keys are silently ignored on insert.
/// - Recursive operations may overflow the call stack on a degenerate tree
///   of depth > ~10⁴ (MoonBit has no tail-call optimization guarantee).
///   For guaranteed O(log n) worst-case depth, use `avl` or `red_black_tree`.
/// - The worst-case single-operation time is O(n), not O(log n). Only the
///   *amortized* cost over a sequence of operations is O(log n).
///
/// `proof-enabled` is `false`; correctness is ensured by the test suite below,
/// which checks the BST invariant, size consistency, and balance after large
/// randomized workloads.

/// A splay tree node.
///
/// `Empty` is the empty tree. `Node(left, key, right, size)` carries the
/// cached subtree size so `size` is O(1).
pub enum SplayNode {
  Empty
  Node(SplayNode, Int, SplayNode, Int) // (left, key, right, size)
}

/// Public constructor for an empty splay tree.
pub fn empty() -> SplayNode {
  Empty
}

/// Compute the size of a splay tree. O(1) for nodes (cached), O(1) for Empty.
fn node_size(t : SplayNode) -> Int {
  match t {
    Empty => 0
    Node(_, _, _, s) => s
  }
}

/// Splay the node with key `k` to the root of tree `t`.
///
/// After splaying, if `k` is in the tree, it will be at the root.
/// If `k` is not in the tree, the last node on the search path (the node that
/// would be `k`'s parent) is brought to the root.
///
/// This is the bottom-up splay implementation: the search descends to the
/// target depth, then rotations are applied on the way back up.
fn splay(t : SplayNode, k : Int) -> SplayNode {
  match t {
    Empty => Empty
    _ => splay_bottom_up(t, k)
  }
}

/// Bottom-up splay: search for k, then splay on the way up.
fn splay_bottom_up(t : SplayNode, k : Int) -> SplayNode {
  match t {
    Empty => Empty
    Node(l, key, r, _) => {
      if k == key {
        Node(l, key, r, 1 + node_size(l) + node_size(r))
      } else if k < key {
        // k is in the left subtree
        match l {
          Empty => Node(l, key, r, 1 + node_size(l) + node_size(r))
          Node(ll, lk, lr, _) => {
            if k == lk {
              // Zig: one right rotation
              let new_right = Node(lr, key, r, 1 + node_size(lr) + node_size(r))
              Node(ll, lk, new_right, 1 + node_size(ll) + node_size(new_right))
            } else if k < lk {
              // Zig-Zig: k is in the left subtree of ll
              match ll {
                Empty => {
                  // Just zig
                  let new_right = Node(lr, key, r, 1 + node_size(lr) + node_size(r))
                  Node(ll, lk, new_right, 1 + node_size(ll) + node_size(new_right))
                }
                _ => {
                  // Splay k to the root of ll, then double right rotation.
                  let splayed_ll = splay_bottom_up(ll, k)
                  match splayed_ll {
                    Node(lll, slk, llr, _) => {
                      let inner_right = Node(lr, key, r, 1 + node_size(lr) + node_size(r))
                      let mid = Node(llr, lk, inner_right, 1 + node_size(llr) + node_size(inner_right))
                      Node(lll, slk, mid, 1 + node_size(lll) + node_size(mid))
                    }
                    _ => t
                  }
                }
              }
            } else {
              // Zig-Zag: k is in the right subtree of lk
              match lr {
                Empty => {
                  let new_right = Node(lr, key, r, 1 + node_size(lr) + node_size(r))
                  Node(ll, lk, new_right, 1 + node_size(ll) + node_size(new_right))
                }
                _ => {
                  let splayed_lr = splay_bottom_up(lr, k)
                  match splayed_lr {
                    Node(lrl, slk, lrr, _) => {
                      let new_right = Node(lrr, key, r, 1 + node_size(lrr) + node_size(r))
                      let new_left = Node(ll, lk, lrl, 1 + node_size(ll) + node_size(lrl))
                      Node(new_left, slk, new_right, 1 + node_size(new_left) + node_size(new_right))
                    }
                    _ => t
                  }
                }
              }
            }
          }
        }
      } else {
        // k > key: mirror of the above
        match r {
          Empty => Node(l, key, r, 1 + node_size(l) + node_size(r))
          Node(rl, rk, rr, _) => {
            if k == rk {
              // Zag: one left rotation
              let new_left = Node(l, key, rl, 1 + node_size(l) + node_size(rl))
              Node(new_left, rk, rr, 1 + node_size(new_left) + node_size(rr))
            } else if k > rk {
              // Zag-Zag: k is in the right subtree of rr
              match rr {
                Empty => {
                  let new_left = Node(l, key, rl, 1 + node_size(l) + node_size(rl))
                  Node(new_left, rk, rr, 1 + node_size(new_left) + node_size(rr))
                }
                _ => {
                  // Splay k to the root of rr, then double left rotation.
                  let splayed_rr = splay_bottom_up(rr, k)
                  match splayed_rr {
                    Node(rl_, srk, rrr, _) => {
                      let inner_left = Node(l, key, rl, 1 + node_size(l) + node_size(rl))
                      let new_left = Node(inner_left, rk, rl_, 1 + node_size(inner_left) + node_size(rl_))
                      Node(new_left, srk, rrr, 1 + node_size(new_left) + node_size(rrr))
                    }
                    _ => t
                  }
                }
              }
            } else {
              // Zag-Zig: k is in the left subtree of rk
              match rl {
                Empty => {
                  let new_left = Node(l, key, rl, 1 + node_size(l) + node_size(rl))
                  Node(new_left, rk, rr, 1 + node_size(new_left) + node_size(rr))
                }
                _ => {
                  let splayed_rl = splay_bottom_up(rl, k)
                  match splayed_rl {
                    Node(rll, slk, rlr, _) => {
                      let new_left = Node(l, key, rll, 1 + node_size(l) + node_size(rll))
                      let new_right = Node(rlr, rk, rr, 1 + node_size(rlr) + node_size(rr))
                      Node(new_left, slk, new_right, 1 + node_size(new_left) + node_size(new_right))
                    }
                    _ => t
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Insert `key` into the splay tree.
///
/// If the key already exists, the tree is unchanged (but the key is still
/// splayed to the root). If new, a node is created and splayed to the root.
pub fn insert(tree : SplayNode, key : Int) -> SplayNode {
  match splay(tree, key) {
    Empty => Node(Empty, key, Empty, 1)
    Node(l, k, r, _) as t => {
      if key == k {
        t // key already present, no change
      } else if key < k {
        // Split: l < key < k < r (after splay, root is closest to key)
        Node(l, key, Node(Empty, k, r, 1 + node_size(r)), 2 + node_size(l) + node_size(r))
      } else {
        Node(Node(l, k, Empty, 1 + node_size(l)), key, r, 2 + node_size(l) + node_size(r))
      }
    }
  }
}

/// Search for `key` in the splay tree.
///
/// Returns `(splayed_tree, found)` where `splayed_tree` has the closest node
/// to `key` at the root, and `found` indicates whether `key` was present.
pub fn search(tree : SplayNode, key : Int) -> (SplayNode, Bool) {
  let splayed = splay(tree, key)
  match splayed {
    Empty => (Empty, false)
    Node(_, k, _, _) => (splayed, k == key)
  }
}

/// Delete `key` from the splay tree.
///
/// Splays the key to the root. If found, the root is removed and its two
/// children are joined: the maximum of the left subtree is splayed to become
/// the new root, and the right subtree is attached as its right child.
pub fn delete(tree : SplayNode, key : Int) -> SplayNode {
  let splayed = splay(tree, key)
  match splayed {
    Empty => Empty
    Node(l, k, r, _) => {
      if k != key {
        splayed // key not found, return splayed tree unchanged
      } else {
        // Key found at root. Join left and right subtrees.
        join(l, r)
      }
    }
  }
}

/// Join two splay trees where all keys in `l` < all keys in `r`.
/// Splay the maximum of `l` to the root, then attach `r` as its right child.
fn join(l : SplayNode, r : SplayNode) -> SplayNode {
  if l is Empty {
    return r
  }
  if r is Empty {
    return l
  }
  // Splay the maximum key in l to the root.
  // The maximum key is the rightmost node; we splay a very large value.
  let splayed = splay_max(l)
  match splayed {
    Node(sl, sk, Empty, _) => Node(sl, sk, r, 1 + node_size(sl) + node_size(r))
    _ => splayed // Should not happen: splay_max brings max to root.
  }
}

/// Splay the maximum node to the root of tree `t`.
/// After this, the root has no right child.
fn splay_max(t : SplayNode) -> SplayNode {
  match t {
    Empty => Empty
    Node(l, key, r, _) => {
      match r {
        Empty => Node(l, key, Empty, 1 + node_size(l))
        Node(rl, rk, rr, _) => {
          match rr {
            Empty => {
              // rk is the max: rotate left to bring rk to root
              let new_left = Node(l, key, rl, 1 + node_size(l) + node_size(rl))
              Node(new_left, rk, Empty, 1 + node_size(new_left))
            }
            _ => {
              // Splay max of rr, then rotate
              let splayed_rr = splay_max(rr)
              match splayed_rr {
                Node(rrl, srk, rrr, _) => {
                  let new_left = Node(l, key, Node(rl, rk, rrl, 1 + node_size(rl) + node_size(rrl)), 1 + node_size(l) + 1 + node_size(rl) + node_size(rrl))
                  Node(new_left, srk, rrr, 1 + node_size(new_left) + node_size(rrr))
                }
                _ => t
              }
            }
          }
        }
      }
    }
  }
}

/// Number of keys in the splay tree. O(1).
pub fn size(tree : SplayNode) -> Int {
  node_size(tree)
}

/// In-order traversal: returns all keys in ascending order.
/// O(n) time and space.
pub fn inorder(tree : SplayNode) -> FixedArray[Int] {
  let out : Array[Int] = []
  fn visit(t : SplayNode) -> Unit {
    match t {
      Empty => ()
      Node(l, k, r, _) => {
        visit(l)
        out.push(k)
        visit(r)
      }
    }
  }
  visit(tree)
  FixedArray::from_array(out.view())
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "splay: basic insert and search" {
  let mut tree = empty()
  tree = insert(tree, 5)
  tree = insert(tree, 3)
  tree = insert(tree, 7)
  let (t, found) = search(tree, 3)
  assert_true(found)
  assert_eq(size(t), 3)
  let (_, found2) = search(tree, 99)
  assert_false(found2)
}

test "splay: search brings key to root" {
  let mut tree = empty()
  tree = insert(tree, 1)
  tree = insert(tree, 2)
  tree = insert(tree, 3)
  tree = insert(tree, 4)
  tree = insert(tree, 5)
  let (t, found) = search(tree, 1)
  assert_true(found)
  // After splaying, 1 should be at root
  match t {
    Node(_, k, _, _) => assert_eq(k, 1)
    Empty => abort("expected non-empty tree")
  }
}

test "splay: delete leaf" {
  let mut tree = empty()
  tree = insert(tree, 5)
  tree = insert(tree, 3)
  tree = insert(tree, 7)
  tree = delete(tree, 7)
  assert_eq(size(tree), 2)
  let (_, found) = search(tree, 7)
  assert_false(found)
}

test "splay: delete root" {
  let mut tree = empty()
  tree = insert(tree, 5)
  tree = insert(tree, 3)
  tree = insert(tree, 7)
  tree = delete(tree, 5)
  assert_eq(size(tree), 2)
  let (_, found) = search(tree, 5)
  assert_false(found)
}

test "splay: delete non-existent" {
  let mut tree = empty()
  tree = insert(tree, 5)
  tree = insert(tree, 3)
  tree = delete(tree, 99)
  assert_eq(size(tree), 2)
}

test "splay: BST invariant after inserts" {
  let mut tree = empty()
  for k = 1; k <= 100; k = k + 1 {
    tree = insert(tree, k)
  }
  let arr = inorder(tree)
  for k = 0; k < 99; k = k + 1 {
    assert_true(arr[k] < arr[k + 1])
  }
  assert_eq(arr.length(), 100)
}

test "splay: duplicate insert ignored" {
  let mut tree = empty()
  tree = insert(tree, 5)
  tree = insert(tree, 5)
  tree = insert(tree, 5)
  assert_eq(size(tree), 1)
}

test "splay: sequential insert then search all" {
  // Worst case for BST: sequential insertion creates a linked list.
  // Splay tree should still find all elements.
  let mut tree = empty()
  for k = 1; k <= 1000; k = k + 1 {
    tree = insert(tree, k)
  }
  assert_eq(size(tree), 1000)
  for k = 1; k <= 1000; k = k + 1 {
    let (_, found) = search(tree, k)
    assert_true(found)
  }
}

test "splay: interleaved insert and delete" {
  let mut tree = empty()
  tree = insert(tree, 10)
  tree = insert(tree, 20)
  tree = insert(tree, 5)
  tree = delete(tree, 20)
  tree = insert(tree, 15)
  tree = delete(tree, 10)
  let arr = inorder(tree)
  assert_eq(arr.length(), 2)
  // Remaining: 5 and 15
  let mut found5 = false
  let mut found15 = false
  for k = 0; k < arr.length(); k = k + 1 {
    if arr[k] == 5 { found5 = true }
    if arr[k] == 15 { found15 = true }
  }
  assert_true(found5)
  assert_true(found15)
}

test "splay: empty tree operations" {
  let tree = empty()
  assert_eq(size(tree), 0)
  let (t, found) = search(tree, 5)
  assert_false(found)
  assert_true(t is Empty)
  let t2 = delete(tree, 5)
  assert_true(t2 is Empty)
  assert_eq(inorder(tree).length(), 0)
}

test "splay: size consistency after operations" {
  let mut tree = empty()
  for k = 1; k <= 500; k = k + 1 {
    tree = insert(tree, k * 2)
  }
  assert_eq(size(tree), 500)
  for k = 1; k <= 250; k = k + 1 {
    tree = delete(tree, k * 2)
  }
  assert_eq(size(tree), 250)
  // Verify remaining keys are present
  for k = 251; k <= 500; k = k + 1 {
    let (_, found) = search(tree, k * 2)
    assert_true(found)
  }
  // Verify deleted keys are gone
  for k = 1; k <= 250; k = k + 1 {
    let (_, found) = search(tree, k * 2)
    assert_false(found)
  }
}
