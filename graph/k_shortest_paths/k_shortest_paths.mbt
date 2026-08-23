/// K-Shortest Paths (Yen's Algorithm) — find K shortest simple paths.
///
/// Yen's algorithm finds the K shortest loopless paths in a weighted
/// directed graph with non-negative edge weights. Uses Dijkstra as
/// a subroutine to find shortest paths after removing deviation nodes.
///
/// ## Complexity
/// - Time:  O(K × V × (E + V log V)).
/// - Space: O(K × V).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Edge representation.
pub struct KEdge {
  to : Int
  weight : Int
}

///|
/// Construct a [`KEdge`] with the given destination and weight.
pub fn k_edge(to : Int, weight : Int) -> KEdge {
  { to, weight }
}

///|
/// Find the K shortest paths from `source` to `target`.
/// Returns a list of (total_cost, path) pairs, sorted by cost.
pub fn k_shortest_paths(
  n : Int,
  adj : Array[Array[KEdge]],
  source : Int,
  target : Int,
  k : Int,
) -> Array[(Int, Array[Int])] {
  if k <= 0 || n == 0 {
    return []
  }
  // Find the shortest path (1st).
  let first = dijkstra_path(n, adj, source, target)
  match first {
    None => return []
    Some((cost, path)) => {
      let results : Array[(Int, Array[Int])] = [(cost, path)]
      let candidates : Array[(Int, Array[Int])] = []
      for ki = 1; ki < k; ki = ki + 1 {
        let prev_path = results[ki - 1].1
        // For each node on the previous path (except the last).
        for i = 0; i < prev_path.length() - 1; i = i + 1 {
          let spur_node = prev_path[i]
          // Root path = prev_path[0..i].
          let root_path : Array[Int] = []
          for j = 0; j <= i; j = j + 1 {
            root_path.push(prev_path[j])
          }
          let root_cost = path_cost(adj, root_path)
          // Remove edges that match root_path.
          let removed_edges : Array[(Int, Int)] = []
          for r = 0; r < results.length(); r = r + 1 {
            let p = results[r].1
            if p.length() > i && paths_prefix_equal(p, root_path, i) {
              removed_edges.push((p[i], p[i + 1]))
            }
          }
          // Also remove root path nodes from the graph (except spur_node).
          let removed_nodes : Array[Int] = []
          for j = 0; j < root_path.length() - 1; j = j + 1 {
            removed_nodes.push(root_path[j])
          }
          // Create filtered adjacency list.
          let spur_adj : Array[Array[KEdge]] = []
          for node = 0; node < n; node = node + 1 {
            let edges : Array[KEdge] = []
            if !removed_nodes.contains(node) {
              for e = 0; e < adj[node].length(); e = e + 1 {
                let edge = adj[node][e]
                if !removed_nodes.contains(edge.to) &&
                  !removed_edges.contains((node, edge.to)) {
                  edges.push(edge)
                }
              }
            }
            spur_adj.push(edges)
          }
          // Find spur path.
          match dijkstra_path(n, spur_adj, spur_node, target) {
            Some((spur_cost, spur_path)) => {
              let total_path = concat_paths(root_path, spur_path)
              let total_cost = root_cost + spur_cost
              // Check if candidate already exists.
              if !candidate_exists(candidates, total_cost, total_path) {
                candidates.push((total_cost, total_path))
              }
            }
            None => ()
          }
        }
        if candidates.length() == 0 {
          break
        }
        // Sort candidates by cost and pick the smallest.
        candidates.sort_by(fn(a, b) { a.0 - b.0 })
        results.push(candidates[0])
        candidates.remove(0) |> ignore
      }
      results
    }
  }
}

///|
/// Check if `path[0..i]` equals `root_path[0..i+1]`.
fn paths_prefix_equal(
  path : Array[Int],
  root_path : Array[Int],
  i : Int,
) -> Bool {
  for j = 0; j <= i; j = j + 1 {
    if path[j] != root_path[j] {
      return false
    }
  }
  true
}

///|
/// Check if a candidate (cost, path) already exists in the list.
fn candidate_exists(
  candidates : Array[(Int, Array[Int])],
  cost : Int,
  path : Array[Int],
) -> Bool {
  for c = 0; c < candidates.length(); c = c + 1 {
    if candidates[c].0 == cost && paths_equal(candidates[c].1, path) {
      return true
    }
  }
  false
}

