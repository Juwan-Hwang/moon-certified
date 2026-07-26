/// AVL Tree: a self-balancing binary search tree.
///
/// Generic: works with any type T given a comparator function.
/// Guarantees O(log n) height for all operations by maintaining
/// balance factor in [-1, 0, 1] at every node via rotations.
///
/// Both height and size are cached in each node, making `height()` and
/// `size()` O(1) operations.
///
/// **Stack safety**: `insert`, `delete`, `search`, `find_min`, and `inorder`
/// are recursive. Because the AVL invariant guarantees height <= 1.44*log2(n+2),
/// the recursion depth is always O(log n) -- at most ~44 for n = 2^32,
/// well within MoonBit's default stack limit. No iterative conversion is
/// needed; the AVL invariant itself is the stack-safety guarantee. As a
/// defensive net against balancing bugs, `insert`/`delete`/`search`/`find_min`
/// abort if the cached `height` exceeds `avl_max_depth` (1000); see
/// `guard_depth`. (Note: `inorder` is unguarded but its depth is also bounded
/// by the AVL height.)
///
/// Not formally verified. Correctness ensured by comprehensive tests
/// including balance verification and large random insertion checks.

///|
/// AVL tree node.
/// - 4th field: cached height (Empty = -1, leaf = 0)
/// - 5th field: cached subtree size (number of nodes)
/// Use `AvlNode::Empty` or `empty()` to create an empty tree.
pub enum AvlNode[T] {
  Empty
  Node(AvlNode[T], T, AvlNode[T], Int, Int)
}

///|
/// Public constructor for an empty AVL tree.
pub fn[T] empty() -> AvlNode[T] {
  Empty
}

///|
/// Return the maximum of two integers.
fn max2(a : Int, b : Int) -> Int {
  if a >= b {
    a
  } else {
    b
  }
}

///|
/// Defensive ceiling on recursion depth. The AVL invariant bounds the height
/// (and thus the recursion depth of every operation) at ~1.44*log2(n+2), so
/// this guard only fires if a balancing bug produces an illegally tall tree or
/// `n` is astronomically large (n > 2^690). The check is O(1) because each node
/// caches its `height`.
let avl_max_depth : Int = 1000

///|
/// Abort if the tree is too tall to recurse into safely. O(1) via cached height.
/// Because AVL recursion depth equals the tree height, a single entry check on
/// the root suffices to bound the whole descent.
fn[T] guard_depth(root : AvlNode[T]) -> Unit {
  if height(root) >= avl_max_depth {
    abort(
      "avl: tree height exceeds safe recursion depth; balancing invariant broken or tree too large",
    )
  }
}

///|
/// Return the height of a node. Empty = -1, leaf = 0. O(1).
pub fn[T] height(root : AvlNode[T]) -> Int {
  match root {
    Empty => -1
    Node(_, _, _, h, _) => h
  }
}

///|
/// Return the number of nodes in the tree. O(1) via cached size.
pub fn[T] size(root : AvlNode[T]) -> Int {
  match root {
    Empty => 0
    Node(_, _, _, _, s) => s
  }
}

///|
/// Recompute and cache both height and size from children. O(1).
fn[T] update_meta(root : AvlNode[T]) -> AvlNode[T] {
  match root {
    Empty => Empty
    Node(l, v, r, _, _) => {
      let h = max2(height(l), height(r)) + 1
      let s = size(l) + 1 + size(r)
      Node(l, v, r, h, s)
    }
  }
}

///|
/// Compute the balance factor: height(left) - height(right).
fn[T] balance_factor(root : AvlNode[T]) -> Int {
  match root {
    Empty => 0
    Node(l, _, r, _, _) => height(l) - height(r)
  }
}

///|
/// Right rotation (for LL case).
fn[T] rotate_right(root : AvlNode[T]) -> AvlNode[T] {
  match root {
    Node(Node(ll, lv, lr, _, _), v, r, _, _) => {
      let new_r = update_meta(Node(lr, v, r, 0, 0))
      update_meta(Node(ll, lv, new_r, 0, 0))
    }
    _ => root
  }
}

