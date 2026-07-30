/// Planarity test using the Demoucron-Malgrange-Pertuiset (DMP) algorithm.
///
/// A graph is planar if it can be drawn on a plane without edge crossings.
/// Kuratowski's theorem: a graph is planar iff it does not contain a
/// subdivision of K5 or K3,3.
///
/// The DMP algorithm is a constructive planarity test that builds a planar
/// embedding incrementally:
/// 1. Find an initial cycle and embed it as two faces
/// 2. Find "pieces" — connected components of unembedded edges
/// 3. For each piece, determine which faces it can be placed in
/// 4. If any piece has no valid face, the graph is non-planar
/// 5. Embed a piece (finding a path through it), splitting a face
/// 6. Repeat until all edges are embedded
///
/// ## Complexity
/// - O(V²) time
/// - O(V + E) space
///
/// ## References
/// - Demoucron, G., Malgrange, Y., and Pertuiset, R. "Graphes planaires:
///   reconnaissance et construction de représentations topologiques."
///   Revue française d'informatique et de recherche opérationnelle, 1964.
/// - Kuratowski, K. "Sur le problème des courbes gauches en topologie."
///   Fundamenta Mathematicae, 1930.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Graph representation
// ---------------------------------------------------------------------------

///|
/// Build adjacency list from edge list, removing self-loops and multi-edges.
fn build_adj(n : Int, edges : Array[(Int, Int)]) -> Array[Array[Int]] {
  let adj : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    adj.push([])
  }
  let seen : Map[(Int, Int), Unit] = Map([])
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v) = edges[i]
    if u >= 0 && u < n && v >= 0 && v < n && u != v {
      let key = if u < v { (u, v) } else { (v, u) }
      match seen.get(key) {
        None => {
          seen[key] = ()
          adj[u].push(v)
          adj[v].push(u)
        }
        Some(_) => ()
      }
    }
  }
  adj
}

// ---------------------------------------------------------------------------
// Cycle finding (iterative DFS)
// ---------------------------------------------------------------------------

///|
/// Find a cycle in the graph using iterative DFS.
/// Returns the cycle as a list of vertices, or None if the graph is a forest.
fn find_cycle(n : Int, adj : Array[Array[Int]]) -> Array[Int]? {
  let visited = Array::make(n, false)
  let parent = Array::make(n, -1)
  for start = 0; start < n; start = start + 1 {
    if visited[start] {
      continue
    }
    // Iterative DFS using explicit stack of (vertex, neighbor_index).
    let stack : Array[(Int, Int)] = [(start, 0)]
    visited[start] = true
    while stack.length() > 0 {
      let (u, ni) = stack[stack.length() - 1]
      if ni < adj[u].length() {
        stack[stack.length() - 1] = (u, ni + 1)
        let v = adj[u][ni]
        if !visited[v] {
          visited[v] = true
          parent[v] = u
          stack.push((v, 0))
        } else if v != parent[u] {
          // Found a back edge u→v. Extract cycle: v → ... → u → v.
          let cycle : Array[Int] = []
          cycle.push(v)
          let mut w = u
          while w != v {
            cycle.push(w)
            w = parent[w]
          }
          return Some(cycle)
        }
      } else {
        ignore(stack.pop())
      }
    }
  }
  None
}

// ---------------------------------------------------------------------------
// DMP algorithm core
// ---------------------------------------------------------------------------

///|
/// Edge key (smaller vertex first) for set operations.
fn edge_key(u : Int, v : Int) -> (Int, Int) {
  if u < v {
    (u, v)
  } else {
    (v, u)
  }
}

///|
/// A piece is a connected component of unembedded edges, along with its
/// attachment vertices (vertices on the current embedding boundary).
struct Piece {
  vertices : Map[Int, Unit] // All vertices in this piece
  attachments : Array[Int] // Vertices on the embedding boundary
  edges : Array[(Int, Int)] // Edges within this piece
}

