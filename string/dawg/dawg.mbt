/// DAWG (Directed Acyclic Word Graph) — minimal automaton for a set of strings.
///
/// A DAWG (also known as a Minimal Acyclic Finite State Automaton, or
/// MA-FSA) is a compact trie variant that merges isomorphic sub-automata,
/// reducing space by up to 90% compared to a standard trie. Unlike a trie,
/// the DAWG shares states that represent the same set of suffixes.
///
/// ## Algorithm
///
/// Uses the **incremental minimization** algorithm (Daciuk et al., 2000):
/// words are inserted in lexicographic order. After inserting each word,
/// states that become equivalent (same transitions, same final-flag) are
/// merged via a "register" of unique representative states.
///
/// When words are added out of lexicographic order, a batch minimization
/// pass (`minimize`) can be called after all insertions to achieve the same
/// result.
///
/// ## Advantages over Trie
/// - **Space**: suffix/substring sharing means far fewer states.
/// - **Query**: O(m) lookup, same as trie.
/// - **Dictionary compression**: commonly used in spell checkers and
///   word games.
///
/// ## Complexity
/// - Build (incremental): O(total_word_length) with register lookup.
/// - Build (batch minimize): O(total_word_length * register_size) worst case.
/// - Lookup: O(m) for a word of length m.
/// - Space: O(unique_states) — much less than trie due to sharing.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A DAWG state with mutable transitions and final flag.
/// Each state has a unique `id` for identity comparison (since MoonBit
/// does not provide reference equality `===` for user-defined types).
priv struct DAWGState {
  id : Int
  mut is_final : Bool
  transitions : Map[Int, DAWGState]
}

///|
/// A DAWG built via incremental minimization.
pub struct DAWG {
  priv root : DAWGState
  // Register of canonical states (used for minimization).
  priv mut register : Array[DAWGState]
  // Stack of states created since the last minimization checkpoint.
  // These are candidates for merging when the next word shares a prefix.
  priv mut unchecked_suffix : Array[DAWGState]
  priv mut word_count : Int
  priv mut last_word : String
  priv mut next_id : Int
  // Whether incremental minimization is active (words in lex order).
  priv mut incremental : Bool
}

///|
/// Create a new empty DAWG.
pub fn new() -> DAWG {
  {
    root: { id: 0, is_final: false, transitions: Map([]) },
    register: [],
    unchecked_suffix: [],
    word_count: 0,
    last_word: "",
    next_id: 1,
    incremental: true,
  }
}

///|
/// Create a new state with a unique id.
fn dawg_new_state(dawg : DAWG) -> DAWGState {
  let id = dawg.next_id
  dawg.next_id = dawg.next_id + 1
  { id, is_final: false, transitions: Map([]) }
}

///|
/// Check if two states are equivalent (same final flag, same transitions
/// to equivalent destinations). Uses the unique `id` for fast identity
/// check first.
fn states_equal(a : DAWGState, b : DAWGState) -> Bool {
  if a.id == b.id {
    return true
  }
  if a.is_final != b.is_final {
    return false
  }
  // Check transitions match exactly (by destination identity).
  let a_keys : Array[Int] = []
  for k, _ in a.transitions {
    a_keys.push(k)
  }
  let b_keys : Array[Int] = []
  for k, _ in b.transitions {
    b_keys.push(k)
  }
  if a_keys.length() != b_keys.length() {
    return false
  }
  a_keys.sort_by(fn(x, y) { x - y })
  b_keys.sort_by(fn(x, y) { x - y })
  for i = 0; i < a_keys.length(); i = i + 1 {
    if a_keys[i] != b_keys[i] {
      return false
    }
    match (a.transitions.get(a_keys[i]), b.transitions.get(b_keys[i])) {
      (Some(da), Some(db)) => if da.id != db.id { return false }
      _ => return false
    }
  }
  true
}

///|
/// Look up a state in the register. If an equivalent state exists,
/// return it; otherwise, add this state to the register and return it.
fn register_or_find(dawg : DAWG, s : DAWGState) -> DAWGState {
  for i = 0; i < dawg.register.length(); i = i + 1 {
    if states_equal(dawg.register[i], s) {
      return dawg.register[i]
    }
  }
  dawg.register.push(s)
  s
}

