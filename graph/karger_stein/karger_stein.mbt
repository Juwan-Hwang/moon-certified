///|
/// Karger-Stein Global Minimum Cut — a randomized algorithm for finding the
/// minimum cut in an undirected graph.
///
/// The minimum cut (min-cut) of an undirected graph is the smallest set of
/// edges whose removal disconnects the graph into two non-empty parts.
///
/// ## Algorithms
///
/// ### Karger's Contraction Algorithm
///
/// 1. While more than 2 vertices remain, pick a random edge and **contract**
///    its endpoints into a single super-vertex (merging their edges, removing
///    self-loops).
/// 2. When 2 super-vertices remain, the edges between them form a cut.
/// 3. Repeat for many trials and return the minimum cut found.
///
/// Each trial succeeds with probability ≥ 1/n². Running O(n² log n) trials
/// gives high probability of finding the min cut.
///
/// ### Karger-Stein Improvement
///
/// Instead of contracting all the way to 2 vertices, contract to
/// ⌈1 + n/√2⌉ vertices, then **recursively** run the algorithm twice on the
/// contracted graph and return the better result. This reduces the number of
/// trials needed to O(log² n) while maintaining high success probability.
///
/// ## Complexity
///
/// | Variant          | Time per trial | Trials needed  |
/// |------------------|----------------|----------------|
/// | Basic Karger     | O(n²)          | O(n² log n)   |
/// | Karger-Stein     | O(n² log n)    | O(log² n)     |
///
/// ## Weighted Graphs
///
/// Edge weights are treated as edge multiplicities: an edge of weight `w`
/// contributes `w` to the cut value. Edge selection is uniform over active
/// edges (edges whose endpoints are in different super-vertices).
///
/// ## References
///
/// - Karger, D. R. (1993). "Global min-cuts in RNC, and other ramifications
///   of a simple min-cut algorithm." *SODA '93*, 21–30.
/// - Karger, D. R. & Stein, C. (1996). "A new approach to the minimum cut
///   problem." *J. ACM*, 43(4), 601–640.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.
const INF : Double = 1.0e18

// ---------------------------------------------------------------------------
// Union-Find with copy support
// ---------------------------------------------------------------------------

///|
priv struct UF {
  parent : Array[Int]
  mut count : Int
}

///|
fn uf_new(n : Int) -> UF {
  let parent = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    parent[i] = i
  }
  { parent, count: n }
}

///|
fn uf_find(uf : UF, x : Int) -> Int {
  let mut root = x
  while uf.parent[root] != root {
    root = uf.parent[root]
  }
  // Path compression
  let mut cur = x
  while uf.parent[cur] != root {
    let next = uf.parent[cur]
    uf.parent[cur] = root
    cur = next
  }
  root
}

///|
fn uf_union(uf : UF, x : Int, y : Int) -> Bool {
  let rx = uf_find(uf, x)
  let ry = uf_find(uf, y)
  if rx == ry {
    return false
  }
  // Simple union (no rank, since we need copy to be exact)
  uf.parent[ry] = rx
  uf.count = uf.count - 1
  true
}

///|
fn uf_copy(uf : UF) -> UF {
  let n = uf.parent.length()
  let parent = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    parent[i] = uf.parent[i]
  }
  { parent, count: uf.count }
}

// ---------------------------------------------------------------------------
// PRNG — xorshift64
// ---------------------------------------------------------------------------

///|
priv struct Rng {
  mut state : UInt64
}

///|
fn rng_new(seed : UInt64) -> Rng {
  let s = if seed == 0UL { 0xDEADBEEFCAFEBABEUL } else { seed }
  let mut state = s
  // Warm up: diffuse small seeds so high bits have full entropy.
  for i = 0; i < 8; i = i + 1 {
    state = state ^ (state << 13)
    state = state ^ (state >> 7)
    state = state ^ (state << 17)
  }
  if state == 0UL {
    state = 0xDEADBEEFCAFEBABEUL
  }
  { state, }
}