///|
/// Find all pieces — connected components of unembedded edges.
/// A piece's attachment vertices are those on the boundary of any face.
fn find_pieces(
  n : Int,
  adj : Array[Array[Int]],
  embedded : Map[(Int, Int), Unit],
  boundary_vertices : Map[Int, Unit]
) -> Array[Piece] {
  let visited = Array::make(n, false)
  let pieces : Array[Piece] = []
  for start = 0; start < n; start = start + 1 {
    if visited[start] {
      continue
    }
    // Check if start has any unembedded edges.
    let has_unembedded = {
      let mut found = false
      for j = 0; j < adj[start].length(); j = j + 1 {
        let v = adj[start][j]
        if !embedded.contains(edge_key(start, v)) {
          found = true
          break
        }
      }
      found
    }
    if !has_unembedded {
      visited[start] = true
      continue
    }
    // BFS to find connected component of unembedded edges.
    let comp_vertices : Map[Int, Unit] = Map([])
    let comp_edges : Array[(Int, Int)] = []
    let queue : Array[Int] = [start]
    let mut qhead = 0
    visited[start] = true
    comp_vertices[start] = ()
    while qhead < queue.length() {
      let u = queue[qhead]
      qhead = qhead + 1
      for j = 0; j < adj[u].length(); j = j + 1 {
        let v = adj[u][j]
        let ek = edge_key(u, v)
        if !embedded.contains(ek) {
          // This edge is unembedded — part of a piece.
          if !comp_vertices.contains(v) {
            // Only add edges once (u < v).
            if u < v {
              comp_edges.push((u, v))
            }
          } else {
            // Both endpoints already in component — edge within piece.
            if u < v {
              comp_edges.push((u, v))
            }
          }
          if !visited[v] {
            visited[v] = true
            comp_vertices[v] = ()
            queue.push(v)
          }
        }
      }
    }
    // Find attachment vertices (on boundary).
    let attachments : Array[Int] = []
    for v, _ in comp_vertices {
      if boundary_vertices.contains(v) {
        attachments.push(v)
      }
    }
    // Also check: a vertex might be in the component but all its edges are
    // embedded. We need to re-check visited — a vertex is truly "in a piece"
    // only if it has at least one unembedded edge.
    // (Already handled by the BFS starting from unembedded edges.)
    if attachments.length() >= 2 || comp_edges.length() > 0 {
      // Filter: only vertices that actually have unembedded edges.
      // Also handle case where a vertex is in comp_vertices but has no
      // unembedded edges (reached via embedded edge during BFS — shouldn't
      // happen given our BFS only follows unembedded edges).
      pieces.push(Piece::{
        vertices: comp_vertices,
        attachments,
        edges: comp_edges,
      })
    }
  }
  pieces
}

///|
/// Check if all attachment vertices of a piece are on the boundary of a face.
fn piece_fits_face(piece : Piece, face : Array[Int]) -> Bool {
  // Build set of face boundary vertices.
  let face_set : Map[Int, Unit] = Map([])
  for i = 0; i < face.length(); i = i + 1 {
    face_set[face[i]] = ()
  }
  // Check all attachments are on the face.
  for i = 0; i < piece.attachments.length(); i = i + 1 {
    if !face_set.contains(piece.attachments[i]) {
      return false
    }
  }
  true
}

///|
/// Find a path within a piece between two attachment vertices that are on
/// the same face. Uses BFS through the piece's unembedded edges.
fn find_path_in_piece(
  piece : Piece,
  start : Int,
  end : Int,
  adj : Array[Array[Int]],
  embedded : Map[(Int, Int), Unit]
) -> Array[Int]? raise Failure {
  let in_piece = piece.vertices
  let visited : Map[Int, Unit] = Map([])
  let parent : Map[Int, Int] = Map([])
  let queue : Array[Int] = [start]
  let mut qhead = 0
  visited[start] = ()
  while qhead < queue.length() {
    let u = queue[qhead]
    qhead = qhead + 1
    if u == end {
      // Reconstruct path.
      let path_rev : Array[Int] = []
      let mut w = end
      path_rev.push(w)
      while w != start {
        match parent.get(w) {
          Some(p) => {
            path_rev.push(p)
            w = p
          }
          None => fail("find_path: parent chain broken")
        }
      }
      // Reverse path_rev into path.
      let path : Array[Int] = []
      for i = path_rev.length() - 1; i >= 0; i = i - 1 {
        path.push(path_rev[i])
      }
      return Some(path)
    }
    for j = 0; j < adj[u].length(); j = j + 1 {
      let v = adj[u][j]
      let ek = edge_key(u, v)
      if !embedded.contains(ek) && in_piece.contains(v) && !visited.contains(v) {
        visited[v] = ()
        parent[v] = u
        queue.push(v)
      }
    }
  }
  None
}

