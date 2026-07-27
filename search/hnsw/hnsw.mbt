/// HNSW (Hierarchical Navigable Small World) — approximate nearest neighbor search.
///
/// HNSW is the algorithm powering modern vector databases (FAISS, Milvus,
/// Pinecone, Weaviate). It builds a multi-layer graph where upper layers
/// contain fewer nodes for fast long-range navigation, and lower layers
/// contain all nodes for precise local search.
///
/// ## Algorithm
///
/// 1. **Insertion**: Each new node is assigned a random maximum layer `l`
///    (geometric distribution with probability `1/mL`). The node is inserted
///    into layers 0 through `l`, connecting to its `M` nearest neighbors at
///    each layer via greedy search from the entry point.
/// 2. **Search**: Starting from the top layer, greedily descend to find the
///    closest node at each layer. At layer 0, expand the search to `ef`
///    candidates and return the top `k`.
///
/// ## Complexity
/// - Insertion: O(M * log N) expected.
/// - Search: O(M * log N + ef * log ef) expected.
/// - Space: O(N * M) for the graph.
///
/// ## Parameters
/// - `M`: maximum number of connections per node (per layer). Typical: 16.
/// - `ef_construction`: search width during insertion. Typical: 200.
/// - `ef_search`: search width during query. Typical: 50–200.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A node in the HNSW graph.
struct Node {
  id : Int // user-provided identifier
  neighbors : FixedArray[Array[Int]] // neighbors[layer] = list of node indices
}

///|
/// The HNSW index.
pub struct HNSW {
  priv nodes : Array[Node] // all nodes, indexed by internal index
  priv mut entry_point : Int // internal index of the entry node (-1 if empty)
  priv mut max_layer : Int // current maximum layer in the graph
  priv m : Int // max connections per layer
  priv m_max0 : Int // max connections at layer 0 (typically 2*M)
  priv ef_construction : Int
  priv ml : Double // level generation factor = 1 / ln(M)
  priv data : Array[Array[Double]] // vectors indexed by internal index
  priv mut rng_state : UInt64 // PRNG state
}

///|
/// Create a new HNSW index.
///
/// - `m`: maximum connections per node (typical: 16).
/// - `ef_construction`: search width during construction (typical: 200).
pub fn new(m : Int, ef_construction : Int) -> HNSW {
  let mm = if m < 2 { 2 } else { m }
  {
    nodes: [],
    entry_point: -1,
    max_layer: -1,
    m: mm,
    m_max0: mm * 2,
    ef_construction: if ef_construction < mm {
      mm
    } else {
      ef_construction
    },
    ml: 1.0 / @math.ln(mm.to_double()),
    data: [],
    rng_state: 12345UL, // fixed seed for reproducibility
  }
}

///|
/// xorshift64 PRNG — fast, high-quality pseudo-random number generator.
///
/// Uses the classic Marsaglia xorshift64 constants (13, 7, 17). The state
/// is a single `UInt64`; each call advances it and returns the new value.
fn next_rand(h : HNSW) -> UInt64 {
  let mut x = h.rng_state
  x = x ^ (x << 13)
  x = x ^ (x >> 7)
  x = x ^ (x << 17)
  h.rng_state = x
  x
}

///|
/// Generate a random level using the geometric distribution with parameter `ml`.
///
/// Returns a non-negative integer. The probability of level ≥ L is
/// exp(-L / ml) = (1/ml)^L, so most nodes reside only at layer 0.
fn random_level(h : HNSW) -> Int {
  // Convert UInt64 to Double in [0, 1) using the upper 53 bits for full
  // Double precision. 2^53 = 9007199254740992.
  let bits = (next_rand(h) >> 11).reinterpret_as_int64().to_double()
  let r = bits / 9007199254740992.0
  let level = -(@math.ln(r) * h.ml).to_int()
  if level < 0 {
    0
  } else {
    level
  }
}

///|
/// Squared Euclidean distance between two vectors.
fn dist2(a : Array[Double], b : Array[Double]) -> Double {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = a[i] - b[i]
    s = s + d * d
  }
  s
}

