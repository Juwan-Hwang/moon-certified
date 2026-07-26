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

///|
/// Verify that `sorted` is a permutation of `original` (no elements lost
/// or duplicated). Uses a counting approach: for each distinct value, the
/// count in `sorted` must equal the count in `original`.
fn assert_permutation(
  original : FixedArray[Int],
  sorted : FixedArray[Int],
) -> Unit raise {
  let n = original.length()
  assert_eq(sorted.length(), n)
  // Find min/max to size the count array.
  if n == 0 {
    return
  }
  let mut lo = original[0]
  let mut hi = original[0]
  for i = 1; i < n; i = i + 1 {
    if original[i] < lo {
      lo = original[i]
    }
    if original[i] > hi {
      hi = original[i]
    }
  }
  let range = hi - lo + 1
  let counts_orig = FixedArray::make(range, 0)
  let counts_sorted = FixedArray::make(range, 0)
  for i = 0; i < n; i = i + 1 {
    counts_orig[original[i] - lo] = counts_orig[original[i] - lo] + 1
    counts_sorted[sorted[i] - lo] = counts_sorted[sorted[i] - lo] + 1
  }
  for v = 0; v < range; v = v + 1 {
    assert_eq(counts_orig[v], counts_sorted[v])
  }
}

///|
test "stress: quick_sort 10000 elements" {
  let n = 10000
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 13) % 1000 })
  let original = FixedArray::makei(n, fn(i) { (i * 7 + 13) % 1000 })
  @quick_sort.quick_sort(xs, fn(a, b) { a - b })
  // Verify sortedness.
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(xs[k] <= xs[k + 1])
  }
  // Verify permutation: no elements lost or duplicated.
  assert_permutation(original, xs)
}

///|
test "stress: merge_sort 10000 elements" {
  let n = 10000
  let xs = FixedArray::makei(n, fn(i) { (i * 3 + 7) % 500 })
  let original = FixedArray::makei(n, fn(i) { (i * 3 + 7) % 500 })
  @merge_sort.merge_sort(xs, fn(a, b) { a - b })
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(xs[k] <= xs[k + 1])
  }
  assert_permutation(original, xs)
}

// ---------------------------------------------------------------------------
// Red-black tree: 1000 insert + 1000 delete with RB property verification
// ---------------------------------------------------------------------------