///|
/// Split a face by embedding a path.
/// The path connects two vertices on the face boundary.
/// Returns the two new faces.
///
/// face1 = path + face_boundary_forward(end → start, exclusive both)
/// face2 = [start] + face_boundary_forward(start → end, exclusive both) + [end] + reversed_path_internal
fn split_face(face : Array[Int], path : Array[Int]) -> (Array[Int], Array[Int]) raise Failure {
  let start = path[0]
  let endp = path[path.length() - 1]
  // Find positions of start and end on the face boundary.
  let mut start_idx = -1
  let mut end_idx = -1
  for i = 0; i < face.length(); i = i + 1 {
    if face[i] == start {
      start_idx = i
    }
    if face[i] == endp {
      end_idx = i
    }
  }
  if start_idx < 0 || end_idx < 0 {
    fail("split_face: path endpoints not on face boundary")
  }
  let flen = face.length()
  // face1: path, then face boundary forward from end to start (exclusive both).
  let face1 : Array[Int] = []
  for i = 0; i < path.length(); i = i + 1 {
    face1.push(path[i])
  }
  let mut idx = end_idx
  while true {
    idx = (idx + 1) % flen
    if idx == start_idx {
      break
    }
    face1.push(face[idx])
  }
  // face2: start, face boundary forward from start to end (exclusive both),
  // end, reversed path internal (excluding start and end).
  let face2 : Array[Int] = []
  face2.push(start)
  idx = start_idx
  while true {
    idx = (idx + 1) % flen
    if idx == end_idx {
      break
    }
    face2.push(face[idx])
  }
  face2.push(endp)
  for i = path.length() - 2; i >= 1; i = i - 1 {
    face2.push(path[i])
  }
  (face1, face2)
}

// ---------------------------------------------------------------------------
// Connected component decomposition
// ---------------------------------------------------------------------------

///|
/// Find connected components of the graph.
/// Returns an array of components, each being a list of vertex indices.
fn find_connected_components(
  n : Int,
  adj : Array[Array[Int]]
) -> Array[Array[Int]] {
  let visited = Array::make(n, false)
  let components : Array[Array[Int]] = []
  for start = 0; start < n; start = start + 1 {
    if visited[start] {
      continue
    }
    let comp : Array[Int] = []
    let queue : Array[Int] = [start]
    let mut qhead = 0
    visited[start] = true
    while qhead < queue.length() {
      let u = queue[qhead]
      qhead = qhead + 1
      comp.push(u)
      for j = 0; j < adj[u].length(); j = j + 1 {
        let v = adj[u][j]
        if !visited[v] {
          visited[v] = true
          queue.push(v)
        }
      }
    }
    components.push(comp)
  }
  components
}

// ---------------------------------------------------------------------------
// DMP on a single connected component
// ---------------------------------------------------------------------------

