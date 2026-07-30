/// Louvain Community Detection — modularity-optimization-based community
/// detection for large networks.
///
/// The Louvain method, developed by Blondel, Guillaume, Lambiotte, and
/// Lefebvre (2008), is a greedy algorithm that detects communities by
/// optimizing **modularity** — a scalar measure of how much the graph's
/// community structure deviates from a random null model.
///
/// ## Algorithm
///
/// The method proceeds in two phases, repeated until no further modularity
/// improvement is possible:
///
/// 1. **Local Optimization**: Each node starts in its own community. For each
///    node, the algorithm computes the modularity gain of moving it to each
///    neighboring community. The node is moved to the community yielding the
///    maximum gain (if positive). This phase repeats until no node moves.
///
/// 2. **Aggregation**: Communities are collapsed into super-nodes. Internal
///    edges become self-loops; inter-community edges become weighted edges
///    between super-nodes. The algorithm returns to Phase 1 on the new graph.
///
/// ## Modularity
///
/// ```text
/// Q = Σ_c [ Σ_in,c / (2m) - γ · (Σ_tot,c / (2m))² ]
/// ```
///
/// where `Σ_in,c` is the sum of weights of edges inside community `c` (each
/// edge counted twice), `Σ_tot,c` is the sum of degrees of nodes in `c`, `m`
/// is the total edge weight, and `γ` is the resolution parameter.
///
/// The modularity gain of moving an isolated node `i` into community `C` is
/// proportional to:
///
/// ```text
/// ΔQ ∝ k_{i,C} − γ · Σ_tot,C · k_i / (2m)
/// ```
///
/// where `k_{i,C}` is the sum of edge weights from `i` to nodes in `C`, and
/// `k_i` is the weighted degree of `i`.
///
/// ## Resolution Parameter
///
/// - `γ = 1.0`: standard modularity (default).
/// - `γ > 1.0`: favors smaller communities.
/// - `γ < 1.0`: favors larger communities.
///
/// ## Complexity
///
/// Each level is O(n) in practice (each node examines only its neighbors),
/// with O(log n) levels typically. Total: near-linear for sparse graphs.
///
/// ## References
///
/// - Blondel, V. D., Guillaume, J.-L., Lambiotte, R., & Lefebvre, E. (2008).
///   "Fast unfolding of communities in large networks." *J. Stat. Mech.*,
///   2008(10), P10008.
/// - Traag, V. A., Waltman, L., & van Eck, N. J. (2019). "From Louvain to
///   Leiden: guaranteeing well-connected communities." *Scientific Reports*,
///   9, 5233.
/// - Newman, M. E. J. (2006). "Modularity and community structure in
///   networks." *Proc. Natl. Acad. Sci.*, 103(23), 8577–8582.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Internal graph representation
// ---------------------------------------------------------------------------

///|
priv struct LouvainGraph {
  n : Int
  // Adjacency list: adj[v] = [(neighbor, weight), ...] (no self-loops).
  adj : Array[Array[(Int, Double)]]
  // Self-loop weight for each node (0 if none).
  self_loop : Array[Double]
  // Total edge weight (each edge counted once, including self-loops).
  m : Double
  // Weighted degree: k[v] = Σ adj weights + 2 · self_loop[v].
  degree : Array[Double]
}

///|
/// Build a `LouvainGraph` from a node count and weighted edge list.
///
/// Edges with endpoints outside `[0, n)` or non-positive weight are silently
/// skipped. Self-loops `(u, u, w)` are stored separately and contribute `2w`
/// to the node's degree.
fn build_graph(n : Int, edges : Array[(Int, Int, Double)]) -> LouvainGraph {
  let adj : Array[Array[(Int, Double)]] = []
  let self_loop = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    adj.push([])
  }
  let mut total_weight = 0.0
  for eid = 0; eid < edges.length(); eid = eid + 1 {
    let (u, v, w) = edges[eid]
    if u < 0 || u >= n || v < 0 || v >= n || w <= 0.0 {
      continue
    }
    if u == v {
      self_loop[u] = self_loop[u] + w
      total_weight = total_weight + w
    } else {
      adj[u].push((v, w))
      adj[v].push((u, w))
      total_weight = total_weight + w
    }
  }
  let degree = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    let mut d = 2.0 * self_loop[i]
    for j = 0; j < adj[i].length(); j = j + 1 {
      d = d + adj[i][j].1
    }
    degree[i] = d
  }
  { n, adj, self_loop, m: total_weight, degree }
}

