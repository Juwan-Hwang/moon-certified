/// B-Tree implementation with configurable minimum degree `t`.
///
/// A B-Tree of minimum degree `t` has at most `2*t - 1` keys per node and at
/// least `t - 1` keys per non-root node. The root may have 0 keys (empty tree).
/// All leaves are at the same depth.
///
/// **Generic**: works with any type `T` given a comparator function.
///
/// Supports insert (with duplicate suppression), search, delete, in-order
/// traversal, and size. All operations run in O(log n) time.
/// `size()` is O(1) via a cached count field.
///
/// Use [`new_with_degree`] to create a B-Tree with a custom minimum degree.
/// The default [`new`] uses `t = 2` (a 2-3 tree).
///
/// Not formally verified. Correctness ensured by comprehensive tests.

///|
/// Default minimum degree when using `new()`.
const BTREE_DEFAULT_DEGREE : Int = 2

///|
/// A B-Tree node.
///
/// `keys` is a sorted array of keys. `children` is an array of child nodes
/// (length = keys.length() + 1 for internal nodes, 0 for leaves). `count`
/// is the cached total number of keys in this subtree, enabling O(1) `size`.
/// `degree` is the minimum degree `t` (shared across all nodes in the tree).
pub struct BTreeNode[T] {
  priv keys : Array[T]
  priv children : Array[BTreeNode[T]]
  priv leaf : Bool
  priv mut count : Int
  priv degree : Int
}

///|
/// Create an empty B-Tree with the default minimum degree `t = 2` (2-3 tree).
pub fn[T] new() -> BTreeNode[T] {
  new_with_degree(BTREE_DEFAULT_DEGREE)
}

///|
/// Create an empty B-Tree with a custom minimum degree `t >= 2`.
/// Higher `t` means wider, shallower trees — better for disk-based scenarios
/// with large block sizes. `t < 2` is clamped to 2.
pub fn[T] new_with_degree(degree : Int) -> BTreeNode[T] {
  let t = if degree < 2 { BTREE_DEFAULT_DEGREE } else { degree }
  { keys: [], children: [], leaf: true, count: 0, degree: t }
}

///|
fn[T] btree_create(leaf : Bool, degree : Int) -> BTreeNode[T] {
  { keys: [], children: [], leaf, count: 0, degree }
}

// ---------------------------------------------------------------------------
// Array helpers — insert / remove at an arbitrary index.
// MoonBit's Array supports push and pop, but not positional insert/remove.
// ---------------------------------------------------------------------------

///|
fn[T] keys_remove(arr : Array[T], idx : Int) -> Unit {
  let n = arr.length()
  for i = idx; i < n - 1; i = i + 1 {
    arr[i] = arr[i + 1]
  }
  ignore(arr.pop())
}

///|
fn[T] keys_insert(arr : Array[T], idx : Int, val : T) -> Unit {
  arr.push(val)
  let n = arr.length()
  for i = n - 1; i > idx; i = i - 1 {
    arr[i] = arr[i - 1]
  }
  arr[idx] = val
}

///|
fn[T] children_remove(arr : Array[BTreeNode[T]], idx : Int) -> Unit {
  let n = arr.length()
  for i = idx; i < n - 1; i = i + 1 {
    arr[i] = arr[i + 1]
  }
  ignore(arr.pop())
}