///|
/// Minimize the unchecked suffix states down to a given prefix length.
/// States beyond position `down_to` in the unchecked_suffix are registered
/// and potentially merged.
fn minimize_suffix(dawg : DAWG, down_to : Int) -> Unit {
  while dawg.unchecked_suffix.length() > down_to {
    let idx = dawg.unchecked_suffix.length() - 1
    let s = dawg.unchecked_suffix[idx]
    dawg.unchecked_suffix.pop() |> ignore
    // Register this state and potentially merge.
    let canonical = register_or_find(dawg, s)
    if canonical.id != s.id {
      // Replace s with canonical in parent's transitions.
      if dawg.unchecked_suffix.length() > 0 {
        let parent = dawg.unchecked_suffix[dawg.unchecked_suffix.length() - 1]
        // Find which transition points to s and redirect it.
        for k, dest in parent.transitions {
          if dest.id == s.id {
            parent.transitions[k] = canonical
          }
        }
      } else {
        // Parent is the root — redirect root's transitions.
        for k, dest in dawg.root.transitions {
          if dest.id == s.id {
            dawg.root.transitions[k] = canonical
          }
        }
      }
    }
  }
}

///|
/// Add a word to the DAWG.
///
/// If words are added in lexicographic order, incremental minimization
/// is performed automatically after each insertion. If a word is added
/// out of order, insertion falls back to trie mode and `minimize` should
/// be called after all words are added.
pub fn add(dawg : DAWG, word : String) -> Unit {
  if dawg.incremental &&
    dawg.word_count > 0 &&
    @utils.str_cmp(word, dawg.last_word) < 0 {
    // Out of order: switch to batch mode.
    dawg.incremental = false
    // Minimize any remaining unchecked states.
    minimize_suffix(dawg, 0)
  }
  if dawg.incremental {
    add_incremental(dawg, word)
  } else {
    add_trie(dawg, word)
  }
}

///|
/// Incremental insertion with minimization (Daciuk et al. 2000).
/// Requires words in lexicographic order.
fn add_incremental(dawg : DAWG, word : String) -> Unit {
  // Find common prefix length with previous word.
  let prev = dawg.last_word
  dawg.last_word = word
  let mut common = 0
  let min_len = if word.length() < prev.length() {
    word.length()
  } else {
    prev.length()
  }
  while common < min_len && word[common] == prev[common] {
    common = common + 1
  }
  // Minimize the unchecked states beyond the common prefix.
  minimize_suffix(dawg, common)
  // Traverse the common prefix.
  let mut current = dawg.root
  for i = 0; i < common; i = i + 1 {
    let c = word[i].to_int()
    match current.transitions.get(c) {
      Some(next) => current = next
      None => {
        // Shouldn't happen since we traversed these before.
        let s = dawg_new_state(dawg)
        current.transitions[c] = s
        current = s
      }
    }
  }
  // Add new states for the remaining suffix.
  for i = common; i < word.length(); i = i + 1 {
    let c = word[i].to_int()
    let s = dawg_new_state(dawg)
    current.transitions[c] = s
    dawg.unchecked_suffix.push(s)
    current = s
  }
  if !current.is_final {
    current.is_final = true
    dawg.word_count = dawg.word_count + 1
  }
}

///|
/// Simple trie insertion (used when words are out of order).
fn add_trie(dawg : DAWG, word : String) -> Unit {
  let mut current = dawg.root
  for i = 0; i < word.length(); i = i + 1 {
    let c = word[i].to_int()
    match current.transitions.get(c) {
      Some(next) => current = next
      None => {
        let s = dawg_new_state(dawg)
        current.transitions[c] = s
        current = s
      }
    }
  }
  if !current.is_final {
    current.is_final = true
    dawg.word_count = dawg.word_count + 1
  }
}

///|
/// Finalize the DAWG by minimizing any remaining unchecked states.
/// Call this after all words have been added (required for incremental
/// mode; optional for batch mode where `minimize` handles it).
pub fn finish(dawg : DAWG) -> Unit {
  if dawg.incremental {
    minimize_suffix(dawg, 0)
  } else {
    minimize(dawg)
  }
}

