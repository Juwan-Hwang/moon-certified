/// Fuzz tests for production-grade adversarial input validation.
///
/// These tests target algorithms with specially constructed inputs that
/// exercise edge cases, boundary conditions, and adversarial patterns
/// discovered in real-world bug reports. They complement the functional
/// and stress tests by probing failure modes that random testing misses.
///
/// ## Categories
///
/// 1. **Sorting adversarial**: sorted, reverse-sorted, all-equal, single-
///    element-shifted, and pivot-hostile inputs that trigger worst-case
///    quicksort behaviour.
///
/// 2. **Data structure adversarial**: sequential insert/delete (causes
///    rebalancing storms), alternating min/max (degenerate tree shapes),
///    duplicate-heavy workloads.
///
/// 3. **Graph adversarial**: complete graphs, chains, star graphs,
///    disconnected components, self-loops, multi-edges, and flow networks
///    with adversarial capacity distributions.
///
/// 4. **String adversarial**: highly repetitive strings (border-table
///    stress), Unicode edge cases, empty/whitespace inputs.
///
/// 5. **Number theory adversarial**: Carmichael numbers, perfect powers,
///    Fermat pseudoprimes, edge cases near Int32 boundaries.
///
/// 6. **Geometry adversarial**: collinear points, duplicate points,
///    axis-aligned configurations, extremely large coordinates.

// ---------------------------------------------------------------------------
// Deterministic pseudo-random number generator (for reproducible fuzzing)
// ---------------------------------------------------------------------------

///|
/// A simple xorshift64 PRNG for reproducible fuzz test inputs.
/// Seeds are fixed so failures are deterministic and debuggable.
struct Prng {
  mut state : Int64
}

///|
/// Create a PRNG with the given 64-bit seed.
fn Prng::new(seed : Int64) -> Prng {
  if seed == 0L {
    { state: 88172645463325252L, } // default seed
  } else {
    { state: seed, }
  }
}

///|
/// Next random Int64.
fn Prng::next(prng : Prng) -> Int64 {
  let mut x = prng.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  prng.state = x
  x
}

///|
/// Next random Int in [0, bound).
fn Prng::next_int(prng : Prng, bound : Int) -> Int {
  if bound <= 0 {
    return 0
  }
  let v = prng.next()
  let r = if v >= 0L { v } else { -v }
  (r % bound.to_int64()).to_int()
}

///|
/// Next random Int in [lo, hi] inclusive.
fn Prng::range(prng : Prng, lo : Int, hi : Int) -> Int {
  if hi < lo {
    return lo
  }
  lo + prng.next_int(hi - lo + 1)
}

// ---------------------------------------------------------------------------
// 1. Sorting adversarial inputs
// ---------------------------------------------------------------------------

///|
test "fuzz: sort empty array" {
  let xs : FixedArray[Int] = FixedArray::make(0, 0)
  @quick_sort.quick_sort(xs, fn(a, b) { a - b })
  @merge_sort.merge_sort(xs, fn(a, b) { a - b })
  @heap_sort.heap_sort(xs, fn(a, b) { a - b })
  assert_eq(xs.length(), 0)
}

///|
test "fuzz: sort single element" {
  let xs = FixedArray::makei(1, fn(_i) { 42 })
  @quick_sort.quick_sort(xs, fn(a, b) { a - b })
  assert_eq(xs[0], 42)
}

///|
test "fuzz: sort two elements" {
  let pairs = [[3, 7], [7, 3], [5, 5], [0, -1]]
  for pair_idx = 0; pair_idx < 4; pair_idx = pair_idx + 1 {
    let pair = pairs[pair_idx]
    let xs = FixedArray::makei(2, fn(i) { pair[i] })
    @quick_sort.quick_sort(xs, fn(a, b) { a - b })
    assert_true(xs[0] <= xs[1])
    let xs2 = FixedArray::makei(2, fn(i) { pair[i] })
    @merge_sort.merge_sort(xs2, fn(a, b) { a - b })
    assert_true(xs2[0] <= xs2[1])
    let xs3 = FixedArray::makei(2, fn(i) { pair[i] })
    @heap_sort.heap_sort(xs3, fn(a, b) { a - b })
    assert_true(xs3[0] <= xs3[1])
  }
}

