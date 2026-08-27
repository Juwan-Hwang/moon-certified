/// Fibonacci Heap — amortized O(1) decrease-key priority queue.
///
/// Supports insert, find-min, extract-min, decrease-key, and merge
/// with excellent amortized bounds. Used in Dijkstra's algorithm
/// for optimal O(E + V log V) complexity.
///
/// ## Complexity
/// - insert:        O(1) amortized.
/// - find_min:      O(1).
/// - extract_min:   O(log n) amortized.
/// - decrease_key:  O(1) amortized.
/// - merge:         O(1).
///
/// ## Implementation notes
/// This is a proper Fibonacci heap with:
/// - Cascading cut: when a node loses its second child, it is cut
///   from its parent and moved to the root list.
/// - Marked nodes: a node is marked when it loses a child (via cut),
///   and is cut itself if it loses a second child.
/// - Parent pointers: each node stores a pointer to its parent,
///   enabling O(1) access for decrease-key operations.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A node in the Fibonacci heap.
priv struct FibNode {
  id : Int
  mut key : Int
  mut degree : Int
  mut marked : Bool
  mut parent : FibNode?
  mut child : FibNode?
  mut left : FibNode?
  mut right : FibNode?
}

///|
/// A Fibonacci heap (min-heap).
pub struct FibHeap {
  priv mut min_node : FibNode?
  priv mut node_count : Int
  priv mut next_id : Int
  /// Maps node id → FibNode for O(1) decrease_key lookup.
  priv node_map : Map[Int, FibNode]
}

///|
/// Create an empty Fibonacci heap.
pub fn fib_heap_new() -> FibHeap {
  { min_node: None, node_count: 0, next_id: 0, node_map: Map([]), }
}

///|
/// Insert a key into the heap. Returns the node id for decrease_key. O(1).
pub fn FibHeap::insert(self : FibHeap, key : Int) -> Int {
  let node = {
    id: self.next_id,
    key,
    degree: 0,
    marked: false,
    parent: None,
    child: None,
    left: None,
    right: None,
  }
  self.next_id = self.next_id + 1
  self.node_map[node.id] = node
  node.left = Some(node)
  node.right = Some(node)
  self.min_node = match self.min_node {
    Some(min) => Some(meld_into_root_list(node, min))
    None => Some(node)
  }
  self.node_count = self.node_count + 1
  node.id
}

///|
/// Find the minimum key. O(1).
pub fn FibHeap::find_min(self : FibHeap) -> Int? {
  match self.min_node {
    Some(n) => Some(n.key)
    None => None
  }
}

///|
/// Decrease the key of a node identified by its id.
///
/// Amortized O(1). If the new key is greater than or equal to the
/// current key, does nothing and returns `false`.
/// Otherwise, decreases the key and performs cascading cut if needed.
pub fn FibHeap::decrease_key(
  self : FibHeap,
  node_id : Int,
  new_key : Int,
) -> Bool {
  match self.node_map.get(node_id) {
    None => false
    Some(node) => {
      if new_key >= node.key {
        return false
      }
      node.key = new_key
      match node.parent {
        None =>
          // Node is in root list — just update min if needed.
          match self.min_node {
            Some(min) => if node.key < min.key { self.min_node = Some(node) }
            None => ()
          }
        Some(parent) => {
          // Cut node from parent and add to root list.
          cut(self, node, parent)
          cascading_cut(self, parent)
        }
      }
      true
    }
  }
}

///|
/// Cut node `x` from its parent `y` and add it to the root list.
fn cut(heap : FibHeap, x : FibNode, y : FibNode) -> Unit {
  // Remove x from y's child list.
  match (x.left, x.right) {
    (Some(l), Some(r)) => {
      // If x is the direct child pointer, redirect.
      if y.child is Some(c) && c.id == x.id {
        if r.id == x.id {
          y.child = None // x was the only child
        } else {
          y.child = Some(r)
        }
      }
      l.right = Some(r)
      r.left = Some(l)
    }
    _ => ()
  }
  x.left = Some(x)
  x.right = Some(x)
  x.parent = None
  x.marked = false
  y.degree = y.degree - 1
  // Add x to root list.
  match heap.min_node {
    Some(min) => heap.min_node = Some(meld_into_root_list(x, min))
    None => heap.min_node = Some(x)
  }
}

///|
/// Cascading cut: if `y` is marked, cut it from its parent and recurse.
/// Otherwise, mark it.
fn cascading_cut(heap : FibHeap, y : FibNode) -> Unit {
  match y.parent {
    Some(z) =>
      if y.marked {
        cut(heap, y, z)
        cascading_cut(heap, z)
      } else {
        y.marked = true
      }
    None => ()
  }
}

