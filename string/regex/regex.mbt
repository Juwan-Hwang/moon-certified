/// Regex Engine — Thompson NFA Construction and Simulation with Capture Groups.
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
/// | `(abc)`     | capture group                         |
/// | `[abc]`     | character class                       |
/// | `[^abc]`    | negated character class               |
/// | `[a-z]`     | character range                       |
/// | `\.`        | escaped literal (any char after `\`)  |
///
/// ## Capture Groups
///
/// Parenthesised sub-expressions `(expr)` become numbered capture groups.
/// Group 0 is the entire match; groups 1, 2, … are assigned left-to-right
/// by opening parenthesis order. Use `find_captures` to retrieve sub-match
/// positions.
///
/// ## Algorithm
///
/// 1. **Parse**: A recursive-descent parser builds NFA fragments directly
///    (no intermediate AST) using Thompson's construction. Capture groups
///    emit marker states (CaptureStart / CaptureEnd) that record positions
///    during simulation.
/// 2. **Simulate**: The NFA is simulated in parallel — all reachable states
///    are tracked simultaneously, giving O(n·m) worst-case time (n = text
///    length, m = pattern length) with no catastrophic backtracking. Each
///    active thread carries its own capture-position array; the first thread
///    to reach a state wins (POSIX leftmost semantics).
///
/// ## Limitations
///
/// - Character classes support byte values 0–255 (Latin-1). Characters
///   outside this range will not match `[...]` classes but will match `.`.
/// - `.` matches any character (including newline).
/// - No backreferences or lookahead.
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
/// - **Split state**: `matcher` is `None`, `is_accept` is `false`,
///   `capture_group` is -1. Both `out1` and `out2` are epsilon transitions.
/// - **Capture state**: `capture_group >= 0`, `is_capture_start` indicates
///   start vs end. Epsilon-like (no input consumed), `out1` is the next state.
/// - **Accept state**: `is_accept` is `true`, `matcher` is `None`, both
///   outs are -1.
priv struct NFAState {
  matcher : Matcher?
  mut out1 : Int // first out-transition (-1 = none/dangling)
  mut out2 : Int // second out-transition (-1 = none/dangling)
  is_accept : Bool
  capture_group : Int // -1 = not a capture state; >= 0 = group id
  is_capture_start : Bool // true = CaptureStart, false = CaptureEnd
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
  mut group_count : Int // number of capture groups (excluding group 0)
}

///|
/// Create a new builder for `pattern`.
fn new_builder(pattern : String) -> Builder {
  { pattern, pos: 0, states: [], group_count: 0 }
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
  capture_group : Int,
  is_capture_start : Bool,
) -> Int {
  let idx = b.states.length()
  b.states.push({ matcher, out1, out2, is_accept, capture_group, is_capture_start })
  idx
}

///|
/// Allocate a Match state (consumes one character, then transitions to `out1`).
fn new_match(b : Builder, matcher : Matcher) -> Int {
  new_state(b, Some(matcher), -1, -1, false, -1, false)
}

///|
/// Allocate a Split state (two epsilon transitions).
fn new_split(b : Builder, out1 : Int, out2 : Int) -> Int {
  new_state(b, None, out1, out2, false, -1, false)
}

///|
/// Allocate a CaptureStart state for group `group_id`.
/// Epsilon-like: does not consume input, records the current text position
/// as the start of capture group `group_id`, then transitions to `out1`.
fn new_capture_start(b : Builder, group_id : Int) -> Int {
  new_state(b, None, -1, -1, false, group_id, true)
}

///|
/// Allocate a CaptureEnd state for group `group_id`.
/// Epsilon-like: does not consume input, records the current text position
/// as the end of capture group `group_id`, then transitions to `out1`.
fn new_capture_end(b : Builder, group_id : Int) -> Int {
  new_state(b, None, -1, -1, false, group_id, false)
}

