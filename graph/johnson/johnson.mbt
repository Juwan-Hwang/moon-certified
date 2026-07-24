/// Johnson's all-pairs shortest paths algorithm.
///
/// Computes the shortest path between every pair of vertices in a weighted
/// directed graph, including graphs with negative edge weights (but no
/// negative-weight cycles).
///
/// The graph is an adjacency list: `graph[i]` is an `Array` of `(neighbor,
/// weight)` pairs, so `graph[i][j] = (v, w)` means a directed edge `i -> v`
/// with weight `w`. For undirected graphs, add each edge in both directions.
///
/// ## Algorithm
///
/// Johnson's algorithm combines Bellman-Ford and Dijkstra:
///   1. Add a virtual source `s` with a zero-weight edge to every vertex, then
///      run Bellman-Ford from `s` to compute vertex potentials `h[v]`.
///      (Equivalently — and as done here — initialize every `h[v] = 0`, which
///      is exactly the state after relaxing `s`'s edges.) Run `n` relaxation
///      passes — the virtual vertex makes `n + 1` vertices, so `|V| - 1 = n`
///      passes reach the shortest paths — then one more pass to detect a
///      negative cycle.
///   2. If a negative cycle exists, return an empty matrix.
///   3. Reweight every edge: `w'(u, v) = w(u, v) + h[u] - h[v]`. The
///      Bellman-Ford optimality condition `h[v] <= h[u] + w(u, v)` guarantees
///      `w' >= 0`, so Dijkstra is now correct.
///   4. Run Dijkstra from every vertex on the reweighted graph, then undo the
///      reweighting: `d(u, v) = d'(u, v) - h[u] + h[v]`.
///
/// ## Returns
///
/// `result[i][j]` is `Some(d)` if `j` is reachable from `i` with shortest
/// distance `d`, or `None` if unreachable. The diagonal `result[i][i]` is
/// `Some(0)` when no negative cycle passes through `i`. An empty matrix (zero
/// rows) is returned when a negative-weight cycle is detected or the input is
/// invalid (`n <= 0`, `graph` too small).
///
/// ## Complexity
///
/// - Bellman-Ford: `O(V * E)`.
/// - Dijkstra (binary heap) from each vertex: `O(V * E log V)`.
/// - Total with a binary heap: `O(V * E log V)`. With a Fibonacci heap the
///   Dijkstra phase drops to `O(V^2 log V + V * E)`.
///
/// ## Limitations
///
/// - Negative-weight cycles cause an empty result (they are detected, not
///   solved).
/// - Distance accumulation uses 64-bit `Int64` arithmetic internally to
///   prevent overflow. Final results are converted back to 32-bit `Int`:
///   if a distance exceeds `Int` range, `None` is returned for that pair.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Sentinel for "infinity" in distance arrays (Int64).
const J_INF : Int64 = 9223372036854775807L

/// A min-heap entry: (reweighted distance, vertex).
priv struct JHeapEntry {
  dist : Int64
  vertex : Int
}

/// Binary min-heap keyed on `dist`, stored in a flat `Array` using the standard
/// 0-indexed layout: parent of `i` is `(i-1)/2`, children are `2i+1` and `2i+2`.
priv struct JMinHeap {
  data : Array[JHeapEntry]
}

fn JMinHeap::new() -> JMinHeap {
  { data: [] }
}

fn JMinHeap::len(heap : JMinHeap) -> Int {
  heap.data.length()
}

/// Insert a (dist, vertex) pair; sifts up to restore the heap property. O(log n).
fn JMinHeap::push(heap : JMinHeap, dist : Int64, vertex : Int) -> Unit {
  heap.data.push({ dist, vertex })
  let mut i = heap.data.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if heap.data[i].dist < heap.data[parent].dist {
      let tmp = heap.data[i]
      heap.data[i] = heap.data[parent]
      heap.data[parent] = tmp
      i = parent
    } else {
      break
    }
  }
}

