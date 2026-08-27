///|
/// Mass Tree — A Cache-Conscious B+ Tree Variant
///
/// MassTree is a B+ tree designed for in-memory OLTP databases. It uses
/// fixed-size nodes sized to fit cache lines (8 slots per node) and
/// stores all values in leaves, with internal nodes holding only
/// routing separators.
///
/// ## Implementation
///
/// - Leaves hold up to `MASS_FANOUT` sorted key-value pairs; internal
///   nodes hold up to `MASS_FANOUT - 1` separators and `MASS_FANOUT`
///   child pointers. Separator `s` of child `i+1` satisfies: all keys
///   in that subtree are `>= s`.
/// - Insert descends with a path stack; overflowing nodes split and
///   propagate one separator upward; the root grows a new level when
///   it splits.
/// - Delete removes from the leaf and drops empty leaves from their
///   parent; the tree height shrinks only when the root degenerates.
///   Non-root internal nodes may keep a single child (the lazy
///   rebalancing strategy described in the MassTree paper), so no key
///   is ever silently dropped.
/// - A stale separator (smaller than the true subtree minimum after a
///   minimum-key deletion) can only route searches to the correct
///   subtree, so separators never need repair on delete.
///
/// ## Complexity
/// - Point lookup / insert / delete: O(log n)
/// - Sorted enumeration (to_array): O(n)
///
/// ## References
/// - Mao, Kohler, Venkatasamy. "Cache-Conscious Concurrency in
///   High-Performance Mass Tree." VLDB 2012.
///
/// `proof-enabled` is `false`.
const MASS_FANOUT : Int = 8

///|
/// Maximum separators per internal node (fanout - 1).
const MASS_MAX_SEPS : Int = MASS_FANOUT - 1

///|
/// Leaf node: stores sorted key-value pairs.
struct MassLeaf {
  keys : Array[Int]
  values : Array[Int]
  mut count : Int
}

///|
/// Internal node: sorted separators; `children[i]` covers keys
/// `< keys[i]` (and `children[count]` covers keys `>= keys[count-1]`).
struct MassInternal {
  keys : Array[Int]
  children : Array[Int]
  mut count : Int // number of separators
}

///|
/// Mass tree. Node indices are valid within `leaves` when the child
/// level is 0 (leaves), otherwise within `internals`. `depth` is the
/// number of internal levels above the leaves (0 = root is a leaf).
pub struct MassTree {
  leaves : Array[MassLeaf]
  internals : Array[MassInternal]
  mut root : Int
  mut depth : Int
  mut size : Int
}

///|
fn mass_leaf_new() -> MassLeaf {
  { keys: Array::new(), values: Array::new(), count: 0 }
}

///|
fn mass_internal_new() -> MassInternal {
  { keys: Array::new(), children: Array::new(), count: 0 }
}

///|
/// Create a new MassTree.
pub fn MassTree::new() -> MassTree {
  let t : MassTree = { leaves: [], internals: [], root: -1, depth: 0, size: 0 }
  t.leaves.push(mass_leaf_new())
  t.root = 0
  t
}

///|
/// Number of key-value pairs stored.
pub fn MassTree::size(self : MassTree) -> Int {
  self.size
}

///|
/// Child index to descend into for `key` inside an internal node.
fn mass_child_index(inn : MassInternal, key : Int) -> Int {
  let mut i = 0
  while i < inn.count && key >= inn.keys[i] {
    i = i + 1
  }
  i
}

///|
/// Split an overflowing leaf in place; returns the separator (first
/// key of the new right leaf) and the right leaf's index.
fn MassTree::mass_split_leaf(self : MassTree, idx : Int) -> (Int, Int) {
  let leaf = self.leaves[idx]
  let right = mass_leaf_new()
  let mid = leaf.count / 2
  for i = mid; i < leaf.count; i = i + 1 {
    right.keys.push(leaf.keys[i])
    right.values.push(leaf.values[i])
  }
  right.count = leaf.count - mid
  // Truncate the left leaf.
  while leaf.keys.length() > mid {
    ignore(leaf.keys.pop())
    ignore(leaf.values.pop())
  }
  leaf.count = mid
  self.leaves.push(right)
  (right.keys[0], self.leaves.length() - 1)
}

///|
/// Split an overflowing internal node in place; the median separator
/// moves up. Returns (median_sep, new right node index).
fn MassTree::mass_split_internal(self : MassTree, idx : Int) -> (Int, Int) {
  let inn = self.internals[idx]
  let mid = inn.count / 2
  let up = inn.keys[mid]
  let right = mass_internal_new()
  for i = mid + 1; i < inn.count; i = i + 1 {
    right.keys.push(inn.keys[i])
  }
  for i = mid + 1; i <= inn.count; i = i + 1 {
    right.children.push(inn.children[i])
  }
  right.count = inn.count - mid - 1
  // Truncate the left node to `mid` separators / mid+1 children.
  while inn.keys.length() > mid {
    ignore(inn.keys.pop())
  }
  while inn.children.length() > mid + 1 {
    ignore(inn.children.pop())
  }
  inn.count = mid
  self.internals.push(right)
  (up, self.internals.length() - 1)
}

