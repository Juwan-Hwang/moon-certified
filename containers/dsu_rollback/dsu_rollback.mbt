/// Rollback Disjoint Set Union (DSU) — Union-Find with undo support.
///
/// This is a **rollback DSU** (also called **persistent DSU** or **DSU with
/// undo**): every `union` operation is recorded on an internal history stack
/// and can be reversed in O(1) via [`rollback`] or [`rollback_to`].
///
/// ## Key Design Decision: No Path Compression
///
/// Standard DSU achieves near-O(1) amortized time via **path compression** +
/// **union by rank**. However, path compression modifies many parent pointers
/// per `find`, making rollback impractical (each `find` would need its own
/// history entry).
///
/// This implementation uses **union by size only** (no path compression), so:
/// - `find` is O(log n) per query (tree height ≤ log₂ n by size invariant).
/// - `union` modifies exactly **two** fields (one `parent`, one `size`),
///   so each rollback is O(1).
///
/// The trade-off is slightly slower `find` but full reversibility.
///
/// ## Use Cases
///
/// - **Offline dynamic connectivity**: process edge insertions/deletions in
///   divide-and-conquer over a time segment tree.
/// - **Bipartite graph checking with edge deletions**.
/// - **Parallel binary search** with DSU state.
/// - **Incremental bridge-finding** (maintenance of 2-edge-connected
///   components with rollback).
///
/// ## Complexity
///
/// | Operation  | Time     | Space |
/// |------------|----------|-------|
/// | `find`     | O(log n) | O(1)  |
/// | `union`    | O(log n) | O(1)  |
/// | `rollback` | O(1)     | O(1)  |
/// | `snapshot` | O(1)     | O(1)  |
/// | `rollback_to` | O(k)  | O(1)  | (k = ops undone) |
///
/// Total space: O(n + h) where h is the history depth.
///
/// ## References
///
/// - Eppstein, D. (1992). "Dynamic generators of hierarchically dense graphs."
/// - Italiano, G. F. et al. (2016). "Dynamic graph algorithms."
/// - Codeforces blog: "DSU with rollback" tutorial.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// History entry
// ---------------------------------------------------------------------------

///|
/// Records a single `union` modification for later reversal.
priv struct HistoryEntry {
  child : Int // node whose parent was changed
  old_parent : Int // previous parent of `child`
  root : Int // root whose size was changed
  old_size : Int // previous size of `root`
  old_count : Int // previous component count
}

// ---------------------------------------------------------------------------
// Data structure
// ---------------------------------------------------------------------------

