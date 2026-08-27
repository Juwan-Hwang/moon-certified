/// Wavelet Tree — succinct sequence data structure.
///
/// A wavelet tree stores a sequence over an alphabet and supports rank,
/// select, and access queries in O(log σ) time where σ is the alphabet
/// size. It uses O(n log σ) bits of space.
///
/// ## Supported operations
///
/// - `access(i)`: Get the character at position `i`.
/// - `rank(c, i)`: Count occurrences of character `c` in positions `[0, i)`.
/// - `select(c, k)`: Find the position of the k-th occurrence of `c`.
/// - `range_count(l, r, c)`: Count occurrences of `c` in `[l, r)`.
///
/// ## Complexity
///
/// - Build: O(n log σ).
/// - Access/Rank/Select: O(log σ).
/// - Space: O(n log σ) bits.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A node in the wavelet tree.
struct WTNode {
  bitvector : FixedArray[Bool] // bit[i] = true if character goes right
  prefix_sum : FixedArray[Int] // prefix_sum[i] = count of true in [0..i)
  select0 : FixedArray[Int] // select0[k] = position of k-th 0 (0-indexed)
  select1 : FixedArray[Int] // select1[k] = position of k-th 1 (0-indexed)
  mut left_child : Int // index of left child, -1 if leaf
  mut right_child : Int // index of right child, -1 if leaf
  lo_alpha : Int // min alphabet index in this node's range
  hi_alpha : Int // max alphabet index in this node's range
}

///|
/// The wavelet tree.
pub struct WaveletTree {
  priv nodes : Array[WTNode]
  priv n : Int
  priv alphabet : Array[Int] // sorted unique character codes
  priv char_index : Map[Int, Int] // char code → alphabet index
}

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------

///|
/// Build a wavelet tree from a string.
pub fn build(text : String) -> WaveletTree {
  let n = text.length()
  if n == 0 {
    return { nodes: [], n: 0, alphabet: [], char_index: Map([]), }
  }
  // Collect and sort alphabet.
  let char_set : Map[Int, Unit] = Map([])
  for i = 0; i < n; i = i + 1 {
    char_set[text[i].to_int()] = ()
  }
  let alphabet : Array[Int] = []
  for c, _ in char_set {
    alphabet.push(c)
  }
  alphabet.sort_by(fn(a, b) { a - b })
  // Map each character to its index in the sorted alphabet.
  let char_index : Map[Int, Int] = Map([])
  for i = 0; i < alphabet.length(); i = i + 1 {
    char_index[alphabet[i]] = i
  }
  // Build indices: for each position, store the alphabet index.
  let indices = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    match char_index.get(text[i].to_int()) {
      Some(idx) => indices[i] = idx
      None => ()
    }
  }
  // Build the tree recursively.
  let nodes : Array[WTNode] = []
  let _ = build_node(nodes, indices, 0, n, 0, alphabet.length() - 1, alphabet)
  { nodes, n, alphabet, char_index, }
}

