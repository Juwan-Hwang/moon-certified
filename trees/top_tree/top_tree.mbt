/// Top Tree — Self-adjusting top tree for dynamic forest with path and subtree queries.
///
/// A **top tree** is a data structure that maintains a forest of trees and
/// supports both **path queries** (aggregate along a path between two nodes)
/// and **subtree queries** (aggregate over a subtree) under link/cut operations,
/// all in O(log n) amortized time.
///
/// This implementation uses the **self-adjusting top tree** approach based on
/// splay trees (Werneck & Tarjan 2007), augmented with "virtual" children
/// to track non-preferred subtrees (side branches).
///
/// ## Supported Operations
///
/// - `link(u, v)`: Add edge (u,v). O(log n) amortized.
/// - `cut(u, v)`: Remove edge (u,v). O(log n) amortized.
/// - `connected(u, v)`: Check if u and v are in the same tree. O(log n) amortized.
/// - `path_sum(u, v)`: Sum of values on path u→v. O(log n) amortized.
/// - `path_min(u, v)`: Minimum value on path u→v. O(log n) amortized.
/// - `path_max(u, v)`: Maximum value on path u→v. O(log n) amortized.
/// - `subtree_sum(u)`: Sum of values in subtree rooted at u. O(log n) amortized.
/// - `set_value(u, val)`: Update vertex u's value. O(log n) amortized.
/// - `vertex_value(u)`: Get vertex u's value. O(log n) amortized.
///
/// ## Key Idea
///
/// The forest is represented using splay trees, where each tree is decomposed
/// into "preferred paths" (chains). Each splay node maintains:
///
/// - **Chain aggregates**: sum/min/max over the preferred path (splay subtree only,
///   excluding virtual children). Used for path queries.
/// - **Virtual aggregates**: sum/min/max over non-preferred children (side branches).
///
/// The **subtree aggregate** of a node is: chain aggregate + virtual aggregate,
/// computed after making the node the root of its represented tree.
///
/// ## Complexity
///
/// All operations: O(log n) amortized time, O(n) space.
///
/// ## References
///
/// - Werneck, R. & Tarjan, R. E. (2007): "Self-Adjusting Top Trees."
///   SODA 2007, pp. 813–822.
/// - Tarjan, R. E. (1997): "Dynamic trees as search trees via Euler tours,
///   applied to the network simplex algorithm." Mathematical Programming, 78.
/// - Sleator, D. D. & Tarjan, R. E. (1983): "A Data Structure for Dynamic Trees."
///   JCSS, 26(3), 362–391.
///
/// `proof-enabled` is `false`; correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Sentinel for "no node".
let nil_node : Int = -1

///|
/// Identity for min aggregate (positive infinity).
let inf_max : Int = 2147483647

///|
/// Identity for max aggregate (negative infinity).
let inf_min : Int = -2147483648

// ---------------------------------------------------------------------------
// Top Tree state
// ---------------------------------------------------------------------------

///|
/// The Top Tree state, maintaining a forest of n vertices (0-indexed).
///
/// Internally uses arrays for splay tree structure (left/right children,
/// parent pointers, lazy reversal flags) and aggregate values.
pub struct TopTree {
  n : Int
  // Splay tree structure.
  left : Array[Int]
  right : Array[Int]
  parent : Array[Int]
  rev : Array[Bool]
  // Vertex values.
  val : Array[Int]
  // Chain aggregates (preferred path only, EXCLUDING virtual children).
  path_sum : Array[Int]
  path_min : Array[Int]
  path_max : Array[Int]
  path_size : Array[Int]
  // Virtual aggregates (non-preferred children = side branches).
  vir_sum : Array[Int]
  vir_min : Array[Int]
  vir_max : Array[Int]
  vir_size : Array[Int]
  // Saved contribution of each node when it was added as a virtual child.
  // Used to correctly undo the addition even if the child's splay tree
  // was restructured between add_virtual and remove_virtual.
  vir_saved_sum : Array[Int]
  vir_saved_size : Array[Int]
}