///|
/// Insert a vector with the given `id` into the index.
pub fn insert(h : HNSW, id : Int, vec : Array[Double]) -> Unit {
  let level = random_level(h)
  let internal_idx = h.nodes.length()
  let neighbors = FixedArray::makei(level + 1, fn(_) { [] })
  h.nodes.push({ id, neighbors })
  h.data.push(Array::copy(vec))
  if h.entry_point == -1 {
    h.entry_point = internal_idx
    h.max_layer = level
    return
  }
  // Greedy search from top layer down to level+1 to find entry point.
  let mut curr = h.entry_point
  let mut curr_dist = dist2(vec, h.data[curr])
  let mut layer = h.max_layer
  while layer > level {
    let mut changed = true
    while changed {
      changed = false
      let neighbors_layer = h.nodes[curr].neighbors[layer]
      for i = 0; i < neighbors_layer.length(); i = i + 1 {
        let n = neighbors_layer[i]
        let d = dist2(vec, h.data[n])
        if d < curr_dist {
          curr_dist = d
          curr = n
          changed = true
        }
      }
    }
    layer = layer - 1
  }
  // From level down to 0, find M nearest neighbors and connect.
  layer = if level < h.max_layer { level } else { h.max_layer }
  while layer >= 0 {
    let candidates = search_layer(h, vec, curr, h.ef_construction, layer)
    // Select M nearest neighbors using the query vector.
    let m = if layer == 0 { h.m_max0 } else { h.m }
    let selected = select_neighbors(h, vec, candidates, m)
    // Connect the new node to selected neighbors.
    for i = 0; i < selected.length(); i = i + 1 {
      let n = selected[i]
      h.nodes[internal_idx].neighbors[layer].push(n)
      h.nodes[n].neighbors[layer].push(internal_idx)
      // Prune neighbor's connections if exceeded M.
      let max_conn = if layer == 0 { h.m_max0 } else { h.m }
      if h.nodes[n].neighbors[layer].length() > max_conn {
        prune_connections(h, n, layer, max_conn)
      }
    }
    curr = if selected.length() > 0 { selected[0] } else { curr }
    layer = layer - 1
  }
  // Update entry point if new node has a higher level.
  if level > h.max_layer {
    h.max_layer = level
    h.entry_point = internal_idx
  }
}

