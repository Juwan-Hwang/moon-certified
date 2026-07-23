/// B-Tree implementation with minimum degree t = 2.
///
/// A B-Tree of order M where M = 2*t - 1 = 3 (maximum keys per node).
/// Each non-root node has at least t - 1 = 1 key. The root may have 0 keys
/// (empty tree). All leaves are at the same depth.
///
/// Supports insert (with duplicate suppression), search, delete, in-order
/// traversal, and size. All operations run in O(log n) time.
///
/// Not formally verified. Correctness ensured by comprehensive tests.

const BTREE_MIN_DEGREE : Int = 2

pub struct BTreeNode {
  keys : Array[Int]
  children : Array[BTreeNode]
  leaf : Bool
}

/// Create an empty B-Tree (a single leaf node with no keys).
pub fn new() -> BTreeNode {
  { keys: [], children: [], leaf: true }
}

fn btree_create(leaf : Bool) -> BTreeNode {
  { keys: [], children: [], leaf }
}

// ---------------------------------------------------------------------------
// Array helpers — insert / remove at an arbitrary index.
// MoonBit's Array supports push and pop, but not positional insert/remove.
// ---------------------------------------------------------------------------

fn keys_remove(arr : Array[Int], idx : Int) -> Unit {
  let n = arr.length()
  for i = idx; i < n - 1; i = i + 1 {
    arr[i] = arr[i + 1]
  }
  ignore(arr.pop())
}

fn keys_insert(arr : Array[Int], idx : Int, val : Int) -> Unit {
  arr.push(val)
  let n = arr.length()
  for i = n - 1; i > idx; i = i - 1 {
    arr[i] = arr[i - 1]
  }
  arr[idx] = val
}

fn children_remove(arr : Array[BTreeNode], idx : Int) -> Unit {
  let n = arr.length()
  for i = idx; i < n - 1; i = i + 1 {
    arr[i] = arr[i + 1]
  }
  ignore(arr.pop())
}

