/// Regex Engine — Thompson NFA Construction and Simulation.
///
/// This package implements a regular expression engine based on Thompson's
/// NFA construction and parallel (all-states-at-once) simulation, following
/// the approach described in Russ Cox's "Regular Expression Matching Can Be
/// Simple And Fast" (https://swtch.com/~rsc/regexp/regexp1.html).
///
/// ## Supported Syntax
///
/// | Syntax      | Meaning                              |
/// |-------------|--------------------------------------|
/// | `abc`       | literal characters                    |
/// | `.`         | any single character                  |
/// | `*`         | zero or more (greedy)                 |
/// | `+`         | one or more (greedy)                  |
/// | `?`         | zero or one (greedy)                  |
/// | `a\|b`      | alternation (a or b)                  |
/// | `(abc)`     | grouping                              |
/// | `[abc]`     | character class                       |
/// | `[^abc]`    | negated character class               |
/// | `[a-z]`     | character range                       |
/// | `\.`        | escaped literal (any char after `\`)  |
///
/// ## Algorithm
///
/// 1. **Parse**: A recursive-descent parser builds NFA fragments directly
///    (no intermediate AST) using Thompson's construction.
/// 2. **Simulate**: The NFA is simulated in parallel — all reachable states
///    are tracked simultaneously, giving O(n·m) worst-case time (n = text
///    length, m = pattern length) with no catastrophic backtracking.
///
/// ## Limitations
///
/// - Character classes support byte values 0–255 (Latin-1). Characters
///   outside this range will not match `[...]` classes but will match `.`.
/// - `.` matches any character (including newline).
/// - No capture groups, backreferences, or lookahead.
/// - Matching is leftmost-longest (POSIX semantics).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Matcher — what a Match state consumes
// ---------------------------------------------------------------------------

///|
/// The kind of character a Match state will accept.
priv enum Matcher {
  /// Match a specific byte value (0–255).
  Char(Int)
  /// Match any character (`.`).
  AnyChar
  /// Match a character class: `set[b]` is true if byte `b` is in the class.
  /// `negated` is true for `[^...]`.
  ClassNode(FixedArray[Bool], Bool)
}

// ---------------------------------------------------------------------------
// NFA state
// ---------------------------------------------------------------------------

///|
/// A single NFA state. States are stored in an array and referenced by index.
///
/// - **Match state**: `matcher` is `Some(...)`, `out1` is the next state,
///   `out2` is unused (-1).
/// - **Split state**: `matcher` is `None`, `is_accept` is `false`. Both
///   `out1` and `out2` are epsilon transitions.
/// - **Accept state**: `is_accept` is `true`, `matcher` is `None`, both
///   outs are -1.
priv struct NFAState {
  matcher : Matcher?
  mut out1 : Int // first out-transition (-1 = none/dangling)
  mut out2 : Int // second out-transition (-1 = none/dangling)
  is_accept : Bool
}

// ---------------------------------------------------------------------------
// Fragment — a partially built NFA with dangling out-transitions
// ---------------------------------------------------------------------------

///|
/// An NFA fragment produced during Thompson's construction.
///
/// - `start` — the entry state index.
/// - `out` — a list of `(state_index, field)` pairs indicating which
///   `out`-transition of which state is still dangling (not yet connected).
///   `field` 0 means `out1`, 1 means `out2`.
priv struct Frag {
  start : Int
  out : Array[(Int, Int)]
}

// ---------------------------------------------------------------------------
// Builder — parser + NFA state allocator
// ---------------------------------------------------------------------------

///|
/// The builder combines the parser state with the NFA state array.
/// Parsing and NFA construction happen simultaneously: each parse function
/// returns a `Frag` that can be composed into larger fragments.
priv struct Builder {
  pattern : String
  mut pos : Int
  states : Array[NFAState]
}