///|
/// Recursively build a wavelet tree node.
fn build_node(
  nodes : Array[WTNode],
  indices : FixedArray[Int],
  start : Int,
  end : Int,
  lo_alpha : Int,
  hi_alpha : Int,
  alphabet : Array[Int],
) -> Int {
  let node_idx = nodes.length()
  if lo_alpha == hi_alpha {
    // Leaf node: no bitvector needed.
    nodes.push({
      bitvector: FixedArray::make(0, false),
      prefix_sum: FixedArray::make(1, 0),
      select0: FixedArray::make(0, 0),
      select1: FixedArray::make(0, 0),
      left_child: -1,
      right_child: -1,
      lo_alpha,
      hi_alpha,
    })
    return node_idx
  }
  let mid = (lo_alpha + hi_alpha) / 2
  // Build bitvector: bit = true if index > mid (goes right).
  let len = end - start
  let bv = FixedArray::make(len, false)
  for i = 0; i < len; i = i + 1 {
    bv[i] = indices[start + i] > mid
  }
  // Build prefix sum: ps[i] = number of 1s in [0, i).
  let ps = FixedArray::make(len + 1, 0)
  let mut zero_count = 0
  let mut one_count = 0
  for i = 0; i < len; i = i + 1 {
    ps[i + 1] = ps[i] + (if bv[i] { 1 } else { 0 })
    if bv[i] {
      one_count = one_count + 1
    } else {
      zero_count = zero_count + 1
    }
  }
  // Precompute select0 and select1 arrays for O(1) select at each level.
  // select0[k] = position of the k-th 0 (0-indexed).
  // select1[k] = position of the k-th 1 (0-indexed).
  let sel0 = FixedArray::make(zero_count, 0)
  let sel1 = FixedArray::make(one_count, 0)
  let mut z = 0
  let mut o = 0
  for i = 0; i < len; i = i + 1 {
    if bv[i] {
      sel1[o] = i
      o = o + 1
    } else {
      sel0[z] = i
      z = z + 1
    }
  }
  // Partition indices: left (≤ mid), right (> mid).
  let left_indices = FixedArray::make(len, 0)
  let right_indices = FixedArray::make(len, 0)
  let mut left_count = 0
  let mut right_count = 0
  for i = 0; i < len; i = i + 1 {
    if bv[i] {
      right_indices[right_count] = indices[start + i]
      right_count = right_count + 1
    } else {
      left_indices[left_count] = indices[start + i]
      left_count = left_count + 1
    }
  }
  nodes.push({
    bitvector: bv,
    prefix_sum: ps,
    select0: sel0,
    select1: sel1,
    left_child: -1, // will be set after children are built
    right_child: -1,
    lo_alpha,
    hi_alpha,
  })
  // Build children.
  let left_idx = build_node(
    nodes, left_indices, 0, left_count, lo_alpha, mid, alphabet,
  )
  let right_idx = build_node(
    nodes,
    right_indices,
    0,
    right_count,
    mid + 1,
    hi_alpha,
    alphabet,
  )
  nodes[node_idx].left_child = left_idx
  nodes[node_idx].right_child = right_idx
  node_idx
}

// ---------------------------------------------------------------------------
// Operations
// ---------------------------------------------------------------------------

///|
/// Access the character at position `i` (0-indexed).
/// Returns the character code as `Int`.
pub fn access(tree : WaveletTree, i : Int) -> Int? {
  if i < 0 || i >= tree.n || tree.nodes.length() == 0 {
    return None
  }
  let mut node_idx = 0
  let mut pos = i
  while node_idx >= 0 && node_idx < tree.nodes.length() {
    let node = tree.nodes[node_idx]
    if node.left_child == -1 {
      // Leaf: return the character at this alphabet index.
      return Some(tree.alphabet[node.lo_alpha])
    }
    let bit = node.bitvector[pos]
    if bit {
      // Go right: new position = number of 1s in [0, pos).
      pos = node.prefix_sum[pos]
      node_idx = node.right_child
    } else {
      // Go left: new position = number of 0s in [0, pos) = pos - prefix_sum[pos].
      pos = pos - node.prefix_sum[pos]
      node_idx = node.left_child
    }
  }
  None
}

///|
/// Count occurrences of character `c` in positions `[0, i)`.
pub fn rank(tree : WaveletTree, c : Int, i : Int) -> Int {
  if i <= 0 || tree.nodes.length() == 0 {
    return 0
  }
  // Look up the alphabet index for character c.
  let ci = match tree.char_index.get(c) {
    Some(idx) => idx
    None => return 0
  }
  let mut node_idx = 0
  let mut pos = if i > tree.n { tree.n } else { i }
  while node_idx >= 0 && node_idx < tree.nodes.length() {
    let node = tree.nodes[node_idx]
    if node.left_child == -1 {
      // Leaf: all positions in this node have the same character.
      return pos
    }
    let mid = (node.lo_alpha + node.hi_alpha) / 2
    if ci <= mid {
      // Go left: new position = number of 0s in [0, pos).
      pos = pos - node.prefix_sum[pos]
      node_idx = node.left_child
    } else {
      // Go right: new position = number of 1s in [0, pos).
      pos = node.prefix_sum[pos]
      node_idx = node.right_child
    }
    if pos == 0 {
      return 0
    }
  }
  0
}

