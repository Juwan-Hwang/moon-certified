///|
/// Counted B-Tree — B-Tree with Subtree Size Tracking
///
/// A counted B-tree extends a standard B-tree by storing the number
/// of elements in each subtree. This enables O(log n) select(rank)
/// and rank(key) operations.
///
/// ## Implementation
///
/// Full CLRS B-tree with minimum degree `COUNTED_BTREE_MIN_DEGREE`:
/// - Proactive (top-down) splitting on insert: every node on the
///   descent path is guaranteed non-full before recursion, so a single
///   downward pass suffices and the root is grown when needed.
/// - Deletion with borrow-from-sibling and merge in a single downward
///   pass, keeping every visited child above the minimum occupancy so
///   backtracking is never required.
/// - Every node carries `count`, the total number of keys in its
///   subtree, maintained incrementally by all structural operations.
///
/// ## Complexity
/// - Insert/Delete/Search: O(log n)
/// - Select/Rank: O(log n)
///
/// `proof-enabled` is `false`.
const COUNTED_BTREE_MIN_DEGREE : Int = 3

///|
/// Maximum number of keys per node (2t - 1).
const COUNTED_BTREE_MAX_KEYS : Int = 2 * COUNTED_BTREE_MIN_DEGREE - 1

///|
/// Counted B-tree node. Keys are sorted; `children` has `n + 1` valid
/// entries when the node is internal. `count` is the total number of
/// keys stored in the subtree rooted at this node (including its own).
struct CountedNode {
  keys : Array[Int]
  values : Array[Int]
  children : Array[CountedNode]
  mut n : Int // number of keys
  leaf : Bool
  /// Count of elements in subtree rooted at this node
  mut count : Int
}

///|
fn counted_node_new(leaf : Bool) -> CountedNode {
  {
    keys: Array::make(COUNTED_BTREE_MAX_KEYS, 0),
    values: Array::make(COUNTED_BTREE_MAX_KEYS, 0),
    children: [],
    n: 0,
    leaf,
    count: 0,
  }
}

///|
/// Counted B-tree.
pub struct CountedBTree {
  mut root : CountedNode
  mut size : Int
}

///|
/// Create a new counted B-tree.
pub fn CountedBTree::new() -> CountedBTree {
  { root: counted_node_new(true), size: 0, }
}

///|
/// Search for a key, returning its associated value.
pub fn CountedBTree::search(self : CountedBTree, key : Int) -> Int? {
  let mut nd = self.root
  let mut result : Int? = None
  let mut scanning = true
  while scanning {
    let mut i = 0
    while i < nd.n && key > nd.keys[i] {
      i = i + 1
    }
    if i < nd.n && key == nd.keys[i] {
      result = Some(nd.values[i])
      scanning = false
    } else if nd.leaf {
      scanning = false
    } else {
      nd = nd.children[i]
    }
  }
  result
}

///|
/// Split the full child `nd.children[i]` in place. The median key moves
/// up into `nd`; the right half becomes a fresh sibling node. The total
/// key count of `nd`'s subtree is unchanged.
fn counted_split_child(nd : CountedNode, i : Int) -> Unit {
  let t = COUNTED_BTREE_MIN_DEGREE
  let full = nd.children[i]
  let sibling = counted_node_new(full.leaf)
  // Move the upper t-1 keys/values to the sibling.
  for j = 0; j < t - 1; j = j + 1 {
    sibling.keys[j] = full.keys[t + j]
    sibling.values[j] = full.values[t + j]
  }
  sibling.n = t - 1
  if !full.leaf {
    // Move the upper t children.
    for j = 0; j < t; j = j + 1 {
      sibling.children.push(full.children[t + j])
    }
    while full.children.length() > t {
      ignore(full.children.pop())
    }
  }
  full.n = t - 1
  // Recompute counts of both halves.
  full.count = t - 1
  for c in full.children {
    full.count = full.count + c.count
  }
  sibling.count = t - 1
  for c in sibling.children {
    sibling.count = sibling.count + c.count
  }
  // Median key/value moves up at position i.
  let med_k = full.keys[t - 1]
  let med_v = full.values[t - 1]
  for j = nd.n; j > i; j = j - 1 {
    nd.keys[j] = nd.keys[j - 1]
    nd.values[j] = nd.values[j - 1]
  }
  nd.keys[i] = med_k
  nd.values[i] = med_v
  // Insert the sibling pointer after position i.
  nd.children.insert(i + 1, sibling)
  nd.n = nd.n + 1
}

