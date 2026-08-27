/// Suffix Automaton (SAM) — the minimal DFA accepting all suffixes of a string.
///
/// A suffix automaton of a string `S` is the smallest directed acyclic graph
/// (DAG) such that every suffix of `S` is accepted. Each path from the root
/// spells a distinct substring of `S`, and every substring of `S` is spelled
/// by exactly one path.
///
/// ## Properties
///
/// For a string of length `n`, the SAM has:
/// - At most `2n - 1` states (vertices)
/// - At most `3n - 4` transitions (edges)
/// Both bounds are tight.
///
/// ## Construction
///
/// Built incrementally by appending characters one at a time. Each append is
/// O(1) amortised (using a hash map for transitions). Total construction is
/// O(n) expected time.
///
/// ## Supported queries
///
/// - `is_substring(s, pattern)` — O(|pattern|) check if pattern is a substring
/// - `count_distinct_substrings(sam)` — O(1) after construction; returns the
///   number of distinct non-empty substrings
/// - `count_occurrences(sam, pattern)` — O(|pattern|) count how many times
///   `pattern` appears as a substring
/// - `longest_common_substring(s, t)` — O(|s| + |t|) using two SAMS
/// - `longest_repeated_substring(sam)` — O(n) finds the longest substring
///   that appears at least twice
///
/// ## Implementation notes
///
/// Transitions are stored in a sorted `Array[(Int, Int)]` of `(byte, next_state)`
/// pairs, giving O(log k) lookup per state where k is the branching factor.
/// This avoids the overhead of a hash map while keeping memory low for sparse
/// states.
///
/// All fields are **package-private**; external callers interact through
/// free functions only.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A state in the suffix automaton.
///
/// - `len`: the length of the longest string in the equivalence class.
/// - `link`: the suffix link — points to the state representing the longest
///   proper suffix of the current class that belongs to a different class.
/// - `trans`: sorted transitions `(byte_value, target_state)`.
/// - `cnt`: occurrence count (populated by `compute_occurrences`).
priv struct SAMState {
  len : Int
  mut link : Int
  trans : Array[(Int, Int)]
  mut cnt : Int
}

