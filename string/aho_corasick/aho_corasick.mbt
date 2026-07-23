/// Aho-Corasick multi-pattern string matching automaton.
///
/// Algorithm Overview
/// ==================
///
/// Aho-Corasick builds a finite automaton from a set of pattern strings that
/// can search for **all** patterns simultaneously in a single left-to-right
/// pass over the text.  It generalises the KMP failure-function idea from one
/// pattern to a trie of many patterns.
///
/// Construction proceeds in two phases:
///
/// 1. **Trie construction.**  Each pattern is inserted one code unit at a
///    time into a trie rooted at node 0.  Every node stores a dense 256-slot
///    children array (one slot per code-unit value 0..255) so that child
///    lookup is O(1).  A node's `output` list records the indices of all
///    patterns that terminate at that node.
///
/// 2. **Failure-link construction (BFS).**  For each node `u` at depth >= 1
///    we compute `u.fail` — the index of the longest proper suffix of the
///    path to `u` that is also a prefix of some pattern (or 0 if none).
///    Root's direct children have `fail = 0`.  For deeper nodes, `u.fail` is
///    found by walking the parent's fail chain until a node with a matching
///    child for the same code unit is found, or root is reached.
///
///    During BFS we also **merge outputs**: every pattern index that appears
///    in `u.fail`'s output list (transitively, since `u.fail` was processed
///    earlier in BFS order and its outputs were already merged) is appended
///    to `u`'s output list.  This means that during search, collecting
///    outputs is a single array scan — no fail-chain traversal is needed at
///    query time.
///
/// Search
/// ======
///
/// Starting at the root, we feed the text one code unit at a time.  When the
/// current node has no child for the incoming code unit, we follow fail
/// links until a match is found or the root is reached.  At each node we
/// visit (after transitioning), we emit every `(end_position, pattern_index)`
/// pair in the node's output list.  Because outputs were merged during
/// construction, this captures every pattern whose occurrence ends at the
/// current text position — including patterns that are proper suffixes of
/// the current match.
///
/// Complexity
/// ==========
///
/// - Build: O(sum of pattern lengths) for trie construction.  The failure-
///   link BFS visits each node once and, for each node, scans all 256 child
///   slots, giving O(nodes * 256) = O(sum of pattern lengths * alphabet) in
///   the worst case.  With a sparse child representation the BFS would be
///   O(sum of pattern lengths), but the dense array gives O(1) child lookup
///   during search at the cost of higher memory.
///
/// - Search: O(text_length + number_of_matches).  Each text code unit
///   advances the automaton at most once (amortised over fail-link
///   traversals, which can only decrease depth), and each match is emitted
///   exactly once.
///
/// Memory
/// ======
///
/// Each node consumes a 256-element `Array[Int]` (children) plus an `Int`
/// (fail) and an `Array[Int]` (output).  For large pattern sets this is
/// wasteful; a sparse map would reduce memory by ~90 % for typical text,
/// trading O(1) child lookup for O(k) where k is the node's branching factor.
///
/// IMPORTANT — string indexing model.  MoonBit's `String` is a sequence of
/// UTF-16 code units: `s[i]` returns the i-th code unit as a `Char`, and
/// `s.length()` counts code units (not Unicode codepoints, not UTF-8 bytes).
/// This is the same indexing model used by the KMP module; for ASCII text a
/// code unit coincides with a byte, matching the "byte-level" intuition.
///
/// Because this implementation uses a dense 256-slot children array, it
/// supports only code units in 0..255 (ASCII plus the Latin-1 supplement,
/// e.g. 'é').  A code unit outside this range (e.g. CJK characters U+4E00+,
/// emoji) triggers an out-of-bounds panic.  For full Unicode support, switch
/// the children representation to a hash map or pre-convert inputs to bytes.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// A node in the Aho-Corasick automaton.
///
/// `children` is a dense 256-slot array: `children[code_unit]` gives the
/// child node index, or -1 when no child exists for that code unit.
/// `fail` is the failure link — the index of the longest proper suffix of
/// the path to this node that is also a prefix of some pattern.  Root's
/// `fail` is 0 (itself).
/// `output` lists the indices of all patterns ending at (or suffix-merging
/// into) this node, in the order: own patterns first (insertion order),
/// then patterns inherited from the fail chain.
pub struct AcNode {
  children : Array[Int]
  mut fail : Int
  output : Array[Int]
}

/// An Aho-Corasick automaton built from a set of pattern strings.
///
/// Build with `build`, search with `search` or `search_first`.
pub struct AcAutomaton {
  nodes : Array[AcNode]
  pattern_count : Int
}

