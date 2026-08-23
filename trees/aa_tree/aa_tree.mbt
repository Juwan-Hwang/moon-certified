/// AA Tree — a simplified balanced BST using levels instead of colors.
///
/// An **AA tree** (Arne Andersson tree) is a self-balancing binary search
/// tree that is a simplified variant of the red-black tree. Instead of
/// storing a color (red/black) per node, AA trees store a **level** — a
/// small integer. The balancing invariants ensure O(log n) height using
/// only two operations: **skew** and **split**.
///
/// ## AA Tree Invariants
///
/// 1. The level of a leaf is 1.
/// 2. The level of a left child is exactly one less than its parent's.
/// 3. The level of a right child is equal to or one less than its parent's.
/// 4. The level of a right grandchild is strictly less than its grandparent's.
/// 5. Every node of level > 1 has two children.
///
/// These invariants imply that all horizontal links (links between nodes of
/// the same level) go to the **right**. This is the key simplification over
/// red-black trees.
///
/// ## Operations
///
/// - **Skew**: Right rotation when a node has a left child at the same level
///   (horizontal left link). Restores the "all horizontal links go right"
///   property.
/// - **Split**: Left rotation when a node has two consecutive right children
///   at the same level. Increases the level of the middle node.
///
/// Both operations are applied bottom-up after insertions and deletions.
///
/// ## Complexity
///
/// | Operation  | Time     |
/// |------------|----------|
/// | `insert`   | O(log n) |
/// | `remove`   | O(log n) |
/// | `search`   | O(log n) |
/// | `find_min` | O(log n) |
/// | `find_max` | O(log n) |
///
/// ## Advantages over Red-Black Trees
///
/// - ~30% fewer lines of code (only skew + split vs. 4+ rotation cases).
/// - No color flip logic; level increment/decrement is straightforward.
/// - Same asymptotic performance.
///
/// ## References
///
/// - Andersson, A. (1993). "Balanced search trees made simple."
///   *Workshop on Algorithms and Data Structures (WADS)*, LNCS 709, 60–71.
/// - Sedgewick, R. & Wayne, K. (2011). *Algorithms*, 4th ed., §3.3.
///   Addison-Wesley.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Node type
// ---------------------------------------------------------------------------

///|
/// An AA tree node.
///
/// `level` is the only balancing information stored (analogous to color in
/// red-black trees, but more expressive). Leaf nodes have level 1.
priv struct AaNode[T] {
  mut val : T
  mut level : Int
  mut left : AaNode[T]?
  mut right : AaNode[T]?
}

// ---------------------------------------------------------------------------
// Tree type
// ---------------------------------------------------------------------------

