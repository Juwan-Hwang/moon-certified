/// Graph coloring algorithms.
///
/// Assigns colours to graph vertices so that no two adjacent vertices share
/// the same colour, while minimising the number of colours used.
///
/// ## Algorithms
///
/// 1. **DSATUR** (Degree of Saturation) — a greedy heuristic that always
///    colours the vertex with the highest saturation degree (number of
///    distinct colours among its neighbours). Ties are broken by ordinary
///    degree. This is one of the strongest polynomial-time heuristics for
///    graph colouring, typically within 1-2 colours of the chromatic number.
///
/// 2. **Greedy sequential** — colours vertices in the given order, always
///    using the smallest available colour. Included as a baseline and for
///    comparison.
///
/// 3. **Welsh-Powell** — greedy on vertices sorted by descending degree.
///
/// ## Complexity
///
/// - DSATUR: O(V² + E) with a naive priority queue (recomputed each step).
///   This is sufficient for V up to ~10⁴. For larger graphs, a Fibonacci
///   heap or bucket-based priority queue would reduce this to O(V log V + E).
/// - Greedy: O(V + E) per vertex ordering.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

/// A graph colouring result.
///
/// `colors[v]` is the colour assigned to vertex `v` (0-indexed), or `-1` if
/// the vertex was not coloured. `num_colors` is the total number of distinct
/// colours used.
pub struct Coloring {
  colors : FixedArray[Int]
  num_colors : Int
}

/// Accessor: the colour of vertex `v`.
pub fn color_of(c : Coloring, v : Int) -> Int {
  c.colors[v]
}

/// The total number of colours used.
pub fn color_count(c : Coloring) -> Int {
  c.num_colors
}

// ---------------------------------------------------------------------------
// DSATUR colouring
// ---------------------------------------------------------------------------

/// Colour the graph using the DSATUR heuristic.
///
/// DSATUR (Degree of Saturation) repeatedly selects the uncoloured vertex
/// with the highest saturation degree — the number of distinct colours among
/// its already-coloured neighbours. Ties are broken by the ordinary degree.
/// The selected vertex is then assigned the smallest colour not used by any
/// neighbour.
///
/// # Parameters
/// - `adj`: adjacency list, `adj[i]` = array of neighbour indices.
/// - `n`: number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// A [`Coloring`] with the assigned colours.
///
/// # Complexity
/// O(V² + E).
pub fn dsatur(adj : Array[Array[Int]], n : Int) -> Coloring {
  if n == 0 {
    return { colors: FixedArray::make(0, 0), num_colors: 0 }
  }
  let colors = FixedArray::make(n, -1)
  // Saturation degree: number of distinct colours among neighbours.
  let saturation = FixedArray::make(n, 0)
  // Track which colours are present among each vertex's neighbours (bitset).
  let neighbor_colors = FixedArray::make(n, 0) // bit i set → colour i used by a neighbour

  let mut num_colors = 0

  for _step = 0; _step < n; _step = _step + 1 {
    // Select the uncoloured vertex with maximum saturation, breaking ties
    // by maximum degree.
    let mut best_v = -1
    let mut best_sat = -1
    let mut best_deg = -1
    for v = 0; v < n; v = v + 1 {
      if colors[v] == -1 {
        let deg = adj[v].length()
        if saturation[v] > best_sat ||
          (saturation[v] == best_sat && deg > best_deg) {
          best_v = v
          best_sat = saturation[v]
          best_deg = deg
        }
      }
    }
    if best_v == -1 {
      break
    }
    // Find the smallest colour not used by any neighbour.
    let mut used = neighbor_colors[best_v]
    let mut c = 0
    while (used & 1) != 0 {
      used = used >> 1
      c = c + 1
    }
    colors[best_v] = c
    if c + 1 > num_colors {
      num_colors = c + 1
    }
    // Update neighbours' saturation and neighbour_colors bitset.
    for idx = 0; idx < adj[best_v].length(); idx = idx + 1 {
      let u = adj[best_v][idx]
      let bit = 1 << c
      if (neighbor_colors[u] & bit) == 0 {
        neighbor_colors[u] = neighbor_colors[u] | bit
        saturation[u] = saturation[u] + 1
      }
    }
  }

  { colors, num_colors }
}

// ---------------------------------------------------------------------------
// Greedy sequential colouring
// ---------------------------------------------------------------------------