///|
fn rng_next_uint64(rng : Rng) -> UInt64 {
  let mut x = rng.state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  rng.state = x
  x
}

///|
fn rng_next_int(rng : Rng, n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if n == 1 {
    return 0
  }
  // Use modulo on raw 64-bit state. For n ≤ 2^32, bias < 2^-32 — negligible.
  let x = rng_next_uint64(rng)
  (x % n.to_uint64()).reinterpret_as_int64().to_int()
}

// ---------------------------------------------------------------------------
// Edge shuffling (Fisher-Yates)
// ---------------------------------------------------------------------------

///|
/// Return a shuffled copy of `0 .. n-1` using Fisher-Yates.
fn shuffle_indices(n : Int, rng : Rng) -> Array[Int] {
  let arr = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    arr[i] = i
  }
  for i = n - 1; i > 0; i = i - 1 {
    let j = rng_next_int(rng, i + 1)
    let tmp = arr[i]
    arr[i] = arr[j]
    arr[j] = tmp
  }
  arr
}

// ---------------------------------------------------------------------------
// Cut counting
// ---------------------------------------------------------------------------

///|
/// Sum the weights of edges whose endpoints are in different super-vertices.
fn count_cut(edges : Array[(Int, Int, Double)], uf : UF) -> Double {
  let mut total = 0.0
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v, w) = edges[i]
    if uf_find(uf, u) != uf_find(uf, v) {
      total = total + w
    }
  }
  total
}

// ---------------------------------------------------------------------------
// Karger-Stein recursive core
// ---------------------------------------------------------------------------

// sqrt(2) ≈ 1.4142135623730951

///|
const SQRT2 : Double = 1.4142135623730951

///|
/// Recursive Karger-Stein contraction.
///
/// Contracts random edges until `⌈1 + n/√2⌉` super-vertices remain, then
/// recurses twice and returns the better result. Base case: when ≤ 6
/// super-vertices remain, contract to 2 and count the cut.
fn karger_stein_recursive(
  edges : Array[(Int, Int, Double)],
  uf : UF,
  num_vertices : Int,
  rng : Rng,
) -> Double {
  if num_vertices <= 2 {
    return count_cut(edges, uf)
  }
  // Base case: small enough to contract directly to 2.
  if num_vertices <= 6 {
    let indices = shuffle_indices(edges.length(), rng)
    let mut current = num_vertices
    for idx = 0; idx < indices.length() && current > 2; idx = idx + 1 {
      let eid = indices[idx]
      let (u, v, _) = edges[eid]
      if uf_union(uf, u, v) {
        current = current - 1
      }
    }
    return count_cut(edges, uf)
  }
  // Target: contract to ⌈1 + n/√2⌉ super-vertices.
  let target = (1.0 + num_vertices.to_double() / SQRT2 + 0.999999999).to_int()
  let t = if target >= num_vertices { num_vertices - 1 } else { target }
  // Contract random edges until t super-vertices remain.
  let indices = shuffle_indices(edges.length(), rng)
  let mut current = num_vertices
  for idx = 0; idx < indices.length() && current > t; idx = idx + 1 {
    let eid = indices[idx]
    let (u, v, _) = edges[eid]
    if uf_union(uf, u, v) {
      current = current - 1
    }
  }
  if current <= 2 {
    return count_cut(edges, uf)
  }
  // Recurse twice on copies of the contraction state.
  let uf1 = uf_copy(uf)
  let uf2 = uf_copy(uf)
  let r1 = karger_stein_recursive(edges, uf1, current, rng)
  let r2 = karger_stein_recursive(edges, uf2, current, rng)
  if r1 < r2 {
    r1
  } else {
    r2
  }
}

// ---------------------------------------------------------------------------
// Partition recovery
// ---------------------------------------------------------------------------

