/// Palindromic Tree (Eertree): stores all distinct palindromic substrings.
///
/// A palindromic tree is a tree-like data structure that represents all
/// distinct palindromic substrings of a string. It was independently
/// discovered by Mikhail Rubinchik and Arseny Shur (who called it "eertree").
///
/// ## Structure
///
/// The tree has two roots:
/// - **Root 0** (length -1): the "imaginary" root for odd-length palindromes.
///   Its suffix link points to itself.
/// - **Root 1** (length 0): the "empty" root for even-length palindromes.
///   Its suffix link points to root 0.
///
/// Every other node represents a distinct palindrome. Each node has:
/// - `length`: the length of the palindrome.
/// - `suffix_link`: the longest proper palindromic suffix of this palindrome.
/// - `children`: transitions by extending the palindrome with a character on
///   both sides.
/// - `count`: the number of occurrences of this palindrome in the string.
///
/// ## Construction
///
/// Characters are processed one by one (online). For each character `c` at
/// position `i`:
/// 1. Find the largest palindromic suffix `v` of the current prefix such that
///    `s[i - length[v] - 1] == s[i]` (i.e., `v` can be extended by `c`).
/// 2. If the extended palindrome already exists as a child of `v`, update
///    `last` and increment the count.
/// 3. Otherwise, create a new node `u`:
///    - Set `length[u] = length[v] + 2`.
///    - Set `suffix_link[u]` by finding the longest palindromic suffix of `v`
///      that can be extended by `c`, then following its child transition.
///    - Add `u` as a child of `v` with character `c`.
///
/// ## Complexity
///
/// - Construction: O(n) amortized time, O(n) space.
/// - The tree has at most n + 2 nodes (n distinct palindromes + 2 roots).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A palindromic tree node.
struct Node {
  length : Int
  mut suffix_link : Int
  children : Array[(Int, Int)] // (byte_value, node_index) pairs, sorted
  mut count : Int // number of occurrences (before propagation)
  first_pos : Int // starting position of first occurrence in the string
}

///|
/// A palindromic tree.
pub struct PalindromicTree {
  nodes : Array[Node]
  mut last : Int // index of the longest palindromic suffix of the current prefix
  s : Array[Int] // byte values of the string
  mut n : Int // current length of the string being processed
}

///|
/// Create an empty palindromic tree.
fn new_tree() -> PalindromicTree {
  let nodes : Array[Node] = []
  // Root 0: length -1, suffix_link = 0
  nodes.push({
    length: -1,
    suffix_link: 0,
    children: [],
    count: 0,
    first_pos: -1,
  })
  // Root 1: length 0, suffix_link = 0
  nodes.push({
    length: 0,
    suffix_link: 0,
    children: [],
    count: 0,
    first_pos: -1,
  })
  { nodes, last: 1, s: [], n: 0 }
}

///|
/// Find the child of node `v` with the given byte value, or return -1 if not found.
fn find_child(node : Node, c : Int) -> Int {
  for i = 0; i < node.children.length(); i = i + 1 {
    let (ch, child) = node.children[i]
    if ch == c {
      return child
    }
  }
  -1
}

///|
/// Add a child to node `v` with the given byte value and node index.
fn add_child(node : Node, c : Int, child : Int) -> Unit {
  node.children.push((c, child))
}

///|
/// Build a palindromic tree from a string.
///
/// Processes each byte of the string sequentially, building the tree in
/// O(n) amortized time.
pub fn build(s : String) -> PalindromicTree {
  let tree = new_tree()
  for i = 0; i < s.length(); i = i + 1 {
    add_char(tree, s[i].to_int())
  }
  propagate_counts(tree)
  tree
}