///|
/// The suffix automaton: an array of states plus the index of the `last`
/// state (the state representing the entire string processed so far).
pub struct SuffixAutomaton {
  priv states : Array[SAMState]
  priv mut last : Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Build a suffix automaton for `s`.
///
/// Processes each byte of `s` left to right, creating at most 2 new states
/// per character. Returns the completed automaton with occurrence counts
/// pre-computed.
pub fn build(s : String) -> SuffixAutomaton {
  let sam : SuffixAutomaton = {
    states: [{ len: 0, link: -1, trans: [], cnt: 1, }],
    last: 0,
  }
  for i = 0; i < s.length(); i = i + 1 {
    extend_sam(sam, s[i].to_int())
  }
  compute_occurrences(sam)
  sam
}

///|
/// Extend the automaton by appending the byte `c`.
fn extend_sam(sam : SuffixAutomaton, c : Int) -> Unit {
  let cur = sam.states.length()
  let last_len = sam.states[sam.last].len
  sam.states.push({ len: last_len + 1, link: -1, trans: [], cnt: 1, })
  let mut p = sam.last
  // Add transitions from all states reachable via suffix links that don't
  // yet have a transition on `c`.
  while p != -1 && !has_trans(sam.states[p], c) {
    set_trans(sam.states[p], c, cur)
    p = sam.states[p].link
  }
  if p == -1 {
    // Reached the root: link to root.
    sam.states[cur].link = 0
  } else {
    // The while loop above guarantees that `p` has a transition on `c`.
    // Use pattern matching instead of unwrap() for production safety.
    match get_trans(sam.states[p], c) {
      Some(q) =>
        if sam.states[p].len + 1 == sam.states[q].len {
          sam.states[cur].link = q
        } else {
          // Clone state `q`.
          let clone = sam.states.length()
          sam.states.push({
            len: sam.states[p].len + 1,
            link: sam.states[q].link,
            trans: copy_trans(sam.states[q].trans),
            cnt: 0,
          })
          // Redirect transitions pointing to q to point to clone.
          while p != -1 {
            match get_trans(sam.states[p], c) {
              Some(t) =>
                if t == q {
                  set_trans(sam.states[p], c, clone)
                } else {
                  break
                }
              None => break
            }
            p = sam.states[p].link
          }
          sam.states[q].link = clone
          sam.states[cur].link = clone
        }
      None =>
        // Theoretically unreachable: the while loop above guarantees `p`
        // has a transition on `c`.  If we ever hit this due to an internal
        // bug, link to root (state 0) as a safe fallback rather than crash.
        sam.states[cur].link = 0
    }
  }
  sam.last = cur
}

// ---------------------------------------------------------------------------
// Occurrence counting
// ---------------------------------------------------------------------------

///|
/// Populate `cnt` for each state by propagating counts up the suffix-link tree.
///
/// After construction, each non-clone state has `cnt = 1`. We sort states by
/// `len` in descending order and add each state's count to its suffix link's
/// parent, accumulating the number of occurrences of each equivalence class.
fn compute_occurrences(sam : SuffixAutomaton) -> Unit {
  let n = sam.states.length()
  // Counting sort by `len` (descending).
  // `sam.last` always holds the state for the entire string, so its `len`
  // is the maximum (no state can represent a string longer than the input).
  let max_len = sam.states[sam.last].len
  if max_len == 0 {
    return
  }
  let cnt_arr = FixedArray::make(max_len + 1, 0)
  for i = 0; i < n; i = i + 1 {
    cnt_arr[sam.states[i].len] = cnt_arr[sam.states[i].len] + 1
  }
  for i = 1; i <= max_len; i = i + 1 {
    cnt_arr[i] = cnt_arr[i] + cnt_arr[i - 1]
  }
  let order = FixedArray::make(n, 0)
  for i = n - 1; i >= 0; i = i - 1 {
    cnt_arr[sam.states[i].len] = cnt_arr[sam.states[i].len] - 1
    order[cnt_arr[sam.states[i].len]] = i
  }
  // Propagate counts in descending order of `len`.
  let mut j = n - 1
  while j > 0 {
    let idx = order[j]
    let link = sam.states[idx].link
    if link >= 0 {
      sam.states[link].cnt = sam.states[link].cnt + sam.states[idx].cnt
    }
    j = j - 1
  }
}

// ---------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------

///|
/// Check if `pattern` is a substring of the string used to build `sam`.
///
/// Walks the automaton following transitions for each byte of `pattern`.
/// Returns `false` if any transition is missing. O(|pattern|).
pub fn is_substring(sam : SuffixAutomaton, pattern : String) -> Bool {
  let mut cur = 0
  for i = 0; i < pattern.length(); i = i + 1 {
    match get_trans(sam.states[cur], pattern[i].to_int()) {
      Some(next) => cur = next
      None => return false
    }
  }
  true
}

///|
/// Count the number of distinct non-empty substrings of the original string.
///
/// Computed as the sum of `(state.len - state.link.len)` over all non-root
/// states. O(n) after construction.
pub fn count_distinct_substrings(sam : SuffixAutomaton) -> Int {
  let mut total = 0
  for i = 1; i < sam.states.length(); i = i + 1 {
    let st = sam.states[i]
    let link_len = if st.link >= 0 { sam.states[st.link].len } else { 0 }
    total = total + (st.len - link_len)
  }
  total
}

///|
/// Count how many times `pattern` appears as a substring.
///
/// Walks the automaton to the state for `pattern`, then returns the
/// pre-computed occurrence count for that state. Returns 0 if `pattern` is
/// not a substring. O(|pattern|).
pub fn count_occurrences(sam : SuffixAutomaton, pattern : String) -> Int {
  let mut cur = 0
  for i = 0; i < pattern.length(); i = i + 1 {
    match get_trans(sam.states[cur], pattern[i].to_int()) {
      Some(next) => cur = next
      None => return 0
    }
  }
  sam.states[cur].cnt
}

///|
/// Find the length of the longest substring that appears at least twice.
///
/// Returns `Some(len)` if such a substring exists, `None` if all characters
/// are distinct (no repeated substring of length > 0).
///
/// The answer is the maximum `state.len` over all non-root, non-clone states
/// (states with `cnt >= 2`). O(n).
pub fn longest_repeated_substring_length(sam : SuffixAutomaton) -> Int? {
  let mut best = 0
  for i = 1; i < sam.states.length(); i = i + 1 {
    let st = sam.states[i]
    if st.cnt >= 2 && st.len > best {
      best = st.len
    }
  }
  if best == 0 {
    None
  } else {
    Some(best)
  }
}

///|
/// Find the longest common substring of two strings.
///
/// Builds a SAM for `s`, then walks `t` through the SAM, tracking the longest
/// match at each position. O(|s| + |t|).
pub fn longest_common_substring(s : String, t : String) -> Int {
  let sam = build(s)
  let mut cur = 0
  let mut l = 0
  let mut best = 0
  for i = 0; i < t.length(); i = i + 1 {
    let c = t[i].to_int()
    // Follow suffix links until we find a state with a transition on `c`.
    while cur != 0 && get_trans(sam.states[cur], c) is None {
      cur = sam.states[cur].link
      if cur >= 0 {
        l = sam.states[cur].len
      } else {
        cur = 0
        l = 0
      }
    }
    match get_trans(sam.states[cur], c) {
      Some(next) => {
        cur = next
        l = l + 1
        if l > best {
          best = l
        }
      }
      None => {
        cur = 0
        l = 0
      }
    }
  }
  best
}

///|
/// Total length of all distinct substrings.
///
/// Computed as the sum of `(state.len * (state.len + 1) / 2 -
/// link_len * (link_len + 1) / 2)` over all non-root states. O(n).
pub fn sum_of_lengths_of_distinct_substrings(sam : SuffixAutomaton) -> Int {
  let mut total = 0
  for i = 1; i < sam.states.length(); i = i + 1 {
    let st = sam.states[i]
    let link_len = if st.link >= 0 { sam.states[st.link].len } else { 0 }
    // Number of substrings ending at this state = st.len - link_len
    // Sum of their lengths = sum_{k=link_len+1}^{st.len} k
    //                       = (st.len*(st.len+1) - link_len*(link_len+1)) / 2
    // Use Int64 to prevent overflow.
    let a = st.len.to_int64() * (st.len.to_int64() + 1L)
    let b = link_len.to_int64() * (link_len.to_int64() + 1L)
    total = total + ((a - b) / 2L).to_int()
  }
  total
}

// ---------------------------------------------------------------------------
// Transition helpers (sorted array for O(log k) lookup)
// ---------------------------------------------------------------------------

///|
/// Binary search for a transition on byte `c` in the sorted transition array.
fn get_trans(st : SAMState, c : Int) -> Int? {
  let mut lo = 0
  let mut hi = st.trans.length() - 1
  while lo <= hi {
    let mid = (lo + hi) / 2
    let (bc, _) = st.trans[mid]
    if bc == c {
      return Some(st.trans[mid].1)
    }
    if bc < c {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  None
}

///|
/// Check whether a transition on `c` exists.
fn has_trans(st : SAMState, c : Int) -> Bool {
  get_trans(st, c) is Some(_)
}

///|
/// Insert or update a transition `(c, target)` keeping the array sorted.
fn set_trans(st : SAMState, c : Int, target : Int) -> Unit {
  let mut lo = 0
  let mut hi = st.trans.length()
  // Binary search for insertion point.
  while lo < hi {
    let mid = (lo + hi) / 2
    let (bc, _) = st.trans[mid]
    if bc < c {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo < st.trans.length() {
    let (bc, _) = st.trans[lo]
    if bc == c {
      st.trans[lo] = (c, target)
      return
    }
  }
  st.trans.insert(lo, (c, target))
}

///|
/// Deep-copy a transition array.
fn copy_trans(src : Array[(Int, Int)]) -> Array[(Int, Int)] {
  let dst : Array[(Int, Int)] = []
  for i = 0; i < src.length(); i = i + 1 {
    dst.push(src[i])
  }
  dst
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "SAM: is_substring basic" {
  let sam = build("ababc")
  assert_eq(is_substring(sam, "ab"), true)
  assert_eq(is_substring(sam, "ba"), true)
  assert_eq(is_substring(sam, "abc"), true)
  assert_eq(is_substring(sam, "ababc"), true)
  assert_eq(is_substring(sam, "abab"), true)
  assert_eq(is_substring(sam, "babc"), true)
  assert_eq(is_substring(sam, "c"), true)
  assert_eq(is_substring(sam, "d"), false)
  assert_eq(is_substring(sam, "abd"), false)
  assert_eq(is_substring(sam, "cab"), false)
}

///|
test "SAM: is_substring empty pattern" {
  let sam = build("hello")
  // Empty pattern is trivially a substring.
  assert_eq(is_substring(sam, ""), true)
}

///|
test "SAM: count_distinct_substrings" {
  // "ababc" distinct substrings: a, b, c, ab, ba, bc, aba, bab, abc, abab,
  // babc, ababc = 12
  let sam = build("ababc")
  assert_eq(count_distinct_substrings(sam), 12)
  // "aaaa" distinct substrings: a, aa, aaa, aaaa = 4
  let sam2 = build("aaaa")
  assert_eq(count_distinct_substrings(sam2), 4)
  // "abc" distinct substrings: a, b, c, ab, bc, abc = 6
  let sam3 = build("abc")
  assert_eq(count_distinct_substrings(sam3), 6)
}

///|
test "SAM: count_occurrences" {
  let sam = build("ababab")
  assert_eq(count_occurrences(sam, "a"), 3)
  assert_eq(count_occurrences(sam, "b"), 3)
  assert_eq(count_occurrences(sam, "ab"), 3)
  assert_eq(count_occurrences(sam, "ba"), 2)
  assert_eq(count_occurrences(sam, "aba"), 2)
  assert_eq(count_occurrences(sam, "bab"), 2)
  assert_eq(count_occurrences(sam, "abab"), 2)
  assert_eq(count_occurrences(sam, "ababab"), 1)
  assert_eq(count_occurrences(sam, "c"), 0)
  assert_eq(count_occurrences(sam, "abc"), 0)
}

///|
test "SAM: longest_repeated_substring" {
  let sam = build("ababab")
  assert_eq(longest_repeated_substring_length(sam), Some(4)) // "abab" appears twice
  let sam2 = build("abcdef")
  assert_eq(longest_repeated_substring_length(sam2), None)
  let sam3 = build("aaaa")
  assert_eq(longest_repeated_substring_length(sam3), Some(3)) // "aaa"
}

///|
test "SAM: longest_common_substring" {
  assert_eq(longest_common_substring("ababc", "babc"), 4) // "babc"
  assert_eq(longest_common_substring("abcdef", "defxyz"), 3) // "def"
  assert_eq(longest_common_substring("hello", "world"), 1) // "o" or "l"
  assert_eq(longest_common_substring("abc", "xyz"), 0)
  assert_eq(longest_common_substring("aaaa", "aa"), 2)
}

///|
test "SAM: sum_of_lengths_of_distinct_substrings" {
  // "ab" → distinct: a(1), b(1), ab(2) → sum = 4
  let sam = build("ab")
  assert_eq(sum_of_lengths_of_distinct_substrings(sam), 4)
  // "abc" → a(1), b(1), c(1), ab(2), bc(2), abc(3) → sum = 10
  let sam2 = build("abc")
  assert_eq(sum_of_lengths_of_distinct_substrings(sam2), 10)
}

///|
test "SAM: state count bound (2n-1)" {
  // For a string of length n, the SAM has at most 2n-1 states.
  let s = "abcdefgh"
  let sam = build(s)
  let n = s.length()
  assert_true(sam.states.length() <= 2 * n - 1)
  assert_true(sam.states.length() >= n + 1) // at least n+1 (root + n)
}

///|
test "SAM: all substrings match brute force" {
  let s = "banana"
  let sam = build(s)
  // Generate all substrings and verify is_substring.
  for i = 0; i < s.length(); i = i + 1 {
    for j = i + 1; j <= s.length(); j = j + 1 {
      let sub = s[i:j].to_owned()
      assert_eq(is_substring(sam, sub), true)
    }
  }
  // Non-substrings.
  assert_eq(is_substring(sam, "nn"), false)
  assert_eq(is_substring(sam, "aaa"), false)
  assert_eq(is_substring(sam, "bn"), false)
}

///|
test "SAM: occurrences match brute force" {
  let s = "mississippi"
  let sam = build(s)
  let check = fn(pat : String) -> Int {
    let mut count = 0
    for i = 0; i + pat.length() <= s.length(); i = i + 1 {
      let mut match_ok = true
      for j = 0; j < pat.length(); j = j + 1 {
        if s[i + j] != pat[j] {
          match_ok = false
          break
        }
      }
      if match_ok {
        count = count + 1
      }
    }
    count
  }
  assert_eq(count_occurrences(sam, "iss"), check("iss")) // 2
  assert_eq(count_occurrences(sam, "ssi"), check("ssi")) // 2
  assert_eq(count_occurrences(sam, "i"), check("i")) // 4
  assert_eq(count_occurrences(sam, "s"), check("s")) // 4
  assert_eq(count_occurrences(sam, "p"), check("p")) // 2
  assert_eq(count_occurrences(sam, "mississippi"), check("mississippi")) // 1
  assert_eq(count_occurrences(sam, "xyz"), 0)
}

///|
test "SAM: count_distinct matches formula" {
  // For a string with all distinct characters "abcde", distinct substrings
  // = n*(n+1)/2 = 5*6/2 = 15
  let sam = build("abcde")
  assert_eq(count_distinct_substrings(sam), 15)
}

///|
test "SAM: single character" {
  let sam = build("a")
  assert_eq(count_distinct_substrings(sam), 1)
  assert_eq(count_occurrences(sam, "a"), 1)
  assert_eq(is_substring(sam, "a"), true)
  assert_eq(is_substring(sam, "b"), false)
  assert_eq(longest_repeated_substring_length(sam), None)
}
