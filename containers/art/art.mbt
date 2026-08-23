/// Adaptive Radix Tree (ART) — cache-friendly ordered index for byte-array keys.
///
/// This is a production-grade implementation of the Adaptive Radix Tree as
/// described by Leis et al. (2013). Key design properties:
///
/// - **Adaptive node sizes**: Inner nodes use Nod1.0e4 (≤4 children), Nod1.0e16
///   (≤16), Nod1.0e48 (≤48), or Nod1.0e256 (≤256), automatically growing and
///   shrinking to minimise memory per node while keeping lookups fast.
/// - **Path compression**: Partial key bytes are stored in each inner node so
///   that long single-child chains are collapsed into one node.
/// - **Lazy expansion**: A leaf is only split into an inner node when two keys
///   diverge at that depth, avoiding unnecessary inner nodes.
///
/// ## Complexity
///
/// | Operation  | Time (average) | Time (worst) |
/// |------------|----------------|--------------|
/// | `insert`   | O(m)           | O(m)         |
/// | `get`      | O(m)           | O(m)         |
/// | `remove`   | O(m)           | O(m)         |
/// | `size`     | O(1)           | O(1)         |
///
/// where `m` = key length in bytes.
///
/// ## References
///
/// - Leis, V., Kemper, A., & Neumann, T. (2013). "The Adaptive Radix Tree:
///   ARTful Indexing for Main-Memory Databases." *ICDE 2013*, 38–49.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Node type constants
// ---------------------------------------------------------------------------

///|
/// Node kind: 0 = leaf, 4/16/48/256 = inner node with that capacity.
const KIND_LEAF : Int = 0

///|
const KIND_N4 : Int = 4

///|
const KIND_N16 : Int = 16

///|
const KIND_N48 : Int = 48

///|
const KIND_N256 : Int = 256

///|
/// Maximum partial key length stored per inner node.
const MAX_PREFIX_LEN : Int = 10

// ---------------------------------------------------------------------------
// Node structure
// ---------------------------------------------------------------------------

///|
/// An ART node. Can be either a leaf (storing a full key + value) or an inner
/// node (with adaptive capacity children).
///
/// Inner nodes use:
/// - `keys` + `children` arrays for Nod1.0e4/Nod1.0e16 (sorted by byte value).
/// - `index` (256-entry byte→slot map) + `children` for Nod1.0e48.
/// - `children` (256-entry direct map) for Nod1.0e256.
pub struct ArtNode {
  /// KIND_LEAF, KIND_N4, KIND_N16, KIND_N48, or KIND_N256.
  mut kind : Int
  // --- Leaf fields ---
  mut key : Array[Int]
  mut val : Int
  // --- Inner node fields ---
  /// Path-compressed partial key bytes.
  mut partial : Array[Int]
  /// Number of valid bytes in `partial`.
  mut partial_len : Int
  /// Number of children currently stored.
  mut num_children : Int
  /// Sorted byte keys for Nod1.0e4/Nod1.0e16.
  mut keys : Array[Int]
  /// Children array (sized to node capacity).
  mut children : Array[ArtNode]
  /// 256-entry index for Nod1.0e48: `index[byte]` = child slot+1, or 0 = empty.
  mut index : Array[Int]
}

///|
/// Create a new leaf node.
fn make_leaf(key : Array[Int], val : Int) -> ArtNode {
  {
    kind: KIND_LEAF,
    key: Array::copy(key),
    val,
    partial: [],
    partial_len: 0,
    num_children: 0,
    keys: [],
    children: [],
    index: [],
  }
}

///|
/// Create a new inner node with the given capacity.
fn make_inner(
  capacity : Int,
  partial : Array[Int],
  partial_len : Int,
) -> ArtNode {
  let p = Array::make(MAX_PREFIX_LEN, 0)
  let copy_len = if partial_len < MAX_PREFIX_LEN {
    partial_len
  } else {
    MAX_PREFIX_LEN
  }
  for i = 0; i < copy_len; i = i + 1 {
    p[i] = partial[i]
  }
  {
    kind: capacity,
    key: [],
    val: 0,
    partial: p,
    partial_len,
    num_children: 0,
    keys: Array::make(capacity, 0),
    children: Array::make(capacity, make_null()),
    index: if capacity == KIND_N48 {
      Array::make(256, 0)
    } else {
      []
    },
  }
}

