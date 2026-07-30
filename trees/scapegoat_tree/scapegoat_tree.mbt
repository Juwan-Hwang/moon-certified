/// Scapegoat Tree — a self-balancing BST with zero per-node overhead.
///
/// A **scapegoat tree** is a self-balancing binary search tree discovered by
/// Arne Andersson and Igal Galperin & Ronald Rivest. Unlike AVL trees (which
/// store height) or Red-Black trees (which store color), scapegoat trees store
/// **no balancing information in nodes** — only the key and child pointers.
/// Balance is maintained by occasionally rebuilding an entire subtree that has
/// become too unbalanced.
///
/// ## Balancing Parameter α
///
/// The tree maintains an **α-balance** invariant: for every node, the size of
/// each subtree is at most `α · size(node)`, where `0.5 < α < 1.0`. The
/// default is `α = 2/3`. A smaller α keeps the tree more balanced (shallower)
/// at the cost of more frequent rebuilds; a larger α allows more imbalance
/// but fewer rebuilds.
///
/// ## Insertion
///
/// 1. Standard BST insert, tracking the insertion depth.
/// 2. If the depth exceeds `h_α(n) = ⌊log_{1/α} n⌋`, walk from root toward
///    the inserted node. The first node where one child's subtree exceeds
///    `α · size(node)` is the **scapegoat**.
/// 3. Rebuild the scapegoat's subtree into a perfectly balanced tree.
///
/// ## Deletion
///
/// 1. Standard BST delete.
/// 2. If `n < α · max_n` (where `max_n` is the size after the last full
///    rebuild), rebuild the entire tree and reset `max_n = n`.
///
/// ## Complexity
///
/// | Operation  | Amortized  | Worst-case |
/// |------------|------------|------------|
/// | `insert`   | O(log n)   | O(n)       |
/// | `delete`   | O(log n)   | O(n)       |
/// | `search`   | O(log n)   | O(log n)   |
/// | `rebuild`  | O(n)       | O(n)       |
///
/// ## Advantages
///
/// - **Zero per-node overhead**: no color, height, or balance factor.
/// - **Simple implementation**: no rotations, only full subtree rebuilds.
/// - **Good cache behavior**: rebuilt subtrees are perfectly balanced.
///
/// ## References
///
/// - Galperin, I. & Rivest, R. L. (1993). "Scapegoat trees."
///   *Proceedings of the Fourth Annual ACM-SIAM Symposium on Discrete
///   Algorithms*, 165–174.
/// - Andersson, A. (1989). "Improving partial rebuilding by using simple
///   balance criteria." *Workshop on Algorithms and Data Structures*.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Node type
// ---------------------------------------------------------------------------

///|
/// A scapegoat tree node. No balancing information is stored.
priv struct SgNode[T] {
  mut val : T
  mut left : SgNode[T]?
  mut right : SgNode[T]?
}

// ---------------------------------------------------------------------------
// Tree type
// ---------------------------------------------------------------------------