///|
/// Minimize the DAWG by replacing equivalent states with their canonical
/// representatives. This should be called after all words have been added
/// when using batch (out-of-order) mode.
/// Uses an iterative post-order DFS with an explicit stack to avoid
/// O(n) recursion depth on degenerate (chain-shaped) DAWGs.
pub fn minimize(dawg : DAWG) -> Unit {
  dawg.register = []
  dawg.unchecked_suffix = []
  // Phase 1: Collect states in post-order using an explicit stack.
  // Stack entries: (state, is_exit_phase).
  // is_exit_phase=false → first visit, push children then re-push as exit.
  // is_exit_phase=true  → all children processed, add to post_order.
  let visited : Array[Int] = []
  let post_order : Array[DAWGState] = []
  let stack : Array[(DAWGState, Bool)] = []
  stack.push((dawg.root, false))
  while stack.length() > 0 {
    let top_idx = stack.length() - 1
    let (state, is_exit) = stack[top_idx]
    stack.pop() |> ignore
    if is_exit {
      post_order.push(state)
      continue
    }
    // Skip if already visited (cycle detection).
    let mut already = false
    for i = 0; i < visited.length(); i = i + 1 {
      if visited[i] == state.id {
        already = true
        break
      }
    }
    if already {
      continue
    }
    visited.push(state.id)
    // Push exit-phase entry (will be processed after all children).
    stack.push((state, true))
    // Push children for processing.
    for _, child in state.transitions {
      stack.push((child, false))
    }
  }
  // Phase 2: Process states in post-order (children before parents).
  // Map from original state.id → canonical representative.
  let canonical_map : Map[Int, DAWGState] = Map([])
  for idx = 0; idx < post_order.length(); idx = idx + 1 {
    let state = post_order[idx]
    // Update transitions to point to canonical children.
    let keys : Array[Int] = []
    for k, _ in state.transitions {
      keys.push(k)
    }
    for key_idx = 0; key_idx < keys.length(); key_idx = key_idx + 1 {
      let k = keys[key_idx]
      match state.transitions.get(k) {
        Some(child) =>
          match canonical_map.get(child.id) {
            Some(canonical) =>
              if canonical.id != child.id {
                state.transitions[k] = canonical
              }
            None => ()
          }
        None => ()
      }
    }
    // Register this state and record the canonical mapping.
    let canonical = register_or_find(dawg, state)
    canonical_map[state.id] = canonical
  }
}

///|
/// Check if a word is in the DAWG. O(m).
pub fn contains(dawg : DAWG, word : String) -> Bool {
  let mut current = dawg.root
  for i = 0; i < word.length(); i = i + 1 {
    let c = word[i].to_int()
    match current.transitions.get(c) {
      Some(next) => current = next
      None => return false
    }
  }
  current.is_final
}

///|
/// Number of words stored.
pub fn word_count(dawg : DAWG) -> Int {
  dawg.word_count
}

///|
/// Check if any word starts with the given prefix. O(m).
pub fn has_prefix(dawg : DAWG, prefix : String) -> Bool {
  let mut current = dawg.root
  for i = 0; i < prefix.length(); i = i + 1 {
    let c = prefix[i].to_int()
    match current.transitions.get(c) {
      Some(next) => current = next
      None => return false
    }
  }
  true
}

///|
/// Count the total number of states in the DAWG (for space analysis).
/// Uses an iterative DFS with an explicit stack to avoid recursion depth
/// issues on chain-shaped DAWGs.
pub fn state_count(dawg : DAWG) -> Int {
  let visited : Array[Int] = []
  let stack : Array[DAWGState] = []
  stack.push(dawg.root)
  let mut count = 0
  while stack.length() > 0 {
    let top_idx = stack.length() - 1
    let state = stack[top_idx]
    stack.pop() |> ignore
    let mut found = false
    for i = 0; i < visited.length(); i = i + 1 {
      if visited[i] == state.id {
        found = true
        break
      }
    }
    if found {
      continue
    }
    visited.push(state.id)
    count = count + 1
    for _, child in state.transitions {
      stack.push(child)
    }
  }
  count
}

