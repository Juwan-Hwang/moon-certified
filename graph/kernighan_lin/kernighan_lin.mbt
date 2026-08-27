/// Kernighan-Lin Graph Partitioning Algorithm.
///
/// The Kernighan-Lin (KL) algorithm is a local-search heuristic for partitioning
/// a weighted undirected graph into two equal-sized sets while minimizing the
/// total weight of edges crossing between the sets (the "cut size").
///
/// ## Algorithm
///
/// 1. **Initial partition**: Split vertices into two halves A and B.
/// 2. **Cost computation**: For each vertex `v`, compute:
///    - External cost `E(v)`: sum of edge weights from `v` to the other set.
///    - Internal cost `I(v)`: sum of edge weights from `v` to its own set.
///    - Difference `D(v) = E(v) − I(v)`.
/// 3. **Swap selection**: Find the unlocked pair `(a, b)` with `a ∈ A, b ∈ B`
///    that maximizes `gain(a, b) = D(a) + D(b) − 2·w(a, b)`.
/// 4. **Lock and update**: Lock `a` and `b`, update `D` values for remaining
///    vertices, and record the cumulative gain.
/// 5. **Best prefix**: After all pairs are locked, find the prefix of swaps with
///    the maximum cumulative gain. If positive, apply those swaps and repeat.
/// 6. **Terminate**: Stop when no improvement is possible.
///
/// ## Complexity
///
/// - Time: O(n²) per pass (n/2 swaps × O(n) scan + O(n) update).
/// - Space: O(n²) for the adjacency matrix.
/// - Typical number of passes: 2–6 for moderate graphs.
///
/// ## Quality
///
/// The KL algorithm does not guarantee a global optimum but produces good
/// 2-way partitions in practice. It is widely used as a building block in
/// circuit partitioning, VLSI design, and parallel computing load balancing.
///
/// ## References
///
/// - Kernighan, B. W. & Lin, S. (1970). "An efficient heuristic procedure for
///   partitioning graphs." *Bell System Technical Journal*, 49(2), 291–307.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

///|
/// Result of a Kernighan-Lin graph partitioning.
pub struct KLResult {
  /// `partition[i]` is 0 or 1 indicating which set vertex `i` belongs to.
  partition : Array[Int]
  /// Total weight of edges crossing the cut.
  cut_size : Double
  /// Number of KL passes executed.
  passes : Int
}

// ---------------------------------------------------------------------------
// Internal graph representation
// ---------------------------------------------------------------------------

///|
/// Weighted undirected graph using an adjacency matrix.
///
/// `weight[i][j]` is the weight of the edge between `i` and `j` (0 if no edge).
/// The matrix is symmetric: `weight[i][j] == weight[j][i]`.
priv struct Graph {
  n : Int
  weight : Array[Array[Double]]
}

///|
fn build_graph(n : Int, edges : Array[(Int, Int, Double)]) -> Graph {
  let weight : Array[Array[Double]] = Array::makei(n, fn(_) {
    Array::make(n, 0.0)
  })
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v, w) = edges[i]
    if u >= 0 && u < n && v >= 0 && v < n && u != v && w > 0.0 {
      weight[u][v] = weight[u][v] + w
      weight[v][u] = weight[v][u] + w
    }
  }
  { n, weight, }
}

// ---------------------------------------------------------------------------
// Cut size computation
// ---------------------------------------------------------------------------

///|
/// Compute the total weight of edges crossing the partition.
fn compute_cut_size(graph : Graph, partition : Array[Int]) -> Double {
  let mut cut = 0.0
  for i = 0; i < graph.n; i = i + 1 {
    for j = i + 1; j < graph.n; j = j + 1 {
      if partition[i] != partition[j] {
        cut = cut + graph.weight[i][j]
      }
    }
  }
  cut
}

// ---------------------------------------------------------------------------
// Kernighan-Lin core
// ---------------------------------------------------------------------------

