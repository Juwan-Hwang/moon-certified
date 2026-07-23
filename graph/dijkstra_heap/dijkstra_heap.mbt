/// Heap-optimized Dijkstra's shortest path algorithm for sparse graphs.
///
/// Uses an adjacency list representation: `graph[i]` is an array of
/// `(neighbor, weight)` pairs. This is more efficient than the adjacency
/// matrix version for sparse graphs: O((V + E) log V) vs O(V²).
///
/// The priority queue is a binary min-heap of `(distance, vertex)` pairs.
/// Lazy deletion is used: when a vertex is popped with a stale distance
/// (greater than the current known distance), it is simply skipped rather
/// than performing an expensive decrease-key operation.
///
/// Returns a `FixedArray[Int?]` where `result[i]` is `Some(d)` if vertex `i`
/// is reachable from `src` with shortest distance `d`, or `None` if unreachable.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.
///
/// Time complexity: O((V + E) log V)
///
/// **Precondition**: All edge weights must be non-negative. Dijkstra's
/// algorithm does not produce correct results with negative weights.
/// Unlike the adjacency-matrix version, negative weights in the adjacency
/// list are processed (not skipped), which can produce incorrect shortest
/// paths. For graphs with negative weights, use Bellman-Ford
/// (`graph/advanced`) or Johnson's algorithm (`graph/johnson`) instead.
///
/// **Overflow protection**: distances are accumulated using Int64 arithmetic
/// internally. If a path distance would overflow Int32 (2³¹−1), the result
/// for that vertex is clamped to `None` (treated as unreachable) to avoid
/// silent wrap-around.

/// Int32 max as Int64, used as the sentinel for "infinity" in distance arrays
/// and for overflow comparison during distance accumulation.
const INT_MAX_I64 : Int64 = 2147483647L

/// A min-heap entry: a (distance, vertex) pair.
/// Distance is stored as Int64 to prevent overflow during accumulation.
priv struct HeapEntry {
  dist : Int64
  vertex : Int
}

/// Binary min-heap keyed on `dist`.
/// Stored in a flat `Array[HeapEntry]` using the standard 0-indexed layout:
/// parent of `i` is `(i-1)/2`, children are `2i+1` and `2i+2`.
priv struct MinHeap {
  data : Array[HeapEntry]
}

fn MinHeap::new() -> MinHeap {
  { data: [] }
}

fn MinHeap::len(heap : MinHeap) -> Int {
  heap.data.length()
}

/// Insert a (dist, vertex) pair.  Sifts up to restore the heap property.
fn MinHeap::push(heap : MinHeap, dist : Int64, vertex : Int) -> Unit {
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

/// Remove and return the minimum entry.  Returns `None` if the heap is empty.
/// Sifts down to restore the heap property.
fn MinHeap::pop(heap : MinHeap) -> HeapEntry? {
  let n = heap.data.length()
  if n == 0 {
    return None
  }
  let result = heap.data[0]
  // Move the last element to the root, then sift down.
  heap.data[0] = heap.data[n - 1]
  let _ = heap.data.pop() // remove the duplicate at the end
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

/// Compute shortest paths from `src` using a min-heap priority queue.
///
/// `graph[i]` is an array of `(neighbor, weight)` tuples.
/// Returns `FixedArray[Int?]` where `None` means unreachable.
///
/// Distances are accumulated in Int64. If a distance exceeds Int32::max,
/// the vertex is treated as unreachable (returned as `None`) to avoid
/// silent overflow.
pub fn dijkstra(
  graph : Array[Array[(Int, Int)]],
  n : Int,
  src : Int,
) -> FixedArray[Int?] {
  if n <= 0 || src < 0 || src >= n || graph.length() < n {
    return FixedArray::make(if n > 0 { n } else { 0 }, None)
  }
  // Use Int64 for distances to prevent overflow during accumulation.
  // INT_MAX_I64 serves as the "infinity" sentinel.
  let dist = FixedArray::make(n, INT_MAX_I64)
  let visited = FixedArray::make(n, false)
  dist[src] = 0L
  let heap = MinHeap::new()
  MinHeap::push(heap, 0L, src)
  while MinHeap::len(heap) > 0 {
    match MinHeap::pop(heap) {
      Some({ dist: d, vertex: u }) =>
        if !visited[u] {
          visited[u] = true
          let neighbors = graph[u]
          for j = 0; j < neighbors.length(); j = j + 1 {
            let (v, w) = neighbors[j]
            if v >= 0 && v < n && !visited[v] {
              // Int64 addition prevents overflow.
              let nd = d + w.to_int64()
              if nd < dist[v] {
                dist[v] = nd
                MinHeap::push(heap, nd, v)
              }
            }
          }
        }
      None => break
    }
  }
  // Convert: distances that fit in Int32 become Some(d), overflow becomes None.
  let result : FixedArray[Int?] = FixedArray::make(n, None)
  for i = 0; i < n; i = i + 1 {
    if dist[i] != INT_MAX_I64 && dist[i] <= INT_MAX_I64 {
      result[i] = Some(dist[i].to_int())
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "dijkstra_heap: basic path graph" {
  let n = 4
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  graph[0].push((1, 1))
  graph[1].push((0, 1))
  graph[1].push((2, 2))
  graph[2].push((1, 2))
  graph[2].push((3, 3))
  graph[3].push((2, 3))
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(1))
  assert_eq(dist[2], Some(3))
  assert_eq(dist[3], Some(6))
}

test "dijkstra_heap: shorter path through intermediate" {
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 1))
  graph[1].push((0, 1))
  graph[1].push((2, 1))
  graph[2].push((1, 1))
  graph[0].push((2, 5))
  graph[2].push((0, 5))
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[2], Some(2)) // 0 -> 1 -> 2 = 2, not 5
}

test "dijkstra_heap: unreachable vertices" {
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 5))
  graph[1].push((0, 5))
  // Vertex 2 is isolated
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(5))
  assert_true(dist[2] is None)
}

