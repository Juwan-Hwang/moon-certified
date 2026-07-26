/// Link-Cut Tree (dynamic tree) data structure.
///
/// Maintains a forest of rooted trees supporting:
/// - `link(u, v)`: add an edge between u and v (in different trees)
/// - `cut(u, v)`: remove the edge between u and v
/// - `find_root(u)`: find the root of the tree containing u
/// - `connected(u, v)`: check if u and v are in the same tree
/// - `lca(u, v)`: lowest common ancestor
/// - Path aggregate queries (sum) on tree paths
/// - Point updates (set node value)
///
/// ## Algorithm
///
/// Uses the Sleator-Tarjan splay-tree representation. Each tree in the forest
/// is decomposed into "preferred paths" (chains). Each chain is stored in a
/// splay tree (auxiliary tree), ordered by depth in the represented tree.
///
/// The key operation is `access(v)`, which makes the path from the root of
/// v's tree to v a single preferred path. All other operations are built on
/// top of access.
///
/// ## Complexity
///
/// - Amortized O(log n) per operation.
/// - Space: O(n).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

///|
/// The Link-Cut Tree state.
pub struct LCT {
  n : Int
  left : Array[Int] // left child in splay tree (-1 if none)
  right : Array[Int] // right child in splay tree (-1 if none)
  parent : Array[Int] // splay-tree parent or path-parent (-1 if none)
  rev : Array[Bool] // lazy reversal flag
  val : Array[Int] // node value
  sum : Array[Int] // subtree sum in splay tree (including this node)
}

///|
/// Create a new LCT with `n` nodes, each with value 0.
pub fn new(n : Int) -> LCT {
  {
    n,
    left: Array::make(n, -1),
    right: Array::make(n, -1),
    parent: Array::make(n, -1),
    rev: Array::make(n, false),
    val: Array::make(n, 0),
    sum: Array::make(n, 0),
  }
}

///|
/// Set the value of node `x`.
///
/// Can be called at any time (before or after link operations).
pub fn set_value(lct : LCT, x : Int, v : Int) -> Unit {
  splay(lct, x)
  lct.val[x] = v
  push_up(lct, x)
}

///|
/// Get the value of node `x`.
pub fn get_value(lct : LCT, x : Int) -> Int {
  lct.val[x]
}

// ---------------------------------------------------------------------------
// Splay tree helpers
// ---------------------------------------------------------------------------

///|
/// Check if `x` is the root of its splay tree.
///
/// A node is the splay-tree root if it has no parent, or if its parent
/// does not consider it a child (path-parent link rather than splay edge).
fn is_root(lct : LCT, x : Int) -> Bool {
  let p = lct.parent[x]
  p == -1 || (lct.left[p] != x && lct.right[p] != x)
}

///|
/// Push up: update sum from children.
fn push_up(lct : LCT, x : Int) -> Unit {
  lct.sum[x] = lct.val[x]
  if lct.left[x] != -1 {
    lct.sum[x] = lct.sum[x] + lct.sum[lct.left[x]]
  }
  if lct.right[x] != -1 {
    lct.sum[x] = lct.sum[x] + lct.sum[lct.right[x]]
  }
}

///|
/// Push down: propagate lazy reversal flag.
fn push_down(lct : LCT, x : Int) -> Unit {
  if lct.rev[x] {
    // Swap left and right children.
    let tmp = lct.left[x]
    lct.left[x] = lct.right[x]
    lct.right[x] = tmp
    // Propagate reversal to children.
    if lct.left[x] != -1 {
      lct.rev[lct.left[x]] = !lct.rev[lct.left[x]]
    }
    if lct.right[x] != -1 {
      lct.rev[lct.right[x]] = !lct.rev[lct.right[x]]
    }
    lct.rev[x] = false
  }
}