///|
/// An AA tree with a user-supplied comparator.
///
/// `compare(a, b)` returns `< 0` when `a < b`, `0` when equal, `> 0` when
/// `a > b`.
pub struct AaTree[T] {
  priv mut root : AaNode[T]?
  priv compare : (T, T) -> Int
  priv mut count : Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create an empty AA tree with the given comparator.
pub fn[T] AaTree::new(compare : (T, T) -> Int) -> AaTree[T] {
  { root: None, compare, count: 0 }
}

// ---------------------------------------------------------------------------
// Basic queries
// ---------------------------------------------------------------------------

///|
/// Returns the number of elements. O(1).
pub fn[T] AaTree::size(self : AaTree[T]) -> Int {
  self.count
}

///|
/// Returns `true` if the tree is empty. O(1).
pub fn[T] AaTree::is_empty(self : AaTree[T]) -> Bool {
  self.count == 0
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

///|
/// Search for a key. O(log n).
pub fn[T] AaTree::contains(self : AaTree[T], key : T) -> Bool {
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
/// Find the minimum key. O(log n).
pub fn[T] AaTree::find_min(self : AaTree[T]) -> T? {
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
/// Find the maximum key. O(log n).
pub fn[T] AaTree::find_max(self : AaTree[T]) -> T? {
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
// Skew and Split — the two rebalancing primitives
// ---------------------------------------------------------------------------

///|
/// Skew: right rotation to eliminate a horizontal left link.
///
/// If `node.left.level == node.level`, rotate right: the left child becomes
/// the new root, and the original node becomes its right child.
///
/// ```
///     T              L
///    / \     →      / \
///   L   C          A   T
///  / \                / \
/// A   B              B   C
/// ```
fn[T] skew(node : AaNode[T]) -> AaNode[T] {
  match node.left {
    Some(l) =>
      if l.level == node.level {
        // Right rotation
        node.left = l.right
        l.right = Some(node)
        l
      } else {
        node
      }
    None => node
  }
}

///|
/// Split: left rotation to fix two consecutive horizontal right links.
///
/// If `node.right.right.level == node.level`, rotate left and increase the
/// level of the middle node.
///
/// ```
///   T                  R
///  / \                / \
/// A   R      →       T   X
///    / \            / \
///   B   X          A   B
/// ```
fn[T] split(node : AaNode[T]) -> AaNode[T] {
  match node.right {
    Some(r) =>
      match r.right {
        Some(rr) =>
          if rr.level == node.level {
            // Left rotation: r becomes new root, node becomes r's left child.
            node.right = r.left
            r.left = Some(node)
            r.level = r.level + 1
            r
          } else {
            node
          }
        None => node
      }
    None => node
  }
}

// ---------------------------------------------------------------------------
// Insertion
// ---------------------------------------------------------------------------

///|
/// Insert a key. O(log n).
///
/// Returns `true` if inserted, `false` if the key already exists.
pub fn[T] AaTree::insert(self : AaTree[T], key : T) -> Bool {
  let inserted : Ref[Bool] = Ref(false)
  self.root = Some(insert_rec(self.root, key, self.compare, inserted))
  if inserted.val {
    self.count = self.count + 1
  }
  inserted.val
}

///|
/// Recursive insert with bottom-up skew and split.
fn[T] insert_rec(
  node : AaNode[T]?,
  key : T,
  compare : (T, T) -> Int,
  inserted : Ref[Bool],
) -> AaNode[T] {
  match node {
    None => {
      inserted.val = true
      { val: key, level: 1, left: None, right: None }
    }
    Some(n) => {
      let c = compare(key, n.val)
      if c < 0 {
        n.left = Some(insert_rec(n.left, key, compare, inserted))
      } else if c > 0 {
        n.right = Some(insert_rec(n.right, key, compare, inserted))
      } else {
        // Duplicate key — do nothing.
        return n
      }
      // Rebalance bottom-up.
      let skewed = skew(n)
      let splitted = split(skewed)
      splitted
    }
  }
}

// ---------------------------------------------------------------------------
// Deletion
// ---------------------------------------------------------------------------

///|
/// Remove a key. O(log n).
///
/// Returns `true` if found and removed, `false` otherwise.
pub fn[T] AaTree::remove(self : AaTree[T], key : T) -> Bool {
  let removed : Ref[Bool] = Ref(false)
  self.root = remove_rec(self.root, key, self.compare, removed)
  if removed.val {
    self.count = self.count - 1
  }
  removed.val
}

///|
/// Recursive delete with bottom-up rebalancing.
fn[T] remove_rec(
  node : AaNode[T]?,
  key : T,
  compare : (T, T) -> Int,
  removed : Ref[Bool],
) -> AaNode[T]? {
  match node {
    None => None
    Some(n) => {
      let c = compare(key, n.val)
      if c == 0 {
        // Found the node to delete.
        removed.val = true
        if n.left is None && n.right is None {
          // Leaf — just remove.
          None
        } else if n.left is None {
          // Only right child — replace with in-order successor.
          let succ = find_min_node(n.right)
          match succ {
            Some(s) => {
              n.val = s.val
              n.right = remove_rec(n.right, s.val, compare, removed)
              Some(rebalance_after_delete(n))
            }
            None => None
          }
        } else {
          // Has left child — replace with in-order predecessor.
          let pred = find_max_node(n.left)
          match pred {
            Some(p) => {
              n.val = p.val
              n.left = remove_rec(n.left, p.val, compare, removed)
              Some(rebalance_after_delete(n))
            }
            None => None
          }
        }
      } else {
        // Not found yet — recurse into the appropriate subtree.
        if c < 0 {
          n.left = remove_rec(n.left, key, compare, removed)
        } else {
          n.right = remove_rec(n.right, key, compare, removed)
        }
        Some(rebalance_after_delete(n))
      }
    }
  }
}

///|
/// Skew on an optional node (no-op if None).
fn[T] skew_opt(node : AaNode[T]?) -> AaNode[T]? {
  match node {
    None => None
    Some(n) => Some(skew(n))
  }
}

///|
/// Split on an optional node (no-op if None).
fn[T] split_opt(node : AaNode[T]?) -> AaNode[T]? {
  match node {
    None => None
    Some(n) => Some(split(n))
  }
}

///|
/// Rebalance a node after deletion: decrease level if needed, then apply
/// skew three times and split twice (Andersson's prescription).
///
/// Reference: Andersson, A. (1993). "Balanced search trees made simple."
fn[T] rebalance_after_delete(n : AaNode[T]) -> AaNode[T] {
  // Step 1: Decrease level if needed.
  // should_be = 1 + min(left.level, right.level)
  let left_level = match n.left {
    None => 0
    Some(l) => l.level
  }
  let right_level = match n.right {
    None => 0
    Some(r) => r.level
  }
  let min_level = if left_level < right_level {
    left_level
  } else {
    right_level
  }
  let should_be = 1 + min_level
  if should_be < n.level {
    n.level = should_be
    // Also decrease right child's level to match.
    match n.right {
      Some(r) => if r.level > should_be { r.level = should_be }
      None => ()
    }
  }
  // Step 2: Three skews (skew at n, then n.right, then n.right.right).
  let n0 = skew(n)
  n0.right = skew_opt(n0.right)
  match n0.right {
    Some(r) => r.right = skew_opt(r.right)
    None => ()
  }
  // Step 3: Two splits (split at n, then n.right).
  let n1 = split(n0)
  n1.right = split_opt(n1.right)
  n1
}

///|
/// Find the minimum node in a subtree.
fn[T] find_min_node(node : AaNode[T]?) -> AaNode[T]? {
  match node {
    None => None
    Some(n) => {
      let mut cur = n
      while cur.left is Some(_) {
        match cur.left {
          Some(l) => cur = l
          None => ()
        }
      }
      Some(cur)
    }
  }
}

///|
/// Find the maximum node in a subtree.
fn[T] find_max_node(node : AaNode[T]?) -> AaNode[T]? {
  match node {
    None => None
    Some(n) => {
      let mut cur = n
      while cur.right is Some(_) {
        match cur.right {
          Some(r) => cur = r
          None => ()
        }
      }
      Some(cur)
    }
  }
}

// ---------------------------------------------------------------------------
// Traversal
// ---------------------------------------------------------------------------

///|
/// In-order traversal. O(n).
pub fn[T] AaTree::in_order(self : AaTree[T], f : (T) -> Unit) -> Unit {
  in_order_rec(self.root, f)
}

///|
fn[T] in_order_rec(node : AaNode[T]?, f : (T) -> Unit) -> Unit {
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
/// Convert to sorted array. O(n).
pub fn[T] AaTree::to_sorted_array(self : AaTree[T]) -> Array[T] {
  let result : Array[T] = []
  self.in_order(fn(v) { result.push(v) })
  result
}

// ---------------------------------------------------------------------------
// Verification (test-only)
// ---------------------------------------------------------------------------

///|
/// Verify BST property.
fn[T] verify_bst(node : AaNode[T]?, compare : (T, T) -> Int) -> Bool {
  match node {
    None => true
    Some(n) => {
      let left_ok = match n.left {
        None => true
        Some(l) => compare(l.val, n.val) < 0 && verify_bst(Some(l), compare)
      }
      let right_ok = match n.right {
        None => true
        Some(r) => compare(r.val, n.val) > 0 && verify_bst(Some(r), compare)
      }
      left_ok && right_ok
    }
  }
}

///|
/// Verify AA tree invariants.
fn[T] verify_aa_invariants(node : AaNode[T]?) -> Bool {
  match node {
    None => true
    Some(n) => {
      // Check: leaf level is 1
      if n.left is None && n.right is None && n.level != 1 {
        return false
      }
      // Check: left child level is exactly one less
      match n.left {
        Some(l) => if l.level != n.level - 1 { return false }
        None => ()
      }
      // Check: right child level is equal or one less
      match n.right {
        Some(r) =>
          if r.level != n.level && r.level != n.level - 1 {
            return false
          }
        None => ()
      }
      // Check: right grandchild level is strictly less
      match n.right {
        Some(r) =>
          match r.right {
            Some(rr) => if rr.level >= n.level { return false }
            None => ()
          }
        None => ()
      }
      // Check: nodes with level > 1 have two children
      if n.level > 1 && (n.left is None || n.right is None) {
        return false
      }
      verify_aa_invariants(n.left) && verify_aa_invariants(n.right)
    }
  }
}

///|
/// Compute tree height. O(n).
fn[T] height_of(node : AaNode[T]?) -> Int {
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
// Tests
// ---------------------------------------------------------------------------

///|
test "aa_tree: empty tree" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  assert_true(t.is_empty())
  assert_eq(t.size(), 0)
  assert_false(t.contains(0))
  assert_true(t.find_min() is None)
  assert_true(t.find_max() is None)
}

///|
test "aa_tree: insert and search" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
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

///|
test "aa_tree: duplicate insert" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  assert_true(t.insert(5))
  assert_false(t.insert(5))
  assert_eq(t.size(), 1)
}

///|
test "aa_tree: find_min and find_max" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(7))
  ignore(t.insert(1))
  ignore(t.insert(9))
  assert_eq(t.find_min(), Some(1))
  assert_eq(t.find_max(), Some(9))
}

///|
test "aa_tree: in-order sorted" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  let input = [7, 3, 9, 1, 5, 8, 2, 6, 4, 0]
  for i = 0; i < input.length(); i = i + 1 {
    ignore(t.insert(input[i]))
  }
  let result = t.to_sorted_array()
  for i = 0; i < 10; i = i + 1 {
    assert_eq(result[i], i)
  }
}

///|
test "aa_tree: BST property after inserts" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 100; i = i + 1 {
    ignore(t.insert(i * 37 % 100))
  }
  assert_true(verify_bst(t.root, t.compare))
  assert_true(verify_aa_invariants(t.root))
}

///|
test "aa_tree: insert sorted ascending" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 200; i = i + 1 {
    ignore(t.insert(i))
  }
  assert_eq(t.size(), 200)
  assert_true(verify_bst(t.root, t.compare))
  assert_true(verify_aa_invariants(t.root))
  let h = height_of(t.root)
  // AA tree height ≤ 2 * log2(n+1) ≈ 16 for n=200
  assert_true(h <= 20)
  let result = t.to_sorted_array()
  for i = 0; i < 200; i = i + 1 {
    assert_eq(result[i], i)
  }
}