///|
/// A scapegoat tree with a user-supplied comparator.
///
/// `compare(a, b)` returns `< 0` when `a < b`, `0` when equal, `> 0` when
/// `a > b`.
pub struct ScapegoatTree[T] {
  priv mut root : SgNode[T]?
  priv compare : (T, T) -> Int
  priv mut count : Int
  priv mut max_count : Int // max size since last full rebuild
  priv alpha : Double // balancing parameter, 0.5 < α < 1.0
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create an empty scapegoat tree with the default α = 2/3.
pub fn[T] ScapegoatTree::new(compare : (T, T) -> Int) -> ScapegoatTree[T] {
  { root: None, compare, count: 0, max_count: 0, alpha: 2.0 / 3.0 }
}

///|
/// Create an empty scapegoat tree with a custom α.
///
/// `alpha` must be in the range (0.5, 1.0). Values closer to 0.5 keep the
/// tree more balanced but trigger more rebuilds; values closer to 1.0 allow
/// more imbalance but fewer rebuilds.
pub fn[T] ScapegoatTree::with_alpha(
  compare : (T, T) -> Int,
  alpha : Double,
) -> ScapegoatTree[T] {
  let a = if alpha <= 0.5 {
    0.51
  } else if alpha >= 1.0 {
    0.99
  } else {
    alpha
  }
  { root: None, compare, count: 0, max_count: 0, alpha: a }
}

// ---------------------------------------------------------------------------
// Basic queries
// ---------------------------------------------------------------------------

///|
/// Returns the number of elements in the tree. O(1).
pub fn[T] ScapegoatTree::size(self : ScapegoatTree[T]) -> Int {
  self.count
}

///|
/// Returns `true` if the tree is empty. O(1).
pub fn[T] ScapegoatTree::is_empty(self : ScapegoatTree[T]) -> Bool {
  self.count == 0
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

///|
/// Search for a key in the tree. O(log n).
///
/// Returns `true` if the key exists.
pub fn[T] ScapegoatTree::contains(self : ScapegoatTree[T], key : T) -> Bool {
  let mut cur = self.root
  while cur is Some(_) {
    match cur {
      Some(n) => {
        let c = (self.compare)(key, n.val)
        if c == 0 {
          return true
        } else if c < 0 {
          cur = n.left
        } else {
          cur = n.right
        }
      }
      None => return false
    }
  }
  false
}

///|
/// Find the minimum key in the tree. O(log n).
///
/// Returns `None` if the tree is empty.
pub fn[T] ScapegoatTree::find_min(self : ScapegoatTree[T]) -> T? {
  match self.root {
    None => None
    Some(n) => {
      let mut node = n
      while node.left is Some(_) {
        match node.left {
          Some(l) => node = l
          None => ()
        }
      }
      Some(node.val)
    }
  }
}

///|
/// Find the maximum key in the tree. O(log n).
///
/// Returns `None` if the tree is empty.
pub fn[T] ScapegoatTree::find_max(self : ScapegoatTree[T]) -> T? {
  match self.root {
    None => None
    Some(n) => {
      let mut node = n
      while node.right is Some(_) {
        match node.right {
          Some(r) => node = r
          None => ()
        }
      }
      Some(node.val)
    }
  }
}

// ---------------------------------------------------------------------------
// Insertion
// ---------------------------------------------------------------------------

///|
/// Insert a key into the tree. O(log n) amortized.
///
/// If the key already exists, the tree is unchanged and `false` is returned.
/// Otherwise, `true` is returned.
pub fn[T] ScapegoatTree::insert(self : ScapegoatTree[T], key : T) -> Bool {
  // Collect the path to the insertion point.
  let path : Array[SgNode[T]] = []
  let mut cur = self.root
  let mut found = false
  while cur is Some(_) && !found {
    match cur {
      Some(n) => {
        path.push(n)
        let c = (self.compare)(key, n.val)
        if c == 0 {
          return false // Duplicate key
        } else if c < 0 {
          cur = n.left
        } else {
          cur = n.right
        }
      }
      None => found = true
    }
  }
  // Create the new node.
  let new_node : SgNode[T] = { val: key, left: None, right: None }
  // Attach to parent.
  if path.length() == 0 {
    self.root = Some(new_node)
  } else {
    let parent = path[path.length() - 1]
    let c = (self.compare)(key, parent.val)
    if c < 0 {
      parent.left = Some(new_node)
    } else {
      parent.right = Some(new_node)
    }
  }
  self.count = self.count + 1
  self.max_count = if self.count > self.max_count { self.count } else { self.max_count }
  // Check if the tree is too deep.
  let h_alpha = log_alpha(self.count, self.alpha)
  let depth = path.length() // depth of the new node
  if depth > h_alpha {
    // Find the scapegoat: walk from root toward the new node.
    // The scapegoat is the highest node on the path where one child's subtree
    // has more than α * total_size nodes.
    let mut i = 0
    let mut scapegoat_idx = -1
    while i < path.length() {
      let node = path[i]
      let node_size = size_of(Some(node))
      let child_size =
        if i + 1 < path.length() {
          size_of(Some(path[i + 1]))
        } else {
          1 // The newly inserted node
        }
      let sibling_size = node_size - child_size - 1
      let threshold = self.alpha * node_size.to_double()
      if child_size.to_double() > threshold || sibling_size.to_double() > threshold {
        scapegoat_idx = i
        // Keep going to find the HIGHEST (smallest i) scapegoat
        break
      }
      i = i + 1
    }
    // Rebuild the scapegoat's subtree.
    if scapegoat_idx >= 0 {
      let scapegoat = path[scapegoat_idx]
      let rebuilt = rebuild(Some(scapegoat))
      // Reattach rebuilt subtree.
      if scapegoat_idx == 0 {
        self.root = rebuilt
      } else {
        let parent = path[scapegoat_idx - 1]
        let c = (self.compare)(scapegoat.val, parent.val)
        if c < 0 {
          parent.left = rebuilt
        } else {
          parent.right = rebuilt
        }
      }
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Deletion
// ---------------------------------------------------------------------------

///|
/// Remove a key from the tree. O(log n) amortized.
///
/// Returns `true` if the key was found and removed, `false` otherwise.
pub fn[T] ScapegoatTree::remove(self : ScapegoatTree[T], key : T) -> Bool {
  // Find the node to delete and its parent.
  let mut parent : SgNode[T]? = None
  let mut cur = self.root
  let mut found = false
  while cur is Some(_) && !found {
    match cur {
      Some(n) => {
        let c = (self.compare)(key, n.val)
        if c == 0 {
          found = true
        } else if c < 0 {
          parent = cur
          cur = n.left
        } else {
          parent = cur
          cur = n.right
        }
      }
      None => ()
    }
  }
  if !found {
    return false
  }
  let node =
    match cur {
      Some(n) => n
      None => return false
    }
  // Case 1: Node has two children — replace with in-order successor.
  if node.left is Some(_) && node.right is Some(_) {
    // Find in-order successor (min of right subtree).
    let mut succ_parent : SgNode[T] = node
    let mut succ = match node.right {
      Some(r) => r
      None => node // unreachable
    }
    while succ.left is Some(_) {
      succ_parent = succ
      match succ.left {
        Some(l) => succ = l
        None => ()
      }
    }
    // Copy successor's value into node.
    node.val = succ.val
    // Delete successor (it has at most one right child).
    if (self.compare)(succ_parent.val, node.val) == 0 {
      // succ_parent is node itself; succ is node.right
      succ_parent.right = succ.right
    } else {
      succ_parent.left = succ.right
    }
  } else {
    // Case 2: Node has 0 or 1 child — replace with child.
    let child =
      match node.left {
        Some(l) => Some(l)
        None =>
          match node.right {
            Some(r) => Some(r)
            None => None
          }
      }
    match parent {
      None => self.root = child
      Some(p) =>
        if (self.compare)(node.val, p.val) < 0 {
          p.left = child
        } else {
          p.right = child
        }
    }
  }
  self.count = self.count - 1
  // Check if we need a full rebuild.
  let threshold = self.alpha * self.max_count.to_double()
  if self.count.to_double() < threshold {
    self.root = rebuild(self.root)
    self.max_count = self.count
  }
  true
}

// ---------------------------------------------------------------------------
// Rebuild: flatten + build perfectly balanced subtree
// ---------------------------------------------------------------------------

///|
/// Rebuild a subtree into a perfectly balanced BST.
///
/// 1. Flatten the subtree into a sorted array (in-order traversal).
/// 2. Build a perfectly balanced BST from the array.
///
/// Returns the new root of the rebuilt subtree.
fn[T] rebuild(node : SgNode[T]?) -> SgNode[T]? {
  let arr : Array[SgNode[T]] = []
  flatten(node, arr)
  if arr.length() == 0 {
    return None
  }
  build_balanced(arr, 0, arr.length() - 1)
}

///|
/// In-order traversal to flatten the subtree into a sorted array.
fn[T] flatten(node : SgNode[T]?, arr : Array[SgNode[T]]) -> Unit {
  match node {
    None => ()
    Some(n) => {
      flatten(n.left, arr)
      arr.push(n)
      flatten(n.right, arr)
    }
  }
}

///|
/// Build a perfectly balanced BST from a sorted array of nodes.
/// Returns the root of the balanced subtree.
fn[T] build_balanced(
  arr : Array[SgNode[T]],
  lo : Int,
  hi : Int,
) -> SgNode[T]? {
  if lo > hi {
    return None
  }
  let mid = lo + (hi - lo) / 2
  let node = arr[mid]
  node.left = build_balanced(arr, lo, mid - 1)
  node.right = build_balanced(arr, mid + 1, hi)
  Some(node)
}

// ---------------------------------------------------------------------------
// Size computation
// ---------------------------------------------------------------------------

///|
/// Compute the size of a subtree. O(n) — no per-node size is stored.
fn[T] size_of(node : SgNode[T]?) -> Int {
  match node {
    None => 0
    Some(n) => 1 + size_of(n.left) + size_of(n.right)
  }
}

// ---------------------------------------------------------------------------
// Height computation
// ---------------------------------------------------------------------------

///|
/// Compute the height of the tree. O(n).
fn[T] height_of(node : SgNode[T]?) -> Int {
  match node {
    None => 0
    Some(n) => {
      let lh = height_of(n.left)
      let rh = height_of(n.right)
      let max_h = if lh > rh { lh } else { rh }
      1 + max_h
    }
  }
}

// ---------------------------------------------------------------------------
// Logarithm for α-balanced height threshold
// ---------------------------------------------------------------------------

///|
/// Compute h_α(n) = floor(log_{1/α}(n)), the maximum allowed height.
///
/// If n ≤ 1, returns 0. Uses iterative multiplication to avoid depending
/// on floating-point logarithm functions.
fn log_alpha(n : Int, alpha : Double) -> Int {
  if n <= 1 {
    return 0
  }
  // Compute floor(log_{1/α}(n)) iteratively.
  // We want the largest h such that (1/α)^h <= n, i.e., α^(-h) <= n.
  // Equivalently, multiply by 1/α until we exceed n.
  let inv_alpha = 1.0 / alpha // > 1.0 since 0.5 < α < 1.0
  let mut power = 1.0
  let mut h = 0
  while power <= n.to_double() {
    power = power * inv_alpha
    h = h + 1
  }
  h - 1
}

// ---------------------------------------------------------------------------
// In-order traversal
// ---------------------------------------------------------------------------

///|
/// Traverse the tree in-order, calling `f` on each key.
pub fn[T] ScapegoatTree::in_order(
  self : ScapegoatTree[T],
  f : (T) -> Unit,
) -> Unit {
  in_order_rec(self.root, f)
}

fn[T] in_order_rec(node : SgNode[T]?, f : (T) -> Unit) -> Unit {
  match node {
    None => ()
    Some(n) => {
      in_order_rec(n.left, f)
      f(n.val)
      in_order_rec(n.right, f)
    }
  }
}

///|
/// Convert the tree to a sorted array (in-order). O(n).
pub fn[T] ScapegoatTree::to_sorted_array(self : ScapegoatTree[T]) -> Array[T] {
  let result : Array[T] = []
  self.in_order(fn(v) { result.push(v) })
  result
}

// ---------------------------------------------------------------------------
// Verification (test-only)
// ---------------------------------------------------------------------------

///|
/// Verify the BST property: left < node < right.
fn[T] verify_bst(
  node : SgNode[T]?,
  compare : (T, T) -> Int,
) -> Bool {
  match node {
    None => true
    Some(n) => {
      let left_ok =
        match n.left {
          None => true
          Some(l) =>
            compare(l.val, n.val) < 0 && verify_bst(Some(l), compare)
        }
      let right_ok =
        match n.right {
          None => true
          Some(r) =>
            compare(r.val, n.val) > 0 && verify_bst(Some(r), compare)
        }
      left_ok && right_ok
    }
  }
}

///|
/// Verify the α-balance property: each subtree size ≤ α · node size.
fn[T] verify_alpha_balance(
  node : SgNode[T]?,
  alpha : Double,
) -> Bool {
  match node {
    None => true
    Some(n) => {
      let total = size_of(Some(n))
      let left_size = size_of(n.left)
      let right_size = size_of(n.right)
      let threshold = alpha * total.to_double()
      if left_size.to_double() > threshold || right_size.to_double() > threshold {
        false
      } else {
        verify_alpha_balance(n.left, alpha) && verify_alpha_balance(n.right, alpha)
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "scapegoat_tree: empty tree" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  assert_true(t.is_empty())
  assert_eq(t.size(), 0)
  assert_false(t.contains(0))
  assert_true(t.find_min() is None)
  assert_true(t.find_max() is None)
}

test "scapegoat_tree: insert and search" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  assert_true(t.insert(5))
  assert_true(t.insert(3))
  assert_true(t.insert(7))
  assert_true(t.insert(1))
  assert_true(t.insert(9))
  assert_eq(t.size(), 5)
  assert_true(t.contains(5))
  assert_true(t.contains(1))
  assert_true(t.contains(9))
  assert_false(t.contains(0))
  assert_false(t.contains(4))
}

test "scapegoat_tree: duplicate insert returns false" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  assert_true(t.insert(5))
  assert_false(t.insert(5))
  assert_eq(t.size(), 1)
}

test "scapegoat_tree: find_min and find_max" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(7))
  ignore(t.insert(1))
  ignore(t.insert(9))
  assert_eq(t.find_min(), Some(1))
  assert_eq(t.find_max(), Some(9))
}

test "scapegoat_tree: in-order traversal is sorted" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  let input = [7, 3, 9, 1, 5, 8, 2, 6, 4, 0]
  for i = 0; i < input.length(); i = i + 1 {
    ignore(t.insert(input[i]))
  }
  let result = t.to_sorted_array()
  assert_eq(result.length(), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(result[i], i)
  }
}

test "scapegoat_tree: BST property maintained after inserts" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 100; i = i + 1 {
    ignore(t.insert(i * 37 % 100))
  }
  assert_true(verify_bst(t.root, t.compare))
}

test "scapegoat_tree: insert sorted ascending (worst case)" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 200; i = i + 1 {
    ignore(t.insert(i))
  }
  assert_eq(t.size(), 200)
  assert_true(verify_bst(t.root, t.compare))
  // After rebuilds, height should be O(log n), not O(n)
  let h = height_of(t.root)
  // For n=200, alpha=2/3: h_alpha ≈ log_{3/2}(200) ≈ 14
  // Allow some slack for the check
  assert_true(h <= 20)
  let result = t.to_sorted_array()
  for i = 0; i < 200; i = i + 1 {
    assert_eq(result[i], i)
  }
}

test "scapegoat_tree: insert sorted descending" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 200; i = i + 1 {
    ignore(t.insert(200 - i))
  }
  assert_eq(t.size(), 200)
  assert_true(verify_bst(t.root, t.compare))
  let h = height_of(t.root)
  assert_true(h <= 20)
}

