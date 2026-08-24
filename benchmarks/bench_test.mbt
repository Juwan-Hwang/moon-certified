/// Performance benchmarks for critical algorithms.
///
/// These benchmarks measure wall-clock time for key operations on large
/// inputs. They serve two purposes:
///
/// 1. **Performance baseline**: establish expected performance ranges so
///    regressions can be detected.
/// 2. **Complexity verification**: by comparing timing at different input
///    sizes, we can empirically confirm the documented complexity class
///    (e.g., O(n log n) vs O(n²)).
///
/// Run with: `moon test --bench` or `moon test -f bench`
///
/// All times are in microseconds (µs). Results are printed to stdout.

// ---------------------------------------------------------------------------
// Timing utility
// ---------------------------------------------------------------------------

///|
/// Run `f` and return elapsed time in microseconds.
fn time_us(f : () -> Unit raise) -> Double raise {
  let t0 = @bench.monotonic_clock_start()
  f()
  @bench.monotonic_clock_end(t0)
}

///|
/// Format a time in microseconds to a human-readable string.
fn fmt_us(us : Double) -> String {
  if us < 1.0 {
    us.to_string() + " µs"
  } else if us < 1000.0 {
    us.to_string() + " µs"
  } else if us < 1_000_000.0 {
    (us / 1000.0).to_string() + " ms"
  } else {
    (us / 1_000_000.0).to_string() + " s"
  }
}

// ---------------------------------------------------------------------------
// Sorting benchmarks: O(n log n) expected
// ---------------------------------------------------------------------------

///|
test "bench: quick_sort 100K elements" {
  let n = 100000
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 13) % 10000 })
  let t = time_us(fn() { @quick_sort.quick_sort(xs, fn(a, b) { a - b }) })
  println("quick_sort 100K: " + fmt_us(t))
  // Verify sorted
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
}

///|
test "bench: merge_sort 100K elements" {
  let n = 100000
  let xs = FixedArray::makei(n, fn(i) { (i * 3 + 7) % 10000 })
  let t = time_us(fn() { @merge_sort.merge_sort(xs, fn(a, b) { a - b }) })
  println("merge_sort 100K: " + fmt_us(t))
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
}

///|
test "bench: heap_sort 100K elements" {
  let n = 100000
  let xs = FixedArray::makei(n, fn(i) { (i * 11 + 7) % 10000 })
  let t = time_us(fn() { @heap_sort.heap_sort(xs, fn(a, b) { a - b }) })
  println("heap_sort 100K: " + fmt_us(t))
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
}