///|
/// Recover the bipartition from a union-find state with exactly 2 roots.
///
/// Returns an array where `partition[i]` is 0 or 1 indicating which side of
/// the cut vertex `i` belongs to. If the union-find has ≠ 2 roots, all
/// vertices are assigned to side 0.
fn recover_partition(uf : UF, n : Int) -> Array[Int] {
  let partition = Array::make(n, 0)
  let mut root0 = -1
  let mut root1 = -1
  for i = 0; i < n; i = i + 1 {
    let r = uf_find(uf, i)
    if root0 == -1 {
      root0 = r
    } else if r != root0 && root1 == -1 {
      root1 = r
    }
  }
  if root1 == -1 {
    return partition
  }
  for i = 0; i < n; i = i + 1 {
    let r = uf_find(uf, i)
    partition[i] = if r == root0 { 0 } else { 1 }
  }
  partition
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Result of a Karger-Stein min-cut computation.
pub struct MinCutResult {
  /// The minimum cut value found (sum of edge weights crossing the cut).
  cut_value : Double
  /// Bipartition: `partition[i]` is 0 or 1 indicating which side vertex `i`
  /// is on.
  partition : Array[Int]
  /// Number of trials executed.
  trials : Int
}

///|
/// Find the global minimum cut of an undirected weighted graph using the
/// Karger-Stein randomized algorithm.
///
/// # Parameters
/// - `n`: Number of vertices, indexed `0 .. n − 1`.
/// - `edges`: Weighted undirected edges as `(u, v, weight)` tuples. Edges
///   with endpoints outside `[0, n)` or non-positive weight are silently
///   skipped. Self-loops are ignored.
/// - `seed`: Seed for the deterministic PRNG. The same seed always produces
///   the same result.
/// - `num_trials`: Number of independent trials. More trials increase the
///   probability of finding the true minimum cut. The algorithm runs each
///   trial independently and returns the best (smallest) cut found.
///
/// # Returns
/// A `MinCutResult` containing the cut value, bipartition, and trial count.
///
/// # Determinism
/// Fully deterministic given the same `seed` and `num_trials`.
///
/// # Complexity
/// O(num_trials · n² · log n) time, O(n + E) space per trial.
pub fn karger_stein(
  n : Int,
  edges : Array[(Int, Int, Double)],
  seed : UInt64,
  num_trials : Int,
) -> MinCutResult {
  if n <= 1 {
    return { cut_value: 0.0, partition: Array::make(n, 0), trials: 0 }
  }
  // Filter valid edges (no self-loops, in-range, positive weight).
  let clean_edges : Array[(Int, Int, Double)] = []
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v, w) = edges[i]
    if u >= 0 && u < n && v >= 0 && v < n && u != v && w > 0.0 {
      clean_edges.push((u, v, w))
    }
  }
  if clean_edges.length() == 0 {
    return { cut_value: 0.0, partition: Array::make(n, 0), trials: 0 }
  }
  let mut best_cut = INF
  let mut best_partition = Array::make(n, 0)
  let trials = if num_trials < 1 { 1 } else { num_trials }
  for trial = 0; trial < trials; trial = trial + 1 {
    let rng = rng_new(seed + trial.to_uint64())
    let uf = uf_new(n)
    let cut = karger_stein_recursive(clean_edges, uf, n, rng)
    if cut < best_cut {
      best_cut = cut
      best_partition = recover_partition(uf, n)
    }
  }
  { cut_value: best_cut, partition: best_partition, trials }
}