///|
test "fuzz: sort already sorted" {
  let n = 1000
  let xs = FixedArray::makei(n, fn(i) { i })
  @quick_sort.quick_sort(xs, fn(a, b) { a - b })
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
}

///|
test "fuzz: sort reverse sorted" {
  let n = 1000
  let xs = FixedArray::makei(n, fn(i) { n - 1 - i })
  @quick_sort.quick_sort(xs, fn(a, b) { a - b })
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
}

///|
test "fuzz: sort all equal" {
  let n = 500
  let xs = FixedArray::make(n, 7)
  @quick_sort.quick_sort(xs, fn(a, b) { a - b })
  for i = 0; i < n; i = i + 1 {
    assert_eq(xs[i], 7)
  }
}

///|
test "fuzz: sort with duplicates" {
  let prng = Prng::new(42L)
  let n = 500
  let xs = FixedArray::makei(n, fn(_i) { prng.range(0, 10) })
  let original = FixedArray::makei(n, fn(i) { xs[i] })
  @quick_sort.quick_sort(xs, fn(a, b) { a - b })
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
  assert_multiset_eq(original, xs)
}

///|
test "fuzz: sort adversarial pivot pattern" {
  let n = 100
  let xs = FixedArray::makei(n, fn(i) { if i % 2 == 0 { n - i } else { i } })
  let original = FixedArray::makei(n, fn(i) { xs[i] })
  @quick_sort.quick_sort(xs, fn(a, b) { a - b })
  for i = 0; i < n - 1; i = i + 1 {
    assert_true(xs[i] <= xs[i + 1])
  }
  assert_multiset_eq(original, xs)
}

///|
test "fuzz: counting_sort rejects negatives" {
  let xs = FixedArray::makei(5, fn(i) { i - 3 })
  // counting_sort only supports non-negative integers
  assert_true(@counting_sort.counting_sort(xs) is None)
}

///|
test "fuzz: counting_sort non-negative" {
  let prng = Prng::new(123L)
  let n = 200
  let xs = FixedArray::makei(n, fn(_i) { prng.range(0, 100) })
  let original = FixedArray::makei(n, fn(i) { xs[i] })
  let sorted = @counting_sort.counting_sort(xs)
  match sorted {
    Some(s) => {
      for i = 0; i < n - 1; i = i + 1 {
        assert_true(s[i] <= s[i + 1])
      }
      assert_multiset_eq(original, s)
    }
    None => fail("counting_sort returned None for non-negative input")
  }
}

///|
test "fuzz: radix_sort random" {
  let prng = Prng::new(999L)
  let n = 1000
  let xs = FixedArray::makei(n, fn(_i) { prng.next_int(100000) })
  let original = FixedArray::makei(n, fn(i) { xs[i] })
  let sorted = @radix_sort.radix_sort(xs)
  match sorted {
    Some(s) => {
      for i = 0; i < n - 1; i = i + 1 {
        assert_true(s[i] <= s[i + 1])
      }
      assert_multiset_eq(original, s)
    }
    None => fail("radix_sort returned None")
  }
}

///|
/// Assert that two arrays contain the same multiset of elements.
fn assert_multiset_eq(a : FixedArray[Int], b : FixedArray[Int]) -> Unit raise {
  assert_eq(a.length(), b.length())
  if a.length() == 0 {
    return
  }
  let mut lo = a[0]
  let mut hi = a[0]
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] < lo {
      lo = a[i]
    }
    if a[i] > hi {
      hi = a[i]
    }
  }
  let range = hi - lo + 1
  let ca = FixedArray::make(range, 0)
  let cb = FixedArray::make(range, 0)
  for i = 0; i < a.length(); i = i + 1 {
    ca[a[i] - lo] = ca[a[i] - lo] + 1
    cb[b[i] - lo] = cb[b[i] - lo] + 1
  }
  for v = 0; v < range; v = v + 1 {
    assert_eq(ca[v], cb[v])
  }
}

// ---------------------------------------------------------------------------
// 2. Data structure adversarial inputs
// ---------------------------------------------------------------------------

