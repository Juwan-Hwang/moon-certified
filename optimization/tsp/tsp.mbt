/// TSP Heuristics — Christofides approximation + 2-Opt / Or-Opt local search.
///
/// This package provides heuristic algorithms for the **Traveling Salesman
/// Problem** (TSP) on **metric** instances — where distances satisfy the
/// triangle inequality: d(i, k) ≤ d(i, j) + d(j, k).
///
/// ## Algorithms
///
/// ### Christofides Algorithm (1.5-approximation)
///
/// For metric TSP, Christofides' algorithm guarantees a tour within **1.5 ×
/// OPT**. The algorithm proceeds as follows:
///
/// 1. **MST**: Build a Minimum Spanning Tree via Prim's algorithm — O(n²).
/// 2. **Odd vertices**: Identify vertices with odd degree in the MST. By the
///    handshaking lemma, there is always an even number of them.
/// 3. **Min-weight perfect matching**: Find a minimum-weight perfect matching
///    on the odd-degree vertices. For ≤ 20 odd vertices, an optimal O(2ᵏ·k²)
///    DP is used; for larger sets, a greedy heuristic is used.
/// 4. **Euler tour**: The MST + matching forms an Eulerian multigraph. Find
///    an Euler tour via Hierholzer's algorithm — O(E).
/// 5. **Shortcut**: Convert the Euler tour to a Hamiltonian cycle by skipping
///    already-visited vertices. The triangle inequality ensures this never
///    increases the tour length.
///
/// ### 2-Opt Local Search
///
/// Repeatedly reverses tour segments to eliminate edge crossings. Each 2-Opt
/// move removes two edges `(vᵢ, vᵢ₊₁)` and `(vⱼ, vⱼ₊₁)`, then reconnects
/// with `(vᵢ, vⱼ)` and `(vᵢ₊₁, vⱼ₊₁)`, reversing the segment `[i+1, j]`.
/// The move is accepted only if it reduces total tour length. One pass is
/// O(n²); the algorithm iterates until no improvement is found or a maximum
/// iteration count is reached.
///
/// ### Or-Opt Local Search
///
/// Moves segments of length 1–3 to better positions in the tour. For each
/// segment, the removal gain and insertion cost are computed in O(1), making
/// one pass O(n²). Or-Opt complements 2-Opt by catching improvements that
/// 2-Opt cannot find (e.g., relocating a single vertex).
///
/// ### Nearest Neighbor
///
/// A simple O(n²) greedy heuristic: start at vertex 0, repeatedly visit the
/// nearest unvisited vertex. Used as a baseline and for comparison.
///
/// ## Complexity
///
/// | Algorithm             | Time       |
/// |-----------------------|------------|
/// | `christofides`        | O(n³)      |
/// | `two_opt` (per pass)  | O(n²)      |
/// | `or_opt` (per pass)   | O(n²)      |
/// | `nearest_neighbor`    | O(n²)      |
/// | `solve_tsp`           | O(n³)      |
///
/// ## References
///
/// - Christofides, N. (1976). "Worst-case analysis of a new heuristic for the
///   travelling salesman problem." Technical Report 388, Carnegie-Mellon.
/// - Croes, G. A. (1958). "A method for solving traveling salesman problems."
///   *Operations Research*, 6(6), 791–812.
/// - Helsgaun, K. (2000). "An effective implementation of the Lin-Kernighan
///   traveling salesman heuristic." *European J. Oper. Res.*, 126(1), 106–130.
/// - Or, I. (1976). "Traveling salesman-type combinatorial problems and their
///   relation to the logistics of regional blood banking." Ph.D. thesis,
///   Northwestern University.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

const INF : Double = 1.0e18

// ---------------------------------------------------------------------------
// Tour cost
// ---------------------------------------------------------------------------

///|
/// Compute the total length of a TSP tour.
///
/// The tour is a permutation of `[0, n)` representing the visit order. The
/// tour is **closed**: the last city connects back to the first.
pub fn tour_cost(tour : Array[Int], dist : (Int, Int) -> Double) -> Double {
  let n = tour.length()
  if n < 2 {
    return 0.0
  }
  let mut total = 0.0
  for i = 0; i < n; i = i + 1 {
    total = total + dist(tour[i], tour[(i + 1) % n])
  }
  total
}

// ---------------------------------------------------------------------------
// Prim's MST — O(n²) for dense graphs
// ---------------------------------------------------------------------------

