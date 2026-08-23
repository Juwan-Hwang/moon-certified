// White-box tests for graph/graph_utils: MinHeap and tarjan_scc_ids.

///|
fn[T] unwrap_or_fail(o : T?) -> T {
  match o {
    Some(v) => v
    None => abort("unwrap_or_fail: got None")
  }
}

// Count the number of distinct SCC ids in `comp[0..n)`.

///|
fn count_distinct(comp : FixedArray[Int], n : Int) -> Int {
  let mut count = 0
  for i = 0; i < n; i = i + 1 {
    let v = comp[i]
    let mut seen = false
    for j = 0; j < i; j = j + 1 {
      if comp[j] == v {
        seen = true
        break
      }
    }
    if !seen {
      count = count + 1
    }
  }
  count
}

// ============== MinHeap ==============

///|
test "minheap_empty" {
  let h = MinHeap::new()
  assert_eq(h.len(), 0)
  assert_true(h.pop() is None)
}

///|
test "minheap_single" {
  let h = MinHeap::new()
  h.push(5L, 0)
  assert_eq(h.len(), 1)
  let e = unwrap_or_fail(h.pop())
  assert_eq(e.dist, 5L)
  assert_eq(e.vertex, 0)
  assert_eq(h.len(), 0)
}

///|
test "minheap_pop_order_is_min_first" {
  let h = MinHeap::new()
  h.push(5L, 0)
  h.push(1L, 1)
  h.push(3L, 2)
  h.push(9L, 3)
  h.push(2L, 4)
  assert_eq(h.len(), 5)
  // Min-heap: smallest dist pops first.
  let e1 = unwrap_or_fail(h.pop())
  assert_eq(e1.dist, 1L)
  assert_eq(e1.vertex, 1)
  let e2 = unwrap_or_fail(h.pop())
  assert_eq(e2.dist, 2L)
  assert_eq(e2.vertex, 4)
  let e3 = unwrap_or_fail(h.pop())
  assert_eq(e3.dist, 3L)
  assert_eq(e3.vertex, 2)
  let e4 = unwrap_or_fail(h.pop())
  assert_eq(e4.dist, 5L)
  assert_eq(e4.vertex, 0)
  let e5 = unwrap_or_fail(h.pop())
  assert_eq(e5.dist, 9L)
  assert_eq(e5.vertex, 3)
  assert_eq(h.len(), 0)
  assert_true(h.pop() is None)
}

///|
test "minheap_equal_dist_pops_some_entry" {
  let h = MinHeap::new()
  h.push(7L, 10)
  h.push(7L, 20)
  let e1 = unwrap_or_fail(h.pop())
  assert_eq(e1.dist, 7L)
  let e2 = unwrap_or_fail(h.pop())
  assert_eq(e2.dist, 7L)
}

// ============== tarjan_scc_ids ==============

///|
test "tarjan_invalid_input" {
  // n <= 0
  let r1 = tarjan_scc_ids([], 0)
  assert_eq(r1.length(), 0)
  // adj has fewer lists than n
  let adj : Array[Array[Int]] = [[]]
  let r2 = tarjan_scc_ids(adj, 5)
  assert_eq(r2.length(), 5)
  for i = 0; i < 5; i = i + 1 {
    assert_eq(r2[i], -1)
  }
}

///|
test "tarjan_single_vertex" {
  let adj : Array[Array[Int]] = [[]]
  let comp = tarjan_scc_ids(adj, 1)
  assert_eq(comp.length(), 1)
  assert_eq(comp[0], 0)
}

///|
test "tarjan_two_isolated_vertices" {
  let adj : Array[Array[Int]] = [[], []]
  let comp = tarjan_scc_ids(adj, 2)
  assert_eq(count_distinct(comp, 2), 2)
  assert_true(comp[0] != comp[1])
}

///|
test "tarjan_single_cycle_plus_incoming" {
  // 0->1->2->0 form a cycle (SCC A); 3->0 points into the cycle (SCC B).
  let adj : Array[Array[Int]] = [[1], [2], [0], [0]]
  let comp = tarjan_scc_ids(adj, 4)
  assert_eq(count_distinct(comp, 4), 2)
  // vertices in the cycle share a component; vertex 3 is separate
  assert_eq(comp[0], comp[1])
  assert_eq(comp[1], comp[2])
  assert_true(comp[0] != comp[3])
}

///|
test "tarjan_two_disjoint_cycles" {
  // cycle {0,1} and cycle {2,3}, disconnected from each other
  let adj : Array[Array[Int]] = [[1], [0], [3], [2]]
  let comp = tarjan_scc_ids(adj, 4)
  assert_eq(count_distinct(comp, 4), 2)
  assert_eq(comp[0], comp[1])
  assert_eq(comp[2], comp[3])
  assert_true(comp[0] != comp[2])
}

///|
test "tarjan_self_loop" {
  let adj : Array[Array[Int]] = [[0]]
  let comp = tarjan_scc_ids(adj, 1)
  assert_eq(comp[0], 0)
}

///|
test "tarjan_acyclic_chain" {
  // 0->1->2, no back edges => each vertex is its own SCC
  let adj : Array[Array[Int]] = [[1], [2], []]
  let comp = tarjan_scc_ids(adj, 3)
  assert_eq(count_distinct(comp, 3), 3)
  assert_true(comp[0] != comp[1])
  assert_true(comp[1] != comp[2])
  assert_true(comp[0] != comp[2])
}
