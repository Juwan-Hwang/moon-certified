/// Union-Find (Disjoint Set Union) data structure.
/// Implements path compression in find() and union by rank in union().
/// Both optimizations together yield inverse-Ackermann amortized complexity,
/// which is effectively constant for all practical input sizes.

struct UnionFind {
  parent : FixedArray[Int]
  rank : FixedArray[Int]
  mut count : Int
}

/// Create a UnionFind with n singleton sets: {0}, {1}, ..., {n-1}.
pub fn new(n : Int) -> UnionFind {
  let parent = FixedArray::make(n, 0)
  let rank = FixedArray::make(n, 0)
  for i = 0; i < n; {
    parent[i] = i
    continue i + 1
  } nobreak {
    ()
  }
  { parent, rank, count: n }
}

/// Find the root (representative) of the set containing x.
/// Applies path compression: every node on the path to root is re-pointed
/// directly at the root, flattening the tree for future queries.
/// Returns the root if 0 <= x < n; returns -1 for out-of-range input.
pub fn find(uf : UnionFind, x : Int) -> Int {
  let n = uf.parent.length()
  if x < 0 || x >= n {
    return -1
  }
  // Find root by following parent pointers
  let mut root = x
  while uf.parent[root] != root {
    root = uf.parent[root]
  }
  // Path compression: re-point every node on the path directly to root
  let mut curr = x
  while uf.parent[curr] != root {
    let next = uf.parent[curr]
    uf.parent[curr] = root
    curr = next
  }
  root
}

/// Union the sets containing x and y, using union by rank.
/// The shorter tree is attached beneath the taller tree's root.
/// When ranks are equal, y's root is attached under x's root and
/// x's rank is incremented by one.
/// Returns true if a merge occurred; false if x and y are already in the
/// same set or if either index is out of range.
pub fn union(uf : UnionFind, x : Int, y : Int) -> Bool {
  let rx = find(uf, x)
  let ry = find(uf, y)
  if rx == -1 || ry == -1 {
    return false
  }
  if rx == ry {
    return false
  }
  if uf.rank[rx] < uf.rank[ry] {
    uf.parent[rx] = ry
  } else if uf.rank[rx] > uf.rank[ry] {
    uf.parent[ry] = rx
  } else {
    uf.parent[ry] = rx
    uf.rank[rx] = uf.rank[rx] + 1
  }
  uf.count = uf.count - 1
  true
}

/// Check whether x and y belong to the same set.
/// Returns false if either index is out of range.
pub fn connected(uf : UnionFind, x : Int, y : Int) -> Bool {
  let rx = find(uf, x)
  let ry = find(uf, y)
  if rx == -1 || ry == -1 {
    return false
  }
  rx == ry
}

/// Return the number of disjoint sets.
pub fn count(uf : UnionFind) -> Int {
  uf.count
}

test "new: creates n singleton sets" {
  let uf = new(10)
  assert_eq(count(uf), 10)
  for i = 0; i < 10; i = i + 1 {
    assert_eq(find(uf, i), i)
  }
}

test "new: zero elements" {
  let uf = new(0)
  assert_eq(count(uf), 0)
}

test "find: invalid index returns -1" {
  let uf = new(5)
  assert_eq(find(uf, -1), -1)
  assert_eq(find(uf, 5), -1)
  assert_eq(find(uf, 100), -1)
}

test "union: basic merge" {
  let uf = new(5)
  assert_eq(union(uf, 0, 1), true)
  assert_eq(count(uf), 4)
  assert_eq(connected(uf, 0, 1), true)
  assert_eq(connected(uf, 0, 2), false)
}

test "union: already connected returns false" {
  let uf = new(5)
  let _ = union(uf, 0, 1)
  assert_eq(union(uf, 0, 1), false)
  assert_eq(union(uf, 1, 0), false)
  assert_eq(count(uf), 4)
}

test "union: invalid indices return false" {
  let uf = new(5)
  assert_eq(union(uf, -1, 0), false)
  assert_eq(union(uf, 0, 5), false)
  assert_eq(union(uf, -1, 100), false)
  assert_eq(count(uf), 5)
}

test "union: transitive connectivity" {
  let uf = new(6)
  let _ = union(uf, 0, 1)
  let _ = union(uf, 1, 2)
  let _ = union(uf, 2, 3)
  assert_eq(connected(uf, 0, 3), true)
  assert_eq(connected(uf, 0, 4), false)
  assert_eq(count(uf), 3) // {0,1,2,3}, {4}, {5}
}