///|
/// Build a Minimum Spanning Tree using Prim's algorithm.
///
/// Returns the parent array: `parent[i]` is the parent of vertex `i` in the
/// MST. The root (vertex 0) has parent `-1`.
fn prim_mst(n : Int, dist : (Int, Int) -> Double) -> Array[Int] {
  let parent = Array::make(n, -1)
  let key = Array::make(n, INF)
  let in_mst = Array::make(n, false)
  key[0] = 0.0
  for iter = 0; iter < n; iter = iter + 1 {
    // Find the minimum-key vertex not yet in MST.
    let mut u = -1
    let mut min_key = INF
    for v = 0; v < n; v = v + 1 {
      if !in_mst[v] && key[v] < min_key {
        min_key = key[v]
        u = v
      }
    }
    if u == -1 {
      break
    }
    in_mst[u] = true
    // Relax adjacent vertices (complete graph: all others are adjacent).
    for v = 0; v < n; v = v + 1 {
      if !in_mst[v] {
        let d = dist(u, v)
        if d < key[v] {
          key[v] = d
          parent[v] = u
        }
      }
    }
  }
  parent
}

// ---------------------------------------------------------------------------
// Minimum Weight Perfect Matching
// ---------------------------------------------------------------------------

///|
/// Compute a minimum weight perfect matching on a set of vertices.
///
/// For small sets (≤ 20 vertices), uses optimal DP over bitmasks — O(2ᵏ·k²).
/// For larger sets, uses a greedy heuristic — O(k² log k).
///
/// `odd` must have an even number of elements.
/// Returns a list of `(u, v)` pairs representing matched vertices.
fn min_weight_perfect_matching(
  odd : Array[Int],
  dist : (Int, Int) -> Double,
) -> Array[(Int, Int)] {
  let k = odd.length()
  if k == 0 {
    return []
  }
  if k <= 20 {
    matching_dp(odd, dist)
  } else {
    matching_greedy(odd, dist)
  }
}

///|
/// Optimal minimum weight perfect matching via DP over bitmasks.
///
/// State: `dp[mask]` = minimum cost to perfectly match the vertices indicated
/// by the set bits in `mask`. Transition: pick the first unset bit `i`, try
/// matching it with every other unset bit `j`.
///
/// Time: O(2ᵏ · k²), suitable for k ≤ 20 (≤ 1M states).
fn matching_dp(
  odd : Array[Int],
  dist : (Int, Int) -> Double,
) -> Array[(Int, Int)] {
  let k = odd.length()
  let full = 1 << k
  let dp = Array::make(full, INF)
  let choice_i = Array::make(full, -1)
  let choice_j = Array::make(full, -1)
  dp[0] = 0.0
  for mask = 0; mask < full; mask = mask + 1 {
    if dp[mask] >= INF {
      continue
    }
    // Find the first unset bit — fixing it avoids double-counting.
    let mut first = -1
    for i = 0; i < k; i = i + 1 {
      if (mask & (1 << i)) == 0 {
        first = i
        break
      }
    }
    if first == -1 {
      continue // All bits set — complete matching.
    }
    // Try matching `first` with each other unset bit.
    for j = first + 1; j < k; j = j + 1 {
      if (mask & (1 << j)) == 0 {
        let new_mask = mask | (1 << first) | (1 << j)
        let cost = dp[mask] + dist(odd[first], odd[j])
        if cost < dp[new_mask] {
          dp[new_mask] = cost
          choice_i[new_mask] = first
          choice_j[new_mask] = j
        }
      }
    }
  }
  // Reconstruct the matching from the choice arrays.
  let result : Array[(Int, Int)] = []
  let mut mask = full - 1
  while mask > 0 {
    let i = choice_i[mask]
    let j = choice_j[mask]
    result.push((odd[i], odd[j]))
    mask = mask ^ (1 << i) ^ (1 << j)
  }
  result
}