///|
/// Create a null/placeholder node (used to fill unused slots).
fn make_null() -> ArtNode {
  {
    kind: -1,
    key: [],
    val: 0,
    partial: [],
    partial_len: 0,
    num_children: 0,
    keys: [],
    children: [],
    index: [],
  }
}

// ---------------------------------------------------------------------------
// ART (root wrapper)
// ---------------------------------------------------------------------------

///|
/// The Adaptive Radix Tree root.
pub struct Art {
  mut root : ArtNode
  mut size : Int
}

///|
/// Create an empty ART.
pub fn art_new() -> Art {
  { root: make_null(), size: 0 }
}

///|
/// Return the number of stored key-value pairs.
pub fn art_size(tree : Art) -> Int {
  tree.size
}

// ---------------------------------------------------------------------------
// Inner node operations
// ---------------------------------------------------------------------------

///|
/// Find a child by byte value in an inner node. Returns the slot index or -1.
fn find_child(node : ArtNode, byte : Int) -> Int {
  match node.kind {
    KIND_N4 | KIND_N16 => {
      // Linear search through sorted keys
      for i = 0; i < node.num_children; i = i + 1 {
        if node.keys[i] == byte {
          return i
        }
      }
      -1
    }
    KIND_N48 => {
      let idx = node.index[byte]
      if idx == 0 {
        -1
      } else {
        idx - 1
      }
    }
    KIND_N256 => {
      let child = node.children[byte]
      if child.kind == -1 {
        -1
      } else {
        byte
      }
    }
    _ => -1
  }
}

///|
/// Get a child by byte value. Returns the child node or None.
fn get_child(node : ArtNode, byte : Int) -> ArtNode? {
  let slot = find_child(node, byte)
  if slot < 0 {
    return None
  }
  match node.kind {
    KIND_N256 => Some(node.children[byte])
    _ => Some(node.children[slot])
  }
}

///|
/// Add a child to an inner node. Grows the node if it's full.
fn add_child(node : ArtNode, byte : Int, child : ArtNode) -> Unit {
  // Check if we need to grow
  if node.num_children >= node.kind {
    grow_node(node)
  }
  match node.kind {
    KIND_N4 => {
      // Insert in sorted order
      let mut i = 0
      while i < node.num_children && node.keys[i] < byte {
        i = i + 1
      }
      // Shift right
      let mut j = node.num_children
      while j > i {
        node.keys[j] = node.keys[j - 1]
        node.children[j] = node.children[j - 1]
        j = j - 1
      }
      node.keys[i] = byte
      node.children[i] = child
      node.num_children = node.num_children + 1
    }
    KIND_N16 => {
      let mut i = 0
      while i < node.num_children && node.keys[i] < byte {
        i = i + 1
      }
      let mut j = node.num_children
      while j > i {
        node.keys[j] = node.keys[j - 1]
        node.children[j] = node.children[j - 1]
        j = j - 1
      }
      node.keys[i] = byte
      node.children[i] = child
      node.num_children = node.num_children + 1
    }
    KIND_N48 => {
      let mut slot = 0
      // Find first empty slot
      let mut found = false
      for i = 0; i < KIND_N48; i = i + 1 {
        if node.children[i].kind == -1 {
          slot = i
          found = true
          break
        }
      }
      if !found {
        slot = node.num_children
      }
      node.children[slot] = child
      node.index[byte] = slot + 1
      node.num_children = node.num_children + 1
    }
    KIND_N256 => {
      node.children[byte] = child
      node.num_children = node.num_children + 1
    }
    _ => abort("add_child on non-inner node")
  }
}

///|
/// Grow a node to the next capacity. Reallocates keys/children/index.
fn grow_node(node : ArtNode) -> Unit {
  let old_kind = node.kind
  let new_kind = match old_kind {
    KIND_N4 => KIND_N16
    KIND_N16 => KIND_N48
    KIND_N48 => KIND_N256
    _ => abort("grow_node: cannot grow Nod1.0e256")
  }
  // Save old data
  let old_keys = node.keys
  let old_children = node.children
  let old_index = node.index
  let old_num = node.num_children
  // Allocate new arrays
  let new_keys = Array::make(new_kind, 0)
  let new_children = Array::make(new_kind, make_null())
  let new_index = if new_kind == KIND_N48 { Array::make(256, 0) } else { [] }
  // Transfer children
  match new_kind {
    KIND_N16 =>
      // Just copy keys and children (same layout, bigger arrays)
      for i = 0; i < old_num; i = i + 1 {
        new_keys[i] = old_keys[i]
        new_children[i] = old_children[i]
      }
    KIND_N48 =>
      // From Nod1.0e16: build index
      for i = 0; i < old_num; i = i + 1 {
        new_children[i] = old_children[i]
        new_index[old_keys[i]] = i + 1
      }
    KIND_N256 =>
      // From Nod1.0e48: expand to direct map
      for b = 0; b < 256; b = b + 1 {
        let idx = old_index[b]
        if idx > 0 {
          new_children[b] = old_children[idx - 1]
        }
      }
    _ => abort("grow_node: unexpected new_kind")
  }
  node.kind = new_kind
  node.keys = new_keys
  node.children = new_children
  node.index = new_index
}

