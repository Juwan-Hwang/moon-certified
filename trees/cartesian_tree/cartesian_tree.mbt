/// Cartesian Tree — a binary tree derived from a sequence, enabling O(1)
/// Range Minimum Queries (RMQ) via the LCA-to-RMQ reduction.
///
/// A **Cartesian tree** for an array `A[0..n-1]` is a binary tree where:
///
/// 1. **Heap property**: Each node's value is ≤ (min-heap) or ≥ (max-heap)
///    its children's values.
/// 2. **In-order property**: An in-order traversal of the tree yields the
///    original array order.
///
/// The key property for RMQ: in a min-Cartesian tree, the **LCA** (Lowest
/// Common Ancestor) of the nodes at positions `i` and `j` corresponds to
/// the position of the minimum element in `A[i..j]`. This reduces RMQ to
/// LCA, which can be answered in O(1) after O(n log n) preprocessing using
/// an Euler tour + sparse table.
///
/// ## Construction
///
/// The tree can be built in **O(n)** time using a stack-based algorithm:
/// maintain the rightmost path of the tree on a stack. For each new element,
/// pop stack elements that violate the heap property. The last popped node
/// becomes the left child of the new node; the new node becomes the right
/// child of the current stack top.
///
/// ## Complexity
///
/// | Operation       | Time       | Preprocessing |
/// |-----------------|------------|---------------|
/// | `from_array`    | O(n)       | —             |
/// | `rmq`           | O(1)       | O(n log n)    |
/// | `in_order`      | O(n)       | —             |
/// | `get`           | O(1)       | —             |
/// | `size`          | O(1)       | —             |
///
/// ## References
///
/// - Vuillemin, J. (1980). "A unifying look at data structures."
///   *Communications of the ACM*, 23(4), 229–239.
/// - Bender, M. A. & Farach-Colton, M. (2000). "The LCA problem revisited."
///   *LATIN 2000*, LNCS 1776, 88–94. (Euler tour + sparse table for LCA.)
/// - Gabow, H. N., Bentley, J. L., & Tarjan, R. E. (1984). "Scaling and
///   related techniques for geometry problems." *STOC 1984*, 135–143.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Node type
// ---------------------------------------------------------------------------

///|
/// Internal node representation.
///
/// Nodes are indexed by their position in the original array (0-based).
priv struct CtNode {
  mut parent : Int // -1 for root
  mut left : Int // -1 for no child
  mut right : Int // -1 for no child
}

// ---------------------------------------------------------------------------
// Tree type
// ---------------------------------------------------------------------------

