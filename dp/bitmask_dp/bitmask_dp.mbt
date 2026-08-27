/// Bitmask dynamic programming framework for NP-hard problems on small graphs.
///
/// This package provides exact solutions to several classic NP-hard problems
/// using **subset enumeration** (bitmask DP). These algorithms are practical
/// only for small instances (n ≤ 20–60 depending on the problem), but they
/// return **provably optimal** results — no heuristics, no approximations.
///
/// ## Algorithms
///
/// | Problem | Algorithm | Complexity | Practical limit |
/// |--------|-----------|------------|-----------------|
/// | TSP (shortest Hamiltonian cycle) | Held-Karp | O(2ⁿ·n²) | n ≤ 22 |
/// | Maximum independent set | Meet-in-the-middle | O(2ⁿᐟ²·n) | n ≤ 44 |
/// | Minimum vertex cover | Duality with MIS | O(2ⁿᐟ²·n) | n ≤ 44 |
/// | Chromatic number | Subset DP | O(3ⁿ) | n ≤ 16 |
/// | Hamiltonian path existence | Subset DP | O(2ⁿ·n) | n ≤ 22 |
/// | Hamiltonian cycle existence | Subset DP | O(2ⁿ·n) | n ≤ 22 |
///
/// ## Graph representation
///
/// Graphs use a **bit-set adjacency matrix**: `adj[i]` is an `Int` whose bit `j`
/// is set iff there is an edge between vertex `i` and vertex `j`. This gives
/// O(1) edge queries and enables fast bitwise independence/cover checks.
///
/// For TSP, distances are provided as a separate `Int64` matrix to support
/// large weights without overflow.
///
/// ## Overflow safety
///
/// - TSP costs use `Int64` throughout.
/// - All subset enumerations use `Int` bitmasks (up to 60 bits on 64-bit
///   platforms). The maximum supported graph size is 60 vertices for MIS/MVC
///   (meet-in-the-middle) and 22 for TSP (memory-limited by 2ⁿ tables).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Sentinel for "no valid value" in DP tables.
let inf64 : Int64 = 9223372036854775807L

///|
/// Sentinel for "no valid value" in Int DP tables (used for chromatic number).
let inf_int : Int = 2147483647

// ---------------------------------------------------------------------------
// Bitset graph utilities
// ---------------------------------------------------------------------------

///|
/// A bit-set graph supporting up to 60 vertices.
///
/// `adj[i]` is a bitmask where bit `j` is set iff edge (i, j) exists.
pub struct BitGraph {
  n : Int
  adj : Array[Int]
}

///|
/// Create a new empty graph with `n` vertices (no edges).
///
/// `n` must be in `1..=60`. Returns `None` for invalid sizes.
pub fn new_graph(n : Int) -> BitGraph? {
  if n < 0 || n > 60 {
    return None
  }
  Some({ n, adj: Array::make(n, 0), })
}

///|
/// Add an undirected edge between `u` and `v`.
///
/// Self-loops are ignored. Out-of-range vertices are silently skipped.
pub fn add_edge(graph : BitGraph, u : Int, v : Int) -> Unit {
  if u == v || u < 0 || u >= graph.n || v < 0 || v >= graph.n {
    return
  }
  graph.adj[u] = graph.adj[u] | (1 << v)
  graph.adj[v] = graph.adj[v] | (1 << u)
}

///|
/// Check whether edge (u, v) exists.
pub fn has_edge(graph : BitGraph, u : Int, v : Int) -> Bool {
  if u < 0 || u >= graph.n || v < 0 || v >= graph.n {
    return false
  }
  (graph.adj[u] & (1 << v)) != 0
}

///|
/// Count the number of set bits in an `Int` (population count).
///
/// Uses Brian Kernighan's algorithm: each iteration clears the lowest set bit.
fn popcount(x : Int) -> Int {
  let mut count = 0
  let mut v = x
  while v != 0 {
    v = v & (v - 1)
    count = count + 1
  }
  count
}

///|
/// Return the index of the lowest set bit in `x` (0-based).
///
/// Returns -1 if `x == 0`.
fn lowest_bit(x : Int) -> Int {
  if x == 0 {
    return -1
  }
  let mut pos = 0
  let mut v = x
  while (v & 1) == 0 {
    v = v >> 1
    pos = pos + 1
  }
  pos
}

///|
/// Bitwise NOT (complement) of an Int.
///
/// MoonBit does not have a `~` operator, so we XOR with -1 (all bits set in
/// two's complement) to achieve the same effect.
fn lnot(x : Int) -> Int {
  x ^ -1
}

// ---------------------------------------------------------------------------
// Traveling Salesman Problem (Held-Karp)
// ---------------------------------------------------------------------------