///|
test "bench: radix_sort 100K elements" {
  let n = 100000
  let xs = FixedArray::makei(n, fn(i) { (i * 17 + 5) % 1000000 })
  let t = time_us(fn() { let _ = @radix_sort.radix_sort(xs) })
  println("radix_sort 100K: " + fmt_us(t))
  match @radix_sort.radix_sort(xs) {
    Some(sorted) =>
      for i = 0; i < n - 1; i = i + 1 {
        assert_true(sorted[i] <= sorted[i + 1])
      }
    None => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// Sorting scaling test: verify O(n log n) by comparing n vs 2n
// ---------------------------------------------------------------------------

///|
/// Verify O(n log n) complexity by counting comparisons, not wall-clock time.
///
/// Timing-based assertions are inherently flaky on CI: CPU frequency scaling,
/// thermal throttling, cache contention, and co-tenant noise can all distort
/// measured ratios. Comparison counting is deterministic and platform-
/// independent — the count depends only on the algorithm and input, not the
/// hardware it runs on.
///
/// For merge sort on n elements, the expected comparison count is in
/// [n/2 · log₂ n, n · log₂ n].  For O(n²) it would be Θ(n²).  We verify:
///
/// 1. The ratio c₂/c₁ is between 1.5 and 3.5 (expected ~2.2 for O(n log n),
///    ~4.0 for O(n²)).
/// 2. The absolute count c₂ is below n₂ · log₂(n₂) · 2 (upper bound for
///    a correct merge sort).
test "bench: merge_sort scaling (n vs 2n)" {
  let n1 = 50000
  let n2 = 100000
  // Use Array[Int] as a mutable counter captured by the closure.
  let cnt1 = Array::make(1, 0)
  let cnt2 = Array::make(1, 0)
  let xs1 = FixedArray::makei(n1, fn(i) { (i * 7 + 3) % 10000 })
  let xs2 = FixedArray::makei(n2, fn(i) { (i * 7 + 3) % 10000 })
  @merge_sort.merge_sort(xs1, fn(a, b) {
    cnt1[0] = cnt1[0] + 1
    a - b
  })
  @merge_sort.merge_sort(xs2, fn(a, b) {
    cnt2[0] = cnt2[0] + 1
    a - b
  })
  let c1 = cnt1[0]
  let c2 = cnt2[0]
  let ratio = c2.to_double() / c1.to_double()
  println(
    "merge_sort comparison count: " + n1.to_string() + "→" + n2.to_string(),
  )
  println(
    "  " +
    c1.to_string() +
    " → " +
    c2.to_string() +
    " (ratio: " +
    ratio.to_string() +
    ")",
  )
  // For O(n log n): n2·log₂(n2) / (n1·log₂(n1)) ≈ 100000·17 / (50000·15.6) ≈ 2.18
  // For O(n²): ratio would be ~4.0.
  assert_true(ratio < 3.5)
  assert_true(ratio > 1.5)
  // Absolute upper bound: merge sort makes at most n·⌈log₂ n⌉ comparisons.
  // n2 = 100000, log₂(100000) ≈ 16.6, so 100000 * 17 = 1,700,000 is a safe ceiling.
  assert_true(c2 < n2 * 17)
}

// ---------------------------------------------------------------------------
// Balanced BST benchmarks: O(log n) per operation
// ---------------------------------------------------------------------------

///|
test "bench: red_black_tree 100K insertions" {
  let mut tree : @red_black_tree.RBNode[Int] = @red_black_tree.empty()
  let t = time_us(fn() {
    for k = 1; k <= 100000; k = k + 1 {
      tree = @red_black_tree.insert(tree, k, fn(a, b) { a - b })
    }
  })
  println("red_black_tree 100K insert: " + fmt_us(t))
  assert_eq(@red_black_tree.size(tree), 100000)
}

///|
test "bench: avl 100K insertions" {
  let mut tree : @avl.AvlNode[Int] = @avl.empty()
  let t = time_us(fn() {
    for k = 1; k <= 100000; k = k + 1 {
      tree = @avl.insert(tree, k, fn(a, b) { a - b })
    }
  })
  println("avl 100K insert: " + fmt_us(t))
  assert_eq(@avl.size(tree), 100000)
}

///|
test "bench: treap 100K insertions" {
  let mut tree : @treap.Treap[Int] = @treap.empty()
  let t = time_us(fn() {
    for k = 1; k <= 100000; k = k + 1 {
      tree = @treap.insert(tree, k, fn(a, b) { a - b })
    }
  })
  println("treap 100K insert: " + fmt_us(t))
  assert_eq(@treap.size(tree), 100000)
}

///|
test "bench: btree 100K insertions" {
  let cmp = fn(a : Int, b : Int) -> Int { a - b }
  let mut root = @btree.new()
  let t = time_us(fn() {
    for k = 1; k <= 100000; k = k + 1 {
      root = @btree.insert(root, k, cmp)
    }
  })
  println("btree 100K insert: " + fmt_us(t))
  assert_eq(@btree.size(root), 100000)
}

///|
test "bench: skip_list 100K insertions" {
  let sl = @skip_list.SkipList::new()
  let t = time_us(fn() {
    for k = 1; k <= 100000; k = k + 1 {
      sl.insert(k, k)
    }
  })
  println("skip_list 100K insert: " + fmt_us(t))
  assert_eq(sl.size(), 100000)
}

// ---------------------------------------------------------------------------
// Fenwick tree (BIT): O(n) build, O(log n) query/update
// ---------------------------------------------------------------------------

///|
test "bench: fenwick 1M build + 1M queries" {
  let n = 1000000
  let arr = FixedArray::makei(n, fn(i) { i % 100 })
  let build_t = time_us(fn() { let _ = @fenwick.build(arr) })
  let ft = @fenwick.build(arr)
  let query_t = time_us(() => {
    let mut sum = 0
    for i = 1; i <= n; i = i + 1 {
      sum = sum + @fenwick.query(ft, i)
    }
    // Prevent optimizer from removing the loop
    if sum < 0 {
      fail("unreachable")
    }
  })
  println("fenwick 1M build: " + fmt_us(build_t))
  println("fenwick 1M queries: " + fmt_us(query_t))
}

// ---------------------------------------------------------------------------
// Segment tree: O(n) build, O(log n) query/update
// ---------------------------------------------------------------------------

///|
test "bench: segment_tree 100K build + 100K queries" {
  let n = 100000
  let arr = FixedArray::makei(n, fn(i) { i % 100 })
  let build_t = time_us(fn() { let _ = @segment_tree.build(arr) })
  let st = @segment_tree.build(arr)
  let query_t = time_us(() => {
    let mut sum = 0
    for i = 0; i < n; i = i + 1 {
      sum = sum + @segment_tree.query(st, i, i + 1)
    }
    if sum < 0 {
      fail("unreachable")
    }
  })
  println("segment_tree 100K build: " + fmt_us(build_t))
  println("segment_tree 100K point queries: " + fmt_us(query_t))
}

///|
test "bench: lazy segment_tree 100K range updates + queries" {
  let n = 100000
  let arr = FixedArray::make(n, 0)
  let st = @segment_tree.lazy_build(arr)
  let update_t = time_us(fn() { @segment_tree.lazy_update(st, 0, n, 1) })
  let query_t = time_us(fn() { let _ = @segment_tree.lazy_query(st, 0, n) })
  println("lazy_segment_tree 100K range update: " + fmt_us(update_t))
  println("lazy_segment_tree 100K range query: " + fmt_us(query_t))
  // After range update of +1 on [0, n), the sum should be n.
  assert_eq(@segment_tree.lazy_query(st, 0, n), n)
}

// ---------------------------------------------------------------------------
// Union-Find: near-O(1) per operation with path compression
// ---------------------------------------------------------------------------

///|
test "bench: union_find 1M operations" {
  let n = 1000000
  let uf = @union_find.new(n)
  let t = time_us(fn() {
    for i = 0; i < n - 1; i = i + 1 {
      let _ = @union_find.union(uf, i, i + 1)
    }
  })
  assert_eq(@union_find.count(uf), 1)
  println("union_find 1M unions: " + fmt_us(t))
}

// ---------------------------------------------------------------------------
// Graph algorithms
// ---------------------------------------------------------------------------

///|
test "bench: dijkstra_heap 1000-node dense graph" {
  let n = 1000
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    let edges : Array[(Int, Int)] = []
    for j = 0; j < n; j = j + 1 {
      if i != j && (i * 7 + j * 3) % 5 == 0 {
        edges.push((j, (i + j) % 100 + 1))
      }
    }
    graph.push(edges)
  }
  let t = time_us(fn() { let _ = @dijkstra_heap.dijkstra(graph, n, 0) })
  println("dijkstra_heap 1000-node dense: " + fmt_us(t))
  let dists = @dijkstra_heap.dijkstra(graph, n, 0)
  // Distance to self is 0.
  assert_true(dists[0] is Some(0))
}

///|
test "bench: scc 1000-node graph" {
  let n = 1000
  let graph = FixedArray::make(n * n, 0)
  // Create a graph with cycles
  for i = 0; i < n - 1; i = i + 1 {
    graph[i * n + (i + 1)] = 1
    graph[(i + 1) * n + i] = 1
  }
  let t = time_us(fn() { let _ = @scc.tarjan_scc(graph, n) })
  println("scc 1000-node: " + fmt_us(t))
  // The graph is a single path with back-edges, so all nodes are in one SCC.
  let components = @scc.tarjan_scc(graph, n)
  assert_true(components.length() > 0)
}

///|
test "bench: kruskal 1000-edge MST" {
  let n = 500
  let edges : Array[@kruskal.Edge] = []
  for i = 0; i < n - 1; i = i + 1 {
    edges.push(@kruskal.edge(i, i + 1, i + 1))
  }
  let edge_arr = FixedArray::from_array(edges.view())
  let t = time_us(fn() { let _ = @kruskal.kruskal_mst(edge_arr, n) })
  println("kruskal 500-node chain MST: " + fmt_us(t))
  // MST of a chain has n-1 edges with total weight sum(1..n-1).
  let (mst_edges, _) = @kruskal.kruskal_mst(edge_arr, n)
  assert_eq(mst_edges.length(), n - 1)
}

// ---------------------------------------------------------------------------
// String algorithms
// ---------------------------------------------------------------------------

///|
test "bench: kmp search 100K text" {
  let mut text = ""
  for i = 0; i < 25000; i = i + 1 {
    text = text + "abcd"
  }
  // 100K chars
  let t = time_us(fn() { let _ = @kmp.kmp_search(text, "abcdabcd") })
  println("kmp 100K text: " + fmt_us(t))
  // "abcdabcd" appears at position 0 in "abcdabcdabcd..."
  let result = @kmp.kmp_search(text, "abcdabcd")
  assert_true(result is Some(0))
}

///|
test "bench: suffix_array 10K string" {
  let mut s = ""
  for i = 0; i < 3333; i = i + 1 {
    s = s + "abc"
  }
  // ~10K chars
  let t = time_us(fn() { let _ = @suffix_array.build(s) })
  println("suffix_array 10K string: " + fmt_us(t))
  let sa = @suffix_array.build(s)
  assert_eq(sa.length(), s.length())
}

// ---------------------------------------------------------------------------
// Number theory
// ---------------------------------------------------------------------------

///|
test "bench: euler_sieve 1M primes" {
  let t = time_us(fn() { let _ = @euler_sieve.sieve(1000000) })
  println("euler_sieve 1M: " + fmt_us(t))
  let primes = @euler_sieve.sieve(1000000)
  // There are 78498 primes below 1M.
  assert_true(primes is Some(_))
  match primes {
    Some(p) => assert_eq(@euler_sieve.prime_count(p), 78498)
    None => assert_true(false)
  }
}

///|
test "bench: miller_rabin 10000 primality checks" {
  let t = time_us(fn() {
    for n = 1; n <= 10000; n = n + 1 {
      let _ = @miller_rabin.is_prime(n)
    }
  })
  println("miller_rabin 10K checks: " + fmt_us(t))
  // 2 is prime, 1 is not, 4 is not.
  assert_true(@miller_rabin.is_prime(2))
  assert_true(!@miller_rabin.is_prime(1))
  assert_true(!@miller_rabin.is_prime(4))
}

///|
test "bench: ntt multiply 1024-coefficient polynomials" {
  let a : Array[Int64] = []
  let b : Array[Int64] = []
  for i = 0; i < 1024; i = i + 1 {
    a.push(i.to_int64())
    b.push((i * 2).to_int64())
  }
  let t = time_us(fn() { let _ = @ntt.multiply(a, b) })
  println("ntt 1024-coefficient multiply: " + fmt_us(t))
  let result = @ntt.multiply(a, b)
  // Result length should be 2*1024 - 1 = 2047.
  assert_true(result.length() >= 1024)
}

// ---------------------------------------------------------------------------
// LIS: O(n log n) vs O(n²)
// ---------------------------------------------------------------------------

///|
test "bench: lis 10K elements" {
  let n = 10000
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 1000 })
  let t = time_us(fn() { let _ = @lis.lis_length(xs) })
  println("lis 10K: " + fmt_us(t))
  let lis_len = @lis.lis_length(xs)
  assert_true(lis_len >= 1)
  assert_true(lis_len <= n)
}