///|
/// Count the number of transitions (edges) in the DAWG.
/// Uses an iterative DFS with an explicit stack to avoid recursion depth
/// issues on chain-shaped DAWGs.
pub fn transition_count(dawg : DAWG) -> Int {
  let visited : Array[Int] = []
  let stack : Array[DAWGState] = []
  stack.push(dawg.root)
  let mut count = 0
  while stack.length() > 0 {
    let top_idx = stack.length() - 1
    let state = stack[top_idx]
    stack.pop() |> ignore
    let mut found = false
    for i = 0; i < visited.length(); i = i + 1 {
      if visited[i] == state.id {
        found = true
        break
      }
    }
    if found {
      continue
    }
    visited.push(state.id)
    for _, child in state.transitions {
      count = count + 1
      stack.push(child)
    }
  }
  count
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "dawg: basic insert and lookup" {
  let d = new()
  add(d, "car")
  add(d, "card")
  add(d, "cat")
  add(d, "dog")
  finish(d)
  assert_true(contains(d, "cat"))
  assert_true(contains(d, "car"))
  assert_true(contains(d, "card"))
  assert_true(contains(d, "dog"))
  assert_false(contains(d, "ca"))
  assert_false(contains(d, "care"))
  assert_false(contains(d, "xyz"))
  assert_eq(word_count(d), 4)
}

///|
test "dawg: prefix lookup" {
  let d = new()
  add(d, "hello")
  add(d, "help")
  add(d, "world")
  finish(d)
  assert_true(has_prefix(d, "hel"))
  assert_true(has_prefix(d, "wor"))
  assert_false(has_prefix(d, "xyz"))
}

///|
test "dawg: empty string" {
  let d = new()
  finish(d)
  assert_false(contains(d, ""))
  add(d, "")
  finish(d)
  assert_true(contains(d, ""))
}

///|
test "dawg: duplicate insert" {
  let d = new()
  add(d, "test")
  add(d, "test")
  finish(d)
  assert_eq(word_count(d), 1)
  assert_true(contains(d, "test"))
}

///|
test "dawg: many words with suffix sharing" {
  let d = new()
  let words = [
    "app", "apple", "application", "apply", "banana", "band", "bandana",
  ]
  let sorted = words.copy()
  sorted.sort_by(fn(a, b) { @utils.str_cmp(a, b) })
  for i = 0; i < sorted.length(); i = i + 1 {
    add(d, sorted[i])
  }
  finish(d)
  for i = 0; i < words.length(); i = i + 1 {
    assert_true(contains(d, words[i]))
  }
  assert_false(contains(d, "apples"))
  assert_true(has_prefix(d, "appl"))
}

///|
test "dawg: out of order insertion" {
  let d = new()
  add(d, "zebra")
  add(d, "apple")
  add(d, "mango")
  finish(d)
  assert_true(contains(d, "zebra"))
  assert_true(contains(d, "apple"))
  assert_true(contains(d, "mango"))
  assert_eq(word_count(d), 3)
}

///|
test "dawg: state sharing reduces states" {
  let d = new()
  add(d, "abc")
  add(d, "bc")
  add(d, "c")
  finish(d)
  // After minimization, the suffix "bc" and "c" should be shared.
  let sc = state_count(d)
  assert_true(sc <= 5) // Sharing reduces states
  assert_true(sc >= 3) // At least root + some states
}

///|
test "dawg: large dictionary" {
  let d = new()
  let words = [
    "a", "ab", "abc", "abcd", "abcde", "b", "bc", "bcd", "bcde", "bcdef", "c", "cd",
    "cde", "cdef", "cdefg",
  ]
  let sorted = words.copy()
  sorted.sort_by(fn(a, b) { @utils.str_cmp(a, b) })
  for i = 0; i < sorted.length(); i = i + 1 {
    add(d, sorted[i])
  }
  finish(d)
  for i = 0; i < words.length(); i = i + 1 {
    assert_true(contains(d, words[i]))
  }
  assert_eq(word_count(d), words.length())
  let sc = state_count(d)
  assert_true(sc < 21)
}

///|
test "dawg: minimization produces correct result" {
  // Verify that after minimization, the DAWG is still correct
  // and shares states for common suffixes.
  let d = new()
  add(d, "ab")
  add(d, "bb")
  finish(d)
  assert_true(contains(d, "ab"))
  assert_true(contains(d, "bb"))
  // Both share the suffix "b" → should have fewer states than trie.
  let sc = state_count(d)
  // Trie: root -> a -> b(f), b -> b(f) = 4 states
  // DAWG: root -> a -> b(f), root -> b(shared) = 3 states
  assert_true(sc <= 4)
}

///|
test "dawg: transition count" {
  let d = new()
  add(d, "cat")
  add(d, "car")
  finish(d)
  assert_true(transition_count(d) > 0)
  // After minimization, shared prefix "ca" should reduce transitions.
  assert_true(transition_count(d) <= 5)
}