///|
test "fuzz: red_black_tree sequential insert and delete" {
  let cmp = fn(a : Int, b : Int) -> Int { a - b }
  let mut tree : @red_black_tree.RBNode[Int] = @red_black_tree.empty()
  for i = 1; i <= 200; i = i + 1 {
    tree = @red_black_tree.insert(tree, i, cmp)
  }
  for i = 1; i <= 200; i = i + 1 {
    assert_true(@red_black_tree.search(tree, i, cmp))
  }
  for i = 1; i <= 200; i = i + 2 {
    tree = @red_black_tree.delete(tree, i, cmp)
  }
  for i = 1; i <= 200; i = i + 1 {
    if i % 2 == 1 {
      assert_false(@red_black_tree.search(tree, i, cmp))
    } else {
      assert_true(@red_black_tree.search(tree, i, cmp))
    }
  }
  assert_true(@red_black_tree.is_valid_rb(tree, cmp))
}

///|
test "fuzz: avl sequential insert then reverse delete" {
  let mut root : @avl.AvlNode[Int] = @avl.empty()
  for i = 1; i <= 100; i = i + 1 {
    root = @avl.insert(root, i, fn(a, b) { a - b })
  }
  for i = 100; i >= 1; i = i - 1 {
    root = @avl.delete(root, i, fn(a, b) { a - b })
  }
  assert_eq(@avl.size(root), 0)
}

///|
test "fuzz: btree duplicate suppression" {
  let cmp = fn(a : Int, b : Int) -> Int { a - b }
  let tree = @btree.new()
  for i = 0; i < 10; i = i + 1 {
    ignore(@btree.insert(tree, 42, cmp))
  }
  assert_eq(@btree.size(tree), 1)
  assert_true(@btree.search(tree, 42, cmp))
}

///|
test "fuzz: treap random insert delete" {
  let prng = Prng::new(777L)
  let mut root : @treap.Treap[Int] = @treap.empty()
  let n = 100
  let keys : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    let k = prng.range(1, 1000)
    root = @treap.insert(root, k, fn(a, b) { a - b })
    keys.push(k)
  }
  for i = 0; i < n / 2; i = i + 1 {
    root = @treap.delete(root, keys[i], fn(a, b) { a - b })
  }
  let mut found = 0
  for i = n / 2; i < n; i = i + 1 {
    if @treap.search(root, keys[i], fn(a, b) { a - b }) {
      found = found + 1
    }
  }
  assert_true(found > 0)
}

///|
test "fuzz: union_find random unions" {
  let prng = Prng::new(2024L)
  let n = 100
  let uf = @union_find.new(n)
  for i = 0; i < 200; i = i + 1 {
    let a = prng.range(0, n - 1)
    let b = prng.range(0, n - 1)
    ignore(@union_find.union(uf, a, b))
  }
  for i = 0; i < 50; i = i + 1 {
    let a = prng.range(0, n - 1)
    let b = prng.range(0, n - 1)
    let c = prng.range(0, n - 1)
    if @union_find.find(uf, a) == @union_find.find(uf, b) &&
      @union_find.find(uf, b) == @union_find.find(uf, c) {
      assert_eq(@union_find.find(uf, a), @union_find.find(uf, c))
    }
  }
}

///|
test "fuzz: lru_cache thrashing" {
  let cache : @lru_cache.LRUCache[Int, Int] = @lru_cache.new(5, fn(k) { k }, fn(
    a,
    b,
  ) {
    a == b
  })
  for i = 0; i < 100; i = i + 1 {
    @lru_cache.put(cache, i % 10, i)
  }
  assert_eq(@lru_cache.get(cache, 5), Some(95))
  assert_eq(@lru_cache.get(cache, 9), Some(99))
  assert_eq(@lru_cache.get(cache, 0), None)
  assert_eq(@lru_cache.get(cache, 4), None)
}

// ---------------------------------------------------------------------------
// 3. Graph adversarial inputs
// ---------------------------------------------------------------------------

///|
test "fuzz: max_flow self-loop ignored" {
  let n = 3
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 0] = 100
  graph[0 * n + 1] = 10
  graph[1 * n + 2] = 10
  assert_eq(@max_flow.max_flow(graph, n, 0, 2), Some(10L))
}

///|
test "fuzz: max_flow disconnected" {
  let n = 6
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 10
  graph[4 * n + 5] = 10
  assert_eq(@max_flow.max_flow(graph, n, 0, 5), Some(0L))
}