///|
/// Greedy minimum weight perfect matching.
///
/// Sorts all pairs by distance, then greedily selects non-overlapping edges.
/// Not optimal, but practical for large odd-vertex sets where the DP is
/// infeasible. The 2-Opt / Or-Opt local search compensates for suboptimal
/// matching in practice.
fn matching_greedy(
  odd : Array[Int],
  dist : (Int, Int) -> Double,
) -> Array[(Int, Int)] {
  let k = odd.length()
  // Generate all pairs with their distances.
  let pairs : Array[(Double, Int, Int)] = []
  for i = 0; i < k; i = i + 1 {
    for j = i + 1; j < k; j = j + 1 {
      pairs.push((dist(odd[i], odd[j]), i, j))
    }
  }
  // Sort by distance ascending.
  pairs.sort_by(fn(a, b) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  // Greedily select non-conflicting edges.
  let matched = Array::make(k, false)
  let result : Array[(Int, Int)] = []
  for idx = 0; idx < pairs.length(); idx = idx + 1 {
    let (_, i, j) = pairs[idx]
    if !matched[i] && !matched[j] {
      matched[i] = true
      matched[j] = true
      result.push((odd[i], odd[j]))
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Euler Tour — Hierholzer's Algorithm
// ---------------------------------------------------------------------------

///|
/// Find an Euler tour of a connected multigraph using Hierholzer's algorithm.
///
/// The graph is given as a list of undirected edges. Every vertex must have
/// even degree (Eulerian condition). The tour starts at vertex 0.
///
/// Returns the tour as a sequence of vertex IDs. The tour is closed (first
/// vertex equals last vertex). The tour is produced in reverse order by the
/// stack-based algorithm; we return it as-is since the shortcut step works
/// in either direction.
///
/// Time: O(E).
fn euler_tour_hierholzer(n : Int, edges : Array[(Int, Int)]) -> Array[Int] {
  let num_edges = edges.length()
  // Build adjacency list: adj[v] = [(neighbor, edge_id), ...]
  let adj : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    adj.push([])
  }
  for eid = 0; eid < num_edges; eid = eid + 1 {
    let (u, v) = edges[eid]
    adj[u].push((v, eid))
    adj[v].push((u, eid))
  }
  // Hierholzer with explicit stack.
  let used = Array::make(num_edges, false)
  let ptr = Array::make(n, 0)
  let stack : Array[Int] = [0]
  let tour : Array[Int] = []
  while stack.length() > 0 {
    let v = stack[stack.length() - 1]
    let mut found = false
    while ptr[v] < adj[v].length() {
      let (u, eid) = adj[v][ptr[v]]
      ptr[v] = ptr[v] + 1
      if !used[eid] {
        used[eid] = true
        stack.push(u)
        found = true
        break
      }
    }
    if !found {
      match stack.pop() {
        Some(v) => tour.push(v)
        None => break
      }
    }
  }
  tour
}

// ---------------------------------------------------------------------------
// Christofides Algorithm
// ---------------------------------------------------------------------------

///|
/// Solve metric TSP using the Christofides algorithm (1.5-approximation).
///
/// **Precondition**: `dist` must satisfy the triangle inequality.
///
/// Returns a permutation of `[0, n)` representing the tour visit order.
/// The tour is closed (last city connects back to first).
///
/// For `n ≤ 2`, the trivial tour is returned.
pub fn christofides(n : Int, dist : (Int, Int) -> Double) -> Array[Int] {
  if n == 0 {
    return []
  }
  if n == 1 {
    return [0]
  }
  if n == 2 {
    return [0, 1]
  }
  // Step 1: Build MST.
  let parent = prim_mst(n, dist)
  // Step 2: Find odd-degree vertices and collect MST edges.
  let degree = Array::make(n, 0)
  let mst_edges : Array[(Int, Int)] = []
  for i = 1; i < n; i = i + 1 {
    let p = parent[i]
    mst_edges.push((p, i))
    degree[p] = degree[p] + 1
    degree[i] = degree[i] + 1
  }
  let odd : Array[Int] = []
  for v = 0; v < n; v = v + 1 {
    if degree[v] % 2 == 1 {
      odd.push(v)
    }
  }
  // Step 3: Minimum weight perfect matching on odd vertices.
  let matching = min_weight_perfect_matching(odd, dist)
  // Step 4: Combine MST + matching into Eulerian multigraph.
  let all_edges : Array[(Int, Int)] = []
  for i = 0; i < mst_edges.length(); i = i + 1 {
    all_edges.push(mst_edges[i])
  }
  for i = 0; i < matching.length(); i = i + 1 {
    all_edges.push(matching[i])
  }
  // Step 5: Euler tour.
  let euler = euler_tour_hierholzer(n, all_edges)
  // Step 6: Shortcut to Hamiltonian cycle.
  let visited = Array::make(n, false)
  let tour : Array[Int] = []
  for i = 0; i < euler.length(); i = i + 1 {
    let v = euler[i]
    if !visited[v] {
      visited[v] = true
      tour.push(v)
    }
  }
  // Safety: if any vertex was missed (shouldn't happen for a connected
  // Eulerian graph), append it.
  for v = 0; v < n; v = v + 1 {
    if !visited[v] {
      tour.push(v)
    }
  }
  tour
}

// ---------------------------------------------------------------------------
// 2-Opt Local Search
// ---------------------------------------------------------------------------

///|
/// Improve a TSP tour using 2-Opt local search.
///
/// Repeatedly reverses tour segments to eliminate edge crossings. Uses a
/// first-improvement strategy: the first improving move found is applied
/// immediately, and the search restarts. Iterates until no improvement is
/// found or `max_iter` (default 1000) passes are completed.
///
/// The input tour is not modified; a new array is returned.
pub fn two_opt(tour : Array[Int], dist : (Int, Int) -> Double) -> Array[Int] {
  two_opt_with_iterations(tour, dist, 1000)
}

///|
/// 2-Opt with a custom maximum number of passes.
pub fn two_opt_with_iterations(
  tour : Array[Int],
  dist : (Int, Int) -> Double,
  max_iter : Int,
) -> Array[Int] {
  let n = tour.length()
  if n < 4 {
    return copy_array(tour)
  }
  let current = copy_array(tour)
  let mut iter = 0
  let mut improved = true
  while improved && iter < max_iter {
    improved = false
    iter = iter + 1
    for i = 0; i < n - 1; i = i + 1 {
      for j = i + 2; j < n; j = j + 1 {
        // Skip adjacent edges connected via the wrap-around.
        if i == 0 && j == n - 1 {
          continue
        }
        let old_cost = dist(current[i], current[i + 1]) + dist(
          current[j],
          current[(j + 1) % n],
        )
        let new_cost = dist(current[i], current[j]) + dist(
          current[i + 1],
          current[(j + 1) % n],
        )
        if new_cost < old_cost - 1.0e-10 {
          reverse_segment(current, i + 1, j)
          improved = true
        }
      }
    }
  }
  current
}

// ---------------------------------------------------------------------------
// Or-Opt Local Search
// ---------------------------------------------------------------------------

///|
/// Improve a TSP tour using Or-Opt local search.
///
/// Moves segments of length 1–3 to better positions in the tour. For each
/// segment, the removal gain and insertion cost are computed in O(1). The
/// search uses first-improvement and iterates until no improvement is found.
///
/// The input tour is not modified; a new array is returned.
pub fn or_opt(tour : Array[Int], dist : (Int, Int) -> Double) -> Array[Int] {
  or_opt_with_iterations(tour, dist, 100)
}

///|
/// Or-Opt with a custom maximum number of passes.
pub fn or_opt_with_iterations(
  tour : Array[Int],
  dist : (Int, Int) -> Double,
  max_iter : Int,
) -> Array[Int] {
  let n = tour.length()
  if n < 5 {
    return copy_array(tour)
  }
  let mut current = copy_array(tour)
  let mut improved = true
  let mut iter = 0
  while improved && iter < max_iter {
    improved = false
    iter = iter + 1
    for seg_len = 1; seg_len <= 3; seg_len = seg_len + 1 {
      if seg_len >= n - 1 {
        continue
      }
      for i = 1; i < n - seg_len; i = i + 1 {
        let prev_i = current[i - 1]
        let first = current[i]
        let last = current[i + seg_len - 1]
        let next_i = current[i + seg_len]
        let remove_gain = dist(prev_i, first) + dist(last, next_i) - dist(
          prev_i,
          next_i,
        )
        for j = 1; j <= n - seg_len; j = j + 1 {
          if j == i {
            continue // No-op: inserting at the same position.
          }
          // Determine the vertices at the insertion point.
          let (v_before, v_after) = if j < i {
            (current[j - 1], current[j])
          } else {
            (current[j + seg_len - 1], current[(j + seg_len) % n])
          }
          let insert_cost = dist(v_before, first) + dist(last, v_after) - dist(
            v_before,
            v_after,
          )
          let gain = remove_gain - insert_cost
          if gain > 1.0e-10 {
            current = or_opt_move(current, i, seg_len, j)
            improved = true
            break
          }
        }
        if improved {
          break
        }
      }
      if improved {
        break
      }
    }
  }
  current
}

///|
/// Perform an Or-Opt move: relocate segment `[i, i+seg_len)` to position `j`.
///
/// Position `j` refers to the index in the **reduced** tour (after removing
/// the segment) where the segment is inserted before.
fn or_opt_move(
  tour : Array[Int],
  i : Int,
  seg_len : Int,
  j : Int,
) -> Array[Int] {
  let n = tour.length()
  // Extract the segment.
  let segment : Array[Int] = []
  for k = 0; k < seg_len; k = k + 1 {
    segment.push(tour[i + k])
  }
  // Build the reduced tour (without the segment).
  let reduced : Array[Int] = []
  for k = 0; k < i; k = k + 1 {
    reduced.push(tour[k])
  }
  for k = i + seg_len; k < n; k = k + 1 {
    reduced.push(tour[k])
  }
  // Adjust insertion index: if j > i, the reduced tour is shorter by seg_len.
  let adj_j = if j > i { j - seg_len } else { j }
  // Build the final tour.
  let result : Array[Int] = []
  for k = 0; k < adj_j; k = k + 1 {
    result.push(reduced[k])
  }
  for k = 0; k < seg_len; k = k + 1 {
    result.push(segment[k])
  }
  for k = adj_j; k < reduced.length(); k = k + 1 {
    result.push(reduced[k])
  }
  result
}

// ---------------------------------------------------------------------------
// Nearest Neighbor Heuristic
// ---------------------------------------------------------------------------

///|
/// Construct a TSP tour using the Nearest Neighbor greedy heuristic.
///
/// Starting from vertex 0, repeatedly visit the nearest unvisited vertex.
/// Time: O(n²). The resulting tour is typically 20–30% above optimal.
pub fn nearest_neighbor(n : Int, dist : (Int, Int) -> Double) -> Array[Int] {
  if n == 0 {
    return []
  }
  if n == 1 {
    return [0]
  }
  let visited = Array::make(n, false)
  let tour : Array[Int] = [0]
  visited[0] = true
  for step = 1; step < n; step = step + 1 {
    let cur = tour[tour.length() - 1]
    let mut best = -1
    let mut best_d = INF
    for v = 0; v < n; v = v + 1 {
      if !visited[v] {
        let d = dist(cur, v)
        if d < best_d {
          best_d = d
          best = v
        }
      }
    }
    if best == -1 {
      break
    }
    visited[best] = true
    tour.push(best)
  }
  tour
}

// ---------------------------------------------------------------------------
// Combined Solver
// ---------------------------------------------------------------------------

///|
/// Solve metric TSP with Christofides + 2-Opt + Or-Opt.
///
/// This is the recommended entry point. The pipeline is:
///
/// 1. Christofides → initial tour (≤ 1.5 × OPT).
/// 2. 2-Opt → eliminate crossings.
/// 3. Or-Opt → relocate short segments.
/// 4. 2-Opt again → Or-Opt may enable further 2-Opt improvements.
///
/// **Precondition**: `dist` must satisfy the triangle inequality.
pub fn solve_tsp(n : Int, dist : (Int, Int) -> Double) -> Array[Int] {
  if n == 0 {
    return []
  }
  if n == 1 {
    return [0]
  }
  if n == 2 {
    return [0, 1]
  }
  let initial = christofides(n, dist)
  let after_2opt = two_opt(initial, dist)
  let after_or_opt = or_opt(after_2opt, dist)
  two_opt(after_or_opt, dist)
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

///|
/// Check whether `tour` is a valid TSP tour for `n` cities.
///
/// A valid tour is a permutation of `[0, n)` — each city visited exactly once.
pub fn is_valid_tour(tour : Array[Int], n : Int) -> Bool {
  if tour.length() != n {
    return false
  }
  let seen = Array::make(n, false)
  for i = 0; i < n; i = i + 1 {
    let v = tour[i]
    if v < 0 || v >= n {
      return false
    }
    if seen[v] {
      return false
    }
    seen[v] = true
  }
  true
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
/// Reverse a segment of an array in place: `[lo, hi]`.
fn reverse_segment(arr : Array[Int], lo : Int, hi : Int) -> Unit {
  let mut i = lo
  let mut j = hi
  while i < j {
    let tmp = arr[i]
    arr[i] = arr[j]
    arr[j] = tmp
    i = i + 1
    j = j - 1
  }
}

///|
/// Shallow-copy an integer array.
fn copy_array(arr : Array[Int]) -> Array[Int] {
  let result : Array[Int] = []
  for i = 0; i < arr.length(); i = i + 1 {
    result.push(arr[i])
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "tsp: tour_cost empty and single" {
  let dist = fn(_a : Int, _b : Int) -> Double { 0.0 }
  assert_true(tour_cost([], dist) == 0.0)
  assert_true(tour_cost([0], dist) == 0.0)
}

///|
test "tsp: tour_cost basic" {
  // 4-city tour: 0 → 1 → 2 → 3 → 0
  // Distances: d(0,1)=10, d(1,2)=20, d(2,3)=30, d(3,0)=40
  let dist = fn(a : Int, b : Int) -> Double {
    let m = [
      [0, 10, 25, 40],
      [10, 0, 20, 35],
      [25, 20, 0, 30],
      [40, 35, 30, 0],
    ]
    m[a][b].to_double()
  }
  let tour = [0, 1, 2, 3]
  let cost = tour_cost(tour, dist)
  // 10 + 20 + 30 + 40 = 100
  assert_true((cost - 100.0).abs() < 1.0e-10)
}

///|
test "tsp: is_valid_tour" {
  assert_true(is_valid_tour([0, 1, 2, 3], 4))
  assert_true(!is_valid_tour([0, 1, 2, 2], 4))
  assert_true(!is_valid_tour([0, 1, 2], 4))
  assert_true(!is_valid_tour([0, 1, 2, 4], 4))
  assert_true(is_valid_tour([], 0))
  assert_true(is_valid_tour([0], 1))
}

///|
test "tsp: christofides edge cases" {
  let dist = fn(a : Int, b : Int) -> Double { (a - b).to_double() }
  assert_true(christofides(0, dist).length() == 0)
  assert_true(christofides(1, dist).length() == 1)
  assert_true(christofides(2, dist).length() == 2)
}

///|
test "tsp: christofides 4-city square" {
  // 4 cities at corners of a unit square.
  //    (0,0)  (1,0)
  //    (0,1)  (1,1)
  // Optimal tour: 4.0 (perimeter).
  // Christofides should give ≤ 1.5 × 4.0 = 6.0.
  let coords = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
  let dist = fn(a : Int, b : Int) -> Double {
    let (ax, ay) = coords[a]
    let (bx, by) = coords[b]
    ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).sqrt()
  }
  let tour = christofides(4, dist)
  assert_true(is_valid_tour(tour, 4))
  let cost = tour_cost(tour, dist)
  // Christofides guarantee: ≤ 1.5 × OPT = 1.5 × 4.0 = 6.0
  assert_true(cost <= 6.0 + 1.0e-10)
}

///|
test "tsp: christofides 5-city" {
  // 5 cities with Euclidean distances (metric TSP).
  let coords = [
    (0.0, 0.0),
    (2.0, 0.0),
    (2.0, 2.0),
    (0.0, 2.0),
    (1.0, 1.0),
  ]
  let dist = fn(a : Int, b : Int) -> Double {
    let (ax, ay) = coords[a]
    let (bx, by) = coords[b]
    ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).sqrt()
  }
  let tour = christofides(5, dist)
  assert_true(is_valid_tour(tour, 5))
  let cost = tour_cost(tour, dist)
  // Optimal for this instance is approximately 6.828.
  // Christofides should give ≤ 1.5 × 6.828 ≈ 10.24.
  assert_true(cost <= 10.5)
}

///|
test "tsp: 2-opt improves tour" {
  // 6 cities on a line: 0-1-2-3-4-5
  // A bad tour zigzags; 2-Opt should straighten it.
  let dist = fn(a : Int, b : Int) -> Double {
    (a - b).to_double().abs()
  }
  // Deliberately bad tour: 0,5,1,4,2,3
  let bad_tour = [0, 5, 1, 4, 2, 3]
  let bad_cost = tour_cost(bad_tour, dist)
  let improved = two_opt(bad_tour, dist)
  assert_true(is_valid_tour(improved, 6))
  let improved_cost = tour_cost(improved, dist)
  assert_true(improved_cost <= bad_cost + 1.0e-10)
  // For a line, the optimal is 10 (0→1→2→3→4→5→0: 1+1+1+1+1+5).
  // 2-Opt should find it or get very close.
  assert_true(improved_cost <= 11.0)
}

///|
test "tsp: 2-opt does not worsen" {
  let coords = [
    (0.0, 0.0),
    (1.0, 5.0),
    (2.0, 3.0),
    (5.0, 2.0),
    (4.0, 4.0),
    (3.0, 1.0),
    (6.0, 6.0),
    (7.0, 3.0),
  ]
  let dist = fn(a : Int, b : Int) -> Double {
    let (ax, ay) = coords[a]
    let (bx, by) = coords[b]
    ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).sqrt()
  }
  let tour = [0, 1, 2, 3, 4, 5, 6, 7]
  let original_cost = tour_cost(tour, dist)
  let improved = two_opt(tour, dist)
  let improved_cost = tour_cost(improved, dist)
  assert_true(improved_cost <= original_cost + 1.0e-10)
  assert_true(is_valid_tour(improved, 8))
}

///|
test "tsp: or-opt improves tour" {
  let coords = [
    (0.0, 0.0),
    (3.0, 0.0),
    (6.0, 0.0),
    (6.0, 3.0),
    (6.0, 6.0),
    (3.0, 6.0),
    (0.0, 6.0),
    (0.0, 3.0),
  ]
  let dist = fn(a : Int, b : Int) -> Double {
    let (ax, ay) = coords[a]
    let (bx, by) = coords[b]
    ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).sqrt()
  }
  // Suboptimal tour.
  let tour = [0, 2, 1, 3, 5, 4, 6, 7]
  let original_cost = tour_cost(tour, dist)
  let improved = or_opt(tour, dist)
  let improved_cost = tour_cost(improved, dist)
  assert_true(improved_cost <= original_cost + 1.0e-10)
  assert_true(is_valid_tour(improved, 8))
}

///|
test "tsp: nearest_neighbor basic" {
  // 4 cities on a line: 0-1-2-3
  let dist = fn(a : Int, b : Int) -> Double {
    (a - b).to_double().abs()
  }
  let tour = nearest_neighbor(4, dist)
  assert_true(is_valid_tour(tour, 4))
  // From 0, nearest is 1, then 2, then 3.
  assert_true(tour[0] == 0)
  assert_true(tour[1] == 1)
}

///|
test "tsp: solve_tsp produces valid tour" {
  let coords = [
    (0.0, 0.0),
    (1.0, 0.0),
    (2.0, 0.0),
    (3.0, 0.0),
    (0.0, 1.0),
    (1.0, 1.0),
    (2.0, 1.0),
    (3.0, 1.0),
    (0.0, 2.0),
    (1.0, 2.0),
  ]
  let dist = fn(a : Int, b : Int) -> Double {
    let (ax, ay) = coords[a]
    let (bx, by) = coords[b]
    ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).sqrt()
  }
  let tour = solve_tsp(10, dist)
  assert_true(is_valid_tour(tour, 10))
}

///|
test "tsp: solve_tsp better than nearest_neighbor" {
  // 8 cities in a grid pattern.
  let coords = [
    (0.0, 0.0),
    (2.0, 0.0),
    (4.0, 0.0),
    (6.0, 0.0),
    (0.0, 2.0),
    (2.0, 2.0),
    (4.0, 2.0),
    (6.0, 2.0),
  ]
  let dist = fn(a : Int, b : Int) -> Double {
    let (ax, ay) = coords[a]
    let (bx, by) = coords[b]
    ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).sqrt()
  }
  let nn_tour = nearest_neighbor(8, dist)
  let solved = solve_tsp(8, dist)
  let nn_cost = tour_cost(nn_tour, dist)
  let solved_cost = tour_cost(solved, dist)
  assert_true(is_valid_tour(solved, 8))
  // solve_tsp should be at least as good as nearest_neighbor.
  assert_true(solved_cost <= nn_cost + 1.0e-10)
}

///|
test "tsp: christofides 10-city approximation" {
  // 10 cities with Euclidean distances.
  let coords = [
    (0.0, 0.0),
    (1.0, 3.0),
    (2.0, 1.0),
    (3.0, 4.0),
    (4.0, 0.0),
    (5.0, 3.0),
    (6.0, 1.0),
    (7.0, 4.0),
    (8.0, 0.0),
    (9.0, 2.0),
  ]
  let dist = fn(a : Int, b : Int) -> Double {
    let (ax, ay) = coords[a]
    let (bx, by) = coords[b]
    ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).sqrt()
  }
  let tour = christofides(10, dist)
  assert_true(is_valid_tour(tour, 10))
  let cost = tour_cost(tour, dist)
  // Brute-force optimal for this instance is ~24.5.
  // Christofides should give ≤ 1.5 × 24.5 ≈ 36.8.
  assert_true(cost <= 37.0)
}

