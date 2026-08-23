/// Weiner's Algorithm — All-Pairs Shortest Path via BFS
///
/// Computes the all-pairs shortest path matrix on an unweighted graph
/// by running BFS from every vertex. For sparse graphs with n nodes and
/// m edges, the total time is O(n·(n+m)).
///
/// ## References
/// - Weiner, "All shortest routes in a graph." 1975.
///
/// `proof-enabled` is `false`.

///|
/// Compute all-pairs shortest path distances using repeated BFS.
///
/// ## Parameters
/// - `adj`: adjacency list (adj[i] = list of neighbor indices)
/// - `n`: number of vertices
///
/// ## Returns
/// dist[i][j] = shortest path distance from i to j (or -1 if unreachable)
pub fn weiner_all_pairs_shortest_path(
  adj : Array[Array[Int]],
  n : Int,
) -> Array[Array[Int]] {
  let dist : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    dist.push(Array::make(n, -1))
  }
  for src = 0; src < n; src = src + 1 {
    // BFS from src
    let queue : Array[Int] = []
    let visited = Array::make(n, false)
    visited[src] = true
    dist[src][src] = 0
    queue.push(src)
    let mut head = 0
    while head < queue.length() {
      let u = queue[head]
      head = head + 1
      if u < adj.length() {
        for v in adj[u] {
          if v >= 0 && v < n && !(visited[v]) {
            visited[v] = true
            dist[src][v] = dist[src][u] + 1
            queue.push(v)
          }
        }
      }
    }
  }
  dist
}

///|
/// Compute the diameter (longest shortest path) of the graph.
pub fn graph_diameter(adj : Array[Array[Int]], n : Int) -> Int {
  let dist = weiner_all_pairs_shortest_path(adj, n)
  let mut max_dist = 0
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if dist[i][j] > max_dist {
        max_dist = dist[i][j]
      }
    }
  }
  max_dist
}

///|
/// Compute the average shortest path length.
pub fn average_path_length(adj : Array[Array[Int]], n : Int) -> Double {
  let dist = weiner_all_pairs_shortest_path(adj, n)
  let mut sum = 0
  let mut count = 0
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j && dist[i][j] >= 0 {
        sum = sum + dist[i][j]
        count = count + 1
      }
    }
  }
  if count == 0 {
    0.0
  } else {
    sum.to_double() / count.to_double()
  }
}