/// Create a fresh node: 256 children all set to -1, fail = 0, empty output.
fn make_node() -> AcNode {
  { children: Array::make(256, -1), fail: 0, output: [] }
}

/// Build an Aho-Corasick automaton from `patterns`.
///
/// Each pattern is inserted one code unit at a time into a trie, then
/// failure links and merged outputs are computed via BFS.  Empty patterns
/// (zero-length strings) are silently skipped: they have no code units to
/// insert and would match at every position, which is rarely the intended
/// behaviour.
///
/// Returns an `AcAutomaton` ready for `search` / `search_first`.
pub fn build(patterns : Array[String]) -> AcAutomaton {
  let root = make_node()
  let nodes : Array[AcNode] = [root]

  // ---- Phase 1: insert each pattern into the trie ----------------------
  for pat_idx = 0; pat_idx < patterns.length(); pat_idx = pat_idx + 1 {
    let pattern = patterns[pat_idx]
    let mut curr = 0 // root
    for i = 0; i < pattern.length(); i = i + 1 {
      let c = pattern[i].to_int()
      if nodes[curr].children[c] == -1 {
        nodes.push(make_node())
        let new_idx = nodes.length() - 1
        nodes[curr].children[c] = new_idx
        curr = new_idx
      } else {
        curr = nodes[curr].children[c]
      }
    }
    // Record this pattern's index at the terminal node.
    nodes[curr].output.push(pat_idx)
  }

  // ---- Phase 2: build failure links and merge outputs (BFS) ------------
  let queue : Array[Int] = []
  let mut head = 0

  // Root's direct children: fail = 0 (root).
  for c = 0; c < 256; c = c + 1 {
    let child = nodes[0].children[c]
    if child != -1 {
      nodes[child].fail = 0
      queue.push(child)
    }
  }

  while head < queue.length() {
    let v = queue[head]
    head = head + 1
    for c = 0; c < 256; c = c + 1 {
      let u = nodes[v].children[c]
      if u != -1 {
        // Walk v's fail chain to find a node that has child c.
        let mut f = nodes[v].fail
        while f != 0 && nodes[f].children[c] == -1 {
          f = nodes[f].fail
        }
        let fc = nodes[f].children[c]
        if fc != -1 && fc != u {
          nodes[u].fail = fc
        } else {
          nodes[u].fail = 0
        }
        // Merge outputs from the fail target into u.  The fail target was
        // processed earlier (it is at a strictly shallower depth), so its
        // output list already contains the transitive closure.
        let fail_target = nodes[u].fail
        for j = 0; j < nodes[fail_target].output.length(); j = j + 1 {
          nodes[u].output.push(nodes[fail_target].output[j])
        }
        queue.push(u)
      }
    }
  }

  { nodes, pattern_count: patterns.length() }
}

/// Search for all pattern occurrences in `text`.
///
/// Returns an `Array[(Int, Int)]` of `(end_position, pattern_index)` pairs,
/// where `end_position` is the exclusive end of the match (the code-unit
/// index just past the last matched code unit).  Results are emitted in
/// order of increasing text position; within the same position, a node's
/// own patterns (insertion order) come before patterns inherited via
/// failure links.
///
/// Empty text or an automaton built from an empty pattern list yields an
/// empty array.
pub fn search(automaton : AcAutomaton, text : String) -> Array[(Int, Int)] {
  let results : Array[(Int, Int)] = []
  let mut curr = 0 // root
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    // Follow fail links until a child is found or root is reached.
    while curr != 0 && automaton.nodes[curr].children[c] == -1 {
      curr = automaton.nodes[curr].fail
    }
    if automaton.nodes[curr].children[c] != -1 {
      curr = automaton.nodes[curr].children[c]
    }
    // Emit all outputs at this node (already merged during build).
    let outputs = automaton.nodes[curr].output
    for j = 0; j < outputs.length(); j = j + 1 {
      results.push((i + 1, outputs[j]))
    }
  }
  results
}

