/// Chu-Liu/Edmonds' Algorithm — Minimum Spanning Arborescence.
///
/// Finds the minimum-cost directed spanning tree (arborescence) rooted at
/// a given vertex. An arborescence is the directed analog of a spanning
/// tree: every vertex except the root has exactly one incoming edge.
///
/// ## Algorithm
///
/// 1. For each non-root vertex, pick the minimum-cost incoming edge.
/// 2. If no cycle is formed, these edges form the arborescence.
/// 3. If a cycle exists, contract it into a super-node, adjust edge weights,
///    and recurse.
///
/// ## Complexity
/// - Time:  O(V × E) — this implementation; O(E log V) is possible with
///   more sophisticated data structures.
/// - Space: O(V + E)
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// An edge in a directed graph: from -> to, with cost.
priv struct DirEdge {
  from : Int
  to : Int
  cost : Int
}

///|
/// Find the minimum spanning arborescence rooted at `root`.
///
/// Parameters:
/// - `n`: number of vertices (0..n-1).
/// - `edges`: list of directed edges (from, to, cost).
/// - `root`: the root vertex.
///
/// Returns `Some(total_cost)` if an arborescence exists, `None` otherwise.
pub fn min_arborescence(
  n : Int,
  edges : Array[(Int, Int, Int)],
  root : Int,
) -> Int? {
  if n <= 0 || root < 0 || root >= n {
    return None
  }
  // Check that every non-root vertex has at least one incoming edge.
  let has_incoming = FixedArray::make(n, false)
  for i = 0; i < edges.length(); i = i + 1 {
    let (_, to, _) = edges[i]
    if to != root && to >= 0 && to < n {
      has_incoming[to] = true
    }
  }
  for i = 0; i < n; i = i + 1 {
    if i != root && !has_incoming[i] {
      return None
    }
  }
  let edge_list : Array[DirEdge] = []
  for i = 0; i < edges.length(); i = i + 1 {
    let (f, t, c) = edges[i]
    if t != root && f >= 0 && f < n && t >= 0 && t < n {
      edge_list.push({ from: f, to: t, cost: c })
    }
  }
  let result = chu_liu_edmonds(n, edge_list, root)
  Some(result)
}