///|
/// Remove a child from an inner node by byte value. Returns the removed child.
/// Shrinks the node if it becomes too small.
fn remove_child(node : ArtNode, byte : Int) -> ArtNode {
  let slot = find_child(node, byte)
  if slot < 0 {
    return make_null()
  }
  let removed = match node.kind {
    KIND_N4 | KIND_N16 => {
      let r = node.children[slot]
      // Shift left
      let mut i = slot
      while i < node.num_children - 1 {
        node.keys[i] = node.keys[i + 1]
        node.children[i] = node.children[i + 1]
        i = i + 1
      }
      node.children[node.num_children - 1] = make_null()
      node.num_children = node.num_children - 1
      r
    }
    KIND_N48 => {
      let r = node.children[slot]
      node.children[slot] = make_null()
      node.index[byte] = 0
      node.num_children = node.num_children - 1
      r
    }
    KIND_N256 => {
      let r = node.children[byte]
      node.children[byte] = make_null()
      node.num_children = node.num_children - 1
      r
    }
    _ => abort("remove_child on non-inner node")
  }
  // Check if we should shrink
  let threshold = match node.kind {
    KIND_N16 => 4
    KIND_N48 => 16
    KIND_N256 => 48
    _ => 0 // Nod1.0e4 doesn't shrink (it becomes a leaf or is removed)
  }
  if node.kind != KIND_N4 && node.num_children <= threshold {
    shrink_node(node)
  }
  removed
}

///|
/// Shrink a node to the next smaller capacity.
fn shrink_node(node : ArtNode) -> Unit {
  let old_kind = node.kind
  let new_kind = match old_kind {
    KIND_N16 => KIND_N4
    KIND_N48 => KIND_N4 // Nod1.0e48 → Nod1.0e4 (skip Nod1.0e16 for simplicity)
    KIND_N256 => KIND_N48
    _ => return
  }
  let old_children = node.children
  let old_index = node.index
  let old_num = node.num_children
  let new_keys = Array::make(new_kind, 0)
  let new_children = Array::make(new_kind, make_null())
  let new_index = if new_kind == KIND_N48 { Array::make(256, 0) } else { [] }
  match old_kind {
    KIND_N16 =>
      for i = 0; i < old_num; i = i + 1 {
        new_keys[i] = node.keys[i]
        new_children[i] = old_children[i]
      }
    KIND_N48 => {
      // Collect non-null children
      let mut idx = 0
      for b = 0; b < 256 && idx < old_num; b = b + 1 {
        let s = old_index[b]
        if s > 0 {
          new_keys[idx] = b
          new_children[idx] = old_children[s - 1]
          idx = idx + 1
        }
      }
    }
    KIND_N256 => {
      // Build Nod1.0e48 index
      let mut idx = 0
      for b = 0; b < 256 && idx < old_num; b = b + 1 {
        let c = old_children[b]
        if c.kind != -1 {
          new_children[idx] = c
          new_index[b] = idx + 1
          idx = idx + 1
        }
      }
    }
    _ => abort("shrink_node: unexpected old_kind")
  }
  node.kind = new_kind
  node.keys = new_keys
  node.children = new_children
  node.index = new_index
}

// ---------------------------------------------------------------------------
// Key comparison helpers
// ---------------------------------------------------------------------------

///|
/// Compare a key against the partial key stored in an inner node.
/// Returns the number of matching bytes.
fn check_prefix(node : ArtNode, key : Array[Int], depth : Int) -> Int {
  let max_cmp = if node.partial_len < MAX_PREFIX_LEN {
    node.partial_len
  } else {
    MAX_PREFIX_LEN
  }
  let mut idx = 0
  while idx < max_cmp &&
        depth + idx < key.length() &&
        node.partial[idx] == key[depth + idx] {
    idx = idx + 1
  }
  idx
}

// ---------------------------------------------------------------------------
// Public API: Insert
// ---------------------------------------------------------------------------