///|
fn[T] children_insert(
  arr : Array[BTreeNode[T]],
  idx : Int,
  val : BTreeNode[T],
) -> Unit {
  arr.push(val)
  let n = arr.length()
  for i = n - 1; i > idx; i = i - 1 {
    arr[i] = arr[i - 1]
  }
  arr[idx] = val
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

///|
/// Search for `key` in the subtree rooted at `root`. Returns true if found.
pub fn[T] search(root : BTreeNode[T], key : T, cmp : (T, T) -> Int) -> Bool {
  let mut i = 0
  let n = root.keys.length()
  while i < n && cmp(root.keys[i], key) < 0 {
    i = i + 1
  }
  if i < n && cmp(root.keys[i], key) == 0 {
    return true
  }
  if root.leaf {
    return false
  }
  search(root.children[i], key, cmp)
}

// ---------------------------------------------------------------------------
// Insert
// ---------------------------------------------------------------------------

///|
/// Split child `i` of node `x`. The child must be full (2t-1 keys).
/// The median key moves up to `x`; a new node receives the right half.
fn[T] split_child(x : BTreeNode[T], i : Int, cmp : (T, T) -> Int) -> Unit {
  let t = x.degree
  let y = x.children[i]
  let z = btree_create(y.leaf, y.degree)
  // Median key is at index t-1 in y.
  let median = y.keys[t - 1]
  // z gets keys at indices t .. 2t-2 (t-1 keys).
  for j = 0; j < t - 1; j = j + 1 {
    z.keys.push(y.keys[t + j])
  }
  // z gets children at indices t .. 2t-1 (t children) if y is not a leaf.
  if !y.leaf {
    for j = 0; j < t; j = j + 1 {
      z.children.push(y.children[t + j])
    }
  }
  // Truncate y: keep only the first t-1 keys and first t children.
  while y.keys.length() > t - 1 {
    ignore(y.keys.pop())
  }
  if !y.leaf {
    while y.children.length() > t {
      ignore(y.children.pop())
    }
  }
  // Insert z as child i+1 and the median as key i in x.
  children_insert(x.children, i + 1, z)
  keys_insert(x.keys, i, median)
  // Update cached counts.
  update_count(y)
  update_count(z)
  update_count(x)
  ignore(cmp)
}

///|
/// Insert `key` into a node that is guaranteed not to be full.
fn[T] insert_non_full(
  node : BTreeNode[T],
  key : T,
  cmp : (T, T) -> Int,
) -> Unit {
  let n = node.keys.length()
  if node.leaf {
    // Find the correct sorted position and insert.
    let mut pos = 0
    while pos < n && cmp(node.keys[pos], key) < 0 {
      pos = pos + 1
    }
    keys_insert(node.keys, pos, key)
    node.count = node.count + 1
  } else {
    // Find the child to descend into.
    let mut i = n - 1
    while i >= 0 && cmp(node.keys[i], key) > 0 {
      i = i - 1
    }
    i = i + 1
    // If that child is full, split it first.
    if node.children[i].keys.length() == 2 * node.degree - 1 {
      split_child(node, i, cmp)
      // After the split, decide which half to descend into.
      if cmp(node.keys[i], key) < 0 {
        i = i + 1
      }
    }
    insert_non_full(node.children[i], key, cmp)
    node.count = node.count + 1
  }
}

///|
/// Insert `key` into the tree rooted at `root`. Duplicates are silently
/// ignored. Returns the (possibly new) root.
pub fn[T] insert(
  root : BTreeNode[T],
  key : T,
  cmp : (T, T) -> Int,
) -> BTreeNode[T] {
  // Suppress duplicates.
  if search(root, key, cmp) {
    return root
  }
  // If the root is full, create a new root and split.
  if root.keys.length() == 2 * root.degree - 1 {
    let new_root = btree_create(false, root.degree)
    new_root.children.push(root)
    split_child(new_root, 0, cmp)
    insert_non_full(new_root, key, cmp)
    new_root
  } else {
    insert_non_full(root, key, cmp)
    root
  }
}

// ---------------------------------------------------------------------------
// Size (cached for O(1) lookup)
// ---------------------------------------------------------------------------

///|
/// Recompute the cached `count` field from keys + children.
/// Called after structural mutations (split, merge, borrow, insert, delete).
fn[T] update_count(node : BTreeNode[T]) -> Unit {
  let mut c = node.keys.length()
  for i = 0; i < node.children.length(); i = i + 1 {
    c = c + node.children[i].count
  }
  node.count = c
}

///|
/// Count the total number of keys in the tree.
/// O(1) via cached count field.
pub fn[T] size(root : BTreeNode[T]) -> Int {
  root.count
}

// ---------------------------------------------------------------------------
// In-order traversal
// ---------------------------------------------------------------------------

///|
/// Visit every key in sorted order, calling `f` on each.
pub fn[T] inorder(root : BTreeNode[T], f : (T) -> Unit) -> Unit {
  let n = root.keys.length()
  for i = 0; i < n; i = i + 1 {
    if !root.leaf {
      inorder(root.children[i], f)
    }
    f(root.keys[i])
  }
  if !root.leaf && root.children.length() > n {
    inorder(root.children[n], f)
  }
}

// ---------------------------------------------------------------------------
// Delete helpers
// ---------------------------------------------------------------------------

///|
/// Return the predecessor of the key at index `idx` (the maximum key in
/// the left subtree). The caller must ensure `children[idx]` has at least
/// t keys.
fn[T] get_pred(node : BTreeNode[T], idx : Int) -> T {
  let mut cur = node.children[idx]
  while !cur.leaf {
    cur = cur.children[cur.keys.length()]
  }
  cur.keys[cur.keys.length() - 1]
}

///|
/// Return the successor of the key at index `idx` (the minimum key in
/// the right subtree). The caller must ensure `children[idx+1]` has at
/// least t keys.
fn[T] get_succ(node : BTreeNode[T], idx : Int) -> T {
  let mut cur = node.children[idx + 1]
  while !cur.leaf {
    cur = cur.children[0]
  }
  cur.keys[0]
}

///|
/// Borrow a key from the left sibling (`children[idx-1]`) into
/// `children[idx]` via the parent key at `idx-1`.
fn[T] _borrow_from_prev(node : BTreeNode[T], idx : Int) -> Unit {
  let child = node.children[idx]
  let sibling = node.children[idx - 1]
  // Move the parent key down to the front of child.
  keys_insert(child.keys, 0, node.keys[idx - 1])
  // Move the last child of sibling to the front of child (if internal).
  if !child.leaf {
    children_insert(child.children, 0, sibling.children[sibling.keys.length()])
    ignore(sibling.children.pop())
  }
  // Move the sibling's last key up to the parent.
  node.keys[idx - 1] = sibling.keys[sibling.keys.length() - 1]
  ignore(sibling.keys.pop())
  update_count(child)
  update_count(sibling)
}

///|
/// Borrow a key from the right sibling (`children[idx+1]`) into
/// `children[idx]` via the parent key at `idx`.
fn[T] _borrow_from_next(node : BTreeNode[T], idx : Int) -> Unit {
  let child = node.children[idx]
  let sibling = node.children[idx + 1]
  // Move the parent key down to the end of child.
  child.keys.push(node.keys[idx])
  // Move the first child of sibling to the end of child (if internal).
  if !child.leaf {
    child.children.push(sibling.children[0])
    children_remove(sibling.children, 0)
  }
  // Move the sibling's first key up to the parent.
  node.keys[idx] = sibling.keys[0]
  keys_remove(sibling.keys, 0)
  update_count(child)
  update_count(sibling)
}

///|
/// Merge `children[idx]` and `children[idx+1]` into a single node.
/// The parent key at `idx` descends to become the median of the merged node.
fn[T] _merge(node : BTreeNode[T], idx : Int) -> Unit {
  let child = node.children[idx]
  let sibling = node.children[idx + 1]
  // Descend the parent key into child.
  child.keys.push(node.keys[idx])
  // Copy all of sibling's keys into child.
  for i = 0; i < sibling.keys.length(); i = i + 1 {
    child.keys.push(sibling.keys[i])
  }
  // Copy all of sibling's children into child (if internal).
  if !child.leaf {
    for i = 0; i < sibling.children.length(); i = i + 1 {
      child.children.push(sibling.children[i])
    }
  }
  // Remove the descended key and the merged sibling from the parent.
  keys_remove(node.keys, idx)
  children_remove(node.children, idx + 1)
  update_count(child)
  update_count(node)
}

///|
/// Ensure `children[idx]` has at least t keys before descending, by
/// borrowing from a sibling or merging with one.
fn[T] _fill(node : BTreeNode[T], idx : Int) -> Unit {
  let t = node.degree
  // A node with 0 keys has a single child that already has >= t keys
  // (from a previous merge), so nothing to do.
  if node.keys.length() == 0 {
    return
  }
  // Try borrowing from the left sibling.
  if idx > 0 && node.children[idx - 1].keys.length() >= t {
    _borrow_from_prev(node, idx)
    // Try borrowing from the right sibling.
  } else if idx < node.keys.length() &&
    node.children[idx + 1].keys.length() >= t {
    _borrow_from_next(node, idx)
    // Both siblings are minimal: merge.
  } else if idx < node.keys.length() {
    _merge(node, idx) // merge with right sibling
  } else {
    _merge(node, idx - 1) // merge with left sibling (idx is last child)
  }
}

///|
/// Delete the key at index `idx` from an internal node.
fn[T] _delete_internal(
  node : BTreeNode[T],
  idx : Int,
  cmp : (T, T) -> Int,
) -> Unit {
  let t = node.degree
  let key = node.keys[idx]
  // Case 2a: left child has >= t keys — replace with predecessor.
  if node.children[idx].keys.length() >= t {
    let pred = get_pred(node, idx)
    node.keys[idx] = pred
    _delete(node.children[idx], pred, cmp)
    // Case 2b: right child has >= t keys — replace with successor.
  } else if node.children[idx + 1].keys.length() >= t {
    let succ = get_succ(node, idx)
    node.keys[idx] = succ
    _delete(node.children[idx + 1], succ, cmp)
    // Case 2c: both children are minimal — merge, then delete from merged.
  } else {
    _merge(node, idx)
    _delete(node.children[idx], key, cmp)
  }
}

///|
/// Delete `key` from the subtree rooted at `node` (mutated in place).
fn[T] _delete(node : BTreeNode[T], key : T, cmp : (T, T) -> Int) -> Unit {
  let t = node.degree
  let n = node.keys.length()
  // Find the first key >= key.
  let mut idx = 0
  while idx < n && cmp(node.keys[idx], key) < 0 {
    idx = idx + 1
  }
  if idx < n && cmp(node.keys[idx], key) == 0 {
    // Key found in this node.
    if node.leaf {
      // Case 1: key in a leaf — simply remove it.
      keys_remove(node.keys, idx)
      node.count = node.count - 1
    } else {
      // Case 2: key in an internal node.
      _delete_internal(node, idx, cmp)
    }
  } else {
    // Case 3: key not in this node.
    if node.leaf {
      return // key not in the tree
    }
    // Key must be in subtree children[idx] (if it exists at all).
    let mut ci = idx
    // Ensure the child we descend into has at least t keys.
    let n_children = node.children.length()
    if node.children[ci].keys.length() < t {
      _fill(node, ci)
    }
    // _fill may merge ci with its left sibling when ci is the last child
    // and both siblings have only t-1 keys. After such a left-merge,
    // children[ci] is removed and the merged content lives at ci-1.
    // A right-merge (or borrow) leaves ci valid, so we only adjust ci
    // when a merge actually happened and ci is now out of range.
    if node.children.length() < n_children && ci >= node.children.length() {
      ci = ci - 1
    }
    _delete(node.children[ci], key, cmp)
  }
  update_count(node)
}

///|
/// Delete `key` from the tree rooted at `root`. If the key is not present
/// the tree is unchanged. Returns the (possibly new) root.
pub fn[T] delete(
  root : BTreeNode[T],
  key : T,
  cmp : (T, T) -> Int,
) -> BTreeNode[T] {
  _delete(root, key, cmp)
  // If the root has been emptied but still has a child, promote it.
  if root.keys.length() == 0 && !root.leaf {
    root.children[0]
  } else {
    root
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
/// Integer comparator for tests.
fn int_cmp(a : Int, b : Int) -> Int {
  a - b
}

///|
test "btree: basic insert and search" {
  let root = new()
  let r = insert(root, 5, int_cmp)
  let r = insert(r, 3, int_cmp)
  let r = insert(r, 7, int_cmp)
  assert_true(search(r, 5, int_cmp))
  assert_true(search(r, 3, int_cmp))
  assert_true(search(r, 7, int_cmp))
  assert_false(search(r, 1, int_cmp))
  assert_false(search(r, 9, int_cmp))
  assert_eq(size(r), 3)
}

///|
test "btree: sequential insert" {
  let mut root = new()
  for i = 1; i <= 10; i = i + 1 {
    root = insert(root, i, int_cmp)
  }
  assert_eq(size(root), 10)
  for i = 1; i <= 10; i = i + 1 {
    assert_true(search(root, i, int_cmp))
  }
}

///|
test "btree: search non-existent" {
  let mut root = new()
  let vals = [10, 20, 30, 40, 50]
  for i = 0; i < 5; i = i + 1 {
    root = insert(root, vals[i], int_cmp)
  }
  assert_false(search(root, 5, int_cmp))
  assert_false(search(root, 15, int_cmp))
  assert_false(search(root, 25, int_cmp))
  assert_false(search(root, 35, int_cmp))
  assert_false(search(root, 45, int_cmp))
  assert_false(search(root, 55, int_cmp))
  assert_false(search(root, 100, int_cmp))
}

///|
test "btree: root split" {
  // With t=2, max keys = 3. Inserting 4 keys forces a root split.
  let mut root = new()
  root = insert(root, 1, int_cmp)
  root = insert(root, 2, int_cmp)
  root = insert(root, 3, int_cmp)
  assert_eq(size(root), 3)
  // This insert causes the root (leaf, 3 keys) to split.
  root = insert(root, 4, int_cmp)
  assert_eq(size(root), 4)
  // After split, root should be an internal node with 1 key.
  assert_false(root.leaf)
  assert_eq(root.keys.length(), 1)
  // All keys should still be found.
  for i = 1; i <= 4; i = i + 1 {
    assert_true(search(root, i, int_cmp))
  }
}

///|
test "btree: internal node split" {
  // Insert enough elements to force splits at multiple levels.
  let mut root = new()
  for i = 1; i <= 20; i = i + 1 {
    root = insert(root, i, int_cmp)
  }
  assert_eq(size(root), 20)
  // The tree should have more than one level.
  assert_false(root.leaf)
  // All keys must be present.
  for i = 1; i <= 20; i = i + 1 {
    assert_true(search(root, i, int_cmp))
  }
}

///|
test "btree: large insert 100 elements" {
  let mut root = new()
  // Insert in a pseudo-random order to exercise different split patterns.
  for i = 0; i < 100; i = i + 1 {
    let val = (i * 37 + 11) % 100
    root = insert(root, val, int_cmp)
  }
  assert_eq(size(root), 100)
  // Every value 0..99 must be present.
  for i = 0; i < 100; i = i + 1 {
    assert_true(search(root, i, int_cmp))
  }
}

///|
test "btree: delete leaf" {
  let mut root = new()
  for i = 1; i <= 10; i = i + 1 {
    root = insert(root, i, int_cmp)
  }
  // Delete a value that resides in a leaf.
  root = delete(root, 1, int_cmp)
  assert_false(search(root, 1, int_cmp))
  assert_eq(size(root), 9)
  // Other keys survive.
  for i = 2; i <= 10; i = i + 1 {
    assert_true(search(root, i, int_cmp))
  }
}

///|
test "btree: delete internal node" {
  let mut root = new()
  for i = 1; i <= 20; i = i + 1 {
    root = insert(root, i, int_cmp)
  }
  // Delete a key that has been promoted to an internal node.
  // With sequential insert 1..20, some of these will be internal.
  root = delete(root, 5, int_cmp)
  assert_false(search(root, 5, int_cmp))
  assert_eq(size(root), 19)
  // Remaining keys survive.
  for i = 1; i <= 20; i = i + 1 {
    if i != 5 {
      assert_true(search(root, i, int_cmp))
    }
  }
}

///|
test "btree: delete root key" {
  let mut root = new()
  for i = 1; i <= 15; i = i + 1 {
    root = insert(root, i, int_cmp)
  }
  // Delete whatever key is currently at the root.
  let root_key = root.keys[0]
  root = delete(root, root_key, int_cmp)
  assert_false(search(root, root_key, int_cmp))
  assert_eq(size(root), 14)
  // In-order traversal should still be sorted and contain all remaining keys.
  let result : Array[Int] = []
  inorder(root, fn(v) { result.push(v) })
  assert_eq(result.length(), 14)
  for i = 1; i < 14; i = i + 1 {
    assert_true(result[i - 1] < result[i])
  }
}

///|
test "btree: delete non-existent" {
  let mut root = new()
  for i = 1; i <= 10; i = i + 1 {
    root = insert(root, i, int_cmp)
  }
  root = delete(root, 999, int_cmp)
  assert_eq(size(root), 10)
  for i = 1; i <= 10; i = i + 1 {
    assert_true(search(root, i, int_cmp))
  }
}

///|
test "btree: delete all elements one by one" {
  let mut root = new()
  for i = 1; i <= 20; i = i + 1 {
    root = insert(root, i, int_cmp)
  }
  assert_eq(size(root), 20)
  for i = 1; i <= 20; i = i + 1 {
    root = delete(root, i, int_cmp)
    assert_false(search(root, i, int_cmp))
    assert_eq(size(root), 20 - i)
  }
  assert_eq(size(root), 0)
}

///|
test "btree: inorder sorted output" {
  let mut root = new()
  let vals = [50, 30, 70, 20, 40, 60, 80, 10, 90, 100]
  for i = 0; i < 10; i = i + 1 {
    root = insert(root, vals[i], int_cmp)
  }
  let result : Array[Int] = []
  inorder(root, fn(v) { result.push(v) })
  assert_eq(result.length(), 10)
  // Verify sorted order.
  for i = 0; i < 10; i = i + 1 {
    assert_eq(result[i], (i + 1) * 10)
  }
}

///|
test "btree: duplicate insert ignored" {
  let mut root = new()
  root = insert(root, 5, int_cmp)
  root = insert(root, 5, int_cmp)
  root = insert(root, 5, int_cmp)
  assert_eq(size(root), 1)
  assert_true(search(root, 5, int_cmp))
}

///|
test "btree: size tracking" {
  let mut root = new()
  assert_eq(size(root), 0)
  root = insert(root, 10, int_cmp)
  assert_eq(size(root), 1)
  root = insert(root, 20, int_cmp)
  root = insert(root, 30, int_cmp)
  assert_eq(size(root), 3)
  root = delete(root, 20, int_cmp)
  assert_eq(size(root), 2)
  root = delete(root, 10, int_cmp)
  root = delete(root, 30, int_cmp)
  assert_eq(size(root), 0)
}

///|
test "btree: empty tree operations" {
  let root = new()
  assert_eq(size(root), 0)
  assert_false(search(root, 1, int_cmp))
  let r2 = delete(root, 1, int_cmp)
  assert_eq(size(r2), 0)
  let result : Array[Int] = []
  inorder(root, fn(v) { result.push(v) })
  assert_eq(result.length(), 0)
}

///|
test "btree: delete with borrow from sibling" {
  // Build a tree that requires borrowing on delete.
  let mut root = new()
  for i = 1; i <= 10; i = i + 1 {
    root = insert(root, i, int_cmp)
  }
  // Delete several keys to trigger borrow operations.
  root = delete(root, 3, int_cmp)
  root = delete(root, 7, int_cmp)
  assert_false(search(root, 3, int_cmp))
  assert_false(search(root, 7, int_cmp))
  assert_eq(size(root), 8)
  // Verify remaining keys.
  let remaining = [1, 2, 4, 5, 6, 8, 9, 10]
  for i = 0; i < remaining.length(); i = i + 1 {
    assert_true(search(root, remaining[i], int_cmp))
  }
  // In-order should be sorted.
  let result : Array[Int] = []
  inorder(root, fn(v) { result.push(v) })
  assert_eq(result.length(), 8)
  for i = 1; i < 8; i = i + 1 {
    assert_true(result[i - 1] < result[i])
  }
}

///|
test "btree: generic with String keys" {
  let mut root = new()
  let cmp = @test_utils.str_cmp
  root = insert(root, "banana", cmp)
  root = insert(root, "apple", cmp)
  root = insert(root, "cherry", cmp)
  assert_true(search(root, "apple", cmp))
  assert_true(search(root, "banana", cmp))
  assert_true(search(root, "cherry", cmp))
  assert_false(search(root, "grape", cmp))
  assert_eq(size(root), 3)
  // In-order should be sorted alphabetically.
  let result : Array[String] = []
  inorder(root, fn(v) { result.push(v) })
  assert_eq(result[0], "apple")
  assert_eq(result[1], "banana")
  assert_eq(result[2], "cherry")
  // Delete and verify.
  root = delete(root, "banana", cmp)
  assert_false(search(root, "banana", cmp))
  assert_eq(size(root), 2)
}

///|
test "btree: configurable degree t=3" {
  // With t=3, max keys per node = 5. Insert 20 keys and verify correctness.
  let mut root = new_with_degree(3)
  for i = 1; i <= 20; i = i + 1 {
    root = insert(root, i, int_cmp)
  }
  assert_eq(size(root), 20)
  // All keys should be present.
  for i = 1; i <= 20; i = i + 1 {
    assert_true(search(root, i, int_cmp))
  }
  // In-order should be sorted.
  let result : Array[Int] = []
  inorder(root, fn(v) { result.push(v) })
  assert_eq(result.length(), 20)
  for i = 1; i < 20; i = i + 1 {
    assert_true(result[i - 1] < result[i])
  }
  // Delete some keys and verify.
  root = delete(root, 5, int_cmp)
  root = delete(root, 10, int_cmp)
  root = delete(root, 15, int_cmp)
  assert_eq(size(root), 17)
  assert_false(search(root, 5, int_cmp))
  assert_false(search(root, 10, int_cmp))
  assert_false(search(root, 15, int_cmp))
}

///|
test "btree: configurable degree t=4" {
  // With t=4, max keys = 7. Higher degree = wider, shallower tree.
  let mut root = new_with_degree(4)
  for i = 1; i <= 50; i = i + 1 {
    root = insert(root, i, int_cmp)
  }
  assert_eq(size(root), 50)
  for i = 1; i <= 50; i = i + 1 {
    assert_true(search(root, i, int_cmp))
  }
  // Delete all and verify empty.
  for i = 1; i <= 50; i = i + 1 {
    root = delete(root, i, int_cmp)
  }
  assert_eq(size(root), 0)
}