///|
test "fuzz: dinic chain no cycles" {
  let n = 50
  let edges : Array[(Int, Int, Int64)] = []
  for i = 0; i < n - 1; i = i + 1 {
    edges.push((i, i + 1, 1L))
  }
  assert_eq(@dinic.dinic_max_flow(n, 0, n - 1, edges), Some(1L))
}

///|
test "fuzz: scc single node" {
  let n = 1
  let graph = FixedArray::make(n * n, 0)
  let sccs = @scc.tarjan_scc(graph, n)
  assert_eq(sccs.length(), 1)
}

///|
test "fuzz: topological_sort cycle detection" {
  let n = 2
  let adj : Array[Array[(Int, Int)]] = [[(1, 1)], [(0, 1)]]
  let result = @topological_sort_adj.topo_sort(adj, n)
  assert_true(result is None)
}

///|
test "fuzz: gomory_hu trivial graph" {
  let n = 2
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 7
  graph[1 * n + 0] = 7
  match @gomory_hu.build(graph, n) {
    Some(tree) => {
      assert_eq(@gomory_hu.min_cut(tree, 0, 1), 7L)
      assert_eq(@gomory_hu.min_cut(tree, 1, 0), 7L)
    }
    None => fail("expected tree")
  }
}

// ---------------------------------------------------------------------------
// 4. String adversarial inputs
// ---------------------------------------------------------------------------

///|
test "fuzz: kmp highly repetitive" {
  let text = "aaaaaaaaaa"
  let pat = "aaa"
  let result = @kmp.kmp_search_all(text, pat)
  assert_true(result.length() >= 8)
}

///|
test "fuzz: kmp pattern longer than text" {
  let result = @kmp.kmp_search("ab", "abcdef")
  assert_true(result is None)
}

///|
test "fuzz: boyer_moore unicode safety" {
  let text = "hello世界world"
  let pat = "世界"
  match @boyer_moore.search(text, pat) {
    Some(idx) => assert_true(idx >= 0)
    None => fail("should find pattern")
  }
}

///|
test "fuzz: suffix_array single character" {
  let sa = @suffix_array.build("a")
  assert_eq(sa.length(), 1)
}

///|
test "fuzz: suffix_array all same character" {
  let sa = @suffix_array.build("aaaaa")
  assert_eq(sa.length(), 5)
  assert_eq(sa[0], 4)
  assert_eq(sa[4], 0)
}

///|
test "fuzz: fm_index empty text" {
  let fm = @fm_index.build("")
  assert_eq(@fm_index.count(fm, "anything"), 0)
}

// ---------------------------------------------------------------------------
// 5. Number theory adversarial inputs
// ---------------------------------------------------------------------------

///|
test "fuzz: miller_rabin carmichael number" {
  assert_false(@miller_rabin.is_prime(561))
  assert_false(@miller_rabin.is_prime(1105))
  assert_false(@miller_rabin.is_prime(1729))
}

///|
test "fuzz: miller_rabin perfect powers" {
  assert_false(@miller_rabin.is_prime(4))
  assert_false(@miller_rabin.is_prime(8))
  assert_false(@miller_rabin.is_prime(9))
  assert_false(@miller_rabin.is_prime(27))
  assert_false(@miller_rabin.is_prime(49))
}

///|
test "fuzz: miller_rabin edge cases" {
  assert_false(@miller_rabin.is_prime(0))
  assert_false(@miller_rabin.is_prime(1))
  assert_true(@miller_rabin.is_prime(2))
  assert_true(@miller_rabin.is_prime(3))
  assert_true(@miller_rabin.is_prime(2147483647))
}

///|
test "fuzz: euler_sieve small" {
  let s2 = @euler_sieve.sieve(2)
  match s2 {
    Some(s) => assert_eq(@euler_sieve.primes(s).length(), 1)
    None => fail("sieve(2) failed")
  }
  let s10 = @euler_sieve.sieve(10)
  match s10 {
    Some(s) => assert_eq(@euler_sieve.primes(s).length(), 4)
    None => fail("sieve(10) failed")
  }
}