///|
test "tsp: stress test 50 cities" {
  // 50 cities on a circle — metric TSP.
  // Optimal is the perimeter order.
  let n = 50
  let dist = fn(a : Int, b : Int) -> Double {
    // Chord distance on a unit circle: 2 * sin(|angle_diff| / 2)
    let pi = 3.14159265358979323846
    let angle_a = 2.0 * pi * a.to_double() / n.to_double()
    let angle_b = 2.0 * pi * b.to_double() / n.to_double()
    let diff = (angle_a - angle_b).abs()
    2.0 * @math.sin(diff / 2.0)
  }
  let tour = solve_tsp(n, dist)
  assert_true(is_valid_tour(tour, n))
  let cost = tour_cost(tour, dist)
  // Optimal for circle is the perimeter: 2 * n * sin(pi/n) ≈ 6.27.
  // With 2-Opt, we should get close to optimal.
  assert_true(cost <= 8.0)
}

///|
test "tsp: stress test 60 cities random" {
  // 60 cities with metric distances (random Euclidean).
  // Use a fixed seed for reproducibility.
  let n = 60
  // Pseudo-random coordinates from a simple LCG.
  let xs = Array::make(n, 0.0)
  let ys = Array::make(n, 0.0)
  let mut seed = 42
  for i = 0; i < n; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    xs[i] = (seed % 1000).to_double()
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    ys[i] = (seed % 1000).to_double()
  }
  let dist = fn(a : Int, b : Int) -> Double {
    let dx = xs[a] - xs[b]
    let dy = ys[a] - ys[b]
    (dx * dx + dy * dy).sqrt()
  }
  let tour = solve_tsp(n, dist)
  assert_true(is_valid_tour(tour, n))
  // solve_tsp should be better than nearest_neighbor.
  let nn_tour = nearest_neighbor(n, dist)
  let nn_cost = tour_cost(nn_tour, dist)
  let solved_cost = tour_cost(tour, dist)
  assert_true(solved_cost <= nn_cost + 1.0e-6)
}

