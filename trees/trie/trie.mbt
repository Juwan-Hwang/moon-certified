/// Trie (prefix tree) for byte-indexed string keys.
///
/// Each node holds 256 child slots (one per byte value). Insertion, exact
/// search, prefix lookup, and deletion all run in O(m) where m is the key
/// length.
///
/// IMPORTANT: MoonBit's String indexing is byte-level, not Unicode codepoint.
/// For multi-byte UTF-8 strings the trie operates on raw bytes, which is
/// correct for ASCII keys and for exact byte-sequence matching of any string.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// A trie node.
///
/// `children` is a 256-entry array indexed by byte value; each slot is `None`
/// or `Some(child)`. The FixedArray contents are mutated in place, so the
/// field does not need `mut`. `is_end` is reassigned during insert/remove and
/// therefore requires `mut`.
pub struct TrieNode {
  children : FixedArray[TrieNode?]
  mut is_end : Bool
}

/// Create an empty trie (a root node with no children, not a word end).
pub fn empty() -> TrieNode {
  { children: FixedArray::make(256, None), is_end: false }
}

/// Follow the path of `word` through the trie. Returns the terminal node, or
/// `None` if the path does not exist at any byte.
fn find_node(root : TrieNode, word : String) -> TrieNode? {
  let mut node = root
  for i = 0; i < word.length(); i = i + 1 {
    let idx = word[i].to_int()
    let child = node.children[idx]
    if child is None {
      return None
    }
    node = child.unwrap()
  }
  Some(node)
}

/// Insert a word into the trie, creating intermediate nodes as needed.
pub fn insert(root : TrieNode, word : String) -> Unit {
  let mut node = root
  for i = 0; i < word.length(); i = i + 1 {
    let idx = word[i].to_int()
    let child = node.children[idx]
    if child is None {
      let new_child = empty()
      node.children[idx] = Some(new_child)
      node = new_child
    } else {
      node = child.unwrap()
    }
  }
  node.is_end = true
}

/// Exact-match search. Returns true iff the word was previously inserted.
pub fn search(root : TrieNode, word : String) -> Bool {
  match find_node(root, word) {
    None => false
    Some(node) => node.is_end
  }
}

/// Prefix search. Returns true iff any inserted word starts with `prefix`.
/// An empty prefix always returns true (the root always exists).
pub fn starts_with(root : TrieNode, prefix : String) -> Bool {
  find_node(root, prefix) is Some(_)
}

/// True iff `node` has at least one child.
fn has_children(node : TrieNode) -> Bool {
  for i = 0; i < 256; i = i + 1 {
    if node.children[i] is Some(_) {
      return true
    }
  }
  false
}

/// Recursive removal helper.
///
/// Unmarks the word's end node and prunes any childless, non-terminal nodes
/// along the path back to the root. Returns true if the word was found and
/// removed, false if it was not present.
fn remove_helper(node : TrieNode, word : String, depth : Int) -> Bool {
  if depth == word.length() {
    if !node.is_end {
      return false // word not present
    }
    node.is_end = false
    return true
  }
  let idx = word[depth].to_int()
  let child = node.children[idx]
  if child is None {
    return false // path does not exist
  }
  let found = remove_helper(child.unwrap(), word, depth + 1)
  if found {
    // Prune: if the child is now a dead end, detach it.
    let c = child.unwrap()
    if !c.is_end && !has_children(c) {
      node.children[idx] = None
    }
  }
  found
}