///|
/// Insert into a non-full node (top-down proactive splitting).
/// Returns `true` if a new key was added (subtree count grew by one),
/// `false` if an existing key's value was updated in place.
fn counted_insert_nonfull(nd : CountedNode, key : Int, value : Int) -> Bool {
  let mut i = nd.n - 1
  while i >= 0 && key < nd.keys[i] {
    i = i - 1
  }
  if i >= 0 && nd.keys[i] == key {
    nd.values[i] = value
    return false
  }
  if nd.leaf {
    // Shift right and insert at i + 1.
    for j = nd.n; j > i + 1; j = j - 1 {
      nd.keys[j] = nd.keys[j - 1]
      nd.values[j] = nd.values[j - 1]
    }
    nd.keys[i + 1] = key
    nd.values[i + 1] = value
    nd.n = nd.n + 1
    nd.count = nd.count + 1
    return true
  }
  let ci = i + 1
  if nd.children[ci].n == COUNTED_BTREE_MAX_KEYS {
    counted_split_child(nd, ci)
    if key == nd.keys[ci] {
      nd.values[ci] = value
      return false
    }
    if key > nd.keys[ci] {
      let added = counted_insert_nonfull(nd.children[ci + 1], key, value)
      if added {
        nd.count = nd.count + 1
      }
      return added
    }
  }
  let added = counted_insert_nonfull(nd.children[ci], key, value)
  if added {
    nd.count = nd.count + 1
  }
  added
}

///|
/// Insert a key-value pair. If the key already exists its value is
/// updated in place; otherwise the pair is inserted and the tree is
/// rebalanced via proactive splitting.
pub fn CountedBTree::insert(
  self : CountedBTree,
  key : Int,
  value : Int,
) -> Unit {
  if self.root.n == COUNTED_BTREE_MAX_KEYS {
    // Grow the tree at the root.
    let old_root = self.root
    let new_root = counted_node_new(false)
    new_root.children.push(old_root)
    counted_split_child(new_root, 0)
    // The split preserves the total key count; initialise the fresh
    // root's aggregate count from its children.
    new_root.count = new_root.n
    for c in new_root.children {
      new_root.count = new_root.count + c.count
    }
    self.root = new_root
  }
  if counted_insert_nonfull(self.root, key, value) {
    self.size = self.size + 1
  }
}

///|
/// Select the i-th smallest key (0-indexed). Returns `None` when the
/// rank is out of bounds.
pub fn CountedBTree::select(self : CountedBTree, rank : Int) -> Int? {
  if rank < 0 || rank >= self.size {
    return None
  }
  let mut nd = self.root
  let mut k = rank
  let mut result : Int? = None
  let mut scanning = true
  while scanning {
    if nd.leaf {
      result = Some(nd.keys[k])
      scanning = false
    } else {
      let mut i = 0
      let mut descended = false
      while !descended {
        let cc = nd.children[i].count
        if k < cc {
          nd = nd.children[i]
          descended = true
        } else {
          k = k - cc
          if k == 0 {
            result = Some(nd.keys[i])
            scanning = false
            descended = true
          } else {
            k = k - 1
            i = i + 1
          }
        }
      }
    }
  }
  result
}

///|
/// Get the rank (number of keys strictly less than `key`).
pub fn CountedBTree::rank(self : CountedBTree, key : Int) -> Int {
  let mut nd = self.root
  let mut r = 0
  let mut scanning = true
  while scanning {
    let mut i = 0
    while i < nd.n && key > nd.keys[i] {
      if !nd.leaf {
        r = r + nd.children[i].count
      }
      r = r + 1
      i = i + 1
    }
    if i < nd.n && key == nd.keys[i] {
      if !nd.leaf {
        r = r + nd.children[i].count
      }
      scanning = false
    } else if nd.leaf {
      scanning = false
    } else {
      nd = nd.children[i]
    }
  }
  r
}

// ===========================================================================
// Deletion (single-pass top-down, CLRS style)
// ===========================================================================