///|
/// Create a new builder for `pattern`.
fn new_builder(pattern : String) -> Builder {
  { pattern, pos: 0, states: [] }
}

///|
/// Peek at the current character code (0–255), or `None` at end of input.
fn peek(b : Builder) -> Int? {
  if b.pos >= b.pattern.length() {
    None
  } else {
    Some(b.pattern[b.pos].to_int())
  }
}

///|
/// Consume and return the current character code, or `None` at end.
fn next_char(b : Builder) -> Int? {
  if b.pos >= b.pattern.length() {
    None
  } else {
    let c = b.pattern[b.pos].to_int()
    b.pos = b.pos + 1
    Some(c)
  }
}

///|
/// Allocate a new NFA state and return its index.
fn new_state(
  b : Builder,
  matcher : Matcher?,
  out1 : Int,
  out2 : Int,
  is_accept : Bool,
) -> Int {
  let idx = b.states.length()
  b.states.push({ matcher, out1, out2, is_accept })
  idx
}

///|
/// Allocate a Match state (consumes one character, then transitions to `out1`).
fn new_match(b : Builder, matcher : Matcher) -> Int {
  new_state(b, Some(matcher), -1, -1, false)
}

///|
/// Allocate a Split state (two epsilon transitions).
fn new_split(b : Builder, out1 : Int, out2 : Int) -> Int {
  new_state(b, None, out1, out2, false)
}

///|
/// Allocate the Accept (final) state.
fn new_accept(b : Builder) -> Int {
  new_state(b, None, -1, -1, true)
}

///|
/// Create an empty fragment that matches the empty string (epsilon).
/// Uses a Split state with one dangling out-transition.
fn empty_frag(b : Builder) -> Frag {
  let s = new_split(b, -1, -1)
  { start: s, out: [(s, 0)] }
}

///|
/// Patch all dangling out-transitions in `outs` to point to `target`.
fn patch(b : Builder, outs : Array[(Int, Int)], target : Int) -> Unit {
  for i = 0; i < outs.length(); i = i + 1 {
    let (state_idx, field) = outs[i]
    if field == 0 {
      b.states[state_idx].out1 = target
    } else {
      b.states[state_idx].out2 = target
    }
  }
}

// ---------------------------------------------------------------------------
// Parser — recursive descent
// ---------------------------------------------------------------------------

///|
/// Parse the full pattern. Returns `Some(Frag)` on success, `None` on error.
fn parse_regex(b : Builder) -> Frag? {
  match parse_alternation(b) {
    Some(frag) =>
      if b.pos == b.pattern.length() {
        Some(frag)
      } else {
        None // Trailing characters (e.g. unmatched ')')
      }
    None => None
  }
}

///|
/// Parse alternation: `concat ('|' concat)*`
fn parse_alternation(b : Builder) -> Frag? {
  match parse_concat(b) {
    None => None
    Some(first) => {
      let mut frag = first
      let mut continue_loop = true
      while continue_loop {
        match peek(b) {
          Some(124) => {
            // 124 = '|'
            b.pos = b.pos + 1 // consume '|'
            match parse_concat(b) {
              None => return None // Error: nothing after '|'
              Some(second) => {
                // Build: Split -> first | second
                let split = new_split(b, frag.start, second.start)
                // Merge the dangling outs.
                let combined : Array[(Int, Int)] = []
                for i = 0; i < frag.out.length(); i = i + 1 {
                  combined.push(frag.out[i])
                }
                for i = 0; i < second.out.length(); i = i + 1 {
                  combined.push(second.out[i])
                }
                frag = { start: split, out: combined }
              }
            }
          }
          _ => continue_loop = false
        }
      }
      Some(frag)
    }
  }
}