///|
test "aa_tree: insert sorted descending" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 200; i = i + 1 {
    ignore(t.insert(200 - i))
  }
  assert_eq(t.size(), 200)
  assert_true(verify_bst(t.root, t.compare))
  assert_true(verify_aa_invariants(t.root))
  let h = height_of(t.root)
  assert_true(h <= 20)
}

///|
test "aa_tree: remove leaf" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(7))
  assert_true(t.remove(3))
  assert_eq(t.size(), 2)
  assert_false(t.contains(3))
  assert_true(verify_bst(t.root, t.compare))
  assert_true(verify_aa_invariants(t.root))
}

///|
test "aa_tree: remove node with one child" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(7))
  ignore(t.insert(8))
  assert_true(t.remove(7))
  assert_eq(t.size(), 3)
  assert_false(t.contains(7))
  assert_true(t.contains(8))
  assert_true(verify_bst(t.root, t.compare))
  assert_true(verify_aa_invariants(t.root))
}

///|
test "aa_tree: remove node with two children" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
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
  assert_true(verify_bst(t.root, t.compare))
  assert_true(verify_aa_invariants(t.root))
  let result = t.to_sorted_array()
  assert_eq(result, [1, 3, 4, 6, 7, 8])
}

///|
test "aa_tree: remove non-existent" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  assert_false(t.remove(7))
  assert_eq(t.size(), 2)
}

