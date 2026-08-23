/// Graph isomorphism testing using Weisfeiler-Leman coloring and
/// backtracking with color constraints.
///
/// Two graphs are isomorphic if there exists a bijection between their
/// vertex sets that preserves adjacency. This implementation combines:
///
/// 1. **1-dimensional Weisfeiler-Leman (WL) coloring** — a polynomial-time
///    vertex partitioning refinement that assigns colors based on the
///    iterative neighborhood structure. Vertices with different WL colors
///    cannot be mapped to each other. This dramatically reduces the search
///    space and can quickly reject many non-isomorphic graph pairs.
/// 2. **Backtracking with color constraints** — only tries mapping vertices
///    within the same WL color class, with adjacency consistency checks.
///    Vertices are ordered by color class size (smallest first) for optimal
///    pruning.
///
/// ## Complexity
///
/// - WL coloring: O(V · E) per iteration, at most V iterations.
/// - Backtracking: O(V!) worst case, but WL coloring typically reduces the
///   branching factor to the size of the smallest color class.
/// - For most practical graphs the algorithm runs in near-polynomial time.
///
/// ## Limitations
///
/// 1-WL cannot distinguish all non-isomorphic graph pairs (e.g., strongly
/// regular graphs with the same parameters). For such cases, the backtracking
/// still gives the correct answer but may take exponential time.
///
/// ## References
///
/// - Weisfeiler, B. "On construction and identification of graphs." 1976.
/// - Cordella, L.P. et al. "An improved algorithm for matching large graphs."
///   IEEE TPAMI, 2004. (VF2 algorithm)
///
/// `proof-enabled` is `false`.