///|
/// Parse concatenation: `quantified*` (zero or more quantified atoms).
///
/// Terminators (`|` or `)`) and end-of-input end the concatenation cleanly.
/// Any other parse failure (e.g. unmatched `(`, trailing `\`, quantifier
/// without an atom) is a syntax error and propagates as `None`.
fn parse_concat(b : Builder) -> Frag? {
  let mut frag = empty_frag(b)
  let mut done = false
  while !done {
    match peek(b) {
      None => done = true
      Some(c) =>
        if c == 124 || c == 41 {
          done = true // '|' or ')' ends the concatenation
        } else {
          match parse_quantified(b) {
            None => return None // Syntax error (not a clean terminator)
            Some(next) => {
              // Concatenate: patch frag's dangling outs to next's start.
              patch(b, frag.out, next.start)
              frag = { start: frag.start, out: next.out }
            }
          }
        }
    }
  }
  Some(frag)
}

///|
/// Parse a quantified atom: `atom ('*' | '+' | '?')?`
fn parse_quantified(b : Builder) -> Frag? {
  match parse_atom(b) {
    None => None
    Some(frag) =>
      match peek(b) {
        Some(42) => {
          // '*' — zero or more
          b.pos = b.pos + 1
          let split = new_split(b, frag.start, -1)
          // Patch frag's dangling outs back to the split (loop).
          patch(b, frag.out, split)
          // The dangling out is split's out2.
          Some({ start: split, out: [(split, 1)] })
        }
        Some(43) => {
          // '+' — one or more
          b.pos = b.pos + 1
          let split = new_split(b, frag.start, -1)
          // Patch frag's dangling outs back to the split (loop).
          patch(b, frag.out, split)
          // Start is frag.start; dangling out is split's out2.
          Some({ start: frag.start, out: [(split, 1)] })
        }
        Some(63) => {
          // '?' — zero or one
          b.pos = b.pos + 1
          let split = new_split(b, frag.start, -1)
          // Merge dangling outs: frag's outs + split's out2.
          let combined : Array[(Int, Int)] = []
          for i = 0; i < frag.out.length(); i = i + 1 {
            combined.push(frag.out[i])
          }
          combined.push((split, 1))
          Some({ start: split, out: combined })
        }
        _ => Some(frag) // No quantifier
      }
  }
}

///|
/// Parse a single atom: `(` regex `)` | `[` class `]` | `\` escape | `.` | literal
fn parse_atom(b : Builder) -> Frag? {
  match next_char(b) {
    None => None // Unexpected end of input
    Some(c) =>
      if c == 40 {
        // '(' — grouping
        let inner = parse_alternation(b)
        match inner {
          None => None
          Some(frag) =>
            match next_char(b) {
              Some(41) => Some(frag) // ')'
              _ => None // Missing ')'
            }
        }
      } else if c == 91 {
        // '[' — character class
        match parse_class(b) {
          None => None
          Some(matcher) => {
            let s = new_match(b, matcher)
            Some({ start: s, out: [(s, 0)] })
          }
        }
      } else if c == 92 {
        // '\' — escaped character
        match next_char(b) {
          None => None // Trailing backslash
          Some(escaped) => {
            let s = new_match(b, Char(escaped))
            Some({ start: s, out: [(s, 0)] })
          }
        }
      } else if c == 46 {
        // '.' — any character
        let s = new_match(b, AnyChar)
        Some({ start: s, out: [(s, 0)] })
      } else if c == 41 || c == 124 || c == 42 || c == 43 || c == 63 {
        // ')', '|', '*', '+', '?' — these should not start an atom
        b.pos = b.pos - 1 // Unconsume
        None
      } else {
        // Literal character
        let s = new_match(b, Char(c))
        Some({ start: s, out: [(s, 0)] })
      }
  }
}