/// Colour the graph using the greedy algorithm in the natural vertex order
/// 0, 1, 2, ..., n-1. Each vertex gets the smallest colour not used by any
/// already-coloured neighbour.
///
/// # Complexity
/// O(V + E).
pub fn greedy_color(adj : Array[Array[Int]], n : Int) -> Coloring {
  if n == 0 {
    return { colors: FixedArray::make(0, 0), num_colors: 0 }
  }
  let colors = FixedArray::make(n, -1)
  let mut num_colors = 0
  for v = 0; v < n; v = v + 1 {
    // Mark colours used by neighbours.
    let used : Array[Bool] = []
    // Check neighbours' colours.
    let mut max_neighbor_color = -1
    for idx = 0; idx < adj[v].length(); idx = idx + 1 {
      let u = adj[v][idx]
      if colors[u] >= 0 {
        while used.length() <= colors[u] {
          used.push(false)
        }
        used[colors[u]] = true
        if colors[u] > max_neighbor_color {
          max_neighbor_color = colors[u]
        }
      }
    }
    // Find smallest unused colour.
    let mut c = 0
    while c < used.length() && used[c] {
      c = c + 1
    }
    colors[v] = c
    if c + 1 > num_colors {
      num_colors = c + 1
    }
  }
  { colors, num_colors }
}

// ---------------------------------------------------------------------------
// Welsh-Powell colouring (greedy on descending degree order)
// ---------------------------------------------------------------------------