///|
/// Create a new Top Tree with `n` vertices, each with value 0.
pub fn TopTree::new(n : Int) -> TopTree {
  {
    n,
    left: Array::make(n, nil_node),
    right: Array::make(n, nil_node),
    parent: Array::make(n, nil_node),
    rev: Array::make(n, false),
    val: Array::make(n, 0),
    path_sum: Array::make(n, 0),
    path_min: Array::make(n, 0),
    path_max: Array::make(n, 0),
    path_size: Array::make(n, 1),
    vir_sum: Array::make(n, 0),
    vir_min: Array::make(n, inf_max),
    vir_max: Array::make(n, inf_min),
    vir_size: Array::make(n, 0),
    vir_saved_sum: Array::make(n, 0),
    vir_saved_size: Array::make(n, 0),
  }
}

///|
/// Create a new Top Tree with initial vertex values.
pub fn TopTree::with_values(n : Int, values : Array[Int]) -> TopTree {
  let t = TopTree::new(n)
  for i = 0; i < n && i < values.length(); i = i + 1 {
    t.val[i] = values[i]
    t.path_sum[i] = values[i]
    t.path_min[i] = values[i]
    t.path_max[i] = values[i]
  }
  t
}

// ---------------------------------------------------------------------------
// Helper: compute total (chain + virtual) aggregates
// ---------------------------------------------------------------------------

///|
/// Total sum of node x's subtree: chain_sum + vir_sum.
fn all_sum(t : TopTree, x : Int) -> Int {
  t.path_sum[x] + t.vir_sum[x]
}

///|
/// Total min of node x's subtree: min(chain_min, vir_min).
fn all_min(t : TopTree, x : Int) -> Int {
  let m = t.path_min[x]
  let vm = t.vir_min[x]
  if m < vm {
    m
  } else {
    vm
  }
}

///|
/// Total max of node x's subtree: max(chain_max, vir_max).
fn all_max(t : TopTree, x : Int) -> Int {
  let m = t.path_max[x]
  let vm = t.vir_max[x]
  if m > vm {
    m
  } else {
    vm
  }
}

///|
/// Total size of node x's subtree: chain_size + vir_size.
fn all_size(t : TopTree, x : Int) -> Int {
  t.path_size[x] + t.vir_size[x]
}

// ---------------------------------------------------------------------------
// Splay tree operations
// ---------------------------------------------------------------------------

///|
/// Check if x is a root of its splay tree (parent is nil or x is a path-parent).
fn is_root(t : TopTree, x : Int) -> Bool {
  let p = t.parent[x]
  p == nil_node || (t.left[p] != x && t.right[p] != x)
}

///|
/// Push down lazy reversal flag.
fn push_down(t : TopTree, x : Int) -> Unit {
  if t.rev[x] {
    let l = t.left[x]
    let r = t.right[x]
    t.left[x] = r
    t.right[x] = l
    if l != nil_node {
      t.rev[l] = !t.rev[l]
    }
    if r != nil_node {
      t.rev[r] = !t.rev[r]
    }
    t.rev[x] = false
  }
}

///|
/// Update chain aggregate values for node x based on its splay children.
/// Chain aggregates EXCLUDE virtual children.
fn push_up(t : TopTree, x : Int) -> Unit {
  let l = t.left[x]
  let r = t.right[x]
  // Chain size: 1 + left.chain_size + right.chain_size.
  let mut ps = 1
  if l != nil_node {
    ps = ps + t.path_size[l]
  }
  if r != nil_node {
    ps = ps + t.path_size[r]
  }
  t.path_size[x] = ps
  // Chain sum: val + left.chain_sum + right.chain_sum (NO vir_sum).
  let mut psum = t.val[x]
  let mut pmin = t.val[x]
  let mut pmax = t.val[x]
  if l != nil_node {
    psum = psum + t.path_sum[l]
    if t.path_min[l] < pmin {
      pmin = t.path_min[l]
    }
    if t.path_max[l] > pmax {
      pmax = t.path_max[l]
    }
  }
  if r != nil_node {
    psum = psum + t.path_sum[r]
    if t.path_min[r] < pmin {
      pmin = t.path_min[r]
    }
    if t.path_max[r] > pmax {
      pmax = t.path_max[r]
    }
  }
  t.path_sum[x] = psum
  t.path_min[x] = pmin
  t.path_max[x] = pmax
}