///|
/// Parse a character class `[...]` or `[^...]`.
///
/// The `[` has already been consumed. Reads until `]` and returns a `Matcher`.
/// Returns `None` if the class is malformed (e.g. missing `]`).
///
/// Ranges (`a-z`) use the **most recently added character** as the low end,
/// tracked via `last_char`. After a range is expanded, `last_char` is reset
/// to `-1` so a subsequent `-` is treated as a literal (preventing
/// `[a-z-0]` from misinterpreting the middle `-`).
fn parse_class(b : Builder) -> Matcher? {
  let set = FixedArray::make(256, false)
  let mut negated = false
  // Check for negation.
  match peek(b) {
    Some(94) => {
      // 94 = '^'
      negated = true
      b.pos = b.pos + 1
    }
    _ => ()
  }
  // last_char tracks the most recently added single character (not the
  // result of a range expansion). Used to detect ranges: `c-c`.
  let mut last_char = -1
  let mut done = false
  while !done {
    match next_char(b) {
      None => return None // Missing ']'
      Some(c) =>
        if c == 93 {
          // ']' — end of class
          done = true
        } else if c == 92 {
          // '\' — escaped character inside class
          match next_char(b) {
            None => return None
            Some(escaped) => {
              set[escaped] = true
              last_char = escaped
            }
          }
        } else if c == 45 && last_char >= 0 {
          // '-' — potential range (there is a preceding character)
          match peek(b) {
            Some(93) => {
              // '-' at end of class: literal '-'
              set[45] = true
              last_char = 45
            }
            _ =>
              // Read the end of the range
              match next_char(b) {
                None => return None
                Some(end_c) =>
                  if end_c == 92 {
                    // Escaped character after '-'
                    match next_char(b) {
                      None => return None
                      Some(escaped_end) => {
                        let lo = last_char
                        let hi = escaped_end
                        if hi >= lo {
                          for k = lo; k <= hi; k = k + 1 {
                            set[k] = true
                          }
                        }
                        last_char = -1
                      }
                    }
                  } else if end_c == 93 {
                    // ']' after '-' — treat '-' as literal
                    set[45] = true
                    last_char = 45
                    done = true
                  } else {
                    let lo = last_char
                    let hi = end_c
                    if hi >= lo {
                      for k = lo; k <= hi; k = k + 1 {
                        set[k] = true
                      }
                    }
                    last_char = -1
                  }
              }
          }
        } else {
          set[c] = true
          last_char = c
        }
    }
  }
  Some(ClassNode(set, negated))
}

// ---------------------------------------------------------------------------
// Public API — Regex struct, compile, is_match, find
// ---------------------------------------------------------------------------

///|
/// A compiled regular expression.
///
/// Create with `compile`. The internal representation is a Thompson NFA
/// stored as an array of states. Matching is done via parallel simulation
/// (all reachable states tracked simultaneously), giving guaranteed linear
/// time in the text length for each match attempt.
pub struct Regex {
  priv states : Array[NFAState]
  priv start : Int
}

///|
/// Compile a regex pattern string into a `Regex`.
///
/// Returns `Some(Regex)` on success, or `None` if the pattern has a syntax
/// error (unbalanced parentheses, trailing quantifiers, unterminated classes,
/// etc.).
///
/// ```moonbit nocheck
/// let re = compile("a(b|c)*d")
/// match re {
///   Some(r) => assert_true(is_match(r, "abcbd"))
///   None => fail("invalid pattern")
/// }
/// ```
pub fn compile(pattern : String) -> Regex? {
  let b = new_builder(pattern)
  match parse_regex(b) {
    None => None
    Some(frag) => {
      let accept = new_accept(b)
      patch(b, frag.out, accept)
      Some({ states: b.states, start: frag.start })
    }
  }
}

// ---------------------------------------------------------------------------
// NFA simulation helpers
// ---------------------------------------------------------------------------

///|
/// Clear the visited array (set all entries to false).
fn clear_visited(visited : FixedArray[Bool]) -> Unit {
  for i = 0; i < visited.length(); i = i + 1 {
    visited[i] = false
  }
}