test "dijkstra_heap: single node" {
  let graph : Array[Array[(Int, Int)]] = [[]]
  let dist = dijkstra(graph, 1, 0)
  assert_eq(dist[0], Some(0))
}

test "dijkstra_heap: directed graph" {
  let n = 3
  let graph : Array[Array[(Int, Int)]] = [[], [], []]
  graph[0].push((1, 2))
  graph[1].push((2, 3))
  // No reverse edges: directed
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(2))
  assert_eq(dist[2], Some(5))
  let dist1 = dijkstra(graph, n, 1)
  assert_true(dist1[0] is None)
  assert_eq(dist1[2], Some(3))
}

test "dijkstra_heap: star graph" {
  let n = 5
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  // Center = 0, edges to 1,2,3,4 with weights 1,2,3,4
  graph[0].push((1, 1))
  graph[0].push((2, 2))
  graph[0].push((3, 3))
  graph[0].push((4, 4))
  for i = 1; i < n; i = i + 1 {
    graph[i].push((0, i))
  }
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(1))
  assert_eq(dist[2], Some(2))
  assert_eq(dist[3], Some(3))
  assert_eq(dist[4], Some(4))
}

test "dijkstra_heap: lazy deletion correctness" {
  // Insert many edges to trigger multiple stale heap entries.
  let n = 6
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  // 0 connects to 1,2,3 with different weights.
  graph[0].push((1, 10))
  graph[0].push((2, 5))
  graph[0].push((3, 1))
  // 3 connects to 1,2 with smaller weights (shorter paths exist).
  graph[3].push((1, 1))
  graph[3].push((2, 1))
  graph[3].push((0, 1))
  graph[1].push((0, 10))
  graph[1].push((3, 1))
  graph[2].push((0, 5))
  graph[2].push((3, 1))
  // 4,5 reachable only from 1
  graph[1].push((4, 1))
  graph[1].push((5, 1))
  graph[4].push((1, 1))
  graph[5].push((1, 1))
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(2)) // 0 -> 3 -> 1 = 1 + 1
  assert_eq(dist[2], Some(2)) // 0 -> 3 -> 2 = 1 + 1
  assert_eq(dist[3], Some(1)) // 0 -> 3
  assert_eq(dist[4], Some(3)) // 0 -> 3 -> 1 -> 4
  assert_eq(dist[5], Some(3)) // 0 -> 3 -> 1 -> 5
}

test "dijkstra_heap: invalid input" {
  let graph : Array[Array[(Int, Int)]] = [[]]
  let r1 = dijkstra(graph, 0, 0)
  assert_eq(r1.length(), 0)
  let r2 = dijkstra(graph, 1, -1)
  assert_true(r2[0] is None)
  let r3 = dijkstra(graph, 1, 1)
  assert_true(r3[0] is None)
}

test "dijkstra_heap: chain 100 nodes" {
  let n = 100
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  for i = 0; i < n - 1; i = i + 1 {
    graph[i].push((i + 1, 1))
    graph[i + 1].push((i, 1))
  }
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[99], Some(99))
  assert_eq(dist[50], Some(50))
}

test "dijkstra_heap: complete graph K5" {
  let n = 5
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  // Complete graph with weight = |i - j| + 1
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      if i != j {
        graph[i].push((j, (if i > j { i - j } else { j - i }) + 1))
      }
    }
  }
  let dist = dijkstra(graph, n, 0)
  assert_eq(dist[0], Some(0))
  assert_eq(dist[1], Some(2))
  assert_eq(dist[2], Some(3))
  assert_eq(dist[3], Some(4))
  assert_eq(dist[4], Some(5))
}

test "dijkstra_heap: overflow protection" {
  // A graph where path distance exceeds Int32::max.
  // Chain of 3 nodes: 0 ->(2^30)-> 1 ->(2^30)-> 2
  // Total distance = 2^31 which overflows Int32.
  let n = 3
  let big_w = 1073741824 // 2^30
  let graph : Array[Array[(Int, Int)]] = []
  for i = 0; i < n; i = i + 1 {
    graph.push([])
  }
  graph[0].push((1, big_w))
  graph[1].push((2, big_w))
  let dist = dijkstra(graph, n, 0)
  // Node 1 is reachable (2^30 fits in Int32).
  assert_eq(dist[1], Some(big_w))
  // Node 2's distance (2^31) overflows Int32: should be None, not a wrong value.
  assert_true(dist[2] is None)
}
