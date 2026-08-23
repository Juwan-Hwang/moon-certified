///|
test "weiner: all pairs shortest path on simple graph" {
  // Graph: 0-1-2-3 (chain)
  let adj = [[1], [0, 2], [1, 3], [2]]
  let dist = weiner_all_pairs_shortest_path(adj, 4)
  assert_eq(dist[0][0], 0)
  assert_eq(dist[0][1], 1)
  assert_eq(dist[0][2], 2)
  assert_eq(dist[0][3], 3)
  assert_eq(dist[3][0], 3)
  assert_eq(dist[2][0], 2)
  assert_eq(dist[1][3], 2)
}

///|
test "weiner: disconnected graph" {
  // Two components: {0,1} and {2,3}
  let adj = [[1], [0], [3], [2]]
  let dist = weiner_all_pairs_shortest_path(adj, 4)
  assert_eq(dist[0][1], 1)
  assert_eq(dist[0][2], -1)
  assert_eq(dist[2][3], 1)
  assert_eq(dist[2][0], -1)
}

///|
test "weiner: complete graph" {
  // K4: all pairs connected
  let adj = [[1, 2, 3], [0, 2, 3], [0, 1, 3], [0, 1, 2]]
  let dist = weiner_all_pairs_shortest_path(adj, 4)
  for i = 0; i < 4; i = i + 1 {
    assert_eq(dist[i][i], 0)
    for j = 0; j < 4; j = j + 1 {
      if i != j {
        assert_eq(dist[i][j], 1)
      }
    }
  }
}

///|
test "weiner: star graph" {
  // Star: center 0, leaves 1-4
  let adj = [[1, 2, 3, 4], [0], [0], [0], [0]]
  let dist = weiner_all_pairs_shortest_path(adj, 5)
  assert_eq(dist[0][1], 1)
  assert_eq(dist[1][2], 2) // via center
  assert_eq(dist[0][4], 1)
  assert_eq(dist[3][4], 2)
}

///|
test "weiner: single node" {
  let adj = [[]]
  let dist = weiner_all_pairs_shortest_path(adj, 1)
  assert_eq(dist[0][0], 0)
}

///|
test "weiner: diameter of chain" {
  let adj = [[1], [0, 2], [1, 3], [2, 4], [3]]
  let d = graph_diameter(adj, 5)
  assert_eq(d, 4)
}

///|
test "weiner: diameter of star" {
  let adj = [[1, 2, 3], [0], [0], [0]]
  let d = graph_diameter(adj, 4)
  assert_eq(d, 2)
}

///|
test "weiner: average path length" {
  // Chain 0-1-2
  let adj = [[1], [0, 2], [1]]
  let avg = average_path_length(adj, 3)
  // Pairs: (0,1)=1, (0,2)=2, (1,0)=1, (1,2)=1, (2,0)=2, (2,1)=1 => sum=8, count=6
  assert_true((avg - 8.0 / 6.0).abs() < 1.0e-9)
}

///|
test "weiner: cyclic graph" {
  // Triangle: 0-1-2-0
  let adj = [[1, 2], [0, 2], [0, 1]]
  let dist = weiner_all_pairs_shortest_path(adj, 3)
  for i = 0; i < 3; i = i + 1 {
    assert_eq(dist[i][i], 0)
    for j = 0; j < 3; j = j + 1 {
      if i != j {
        assert_eq(dist[i][j], 1)
      }
    }
  }
}

///|
test "weiner: larger random graph" {
  // Grid 3x3: 9 nodes
  // 0-1-2
  // | | |
  // 3-4-5
  // | | |
  // 6-7-8
  let adj = [
    [1, 3], // 0
    [0, 2, 4], // 1
    [1, 5], // 2
    [0, 4, 6], // 3
    [1, 3, 5, 7], // 4
    [2, 4, 8], // 5
    [3, 7], // 6
    [4, 6, 8], // 7
    [5, 7], // 8
  ]
  let dist = weiner_all_pairs_shortest_path(adj, 9)
  assert_eq(dist[0][8], 4) // 0->1->2->5->8 or 0->3->6->7->8
  assert_eq(dist[0][4], 2) // 0->1->4 or 0->3->4
  assert_eq(dist[4][0], 2)
  let d = graph_diameter(adj, 9)
  assert_eq(d, 4)
}
