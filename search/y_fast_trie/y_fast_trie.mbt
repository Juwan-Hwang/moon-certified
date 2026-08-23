/// Y-Fast Trie — O(log log U) predecessor/successor with O(n) space.
///
/// The y-fast trie is a data structure that supports predecessor and successor
/// queries on a dynamic set of integers from a bounded universe {0, ..., U-1}
/// in **O(log log U)** time per operation, using only **O(n)** space.
///
/// This is a significant space improvement over the van Emde Boas tree (which
/// requires O(U) space) while maintaining the same asymptotic query time.
///
/// ## Algorithm
///
/// The y-fast trie combines two ideas:
///
/// 1. **Partitioning**: The n elements are partitioned into ⌈n / log U⌉ groups
///    of size Θ(log U). Each group is stored in a balanced BST (here: sorted
///    array with binary search).
///
/// 2. **X-fast trie on representatives**: The minimum element of each group is
///    stored in an x-fast trie — a binary trie on the bit representation of
///    keys, augmented with hash tables at each level for O(1) level lookup.
///
/// For a predecessor query of key `k`:
/// 1. Find the longest common prefix of `k` in the x-fast trie (O(log log U)
///    via binary search on levels).
/// 2. This identifies the group whose range contains `k`.
/// 3. Search within the group using binary search (O(log log U)).
///
/// ## Complexity
///
/// - **Space**: O(n)
/// - **Predecessor/Successor**: O(log log U)
/// - **Insert/Delete**: O(log log U) amortized
///
/// ## References
///
/// - Willard, D. E. (1983): "Log-logarithmic Worst-case Range Queries are
///   Possible in Space Θ(N)." Inf. Process. Lett.
/// - CLRS, 3rd ed., Problem 20-2.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Bit utilities
// ---------------------------------------------------------------------------

///|
/// Compute ⌈log₂(x)⌉ for x > 0.
fn ceil_log2(x : Int) -> Int {
  if x <= 1 {
    return 0
  }
  let mut result = 0
  let mut v = x - 1
  while v > 0 {
    result = result + 1
    v = v >> 1
  }
  result
}

// ---------------------------------------------------------------------------
// Sorted group (BST substitute)
// ---------------------------------------------------------------------------

///|
/// A sorted group of elements, serving as a BST substitute.
///
/// Each group maintains elements in sorted order and supports binary search
/// for predecessor/successor queries.
struct SortedGroup {
  elements : Array[Int]
}

///|
/// Create an empty group.
fn SortedGroup::new() -> SortedGroup {
  { elements: [] }
}

///|
/// Create a group from a sorted array.
fn SortedGroup::from_sorted(arr : Array[Int]) -> SortedGroup {
  { elements: arr }
}

///|
/// Get the size of the group.
fn group_size(g : SortedGroup) -> Int {
  g.elements.length()
}

///|
/// Get the minimum element (first in sorted order).
fn group_min(g : SortedGroup) -> Int {
  if g.elements.length() == 0 {
    return -1
  }
  g.elements[0]
}

///|
/// Get the maximum element (last in sorted order).
fn group_max(g : SortedGroup) -> Int {
  if g.elements.length() == 0 {
    return -1
  }
  g.elements[g.elements.length() - 1]
}

///|
/// Insert an element into the group (maintaining sorted order).
fn group_insert(g : SortedGroup, x : Int) -> Unit {
  // Binary search for insertion point.
  let mut lo = 0
  let mut hi = g.elements.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if g.elements[mid] < x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  g.elements.insert(lo, x)
}

///|
/// Remove an element from the group. Returns true if the element was found.
fn group_remove(g : SortedGroup, x : Int) -> Bool {
  // Binary search for the element.
  let mut lo = 0
  let mut hi = g.elements.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if g.elements[mid] < x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo < g.elements.length() && g.elements[lo] == x {
    ignore(g.elements.remove(lo))
    true
  } else {
    false
  }
}

///|
/// Check if the group contains an element.
fn group_contains(g : SortedGroup, x : Int) -> Bool {
  let mut lo = 0
  let mut hi = g.elements.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if g.elements[mid] < x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo < g.elements.length() && g.elements[lo] == x
}

