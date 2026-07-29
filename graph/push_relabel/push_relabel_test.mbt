test "push_relabel: simple path" {
  let pr = new(4)
  pr.add_edge(0, 1, 3)
  pr.add_edge(1, 2, 2)
  pr.add_edge(2, 3, 1)
  assert_eq(pr.max_flow(0, 3), 1L)
}

test "push_relabel: diamond network" {
  let pr = new(4)
  pr.add_edge(0, 1, 100)
  pr.add_edge(0, 2, 100)
  pr.add_edge(1, 3, 100)
  pr.add_edge(2, 3, 100)
  assert_eq(pr.max_flow(0, 3), 200L)
}

test "push_relabel: bottleneck" {
  let pr = new(4)
  pr.add_edge(0, 1, 10)
  pr.add_edge(0, 2, 10)
  pr.add_edge(1, 3, 5)
  pr.add_edge(2, 3, 5)
  pr.add_edge(1, 2, 15)
  assert_eq(pr.max_flow(0, 3), 10L)
}

test "push_relabel: no path" {
  let pr = new(3)
  pr.add_edge(0, 1, 5)
  assert_eq(pr.max_flow(0, 2), 0L)
}

test "push_relabel: CLRS example" {
  let pr = new(6)
  pr.add_edge(0, 1, 16)
  pr.add_edge(0, 2, 13)
  pr.add_edge(1, 2, 10)
  pr.add_edge(2, 1, 4)
  pr.add_edge(1, 3, 12)
  pr.add_edge(2, 4, 14)
  pr.add_edge(3, 2, 9)
  pr.add_edge(3, 5, 20)
  pr.add_edge(4, 3, 7)
  pr.add_edge(4, 5, 4)
  assert_eq(pr.max_flow(0, 5), 23L)
}

test "push_relabel: invalid input" {
  let pr = new(3)
  pr.add_edge(0, 1, 5)
  assert_eq(pr.max_flow(0, 0), 0L)
  assert_eq(pr.max_flow(-1, 1), 0L)
  assert_eq(pr.max_flow(0, 5), 0L)
}