/// Remove and return the minimum entry, or `None` if empty; sifts down. O(log n).
fn JMinHeap::pop(heap : JMinHeap) -> JHeapEntry? {
  let n = heap.data.length()
  if n == 0 {
    return None
  }
  let result = heap.data[0]
  // Move the last element to the root, then sift down.
  heap.data[0] = heap.data[n - 1]
  let _ = heap.data.pop()
  let len = heap.data.length()
  let mut i = 0
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut smallest = i
    if left < len && heap.data[left].dist < heap.data[smallest].dist {
      smallest = left
    }
    if right < len && heap.data[right].dist < heap.data[smallest].dist {
      smallest = right
    }
    if smallest != i {
      let tmp = heap.data[i]
      heap.data[i] = heap.data[smallest]
      heap.data[smallest] = tmp
      i = smallest
    } else {
      break
    }
  }
  Some(result)
}

/// Run Bellman-Ford with all potentials initialized to 0. This is equivalent to
/// adding a virtual source with a zero-weight edge to every vertex (relaxing
/// those edges sets every `h[v]` to 0). Fills `h` with the vertex potentials.
/// Returns `true` if a negative-weight cycle is detected.
///
/// With the virtual source there are `n + 1` vertices, so `n` relaxation passes
/// reach the shortest paths; one extra pass detects a negative cycle.
fn bellman_ford_potentials(
  graph : Array[Array[(Int, Int)]],
  n : Int,
  h : FixedArray[Int64],
) -> Bool {
  // n relaxation passes (|V| - 1 with the virtual vertex).
  for iter = 0; iter < n; iter = iter + 1 {
    for u = 0; u < n; u = u + 1 {
      let neighbors = graph[u]
      for j = 0; j < neighbors.length(); j = j + 1 {
        let (v, w) = neighbors[j]
        if v >= 0 && v < n {
          // h[u] is always finite: it starts at 0 and only ever decreases.
          let nd = h[u] + w.to_int64()
          if nd < h[v] {
            h[v] = nd
          }
        }
      }
    }
  }
  // Detection pass: if any edge can still relax, a negative cycle exists.
  for u = 0; u < n; u = u + 1 {
    let neighbors = graph[u]
    for j = 0; j < neighbors.length(); j = j + 1 {
      let (v, w) = neighbors[j]
      if v >= 0 && v < n {
        if h[u] + w.to_int64() < h[v] {
          return true
        }
      }
    }
  }
  false
}

/// Dijkstra from `src` on the reweighted graph. Edge weights are computed on
/// the fly as `w + h[u] - h[v]`, which are non-negative by the potential
/// property, so Dijkstra is valid. Lazy deletion skips stale heap entries.
///
/// Returns the real (un-reweighted) shortest distances as `Int?`, where `None`
/// means unreachable.
fn dijkstra_reweighted(
  graph : Array[Array[(Int, Int)]],
  n : Int,
  src : Int,
  h : FixedArray[Int64],
) -> FixedArray[Int?] {
  let dist = FixedArray::make(n, J_INF) // reweighted distances (Int64)
  let visited = FixedArray::make(n, false)
  dist[src] = 0L
  let heap = JMinHeap::new()
  JMinHeap::push(heap, 0L, src)
  while JMinHeap::len(heap) > 0 {
    match JMinHeap::pop(heap) {
      Some({ dist: d, vertex: u }) =>
        if !visited[u] {
          visited[u] = true
          let neighbors = graph[u]
          for j = 0; j < neighbors.length(); j = j + 1 {
            let (v, w) = neighbors[j]
            if v >= 0 && v < n && !visited[v] {
              // Reweighted cost: w + h[u] - h[v] >= 0.
              let rw = w.to_int64() + h[u] - h[v]
              let nd = d + rw
              if nd < dist[v] {
                dist[v] = nd
                JMinHeap::push(heap, nd, v)
              }
            }
          }
        }
      None => break
    }
  }
  // Undo the reweighting: d(u, v) = d'(u, v) - h[u] + h[v].
  // Convert Int64 back to Int, returning None for overflow.
  let result : FixedArray[Int?] = FixedArray::make(n, None)
  for v = 0; v < n; v = v + 1 {
    if dist[v] != J_INF {
      let real_dist = dist[v] - h[src] + h[v]
      if real_dist > 2147483647L || real_dist < -2147483648L {
        result[v] = None // overflow: distance exceeds Int range
      } else {
        result[v] = Some(real_dist.to_int())
      }
    }
  }
  result
}