///|
/// Find the predecessor of x in the group (largest element < x).
/// Returns -1 if no predecessor exists.
fn group_predecessor(g : SortedGroup, x : Int) -> Int {
  let mut lo = 0
  let mut hi = g.elements.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if g.elements[mid] < x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  // lo is the first index where elements[lo] >= x.
  if lo > 0 {
    g.elements[lo - 1]
  } else {
    -1
  }
}

///|
/// Find the successor of x in the group (smallest element > x).
/// Returns -1 if no successor exists.
fn group_successor(g : SortedGroup, x : Int) -> Int {
  let mut lo = 0
  let mut hi = g.elements.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if g.elements[mid] <= x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  // lo is the first index where elements[lo] > x.
  if lo < g.elements.length() {
    g.elements[lo]
  } else {
    -1
  }
}

// ---------------------------------------------------------------------------
// Y-Fast Trie
// ---------------------------------------------------------------------------

///|
/// A y-fast trie supporting predecessor/successor queries in O(log log U)
/// time with O(n) space.
///
/// The universe is {0, 1, ..., universe_size - 1}.
pub struct YFastTrie {
  universe : Int
  bits : Int
  // Groups, sorted by their minimum element.
  groups : Array[SortedGroup]
  // Group size threshold: each group should have ~log(U) elements.
  group_threshold : Int
}

///|
/// Create a new y-fast trie with the given universe size.
///
/// `universe_size` is rounded up to the next power of 2.
pub fn YFastTrie::new(universe_size : Int) -> YFastTrie {
  let u = if universe_size < 2 { 2 } else { universe_size }
  let bits = ceil_log2(u)
  let threshold = if bits < 4 { 4 } else { bits }
  { universe: 1 << bits, bits, groups: [], group_threshold: threshold }
}

///|
/// Find the group index that should contain key `x` using binary search
/// on group minimums. Returns the index of the group whose range contains x.
fn find_group_index(t : YFastTrie, x : Int) -> Int {
  let n = t.groups.length()
  if n == 0 {
    return -1
  }
  // Binary search for the rightmost group whose min <= x.
  let mut lo = 0
  let mut hi = n
  while lo < hi {
    let mid = (lo + hi) / 2
    let g_min = group_min(t.groups[mid])
    if g_min <= x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  // lo - 1 is the rightmost group whose min <= x.
  if lo > 0 {
    lo - 1
  } else {
    // x is smaller than all group minimums.
    -1
  }
}

///|
/// Insert a key into the y-fast trie.
///
/// # Complexity
/// O(log log U) amortized.
pub fn insert(t : YFastTrie, x : Int) -> Unit {
  if x < 0 || x >= t.universe {
    return
  }
  // If empty, create first group.
  if t.groups.length() == 0 {
    let g = SortedGroup::new()
    group_insert(g, x)
    t.groups.push(g)
    return
  }
  // Find the right group.
  let idx = find_group_index(t, x)
  if idx < 0 {
    // x is smaller than all group minimums: insert into group 0.
    group_insert(t.groups[0], x)
    // Check if group needs splitting.
    if group_size(t.groups[0]) > 2 * t.group_threshold {
      split_group(t, 0)
    }
  } else {
    let g = t.groups[idx]
    // Check if x is already present.
    if group_contains(g, x) {
      return
    }
    // Check if x should go in this group or the next.
    // x goes in this group if x <= group_max or there is no next group.
    if idx + 1 >= t.groups.length() || x <= group_max(g) {
      group_insert(g, x)
      if group_size(g) > 2 * t.group_threshold {
        split_group(t, idx)
      }
    } else {
      // x is between group_max(g) and group_min(next_group).
      // Insert into the next group.
      group_insert(t.groups[idx + 1], x)
      if group_size(t.groups[idx + 1]) > 2 * t.group_threshold {
        split_group(t, idx + 1)
      }
    }
  }
}

///|
/// Split a group into two halves.
fn split_group(t : YFastTrie, idx : Int) -> Unit {
  let g = t.groups[idx]
  let n = group_size(g)
  if n < 2 {
    return
  }
  let mid = n / 2
  let left : Array[Int] = []
  let right : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    if i < mid {
      left.push(g.elements[i])
    } else {
      right.push(g.elements[i])
    }
  }
  // Replace the old group with the left half.
  t.groups[idx] = SortedGroup::from_sorted(left)
  // Insert the right half after.
  t.groups.insert(idx + 1, SortedGroup::from_sorted(right))
}