///|
/// Allocate the Accept (final) state.
fn new_accept(b : Builder) -> Int {
  new_state(b, None, -1, -1, true, -1, false)
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
///
/// For `(`, a capture group is created: the group number is assigned
/// incrementally, and CaptureStart/CaptureEnd states are emitted around the
/// inner fragment.
fn parse_atom(b : Builder) -> Frag? {
  match next_char(b) {
    None => None // Unexpected end of input
    Some(c) =>
      if c == 40 {
        // '(' — capture group
        b.group_count = b.group_count + 1
        let group_id = b.group_count
        let cap_start = new_capture_start(b, group_id)
        let inner = parse_alternation(b)
        match inner {
          None => None
          Some(frag) =>
            match next_char(b) {
              Some(41) => {
                // ')' — close capture group
                let cap_end = new_capture_end(b, group_id)
                // Connect: cap_start -> frag -> cap_end
                patch(b, [(cap_start, 0)], frag.start)
                patch(b, frag.out, cap_end)
                Some({ start: cap_start, out: [(cap_end, 0)] })
              }
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
        // '\' — escaped character or character class shorthand
        match next_char(b) {
          None => None // Trailing backslash
          Some(escaped) => {
            // Handle character class shorthands: \d, \D, \w, \W, \s, \S
            let shorthand = match escaped {
              100 => {
                // \d — digit [0-9]
                let set = FixedArray::make(256, false)
                for i = 48; i <= 57; i = i + 1 {
                  set[i] = true
                }
                Some(ClassNode(set, false))
              }
              68 => {
                // \D — non-digit [^0-9]
                let set = FixedArray::make(256, false)
                for i = 48; i <= 57; i = i + 1 {
                  set[i] = true
                }
                Some(ClassNode(set, true))
              }
              119 => {
                // \w — word character [a-zA-Z0-9_]
                let set = FixedArray::make(256, false)
                for i = 48; i <= 57; i = i + 1 {
                  set[i] = true
                }
                for i = 65; i <= 90; i = i + 1 {
                  set[i] = true
                }
                for i = 97; i <= 122; i = i + 1 {
                  set[i] = true
                }
                set[95] = true // underscore
                Some(ClassNode(set, false))
              }
              87 => {
                // \W — non-word character
                let set = FixedArray::make(256, false)
                for i = 48; i <= 57; i = i + 1 {
                  set[i] = true
                }
                for i = 65; i <= 90; i = i + 1 {
                  set[i] = true
                }
                for i = 97; i <= 122; i = i + 1 {
                  set[i] = true
                }
                set[95] = true
                Some(ClassNode(set, true))
              }
              115 => {
                // \s — whitespace [ \t\n\r\f\v]
                let set = FixedArray::make(256, false)
                set[32] = true // space
                set[9] = true // tab
                set[10] = true // newline
                set[13] = true // carriage return
                set[12] = true // form feed
                set[11] = true // vertical tab
                Some(ClassNode(set, false))
              }
              83 => {
                // \S — non-whitespace
                let set = FixedArray::make(256, false)
                set[32] = true
                set[9] = true
                set[10] = true
                set[13] = true
                set[12] = true
                set[11] = true
                Some(ClassNode(set, true))
              }
              _ => None
            }
            match shorthand {
              Some(m) => {
                let s = new_match(b, m)
                Some({ start: s, out: [(s, 0)] })
              }
              None => {
                // Regular escaped character
                let s = new_match(b, Char(escaped))
                Some({ start: s, out: [(s, 0)] })
              }
            }
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
// Public API — Regex struct, compile, match functions
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
  priv num_groups : Int // number of capture groups (excluding group 0)
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
      Some({ states: b.states, start: frag.start, num_groups: b.group_count })
    }
  }
}

///|
/// Returns the number of capture groups in the compiled regex (excluding
/// group 0, which is the entire match). For a pattern with no parentheses,
/// this returns 0.
pub fn group_count(re : Regex) -> Int {
  re.num_groups
}

// ---------------------------------------------------------------------------
// Capture result type
// ---------------------------------------------------------------------------

///|
/// The result of a capture-group match.
///
/// - `start` / `end`: byte offsets of the entire match (group 0).
/// - `groups`: array of length `group_count(re)`. `groups[i]` corresponds
///   to capture group `i + 1`. `Some((s, e))` if the group participated in
///   the match, `None` if it did not match (e.g. inside an unmatched
///   alternation branch).
pub struct CaptureMatch {
  start : Int
  end : Int
  groups : Array[(Int, Int)?]
}

///|
/// Retrieve a capture group from a match.
///
/// `idx == 0` returns the entire match `(start, end)`.
/// `idx >= 1` returns the corresponding capture group, or `None` if the
/// group did not participate in the match.
pub fn group(m : CaptureMatch, idx : Int) -> (Int, Int)? {
  if idx == 0 {
    Some((m.start, m.end))
  } else if idx >= 1 && idx <= m.groups.length() {
    m.groups[idx - 1]
  } else {
    None
  }
}

// ---------------------------------------------------------------------------
// NFA simulation helpers (capture-aware)
// ---------------------------------------------------------------------------

///|
/// A thread in the parallel NFA simulation: a state index paired with
/// capture positions. `captures[2*g]` = start of group `g+1`,
/// `captures[2*g+1]` = end of group `g+1`, -1 = unset.
type Thread = (Int, FixedArray[Int])

///|
/// Clear the visited array (set all entries to false).
fn clear_visited(visited : FixedArray[Bool]) -> Unit {
  for i = 0; i < visited.length(); i = i + 1 {
    visited[i] = false
  }
}

///|
/// Deep-copy a captures array.
fn copy_captures(caps : FixedArray[Int]) -> FixedArray[Int] {
  let n = caps.length()
  if n == 0 {
    return FixedArray::make(0, 0)
  }
  let result = FixedArray::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    result[i] = caps[i]
  }
  result
}

///|
/// Recursively add a state and all states reachable via epsilon transitions
/// to `list`. Uses `visited` to avoid revisiting (prevents infinite loops
/// on cycles like `a*`).
///
/// Only Match and Accept states are added to `list`; Split and Capture
/// states are traversed but not stored (they represent pure epsilon
/// transitions). Capture states update the thread's captures array
/// (copy-on-write) before following their out-transition.
///
/// `pos` is the current text position (the index of the next character to
/// be consumed). Capture markers record this position.
fn add_state(
  states : Array[NFAState],
  state_idx : Int,
  pos : Int,
  captures : FixedArray[Int],
  list : Array[Thread],
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
    list.push((state_idx, captures))
  } else if s.capture_group >= 0 {
    // Capture state: epsilon-like, update captures and follow out1.
    // Copy-on-write: create a new captures array so the original thread's
    // captures are not affected (split branches may share the same array).
    let new_caps = copy_captures(captures)
    let g = s.capture_group
    // captures indices: group 1 is at [0],[1]; group g is at [2*(g-1)],[2*(g-1)+1].
    let base = 2 * (g - 1)
    if s.is_capture_start {
      new_caps[base] = pos
    } else {
      new_caps[base + 1] = pos
    }
    add_state(states, s.out1, pos, new_caps, list, visited)
  } else {
    match s.matcher {
      None => {
        // Split state: follow both epsilon transitions.
        add_state(states, s.out1, pos, captures, list, visited)
        add_state(states, s.out2, pos, captures, list, visited)
      }
      Some(_) =>
        // Match state: add to list with its captures.
        list.push((state_idx, captures))
    }
  }
}

///|
/// Check if any thread in `list` is in the Accept state.
/// Returns the captures of the first accepting thread, or `None`.
fn find_accept(
  states : Array[NFAState],
  list : Array[Thread],
) -> FixedArray[Int]? {
  for i = 0; i < list.length(); i = i + 1 {
    let (state_idx, captures) = list[i]
    if states[state_idx].is_accept {
      return Some(captures)
    }
  }
  None
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
///
/// `pos` is the text position *after* consuming `ch` (i.e. the index of the
/// next character). Capture markers encountered during epsilon closure record
/// this position.
fn step(
  states : Array[NFAState],
  current : Array[Thread],
  ch : Int,
  pos : Int,
  next : Array[Thread],
  visited : FixedArray[Bool],
) -> Unit {
  clear_visited(visited)
  next.clear()
  for i = 0; i < current.length(); i = i + 1 {
    let (state_idx, captures) = current[i]
    let s = states[state_idx]
    match s.matcher {
      Some(m) =>
        if match_char(m, ch) {
          add_state(states, s.out1, pos, captures, next, visited)
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
  match find_captures(re, text) {
    None => None
    Some(m) => Some((m.start, m.end))
  }
}

///|
/// Find the first (leftmost-longest) match of `re` in `text`, with capture
/// group positions.
///
/// Returns `Some(CaptureMatch)` if a match is found, or `None` if no match.
/// The `CaptureMatch` contains the overall match span and the positions of
/// each capture group.
///
/// ```moonbit nocheck
/// let re = compile("(\\d+)-(\\d+)").unwrap()
/// match find_captures(re, "abc 123-456 end") {
///   Some(m) => {
///     assert_eq(m.start, 4)
///     assert_eq(m.end, 11)
///     // Group 1: "123" at (4, 7)
///     assert_eq(group(m, 1), Some((4, 7)))
///     // Group 2: "456" at (8, 11)
///     assert_eq(group(m, 2), Some((8, 11)))
///   }
///   None => fail("expected match")
/// }
/// ```
pub fn find_captures(re : Regex, text : String) -> CaptureMatch? {
  let n = text.length()
  let num_states = re.states.length()
  let visited = FixedArray::make(num_states, false)
  let current : Array[Thread] = []
  let next : Array[Thread] = []
  let caps_size = 2 * re.num_groups
  // Try matching starting at each position (including past the end for
  // empty-string matches).
  for s = 0; s <= n; s = s + 1 {
    // Initialize the NFA at position s with empty captures.
    clear_visited(visited)
    current.clear()
    let initial_caps = FixedArray::make(caps_size, -1)
    add_state(re.states, re.start, s, initial_caps, current, visited)
    // Check for an immediate (empty) match.
    let mut best_end = -1
    let mut best_caps : FixedArray[Int]? = None
    match find_accept(re.states, current) {
      Some(caps) => {
        best_end = s
        best_caps = Some(caps)
      }
      None => ()
    }
    // Advance through the remaining text.
    let mut e = s
    let mut alive = true
    while e < n && alive {
      step(re.states, current, text[e].to_int(), e + 1, next, visited)
      e = e + 1
      // Move next into current.
      current.clear()
      for i = 0; i < next.length(); i = i + 1 {
        current.push(next[i])
      }
      if current.length() == 0 {
        alive = false
      } else {
        match find_accept(re.states, current) {
          Some(caps) => {
            best_end = e
            best_caps = Some(caps)
          }
          None => ()
        }
      }
    }
    if best_end >= 0 {
      // Build the CaptureMatch from the best captures.
      let groups : Array[(Int, Int)?] = Array::make(re.num_groups, None)
      match best_caps {
        Some(caps) =>
          for g = 1; g <= re.num_groups; g = g + 1 {
            let base = 2 * (g - 1)
            let gs = caps[base]
            let ge = caps[base + 1]
            if gs >= 0 && ge >= 0 {
              groups[g - 1] = Some((gs, ge))
            }
          }
        None => ()
      }
      return Some({ start: s, end: best_end, groups })
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

// ---------------------------------------------------------------------------
// Capture group tests
// ---------------------------------------------------------------------------

///|
test "regex: group_count" {
  assert_eq(group_count(compile("abc").unwrap()), 0)
  assert_eq(group_count(compile("(abc)").unwrap()), 1)
  assert_eq(group_count(compile("(a)(b)(c)").unwrap()), 3)
  assert_eq(group_count(compile("(a(b(c)))").unwrap()), 3)
  assert_eq(group_count(compile("(a|b)*c(d|e)+").unwrap()), 2)
}

///|
test "regex: basic capture group" {
  let re = compile("(\\d+)-(\\d+)").unwrap()
  match find_captures(re, "abc 123-456 end") {
    Some(m) => {
      assert_eq(m.start, 4)
      assert_eq(m.end, 11)
      assert_eq(group(m, 0), Some((4, 11)))
      assert_eq(group(m, 1), Some((4, 7))) // "123"
      assert_eq(group(m, 2), Some((8, 11))) // "456"
    }
    None => fail("expected match")
  }
}

///|
test "regex: capture group with alternation" {
  let re = compile("(foo|bar)").unwrap()
  match find_captures(re, "hello bar world") {
    Some(m) => {
      assert_eq(m.start, 6)
      assert_eq(m.end, 9)
      assert_eq(group(m, 1), Some((6, 9))) // "bar"
    }
    None => fail("expected match")
  }
}

///|
test "regex: nested capture groups" {
  let re = compile("(a(b)c)").unwrap()
  match find_captures(re, "abc") {
    Some(m) => {
      assert_eq(group(m, 1), Some((0, 3))) // "abc"
      assert_eq(group(m, 2), Some((1, 2))) // "b"
    }
    None => fail("expected match")
  }
}

///|
test "regex: capture in starred group" {
  let re = compile("(ab)*").unwrap()
  match find_captures(re, "ababab") {
    Some(m) => {
      // The last iteration of (ab) should be captured.
      let g1 = group(m, 1)
      assert_true(g1 is Some(_))
      match g1 {
        Some((s, e)) => {
          // Last "ab" is at positions 4..6.
          assert_eq(s, 4)
          assert_eq(e, 6)
        }
        None => fail("expected group 1")
      }
    }
    None => fail("expected match")
  }
}

///|
test "regex: capture group not matched (alternation)" {
  // When the first branch matches, the second group doesn't participate.
  let re = compile("(a)|(b)").unwrap()
  match find_captures(re, "a") {
    Some(m) => {
      assert_eq(group(m, 1), Some((0, 1))) // "a"
      assert_eq(group(m, 2), None) // "b" branch not taken
    }
    None => fail("expected match")
  }
  match find_captures(re, "b") {
    Some(m) => {
      assert_eq(group(m, 1), None) // "a" branch not taken
      assert_eq(group(m, 2), Some((0, 1))) // "b"
    }
    None => fail("expected match")
  }
}

///|
test "regex: no capture groups" {
  let re = compile("abc").unwrap()
  match find_captures(re, "xxabcxx") {
    Some(m) => {
      assert_eq(m.start, 2)
      assert_eq(m.end, 5)
      assert_eq(m.groups.length(), 0)
      assert_eq(group(m, 0), Some((2, 5)))
      assert_eq(group(m, 1), None) // out of range
    }
    None => fail("expected match")
  }
}

///|
test "regex: capture with email-like pattern" {
  let re = compile("([a-z]+)@([a-z]+)\\.([a-z]+)").unwrap()
  match find_captures(re, "contact: user@example.com end") {
    Some(m) => {
      assert_eq(group(m, 1), Some((9, 13))) // "user"
      assert_eq(group(m, 2), Some((14, 21))) // "example"
      assert_eq(group(m, 3), Some((22, 25))) // "com"
    }
    None => fail("expected match")
  }
}

///|
test "regex: capture group out of range returns None" {
  let re = compile("(a)").unwrap()
  match find_captures(re, "a") {
    Some(m) => {
      assert_eq(group(m, 0), Some((0, 1)))
      assert_eq(group(m, 1), Some((0, 1)))
      assert_eq(group(m, 2), None) // out of range
      assert_eq(group(m, -1), None) // negative
    }
    None => fail("expected match")
  }
}

///|
test "regex: find_captures no match returns None" {
  let re = compile("(xyz)").unwrap()
  assert_true(find_captures(re, "abcdef") is None)
}

///|
test "regex: empty capture group" {
  let re = compile("a()b").unwrap()
  match find_captures(re, "ab") {
    Some(m) => {
      assert_eq(m.start, 0)
      assert_eq(m.end, 2)
      // Group 1 matches empty string at position 1.
      assert_eq(group(m, 1), Some((1, 1)))
    }
    None => fail("expected match")
  }
}

///|
test "regex: multiple capture groups in sequence" {
  let re = compile("(\\d+):(\\d+):(\\d+)").unwrap()
  match find_captures(re, "time 10:20:30 end") {
    Some(m) => {
      assert_eq(group(m, 1), Some((5, 7))) // "10"
      assert_eq(group(m, 2), Some((8, 10))) // "20"
      assert_eq(group(m, 3), Some((11, 13))) // "30"
    }
    None => fail("expected match")
  }
}

///|
test "regex: capture group with quantifier" {
  let re = compile("(\\w+)").unwrap()
  match find_captures(re, "  hello  ") {
    Some(m) => {
      assert_eq(m.start, 2)
      assert_eq(m.end, 7)
      assert_eq(group(m, 1), Some((2, 7)))
    }
    None => fail("expected match")
  }
}

///|
test "regex: deeply nested capture groups" {
  let re = compile("(a(b(c)d)e)").unwrap()
  match find_captures(re, "abcde") {
    Some(m) => {
      assert_eq(group(m, 1), Some((0, 5))) // "abcde"
      assert_eq(group(m, 2), Some((1, 4))) // "bcd"
      assert_eq(group(m, 3), Some((2, 3))) // "c"
    }
    None => fail("expected match")
  }
}