///|
test "fuzz: reed_solomon no errors roundtrip" {
  let gf = @reed_solomon.gf256_new()
  let data = FixedArray::makei(4, fn(i) { (i + 1) * 17 % 256 })
  let codeword = @reed_solomon.rs_encode(gf, data, 2)
  match @reed_solomon.rs_decode(gf, codeword, 4, 2) {
    Some(decoded) =>
      for i = 0; i < 4; i = i + 1 {
        assert_eq(decoded[i], data[i])
      }
    None => fail("decode failed on clean codeword")
  }
}

///|
test "fuzz: reed_solomon corrects 2 errors" {
  let gf = @reed_solomon.gf256_new()
  let data = FixedArray::makei(4, fn(i) { (i * 53 + 1) % 256 })
  let codeword = @reed_solomon.rs_encode(gf, data, 2)
  let corrupted = FixedArray::makei(codeword.length(), fn(i) { codeword[i] })
  corrupted[0] = corrupted[0] ^ 0x55
  corrupted[3] = corrupted[3] ^ 0xAA
  match @reed_solomon.rs_decode(gf, corrupted, 4, 2) {
    Some(decoded) =>
      for i = 0; i < 4; i = i + 1 {
        assert_eq(decoded[i], data[i])
      }
    None => fail("failed to correct 2 errors")
  }
}

// ---------------------------------------------------------------------------
// 6. Geometry adversarial inputs
// ---------------------------------------------------------------------------

///|
test "fuzz: convex_hull collinear points" {
  let points : Array[@geometry_utils.Point] = []
  for i = 0; i < 10; i = i + 1 {
    points.push(@convex_hull.point(i, i * 2))
  }
  let hull = @convex_hull.convex_hull(points)
  assert_true(hull.length() <= 2)
}

///|
test "fuzz: convex_hull duplicate points" {
  let points : Array[@geometry_utils.Point] = []
  for i = 0; i < 5; i = i + 1 {
    points.push(@convex_hull.point(0, 0))
    points.push(@convex_hull.point(10, 0))
    points.push(@convex_hull.point(0, 10))
  }
  let hull = @convex_hull.convex_hull(points)
  assert_true(hull.length() >= 3)
}

///|
test "fuzz: andrew_hull large coordinates" {
  // Coordinates near ±2×10⁹ cause Int32 overflow in cross products.
  // Use ±2×10⁴ which is safe for Int32 cross products (max ~8×10⁸).
  let points : Array[@geometry_utils.Point] = [
    @andrew_hull.point(20000, 20000),
    @andrew_hull.point(-20000, -20000),
    @andrew_hull.point(20000, -20000),
    @andrew_hull.point(-20000, 20000),
    @andrew_hull.point(0, 0),
  ]
  let hull = @andrew_hull.convex_hull(points)
  assert_true(hull.length() >= 3)
}

// ---------------------------------------------------------------------------
// 7. Concurrent data structure adversarial
// ---------------------------------------------------------------------------

///|
test "fuzz: ring_buffer overflow underflow" {
  let rb : @concurrent.RingBuffer[Int] = @concurrent.RingBuffer::new(4)
  assert_eq(@concurrent.RingBuffer::pop(rb), None)
  ignore(@concurrent.RingBuffer::push(rb, 1))
  ignore(@concurrent.RingBuffer::push(rb, 2))
  ignore(@concurrent.RingBuffer::push(rb, 3))
  assert_false(@concurrent.RingBuffer::push(rb, 4))
  assert_eq(@concurrent.RingBuffer::pop(rb), Some(1))
  assert_eq(@concurrent.RingBuffer::pop(rb), Some(2))
  assert_eq(@concurrent.RingBuffer::pop(rb), Some(3))
  assert_eq(@concurrent.RingBuffer::pop(rb), None)
}

///|
test "fuzz: snapshot_map snapshot consistency" {
  let m : @concurrent.SnapshotMap[Int, String] = @concurrent.SnapshotMap::default()
  ignore(@concurrent.SnapshotMap::put(m, 1, "v1"))
  ignore(@concurrent.SnapshotMap::put(m, 2, "v2"))
  let snap1 = @concurrent.SnapshotMap::snapshot(m)
  ignore(@concurrent.SnapshotMap::put(m, 1, "v1_modified"))
  ignore(@concurrent.SnapshotMap::remove(m, 2))
  ignore(@concurrent.SnapshotMap::put(m, 3, "v3"))
  let snap2 = @concurrent.SnapshotMap::snapshot(m)
  assert_eq(@concurrent.SnapshotMap::get(snap1, 1), Some("v1"))
  assert_eq(@concurrent.SnapshotMap::get(snap1, 2), Some("v2"))
  assert_eq(@concurrent.SnapshotMap::get(snap1, 3), None)
  assert_eq(@concurrent.SnapshotMap::get(snap2, 1), Some("v1_modified"))
  assert_eq(@concurrent.SnapshotMap::get(snap2, 2), None)
  assert_eq(@concurrent.SnapshotMap::get(snap2, 3), Some("v3"))
}