// ---------------------------------------------------------------------------
// One level of local optimization
// ---------------------------------------------------------------------------

///|
/// Run one level of local modularity optimization.
///
/// Each node starts in its own community. For each node, the algorithm
/// removes it from its current community, computes the modularity gain of
/// moving it to each neighboring community, and places it in the best one
/// (if the gain is positive). This repeats for `max_iter` passes or until
/// no node moves.
///
/// Returns `(community, improved)` where `community[i]` is the community ID
/// of node `i` and `improved` is `true` if any node moved.
fn one_level(
  graph : LouvainGraph,
  resolution : Double,
  max_iter : Int,
  tolerance : Double,
) -> (Array[Int], Bool) {
  let n = graph.n
  let m = graph.m
  if n == 0 || m == 0.0 || max_iter <= 0 {
    let comm = Array::make(n, 0)
    for i = 0; i < n; i = i + 1 {
      comm[i] = i
    }
    return (comm, false)
  }
  let two_m = 2.0 * m
  // Initialize: each node in its own community.
  let community = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    community[i] = i
  }
  // sigma_tot[c] = sum of degrees of nodes in community c.
  let sigma_tot = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    sigma_tot[i] = graph.degree[i]
  }
  // k_ic[c] = sum of weights from current node to community c.
  // Reused across nodes; reset via `touched` list after each node.
  let k_ic = Array::make(n, 0.0)
  // Flag array: touched_flag[c] = true if community c is in the `touched`
  // list for the current node. Reset after each node to avoid O(n) clears.
  let touched_flag = Array::make(n, false)
  let touched : Array[Int] = []
  let mut improved = false
  for iter = 0; iter < max_iter; iter = iter + 1 {
    let mut moved = false
    for i = 0; i < n; i = i + 1 {
      let old_comm = community[i]
      let ki = graph.degree[i]
      // Remove i from old_comm.
      sigma_tot[old_comm] = sigma_tot[old_comm] - ki
      // Accumulate k_{i,C} for each neighboring community.
      touched.clear()
      // Always consider old_comm as a candidate.
      touched_flag[old_comm] = true
      touched.push(old_comm)
      for j = 0; j < graph.adj[i].length(); j = j + 1 {
        let (neighbor, weight) = graph.adj[i][j]
        let c = community[neighbor]
        k_ic[c] = k_ic[c] + weight
        if !touched_flag[c] {
          touched_flag[c] = true
          touched.push(c)
        }
      }
      // Find best community: maximize k_{i,C} − γ · σ_tot,C · k_i / (2m).
      let mut best_comm = old_comm
      let mut best_gain = k_ic[old_comm] - resolution * sigma_tot[old_comm] *
        ki /
        two_m
      for t = 0; t < touched.length(); t = t + 1 {
        let c = touched[t]
        if c == old_comm {
          continue
        }
        let gain = k_ic[c] - resolution * sigma_tot[c] * ki / two_m
        if gain > best_gain + tolerance {
          best_gain = gain
          best_comm = c
        }
      }
      // Place i in best_comm.
      sigma_tot[best_comm] = sigma_tot[best_comm] + ki
      community[i] = best_comm
      if best_comm != old_comm {
        moved = true
        improved = true
      }
      // Reset k_ic and touched_flag for touched communities.
      for t = 0; t < touched.length(); t = t + 1 {
        k_ic[touched[t]] = 0.0
        touched_flag[touched[t]] = false
      }
    }
    if !moved {
      break
    }
  }
  (community, improved)
}