/// Return the first match found in `text`, or `None` if no pattern matches.
///
/// "First" means the match with the earliest end position.  If multiple
/// patterns end at the same earliest position, the one appearing first in the
/// node's output list is returned (own patterns in insertion order, then
/// patterns inherited via failure links).
pub fn search_first(
  automaton : AcAutomaton,
  text : String
) -> (Int, Int)? {
  let mut curr = 0 // root
  for i = 0; i < text.length(); i = i + 1 {
    let c = text[i].to_int()
    while curr != 0 && automaton.nodes[curr].children[c] == -1 {
      curr = automaton.nodes[curr].fail
    }
    if automaton.nodes[curr].children[c] != -1 {
      curr = automaton.nodes[curr].children[c]
    }
    let outputs = automaton.nodes[curr].output
    if outputs.length() > 0 {
      return Some((i + 1, outputs[0]))
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Helpers for tests
// ---------------------------------------------------------------------------

/// Comparator for (Int, Int) tuples: sort by first element, then second.
fn cmp_pair(a : (Int, Int), b : (Int, Int)) -> Int {
  if a.0 != b.0 {
    a.0 - b.0
  } else {
    a.1 - b.1
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "aho_corasick: basic match (single pattern)" {
  let ac = build(["world"])
  let results = search(ac, "hello world")
  assert_eq(results, [(11, 0)])
  assert_eq(search_first(ac, "hello world"), Some((11, 0)))
}

test "aho_corasick: multiple patterns" {
  // Classic Aho-Corasick example: patterns "he", "she", "his", "hers"
  // in text "ushers".
  //   "she" ends at 4 (starts at 1)
  //   "he"  ends at 4 (starts at 2)
  //   "hers" ends at 6 (starts at 2)
  let ac = build(["he", "she", "his", "hers"])
  let results = search(ac, "ushers")
  results.sort_by(cmp_pair)
  assert_eq(results, [(4, 0), (4, 1), (6, 3)])
  // search_first: "she" (index 1) is the first output at position 4.
  assert_eq(search_first(ac, "ushers"), Some((4, 1)))
}

test "aho_corasick: overlapping matches" {
  // "aa" and "aaa" in "aaaa":
  //   "aa"  ends at 2, 3, 4
  //   "aaa" ends at 3, 4
  let ac = build(["aa", "aaa"])
  let results = search(ac, "aaaa")
  results.sort_by(cmp_pair)
  assert_eq(results, [(2, 0), (3, 0), (3, 1), (4, 0), (4, 1)])
}

test "aho_corasick: no match" {
  let ac = build(["xyz"])
  assert_eq(search(ac, "hello").length(), 0)
  assert_true(search_first(ac, "hello") is None)
}

test "aho_corasick: empty pattern list" {
  let ac = build([])
  assert_eq(search(ac, "hello").length(), 0)
  assert_true(search_first(ac, "hello") is None)
}

test "aho_corasick: empty text" {
  let ac = build(["abc"])
  assert_eq(search(ac, "").length(), 0)
  assert_true(search_first(ac, "") is None)
}

test "aho_corasick: pattern is substring of another" {
  // "he" is a proper suffix of "she".  When searching "she", both patterns
  // match at position 3.
  let ac = build(["he", "she"])
  let results = search(ac, "she")
  results.sort_by(cmp_pair)
  assert_eq(results, [(3, 0), (3, 1)])
  // "she" (index 1) is the node's own output; "he" (index 0) is inherited.
  assert_eq(search_first(ac, "she"), Some((3, 1)))
}

test "aho_corasick: Unicode code unit matching" {
  // MoonBit strings are UTF-16: 'é' (U+00E9) is a single code unit (233),
  // which fits in the 256-slot children array.  "café" has code units
  // ['c','a','f','é'] (length 4); 'é' is at index 3 and ends at index 4.
  let ac = build(["é"])
  let results = search(ac, "café")
  assert_eq(results, [(4, 0)])
  assert_eq(search_first(ac, "café"), Some((4, 0)))
}

test "aho_corasick: duplicate patterns" {
  // Two identical patterns share the same terminal node; both indices
  // appear in the node's output list.
  let ac = build(["ab", "ab"])
  let results = search(ac, "ab")
  results.sort_by(cmp_pair)
  assert_eq(results, [(2, 0), (2, 1)])
  assert_eq(search_first(ac, "ab"), Some((2, 0)))
}

test "aho_corasick: large-scale test" {
  // Cross-check search results against a brute-force scanner.
  let patterns = ["ab", "abc", "bc", "c", "cd", "abcd"]
  let text = "abcdabcd"
  let ac = build(patterns)
  let results = search(ac, text)
  results.sort_by(cmp_pair)

  // Brute force: for each pattern, find all start positions.
  let expected : Array[(Int, Int)] = []
  for pat_idx = 0; pat_idx < patterns.length(); pat_idx = pat_idx + 1 {
    let pat = patterns[pat_idx]
    let m = pat.length()
    for start = 0; start + m <= text.length(); start = start + 1 {
      let mut ok = true
      for k = 0; k < m; k = k + 1 {
        if text[start + k] != pat[k] {
          ok = false
        }
      }
      if ok {
        expected.push((start + m, pat_idx))
      }
    }
  }
  expected.sort_by(cmp_pair)

  assert_eq(results.length(), expected.length())
  for i = 0; i < results.length(); i = i + 1 {
    assert_eq(results[i], expected[i])
  }
}