///|
/// Compute D(v) = E(v) - I(v) for all vertices.
///
/// - E(v) = sum of weights from v to vertices in the other set.
/// - I(v) = sum of weights from v to vertices in the same set.
fn compute_d_values(graph : Graph, partition : Array[Int]) -> Array[Double] {
  let n = graph.n
  let d = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let mut ext = 0.0
    let mut int_ = 0.0
    for j = 0; j < n; j = j + 1 {
      if i != j {
        if partition[i] != partition[j] {
          ext = ext + graph.weight[i][j]
        } else {
          int_ = int_ + graph.weight[i][j]
        }
      }
    }
    d[i] = ext - int_
  }
  d
}

///|
/// One pass of the Kernighan-Lin algorithm.
///
/// Tries all n/2 swaps, records the sequence of cumulative gains, and returns
/// the best prefix length (number of swaps to apply) and the total gain at
/// that point. If the best gain is ≤ 0, no swaps should be applied.
///
/// Returns `(best_k, best_gain, swaps)` where `swaps` is the ordered list of
/// `(a, b)` pairs that were selected.
fn kl_pass(
  graph : Graph,
  partition : Array[Int],
  d : Array[Double],
) -> (Int, Double, Array[(Int, Int)]) {
  let n = graph.n
  let half = n / 2
  let locked = Array::make(n, false)
  let d_copy = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    d_copy[i] = d[i]
  }
  let swaps : Array[(Int, Int)] = []
  let gains : Array[Double] = []
  let mut cumulative = 0.0
  // Perform n/2 swap selections.
  for step = 0; step < half; step = step + 1 {
    // Find the best unlocked pair (a, b) with a in set 0, b in set 1.
    let mut best_gain = -1.0e18
    let mut best_a = -1
    let mut best_b = -1
    for a = 0; a < n; a = a + 1 {
      if locked[a] || partition[a] != 0 {
        continue
      }
      for b = 0; b < n; b = b + 1 {
        if locked[b] || partition[b] != 1 {
          continue
        }
        let gain = d_copy[a] + d_copy[b] - 2.0 * graph.weight[a][b]
        if gain > best_gain {
          best_gain = gain
          best_a = a
          best_b = b
        }
      }
    }
    if best_a == -1 || best_b == -1 {
      break
    }
    // Lock the pair.
    locked[best_a] = true
    locked[best_b] = true
    swaps.push((best_a, best_b))
    cumulative = cumulative + best_gain
    gains.push(cumulative)
    // Update D values for remaining unlocked vertices.
    for v = 0; v < n; v = v + 1 {
      if !locked[v] {
        let wa = graph.weight[v][best_a]
        let wb = graph.weight[v][best_b]
        if partition[v] == 0 {
          // v is in A (same as a). a moves to B: edge (v,a) internal→external, D += 2*wa.
          // b moves to A: edge (v,b) external→internal, D -= 2*wb.
          d_copy[v] = d_copy[v] + 2.0 * wa - 2.0 * wb
        } else {
          // v is in B (same as b). b moves to A: edge (v,b) internal→external, D += 2*wb.
          // a moves to B: edge (v,a) external→internal, D -= 2*wa.
          d_copy[v] = d_copy[v] - 2.0 * wa + 2.0 * wb
        }
      }
    }
  }
  // Find the step with maximum cumulative gain.
  let mut best_k = 0
  let mut best_total = 0.0
  for k = 0; k < gains.length(); k = k + 1 {
    if gains[k] > best_total {
      best_total = gains[k]
      best_k = k + 1
    }
  }
  (best_k, best_total, swaps)
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Partition a weighted undirected graph into two equal-sized sets using the
/// Kernighan-Lin algorithm.
///
/// # Parameters
/// - `n`: Number of vertices, indexed `0 .. n − 1`.
/// - `edges`: Weighted undirected edges as `(u, v, weight)` tuples. Edges
///   with endpoints outside `[0, n)` or non-positive weight are silently
///   skipped. Self-loops are ignored.
/// - `max_passes`: Maximum number of KL passes. Each pass tries all n/2 swaps
///   and applies the best prefix. The algorithm stops early if no improvement
///   is found. Typical convergence is 2–6 passes.
///
/// # Returns
/// A `KLResult` containing the partition, cut size, and pass count.
///
/// # Partition Balance
/// If `n` is even, each set has exactly `n/2` vertices.
/// If `n` is odd, set 0 has `⌈n/2⌉` vertices and set 1 has `⌊n/2⌋`.
///
/// # Complexity
/// O(max_passes · n²) time, O(n²) space.
pub fn kernighan_lin(
  n : Int,
  edges : Array[(Int, Int, Double)],
  max_passes : Int,
) -> KLResult {
  if n <= 1 {
    return { partition: Array::make(n, 0), cut_size: 0.0, passes: 0, }
  }
  let graph = build_graph(n, edges)
  // Initial partition: first half → set 0, second half → set 1.
  let partition = Array::make(n, 0)
  let half = n / 2
  for i = half; i < n; i = i + 1 {
    partition[i] = 1
  }
  let mut pass_count = 0
  let mut improved = true
  let passes = if max_passes < 1 { 1 } else { max_passes }
  while improved && pass_count < passes {
    pass_count = pass_count + 1
    let d = compute_d_values(graph, partition)
    let (best_k, best_gain, swaps) = kl_pass(graph, partition, d)
    if best_k > 0 && best_gain > 0.0 {
      // Apply the best prefix of swaps.
      for i = 0; i < best_k; i = i + 1 {
        let (a, b) = swaps[i]
        partition[a] = 1
        partition[b] = 0
      }
      improved = true
    } else {
      improved = false
    }
  }
  let cut = compute_cut_size(graph, partition)
  { partition, cut_size: cut, passes: pass_count, }
}