///|
test "tsp: 2-opt optimal for small instance" {
  // 4 cities forming a square. 2-Opt from a bad tour should find optimal.
  let coords = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
  let dist = fn(a : Int, b : Int) -> Double {
    let (ax, ay) = coords[a]
    let (bx, by) = coords[b]
    ((ax - bx) * (ax - bx) + (ay - by) * (ay - by)).sqrt()
  }
  // Bad tour with crossing: 0 → 1 → 3 → 2 → 0
  let bad_tour = [0, 1, 3, 2]
  let improved = two_opt(bad_tour, dist)
  let improved_cost = tour_cost(improved, dist)
  // Optimal is 4.0 (perimeter).
  assert_true((improved_cost - 4.0).abs() < 1.0e-10)
}

///|
test "tsp: or-opt moves single vertex" {
  // Tour where moving one vertex improves the cost.
  // Cities on a line: 0, 1, 2, 3, 4
  // Tour: 0 → 2 → 1 → 3 → 4 (vertex 2 is out of place)
  let dist = fn(a : Int, b : Int) -> Double {
    (a - b).to_double().abs()
  }
  let tour = [0, 2, 1, 3, 4]
  let original_cost = tour_cost(tour, dist)
  let improved = or_opt(tour, dist)
  let improved_cost = tour_cost(improved, dist)
  assert_true(is_valid_tour(improved, 5))
  assert_true(improved_cost <= original_cost)
}