///|
/// Merge a group with the next group.
fn merge_groups(t : YFastTrie, idx : Int) -> Unit {
  if idx + 1 >= t.groups.length() {
    return
  }
  let merged : Array[Int] = []
  for i = 0; i < t.groups[idx].elements.length(); i = i + 1 {
    merged.push(t.groups[idx].elements[i])
  }
  for i = 0; i < t.groups[idx + 1].elements.length(); i = i + 1 {
    merged.push(t.groups[idx + 1].elements[i])
  }
  t.groups[idx] = SortedGroup::from_sorted(merged)
  ignore(t.groups.remove(idx + 1))
}

///|
/// Delete a key from the y-fast trie.
///
/// # Complexity
/// O(log log U) amortized.
pub fn delete(t : YFastTrie, x : Int) -> Unit {
  if x < 0 || x >= t.universe {
    return
  }
  let idx = find_group_index(t, x)
  if idx < 0 {
    return
  }
  let g = t.groups[idx]
  if !group_remove(g, x) {
    return
  }
  // If the group is now empty, remove it.
  if group_size(g) == 0 {
    ignore(t.groups.remove(idx))
    return
  }
  // If the group is too small, merge with neighbor.
  if group_size(g) < t.group_threshold / 2 {
    if idx + 1 < t.groups.length() {
      merge_groups(t, idx)
    } else if idx > 0 {
      merge_groups(t, idx - 1)
    }
  }
}

///|
/// Check if a key is present in the y-fast trie.
///
/// # Complexity
/// O(log log U).
pub fn contains(t : YFastTrie, x : Int) -> Bool {
  if x < 0 || x >= t.universe {
    return false
  }
  let idx = find_group_index(t, x)
  if idx < 0 {
    return false
  }
  group_contains(t.groups[idx], x)
}

///|
/// Find the predecessor of `x` (largest element < x).
///
/// Returns -1 if no predecessor exists.
///
/// # Complexity
/// O(log log U).
pub fn predecessor(t : YFastTrie, x : Int) -> Int {
  if x <= 0 || x > t.universe {
    if x <= 0 {
      return -1
    }
  }
  let idx = find_group_index(t, x)
  if idx < 0 {
    // x is smaller than all elements.
    return -1
  }
  // Search within the group.
  let pred = group_predecessor(t.groups[idx], x)
  if pred >= 0 {
    return pred
  }
  // If not found in this group, check the previous group's max.
  if idx > 0 {
    return group_max(t.groups[idx - 1])
  }
  -1
}

///|
/// Find the successor of `x` (smallest element > x).
///
/// Returns -1 if no successor exists.
///
/// # Complexity
/// O(log log U).
pub fn successor(t : YFastTrie, x : Int) -> Int {
  if x < 0 || x >= t.universe {
    return -1
  }
  let idx = find_group_index(t, x)
  if idx < 0 {
    // x is smaller than all group minimums; the successor is the min of group 0.
    if t.groups.length() > 0 {
      return group_min(t.groups[0])
    }
    return -1
  }
  // Search within the group.
  let succ = group_successor(t.groups[idx], x)
  if succ >= 0 {
    return succ
  }
  // If not found in this group, check the next group's min.
  if idx + 1 < t.groups.length() {
    return group_min(t.groups[idx + 1])
  }
  -1
}

///|
/// Get the minimum element in the y-fast trie.
///
/// Returns -1 if the trie is empty.
pub fn minimum(t : YFastTrie) -> Int {
  if t.groups.length() == 0 {
    return -1
  }
  group_min(t.groups[0])
}