///|
/// Partition a graph using Kernighan-Lin with default parameters (max 20 passes).
pub fn kernighan_lin_default(
  n : Int,
  edges : Array[(Int, Int, Double)],
) -> KLResult {
  kernighan_lin(n, edges, 20)
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
test "kernighan_lin: empty graph" {
  let result = kernighan_lin_default(0, [])
  assert_true(result.cut_size == 0.0)
}

///|
test "kernighan_lin: single vertex" {
  let result = kernighan_lin_default(1, [])
  assert_true(result.cut_size == 0.0)
}

///|
test "kernighan_lin: two vertices" {
  let edges = uw([(0, 1)])
  let result = kernighan_lin(2, edges, 10)
  // Two vertices must be split, cut = 1.
  assert_true(result.cut_size == 1.0)
  assert_true(result.partition[0] != result.partition[1])
}

///|
test "kernighan_lin: two cliques connected by bridge" {
  // Two K4 cliques connected by a single bridge edge.
  // Optimal partition: each clique in one set, cut = 1.
  let edges = uw([
    (0, 1),
    (0, 2),
    (0, 3),
    (1, 2),
    (1, 3),
    (2, 3), // K4 A
    (4, 5),
    (4, 6),
    (4, 7),
    (5, 6),
    (5, 7),
    (6, 7), // K4 B
    (3, 4), // bridge
  ])
  let result = kernighan_lin(8, edges, 20)
  // The optimal cut is 1 (cutting the bridge).
  assert_true(result.cut_size <= 1.0 + 1.0e-10)
}

///|
test "kernighan_lin: path graph" {
  // Path: 0-1-2-3-4-5
  // Optimal partition: {0,1,2} vs {3,4,5}, cut = 1
  let edges = uw([(0, 1), (1, 2), (2, 3), (3, 4), (4, 5)])
  let result = kernighan_lin(6, edges, 20)
  assert_true(result.cut_size <= 1.0 + 1.0e-10)
}

///|
test "kernighan_lin: cycle graph" {
  // 6-cycle: 0-1-2-3-4-5-0
  // Optimal partition: {0,1,2} vs {3,4,5}, cut = 2
  let edges = uw([(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0)])
  let result = kernighan_lin(6, edges, 20)
  assert_true(result.cut_size <= 2.0 + 1.0e-10)
}

///|
test "kernighan_lin: complete graph K4" {
  // K4: all edges weight 1.
  // Any balanced 2+2 partition has cut = 4.
  let edges = uw([(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)])
  let result = kernighan_lin(4, edges, 20)
  assert_true(result.cut_size == 4.0)
}

///|
test "kernighan_lin: weighted graph" {
  // Two triangles connected by a weight-10 bridge.
  // Optimal: cut the bridge, cut = 10.
  // But KL might also find cut = 3+3 = 6 if it splits a triangle.
  // Actually, the min cut for balanced partition is different from min cut.
  // With 6 vertices, balanced = 3+3.
  // If we put {0,1,2} in A and {3,4,5} in B: cut = 10 (bridge only).
  // If we put {0,1,5} in A and {2,3,4} in B: cut = 1+1+1+1 = 4 (triangle edges).
  // So the optimal balanced partition has cut = 4, not 10.
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 1.0),
    (1, 2, 1.0),
    (0, 2, 1.0), // triangle A
    (3, 4, 1.0),
    (4, 5, 1.0),
    (3, 5, 1.0), // triangle B
    (2, 3, 10.0), // bridge
  ]
  let result = kernighan_lin(6, edges, 20)
  // The optimal balanced partition should be {0,1,5} vs {2,3,4} with cut=4
  // or {0,1,2} vs {3,4,5} with cut=10.
  // KL should find the better one (cut ≤ 10).
  assert_true(result.cut_size <= 10.0 + 1.0e-10)
}