///|
/// Recursive Chu-Liu/Edmonds implementation.
fn chu_liu_edmonds(n : Int, edges : Array[DirEdge], root : Int) -> Int {
  // Step 1: For each non-root vertex, select the minimum incoming edge.
  let min_edge = FixedArray::make(n, -1) // index into edges
  let min_cost = FixedArray::make(n, 2147483647)
  for i = 0; i < edges.length(); i = i + 1 {
    let e = edges[i]
    if e.to != root && e.cost < min_cost[e.to] {
      min_cost[e.to] = e.cost
      min_edge[e.to] = i
    }
  }
  // Step 2: Detect cycles among selected edges.
  let mut cycle_start = -1
  let visited = FixedArray::make(n, 0) // 0=unvisited, 1=in progress, 2=done
  for i = 0; i < n; i = i + 1 {
    if i == root || visited[i] != 0 {
      continue
    }
    // Follow the chain of min edges.
    let path : Array[Int] = []
    let mut v = i
    while v != root && visited[v] == 0 {
      visited[v] = 1
      path.push(v)
      let ei = min_edge[v]
      if ei < 0 {
        break
      }
      v = edges[ei].from
    }
    if v != root && visited[v] == 1 {
      // Found a cycle starting at v.
      cycle_start = v
      break
    }
    // Mark all as done.
    for j = 0; j < path.length(); j = j + 1 {
      visited[path[j]] = 2
    }
  }
  // Step 3: If no cycle, return sum of min costs.
  if cycle_start < 0 {
    let mut total = 0
    for i = 0; i < n; i = i + 1 {
      if i != root && min_edge[i] >= 0 {
        total = total + edges[min_edge[i]].cost
      }
    }
    return total
  }
  // Step 4: Contract the cycle.
  // Find all nodes in the cycle.
  let in_cycle = FixedArray::make(n, false)
  let mut v = cycle_start
  let cycle_nodes : Array[Int] = []
  while true {
    in_cycle[v] = true
    cycle_nodes.push(v)
    v = edges[min_edge[v]].from
    if v == cycle_start {
      break
    }
  }
  let cycle_cost = {
    let mut s = 0
    for i = 0; i < cycle_nodes.length(); i = i + 1 {
      s = s + min_cost[cycle_nodes[i]]
    }
    s
  }
  // Build contracted graph: cycle -> super-node (index n).
  let super_node = n
  let new_n = n + 1
  let new_edges : Array[DirEdge] = []
  // Map old vertex to new vertex.
  let remap = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    if in_cycle[i] {
      remap[i] = super_node
    } else {
      remap[i] = i
    }
  }
  for i = 0; i < edges.length(); i = i + 1 {
    let e = edges[i]
    let nf = remap[e.from]
    let nt = remap[e.to]
    if nf != nt {
      if in_cycle[e.to] {
        // Edge entering cycle: subtract min_cost[e.to]
        new_edges.push({
          from: nf,
          to: super_node,
          cost: e.cost - min_cost[e.to],
        })
      } else {
        new_edges.push({ from: nf, to: nt, cost: e.cost })
      }
    }
  }
  // Recurse on contracted graph.
  let sub_result = chu_liu_edmonds(new_n, new_edges, root)
  // The recursion handles the contraction; the cycle cost is added back.
  sub_result + cycle_cost
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "chu_liu: simple tree" {
  // Root=0, edges: 0->1(1), 0->2(2), 0->3(3)
  let edges = [(0, 1, 1), (0, 2, 2), (0, 3, 3)]
  let result = min_arborescence(4, edges, 0)
  assert_eq(result, Some(6))
}

///|
test "chu_liu: picks minimum incoming" {
  // 0->1(10), 0->1(5) — should pick cost 5
  let edges = [(0, 1, 10), (0, 1, 5)]
  let result = min_arborescence(2, edges, 0)
  assert_eq(result, Some(5))
}

///|
test "chu_liu: with cycle contraction" {
  // Root=0. Cycle 1->2->1 with costs.
  // 0->1(1), 1->2(1), 2->1(1)
  // MSA: 0->1(1) + 1->2(1) = 2 (skip 2->1 to avoid cycle)
  let edges = [(0, 1, 1), (1, 2, 1), (2, 1, 1)]
  let result = min_arborescence(3, edges, 0)
  assert_eq(result, Some(2))
}

///|
test "chu_liu: no arborescence (disconnected)" {
  // Vertex 3 has no incoming edge.
  let edges = [(0, 1, 1), (1, 2, 1)]
  let result = min_arborescence(4, edges, 0)
  assert_eq(result, None)
}

///|
test "chu_liu: complex graph" {
  // Classic example with cycle.
  let edges = [(0, 1, 4), (0, 2, 1), (1, 2, 2), (2, 1, 1), (2, 3, 5), (1, 3, 3)]
  let result = min_arborescence(4, edges, 0)
  // Optimal: 0->2(1), 2->1(1), 1->3(3) = 5
  assert_eq(result, Some(5))
}

///|
test "chu_liu: single vertex" {
  let edges : Array[(Int, Int, Int)] = []
  let result = min_arborescence(1, edges, 0)
  assert_eq(result, Some(0))
}

///|
test "chu_liu: chain graph" {
  let edges = [(0, 1, 5), (1, 2, 3), (2, 3, 7), (3, 4, 1)]
  let result = min_arborescence(5, edges, 0)
  assert_eq(result, Some(16))
}

///|
test "chu_liu: root has no incoming edges required" {
  // Root=2; edges into root should be ignored.
  let edges = [(0, 1, 1), (1, 2, 1), (2, 0, 1)]
  let result = min_arborescence(3, edges, 2)
  // MSA: 2->0(1), 0->1(1) = 2
  assert_eq(result, Some(2))
}
