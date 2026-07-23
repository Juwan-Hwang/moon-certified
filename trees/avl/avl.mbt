/// AVL Tree: a self-balancing binary search tree.
///
/// Guarantees O(log n) height for all operations by maintaining
/// balance factor in [-1, 0, 1] at every node via rotations.
///
/// Not formally verified. Correctness ensured by comprehensive tests
/// including balance verification and large random insertion checks.

/// AVL tree node. The fourth field is the cached height.
/// Use `AvlNode::Empty` or `empty()` to create an empty tree.
pub enum AvlNode {
  Empty
  Node(AvlNode, Int, AvlNode, Int)
}

/// Public constructor for an empty AVL tree.
pub fn empty() -> AvlNode {
  Empty
}

/// Return the maximum of two integers.
fn max2(a : Int, b : Int) -> Int {
  if a >= b {
    a
  } else {
    b
  }
}

/// Return the height of a node. Empty = -1, leaf = 0.
pub fn height(root : AvlNode) -> Int {
  match root {
    Empty => -1
    Node(_, _, _, h) => h
  }
}

/// Return the number of nodes in the tree.
pub fn size(root : AvlNode) -> Int {
  match root {
    Empty => 0
    Node(l, _, r, _) => size(l) + 1 + size(r)
  }
}

/// Update the cached height of a node based on its children.
fn update_height(root : AvlNode) -> AvlNode {
  match root {
    Empty => Empty
    Node(l, v, r, _) => {
      let h = max2(height(l), height(r)) + 1
      Node(l, v, r, h)
    }
  }
}

/// Compute the balance factor: height(left) - height(right).
fn balance_factor(root : AvlNode) -> Int {
  match root {
    Empty => 0
    Node(l, _, r, _) => height(l) - height(r)
  }
}

/// Right rotation (for LL case).
fn rotate_right(root : AvlNode) -> AvlNode {
  match root {
    Node(Node(ll, lv, lr, _), v, r, _) => {
      let new_r = update_height(Node(lr, v, r, 0))
      update_height(Node(ll, lv, new_r, 0))
    }
    _ => root
  }
}

/// Left rotation (for RR case).
fn rotate_left(root : AvlNode) -> AvlNode {
  match root {
    Node(l, v, Node(rl, rv, rr, _), _) => {
      let new_l = update_height(Node(l, v, rl, 0))
      update_height(Node(new_l, rv, rr, 0))
    }
    _ => root
  }
}

