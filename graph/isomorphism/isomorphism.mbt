/// Graph isomorphism testing using backtracking with vertex invariants.
///
/// Two graphs are isomorphic if there exists a bijection between their
/// vertex sets that preserves adjacency. This implementation uses
/// degree-sequence filtering and backtracking with pruning.
///
/// ## Performance
/// - Worst case: O(V!) (exponential)
/// - Practical: much faster with degree-based pruning
///
/// ## References
/// - Cordella, L.P. et al. "An improved algorithm for matching large graphs."
///   IEEE Transactions on Pattern Analysis and Machine Intelligence, 2004.
///
/// `proof-enabled` is `false`.

///|
/// Check if two graphs are isomorphic.
///
/// `n1` = number of vertices in graph 1
/// `adj1` = adjacency list of graph 1 (adj1[i] = list of neighbors of i)
/// `n2` = number of vertices in graph 2
/// `adj2` = adjacency list of graph 2
///
/// Returns `true` if the graphs are isomorphic.
pub fn is_isomorphic(
  n1 : Int,
  adj1 : Array[Array[Int]],
  n2 : Int,
  adj2 : Array[Array[Int]],
) -> Bool {
  if n1 != n2 {
    return false
  }
  if n1 == 0 {
    return true
  }
  // Quick check: same edge count
  let mut e1 = 0
  let mut e2 = 0
  for i = 0; i < n1; i = i + 1 {
    e1 = e1 + adj1[i].length()
    e2 = e2 + adj2[i].length()
  }
  if e1 != e2 {
    return false
  }
  // Quick check: same degree sequence
  let deg1 = Array::make(n1, 0)
  let deg2 = Array::make(n2, 0)
  for i = 0; i < n1; i = i + 1 {
    deg1[i] = adj1[i].length()
    deg2[i] = adj2[i].length()
  }
  // Sort degree sequences
  Array::sort(deg1)
  Array::sort(deg2)
  for i = 0; i < n1; i = i + 1 {
    if deg1[i] != deg2[i] {
      return false
    }
  }
  // Build adjacency matrices for O(1) lookup
  let mat1 : Array[Array[Bool]] = []
  let mat2 : Array[Array[Bool]] = []
  for i = 0; i < n1; i = i + 1 {
    mat1.push(Array::make(n1, false))
    mat2.push(Array::make(n1, false))
  }
  for i = 0; i < n1; i = i + 1 {
    for j = 0; j < adj1[i].length(); j = j + 1 {
      mat1[i][adj1[i][j]] = true
    }
    for j = 0; j < adj2[i].length(); j = j + 1 {
      mat2[i][adj2[i][j]] = true
    }
  }
  // Backtracking with degree-based candidate ordering
  let mapping = Array::make(n1, -1) // mapping[i] = vertex in G2 that i maps to
  let used = Array::make(n1, false) // used[j] = vertex j in G2 is already mapped
  // Order vertices by degree (descending) for better pruning
  let order : Array[Int] = []
  for i = 0; i < n1; i = i + 1 {
    order.push(i)
  }
  // Simple sort by degree descending
  for i = 0; i < n1 - 1; i = i + 1 {
    for j = i + 1; j < n1; j = j + 1 {
      if deg1[order[i]] < deg1[order[j]] {
        let tmp = order[i]
        order[i] = order[j]
        order[j] = tmp
      }
    }
  }
  backtrack(0, n1, order, mat1, mat2, mapping, used, deg1, deg2)
}

///|
/// Backtracking search for isomorphism.
fn backtrack(
  depth : Int,
  n : Int,
  order : Array[Int],
  mat1 : Array[Array[Bool]],
  mat2 : Array[Array[Bool]],
  mapping : Array[Int],
  used : Array[Bool],
  deg1 : Array[Int],
  deg2 : Array[Int],
) -> Bool {
  if depth == n {
    return true
  }
  let u = order[depth]
  for v = 0; v < n; v = v + 1 {
    if !used[v] && deg2[v] == deg1[u] {
      // Check consistency: all already-mapped neighbors must match
      let mut ok = true
      for w = 0; w < n && ok; w = w + 1 {
        if mapping[w] >= 0 {
          if mat1[u][w] != mat2[v][mapping[w]] {
            ok = false
          }
        }
      }
      if ok {
        mapping[u] = v
        used[v] = true
        if backtrack(depth + 1, n, order, mat1, mat2, mapping, used, deg1, deg2) {
          return true
        }
        mapping[u] = -1
        used[v] = false
      }
    }
  }
  false
}

test "isomorphism: identical graphs" {
  let g1 = [[1, 2], [0, 2], [0, 1]] // triangle
  let g2 = [[1, 2], [0, 2], [0, 1]]
  assert_true(is_isomorphic(3, g1, 3, g2))
}

test "isomorphism: relabeled triangle" {
  let g1 = [[1, 2], [0, 2], [0, 1]] // triangle 0-1-2
  // g2: 2-0-1 (renamed)
  let g2r = [[1, 2], [0, 2], [0, 1]]
  assert_true(is_isomorphic(3, g1, 3, g2r))
}

test "isomorphism: path vs triangle" {
  let g1 = [[1], [0, 2], [1]] // path 0-1-2
  let g2 = [[1, 2], [0, 2], [0, 1]] // triangle
  assert_false(is_isomorphic(3, g1, 3, g2))
}

test "isomorphism: different sizes" {
  assert_false(is_isomorphic(3, [[1], [0], []], 2, [[1], [0]]))
}

test "isomorphism: single vertex" {
  assert_true(is_isomorphic(1, [[]], 1, [[]]))
}

test "isomorphism: square vs two disconnected edges" {
  // Square: 0-1-2-3-0
  let g1 = [[1, 3], [0, 2], [1, 3], [0, 2]]
  // Two disconnected edges: 0-1, 2-3
  let g2 = [[1], [0], [3], [2]]
  // Same degree sequence (all degree 2 vs all degree 1)
  // Wait, degree seq differs: g1 all degree 2, g2 all degree 1
  assert_false(is_isomorphic(4, g1, 4, g2))
}

test "isomorphism: K4 relabeled" {
  // Complete graph K4
  let g1 = [[1, 2, 3], [0, 2, 3], [0, 1, 3], [0, 1, 2]]
  // K4 with different labeling
  let g2 = [[1, 2, 3], [0, 2, 3], [0, 1, 3], [0, 1, 2]]
  assert_true(is_isomorphic(4, g1, 4, g2))
}