///|
/// Insert a key-value pair into the ART.
///
/// If the key already exists, the value is updated and the old value is
/// returned. Otherwise `None` is returned.
///
/// Key is an `Array[Int]` where each element is a byte value (0–255).
pub fn art_insert(tree : Art, key : Array[Int], val : Int) -> Int? {
  if tree.root.kind == -1 {
    tree.root = make_leaf(key, val)
    tree.size = 1
    return None
  }
  let old = insert_recursive(tree.root, key, val, 0)
  if old is None {
    tree.size = tree.size + 1
  }
  old
}

///|
/// Recursive insert. Returns old value if key existed, None otherwise.
fn insert_recursive(
  node : ArtNode,
  key : Array[Int],
  val : Int,
  depth : Int,
) -> Int? {
  // If node is a leaf, we may need to split
  if node.kind == KIND_LEAF {
    // Check if keys are identical
    if keys_equal(node.key, key) {
      let old = node.val
      node.val = val
      return Some(old)
    }
    // Need to split this leaf into an inner node.
    // CRITICAL: Create a fresh leaf copy of the old data BEFORE modifying node,
    // because node and leaf1 would alias the same struct.
    let leaf1 = make_leaf(node.key, node.val)
    let leaf2 = make_leaf(key, val)
    // Find the divergence point
    let mut d = depth
    while d < leaf1.key.length() &&
          d < leaf2.key.length() &&
          leaf1.key[d] == leaf2.key[d] {
      d = d + 1
    }
    // Store the common prefix as partial key
    let prefix_len = d - depth
    let p = Array::make(MAX_PREFIX_LEN, 0)
    let copy_len = if prefix_len < MAX_PREFIX_LEN {
      prefix_len
    } else {
      MAX_PREFIX_LEN
    }
    for i = 0; i < copy_len; i = i + 1 {
      p[i] = leaf1.key[depth + i]
    }
    // Add both children
    let b1 = if d < leaf1.key.length() { leaf1.key[d] } else { -1 }
    let b2 = if d < leaf2.key.length() { leaf2.key[d] } else { -1 }
    // Transform node into a Nod1.0e4 inner node in-place
    node.kind = KIND_N4
    node.key = []
    node.val = 0
    node.partial = p
    node.partial_len = prefix_len
    node.num_children = 0
    node.keys = Array::make(KIND_N4, 0)
    node.children = Array::make(KIND_N4, make_null())
    node.index = []
    // Add both children to the now-inner node
    if b1 == -1 {
      add_child(node, 0, leaf1)
      add_child(node, b2, leaf2)
    } else if b2 == -1 {
      add_child(node, b1, leaf1)
      add_child(node, 0, leaf2)
    } else {
      add_child(node, b1, leaf1)
      add_child(node, b2, leaf2)
    }
    return None
  }
  // Inner node: check partial key match
  let matched = check_prefix(node, key, depth)
  if matched != node.partial_len {
    // Partial key mismatch — need to split this inner node.
    // Create a copy of the old node's data, then transform node in-place.
    let old_kind = node.kind
    let old_num = node.num_children
    let old_keys = Array::copy(node.keys)
    let old_children = Array::copy(node.children)
    let old_index = if node.index.length() > 0 {
      Array::copy(node.index)
    } else {
      []
    }
    let old_partial_len = node.partial_len
    let old_partial = Array::copy(node.partial)
    // The byte at which the old node diverges
    let old_byte = if matched < MAX_PREFIX_LEN {
      old_partial[matched]
    } else {
      0
    }
    let new_old_partial_len = old_partial_len - matched - 1
    let new_old_partial = Array::make(MAX_PREFIX_LEN, 0)
    for i = 0; i < new_old_partial_len && i < MAX_PREFIX_LEN; i = i + 1 {
      new_old_partial[i] = old_partial[matched + 1 + i]
    }
    // Create the old node as a separate child node
    let old_node_copy = make_inner(
      old_kind, new_old_partial, new_old_partial_len,
    )
    old_node_copy.num_children = old_num
    old_node_copy.keys = old_keys
    old_node_copy.children = old_children
    old_node_copy.index = old_index
    // Create the new leaf for the inserting key
    let new_leaf = make_leaf(key, val)
    // The byte at which the new leaf diverges
    let new_byte = if depth + matched < key.length() {
      key[depth + matched]
    } else {
      -1
    }
    // Transform node into a new Nod1.0e4 with the common prefix
    node.kind = KIND_N4
    node.partial = Array::make(MAX_PREFIX_LEN, 0)
    for i = 0; i < matched && i < MAX_PREFIX_LEN; i = i + 1 {
      node.partial[i] = old_partial[i]
    }
    node.partial_len = matched
    node.num_children = 0
    node.keys = Array::make(KIND_N4, 0)
    node.children = Array::make(KIND_N4, make_null())
    node.index = []
    // Add both children
    if old_byte >= 0 {
      add_child(node, old_byte, old_node_copy)
    } else {
      add_child(node, 0, old_node_copy)
    }
    if new_byte >= 0 {
      add_child(node, new_byte, new_leaf)
    } else {
      add_child(node, 0, new_leaf)
    }
    return None
  }
  // Partial key fully matched — descend
  let new_depth = depth + node.partial_len
  if new_depth >= key.length() {
    // Key is a prefix of the stored path — check if there's a leaf at byte 0
    let slot = find_child(node, 0)
    if slot >= 0 {
      let child = node.children[slot]
      if child.kind == KIND_LEAF {
        let old = child.val
        child.val = val
        return Some(old)
      }
    }
    // No existing value — insert a leaf at byte 0
    add_child(node, 0, make_leaf(key, val))
    return None
  }
  let byte = key[new_depth]
  let slot = find_child(node, byte)
  if slot >= 0 {
    // Descend into existing child
    let child = match node.kind {
      KIND_N256 => node.children[byte]
      _ => node.children[slot]
    }
    let result = insert_recursive(child, key, val, new_depth + 1)
    // Write back (in case child was transformed from leaf to inner)
    match node.kind {
      KIND_N256 => node.children[byte] = child
      _ => node.children[slot] = child
    }
    return result
  }
  // No child at this byte — add a new leaf
  add_child(node, byte, make_leaf(key, val))
  return None
}