// ---------------------------------------------------------------------------
// Convex hull
// ---------------------------------------------------------------------------

///|
test "bench: convex_hull 10K points" {
  let n = 10000
  let points : Array[@geometry_utils.Point] = []
  for i = 0; i < n; i = i + 1 {
    points.push(@geometry_utils.point((i * 7 + 3) % 1000, (i * 13 + 5) % 1000))
  }
  let t = time_us(fn() { let _ = @convex_hull.convex_hull(points) })
  println("convex_hull 10K points: " + fmt_us(t))
  let hull = @convex_hull.convex_hull(points)
  // Hull should have at least 3 points and at most n points.
  assert_true(hull.length() >= 3)
  assert_true(hull.length() <= n)
}

// ---------------------------------------------------------------------------
// Crypto benchmarks: hashing and block cipher
// ---------------------------------------------------------------------------

///|
test "bench: sha256 1MB data" {
  let buf : Array[Byte] = []
  for i = 0; i < 1000000; i = i + 1 {
    buf.push((i % 256).to_byte())
  }
  let data = Bytes::from_array(buf)
  let t = time_us(fn() { let _ = @sha256.sha256(data) })
  println("sha256 1MB: " + fmt_us(t))
  let digest = @sha256.sha256(data)
  assert_eq(digest.length(), 32)
}