///|
/// Recursively add a state and all states reachable via epsilon transitions
/// to `list`. Uses `visited` to avoid revisiting (prevents infinite loops
/// on cycles like `a*`).
///
/// Only Match and Accept states are added to `list`; Split states are
/// traversed but not stored (they represent pure epsilon transitions).
fn add_state(
  states : Array[NFAState],
  state_idx : Int,
  list : Array[Int],
  visited : FixedArray[Bool],
) -> Unit {
  if state_idx < 0 || state_idx >= states.length() {
    return
  }
  if visited[state_idx] {
    return
  }
  visited[state_idx] = true
  let s = states[state_idx]
  if s.is_accept {
    list.push(state_idx)
  } else {
    match s.matcher {
      None => {
        // Split state: follow both epsilon transitions.
        add_state(states, s.out1, list, visited)
        add_state(states, s.out2, list, visited)
      }
      Some(_) =>
        // Match state: add to list.
        list.push(state_idx)
    }
  }
}

///|
/// Check if any state in `list` is the Accept state.
fn has_accept(states : Array[NFAState], list : Array[Int]) -> Bool {
  for i = 0; i < list.length(); i = i + 1 {
    if states[list[i]].is_accept {
      return true
    }
  }
  false
}

///|
/// Check if a character matches a `Matcher`.
fn match_char(m : Matcher, ch : Int) -> Bool {
  match m {
    Char(c) => ch == c
    AnyChar => true
    ClassNode(set, negated) =>
      if ch >= 0 && ch < 256 {
        if negated {
          !set[ch]
        } else {
          set[ch]
        }
      } else {
        // Characters outside 0–255: match iff class is negated.
        negated
      }
  }
}

///|
/// Advance the NFA by one character. For each Match state in `current`
/// whose matcher accepts `ch`, follow its out-transition (with epsilon-closure)
/// and add to `next`. Clears `visited` and `next` before processing.
fn step(
  states : Array[NFAState],
  current : Array[Int],
  ch : Int,
  next : Array[Int],
  visited : FixedArray[Bool],
) -> Unit {
  clear_visited(visited)
  next.clear()
  for i = 0; i < current.length(); i = i + 1 {
    let s = states[current[i]]
    match s.matcher {
      Some(m) =>
        if match_char(m, ch) {
          add_state(states, s.out1, next, visited)
        }
      None => () // Accept state: no transition.
    }
  }
}

// ---------------------------------------------------------------------------
// Public matching functions
// ---------------------------------------------------------------------------

///|
/// Test whether `re` matches anywhere in `text`.
///
/// Returns `true` if the regex matches any substring of `text` (including
/// the empty substring if the pattern allows it).
///
/// ```moonbit nocheck
/// let re = compile("hello").unwrap()
/// assert_true(is_match(re, "say hello world"))
/// assert_false(is_match(re, "goodbye"))
/// ```
pub fn is_match(re : Regex, text : String) -> Bool {
  match find(re, text) {
    Some(_) => true
    None => false
  }
}