fn children_insert(
  arr : Array[BTreeNode],
  idx : Int,
  val : BTreeNode,
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

/// Search for `key` in the subtree rooted at `root`. Returns true if found.
pub fn search(root : BTreeNode, key : Int) -> Bool {
  let mut i = 0
  let n = root.keys.length()
  while i < n && root.keys[i] < key {
    i = i + 1
  }
  if i < n && root.keys[i] == key {
    return true
  }
  if root.leaf {
    return false
  }
  search(root.children[i], key)
}

// ---------------------------------------------------------------------------
// Insert
// ---------------------------------------------------------------------------

/// Split child `i` of node `x`. The child must be full (2t-1 keys).
/// The median key moves up to `x`; a new node receives the right half.
fn split_child(x : BTreeNode, i : Int) -> Unit {
  let t = BTREE_MIN_DEGREE
  let y = x.children[i]
  let z = btree_create(y.leaf)
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
}

/// Insert `key` into a node that is guaranteed not to be full.
fn insert_non_full(node : BTreeNode, key : Int) -> Unit {
  let n = node.keys.length()
  if node.leaf {
    // Find the correct sorted position and insert.
    let mut pos = 0
    while pos < n && node.keys[pos] < key {
      pos = pos + 1
    }
    keys_insert(node.keys, pos, key)
  } else {
    // Find the child to descend into.
    let mut i = n - 1
    while i >= 0 && node.keys[i] > key {
      i = i - 1
    }
    i = i + 1
    // If that child is full, split it first.
    if node.children[i].keys.length() == 2 * BTREE_MIN_DEGREE - 1 {
      split_child(node, i)
      // After the split, decide which half to descend into.
      if node.keys[i] < key {
        i = i + 1
      }
    }
    insert_non_full(node.children[i], key)
  }
}

/// Insert `key` into the tree rooted at `root`. Duplicates are silently
/// ignored. Returns the (possibly new) root.
pub fn insert(root : BTreeNode, key : Int) -> BTreeNode {
  // Suppress duplicates.
  if search(root, key) {
    return root
  }
  // If the root is full, create a new root and split.
  if root.keys.length() == 2 * BTREE_MIN_DEGREE - 1 {
    let new_root = btree_create(false)
    new_root.children.push(root)
    split_child(new_root, 0)
    insert_non_full(new_root, key)
    new_root
  } else {
    insert_non_full(root, key)
    root
  }
}

// ---------------------------------------------------------------------------
// Size
// ---------------------------------------------------------------------------

/// Count the total number of keys in the tree.
pub fn size(root : BTreeNode) -> Int {
  let mut count = root.keys.length()
  for i = 0; i < root.children.length(); i = i + 1 {
    count = count + size(root.children[i])
  }
  count
}

// ---------------------------------------------------------------------------
// In-order traversal
// ---------------------------------------------------------------------------

/// Visit every key in sorted order, calling `f` on each.
pub fn inorder(root : BTreeNode, f : (Int) -> Unit) -> Unit {
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

/// Return the predecessor of the key at index `idx` (the maximum key in
/// the left subtree). The caller must ensure `children[idx]` has at least
/// t keys.
fn get_pred(node : BTreeNode, idx : Int) -> Int {
  let mut cur = node.children[idx]
  while !cur.leaf {
    cur = cur.children[cur.keys.length()]
  }
  cur.keys[cur.keys.length() - 1]
}

/// Return the successor of the key at index `idx` (the minimum key in
/// the right subtree). The caller must ensure `children[idx+1]` has at
/// least t keys.
fn get_succ(node : BTreeNode, idx : Int) -> Int {
  let mut cur = node.children[idx + 1]
  while !cur.leaf {
    cur = cur.children[0]
  }
  cur.keys[0]
}

/// Borrow a key from the left sibling (`children[idx-1]`) into
/// `children[idx]` via the parent key at `idx-1`.
fn _borrow_from_prev(node : BTreeNode, idx : Int) -> Unit {
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
}

/// Borrow a key from the right sibling (`children[idx+1]`) into
/// `children[idx]` via the parent key at `idx`.
fn _borrow_from_next(node : BTreeNode, idx : Int) -> Unit {
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
}

/// Merge `children[idx]` and `children[idx+1]` into a single node.
/// The parent key at `idx` descends to become the median of the merged node.
fn _merge(node : BTreeNode, idx : Int) -> Unit {
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
}

/// Ensure `children[idx]` has at least t keys before descending, by
/// borrowing from a sibling or merging with one.
fn _fill(node : BTreeNode, idx : Int) -> Unit {
  let t = BTREE_MIN_DEGREE
  // A node with 0 keys has a single child that already has >= t keys
  // (from a previous merge), so nothing to do.
  if node.keys.length() == 0 {
    return
  }
  // Try borrowing from the left sibling.
  if idx > 0 && node.children[idx - 1].keys.length() >= t {
    _borrow_from_prev(node, idx)
  }
  // Try borrowing from the right sibling.
  else if idx < node.keys.length() &&
          node.children[idx + 1].keys.length() >= t {
    _borrow_from_next(node, idx)
  }
  // Both siblings are minimal: merge.
  else {
    if idx < node.keys.length() {
      _merge(node, idx) // merge with right sibling
    } else {
      _merge(node, idx - 1) // merge with left sibling (idx is last child)
    }
  }
}

/// Delete the key at index `idx` from an internal node.
fn _delete_internal(node : BTreeNode, idx : Int) -> Unit {
  let t = BTREE_MIN_DEGREE
  let key = node.keys[idx]
  // Case 2a: left child has >= t keys — replace with predecessor.
  if node.children[idx].keys.length() >= t {
    let pred = get_pred(node, idx)
    node.keys[idx] = pred
    _delete(node.children[idx], pred)
  }
  // Case 2b: right child has >= t keys — replace with successor.
  else if node.children[idx + 1].keys.length() >= t {
    let succ = get_succ(node, idx)
    node.keys[idx] = succ
    _delete(node.children[idx + 1], succ)
  }
  // Case 2c: both children are minimal — merge, then delete from merged.
  else {
    _merge(node, idx)
    _delete(node.children[idx], key)
  }
}

/// Delete `key` from the subtree rooted at `node` (mutated in place).
fn _delete(node : BTreeNode, key : Int) -> Unit {
  let t = BTREE_MIN_DEGREE
  let n = node.keys.length()
  // Find the first key >= key.
  let mut idx = 0
  while idx < n && node.keys[idx] < key {
    idx = idx + 1
  }
  if idx < n && node.keys[idx] == key {
    // Key found in this node.
    if node.leaf {
      // Case 1: key in a leaf — simply remove it.
      keys_remove(node.keys, idx)
    } else {
      // Case 2: key in an internal node.
      _delete_internal(node, idx)
    }
  } else {
    // Case 3: key not in this node.
    if node.leaf {
      return // key not in the tree
    }
    // Key must be in subtree children[idx] (if it exists at all).
    let mut ci = idx
    // Ensure the child we descend into has at least t keys.
    if node.children[ci].keys.length() < t {
      _fill(node, ci)
    }
    // After _fill the structure may have changed; clamp ci.
    if ci > node.keys.length() {
      ci = node.keys.length()
    }
    _delete(node.children[ci], key)
  }
}

/// Delete `key` from the tree rooted at `root`. If the key is not present
/// the tree is unchanged. Returns the (possibly new) root.
pub fn delete(root : BTreeNode, key : Int) -> BTreeNode {
  _delete(root, key)
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

test "btree: basic insert and search" {
  let root = new()
  let r = insert(root, 5)
  let r = insert(r, 3)
  let r = insert(r, 7)
  assert_true(search(r, 5))
  assert_true(search(r, 3))
  assert_true(search(r, 7))
  assert_false(search(r, 1))
  assert_false(search(r, 9))
  assert_eq(size(r), 3)
}

test "btree: sequential insert" {
  let mut root = new()
  for i = 1; i <= 10; i = i + 1 {
    root = insert(root, i)
  }
  assert_eq(size(root), 10)
  for i = 1; i <= 10; i = i + 1 {
    assert_true(search(root, i))
  }
}

test "btree: search non-existent" {
  let mut root = new()
  let vals = [10, 20, 30, 40, 50]
  for i = 0; i < 5; i = i + 1 {
    root = insert(root, vals[i])
  }
  assert_false(search(root, 5))
  assert_false(search(root, 15))
  assert_false(search(root, 25))
  assert_false(search(root, 35))
  assert_false(search(root, 45))
  assert_false(search(root, 55))
  assert_false(search(root, 100))
}

test "btree: root split" {
  // With t=2, max keys = 3. Inserting 4 keys forces a root split.
  let mut root = new()
  root = insert(root, 1)
  root = insert(root, 2)
  root = insert(root, 3)
  assert_eq(size(root), 3)
  // This insert causes the root (leaf, 3 keys) to split.
  root = insert(root, 4)
  assert_eq(size(root), 4)
  // After split, root should be an internal node with 1 key.
  assert_false(root.leaf)
  assert_eq(root.keys.length(), 1)
  // All keys should still be found.
  for i = 1; i <= 4; i = i + 1 {
    assert_true(search(root, i))
  }
}

test "btree: internal node split" {
  // Insert enough elements to force splits at multiple levels.
  let mut root = new()
  for i = 1; i <= 20; i = i + 1 {
    root = insert(root, i)
  }
  assert_eq(size(root), 20)
  // The tree should have more than one level.
  assert_false(root.leaf)
  // All keys must be present.
  for i = 1; i <= 20; i = i + 1 {
    assert_true(search(root, i))
  }
}

test "btree: large insert 100 elements" {
  let mut root = new()
  // Insert in a pseudo-random order to exercise different split patterns.
  for i = 0; i < 100; i = i + 1 {
    let val = (i * 37 + 11) % 100
    root = insert(root, val)
  }
  assert_eq(size(root), 100)
  // Every value 0..99 must be present.
  for i = 0; i < 100; i = i + 1 {
    assert_true(search(root, i))
  }
}

test "btree: delete leaf" {
  let mut root = new()
  for i = 1; i <= 10; i = i + 1 {
    root = insert(root, i)
  }
  // Delete a value that resides in a leaf.
  root = delete(root, 1)
  assert_false(search(root, 1))
  assert_eq(size(root), 9)
  // Other keys survive.
  for i = 2; i <= 10; i = i + 1 {
    assert_true(search(root, i))
  }
}

test "btree: delete internal node" {
  let mut root = new()
  for i = 1; i <= 20; i = i + 1 {
    root = insert(root, i)
  }
  // Delete a key that has been promoted to an internal node.
  // With sequential insert 1..20, some of these will be internal.
  root = delete(root, 5)
  assert_false(search(root, 5))
  assert_eq(size(root), 19)
  // Remaining keys survive.
  for i = 1; i <= 20; i = i + 1 {
    if i != 5 {
      assert_true(search(root, i))
    }
  }
}

test "btree: delete root key" {
  let mut root = new()
  for i = 1; i <= 15; i = i + 1 {
    root = insert(root, i)
  }
  // Delete whatever key is currently at the root.
  let root_key = root.keys[0]
  root = delete(root, root_key)
  assert_false(search(root, root_key))
  assert_eq(size(root), 14)
  // In-order traversal should still be sorted and contain all remaining keys.
  let result : Array[Int] = []
  inorder(root, fn(v) { result.push(v) })
  assert_eq(result.length(), 14)
  for i = 1; i < 14; i = i + 1 {
    assert_true(result[i - 1] < result[i])
  }
}

test "btree: delete non-existent" {
  let mut root = new()
  for i = 1; i <= 10; i = i + 1 {
    root = insert(root, i)
  }
  root = delete(root, 999)
  assert_eq(size(root), 10)
  for i = 1; i <= 10; i = i + 1 {
    assert_true(search(root, i))
  }
}

test "btree: delete all elements one by one" {
  let mut root = new()
  for i = 1; i <= 20; i = i + 1 {
    root = insert(root, i)
  }
  assert_eq(size(root), 20)
  for i = 1; i <= 20; i = i + 1 {
    root = delete(root, i)
    assert_false(search(root, i))
    assert_eq(size(root), 20 - i)
  }
  assert_eq(size(root), 0)
}

test "btree: inorder sorted output" {
  let mut root = new()
  let vals = [50, 30, 70, 20, 40, 60, 80, 10, 90, 100]
  for i = 0; i < 10; i = i + 1 {
    root = insert(root, vals[i])
  }
  let result : Array[Int] = []
  inorder(root, fn(v) { result.push(v) })
  assert_eq(result.length(), 10)
  // Verify sorted order.
  for i = 0; i < 10; i = i + 1 {
    assert_eq(result[i], (i + 1) * 10)
  }
}

test "btree: duplicate insert ignored" {
  let mut root = new()
  root = insert(root, 5)
  root = insert(root, 5)
  root = insert(root, 5)
  assert_eq(size(root), 1)
  assert_true(search(root, 5))
}

test "btree: size tracking" {
  let mut root = new()
  assert_eq(size(root), 0)
  root = insert(root, 10)
  assert_eq(size(root), 1)
  root = insert(root, 20)
  root = insert(root, 30)
  assert_eq(size(root), 3)
  root = delete(root, 20)
  assert_eq(size(root), 2)
  root = delete(root, 10)
  root = delete(root, 30)
  assert_eq(size(root), 0)
}

test "btree: empty tree operations" {
  let root = new()
  assert_eq(size(root), 0)
  assert_false(search(root, 1))
  let r2 = delete(root, 1)
  assert_eq(size(r2), 0)
  let result : Array[Int] = []
  inorder(root, fn(v) { result.push(v) })
  assert_eq(result.length(), 0)
}

test "btree: delete with borrow from sibling" {
  // Build a tree that requires borrowing on delete.
  let mut root = new()
  for i = 1; i <= 10; i = i + 1 {
    root = insert(root, i)
  }
  // Delete several keys to trigger borrow operations.
  root = delete(root, 3)
  root = delete(root, 7)
  assert_false(search(root, 3))
  assert_false(search(root, 7))
  assert_eq(size(root), 8)
  // Verify remaining keys.
  let remaining = [1, 2, 4, 5, 6, 8, 9, 10]
  for i = 0; i < remaining.length(); i = i + 1 {
    assert_true(search(root, remaining[i]))
  }
  // In-order should be sorted.
  let result : Array[Int] = []
  inorder(root, fn(v) { result.push(v) })
  assert_eq(result.length(), 8)
  for i = 1; i < 8; i = i + 1 {
    assert_true(result[i - 1] < result[i])
  }
}