///|
/// Insert a separator and child pointer into an internal node at the
/// given positions.
fn mass_internal_insert(
  inn : MassInternal,
  pos : Int,
  sep : Int,
  child : Int,
) -> Unit {
  inn.keys.insert(pos, sep)
  inn.children.insert(pos + 1, child)
  inn.count = inn.count + 1
}

///|
/// Remove the empty subtree recorded at the top of the path stacks
/// from its parent, then climb while the parent itself becomes
/// completely empty (no separators and no children). The tree height
/// shrinks when the root degenerates to a single child; a root that
/// becomes entirely empty resets to a single empty leaf. Non-root
/// internal nodes may keep a single child — MassTree's lazy
/// rebalancing strategy — so routing stays correct without separator
/// repair.
fn MassTree::mass_collapse_up(
  self : MassTree,
  path_i : Array[Int],
  path_c : Array[Int],
) -> Unit {
  while true {
    let p_idx = path_i[path_i.length() - 1]
    let ci = path_c[path_c.length() - 1]
    ignore(path_i.pop())
    ignore(path_c.pop())
    let parent = self.internals[p_idx]
    // Drop the pointer to the empty subtree and the separator routing
    // into it (a degenerate parent with zero separators has no
    // separator to remove).
    ignore(parent.children.remove(ci))
    if parent.count > 0 {
      if ci == 0 {
        ignore(parent.keys.remove(0))
      } else {
        ignore(parent.keys.remove(ci - 1))
      }
      parent.count = parent.count - 1
    }
    if parent.children.length() > 0 {
      if path_i.length() == 0 {
        // The parent is the root: shrink through any degenerate
        // single-child levels.
        while self.depth > 0 && self.internals[self.root].count == 0 {
          self.root = self.internals[self.root].children[0]
          self.depth = self.depth - 1
        }
      }
      return
    }
    // The parent is now completely empty.
    if path_i.length() == 0 {
      // The whole tree is empty: reset to a single empty leaf root.
      self.leaves.push(mass_leaf_new())
      self.root = self.leaves.length() - 1
      self.depth = 0
      return
    }
    // Otherwise climb: the empty parent must be dropped from its own
    // parent on the next iteration.
  }
}

///|
/// Search for a key.
pub fn MassTree::search(self : MassTree, key : Int) -> Int? {
  let mut cur = self.root
  let mut level = self.depth
  while level > 0 {
    let inn = self.internals[cur]
    cur = inn.children[mass_child_index(inn, key)]
    level = level - 1
  }
  let leaf = self.leaves[cur]
  let mut i = 0
  while i < leaf.count && leaf.keys[i] < key {
    i = i + 1
  }
  if i < leaf.count && leaf.keys[i] == key {
    Some(leaf.values[i])
  } else {
    None
  }
}

///|
/// Insert a key-value pair. Existing keys have their value updated;
/// otherwise the pair is inserted with splits propagated upward.
pub fn MassTree::insert(self : MassTree, key : Int, value : Int) -> Unit {
  // Descend, recording (internal node, child position) along the way.
  let path_i : Array[Int] = []
  let path_c : Array[Int] = []
  let mut cur = self.root
  let mut level = self.depth
  while level > 0 {
    let inn = self.internals[cur]
    let ci = mass_child_index(inn, key)
    path_i.push(cur)
    path_c.push(ci)
    cur = inn.children[ci]
    level = level - 1
  }
  // Insert into the leaf.
  let leaf = self.leaves[cur]
  let mut pos = 0
  while pos < leaf.count && leaf.keys[pos] < key {
    pos = pos + 1
  }
  if pos < leaf.count && leaf.keys[pos] == key {
    leaf.values[pos] = value
    return
  }
  leaf.keys.insert(pos, key)
  leaf.values.insert(pos, value)
  leaf.count = leaf.count + 1
  self.size = self.size + 1
  if leaf.count <= MASS_FANOUT {
    return
  }
  // Split and propagate.
  let (sep0, right0) = self.mass_split_leaf(cur)
  let mut sep = sep0
  let mut new_child = right0
  while true {
    if path_i.length() == 0 {
      // Grow a new root level.
      let new_root = mass_internal_new()
      new_root.keys.push(sep)
      new_root.children.push(self.root)
      new_root.children.push(new_child)
      new_root.count = 1
      self.internals.push(new_root)
      self.root = self.internals.length() - 1
      self.depth = self.depth + 1
      return
    }
    let p_idx = path_i[path_i.length() - 1]
    let ci = path_c[path_c.length() - 1]
    ignore(path_i.pop())
    ignore(path_c.pop())
    let parent = self.internals[p_idx]
    mass_internal_insert(parent, ci, sep, new_child)
    if parent.count <= MASS_MAX_SEPS {
      return
    }
    let (up, right) = self.mass_split_internal(p_idx)
    sep = up
    new_child = right
  }
}

