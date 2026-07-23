/// Kruskal's Minimum Spanning Tree algorithm.
///
/// Builds a minimum-weight spanning forest of an undirected graph by greedily
/// adding edges in order of increasing weight, skipping any edge whose
/// endpoints already belong to the same connected component. Cycle detection
/// is delegated to the Union-Find data structure from `containers/union_find`.
///
/// Edges are sorted with O(E log E) merge sort.
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// A weighted undirected edge between vertex `from` and vertex `to`.
///
/// The type is `pub` so callers in other packages can read `.from`, `.to` and
/// `.weight` from the edges returned by `kruskal_mst`. To construct an edge,
/// use the [`edge`] constructor — the fields are not directly constructible
/// outside this package.
pub struct Edge {
  from : Int
  to : Int
  weight : Int
}

/// Construct an [`Edge`]. This is the canonical way for external callers to
/// create edges.
pub fn edge(from : Int, to : Int, weight : Int) -> Edge {
  { from, to, weight }
}

/// Merge sort for edges by ascending weight. O(E log E).
/// Uses a temporary buffer for merging.
fn sort_edges(edges : FixedArray[Edge]) -> Unit {
  let n = edges.length()
  if n <= 1 {
    return
  }
  let buf = FixedArray::make(n, edge(0, 0, 0))
  merge_sort_edges(edges, buf, 0, n)
}

fn merge_sort_edges(
  edges : FixedArray[Edge],
  buf : FixedArray[Edge],
  lo : Int,
  hi : Int,
) -> Unit {
  if hi - lo <= 1 {
    return
  }
  let mid = lo + (hi - lo) / 2
  merge_sort_edges(edges, buf, lo, mid)
  merge_sort_edges(edges, buf, mid, hi)
  merge_edges(edges, buf, lo, mid, hi)
}

fn merge_edges(
  edges : FixedArray[Edge],
  buf : FixedArray[Edge],
  lo : Int,
  mid : Int,
  hi : Int,
) -> Unit {
  let mut i = lo
  let mut j = mid
  let mut k = lo
  while i < mid && j < hi {
    if edges[i].weight <= edges[j].weight {
      buf[k] = edges[i]
      i = i + 1
    } else {
      buf[k] = edges[j]
      j = j + 1
    }
    k = k + 1
  }
  while i < mid {
    buf[k] = edges[i]
    i = i + 1
    k = k + 1
  }
  while j < hi {
    buf[k] = edges[j]
    j = j + 1
    k = k + 1
  }
  let mut m = lo
  while m < hi {
    edges[m] = buf[m]
    m = m + 1
  }
}

/// Compute the Minimum Spanning Tree (forest) of an undirected graph.
///
/// # Parameters
/// - `edges`: the weighted undirected edges of the graph. The input array is
///   not modified; a copy is sorted internally.
/// - `n`: the number of vertices, indexed `0 .. n - 1`. Edges whose endpoints
///   fall outside this range are silently ignored.
///
/// # Returns
/// `(mst_edges, total_weight)` where `mst_edges` are the selected edges and
/// `total_weight` is their summed weight. For a connected graph the result has
/// exactly `n - 1` edges; for a disconnected graph it is a spanning forest with
/// one tree per component (fewer than `n - 1` edges). Returns an empty array
/// and weight `0` when `n <= 0` or there are no edges.
pub fn kruskal_mst(
  edges : FixedArray[Edge],
  n : Int,
) -> (FixedArray[Edge], Int) {
  if n <= 0 || edges.length() == 0 {
    return (FixedArray::make(0, edge(0, 0, 0)), 0)
  }
  // Sort a copy so the caller's array is left untouched.
  let sorted = FixedArray::makei(edges.length(), fn(i) { edges[i] })
  sort_edges(sorted)
  let uf = @union_find.new(n)
  // A spanning forest on n vertices never needs more than n - 1 edges.
  let selected = FixedArray::make(n - 1, edge(0, 0, 0))
  let mut count = 0
  let mut total = 0
  for i = 0; i < sorted.length(); i = i + 1 {
    let e = sorted[i]
    // `union` returns true exactly when the endpoints were in different
    // components, i.e. the edge does not close a cycle. Once n - 1 edges
    // have been added every vertex is connected, so no further edge can
    // succeed and `count` never exceeds n - 1.
    if @union_find.union(uf, e.from, e.to) {
      selected[count] = e
      count = count + 1
      total = total + e.weight
    }
  }
  // Trim to the exact number of edges selected (matters for forests).
  let mst = FixedArray::makei(count, fn(i) { selected[i] })
  (mst, total)
}

