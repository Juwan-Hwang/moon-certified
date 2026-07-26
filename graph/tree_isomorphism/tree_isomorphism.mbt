/// Tree Isomorphism — check if two unrooted trees are isomorphic.
///
/// Uses the AHU (Aho, Hopcroft, Ullman) algorithm: assign canonical
/// labels to tree nodes via bottom-up sorting of child labels. Two
/// trees are isomorphic iff their canonical forms match.
///
/// ## Complexity
/// - Time:  O(n log n) due to sorting child labels.
/// - Space: O(n).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// Check if two unrooted trees (given as edge lists) are isomorphic.
/// `n` is the number of nodes (0 to n-1).
pub fn are_trees_isomorphic(
  n : Int,
  edges1 : Array[(Int, Int)],
  edges2 : Array[(Int, Int)],
) -> Bool {
  if n <= 1 {
    return edges1.length() == edges2.length()
  }
  // Quick check: trees must have the same number of edges.
  if edges1.length() != edges2.length() {
    return false
  }
  // Validate that all node references are within [0, n).
  for i = 0; i < edges1.length(); i = i + 1 {
    let (u, v) = edges1[i]
    if u < 0 || u >= n || v < 0 || v >= n {
      return false
    }
  }
  for i = 0; i < edges2.length(); i = i + 1 {
    let (u, v) = edges2[i]
    if u < 0 || u >= n || v < 0 || v >= n {
      return false
    }
  }
  let adj1 = build_adj(n, edges1)
  let adj2 = build_adj(n, edges2)
  let center1 = find_centers(n, adj1)
  let center2 = find_centers(n, adj2)
  if center1.length() != center2.length() {
    return false
  }
  // Try rooting at each center.
  for i = 0; i < center1.length(); i = i + 1 {
    let label1 = root_tree(n, adj1, center1[i])
    for j = 0; j < center2.length(); j = j + 1 {
      let label2 = root_tree(n, adj2, center2[j])
      if label1 == label2 {
        return true
      }
    }
  }
  false
}

fn build_adj(n : Int, edges : Array[(Int, Int)]) -> Array[Array[Int]] {
  let adj : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    adj.push([])
  }
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v) = edges[i]
    adj[u].push(v)
    adj[v].push(u)
  }
  adj
}

/// Find tree centers using the leaf-removal (topological sort) method.
fn find_centers(n : Int, adj : Array[Array[Int]]) -> Array[Int] {
  if n == 0 {
    return []
  }
  if n == 1 {
    return [0]
  }
  let degree = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    degree[i] = adj[i].length()
  }
  let leaves : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    if degree[i] <= 1 {
      leaves.push(i)
    }
  }
  let mut remaining = n
  while remaining > 2 {
    let new_leaves : Array[Int] = []
    for i = 0; i < leaves.length(); i = i + 1 {
      let leaf = leaves[i]
      degree[leaf] = 0
      remaining = remaining - 1
    }
    for i = 0; i < leaves.length(); i = i + 1 {
      let leaf = leaves[i]
      for j = 0; j < adj[leaf].length(); j = j + 1 {
        let neighbor = adj[leaf][j]
        if degree[neighbor] > 0 {
          degree[neighbor] = degree[neighbor] - 1
          if degree[neighbor] == 1 {
            new_leaves.push(neighbor)
          }
        }
      }
    }
    if new_leaves.length() == 0 {
      break
    }
    leaves.clear()
    for i = 0; i < new_leaves.length(); i = i + 1 {
      leaves.push(new_leaves[i])
    }
  }
  let centers : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    if degree[i] > 0 {
      centers.push(i)
    }
  }
  if centers.length() == 0 {
    for i = 0; i < leaves.length(); i = i + 1 {
      centers.push(leaves[i])
    }
  }
  centers
}

/// Root the tree at `root` and compute canonical labels.
fn root_tree(n : Int, adj : Array[Array[Int]], root : Int) -> String {
  let labels = FixedArray::make(n, "")
  let visited = FixedArray::make(n, false)
  dfs_label(root, adj, visited, labels)
  labels[root]
}

fn dfs_label(
  node : Int,
  adj : Array[Array[Int]],
  visited : FixedArray[Bool],
  labels : FixedArray[String],
) -> Unit {
  visited[node] = true
  let child_labels : Array[String] = []
  for i = 0; i < adj[node].length(); i = i + 1 {
    let neighbor = adj[node][i]
    if !visited[neighbor] {
      dfs_label(neighbor, adj, visited, labels)
      child_labels.push(labels[neighbor])
    }
  }
  child_labels.sort()
  let mut label = "("
  for i = 0; i < child_labels.length(); i = i + 1 {
    label = label + child_labels[i]
  }
  label = label + ")"
  labels[node] = label
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "tree_isomorphism: identical trees" {
  let edges = [(0, 1), (0, 2), (0, 3)]
  assert_true(are_trees_isomorphic(4, edges, edges))
}

test "tree_isomorphism: star vs path" {
  let star = [(0, 1), (0, 2), (0, 3)]
  let path = [(0, 1), (1, 2), (2, 3)]
  assert_false(are_trees_isomorphic(4, star, path))
}

test "tree_isomorphism: relabeled isomorphic" {
  let t1 = [(0, 1), (1, 2), (2, 3)]
  let t2 = [(3, 2), (2, 1), (1, 0)]
  assert_true(are_trees_isomorphic(4, t1, t2))
}

test "tree_isomorphism: different sizes" {
  let t1 = [(0, 1), (0, 2)]
  let t2 = [(0, 1), (1, 2), (2, 3)]
  assert_false(are_trees_isomorphic(3, t1, t2))
}

test "tree_isomorphism: single node" {
  let edges : Array[(Int, Int)] = []
  assert_true(are_trees_isomorphic(1, edges, edges))
}

test "tree_isomorphism: complex isomorphic" {
  let t1 = [(0, 1), (1, 2), (2, 3), (1, 4), (2, 5)]
  let t2 = [(3, 2), (2, 1), (1, 0), (2, 5), (1, 4)]
  assert_true(are_trees_isomorphic(6, t1, t2))
}