///|
/// Left rotation (for RR case).
fn[T] rotate_left(root : AvlNode[T]) -> AvlNode[T] {
  match root {
    Node(l, v, Node(rl, rv, rr, _, _), _, _) => {
      let new_l = update_meta(Node(l, v, rl, 0, 0))
      update_meta(Node(new_l, rv, rr, 0, 0))
    }
    _ => root
  }
}

///|
/// Rebalance a node if its balance factor is outside [-1, 1].
fn[T] rebalance(root : AvlNode[T]) -> AvlNode[T] {
  let node = update_meta(root)
  let bf = balance_factor(node)
  if bf > 1 {
    // Left-heavy
    match node {
      Node(l, v, r, _, _) =>
        if balance_factor(l) < 0 {
          // LR case: rotate left child left, then right
          let new_l = rotate_left(l)
          rotate_right(update_meta(Node(new_l, v, r, 0, 0)))
        } else {
          // LL case: rotate right
          rotate_right(node)
        }
      _ => node
    }
  } else if bf < -1 {
    // Right-heavy
    match node {
      Node(l, v, r, _, _) =>
        if balance_factor(r) > 0 {
          // RL case: rotate right child right, then left
          let new_r = rotate_right(r)
          rotate_left(update_meta(Node(l, v, new_r, 0, 0)))
        } else {
          // RR case: rotate left
          rotate_left(node)
        }
      _ => node
    }
  } else {
    node
  }
}

///|
/// Insert a value into the AVL tree. Duplicates are ignored.
pub fn[T] insert(root : AvlNode[T], val : T, cmp : (T, T) -> Int) -> AvlNode[T] {
  guard_depth(root)
  match root {
    Empty => Node(Empty, val, Empty, 0, 1)
    Node(l, v, r, _, _) => {
      let c = cmp(val, v)
      if c < 0 {
        rebalance(Node(insert(l, val, cmp), v, r, 0, 0))
      } else if c > 0 {
        rebalance(Node(l, v, insert(r, val, cmp), 0, 0))
      } else {
        root // Duplicate, ignore
      }
    }
  }
}

///|
/// Search for a value in the AVL tree.
pub fn[T] search(root : AvlNode[T], val : T, cmp : (T, T) -> Int) -> Bool {
  guard_depth(root)
  match root {
    Empty => false
    Node(l, v, r, _, _) => {
      let c = cmp(val, v)
      if c < 0 {
        search(l, val, cmp)
      } else if c > 0 {
        search(r, val, cmp)
      } else {
        true
      }
    }
  }
}

///|
/// Find the minimum value in an AVL tree. Returns None if the tree is empty.
pub fn[T] find_min(root : AvlNode[T]) -> T? {
  guard_depth(root)
  match root {
    Empty => None
    Node(Empty, v, _, _, _) => Some(v)
    Node(l, _, _, _, _) => find_min(l)
  }
}

///|
/// Delete a value from the AVL tree.
pub fn[T] delete(root : AvlNode[T], val : T, cmp : (T, T) -> Int) -> AvlNode[T] {
  guard_depth(root)
  match root {
    Empty => Empty
    Node(l, v, r, _, _) => {
      let c = cmp(val, v)
      if c < 0 {
        rebalance(Node(delete(l, val, cmp), v, r, 0, 0))
      } else if c > 0 {
        rebalance(Node(l, v, delete(r, val, cmp), 0, 0))
      } else {
        // Found the node to delete
        match (l, r) {
          (Empty, _) => r
          (_, Empty) => l
          (_, _) => {
            // Both children non-empty. find_min(r) returns Some because r is
            // non-empty. If somehow None, keep the original key as fallback.
            let succ = match find_min(r) {
              Some(s) => s
              None => v
            }
            rebalance(Node(l, succ, delete(r, succ, cmp), 0, 0))
          }
        }
      }
    }
  }
}

///|
/// In-order traversal, returning a sorted FixedArray of all values.
pub fn[T] inorder(root : AvlNode[T]) -> FixedArray[T] {
  let buf : Array[T] = []
  inorder_fill(root, buf)
  FixedArray::from_array(buf.view())
}

///|
/// Fill the buffer array in-order.
fn[T] inorder_fill(root : AvlNode[T], buf : Array[T]) -> Unit {
  match root {
    Empty => ()
    Node(l, v, r, _, _) => {
      inorder_fill(l, buf)
      buf.push(v)
      inorder_fill(r, buf)
    }
  }
}