///|
test "stress: red_black_tree 1000 insert + 1000 delete" {
  let mut tree : @red_black_tree.RBNode[Int] = @red_black_tree.empty()
  for k = 1; k <= 1000; k = k + 1 {
    tree = @red_black_tree.insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(@red_black_tree.size(tree), 1000)
  assert_true(@red_black_tree.is_valid_rb(tree, fn(a, b) { a - b }))
  for k = 1; k <= 1000; k = k + 1 {
    tree = @red_black_tree.delete(tree, k, fn(a, b) { a - b })
  }
  assert_eq(@red_black_tree.size(tree), 0)
}

// ---------------------------------------------------------------------------
// B-Tree: 1000 insertions + search verification
// ---------------------------------------------------------------------------

///|
test "stress: btree 1000 insert + search" {
  let cmp = fn(a : Int, b : Int) -> Int { a - b }
  let mut root = @btree.new()
  for k = 1; k <= 1000; k = k + 1 {
    root = @btree.insert(root, k, cmp)
  }
  for k = 1; k <= 1000; k = k + 1 {
    assert_true(@btree.search(root, k, cmp))
  }
  assert_false(@btree.search(root, 1001, cmp))
}

// ---------------------------------------------------------------------------
// Union-Find: 10,000 unions reducing to 1 component
// ---------------------------------------------------------------------------

///|
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

///|
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

///|
test "stress: bloom_filter 10000 elements no false negatives" {
  let str_hash = fn(s : String) -> Int {
    let mut h = 0
    for i = 0; i < s.length(); i = i + 1 {
      h = h * 31 + s[i].to_int()
    }
    h
  }
  let bf = @bloom_filter.new(10000, 0.01, str_hash)
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

///|
test "stress: lru_cache 10000 operations" {
  let str_hash = fn(s : String) -> Int {
    let mut h = 0
    for i = 0; i < s.length(); i = i + 1 {
      h = h * 31 + s[i].to_int()
    }
    h
  }
  let str_eq = fn(a : String, b : String) -> Bool { a == b }
  let cache : @lru_cache.LRUCache[String, Int] = @lru_cache.new(
    100, str_hash, str_eq,
  )
  for i = 0; i < 10000; i = i + 1 {
    @lru_cache.put(cache, "key_\{i % 200}", i)
  }
  // Capacity is 100: at most 100 entries should remain.
  assert_true(@lru_cache.size(cache) <= 100)
}

// ---------------------------------------------------------------------------
// Max flow: 100-node chain network
// ---------------------------------------------------------------------------

///|
test "stress: max_flow 100 node network" {
  let n = 100
  let graph = FixedArray::make(n * n, 0)
  // Chain: 0 -> 1 -> 2 -> ... -> 99, each with capacity 10
  for i = 0; i < n - 1; i = i + 1 {
    graph[i * n + (i + 1)] = 10
  }
  let flow = @max_flow.max_flow(graph, n, 0, n - 1)
  assert_eq(flow, Some(10L))
}

// ---------------------------------------------------------------------------
// LIS: 5,000 elements
// ---------------------------------------------------------------------------

///|
test "stress: lis 5000 elements" {
  let n = 5000
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 1000 })
  let len = @lis.lis_length(xs)
  // Verify the result is a valid LIS length by cross-checking with
  // a brute-force O(n^2) DP on a smaller sample.
  let sample_n = 200
  let sample = FixedArray::makei(sample_n, fn(i) { (i * 7 + 3) % 100 })
  let sample_len = @lis.lis_length(sample)
  // Brute-force LIS on the sample.
  let dp = FixedArray::make(sample_n, 1)
  for i = 0; i < sample_n; i = i + 1 {
    for j = 0; j < i; j = j + 1 {
      if sample[j] < sample[i] && dp[j] + 1 > dp[i] {
        dp[i] = dp[j] + 1
      }
    }
  }
  let mut brute_max = 0
  for i = 0; i < sample_n; i = i + 1 {
    if dp[i] > brute_max {
      brute_max = dp[i]
    }
  }
  assert_eq(sample_len, brute_max)
  // For the full array: reconstruct the actual subsequence and verify it is
  // strictly increasing, is a valid subsequence of xs, and has length equal
  // to lis_length. This is much stronger than the trivial `1 <= len <= n`
  // bounds check: it confirms the reported length is actually achievable by
  // a concrete increasing subsequence drawn from the input.
  let seq = @lis.lis_sequence(xs)
  assert_eq(seq.length(), len)
  // Strictly increasing.
  for k = 1; k < seq.length(); k = k + 1 {
    assert_true(seq[k - 1] < seq[k])
  }
  // Valid subsequence of xs: scan xs and match seq in order.
  let mut j = 0
  for i = 0; i < n && j < seq.length(); i = i + 1 {
    if xs[i] == seq[j] {
      j = j + 1
    }
  }
  assert_eq(j, seq.length())
}

// ---------------------------------------------------------------------------
// Suffix array: 600-character periodic string
// ---------------------------------------------------------------------------

///|
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

///|
test "stress: convex_hull 1000 random points" {
  let points : Array[@geometry_utils.Point] = []
  for i = 0; i < 1000; i = i + 1 {
    let x = (i * 7 + 3) % 100
    let y = (i * 13 + 5) % 100
    points.push(@geometry_utils.point(x, y))
  }
  let hull = @convex_hull.convex_hull(points)
  // Hull should have at least 3 points for non-degenerate input
  assert_true(hull.length() >= 3)
  // Verify all turns are counterclockwise (convex) using cross64 to
  // avoid Int32 overflow for large coordinates.
  let h = hull.length()
  for i = 0; i < h; i = i + 1 {
    let p0 = hull[i]
    let p1 = hull[(i + 1) % h]
    let p2 = hull[(i + 2) % h]
    assert_true(@geometry_utils.cross64(p0, p1, p2) >= 0L)
  }
}

// ---------------------------------------------------------------------------
// New v0.5.0 algorithm stress tests
// ---------------------------------------------------------------------------