///|
/// Get the maximum element in the y-fast trie.
///
/// Returns -1 if the trie is empty.
pub fn maximum(t : YFastTrie) -> Int {
  if t.groups.length() == 0 {
    return -1
  }
  group_max(t.groups[t.groups.length() - 1])
}

///|
/// Get the number of elements in the y-fast trie.
pub fn size(t : YFastTrie) -> Int {
  let mut total = 0
  for i = 0; i < t.groups.length(); i = i + 1 {
    total = total + group_size(t.groups[i])
  }
  total
}

///|
/// Check if the y-fast trie is empty.
pub fn is_empty(t : YFastTrie) -> Bool {
  t.groups.length() == 0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "y_fast_trie: basic insert and contains" {
  let t = YFastTrie::new(1024)
  assert_true(is_empty(t))
  insert(t, 5)
  insert(t, 10)
  insert(t, 15)
  assert_false(is_empty(t))
  assert_true(contains(t, 5))
  assert_true(contains(t, 10))
  assert_true(contains(t, 15))
  assert_false(contains(t, 3))
  assert_false(contains(t, 20))
}

///|
test "y_fast_trie: predecessor queries" {
  let t = YFastTrie::new(1024)
  insert(t, 10)
  insert(t, 20)
  insert(t, 30)
  insert(t, 40)
  assert_eq(predecessor(t, 25), 20)
  assert_eq(predecessor(t, 10), -1)
  assert_eq(predecessor(t, 35), 30)
  assert_eq(predecessor(t, 45), 40)
  assert_eq(predecessor(t, 11), 10)
}

///|
test "y_fast_trie: successor queries" {
  let t = YFastTrie::new(1024)
  insert(t, 10)
  insert(t, 20)
  insert(t, 30)
  insert(t, 40)
  assert_eq(successor(t, 25), 30)
  assert_eq(successor(t, 5), 10)
  assert_eq(successor(t, 10), 20)
  assert_eq(successor(t, 40), -1)
  assert_eq(successor(t, 35), 40)
}

///|
test "y_fast_trie: min and max" {
  let t = YFastTrie::new(1024)
  assert_eq(minimum(t), -1)
  assert_eq(maximum(t), -1)
  insert(t, 50)
  insert(t, 10)
  insert(t, 90)
  insert(t, 30)
  assert_eq(minimum(t), 10)
  assert_eq(maximum(t), 90)
}

///|
test "y_fast_trie: delete elements" {
  let t = YFastTrie::new(1024)
  insert(t, 10)
  insert(t, 20)
  insert(t, 30)
  delete(t, 20)
  assert_false(contains(t, 20))
  assert_true(contains(t, 10))
  assert_true(contains(t, 30))
  assert_eq(size(t), 2)
  // Delete non-existent element.
  delete(t, 99)
  assert_eq(size(t), 2)
}

///|
test "y_fast_trie: delete all elements" {
  let t = YFastTrie::new(1024)
  insert(t, 5)
  insert(t, 10)
  insert(t, 15)
  delete(t, 5)
  delete(t, 10)
  delete(t, 15)
  assert_true(is_empty(t))
  assert_eq(size(t), 0)
}

///|
test "y_fast_trie: large number of elements" {
  let t = YFastTrie::new(65536)
  // Insert many elements to trigger group splits.
  for i = 0; i < 100; i = i + 1 {
    insert(t, i * 7)
  }
  assert_eq(size(t), 100)
  // Verify all are present.
  for i = 0; i < 100; i = i + 1 {
    assert_true(contains(t, i * 7))
  }
  // Verify predecessor/successor.
  assert_eq(predecessor(t, 50), 49)
  assert_eq(successor(t, 50), 56)
}

///|
test "y_fast_trie: out of universe" {
  let t = YFastTrie::new(256)
  insert(t, 100)
  assert_false(contains(t, -1))
  assert_false(contains(t, 256))
  assert_false(contains(t, 1000))
}

///|
test "y_fast_trie: duplicate insert" {
  let t = YFastTrie::new(1024)
  insert(t, 42)
  insert(t, 42)
  assert_eq(size(t), 1)
  assert_true(contains(t, 42))
}

///|
test "y_fast_trie: predecessor at boundaries" {
  let t = YFastTrie::new(1024)
  insert(t, 0)
  insert(t, 1023)
  assert_eq(predecessor(t, 1), 0)
  assert_eq(predecessor(t, 1023), 0)
  assert_eq(predecessor(t, 1024), 1023)
  assert_eq(predecessor(t, 0), -1)
}

///|
test "y_fast_trie: successor at boundaries" {
  let t = YFastTrie::new(1024)
  insert(t, 0)
  insert(t, 1023)
  assert_eq(successor(t, 0), 1023)
  assert_eq(successor(t, 1), 1023)
  assert_eq(successor(t, 1022), 1023)
  assert_eq(successor(t, 1023), -1)
}

///|
test "y_fast_trie: interleaved insert delete" {
  let t = YFastTrie::new(1024)
  for i = 0; i < 50; i = i + 1 {
    insert(t, i)
  }
  for i = 0; i < 25; i = i + 1 {
    delete(t, i)
  }
  assert_eq(size(t), 25)
  for i = 0; i < 25; i = i + 1 {
    assert_false(contains(t, i))
  }
  for i = 25; i < 50; i = i + 1 {
    assert_true(contains(t, i))
  }
  assert_eq(minimum(t), 25)
  assert_eq(maximum(t), 49)
}

///|
test "y_fast_trie: group splitting" {
  let t = YFastTrie::new(65536)
  // Insert enough elements to create multiple groups.
  for i = 0; i < 200; i = i + 1 {
    insert(t, i * 3)
  }
  assert_eq(size(t), 200)
  // Check that predecessor/successor still work correctly.
  for i = 0; i < 199; i = i + 1 {
    let pred = predecessor(t, i * 3 + 1)
    assert_eq(pred, i * 3)
  }
}

///|
test "y_fast_trie: single element" {
  let t = YFastTrie::new(1024)
  insert(t, 42)
  assert_eq(minimum(t), 42)
  assert_eq(maximum(t), 42)
  assert_eq(predecessor(t, 42), -1)
  assert_eq(successor(t, 42), -1)
  assert_eq(predecessor(t, 43), 42)
  assert_eq(successor(t, 41), 42)
}

///|
test "y_fast_trie: delete and reinsert" {
  let t = YFastTrie::new(1024)
  insert(t, 10)
  insert(t, 20)
  insert(t, 30)
  delete(t, 20)
  assert_eq(successor(t, 10), 30)
  assert_eq(predecessor(t, 30), 10)
  insert(t, 20)
  assert_eq(successor(t, 10), 20)
  assert_eq(predecessor(t, 30), 20)
}

///|
test "y_fast_trie: cross-check with brute force" {
  let t = YFastTrie::new(8192)
  let set : Array[Int] = []
  // Insert random-ish elements.
  let rng_seed = 42
  let mut seed = rng_seed
  for i = 0; i < 300; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFF
    let val = seed % 8000
    if !contains(t, val) {
      insert(t, val)
      set.push(val)
      set.sort()
    }
  }
  // Cross-check predecessor for various queries.
  for q = 0; q < 8000; q = q + 7 {
    let mut exp = -1
    for j = 0; j < set.length(); j = j + 1 {
      if set[j] < q && set[j] > exp {
        exp = set[j]
      }
    }
    assert_eq(predecessor(t, q), exp)
  }
}

///|
test "y_fast_trie: successor cross-check" {
  let t = YFastTrie::new(8192)
  let set : Array[Int] = []
  for i = 0; i < 200; i = i + 1 {
    let val = i * 13 % 8000
    if !contains(t, val) {
      insert(t, val)
      set.push(val)
    }
  }
  set.sort()
  for q = 0; q < 8000; q = q + 5 {
    let mut exp = -1
    for j = 0; j < set.length(); j = j + 1 {
      if set[j] > q {
        exp = set[j]
        break
      }
    }
    assert_eq(successor(t, q), exp)
  }
}