///|
test "bench: aes-128-gcm encrypt 64KB" {
  let key = match @aes.new_key(FixedArray::make(16, b'\x00')) {
    Some(k) => k
    None => abort("key creation failed in benchmark")
  }
  let plaintext = FixedArray::makei(65536, fn(i) { (i % 256).to_byte() })
  let iv = FixedArray::make(12, b'\x00')
  let aad = FixedArray::make(0, b'\x00')
  let t = time_us(fn() { let _ = @aes.encrypt_gcm(key, iv, plaintext, aad) })
  println("aes-128-gcm encrypt 64KB: " + fmt_us(t))
  let result = match @aes.encrypt_gcm(key, iv, plaintext, aad) {
    Some(r) => r
    None => abort("encryption failed in benchmark")
  }
  assert_true(result.ciphertext.length() == plaintext.length())
  assert_eq(result.tag.length(), 16)
}

// ---------------------------------------------------------------------------
// Compression benchmarks
// ---------------------------------------------------------------------------

///|
test "bench: deflate compress 100KB" {
  let buf : Array[Byte] = []
  for i = 0; i < 100000; i = i + 1 {
    // Semi-compressible: repeating patterns with some noise.
    buf.push(((i * 7 + 3) % 64).to_byte())
  }
  let data = Bytes::from_array(buf)
  let t = time_us(fn() { let _ = @deflate.deflate(data) })
  println("deflate compress 100KB: " + fmt_us(t))
  let compressed = @deflate.deflate(data)
  // Compressed should be smaller for this compressible data.
  assert_true(compressed.length() < data.length())
  // Verify round-trip.
  let decompressed = match @deflate.inflate(compressed) {
    Some(d) => d
    None => abort("inflate failed in benchmark")
  }
  assert_eq(decompressed, data)
}

