/// Binary Search Tree (BST) implementation.
/// Supports insert, search, delete, and in-order traversal.
/// No duplicate values are stored.

/// Binary Search Tree node type.
/// Use `Node::Empty` to create an empty tree.
pub enum Node {
  Empty
  Node(Node, Int, Node)
}

/// Insert a value into the BST. Duplicates are silently ignored.
pub fn insert(root : Node, val : Int) -> Node {
  match root {
    Empty => Node(Empty, val, Empty)
    Node(l, v, r) =>
      if val < v {
        Node(insert(l, val), v, r)
      } else if val > v {
        Node(l, v, insert(r, val))
      } else {
        root // duplicate: no change
      }
  }
}

/// Search for a value in the BST. Returns true if found.
pub fn search(root : Node, val : Int) -> Bool {
  match root {
    Empty => false
    Node(l, v, r) =>
      if val == v {
        true
      } else if val < v {
        search(l, val)
      } else {
        search(r, val)
      }
  }
}

/// Find the minimum value in a BST. Returns None if the tree is empty.
pub fn find_min(root : Node) -> Int? {
  match root {
    Empty => None
    Node(Empty, v, _) => Some(v)
    Node(l, _, _) => find_min(l)
  }
}

/// Remove the current node, handling all three deletion cases:
/// - No children (leaf): return Empty
/// - One child: return the non-empty child
/// - Two children: replace value with in-order successor, then delete successor
fn remove_node(left : Node, right : Node) -> Node {
  match left {
    Empty => right
    _ =>
      match right {
        Empty => left
        _ => {
          let succ = find_min(right).unwrap_or(0)
          Node(left, succ, delete(right, succ))
        }
      }
  }
}

/// Delete a value from the BST. Returns the new tree.
/// If the value doesn't exist, the tree is unchanged.
pub fn delete(root : Node, val : Int) -> Node {
  match root {
    Empty => Empty
    Node(l, v, r) =>
      if val < v {
        Node(delete(l, val), v, r)
      } else if val > v {
        Node(l, v, delete(r, val))
      } else {
        remove_node(l, r)
      }
  }
}

/// Count the number of nodes in the BST.
pub fn size(root : Node) -> Int {
  match root {
    Empty => 0
    Node(l, _, r) => 1 + size(l) + size(r)
  }
}

/// Fill the result array with in-order traversal starting at index idx.
/// Returns the next available index after filling.
fn inorder_fill(root : Node, result : FixedArray[Int], idx : Int) -> Int {
  match root {
    Empty => idx
    Node(l, v, r) => {
      let idx1 = inorder_fill(l, result, idx)
      result[idx1] = v
      inorder_fill(r, result, idx1 + 1)
    }
  }
}

/// In-order traversal returning a sorted FixedArray of all values.
pub fn inorder(root : Node) -> FixedArray[Int] {
  let n = size(root)
  let result = FixedArray::make(n, 0)
  let _ = inorder_fill(root, result, 0)
  result
}

test "insert: basic" {
  let tree = insert(Empty, 5)
  assert_eq(size(tree), 1)
  let tree = insert(tree, 3)
  let tree = insert(tree, 7)
  assert_eq(size(tree), 3)
}

test "insert: duplicate ignored" {
  let tree = insert(Empty, 5)
  let tree = insert(tree, 5) // duplicate
  assert_eq(size(tree), 1)
  let tree = insert(tree, 3)
  let tree = insert(tree, 3) // duplicate
  assert_eq(size(tree), 2)
}

test "search: found" {
  let tree = insert(Empty, 10)
  let tree = insert(tree, 5)
  let tree = insert(tree, 15)
  let tree = insert(tree, 3)
  let tree = insert(tree, 7)
  assert_eq(search(tree, 10), true)
  assert_eq(search(tree, 5), true)
  assert_eq(search(tree, 15), true)
  assert_eq(search(tree, 3), true)
  assert_eq(search(tree, 7), true)
}

test "search: not found" {
  let tree = insert(Empty, 10)
  let tree = insert(tree, 5)
  let tree = insert(tree, 15)
  assert_eq(search(tree, 0), false)
  assert_eq(search(tree, 8), false)
  assert_eq(search(tree, 20), false)
  assert_eq(search(tree, 12), false)
}

test "search: empty tree" {
  assert_eq(search(Empty, 42), false)
}

test "delete: leaf node" {
  let tree = insert(Empty, 5)
  let tree = insert(tree, 3)
  let tree = insert(tree, 7)
  // Delete leaf 3
  let tree = delete(tree, 3)
  assert_eq(size(tree), 2)
  assert_eq(search(tree, 3), false)
  assert_eq(search(tree, 5), true)
  assert_eq(search(tree, 7), true)
}

test "delete: node with one child (left)" {
  //     5
  //    /
  //   3
  //  /
  // 1
  let tree = insert(Empty, 5)
  let tree = insert(tree, 3)
  let tree = insert(tree, 1)
  // Delete 3, which has one child (1)
  let tree = delete(tree, 3)
  assert_eq(size(tree), 2)
  assert_eq(search(tree, 3), false)
  assert_eq(search(tree, 1), true)
  assert_eq(search(tree, 5), true)
}

test "delete: node with one child (right)" {
  //   5
  //    \
  //     7
  //      \
  //       9
  let tree = insert(Empty, 5)
  let tree = insert(tree, 7)
  let tree = insert(tree, 9)
  // Delete 7, which has one child (9)
  let tree = delete(tree, 7)
  assert_eq(size(tree), 2)
  assert_eq(search(tree, 7), false)
  assert_eq(search(tree, 9), true)
  assert_eq(search(tree, 5), true)
}