///|
/// Check if the tree is balanced (all nodes have |balance_factor| <= 1).
fn[T] is_balanced(root : AvlNode[T]) -> Bool {
  match root {
    Empty => true
    Node(l, _, r, _, _) => {
      let bf = balance_factor(root)
      bf >= -1 && bf <= 1 && is_balanced(l) && is_balanced(r)
    }
  }
}

///|
/// Check if the tree satisfies BST ordering (in-order is sorted).
fn[T] is_bst(root : AvlNode[T], cmp : (T, T) -> Int) -> Bool {
  let arr = inorder(root)
  let n = arr.length()
  let mut ok = true
  let mut i = 1
  while i < n {
    if cmp(arr[i], arr[i - 1]) < 0 {
      ok = false
    }
    i = i + 1
  }
  ok
}

///|
test "avl: basic insert and search" {
  let tree : AvlNode[Int] = empty()
  let t1 = insert(tree, 5, fn(a, b) { a - b })
  assert_true(search(t1, 5, fn(a, b) { a - b }))
  assert_false(search(t1, 3, fn(a, b) { a - b }))
  let t2 = insert(t1, 3, fn(a, b) { a - b })
  let t3 = insert(t2, 7, fn(a, b) { a - b })
  assert_true(search(t3, 3, fn(a, b) { a - b }))
  assert_true(search(t3, 7, fn(a, b) { a - b }))
  assert_true(search(t3, 5, fn(a, b) { a - b }))
}

///|
test "avl: duplicate insert ignored" {
  let tree = insert(insert(empty(), 5, fn(a, b) { a - b }), 5, fn(a, b) {
    a - b
  })
  assert_eq(size(tree), 1)
}

///|
test "avl: sequential insert maintains balance" {
  // Insert 1,2,3,4,5,6,7 -- should produce height 2, not 6
  let mut tree : AvlNode[Int] = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(size(tree), 7)
  assert_true(is_balanced(tree))
  assert_true(height(tree) <= 2)
  assert_true(is_bst(tree, fn(a, b) { a - b }))
}

///|
test "avl: reverse insert maintains balance" {
  let mut tree : AvlNode[Int] = empty()
  for k = 7; k >= 1; k = k - 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(size(tree), 7)
  assert_true(is_balanced(tree))
  assert_true(height(tree) <= 2)
  assert_true(is_bst(tree, fn(a, b) { a - b }))
}

///|
test "avl: delete leaf" {
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
  assert_true(is_balanced(t2))
}

///|
test "avl: delete node with one child" {
  let tree = insert(
    insert(
      insert(insert(empty(), 5, fn(a, b) { a - b }), 3, fn(a, b) { a - b }),
      7,
      fn(a, b) { a - b },
    ),
    8,
    fn(a, b) { a - b },
  )
  let t2 = delete(tree, 7, fn(a, b) { a - b })
  assert_false(search(t2, 7, fn(a, b) { a - b }))
  assert_true(search(t2, 8, fn(a, b) { a - b }))
  assert_true(is_balanced(t2))
  assert_true(is_bst(t2, fn(a, b) { a - b }))
}

///|
test "avl: delete node with two children" {
  let mut tree : AvlNode[Int] = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  let t2 = delete(tree, 4, fn(a, b) { a - b }) // root or near-root
  assert_false(search(t2, 4, fn(a, b) { a - b }))
  assert_eq(size(t2), 6)
  assert_true(is_balanced(t2))
  assert_true(is_bst(t2, fn(a, b) { a - b }))
}

///|
test "avl: delete root" {
  let tree = insert(
    insert(
      insert(
        insert(insert(empty(), 10, fn(a, b) { a - b }), 5, fn(a, b) { a - b }),
        15,
        fn(a, b) { a - b },
      ),
      3,
      fn(a, b) { a - b },
    ),
    7,
    fn(a, b) { a - b },
  )
  let t2 = delete(tree, 10, fn(a, b) { a - b })
  assert_false(search(t2, 10, fn(a, b) { a - b }))
  assert_true(search(t2, 5, fn(a, b) { a - b }))
  assert_true(search(t2, 15, fn(a, b) { a - b }))
  assert_true(is_balanced(t2))
  assert_true(is_bst(t2, fn(a, b) { a - b }))
}