/// Remove a word from the trie. Returns true if the word was found and
/// removed, false if it was not present.
pub fn remove(root : TrieNode, word : String) -> Bool {
  remove_helper(root, word, 0)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "trie: insert and search" {
  let root = empty()
  insert(root, "hello")
  insert(root, "world")
  assert_eq(search(root, "hello"), true)
  assert_eq(search(root, "world"), true)
  assert_eq(search(root, "hell"), false) // prefix is not a word
  assert_eq(search(root, "helloo"), false)
  assert_eq(search(root, ""), false)
}

test "trie: prefix search" {
  let root = empty()
  insert(root, "apple")
  insert(root, "application")
  insert(root, "app")
  assert_eq(starts_with(root, "app"), true)
  assert_eq(starts_with(root, "appl"), true)
  assert_eq(starts_with(root, "apple"), true)
  assert_eq(starts_with(root, "application"), true)
  assert_eq(starts_with(root, "appli"), true)
  assert_eq(starts_with(root, "b"), false)
  assert_eq(starts_with(root, ""), true) // empty prefix always matches
}

test "trie: remove existing word" {
  let root = empty()
  insert(root, "apple")
  insert(root, "app")
  assert_eq(remove(root, "apple"), true)
  assert_eq(search(root, "apple"), false)
  assert_eq(search(root, "app"), true) // shorter word survives
  // "appl" nodes should be pruned but "app" remains.
  assert_eq(starts_with(root, "app"), true)
  assert_eq(starts_with(root, "appl"), false)
}

test "trie: remove non-existent word" {
  let root = empty()
  insert(root, "hello")
  assert_eq(remove(root, "world"), false)
  assert_eq(search(root, "hello"), true) // trie unchanged
  assert_eq(remove(root, "hell"), false) // prefix, not a word
  assert_eq(search(root, "hello"), true)
}

test "trie: remove from empty trie" {
  let root = empty()
  assert_eq(remove(root, "anything"), false)
}

test "trie: empty string" {
  let root = empty()
  assert_eq(search(root, ""), false)
  assert_eq(starts_with(root, ""), true)
  insert(root, "")
  assert_eq(search(root, ""), true)
  assert_eq(remove(root, ""), true)
  assert_eq(search(root, ""), false)
}

test "trie: single character" {
  let root = empty()
  insert(root, "a")
  assert_eq(search(root, "a"), true)
  assert_eq(search(root, "b"), false)
  assert_eq(starts_with(root, "a"), true)
  assert_eq(remove(root, "a"), true)
  assert_eq(search(root, "a"), false)
  assert_eq(starts_with(root, "a"), false) // pruned
}

test "trie: multiple words with common prefix" {
  let root = empty()
  insert(root, "app")
  insert(root, "apple")
  insert(root, "apply")
  insert(root, "apt")
  // All four are distinct words.
  assert_eq(search(root, "app"), true)
  assert_eq(search(root, "apple"), true)
  assert_eq(search(root, "apply"), true)
  assert_eq(search(root, "apt"), true)
  // Common prefixes.
  assert_eq(starts_with(root, "ap"), true)
  assert_eq(starts_with(root, "app"), true)
  assert_eq(starts_with(root, "appl"), true)
  assert_eq(starts_with(root, "apt"), true)
  // Remove the middle word; neighbours survive.
  assert_eq(remove(root, "apple"), true)
  assert_eq(search(root, "apple"), false)
  assert_eq(search(root, "app"), true)
  assert_eq(search(root, "apply"), true)
  assert_eq(search(root, "apt"), true)
  // "appl" path survives because "apply" still uses it.
  assert_eq(starts_with(root, "appl"), true)
}

test "trie: remove prunes entire chain" {
  let root = empty()
  insert(root, "abc")
  assert_eq(remove(root, "abc"), true)
  // The entire chain a -> b -> c should be pruned back to the root.
  assert_eq(starts_with(root, "a"), false)
  assert_eq(starts_with(root, ""), true) // root still exists
}

test "trie: re-insert after removal" {
  let root = empty()
  insert(root, "cat")
  assert_eq(remove(root, "cat"), true)
  assert_eq(search(root, "cat"), false)
  insert(root, "cat")
  assert_eq(search(root, "cat"), true)
}

test "trie: large dataset" {
  let root = empty()
  let words = [
    "algorithm", "binary", "branch", "breadth", "cycle", "data",
    "depth", "dijkstra", "edge", "fenwick", "forest", "graph",
    "heap", "insert", "kruskal", "leaf", "matrix", "node",
    "path", "prim", "queue", "recursive", "search", "segment",
    "stack", "tarjan", "tree", "trie", "union", "vertex",
    "weight", "xor",
  ]
  for k = 0; k < words.length(); k = k + 1 {
    insert(root, words[k])
  }
  // Every inserted word is found.
  for k = 0; k < words.length(); k = k + 1 {
    assert_eq(search(root, words[k]), true)
  }
  // Prefixes of inserted words match.
  assert_eq(starts_with(root, "di"), true) // dijkstra
  assert_eq(starts_with(root, "tr"), true) // tree, trie
  assert_eq(starts_with(root, "graph"), true)
  // Non-existent words and prefixes.
  assert_eq(search(root, "graphs"), false)
  assert_eq(starts_with(root, "z"), false)
  // Remove half the words; the rest survive.
  for k = 0; k < words.length(); k = k + 1 {
    if k % 2 == 0 {
      assert_eq(remove(root, words[k]), true)
    }
  }
  for k = 0; k < words.length(); k = k + 1 {
    assert_eq(search(root, words[k]), k % 2 != 0)
  }
}

test "trie: insert duplicate word" {
  let root = empty()
  insert(root, "hello")
  insert(root, "hello") // duplicate, idempotent
  assert_eq(search(root, "hello"), true)
  assert_eq(remove(root, "hello"), true)
  assert_eq(search(root, "hello"), false)
  assert_eq(remove(root, "hello"), false) // already removed
}