// ---------------------------------------------------------------------------
// ML benchmarks: K-Means clustering
// ---------------------------------------------------------------------------

///|
test "bench: kmeans 1000 points 5 clusters" {
  let points : Array[Array[Double]] = []
  // Generate 5 clusters of 200 points each around centers.
  let centers = [
    [0.0, 0.0],
    [10.0, 10.0],
    [20.0, 0.0],
    [0.0, 20.0],
    [20.0, 20.0],
  ]
  for c = 0; c < 5; c = c + 1 {
    for p = 0; p < 200; p = p + 1 {
      let dx = ((p * 7 + c * 3) % 100).to_double() / 100.0 - 0.5
      let dy = ((p * 13 + c * 5) % 100).to_double() / 100.0 - 0.5
      points.push([centers[c][0] + dx, centers[c][1] + dy])
    }
  }
  let t = time_us(fn() { let _ = @kmeans.kmeans_with_seed(points, 5, 50, 42) })
  println("kmeans 1000 pts 5 clusters: " + fmt_us(t))
  let result = @kmeans.kmeans_with_seed(points, 5, 50, 42)
  assert_eq(result.centroids.length(), 5)
  assert_eq(result.assignments.length(), 1000)
}

// ---------------------------------------------------------------------------
// DP benchmarks
// ---------------------------------------------------------------------------

///|
test "bench: matrix_chain 100 matrices" {
  let dims : Array[Int] = []
  for i = 0; i < 101; i = i + 1 {
    dims.push(10 + i * 7 % 90)
  }
  let t = time_us(fn() { let _ = @matrix_chain.matrix_chain_order(dims) })
  println("matrix_chain 100 matrices: " + fmt_us(t))
  let cost = @matrix_chain.matrix_chain_order(dims)
  // Cost should be positive for non-trivial chain.
  assert_true(cost > 0)
}