///|
fn dijkstra_path(
  n : Int,
  adj : Array[Array[KEdge]],
  source : Int,
  target : Int,
) -> (Int, Array[Int])? {
  let dist = FixedArray::make(n, 0x7FFFFFFF)
  let prev = FixedArray::make(n, -1)
  let visited = FixedArray::make(n, false)
  dist[source] = 0
  for _ in 0..<n {
    let mut u = -1
    let mut min_d = 0x7FFFFFFF
    for i = 0; i < n; i = i + 1 {
      if !visited[i] && dist[i] < min_d {
        min_d = dist[i]
        u = i
      }
    }
    if u == -1 {
      break
    }
    visited[u] = true
    if u == target {
      break
    }
    for e = 0; e < adj[u].length(); e = e + 1 {
      let edge = adj[u][e]
      if !visited[edge.to] && dist[u] + edge.weight < dist[edge.to] {
        dist[edge.to] = dist[u] + edge.weight
        prev[edge.to] = u
      }
    }
  }
  if dist[target] == 0x7FFFFFFF {
    return None
  }
  // Reconstruct path by reversing.
  let path : Array[Int] = []
  let mut node = target
  while node != -1 {
    path.push(node)
    node = prev[node]
  }
  // Manual reverse (Array.reverse may not be available).
  let result : Array[Int] = []
  for i = path.length() - 1; i >= 0; i = i - 1 {
    result.push(path[i])
  }
  Some((dist[target], result))
}

///|
fn path_cost(adj : Array[Array[KEdge]], path : Array[Int]) -> Int {
  let mut cost = 0
  for i = 0; i < path.length() - 1; i = i + 1 {
    let u = path[i]
    let v = path[i + 1]
    for e = 0; e < adj[u].length(); e = e + 1 {
      if adj[u][e].to == v {
        cost = cost + adj[u][e].weight
        break
      }
    }
  }
  cost
}

///|
fn concat_paths(root : Array[Int], spur : Array[Int]) -> Array[Int] {
  let result : Array[Int] = []
  for i = 0; i < root.length() - 1; i = i + 1 {
    result.push(root[i])
  }
  for i = 0; i < spur.length(); i = i + 1 {
    result.push(spur[i])
  }
  result
}

///|
fn paths_equal(a : Array[Int], b : Array[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "k_shortest_paths: basic" {
  // Graph: 0->1 (1), 0->2 (2), 1->3 (2), 2->3 (1), 0->3 (10)
  let adj : Array[Array[KEdge]] = [
    [{ to: 1, weight: 1 }, { to: 2, weight: 2 }, { to: 3, weight: 10 }],
    [{ to: 3, weight: 2 }],
    [{ to: 3, weight: 1 }],
    [],
  ]
  let paths = k_shortest_paths(4, adj, 0, 3, 3)
  assert_eq(paths.length(), 3)
  // Shortest: 0->2->3 (3), 2nd: 0->1->3 (3), 3rd: 0->3 (10)
  assert_eq(paths[0].0, 3)
  assert_eq(paths[1].0, 3)
  assert_eq(paths[2].0, 10)
}

///|
test "k_shortest_paths: single path" {
  let adj : Array[Array[KEdge]] = [[{ to: 1, weight: 5 }], []]
  let paths = k_shortest_paths(2, adj, 0, 1, 3)
  assert_eq(paths.length(), 1)
  assert_eq(paths[0].0, 5)
}

///|
test "k_shortest_paths: no path" {
  let adj : Array[Array[KEdge]] = [[], []]
  let paths = k_shortest_paths(2, adj, 0, 1, 1)
  assert_eq(paths.length(), 0)
}

///|
test "k_shortest_paths: multiple equal-weight paths" {
  // Diamond: 0→1→3 and 0→2→3, both weight 2
  let adj : Array[Array[KEdge]] = [
    [k_edge(1, 1), k_edge(2, 1)],
    [k_edge(3, 1)],
    [k_edge(3, 1)],
    [],
  ]
  let paths = k_shortest_paths(4, adj, 0, 3, 2)
  assert_eq(paths.length(), 2)
  assert_eq(paths[0].0, 2)
  assert_eq(paths[1].0, 2)
}

///|
test "k_shortest_paths: k larger than available paths" {
  let adj : Array[Array[KEdge]] = [[k_edge(1, 5)], [k_edge(2, 3)], []]
  let paths = k_shortest_paths(3, adj, 0, 2, 10)
  assert_true(paths.length() <= 10)
  assert_true(paths.length() >= 1)
  assert_eq(paths[0].0, 8)
}

///|
test "k_shortest_paths: self-loop source" {
  let adj : Array[Array[KEdge]] = [[k_edge(0, 1), k_edge(1, 5)], []]
  let paths = k_shortest_paths(2, adj, 0, 1, 1)
  assert_eq(paths.length(), 1)
  assert_eq(paths[0].0, 5)
}