// ---------------------------------------------------------------------------
// Public API: Get
// ---------------------------------------------------------------------------

///|
/// Look up a key in the ART. Returns `Some(value)` or `None`.
pub fn art_get(tree : Art, key : Array[Int]) -> Int? {
  if tree.root.kind == -1 {
    return None
  }
  find_leaf(tree.root, key, 0)
}

///|
/// Recursively find the leaf for a key.
fn find_leaf(node : ArtNode, key : Array[Int], depth : Int) -> Int? {
  if node.kind == KIND_LEAF {
    if keys_equal(node.key, key) {
      return Some(node.val)
    }
    return None
  }
  // Check partial key
  let matched = check_prefix(node, key, depth)
  if matched != node.partial_len {
    return None
  }
  let new_depth = depth + node.partial_len
  if new_depth >= key.length() {
    // Check for a leaf at byte 0 (key prefix match)
    let slot = find_child(node, 0)
    if slot >= 0 {
      let child = node.children[slot]
      if child.kind == KIND_LEAF && keys_equal(child.key, key) {
        return Some(child.val)
      }
    }
    return None
  }
  let byte = key[new_depth]
  let child = get_child(node, byte)
  match child {
    Some(c) => find_leaf(c, key, new_depth + 1)
    None => None
  }
}

// ---------------------------------------------------------------------------
// Public API: Remove
// ---------------------------------------------------------------------------

///|
/// Remove a key from the ART. Returns `Some(value)` if the key existed.
pub fn art_remove(tree : Art, key : Array[Int]) -> Int? {
  if tree.root.kind == -1 {
    return None
  }
  // Special case: root is a leaf
  if tree.root.kind == KIND_LEAF {
    if keys_equal(tree.root.key, key) {
      let old = tree.root.val
      tree.root = make_null()
      tree.size = tree.size - 1
      return Some(old)
    }
    return None
  }
  let result = remove_recursive(tree.root, key, 0)
  if result is Some(_) {
    tree.size = tree.size - 1
    // If root has become empty, reset to null
    if tree.root.num_children == 0 {
      tree.root = make_null()
    } else if tree.root.num_children == 1 && tree.root.partial_len == 0 {
      // Hoist single child as new root (only if no partial key)
      let mut child_byte = -1
      for b = 0; b < 256 && child_byte < 0; b = b + 1 {
        let s = find_child(tree.root, b)
        if s >= 0 {
          child_byte = b
        }
      }
      if child_byte >= 0 {
        let child = match tree.root.kind {
          KIND_N256 => tree.root.children[child_byte]
          _ => tree.root.children[find_child(tree.root, child_byte)]
        }
        if child.kind == KIND_LEAF {
          tree.root = child
        }
      }
    }
  }
  result
}

