///|
test "parallel_bfs: simple chain" {
  // 0-1-2-3-4
  let adj = [[1], [0, 2], [1, 3], [2, 4], [3]]
  let result = parallel_bfs(adj, 5, 0, 2)
  assert_eq(result.visited, 5)
  assert_eq(result.levels, 5)
  assert_eq(result.dist[0], 0)
  assert_eq(result.dist[4], 4)
  assert_eq(result.parent[0], -1)
  assert_eq(result.parent[1], 0)
  assert_eq(result.parent[4], 3)
}

///|
test "parallel_bfs: star graph" {
  let adj = [[1, 2, 3, 4], [0], [0], [0], [0]]
  let result = parallel_bfs(adj, 5, 0, 4)
  assert_eq(result.visited, 5)
  assert_eq(result.dist[1], 1)
  assert_eq(result.dist[4], 1)
  assert_eq(result.parent[2], 0)
}

///|
test "parallel_bfs: disconnected" {
  // Two components
  let adj = [[1], [0], [3], [2]]
  let result = parallel_bfs(adj, 4, 0, 2)
  assert_eq(result.visited, 2)
  assert_eq(result.dist[0], 0)
  assert_eq(result.dist[1], 1)
  assert_eq(result.dist[2], -1)
  assert_eq(result.dist[3], -1)
}

///|
test "parallel_bfs: invalid source" {
  let adj = [[1], [0]]
  let result = parallel_bfs(adj, 2, 5, 1)
  assert_eq(result.visited, 0)
  assert_eq(result.levels, 0)
}

///|
test "parallel_bfs: single worker matches multi-worker" {
  // Graph with branching
  let adj = [[1, 2, 3], [0, 4], [0, 5], [0, 6], [1], [2], [3]]
  let r1 = parallel_bfs(adj, 7, 0, 1)
  let r4 = parallel_bfs(adj, 7, 0, 4)
  // Results should be identical regardless of worker count
  for i = 0; i < 7; i = i + 1 {
    assert_eq(r4.dist[i], r1.dist[i])
  }
  assert_eq(r4.visited, r1.visited)
  assert_eq(r4.levels, r1.levels)
}

///|
test "parallel_bfs: complete graph" {
  let adj = [[1, 2, 3], [0, 2, 3], [0, 1, 3], [0, 1, 2]]
  let result = parallel_bfs(adj, 4, 0, 2)
  assert_eq(result.visited, 4)
  assert_eq(result.levels, 2) // level 0 (source) + level 1 (all others)
  for i = 1; i < 4; i = i + 1 {
    assert_eq(result.dist[i], 1)
  }
}

///|
test "parallel_bfs: connected components" {
  // 3 components: {0,1}, {2,3,4}, {5}
  let adj = [[1], [0], [3, 4], [2], [2], []]
  let comps = parallel_connected_components(adj, 6, 2)
  assert_eq(comps[0], comps[1]) // 0 and 1 same component
  assert_true(comps[0] != comps[2]) // different from component of 2
  assert_eq(comps[2], comps[3]) // 2,3,4 same
  assert_eq(comps[3], comps[4])
  assert_true(comps[5] != comps[0]) // 5 is its own component
}

///|
test "parallel_bfs: count components" {
  // 2 components: {0,1,2} and {3,4}
  let adj = [[1], [0, 2], [1], [4], [3]]
  let count = count_components(adj, 5, 2)
  assert_eq(count, 2)
}

///|
test "parallel_bfs: cycle graph" {
  // 0-1-2-3-0
  let adj = [[1, 3], [0, 2], [1, 3], [0, 2]]
  let result = parallel_bfs(adj, 4, 0, 2)
  assert_eq(result.visited, 4)
  assert_eq(result.dist[0], 0)
  assert_eq(result.dist[1], 1)
  assert_eq(result.dist[3], 1)
  assert_eq(result.dist[2], 2)
}