// ---------------------------------------------------------------------------
// Community renumbering
// ---------------------------------------------------------------------------

///|
/// Renumber community IDs to be contiguous (0, 1, 2, ...).
///
/// Returns `(renumbered, count)` where `count` is the number of distinct
/// communities.
fn renumber(community : Array[Int]) -> (Array[Int], Int) {
  let n = community.length()
  let result = Array::make(n, 0)
  // Map from old community ID to new ID.
  let remap = Array::make(n, -1)
  let mut count = 0
  for i = 0; i < n; i = i + 1 {
    let old_id = community[i]
    if old_id >= 0 && old_id < n && remap[old_id] == -1 {
      remap[old_id] = count
      count = count + 1
    }
    result[i] = if old_id >= 0 && old_id < n { remap[old_id] } else { 0 }
  }
  (result, count)
}

// ---------------------------------------------------------------------------
// Aggregation
// ---------------------------------------------------------------------------

///|
/// Build a new graph by aggregating communities into super-nodes.
///
/// Internal edges become self-loops; inter-community edges become weighted
/// edges between super-nodes. Edge weights between the same pair of
/// super-nodes are summed.
fn aggregate(
  graph : LouvainGraph,
  community : Array[Int],
  num_comm : Int,
) -> LouvainGraph {
  let new_self_loop = Array::make(num_comm, 0.0)
  // Edge weight matrix (upper triangular used).
  let edge_w : Array[Array[Double]] = []
  for i = 0; i < num_comm; i = i + 1 {
    edge_w.push(Array::make(num_comm, 0.0))
  }
  let mut total_weight = 0.0
  // Self-loops from old graph → new self-loops.
  for i = 0; i < graph.n; i = i + 1 {
    if graph.self_loop[i] > 0.0 {
      let c = community[i]
      new_self_loop[c] = new_self_loop[c] + graph.self_loop[i]
      total_weight = total_weight + graph.self_loop[i]
    }
  }
  // Edges (count each undirected edge once: i < neighbor).
  for i = 0; i < graph.n; i = i + 1 {
    for j = 0; j < graph.adj[i].length(); j = j + 1 {
      let (neighbor, weight) = graph.adj[i][j]
      if i < neighbor {
        let ci = community[i]
        let cj = community[neighbor]
        if ci == cj {
          new_self_loop[ci] = new_self_loop[ci] + weight
          total_weight = total_weight + weight
        } else {
          let lo = if ci < cj { ci } else { cj }
          let hi = if ci < cj { cj } else { ci }
          edge_w[lo][hi] = edge_w[lo][hi] + weight
          total_weight = total_weight + weight
        }
      }
    }
  }
  // Build new adjacency list.
  let new_adj : Array[Array[(Int, Double)]] = []
  for i = 0; i < num_comm; i = i + 1 {
    new_adj.push([])
  }
  for i = 0; i < num_comm; i = i + 1 {
    for j = i + 1; j < num_comm; j = j + 1 {
      if edge_w[i][j] > 0.0 {
        new_adj[i].push((j, edge_w[i][j]))
        new_adj[j].push((i, edge_w[i][j]))
      }
    }
  }
  // Compute new degrees.
  let new_degree = Array::make(num_comm, 0.0)
  for i = 0; i < num_comm; i = i + 1 {
    let mut d = 2.0 * new_self_loop[i]
    for j = 0; j < new_adj[i].length(); j = j + 1 {
      d = d + new_adj[i][j].1
    }
    new_degree[i] = d
  }
  { n: num_comm, adj: new_adj, self_loop: new_self_loop, m: total_weight, degree: new_degree }
}

// ---------------------------------------------------------------------------
// Modularity computation
// ---------------------------------------------------------------------------