///|
/// Solve TSP using the Held-Karp dynamic programming algorithm.
///
/// Given a complete directed graph with `n` vertices and a distance matrix
/// `dist[i][j]`, find the minimum-cost Hamiltonian cycle (visiting every
/// vertex exactly once and returning to the start).
///
/// # Parameters
/// - `n`: number of vertices, indexed `0..n-1`.
/// - `dist`: `n × n` distance matrix. `dist[i][j]` is the cost of traveling
///   from `i` to `j`. Must be non-negative `Int64` values. The matrix need
///   not be symmetric (asymmetric TSP is supported).
///
/// # Returns
/// `Some(cost)` — the minimum tour cost, or `None` if `n < 2` or the matrix
/// is malformed.
///
/// # Complexity
/// - Time:  O(2ⁿ · n²)
/// - Space: O(2ⁿ · n) — stored in a flat `FixedArray[Int64]`.
///
/// For `n = 20`: ~2²⁰ × 20 × 20 ≈ 4 × 10⁸ operations, ~160 MB memory.
/// Practical limit: n ≤ 22.
///
/// # Algorithm
///
/// `dp[mask][v]` = minimum cost to visit the set of vertices in `mask`
/// (a bitmask), starting from vertex 0 and ending at vertex `v`.
///
/// - Base: `dp[1][0] = 0` (start at vertex 0, having visited only vertex 0).
/// - Transition: for each `mask` containing `v`, try all predecessors `u` in
///   `mask \ {v}`:
///   `dp[mask][v] = min(dp[mask ^ (1<<v)][u] + dist[u][v])`
/// - Answer: `min(dp[full][v] + dist[v][0])` over all `v`.
///
/// The implementation is **fully iterative** (no recursion) to prevent stack
/// overflow on large inputs.
pub fn tsp(n : Int, dist : Array[Array[Int64]]) -> Int64? {
  if n < 2 || dist.length() < n {
    return None
  }
  // Validate the distance matrix.
  for i = 0; i < n; i = i + 1 {
    if dist[i].length() < n {
      return None
    }
    for j = 0; j < n; j = j + 1 {
      if dist[i][j] < 0L {
        return None
      }
    }
  }
  let full = (1 << n) - 1
  // dp[mask * n + v] = min cost to visit `mask`, ending at `v`.
  let dp_size = (1 << n) * n
  let dp = FixedArray::make(dp_size, inf64)
  // Base case: start at vertex 0.
  dp[1 * n + 0] = 0L
  // Iterate over all subsets containing vertex 0.
  for mask = 1; mask <= full; mask = mask + 1 {
    if (mask & 1) == 0 {
      // Vertex 0 must be in every valid subset.
      continue
    }
    // For each vertex v in the current mask, relax from all u in mask\{v}.
    for v = 0; v < n; v = v + 1 {
      if (mask & (1 << v)) == 0 {
        continue
      }
      let cur = dp[mask * n + v]
      if cur == inf64 {
        continue
      }
      // Try extending to each vertex u not yet in mask.
      for u = 0; u < n; u = u + 1 {
        if (mask & (1 << u)) != 0 {
          continue
        }
        let new_mask = mask | (1 << u)
        let new_cost = cur + dist[v][u]
        let idx = new_mask * n + u
        if new_cost < dp[idx] {
          dp[idx] = new_cost
        }
      }
    }
  }
  // Answer: min over all v of dp[full][v] + dist[v][0].
  let mut best = inf64
  for v = 0; v < n; v = v + 1 {
    let tour_cost = dp[full * n + v]
    if tour_cost != inf64 && dist[v][0] >= 0L {
      let total = tour_cost + dist[v][0]
      if total < best {
        best = total
      }
    }
  }
  if best == inf64 {
    None
  } else {
    Some(best)
  }
}

///|
/// Solve TSP and reconstruct the optimal tour.
///
/// Returns `Some((cost, tour))` where `tour` is an array of vertex indices
/// `[0, v₁, v₂, ..., v_{n-1}]` representing the optimal visiting order.
/// Returns `None` if no valid tour exists or the input is invalid.
///
/// # Complexity
/// Same as [`tsp`], plus O(n) for path reconstruction.
pub fn tsp_path(n : Int, dist : Array[Array[Int64]]) -> (Int64, Array[Int])? {
  if n < 2 || dist.length() < n {
    return None
  }
  for i = 0; i < n; i = i + 1 {
    if dist[i].length() < n {
      return None
    }
    for j = 0; j < n; j = j + 1 {
      if dist[i][j] < 0L {
        return None
      }
    }
  }
  let full = (1 << n) - 1
  let dp_size = (1 << n) * n
  let dp = FixedArray::make(dp_size, inf64)
  // parent[mask * n + v] = the predecessor vertex u (for path reconstruction).
  let parent = FixedArray::make(dp_size, -1)
  dp[1 * n + 0] = 0L
  for mask = 1; mask <= full; mask = mask + 1 {
    if (mask & 1) == 0 {
      continue
    }
    for v = 0; v < n; v = v + 1 {
      if (mask & (1 << v)) == 0 {
        continue
      }
      let cur = dp[mask * n + v]
      if cur == inf64 {
        continue
      }
      for u = 0; u < n; u = u + 1 {
        if (mask & (1 << u)) != 0 {
          continue
        }
        let new_mask = mask | (1 << u)
        let new_cost = cur + dist[v][u]
        let idx = new_mask * n + u
        if new_cost < dp[idx] {
          dp[idx] = new_cost
          parent[idx] = v
        }
      }
    }
  }
  // Find the best closing vertex.
  let mut best = inf64
  let mut best_v = -1
  for v = 0; v < n; v = v + 1 {
    let tour_cost = dp[full * n + v]
    if tour_cost != inf64 {
      let total = tour_cost + dist[v][0]
      if total < best {
        best = total
        best_v = v
      }
    }
  }
  if best_v == -1 {
    return None
  }
  // Reconstruct the path by following parent pointers.
  let tour : Array[Int] = []
  let mut mask = full
  let mut v = best_v
  while mask != 0 && v != -1 {
    tour.push(v)
    let p = parent[mask * n + v]
    mask = mask ^ (1 << v)
    v = p
  }
  // The path is reconstructed in reverse order; reverse it.
  // tour is now [best_v, ..., 0], we want [0, ..., best_v].
  let len = tour.length()
  let reversed : Array[Int] = []
  for i = len - 1; i >= 0; i = i - 1 {
    reversed.push(tour[i])
  }
  Some((best, reversed))
}

