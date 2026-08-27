/// Suffix Tree — compressed trie of all suffixes of a string.
///
/// A suffix tree of a string `S` is a compressed trie containing all suffixes
/// of `S`. It enables O(|pattern|) substring queries, O(|S|) longest repeated
/// substring finding, and O(|S|) distinct substring counting.
///
/// ## Algorithm
///
/// Built using Ukkonen's algorithm, which constructs the tree in O(n) time
/// (for constant-size alphabets) by processing the string left to right.
/// Uses suffix links and an active point (active_node, active_edge,
/// active_len) with implicit extensions to achieve linear time.
///
/// A sentinel value (-1) is appended to ensure all suffixes end at leaf
/// nodes. This guarantees that no suffix is a prefix of another, so every
/// suffix terminates at a distinct leaf.
///
/// ## Complexity
///
/// - Construction: O(n) for constant alphabets, O(n log σ) for general alphabets
/// - Space: O(n)
/// - Substring query: O(|pattern|)
/// - Longest repeated substring: O(n)
/// - Distinct substring count: O(n)
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A node in the suffix tree.
///
/// - `children`: array of `(char_code, child_index, edge_start, edge_end)`.
///   `edge_end` is exclusive; -1 means the edge extends to `global_end`
///   (a leaf edge that grows with the text).
/// - `link`: suffix link target (-1 for root).
/// - `leaf_count`: number of leaves in the subtree (for occurrence counting).
priv struct STNode {
  children : Array[(Int, Int, Int, Int)]
  mut link : Int
  mut leaf_count : Int
}

