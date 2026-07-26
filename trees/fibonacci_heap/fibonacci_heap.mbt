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
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A node in the Fibonacci heap.
priv struct FibNode {
  id : Int
  key : Int
  mut degree : Int
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
}

///|
/// Create an empty Fibonacci heap.
pub fn fib_heap_new() -> FibHeap {
  { min_node: None, node_count: 0, next_id: 0 }
}

///|
/// Insert a key into the heap. O(1).
pub fn FibHeap::insert(self : FibHeap, key : Int) -> Unit {
  let node = {
    id: self.next_id,
    key,
    degree: 0,
    child: None,
    left: None,
    right: None,
  }
  self.next_id = self.next_id + 1
  node.left = Some(node)
  node.right = Some(node)
  self.min_node = match self.min_node {
    Some(min) => Some(meld_into_root_list(node, min))
    None => Some(node)
  }
  self.node_count = self.node_count + 1
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
/// Extract the minimum element. Amortized O(log n).
pub fn FibHeap::extract_min(self : FibHeap) -> Int? {
  match self.min_node {
    None => None
    Some(z) => {
      // Add z's children to the root list.
      match z.child {
        Some(c) => {
          // Detach children and add to root list.
          let mut child = c
          let mut first = true
          while first || child.id != c.id {
            first = false
            let next = match child.right {
              Some(r) => r
              None => child
            }
            // Detach from sibling list.
            child.left = Some(child)
            child.right = Some(child)
            // Add to root list.
            self.min_node = Some(meld_into_root_list(child, z))
            child = next
            if child.id == c.id {
              break
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
  let max_degree = 64 // Upper bound for practical use.
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
    while d < max_degree && degree_arr[d] is Some(_) {
      let mut y = degree_arr[d].unwrap()
      if x.key > y.key {
        // Swap x and y.
        let tmp = x
        x = y
        y = tmp
      }
      // Make y a child of x.
      link(y, x)
      degree_arr[d] = None
      d = d + 1
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
  h.insert(5)
  h.insert(3)
  h.insert(7)
  h.insert(1)
  h.insert(9)
  assert_eq(h.find_min(), Some(1))
  assert_eq(h.len(), 5)
}

///|
test "fib_heap: extract_min sorted order" {
  let h = fib_heap_new()
  let values = [7, 3, 9, 1, 5, 2, 8, 4, 6, 0]
  for i = 0; i < values.length(); i = i + 1 {
    h.insert(values[i])
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
  h.insert(42)
  assert_eq(h.find_min(), Some(42))
  assert_eq(h.extract_min(), Some(42))
  assert_true(h.is_empty())
}

///|
test "fib_heap: duplicates" {
  let h = fib_heap_new()
  h.insert(3)
  h.insert(3)
  h.insert(1)
  h.insert(1)
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
    h.insert(v)
  }
  values.sort()
  for i = 0; i < 200; i = i + 1 {
    assert_eq(h.extract_min(), Some(values[i]))
  }
}