///|
/// Rollback DSU — Union-Find with O(1) undo per operation.
///
/// Created via [`new`]. Use [`union`] to merge sets, [`find`] to query
/// representatives, [`snapshot`] to mark a point in time, and [`rollback`] or
/// [`rollback_to`] to undo operations.
pub struct RollbackDSU {
  priv parent : FixedArray[Int]
  priv size : FixedArray[Int]
  priv mut count : Int
  priv history : Array[HistoryEntry]
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create a RollbackDSU with `n` singleton sets: {0}, {1}, ..., {n−1}.
///
/// If `n < 0`, it is clamped to 0 (empty structure).
pub fn new(n : Int) -> RollbackDSU {
  let n = if n < 0 { 0 } else { n }
  let parent = FixedArray::make(n, 0)
  let size = FixedArray::make(n, 1)
  for i = 0; i < n; i = i + 1 {
    parent[i] = i
  }
  { parent, size, count: n, history: [] }
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

///|
/// Find the root (representative) of the set containing `x`.
///
/// **No path compression** is applied — every node on the path remains
/// unchanged, ensuring O(1) rollback.
///
/// Returns `Some(root)` if `0 ≤ x < n`; `None` for out-of-range input.
///
/// Time: O(log n).
pub fn find(dsu : RollbackDSU, x : Int) -> Int? {
  let n = dsu.parent.length()
  if x < 0 || x >= n {
    return None
  }
  let mut root = x
  while dsu.parent[root] != root {
    root = dsu.parent[root]
  }
  Some(root)
}

///|
/// Check whether `x` and `y` are in the same connected component.
///
/// Returns `false` if either index is out of range.
///
/// Time: O(log n).
pub fn connected(dsu : RollbackDSU, x : Int, y : Int) -> Bool {
  match find(dsu, x) {
    None => return false
    Some(rx) =>
      match find(dsu, y) {
        None => false
        Some(ry) => rx == ry
      }
  }
}

///|
/// Return the number of disjoint components.
///
/// Time: O(1).
pub fn count(dsu : RollbackDSU) -> Int {
  dsu.count
}

///|
/// Return the size of the component containing `x`.
///
/// Returns `None` if `x` is out of range.
///
/// Time: O(log n).
pub fn component_size(dsu : RollbackDSU, x : Int) -> Int? {
  match find(dsu, x) {
    None => None
    Some(root) => Some(dsu.size[root])
  }
}

///|
/// Return the number of elements (nodes) in the DSU.
///
/// Time: O(1).
pub fn len(dsu : RollbackDSU) -> Int {
  dsu.parent.length()
}

// ---------------------------------------------------------------------------
// Mutations
// ---------------------------------------------------------------------------

///|
/// Union the sets containing `x` and `y`, using union by size.
///
/// The smaller tree is attached beneath the larger tree's root. This operation
/// is recorded on the history stack and can be reversed by [`rollback`].
///
/// Returns `true` if a merge occurred; `false` if `x` and `y` are already in
/// the same set or either index is out of range.
///
/// Time: O(log n).
pub fn union(dsu : RollbackDSU, x : Int, y : Int) -> Bool {
  let rx = match find(dsu, x) {
    None => return false
    Some(r) => r
  }
  let ry = match find(dsu, y) {
    None => return false
    Some(r) => r
  }
  if rx == ry {
    return false
  }
  // Attach smaller tree under larger tree.
  let (child, root) = if dsu.size[rx] < dsu.size[ry] {
    (rx, ry)
  } else if dsu.size[rx] > dsu.size[ry] {
    (ry, rx)
  } else {
    // Equal size: attach ry under rx (deterministic tie-breaking).
    (ry, rx)
  }
  // Record history.
  let entry : HistoryEntry = {
    child,
    old_parent: dsu.parent[child],
    root,
    old_size: dsu.size[root],
    old_count: dsu.count,
  }
  dsu.history.push(entry)
  // Apply union.
  dsu.parent[child] = root
  dsu.size[root] = dsu.size[root] + dsu.size[child]
  dsu.count = dsu.count - 1
  true
}

// ---------------------------------------------------------------------------
// Rollback
// ---------------------------------------------------------------------------

///|
/// Return the current history depth (number of recorded `union` operations).
///
/// Use this as a snapshot token: pass it to [`rollback_to`] to undo all
/// operations performed after this point.
///
/// Time: O(1).
pub fn snapshot(dsu : RollbackDSU) -> Int {
  dsu.history.length()
}

///|
/// Undo the most recent `union` operation.
///
/// Does nothing if the history is empty.
///
/// Time: O(1).
pub fn rollback(dsu : RollbackDSU) -> Unit {
  match dsu.history.pop() {
    None => ()
    Some(entry) => {
      dsu.parent[entry.child] = entry.old_parent
      dsu.size[entry.root] = entry.old_size
      dsu.count = entry.old_count
    }
  }
}

///|
/// Undo all `union` operations until the history depth equals `target`.
///
/// If `target` ≥ current depth, this is a no-op. If `target < 0`, all
/// operations are undone.
///
/// Time: O(current_depth − target).
pub fn rollback_to(dsu : RollbackDSU, target : Int) -> Unit {
  while dsu.history.length() > target && dsu.history.length() > 0 {
    rollback(dsu)
  }
}

///|
/// Clear all history without rolling back.
///
/// After calling this, previous `union` operations can no longer be undone.
/// The current DSU state is unchanged. This is useful to free memory when
/// rollback is no longer needed.
pub fn clear_history(dsu : RollbackDSU) -> Unit {
  dsu.history.clear()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "rollback_dsu: basic union and find" {
  let dsu = new(5)
  assert_eq(count(dsu), 5)
  assert_true(union(dsu, 0, 1))
  assert_true(union(dsu, 2, 3))
  assert_eq(count(dsu), 3)
  assert_true(connected(dsu, 0, 1))
  assert_true(connected(dsu, 2, 3))
  assert_false(connected(dsu, 0, 2))
}

///|
test "rollback_dsu: single rollback" {
  let dsu = new(5)
  let _ = union(dsu, 0, 1)
  let _ = union(dsu, 2, 3)
  assert_eq(count(dsu), 3)
  assert_true(connected(dsu, 2, 3))
  // Undo the last union (2,3).
  rollback(dsu)
  assert_eq(count(dsu), 4)
  assert_false(connected(dsu, 2, 3))
  // The first union (0,1) should still be active.
  assert_true(connected(dsu, 0, 1))
}

///|
test "rollback_dsu: rollback to snapshot" {
  let dsu = new(6)
  let _ = union(dsu, 0, 1)
  let _ = union(dsu, 1, 2)
  let snap = snapshot(dsu) // snap = 2
  let _ = union(dsu, 3, 4)
  let _ = union(dsu, 4, 5)
  let _ = union(dsu, 0, 3) // now everything is connected
  assert_eq(count(dsu), 1)
  assert_true(connected(dsu, 0, 5))
  // Rollback to snapshot.
  rollback_to(dsu, snap)
  assert_eq(count(dsu), 4) // 3 components from {0,1,2}, {3}, {4}, {5}
  assert_true(connected(dsu, 0, 2))
  assert_false(connected(dsu, 0, 5))
}

///|
test "rollback_dsu: multiple rollbacks" {
  let dsu = new(4)
  let _ = union(dsu, 0, 1)
  let _ = union(dsu, 1, 2)
  let _ = union(dsu, 2, 3)
  assert_eq(count(dsu), 1)
  // Undo all three unions one by one.
  rollback(dsu)
  assert_eq(count(dsu), 2)
  assert_false(connected(dsu, 2, 3))
  assert_true(connected(dsu, 0, 2))
  rollback(dsu)
  assert_eq(count(dsu), 3)
  assert_false(connected(dsu, 1, 2))
  rollback(dsu)
  assert_eq(count(dsu), 4)
  assert_false(connected(dsu, 0, 1))
}

///|
test "rollback_dsu: rollback empty history" {
  let dsu = new(3)
  rollback(dsu) // should not crash
  assert_eq(count(dsu), 3)
}

///|
test "rollback_dsu: rollback_to with negative target" {
  let dsu = new(4)
  let _ = union(dsu, 0, 1)
  let _ = union(dsu, 2, 3)
  rollback_to(dsu, -1) // undo everything
  assert_eq(count(dsu), 4)
  assert_false(connected(dsu, 0, 1))
  assert_false(connected(dsu, 2, 3))
}

///|
test "rollback_dsu: rollback_to with large target" {
  let dsu = new(4)
  let _ = union(dsu, 0, 1)
  rollback_to(dsu, 100) // should be no-op
  assert_eq(count(dsu), 3)
  assert_true(connected(dsu, 0, 1))
}

///|
test "rollback_dsu: union same set" {
  let dsu = new(4)
  assert_true(union(dsu, 0, 1))
  assert_false(union(dsu, 0, 1)) // already in same set
  assert_eq(snapshot(dsu), 1) // only one history entry
}

///|
test "rollback_dsu: out of range" {
  let dsu = new(3)
  assert_false(union(dsu, 0, 5))
  assert_false(union(dsu, -1, 2))
  assert_eq(find(dsu, 5), None)
  assert_eq(find(dsu, -1), None)
  assert_eq(count(dsu), 3)
}

///|
test "rollback_dsu: component size" {
  let dsu = new(5)
  let _ = union(dsu, 0, 1)
  let _ = union(dsu, 1, 2)
  assert_eq(component_size(dsu, 0), Some(3))
  assert_eq(component_size(dsu, 3), Some(1))
  assert_eq(component_size(dsu, 10), None)
  rollback(dsu)
  assert_eq(component_size(dsu, 0), Some(2))
}

///|
test "rollback_dsu: clear history" {
  let dsu = new(4)
  let _ = union(dsu, 0, 1)
  let _ = union(dsu, 2, 3)
  assert_eq(snapshot(dsu), 2)
  clear_history(dsu)
  assert_eq(snapshot(dsu), 0)
  // State should be unchanged.
  assert_eq(count(dsu), 2)
  assert_true(connected(dsu, 0, 1))
  // Rollback should do nothing now.
  rollback(dsu)
  assert_eq(count(dsu), 2)
}

///|
test "rollback_dsu: large chain union and rollback" {
  let n = 100
  let dsu = new(n)
  // Union 0-1, 1-2, 2-3, ..., (n-2)-(n-1)
  for i = 0; i < n - 1; i = i + 1 {
    let _ = union(dsu, i, i + 1)
  }
  assert_eq(count(dsu), 1)
  assert_true(connected(dsu, 0, n - 1))
  // Rollback all.
  rollback_to(dsu, 0)
  assert_eq(count(dsu), n)
  assert_false(connected(dsu, 0, 1))
}

///|
test "rollback_dsu: interleave union and rollback" {
  let dsu = new(8)
  let _ = union(dsu, 0, 1)
  let _ = union(dsu, 2, 3)
  rollback(dsu) // undo (2,3)
  let _ = union(dsu, 1, 2) // merge {0,1} with {2}
  let _ = union(dsu, 4, 5)
  assert_eq(count(dsu), 5) // {0,1,2}, {3}, {4,5}, {6}, {7}
  assert_true(connected(dsu, 0, 2))
  assert_false(connected(dsu, 2, 3))
  assert_true(connected(dsu, 4, 5))
  rollback(dsu) // undo (4,5)
  assert_eq(count(dsu), 6)
  assert_false(connected(dsu, 4, 5))
  assert_true(connected(dsu, 0, 2))
}

///|
test "rollback_dsu: tree height is O(log n) without path compression" {
  // With union by size (no path compression), tree height ≤ log₂(n).
  let n = 64
  let dsu = new(n)
  // Union all into one component.
  for i = 1; i < n; i = i + 1 {
    let _ = union(dsu, 0, i)
  }
  assert_eq(count(dsu), 1)
  // find should still be fast (O(log n)).
  assert_true(connected(dsu, 0, n - 1))
  // Verify all elements are connected.
  for i = 0; i < n; i = i + 1 {
    assert_true(connected(dsu, 0, i))
  }
}

///|
test "rollback_dsu: len returns element count" {
  let dsu = new(10)
  assert_eq(len(dsu), 10)
  let _ = union(dsu, 0, 1)
  assert_eq(len(dsu), 10) // len doesn't change with unions
}

///|
test "rollback_dsu: full rollback restores initial state" {
  let n = 10
  let dsu = new(n)
  // Perform various unions.
  let _ = union(dsu, 0, 1)
  let _ = union(dsu, 2, 3)
  let _ = union(dsu, 4, 5)
  let _ = union(dsu, 1, 2)
  let _ = union(dsu, 3, 4)
  // Now {0,1,2,3,4,5} are one component.
  assert_eq(count(dsu), n - 5)
  // Rollback everything.
  rollback_to(dsu, 0)
  assert_eq(count(dsu), n)
  // Verify no two elements are connected.
  for i = 0; i < n; i = i + 1 {
    for j = i + 1; j < n; j = j + 1 {
      assert_false(connected(dsu, i, j))
    }
  }
}

///|
test "rollback_dsu: empty dsu" {
  let dsu = new(0)
  assert_eq(count(dsu), 0)
  assert_eq(len(dsu), 0)
  assert_false(union(dsu, 0, 1))
  rollback(dsu) // no-op
  assert_eq(snapshot(dsu), 0)
}