///|
/// Compute the modularity of a given partition on a graph.
///
/// Q = Σ_c [ Σ_in,c / (2m) − γ · (Σ_tot,c / (2m))² ]
///
/// Returns 0.0 for graphs with no edges.
fn compute_modularity(
  graph : LouvainGraph,
  community : Array[Int],
  resolution : Double,
) -> Double {
  let n = graph.n
  let m = graph.m
  if n == 0 || m == 0.0 {
    return 0.0
  }
  let two_m = 2.0 * m
  // Find max community ID.
  let mut max_comm = 0
  for i = 0; i < n; i = i + 1 {
    if community[i] > max_comm {
      max_comm = community[i]
    }
  }
  let nc = max_comm + 1
  let sigma_in = Array::make(nc, 0.0)
  let sigma_tot = Array::make(nc, 0.0)
  // Self-loops: contribute 2 · w to sigma_in.
  for i = 0; i < n; i = i + 1 {
    let c = community[i]
    sigma_in[c] = sigma_in[c] + 2.0 * graph.self_loop[i]
    sigma_tot[c] = sigma_tot[c] + graph.degree[i]
  }
  // Internal edges (count each once: i < neighbor): contribute 2 · w to sigma_in.
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < graph.adj[i].length(); j = j + 1 {
      let (neighbor, weight) = graph.adj[i][j]
      if i < neighbor && community[i] == community[neighbor] {
        sigma_in[community[i]] = sigma_in[community[i]] + 2.0 * weight
      }
    }
  }
  // Q = Σ_c [ sigma_in[c] / (2m) − γ · (sigma_tot[c] / (2m))² ]
  let mut q = 0.0
  for c = 0; c < nc; c = c + 1 {
    let ratio = sigma_tot[c] / two_m
    q = q + sigma_in[c] / two_m - resolution * ratio * ratio
  }
  q
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Result of a Louvain community detection run.
pub struct LouvainResult {
  /// Community assignment for each original node. IDs are contiguous
  /// starting from 0.
  communities : Array[Int]
  /// Number of distinct communities detected.
  num_communities : Int
  /// Modularity value of the detected partition.
  modularity : Double
  /// Number of levels (passes) executed.
  levels : Int
}

///|
/// Detect communities in an undirected weighted graph using the Louvain method.
///
/// # Parameters
/// - `n`: Number of nodes, indexed `0 .. n − 1`.
/// - `edges`: Weighted undirected edges as `(u, v, weight)` tuples. Edges
///   with endpoints outside `[0, n)` or non-positive weight are silently
///   skipped. Self-loops `(u, u, w)` are supported.
/// - `resolution`: Resolution parameter `γ`. Use `1.0` for standard
///   modularity. Higher values produce smaller communities; lower values
///   produce larger ones.
/// - `max_levels`: Maximum number of Louvain levels (aggregation passes).
///   Typical convergence is within `O(log n)` levels.
/// - `max_iter`: Maximum number of local-optimization passes per level.
/// - `tolerance`: Minimum modularity gain for a node move to be accepted.
///   Prevents floating-point noise from causing unnecessary moves.
///
/// # Returns
/// A `LouvainResult` containing the community assignment, community count,
/// modularity value, and level count.
///
/// # Determinism
/// The algorithm is fully deterministic: the same input always produces the
/// same output. Node iteration order is fixed (0, 1, ..., n−1).
///
/// # Complexity
/// Near-linear in practice for sparse graphs: O(n · max_iter) per level,
/// O(log n) levels typically.
pub fn louvain(
  n : Int,
  edges : Array[(Int, Int, Double)],
  resolution : Double,
  max_levels : Int,
  max_iter : Int,
  tolerance : Double,
) -> LouvainResult {
  if n <= 0 {
    return { communities: [], num_communities: 0, modularity: 0.0, levels: 0 }
  }
  if n == 1 {
    return { communities: [0], num_communities: 1, modularity: 0.0, levels: 0 }
  }
  let original_graph = build_graph(n, edges)
  // mapping[i] = which current-level graph node original node i belongs to.
  let mapping = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    mapping[i] = i
  }
  let mut graph = original_graph
  let mut levels = 0
  let mut level = 0
  while level < max_levels {
    level = level + 1
    let (comm, improved) = one_level(graph, resolution, max_iter, tolerance)
    let (renumbered, num_comm) = renumber(comm)
    // Update mapping: each original node's community is renumbered.
    for i = 0; i < n; i = i + 1 {
      mapping[i] = renumbered[mapping[i]]
    }
    levels = level
    if !improved || num_comm == graph.n {
      break
    }
    // Aggregate for next level.
    graph = aggregate(graph, renumbered, num_comm)
  }
  // Compute final modularity on the original graph.
  let mod = compute_modularity(original_graph, mapping, resolution)
  // Count distinct communities.
  let (final_comm, num_comm) = renumber(mapping)
  { communities: final_comm, num_communities: num_comm, modularity: mod, levels }
}

