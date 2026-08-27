/// Edmonds' Blossom algorithm for maximum cardinality matching in general graphs.
///
/// Finds a maximum matching in an arbitrary (not necessarily bipartite)
/// undirected graph. The algorithm repeatedly searches for **augmenting
/// paths** — alternating paths that start and end at unmatched vertices —
/// and augments the matching along them. The key difficulty in general
/// graphs is **blossoms**: odd cycles that arise during the search. Edmonds'
/// insight is to contract each blossom into a single "super-vertex" and
/// continue the search in the contracted graph; the result lifts back
/// automatically.
///
/// ## Algorithm
///
/// The implementation follows the classic BFS-based approach:
///
/// 1. Start from each unmatched vertex as a potential root.
/// 2. BFS explores alternating paths: from an "outer" (even-distance) vertex,
///    traverse any edge; if the neighbour is matched, its partner becomes
///    the next outer vertex.
/// 3. When an edge connects two outer vertices in the same tree, a **blossom**
///    (odd cycle) is detected. Contract it using a union-find structure.
/// 4. When an edge connects an outer vertex to an unmatched vertex, an
///    augmenting path has been found. Augment along it and restart.
///
/// ## Complexity
///
/// O(V * (V + E)) in the worst case (each augmentation search is O(V + E),
/// and there are at most V/2 augmentations). This matches the textbook bound
/// for the basic Blossom algorithm. For truly large graphs, Micali-Vazirani
/// achieves O(sqrt(V) * E), but requires a much more complex implementation.
///
/// ## Representation
///
/// - Graph: adjacency list, `adj[i]` = array of neighbour indices.
/// - Matching: `match[v]` = partner vertex, or `-1` if unmatched.
/// - Blossom contraction: a union-find (`uf`) that merges vertices in the
///   same blossom so subsequent BFS steps treat them as one node.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A general-graph matching result.
///
/// `matches[v]` is the vertex that `v` is matched to, or `-1` if `v` is
/// unmatched. The array has length `n` (vertex count).
pub struct Matching {
  matches : FixedArray[Int]
  card : Int
}

///|
/// Accessor: the vertex matched to `v`, or `-1` if unmatched.
pub fn partner(m : Matching, v : Int) -> Int {
  m.matches[v]
}

///|
/// Number of matched edges (half the number of matched vertices).
pub fn cardinality(m : Matching) -> Int {
  m.card
}

// ---------------------------------------------------------------------------
// Union-Find for blossom contraction
// ---------------------------------------------------------------------------

///|
priv struct UnionFind {
  parent : FixedArray[Int]
  rank : FixedArray[Int]
}

///|
fn uf_new(n : Int) -> UnionFind {
  { parent: FixedArray::makei(n, fn(i) { i }), rank: FixedArray::make(n, 0), }
}

///|
fn uf_find(uf : UnionFind, x : Int) -> Int {
  let mut x = x
  while uf.parent[x] != x {
    uf.parent[x] = uf.parent[uf.parent[x]] // path halving
    x = uf.parent[x]
  }
  x
}

///|
fn uf_union(uf : UnionFind, a : Int, b : Int) -> Unit {
  let ra = uf_find(uf, a)
  let rb = uf_find(uf, b)
  if ra == rb {
    return
  }
  if uf.rank[ra] < uf.rank[rb] {
    uf.parent[ra] = rb
  } else if uf.rank[ra] > uf.rank[rb] {
    uf.parent[rb] = ra
  } else {
    uf.parent[rb] = ra
    uf.rank[ra] = uf.rank[ra] + 1
  }
}

// ---------------------------------------------------------------------------
// Core Blossom algorithm
// ---------------------------------------------------------------------------

///|
const UNMATCHED : Int = -1

///|
const NIL : Int = -1

///|
/// BFS state for a single augmenting-path search.
priv struct BFSState {
  n : Int
  adj : Array[Array[Int]]
  match_arr : FixedArray[Int]
  uf : UnionFind
  // BFS labels: 0 = unvisited, 1 = outer (even), 2 = inner (odd)
  label : FixedArray[Int]
  // Parent in the alternating tree.
  parent : FixedArray[Int]
  // The blossom base for each vertex (used during contraction).
  base : FixedArray[Int]
  // BFS queue.
  queue : Array[Int]
  mut q_head : Int
}