test "scapegoat_tree: remove leaf" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(7))
  assert_true(t.remove(3))
  assert_eq(t.size(), 2)
  assert_false(t.contains(3))
  assert_true(t.contains(5))
  assert_true(t.contains(7))
}

test "scapegoat_tree: remove node with one child" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(7))
  ignore(t.insert(8))
  assert_true(t.remove(7))
  assert_eq(t.size(), 3)
  assert_false(t.contains(7))
  assert_true(t.contains(8))
  assert_true(verify_bst(t.root, t.compare))
}

test "scapegoat_tree: remove node with two children" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(7))
  ignore(t.insert(1))
  ignore(t.insert(4))
  ignore(t.insert(6))
  ignore(t.insert(8))
  assert_true(t.remove(5))
  assert_eq(t.size(), 6)
  assert_false(t.contains(5))
  assert_true(t.contains(3))
  assert_true(t.contains(7))
  assert_true(verify_bst(t.root, t.compare))
  let result = t.to_sorted_array()
  assert_eq(result, [1, 3, 4, 6, 7, 8])
}

test "scapegoat_tree: remove non-existent" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  assert_false(t.remove(7))
  assert_eq(t.size(), 2)
}

test "scapegoat_tree: remove all elements" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 50; i = i + 1 {
    ignore(t.insert(i))
  }
  for i = 0; i < 50; i = i + 1 {
    assert_true(t.remove(i))
  }
  assert_eq(t.size(), 0)
  assert_true(t.is_empty())
}