///|
/// The suffix tree.
///
/// - `text`: byte values of the original string, with sentinel (-1) appended.
/// - `nodes`: all tree nodes; node 0 is the root.
/// - `global_end`: shared exclusive end for leaf edges; equals `text.length()`
///   after construction.
/// - `length`: original string length (without sentinel).
pub struct SuffixTree {
  priv text : Array[Int]
  priv nodes : Array[STNode]
  priv mut global_end : Int
  priv length : Int
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
/// Effective end of an edge: resolve -1 to `global_end`.
fn eff_end(st : SuffixTree, end : Int) -> Int {
  if end == -1 {
    st.global_end
  } else {
    end
  }
}

///|
/// Edge length: `[start, eff_end)`.
fn edge_len(st : SuffixTree, start : Int, end : Int) -> Int {
  eff_end(st, end) - start
}

///|
/// Find a child by character code.
/// Returns its index in the children array, or -1 if not found.
fn find_child(children : Array[(Int, Int, Int, Int)], ch : Int) -> Int {
  let mut i = 0
  while i < children.length() {
    if children[i].0 == ch {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Create a fresh node (no children, no suffix link, zero leaf count).
fn new_node() -> STNode {
  { children: [], link: -1, leaf_count: 0, }
}

// ---------------------------------------------------------------------------
// Construction — Ukkonen's algorithm
// ---------------------------------------------------------------------------

///|
/// Build a suffix tree for `s`.
///
/// Processes each byte of `s` left to right, creating at most 2 new nodes per
/// character. After construction, leaf counts are pre-computed for O(|pattern|)
/// occurrence queries.
pub fn build(s : String) -> SuffixTree {
  let n = s.length()
  // Build text array: byte values + sentinel (-1).
  let text : Array[Int] = Array::make(n + 1, -1)
  for i = 0; i < n; i = i + 1 {
    text[i] = s[i].to_int()
  }
  // text[n] = -1 (sentinel)

  let st : SuffixTree = {
    text,
    nodes: [new_node()], // node 0 = root
    global_end: 0,
    length: n,
  }

  // Active point state.
  let mut active_node = 0
  let mut active_edge = -1 // index into text (the char that starts the active edge)
  let mut active_len = 0
  let mut remaining = 0 // number of suffixes waiting to be added
  let mut last_new = -1 // last newly created internal node (for suffix links)

  // Process n+1 characters (including sentinel).
  for i = 0; i <= n; i = i + 1 {
    // Phase i: add character text[i].
    // Rule 1 (extend all leaves) is handled automatically by incrementing
    // global_end: every leaf edge [start, -1) now includes text[i].
    st.global_end = i + 1
    remaining = remaining + 1
    last_new = -1

    while remaining > 0 {
      if active_len == 0 {
        active_edge = i
      }

      let ch = text[active_edge]
      let child_pos = find_child(st.nodes[active_node].children, ch)

      if child_pos == -1 {
        // Rule 2a: no edge starting with `ch`; create a new leaf.
        let leaf_idx = st.nodes.length()
        st.nodes.push(new_node())
        st.nodes[active_node].children.push((ch, leaf_idx, i, -1))

        // Set suffix link from the previous new internal node.
        if last_new != -1 {
          st.nodes[last_new].link = active_node
          last_new = -1
        }

        remaining = remaining - 1
        // Advance the active point.
        if active_node == 0 {
          if active_len > 0 {
            active_len = active_len - 1
            active_edge = i - remaining + 1
          }
        } else {
          active_node = st.nodes[active_node].link
        }
      } else {
        let (_, child, start, end) = st.nodes[active_node].children[child_pos]
        let elen = edge_len(st, start, end)

        if active_len >= elen {
          // Walk down: the active point is past this edge; move to child.
          active_node = child
          active_edge = active_edge + elen
          active_len = active_len - elen
          // `remaining` is unchanged; loop continues to descend further.
        } else {
          let next_ch = text[start + active_len]
          if next_ch == text[i] {
            // Rule 3: the character already exists (showstopper).
            if last_new != -1 {
              st.nodes[last_new].link = active_node
              last_new = -1
            }
            active_len = active_len + 1
            break // exit while loop; go to next phase
          } else {
            // Rule 2b: split the edge at `start + active_len`.
            let split_pos = start + active_len
            let internal_idx = st.nodes.length()
            st.nodes.push(new_node())

            let old_end = end
            // Redirect the existing edge to point to the new internal node.
            st.nodes[active_node].children[child_pos] = (
              ch, internal_idx, start, split_pos,
            )
            // The old child becomes a child of the internal node.
            st.nodes[internal_idx].children.push(
              (text[split_pos], child, split_pos, old_end),
            )
            // Create a new leaf for the current suffix.
            let leaf_idx = st.nodes.length()
            st.nodes.push(new_node())
            st.nodes[internal_idx].children.push((text[i], leaf_idx, i, -1))

            // Suffix link: chain from the previous new internal node.
            if last_new != -1 {
              st.nodes[last_new].link = internal_idx
            }
            last_new = internal_idx

            remaining = remaining - 1
            // Advance the active point.
            if active_node == 0 {
              if active_len > 0 {
                active_len = active_len - 1
                active_edge = i - remaining + 1
              }
            } else {
              active_node = st.nodes[active_node].link
            }
          }
        }
      }
    }
  }

  // Pre-compute leaf counts for O(|pattern|) occurrence queries.
  let _ = compute_leaf_counts(st, 0)
  st
}

///|
/// Iteratively compute the number of leaves in each subtree.
///
/// Uses an explicit stack for post-order traversal to avoid O(n) recursion
/// depth on degenerate trees (e.g., "aaaa...a" produces a chain).
fn compute_leaf_counts(st : SuffixTree, root_idx : Int) -> Int {
  // Stack entries: (node_idx, visited_flag).
  // First pass: push (node, false). When popped with false, re-push as
  // (node, true) then push all children as (child, false).
  // When popped with true, all children have been processed; compute sum.
  let stack : Array[(Int, Bool)] = [(root_idx, false)]
  while stack.length() > 0 {
    let (idx, visited) = match stack.pop() {
      Some(v) => v
      None => break
    }
    let node = st.nodes[idx]
    if visited {
      // All children processed; sum their leaf counts.
      if node.children.length() == 0 {
        node.leaf_count = 1
      } else {
        let mut total = 0
        for i = 0; i < node.children.length(); i = i + 1 {
          let (_, child, _, _) = node.children[i]
          total = total + st.nodes[child].leaf_count
        }
        node.leaf_count = total
      }
    } else {
      // First visit: push self as visited, then push all children.
      stack.push((idx, true))
      for i = 0; i < node.children.length(); i = i + 1 {
        let (_, child, _, _) = node.children[i]
        stack.push((child, false))
      }
    }
  }
  st.nodes[root_idx].leaf_count
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

///|
/// Return the length of the original string (without the sentinel).
pub fn text_length(st : SuffixTree) -> Int {
  st.length
}

///|
/// Check if `pattern` is a substring of the original string.
///
/// Walks the tree from the root following edges for each byte of `pattern`.
/// Returns `false` if any character mismatches or an edge is missing.
/// O(|pattern|) time.
pub fn contains(st : SuffixTree, pattern : String) -> Bool {
  match find_node(st, pattern) {
    None => false
    Some(_) => true
  }
}

///|
/// Find the node at which the pattern path ends.
///
/// Returns `Some(node_index)` if the pattern exists, `None` otherwise.
/// The returned node's `leaf_count` gives the number of occurrences.
fn find_node(st : SuffixTree, pattern : String) -> Int? {
  let pat_len = pattern.length()
  if pat_len == 0 {
    return Some(0)
  }

  let mut node = 0
  let mut pat_idx = 0

  while pat_idx < pat_len {
    let ch = pattern[pat_idx].to_int()
    let child_pos = find_child(st.nodes[node].children, ch)
    if child_pos == -1 {
      return None
    }
    let (_, child, start, end) = st.nodes[node].children[child_pos]
    let elen = edge_len(st, start, end)

    // Match along this edge character by character.
    let mut j = 0
    while j < elen && pat_idx < pat_len {
      if st.text[start + j] != pattern[pat_idx].to_int() {
        return None
      }
      j = j + 1
      pat_idx = pat_idx + 1
    }

    node = child
  }

  Some(node)
}

///|
/// Count the number of occurrences of `pattern` in the original string.
///
/// Walks the tree to the endpoint of `pattern`, then returns the
/// pre-computed leaf count of that subtree. Returns 0 if `pattern` is not
/// found. O(|pattern|) time.
pub fn count_occurrences(st : SuffixTree, pattern : String) -> Int {
  match find_node(st, pattern) {
    None => 0
    Some(node) => st.nodes[node].leaf_count
  }
}

///|
/// Count the number of distinct non-empty substrings of the original string.
///
/// Computed as the sum of all edge lengths minus the number of leaves (each
/// leaf contributes one sentinel character that is not part of the original
/// string). O(n) time.
pub fn count_distinct_substrings(st : SuffixTree) -> Int {
  let mut total = 0
  for i = 0; i < st.nodes.length(); i = i + 1 {
    let node = st.nodes[i]
    for j = 0; j < node.children.length(); j = j + 1 {
      let (_, _, start, end) = node.children[j]
      total = total + edge_len(st, start, end)
    }
  }
  // Subtract the sentinel characters (one per leaf = n + 1 leaves).
  total - st.nodes[0].leaf_count
}

///|
/// Find the length of the longest substring that appears at least twice.
///
/// The answer is the depth of the deepest internal node (a node with at least
/// one child). The path from root to that node spells the longest repeated
/// substring. Returns `None` if all characters are distinct.
/// O(n) time.
pub fn longest_repeated_substring_length(st : SuffixTree) -> Int? {
  let (depth, _) = find_deepest_internal(st, 0, 0)
  if depth == 0 {
    None
  } else {
    Some(depth)
  }
}

///|
/// Iteratively find the deepest internal node.
///
/// Uses an explicit stack for DFS to avoid O(n) recursion depth on degenerate
/// trees. Returns `(depth, node_index)`. A depth of 0 means no internal node
/// below the given starting depth was found (only leaves or root).
fn find_deepest_internal(
  st : SuffixTree,
  root : Int,
  start_depth : Int,
) -> (Int, Int) {
  let stack : Array[(Int, Int)] = [(root, start_depth)]
  let mut best = (0, -1)
  while stack.length() > 0 {
    let (node, depth) = match stack.pop() {
      Some(v) => v
      None => break
    }
    let children = st.nodes[node].children
    if children.length() == 0 {
      // Leaf node: not an internal node, skip.
      continue
    }
    // This is an internal node; track it as a candidate.
    if depth > best.0 {
      best = (depth, node)
    }
    // Push all children with accumulated depth.
    for i = 0; i < children.length(); i = i + 1 {
      let (_, child, start, end) = children[i]
      let elen = edge_len(st, start, end)
      stack.push((child, depth + elen))
    }
  }
  best
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "suffix_tree: empty string" {
  let st = build("")
  assert_true(contains(st, ""))
  assert_false(contains(st, "a"))
  assert_eq(count_occurrences(st, ""), 1)
  assert_eq(count_distinct_substrings(st), 0)
  assert_true(longest_repeated_substring_length(st) is None)
}

///|
test "suffix_tree: single char" {
  let st = build("a")
  assert_true(contains(st, "a"))
  assert_true(contains(st, ""))
  assert_false(contains(st, "b"))
  assert_false(contains(st, "aa"))
  assert_eq(count_occurrences(st, "a"), 1)
  assert_eq(count_distinct_substrings(st), 1)
  assert_true(longest_repeated_substring_length(st) is None)
}

///|
test "suffix_tree: two same chars" {
  let st = build("aa")
  assert_true(contains(st, "a"))
  assert_true(contains(st, "aa"))
  assert_false(contains(st, "ab"))
  assert_eq(count_occurrences(st, "a"), 2)
  assert_eq(count_occurrences(st, "aa"), 1)
  assert_eq(count_distinct_substrings(st), 2)
  assert_eq(longest_repeated_substring_length(st), Some(1))
}

///|
test "suffix_tree: abac" {
  let st = build("abac")
  assert_true(contains(st, "a"))
  assert_true(contains(st, "ab"))
  assert_true(contains(st, "aba"))
  assert_true(contains(st, "abac"))
  assert_true(contains(st, "bac"))
  assert_true(contains(st, "ac"))
  assert_true(contains(st, "c"))
  assert_false(contains(st, "abc"))
  assert_false(contains(st, "abaca"))
  assert_eq(count_occurrences(st, "a"), 2)
  assert_eq(count_occurrences(st, "ab"), 1)
  assert_eq(count_occurrences(st, "b"), 1)
  assert_eq(count_occurrences(st, "c"), 1)
  assert_eq(count_distinct_substrings(st), 9)
  // "a" is the longest repeated substring (length 1)
  assert_eq(longest_repeated_substring_length(st), Some(1))
}

///|
test "suffix_tree: banana" {
  let st = build("banana")
  assert_true(contains(st, "banana"))
  assert_true(contains(st, "anana"))
  assert_true(contains(st, "nana"))
  assert_true(contains(st, "ana"))
  assert_true(contains(st, "na"))
  assert_true(contains(st, "a"))
  assert_true(contains(st, "ban"))
  assert_false(contains(st, "xyz"))
  assert_eq(count_occurrences(st, "a"), 3)
  assert_eq(count_occurrences(st, "n"), 2)
  assert_eq(count_occurrences(st, "an"), 2)
  assert_eq(count_occurrences(st, "ana"), 2)
  assert_eq(count_occurrences(st, "na"), 2)
  assert_eq(count_occurrences(st, "ban"), 1)
  assert_eq(count_distinct_substrings(st), 15)
  // "ana" is the longest repeated substring (length 3)
  assert_eq(longest_repeated_substring_length(st), Some(3))
}

///|
test "suffix_tree: mississippi" {
  let st = build("mississippi")
  assert_true(contains(st, "mississippi"))
  assert_true(contains(st, "issi"))
  assert_true(contains(st, "ssissippi"))
  assert_false(contains(st, "mississippix"))
  assert_eq(count_occurrences(st, "i"), 4)
  assert_eq(count_occurrences(st, "s"), 4)
  assert_eq(count_occurrences(st, "ss"), 2)
  assert_eq(count_occurrences(st, "issi"), 2)
  assert_eq(count_occurrences(st, "iss"), 2)
  assert_eq(count_occurrences(st, "ppi"), 1)
  assert_eq(count_distinct_substrings(st), 53)
  // "issi" is the longest repeated substring (length 4)
  assert_eq(longest_repeated_substring_length(st), Some(4))
}

///|
test "suffix_tree: all distinct chars" {
  let st = build("abcdef")
  assert_eq(count_distinct_substrings(st), 21) // 6*7/2 = 21
  assert_true(longest_repeated_substring_length(st) is None)
  assert_eq(count_occurrences(st, "abc"), 1)
  assert_eq(count_occurrences(st, "def"), 1)
  assert_eq(count_occurrences(st, "xyz"), 0)
}

///|
test "suffix_tree: repeated string" {
  let st = build("abcabc")
  assert_true(contains(st, "abcabc"))
  assert_true(contains(st, "abc"))
  assert_true(contains(st, "bca"))
  assert_true(contains(st, "cab"))
  assert_eq(count_occurrences(st, "abc"), 2)
  assert_eq(count_occurrences(st, "bca"), 1)
  assert_eq(count_occurrences(st, "cab"), 1)
  assert_eq(count_occurrences(st, "ab"), 2)
  assert_eq(count_distinct_substrings(st), 15)
  // "abc" is the longest repeated substring (length 3)
  assert_eq(longest_repeated_substring_length(st), Some(3))
}

///|
test "suffix_tree: aaaaa" {
  let st = build("aaaaa")
  assert_true(contains(st, "aaaaa"))
  assert_true(contains(st, "aaaa"))
  assert_false(contains(st, "aaaaaa"))
  assert_eq(count_occurrences(st, "a"), 5)
  assert_eq(count_occurrences(st, "aa"), 4)
  assert_eq(count_occurrences(st, "aaa"), 3)
  assert_eq(count_occurrences(st, "aaaa"), 2)
  assert_eq(count_occurrences(st, "aaaaa"), 1)
  assert_eq(count_distinct_substrings(st), 5)
  assert_eq(longest_repeated_substring_length(st), Some(4))
}

///|
test "suffix_tree: abababab" {
  let st = build("abababab")
  assert_eq(count_occurrences(st, "ab"), 4)
  assert_eq(count_occurrences(st, "abab"), 3)
  assert_eq(count_occurrences(st, "ababab"), 2)
  assert_eq(count_occurrences(st, "abababab"), 1)
  assert_eq(count_distinct_substrings(st), 15)
  // "ababab" is the longest repeated substring (length 6)
  assert_eq(longest_repeated_substring_length(st), Some(6))
}

///|
test "suffix_tree: abcab" {
  let st = build("abcab")
  assert_true(contains(st, "abcab"))
  assert_true(contains(st, "ab"))
  assert_true(contains(st, "bc"))
  assert_true(contains(st, "ca"))
  assert_false(contains(st, "ac"))
  assert_eq(count_occurrences(st, "ab"), 2)
  assert_eq(count_occurrences(st, "a"), 2)
  assert_eq(count_occurrences(st, "b"), 2)
  assert_eq(count_occurrences(st, "c"), 1)
  assert_eq(count_distinct_substrings(st), 12)
  assert_eq(longest_repeated_substring_length(st), Some(2))
}

///|
test "suffix_tree: occurrences edge cases" {
  let st = build("ababa")
  assert_eq(count_occurrences(st, "aba"), 2)
  assert_eq(count_occurrences(st, "ba"), 2)
  assert_eq(count_occurrences(st, "a"), 3)
  assert_eq(count_occurrences(st, "b"), 2)
  assert_eq(count_occurrences(st, "ababa"), 1)
  assert_eq(count_occurrences(st, "xyz"), 0)
  assert_eq(count_occurrences(st, "ababaa"), 0)
}

///|
test "suffix_tree: stress long repeated string" {
  // Build a string of 500 'a' characters — worst case for tree depth.
  let mut s = ""
  for i = 0; i < 500; i = i + 1 {
    s = s + "a"
  }
  let st = build(s)
  assert_eq(text_length(st), 500)
  assert_true(contains(st, s))
  assert_eq(count_occurrences(st, "a"), 500)
  assert_eq(count_occurrences(st, "aa"), 499)
  // Longest repeated substring is the whole string minus 1 char.
  assert_eq(longest_repeated_substring_length(st), Some(499))
  // n*(n+1)/2 distinct substrings for all-same string.
  assert_eq(count_distinct_substrings(st), 500)
}

///|
test "suffix_tree: stress long pattern string" {
  // Build "ababab...ab" of length 200 to test iterative traversal.
  let mut s = ""
  for i = 0; i < 100; i = i + 1 {
    s = s + "ab"
  }
  let st = build(s)
  assert_eq(text_length(st), 200)
  assert_true(contains(st, s))
  assert_eq(count_occurrences(st, "ab"), 100)
  assert_eq(count_occurrences(st, "abab"), 99)
  // Longest repeated substring: "ab" * 99 = length 198.
  assert_eq(longest_repeated_substring_length(st), Some(198))
}