/// An empty distance matrix, returned for a negative cycle or invalid input.
fn empty_matrix() -> FixedArray[FixedArray[Int?]] {
  let inner : FixedArray[Int?] = FixedArray::make(0, None)
  FixedArray::make(0, inner)
}

/// Compute all-pairs shortest paths using Johnson's algorithm.
///
/// `graph[i]` is an `Array` of `(neighbor, weight)` pairs. Returns an `n x n`
/// matrix where `result[i][j]` is `Some(d)` (shortest distance) or `None`
/// (unreachable). Returns an empty matrix (zero rows) if a negative-weight
/// cycle is detected or the input is invalid.
pub fn johnson(
  graph : Array[Array[(Int, Int)]],
  n : Int,
) -> FixedArray[FixedArray[Int?]] {
  if n <= 0 || graph.length() < n {
    return empty_matrix()
  }
  // Step 1: Bellman-Ford potentials (init-to-0 stands in for the virtual source).
  let h = FixedArray::make(n, 0L)
  if bellman_ford_potentials(graph, n, h) {
    return empty_matrix() // negative-weight cycle detected
  }
  // Steps 2-4: Dijkstra from every vertex on the reweighted graph.
  FixedArray::makei(n, fn(src) { dijkstra_reweighted(graph, n, src, h) })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "johnson: basic weighted graph" {
  // Undirected weighted graph:
  //   0 --1-- 1 --2-- 2 --3-- 3
  //   `----------10------------'
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[1].push((0, 1))
  graph[1].push((2, 2))
  graph[2].push((1, 2))
  graph[2].push((3, 3))
  graph[3].push((2, 3))
  graph[0].push((3, 10))
  graph[3].push((0, 10))
  let d = johnson(graph, n)
  assert_eq(d.length(), n)
  // Row 0: 0->1=1, 0->1->2=3, 0->1->2->3=6 (beats direct 0->3=10)
  assert_eq(d[0][0], Some(0))
  assert_eq(d[0][1], Some(1))
  assert_eq(d[0][2], Some(3))
  assert_eq(d[0][3], Some(6))
  // Row 1
  assert_eq(d[1][0], Some(1))
  assert_eq(d[1][1], Some(0))
  assert_eq(d[1][2], Some(2))
  assert_eq(d[1][3], Some(5))
  // Row 2
  assert_eq(d[2][0], Some(3))
  assert_eq(d[2][1], Some(2))
  assert_eq(d[2][2], Some(0))
  assert_eq(d[2][3], Some(3))
  // Row 3
  assert_eq(d[3][0], Some(6))
  assert_eq(d[3][1], Some(5))
  assert_eq(d[3][2], Some(3))
  assert_eq(d[3][3], Some(0))
}

test "johnson: negative weights, no negative cycle" {
  // Directed graph with a negative edge (1 -> 2 : -3) but no cycle at all.
  //   0 ->1-> 5      0 ->2-> 2
  //   1 ->2-> -3     1 ->3-> 2
  //   2 ->3-> 1
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 5))
  graph[0].push((2, 2))
  graph[1].push((2, -3))
  graph[2].push((3, 1))
  graph[1].push((3, 2))
  let d = johnson(graph, n)
  assert_eq(d.length(), n)
  // Row 0
  assert_eq(d[0][0], Some(0))
  assert_eq(d[0][1], Some(5))
  assert_eq(d[0][2], Some(2)) // 0->2 = 2, ties 0->1->2 = 5-3 = 2
  assert_eq(d[0][3], Some(3)) // 0->2->3 = 2+1 = 3
  // Row 1
  assert_true(d[1][0] is None)
  assert_eq(d[1][1], Some(0))
  assert_eq(d[1][2], Some(-3))
  assert_eq(d[1][3], Some(-2)) // 1->2->3 = -3+1 = -2 (beats 1->3 = 2)
  // Row 2
  assert_true(d[2][0] is None)
  assert_true(d[2][1] is None)
  assert_eq(d[2][2], Some(0))
  assert_eq(d[2][3], Some(1))
  // Row 3
  assert_true(d[3][0] is None)
  assert_true(d[3][1] is None)
  assert_true(d[3][2] is None)
  assert_eq(d[3][3], Some(0))
}