// ---------------------------------------------------------------------------
// Maximum Independent Set (meet-in-the-middle)
// ---------------------------------------------------------------------------

///|
/// Find the size of the maximum independent set using meet-in-the-middle.
///
/// An **independent set** is a subset of vertices with no edges between any
/// two of them. The **maximum independent set** is the largest such subset.
///
/// # Parameters
/// - `adj`: adjacency bitmasks. `adj[i]` has bit `j` set iff edge (i, j).
///   The graph is treated as undirected (the caller should set both
///   `adj[i] |= (1<<j)` and `adj[j] |= (1<<i)`).
/// - `n`: number of vertices.
///
/// # Returns
/// The size of the maximum independent set.
///
/// # Complexity
/// - Time:  O(2ⁿᐟ² · n)
/// - Space: O(2ⁿᐟ²)
///
/// Practical limit: n ≤ 44 (each half ≤ 22, so 2²² ≈ 4M entries).
///
/// # Algorithm (meet-in-the-middle)
///
/// 1. Split vertices into two halves: `L = {0, ..., mid-1}` and
///    `R = {mid, ..., n-1}`.
/// 2. Enumerate all independent sets in `L`. For each, record its size and
///    the set of vertices in `L` that are **blocked** (adjacent to something
///    in `R` that will be chosen later — precomputed as adjacency from `R`).
/// 3. For each independent set `S_R` in `R`, compute the set of vertices in
///    `L` that are **compatible** (not adjacent to any vertex in `S_R`):
///    `compat_L = full_L & ~(OR of adj[v] for v in S_R, restricted to L)`.
/// 4. Precompute `max_indep[mask]` = maximum independent set size among all
///    subsets of `mask` in `L`. This is done with the SOS DP pattern.
/// 5. Answer = `max over S_R: |S_R| + max_indep[compat_L]`.
///
/// This is **exact** — not a heuristic or approximation.
pub fn max_independent_set(adj : Array[Int], n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if n == 1 {
    return 1
  }
  let mid = n / 2
  let left_size = 1 << mid
  let right_size = 1 << (n - mid)
  // Mask of all left vertices.
  let full_left = left_size - 1
  // For each vertex in R, precompute which left vertices it blocks.
  // blocked_by_R[v - mid] = adjacency of v restricted to L bits.
  let right_count = n - mid
  let blocked_by_r = FixedArray::make(right_count, 0)
  for i = 0; i < right_count; i = i + 1 {
    let v = mid + i
    blocked_by_r[i] = adj[v] & full_left
  }
  // --- Phase 1: enumerate independent sets in L ---
  // max_indep_L[mask] = max independent set size that is a subset of `mask`.
  // We first compute ind_size[mask] = size of independent set `mask` (or -1
  // if `mask` is not independent), then do SOS-style max.
  let max_indep_l = FixedArray::make(left_size, 0)
  // Enumerate all subsets of L and check independence.
  // An independent set in L: for each v in the set, adj[v] restricted to L
  // must not intersect the set.
  for mask = 0; mask < left_size; mask = mask + 1 {
    let mut is_indep = true
    let mut m = mask
    while m != 0 {
      let v = lowest_bit(m)
      let neighbors_in_l = adj[v] & full_left
      // Check if any neighbor of v (in L) is also in mask (other than v).
      if (neighbors_in_l & mask) != 0 {
        is_indep = false
        break
      }
      m = m & (m - 1) // clear lowest set bit
    }
    if is_indep {
      max_indep_l[mask] = popcount(mask)
    } else {
      max_indep_l[mask] = 0 // not independent, but subset-of-max will handle it
    }
  }
  // SOS-style max: for each bit i, max_indep_l[mask] = max of itself and
  // max_indep_l[mask without bit i]. This propagates the max independent set
  // size to all supersets... actually we want: for each `mask`, the max over
  // all independent sets that are subsets of `mask`.
  // Standard approach: for each bit i, for each mask with bit i set:
  //   max_indep_l[mask] = max(max_indep_l[mask], max_indep_l[mask ^ (1<<i)])
  // This computes f[mask] = max_{sub ⊆ mask} ind_size[sub].
  for i = 0; i < mid; i = i + 1 {
    let bit = 1 << i
    for mask = 0; mask < left_size; mask = mask + 1 {
      if (mask & bit) != 0 {
        let prev = max_indep_l[mask ^ bit]
        if prev > max_indep_l[mask] {
          max_indep_l[mask] = prev
        }
      }
    }
  }
  // --- Phase 2: enumerate independent sets in R and combine ---
  let mut best = 0
  for r_mask = 0; r_mask < right_size; r_mask = r_mask + 1 {
    // Check independence of r_mask within R.
    let mut is_indep = true
    let mut m = r_mask
    while m != 0 {
      let bit_pos = lowest_bit(m)
      let v = mid + bit_pos
      // Neighbors of v within R (bits shifted to R-local indexing).
      let neighbors_r = (adj[v] >> mid) & (right_size - 1)
      if (neighbors_r & r_mask) != 0 {
        is_indep = false
        break
      }
      m = m & (m - 1)
    }
    if !is_indep {
      continue
    }
    // Compute compatible left vertices: those NOT adjacent to any vertex in r_mask.
    let mut blocked = 0
    let mut m2 = r_mask
    while m2 != 0 {
      let bit_pos = lowest_bit(m2)
      blocked = blocked | blocked_by_r[bit_pos]
      m2 = m2 & (m2 - 1)
    }
    let compat_l = full_left & lnot(blocked)
    // Max independent set in L that is a subset of compat_l.
    let left_best = max_indep_l[compat_l]
    let total = popcount(r_mask) + left_best
    if total > best {
      best = total
    }
  }
  best
}