///|
/// A Cartesian tree supporting O(1) Range Minimum/Maximum Queries.
///
/// `compare(a, b)` returns `< 0` when `a < b`, `0` when equal, `> 0` when
/// `a > b`. For a **min-Cartesian tree** (RMQ), use `(a, b) => a - b`.
/// For a **max-Cartesian tree** (Range Maximum Query), use `(a, b) => b - a`.
pub struct CartesianTree[T] {
  priv values : Array[T]
  priv nodes : Array[CtNode]
  priv root_index : Int
  // Euler tour for LCA
  priv mut euler : Array[Int] // node indices in Euler tour order
  priv mut depths : Array[Int] // depth of each Euler tour entry
  priv first_occ : Array[Int] // first occurrence index in Euler tour per node
  // Sparse table for RMQ on Euler tour depths
  priv mut sparse : Array[Array[Int]] // sparse[k][i] = argmin of depths[i..i+2^k-1]
  priv mut log_table : Array[Int]
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Build a Cartesian tree from an array. O(n) construction + O(n log n)
/// preprocessing for O(1) RMQ.
///
/// `compare(a, b)` returns `< 0` when `a < b`. For a min-Cartesian tree
/// (default RMQ behavior), use `(a, b) => a - b`. For a max-Cartesian tree,
/// negate the comparator.
pub fn[T] CartesianTree::from_array(
  arr : Array[T],
  compare : (T, T) -> Int,
) -> CartesianTree[T] {
  let n = arr.length()
  // Copy values
  let values : Array[T] = []
  for i = 0; i < n; i = i + 1 {
    values.push(arr[i])
  }
  // Initialize nodes
  let nodes : Array[CtNode] = []
  for i = 0; i < n; i = i + 1 {
    nodes.push({ parent: -1, left: -1, right: -1, })
  }
  // Stack-based O(n) construction.
  // Stack holds indices of nodes on the rightmost path.
  let stack : Array[Int] = []
  let mut root_index = if n > 0 { 0 } else { -1 }
  for i = 0; i < n; i = i + 1 {
    let mut last_popped = -1
    // Pop nodes from stack while they have greater value than arr[i]
    // (for min-heap: parent should be <= children)
    while stack.length() > 0 {
      let top = stack[stack.length() - 1]
      if compare(values[top], values[i]) > 0 {
        // top's value > i's value → pop top, it will become i's left subtree
        last_popped = match stack.pop() {
          Some(v) => v
          None => -1
        }
      } else {
        break
      }
    }
    // last_popped becomes left child of i
    nodes[i].left = last_popped
    if last_popped >= 0 {
      nodes[last_popped].parent = i
    }
    // If stack is not empty, i becomes right child of stack top
    if stack.length() > 0 {
      let top = stack[stack.length() - 1]
      nodes[top].right = i
      nodes[i].parent = top
    } else {
      // i is the new root
      root_index = i
    }
    stack.push(i)
  }
  // Build Euler tour + sparse table for LCA
  let tree : CartesianTree[T] = {
    values,
    nodes,
    root_index,
    euler: [],
    depths: [],
    first_occ: Array::make(n, -1),
    sparse: [],
    log_table: [],
  }
  if n > 0 {
    tree.build_lca_preprocessing()
  }
  tree
}

// ---------------------------------------------------------------------------
// Basic queries
// ---------------------------------------------------------------------------

///|
/// Returns the number of elements. O(1).
pub fn[T] CartesianTree::size(self : CartesianTree[T]) -> Int {
  self.values.length()
}

///|
/// Get the value at a given index. O(1).
///
/// Returns `None` if the index is out of bounds.
pub fn[T] CartesianTree::get(self : CartesianTree[T], index : Int) -> T? {
  if index < 0 || index >= self.values.length() {
    None
  } else {
    Some(self.values[index])
  }
}

///|
/// Returns the root node index, or -1 if the tree is empty.
pub fn[T] CartesianTree::root(self : CartesianTree[T]) -> Int {
  self.root_index
}

// ---------------------------------------------------------------------------
// Range Minimum/Maximum Query
// ---------------------------------------------------------------------------

///|
/// Range query: returns the index of the minimum (or maximum, depending on
/// the comparator) element in `A[lo..hi]` (inclusive). O(1).
///
/// Returns `None` if the range is invalid or the tree is empty.
///
/// For a min-Cartesian tree, this returns the index of the **minimum** element.
/// For a max-Cartesian tree, it returns the index of the **maximum** element.
pub fn[T] CartesianTree::rmq(
  self : CartesianTree[T],
  lo : Int,
  hi : Int,
) -> Int? {
  let n = self.values.length()
  if n == 0 || lo < 0 || hi >= n || lo > hi {
    return None
  }
  if lo == hi {
    return Some(lo)
  }
  // LCA of nodes lo and hi gives the position of the min/max element
  Some(self.lca(lo, hi))
}

// ---------------------------------------------------------------------------
// LCA via Euler tour + sparse table
// ---------------------------------------------------------------------------

///|
/// Build the Euler tour, depth array, first occurrence array, and sparse
/// table for O(1) LCA queries.
fn[T] CartesianTree::build_lca_preprocessing(self : CartesianTree[T]) -> Unit {
  // 1. Build Euler tour via iterative DFS
  // Euler tour: record node each time we visit it (on entry and after each child)
  let euler : Array[Int] = []
  let depths : Array[Int] = []
  // Iterative DFS using a stack of (node, depth, child_to_process)
  // child_to_process: 0 = not started, 1 = processing left, 2 = processing right, 3 = done
  let dfs_stack : Array[(Int, Int, Int)] = []
  if self.root_index >= 0 {
    dfs_stack.push((self.root_index, 0, 0))
  }
  while dfs_stack.length() > 0 {
    let (node, depth, state) = dfs_stack[dfs_stack.length() - 1]
    if state == 0 {
      // First visit: record in Euler tour
      euler.push(node)
      depths.push(depth)
      if self.first_occ[node] == -1 {
        self.first_occ[node] = euler.length() - 1
      }
    }
    if state == 0 {
      // Process left child
      let left = self.nodes[node].left
      dfs_stack[dfs_stack.length() - 1] = (node, depth, 1)
      if left >= 0 {
        dfs_stack.push((left, depth + 1, 0))
      }
    } else if state == 1 {
      // Return from left child: record node again
      let left = self.nodes[node].left
      if left >= 0 {
        euler.push(node)
        depths.push(depth)
      }
      // Process right child
      dfs_stack[dfs_stack.length() - 1] = (node, depth, 2)
      let right = self.nodes[node].right
      if right >= 0 {
        dfs_stack.push((right, depth + 1, 0))
      }
    } else if state == 2 {
      // Return from right child: record node again
      let right = self.nodes[node].right
      if right >= 0 {
        euler.push(node)
        depths.push(depth)
      }
      dfs_stack[dfs_stack.length() - 1] = (node, depth, 3)
    } else {
      // Done with this node
      ignore(dfs_stack.pop())
    }
  }
  self.euler = euler
  self.depths = depths
  // 2. Build log table
  let m = euler.length()
  let log_table : Array[Int] = Array::make(m + 1, 0)
  for i = 2; i <= m; i = i + 1 {
    log_table[i] = log_table[i / 2] + 1
  }
  self.log_table = log_table
  // 3. Build sparse table for RMQ on depths
  // sparse[k][i] = index j in [i, i+2^k-1] minimizing depths[j]
  let max_k = log_table[m] + 1
  let sparse : Array[Array[Int]] = []
  // Level 0: each entry is itself
  let level0 : Array[Int] = Array::make(m, 0)
  for i = 0; i < m; i = i + 1 {
    level0[i] = i
  }
  sparse.push(level0)
  // Higher levels
  for k = 1; k < max_k; k = k + 1 {
    let prev = sparse[k - 1]
    let span = 1 << k
    let half = 1 << (k - 1)
    let level : Array[Int] = Array::make(m, 0)
    for i = 0; i + span <= m; i = i + 1 {
      let left_idx = prev[i]
      let right_idx = prev[i + half]
      // Choose the one with smaller depth (ties broken by smaller index)
      level[i] = if depths[left_idx] <= depths[right_idx] {
        left_idx
      } else {
        right_idx
      }
    }
    sparse.push(level)
  }
  self.sparse = sparse
}

///|
/// Compute the LCA (Lowest Common Ancestor) of nodes at positions u and v.
/// O(1) via Euler tour + sparse table.
fn[T] CartesianTree::lca(self : CartesianTree[T], u : Int, v : Int) -> Int {
  let fu = self.first_occ[u]
  let fv = self.first_occ[v]
  let (lo, hi) = if fu <= fv { (fu, fv) } else { (fv, fu) }
  let k = self.log_table[hi - lo + 1]
  let span = 1 << k
  let left_idx = self.sparse[k][lo]
  let right_idx = self.sparse[k][hi - span + 1]
  let min_idx = if self.depths[left_idx] <= self.depths[right_idx] {
    left_idx
  } else {
    right_idx
  }
  self.euler[min_idx]
}

// ---------------------------------------------------------------------------
// Traversal
// ---------------------------------------------------------------------------

///|
/// In-order traversal. O(n).
///
/// An in-order traversal of a Cartesian tree yields the original array order.
pub fn[T] CartesianTree::in_order(
  self : CartesianTree[T],
  f : (T) -> Unit,
) -> Unit {
  if self.root_index < 0 {
    return
  }
  // Iterative in-order traversal
  let stack : Array[Int] = []
  let mut cur = self.root_index
  while cur >= 0 || stack.length() > 0 {
    // Go to leftmost
    while cur >= 0 {
      stack.push(cur)
      cur = self.nodes[cur].left
    }
    cur = match stack.pop() {
      Some(v) => v
      None => -1
    }
    f(self.values[cur])
    cur = self.nodes[cur].right
  }
}

///|
/// Convert to array (in-order, which equals the original array). O(n).
pub fn[T] CartesianTree::to_array(self : CartesianTree[T]) -> Array[T] {
  let result : Array[T] = []
  self.in_order(fn(v) { result.push(v) })
  result
}

// ---------------------------------------------------------------------------
// Verification (test-only)
// ---------------------------------------------------------------------------

///|
/// Verify the Cartesian tree invariants:
/// 1. Heap property: each node's value ≤ (or ≥) its children's values.
/// 2. In-order property: in-order traversal yields the original array.
fn[T] verify_cartesian(
  tree : CartesianTree[T],
  compare : (T, T) -> Int,
) -> Bool {
  let n = tree.values.length()
  if n == 0 {
    return tree.root_index == -1
  }
  // Check heap property
  for i = 0; i < n; i = i + 1 {
    let node = tree.nodes[i]
    let left = node.left
    let right = node.right
    if left >= 0 && compare(tree.values[i], tree.values[left]) > 0 {
      return false
    }
    if right >= 0 && compare(tree.values[i], tree.values[right]) > 0 {
      return false
    }
  }
  // Check in-order property
  let result = tree.to_array()
  if result.length() != n {
    return false
  }
  for i = 0; i < n; i = i + 1 {
    if compare(result[i], tree.values[i]) != 0 {
      return false
    }
  }
  // Check root has no parent
  if tree.root_index >= 0 && tree.nodes[tree.root_index].parent != -1 {
    return false
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "cartesian_tree: empty array" {
  let t = CartesianTree::from_array([], fn(a : Int, b : Int) -> Int { a - b })
  assert_eq(t.size(), 0)
  assert_true(t.root() == -1)
  assert_true(t.rmq(0, 0) is None)
}

///|
test "cartesian_tree: single element" {
  let t = CartesianTree::from_array([42], fn(a : Int, b : Int) -> Int { a - b })
  assert_eq(t.size(), 1)
  assert_eq(t.root(), 0)
  assert_eq(t.rmq(0, 0), Some(0))
  assert_eq(t.get(0), Some(42))
}

///|
test "cartesian_tree: two elements ascending" {
  let t = CartesianTree::from_array([1, 2], fn(a : Int, b : Int) -> Int {
    a - b
  })
  // Min-heap: 1 is root, 2 is right child
  assert_eq(t.root(), 0)
  assert_eq(t.rmq(0, 1), Some(0)) // min is 1 at index 0
  assert_eq(t.rmq(1, 1), Some(1))
  assert_true(verify_cartesian(t, fn(a : Int, b : Int) -> Int { a - b }))
}

///|
test "cartesian_tree: two elements descending" {
  let t = CartesianTree::from_array([2, 1], fn(a : Int, b : Int) -> Int {
    a - b
  })
  // Min-heap: 1 is root, 2 is left child
  assert_eq(t.root(), 1)
  assert_eq(t.rmq(0, 1), Some(1)) // min is 1 at index 1
  assert_true(verify_cartesian(t, fn(a : Int, b : Int) -> Int { a - b }))
}

///|
test "cartesian_tree: in-order preserves original array" {
  let arr = [5, 2, 8, 1, 9, 3, 7, 4, 6]
  let t = CartesianTree::from_array(arr, fn(a : Int, b : Int) -> Int { a - b })
  let result = t.to_array()
  assert_eq(result, arr)
}

///|
test "cartesian_tree: heap property" {
  let arr = [5, 2, 8, 1, 9, 3, 7, 4, 6]
  let t = CartesianTree::from_array(arr, fn(a : Int, b : Int) -> Int { a - b })
  assert_true(verify_cartesian(t, fn(a : Int, b : Int) -> Int { a - b }))
}

///|
test "cartesian_tree: rmq basic" {
  //                1(3)
  //               /    \
  //             0(5)   5(3)  -- wait, 3==3, tie-breaking
  // Actually: arr = [5, 2, 8, 1, 9, 3, 7, 4, 6]
  // min = 1 at index 3 → root
  let arr = [5, 2, 8, 1, 9, 3, 7, 4, 6]
  let t = CartesianTree::from_array(arr, fn(a : Int, b : Int) -> Int { a - b })
  // Full range: min is 1 at index 3
  assert_eq(t.rmq(0, 8), Some(3))
  // Range [0, 1]: min is 2 at index 1
  assert_eq(t.rmq(0, 1), Some(1))
  // Range [4, 8]: min is 3 at index 5
  assert_eq(t.rmq(4, 8), Some(5))
  // Range [2, 2]: single element
  assert_eq(t.rmq(2, 2), Some(2))
  // Range [0, 4]: min is 1 at index 3
  assert_eq(t.rmq(0, 4), Some(3))
}

///|
test "cartesian_tree: rmq all same values" {
  let arr = [5, 5, 5, 5, 5]
  let t = CartesianTree::from_array(arr, fn(a : Int, b : Int) -> Int { a - b })
  // All values equal, any index is valid min
  let result = t.rmq(0, 4)
  assert_true(result is Some(_))
  // Check all single-element queries
  for i = 0; i < 5; i = i + 1 {
    assert_eq(t.rmq(i, i), Some(i))
  }
  assert_true(verify_cartesian(t, fn(a : Int, b : Int) -> Int { a - b }))
}

///|
test "cartesian_tree: rmq sorted ascending" {
  let arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  let t = CartesianTree::from_array(arr, fn(a : Int, b : Int) -> Int { a - b })
  // Min is always at the left end of any range
  assert_eq(t.rmq(0, 9), Some(0))
  assert_eq(t.rmq(3, 7), Some(3))
  assert_eq(t.rmq(5, 5), Some(5))
  assert_true(verify_cartesian(t, fn(a : Int, b : Int) -> Int { a - b }))
}

///|
test "cartesian_tree: rmq sorted descending" {
  let arr = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]
  let t = CartesianTree::from_array(arr, fn(a : Int, b : Int) -> Int { a - b })
  // Min is always at the right end of any range
  assert_eq(t.rmq(0, 9), Some(9))
  assert_eq(t.rmq(0, 4), Some(4))
  assert_eq(t.rmq(3, 7), Some(7))
  assert_true(verify_cartesian(t, fn(a : Int, b : Int) -> Int { a - b }))
}

///|
test "cartesian_tree: max-heap via reversed comparator" {
  // Reversed comparator → max-Cartesian tree
  let arr = [5, 2, 8, 1, 9, 3, 7, 4, 6]
  let t = CartesianTree::from_array(arr, fn(a : Int, b : Int) -> Int { b - a })
  // Full range: max is 9 at index 4
  assert_eq(t.rmq(0, 8), Some(4))
  // Range [0, 2]: max is 8 at index 2
  assert_eq(t.rmq(0, 2), Some(2))
  // Range [5, 8]: max is 7 at index 6
  assert_eq(t.rmq(5, 8), Some(6))
  assert_true(verify_cartesian(t, fn(a : Int, b : Int) -> Int { b - a }))
}

///|
test "cartesian_tree: rmq invalid ranges" {
  let t = CartesianTree::from_array([1, 2, 3], fn(a : Int, b : Int) -> Int {
    a - b
  })
  assert_true(t.rmq(-1, 2) is None)
  assert_true(t.rmq(0, 3) is None)
  assert_true(t.rmq(2, 1) is None)
}

///|
test "cartesian_tree: stress test rmq correctness" {
  // Compare O(1) RMQ against brute-force O(n) scan
  let arr = [7, 3, 9, 1, 8, 5, 2, 6, 4, 0, 7, 3, 8, 1, 5]
  let t = CartesianTree::from_array(arr, fn(a : Int, b : Int) -> Int { a - b })
  for lo = 0; lo < arr.length(); lo = lo + 1 {
    for hi = lo; hi < arr.length(); hi = hi + 1 {
      // Brute-force: find min index
      let mut min_idx = lo
      for k = lo + 1; k <= hi; k = k + 1 {
        if arr[k] < arr[min_idx] {
          min_idx = k
        }
      }
      assert_eq(t.rmq(lo, hi), Some(min_idx))
    }
  }
  assert_true(verify_cartesian(t, fn(a : Int, b : Int) -> Int { a - b }))
}

///|
test "cartesian_tree: large random stress test" {
  // Generate pseudo-random array and verify RMQ
  let mut seed = 12345
  let arr : Array[Int] = []
  for i = 0; i < 500; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    arr.push(seed % 1000)
  }
  let t = CartesianTree::from_array(arr, fn(a : Int, b : Int) -> Int { a - b })
  assert_true(verify_cartesian(t, fn(a : Int, b : Int) -> Int { a - b }))
  // Test 200 random queries
  for q = 0; q < 200; q = q + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let lo = seed % 500
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let hi = lo + seed % (500 - lo)
    // Brute-force
    let mut min_idx = lo
    for k = lo + 1; k <= hi; k = k + 1 {
      if arr[k] < arr[min_idx] {
        min_idx = k
      }
    }
    assert_eq(t.rmq(lo, hi), Some(min_idx))
  }
}

///|
test "cartesian_tree: string keys" {
  let arr = ["cherry", "apple", "banana", "date"]
  let t = CartesianTree::from_array(arr, fn(a : String, b : String) -> Int {
    let ac = a.to_array()
    let bc = b.to_array()
    let n = if ac.length() < bc.length() { ac.length() } else { bc.length() }
    let mut i = 0
    while i < n {
      let d = ac[i].to_int() - bc[i].to_int()
      if d != 0 {
        return d
      }
      i = i + 1
    }
    ac.length() - bc.length()
  })
  // "apple" is the minimum at index 1
  assert_eq(t.rmq(0, 3), Some(1))
  assert_eq(t.rmq(0, 0), Some(0))
  assert_eq(t.rmq(2, 3), Some(2)) // "banana" < "date"
  assert_true(t.to_array() == arr)
}