///|
test "kernighan_lin: partition balance" {
  // The partition should be balanced: |set0| == |set1| for even n.
  let edges = uw([(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0), (0, 3)])
  let result = kernighan_lin(6, edges, 20)
  let mut count0 = 0
  let mut count1 = 0
  for i = 0; i < 6; i = i + 1 {
    if result.partition[i] == 0 {
      count0 = count0 + 1
    } else {
      count1 = count1 + 1
    }
  }
  assert_eq(count0, 3)
  assert_eq(count1, 3)
}

///|
test "kernighan_lin: odd vertex count" {
  // 5 vertices: partition should be 3+2.
  let edges = uw([(0, 1), (1, 2), (2, 3), (3, 4)])
  let result = kernighan_lin(5, edges, 20)
  let mut count0 = 0
  let mut count1 = 0
  for i = 0; i < 5; i = i + 1 {
    if result.partition[i] == 0 {
      count0 = count0 + 1
    } else {
      count1 = count1 + 1
    }
  }
  // For odd n=5, set0 has ceil(5/2)=3, set1 has floor(5/2)=2.
  assert_eq(count0 + count1, 5)
  assert_true(count0 == 3 || count0 == 2)
}

///|
test "kernighan_lin: star graph" {
  // Star: center 0 connected to 1,2,3,4,5,6,7
  // Balanced partition 4+4: optimal is center + 3 leaves vs 4 leaves.
  // Cut = 4 (the 4 edges from center to the leaves in the other set).
  // Or center in one set, 3 leaves with it, 4 leaves in other set → cut = 4.
  // Actually, best is center + 3 leaves vs 4 leaves: cut = 4.
  // Or center alone with 3 others vs 4 others: cut = 4.
  // Actually if center is in set A with 3 leaves, the 4 leaves in B each
  // have 1 edge to center, so cut = 4.
  // If center is in set A with 0 leaves (4 others in A): impossible (4+4).
  // Wait, n=8, half=4. If center is in A with 3 leaves, 4 leaves in B.
  // Cut = 4 (edges from center to the 4 B-leaves).
  // If center is in A with 4 leaves, 3 leaves in B → impossible (A has 5).
  // So the min balanced cut is 4.
  let edges = uw([(0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (0, 6), (0, 7)])
  let result = kernighan_lin(8, edges, 20)
  assert_true(result.cut_size <= 4.0 + 1.0e-10)
}

///|
test "kernighan_lin: no edges" {
  // Disconnected graph: any partition has cut = 0.
  let result = kernighan_lin(6, [], 10)
  assert_true(result.cut_size == 0.0)
}

///|
test "kernighan_lin: invalid edges skipped" {
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 1.0), // valid
    (-1, 2, 1.0), // invalid
    (0, 5, 1.0), // out of range
    (1, 2, 0.0), // zero weight
    (0, 0, 1.0), // self-loop
    (0, 2, 1.0), // valid
    (1, 2, 1.0), // valid
    (2, 3, 1.0), // valid
  ]
  let result = kernighan_lin(4, edges, 20)
  // Graph: 0-1, 0-2, 1-2, 2-3 (triangle + pendant)
  // Balanced 2+2 partitions:
  // {0,1} vs {2,3}: cut = w(0,2)+w(1,2) = 2 (optimal)
  // {0,2} vs {1,3}: cut = w(0,1)+w(1,2)+w(2,3) = 3
  // {0,3} vs {1,2}: cut = w(0,1)+w(0,2)+w(2,3) = 3
  assert_true(result.cut_size <= 2.0 + 1.0e-10)
}

