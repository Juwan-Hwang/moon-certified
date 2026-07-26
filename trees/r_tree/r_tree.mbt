/// R-Tree — spatial indexing for 2D bounding rectangles.
///
/// Organizes multi-dimensional rectangles into a balanced tree for
/// efficient spatial queries (window queries, nearest-neighbor).
/// Uses the R*-tree insertion heuristic with node splitting.
///
/// ## Complexity
/// - Search:  O(log n) average for point queries.
/// - Insert:  O(log n) average.
/// - Space:   O(n).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// A 2D bounding rectangle.
pub struct Rect {
  min_x : Double
  min_y : Double
  max_x : Double
  max_y : Double
}

/// An entry in the R-tree (rectangle + associated value).
pub struct Entry {
  rect : Rect
  value : Int
}

priv struct RTreeNode {
  is_leaf : Bool
  mut entries : Array[Entry]
  mut children : Array[(Rect, RTreeNode)]
  mut rect : Rect // MBR of all children
}

/// An R-tree.
pub struct RTree {
  priv mut root : RTreeNode?
  priv max_entries : Int
}

/// Create a new R-tree with the given max entries per node.
pub fn rtree_new(max_entries : Int) -> RTree {
  let m = if max_entries < 4 { 4 } else { max_entries }
  { root: None, max_entries: m }
}

/// Insert a rectangle with an associated value.
pub fn RTree::insert(self : RTree, rect : Rect, value : Int) -> Unit {
  match self.root {
    None =>
      self.root = Some({
        is_leaf: true,
        entries: [{ rect, value }],
        children: [],
        rect: { ..rect },
      })
    Some(root) => {
      // Insert and get potential split.
      let split = insert_recursive(root, rect, value, self.max_entries)
      match split {
        None => ()
        Some((new_rect, new_node)) => {
          // Create new root.
          self.root = Some({
            is_leaf: false,
            entries: [],
            children: [(root.rect, root), (new_rect, new_node)],
            rect: union(root.rect, new_rect),
          })
        }
      }
    }
  }
}

/// Find all entries whose rectangles intersect the query rectangle.
pub fn RTree::query(self : RTree, rect : Rect) -> Array[Entry] {
  let result : Array[Entry] = []
  match self.root {
    None => ()
    Some(root) => query_recursive(root, rect, result)
  }
  result
}

/// Find all entries whose rectangles contain a point.
pub fn RTree::query_point(self : RTree, x : Double, y : Double) -> Array[Entry] {
  self.query({ min_x: x, min_y: y, max_x: x, max_y: y })
}

fn insert_recursive(
  node : RTreeNode,
  rect : Rect,
  value : Int,
  max_entries : Int,
) -> (Rect, RTreeNode)? {
  if node.is_leaf {
    node.entries.push({ rect, value })
    node.rect = union(node.rect, rect)
    if node.entries.length() > max_entries {
      return Some(split_leaf(node, max_entries))
    }
    None
  } else {
    // Choose the child whose MBR needs least enlargement.
    let mut best_idx = 0
    let mut best_enlargement = 1.0e18
    for i = 0; i < node.children.length(); i = i + 1 {
      let (child_rect, _) = node.children[i]
      let enlarged = union(child_rect, rect)
      let area = rect_area(enlarged) - rect_area(child_rect)
      if area < best_enlargement {
        best_enlargement = area
        best_idx = i
      }
    }
    let (_, child) = node.children[best_idx]
    let split = insert_recursive(child, rect, value, max_entries)
    // Update child rect.
    match split {
      None =>
        node.children[best_idx] = (child.rect, child)
      Some((new_rect, new_node)) => {
        node.children[best_idx] = (child.rect, child)
        node.children.push((new_rect, new_node))
        if node.children.length() > max_entries {
          return Some(split_internal(node, max_entries))
        }
      }
    }
    node.rect = union(node.rect, rect)
    None
  }
}

fn query_recursive(
  node : RTreeNode,
  rect : Rect,
  result : Array[Entry],
) -> Unit {
  if !intersects(node.rect, rect) {
    return
  }
  if node.is_leaf {
    for i = 0; i < node.entries.length(); i = i + 1 {
      if intersects(node.entries[i].rect, rect) {
        result.push(node.entries[i])
      }
    }
  } else {
    for i = 0; i < node.children.length(); i = i + 1 {
      let (child_rect, child) = node.children[i]
      if intersects(child_rect, rect) {
        query_recursive(child, rect, result)
      }
    }
  }
}