///|
/// Ensure `nd.children[i]` holds at least `COUNTED_BTREE_MIN_DEGREE`
/// keys: borrow from the richer sibling, or merge with a sibling when
/// both neighbours are minimal. After this call the caller must
/// re-search `nd` because keys/child positions may have shifted.
fn counted_fill_child(nd : CountedNode, i : Int) -> Unit {
  let t = COUNTED_BTREE_MIN_DEGREE
  let child = nd.children[i]
  if i > 0 && nd.children[i - 1].n >= t {
    // Borrow the largest key from the left sibling.
    let left = nd.children[i - 1]
    for j = child.n; j > 0; j = j - 1 {
      child.keys[j] = child.keys[j - 1]
      child.values[j] = child.values[j - 1]
    }
    // Keys transferred: the separator going down plus, for internal
    // nodes, the whole rightmost subtree of `left` moving over.
    let mut moved_count = 1
    if !child.leaf {
      let moved = left.children[left.n]
      child.children.insert(0, moved)
      ignore(left.children.pop())
      moved_count = moved_count + moved.count
    }
    child.keys[0] = nd.keys[i - 1]
    child.values[0] = nd.values[i - 1]
    nd.keys[i - 1] = left.keys[left.n - 1]
    nd.values[i - 1] = left.values[left.n - 1]
    left.n = left.n - 1
    child.n = child.n + 1
    left.count = left.count - moved_count
    child.count = child.count + moved_count
  } else if i < nd.n && nd.children[i + 1].n >= t {
    // Borrow the smallest key from the right sibling.
    let right = nd.children[i + 1]
    child.keys[child.n] = nd.keys[i]
    child.values[child.n] = nd.values[i]
    nd.keys[i] = right.keys[0]
    nd.values[i] = right.values[0]
    // Keys transferred: the separator going down plus, for internal
    // nodes, the whole leftmost subtree of `right` moving over.
    let mut moved_count = 1
    if !child.leaf {
      let moved = right.children[0]
      child.children.push(moved)
      ignore(right.children.remove(0))
      moved_count = moved_count + moved.count
    }
    for j = 0; j < right.n - 1; j = j + 1 {
      right.keys[j] = right.keys[j + 1]
      right.values[j] = right.values[j + 1]
    }
    right.n = right.n - 1
    child.n = child.n + 1
    child.count = child.count + moved_count
    right.count = right.count - moved_count
  } else if i < nd.n {
    // Merge the right sibling into `child` (separator moves down).
    // Covers both interior positions and the first child (i == 0),
    // which has no left sibling to borrow from or merge into.
    let right = nd.children[i + 1]
    child.keys[child.n] = nd.keys[i]
    child.values[child.n] = nd.values[i]
    child.n = child.n + 1
    for j = 0; j < right.n; j = j + 1 {
      child.keys[child.n] = right.keys[j]
      child.values[child.n] = right.values[j]
      child.n = child.n + 1
    }
    if !child.leaf {
      for c in right.children {
        child.children.push(c)
      }
    }
    child.count = child.count + right.count + 1
    for j = i; j < nd.n - 1; j = j + 1 {
      nd.keys[j] = nd.keys[j + 1]
      nd.values[j] = nd.values[j + 1]
    }
    ignore(nd.children.remove(i + 1))
    nd.n = nd.n - 1
  } else {
    // Last child (i == nd.n > 0): merge into the left sibling; the
    // merged node stays at position i-1.
    let left = nd.children[i - 1]
    left.keys[left.n] = nd.keys[i - 1]
    left.values[left.n] = nd.values[i - 1]
    left.n = left.n + 1
    for j = 0; j < child.n; j = j + 1 {
      left.keys[left.n] = child.keys[j]
      left.values[left.n] = child.values[j]
      left.n = left.n + 1
    }
    if !left.leaf {
      for c in child.children {
        left.children.push(c)
      }
    }
    left.count = left.count + child.count + 1
    nd.n = nd.n - 1
    ignore(nd.children.remove(i))
  }
}

///|
/// Remove and return the maximum key/value of a subtree, keeping the
/// min-occupancy invariant via fills on the descent. Counts along the
/// descent path are decremented.
fn counted_extract_max(nd : CountedNode) -> (Int, Int) {
  let t = COUNTED_BTREE_MIN_DEGREE
  if nd.leaf {
    let k = nd.keys[nd.n - 1]
    let v = nd.values[nd.n - 1]
    nd.n = nd.n - 1
    nd.count = nd.count - 1
    return (k, v)
  }
  let last = nd.n
  if nd.children[last].n == t - 1 {
    counted_fill_child(nd, last)
  }
  let (k, v) = counted_extract_max(nd.children[nd.n])
  nd.count = nd.count - 1
  (k, v)
}

///|
/// Remove and return the minimum key/value of a subtree.
fn counted_extract_min(nd : CountedNode) -> (Int, Int) {
  let t = COUNTED_BTREE_MIN_DEGREE
  if nd.leaf {
    let k = nd.keys[0]
    let v = nd.values[0]
    for j = 0; j < nd.n - 1; j = j + 1 {
      nd.keys[j] = nd.keys[j + 1]
      nd.values[j] = nd.values[j + 1]
    }
    nd.n = nd.n - 1
    nd.count = nd.count - 1
    return (k, v)
  }
  if nd.children[0].n == t - 1 {
    counted_fill_child(nd, 0)
  }
  let (k, v) = counted_extract_min(nd.children[0])
  nd.count = nd.count - 1
  (k, v)
}