/// Rebalance a node if its balance factor is outside [-1, 1].
fn rebalance(root : AvlNode) -> AvlNode {
  let node = update_height(root)
  let bf = balance_factor(node)
  if bf > 1 {
    // Left-heavy
    match node {
      Node(l, v, r, _) =>
        if balance_factor(l) < 0 {
          // LR case: rotate left child left, then right
          let new_l = rotate_left(l)
          rotate_right(update_height(Node(new_l, v, r, 0)))
        } else {
          // LL case: rotate right
          rotate_right(node)
        }
      _ => node
    }
  } else if bf < -1 {
    // Right-heavy
    match node {
      Node(l, v, r, _) =>
        if balance_factor(r) > 0 {
          // RL case: rotate right child right, then left
          let new_r = rotate_right(r)
          rotate_left(update_height(Node(l, v, new_r, 0)))
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

/// Insert a value into the AVL tree. Duplicates are ignored.
pub fn insert(root : AvlNode, val : Int) -> AvlNode {
  match root {
    Empty => Node(Empty, val, Empty, 0)
    Node(l, v, r, _) =>
      if val < v {
        rebalance(Node(insert(l, val), v, r, 0))
      } else if val > v {
        rebalance(Node(l, v, insert(r, val), 0))
      } else {
        root // Duplicate, ignore
      }
  }
}

/// Search for a value in the AVL tree.
pub fn search(root : AvlNode, val : Int) -> Bool {
  match root {
    Empty => false
    Node(l, v, r, _) =>
      if val < v {
        search(l, val)
      } else if val > v {
        search(r, val)
      } else {
        true
      }
  }
}

/// Find the minimum value in a non-empty tree.
fn find_min(root : AvlNode) -> Int {
  match root {
    Empty => abort("find_min on empty tree")
    Node(Empty, v, _, _) => v
    Node(l, _, _, _) => find_min(l)
  }
}

/// Delete a value from the AVL tree.
pub fn delete(root : AvlNode, val : Int) -> AvlNode {
  match root {
    Empty => Empty
    Node(l, v, r, _) =>
      if val < v {
        rebalance(Node(delete(l, val), v, r, 0))
      } else if val > v {
        rebalance(Node(l, v, delete(r, val), 0))
      } else {
        // Found the node to delete
        match (l, r) {
          (Empty, _) => r
          (_, Empty) => l
          (_, _) => {
            let succ = find_min(r)
            rebalance(Node(l, succ, delete(r, succ), 0))
          }
        }
      }
  }
}

/// In-order traversal, returning a sorted FixedArray of all values.
pub fn inorder(root : AvlNode) -> FixedArray[Int] {
  let n = size(root)
  let result = FixedArray::make(n, 0)
  let _ = inorder_fill(root, result, 0)
  result
}

/// Fill the result array in-order, returning the next index.
fn inorder_fill(
  root : AvlNode,
  result : FixedArray[Int],
  idx : Int,
) -> Int {
  match root {
    Empty => idx
    Node(l, v, r, _) => {
      let after_left = inorder_fill(l, result, idx)
      result[after_left] = v
      inorder_fill(r, result, after_left + 1)
    }
  }
}

/// Check if the tree is balanced (all nodes have |balance_factor| <= 1).
fn is_balanced(root : AvlNode) -> Bool {
  match root {
    Empty => true
    Node(l, _, r, _) => {
      let bf = balance_factor(root)
      bf >= -1 && bf <= 1 && is_balanced(l) && is_balanced(r)
    }
  }
}

/// Check if the tree satisfies BST ordering (in-order is sorted).
fn is_bst(root : AvlNode) -> Bool {
  let arr = inorder(root)
  let n = arr.length()
  let mut ok = true
  let mut i = 1
  while i < n {
    if arr[i] < arr[i - 1] {
      ok = false
    }
    i = i + 1
  }
  ok
}

test "avl: basic insert and search" {
  let tree = empty()
  let t1 = insert(tree, 5)
  assert_true(search(t1, 5))
  assert_false(search(t1, 3))
  let t2 = insert(t1, 3)
  let t3 = insert(t2, 7)
  assert_true(search(t3, 3))
  assert_true(search(t3, 7))
  assert_true(search(t3, 5))
}

test "avl: duplicate insert ignored" {
  let tree = insert(insert(empty(), 5), 5)
  assert_eq(size(tree), 1)
}

test "avl: sequential insert maintains balance" {
  // Insert 1,2,3,4,5,6,7 — should produce height 2, not 6
  let mut tree = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k)
  }
  assert_eq(size(tree), 7)
  assert_true(is_balanced(tree))
  assert_true(height(tree) <= 2)
  assert_true(is_bst(tree))
}

test "avl: reverse insert maintains balance" {
  let mut tree = empty()
  for k = 7; k >= 1; k = k - 1 {
    tree = insert(tree, k)
  }
  assert_eq(size(tree), 7)
  assert_true(is_balanced(tree))
  assert_true(height(tree) <= 2)
  assert_true(is_bst(tree))
}

test "avl: delete leaf" {
  let tree = insert(insert(insert(empty(), 5), 3), 7)
  let t2 = delete(tree, 7)
  assert_false(search(t2, 7))
  assert_true(search(t2, 5))
  assert_true(search(t2, 3))
  assert_eq(size(t2), 2)
  assert_true(is_balanced(t2))
}

test "avl: delete node with one child" {
  let tree = insert(insert(insert(insert(empty(), 5), 3), 7), 8)
  let t2 = delete(tree, 7)
  assert_false(search(t2, 7))
  assert_true(search(t2, 8))
  assert_true(is_balanced(t2))
  assert_true(is_bst(t2))
}

test "avl: delete node with two children" {
  let mut tree = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k)
  }
  let t2 = delete(tree, 4) // root or near-root
  assert_false(search(t2, 4))
  assert_eq(size(t2), 6)
  assert_true(is_balanced(t2))
  assert_true(is_bst(t2))
}