///|
test "stress: heap_sort 10000 elements" {
  let n = 10000
  let xs = FixedArray::makei(n, fn(i) { (i * 11 + 7) % 1000 })
  let original = FixedArray::makei(n, fn(i) { (i * 11 + 7) % 1000 })
  @heap_sort.heap_sort(xs, fn(a, b) { a - b })
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(xs[k] <= xs[k + 1])
  }
  assert_permutation(original, xs)
}

///|
test "stress: counting_sort 10000 elements" {
  let n = 10000
  let xs = FixedArray::makei(n, fn(i) { (i * 13 + 3) % 500 })
  let sorted = @counting_sort.counting_sort(xs).unwrap()
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(sorted[k] <= sorted[k + 1])
  }
  assert_permutation(xs, sorted)
}

///|
test "stress: radix_sort 10000 elements" {
  let n = 10000
  let xs = FixedArray::makei(n, fn(i) { (i * 17 + 5) % 1000000 })
  let sorted = @radix_sort.radix_sort(xs).unwrap()
  for k = 0; k < n - 1; k = k + 1 {
    assert_true(sorted[k] <= sorted[k + 1])
  }
  assert_permutation(xs, sorted)
}

///|
test "stress: avl 1000 insert + delete with balance" {
  let mut tree : @avl.AvlNode[Int] = @avl.empty()
  for k = 1; k <= 1000; k = k + 1 {
    tree = @avl.insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(@avl.size(tree), 1000)
  assert_true(@avl.height(tree) <= 20)
  for k = 1; k <= 500; k = k + 1 {
    tree = @avl.delete(tree, k, fn(a, b) { a - b })
  }
  assert_eq(@avl.size(tree), 500)
  assert_true(@avl.height(tree) <= 20)
}

///|
test "stress: skip_list 1000 insert + search + delete" {
  let sl = @skip_list.SkipList::new()
  for k = 1; k <= 1000; k = k + 1 {
    sl.insert(k, k * 10)
  }
  assert_eq(sl.size(), 1000)
  for k = 1; k <= 1000; k = k + 1 {
    assert_eq(sl.search(k), Some(k * 10))
  }
  for k = 1; k <= 500; k = k + 1 {
    assert_eq(sl.delete(k), true)
  }
  assert_eq(sl.size(), 500)
}

///|
test "stress: treap 1000 insert + search + delete" {
  let mut tree : @treap.Treap[Int] = @treap.empty()
  for k = 1; k <= 1000; k = k + 1 {
    tree = @treap.insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(@treap.size(tree), 1000)
  for k = 1; k <= 1000; k = k + 1 {
    assert_true(@treap.search(tree, k, fn(a, b) { a - b }))
  }
  for k = 1; k <= 500; k = k + 1 {
    tree = @treap.delete(tree, k, fn(a, b) { a - b })
  }
  assert_eq(@treap.size(tree), 500)
}

///|
test "stress: miller_rabin primality check 1..10000" {
  // Cross-check Miller-Rabin against trial division for all n in [1, 10000].
  let is_prime_trial = fn(n : Int) -> Bool {
    if n < 2 {
      return false
    }
    if n < 4 {
      return true
    }
    if n % 2 == 0 {
      return false
    }
    let mut i = 3
    while i * i <= n {
      if n % i == 0 {
        return false
      }
      i = i + 2
    }
    true
  }
  for n = 1; n <= 10000; n = n + 1 {
    assert_eq(@miller_rabin.is_prime(n), is_prime_trial(n))
  }
}

///|
test "stress: z_function search in 2000-char text" {
  let mut text = ""
  for i = 0; i < 500; i = i + 1 {
    text = text + "ab"
  }
  // 1000-char text of alternating "ab"
  let positions = @z_function.z_search("abab", text)
  assert_true(positions.length() > 0)
}

///|
test "stress: manacher on 1000-char palindrome" {
  let mut s = ""
  for i = 0; i < 500; i = i + 1 {
    s = s + "a"
  }
  // 500-char all-a string: longest palindrome is the whole string
  match @manacher.longest_palindrome(s) {
    Some(p) => assert_eq(p.length(), 500)
    None => abort("expected palindrome")
  }
  // Count should be n*(n+1)/2 for all-same string
  assert_eq(@manacher.count_palindromes(s), 500 * 501 / 2)
}

///|
test "stress: scc 1000-node chain (iterative, no stack overflow)" {
  let n = 1000
  let graph = FixedArray::make(n * n, 0)
  // Chain: 0 -> 1 -> 2 -> ... -> 999
  for i = 0; i < n - 1; i = i + 1 {
    graph[i * n + (i + 1)] = 1
  }
  let sccs = @scc.tarjan_scc(graph, n)
  // A chain has n SCCs (each node is its own SCC)
  assert_eq(sccs.length(), n)
}

///|
test "stress: johnson cross-check with dijkstra_heap" {
  let n = 50
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    let edges : Array[(Int, Int)] = []
    for j = 0; j < n; j = j + 1 {
      if i != j && (i * 7 + j * 3) % 3 == 0 {
        edges.push((j, (i + j) % 20 + 1))
      }
    }
    graph.push(edges)
  }
  let dist_j = @johnson.johnson(graph, n)
  let dist_d = @dijkstra_heap.dijkstra(graph, n, 0)
  // Johnson's result for vertex 0 should match Dijkstra's
  for j = 0; j < n; j = j + 1 {
    assert_eq(dist_j[0][j], dist_d[j])
  }
}

///|
test "stress: bidirectional_bfs 1000-node chain" {
  let n = 1000
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    let edges : Array[(Int, Int)] = []
    if i + 1 < n {
      edges.push((i + 1, 1))
    }
    if i > 0 {
      edges.push((i - 1, 1))
    }
    graph.push(edges)
  }
  let dist = @bidirectional_bfs.bidirectional_bfs(graph, n, 0, 999)
  assert_eq(dist, Some(999))
}