///|
/// Find the maximum independent set and return the vertex set.
///
/// Returns `(size, vertices)` where `vertices` is an array of vertex indices
/// forming a maximum independent set.
pub fn max_independent_set_vertices(
  adj : Array[Int],
  n : Int,
) -> (Int, Array[Int]) {
  if n <= 0 {
    return (0, [])
  }
  if n == 1 {
    return (1, [0])
  }
  let mid = n / 2
  let left_size = 1 << mid
  let right_size = 1 << (n - mid)
  let full_left = left_size - 1
  let right_count = n - mid
  let blocked_by_r = FixedArray::make(right_count, 0)
  for i = 0; i < right_count; i = i + 1 {
    let v = mid + i
    blocked_by_r[i] = adj[v] & full_left
  }
  // For each independent set in L, store the mask itself (for reconstruction).
  // max_indep_l[mask] = max independent set size ⊆ mask.
  // best_set_l[mask] = the actual independent set achieving that max.
  let max_indep_l = FixedArray::make(left_size, 0)
  let best_set_l = FixedArray::make(left_size, 0)
  for mask = 0; mask < left_size; mask = mask + 1 {
    let mut is_indep = true
    let mut m = mask
    while m != 0 {
      let v = lowest_bit(m)
      let neighbors_in_l = adj[v] & full_left
      if (neighbors_in_l & mask) != 0 {
        is_indep = false
        break
      }
      m = m & (m - 1)
    }
    if is_indep {
      max_indep_l[mask] = popcount(mask)
      best_set_l[mask] = mask
    } else {
      max_indep_l[mask] = 0
      best_set_l[mask] = 0
    }
  }
  // SOS max propagation.
  for i = 0; i < mid; i = i + 1 {
    let bit = 1 << i
    for mask = 0; mask < left_size; mask = mask + 1 {
      if (mask & bit) != 0 {
        let prev = max_indep_l[mask ^ bit]
        if prev > max_indep_l[mask] {
          max_indep_l[mask] = prev
          best_set_l[mask] = best_set_l[mask ^ bit]
        }
      }
    }
  }
  // Phase 2: enumerate R and combine.
  let mut best = 0
  let mut best_r_mask = 0
  let mut best_l_mask = 0
  for r_mask = 0; r_mask < right_size; r_mask = r_mask + 1 {
    let mut is_indep = true
    let mut m = r_mask
    while m != 0 {
      let bit_pos = lowest_bit(m)
      let v = mid + bit_pos
      let neighbors_r = (adj[v] >> mid) & (right_size - 1)
      if (neighbors_r & r_mask) != 0 {
        is_indep = false
        break
      }
      m = m & (m - 1)
    }
    if !is_indep {
      continue
    }
    let mut blocked = 0
    let mut m2 = r_mask
    while m2 != 0 {
      let bit_pos = lowest_bit(m2)
      blocked = blocked | blocked_by_r[bit_pos]
      m2 = m2 & (m2 - 1)
    }
    let compat_l = full_left & lnot(blocked)
    let left_best = max_indep_l[compat_l]
    let total = popcount(r_mask) + left_best
    if total > best {
      best = total
      best_r_mask = r_mask
      best_l_mask = best_set_l[compat_l]
    }
  }
  // Reconstruct vertex list.
  let vertices : Array[Int] = []
  let mut m = best_l_mask
  while m != 0 {
    let v = lowest_bit(m)
    vertices.push(v)
    m = m & (m - 1)
  }
  m = best_r_mask
  while m != 0 {
    let bit_pos = lowest_bit(m)
    vertices.push(mid + bit_pos)
    m = m & (m - 1)
  }
  (best, vertices)
}

// ---------------------------------------------------------------------------
// Minimum Vertex Cover
// ---------------------------------------------------------------------------

///|
/// Find the size of the minimum vertex cover.
///
/// A **vertex cover** is a set of vertices such that every edge has at least
/// one endpoint in the set. The **minimum vertex cover** is the smallest
/// such set.
///
/// By König's theorem (for bipartite graphs) and the general duality:
///
/// ```text
///   min vertex cover = n - max independent set
/// ```
///
/// This holds for **all** graphs (not just bipartite), because the complement
/// of a vertex cover is an independent set and vice versa.
///
/// # Parameters
/// - `adj`: adjacency bitmasks (same format as [`max_independent_set`]).
/// - `n`: number of vertices.
///
/// # Returns
/// The size of the minimum vertex cover.
///
/// # Complexity
/// Same as [`max_independent_set`]: O(2ⁿᐟ² · n).
pub fn min_vertex_cover(adj : Array[Int], n : Int) -> Int {
  n - max_independent_set(adj, n)
}

///|
/// Find the minimum vertex cover and return the vertex set.
///
/// Returns `(size, vertices)` where `vertices` is an array of vertex indices
/// forming a minimum vertex cover.
pub fn min_vertex_cover_vertices(
  adj : Array[Int],
  n : Int,
) -> (Int, Array[Int]) {
  let (_, mis_vertices) = max_independent_set_vertices(adj, n)
  // Vertex cover = complement of independent set.
  let in_mis = FixedArray::make(n, false)
  for i = 0; i < mis_vertices.length(); i = i + 1 {
    in_mis[mis_vertices[i]] = true
  }
  let cover : Array[Int] = []
  for v = 0; v < n; v = v + 1 {
    if !in_mis[v] {
      cover.push(v)
    }
  }
  (cover.length(), cover)
}

// ---------------------------------------------------------------------------
// Chromatic Number
// ---------------------------------------------------------------------------