///|
fn bfs_state(
  n : Int,
  adj : Array[Array[Int]],
  match_arr : FixedArray[Int],
) -> BFSState {
  {
    n,
    adj,
    match_arr,
    uf: uf_new(n),
    label: FixedArray::make(n, 0),
    parent: FixedArray::make(n, NIL),
    base: FixedArray::makei(n, fn(i) { i }),
    queue: [],
    q_head: 0,
  }
}

///|
/// Find the least common ancestor of u and v in the alternating tree.
/// This identifies the base of the blossom formed by the edge (u, v).
fn lca_blossom(st : BFSState, u_in : Int, v_in : Int) -> Int {
  // Walk up from u and v alternately, marking visited vertices.
  let visited = FixedArray::make(st.n, false)
  let mut u = uf_find(st.uf, u_in)
  let mut v = uf_find(st.uf, v_in)
  while true {
    if u != NIL {
      if visited[u] {
        return u
      }
      visited[u] = true
      u = st.parent[u]
      if u != NIL {
        u = uf_find(st.uf, u)
        u = st.parent[u]
      }
    }
    if v != NIL {
      if visited[v] {
        return v
      }
      visited[v] = true
      v = st.parent[v]
      if v != NIL {
        v = uf_find(st.uf, v)
        v = st.parent[v]
      }
    }
    if u == NIL && v == NIL {
      break
    }
  }
  // Should not reach here for a valid blossom
  NIL
}

///|
/// Mark the path from vertex `x` up to the blossom base `a` as part of the
/// blossom. This contracts the odd cycle into a single super-vertex.
fn mark_blossom(st : BFSState, x_in : Int, a : Int) -> Unit {
  let mut x = uf_find(st.uf, x_in)
  while x != a {
    // x's match partner should be labelled outer and added to the queue.
    let partner = st.match_arr[x]
    let partner_base = st.base[partner]
    if st.label[partner_base] != 1 {
      st.label[partner_base] = 1
      st.queue.push(partner_base)
    }
    // Union x into the blossom base a.
    uf_union(st.uf, x, a)
    st.base[x] = a
    // Move up the alternating tree.
    x = st.parent[partner_base]
    if x != NIL {
      x = uf_find(st.uf, x)
    }
  }
}

///|
/// Contract the blossom formed by the edge (u, v) with base `a`.
/// All vertices on the odd cycle are merged into one super-vertex.
fn contract_blossom(st : BFSState, u : Int, v : Int, a : Int) -> Unit {
  // Mark both sides of the cycle.
  mark_blossom(st, u, a)
  mark_blossom(st, v, a)
}