///|
/// Find the position of the k-th (0-indexed) occurrence of character `c`.
/// Returns the 0-indexed position, or `None` if there aren't k+1 occurrences.
///
/// Uses a recursive top-down traversal that composes select0/select1
/// lookups on the way back up, achieving O(log σ) time complexity.
pub fn select(tree : WaveletTree, c : Int, k : Int) -> Int? {
  if k < 0 || tree.nodes.length() == 0 {
    return None
  }
  let alpha_idx = match tree.char_index.get(c) {
    Some(idx) => idx
    None => return None
  }
  // Check that there are at least k+1 occurrences.
  let total = rank(tree, c, tree.n)
  if k >= total {
    return None
  }
  Some(select_helper(tree, 0, alpha_idx, k))
}

///|
/// Recursive helper: returns the position of the k-th occurrence of the
/// character with alphabet index `alpha_idx` in the subtree rooted at
/// `node_idx`, expressed as a position in that node's subsequence.
fn select_helper(
  tree : WaveletTree,
  node_idx : Int,
  alpha_idx : Int,
  k : Int,
) -> Int {
  let node = tree.nodes[node_idx]
  if node.left_child == -1 {
    // Leaf: the k-th occurrence is at position k in this node's subsequence.
    return k
  }
  let mid = (node.lo_alpha + node.hi_alpha) / 2
  if alpha_idx <= mid {
    // Character goes left: recurse into left child, then map back via select0.
    let child_pos = select_helper(tree, node.left_child, alpha_idx, k)
    node.select0[child_pos]
  } else {
    // Character goes right: recurse into right child, then map back via select1.
    let child_pos = select_helper(tree, node.right_child, alpha_idx, k)
    node.select1[child_pos]
  }
}

///|
/// Count occurrences of character `c` in positions `[l, r)`.
pub fn range_count(tree : WaveletTree, l : Int, r : Int, c : Int) -> Int {
  if l >= r || l < 0 || r > tree.n {
    return 0
  }
  rank(tree, c, r) - rank(tree, c, l)
}

///|
/// The length of the indexed sequence.
pub fn length(tree : WaveletTree) -> Int {
  tree.n
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "wavelet: access" {
  let wt = build("banana")
  assert_eq(access(wt, 0), Some('b'.to_int()))
  assert_eq(access(wt, 1), Some('a'.to_int()))
  assert_eq(access(wt, 2), Some('n'.to_int()))
  assert_eq(access(wt, 5), Some('a'.to_int()))
}

///|
test "wavelet: rank" {
  let wt = build("banana")
  assert_eq(rank(wt, 'a'.to_int(), 6), 3)
  assert_eq(rank(wt, 'a'.to_int(), 3), 1)
  assert_eq(rank(wt, 'n'.to_int(), 6), 2)
  assert_eq(rank(wt, 'b'.to_int(), 6), 1)
}

///|
test "wavelet: select" {
  let wt = build("banana")
  assert_eq(select(wt, 'a'.to_int(), 0), Some(1))
  assert_eq(select(wt, 'a'.to_int(), 1), Some(3))
  assert_eq(select(wt, 'a'.to_int(), 2), Some(5))
  assert_eq(select(wt, 'a'.to_int(), 3), None)
}

///|
test "wavelet: range_count" {
  let wt = build("mississippi")
  assert_eq(range_count(wt, 0, 11, 's'.to_int()), 4)
  assert_eq(range_count(wt, 0, 5, 's'.to_int()), 2)
  assert_eq(range_count(wt, 5, 11, 'i'.to_int()), 2)
}

///|
test "wavelet: single character string" {
  let wt = build("a")
  assert_eq(access(wt, 0), Some('a'.to_int()))
  assert_eq(rank(wt, 'a'.to_int(), 1), 1)
  assert_eq(rank(wt, 'a'.to_int(), 0), 0)
}

///|
test "wavelet: all same characters" {
  let wt = build("aaaa")
  assert_eq(rank(wt, 'a'.to_int(), 4), 4)
  assert_eq(rank(wt, 'a'.to_int(), 2), 2)
  assert_eq(select(wt, 'a'.to_int(), 2), Some(2))
}

///|
test "wavelet: out of bounds" {
  let wt = build("hello")
  assert_eq(access(wt, -1), None)
  assert_eq(access(wt, 100), None)
  assert_eq(rank(wt, 'h'.to_int(), 0), 0)
}

///|
test "wavelet: length" {
  let wt = build("banana")
  assert_eq(length(wt), 6)
}