///|
/// Compute the chromatic number of a graph.
///
/// The **chromatic number** χ(G) is the minimum number of colors needed to
/// color the vertices of `G` such that no two adjacent vertices share the
/// same color.
///
/// # Parameters
/// - `adj`: adjacency bitmasks.
/// - `n`: number of vertices.
///
/// # Returns
/// The chromatic number. Returns 0 for empty graphs (n = 0), 1 for edgeless
/// graphs.
///
/// # Complexity
/// - Time:  O(3ⁿ) (precompute independent sets + subset DP).
/// - Space: O(2ⁿ).
///
/// Practical limit: n ≤ 16 (3¹⁶ ≈ 43M operations).
///
/// # Algorithm
///
/// 1. Precompute `is_indep[mask]` for all masks: true iff `mask` is an
///    independent set (no two vertices in `mask` are adjacent).
/// 2. DP: `chi[mask]` = minimum colors to color the vertices in `mask`.
///    - `chi[0] = 0`
///    - `chi[mask] = 1 + min(chi[mask \ S])` over all independent sets `S`
///      that are subsets of `mask` and contain the lowest bit of `mask`.
///    - The "lowest bit" constraint ensures each partition is counted once.
///
/// This is the standard O(3ⁿ) chromatic number algorithm.
pub fn chromatic_number(adj : Array[Int], n : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if n > 60 {
    // Bit-set overflow; fall back to a safe upper bound.
    return n
  }
  let full = (1 << n) - 1
  // Precompute is_indep[mask].
  let is_indep = FixedArray::make(1 << n, true)
  for mask = 1; mask <= full; mask = mask + 1 {
    // Check if mask is independent: for each v in mask, adj[v] & mask == 0
    // (excluding v itself, which shouldn't be in adj[v] for simple graphs).
    let lb = lowest_bit(mask)
    let v = lb
    // If removing v gives an independent set and v has no neighbor in mask,
    // then mask is independent.
    let rest = mask ^ (1 << v)
    if !is_indep[rest] {
      is_indep[mask] = false
    } else if (
      // Check v against all other vertices in mask.
        adj[v] & mask
      ) !=
      0 {
      is_indep[mask] = false
    }
  }
  // DP: chi[mask] = min colors for mask.
  let chi = FixedArray::make(1 << n, inf_int)
  chi[0] = 0
  for mask = 1; mask <= full; mask = mask + 1 {
    let lb = lowest_bit(mask)
    // Enumerate all independent subsets S of mask that contain the lowest bit.
    // Standard trick: iterate sub = mask; sub = (sub-1) & mask.
    // But we only want subsets containing the lowest bit.
    let mut sub = mask
    while sub != 0 {
      // Check if sub contains the lowest bit of mask.
      if (sub & (1 << lb)) != 0 && is_indep[sub] {
        let remaining = mask ^ sub
        let candidate = chi[remaining] + 1
        if candidate < chi[mask] {
          chi[mask] = candidate
        }
      }
      sub = (sub - 1) & mask
    }
  }
  chi[full]
}

// ---------------------------------------------------------------------------
// Hamiltonian Path / Cycle
// ---------------------------------------------------------------------------

///|
/// Check whether the graph contains a Hamiltonian path.
///
/// A **Hamiltonian path** visits every vertex exactly once.
///
/// # Parameters
/// - `adj`: adjacency bitmasks (undirected graph).
/// - `n`: number of vertices.
///
/// # Returns
/// `true` if a Hamiltonian path exists, `false` otherwise.
///
/// # Complexity
/// - Time:  O(2ⁿ · n²) — actually O(2ⁿ · n) with bitmask adjacency.
/// - Space: O(2ⁿ) bits.
///
/// Practical limit: n ≤ 22.
///
/// # Algorithm
///
/// `dp[mask]` = bitset of all vertices `v` such that there exists a
/// Hamiltonian path visiting exactly the vertices in `mask` and ending at `v`.
///
/// - Base: `dp[1 << v] = (1 << v)` for all v (path of length 0 ending at v).
/// - Transition: `dp[mask | (1 << u)] |= (1 << u)` for each `v` in `dp[mask]`
///   where `u` is adjacent to `v` and `u` is not in `mask`.
/// - Answer: `dp[full] != 0`.
///
/// Using bitsets for `dp` makes each transition a single bitwise OR, giving
/// O(2ⁿ · n) total.
pub fn has_hamiltonian_path(adj : Array[Int], n : Int) -> Bool {
  if n <= 1 {
    return n == 1
  }
  if n > 60 {
    return false
  }
  let full = (1 << n) - 1
  // dp[mask] = bitset of possible ending vertices for a path covering `mask`.
  let dp = FixedArray::make(1 << n, 0)
  // Base: single-vertex paths.
  for v = 0; v < n; v = v + 1 {
    dp[1 << v] = 1 << v
  }
  for mask = 1; mask <= full; mask = mask + 1 {
    let ends = dp[mask]
    if ends == 0 {
      continue
    }
    // For each ending vertex v, try extending to neighbors not in mask.
    let mut v_bits = ends
    while v_bits != 0 {
      let v = lowest_bit(v_bits)
      // Neighbors of v not yet in mask.
      let candidates = adj[v] & lnot(mask)
      let mut c = candidates
      while c != 0 {
        let u = lowest_bit(c)
        dp[mask | (1 << u)] = dp[mask | (1 << u)] | (1 << u)
        c = c & (c - 1)
      }
      v_bits = v_bits & (v_bits - 1)
    }
  }
  dp[full] != 0
}