///|
/// Add a character (byte value) to the palindromic tree.
fn add_char(tree : PalindromicTree, c : Int) -> Unit {
  tree.s.push(c)
  let n = tree.s.length()
  tree.n = n
  // Step 1: find the largest palindromic suffix that can be extended by c.
  let mut curr = tree.last
  while true {
    let len = tree.nodes[curr].length
    // Check if s[n - 1 - len - 1] == s[n - 1] == c
    if n - 1 - len - 1 >= 0 && tree.s[n - 1 - len - 1] == c {
      break
    }
    curr = tree.nodes[curr].suffix_link
  }
  // Step 2: check if the extended palindrome already exists.
  let child = find_child(tree.nodes[curr], c)
  if child != -1 {
    // Already exists, just update last and increment count.
    tree.last = child
    tree.nodes[child].count = tree.nodes[child].count + 1
    return
  }
  // Step 3: create a new node.
  let new_len = tree.nodes[curr].length + 2
  // The new palindrome ends at position n-1 and has length new_len,
  // so it starts at position n - 1 - new_len + 1 = n - new_len.
  let fp = n - new_len
  let new_node = {
    length: new_len,
    suffix_link: 1, // placeholder, will be set below
    children: [],
    count: 1,
    first_pos: fp,
  }
  let new_idx = tree.nodes.length()
  tree.nodes.push(new_node)
  add_child(tree.nodes[curr], c, new_idx)
  // Set the suffix link of the new node.
  if new_len == 1 {
    // Single character palindrome: suffix link is the empty root (node 1).
    tree.nodes[new_idx].suffix_link = 1
  } else {
    // Find the longest proper palindromic suffix that can be extended by c.
    let mut suf = tree.nodes[curr].suffix_link
    while true {
      let len = tree.nodes[suf].length
      if n - 1 - len - 1 >= 0 && tree.s[n - 1 - len - 1] == c {
        break
      }
      suf = tree.nodes[suf].suffix_link
    }
    let suf_child = find_child(tree.nodes[suf], c)
    tree.nodes[new_idx].suffix_link = suf_child
  }
  tree.last = new_idx
}

///|
/// Propagate occurrence counts from leaves to roots.
///
/// After building, `count[i]` stores the number of times the palindrome at
/// node `i` was the longest palindromic suffix. Propagation adds the counts
/// of all suffix-link descendants to get the total occurrence count.
fn propagate_counts(tree : PalindromicTree) -> Unit {
  // Process nodes in reverse order of creation (longer palindromes first).
  let num_nodes = tree.nodes.length()
  for i = num_nodes - 1; i >= 2; i = i - 1 {
    let suf = tree.nodes[i].suffix_link
    tree.nodes[suf].count = tree.nodes[suf].count + tree.nodes[i].count
  }
}

///|
/// Count the number of distinct palindromic substrings.
///
/// This is the number of nodes minus 2 (excluding the two roots).
pub fn count_distinct_palindromes(tree : PalindromicTree) -> Int {
  tree.nodes.length() - 2
}

///|
/// Count the total number of palindromic substrings (including duplicates).
///
/// This is the sum of `count[i]` for all non-root nodes.
/// Returns Int64 to handle large strings.
pub fn count_all_palindromes(tree : PalindromicTree) -> Int64 {
  let mut total : Int64 = 0L
  for i = 2; i < tree.nodes.length(); i = i + 1 {
    total = total + tree.nodes[i].count.to_int64()
  }
  total
}

///|
/// Find the length of the longest palindromic substring.
pub fn longest_palindrome_length(tree : PalindromicTree) -> Int {
  let mut max_len = 0
  for i = 2; i < tree.nodes.length(); i = i + 1 {
    if tree.nodes[i].length > max_len {
      max_len = tree.nodes[i].length
    }
  }
  max_len
}

///|
/// Get all distinct palindromic substrings as an array of strings.
///
/// The substrings are returned in no particular order.
/// This is primarily for testing and debugging.
pub fn all_palindromes(tree : PalindromicTree) -> Array[String] {
  let result : Array[String] = []
  for i = 2; i < tree.nodes.length(); i = i + 1 {
    let node = tree.nodes[i]
    let len = node.length
    let pos = node.first_pos
    // Reconstruct the palindrome from the stored byte array.
    let buf = StringBuilder::new()
    for j = 0; j < len; j = j + 1 {
      let byte_val = tree.s[pos + j]
      // Safe conversion: validate byte range before casting.
      if byte_val >= 0 && byte_val <= 0x10FFFF {
        buf.write_char(byte_val.unsafe_to_char())
      }
    }
    result.push(buf.to_string())
  }
  result
}