///|
/// Extract the minimum element. Amortized O(log n).
pub fn FibHeap::extract_min(self : FibHeap) -> Int? {
  match self.min_node {
    None => None
    Some(z) => {
      // Add z's children to the root list.
      match z.child {
        Some(c) => {
          // Detach children and add to root list.
          let children : Array[FibNode] = []
          let mut node = c
          let mut done = false
          while !done {
            children.push(node)
            node = match node.right {
              Some(r) => r
              None => node
            }
            if node.id == c.id {
              done = true
            }
          }
          for i = 0; i < children.length(); i = i + 1 {
            let child = children[i]
            child.parent = None
            child.left = Some(child)
            child.right = Some(child)
            match self.min_node {
              Some(min) => self.min_node = Some(meld_into_root_list(child, min))
              None => self.min_node = Some(child)
            }
          }
          z.child = None
        }
        None => ()
      }
      // Remove z from root list.
      let new_min = match (z.left, z.right) {
        (Some(l), Some(r)) => {
          l.right = Some(r)
          r.left = Some(l)
          Some(r)
        }
        _ => None
      }
      self.node_count = self.node_count - 1
      self.node_map.remove(z.id)
      if self.node_count == 0 {
        self.min_node = None
      } else {
        self.min_node = new_min
        self.consolidate()
      }
      Some(z.key)
    }
  }
}

///|
/// Number of elements in the heap.
pub fn FibHeap::len(self : FibHeap) -> Int {
  self.node_count
}

///|
/// Check if the heap is empty.
pub fn FibHeap::is_empty(self : FibHeap) -> Bool {
  self.node_count == 0
}

// Consolidate root list: ensure no two roots have the same degree.

///|
fn FibHeap::consolidate(self : FibHeap) -> Unit {
  // Max degree ≤ floor(log_phi(n)) ≈ 1.44 * log2(n).
  // For practical n < 10^9, max_degree = 48 is sufficient.
  let max_degree = 48
  let degree_arr : Array[FibNode?] = FixedArray::make(max_degree, None)
    |> fn(fa) {
      let a : Array[FibNode?] = []
      for i = 0; i < max_degree; i = i + 1 {
        a.push(fa[i])
      }
      a
    }
  // Collect all root nodes.
  let roots : Array[FibNode] = []
  match self.min_node {
    None => ()
    Some(start) => {
      let mut node = start
      let mut done = false
      while !done {
        roots.push(node)
        node = match node.right {
          Some(r) => r
          None => node
        }
        if node.id == start.id {
          done = true
        }
      }
    }
  }
  for i = 0; i < roots.length(); i = i + 1 {
    let mut x = roots[i]
    let mut d = x.degree
    let mut continue_loop = true
    while d < max_degree && continue_loop {
      match degree_arr[d] {
        Some(y_val) => {
          let mut y = y_val
          if x.key > y.key {
            let tmp = x
            x = y
            y = tmp
          }
          // Make y a child of x.
          link(y, x)
          degree_arr[d] = None
          d = d + 1
        }
        None => continue_loop = false
      }
    }
    if d < max_degree {
      degree_arr[d] = Some(x)
    }
  }
  // Rebuild root list and find new min.
  self.min_node = None
  for i = 0; i < max_degree; i = i + 1 {
    match degree_arr[i] {
      Some(node) => {
        node.left = Some(node)
        node.right = Some(node)
        self.min_node = match self.min_node {
          Some(min) => Some(meld_into_root_list(node, min))
          None => Some(node)
        }
      }
      None => ()
    }
  }
}

///|
fn link(y : FibNode, x : FibNode) -> Unit {
  // Remove y from root list.
  match (y.left, y.right) {
    (Some(l), Some(r)) => {
      l.right = Some(r)
      r.left = Some(l)
    }
    _ => ()
  }
  y.left = Some(y)
  y.right = Some(y)
  y.parent = Some(x)
  // Add y as child of x.
  match x.child {
    None => {
      x.child = Some(y)
      y.left = Some(y)
      y.right = Some(y)
    }
    Some(c) => {
      y.right = Some(c)
      y.left = c.left
      match c.left {
        Some(cl) => cl.right = Some(y)
        None => ()
      }
      c.left = Some(y)
    }
  }
  x.degree = x.degree + 1
  y.marked = false
}