///|
test "stress: topo_sort_adj 1000-node chain DAG" {
  let n = 1000
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    let edges : Array[(Int, Int)] = []
    if i + 1 < n {
      edges.push((i + 1, 1))
    }
    graph.push(edges)
  }
  match @topological_sort_adj.topo_sort(graph, n) {
    Some(order) => {
      assert_eq(order.length(), n)
      assert_eq(order[0], 0)
      assert_eq(order[n - 1], n - 1)
    }
    None => abort("expected topo sort to succeed")
  }
  assert_false(@topological_sort_adj.has_cycle(graph, n))
}

///|
test "stress: andrew_hull 1000 random points" {
  let n = 1000
  let points : Array[@geometry_utils.Point] = []
  for i = 0; i < n; i = i + 1 {
    points.push(@geometry_utils.point((i * 7 + 3) % 200, (i * 13 + 5) % 200))
  }
  let hull = @andrew_hull.convex_hull(points)
  assert_true(hull.length() >= 3)
}

///|
test "stress: segment_tree lazy 1000 range updates + queries" {
  let n = 1000
  let arr = FixedArray::make(n, 0)
  let st = @segment_tree.lazy_build(arr)
  // Add 5 to range [0, 500)
  @segment_tree.lazy_update(st, 0, 500, 5)
  assert_eq(@segment_tree.lazy_query(st, 0, 500), 500 * 5)
  assert_eq(@segment_tree.lazy_query(st, 500, 1000), 0)
  // Add 3 to range [200, 800)
  @segment_tree.lazy_update(st, 200, 800, 3)
  // [0, 200) = 5, [200, 500) = 8, [500, 800) = 3, [800, 1000) = 0
  assert_eq(@segment_tree.lazy_query(st, 0, 200), 200 * 5)
  assert_eq(@segment_tree.lazy_query(st, 200, 500), 300 * 8)
  assert_eq(@segment_tree.lazy_query(st, 500, 800), 300 * 3)
  assert_eq(@segment_tree.lazy_query(st, 800, 1000), 0)
}

///|
test "stress: interpolation_search 10000 uniform array" {
  let n = 10000
  let arr = FixedArray::makei(n, fn(i) { i * 2 })
  match @interpolation_search.interpolation_search(arr, 10000) {
    Some(idx) => assert_eq(arr[idx], 10000)
    None => abort("expected to find target")
  }
}

///|
test "stress: exponential_search 10000 sorted array" {
  let n = 10000
  let arr = FixedArray::makei(n, fn(i) { i })
  match @exponential_search.exponential_search(arr, 7777) {
    Some(idx) => assert_eq(arr[idx], 7777)
    None => abort("expected to find target")
  }
}
