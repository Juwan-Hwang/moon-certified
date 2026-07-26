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

/// Run `f` and return elapsed time in microseconds.
fn time_us(f : () -> Unit) -> Double {
  let t0 = @bench.monotonic_clock_start()
  f()
  @bench.monotonic_clock_end(t0)
}

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

test "bench: quick_sort 100K elements" {
  let n = 100000
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 13) % 10000 })
  let t = time_us(fn() {
    @quick_sort.quick_sort(xs, fn(a, b) { a - b })
  })
  println("quick_sort 100K: " + fmt_us(t))
  // Verify sorted
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
}

test "bench: merge_sort 100K elements" {
  let n = 100000
  let xs = FixedArray::makei(n, fn(i) { (i * 3 + 7) % 10000 })
  let t = time_us(fn() {
    @merge_sort.merge_sort(xs, fn(a, b) { a - b })
  })
  println("merge_sort 100K: " + fmt_us(t))
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
}

test "bench: heap_sort 100K elements" {
  let n = 100000
  let xs = FixedArray::makei(n, fn(i) { (i * 11 + 7) % 10000 })
  let t = time_us(fn() {
    @heap_sort.heap_sort(xs, fn(a, b) { a - b })
  })
  println("heap_sort 100K: " + fmt_us(t))
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
}

test "bench: radix_sort 100K elements" {
  let n = 100000
  let xs = FixedArray::makei(n, fn(i) { (i * 17 + 5) % 1000000 })
  let t = time_us(fn() {
    let _ = @radix_sort.radix_sort(xs)
  })
  println("radix_sort 100K: " + fmt_us(t))
}

// ---------------------------------------------------------------------------
// Sorting scaling test: verify O(n log n) by comparing n vs 2n
// ---------------------------------------------------------------------------

test "bench: merge_sort scaling (n vs 2n)" {
  let n1 = 50000
  let n2 = 100000
  let xs1 = FixedArray::makei(n1, fn(i) { (i * 7 + 3) % 10000 })
  let xs2 = FixedArray::makei(n2, fn(i) { (i * 7 + 3) % 10000 })
  let t1 = time_us(fn() {
    @merge_sort.merge_sort(xs1, fn(a, b) { a - b })
  })
  let t2 = time_us(fn() {
    @merge_sort.merge_sort(xs2, fn(a, b) { a - b })
  })
  let ratio = t2 / t1
  println("merge_sort scaling: " + n1.to_string() + " → " + n2.to_string())
  println("  " + fmt_us(t1) + " → " + fmt_us(t2) + " (ratio: " + ratio.to_string() + ")")
  // For O(n log n), ratio should be ~2.1-2.3.
  // For O(n²), ratio would be ~4.0.
  // Tighten upper bound to 3.5 to distinguish O(n log n) from O(n²).
  assert_true(ratio < 3.5)
  assert_true(ratio > 1.5)
}

// ---------------------------------------------------------------------------
// Balanced BST benchmarks: O(log n) per operation
// ---------------------------------------------------------------------------

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

test "bench: fenwick 1M build + 1M queries" {
  let n = 1000000
  let arr = FixedArray::makei(n, fn(i) { i % 100 })
  let build_t = time_us(fn() {
    let _ = @fenwick.build(arr)
  })
  let ft = @fenwick.build(arr)
  let query_t = time_us(fn() {
    let mut sum = 0
    for i = 1; i <= n; i = i + 1 {
      sum = sum + @fenwick.query(ft, i)
    }
    // Prevent optimizer from removing the loop
    if sum < 0 { abort("unreachable") }
  })
  println("fenwick 1M build: " + fmt_us(build_t))
  println("fenwick 1M queries: " + fmt_us(query_t))
}

// ---------------------------------------------------------------------------
// Segment tree: O(n) build, O(log n) query/update
// ---------------------------------------------------------------------------

test "bench: segment_tree 100K build + 100K queries" {
  let n = 100000
  let arr = FixedArray::makei(n, fn(i) { i % 100 })
  let build_t = time_us(fn() {
    let _ = @segment_tree.build(arr)
  })
  let st = @segment_tree.build(arr)
  let query_t = time_us(fn() {
    let mut sum = 0
    for i = 0; i < n; i = i + 1 {
      sum = sum + @segment_tree.query(st, i, i + 1)
    }
    if sum < 0 { abort("unreachable") }
  })
  println("segment_tree 100K build: " + fmt_us(build_t))
  println("segment_tree 100K point queries: " + fmt_us(query_t))
}