///|
/// Find the first (leftmost-longest) match of `re` in `text`.
///
/// Returns `Some((start, end))` where `start` is the byte offset of the
/// first character of the match and `end` is the byte offset just past the
/// last character. Returns `None` if no match is found.
///
/// The search tries each start position from left to right. At each position,
/// the longest match is returned (POSIX leftmost-longest semantics).
///
/// ```moonbit nocheck
/// let re = compile("a+").unwrap()
/// match find(re, "xxaaaay") {
///   Some((s, e)) => {
///     assert_eq(s, 2)
///     assert_eq(e, 6)
///   }
///   None => fail("expected match")
/// }
/// ```
pub fn find(re : Regex, text : String) -> (Int, Int)? {
  let n = text.length()
  let num_states = re.states.length()
  let visited = FixedArray::make(num_states, false)
  let current : Array[Int] = []
  let next : Array[Int] = []
  // Try matching starting at each position (including past the end for
  // empty-string matches).
  for s = 0; s <= n; s = s + 1 {
    // Initialize the NFA at position s.
    clear_visited(visited)
    current.clear()
    add_state(re.states, re.start, current, visited)
    // Check for an immediate (empty) match.
    let mut best_end = -1
    if has_accept(re.states, current) {
      best_end = s
    }
    // Advance through the remaining text.
    let mut e = s
    let mut alive = true
    while e < n && alive {
      step(re.states, current, text[e].to_int(), next, visited)
      e = e + 1
      // Move next into current.
      current.clear()
      for i = 0; i < next.length(); i = i + 1 {
        current.push(next[i])
      }
      if current.length() == 0 {
        alive = false
      } else if has_accept(re.states, current) {
        best_end = e
      }
    }
    if best_end >= 0 {
      return Some((s, best_end))
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "regex: compile valid pattern" {
  assert_true(compile("abc") is Some(_))
  assert_true(compile("a(b|c)*d") is Some(_))
  assert_true(compile("[a-z]+") is Some(_))
  assert_true(compile("") is Some(_))
}

///|
test "regex: compile invalid pattern returns None" {
  // Unmatched parenthesis.
  assert_true(compile("(") is None)
  assert_true(compile("a(b") is None)
  // Quantifier without atom.
  assert_true(compile("*") is None)
  assert_true(compile("+") is None)
  assert_true(compile("?") is None)
  // Unterminated character class.
  assert_true(compile("[abc") is None)
  // Trailing backslash.
  assert_true(compile("a\\") is None)
}

///|
test "regex: literal match" {
  let re = compile("hello").unwrap()
  assert_true(is_match(re, "hello"))
  assert_true(is_match(re, "hello world"))
  assert_true(is_match(re, "say hello!"))
  assert_false(is_match(re, "hell"))
  assert_false(is_match(re, "world"))
}

///|
test "regex: find literal" {
  let re = compile("abc").unwrap()
  match find(re, "xxabcxx") {
    Some((s, e)) => {
      assert_eq(s, 2)
      assert_eq(e, 5)
    }
    None => fail("expected match")
  }
}

///|
test "regex: find no match" {
  let re = compile("xyz").unwrap()
  assert_true(find(re, "abcdef") is None)
}

///|
test "regex: dot matches any char" {
  let re = compile("a.c").unwrap()
  assert_true(is_match(re, "abc"))
  assert_true(is_match(re, "axc"))
  assert_true(is_match(re, "a c"))
  assert_false(is_match(re, "ac"))
}

///|
test "regex: star (zero or more)" {
  let re = compile("a*").unwrap()
  assert_true(is_match(re, ""))
  assert_true(is_match(re, "a"))
  assert_true(is_match(re, "aaa"))
  assert_true(is_match(re, "bbb")) // a* matches empty at pos 0
}

///|
test "regex: plus (one or more)" {
  let re = compile("a+").unwrap()
  assert_false(is_match(re, ""))
  assert_true(is_match(re, "a"))
  assert_true(is_match(re, "aaa"))
}

///|
test "regex: question (zero or one)" {
  let re = compile("ab?c").unwrap()
  assert_true(is_match(re, "ac")) // b is optional
  assert_true(is_match(re, "abc"))
  assert_false(is_match(re, "abbc"))
}

///|
test "regex: alternation" {
  let re = compile("cat|dog").unwrap()
  assert_true(is_match(re, "cat"))
  assert_true(is_match(re, "dog"))
  assert_false(is_match(re, "bird"))
}

///|
test "regex: grouping" {
  let re = compile("(ab)+").unwrap()
  assert_true(is_match(re, "ab"))
  assert_true(is_match(re, "abab"))
  assert_true(is_match(re, "ababab"))
  assert_false(is_match(re, "a"))
}

///|
test "regex: nested groups" {
  let re = compile("(a(b|c)*d)+").unwrap()
  assert_true(is_match(re, "abd"))
  assert_true(is_match(re, "abcd"))
  assert_true(is_match(re, "abcbcd"))
  assert_true(is_match(re, "abdbcd"))
  assert_false(is_match(re, "a"))
}

///|
test "regex: character class" {
  let re = compile("[abc]").unwrap()
  assert_true(is_match(re, "a"))
  assert_true(is_match(re, "b"))
  assert_true(is_match(re, "c"))
  assert_false(is_match(re, "d"))
}

///|
test "regex: negated character class" {
  let re = compile("[^abc]").unwrap()
  assert_false(is_match(re, "a"))
  assert_false(is_match(re, "b"))
  assert_false(is_match(re, "c"))
  assert_true(is_match(re, "d"))
  assert_true(is_match(re, "1"))
}

///|
test "regex: character range" {
  let re = compile("[a-z]").unwrap()
  assert_true(is_match(re, "a"))
  assert_true(is_match(re, "m"))
  assert_true(is_match(re, "z"))
  assert_false(is_match(re, "A"))
  assert_false(is_match(re, "0"))
}

///|
test "regex: mixed range class" {
  let re = compile("[a-zA-Z0-9]").unwrap()
  assert_true(is_match(re, "a"))
  assert_true(is_match(re, "Z"))
  assert_true(is_match(re, "5"))
  assert_false(is_match(re, "!"))
}

///|
test "regex: escaped special chars" {
  let re = compile("a\\.b").unwrap()
  assert_true(is_match(re, "a.b"))
  assert_false(is_match(re, "axb"))
  let re2 = compile("a\\*b").unwrap()
  assert_true(is_match(re2, "a*b"))
  assert_false(is_match(re2, "axb"))
}

///|
test "regex: empty pattern matches empty string" {
  let re = compile("").unwrap()
  assert_true(is_match(re, ""))
  assert_true(is_match(re, "abc")) // Empty match at pos 0
}

///|
test "regex: find longest match" {
  let re = compile("a+").unwrap()
  match find(re, "xxaaaay") {
    Some((s, e)) => {
      assert_eq(s, 2)
      assert_eq(e, 6) // Longest: 4 a's
    }
    None => fail("expected match")
  }
}

///|
test "regex: find at different positions" {
  let re = compile("bc").unwrap()
  match find(re, "abcd") {
    Some((s, e)) => {
      assert_eq(s, 1)
      assert_eq(e, 3)
    }
    None => fail("expected match")
  }
}

///|
test "regex: complex pattern" {
  // Match a simple word: letters followed by optional digits.
  let re = compile("[a-z]+[0-9]*").unwrap()
  assert_true(is_match(re, "hello"))
  assert_true(is_match(re, "hello123"))
  assert_true(is_match(re, "test"))
  match find(re, "..abc123..") {
    Some((s, e)) => {
      assert_eq(s, 2)
      assert_eq(e, 8)
    }
    None => fail("expected match")
  }
}

///|
test "regex: alternation with groups" {
  let re = compile("(foo|bar)+").unwrap()
  assert_true(is_match(re, "foo"))
  assert_true(is_match(re, "bar"))
  assert_true(is_match(re, "foobar"))
  assert_true(is_match(re, "foofoo"))
  assert_false(is_match(re, "baz"))
}

///|
test "regex: star at start of pattern" {
  let re = compile("a*b").unwrap()
  assert_true(is_match(re, "b"))
  assert_true(is_match(re, "ab"))
  assert_true(is_match(re, "aaab"))
  assert_false(is_match(re, "aac"))
}

///|
test "regex: multiple quantifiers" {
  let re = compile("a*b+c?").unwrap()
  assert_true(is_match(re, "b"))
  assert_true(is_match(re, "ab"))
  assert_true(is_match(re, "aaabbc"))
  assert_true(is_match(re, "bc"))
  assert_false(is_match(re, "d"))
}