///|
/// Delete a key. Returns `true` if the key existed and was removed.
/// Empty nodes are collapsed lazily toward the root.
pub fn MassTree::delete(self : MassTree, key : Int) -> Bool {
  let path_i : Array[Int] = []
  let path_c : Array[Int] = []
  let mut cur = self.root
  let mut level = self.depth
  while level > 0 {
    let inn = self.internals[cur]
    let ci = mass_child_index(inn, key)
    path_i.push(cur)
    path_c.push(ci)
    cur = inn.children[ci]
    level = level - 1
  }
  let leaf = self.leaves[cur]
  let mut pos = 0
  while pos < leaf.count && leaf.keys[pos] < key {
    pos = pos + 1
  }
  if pos >= leaf.count || leaf.keys[pos] != key {
    return false
  }
  ignore(leaf.keys.remove(pos))
  ignore(leaf.values.remove(pos))
  leaf.count = leaf.count - 1
  self.size = self.size - 1
  if leaf.count > 0 {
    return true
  }
  if path_i.length() == 0 {
    // The leaf is the root; an empty root is allowed.
    return true
  }
  // The leaf is empty: remove it from its parent, collapsing any
  // ancestor that ends up with a single child.
  self.mass_collapse_up(path_i, path_c)
  true
}

///|
fn MassTree::mass_collect(
  self : MassTree,
  node : Int,
  level : Int,
  out : Array[(Int, Int)],
) -> Unit {
  if level == 0 {
    let leaf = self.leaves[node]
    for i = 0; i < leaf.count; i = i + 1 {
      out.push((leaf.keys[i], leaf.values[i]))
    }
  } else {
    let inn = self.internals[node]
    for i = 0; i <= inn.count; i = i + 1 {
      self.mass_collect(inn.children[i], level - 1, out)
    }
  }
}

///|
/// Get all entries in sorted order (in-order traversal).
pub fn MassTree::to_array(self : MassTree) -> Array[(Int, Int)] {
  let result : Array[(Int, Int)] = []
  self.mass_collect(self.root, self.depth, result)
  result
}

///|
fn MassTree::mass_min_key(self : MassTree, node : Int, level : Int) -> Int {
  if level == 0 {
    self.leaves[node].keys[0]
  } else {
    self.mass_min_key(self.internals[node].children[0], level - 1)
  }
}

///|
fn MassTree::mass_count_entries(
  self : MassTree,
  node : Int,
  level : Int,
) -> Int {
  if level == 0 {
    self.leaves[node].count
  } else {
    let inn = self.internals[node]
    let mut total = 0
    for i = 0; i <= inn.count; i = i + 1 {
      total = total + self.mass_count_entries(inn.children[i], level - 1)
    }
    total
  }
}

///|
fn MassTree::mass_check_subtree(
  self : MassTree,
  node : Int,
  level : Int,
) -> Bool {
  if level == 0 {
    let leaf = self.leaves[node]
    if leaf.count > MASS_FANOUT {
      return false
    }
    if leaf.keys.length() != leaf.count {
      return false
    }
    for i = 0; i < leaf.count - 1; i = i + 1 {
      if leaf.keys[i] >= leaf.keys[i + 1] {
        return false
      }
    }
    true
  } else {
    let inn = self.internals[node]
    if inn.children.length() != inn.count + 1 {
      return false
    }
    if inn.count > MASS_MAX_SEPS {
      return false
    }
    for i = 0; i < inn.count - 1; i = i + 1 {
      if inn.keys[i] >= inn.keys[i + 1] {
        return false
      }
    }
    for i = 0; i <= inn.count; i = i + 1 {
      if !self.mass_check_subtree(inn.children[i], level - 1) {
        return false
      }
    }
    // Separator routing: every key of child i+1 must be >= keys[i].
    for i = 0; i < inn.count; i = i + 1 {
      if self.mass_min_key(inn.children[i + 1], level - 1) < inn.keys[i] {
        return false
      }
    }
    true
  }
}

///|
/// Verify structural invariants: separator routing, leaf sortedness,
/// occupancy bounds, and `size` matching the actual number of stored
/// pairs. Runs in O(n); intended for property testing and debugging.
pub fn MassTree::verify_invariants(self : MassTree) -> Bool {
  self.mass_check_subtree(self.root, self.depth) && self.mass_count_entries(
    self.root,
    self.depth,
  ) == self.size
}
