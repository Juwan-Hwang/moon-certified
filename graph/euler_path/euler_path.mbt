/// Euler path and circuit finding using Hierholzer's algorithm.
///
/// Given a **directed** graph as an adjacency list, finds an Euler path (a
/// path that visits every edge exactly once) or an Euler circuit (an Euler
/// path that starts and ends at the same vertex).
///
/// ## Existence conditions (directed graph)
///
/// An **Euler circuit** exists when:
/// - Every vertex has equal in-degree and out-degree, and
/// - All edges belong to a single strongly connected component (ignoring
///   isolated vertices).
///
/// An **Euler path** (but not circuit) exists when:
/// - Exactly one vertex has `out-degree = in-degree + 1` (the start vertex),
/// - Exactly one vertex has `in-degree = out-degree + 1` (the end vertex),
/// - All other vertices have equal in-degree and out-degree, and
/// - All edges belong to a single connected component.
///
/// If neither condition holds, no Euler path/circuit exists.
///
/// ## Algorithm
///
/// Uses Hierholzer's algorithm:
/// 1. Start at the designated start vertex (for an Euler path) or any vertex
///    with outgoing edges (for an Euler circuit).
/// 2. Follow edges greedily, removing each edge as it is traversed, until
///    stuck (no outgoing edges remain).
/// 3. If any vertex on the current path still has unused outgoing edges,
///    splice a detour starting from that vertex.
/// 4. The result is the Euler path/circuit in reverse order.
///
/// ## Complexity
///
/// - Time: O(V + E) — each edge is visited once.
/// - Space: O(V + E) for the adjacency list and stack.
///
/// ## Implementation notes
///
/// The DFS is **iterative** (explicit stack) to prevent stack overflow on
/// large graphs. MoonBit does not guarantee tail-call optimisation.
///
/// Edge removal uses a per-vertex pointer (`ptr[v]`) that tracks the next
/// unvisited edge, giving O(1) amortised edge consumption without the
/// overhead of actually removing elements from the adjacency list.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Result of Euler path/circuit computation.
///
/// - `path`: a `FixedArray[Int]` of vertex indices in the order they are
///   visited. For an Euler circuit, the first and last vertices are the same.
///   Empty when no Euler path/circuit exists.
/// - `is_circuit`: `true` when the result is an Euler circuit (start == end),
///   `false` when it is an Euler path.
pub struct EulerResult {
  path : FixedArray[Int]
  is_circuit : Bool
}

// ---------------------------------------------------------------------------
// Degree computation
// ---------------------------------------------------------------------------

/// Compute in-degree and out-degree for each vertex.
///
/// Returns `(in_deg, out_deg)` as a pair of `FixedArray[Int]`.
fn compute_degrees(
  adj : Array[Array[Int]],
  n : Int,
) -> (FixedArray[Int], FixedArray[Int]) {
  let in_deg = FixedArray::make(n, 0)
  let out_deg = FixedArray::make(n, 0)
  for u = 0; u < n; u = u + 1 {
    out_deg[u] = adj[u].length()
    for j = 0; j < adj[u].length(); j = j + 1 {
      let v = adj[u][j]
      if v >= 0 && v < n {
        in_deg[v] = in_deg[v] + 1
      }
    }
  }
  (in_deg, out_deg)
}

// ---------------------------------------------------------------------------
// Connectivity check (BFS)
// ---------------------------------------------------------------------------