///|
test "avl: inorder produces sorted output" {
  let mut tree : AvlNode[Int] = empty()
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
test "avl: size tracking" {
  let mut tree : AvlNode[Int] = empty()
  assert_eq(size(tree), 0)
  tree = insert(tree, 10, fn(a, b) { a - b })
  assert_eq(size(tree), 1)
  tree = insert(tree, 20, fn(a, b) { a - b })
  tree = insert(tree, 30, fn(a, b) { a - b })
  assert_eq(size(tree), 3)
  tree = delete(tree, 20, fn(a, b) { a - b })
  assert_eq(size(tree), 2)
}

///|
test "avl: height after deletions" {
  let mut tree : AvlNode[Int] = empty()
  for k = 1; k <= 15; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_true(height(tree) <= 4)
  assert_true(is_balanced(tree))
  for k = 1; k <= 10; k = k + 1 {
    tree = delete(tree, k, fn(a, b) { a - b })
  }
  assert_eq(size(tree), 5)
  assert_true(is_balanced(tree))
  assert_true(is_bst(tree, fn(a, b) { a - b }))
}

///|
test "avl: large random insert" {
  let mut tree : AvlNode[Int] = empty()
  let n = 100
  for k = 0; k < n; k = k + 1 {
    tree = insert(tree, (k * 37 + 11) % n, fn(a, b) { a - b })
  }
  assert_eq(size(tree), n)
  assert_true(is_balanced(tree))
  assert_true(is_bst(tree, fn(a, b) { a - b }))
  // Height should be O(log n), definitely <= 2*log2(n) + 1
  assert_true(height(tree) <= 14)
}

///|
test "avl: empty tree operations" {
  let tree : AvlNode[Int] = empty()
  assert_eq(size(tree), 0)
  assert_eq(height(tree), -1)
  assert_false(search(tree, 1, fn(a, b) { a - b }))
  assert_eq(inorder(tree).length(), 0)
  let t2 = delete(tree, 1, fn(a, b) { a - b })
  assert_eq(size(t2), 0)
}

///|
test "avl: single node operations" {
  let tree = insert(empty(), 42, fn(a, b) { a - b })
  assert_eq(size(tree), 1)
  assert_eq(height(tree), 0)
  assert_true(search(tree, 42, fn(a, b) { a - b }))
  assert_false(search(tree, 1, fn(a, b) { a - b }))
  let sorted = inorder(tree)
  assert_eq(sorted[0], 42)
  let t2 = delete(tree, 42, fn(a, b) { a - b })
  assert_eq(size(t2), 0)
  assert_false(search(t2, 42, fn(a, b) { a - b }))
}

///|
test "avl: delete all elements one by one" {
  let mut tree : AvlNode[Int] = empty()
  for k = 1; k <= 10; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  for k = 1; k <= 10; k = k + 1 {
    tree = delete(tree, k, fn(a, b) { a - b })
    assert_true(is_balanced(tree))
    assert_true(is_bst(tree, fn(a, b) { a - b }))
  }
  assert_eq(size(tree), 0)
}

///|
test "avl: LR rotation case" {
  // Insert 3, 1, 2: should trigger LR rotation
  let tree = insert(
    insert(insert(empty(), 3, fn(a, b) { a - b }), 1, fn(a, b) { a - b }),
    2,
    fn(a, b) { a - b },
  )
  assert_true(is_balanced(tree))
  assert_true(is_bst(tree, fn(a, b) { a - b }))
  let sorted = inorder(tree)
  assert_eq(sorted[0], 1)
  assert_eq(sorted[1], 2)
  assert_eq(sorted[2], 3)
}

///|
test "avl: RL rotation case" {
  // Insert 1, 3, 2: should trigger RL rotation
  let tree = insert(
    insert(insert(empty(), 1, fn(a, b) { a - b }), 3, fn(a, b) { a - b }),
    2,
    fn(a, b) { a - b },
  )
  assert_true(is_balanced(tree))
  assert_true(is_bst(tree, fn(a, b) { a - b }))
  let sorted = inorder(tree)
  assert_eq(sorted[0], 1)
  assert_eq(sorted[1], 2)
  assert_eq(sorted[2], 3)
}