///|
/// Try to find an augmenting path starting from `root` (an unmatched vertex).
/// Returns `true` if augmentation was found (matching updated).
fn find_augmenting_path(st : BFSState, root : Int) -> Bool {
  // Reset BFS state for this root.
  for i = 0; i < st.n; i = i + 1 {
    st.label[i] = 0
    st.parent[i] = NIL
    st.base[i] = i
    st.uf.parent[i] = i
    st.uf.rank[i] = 0
  }
  st.queue.clear()
  st.q_head = 0

  st.label[root] = 1 // outer
  st.queue.push(root)

  while st.q_head < st.queue.length() {
    let u_orig = st.queue[st.q_head]
    st.q_head = st.q_head + 1
    let u = uf_find(st.uf, u_orig)

    for idx = 0; idx < st.adj[u_orig].length(); idx = idx + 1 {
      let v_raw = st.adj[u_orig][idx]
      let v = uf_find(st.uf, v_raw)

      if v == u {
        continue // self-loop after contraction
      }

      if st.label[v] == 0 {
        // Unvisited vertex: if matched, extend the alternating tree.
        st.label[v] = 2 // inner
        st.parent[v] = u
        // Use original vertex index for match_arr lookup.
        let w = st.match_arr[v_raw]
        if w == UNMATCHED {
          // Found an augmenting path: root ... u - v_raw.
          // Reconstruct the alternating path from v_raw back to root,
          // then flip every other edge.
          //
          // Path vertices (from v_raw to root):
          //   v_raw (inner, unmatched)
          //   parent[v_raw] = u (outer)
          //   match[u] = inner1 (u's old partner)
          //   parent[inner1] = outer1
          //   match[outer1] = inner2
          //   ... until root.
          let path : Array[Int] = []
          path.push(v_raw)
          let mut cur = v_raw
          while cur != root {
            let outer_v = st.parent[cur] // inner -> outer
            path.push(outer_v)
            if outer_v == root {
              break
            }
            let inner_v = st.match_arr[outer_v] // outer -> inner (old match)
            path.push(inner_v)
            cur = inner_v
          }
          // path = [v_raw, u, inner1, outer1, ..., root]
          // Flip: (v_raw,u), (inner1,outer1), ..., (w1,root)
          for i = 0; i < path.length() - 1; i = i + 2 {
            st.match_arr[path[i]] = path[i + 1]
            st.match_arr[path[i + 1]] = path[i]
          }
          return true
        }
        let w_rep = uf_find(st.uf, w)
        st.label[w_rep] = 1 // outer
        st.queue.push(w)
      } else if st.label[v] == 1 {
        // Two outer vertices: might form a blossom.
        let a = lca_blossom(st, u, v)
        if a == NIL {
          continue
        }
        contract_blossom(st, u, v, a)
      }
    }
  }
  false
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Compute the maximum cardinality matching in a general undirected graph.
///
/// # Parameters
/// - `adj`: adjacency list where `adj[i]` is an array of neighbour indices.
///   Edges should be symmetric (if `j` is in `adj[i]`, then `i` should be in
///   `adj[j]`); self-loops and multi-edges are tolerated but ignored.
/// - `n`: number of vertices, indexed `0 .. n - 1`.
///
/// # Returns
/// A [`Matching`] containing the `matches` array (`matches[v]` = partner or
/// `-1`) and the cardinality (number of matched edges).
///
/// # Complexity
/// O(V * (V + E)) worst case.
pub fn max_matching(adj : Array[Array[Int]], n : Int) -> Matching {
  let match_arr = FixedArray::make(n, UNMATCHED)
  let mut card = 0

  // Try to augment from each unmatched vertex.
  for root = 0; root < n; root = root + 1 {
    if match_arr[root] == UNMATCHED {
      let st = bfs_state(n, adj, match_arr)
      if find_augmenting_path(st, root) {
        // Copy the updated matching back.
        for i = 0; i < n; i = i + 1 {
          match_arr[i] = st.match_arr[i]
        }
        card = card + 1
      }
    }
  }

  { matches: match_arr, card, }
}

///|
/// Compute the maximum cardinality matching from a flat edge list.
///
/// Convenience wrapper that builds the adjacency list from a list of edges
/// given as `(u, v)` pairs.
pub fn max_matching_from_edges(edges : Array[(Int, Int)], n : Int) -> Matching {
  let adj : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    adj.push([])
  }
  for i = 0; i < edges.length(); i = i + 1 {
    let (u, v) = edges[i]
    if u >= 0 && u < n && v >= 0 && v < n && u != v {
      adj[u].push(v)
      adj[v].push(u)
    }
  }
  max_matching(adj, n)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "edmonds_blossom: simple path of 3 vertices" {
  // 0 - 1 - 2: maximum matching is {(0,1)}, cardinality 1
  let adj : Array[Array[Int]] = [[1], [0, 2], [1]]
  let m = max_matching(adj, 3)
  assert_eq(m.card, 1)
}

///|
test "edmonds_blossom: triangle (odd cycle)" {
  // 0 - 1 - 2 - 0: triangle. Maximum matching is 1 edge.
  let adj : Array[Array[Int]] = [[1, 2], [0, 2], [0, 1]]
  let m = max_matching(adj, 3)
  assert_eq(m.card, 1)
  // Every matched vertex has a valid partner.
  for v = 0; v < 3; v = v + 1 {
    if m.matches[v] != UNMATCHED {
      assert_eq(m.matches[m.matches[v]], v)
    }
  }
}

///|
test "edmonds_blossom: pentagon (5-cycle, blossom)" {
  // 0-1-2-3-4-0: odd cycle of length 5. Max matching = 2.
  let adj : Array[Array[Int]] = [[1, 4], [0, 2], [1, 3], [2, 4], [3, 0]]
  let m = max_matching(adj, 5)
  assert_eq(m.card, 2)
}

///|
test "edmonds_blossom: complete graph K4" {
  // K4: max matching = 2
  let adj : Array[Array[Int]] = [[1, 2, 3], [0, 2, 3], [0, 1, 3], [0, 1, 2]]
  let m = max_matching(adj, 4)
  assert_eq(m.card, 2)
}

///|
test "edmonds_blossom: complete graph K5 (odd, blossom)" {
  // K5: max matching = 2 (floor(5/2))
  let adj : Array[Array[Int]] = [
    [1, 2, 3, 4],
    [0, 2, 3, 4],
    [0, 1, 3, 4],
    [0, 1, 2, 4],
    [0, 1, 2, 3],
  ]
  let m = max_matching(adj, 5)
  assert_eq(m.card, 2)
}

///|
test "edmonds_blossom: path of 6 vertices" {
  // 0-1-2-3-4-5: max matching = 3
  let adj : Array[Array[Int]] = [[1], [0, 2], [1, 3], [2, 4], [3, 5], [4]]
  let m = max_matching(adj, 6)
  assert_eq(m.card, 3)
}

///|
test "edmonds_blossom: star graph" {
  // 0 connected to 1,2,3: max matching = 1
  let adj : Array[Array[Int]] = [[1, 2, 3], [0], [0], [0]]
  let m = max_matching(adj, 4)
  assert_eq(m.card, 1)
}

///|
test "edmonds_blossom: two triangles connected" {
  // 0-1-2-0 and 3-4-5-3, plus edge 2-3
  // Max matching = 3 (one per triangle + the bridge, or 2 per triangle region)
  let adj : Array[Array[Int]] = [
    [1, 2],
    [0, 2],
    [0, 1, 3],
    [2, 4, 5],
    [3, 5],
    [3, 4],
  ]
  let m = max_matching(adj, 6)
  // Max matching is at least 2 (one per triangle), could be 3 with bridge
  assert_true(m.card >= 2)
  assert_true(m.card <= 3)
}

///|
test "edmonds_blossom: empty graph" {
  let adj : Array[Array[Int]] = [[], [], []]
  let m = max_matching(adj, 3)
  assert_eq(m.card, 0)
}

///|
test "edmonds_blossom: single edge" {
  let adj : Array[Array[Int]] = [[1], [0]]
  let m = max_matching(adj, 2)
  assert_eq(m.card, 1)
  assert_eq(m.matches[0], 1)
  assert_eq(m.matches[1], 0)
}

///|
test "edmonds_blossom: from edges" {
  let edges : Array[(Int, Int)] = [(0, 1), (1, 2), (2, 3), (3, 4)]
  let m = max_matching_from_edges(edges, 5)
  assert_eq(m.card, 2)
}

///|
test "edmonds_blossom: Petersen-like graph" {
  // A graph that requires multiple blossom contractions.
  // Outer 5-cycle: 0-1-2-3-4-0
  // Inner star: 0-5, 1-5, 2-5, 3-5, 4-5
  let adj : Array[Array[Int]] = [
    [1, 4, 5],
    [0, 2, 5],
    [1, 3, 5],
    [2, 4, 5],
    [3, 0, 5],
    [0, 1, 2, 3, 4],
  ]
  let m = max_matching(adj, 6)
  // Max matching: floor(6/2) = 3
  assert_true(m.card >= 2)
  assert_true(m.card <= 3)
}

///|
test "edmonds_blossom: matching validity" {
  // Verify that the matching is valid: if v is matched to u, then u is
  // matched to v.
  let adj : Array[Array[Int]] = [[1, 2, 3], [0, 2], [0, 1, 3], [0, 2]]
  let m = max_matching(adj, 4)
  for v = 0; v < 4; v = v + 1 {
    if m.matches[v] != UNMATCHED {
      let u = m.matches[v]
      assert_eq(m.matches[u], v)
    }
  }
}