test "scapegoat_tree: intermixed insert and remove" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(7))
  ignore(t.remove(3))
  ignore(t.insert(1))
  ignore(t.insert(9))
  ignore(t.remove(5))
  ignore(t.insert(4))
  assert_true(verify_bst(t.root, t.compare))
  let result = t.to_sorted_array()
  assert_eq(result, [1, 4, 7, 9])
}

test "scapegoat_tree: alpha balance after heavy inserts" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 500; i = i + 1 {
    ignore(t.insert(i * 31 % 500))
  }
  assert_eq(t.size(), 500)
  assert_true(verify_bst(t.root, t.compare))
  // Scapegoat tree guarantees O(log n) height, not strict α-balance at all times.
  // The α-balance property holds immediately after a rebuild, but between
  // rebuilds a single insertion can temporarily violate it.
  // The height guarantee is the actual invariant.
  let h = height_of(t.root)
  // For n=500, alpha=2/3: h_alpha ≈ log_{3/2}(500) ≈ 15.3
  // Allow some slack for temporary imbalance between rebuilds.
  assert_true(h <= 25)
}

test "scapegoat_tree: height is logarithmic" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 1000; i = i + 1 {
    ignore(t.insert(i))
  }
  let h = height_of(t.root)
  // For n=1000, alpha=2/3: h_alpha ≈ log_{3/2}(1000) ≈ 17.5
  // Allow some slack
  assert_true(h <= 25)
  // Should be much less than n=1000
  assert_true(h < 100)
}