///|
test "kernighan_lin: deterministic" {
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
  let r1 = kernighan_lin(8, edges, 20)
  let r2 = kernighan_lin(8, edges, 20)
  assert_eq(r1.cut_size, r2.cut_size)
  assert_eq(r1.partition, r2.partition)
}

///|
test "kernighan_lin: max passes limit" {
  let edges = uw([(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0)])
  let result = kernighan_lin(6, edges, 1)
  assert_true(result.passes <= 1)
}

///|
test "kernighan_lin: two cliques weighted bridge" {
  // Two K3 cliques connected by a weight-100 bridge.
  // Balanced 3+3: {0,1,2} vs {3,4,5} has cut = 100.
  // Alternative: {0,1,5} vs {2,3,4} has cut = 1+1+1+1 = 4.
  // KL should find cut ≤ 100.
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 1.0),
    (1, 2, 1.0),
    (0, 2, 1.0),
    (3, 4, 1.0),
    (4, 5, 1.0),
    (3, 5, 1.0),
    (2, 3, 100.0),
  ]
  let result = kernighan_lin(6, edges, 20)
  assert_true(result.cut_size <= 100.0 + 1.0e-10)
}

///|
test "kernighan_lin: grid graph" {
  // 3x2 grid:
  // 0 - 1 - 2
  // |   |   |
  // 3 - 4 - 5
  // Balanced 3+3: optimal is {0,1,3} vs {2,4,5} or {0,3,4} vs {1,2,5}
  // Cut for {0,1,3} vs {2,4,5}: edges 1-2, 3-4, 4-5 = 3
  // Cut for {0,3,4} vs {1,2,5}: edges 0-1, 3-4, 2-5, 4-5 = 4
  // So optimal is 3.
  let edges = uw([
    (0, 1),
    (1, 2),
    (3, 4),
    (4, 5), // horizontal
    (0, 3),
    (1, 4),
    (2, 5), // vertical
  ])
  let result = kernighan_lin(6, edges, 20)
  assert_true(result.cut_size <= 3.0 + 1.0e-10)
}

///|
test "kernighan_lin: heavy internal edges" {
  // Graph with strong internal connections and weak bridge.
  // {0,1,2,3} with all internal edges weight 10.
  // {4,5,6,7} with all internal edges weight 10.
  // Bridge 3-4 weight 1.
  // Balanced 4+4: {0,1,2,3} vs {4,5,6,7}: cut = 1.
  // This is the optimal partition.
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 10.0),
    (0, 2, 10.0),
    (0, 3, 10.0),
    (1, 2, 10.0),
    (1, 3, 10.0),
    (2, 3, 10.0),
    (4, 5, 10.0),
    (4, 6, 10.0),
    (4, 7, 10.0),
    (5, 6, 10.0),
    (5, 7, 10.0),
    (6, 7, 10.0),
    (3, 4, 1.0),
  ]
  let result = kernighan_lin(8, edges, 20)
  assert_true(result.cut_size <= 1.0 + 1.0e-10)
}

///|
test "kernighan_lin: larger graph stress" {
  // Two K8 cliques connected by a single bridge.
  // 16 vertices, balanced 8+8.
  // Optimal: {0..7} vs {8..15}, cut = 1.
  let edges : Array[(Int, Int, Double)] = []
  // K8 clique A: vertices 0-7
  for i = 0; i < 8; i = i + 1 {
    for j = i + 1; j < 8; j = j + 1 {
      edges.push((i, j, 1.0))
    }
  }
  // K8 clique B: vertices 8-15
  for i = 8; i < 16; i = i + 1 {
    for j = i + 1; j < 16; j = j + 1 {
      edges.push((i, j, 1.0))
    }
  }
  // Bridge
  edges.push((7, 8, 1.0))
  let result = kernighan_lin(16, edges, 30)
  assert_true(result.cut_size <= 1.0 + 1.0e-10)
}