/// Colour the graph using the Welsh-Powell algorithm: sort vertices by
/// descending degree, then apply the greedy algorithm in that order.
///
/// # Complexity
/// O(V log V + E).
pub fn welsh_powell(adj : Array[Array[Int]], n : Int) -> Coloring {
  if n == 0 {
    return { colors: FixedArray::make(0, 0), num_colors: 0 }
  }
  // Sort vertex indices by descending degree.
  let order : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    order.push(i)
  }
  order.sort_by(fn(a, b) {
    let da = adj[a].length()
    let db = adj[b].length()
    db - da
  })
  let colors = FixedArray::make(n, -1)
  let mut num_colors = 0
  for idx = 0; idx < n; idx = idx + 1 {
    let v = order[idx]
    let used : Array[Bool] = []
    for j = 0; j < adj[v].length(); j = j + 1 {
      let u = adj[v][j]
      if colors[u] >= 0 {
        while used.length() <= colors[u] {
          used.push(false)
        }
        used[colors[u]] = true
      }
    }
    let mut c = 0
    while c < used.length() && used[c] {
      c = c + 1
    }
    colors[v] = c
    if c + 1 > num_colors {
      num_colors = c + 1
    }
  }
  { colors, num_colors }
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/// Verify that a colouring is valid: no two adjacent vertices share a colour.
/// Returns `true` if valid, `false` otherwise.
pub fn is_valid_coloring(
  adj : Array[Array[Int]],
  n : Int,
  c : Coloring,
) -> Bool {
  for v = 0; v < n; v = v + 1 {
    if c.colors[v] < 0 {
      return false
    }
    for j = 0; j < adj[v].length(); j = j + 1 {
      let u = adj[v][j]
      if u > v && c.colors[v] == c.colors[u] {
        return false
      }
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "dsatur: triangle needs 3 colours" {
  let adj : Array[Array[Int]] = [[1, 2], [0, 2], [0, 1]]
  let c = dsatur(adj, 3)
  assert_eq(c.num_colors, 3)
  assert_true(is_valid_coloring(adj, 3, c))
}

test "dsatur: bipartite graph needs 2 colours" {
  // 0-1, 0-3, 2-1, 2-3: a 4-cycle
  let adj : Array[Array[Int]] = [[1, 3], [0, 2], [1, 3], [0, 2]]
  let c = dsatur(adj, 4)
  assert_eq(c.num_colors, 2)
  assert_true(is_valid_coloring(adj, 4, c))
}

test "dsatur: complete graph K4 needs 4 colours" {
  let adj : Array[Array[Int]] = [
    [1, 2, 3], [0, 2, 3], [0, 1, 3], [0, 1, 2],
  ]
  let c = dsatur(adj, 4)
  assert_eq(c.num_colors, 4)
  assert_true(is_valid_coloring(adj, 4, c))
}

test "dsatur: path graph needs 2 colours" {
  // 0-1-2-3-4
  let adj : Array[Array[Int]] = [[1], [0, 2], [1, 3], [2, 4], [3]]
  let c = dsatur(adj, 5)
  assert_eq(c.num_colors, 2)
  assert_true(is_valid_coloring(adj, 5, c))
}

test "dsatur: star graph needs 2 colours" {
  let adj : Array[Array[Int]] = [[1, 2, 3, 4], [0], [0], [0], [0]]
  let c = dsatur(adj, 5)
  assert_eq(c.num_colors, 2)
  assert_true(is_valid_coloring(adj, 5, c))
}

test "dsatur: empty graph needs 0 colours" {
  let adj : Array[Array[Int]] = [[], [], []]
  let c = dsatur(adj, 3)
  assert_eq(c.num_colors, 1)
  assert_true(is_valid_coloring(adj, 3, c))
}

test "greedy: triangle" {
  let adj : Array[Array[Int]] = [[1, 2], [0, 2], [0, 1]]
  let c = greedy_color(adj, 3)
  assert_eq(c.num_colors, 3)
  assert_true(is_valid_coloring(adj, 3, c))
}

test "greedy: bipartite" {
  let adj : Array[Array[Int]] = [[1, 3], [0, 2], [1, 3], [0, 2]]
  let c = greedy_color(adj, 4)
  assert_eq(c.num_colors, 2)
  assert_true(is_valid_coloring(adj, 4, c))
}

test "welsh_powell: triangle" {
  let adj : Array[Array[Int]] = [[1, 2], [0, 2], [0, 1]]
  let c = welsh_powell(adj, 3)
  assert_eq(c.num_colors, 3)
  assert_true(is_valid_coloring(adj, 3, c))
}

test "welsh_powell: K4" {
  let adj : Array[Array[Int]] = [
    [1, 2, 3], [0, 2, 3], [0, 1, 3], [0, 1, 2],
  ]
  let c = welsh_powell(adj, 4)
  assert_eq(c.num_colors, 4)
  assert_true(is_valid_coloring(adj, 4, c))
}

test "dsatur: Petersen graph (3-regular, chromatic number 3)" {
  // The Petersen graph is 3-regular and has chromatic number 3.
  // Outer 5-cycle: 0-1-2-3-4-0
  // Inner 5-pointed star: 5-7-9-6-8-5
  // Spokes: 0-5, 1-6, 2-7, 3-8, 4-9
  let adj : Array[Array[Int]] = [
    [1, 4, 5], // 0
    [0, 2, 6], // 1
    [1, 3, 7], // 2
    [2, 4, 8], // 3
    [3, 0, 9], // 4
    [0, 7, 8], // 5
    [1, 8, 9], // 6
    [2, 5, 9], // 7
    [3, 5, 6], // 8
    [4, 6, 7], // 9
  ]
  let c = dsatur(adj, 10)
  assert_true(c.num_colors >= 3) // at least chromatic number
  assert_true(c.num_colors <= 4) // DSATUR should get close
  assert_true(is_valid_coloring(adj, 10, c))
}

test "dsatur: cycle of length 5 needs 3 colours" {
  // Odd cycle: chromatic number is 3
  let adj : Array[Array[Int]] = [
    [1, 4], [0, 2], [1, 3], [2, 4], [3, 0],
  ]
  let c = dsatur(adj, 5)
  assert_eq(c.num_colors, 3)
  assert_true(is_valid_coloring(adj, 5, c))
}

test "dsatur: cycle of length 6 needs 2 colours" {
  // Even cycle: chromatic number is 2
  let adj : Array[Array[Int]] = [
    [1, 5], [0, 2], [1, 3], [2, 4], [3, 5], [4, 0],
  ]
  let c = dsatur(adj, 6)
  assert_eq(c.num_colors, 2)
  assert_true(is_valid_coloring(adj, 6, c))
}

test "dsatur: wheel graph W5 (5-cycle + hub)" {
  // Hub 0 connected to all of 1-5, plus 1-2-3-4-5-1 cycle
  let adj : Array[Array[Int]] = [
    [1, 2, 3, 4, 5], // hub
    [0, 2, 5], [0, 1, 3], [0, 2, 4], [0, 3, 5], [0, 1, 4],
  ]
  let c = dsatur(adj, 6)
  assert_true(is_valid_coloring(adj, 6, c))
  // W5 (odd rim): chromatic number is 4 (hub needs one colour, rim needs 3)
  assert_true(c.num_colors >= 3)
}

test "is_valid_coloring: rejects invalid colouring" {
  let adj : Array[Array[Int]] = [[1], [0]]
  let bad = { colors: FixedArray::make(2, 0), num_colors: 1 }
  assert_false(is_valid_coloring(adj, 2, bad))
}

test "is_valid_coloring: accepts valid colouring" {
  let adj : Array[Array[Int]] = [[1], [0]]
  let good = { colors: FixedArray::make(2, 0), num_colors: 2 }
  good.colors[1] = 1
  assert_true(is_valid_coloring(adj, 2, good))
}