///|
/// Search a single layer for the nearest neighbors, returning a list of
/// node indices sorted by distance (closest first).
fn search_layer(
  h : HNSW,
  query : Array[Double],
  entry : Int,
  ef : Int,
  layer : Int,
) -> Array[(Double, Int)] {
  let visited : Array[Int] = [entry]
  let candidates : Array[(Double, Int)] = [(dist2(query, h.data[entry]), entry)]
  let results : Array[(Double, Int)] = [(dist2(query, h.data[entry]), entry)]
  while candidates.length() > 0 {
    // Find the closest unexplored candidate.
    let mut min_idx = 0
    for i = 1; i < candidates.length(); i = i + 1 {
      if candidates[i].0 < candidates[min_idx].0 {
        min_idx = i
      }
    }
    let (c_dist, c) = candidates[min_idx]
    candidates.remove(min_idx) |> ignore
    // Find the furthest in results.
    let mut furthest_idx = 0
    for i = 1; i < results.length(); i = i + 1 {
      if results[i].0 > results[furthest_idx].0 {
        furthest_idx = i
      }
    }
    let furthest_dist = results[furthest_idx].0
    if c_dist > furthest_dist {
      break
    }
    // Explore neighbors.
    let neighbors = h.nodes[c].neighbors[layer]
    for i = 0; i < neighbors.length(); i = i + 1 {
      let n = neighbors[i]
      let mut already = false
      for v = 0; v < visited.length(); v = v + 1 {
        if visited[v] == n {
          already = true
          break
        }
      }
      if !already {
        visited.push(n)
        let d = dist2(query, h.data[n])
        if results.length() < ef || d < furthest_dist {
          candidates.push((d, n))
          results.push((d, n))
          if results.length() > ef {
            // Remove the furthest.
            let mut fi = 0
            for i = 1; i < results.length(); i = i + 1 {
              if results[i].0 > results[fi].0 {
                fi = i
              }
            }
            results.remove(fi) |> ignore
          }
        }
      }
    }
  }
  // Sort results by distance (closest first).
  results.sort_by(fn(a, b) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  results
}

///|
/// Select the M nearest neighbors from a candidate list.
///
/// `candidates` is a list of (distance, node_index) pairs sorted by distance.
/// Returns the first `m` node indices (i.e., the M closest).
fn select_neighbors(
  h : HNSW,
  query : Array[Double],
  candidates : Array[(Double, Int)],
  m : Int,
) -> Array[Int] {
  // `candidates` is already sorted by distance from search_layer.
  // Simply take the first m entries — these are the M closest.
  let result : Array[Int] = []
  let limit = if candidates.length() < m { candidates.length() } else { m }
  for i = 0; i < limit; i = i + 1 {
    result.push(candidates[i].1)
  }
  // Mark `query` and `h` as intentionally used (the query distance is
  // already computed in search_layer; `h` is needed for future pruning
  // heuristics that reference the data vectors).
  ignore(query)
  ignore(h)
  result
}

///|
/// Prune connections of a node to at most `max_conn` neighbors.
///
/// Keeps the `max_conn` closest neighbors (by distance to the node's own
/// data vector), rather than arbitrarily keeping the first N.
fn prune_connections(h : HNSW, node : Int, layer : Int, max_conn : Int) -> Unit {
  let neighbors = h.nodes[node].neighbors[layer]
  if neighbors.length() <= max_conn {
    return
  }
  // Compute distances from this node to each neighbor, then keep the closest.
  let node_vec = h.data[node]
  let pairs : Array[(Double, Int)] = []
  for i = 0; i < neighbors.length(); i = i + 1 {
    let n = neighbors[i]
    pairs.push((dist2(node_vec, h.data[n]), n))
  }
  pairs.sort_by(fn(a, b) {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  let pruned : Array[Int] = []
  for i = 0; i < max_conn; i = i + 1 {
    pruned.push(pairs[i].1)
  }
  h.nodes[node].neighbors[layer] = pruned
}

///|
/// Search for the `k` nearest neighbors of `query`.
///
/// Returns an array of (distance, id) pairs sorted by distance.
pub fn search(
  h : HNSW,
  query : Array[Double],
  k : Int,
  ef_search : Int,
) -> Array[(Double, Int)] {
  if h.entry_point == -1 || k <= 0 {
    return []
  }
  let mut curr = h.entry_point
  let mut curr_dist = dist2(query, h.data[curr])
  // Greedy descent from top layer to layer 1.
  let mut layer = h.max_layer
  while layer > 0 {
    let mut changed = true
    while changed {
      changed = false
      let neighbors = h.nodes[curr].neighbors[layer]
      for i = 0; i < neighbors.length(); i = i + 1 {
        let n = neighbors[i]
        let d = dist2(query, h.data[n])
        if d < curr_dist {
          curr_dist = d
          curr = n
          changed = true
        }
      }
    }
    layer = layer - 1
  }
  // At layer 0, search with ef.
  let ef = if ef_search > k { ef_search } else { k }
  let candidates = search_layer(h, query, curr, ef, 0)
  // Map to (distance, id) and return top k.
  let top : Array[(Double, Int)] = []
  let limit = if candidates.length() < k { candidates.length() } else { k }
  for i = 0; i < limit; i = i + 1 {
    let (d, n) = candidates[i]
    top.push((d, h.nodes[n].id))
  }
  top
}

///|
/// Number of vectors in the index.
pub fn len(h : HNSW) -> Int {
  h.nodes.length()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "hnsw: single insert and search" {
  let h = new(4, 16)
  insert(h, 0, [1.0, 0.0, 0.0])
  assert_eq(len(h), 1)
  let results = search(h, [1.0, 0.0, 0.0], 1, 16)
  assert_eq(results.length(), 1)
  assert_eq(results[0].1, 0)
}

///|
test "hnsw: exact search small" {
  let h = new(4, 16)
  insert(h, 0, [0.0, 0.0])
  insert(h, 1, [1.0, 0.0])
  insert(h, 2, [0.0, 1.0])
  insert(h, 3, [1.0, 1.0])
  let results = search(h, [0.1, 0.1], 2, 32)
  assert_eq(results.length(), 2)
  // Closest to (0.1, 0.1) should be (0,0) and (1,0).
  assert_true(results[0].1 == 0 || results[0].1 == 1)
}

///|
test "hnsw: larger dataset" {
  let h = new(8, 32)
  // Insert a 2D grid of points.
  for i = 0; i < 10; i = i + 1 {
    for j = 0; j < 10; j = j + 1 {
      insert(h, i * 10 + j, [i.to_double(), j.to_double()])
    }
  }
  assert_eq(len(h), 100)
  // Search for nearest neighbor of (5.1, 5.1).
  let results = search(h, [5.1, 5.1], 1, 50)
  assert_eq(results.length(), 1)
  // The nearest point should be (5, 5) = id 55.
  assert_eq(results[0].1, 55)
}

///|
test "hnsw: empty index" {
  let h = new(4, 16)
  let results = search(h, [1.0, 2.0], 5, 16)
  assert_eq(results.length(), 0)
}