///|
/// Delete `key` from the subtree rooted at `nd`. Returns `true` if the
/// key was found and removed; subtree counts are updated on the way up.
/// After a fill the node is re-searched via a recursive call.
fn counted_delete_from(nd : CountedNode, key : Int) -> Bool {
  let t = COUNTED_BTREE_MIN_DEGREE
  let mut i = 0
  while i < nd.n && key > nd.keys[i] {
    i = i + 1
  }
  let found_here = i < nd.n && key == nd.keys[i]
  if found_here {
    if nd.leaf {
      // Case 2a: key in a leaf — shift out.
      for j = i; j < nd.n - 1; j = j + 1 {
        nd.keys[j] = nd.keys[j + 1]
        nd.values[j] = nd.values[j + 1]
      }
      nd.n = nd.n - 1
      nd.count = nd.count - 1
      return true
    }
    // Case 2: key in an internal node. Replace with predecessor or
    // successor; if both adjacent children are minimal, merge them
    // (with the separator) and continue inside the merged node.
    if nd.children[i].n >= t {
      let (pk, pv) = counted_extract_max(nd.children[i])
      nd.keys[i] = pk
      nd.values[i] = pv
      nd.count = nd.count - 1
      return true
    }
    if nd.children[i + 1].n >= t {
      let (sk, sv) = counted_extract_min(nd.children[i + 1])
      nd.keys[i] = sk
      nd.values[i] = sv
      nd.count = nd.count - 1
      return true
    }
    // Both children minimal: merge right into left over the key.
    let left = nd.children[i]
    let right = nd.children[i + 1]
    left.keys[left.n] = key
    left.values[left.n] = nd.values[i]
    left.n = left.n + 1
    for j = 0; j < right.n; j = j + 1 {
      left.keys[left.n] = right.keys[j]
      left.values[left.n] = right.values[j]
      left.n = left.n + 1
    }
    if !left.leaf {
      for c in right.children {
        left.children.push(c)
      }
    }
    left.count = left.count + right.count + 1
    for j = i; j < nd.n - 1; j = j + 1 {
      nd.keys[j] = nd.keys[j + 1]
      nd.values[j] = nd.values[j + 1]
    }
    ignore(nd.children.remove(i + 1))
    nd.n = nd.n - 1
    // The key now lives inside the merged node; descend into it.
    let removed = counted_delete_from(left, key)
    if removed {
      nd.count = nd.count - 1
    }
    return removed
  }
  if nd.leaf {
    return false
  }
  // Case 3: descend, ensuring the child holds at least t keys first.
  if nd.children[i].n == t - 1 {
    counted_fill_child(nd, i)
    // Fill may have moved keys/children: re-search this node.
    return counted_delete_from(nd, key)
  }
  let child = nd.children[i]
  let removed = counted_delete_from(child, key)
  if removed {
    nd.count = nd.count - 1
  }
  removed
}

///|
/// Verify the internal order-statistic invariant: every node's stored
/// `count` equals the actual number of keys in its subtree, and the
/// root's count equals `size`. Runs in O(n); intended for property
/// testing and debugging.
pub fn CountedBTree::verify_invariants(self : CountedBTree) -> Bool {
  counted_counts_consistent(self.root) && self.root.count == self.size
}

///|
fn counted_counts_consistent(nd : CountedNode) -> Bool {
  let mut total = nd.n
  if !nd.leaf {
    for c in nd.children {
      if !counted_counts_consistent(c) {
        return false
      }
      total = total + c.count
    }
  }
  total == nd.count
}

///|
/// Delete a key. Returns `true` if the key existed and was removed.
pub fn CountedBTree::delete(self : CountedBTree, key : Int) -> Bool {
  let root = self.root
  let removed = counted_delete_from(root, key)
  if removed {
    self.size = self.size - 1
    // Shrink the tree when the root becomes an empty internal node.
    if root.n == 0 && !root.leaf {
      self.root = root.children[0]
    }
  }
  removed
}

///|
/// Collect all key-value pairs in sorted order (in-order traversal).
pub fn CountedBTree::to_array(self : CountedBTree) -> Array[(Int, Int)] {
  let result : Array[(Int, Int)] = []
  counted_inorder(self.root, result)
  result
}

///|
fn counted_inorder(nd : CountedNode, out : Array[(Int, Int)]) -> Unit {
  for i = 0; i < nd.n; i = i + 1 {
    if !nd.leaf {
      counted_inorder(nd.children[i], out)
    }
    out.push((nd.keys[i], nd.values[i]))
  }
  if !nd.leaf {
    counted_inorder(nd.children[nd.n], out)
  }
}
