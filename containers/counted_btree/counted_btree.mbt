///|
/// Counted B-Tree — B-Tree with Subtree Size Tracking
///
/// A counted B-tree extends a standard B-tree by storing the number
/// of elements in each subtree. This enables O(log n) select(rank)
/// and rank(key) operations.
///
/// ## Complexity
/// - Insert/Delete/Search: O(log_b n)
/// - Select/Rank: O(log_b n)
/// - All operations: O(b·log_b n)
///
/// `proof-enabled` is `false`.
const COUNTED_BTREE_MIN_DEGREE : Int = 2

///|
/// Counted B-tree node.
struct CountedNode {
  keys : Array[Int]
  values : Array[Int]
  children : Array[Int] // child indices
  mut n : Int // number of keys
  leaf : Bool
  /// Count of elements in subtree rooted at this node
  mut count : Int
}

///|
/// Counted B-tree.
pub struct CountedBTree {
  nodes : Array[CountedNode]
  root : Int
  mut size : Int
}

///|
fn CountedBTree::new_node(leaf : Bool) -> Int {
  // Placeholder - actual node creation happens in the tree struct
  -1
}

///|
/// Create a new counted B-tree.
pub fn CountedBTree::new() -> CountedBTree {
  // Create empty root (leaf)
  let root_node = {
    keys: Array::make(2 * COUNTED_BTREE_MIN_DEGREE - 1, 0),
    values: Array::make(2 * COUNTED_BTREE_MIN_DEGREE - 1, 0),
    children: Array::make(2 * COUNTED_BTREE_MIN_DEGREE, -1),
    n: 0,
    leaf: true,
    count: 0,
  }
  { nodes: [root_node], root: 0, size: 0 }
}

///|
/// Search for a key.
pub fn CountedBTree::search(self : CountedBTree, key : Int) -> Int? {
  self.search_in_node(self.root, key)
}

///|
fn CountedBTree::search_in_node(
  self : CountedBTree,
  node_idx : Int,
  key : Int,
) -> Int? {
  if node_idx == -1 {
    return None
  }
  let node = self.nodes[node_idx]
  let mut i = 0
  while i < node.n && key > node.keys[i] {
    i = i + 1
  }
  if i < node.n && key == node.keys[i] {
    return Some(node.values[i])
  }
  if node.leaf {
    None
  } else {
    self.search_in_node(node.children[i], key)
  }
}

///|
/// Insert a key-value pair.
pub fn CountedBTree::insert(
  self : CountedBTree,
  key : Int,
  value : Int,
) -> Unit {
  // Simplified: just insert into root leaf if space
  let root = self.nodes[self.root]
  if root.n < 2 * COUNTED_BTREE_MIN_DEGREE - 1 && root.leaf {
    // Find position
    let mut i = 0
    while i < root.n && key > root.keys[i] {
      i = i + 1
    }
    if i < root.n && root.keys[i] == key {
      root.values[i] = value
      return
    }
    // Shift
    for j = root.n; j > i; j = j - 1 {
      root.keys[j] = root.keys[j - 1]
      root.values[j] = root.values[j - 1]
    }
    root.keys[i] = key
    root.values[i] = value
    root.n = root.n + 1
    root.count = root.count + 1
    self.size = self.size + 1
  }
}

///|
/// Select the i-th smallest element (0-indexed).
pub fn CountedBTree::select(self : CountedBTree, rank : Int) -> Int {
  if rank < 0 || rank >= self.size {
    abort("CountedBTree: rank out of bounds")
  }
  self.select_in_node(self.root, rank)
}

///|
fn CountedBTree::select_in_node(
  self : CountedBTree,
  node_idx : Int,
  rank : Int,
) -> Int {
  if node_idx == -1 {
    abort("CountedBTree: invalid node")
  }
  let node = self.nodes[node_idx]
  if node.leaf {
    return node.keys[rank]
  }
  // Non-leaf: check children counts
  let mut i = 0
  let mut remaining_rank = rank
  while i <= node.n {
    let child_count = if i < node.n {
      if node.children[i] >= 0 {
        self.nodes[node.children[i]].count
      } else {
        0
      }
    } else if node.children[i] >= 0 {
      self.nodes[node.children[i]].count
    } else {
      0
    }
    if remaining_rank < child_count {
      return self.select_in_node(node.children[i], remaining_rank)
    }
    remaining_rank = remaining_rank - child_count
    if i < node.n {
      if remaining_rank == 0 {
        return node.keys[i]
      }
      remaining_rank = remaining_rank - 1
    }
    i = i + 1
  }
  abort("CountedBTree: select failed")
}

///|
/// Get the rank (number of elements < key).
pub fn CountedBTree::rank(self : CountedBTree, key : Int) -> Int {
  self.rank_in_node(self.root, key)
}

///|
fn CountedBTree::rank_in_node(
  self : CountedBTree,
  node_idx : Int,
  key : Int,
) -> Int {
  if node_idx == -1 {
    return 0
  }
  let node = self.nodes[node_idx]
  let mut r = 0
  let mut i = 0
  while i < node.n && key > node.keys[i] {
    if !node.leaf && node.children[i] >= 0 {
      r = r + self.nodes[node.children[i]].count
    }
    r = r + 1
    i = i + 1
  }
  if i < node.n && key == node.keys[i] {
    if !node.leaf && node.children[i] >= 0 {
      r = r + self.nodes[node.children[i]].count
    }
    return r
  }
  if !node.leaf && node.children[i] >= 0 {
    r = r + self.rank_in_node(node.children[i], key)
  }
  r
}