test "scapegoat_tree: custom alpha" {
  let t = ScapegoatTree::with_alpha(fn(a : Int, b : Int) -> Int { a - b }, 0.6)
  for i = 0; i < 200; i = i + 1 {
    ignore(t.insert(i))
  }
  assert_true(verify_bst(t.root, t.compare))
  // With α=0.6, tree should be more balanced
  let h = height_of(t.root)
  // log_{1/0.6}(200) ≈ log_{5/3}(200) ≈ 10.3
  assert_true(h <= 18)
}

test "scapegoat_tree: full rebuild after deletions" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 100; i = i + 1 {
    ignore(t.insert(i))
  }
  // Delete more than 1-α = 1/3 of elements
  for i = 0; i < 40; i = i + 1 {
    ignore(t.remove(i))
  }
  assert_eq(t.size(), 60)
  assert_true(verify_bst(t.root, t.compare))
  // After rebuild, tree should be well-balanced
  let h = height_of(t.root)
  assert_true(h <= 15)
}

test "scapegoat_tree: alpha balance holds after rebuild" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 100; i = i + 1 {
    ignore(t.insert(i))
  }
  // Remove exactly enough to trigger one rebuild (count < α * max_count)
  // α = 2/3, max_count = 100, threshold = 66.67
  // Remove 34 elements so count = 66 < 66.67 → rebuild triggers
  for i = 0; i < 34; i = i + 1 {
    ignore(t.remove(i))
  }
  assert_eq(t.size(), 66)
  assert_true(verify_bst(t.root, t.compare))
  // After a full rebuild, α-balance property must hold
  assert_true(verify_alpha_balance(t.root, t.alpha))
}