test "bench: lazy segment_tree 100K range updates + queries" {
  let n = 100000
  let arr = FixedArray::make(n, 0)
  let st = @segment_tree.lazy_build(arr)
  let update_t = time_us(fn() {
    @segment_tree.lazy_update(st, 0, n, 1)
  })
  let query_t = time_us(fn() {
    let _ = @segment_tree.lazy_query(st, 0, n)
  })
  println("lazy_segment_tree 100K range update: " + fmt_us(update_t))
  println("lazy_segment_tree 100K range query: " + fmt_us(query_t))
}

// ---------------------------------------------------------------------------
// Union-Find: near-O(1) per operation with path compression
// ---------------------------------------------------------------------------

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
  let t = time_us(fn() {
    let _ = @dijkstra_heap.dijkstra(graph, n, 0)
  })
  println("dijkstra_heap 1000-node dense: " + fmt_us(t))
}

test "bench: scc 1000-node graph" {
  let n = 1000
  let graph = FixedArray::make(n * n, 0)
  // Create a graph with cycles
  for i = 0; i < n - 1; i = i + 1 {
    graph[i * n + (i + 1)] = 1
    graph[(i + 1) * n + i] = 1
  }
  let t = time_us(fn() {
    let _ = @scc.tarjan_scc(graph, n)
  })
  println("scc 1000-node: " + fmt_us(t))
}

test "bench: kruskal 1000-edge MST" {
  let n = 500
  let edges : Array[@kruskal.Edge] = []
  for i = 0; i < n - 1; i = i + 1 {
    edges.push(@kruskal.edge(i, i + 1, i + 1))
  }
  let edge_arr = FixedArray::from_array(edges.view())
  let t = time_us(fn() {
    let _ = @kruskal.kruskal_mst(edge_arr, n)
  })
  println("kruskal 500-node chain MST: " + fmt_us(t))
}

// ---------------------------------------------------------------------------
// String algorithms
// ---------------------------------------------------------------------------

test "bench: kmp search 100K text" {
  let mut text = ""
  for i = 0; i < 25000; i = i + 1 {
    text = text + "abcd"
  }
  // 100K chars
  let t = time_us(fn() {
    let _ = @kmp.kmp_search("abcdabcd", text)
  })
  println("kmp 100K text: " + fmt_us(t))
}

test "bench: suffix_array 10K string" {
  let mut s = ""
  for i = 0; i < 3333; i = i + 1 {
    s = s + "abc"
  }
  // ~10K chars
  let t = time_us(fn() {
    let _ = @suffix_array.build(s)
  })
  println("suffix_array 10K string: " + fmt_us(t))
}

// ---------------------------------------------------------------------------
// Number theory
// ---------------------------------------------------------------------------

test "bench: euler_sieve 1M primes" {
  let t = time_us(fn() {
    let _ = @euler_sieve.sieve(1000000)
  })
  println("euler_sieve 1M: " + fmt_us(t))
}

test "bench: miller_rabin 10000 primality checks" {
  let t = time_us(fn() {
    for n = 1; n <= 10000; n = n + 1 {
      let _ = @miller_rabin.is_prime(n)
    }
  })
  println("miller_rabin 10K checks: " + fmt_us(t))
}

test "bench: ntt multiply 1024-coefficient polynomials" {
  let a : Array[Int64] = []
  let b : Array[Int64] = []
  for i = 0; i < 1024; i = i + 1 {
    a.push(i.to_int64())
    b.push((i * 2).to_int64())
  }
  let t = time_us(fn() {
    let _ = @ntt.multiply(a, b)
  })
  println("ntt 1024-coefficient multiply: " + fmt_us(t))
}

// ---------------------------------------------------------------------------
// LIS: O(n log n) vs O(n²)
// ---------------------------------------------------------------------------

test "bench: lis 10K elements" {
  let n = 10000
  let xs = FixedArray::makei(n, fn(i) { (i * 7 + 3) % 1000 })
  let t = time_us(fn() {
    let _ = @lis.lis_length(xs)
  })
  println("lis 10K: " + fmt_us(t))
}

// ---------------------------------------------------------------------------
// Convex hull
// ---------------------------------------------------------------------------

test "bench: convex_hull 10K points" {
  let n = 10000
  let points : Array[@geometry_utils.Point] = []
  for i = 0; i < n; i = i + 1 {
    points.push(@geometry_utils.point((i * 7 + 3) % 1000, (i * 13 + 5) % 1000))
  }
  let t = time_us(fn() {
    let _ = @convex_hull.convex_hull(points)
  })
  println("convex_hull 10K points: " + fmt_us(t))
}