test "avl: delete root" {
  let tree = insert(insert(insert(insert(insert(empty(), 10), 5), 15), 3), 7)
  let t2 = delete(tree, 10)
  assert_false(search(t2, 10))
  assert_true(search(t2, 5))
  assert_true(search(t2, 15))
  assert_true(is_balanced(t2))
  assert_true(is_bst(t2))
}

test "avl: inorder produces sorted output" {
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

test "avl: size tracking" {
  let mut tree = empty()
  assert_eq(size(tree), 0)
  tree = insert(tree, 10)
  assert_eq(size(tree), 1)
  tree = insert(tree, 20)
  tree = insert(tree, 30)
  assert_eq(size(tree), 3)
  tree = delete(tree, 20)
  assert_eq(size(tree), 2)
}

test "avl: height after deletions" {
  let mut tree = empty()
  for k = 1; k <= 15; k = k + 1 {
    tree = insert(tree, k)
  }
  assert_true(height(tree) <= 4)
  assert_true(is_balanced(tree))
  for k = 1; k <= 10; k = k + 1 {
    tree = delete(tree, k)
  }
  assert_eq(size(tree), 5)
  assert_true(is_balanced(tree))
  assert_true(is_bst(tree))
}

test "avl: large random insert" {
  let mut tree = empty()
  let n = 100
  for k = 0; k < n; k = k + 1 {
    tree = insert(tree, (k * 37 + 11) % n)
  }
  assert_eq(size(tree), n)
  assert_true(is_balanced(tree))
  assert_true(is_bst(tree))
  // Height should be O(log n), definitely <= 2*log2(n) + 1
  assert_true(height(tree) <= 14)
}

test "avl: empty tree operations" {
  let tree = empty()
  assert_eq(size(tree), 0)
  assert_eq(height(tree), -1)
  assert_false(search(tree, 1))
  assert_eq(inorder(tree).length(), 0)
  let t2 = delete(tree, 1)
  assert_eq(size(t2), 0)
}

test "avl: single node operations" {
  let tree = insert(empty(), 42)
  assert_eq(size(tree), 1)
  assert_eq(height(tree), 0)
  assert_true(search(tree, 42))
  assert_false(search(tree, 1))
  let sorted = inorder(tree)
  assert_eq(sorted[0], 42)
  let t2 = delete(tree, 42)
  assert_eq(size(t2), 0)
  assert_false(search(t2, 42))
}

test "avl: delete all elements one by one" {
  let mut tree = empty()
  for k = 1; k <= 10; k = k + 1 {
    tree = insert(tree, k)
  }
  for k = 1; k <= 10; k = k + 1 {
    tree = delete(tree, k)
    assert_true(is_balanced(tree))
    assert_true(is_bst(tree))
  }
  assert_eq(size(tree), 0)
}

test "avl: LR rotation case" {
  // Insert 3, 1, 2: should trigger LR rotation
  let tree = insert(insert(insert(empty(), 3), 1), 2)
  assert_true(is_balanced(tree))
  assert_true(is_bst(tree))
  let sorted = inorder(tree)
  assert_eq(sorted[0], 1)
  assert_eq(sorted[1], 2)
  assert_eq(sorted[2], 3)
}

test "avl: RL rotation case" {
  // Insert 1, 3, 2: should trigger RL rotation
  let tree = insert(insert(insert(empty(), 1), 3), 2)
  assert_true(is_balanced(tree))
  assert_true(is_bst(tree))
  let sorted = inorder(tree)
  assert_eq(sorted[0], 1)
  assert_eq(sorted[1], 2)
  assert_eq(sorted[2], 3)
}