///|
/// Recursive remove. Returns old value if key existed.
fn remove_recursive(node : ArtNode, key : Array[Int], depth : Int) -> Int? {
  if node.kind == KIND_LEAF {
    if keys_equal(node.key, key) {
      return Some(node.val)
    }
    return None
  }
  // Check partial key
  let matched = check_prefix(node, key, depth)
  if matched != node.partial_len {
    return None
  }
  let new_depth = depth + node.partial_len
  if new_depth >= key.length() {
    // Check for a leaf at byte 0
    let slot = find_child(node, 0)
    if slot < 0 {
      return None
    }
    let child = node.children[slot]
    if child.kind == KIND_LEAF && keys_equal(child.key, key) {
      let old = child.val
      let _ = remove_child(node, 0)
      return Some(old)
    }
    return None
  }
  let byte = key[new_depth]
  let slot = find_child(node, byte)
  if slot < 0 {
    return None
  }
  let child = match node.kind {
    KIND_N256 => node.children[byte]
    _ => node.children[slot]
  }
  let result = remove_recursive(child, key, new_depth + 1)
  if result is Some(_) {
    // If child is a leaf that matched, remove it from parent
    if child.kind == KIND_LEAF {
      let _ = remove_child(node, byte)
    } else if child.num_children == 0 {
      // Empty inner node — remove it
      let _ = remove_child(node, byte)
    } else if child.num_children == 1 && child.partial_len == 0 {
      // Hoist the single remaining child
      let mut remaining_byte = -1
      for i = 0; i < 256 && remaining_byte < 0; i = i + 1 {
        let s = find_child(child, i)
        if s >= 0 {
          remaining_byte = i
        }
      }
      if remaining_byte >= 0 {
        let grandchild = match child.kind {
          KIND_N256 => child.children[remaining_byte]
          _ => child.children[find_child(child, remaining_byte)]
        }
        match node.kind {
          KIND_N256 => node.children[byte] = grandchild
          _ => node.children[slot] = grandchild
        }
      }
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Public API: Contains
// ---------------------------------------------------------------------------

///|
/// Check if a key exists in the ART.
pub fn art_contains(tree : Art, key : Array[Int]) -> Bool {
  art_get(tree, key) is Some(_)
}

// ---------------------------------------------------------------------------
// Public API: Iterate
// ---------------------------------------------------------------------------

///|
/// Iterate over all key-value pairs in key order (lexicographic by byte).
pub fn art_for_each(tree : Art, f : (Array[Int], Int) -> Unit) -> Unit {
  if tree.root.kind == -1 {
    return
  }
  iterate_node(tree.root, f)
}

///|
/// Recursively iterate over all leaves in a subtree.
fn iterate_node(node : ArtNode, f : (Array[Int], Int) -> Unit) -> Unit {
  if node.kind == -1 {
    return
  }
  if node.kind == KIND_LEAF {
    f(node.key, node.val)
    return
  }
  match node.kind {
    KIND_N4 | KIND_N16 =>
      for i = 0; i < node.num_children; i = i + 1 {
        iterate_node(node.children[i], f)
      }
    KIND_N48 =>
      for b = 0; b < 256; b = b + 1 {
        let idx = node.index[b]
        if idx > 0 {
          iterate_node(node.children[idx - 1], f)
        }
      }
    KIND_N256 =>
      for b = 0; b < 256; b = b + 1 {
        let c = node.children[b]
        if c.kind != -1 {
          iterate_node(c, f)
        }
      }
    _ => ()
  }
}

///|
/// Collect all key-value pairs into an array, sorted by key.
pub fn art_to_array(tree : Art) -> Array[(Array[Int], Int)] {
  let result : Array[(Array[Int], Int)] = []
  art_for_each(tree, fn(k, v) { result.push((Array::copy(k), v)) })
  result
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

///|
/// Compare two byte-array keys for equality.
fn keys_equal(a : Array[Int], b : Array[Int]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Convert a string to a byte array (ASCII values).
pub fn string_to_bytes(s : String) -> Array[Int] {
  let bytes : Array[Int] = []
  for c in s {
    bytes.push(c.to_int())
  }
  bytes
}

///|
/// Convert a byte array back to a string.
pub fn bytes_to_string(bytes : Array[Int]) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < bytes.length(); i = i + 1 {
    buf.write_char(Int::unsafe_to_char(bytes[i]))
  }
  buf.to_string()
}
