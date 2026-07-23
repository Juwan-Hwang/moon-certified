/// Binary Search Tree (BST).
///
/// A persistent (immutable), non-self-balancing binary search tree over `Int`.
/// Supports insert, search, delete, and in-order traversal. Duplicate values
/// are silently ignored on insert.
///
/// # Stack safety
///
/// Every operation — insert, delete, search, find_min, size, inorder — is
/// **iterative**, using explicit heap-allocated work stacks. None of them
/// recurse down the tree, so none can overflow the call stack — not even on a
/// fully degenerate (linked-list-shaped) tree of 10^5+ nodes produced by
/// inserting already-sorted data. The descent path is recorded on an `Array`
/// and the spine rebuilt bottom-up, keeping call-stack depth O(1) regardless
/// of tree height.
///
/// # Complexity note — intentionally not self-balancing
///
/// This BST is **deliberately** not self-balancing. On balanced or random input
/// all operations are O(log n); on adversarial (pre-sorted) input the tree
/// degenerates into a linked list and operations become O(n) in *time* (though
/// still O(1) in call-stack depth, see above). This linear-time behaviour on
/// adversarial input is the inherent, documented cost of skipping rebalancing;
/// the payoff is a far simpler, lighter structure well suited to trusted input.
///
/// **For adversarial or untrusted input, prefer a self-balancing tree:**
/// `@avl` (AVL tree) or `@red_black_tree` (red-black tree), both of which
/// guarantee O(log n) time regardless of insertion order.
///
/// Not formally verified. Correctness is ensured by a comprehensive test suite,
/// including a 10^5-depth degenerate-tree stack-safety case.

/// Binary Search Tree node type.
/// Use `Node::Empty` to create an empty tree.
pub enum Node {
  Empty
  Node(Node, Int, Node)
}

/// Insert a value into the BST. Duplicates are ignored (the tree is returned
/// unchanged). Iterative: the descent path is recorded on a heap stack and
/// the spine rebuilt bottom-up, so insertion is stack-safe on degenerate trees.
pub fn insert(root : Node, val : Int) -> Node {
  // Each path frame records (value, sibling, dir): `sibling` is the child we
  // did NOT descend into, `dir` is 0 for left / 1 for right. This is exactly
  // what is needed to rebuild every ancestor when climbing back up.
  let path : Array[(Int, Node, Int)] = []
  let mut cur = root
  let mut descend = true
  while descend {
    match cur {
      Empty => descend = false
      Node(l, v, r) =>
        if val < v {
          path.push((v, r, 0))
          cur = l
        } else if val > v {
          path.push((v, l, 1))
          cur = r
        } else {
          return root // duplicate: tree unchanged
        }
    }
  }
  rebuild_spine(path, Node(Empty, val, Empty))
}

/// Search for a value. Returns true if present. Iterative descent — O(1) in
/// call-stack depth regardless of tree height.
pub fn search(root : Node, val : Int) -> Bool {
  let mut cur = root
  let mut found = false
  let mut go = true
  while go {
    match cur {
      Empty => go = false
      Node(l, v, r) =>
        if val == v {
          found = true
          go = false
        } else if val < v {
          cur = l
        } else {
          cur = r
        }
    }
  }
  found
}

/// Find the minimum value, or `None` if the tree is empty. Iterative left walk
/// — stack-safe on degenerate trees.
pub fn find_min(root : Node) -> Int? {
  let mut cur = root
  let mut result : Int? = None
  let mut go = true
  while go {
    match cur {
      Empty => go = false
      Node(l, v, _) => {
        result = Some(v)
        cur = l
      }
    }
  }
  result
}

/// Delete a value. If absent the tree is returned unchanged. Iterative: the
/// descent path is heap-stacked and the spine rebuilt bottom-up, so deletion
/// is stack-safe even on degenerate trees.
pub fn delete(root : Node, val : Int) -> Node {
  let path : Array[(Int, Node, Int)] = []
  let mut cur = root
  let mut found = false
  let mut go = true
  while go {
    match cur {
      Empty => go = false
      Node(l, v, r) =>
        if val < v {
          path.push((v, r, 0))
          cur = l
        } else if val > v {
          path.push((v, l, 1))
          cur = r
        } else {
          found = true
          go = false
        }
    }
  }
  if !found {
    return root // value absent: tree unchanged
  }
  rebuild_spine(path, remove_at(cur))
}

/// Compute the subtree that replaces a located target node.
/// - leaf / single child: the non-empty child (or `Empty`)
/// - two children: hoist the in-order successor (min of the right subtree)
///   into the node and splice the successor out — done iteratively, with no
///   `abort`: the impossible `None` from `extract_min` falls back to leaving
///   the node unchanged.
fn remove_at(node : Node) -> Node {
  match node {
    Empty => Empty // unreachable: only invoked on a node we located
    Node(l, _, r) =>
      match (l, r) {
        (Empty, _) => r
        (_, Empty) => l
        (_, _) =>
          // Both children present, so `r` is non-empty and `extract_min`
          // always returns Some. The None arm is an unreachable safety net.
          match extract_min(r) {
            Some((succ, new_r)) => Node(l, succ, new_r)
            None => node
          }
      }
  }
}