///|
/// Detect communities using the Louvain method with default parameters.
///
/// Equivalent to `louvain(n, edges, 1.0, 100, 100, 1.0e-6)`.
pub fn louvain_default(
  n : Int,
  edges : Array[(Int, Int, Double)],
) -> LouvainResult {
  louvain(n, edges, 1.0, 100, 100, 1.0e-6)
}

///|
/// Compute the modularity of a given community partition.
///
/// # Parameters
/// - `n`: Number of nodes.
/// - `edges`: Weighted undirected edges as `(u, v, weight)` tuples.
/// - `communities`: Community assignment for each node.
/// - `resolution`: Resolution parameter `γ` (use `1.0` for standard modularity).
///
/// # Returns
/// The modularity value `Q ∈ [−1, 1]`. Higher values indicate stronger
/// community structure. Returns `0.0` for graphs with no edges.
pub fn modularity(
  n : Int,
  edges : Array[(Int, Int, Double)],
  communities : Array[Int],
  resolution : Double,
) -> Double {
  if n <= 0 || communities.length() == 0 {
    return 0.0
  }
  let graph = build_graph(n, edges)
  compute_modularity(graph, communities, resolution)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
/// Build unweighted edges from integer pairs with weight 1.0.
fn unweighted(pairs : Array[(Int, Int)]) -> Array[(Int, Int, Double)] {
  let result : Array[(Int, Int, Double)] = []
  for i = 0; i < pairs.length(); i = i + 1 {
    let (u, v) = pairs[i]
    result.push((u, v, 1.0))
  }
  result
}

test "louvain: empty graph" {
  let result = louvain_default(0, [])
  assert_eq(result.communities.length(), 0)
  assert_eq(result.num_communities, 0)
  assert_true(result.modularity == 0.0)
}

test "louvain: single node" {
  let result = louvain_default(1, [])
  assert_eq(result.communities, [0])
  assert_eq(result.num_communities, 1)
}

test "louvain: two disconnected nodes" {
  let result = louvain_default(2, [])
  assert_eq(result.num_communities, 2)
  assert_eq(result.communities[0], 0)
  assert_eq(result.communities[1], 1)
}

test "louvain: two connected nodes" {
  let result = louvain_default(2, [(0, 1, 1.0)])
  assert_eq(result.num_communities, 1)
  assert_eq(result.communities[0], result.communities[1])
}

test "louvain: triangle is one community" {
  let edges = unweighted([(0, 1), (1, 2), (0, 2)])
  let result = louvain_default(3, edges)
  assert_eq(result.num_communities, 1)
  assert_eq(result.communities[0], result.communities[1])
  assert_eq(result.communities[1], result.communities[2])
}

test "louvain: two triangles connected by bridge" {
  // Triangle A: 0-1-2, Triangle B: 3-4-5, Bridge: 2-3
  let edges = unweighted([
    (0, 1), (1, 2), (0, 2), // Triangle A
    (3, 4), (4, 5), (3, 5), // Triangle B
    (2, 3), // Bridge
  ])
  let result = louvain_default(6, edges)
  // Each triangle should form a separate community.
  assert_eq(result.num_communities, 2)
  // Triangle A nodes in same community.
  assert_eq(result.communities[0], result.communities[1])
  assert_eq(result.communities[1], result.communities[2])
  // Triangle B nodes in same community.
  assert_eq(result.communities[3], result.communities[4])
  assert_eq(result.communities[4], result.communities[5])
  // A and B in different communities.
  assert_true(result.communities[0] != result.communities[3])
}

test "louvain: two triangles with strong internal weights" {
  // Same structure but internal edges have weight 5, bridge weight 1
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 5.0), (1, 2, 5.0), (0, 2, 5.0),
    (3, 4, 5.0), (4, 5, 5.0), (3, 5, 5.0),
    (2, 3, 1.0),
  ]
  let result = louvain_default(6, edges)
  assert_eq(result.num_communities, 2)
  assert_eq(result.communities[0], result.communities[1])
  assert_eq(result.communities[1], result.communities[2])
  assert_eq(result.communities[3], result.communities[4])
  assert_eq(result.communities[4], result.communities[5])
  assert_true(result.communities[0] != result.communities[3])
  // Modularity should be high (strong community structure).
  assert_true(result.modularity > 0.3)
}