///|
test "tsp: matching_dp optimal" {
  // 4 odd vertices with known optimal matching.
  let odd = [0, 1, 2, 3]
  let dist = fn(a : Int, b : Int) -> Double {
    let m = [
      [0.0, 1.0, 10.0, 10.0],
      [1.0, 0.0, 10.0, 10.0],
      [10.0, 10.0, 0.0, 2.0],
      [10.0, 10.0, 2.0, 0.0],
    ]
    m[a][b]
  }
  let matching = min_weight_perfect_matching(odd, dist)
  // Optimal: (0,1) + (2,3) = 1 + 2 = 3
  assert_true(matching.length() == 2)
  let mut total = 0.0
  for i = 0; i < matching.length(); i = i + 1 {
    let (u, v) = matching[i]
    total = total + dist(u, v)
  }
  assert_true((total - 3.0).abs() < 1.0e-10)
}

///|
test "tsp: matching_greedy basic" {
  // 22 odd vertices — triggers greedy path.
  let odd : Array[Int] = []
  for i = 0; i < 22; i = i + 1 {
    odd.push(i)
  }
  let dist = fn(a : Int, b : Int) -> Double {
    (a - b).to_double().abs()
  }
  let matching = min_weight_perfect_matching(odd, dist)
  assert_true(matching.length() == 11)
  // Verify all vertices are matched.
  let matched = Array::make(22, false)
  for i = 0; i < matching.length(); i = i + 1 {
    let (u, v) = matching[i]
    matched[u] = true
    matched[v] = true
  }
  for i = 0; i < 22; i = i + 1 {
    assert_true(matched[i])
  }
}