/// Convenience wrapper around [`kruskal_mst`] that returns only the total
/// weight of the minimum spanning forest.
pub fn mst_weight(edges : FixedArray[Edge], n : Int) -> Int {
  let (_, w) = kruskal_mst(edges, n)
  w
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "kruskal: simple connected graph (triangle)" {
  // 0--1 (1)
  // |  /
  // 2      (1-2: 2, 0-2: 3)
  // Edges: 0-1(1), 1-2(2), 0-2(3). MST = {0-1, 1-2}, weight 3.
  let edges = FixedArray::make(3, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(1, 2, 2)
  edges[2] = edge(0, 2, 3)
  let (mst, w) = kruskal_mst(edges, 3)
  assert_eq(mst.length(), 2)
  assert_eq(w, 3)
}

test "kruskal: disconnected graph yields a forest" {
  // Two components: {0,1} and {2,3}. 4 nodes but only 2 MST edges.
  let edges = FixedArray::make(2, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(2, 3, 2)
  let (mst, w) = kruskal_mst(edges, 4)
  assert_eq(mst.length(), 2)
  assert_eq(w, 3)
}

test "kruskal: single edge" {
  let edges = FixedArray::make(1, edge(0, 0, 0))
  edges[0] = edge(0, 1, 5)
  let (mst, w) = kruskal_mst(edges, 2)
  assert_eq(mst.length(), 1)
  assert_eq(w, 5)
}

test "kruskal: no edges returns empty" {
  let edges = FixedArray::make(0, edge(0, 0, 0))
  let (mst, w) = kruskal_mst(edges, 3)
  assert_eq(mst.length(), 0)
  assert_eq(w, 0)
}

test "kruskal: non-positive n returns empty" {
  let edges = FixedArray::make(1, edge(0, 1, 1))
  let (mst, w) = kruskal_mst(edges, 0)
  assert_eq(mst.length(), 0)
  assert_eq(w, 0)
  let (mst2, w2) = kruskal_mst(edges, -3)
  assert_eq(mst2.length(), 0)
  assert_eq(w2, 0)
}

test "kruskal: complete graph K4" {
  // K4: 4 nodes, 6 edges. The three cheapest form the MST (1+2+3 = 6).
  let edges = FixedArray::make(6, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(0, 2, 2)
  edges[2] = edge(0, 3, 3)
  edges[3] = edge(1, 2, 4)
  edges[4] = edge(1, 3, 5)
  edges[5] = edge(2, 3, 6)
  let (mst, w) = kruskal_mst(edges, 4)
  assert_eq(mst.length(), 3)
  assert_eq(w, 6)
}

test "kruskal: equal weights" {
  // Square with unit weights. MST has 3 edges, weight 3.
  let edges = FixedArray::make(4, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(1, 2, 1)
  edges[2] = edge(2, 3, 1)
  edges[3] = edge(3, 0, 1)
  let (mst, w) = kruskal_mst(edges, 4)
  assert_eq(mst.length(), 3)
  assert_eq(w, 3)
}

test "kruskal: negative weights" {
  // Sorted: 0-1(-5), 0-2(1), 1-2(3). MST = {0-1, 0-2}, weight -4.
  let edges = FixedArray::make(3, edge(0, 0, 0))
  edges[0] = edge(0, 1, -5)
  edges[1] = edge(1, 2, 3)
  edges[2] = edge(0, 2, 1)
  let (mst, w) = kruskal_mst(edges, 3)
  assert_eq(mst.length(), 2)
  assert_eq(w, -4)
}

test "kruskal: star topology" {
  // Center 0 linked to 1..4. All star edges are mutually non-cycling.
  let edges = FixedArray::make(4, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(0, 2, 2)
  edges[2] = edge(0, 3, 3)
  edges[3] = edge(0, 4, 4)
  let (mst, w) = kruskal_mst(edges, 5)
  assert_eq(mst.length(), 4)
  assert_eq(w, 10)
}

test "kruskal: line topology with heavy chord" {
  // Path 0-1-2-3-4 plus a heavy shortcut 0-4. MST = the path, weight 10.
  let edges = FixedArray::make(5, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(1, 2, 2)
  edges[2] = edge(2, 3, 3)
  edges[3] = edge(3, 4, 4)
  edges[4] = edge(0, 4, 100)
  let (mst, w) = kruskal_mst(edges, 5)
  assert_eq(mst.length(), 4)
  assert_eq(w, 10)
}

test "kruskal: MST is acyclic" {
  // A graph rich in cycles; re-unioning the MST edges must never collide.
  let edges = FixedArray::make(6, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(1, 2, 2)
  edges[2] = edge(2, 3, 3)
  edges[3] = edge(3, 0, 4) // cycle 0-1-2-3-0
  edges[4] = edge(0, 2, 5) // diagonal
  edges[5] = edge(1, 3, 6) // diagonal
  let (mst, _) = kruskal_mst(edges, 4)
  let uf = @union_find.new(4)
  for i = 0; i < mst.length(); i = i + 1 {
    let e = mst[i]
    // Each MST edge must join two previously separate components.
    assert_eq(@union_find.union(uf, e.from, e.to), true)
  }
}

test "kruskal: connected graph yields exactly n-1 edges" {
  // 5-node connected graph; MST must have exactly 4 edges and span all nodes.
  let edges = FixedArray::make(7, edge(0, 0, 0))
  edges[0] = edge(0, 1, 2)
  edges[1] = edge(1, 2, 3)
  edges[2] = edge(2, 3, 1)
  edges[3] = edge(3, 4, 4)
  edges[4] = edge(0, 4, 9)
  edges[5] = edge(1, 4, 7)
  edges[6] = edge(0, 3, 8)
  let (mst, _) = kruskal_mst(edges, 5)
  assert_eq(mst.length(), 4)
  let uf = @union_find.new(5)
  for i = 0; i < mst.length(); i = i + 1 {
    let e = mst[i]
    let _ = @union_find.union(uf, e.from, e.to)
  }
  // All 5 vertices end up in a single component.
  assert_eq(@union_find.count(uf), 1)
}

test "kruskal: large graph (10 nodes, 24 edges)" {
  let n = 10
  // 9 light line edges (weights 1..9) span all nodes and form the MST.
  // 15 heavy chords (weight 100) connect non-adjacent nodes and are rejected.
  let chords = [
    (0, 2), (0, 3), (1, 3), (1, 4), (2, 4),
    (2, 5), (3, 5), (3, 6), (4, 6), (4, 7),
    (5, 7), (5, 8), (6, 8), (6, 9), (7, 9),
  ]
  let edges = FixedArray::make(9 + chords.length(), edge(0, 0, 0))
  for i = 0; i < 9; i = i + 1 {
    edges[i] = edge(i, i + 1, i + 1)
  }
  for k = 0; k < chords.length(); k = k + 1 {
    let (a, b) = chords[k]
    edges[9 + k] = edge(a, b, 100)
  }
  let (mst, w) = kruskal_mst(edges, n)
  assert_eq(mst.length(), 9)
  assert_eq(w, 45) // 1 + 2 + ... + 9
}

test "kruskal: mst_weight matches kruskal_mst" {
  let edges = FixedArray::make(3, edge(0, 0, 0))
  edges[0] = edge(0, 1, 1)
  edges[1] = edge(1, 2, 2)
  edges[2] = edge(0, 2, 3)
  let (_, w) = kruskal_mst(edges, 3)
  assert_eq(mst_weight(edges, 3), w)
  assert_eq(mst_weight(edges, 3), 3)
}