test "louvain: complete graph is one community" {
  // K5: complete graph on 5 nodes
  let edges = unweighted([
    (0, 1), (0, 2), (0, 3), (0, 4),
    (1, 2), (1, 3), (1, 4),
    (2, 3), (2, 4),
    (3, 4),
  ])
  let result = louvain_default(5, edges)
  assert_eq(result.num_communities, 1)
  for i = 1; i < 5; i = i + 1 {
    assert_eq(result.communities[i], result.communities[0])
  }
}

test "louvain: ring graph" {
  // 8-node ring: 0-1-2-3-4-5-6-7-0
  let edges = unweighted([
    (0, 1), (1, 2), (2, 3), (3, 4),
    (4, 5), (5, 6), (6, 7), (7, 0),
  ])
  let result = louvain_default(8, edges)
  // A ring has weak community structure; Louvain should still find
  // some partition. Modularity should be non-negative.
  assert_true(result.modularity >= -0.001)
  assert_true(result.num_communities >= 1)
}

test "louvain: star graph" {
  // Star: center 0 connected to 1..6
  let edges = unweighted([
    (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (0, 6),
  ])
  let result = louvain_default(7, edges)
  // Star has no community structure; modularity should be near 0 or negative.
  assert_true(result.num_communities >= 1)
}

test "louvain: weighted graph" {
  // Two communities with weighted edges
  // Community A: 0-1 (weight 10), 1-2 (weight 10), 0-2 (weight 10)
  // Community B: 3-4 (weight 10), 4-5 (weight 10), 3-5 (weight 10)
  // Bridge: 2-3 (weight 1)
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 10.0), (1, 2, 10.0), (0, 2, 10.0),
    (3, 4, 10.0), (4, 5, 10.0), (3, 5, 10.0),
    (2, 3, 1.0),
  ]
  let result = louvain_default(6, edges)
  assert_eq(result.num_communities, 2)
  assert_eq(result.communities[0], result.communities[1])
  assert_eq(result.communities[1], result.communities[2])
  assert_eq(result.communities[3], result.communities[4])
  assert_eq(result.communities[4], result.communities[5])
  assert_true(result.communities[0] != result.communities[3])
}