test "connected: same element" {
  let uf = new(5)
  assert_eq(connected(uf, 3, 3), true)
}

test "connected: invalid indices return false" {
  let uf = new(5)
  assert_eq(connected(uf, -1, 0), false)
  assert_eq(connected(uf, 0, 5), false)
}

test "count: decreases with each union" {
  let uf = new(10)
  assert_eq(count(uf), 10)
  let _ = union(uf, 0, 1)
  assert_eq(count(uf), 9)
  let _ = union(uf, 2, 3)
  assert_eq(count(uf), 8)
  let _ = union(uf, 0, 2) // merge {0,1} and {2,3}
  assert_eq(count(uf), 7)
}

test "path compression: deep node points to root" {
  let uf = new(4)
  // Build a tree of depth 2:
  // union(0,1): parent[1]=0, rank[0]=1
  let _ = union(uf, 0, 1)
  // union(2,3): parent[3]=2, rank[2]=1
  let _ = union(uf, 2, 3)
  // union(0,2): equal rank, parent[2]=0, rank[0]=2
  // Tree structure: 0 (root), 1->0, 2->0, 3->2
  let _ = union(uf, 0, 2)
  // Before find(3), parent[3] is still 2
  assert_eq(uf.parent[3], 2)
  // find(3) compresses path: 3->2->0 becomes 3->0
  let root = find(uf, 3)
  assert_eq(root, 0)
  // After path compression, parent[3] should point directly to root
  assert_eq(uf.parent[3], 0)
}

test "union by rank: rank tracking" {
  let uf = new(8)
  // Build two trees of rank 1:
  let _ = union(uf, 0, 1)
  assert_eq(uf.rank[0], 1)
  assert_eq(uf.rank[1], 0)
  let _ = union(uf, 2, 3)
  assert_eq(uf.rank[2], 1)
  assert_eq(uf.rank[3], 0)
  // Merge equal-rank trees: rank[0] becomes 2
  let _ = union(uf, 0, 2)
  assert_eq(uf.rank[0], 2)
  assert_eq(uf.rank[2], 1)
  // Build another rank-2 tree:
  let _ = union(uf, 4, 5)
  assert_eq(uf.rank[4], 1)
  let _ = union(uf, 6, 7)
  assert_eq(uf.rank[6], 1)
  let _ = union(uf, 4, 6)
  assert_eq(uf.rank[4], 2)
  // Merge two rank-2 trees: rank[0] becomes 3
  let _ = union(uf, 0, 4)
  assert_eq(uf.rank[0], 3)
  assert_eq(count(uf), 1)
}

test "cycle detection: union same set returns false" {
  let uf = new(5)
  let _ = union(uf, 0, 1)
  let _ = union(uf, 1, 2)
  // 0 and 2 are now in the same set
  assert_eq(union(uf, 0, 2), false) // would create cycle
  assert_eq(union(uf, 2, 0), false) // would create cycle
}

test "large sets: 100 element chain" {
  let uf = new(100)
  // Union consecutive: 0-1, 1-2, ..., 98-99
  for i = 0; i < 99; i = i + 1 {
    let _ = union(uf, i, i + 1)
  }
  assert_eq(connected(uf, 0, 99), true)
  assert_eq(count(uf), 1)
}

test "large sets: star union" {
  let uf = new(8)
  // Star: union everything with 0
  for i = 1; i < 8; i = i + 1 {
    let _ = union(uf, 0, i)
  }
  assert_eq(count(uf), 1)
  for i = 0; i < 8; i = i + 1 {
    assert_eq(connected(uf, 0, i), true)
  }
}

test "large sets: random-like unions" {
  let uf = new(50)
  // Union i with (i*7+3) % 50
  for i = 0; i < 50; i = i + 1 {
    let _ = union(uf, i, (i * 7 + 3) % 50)
  }
  // Some merges must have happened
  assert_eq(count(uf) < 50, true)
  // find should return a valid root in [0, 50) that is self-parenting
  for i = 0; i < 50; i = i + 1 {
    let r = find(uf, i)
    assert_eq(r >= 0 && r < 50, true)
    assert_eq(find(uf, r), r)
  }
}