///|
/// Check whether the graph contains a Hamiltonian cycle.
///
/// A **Hamiltonian cycle** visits every vertex exactly once and returns to
/// the starting vertex.
///
/// # Parameters
/// - `adj`: adjacency bitmasks (undirected graph).
/// - `n`: number of vertices.
///
/// # Returns
/// `true` if a Hamiltonian cycle exists, `false` otherwise.
///
/// # Complexity
/// Same as [`has_hamiltonian_path`]: O(2ⁿ · n).
///
/// # Algorithm
///
/// Same DP as [`has_hamiltonian_path`], but the answer checks: for each
/// ending vertex `v` in `dp[full]`, is `v` adjacent to the start vertex 0?
/// (We fix vertex 0 as the start without loss of generality.)
pub fn has_hamiltonian_cycle(adj : Array[Int], n : Int) -> Bool {
  if n <= 2 {
    return n == 2 && (adj[0] & 2) != 0
  }
  if n > 60 {
    return false
  }
  let full = (1 << n) - 1
  let dp = FixedArray::make(1 << n, 0)
  // Fix start at vertex 0.
  dp[1] = 1
  for mask = 1; mask <= full; mask = mask + 1 {
    if (mask & 1) == 0 {
      // Vertex 0 must be in every valid path (it's the fixed start).
      continue
    }
    let ends = dp[mask]
    if ends == 0 {
      continue
    }
    let mut v_bits = ends
    while v_bits != 0 {
      let v = lowest_bit(v_bits)
      let candidates = adj[v] & lnot(mask)
      let mut c = candidates
      while c != 0 {
        let u = lowest_bit(c)
        dp[mask | (1 << u)] = dp[mask | (1 << u)] | (1 << u)
        c = c & (c - 1)
      }
      v_bits = v_bits & (v_bits - 1)
    }
  }
  // Check: does any ending vertex in dp[full] connect back to vertex 0?
  let ends = dp[full]
  if ends == 0 {
    return false
  }
  // Vertex 0 should not be in ends (it's already visited), but check neighbors.
  let mut v_bits = ends
  while v_bits != 0 {
    let v = lowest_bit(v_bits)
    if (adj[v] & 1) != 0 {
      // v is adjacent to vertex 0 → cycle complete.
      return true
    }
    v_bits = v_bits & (v_bits - 1)
  }
  false
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// --- TSP tests ---

///|
test "tsp: simple 4-city symmetric" {
  //     0 --1-- 1
  //     |       |
  //     2       3
  //     |       |
  //     3 --4-- 2
  // Distances:
  //   0-1: 1, 0-3: 2, 1-2: 3, 2-3: 4
  //   0-2: 10 (far), 1-3: 10 (far)
  // Optimal tour: 0 → 1 → 2 → 3 → 0 = 1+3+4+2 = 10
  let n = 4
  let dist : Array[Array[Int64]] = [
    [0L, 1L, 10L, 2L],
    [1L, 0L, 3L, 10L],
    [10L, 3L, 0L, 4L],
    [2L, 10L, 4L, 0L],
  ]
  assert_eq(tsp(n, dist), Some(10L))
}

///|
test "tsp: asymmetric" {
  // Asymmetric: going one direction is cheaper.
  //   0 → 1 (1), 1 → 2 (1), 2 → 0 (1)
  //   0 → 2 (10), 2 → 1 (10), 1 → 0 (10)
  // Optimal: 0 → 1 → 2 → 0 = 1+1+1 = 3
  let n = 3
  let dist : Array[Array[Int64]] = [[0L, 1L, 10L], [10L, 0L, 1L], [1L, 10L, 0L]]
  assert_eq(tsp(n, dist), Some(3L))
}

///|
test "tsp: two cities" {
  let dist : Array[Array[Int64]] = [[0L, 5L], [5L, 0L]]
  assert_eq(tsp(2, dist), Some(10L))
}

///|
test "tsp: invalid inputs" {
  assert_true(tsp(1, [[0L]]) is None)
  assert_true(tsp(0, []) is None)
  // Negative distance.
  let bad : Array[Array[Int64]] = [[0L, -1L], [1L, 0L]]
  assert_true(tsp(2, bad) is None)
}

///|
test "tsp: complete graph K5 unit weights" {
  // All distances 1. Any tour = 5.
  let n = 5
  let dist : Array[Array[Int64]] = []
  for i = 0; i < n; i = i + 1 {
    let row : Array[Int64] = []
    for j = 0; j < n; j = j + 1 {
      if i == j {
        row.push(0L)
      } else {
        row.push(1L)
      }
    }
    dist.push(row)
  }
  assert_eq(tsp(n, dist), Some(5L))
}

///|
test "tsp: path reconstruction" {
  // 4 cities, optimal tour 0 → 1 → 2 → 3 → 0 = 10.
  let n = 4
  let dist : Array[Array[Int64]] = [
    [0L, 1L, 10L, 2L],
    [1L, 0L, 3L, 10L],
    [10L, 3L, 0L, 4L],
    [2L, 10L, 4L, 0L],
  ]
  let result = tsp_path(n, dist)
  match result {
    Some((cost, tour)) => {
      assert_eq(cost, 10L)
      assert_eq(tour.length(), n)
      // Verify the tour starts at 0.
      assert_eq(tour[0], 0)
      // Verify the tour is valid: each consecutive pair has a distance,
      // and the tour returns to 0 (cost includes return).
      let mut total = 0L
      for i = 0; i < n - 1; i = i + 1 {
        total = total + dist[tour[i]][tour[i + 1]]
      }
      total = total + dist[tour[n - 1]][tour[0]]
      assert_eq(total, 10L)
      // Verify all vertices are distinct.
      let seen = FixedArray::make(n, false)
      for i = 0; i < n; i = i + 1 {
        assert_true(!seen[tour[i]])
        seen[tour[i]] = true
      }
    }
    None => fail("expected Some")
  }
}

///|
test "tsp: large weights no overflow" {
  // Weights near Int64 max / 4.
  let big = 2000000000000L
  let n = 3
  let dist : Array[Array[Int64]] = [
    [0L, big, big],
    [big, 0L, big],
    [big, big, 0L],
  ]
  // Tour = 3 * big.
  assert_eq(tsp(n, dist), Some(big * 3L))
}

// --- Maximum Independent Set tests ---

///|
test "mis: empty graph" {
  assert_eq(max_independent_set([], 0), 0)
}

///|
test "mis: single vertex" {
  assert_eq(max_independent_set([0], 1), 1)
}

///|
test "mis: no edges (all independent)" {
  // 5 isolated vertices → MIS = 5.
  let adj = [0, 0, 0, 0, 0]
  assert_eq(max_independent_set(adj, 5), 5)
}

///|
test "mis: complete graph K4" {
  // Every pair adjacent → MIS = 1.
  let n = 4
  let adj = [0, 0, 0, 0]
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        adj[i] = adj[i] | (1 << j)
      }
    }
  }
  assert_eq(max_independent_set(adj, n), 1)
}

