/// Stress tests for production-grade validation.
///
/// These tests verify that algorithms handle large inputs (10^3 - 10^4)
/// without stack overflow, timeout, or correctness degradation.
///
/// Each test exercises a different algorithm family on large data to ensure
/// the implementations scale correctly and don't suffer from recursion
/// depth issues, performance cliffs, or silent data corruption.

// ---------------------------------------------------------------------------
// Sorting: 10,000 elements with pseudo-random distribution
// ---------------------------------------------------------------------------

test "stress: quick_sort 10000 elements" {
  let n = 10000
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 13) % 1000 })
  @quick_sort.quick_sort(xs, fn(a, b) { a - b })
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(xs[k] <= xs[k + 1])
  }
}

test "stress: merge_sort 10000 elements" {
  let n = 10000
  let xs = FixedArray::makei(n, fn(i) { (i * 3 + 7) % 500 })
  @merge_sort.merge_sort(xs, fn(a, b) { a - b })
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(xs[k] <= xs[k + 1])
  }
}

// ---------------------------------------------------------------------------
// Red-black tree: 1000 insert + 1000 delete with RB property verification
// ---------------------------------------------------------------------------

test "stress: red_black_tree 1000 insert + 1000 delete" {
  let mut tree : @red_black_tree.RBNode[Int] = @red_black_tree.empty()
  for k = 1; k <= 1000; k = k + 1 {
    tree = @red_black_tree.insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(@red_black_tree.size(tree), 1000)
  assert_true(@red_black_tree.is_valid_rb(tree))
  for k = 1; k <= 1000; k = k + 1 {
    tree = @red_black_tree.delete(tree, k, fn(a, b) { a - b })
  }
  assert_eq(@red_black_tree.size(tree), 0)
}

// ---------------------------------------------------------------------------
// B-Tree: 1000 insertions + search verification
// ---------------------------------------------------------------------------

test "stress: btree 1000 insert + search" {
  let mut root = @btree.new()
  for k = 1; k <= 1000; k = k + 1 {
    root = @btree.insert(root, k)
  }
  for k = 1; k <= 1000; k = k + 1 {
    assert_true(@btree.search(root, k))
  }
  assert_false(@btree.search(root, 1001))
}

// ---------------------------------------------------------------------------
// Union-Find: 10,000 unions reducing to 1 component
// ---------------------------------------------------------------------------

test "stress: union_find 10000 unions" {
  let uf = @union_find.new(10000)
  for i = 0; i < 9999; i = i + 1 {
    let _ = @union_find.union(uf, i, i + 1)
  }
  assert_eq(@union_find.count(uf), 1)
  assert_true(@union_find.connected(uf, 0, 9999))
}

// ---------------------------------------------------------------------------
// Heap-optimized Dijkstra: 1000-node chain graph
// ---------------------------------------------------------------------------

test "stress: dijkstra_heap 1000 node graph" {
  let n = 1000
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    let edges : Array[(Int, Int)] = []
    if i + 1 < n {
      edges.push((i + 1, 1))
    }
    graph.push(edges)
  }
  let dist = @dijkstra_heap.dijkstra(graph, n, 0)
  assert_eq(dist[n - 1], Some(n - 1))
}

// ---------------------------------------------------------------------------
// Bloom filter: 10,000 elements, zero false negatives
// ---------------------------------------------------------------------------

test "stress: bloom_filter 10000 elements no false negatives" {
  let bf = @bloom_filter.new(10000, 0.01)
  for i = 0; i < 10000; i = i + 1 {
    @bloom_filter.add(bf, "key_\{i}")
  }
  for i = 0; i < 10000; i = i + 1 {
    assert_true(@bloom_filter.contains(bf, "key_\{i}"))
  }
}

// ---------------------------------------------------------------------------
// LRU cache: 10,000 operations with capacity constraint
// ---------------------------------------------------------------------------

test "stress: lru_cache 10000 operations" {
  let eq = fn(a : String, b : String) -> Bool { a == b }
  let cache : @lru_cache.LRUCache[String, Int] = @lru_cache.new(100)
  for i = 0; i < 10000; i = i + 1 {
    @lru_cache.put(cache, "key_\{i % 200}", i, eq)
  }
  // Capacity is 100: at most 100 entries should remain.
  assert_true(@lru_cache.size(cache) <= 100)
}

// ---------------------------------------------------------------------------
// Max flow: 100-node chain network
// ---------------------------------------------------------------------------

test "stress: max_flow 100 node network" {
  let n = 100
  let graph = FixedArray::make(n * n, 0)
  // Chain: 0 -> 1 -> 2 -> ... -> 99, each with capacity 10
  for i = 0; i < n - 1; i = i + 1 {
    graph[i * n + (i + 1)] = 10
  }
  let flow = @max_flow.max_flow(graph, n, 0, n - 1)
  assert_eq(flow, 10)
}

// ---------------------------------------------------------------------------
// LIS: 5,000 elements
// ---------------------------------------------------------------------------

test "stress: lis 5000 elements" {
  let n = 5000
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 1000 })
  let len = @lis.lis_length(xs)
  assert_true(len > 0)
  assert_true(len <= n)
}

// ---------------------------------------------------------------------------
// Suffix array: 600-character periodic string
// ---------------------------------------------------------------------------

test "stress: suffix_array 600 char string" {
  let mut s = ""
  for i = 0; i < 200; i = i + 1 {
    s = s + "abc"
  }
  // 600 chars
  let sa = @suffix_array.build(s)
  assert_eq(sa.length(), 600)
  // Search should find "abc"
  assert_true(@suffix_array.search(sa, s, "abc") is Some(_))
}

// ---------------------------------------------------------------------------
// Convex hull: 1000 pseudo-random points
// ---------------------------------------------------------------------------

test "stress: convex_hull 1000 random points" {
  let points : Array[@convex_hull.Point] = []
  for i = 0; i < 1000; i = i + 1 {
    let x = (i * 7 + 3) % 100
    let y = (i * 13 + 5) % 100
    points.push(@convex_hull.point(x, y))
  }
  let hull = @convex_hull.convex_hull(points)
  // Hull should have at least 3 points for non-degenerate input
  assert_true(hull.length() >= 3)
  // Verify all turns are counterclockwise (convex)
  let h = hull.length()
  for i = 0; i < h; i = i + 1 {
    let p0 = hull[i]
    let p1 = hull[(i + 1) % h]
    let p2 = hull[(i + 2) % h]
    let cross = (p1.x - p0.x) * (p2.y - p0.y) - (p1.y - p0.y) * (p2.x - p0.x)
    assert_true(cross >= 0)
  }
}