///|
/// Rotate x up (within its splay tree).
fn rotate(t : TopTree, x : Int) -> Unit {
  let p = t.parent[x]
  let g = t.parent[p]
  let is_left = t.left[p] == x
  // Determine if p is a splay root.
  let p_is_root = is_root(t, p)
  // Disconnect x's child that will move to p.
  let child = if is_left { t.right[x] } else { t.left[x] }
  // Move child to p.
  if is_left {
    t.right[x] = p
    t.left[p] = child
  } else {
    t.left[x] = p
    t.right[p] = child
  }
  // Set child's parent.
  if child != nil_node {
    t.parent[child] = p
  }
  // Set p's parent to x.
  t.parent[p] = x
  // Set x's parent to g.
  t.parent[x] = g
  // Update g's child pointer (if p was not a splay root).
  if g != nil_node && !p_is_root {
    if t.left[g] == p {
      t.left[g] = x
    } else if t.right[g] == p {
      t.right[g] = x
    }
    push_up(t, p)
    push_up(t, x)
    push_up(t, g)
  } else {
    push_up(t, p)
    push_up(t, x)
  }
}

///|
/// Splay node x to the root of its splay tree.
fn splay(t : TopTree, x : Int) -> Unit {
  // Push down all ancestors first.
  push_down_path(t, x)
  while !is_root(t, x) {
    let p = t.parent[x]
    if !is_root(t, p) {
      let g = t.parent[p]
      // Zig-zig or zig-zag.
      let p_is_left = t.left[g] == p
      let x_is_left = t.left[p] == x
      if p_is_left == x_is_left {
        // Zig-zig: rotate p first.
        rotate(t, p)
      } else {
        // Zig-zag: rotate x first.
        rotate(t, x)
      }
    }
    rotate(t, x)
  }
}

///|
/// Push down all ancestors of x (from root to x).
fn push_down_path(t : TopTree, x : Int) -> Unit {
  // Collect path to root.
  let path : Array[Int] = []
  let mut cur = x
  while cur != nil_node {
    path.push(cur)
    if is_root(t, cur) {
      break
    }
    cur = t.parent[cur]
  }
  // Push down from root to x.
  let mut i = path.length() - 1
  while i >= 0 {
    push_down(t, path[i])
    i = i - 1
  }
}

// ---------------------------------------------------------------------------
// Access — the core operation
// ---------------------------------------------------------------------------

///|
/// Add node `child` as a virtual child of `x`.
///
/// Records the child's total contribution (all_sum, all_size) at the time
/// of addition, so that remove_virtual can correctly undo it even if the
/// child's splay tree was restructured in between.
fn add_virtual(t : TopTree, x : Int, child : Int) -> Unit {
  let s = all_sum(t, child)
  let sz = all_size(t, child)
  t.vir_saved_sum[child] = s
  t.vir_saved_size[child] = sz
  t.vir_sum[x] = t.vir_sum[x] + s
  t.vir_size[x] = t.vir_size[x] + sz
  let cmn = all_min(t, child)
  let cmx = all_max(t, child)
  if cmn < t.vir_min[x] {
    t.vir_min[x] = cmn
  }
  if cmx > t.vir_max[x] {
    t.vir_max[x] = cmx
  }
}

///|
/// Remove node `child` from virtual children of `x`.
///
/// Uses the saved contribution from when child was added, NOT the current
/// all_sum(child), because the child's splay tree may have been restructured
/// (e.g., by accessing a node in its subtree) between add and remove.
fn remove_virtual(t : TopTree, x : Int, child : Int) -> Unit {
  t.vir_sum[x] = t.vir_sum[x] - t.vir_saved_sum[child]
  t.vir_size[x] = t.vir_size[x] - t.vir_saved_size[child]
  // vir_min/vir_max cannot be precisely updated on removal.
  // Reset to identity when no virtual children remain.
  if t.vir_size[x] == 0 {
    t.vir_min[x] = inf_max
    t.vir_max[x] = inf_min
  }
}