/// Remove and return the minimum value of a subtree, together with the
/// subtree that remains. Returns `None` if the subtree is empty. Iterative:
/// walks left recording the spine, then rebuilds upward — no recursion, no
/// `abort`.
fn extract_min(root : Node) -> (Int, Node)? {
  // Each frame records (value, right-sibling) for every node we descend left
  // through; the node whose left child is `Empty` is the minimum.
  let path : Array[(Int, Node)] = []
  let mut cur = root
  let mut result : (Int, Node)? = None
  let mut go = true
  while go {
    match cur {
      Node(Empty, v, r) => {
        // `cur` is the minimum: splice it out, replacing it with its right
        // child, then rebuild the spine back up to (and including) `root`.
        let min = v
        let mut acc = r
        let mut build = true
        while build {
          match path.pop() {
            None => build = false
            Some((pv, pr)) => acc = Node(acc, pv, pr)
          }
        }
        result = Some((min, acc))
        go = false
      }
      Node(l, v, r) => {
        path.push((v, r))
        cur = l
      }
      Empty => {
        result = None // empty subtree: nothing to extract
        go = false
      }
    }
  }
  result
}

/// Rebuild a path spine bottom-up. `start` is the new subtree at the bottom of
/// the descent; each recorded `(value, sibling, dir)` frame produces a new
/// ancestor with `start` attached on the descended side. Returns the new root.
fn rebuild_spine(
  path : Array[(Int, Node, Int)],
  start : Node,
) -> Node {
  let mut acc = start
  let mut go = true
  while go {
    match path.pop() {
      None => go = false
      Some((v, sib, dir)) =>
        if dir == 0 {
          acc = Node(acc, v, sib)
        } else {
          acc = Node(sib, v, acc)
        }
    }
  }
  acc
}

/// Number of nodes. Iterative pre-order walk with an explicit stack — O(n) in
/// time and heap space, O(1) in call-stack depth.
pub fn size(root : Node) -> Int {
  let mut count = 0
  let stack : Array[Node] = [root]
  let mut go = true
  while go {
    match stack.pop() {
      None => go = false
      Some(node) =>
        match node {
          Empty => ()
          Node(l, _, r) => {
            count = count + 1
            stack.push(l)
            stack.push(r)
          }
        }
    }
  }
  count
}

/// In-order traversal returning a sorted `FixedArray[Int]`. Iterative (standard
/// left-spine stack), so it is stack-safe on degenerate trees.
pub fn inorder(root : Node) -> FixedArray[Int] {
  let n = size(root)
  let result = FixedArray::make(n, 0)
  // Each frame records (value, right-child): emit the value in order, then
  // descend into the right child.
  let stack : Array[(Int, Node)] = []
  let mut cur = root
  let mut idx = 0
  let mut go = true
  while go {
    // Descend the left spine, pushing every node visited.
    let mut descend = true
    while descend {
      match cur {
        Empty => descend = false
        Node(l, v, r) => {
          stack.push((v, r))
          cur = l
        }
      }
    }
    match stack.pop() {
      None => go = false
      Some((v, r)) => {
        result[idx] = v
        idx = idx + 1
        cur = r
      }
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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

test "find_min: basic and empty" {
  let tree = insert(Empty, 50)
  let tree = insert(tree, 30)
  let tree = insert(tree, 70)
  let tree = insert(tree, 20)
  let tree = insert(tree, 40)
  assert_eq(find_min(tree).unwrap(), 20)
  assert_true(find_min(Empty) is None)
}

test "bst: deep degenerate tree is stack-safe" {
  // Build a left-leaning chain of 10^5 nodes by direct construction — O(n),
  // not the O(n^2) of sequential `insert`. Under the previous recursive
  // implementation every operation below would overflow the call stack; the
  // iterative implementations keep call-stack depth O(1).
  let n = 100000
  let mut tree : Node = Empty
  for k = 1; k <= n; k = k + 1 {
    tree = Node(tree, k, Empty)
  }
  // find_min walks the full 10^5-deep left spine.
  assert_eq(find_min(tree).unwrap(), 1)
  // search reaches the deepest element and misses one past it.
  assert_eq(search(tree, 1), true)
  assert_eq(search(tree, n), true)
  assert_eq(search(tree, n + 1), false)
  // size walks every node iteratively.
  assert_eq(size(tree), n)
  // inorder produces a fully sorted output over 10^5 elements.
  let arr = inorder(tree)
  assert_eq(arr.length(), n)
  assert_eq(arr[0], 1)
  assert_eq(arr[n - 1], n)
  // insert descends 10^5 then rebuilds 10^5 back up — all on the heap.
  let tree2 = insert(tree, 0)
  assert_eq(size(tree2), n + 1)
  assert_eq(search(tree2, 0), true)
  assert_eq(find_min(tree2).unwrap(), 0)
  // delete reaches and removes the deepest leaf.
  let tree3 = delete(tree, 1)
  assert_eq(size(tree3), n - 1)
  assert_eq(search(tree3, 1), false)
  assert_eq(find_min(tree3).unwrap(), 2)
}

test "bst: right-leaning degenerate tree is stack-safe" {
  // Mirror of the left-leaning case: a right chain, exercising the right
  // descent / right-sibling rebuild path of every operation.
  let n = 100000
  let mut tree : Node = Empty
  for k = n; k >= 1; k = k - 1 {
    tree = Node(Empty, k, tree)
  }
  assert_eq(find_min(tree).unwrap(), 1)
  assert_eq(search(tree, n), true)
  assert_eq(size(tree), n)
  let arr = inorder(tree)
  assert_eq(arr.length(), n)
  assert_eq(arr[0], 1)
  assert_eq(arr[n - 1], n)
  // Delete the maximum (rightmost) node — two-children path is not hit on a
  // chain, but the full descent + spine rebuild is exercised.
  let tree2 = delete(tree, n)
  assert_eq(size(tree2), n - 1)
  assert_eq(search(tree2, n), false)
  let tree3 = insert(tree, n + 1)
  assert_eq(search(tree3, n + 1), true)
  assert_eq(size(tree3), n + 1)
}