///|
/// Count occurrences of a specific palindromic substring.
///
/// Returns 0 if the palindrome is not found.
pub fn count_occurrences(tree : PalindromicTree, palindrome : String) -> Int {
  let pal_bytes : Array[Int] = []
  for i = 0; i < palindrome.length(); i = i + 1 {
    pal_bytes.push(palindrome[i].to_int())
  }
  let pal_len = pal_bytes.length()
  // Search nodes for an exact match using first_pos to recover the actual
  // palindrome content stored at each node.
  for i = 2; i < tree.nodes.length(); i = i + 1 {
    let node = tree.nodes[i]
    if node.length == pal_len {
      // Compare the palindrome stored at this node with the input.
      let mut matches = true
      for j = 0; j < pal_len; j = j + 1 {
        if tree.s[node.first_pos + j] != pal_bytes[j] {
          matches = false
          break
        }
      }
      if matches {
        return node.count
      }
    }
  }
  0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "palindromic_tree: basic" {
  // s = "abba"
  // Distinct palindromes: "a", "b", "bb", "abb", "abba" → 5
  // Wait, "abb" is not a palindrome. Let me recount.
  // Palindromes: "a" (pos 0), "b" (pos 1), "b" (pos 2), "a" (pos 3),
  // "bb" (pos 1-2), "abba" (pos 0-3)
  // Distinct: "a", "b", "bb", "abba" → 4
  let tree = build("abba")
  assert_eq(count_distinct_palindromes(tree), 4)
}

///|
test "palindromic_tree: all same" {
  // s = "aaaa"
  // Distinct palindromes: "a", "aa", "aaa", "aaaa" → 4
  let tree = build("aaaa")
  assert_eq(count_distinct_palindromes(tree), 4)
}

///|
test "palindromic_tree: count all" {
  // s = "abba"
  // All palindromic substrings (by position):
  // "a" (0), "b" (1), "b" (2), "a" (3), "bb" (1-2), "abba" (0-3) → 6
  let tree = build("abba")
  assert_eq(count_all_palindromes(tree), 6L)
}

///|
test "palindromic_tree: count all aaaa" {
  // s = "aaaa"
  // All palindromic substrings:
  // Length 1: 4 (a, a, a, a)
  // Length 2: 3 (aa, aa, aa)
  // Length 3: 2 (aaa, aaa)
  // Length 4: 1 (aaaa)
  // Total: 4 + 3 + 2 + 1 = 10
  let tree = build("aaaa")
  assert_eq(count_all_palindromes(tree), 10L)
}

///|
test "palindromic_tree: longest" {
  // s = "abacaba"
  // Longest palindrome: "abacaba" (length 7)
  let tree = build("abacaba")
  assert_eq(longest_palindrome_length(tree), 7)
}

///|
test "palindromic_tree: longest in abba" {
  let tree = build("abba")
  assert_eq(longest_palindrome_length(tree), 4)
}

///|
test "palindromic_tree: empty string" {
  let tree = build("")
  assert_eq(count_distinct_palindromes(tree), 0)
  assert_eq(count_all_palindromes(tree), 0L)
  assert_eq(longest_palindrome_length(tree), 0)
}

///|
test "palindromic_tree: single char" {
  let tree = build("a")
  assert_eq(count_distinct_palindromes(tree), 1)
  assert_eq(count_all_palindromes(tree), 1L)
  assert_eq(longest_palindrome_length(tree), 1)
}

///|
test "palindromic_tree: abcba" {
  // s = "abcba"
  // Distinct palindromes: "a", "b", "c", "bcb", "abcba" → 5
  // All palindromic substrings (with duplicates):
  // "a"(0), "b"(1), "c"(2), "b"(3), "a"(4), "bcb"(1-3), "abcba"(0-4) → 7
  let tree = build("abcba")
  assert_eq(count_distinct_palindromes(tree), 5)
  assert_eq(count_all_palindromes(tree), 7L)
  assert_eq(longest_palindrome_length(tree), 5)
}

///|
test "palindromic_tree: all distinct palindromes" {
  let tree = build("abba")
  let pals = all_palindromes(tree)
  assert_eq(pals.length(), 4)
  // Verify each is a palindrome.
  for i = 0; i < pals.length(); i = i + 1 {
    let p = pals[i]
    let len = p.length()
    for j = 0; j < len / 2; j = j + 1 {
      assert_eq(p[j].to_int(), p[len - 1 - j].to_int())
    }
  }
}

///|
test "palindromic_tree: count occurrences" {
  // s = "ababa"
  // "a" appears at positions 0, 2, 4 → 3
  // "b" appears at positions 1, 3 → 2
  // "aba" appears at positions 0-2, 2-4 → 2
  // "bab" appears at position 1-3 → 1
  // "ababa" appears at position 0-4 → 1
  let tree = build("ababa")
  assert_eq(count_occurrences(tree, "a"), 3)
  assert_eq(count_occurrences(tree, "b"), 2)
  assert_eq(count_occurrences(tree, "aba"), 2)
  assert_eq(count_occurrences(tree, "bab"), 1)
  assert_eq(count_occurrences(tree, "ababa"), 1)
}