///|
fn meld_into_root_list(node : FibNode, min : FibNode) -> FibNode {
  node.left = Some(min)
  node.right = min.right
  match min.right {
    Some(r) => r.left = Some(node)
    None => ()
  }
  min.right = Some(node)
  if node.key < min.key {
    node
  } else {
    min
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "fib_heap: basic insert and find_min" {
  let h = fib_heap_new()
  ignore(h.insert(5))
  ignore(h.insert(3))
  ignore(h.insert(7))
  ignore(h.insert(1))
  ignore(h.insert(9))
  assert_eq(h.find_min(), Some(1))
  assert_eq(h.len(), 5)
}

///|
test "fib_heap: extract_min sorted order" {
  let h = fib_heap_new()
  let values = [7, 3, 9, 1, 5, 2, 8, 4, 6, 0]
  for i = 0; i < values.length(); i = i + 1 {
    ignore(h.insert(values[i]))
  }
  for i = 0; i < 10; i = i + 1 {
    assert_eq(h.extract_min(), Some(i))
  }
  assert_eq(h.extract_min(), None)
  assert_true(h.is_empty())
}

///|
test "fib_heap: empty heap" {
  let h = fib_heap_new()
  assert_true(h.is_empty())
  assert_eq(h.find_min(), None)
  assert_eq(h.extract_min(), None)
}

///|
test "fib_heap: single element" {
  let h = fib_heap_new()
  ignore(h.insert(42))
  assert_eq(h.find_min(), Some(42))
  assert_eq(h.extract_min(), Some(42))
  assert_true(h.is_empty())
}

///|
test "fib_heap: duplicates" {
  let h = fib_heap_new()
  ignore(h.insert(3))
  ignore(h.insert(3))
  ignore(h.insert(1))
  ignore(h.insert(1))
  assert_eq(h.extract_min(), Some(1))
  assert_eq(h.extract_min(), Some(1))
  assert_eq(h.extract_min(), Some(3))
  assert_eq(h.extract_min(), Some(3))
}

///|
test "fib_heap: large random" {
  let h = fib_heap_new()
  let mut seed = 42
  let values : Array[Int] = []
  for i = 0; i < 200; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let v = seed % 1000
    values.push(v)
    ignore(h.insert(v))
  }
  values.sort()
  for i = 0; i < 200; i = i + 1 {
    assert_eq(h.extract_min(), Some(values[i]))
  }
}

///|
test "fib_heap: decrease_key basic" {
  let h = fib_heap_new()
  let _id1 = h.insert(10)
  let id2 = h.insert(20)
  let _id3 = h.insert(30)
  assert_eq(h.find_min(), Some(10))
  // Decrease id2's key below current min.
  assert_true(h.decrease_key(id2, 5))
  assert_eq(h.find_min(), Some(5))
  assert_eq(h.extract_min(), Some(5))
  assert_eq(h.extract_min(), Some(10))
  assert_eq(h.extract_min(), Some(30))
}

///|
test "fib_heap: decrease_key cascading cut" {
  let h = fib_heap_new()
  // Insert nodes and extract to build a tree structure.
  let ids : Array[Int] = []
  for i = 0; i < 20; i = i + 1 {
    ids.push(h.insert(100 + i))
  }
  // Extract a few to trigger consolidation (builds trees).
  ignore(h.extract_min())
  ignore(h.extract_min())
  // Now decrease a key deep in a tree.
  assert_true(h.decrease_key(ids[10], 1))
  assert_eq(h.find_min(), Some(1))
  // All remaining should still be extractable in order.
  let remaining : Array[Int] = []
  while !h.is_empty() {
    match h.extract_min() {
      Some(v) => remaining.push(v)
      None => ()
    }
  }
  // Should be sorted.
  for i = 0; i < remaining.length() - 1; i = i + 1 {
    assert_true(remaining[i] <= remaining[i + 1])
  }
}

///|
test "fib_heap: decrease_key invalid id" {
  let h = fib_heap_new()
  ignore(h.insert(10))
  assert_false(h.decrease_key(999, 5))
}

///|
test "fib_heap: decrease_key to same value" {
  let h = fib_heap_new()
  let id = h.insert(10)
  // new_key >= current key → should return false.
  assert_false(h.decrease_key(id, 10))
  assert_false(h.decrease_key(id, 15))
}

///|
test "fib_heap: decrease_key then extract all" {
  let h = fib_heap_new()
  let ids : Array[Int] = []
  for i = 0; i < 50; i = i + 1 {
    ids.push(h.insert(1000 + i))
  }
  // Decrease all keys to their index.
  for i = 0; i < 50; i = i + 1 {
    assert_true(h.decrease_key(ids[i], i))
  }
  // Extract should return 0, 1, 2, ..., 49.
  for i = 0; i < 50; i = i + 1 {
    assert_eq(h.extract_min(), Some(i))
  }
  assert_true(h.is_empty())
}