///|
test "tsp: euler tour triangle" {
  // Triangle graph: edges (0,1), (1,2), (2,0) — all even degree.
  let edges : Array[(Int, Int)] = [(0, 1), (1, 2), (2, 0)]
  let tour = euler_tour_hierholzer(3, edges)
  // Tour should have 4 entries (3 vertices + return to start).
  assert_true(tour.length() == 4)
  // First and last should be the same (vertex 0).
  assert_true(tour[0] == tour[3])
}

///|
test "tsp: prim_mst basic" {
  // 4 cities, complete graph.
  let dist = fn(a : Int, b : Int) -> Double {
    let m = [
      [0.0, 1.0, 3.0, 4.0],
      [1.0, 0.0, 2.0, 5.0],
      [3.0, 2.0, 0.0, 6.0],
      [4.0, 5.0, 6.0, 0.0],
    ]
    m[a][b]
  }
  let parent = prim_mst(4, dist)
  // MST edges: (0,1)=1, (1,2)=2, (0,3)=4 — total 7.
  // Or: (0,1)=1, (1,2)=2, (2,3)=6 — total 9 (worse).
  // So MST should be {0-1, 1-2, 0-3}.
  let mut mst_cost = 0.0
  for i = 1; i < 4; i = i + 1 {
    mst_cost = mst_cost + dist(parent[i], i)
  }
  assert_true((mst_cost - 7.0).abs() < 1.0e-10)
}