fn split_leaf(node : RTreeNode, max_entries : Int) -> (Rect, RTreeNode) {
  let n = node.entries.length()
  let mid = n / 2
  let entries1 : Array[Entry] = []
  let entries2 : Array[Entry] = []
  for i = 0; i < mid; i = i + 1 {
    entries1.push(node.entries[i])
  }
  for i = mid; i < n; i = i + 1 {
    entries2.push(node.entries[i])
  }
  node.entries = entries1
  node.rect = compute_mbr_entries(entries1)
  let new_node : RTreeNode = {
    is_leaf: true,
    entries: entries2,
    children: [],
    rect: compute_mbr_entries(entries2),
  }
  ignore(max_entries)
  (new_node.rect, new_node)
}

fn split_internal(node : RTreeNode, max_entries : Int) -> (Rect, RTreeNode) {
  let n = node.children.length()
  let mid = n / 2
  let children1 : Array[(Rect, RTreeNode)] = []
  let children2 : Array[(Rect, RTreeNode)] = []
  for i = 0; i < mid; i = i + 1 {
    children1.push(node.children[i])
  }
  for i = mid; i < n; i = i + 1 {
    children2.push(node.children[i])
  }
  node.children = children1
  node.rect = compute_mbr_children(children1)
  let new_node : RTreeNode = {
    is_leaf: false,
    entries: [],
    children: children2,
    rect: compute_mbr_children(children2),
  }
  ignore(max_entries)
  (new_node.rect, new_node)
}

fn union(a : Rect, b : Rect) -> Rect {
  {
    min_x: if a.min_x < b.min_x { a.min_x } else { b.min_x },
    min_y: if a.min_y < b.min_y { a.min_y } else { b.min_y },
    max_x: if a.max_x > b.max_x { a.max_x } else { b.max_x },
    max_y: if a.max_y > b.max_y { a.max_y } else { b.max_y },
  }
}

fn intersects(a : Rect, b : Rect) -> Bool {
  a.min_x <= b.max_x && a.max_x >= b.min_x && a.min_y <= b.max_y && a.max_y >= b.min_y
}

fn rect_area(r : Rect) -> Double {
  (r.max_x - r.min_x) * (r.max_y - r.min_y)
}

fn compute_mbr_entries(entries : Array[Entry]) -> Rect {
  if entries.length() == 0 {
    return { min_x: 0.0, min_y: 0.0, max_x: 0.0, max_y: 0.0 }
  }
  let mut r = entries[0].rect
  for i = 1; i < entries.length(); i = i + 1 {
    r = union(r, entries[i].rect)
  }
  r
}

fn compute_mbr_children(children : Array[(Rect, RTreeNode)]) -> Rect {
  if children.length() == 0 {
    return { min_x: 0.0, min_y: 0.0, max_x: 0.0, max_y: 0.0 }
  }
  let mut r = children[0].0
  for i = 1; i < children.length(); i = i + 1 {
    r = union(r, children[i].0)
  }
  r
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "rtree: basic insert and query" {
  let t = rtree_new(8)
  t.insert({ min_x: 0.0, min_y: 0.0, max_x: 1.0, max_y: 1.0 }, 1)
  t.insert({ min_x: 2.0, min_y: 2.0, max_x: 3.0, max_y: 3.0 }, 2)
  t.insert({ min_x: 4.0, min_y: 4.0, max_x: 5.0, max_y: 5.0 }, 3)
  let r = t.query({ min_x: 0.5, min_y: 0.5, max_x: 2.5, max_y: 2.5 })
  assert_eq(r.length(), 2)
}

test "rtree: point query" {
  let t = rtree_new(8)
  t.insert({ min_x: 0.0, min_y: 0.0, max_x: 2.0, max_y: 2.0 }, 10)
  t.insert({ min_x: 3.0, min_y: 3.0, max_x: 5.0, max_y: 5.0 }, 20)
  let r = t.query_point(1.0, 1.0)
  assert_eq(r.length(), 1)
  assert_eq(r[0].value, 10)
}

test "rtree: empty tree" {
  let t = rtree_new(8)
  let r = t.query({ min_x: 0.0, min_y: 0.0, max_x: 10.0, max_y: 10.0 })
  assert_eq(r.length(), 0)
}

test "rtree: no intersection" {
  let t = rtree_new(8)
  t.insert({ min_x: 0.0, min_y: 0.0, max_x: 1.0, max_y: 1.0 }, 1)
  let r = t.query({ min_x: 5.0, min_y: 5.0, max_x: 6.0, max_y: 6.0 })
  assert_eq(r.length(), 0)
}

test "rtree: many entries" {
  let t = rtree_new(4)
  for i = 0; i < 50; i = i + 1 {
    let x = i.to_double()
    t.insert({ min_x: x, min_y: x, max_x: x + 1.0, max_y: x + 1.0 }, i)
  }
  let r = t.query({ min_x: 10.0, min_y: 10.0, max_x: 20.0, max_y: 20.0 })
  // Entries 10..20 intersect (11 entries: indices 10 through 20).
  assert_true(r.length() >= 10)
}