///|
test "aa_tree: remove all" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 50; i = i + 1 {
    ignore(t.insert(i))
  }
  for i = 0; i < 50; i = i + 1 {
    assert_true(t.remove(i))
  }
  assert_eq(t.size(), 0)
  assert_true(t.is_empty())
  assert_true(t.root is None)
}

///|
test "aa_tree: intermixed insert and remove" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(7))
  ignore(t.remove(3))
  ignore(t.insert(1))
  ignore(t.insert(9))
  ignore(t.remove(5))
  ignore(t.insert(4))
  assert_true(verify_bst(t.root, t.compare))
  assert_true(verify_aa_invariants(t.root))
  let result = t.to_sorted_array()
  assert_eq(result, [1, 4, 7, 9])
}

///|
test "aa_tree: height is logarithmic" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  for i = 0; i < 1000; i = i + 1 {
    ignore(t.insert(i))
  }
  let h = height_of(t.root)
  // AA tree height ≤ 2 * log2(n+1) ≈ 20 for n=1000
  assert_true(h <= 25)
  assert_true(h < 100)
}

///|
test "aa_tree: stress test random operations" {
  let t = AaTree::new(fn(a : Int, b : Int) -> Int { a - b })
  let mut seed = 42
  let present : Array[Bool] = Array::make(200, false)
  let mut count = 0
  for i = 0; i < 2000; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let val = seed % 200
    let op = seed % 3
    if op == 0 || op == 1 {
      if !present[val] {
        assert_true(t.insert(val))
        present[val] = true
        count = count + 1
      } else {
        assert_false(t.insert(val))
      }
    } else if present[val] {
      assert_true(t.remove(val))
      present[val] = false
      count = count - 1
    } else {
      assert_false(t.remove(val))
    }
    if i % 500 == 499 {
      assert_true(verify_bst(t.root, t.compare))
      assert_true(verify_aa_invariants(t.root))
      assert_eq(t.size(), count)
    }
  }
  assert_true(verify_bst(t.root, t.compare))
  assert_true(verify_aa_invariants(t.root))
  assert_eq(t.size(), count)
  let sorted = t.to_sorted_array()
  let mut idx = 0
  for v = 0; v < 200; v = v + 1 {
    if present[v] {
      assert_eq(sorted[idx], v)
      idx = idx + 1
    }
  }
}

///|
test "aa_tree: string keys" {
  let t = AaTree::new(fn(a : String, b : String) -> Int {
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