///|
/// Find the global minimum cut with default parameters.
///
/// Equivalent to `karger_stein(n, edges, 42, max(n², 10))` — uses a fixed
/// seed and enough trials for high probability of finding the true min cut.
pub fn karger_stein_default(
  n : Int,
  edges : Array[(Int, Int, Double)],
) -> MinCutResult {
  let trials = if n < 4 { 10 } else { n * n }
  karger_stein(n, edges, 42UL, trials)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
fn uw(pairs : Array[(Int, Int)]) -> Array[(Int, Int, Double)] {
  let r : Array[(Int, Int, Double)] = []
  for i = 0; i < pairs.length(); i = i + 1 {
    let (u, v) = pairs[i]
    r.push((u, v, 1.0))
  }
  r
}

///|
test "karger_stein: empty graph" {
  let result = karger_stein_default(0, [])
  assert_true(result.cut_value == 0.0)
}

///|
test "karger_stein: single vertex" {
  let result = karger_stein_default(1, [])
  assert_true(result.cut_value == 0.0)
}

///|
test "karger_stein: single edge" {
  let result = karger_stein_default(2, [(0, 1, 1.0)])
  assert_true(result.cut_value == 1.0)
  assert_true(result.partition[0] != result.partition[1])
}

///|
test "karger_stein: triangle min cut is 2" {
  let edges = uw([(0, 1), (1, 2), (0, 2)])
  let result = karger_stein(3, edges, 42UL, 50)
  assert_true(result.cut_value == 2.0)
}

///|
test "karger_stein: K4 min cut is 3" {
  let edges = uw([(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)])
  let result = karger_stein(4, edges, 42UL, 100)
  assert_true(result.cut_value == 3.0)
}

///|
test "karger_stein: two triangles bridge min cut is 1" {
  let edges = uw([
    (0, 1),
    (1, 2),
    (0, 2), // triangle A
    (3, 4),
    (4, 5),
    (3, 5), // triangle B
    (2, 3), // bridge
  ])
  let result = karger_stein(6, edges, 42UL, 200)
  assert_true(result.cut_value == 1.0)
}

///|
test "karger_stein: square min cut is 2" {
  let edges = uw([(0, 1), (1, 2), (2, 3), (3, 0)])
  let result = karger_stein(4, edges, 42UL, 100)
  assert_true(result.cut_value == 2.0)
}

///|
test "karger_stein: K5 min cut is 4" {
  let edges = uw([
    (0, 1),
    (0, 2),
    (0, 3),
    (0, 4),
    (1, 2),
    (1, 3),
    (1, 4),
    (2, 3),
    (2, 4),
    (3, 4),
  ])
  let result = karger_stein(5, edges, 42UL, 100)
  assert_true(result.cut_value == 4.0)
}

///|
test "karger_stein: weighted graph" {
  // Two triangles connected by a weight-5 bridge
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 1.0),
    (1, 2, 1.0),
    (0, 2, 1.0),
    (3, 4, 1.0),
    (4, 5, 1.0),
    (3, 5, 1.0),
    (2, 3, 5.0),
  ]
  let result = karger_stein(6, edges, 42UL, 200)
  // Min cut is 2 (isolating any non-bridge vertex) vs 5 (cutting the bridge).
  assert_true(result.cut_value <= 2.0 + 1.0e-10)
}

///|
test "karger_stein: disconnected graph" {
  // Two disconnected edges: min cut is 0
  let edges = uw([(0, 1), (2, 3)])
  let result = karger_stein(4, edges, 42UL, 50)
  assert_true(result.cut_value == 0.0)
}

///|
test "karger_stein: determinism" {
  let edges = uw([(0, 1), (1, 2), (0, 2), (2, 3), (3, 4), (4, 5), (3, 5)])
  let r1 = karger_stein(6, edges, 123UL, 50)
  let r2 = karger_stein(6, edges, 123UL, 50)
  assert_eq(r1.cut_value, r2.cut_value)
  assert_eq(r1.partition, r2.partition)
}

///|
test "karger_stein: more trials never worse" {
  let edges = uw([
    (0, 1),
    (0, 2),
    (0, 3),
    (1, 2),
    (1, 3),
    (2, 3),
    (3, 4),
    (4, 5),
    (4, 6),
    (5, 6),
    (5, 7),
    (6, 7),
  ])
  let r1 = karger_stein(8, edges, 42UL, 1)
  let r10 = karger_stein(8, edges, 42UL, 10)
  assert_true(r10.cut_value <= r1.cut_value)
}