/// Check whether all edges are in the same weakly connected component.
///
/// A vertex with zero total degree is ignored (it has no edges and doesn't
/// affect Euler path existence). The check ensures that every vertex with
/// at least one edge is reachable from the start vertex when edge directions
/// are ignored.
fn check_connectivity(
  adj : Array[Array[Int]],
  n : Int,
  start : Int,
) -> Bool {
  // Build undirected adjacency for connectivity.
  let undirected : Array[Array[Int]] = []
  for _i = 0; _i < n; _i = _i + 1 {
    undirected.push([])
  }
  let has_edge = FixedArray::make(n, false)
  for u = 0; u < n; u = u + 1 {
    for j = 0; j < adj[u].length(); j = j + 1 {
      let v = adj[u][j]
      if v >= 0 && v < n {
        undirected[u].push(v)
        undirected[v].push(u)
        has_edge[u] = true
        has_edge[v] = true
      }
    }
  }
  // BFS from start (ignoring direction).
  let visited = FixedArray::make(n, false)
  let queue : Array[Int] = [start]
  visited[start] = true
  let mut head = 0
  while head < queue.length() {
    let u = queue[head]
    head = head + 1
    for j = 0; j < undirected[u].length(); j = j + 1 {
      let v = undirected[u][j]
      if !visited[v] {
        visited[v] = true
        queue.push(v)
      }
    }
  }
  // Every vertex with at least one edge must be visited.
  for v = 0; v < n; v = v + 1 {
    if has_edge[v] && !visited[v] {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Hierholzer's algorithm (iterative)
// ---------------------------------------------------------------------------

/// Run Hierholzer's algorithm starting from `start`.
///
/// Uses an iterative approach with two stacks:
/// - `stack`: the current DFS path (vertices not yet fully explored).
/// - `circuit`: the completed circuit (in reverse order).
///
/// Each vertex maintains a pointer (`ptr`) into its adjacency list. When
/// all edges of the current vertex are consumed, it is moved to the
/// `circuit` stack.
fn hierholzer(
  adj : Array[Array[Int]],
  n : Int,
  start : Int,
) -> FixedArray[Int] {
  let ptr = FixedArray::make(n, 0) // next edge index for each vertex
  let stack : Array[Int] = [start]
  let circuit : Array[Int] = []
  while stack.length() > 0 {
    let top_idx = stack.length() - 1
    let u = stack[top_idx]
    // Skip invalid edges (out of bounds).
    while ptr[u] < adj[u].length() {
      let v = adj[u][ptr[u]]
      if v >= 0 && v < n {
        break
      }
      ptr[u] = ptr[u] + 1
    }
    if ptr[u] < adj[u].length() {
      // Consume the next edge.
      let v = adj[u][ptr[u]]
      ptr[u] = ptr[u] + 1
      stack.push(v)
    } else {
      // No more edges: move to circuit.
      circuit.push(u)
      ignore(stack.pop())
    }
  }
  // The circuit is in reverse order; reverse it.
  let len = circuit.length()
  FixedArray::makei(len, fn(i) { circuit[len - 1 - i] })
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Find an Euler path or circuit in a directed graph.
///
/// # Parameters
/// - `adj`: adjacency list where `adj[i]` is an array of vertices that `i`
///   has directed edges to. Multi-edges are supported (parallel edges are
///   treated as distinct edges).
/// - `n`: number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// An `EulerResult`:
/// - If an Euler circuit exists: `path` contains the circuit (start == end),
///   `is_circuit` is `true`.
/// - If an Euler path (but not circuit) exists: `path` contains the path,
///   `is_circuit` is `false`.
/// - If neither exists: `path` is empty.
///
/// # Complexity
/// - Time: O(V + E)
/// - Space: O(V + E)
///
/// The algorithm is iterative (explicit stack), preventing stack overflow on
/// large graphs.
pub fn find_euler_path(
  adj : Array[Array[Int]],
  n : Int,
) -> EulerResult {
  if n <= 0 || adj.length() < n {
    return { path: FixedArray::make(0, 0), is_circuit: false }
  }
  // Count total edges.
  let mut total_edges = 0
  for u = 0; u < n; u = u + 1 {
    total_edges = total_edges + adj[u].length()
  }
  if total_edges == 0 {
    // Empty graph: trivial circuit on vertex 0 (if it exists).
    return { path: FixedArray::make(0, 0), is_circuit: false }
  }
  let (in_deg, out_deg) = compute_degrees(adj, n)
  // Classify vertices.
  let start_candidates : Array[Int] = [] // out = in + 1
  let end_candidates : Array[Int] = [] // in = out + 1
  let mut is_circuit = true
  for v = 0; v < n; v = v + 1 {
    let diff = out_deg[v] - in_deg[v]
    if diff == 1 {
      start_candidates.push(v)
      is_circuit = false
    } else if diff == -1 {
      end_candidates.push(v)
      is_circuit = false
    } else if diff != 0 {
      // No Euler path possible.
      return { path: FixedArray::make(0, 0), is_circuit: false }
    }
  }
  // Validate: exactly 0 or 2 special vertices.
  let mut start : Int = -1 // default value
  if is_circuit {
    // Euler circuit: start from any vertex with outgoing edges.
    let mut s = 0
    while s < n && adj[s].length() == 0 {
      s = s + 1
    }
    if s >= n {
      return { path: FixedArray::make(0, 0), is_circuit: false }
    }
    start = s
  } else {
    if start_candidates.length() != 1 || end_candidates.length() != 1 {
      return { path: FixedArray::make(0, 0), is_circuit: false }
    }
    start = start_candidates[0]
  }
  // Check connectivity.
  if !check_connectivity(adj, n, start) {
    return { path: FixedArray::make(0, 0), is_circuit: false }
  }
  // Run Hierholzer.
  let path = hierholzer(adj, n, start)
  // Verify: the path should have total_edges + 1 vertices.
  if path.length() != total_edges + 1 {
    return { path: FixedArray::make(0, 0), is_circuit: false }
  }
  { path, is_circuit }
}

/// Check whether a directed graph has an Euler circuit.
///
/// An Euler circuit exists when every vertex has equal in-degree and
/// out-degree, and all edges are in a single connected component.
pub fn has_euler_circuit(adj : Array[Array[Int]], n : Int) -> Bool {
  find_euler_path(adj, n).is_circuit
}

/// Check whether a directed graph has an Euler path (including circuits).
pub fn has_euler_path(adj : Array[Array[Int]], n : Int) -> Bool {
  find_euler_path(adj, n).path.length() > 0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "euler: simple circuit (directed cycle)" {
  // 0 -> 1 -> 2 -> 0
  let n = 3
  let adj : Array[Array[Int]] = [[1], [2], [0]]
  let result = find_euler_path(adj, n)
  assert_eq(result.is_circuit, true)
  assert_eq(result.path.length(), 4) // 3 edges + 1 vertex
  // First and last should be the same.
  assert_eq(result.path[0], result.path[3])
}

test "euler: self-loop circuit" {
  // 0 -> 0
  let adj : Array[Array[Int]] = [[0]]
  let result = find_euler_path(adj, 1)
  assert_eq(result.is_circuit, true)
  assert_eq(result.path.length(), 2)
  assert_eq(result.path[0], 0)
  assert_eq(result.path[1], 0)
}

test "euler: path (not circuit)" {
  // 0 -> 1 -> 2
  let adj : Array[Array[Int]] = [[1], [2], []]
  let result = find_euler_path(adj, 3)
  assert_eq(result.is_circuit, false)
  assert_eq(result.path.length(), 3) // 2 edges + 1 vertex
  assert_eq(result.path[0], 0)
  assert_eq(result.path[1], 1)
  assert_eq(result.path[2], 2)
}

test "euler: no path (degree mismatch)" {
  // 0 -> 1, 0 -> 2
  let adj : Array[Array[Int]] = [[1, 2], [], []]
  let result = find_euler_path(adj, 3)
  assert_eq(result.path.length(), 0)
}

test "euler: disconnected graph" {
  // 0 -> 1, 2 -> 3 (two disconnected edges)
  let adj : Array[Array[Int]] = [[1], [], [3], []]
  let result = find_euler_path(adj, 4)
  assert_eq(result.path.length(), 0)
}

test "euler: multi-edge circuit" {
  // 0 -> 1, 0 -> 1, 1 -> 0, 1 -> 0
  let adj : Array[Array[Int]] = [[1, 1], [0, 0]]
  let result = find_euler_path(adj, 2)
  assert_eq(result.is_circuit, true)
  assert_eq(result.path.length(), 5) // 4 edges + 1 vertex
}

test "euler: complex circuit" {
  // Two cycles sharing vertex 0:
  // 0 -> 1 -> 0, 0 -> 2 -> 0
  let adj : Array[Array[Int]] = [[1, 2], [0], [0]]
  let result = find_euler_path(adj, 3)
  assert_eq(result.is_circuit, true)
  assert_eq(result.path.length(), 5) // 4 edges + 1 vertex
  // Verify all edges are used by checking path[0] == path[4].
  assert_eq(result.path[0], result.path[4])
}

test "euler: path with detour" {
  // 0 -> 1 -> 2 (path)
  // 1 -> 3 -> 1 (detour at vertex 1)
  // Start: 0 (out=1, in=0), End: 2 (out=0, in=1)
  let adj : Array[Array[Int]] = [[1], [2, 3], [], [1]]
  let result = find_euler_path(adj, 4)
  assert_eq(result.is_circuit, false)
  assert_eq(result.path.length(), 5) // 4 edges + 1 vertex
  assert_eq(result.path[0], 0) // starts at 0
  assert_eq(result.path[4], 2) // ends at 2
  // Verify the path is valid: each consecutive pair is an edge.
  // Path: 0 -> 1 -> 3 -> 1 -> 2
  assert_eq(result.path[0], 0)
  assert_eq(result.path[1], 1)
  assert_eq(result.path[2], 3)
  assert_eq(result.path[3], 1)
  assert_eq(result.path[4], 2)
}

test "euler: empty graph" {
  let adj : Array[Array[Int]] = [[], [], []]
  let result = find_euler_path(adj, 3)
  assert_eq(result.path.length(), 0)
}

test "euler: invalid n" {
  let adj : Array[Array[Int]] = []
  let result = find_euler_path(adj, 0)
  assert_eq(result.path.length(), 0)
}

test "euler: single edge" {
  // 0 -> 1
  let adj : Array[Array[Int]] = [[1], []]
  let result = find_euler_path(adj, 2)
  assert_eq(result.is_circuit, false)
  assert_eq(result.path.length(), 2)
  assert_eq(result.path[0], 0)
  assert_eq(result.path[1], 1)
}

test "euler: large circuit (stack safety)" {
  // Ring of 1000 nodes: 0 -> 1 -> 2 -> ... -> 999 -> 0
  let n = 1000
  let adj : Array[Array[Int]] = []
  for _i = 0; _i < n; _i = _i + 1 {
    adj.push([])
  }
  for i = 0; i < n; i = i + 1 {
    adj[i].push((i + 1) % n)
  }
  let result = find_euler_path(adj, n)
  assert_eq(result.is_circuit, true)
  assert_eq(result.path.length(), n + 1) // n edges + 1 vertex
  // First and last should be the same.
  assert_eq(result.path[0], result.path[n])
}

test "has_euler_circuit: basic checks" {
  // Circuit exists.
  assert_eq(has_euler_circuit([[1], [2], [0]], 3), true)
  // Path exists but not circuit.
  assert_eq(has_euler_circuit([[1], [2], []], 3), false)
  // No path.
  assert_eq(has_euler_circuit([[1, 2], [], []], 3), false)
}

test "has_euler_path: basic checks" {
  // Circuit is also a path.
  assert_eq(has_euler_path([[1], [2], [0]], 3), true)
  // Path exists.
  assert_eq(has_euler_path([[1], [2], []], 3), true)
  // No path.
  assert_eq(has_euler_path([[1, 2], [], []], 3), false)
}