test "louvain: self-loop" {
  // Node with self-loop plus two connected triangles.
  // Self-loop weight is modest (1.0) to avoid dominating the degree.
  let edges : Array[(Int, Int, Double)] = [
    (0, 0, 1.0), // self-loop on node 0
    (0, 1, 1.0), (1, 2, 1.0), (0, 2, 1.0), // triangle 0-1-2
    (3, 4, 1.0), (4, 5, 1.0), (3, 5, 1.0), // triangle 3-4-5
    (2, 3, 1.0), // bridge
  ]
  let result = louvain_default(6, edges)
  assert_eq(result.num_communities, 2)
  assert_eq(result.communities[0], result.communities[1])
  assert_eq(result.communities[1], result.communities[2])
  assert_eq(result.communities[3], result.communities[4])
  assert_eq(result.communities[4], result.communities[5])
  assert_true(result.communities[0] != result.communities[3])
}

test "louvain: determinism" {
  let edges = unweighted([
    (0, 1), (1, 2), (0, 2),
    (3, 4), (4, 5), (3, 5),
    (2, 3),
  ])
  let r1 = louvain_default(6, edges)
  let r2 = louvain_default(6, edges)
  assert_eq(r1.num_communities, r2.num_communities)
  assert_eq(r1.modularity, r2.modularity)
  for i = 0; i < 6; i = i + 1 {
    assert_eq(r1.communities[i], r2.communities[i])
  }
}

test "louvain: modularity computation" {
  // Two triangles connected by bridge
  let edges = unweighted([
    (0, 1), (1, 2), (0, 2),
    (3, 4), (4, 5), (3, 5),
    (2, 3),
  ])
  // Correct partition: {0,1,2} and {3,4,5}
  let good_partition = [0, 0, 0, 1, 1, 1]
  let q_good = modularity(6, edges, good_partition, 1.0)
  // Bad partition: {0,3}, {1,4}, {2,5}
  let bad_partition = [0, 1, 2, 0, 1, 2]
  let q_bad = modularity(6, edges, bad_partition, 1.0)
  // Good partition should have higher modularity.
  assert_true(q_good > q_bad)
  // Good partition modularity should be positive.
  assert_true(q_good > 0.0)
}

test "louvain: modularity range" {
  // For any partition, modularity is in [-1, 1]
  let edges = unweighted([(0, 1), (1, 2), (0, 2)])
  let q_all_same = modularity(3, edges, [0, 0, 0], 1.0)
  let q_all_diff = modularity(3, edges, [0, 1, 2], 1.0)
  assert_true(q_all_same <= 1.0 && q_all_same >= -1.0)
  assert_true(q_all_diff <= 1.0 && q_all_diff >= -1.0)
  // All in one community should have higher modularity for a triangle.
  assert_true(q_all_same > q_all_diff)
}

test "louvain: resolution parameter" {
  // Higher resolution → more (smaller) communities
  let edges = unweighted([
    (0, 1), (1, 2), (0, 2),
    (3, 4), (4, 5), (3, 5),
    (2, 3),
  ])
  let low_res = louvain(6, edges, 0.5, 100, 100, 1.0e-6)
  let high_res = louvain(6, edges, 2.0, 100, 100, 1.0e-6)
  // Higher resolution should produce at least as many communities.
  assert_true(high_res.num_communities >= low_res.num_communities)
}

test "louvain: four cliques" {
  // Four K3 cliques connected in a ring by single edges
  // Clique A: 0-1-2, B: 3-4-5, C: 6-7-8, D: 9-10-11
  // Bridges: 2-3, 5-6, 8-9, 11-0
  let edges = unweighted([
    (0, 1), (1, 2), (0, 2), // A
    (3, 4), (4, 5), (3, 5), // B
    (6, 7), (7, 8), (6, 8), // C
    (9, 10), (10, 11), (9, 11), // D
    (2, 3), (5, 6), (8, 9), (11, 0), // ring of bridges
  ])
  let result = louvain_default(12, edges)
  // Should find 4 communities (one per clique).
  assert_eq(result.num_communities, 4)
  // Each clique's nodes should be in the same community.
  assert_eq(result.communities[0], result.communities[1])
  assert_eq(result.communities[1], result.communities[2])
  assert_eq(result.communities[3], result.communities[4])
  assert_eq(result.communities[4], result.communities[5])
  assert_eq(result.communities[6], result.communities[7])
  assert_eq(result.communities[7], result.communities[8])
  assert_eq(result.communities[9], result.communities[10])
  assert_eq(result.communities[10], result.communities[11])
  // All four communities should be distinct.
  let c0 = result.communities[0]
  let c1 = result.communities[3]
  let c2 = result.communities[6]
  let c3 = result.communities[9]
  assert_true(c0 != c1)
  assert_true(c1 != c2)
  assert_true(c2 != c3)
  assert_true(c0 != c2)
  assert_true(c0 != c3)
  assert_true(c1 != c3)
}