///|
test "karger_stein: partition validity" {
  // The partition should have exactly 2 non-empty sides.
  let edges = uw([(0, 1), (1, 2), (0, 2), (2, 3)])
  let result = karger_stein(4, edges, 42UL, 100)
  let mut side0 = 0
  let mut side1 = 0
  for i = 0; i < 4; i = i + 1 {
    if result.partition[i] == 0 {
      side0 = side0 + 1
    } else {
      side1 = side1 + 1
    }
  }
  assert_true(side0 > 0)
  assert_true(side1 > 0)
  assert_eq(side0 + side1, 4)
}

///|
test "karger_stein: path graph min cut is 1" {
  // Path: 0-1-2-3-4, min cut is 1 (any single edge)
  let edges = uw([(0, 1), (1, 2), (2, 3), (3, 4)])
  let result = karger_stein(5, edges, 42UL, 100)
  assert_true(result.cut_value == 1.0)
}

///|
test "karger_stein: star graph min cut is 1" {
  // Star: center 0 connected to 1..5, min cut is 1
  let edges = uw([(0, 1), (0, 2), (0, 3), (0, 4), (0, 5)])
  let result = karger_stein(6, edges, 42UL, 100)
  assert_true(result.cut_value == 1.0)
}

///|
test "karger_stein: invalid edges skipped" {
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 1.0), // valid
    (-1, 2, 1.0), // invalid
    (0, 5, 1.0), // out of range
    (1, 2, 0.0), // zero weight
    (0, 0, 1.0), // self-loop
    (0, 2, 1.0), // valid
    (1, 2, 1.0), // valid
  ]
  let result = karger_stein(3, edges, 42UL, 50)
  // Triangle 0-1-2, min cut = 2
  assert_true(result.cut_value == 2.0)
}

///|
test "karger_stein: weighted bridge" {
  // Two K4's connected by a weight-1 bridge
  // Each K4 has min cut 3, bridge has weight 1
  // Global min cut is 1 (cutting the bridge)
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 1.0),
    (0, 2, 1.0),
    (0, 3, 1.0),
    (1, 2, 1.0),
    (1, 3, 1.0),
    (2, 3, 1.0),
    (4, 5, 1.0),
    (4, 6, 1.0),
    (4, 7, 1.0),
    (5, 6, 1.0),
    (5, 7, 1.0),
    (6, 7, 1.0),
    (3, 4, 1.0), // bridge
  ]
  let result = karger_stein(8, edges, 42UL, 300)
  assert_true(result.cut_value == 1.0)
}

///|
test "karger_stein: cycle graph min cut is 2" {
  // 6-cycle: 0-1-2-3-4-5-0
  let edges = uw([(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0)])
  let result = karger_stein(6, edges, 42UL, 100)
  assert_true(result.cut_value == 2.0)
}

///|
test "karger_stein: double edge min cut" {
  // Two vertices connected by 3 parallel edges (represented as weight 3)
  // Plus each connected to a third vertex by 1 edge
  // Graph: 0=1 (weight 3), 0-2 (weight 1), 1-2 (weight 1)
  // Min cut: cut {0} from {1,2}: weight 3+1=4, or cut {1} from {0,2}: 3+1=4
  // or cut {2} from {0,1}: 1+1=2
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 3.0),
    (0, 2, 1.0),
    (1, 2, 1.0),
  ]
  // Use enough trials to guarantee finding the min cut with high probability.
  // For n=3, each trial has ≥1/3 chance of finding the optimal cut.
  let result = karger_stein(3, edges, 42UL, 500)
  assert_true(result.cut_value <= 2.0 + 1.0e-10)
}