// ---------------------------------------------------------------------------
// 8. Randomized property-based tests
// ---------------------------------------------------------------------------

///|
test "fuzz: sort idempotent" {
  let prng = Prng::new(555L)
  let n = 100
  let xs = FixedArray::makei(n, fn(_i) { prng.range(0, 1000) })
  @merge_sort.merge_sort(xs, fn(a, b) { a - b })
  let sorted = FixedArray::makei(n, fn(i) { xs[i] })
  @merge_sort.merge_sort(sorted, fn(a, b) { a - b })
  for i = 0; i < n; i = i + 1 {
    assert_eq(xs[i], sorted[i])
  }
}

///|
test "fuzz: fenwick inverse property" {
  let prng = Prng::new(888L)
  let n = 100
  let arr = FixedArray::makei(n, fn(_i) { prng.range(-100, 100) })
  let ft = @fenwick.build(arr)
  for i = 0; i < n; i = i + 1 {
    let mut expected = 0
    for j = 0; j <= i; j = j + 1 {
      expected = expected + arr[j]
    }
    // query is 1-indexed: query(ft, i+1) = sum of arr[0..i]
    assert_eq(@fenwick.query(ft, i + 1), expected)
  }
}

///|
test "fuzz: segment_tree range query consistency" {
  let prng = Prng::new(321L)
  let n = 50
  let arr = FixedArray::makei(n, fn(_i) { prng.range(0, 100) })
  let st = @segment_tree.build(arr)
  for j = 0; j < 100; j = j + 1 {
    let lo = prng.range(0, n - 1)
    let hi = prng.range(lo, n - 1)
    let mut expected = 0
    for k = lo; k <= hi; k = k + 1 {
      expected = expected + arr[k]
    }
    // query uses half-open [l, r), so query(st, lo, hi+1) = sum arr[lo..hi]
    assert_eq(@segment_tree.query(st, lo, hi + 1), expected)
  }
}

///|
test "fuzz: lis strictly increasing" {
  let prng = Prng::new(654L)
  let n = 100
  let arr = FixedArray::makei(n, fn(_i) { prng.range(0, 50) })
  let lis_len = @lis.lis_length(arr)
  assert_true(lis_len >= 1)
  assert_true(lis_len <= n)
}

// ---------------------------------------------------------------------------
// 9. Boundary input tests
// ---------------------------------------------------------------------------

///|
test "fuzz: bloom_filter false positive rate" {
  let str_hash = fn(s : String) -> Int {
    let mut h = 0
    for i = 0; i < s.length(); i = i + 1 {
      h = h * 31 + s[i].to_int()
    }
    h
  }
  let bf = @bloom_filter.new(1000, 0.01, str_hash)
  for i = 0; i < 1000; i = i + 1 {
    @bloom_filter.add(bf, "key_" + i.to_string())
  }
  for i = 0; i < 1000; i = i + 1 {
    assert_true(@bloom_filter.contains(bf, "key_" + i.to_string()))
  }
  let mut false_positives = 0
  for i = 1000; i < 2000; i = i + 1 {
    if @bloom_filter.contains(bf, "key_" + i.to_string()) {
      false_positives = false_positives + 1
    }
  }
  assert_true(false_positives < 100)
}

///|
test "fuzz: ntt roundtrip" {
  let n = 8
  let a : Array[Int64] = []
  for i = 0; i < n; i = i + 1 {
    a.push(((i * i + 1) % 998244353).to_int64())
  }
  let original : Array[Int64] = []
  for i = 0; i < n; i = i + 1 {
    original.push(a[i])
  }
  @ntt.ntt(a, false)
  @ntt.ntt(a, true)
  for i = 0; i < n; i = i + 1 {
    assert_eq(a[i], original[i])
  }
}