///|
/// Rotate node `x` up in its splay tree.
fn rotate(lct : LCT, x : Int) -> Unit {
  let p = lct.parent[x]
  let g = lct.parent[p]
  if lct.left[p] == x {
    // x is left child: right rotation.
    lct.left[p] = lct.right[x]
    if lct.right[x] != -1 {
      lct.parent[lct.right[x]] = p
    }
    lct.right[x] = p
  } else {
    // x is right child: left rotation.
    lct.right[p] = lct.left[x]
    if lct.left[x] != -1 {
      lct.parent[lct.left[x]] = p
    }
    lct.left[x] = p
  }
  lct.parent[p] = x
  lct.parent[x] = g
  // Update grandparent's child pointer if p was a splay child of g.
  if g != -1 {
    if lct.left[g] == p {
      lct.left[g] = x
    } else if lct.right[g] == p {
      lct.right[g] = x
    }
    // If p was not a child of g (path-parent), leave g unchanged.
  }
  push_up(lct, p)
  push_up(lct, x)
}

///|
/// Splay node `x` to the root of its splay tree.
fn splay(lct : LCT, x : Int) -> Unit {
  // Collect path from x to root of splay tree for push_down.
  let path : Array[Int] = []
  let mut y = x
  while true {
    path.push(y)
    if is_root(lct, y) {
      break
    }
    y = lct.parent[y]
  }
  // Push down in reverse order (root first).
  let len = path.length()
  for i = len - 1; i >= 0; i = i - 1 {
    push_down(lct, path[i])
  }
  // Splay: rotate x up until it is the root.
  while !is_root(lct, x) {
    let p = lct.parent[x]
    if !is_root(lct, p) {
      let g = lct.parent[p]
      // Zig-zig: both same direction → rotate parent first.
      // Zig-zag: different directions → rotate x first.
      if (lct.left[g] == p) == (lct.left[p] == x) {
        rotate(lct, p)
      } else {
        rotate(lct, x)
      }
    }
    rotate(lct, x)
  }
}

// ---------------------------------------------------------------------------
// Core operations
// ---------------------------------------------------------------------------

///|
/// Access: make the path from the root of x's tree to x a preferred path.
/// Returns the last node visited (used for LCA computation).
fn access(lct : LCT, x : Int) -> Int {
  splay(lct, x)
  // Disconnect right child (break the chain below x).
  lct.right[x] = -1
  push_up(lct, x)
  let mut last = x
  let mut cur = x
  while lct.parent[cur] != -1 {
    let p = lct.parent[cur]
    splay(lct, p)
    // Attach cur as right child of p (extend p's chain to include cur).
    lct.right[p] = cur
    push_up(lct, p)
    last = p
    cur = p
  }
  // Splay the original node to the root for convenience.
  splay(lct, x)
  last
}

///|
/// Make `x` the root of its represented tree.
pub fn make_root(lct : LCT, x : Int) -> Unit {
  let _ = access(lct, x)
  splay(lct, x)
  // Reverse the entire path: makes x the root of the represented tree.
  lct.rev[x] = !lct.rev[x]
}

///|
/// Find the root of the tree containing `x`.
pub fn find_root(lct : LCT, x : Int) -> Int {
  let _ = access(lct, x)
  splay(lct, x)
  // The root is the leftmost node in the splay tree.
  let mut cur = x
  push_down(lct, cur)
  while lct.left[cur] != -1 {
    cur = lct.left[cur]
    push_down(lct, cur)
  }
  splay(lct, cur)
  cur
}

///|
/// Check if `u` and `v` are in the same tree.
pub fn connected(lct : LCT, u : Int, v : Int) -> Bool {
  if u == v {
    return true
  }
  find_root(lct, u) == find_root(lct, v)
}

///|
/// Add an edge between `u` and `v` (they must be in different trees).
///
/// After linking, `u` becomes a child of `v` in the represented tree.
pub fn link(lct : LCT, u : Int, v : Int) -> Unit {
  make_root(lct, u)
  // Only link if they are not already connected.
  if find_root(lct, v) != u {
    lct.parent[u] = v
  }
}

