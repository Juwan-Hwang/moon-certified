/// Parallel BFS — Level-Synchronous Breadth-First Search
///
/// Parallel BFS partitions frontier vertices across worker "threads"
/// (simulated via sequential processing of partitions) to enable
/// concurrent edge relaxation.
///
/// ## Design
/// This is a level-synchronous BFS where each level of the BFS tree is
/// processed in "parallel" (here: sequentially but with partition structure
/// to demonstrate the algorithm's data access pattern).
///
/// ## References
/// - Beamer, Asanovic, Patterson. "Direction-Optimizing BFS." SC 2012.
///
/// `proof-enabled` is `false`.

///|
/// Parallel BFS result.
pub struct ParallelBfsResult {
  /// Distance from source for each vertex (-1 if unreachable)
  dist : Array[Int]
  /// Parent of each vertex (-1 if no parent)
  parent : Array[Int]
  /// Number of vertices reached
  visited : Int
  /// Number of levels (eccentricity of source)
  levels : Int
}

///|
/// Run level-synchronous BFS from a source vertex.
///
/// ## Parameters
/// - `adj`: adjacency list
/// - `n`: number of vertices
/// - `source`: source vertex index
/// - `n_workers`: number of "parallel" workers (affects frontier partition)
pub fn parallel_bfs(
  adj : Array[Array[Int]],
  n : Int,
  source : Int,
  n_workers : Int,
) -> ParallelBfsResult {
  let dist = Array::make(n, -1)
  let parent = Array::make(n, -1)
  if source < 0 || source >= n {
    return { dist, parent, visited: 0, levels: 0, }
  }
  dist[source] = 0
  let mut frontier : Array[Int] = [source]
  let mut visited = 1
  let mut levels = 0
  while frontier.length() > 0 {
    levels = levels + 1
    // Partition frontier among workers
    let mut chunk_size = (frontier.length() + n_workers - 1) / n_workers
    if chunk_size < 1 {
      chunk_size = 1
    }
    let next_frontier : Array[Int] = []
    for w = 0; w < n_workers; w = w + 1 {
      let start = w * chunk_size
      let end = if start + chunk_size < frontier.length() {
        start + chunk_size
      } else {
        frontier.length()
      }
      // Process this worker's portion
      for i = start; i < end; i = i + 1 {
        let u = frontier[i]
        if u >= 0 && u < adj.length() {
          for v in adj[u] {
            if v >= 0 && v < n && dist[v] == -1 {
              dist[v] = dist[u] + 1
              parent[v] = u
              next_frontier.push(v)
              visited = visited + 1
            }
          }
        }
      }
    }
    frontier = next_frontier
  }
  { dist, parent, visited, levels, }
}

///|
/// Compute connected components using repeated BFS.
pub fn parallel_connected_components(
  adj : Array[Array[Int]],
  n : Int,
  n_workers : Int,
) -> Array[Int] {
  let component = Array::make(n, -1)
  let mut comp_id = 0
  for src = 0; src < n; src = src + 1 {
    if component[src] == -1 {
      let result = parallel_bfs(adj, n, src, n_workers)
      for i = 0; i < n; i = i + 1 {
        if result.dist[i] >= 0 {
          component[i] = comp_id
        }
      }
      comp_id = comp_id + 1
    }
  }
  component
}

///|
/// Count the number of connected components.
pub fn count_components(
  adj : Array[Array[Int]],
  n : Int,
  n_workers : Int,
) -> Int {
  let comp = parallel_connected_components(adj, n, n_workers)
  let mut max_comp = -1
  for c in comp {
    if c > max_comp {
      max_comp = c
    }
  }
  max_comp + 1
}