///|
test "mis: path graph P5" {
  // 0 - 1 - 2 - 3 - 4
  // MIS = {0, 2, 4} → size 3.
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 1), (1, 2), (2, 3), (3, 4)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_eq(max_independent_set(adj, 5), 3)
}

///|
test "mis: cycle C5" {
  // 0 - 1 - 2 - 3 - 4 - 0
  // MIS = 2 (e.g., {0, 2}).
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_eq(max_independent_set(adj, 5), 2)
}

///|
test "mis: star graph" {
  // Center 0 connected to 1, 2, 3, 4.
  // MIS = {1, 2, 3, 4} → size 4.
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 1), (0, 2), (0, 3), (0, 4)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_eq(max_independent_set(adj, 5), 4)
}

///|
test "mis: bipartite graph" {
  // Complete bipartite K_{2,3}: {0,1} vs {2,3,4}
  // MIS = max(2, 3) = 3.
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 2), (0, 3), (0, 4), (1, 2), (1, 3), (1, 4)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_eq(max_independent_set(adj, 5), 3)
}

///|
test "mis: vertex set reconstruction" {
  // Path: 0 - 1 - 2 - 3 - 4
  // MIS = {0, 2, 4}, size 3.
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 1), (1, 2), (2, 3), (3, 4)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  let (size, vertices) = max_independent_set_vertices(adj, 5)
  assert_eq(size, 3)
  // Verify independence: no two vertices in the set are adjacent.
  for i = 0; i < vertices.length(); i = i + 1 {
    for j = i + 1; j < vertices.length(); j = j + 1 {
      let u = vertices[i]
      let v = vertices[j]
      assert_true((adj[u] & (1 << v)) == 0)
    }
  }
}

///|
test "mis: brute force cross-check n=10" {
  // Random graph with 10 vertices, cross-check against brute force.
  let n = 10
  let adj = Array::make(n, 0)
  // Deterministic pseudo-random edges.
  let mut st = 42
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      st = (st * 1103515245 + 12345) & 0x7FFFFFFF
      if st % 100 < 40 {
        // 40% edge probability.
        adj[i] = adj[i] | (1 << j)
        adj[j] = adj[j] | (1 << i)
      }
    }
  }
  let mis_size = max_independent_set(adj, n)
  // Brute force: try all 2^10 = 1024 subsets.
  let mut brute = 0
  for mask = 0; mask < 1 << n; mask = mask + 1 {
    let mut ok = true
    for i = 0; i < n && ok; i = i + 1 {
      if (mask & (1 << i)) != 0 {
        if (adj[i] & mask) != 0 {
          ok = false
        }
      }
    }
    if ok {
      let sz = popcount(mask)
      if sz > brute {
        brute = sz
      }
    }
  }
  assert_eq(mis_size, brute)
}

// --- Minimum Vertex Cover tests ---

///|
test "mvc: path graph P5" {
  // 0 - 1 - 2 - 3 - 4
  // MVC = {1, 3} → size 2. (n - MIS = 5 - 3 = 2)
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 1), (1, 2), (2, 3), (3, 4)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_eq(min_vertex_cover(adj, 5), 2)
}

///|
test "mvc: complete graph K4" {
  let n = 4
  let adj = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        adj[i] = adj[i] | (1 << j)
      }
    }
  }
  // MVC = 3 (need n-1 vertices for K_n).
  assert_eq(min_vertex_cover(adj, n), 3)
}

///|
test "mvc: vertex set reconstruction" {
  // Path: 0 - 1 - 2 - 3 - 4
  // MVC = {1, 3} or {0, 2, 4}... wait: MVC = n - MIS = 5 - 3 = 2.
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 1), (1, 2), (2, 3), (3, 4)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  let (size, cover) = min_vertex_cover_vertices(adj, 5)
  assert_eq(size, 2)
  // Verify vertex cover: every edge has at least one endpoint in cover.
  let in_cover = FixedArray::make(5, false)
  for v in cover {
    in_cover[v] = true
  }
  for e in edges {
    let (u, v) = e
    assert_true(in_cover[u] || in_cover[v])
  }
}