test "johnson: no path between some vertices" {
  // Directed chain 0 -> 1 -> 2, vertex 3 isolated.
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[1].push((2, 1))
  let d = johnson(graph, n)
  assert_eq(d[0][0], Some(0))
  assert_eq(d[0][1], Some(1))
  assert_eq(d[0][2], Some(2))
  assert_true(d[0][3] is None)
  assert_true(d[1][0] is None)
  assert_eq(d[1][2], Some(1))
  assert_true(d[2][0] is None)
  assert_true(d[3][0] is None)
  assert_eq(d[3][3], Some(0))
}

test "johnson: single node" {
  let graph : Array[Array[(Int, Int)]] = [[]]
  let d = johnson(graph, 1)
  assert_eq(d.length(), 1)
  assert_eq(d[0][0], Some(0))
}

test "johnson: disconnected graph" {
  // Two undirected components: {0,1} and {2,3}.
  let n = 4
  let graph : Array[Array[(Int, Int)]] = [[], [], [], []]
  graph[0].push((1, 1))
  graph[1].push((0, 1))
  graph[2].push((3, 1))
  graph[3].push((2, 1))
  let d = johnson(graph, n)
  assert_eq(d[0][0], Some(0))
  assert_eq(d[0][1], Some(1))
  assert_true(d[0][2] is None)
  assert_true(d[0][3] is None)
  assert_eq(d[2][2], Some(0))
  assert_eq(d[2][3], Some(1))
  assert_true(d[2][0] is None)
  assert_eq(d[3][3], Some(0))
}

test "johnson: negative cycle detection" {
  // 0 ->1-> 1, 1 ->2-> -3, 2 ->0-> 1  =>  cycle sum = -1 < 0.
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 1))
  graph[1].push((2, -3))
  graph[2].push((0, 1))
  let d = johnson(graph, n)
  // A negative cycle yields an empty matrix.
  assert_eq(d.length(), 0)
}

test "johnson: zero-weight cycle is not negative" {
  // 0 ->1-> 1, 1 ->2-> -1, 2 ->0-> 0  =>  cycle sum = 0 (allowed).
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 1))
  graph[1].push((2, -1))
  graph[2].push((0, 0))
  let d = johnson(graph, n)
  assert_eq(d.length(), n) // not empty: no negative cycle
  assert_eq(d[0][0], Some(0))
  assert_eq(d[0][1], Some(1))
  assert_eq(d[0][2], Some(0)) // 0->1->2 = 1 + (-1) = 0, ties 0->...->2
  assert_eq(d[1][2], Some(-1))
}

test "johnson: diagonal is zero and negative edges respected" {
  // Directed acyclic graph with a negative edge (acyclic => no negative cycle).
  //   0 ->1-> 2     0 ->2-> 5     1 ->2-> -1
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 2))
  graph[0].push((2, 5))
  graph[1].push((2, -1))
  let d = johnson(graph, n)
  assert_eq(d.length(), n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(d[i][i], Some(0))
  }
  assert_eq(d[0][1], Some(2))
  assert_eq(d[0][2], Some(1)) // 0->1->2 = 2 + (-1) = 1 (beats 0->2 = 5)
  assert_eq(d[1][2], Some(-1))
  assert_true(d[1][0] is None)
  assert_true(d[2][0] is None)
}

test "johnson: invalid input returns empty matrix" {
  let graph : Array[Array[(Int, Int)]] = []
  assert_eq(johnson(graph, 0).length(), 0)
  assert_eq(johnson(graph, -1).length(), 0)
  // graph too small for n
  let small : Array[Array[(Int, Int)]] = [[]]
  assert_eq(johnson(small, 3).length(), 0)
}

test "johnson: complete graph K4 with unit weights" {
  let n = 4
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        graph[i].push((j, 1))
      }
    }
  }
  let d = johnson(graph, n)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i == j {
        assert_eq(d[i][j], Some(0))
      } else {
        assert_eq(d[i][j], Some(1))
      }
    }
  }
}

test "johnson: chain 30 nodes directed" {
  let n = 30
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  for i = 0; i < n - 1; i = i + 1 {
    graph[i].push((i + 1, 1))
  }
  let d = johnson(graph, n)
  // Only forward paths exist.
  assert_eq(d[0][29], Some(29))
  assert_eq(d[5][10], Some(5))
  assert_true(d[10][5] is None)
  assert_eq(d[29][29], Some(0))
}