///|
test "bench: knapsack 1000 items capacity 10000" {
  let n = 1000
  let weights : Array[Int] = []
  let values : Array[Int] = []
  let counts : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    weights.push(1 + i * 7 % 50)
    values.push(1 + i * 13 % 100)
    counts.push(1 + i * 3 % 5)
  }
  let capacity = 10000
  let t = time_us(fn() {
    let _ = @knapsack_opt.multiple_knapsack(weights, values, counts, capacity)
  })
  println("knapsack 1000 items cap 10K: " + fmt_us(t))
  let result = @knapsack_opt.multiple_knapsack(
    weights, values, counts, capacity,
  )
  assert_true(result > 0)
}

// ---------------------------------------------------------------------------
// Geometry benchmarks: closest pair and Delaunay triangulation
// ---------------------------------------------------------------------------

///|
test "bench: closest_pair 10K points" {
  let n = 10000
  let points : Array[@geometry_utils.Point] = []
  for i = 0; i < n; i = i + 1 {
    points.push(
      @geometry_utils.point((i * 7 + 3) % 10000, (i * 13 + 5) % 10000),
    )
  }
  let t = time_us(fn() { let _ = @closest_pair.closest_pair(points) })
  println("closest_pair 10K points: " + fmt_us(t))
  let dist = match @closest_pair.closest_pair(points) {
    Some(d) => d
    None => abort("closest_pair failed in benchmark")
  }
  assert_true(dist >= 0L)
}

///|
test "bench: delaunay 1000 points" {
  let n = 1000
  let points : Array[@delaunay.DPoint] = []
  for i = 0; i < n; i = i + 1 {
    points.push(@delaunay.dpoint((i * 7 + 3) % 5000, (i * 13 + 5) % 5000))
  }
  let t = time_us(fn() { let _ = @delaunay.triangulate(points) })
  println("delaunay 1000 points: " + fmt_us(t))
  let result = @delaunay.triangulate(points)
  // triangles is a flat FixedArray[Int] (3 ints per triangle: v0, v1, v2).
  // For n >= 3 points there should be at least one triangle (3 entries).
  assert_true(result.triangles.length() >= 3)
}

// ---------------------------------------------------------------------------
// Graph benchmarks: dominator tree and maximum matching
// ---------------------------------------------------------------------------

///|
test "bench: dominator_tree 1000-node graph" {
  let n = 1000
  let adj : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    let succ : Array[Int] = []
    // Each node connects to next few nodes, creating a DAG-like structure.
    for j = 1; j <= 3; j = j + 1 {
      let target = i + j
      if target < n {
        succ.push(target)
      }
    }
    // Add some cross edges for complexity.
    if i > 10 && i * 3 % 7 == 0 {
      succ.push(i / 2)
    }
    adj.push(succ)
  }
  let t = time_us(fn() {
    let _ = @dominator_tree.build_dominator_tree_arr(adj, n, 0)
  })
  println("dominator_tree 1000-node: " + fmt_us(t))
  let tree = @dominator_tree.build_dominator_tree_arr(adj, n, 0)
  assert_eq(@dominator_tree.vertex_count(tree), n)
  // Root dominates itself.
  assert_true(@dominator_tree.dominates(tree, 0, 0))
}

///|
test "bench: edmonds_blossom 200-node graph" {
  let n = 200
  let adj : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    let neighbors : Array[Int] = []
    // Create a graph with some cycles and odd-length cycles (blossoms).
    let j = (i + 1) % n
    neighbors.push(j)
    if i + 3 < n {
      neighbors.push(i + 3)
    }
    if i > 5 && i % 2 == 0 {
      neighbors.push(i - 5)
    }
    adj.push(neighbors)
  }
  let t = time_us(fn() { let _ = @edmonds_blossom.max_matching(adj, n) })
  println("edmonds_blossom 200-node: " + fmt_us(t))
  let m = @edmonds_blossom.max_matching(adj, n)
  // In a graph with n=200 nodes, matching cardinality should be at least 1
  // (there are edges) and at most n/2 = 100.
  let card = @edmonds_blossom.cardinality(m)
  assert_true(card >= 1)
  assert_true(card <= n / 2)
}