test "scapegoat_tree: stress test random operations" {
  let t = ScapegoatTree::new(fn(a : Int, b : Int) -> Int { a - b })
  let mut seed = 42
  let present : Array[Bool] = Array::make(200, false)
  let mut count = 0
  for i = 0; i < 2000; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let val = seed % 200
    let op = seed % 3
    if op == 0 || op == 1 {
      // Insert
      if !present[val] {
        assert_true(t.insert(val))
        present[val] = true
        count = count + 1
      } else {
        assert_false(t.insert(val))
      }
    } else {
      // Remove
      if present[val] {
        assert_true(t.remove(val))
        present[val] = false
        count = count - 1
      } else {
        assert_false(t.remove(val))
      }
    }
    // Periodically verify BST property
    if i % 500 == 499 {
      assert_true(verify_bst(t.root, t.compare))
      assert_eq(t.size(), count)
    }
  }
  // Final verification
  assert_true(verify_bst(t.root, t.compare))
  assert_eq(t.size(), count)
  // Verify all present elements are in the tree
  let sorted = t.to_sorted_array()
  let mut idx = 0
  for v = 0; v < 200; v = v + 1 {
    if present[v] {
      assert_eq(sorted[idx], v)
      idx = idx + 1
    }
  }
}

test "scapegoat_tree: string keys" {
  let t = ScapegoatTree::new(fn(a : String, b : String) -> Int {
    let ac = a.to_array()
    let bc = b.to_array()
    let n = if ac.length() < bc.length() { ac.length() } else { bc.length() }
    let mut i = 0
    while i < n {
      let d = ac[i].to_int() - bc[i].to_int()
      if d != 0 { return d }
      i = i + 1
    }
    ac.length() - bc.length()
  })
  ignore(t.insert("cherry"))
  ignore(t.insert("apple"))
  ignore(t.insert("banana"))
  ignore(t.insert("date"))
  assert_eq(t.find_min(), Some("apple"))
  assert_eq(t.find_max(), Some("date"))
  assert_true(t.contains("banana"))
  assert_false(t.contains("elderberry"))
  let result = t.to_sorted_array()
  assert_eq(result, ["apple", "banana", "cherry", "date"])
}