test "louvain: levels executed" {
  let edges = unweighted([
    (0, 1), (1, 2), (0, 2),
    (3, 4), (4, 5), (3, 5),
    (2, 3),
  ])
  let result = louvain_default(6, edges)
  // Should execute at least 1 level.
  assert_true(result.levels >= 1)
}

test "louvain: stress test 100 nodes" {
  // 10 groups of 10 nodes, each group is a clique, connected by single edges
  let edges : Array[(Int, Int, Double)] = []
  for g = 0; g < 10; g = g + 1 {
    // Clique within group g
    let base = g * 10
    for i = 0; i < 10; i = i + 1 {
      for j = i + 1; j < 10; j = j + 1 {
        edges.push((base + i, base + j, 1.0))
      }
    }
    // Bridge to next group (circular)
    if g < 9 {
      edges.push((base + 9, base + 10, 1.0))
    }
  }
  let result = louvain_default(100, edges)
  // Should detect 10 communities.
  assert_eq(result.num_communities, 10)
  // Each group should be in the same community.
  for g = 0; g < 10; g = g + 1 {
    let base = g * 10
    let comm = result.communities[base]
    for i = 1; i < 10; i = i + 1 {
      assert_eq(result.communities[base + i], comm)
    }
  }
  // Modularity should be high.
  assert_true(result.modularity > 0.5)
}

test "louvain: no edges returns each node as community" {
  let result = louvain_default(5, [])
  assert_eq(result.num_communities, 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(result.communities[i], i)
  }
  assert_true(result.modularity == 0.0)
}

test "louvain: invalid edges are skipped" {
  // Edges with negative nodes, out-of-range nodes, or non-positive weights
  let edges : Array[(Int, Int, Double)] = [
    (0, 1, 1.0), // valid
    (-1, 2, 1.0), // invalid: negative node
    (0, 5, 1.0), // invalid: out of range
    (1, 2, 0.0), // invalid: zero weight
    (1, 2, -1.0), // invalid: negative weight
    (0, 2, 1.0), // valid
  ]
  let result = louvain_default(3, edges)
  // Should treat as triangle 0-1-2.
  assert_eq(result.num_communities, 1)
}

test "louvain: two-community asymmetric" {
  // Asymmetric: large dense community (0-4) and small dense community (5-7)
  // connected by one weak edge
  let edges : Array[(Int, Int, Double)] = [
    // Large community: K5 on nodes 0-4
    (0, 1, 1.0), (0, 2, 1.0), (0, 3, 1.0), (0, 4, 1.0),
    (1, 2, 1.0), (1, 3, 1.0), (1, 4, 1.0),
    (2, 3, 1.0), (2, 4, 1.0),
    (3, 4, 1.0),
    // Small community: K3 on nodes 5-7
    (5, 6, 1.0), (5, 7, 1.0), (6, 7, 1.0),
    // Bridge
    (4, 5, 1.0),
  ]
  let result = louvain_default(8, edges)
  assert_eq(result.num_communities, 2)
  // Large community nodes together.
  for i = 1; i < 5; i = i + 1 {
    assert_eq(result.communities[i], result.communities[0])
  }
  // Small community nodes together.
  assert_eq(result.communities[5], result.communities[6])
  assert_eq(result.communities[6], result.communities[7])
  // Different communities.
  assert_true(result.communities[0] != result.communities[5])
}
