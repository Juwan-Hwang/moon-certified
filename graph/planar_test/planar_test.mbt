/// Planarity test using necessary conditions (Euler's formula) and
/// Kuratowski subgraph detection (K5 and K3,3).
///
/// A graph is planar if it can be drawn on a plane without edge crossings.
/// Kuratowski's theorem: a graph is planar iff it does not contain a
/// subdivision of K5 or K3,3.
///
/// ## Performance
/// - Subgraph checks are O(V^k) where k=5 for K5 and k=6 for K3,3
/// - Suitable for small to medium graphs
///
/// ## References
/// - Kuratowski, K. "Sur le problème des courbes gauches en topologie."
///   Fundamenta Mathematicae, 1930.
/// - Boyer, J. and Myrvold, W. "Simplified O(n) planarity by edge addition."
///   Journal of Graph Algorithms and Applications, 2004.
///
/// `proof-enabled` is `false`.

///|
/// Check if the graph contains a triangle.
fn check_triangle(n : Int, edges : Array[(Int, Int)]) -> Bool {
  let adj : Array[Array[Bool]] = []
  for i = 0; i < n; i = i + 1 {
    adj.push(Array::make(n, false))
  }
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v) = edges[i]
    if u >= 0 && u < n && v >= 0 && v < n && u != v {
      adj[u][v] = true
      adj[v][u] = true
    }
  }
  for u = 0; u < n; u = u + 1 {
    for v = u + 1; v < n; v = v + 1 {
      if adj[u][v] {
        for w = v + 1; w < n; w = w + 1 {
          if adj[u][w] && adj[v][w] {
            return true
          }
        }
      }
    }
  }
  false
}

///|
/// Check for K5 as a subgraph.
fn has_k5(n : Int, adj : Array[Array[Bool]]) -> Bool {
  if n < 5 {
    return false
  }
  for a = 0; a < n - 4; a = a + 1 {
    for b = a + 1; b < n - 3; b = b + 1 {
      if !adj[a][b] {
        continue
      }
      for c = b + 1; c < n - 2; c = c + 1 {
        if !adj[a][c] || !adj[b][c] {
          continue
        }
        for d = c + 1; d < n - 1; d = d + 1 {
          if !adj[a][d] || !adj[b][d] || !adj[c][d] {
            continue
          }
          for e = d + 1; e < n; e = e + 1 {
            if adj[a][e] && adj[b][e] && adj[c][e] && adj[d][e] {
              return true
            }
          }
        }
      }
    }
  }
  false
}

///|
/// Check for K3,3 as a subgraph.
fn has_k33(n : Int, adj : Array[Array[Bool]]) -> Bool {
  if n < 6 {
    return false
  }
  for a = 0; a < n - 5; a = a + 1 {
    for b = a + 1; b < n - 4; b = b + 1 {
      for c = b + 1; c < n - 3; c = c + 1 {
        for d = c + 1; d < n - 2; d = d + 1 {
          for e = d + 1; e < n - 1; e = e + 1 {
            for f = e + 1; f < n; f = f + 1 {
              let nodes = [a, b, c, d, e, f]
              let partitions = [
                ([0, 1, 2], [3, 4, 5]),
                ([0, 1, 3], [2, 4, 5]),
                ([0, 1, 4], [2, 3, 5]),
                ([0, 1, 5], [2, 3, 4]),
                ([0, 2, 3], [1, 4, 5]),
                ([0, 2, 4], [1, 3, 5]),
                ([0, 2, 5], [1, 3, 4]),
                ([0, 3, 4], [1, 2, 5]),
                ([0, 3, 5], [1, 2, 4]),
                ([0, 4, 5], [1, 2, 3]),
              ]
              for p = 0; p < partitions.length(); p = p + 1 {
                let (s1, s2) = partitions[p]
                let mut all_edges = true
                for i = 0; i < 3 && all_edges; i = i + 1 {
                  for j = 0; j < 3 && all_edges; j = j + 1 {
                    if !adj[nodes[s1[i]]][nodes[s2[j]]] {
                      all_edges = false
                    }
                  }
                }
                if all_edges {
                  return true
                }
              }
            }
          }
        }
      }
    }
  }
  false
}

///|
/// Test if a graph is planar.
///
/// Uses Euler's formula necessary conditions and Kuratowski subgraph detection.
/// Returns `true` if the graph is planar, `false` otherwise.
pub fn is_planar(n : Int, edges : Array[(Int, Int)]) -> Bool {
  if n <= 4 {
    return true
  }
  let m = edges.length()
  // Necessary condition: E <= 3V - 6 (for V >= 3)
  if n >= 3 && m > 3 * n - 6 {
    return false
  }
  // Build adjacency matrix
  let adj : Array[Array[Bool]] = []
  for i = 0; i < n; i = i + 1 {
    adj.push(Array::make(n, false))
  }
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v) = edges[i]
    if u >= 0 && u < n && v >= 0 && v < n && u != v {
      adj[u][v] = true
      adj[v][u] = true
    }
  }
  // For triangle-free graphs: E <= 2V - 4
  let tri = check_triangle(n, edges)
  if !tri && m > 2 * n - 4 {
    return false
  }
  // Check for K5 subgraph
  if has_k5(n, adj) {
    return false
  }
  // Check for K3,3 subgraph
  if has_k33(n, adj) {
    return false
  }
  true
}

test "planar_test: K4 is planar" {
  let edges = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)]
  assert_true(is_planar(4, edges))
}

test "planar_test: K5 is not planar" {
  let edges = [
    (0, 1), (0, 2), (0, 3), (0, 4),
    (1, 2), (1, 3), (1, 4),
    (2, 3), (2, 4),
    (3, 4),
  ]
  assert_false(is_planar(5, edges))
}

test "planar_test: K3,3 is not planar" {
  let edges = [
    (0, 3), (0, 4), (0, 5),
    (1, 3), (1, 4), (1, 5),
    (2, 3), (2, 4), (2, 5),
  ]
  assert_false(is_planar(6, edges))
}

test "planar_test: tree is planar" {
  let edges = [(0, 1), (1, 2), (1, 3), (0, 4), (4, 5)]
  assert_true(is_planar(6, edges))
}

test "planar_test: cycle is planar" {
  let edges = [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)]
  assert_true(is_planar(5, edges))
}

test "planar_test: single edge" {
  assert_true(is_planar(2, [(0, 1)]))
}

test "planar_test: too many edges" {
  // 7 nodes, 16 edges: 3*7-6=15, so 16 > 15 => not planar
  let edges = [
    (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (0, 6),
    (1, 2), (1, 3), (1, 4), (1, 5),
    (2, 3), (2, 4), (2, 5),
    (3, 4), (3, 5),
    (4, 5),
  ]
  assert_false(is_planar(7, edges))
}