///|
/// Make the path from root of x's tree to x a single preferred path.
fn access(t : TopTree, x : Int) -> Unit {
  splay(t, x)
  // Detach right subtree (preferred child below x becomes virtual).
  let r = t.right[x]
  if r != nil_node {
    add_virtual(t, x, r)
    t.parent[r] = x // path-parent
    t.right[x] = nil_node
    push_up(t, x)
  }
  // Walk up path-parents, splaying and updating.
  let mut cur = x
  while t.parent[cur] != nil_node {
    let p = t.parent[cur]
    splay(t, p)
    // Detach p's old preferred child.
    let old_r = t.right[p]
    if old_r != nil_node {
      add_virtual(t, p, old_r)
      t.parent[old_r] = p // path-parent
      t.right[p] = nil_node
    }
    // Remove cur from p's virtual children (it's now preferred).
    remove_virtual(t, p, cur)
    // Attach cur as p's preferred child.
    t.right[p] = cur
    t.parent[cur] = p
    push_up(t, p)
    cur = p
  }
  splay(t, x)
}

///|
/// Make x the root of its represented tree (reverse the path from root to x).
///
/// This is needed before `subtree_sum` queries to ensure the correct rooting.
/// `path_sum`, `path_min`, and `path_max` internally call `make_root`, which
/// changes the root. Call `make_root` to restore or set the desired root
/// before subtree queries.
pub fn make_root(t : TopTree, x : Int) -> Unit {
  access(t, x)
  t.rev[x] = !t.rev[x]
  push_down(t, x)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Check if vertices u and v are in the same tree.
pub fn connected(t : TopTree, u : Int, v : Int) -> Bool {
  if u == v {
    return true
  }
  if u < 0 || u >= t.n || v < 0 || v >= t.n {
    return false
  }
  find_root(t, u) == find_root(t, v)
}

///|
/// Find the root of the tree containing x.
fn find_root(t : TopTree, x : Int) -> Int {
  access(t, x)
  let mut cur = x
  push_down(t, cur)
  while t.left[cur] != nil_node {
    cur = t.left[cur]
    push_down(t, cur)
  }
  splay(t, cur)
  cur
}

///|
/// Add an edge between u and v (must be in different trees).
///
/// After link, v becomes the parent of u (u's tree is attached under v).
pub fn link(t : TopTree, u : Int, v : Int) -> Unit {
  if u < 0 || u >= t.n || v < 0 || v >= t.n || u == v {
    return
  }
  make_root(t, u)
  if find_root(t, u) == find_root(t, v) {
    return
  }
  // u is root of its tree. Make v its parent.
  // u becomes a virtual child of v.
  access(t, v)
  add_virtual(t, v, u)
  t.parent[u] = v // path-parent
  push_up(t, v)
}

///|
/// Remove the edge between u and v.
pub fn cut(t : TopTree, u : Int, v : Int) -> Unit {
  if u < 0 || u >= t.n || v < 0 || v >= t.n || u == v {
    return
  }
  make_root(t, u)
  access(t, v)
  // Now v's left child should be u (if edge exists).
  if t.left[v] == u && t.right[u] == nil_node {
    t.left[v] = nil_node
    t.parent[u] = nil_node
    push_up(t, v)
  }
}

///|
/// Get the value of vertex u.
pub fn vertex_value(t : TopTree, u : Int) -> Int {
  if u < 0 || u >= t.n {
    return 0
  }
  access(t, u)
  t.val[u]
}

///|
/// Set the value of vertex u to `new_val`.
pub fn set_value(t : TopTree, u : Int, new_val : Int) -> Unit {
  if u < 0 || u >= t.n {
    return
  }
  access(t, u)
  t.val[u] = new_val
  push_up(t, u)
}

///|
/// Compute the sum of values on the path from u to v.
pub fn path_sum(t : TopTree, u : Int, v : Int) -> Int {
  if u < 0 || u >= t.n || v < 0 || v >= t.n {
    return 0
  }
  make_root(t, u)
  access(t, v)
  t.path_sum[v]
}

///|
/// Compute the minimum value on the path from u to v.
pub fn path_min(t : TopTree, u : Int, v : Int) -> Int {
  if u < 0 || u >= t.n || v < 0 || v >= t.n {
    return inf_max
  }
  make_root(t, u)
  access(t, v)
  t.path_min[v]
}

///|
/// Compute the maximum value on the path from u to v.
pub fn path_max(t : TopTree, u : Int, v : Int) -> Int {
  if u < 0 || u >= t.n || v < 0 || v >= t.n {
    return inf_min
  }
  make_root(t, u)
  access(t, v)
  t.path_max[v]
}

///|
/// Compute the sum of values in the subtree rooted at u.
///
/// After `access(u)`, u is the deepest node on the preferred path from the
/// root to u. u's right child is nil, and u's left child represents ancestors
/// (NOT in u's subtree). u's virtual children represent u's children in the
/// represented tree. Therefore:
///
/// `subtree_sum(u) = val[u] + vir_sum[u]`
///
/// This does NOT call `make_root(u)`, so the root of the represented tree
/// is preserved for subsequent operations. Calling `make_root(u)` would
/// make u the root, causing u's "subtree" to become the entire tree.
pub fn subtree_sum(t : TopTree, u : Int) -> Int {
  if u < 0 || u >= t.n {
    return 0
  }
  access(t, u)
  t.val[u] + t.vir_sum[u]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "TopTree: basic link and connected" {
  let t = TopTree::new(5)
  assert_false(connected(t, 0, 1))
  link(t, 0, 1)
  assert_true(connected(t, 0, 1))
  assert_false(connected(t, 0, 2))
  link(t, 1, 2)
  assert_true(connected(t, 0, 2))
  assert_true(connected(t, 1, 2))
}

///|
test "TopTree: cut disconnects" {
  let t = TopTree::new(5)
  link(t, 0, 1)
  link(t, 1, 2)
  link(t, 2, 3)
  assert_true(connected(t, 0, 3))
  cut(t, 1, 2)
  assert_false(connected(t, 0, 3))
  assert_true(connected(t, 0, 1))
  assert_true(connected(t, 2, 3))
}

///|
test "TopTree: path sum" {
  let t = TopTree::with_values(5, [1, 2, 3, 4, 5])
  // Tree: 0-1-2-3-4 (chain)
  link(t, 0, 1)
  link(t, 1, 2)
  link(t, 2, 3)
  link(t, 3, 4)
  // Path 0→4: 1+2+3+4+5 = 15
  assert_eq(path_sum(t, 0, 4), 15)
  // Path 1→3: 2+3+4 = 9
  assert_eq(path_sum(t, 1, 3), 9)
  // Path 0→0: 1
  assert_eq(path_sum(t, 0, 0), 1)
}

///|
test "TopTree: path min and max" {
  let t = TopTree::with_values(6, [5, 3, 8, 1, 9, 2])
  // Tree: 0-1-2-3-4-5 (chain)
  link(t, 0, 1)
  link(t, 1, 2)
  link(t, 2, 3)
  link(t, 3, 4)
  link(t, 4, 5)
  // Path 0→5: values 5,3,8,1,9,2 → min=1, max=9
  assert_eq(path_min(t, 0, 5), 1)
  assert_eq(path_max(t, 0, 5), 9)
  // Path 1→3: values 3,8,1 → min=1, max=8
  assert_eq(path_min(t, 1, 3), 1)
  assert_eq(path_max(t, 1, 3), 8)
}

///|
test "TopTree: set value updates path" {
  let t = TopTree::with_values(4, [1, 2, 3, 4])
  link(t, 0, 1)
  link(t, 1, 2)
  link(t, 2, 3)
  assert_eq(path_sum(t, 0, 3), 10)
  set_value(t, 2, 10)
  assert_eq(path_sum(t, 0, 3), 17)
  assert_eq(vertex_value(t, 2), 10)
}

///|
test "TopTree: subtree sum" {
  let t = TopTree::with_values(7, [1, 2, 3, 4, 5, 6, 7])
  // Tree:
  //       0
  //      /|\
  //     1 2 3
  //    /|   |
  //   4 5   6
  link(t, 1, 0)
  link(t, 2, 0)
  link(t, 3, 0)
  link(t, 4, 1)
  link(t, 5, 1)
  link(t, 6, 3)
  // Subtree of 0: all nodes = 1+2+3+4+5+6+7 = 28
  assert_eq(subtree_sum(t, 0), 28)
  // Subtree of 1: nodes 1,4,5 = 2+5+6 = 13
  assert_eq(subtree_sum(t, 1), 13)
  // Subtree of 3: nodes 3,6 = 4+7 = 11
  assert_eq(subtree_sum(t, 3), 11)
}

///|
test "TopTree: subtree sum after cut" {
  let t = TopTree::with_values(6, [1, 2, 3, 4, 5, 6])
  // Tree: 0-1-2, 0-3-4, 3-5
  link(t, 1, 0)
  link(t, 2, 0)
  link(t, 3, 0)
  link(t, 4, 3)
  link(t, 5, 3)
  // Subtree of 0: all = 1+2+3+4+5+6 = 21
  assert_eq(subtree_sum(t, 0), 21)
  // Cut 0-3: subtree of 0 becomes 0,1,2 = 1+2+3 = 6
  cut(t, 0, 3)
  assert_eq(subtree_sum(t, 0), 6)
  // Subtree of 3: 3,4,5 = 4+5+6 = 15
  assert_eq(subtree_sum(t, 3), 15)
}

///|
test "TopTree: star graph" {
  let t = TopTree::with_values(5, [10, 20, 30, 40, 50])
  // Star: center=0, leaves=1,2,3,4
  link(t, 1, 0)
  link(t, 2, 0)
  link(t, 3, 0)
  link(t, 4, 0)
  // Path 1→2: 20+10+30 = 60
  assert_eq(path_sum(t, 1, 2), 60)
  // Path 3→4: 40+10+50 = 100
  assert_eq(path_sum(t, 3, 4), 100)
  // Restore root to 0 for subtree queries (path_sum changes the root).
  make_root(t, 0)
  // Subtree of 0: all = 10+20+30+40+50 = 150
  assert_eq(subtree_sum(t, 0), 150)
  // Subtree of 1: just 1 = 20
  assert_eq(subtree_sum(t, 1), 20)
}

///|
test "TopTree: link creates tree" {
  let t = TopTree::with_values(4, [1, 2, 3, 4])
  link(t, 0, 1)
  link(t, 2, 3)
  assert_true(connected(t, 0, 1))
  assert_true(connected(t, 2, 3))
  assert_false(connected(t, 0, 2))
  // Link the two trees.
  link(t, 1, 2)
  assert_true(connected(t, 0, 3))
  assert_eq(path_sum(t, 0, 3), 10)
}

///|
test "TopTree: cut and relink" {
  let t = TopTree::with_values(4, [1, 2, 3, 4])
  link(t, 0, 1)
  link(t, 1, 2)
  link(t, 2, 3)
  cut(t, 1, 2)
  assert_false(connected(t, 0, 3))
  assert_eq(path_sum(t, 0, 1), 3)
  assert_eq(path_sum(t, 2, 3), 7)
  // Relink differently.
  link(t, 0, 3)
  assert_true(connected(t, 1, 2))
  // Path 1→2 goes through 0 and 3: 2+1+4+3 = 10
  assert_eq(path_sum(t, 1, 2), 10)
}

///|
test "TopTree: single vertex" {
  let t = TopTree::with_values(1, [42])
  assert_eq(path_sum(t, 0, 0), 42)
  assert_eq(path_min(t, 0, 0), 42)
  assert_eq(path_max(t, 0, 0), 42)
  assert_eq(subtree_sum(t, 0), 42)
  assert_eq(vertex_value(t, 0), 42)
}

///|
test "TopTree: update then query" {
  let t = TopTree::with_values(5, [10, 20, 30, 40, 50])
  link(t, 0, 1)
  link(t, 1, 2)
  link(t, 2, 3)
  link(t, 3, 4)
  // Original path sum: 10+20+30+40+50 = 150
  assert_eq(path_sum(t, 0, 4), 150)
  set_value(t, 2, 100)
  // New path sum: 10+20+100+40+50 = 220
  assert_eq(path_sum(t, 0, 4), 220)
  assert_eq(path_max(t, 0, 4), 100)
  assert_eq(path_min(t, 0, 4), 10)
}

///|
test "TopTree: binary tree structure" {
  let t = TopTree::with_values(7, [1, 2, 3, 4, 5, 6, 7])
  // Binary tree:
  //        0
  //       / \
  //      1   2
  //     / \ / \
  //    3  4 5  6
  link(t, 1, 0)
  link(t, 2, 0)
  link(t, 3, 1)
  link(t, 4, 1)
  link(t, 5, 2)
  link(t, 6, 2)
  // Subtree of 0: all = 28
  assert_eq(subtree_sum(t, 0), 28)
  // Subtree of 1: 1,3,4 → 2+4+5 = 11
  assert_eq(subtree_sum(t, 1), 11)
  // Subtree of 2: 2,5,6 → 3+6+7 = 16
  assert_eq(subtree_sum(t, 2), 16)
  // Path 3→6: 4+2+1+3+7 = 17
  assert_eq(path_sum(t, 3, 6), 17)
  // Path 3→4: 4+2+5 = 11
  assert_eq(path_sum(t, 3, 4), 11)
}

///|
test "TopTree: large chain stress" {
  let n = 200
  let values = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    values[i] = i + 1
  }
  let t = TopTree::with_values(n, values)
  // Build chain 0-1-2-...-199
  for i = 0; i < n - 1; i = i + 1 {
    link(t, i, i + 1)
  }
  // Path sum 0→199: sum(1..200) = 20100
  let expected = n * (n + 1) / 2
  assert_eq(path_sum(t, 0, n - 1), expected)
  // Path min: 1, Path max: 200
  assert_eq(path_min(t, 0, n - 1), 1)
  assert_eq(path_max(t, 0, n - 1), n)
  // Subtree of vertex 100: depends on which is root.
  // After make_root(0), subtree of 0 = entire tree.
  assert_eq(subtree_sum(t, 0), expected)
  // Cut edge 99-100.
  cut(t, 99, 100)
  assert_false(connected(t, 0, 100))
  // Path sum 0→99: sum(1..100) = 5050
  assert_eq(path_sum(t, 0, 99), 5050)
  // Path sum 100→199: sum(101..200) = 15050
  assert_eq(path_sum(t, 100, 199), 15050)
}

///|
test "TopTree: self-loop prevention" {
  let t = TopTree::new(3)
  link(t, 0, 0) // Should be ignored
  assert_true(connected(t, 0, 0))
}

///|
test "TopTree: cut nonexistent edge" {
  let t = TopTree::with_values(4, [1, 2, 3, 4])
  link(t, 0, 1)
  link(t, 2, 3)
  cut(t, 0, 3) // No edge exists
  assert_true(connected(t, 0, 1))
  assert_true(connected(t, 2, 3))
}

///|
test "TopTree: path query on branch" {
  let t = TopTree::with_values(6, [1, 2, 3, 4, 5, 6])
  // Tree:
  //     0
  //    / \
  //   1   2
  //  / \   \
  // 3   4   5
  link(t, 1, 0)
  link(t, 2, 0)
  link(t, 3, 1)
  link(t, 4, 1)
  link(t, 5, 2)
  // Path 3→5: 4+2+1+3+6 = 16
  assert_eq(path_sum(t, 3, 5), 16)
  // Path 3→4: 4+2+5 = 11
  assert_eq(path_sum(t, 3, 4), 11)
  // Path 0→5: 1+3+6 = 10
  assert_eq(path_sum(t, 0, 5), 10)
}

///|
test "TopTree: default values zero" {
  let t = TopTree::new(4)
  link(t, 0, 1)
  link(t, 1, 2)
  assert_eq(path_sum(t, 0, 2), 0)
  assert_eq(vertex_value(t, 1), 0)
  set_value(t, 1, 5)
  assert_eq(path_sum(t, 0, 2), 5)
}