///|
/// Run the DMP planarity test on a single connected component.
///
/// The component is described by its adjacency list (using original vertex
/// indices). We find a cycle within the component and run the DMP loop.
fn dmp_connected(
  n : Int,
  adj : Array[Array[Int]]
) -> Bool raise Failure {
  // Necessary condition: E <= 3V - 6 (for V >= 3)
  let m = {
    let mut count = 0
    for i = 0; i < n; i = i + 1 {
      count = count + adj[i].length()
    }
    count / 2
  }
  if n >= 3 && m > 3 * n - 6 {
    return false
  }
  // Find a cycle.
  let cycle = match find_cycle(n, adj) {
    None => return true // Forest — always planar
    Some(c) => c
  }
  // Initialize: embed the cycle as two faces.
  let embedded : Map[(Int, Int), Unit] = Map([])
  for i = 0; i < cycle.length(); i = i + 1 {
    let u = cycle[i]
    let v = cycle[(i + 1) % cycle.length()]
    embedded[edge_key(u, v)] = ()
  }
  // Two faces: the cycle traversed in both directions.
  let face1 : Array[Int] = []
  let face2 : Array[Int] = []
  for i = 0; i < cycle.length(); i = i + 1 {
    face1.push(cycle[i])
  }
  for i = cycle.length() - 1; i >= 0; i = i - 1 {
    face2.push(cycle[i])
  }
  let faces : Array[Array[Int]] = [face1, face2]
  // Main DMP loop.
  let max_iter = n * n + 100 // Safety bound.
  let mut iter = 0
  while iter < max_iter {
    iter = iter + 1
    // Build set of boundary vertices.
    let boundary_vertices : Map[Int, Unit] = Map([])
    for f = 0; f < faces.length(); f = f + 1 {
      for i = 0; i < faces[f].length(); i = i + 1 {
        boundary_vertices[faces[f][i]] = ()
      }
    }
    // Find pieces.
    let pieces = find_pieces(n, adj, embedded, boundary_vertices)
    if pieces.length() == 0 {
      // All edges embedded.
      return true
    }
    // For each piece, find valid faces.
    // Also handle pieces that are single edges between two boundary vertices.
    let mut selected_piece = -1
    let mut selected_face = -1
    let mut min_faces = 999999
    for p = 0; p < pieces.length(); p = p + 1 {
      let piece = pieces[p]
      let valid_faces : Array[Int] = []
      for f = 0; f < faces.length(); f = f + 1 {
        if piece_fits_face(piece, faces[f]) {
          valid_faces.push(f)
        }
      }
      if valid_faces.length() == 0 {
        // Piece cannot fit in any face — non-planar.
        return false
      }
      if valid_faces.length() < min_faces {
        min_faces = valid_faces.length()
        selected_piece = p
        selected_face = valid_faces[0]
      }
    }
    if selected_piece < 0 {
      return true
    }
    // Embed the selected piece in the selected face.
    let piece = pieces[selected_piece]
    let face = faces[selected_face]
    // Find a path in the piece between two attachment vertices on the face.
    let mut path_found = false
    for i = 0; i < piece.attachments.length() && !path_found; i = i + 1 {
      for j = i + 1; j < piece.attachments.length() && !path_found; j = j + 1 {
        match find_path_in_piece(
          piece,
          piece.attachments[i],
          piece.attachments[j],
          adj,
          embedded
        ) {
          Some(path) => {
            // Embed the path edges.
            for k = 0; k < path.length() - 1; k = k + 1 {
              embedded[edge_key(path[k], path[k + 1])] = ()
            }
            // Split the face.
            let (f1, f2) = split_face(face, path)
            faces[selected_face] = f1
            faces.push(f2)
            path_found = true
          }
          None => continue
        }
      }
    }
    // If no path found between any pair of attachments, the piece might
    // be a single vertex or have all edges already embedded. Skip it.
    if !path_found {
      // This shouldn't happen if pieces are correctly identified.
      // Mark all edges in the piece as embedded to avoid infinite loop.
      for i = 0; i < piece.edges.length(); i = i + 1 {
        embedded[piece.edges[i]] = ()
      }
    }
  }
  // If we exceeded max iterations, check if all edges are embedded.
  let mut all_embedded = true
  for u = 0; u < n; u = u + 1 {
    for j = 0; j < adj[u].length(); j = j + 1 {
      let v = adj[u][j]
      if u < v && !embedded.contains(edge_key(u, v)) {
        all_embedded = false
        break
      }
    }
    if !all_embedded {
      break
    }
  }
  all_embedded
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Test if a graph is planar using the DMP algorithm.
///
/// Returns `true` if the graph is planar, `false` otherwise.
///
/// ## Parameters
/// - `n`: number of vertices (0-indexed: 0..n-1)
/// - `edges`: array of (u, v) pairs representing undirected edges
///
/// ## Complexity
/// O(V²) time, O(V + E) space.
///
/// ## Algorithm
/// The graph is decomposed into connected components. Each component is
/// tested independently using DMP (Demoucron-Malgrange-Pertuiset): a
/// constructive planarity test that builds a planar embedding incrementally
/// by embedding "pieces" into faces. If any piece cannot fit in any face,
/// the component is non-planar (contains a Kuratowski subdivision of K5
/// or K3,3).
pub fn is_planar(n : Int, edges : Array[(Int, Int)]) -> Bool raise Failure {
  if n <= 4 {
    return true
  }
  let adj = build_adj(n, edges)
  // Decompose into connected components and test each independently.
  let components = find_connected_components(n, adj)
  for c = 0; c < components.length(); c = c + 1 {
    let comp = components[c]
    let comp_size = comp.length()
    if comp_size <= 4 {
      continue // Any graph with ≤ 4 vertices is planar.
    }
    // Build remapped subgraph for this component.
    let remap : Map[Int, Int] = Map([])
    for i = 0; i < comp_size; i = i + 1 {
      remap[comp[i]] = i
    }
    let sub_adj : Array[Array[Int]] = []
    for i = 0; i < comp_size; i = i + 1 {
      sub_adj.push([])
    }
    for i = 0; i < comp_size; i = i + 1 {
      let orig = comp[i]
      for j = 0; j < adj[orig].length(); j = j + 1 {
        let neighbor = adj[orig][j]
        match remap.get(neighbor) {
          Some(mapped) => sub_adj[i].push(mapped)
          None => continue
        }
      }
    }
    if !dmp_connected(comp_size, sub_adj) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

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

test "planar_test: K5 subdivision is not planar" {
  // K5 with one edge (0-1) replaced by path 0-5-1.
  // This is a subdivision of K5, so it's non-planar.
  // The old subgraph check would miss this because there's no K5 subgraph.
  let edges = [
    (0, 5), (5, 1), // path replacing edge 0-1
    (0, 2), (0, 3), (0, 4),
    (1, 2), (1, 3), (1, 4),
    (2, 3), (2, 4),
    (3, 4),
  ]
  assert_false(is_planar(6, edges))
}

test "planar_test: K3,3 subdivision is not planar" {
  // K3,3 with one edge (0-3) replaced by path 0-6-3.
  // This is a subdivision of K3,3, so it's non-planar.
  let edges = [
    (0, 6), (6, 3), // path replacing edge 0-3
    (0, 4), (0, 5),
    (1, 3), (1, 4), (1, 5),
    (2, 3), (2, 4), (2, 5),
  ]
  assert_false(is_planar(7, edges))
}

test "planar_test: planar graph with degree-2 vertices" {
  // A square with a diagonal, plus some degree-2 vertices on edges.
  // This is planar.
  let edges = [
    (0, 1), (1, 2), (2, 3), (3, 0), // square
    (0, 2), // diagonal
    (1, 4), (4, 3), // path from 1 to 3 via 4
  ]
  assert_true(is_planar(5, edges))
}

test "planar_test: Petersen graph is not planar" {
  // Petersen graph: 10 vertices, 15 edges, non-planar.
  let edges = [
    (0, 1), (1, 2), (2, 3), (3, 4), (4, 0), // outer cycle
    (0, 5), (1, 6), (2, 7), (3, 8), (4, 9), // spokes
    (5, 7), (7, 9), (9, 6), (6, 8), (8, 5), // inner pentagram
  ]
  assert_false(is_planar(10, edges))
}

test "planar_test: triangular prism is planar" {
  // Triangular prism: 6 vertices, 9 edges, planar.
  let edges = [
    (0, 1), (1, 2), (2, 0), // top triangle
    (3, 4), (4, 5), (5, 3), // bottom triangle
    (0, 3), (1, 4), (2, 5), // vertical edges
  ]
  assert_true(is_planar(6, edges))
}

test "planar_test: disconnected planar graph" {
  let edges = [
    (0, 1), (1, 2), (2, 0), // triangle
    (3, 4), (4, 5), (5, 3), // another triangle
  ]
  assert_true(is_planar(6, edges))
}

test "planar_test: disconnected with non-planar component" {
  let edges = [
    (0, 1), (1, 2), (2, 0), // triangle (planar)
    (3, 4), (3, 5), (3, 6), (3, 7), // K5 part 1
    (4, 5), (4, 6), (4, 7),
    (5, 6), (5, 7),
    (6, 7),
  ]
  assert_false(is_planar(8, edges))
}