test "delete: node with two children" {
  //       5
  //      / \
  //     3   7
  //    / \   \
  //   1   4   9
  let tree = insert(Empty, 5)
  let tree = insert(tree, 3)
  let tree = insert(tree, 7)
  let tree = insert(tree, 1)
  let tree = insert(tree, 4)
  let tree = insert(tree, 9)
  // Delete 3, which has two children (1 and 4)
  let tree = delete(tree, 3)
  assert_eq(size(tree), 5)
  assert_eq(search(tree, 3), false)
  assert_eq(search(tree, 1), true)
  assert_eq(search(tree, 4), true)
  assert_eq(search(tree, 5), true)
  assert_eq(search(tree, 7), true)
  assert_eq(search(tree, 9), true)
  // In-order should still be sorted
  let arr = inorder(tree)
  assert_eq(arr[0], 1)
  assert_eq(arr[1], 4)
  assert_eq(arr[2], 5)
  assert_eq(arr[3], 7)
  assert_eq(arr[4], 9)
}

test "delete: root node with two children" {
  //       5
  //      / \
  //     3   7
  let tree = insert(Empty, 5)
  let tree = insert(tree, 3)
  let tree = insert(tree, 7)
  // Delete root 5 (has two children)
  let tree = delete(tree, 5)
  assert_eq(size(tree), 2)
  assert_eq(search(tree, 5), false)
  assert_eq(search(tree, 3), true)
  assert_eq(search(tree, 7), true)
  // In-order should still be sorted
  let arr = inorder(tree)
  assert_eq(arr[0], 3)
  assert_eq(arr[1], 7)
}

test "delete: non-existent value" {
  let tree = insert(Empty, 5)
  let tree = insert(tree, 3)
  let tree = insert(tree, 7)
  let tree = delete(tree, 100)
  assert_eq(size(tree), 3)
  assert_eq(search(tree, 5), true)
}

test "delete: from empty tree" {
  let tree = delete(Empty, 42)
  assert_eq(size(tree), 0)
}

test "delete: all elements one by one" {
  let tree = insert(Empty, 5)
  let tree = insert(tree, 3)
  let tree = insert(tree, 7)
  let tree = insert(tree, 1)
  let tree = insert(tree, 4)
  let tree = insert(tree, 6)
  let tree = insert(tree, 9)
  assert_eq(size(tree), 7)
  let tree = delete(tree, 1)
  assert_eq(size(tree), 6)
  let tree = delete(tree, 3)
  assert_eq(size(tree), 5)
  let tree = delete(tree, 4)
  assert_eq(size(tree), 4)
  let tree = delete(tree, 5)
  assert_eq(size(tree), 3)
  let tree = delete(tree, 6)
  assert_eq(size(tree), 2)
  let tree = delete(tree, 7)
  assert_eq(size(tree), 1)
  let tree = delete(tree, 9)
  assert_eq(size(tree), 0)
}

test "inorder: sorted output" {
  let tree = insert(Empty, 50)
  let tree = insert(tree, 30)
  let tree = insert(tree, 70)
  let tree = insert(tree, 20)
  let tree = insert(tree, 40)
  let tree = insert(tree, 60)
  let tree = insert(tree, 80)
  let arr = inorder(tree)
  assert_eq(arr.length(), 7)
  assert_eq(arr[0], 20)
  assert_eq(arr[1], 30)
  assert_eq(arr[2], 40)
  assert_eq(arr[3], 50)
  assert_eq(arr[4], 60)
  assert_eq(arr[5], 70)
  assert_eq(arr[6], 80)
}

test "inorder: empty tree" {
  let arr = inorder(Empty)
  assert_eq(arr.length(), 0)
}

test "inorder: single node" {
  let tree = insert(Empty, 42)
  let arr = inorder(tree)
  assert_eq(arr.length(), 1)
  assert_eq(arr[0], 42)
}

test "size: empty tree" {
  assert_eq(size(Empty), 0)
}

test "inorder: comprehensive" {
  // Insert elements in non-sorted order
  let tree = insert(Empty, 5)
  let tree = insert(tree, 3)
  let tree = insert(tree, 8)
  let tree = insert(tree, 1)
  let tree = insert(tree, 4)
  let tree = insert(tree, 7)
  let tree = insert(tree, 9)
  let tree = insert(tree, 2)
  let tree = insert(tree, 6)
  let tree = insert(tree, 0)
  let arr = inorder(tree)
  assert_eq(arr.length(), 10)
  // Verify sorted: 0, 1, 2, ..., 9
  for i = 0; i < 10; i = i + 1 {
    assert_eq(arr[i], i)
  }
}

test "delete: root with two children and deep successor" {
  //        50
  //       /  \
  //      30   70
  //     / \   / \
  //    20 40 60 80
  //             \
  //             85
  let tree = insert(Empty, 50)
  let tree = insert(tree, 30)
  let tree = insert(tree, 70)
  let tree = insert(tree, 20)
  let tree = insert(tree, 40)
  let tree = insert(tree, 60)
  let tree = insert(tree, 80)
  let tree = insert(tree, 85)
  // Delete 50 (root), successor is 60 (min of right subtree)
  let tree = delete(tree, 50)
  assert_eq(size(tree), 7)
  assert_eq(search(tree, 50), false)
  assert_eq(search(tree, 60), true)
  // In-order should still be sorted
  let arr = inorder(tree)
  assert_eq(arr.length(), 7)
  assert_eq(arr[0], 20)
  assert_eq(arr[1], 30)
  assert_eq(arr[2], 40)
  assert_eq(arr[3], 60)
  assert_eq(arr[4], 70)
  assert_eq(arr[5], 80)
  assert_eq(arr[6], 85)
}