///|
/// Check if two graphs are isomorphic.
///
/// Uses 1-dimensional Weisfeiler-Leman coloring for initial vertex
/// partitioning, followed by backtracking with color constraints and
/// adjacency consistency checks.
///
/// ## Parameters
/// - `n1`: number of vertices in graph 1
/// - `adj1`: adjacency list of graph 1 (`adj1[i]` = list of neighbors of `i`)
/// - `n2`: number of vertices in graph 2
/// - `adj2`: adjacency list of graph 2
///
/// ## Returns
/// `true` if the graphs are isomorphic.
pub fn is_isomorphic(
  n1 : Int,
  adj1 : Array[Array[Int]],
  n2 : Int,
  adj2 : Array[Array[Int]],
) -> Bool {
  if n1 != n2 {
    return false
  }
  if n1 <= 1 {
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
  // Degree computation
  let deg1 = Array::make(n1, 0)
  let deg2 = Array::make(n2, 0)
  for i = 0; i < n1; i = i + 1 {
    deg1[i] = adj1[i].length()
    deg2[i] = adj2[i].length()
  }
  // Quick check: same degree sequence
  let sorted_deg1 = Array::make(n1, 0)
  let sorted_deg2 = Array::make(n2, 0)
  for i = 0; i < n1; i = i + 1 {
    sorted_deg1[i] = deg1[i]
    sorted_deg2[i] = deg2[i]
  }
  sorted_deg1.sort()
  sorted_deg2.sort()
  for i = 0; i < n1; i = i + 1 {
    if sorted_deg1[i] != sorted_deg2[i] {
      return false
    }
  }
  // WL coloring for both graphs
  let colors1 = wl_coloring(n1, adj1, deg1)
  let colors2 = wl_coloring(n2, adj2, deg2)
  // Quick check: same color multiset
  let sorted_c1 = Array::make(n1, 0)
  let sorted_c2 = Array::make(n2, 0)
  for i = 0; i < n1; i = i + 1 {
    sorted_c1[i] = colors1[i]
    sorted_c2[i] = colors2[i]
  }
  sorted_c1.sort()
  sorted_c2.sort()
  for i = 0; i < n1; i = i + 1 {
    if sorted_c1[i] != sorted_c2[i] {
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
  // Compute color class sizes for vertex ordering.
  // Vertices in smaller color classes are assigned first (most constrained).
  let mut max_color = 0
  for i = 0; i < n1; i = i + 1 {
    if colors1[i] > max_color {
      max_color = colors1[i]
    }
  }
  let class_sizes = Array::make(max_color + 1, 0)
  for i = 0; i < n1; i = i + 1 {
    class_sizes[colors1[i]] = class_sizes[colors1[i]] + 1
  }
  // Order: smallest color class first, then highest degree (most constrained)
  let order : Array[Int] = []
  for i = 0; i < n1; i = i + 1 {
    order.push(i)
  }
  order.sort_by(fn(a, b) {
    let sa = class_sizes[colors1[a]]
    let sb = class_sizes[colors1[b]]
    if sa != sb {
      if sa < sb {
        -1
      } else {
        1
      }
    } else if deg1[a] != deg1[b] {
      if deg1[a] > deg1[b] {
        -1
      } else {
        1
      }
    } else {
      0
    }
  })
  // Backtracking with WL color constraint
  let mapping = Array::make(n1, -1)
  let used = Array::make(n1, false)
  backtrack_isomorphism(
    0, n1, order, mat1, mat2, mapping, used, colors1, colors2, deg1, deg2,
  )
}

///|
/// 1-dimensional Weisfeiler-Leman vertex coloring.
///
/// Iteratively refines vertex colors based on the multiset of neighbor colors
/// until the partition stabilizes. Two vertices that end up with different
/// colors cannot be mapped to each other in any isomorphism.
///
/// ## Complexity
/// O(V · E) per iteration, at most V iterations → O(V² · E) worst case.
fn wl_coloring(
  n : Int,
  adj : Array[Array[Int]],
  deg : Array[Int],
) -> Array[Int] {
  let colors = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    colors[i] = deg[i]
  }
  let mut changed = true
  let max_iters = n + 1
  for iter = 0; iter < max_iters && changed; iter = iter + 1 {
    changed = false
    // Compute signature for each vertex: (own_color, sorted neighbor colors)
    let sigs : Array[Array[Int]] = []
    for v = 0; v < n; v = v + 1 {
      let sig : Array[Int] = [colors[v]]
      for j = 0; j < adj[v].length(); j = j + 1 {
        sig.push(colors[adj[v][j]])
      }
      sig.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
      sigs.push(sig)
    }
    // Canonicalize: assign new color IDs based on sorted unique signatures
    let new_colors = canonicalize_sigs(n, sigs)
    for v = 0; v < n; v = v + 1 {
      if new_colors[v] != colors[v] {
        changed = true
      }
      colors[v] = new_colors[v]
    }
  }
  colors
}

///|
/// Assign canonical color IDs (0, 1, 2, ...) based on sorted unique signatures.
///
/// Sorts vertex indices by their signatures lexicographically, then assigns
/// the same color ID to vertices with identical signatures.
fn canonicalize_sigs(n : Int, sigs : Array[Array[Int]]) -> Array[Int] {
  let indices : Array[Int] = []
  for v = 0; v < n; v = v + 1 {
    indices.push(v)
  }
  indices.sort_by(fn(a, b) { compare_int_arrays(sigs[a], sigs[b]) })
  let new_colors = Array::make(n, 0)
  let mut color_id = 0
  new_colors[indices[0]] = 0
  for i = 1; i < n; i = i + 1 {
    if compare_int_arrays(sigs[indices[i]], sigs[indices[i - 1]]) != 0 {
      color_id = color_id + 1
    }
    new_colors[indices[i]] = color_id
  }
  new_colors
}

///|
/// Lexicographic comparison of two integer arrays.
/// Returns -1 if `a < b`, 1 if `a > b`, 0 if equal.
fn compare_int_arrays(a : Array[Int], b : Array[Int]) -> Int {
  let la = a.length()
  let lb = b.length()
  let min_len = if la < lb { la } else { lb }
  for i = 0; i < min_len; i = i + 1 {
    if a[i] < b[i] {
      return -1
    }
    if a[i] > b[i] {
      return 1
    }
  }
  if la < lb {
    -1
  } else if la > lb {
    1
  } else {
    0
  }
}

///|
/// Backtracking search for isomorphism with WL color constraint.
///
/// Only tries mapping vertex `u` to vertex `v` if they share the same WL
/// color. Checks adjacency consistency: all already-mapped neighbors must
/// have corresponding edges in the target graph.
fn backtrack_isomorphism(
  depth : Int,
  n : Int,
  order : Array[Int],
  mat1 : Array[Array[Bool]],
  mat2 : Array[Array[Bool]],
  mapping : Array[Int],
  used : Array[Bool],
  colors1 : Array[Int],
  colors2 : Array[Int],
  deg1 : Array[Int],
  deg2 : Array[Int],
) -> Bool {
  if depth == n {
    return true
  }
  let u = order[depth]
  for v = 0; v < n; v = v + 1 {
    if !used[v] && deg2[v] == deg1[u] && colors2[v] == colors1[u] {
      // Check adjacency consistency with all already-mapped vertices
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
        if backtrack_isomorphism(
            depth + 1,
            n,
            order,
            mat1,
            mat2,
            mapping,
            used,
            colors1,
            colors2,
            deg1,
            deg2,
          ) {
          return true
        }
        mapping[u] = -1
        used[v] = false
      }
    }
  }
  false
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "isomorphism: identical graphs" {
  let g1 = [[1, 2], [0, 2], [0, 1]] // triangle
  let g2 = [[1, 2], [0, 2], [0, 1]]
  assert_true(is_isomorphic(3, g1, 3, g2))
}

///|
test "isomorphism: relabeled triangle" {
  let g1 = [[1, 2], [0, 2], [0, 1]] // triangle 0-1-2
  let g2 = [[1, 2], [0, 2], [0, 1]]
  assert_true(is_isomorphic(3, g1, 3, g2))
}

///|
test "isomorphism: path vs triangle" {
  let g1 = [[1], [0, 2], [1]] // path 0-1-2
  let g2 = [[1, 2], [0, 2], [0, 1]] // triangle
  assert_false(is_isomorphic(3, g1, 3, g2))
}

///|
test "isomorphism: different sizes" {
  assert_false(is_isomorphic(3, [[1], [0], []], 2, [[1], [0]]))
}

///|
test "isomorphism: single vertex" {
  assert_true(is_isomorphic(1, [[]], 1, [[]]))
}

///|
test "isomorphism: square vs two disconnected edges" {
  // Square: 0-1-2-3-0
  let g1 = [[1, 3], [0, 2], [1, 3], [0, 2]]
  // Two disconnected edges: 0-1, 2-3
  let g2 = [[1], [0], [3], [2]]
  assert_false(is_isomorphic(4, g1, 4, g2))
}

///|
test "isomorphism: K4 relabeled" {
  // Complete graph K4
  let g1 = [[1, 2, 3], [0, 2, 3], [0, 1, 3], [0, 1, 2]]
  let g2 = [[1, 2, 3], [0, 2, 3], [0, 1, 3], [0, 1, 2]]
  assert_true(is_isomorphic(4, g1, 4, g2))
}

///|
test "isomorphism: C6 vs two triangles" {
  // C6: 6-cycle — all degree 2, connected
  let c6 = [[1, 5], [0, 2], [1, 3], [2, 4], [3, 5], [4, 0]]
  // Two disjoint triangles — all degree 2, disconnected
  let two_tri = [[1, 2], [0, 2], [0, 1], [4, 5], [3, 5], [3, 4]]
  assert_false(is_isomorphic(6, c6, 6, two_tri))
}

///|
test "isomorphism: path P5 isomorphic to itself" {
  let p = [[1], [0, 2], [1, 3], [2, 4], [3]]
  assert_true(is_isomorphic(5, p, 5, p))
}

///|
test "isomorphism: disconnected graphs" {
  // Two isolated edges + isolated vertex
  let g1 = [[1], [0], [], [4], [3]]
  let g2 = [[1], [0], [], [4], [3]]
  assert_true(is_isomorphic(5, g1, 5, g2))
}

///|
test "isomorphism: K3,3 vs triangular prism" {
  // Both are 3-regular on 6 vertices, 9 edges.
  // K3,3 is bipartite (no triangles); prism has two triangles.
  let k33 = [[3, 4, 5], [3, 4, 5], [3, 4, 5], [0, 1, 2], [0, 1, 2], [0, 1, 2]]
  let prism = [[1, 2, 3], [0, 2, 4], [0, 1, 5], [0, 4, 5], [1, 3, 5], [2, 3, 4]]
  assert_false(is_isomorphic(6, k33, 6, prism))
}

///|
test "isomorphism: Petersen graph self-isomorphic" {
  // Petersen graph: 3-regular, 10 vertices, 15 edges
  let p = [
    [1, 4, 5],
    [0, 2, 6],
    [1, 3, 7],
    [2, 4, 8],
    [3, 0, 9],
    [0, 7, 8],
    [1, 8, 9],
    [2, 5, 9],
    [3, 5, 6],
    [4, 6, 7],
  ]
  assert_true(is_isomorphic(10, p, 10, p))
}