///|
/// Remove the edge between `u` and `v` (it must exist).
///
/// If the edge does not exist, this is a no-op.
pub fn cut(lct : LCT, u : Int, v : Int) -> Unit {
  make_root(lct, u)
  let _ = access(lct, v)
  splay(lct, v)
  // After make_root(u) and access(v), if edge u-v exists:
  // u is the left child of v, and u has no right child (no nodes between them).
  if lct.left[v] == u && lct.right[u] == -1 {
    lct.left[v] = -1
    lct.parent[u] = -1
    push_up(lct, v)
  }
}

///|
/// Query the sum of values on the path from `u` to `v`.
pub fn query_path_sum(lct : LCT, u : Int, v : Int) -> Int {
  make_root(lct, u)
  let _ = access(lct, v)
  splay(lct, v)
  lct.sum[v]
}

///|
/// Find the lowest common ancestor of `u` and `v`.
///
/// Returns -1 if they are not in the same tree.
pub fn lca(lct : LCT, u : Int, v : Int) -> Int {
  if !connected(lct, u, v) {
    return -1
  }
  let _ = access(lct, u)
  access(lct, v)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "lct: basic link and connected" {
  let lct = new(5)
  assert_false(connected(lct, 0, 1))
  link(lct, 0, 1)
  assert_true(connected(lct, 0, 1))
  assert_false(connected(lct, 0, 2))
  link(lct, 1, 2)
  assert_true(connected(lct, 0, 2))
  assert_false(connected(lct, 0, 3))
  link(lct, 2, 3)
  link(lct, 3, 4)
  assert_true(connected(lct, 0, 4))
}

///|
test "lct: cut" {
  let lct = new(5)
  link(lct, 0, 1)
  link(lct, 1, 2)
  link(lct, 2, 3)
  assert_true(connected(lct, 0, 3))
  cut(lct, 1, 2)
  assert_true(connected(lct, 0, 1))
  assert_true(connected(lct, 2, 3))
  assert_false(connected(lct, 0, 3))
}

///|
test "lct: cut non-existent edge" {
  let lct = new(4)
  link(lct, 0, 1)
  link(lct, 2, 3)
  // Cut non-existent edge 0-3: should be a no-op.
  cut(lct, 0, 3)
  assert_true(connected(lct, 0, 1))
  assert_true(connected(lct, 2, 3))
  assert_false(connected(lct, 0, 3))
}

///|
test "lct: path sum" {
  let lct = new(5)
  set_value(lct, 0, 10)
  set_value(lct, 1, 20)
  set_value(lct, 2, 30)
  set_value(lct, 3, 40)
  set_value(lct, 4, 50)
  link(lct, 0, 1)
  link(lct, 1, 2)
  link(lct, 2, 3)
  link(lct, 3, 4)
  // Tree: 4 -> 3 -> 2 -> 1 -> 0
  // Path 0-4: sum = 10+20+30+40+50 = 150
  assert_eq(query_path_sum(lct, 0, 4), 150)
  // Path 1-3: sum = 20+30+40 = 90
  assert_eq(query_path_sum(lct, 1, 3), 90)
}

///|
test "lct: update value" {
  let lct = new(3)
  set_value(lct, 0, 1)
  set_value(lct, 1, 2)
  set_value(lct, 2, 3)
  link(lct, 0, 1)
  link(lct, 1, 2)
  assert_eq(query_path_sum(lct, 0, 2), 6)
  set_value(lct, 1, 10)
  assert_eq(query_path_sum(lct, 0, 2), 14)
}

///|
test "lct: find root" {
  let lct = new(5)
  link(lct, 0, 1)
  link(lct, 1, 2)
  link(lct, 2, 3)
  link(lct, 3, 4)
  // After linking, all nodes are in one tree.
  // find_root should return the same node for all nodes.
  let r0 = find_root(lct, 0)
  let r1 = find_root(lct, 1)
  let r4 = find_root(lct, 4)
  assert_eq(r0, r1)
  assert_eq(r0, r4)
}

///|
test "lct: lca" {
  let lct = new(5)
  // Build tree:
  //       0
  //      / \
  //     1   2
  //    / \
  //   3   4
  link(lct, 1, 0) // 1 is child of 0
  link(lct, 2, 0) // 2 is child of 0
  link(lct, 3, 1) // 3 is child of 1
  link(lct, 4, 1) // 4 is child of 1
  assert_eq(lca(lct, 3, 4), 1)
  assert_eq(lca(lct, 3, 2), 0)
  assert_eq(lca(lct, 3, 0), 0)
  assert_eq(lca(lct, 3, 3), 3)
}

///|
test "lct: complex" {
  let lct = new(6)
  set_value(lct, 0, 1)
  set_value(lct, 1, 2)
  set_value(lct, 2, 3)
  set_value(lct, 3, 4)
  set_value(lct, 4, 5)
  set_value(lct, 5, 6)
  // Build a chain: 0-1-2-3-4-5
  link(lct, 0, 1)
  link(lct, 1, 2)
  link(lct, 2, 3)
  link(lct, 3, 4)
  link(lct, 4, 5)
  assert_eq(query_path_sum(lct, 0, 5), 21)
  // Cut the tree: remove edge 2-3
  cut(lct, 2, 3)
  assert_eq(query_path_sum(lct, 0, 2), 6)
  assert_eq(query_path_sum(lct, 3, 5), 15)
  assert_false(connected(lct, 0, 3))
  // Re-link: connect 2 and 3 again
  link(lct, 2, 3)
  assert_true(connected(lct, 0, 5))
  assert_eq(query_path_sum(lct, 0, 5), 21)
}

///|
test "lct: star graph" {
  let lct = new(5)
  set_value(lct, 0, 100)
  set_value(lct, 1, 10)
  set_value(lct, 2, 20)
  set_value(lct, 3, 30)
  set_value(lct, 4, 40)
  // Star: center 0, leaves 1,2,3,4
  link(lct, 1, 0) // 1 is child of 0
  link(lct, 2, 0) // 2 is child of 0
  link(lct, 3, 0) // 3 is child of 0
  link(lct, 4, 0) // 4 is child of 0
  // Path 1-0-2: sum = 10+100+20 = 130
  assert_eq(query_path_sum(lct, 1, 2), 130)
  // Path 3-0-4: sum = 30+100+40 = 170
  assert_eq(query_path_sum(lct, 3, 4), 170)
  // LCA(1, 2) = 0
  assert_eq(lca(lct, 1, 2), 0)
  // LCA(1, 4) = 0
  assert_eq(lca(lct, 1, 4), 0)
}

///|
test "lct: single node" {
  let lct = new(1)
  set_value(lct, 0, 42)
  assert_eq(query_path_sum(lct, 0, 0), 42)
  assert_eq(find_root(lct, 0), 0)
  assert_eq(lca(lct, 0, 0), 0)
}

///|
test "lct: two nodes" {
  let lct = new(2)
  set_value(lct, 0, 5)
  set_value(lct, 1, 7)
  link(lct, 0, 1)
  assert_true(connected(lct, 0, 1))
  assert_eq(query_path_sum(lct, 0, 1), 12)
  cut(lct, 0, 1)
  assert_false(connected(lct, 0, 1))
}

///|
test "lct: relink after cut" {
  let lct = new(4)
  set_value(lct, 0, 1)
  set_value(lct, 1, 2)
  set_value(lct, 2, 3)
  set_value(lct, 3, 4)
  // Chain: 0-1-2-3
  link(lct, 0, 1)
  link(lct, 1, 2)
  link(lct, 2, 3)
  assert_eq(query_path_sum(lct, 0, 3), 10)
  // Cut middle edge
  cut(lct, 1, 2)
  assert_eq(query_path_sum(lct, 0, 1), 3)
  assert_eq(query_path_sum(lct, 2, 3), 7)
  // Relink in different configuration: 1-2
  link(lct, 1, 2)
  assert_eq(query_path_sum(lct, 0, 3), 10)
  // Cut and relink as 0-2, 1-3
  cut(lct, 0, 1)
  cut(lct, 2, 3)
  link(lct, 0, 2)
  link(lct, 1, 3)
  assert_true(connected(lct, 0, 3))
  assert_eq(query_path_sum(lct, 0, 3), 10)
}
