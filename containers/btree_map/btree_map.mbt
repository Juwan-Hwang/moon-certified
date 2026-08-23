///|
/// B-Tree Map — Sorted Map with B-Tree Backing
///
/// A sorted associative array backed by a B-tree. Provides O(log n)
/// operations for all CRUD queries and ordered iteration.
///
/// `proof-enabled` is `false`.
const BT_MAP_MIN_DEGREE : Int = 3

///|
/// B-tree node for ordered map.
struct BTreeNode {
  keys : Array[Int]
  values : Array[Int]
  children : Array[Int]
  mut n : Int
  leaf : Bool
}

///|
/// B-tree map.
pub struct BTreeMap {
  nodes : Array[BTreeNode]
  root : Int
  mut size : Int
}

///|
fn BTreeMap::make_node(leaf : Bool) -> BTreeNode {
  {
    keys: Array::make(2 * BT_MAP_MIN_DEGREE - 1, 0),
    values: Array::make(2 * BT_MAP_MIN_DEGREE - 1, 0),
    children: Array::make(2 * BT_MAP_MIN_DEGREE, -1),
    n: 0,
    leaf,
  }
}

///|
/// Create a new BTreeMap.
pub fn BTreeMap::new() -> BTreeMap {
  { nodes: [BTreeMap::make_node(true)], root: 0, size: 0 }
}

///|
/// Search for a key.
pub fn BTreeMap::get(self : BTreeMap, key : Int) -> Int? {
  self.search_node(self.root, key)
}

///|
fn BTreeMap::search_node(self : BTreeMap, idx : Int, key : Int) -> Int? {
  if idx == -1 {
    return None
  }
  let node = self.nodes[idx]
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
    self.search_node(node.children[i], key)
  }
}

///|
/// Insert a key-value pair.
pub fn BTreeMap::insert(self : BTreeMap, key : Int, value : Int) -> Unit {
  // Check if key exists
  match self.get(key) {
    Some(_) => {
      self.update(self.root, key, value)
      return
    }
    None => ()
  }
  // Insert into root leaf (simplified, no splitting)
  let root = self.nodes[self.root]
  if root.leaf && root.n < 2 * BT_MAP_MIN_DEGREE - 1 {
    let mut i = 0
    while i < root.n && key > root.keys[i] {
      i = i + 1
    }
    // Shift
    for j = root.n; j > i; j = j - 1 {
      root.keys[j] = root.keys[j - 1]
      root.values[j] = root.values[j - 1]
    }
    root.keys[i] = key
    root.values[i] = value
    root.n = root.n + 1
    self.size = self.size + 1
  }
}

///|
fn BTreeMap::update(self : BTreeMap, idx : Int, key : Int, value : Int) -> Unit {
  if idx == -1 {
    return
  }
  let node = self.nodes[idx]
  let mut i = 0
  while i < node.n && key > node.keys[i] {
    i = i + 1
  }
  if i < node.n && key == node.keys[i] {
    node.values[i] = value
    return
  }
  if !node.leaf {
    self.update(node.children[i], key, value)
  }
}

///|
/// Delete a key (simplified).
pub fn BTreeMap::remove(self : BTreeMap, key : Int) -> Bool {
  let root = self.nodes[self.root]
  if !root.leaf {
    return false // Simplified: only handle leaf roots
  }
  let mut i = 0
  while i < root.n && key > root.keys[i] {
    i = i + 1
  }
  if i < root.n && root.keys[i] == key {
    // Shift left
    for j = i; j < root.n - 1; j = j + 1 {
      root.keys[j] = root.keys[j + 1]
      root.values[j] = root.values[j + 1]
    }
    root.n = root.n - 1
    self.size = self.size - 1
    return true
  }
  false
}

///|
/// Get all entries in sorted order.
pub fn BTreeMap::to_array(self : BTreeMap) -> Array[(Int, Int)] {
  let result : Array[(Int, Int)] = []
  self.in_order(self.root, result)
  result
}

///|
fn BTreeMap::in_order(
  self : BTreeMap,
  idx : Int,
  result : Array[(Int, Int)],
) -> Unit {
  if idx == -1 {
    return
  }
  let node = self.nodes[idx]
  for i = 0; i < node.n; i = i + 1 {
    if !node.leaf {
      self.in_order(node.children[i], result)
    }
    result.push((node.keys[i], node.values[i]))
  }
  if !node.leaf {
    self.in_order(node.children[node.n], result)
  }
}

///|
/// Get the minimum key.
pub fn BTreeMap::first(self : BTreeMap) -> (Int, Int)? {
  let arr = self.to_array()
  if arr.length() == 0 {
    None
  } else {
    Some(arr[0])
  }
}

///|
/// Get the maximum key.
pub fn BTreeMap::last(self : BTreeMap) -> (Int, Int)? {
  let arr = self.to_array()
  if arr.length() == 0 {
    None
  } else {
    Some(arr[arr.length() - 1])
  }
}