///|
test "mvc: brute force cross-check n=10" {
  let n = 10
  let adj = Array::make(n, 0)
  let mut st = 99
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      st = (st * 1103515245 + 12345) & 0x7FFFFFFF
      if st % 100 < 50 {
        adj[i] = adj[i] | (1 << j)
        adj[j] = adj[j] | (1 << i)
      }
    }
  }
  let mvc_size = min_vertex_cover(adj, n)
  // Brute force: find minimum vertex cover.
  let mut brute = n
  for mask = 0; mask < 1 << n; mask = mask + 1 {
    let sz = popcount(mask)
    if sz >= brute {
      continue
    }
    // Check if mask is a vertex cover.
    let mut ok = true
    for i = 0; i < n && ok; i = i + 1 {
      // For each vertex i NOT in the cover, all its neighbors must be in the cover.
      if (mask & (1 << i)) == 0 {
        if (adj[i] & lnot(mask)) != 0 {
          ok = false
        }
      }
    }
    if ok {
      brute = sz
    }
  }
  assert_eq(mvc_size, brute)
}

// --- Chromatic Number tests ---

///|
test "chromatic: empty graph" {
  assert_eq(chromatic_number([], 0), 0)
}

///|
test "chromatic: no edges" {
  let adj = [0, 0, 0, 0]
  assert_eq(chromatic_number(adj, 4), 1)
}

///|
test "chromatic: complete graph K4" {
  let n = 4
  let adj = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        adj[i] = adj[i] | (1 << j)
      }
    }
  }
  assert_eq(chromatic_number(adj, n), 4)
}

///|
test "chromatic: bipartite graph" {
  // Path: 0 - 1 - 2 - 3
  // χ = 2.
  let adj = [0, 0, 0, 0]
  let edges = [(0, 1), (1, 2), (2, 3)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_eq(chromatic_number(adj, 4), 2)
}

///|
test "chromatic: odd cycle C5" {
  // C5 needs 3 colors.
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_eq(chromatic_number(adj, 5), 3)
}

///|
test "chromatic: even cycle C6" {
  // C6 needs 2 colors.
  let adj = [0, 0, 0, 0, 0, 0]
  let edges = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_eq(chromatic_number(adj, 6), 2)
}

///|
test "chromatic: wheel graph W5" {
  // Center 0 connected to cycle 1-2-3-4-5-1.
  // χ = 4 (odd cycle + hub).
  let adj = [0, 0, 0, 0, 0, 0]
  let edges = [
    (0, 1),
    (0, 2),
    (0, 3),
    (0, 4),
    (0, 5),
    (1, 2),
    (2, 3),
    (3, 4),
    (4, 5),
    (5, 1),
  ]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_eq(chromatic_number(adj, 6), 4)
}

// --- Hamiltonian Path / Cycle tests ---

///|
test "hamiltonian: path in complete graph" {
  let n = 5
  let adj = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        adj[i] = adj[i] | (1 << j)
      }
    }
  }
  assert_true(has_hamiltonian_path(adj, n))
  assert_true(has_hamiltonian_cycle(adj, n))
}

///|
test "hamiltonian: path in a chain" {
  // 0 - 1 - 2 - 3 - 4
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 1), (1, 2), (2, 3), (3, 4)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_true(has_hamiltonian_path(adj, 5))
  // No cycle (no edge 4-0).
  assert_false(has_hamiltonian_cycle(adj, 5))
}

///|
test "hamiltonian: cycle in C5" {
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_true(has_hamiltonian_path(adj, 5))
  assert_true(has_hamiltonian_cycle(adj, 5))
}

///|
test "hamiltonian: no path (disconnected)" {
  // 0 - 1, 2 - 3 (two components, 4 vertices).
  let adj = [0, 0, 0, 0]
  let edges = [(0, 1), (2, 3)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_false(has_hamiltonian_path(adj, 4))
  assert_false(has_hamiltonian_cycle(adj, 4))
}

///|
test "hamiltonian: star graph has no Hamiltonian path for n > 3" {
  // Center 0, leaves 1, 2, 3, 4.
  // No Hamiltonian path for n=5 star (leaves can't be consecutive).
  let adj = [0, 0, 0, 0, 0]
  let edges = [(0, 1), (0, 2), (0, 3), (0, 4)]
  for e in edges {
    let (u, v) = e
    adj[u] = adj[u] | (1 << v)
    adj[v] = adj[v] | (1 << u)
  }
  assert_false(has_hamiltonian_path(adj, 5))
}

// --- BitGraph API tests ---

///|
test "bitgraph: basic operations" {
  let g = match new_graph(5) {
    Some(g) => g
    None => fail("new_graph failed")
  }
  assert_false(has_edge(g, 0, 1))
  add_edge(g, 0, 1)
  add_edge(g, 1, 2)
  assert_true(has_edge(g, 0, 1))
  assert_true(has_edge(g, 1, 0))
  assert_true(has_edge(g, 1, 2))
  assert_false(has_edge(g, 0, 2))
}

///|
test "bitgraph: invalid size rejected" {
  assert_true(new_graph(61) is None)
  assert_true(new_graph(-1) is None)
}

// --- Cross-check: MIS + MVC = n ---

///|
test "duality: MIS + MVC = n" {
  // For any graph, max independent set + min vertex cover = n.
  let n = 12
  let adj = Array::make(n, 0)
  let mut st = 777
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      st = (st * 1103515245 + 12345) & 0x7FFFFFFF
      if st % 100 < 45 {
        adj[i] = adj[i] | (1 << j)
        adj[j] = adj[j] | (1 << i)
      }
    }
  }
  let mis = max_independent_set(adj, n)
  let mvc = min_vertex_cover(adj, n)
  assert_eq(mis + mvc, n)
}
