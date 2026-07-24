/// Shared graph algorithm utilities: binary min-heap keyed on `Int64`.
///
/// This heap is used by `dijkstra_heap` and `johnson` as their priority queue
/// for shortest-path computation. Extracting it here eliminates the code
/// duplication where identical min-heap implementations were copy-pasted into
/// each algorithm package — a single bug fix now propagates automatically.
///
/// **Design.** Standard 0-indexed binary heap stored in a flat `Array`:
/// parent of `i` is `(i-1)/2`, children are `2i+1` and `2i+2`.
/// Lazy deletion is the caller's responsibility: stale entries (popped with
/// a distance greater than the current known distance) are simply skipped.

/// A min-heap entry: a (distance, vertex) pair.
///
/// `dist` is `Int64` to prevent overflow during distance accumulation
/// (e.g. in Dijkstra/Johnson where intermediate sums can exceed `Int32::max`).
pub struct HeapEntry {
  dist : Int64
  vertex : Int
}

/// Binary min-heap keyed on `dist`.
///
/// Stored in a flat `Array[HeapEntry]` using the standard 0-indexed layout:
/// parent of `i` is `(i-1)/2`, children are `2i+1` and `2i+2`.
pub struct MinHeap {
  data : Array[HeapEntry]
}

/// Create an empty min-heap.
pub fn MinHeap::new() -> MinHeap {
  { data: [] }
}

/// Number of entries currently in the heap.
pub fn MinHeap::len(heap : MinHeap) -> Int {
  heap.data.length()
}

/// Insert a `(dist, vertex)` pair. Sifts up to restore the heap property.
///
/// Time: O(log n).
pub fn MinHeap::push(heap : MinHeap, dist : Int64, vertex : Int) -> Unit {
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

/// Remove and return the minimum entry, or `None` if the heap is empty.
/// Sifts down to restore the heap property.
///
/// Time: O(log n).
pub fn MinHeap::pop(heap : MinHeap) -> HeapEntry? {
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

// ---------------------------------------------------------------------------
// Tarjan's Strongly Connected Components (shared)
// ---------------------------------------------------------------------------
//
// This implementation is shared by `graph/scc` (adjacency-list variant) and
// `graph/two_sat`. Extracting it here eliminates the code duplication where
// identical iterative Tarjan SCC logic was copy-pasted into each package.
//
// The function returns SCC component IDs: `comp[i]` is the ID of the SCC
// containing vertex `i`. IDs are assigned in the order SCCs are found, which
// is reverse topological order (sinks first). This property is essential for
// 2-SAT: if `comp[x] < comp[¬x]`, then `x` should be set true.

/// Mutable state for iterative Tarjan's SCC algorithm.
priv struct TarjanState {
  adj : Array[Array[Int]]
  mut index_counter : Int
  indices : FixedArray[Int] // -1 = not yet visited
  lowlink : FixedArray[Int]
  on_stack : FixedArray[Bool]
  stack : FixedArray[Int]
  mut stack_top : Int
  comp : FixedArray[Int] // SCC ID assigned to each vertex (-1 = unassigned)
  mut scc_count : Int
}

fn TarjanState::new(adj : Array[Array[Int]], n : Int) -> TarjanState {
  {
    adj,
    index_counter: 0,
    indices: FixedArray::make(n, -1),
    lowlink: FixedArray::make(n, 0),
    on_stack: FixedArray::make(n, false),
    stack: FixedArray::make(n, 0),
    stack_top: 0,
    comp: FixedArray::make(n, -1),
    scc_count: 0,
  }
}

/// Iterative DFS core of Tarjan's algorithm using an explicit stack.
/// Avoids recursion depth limits for large graphs.
fn tarjan_strongconnect(state : TarjanState, start : Int) -> Unit {
  let dfs_stack : Array[(Int, Int)] = [(start, 0)]
  state.indices[start] = state.index_counter
  state.lowlink[start] = state.index_counter
  state.index_counter = state.index_counter + 1
  state.stack[state.stack_top] = start
  state.stack_top = state.stack_top + 1
  state.on_stack[start] = true
  while dfs_stack.length() > 0 {
    let top_idx = dfs_stack.length() - 1
    let (v, next_j) = dfs_stack[top_idx]
    let neighbors = state.adj[v]
    if next_j < neighbors.length() {
      dfs_stack[top_idx] = (v, next_j + 1)
      let w = neighbors[next_j]
      if state.indices[w] == -1 {
        state.indices[w] = state.index_counter
        state.lowlink[w] = state.index_counter
        state.index_counter = state.index_counter + 1
        state.stack[state.stack_top] = w
        state.stack_top = state.stack_top + 1
        state.on_stack[w] = true
        dfs_stack.push((w, 0))
      } else if state.on_stack[w] {
        if state.indices[w] < state.lowlink[v] {
          state.lowlink[v] = state.indices[w]
        }
      }
    } else {
      ignore(dfs_stack.pop())
      if dfs_stack.length() > 0 {
        let parent_idx = dfs_stack.length() - 1
        let (parent, _) = dfs_stack[parent_idx]
        if state.lowlink[v] < state.lowlink[parent] {
          state.lowlink[parent] = state.lowlink[v]
        }
      }
      if state.lowlink[v] == state.indices[v] {
        let mut w = -1
        while w != v {
          state.stack_top = state.stack_top - 1
          w = state.stack[state.stack_top]
          state.on_stack[w] = false
          state.comp[w] = state.scc_count
        }
        state.scc_count = state.scc_count + 1
      }
    }
  }
}

/// Compute SCC component IDs using Tarjan's algorithm (iterative).
///
/// `adj[i]` is the adjacency list of vertex `i`: an array of neighbor indices.
/// Returns `FixedArray[Int]` where `result[i]` is the SCC ID of vertex `i`.
/// IDs are assigned in reverse topological order (sinks get lower IDs).
/// Returns a `FixedArray` of `-1` for invalid input (`n <= 0`).
pub fn tarjan_scc_ids(adj : Array[Array[Int]], n : Int) -> FixedArray[Int] {
  if n <= 0 || adj.length() < n {
    return FixedArray::make(if n > 0 { n } else { 0 }, -1)
  }
  let state = TarjanState::new(adj, n)
  for v = 0; v < n; v = v + 1 {
    if state.indices[v] == -1 {
      tarjan_strongconnect(state, v)
    }
  }
  state.comp
}
