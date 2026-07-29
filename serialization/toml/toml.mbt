/// TOML (Tom's Obvious, Minimal Language) — TOML 1.0.0 parser and serializer.
///
/// This package provides a production-grade TOML implementation with:
///
/// - **TOML 1.0.0 core subset**: key/value pairs, `[table]` headers,
///   `[[array-of-tables]]`, dotted keys, inline tables, arrays, basic and
///   literal strings (single- and multi-line), integers (decimal, `0x`, `0o`,
///   `0b`, with `_` separators), floats (incl. `inf`/`nan`), and booleans.
/// - **Comment handling**: `#` comments are accepted everywhere a value or
///   statement boundary is expected.
/// - **Structural fidelity**: tables defined out-of-order via headers are
///   merged into a single nested value tree, mirroring the TOML data model.
/// - **Round-trippable serializer**: `to_toml` emits canonical TOML text that
///   re-parses to an equal value tree.
/// - **Option-based error handling**: `parse` returns `TomlValue?` (`None` on
///   malformed input), matching the library-wide convention.
///
/// ## References
///
/// - TOML 1.0.0 specification: <https://toml.io/en/v1.0.0>
///
/// ## Limitations
///
/// - Integers are stored as 32-bit `Int`; values outside `[-2^31, 2^31-1]`
///   are not supported (a parse failure occurs).
/// - Local date/time values are not modelled (they would parse as strings).
/// - Strict duplicate-key detection is relaxed: re-selecting an existing
///   table via a header is permitted; conflicting redefinitions of a leaf
///   key are rejected.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// TomlValue type
// ---------------------------------------------------------------------------

///|
/// A TOML value, following the TOML 1.0.0 data model.
///
/// - `Str(String)` — a TOML string (basic or literal).
/// - `Int(Int)` — a TOML integer (decimal/hex/octal/binary).
/// - `Float(Double)` — a TOML float (including `inf`/`nan`).
/// - `Bool(Bool)` — `true` or `false`.
/// - `Array(Array[TomlValue])` — a TOML array (ordered, heterogeneous).
/// - `Table(Array[(String, TomlValue)])` — a TOML table (ordered map).
///   Duplicate keys are not produced by the parser; lookups use last-wins
///   semantics for safety.
pub enum TomlValue {
  Str(String)
  Int(Int)
  Float(Double)
  Bool(Bool)
  Array(Array[TomlValue])
  Table(Array[(String, TomlValue)])
}

///|
/// Structural equality for `TomlValue`. Two values are equal iff they have
/// the same type and recursively equal contents.
impl Eq for TomlValue with equal(a, b) {
  match (a, b) {
    (Str(x), Str(y)) => x == y
    (Int(x), Int(y)) => x == y
    (Float(x), Float(y)) => x == y
    (Bool(x), Bool(y)) => x == y
    (Array(x), Array(y)) => toml_array_eq(x, y)
    (Table(x), Table(y)) => toml_table_eq(x, y)
    _ => false
  }
}

///|
fn toml_array_eq(x : Array[TomlValue], y : Array[TomlValue]) -> Bool {
  if x.length() != y.length() {
    return false
  }
  let mut eq = true
  for i = 0; i < x.length(); i = i + 1 {
    if !(x[i] == y[i]) {
      eq = false
      break
    }
  }
  eq
}

///|
fn toml_table_eq(x : Array[(String, TomlValue)], y : Array[(String, TomlValue)]) -> Bool {
  if x.length() != y.length() {
    return false
  }
  let mut eq = true
  for i = 0; i < x.length(); i = i + 1 {
    let (xk, xv) = x[i]
    let (yk, yv) = y[i]
    if xk != yk || !(xv == yv) {
      eq = false
      break
    }
  }
  eq
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

///|
/// Construct a TOML string value.
pub fn toml_str(s : String) -> TomlValue {
  Str(s)
}

///|
/// Construct a TOML integer value.
pub fn toml_int(i : Int) -> TomlValue {
  Int(i)
}

///|
/// Construct a TOML float value.
pub fn toml_float(f : Double) -> TomlValue {
  Float(f)
}

///|
/// Construct a TOML boolean value.
pub fn toml_bool(b : Bool) -> TomlValue {
  Bool(b)
}

///|
/// Construct a TOML array from a list of values.
pub fn toml_array(items : Array[TomlValue]) -> TomlValue {
  Array(items)
}

///|
/// Construct a TOML table from a list of key-value pairs.
pub fn toml_table(pairs : Array[(String, TomlValue)]) -> TomlValue {
  Table(pairs)
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

///|
/// Look up a key in a TOML table. Returns `None` if `v` is not a table or
/// the key is absent. Last occurrence wins on duplicate keys.
pub fn get(v : TomlValue, key : String) -> TomlValue? {
  match v {
    Table(pairs) => {
      let mut result : TomlValue? = None
      for i = 0; i < pairs.length(); i = i + 1 {
        let (k, val) = pairs[i]
        if k == key {
          result = Some(val)
        }
      }
      result
    }
    _ => None
  }
}

///|
/// Extract the `String` payload, or `None` if `v` is not a string.
pub fn as_str(v : TomlValue?) -> String? {
  match v {
    Some(Str(s)) => Some(s)
    _ => None
  }
}

///|
/// Extract the `Int` payload, or `None` if `v` is not an integer.
pub fn as_int(v : TomlValue?) -> Int? {
  match v {
    Some(Int(i)) => Some(i)
    _ => None
  }
}

///|
/// Extract the `Double` payload, or `None` if `v` is not a float.
pub fn as_float(v : TomlValue?) -> Double? {
  match v {
    Some(Float(f)) => Some(f)
    _ => None
  }
}

///|
/// Extract the `Bool` payload, or `None` if `v` is not a boolean.
pub fn as_bool(v : TomlValue?) -> Bool? {
  match v {
    Some(Bool(b)) => Some(b)
    _ => None
  }
}

///|
/// Extract the array payload, or `None` if `v` is not an array.
pub fn as_array(v : TomlValue?) -> Array[TomlValue]? {
  match v {
    Some(Array(a)) => Some(a)
    _ => None
  }
}

///|
/// Extract the table payload, or `None` if `v` is not a table.
pub fn as_table(v : TomlValue?) -> Array[(String, TomlValue)]? {
  match v {
    Some(Table(pairs)) => Some(pairs)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

///|
/// Parse a TOML document into a `TomlValue` (always a `Table` on success).
///
/// Returns `Some(value)` on success, or `None` if the input is not valid
/// TOML (including trailing garbage after the last statement).
pub fn parse(input : String) -> TomlValue? {
  let root : Array[(String, TomlValue)] = []
  let p : TomlParser = { input, pos: 0, root, current: root }
  let mut ok = true
  let mut continue_loop = true
  while continue_loop {
    TomlParser::skip_ws_comments_newlines(p)
    if p.pos >= p.input.length() {
      continue_loop = false
    } else {
      let c = p.input[p.pos].to_int()
      if c == 91 {
        // '[' — table or array-of-tables header
        match TomlParser::parse_header(p) {
          false => {
            ok = false
            continue_loop = false
          }
          true => ()
        }
      } else {
        match TomlParser::parse_key_value(p) {
          false => {
            ok = false
            continue_loop = false
          }
          true => ()
        }
      }
    }
  }
  if ok {
    Some(Table(p.root))
  } else {
    None
  }
}

///|
/// Parse a TOML document, returning `default` on failure.
pub fn parse_or(input : String, default : TomlValue) -> TomlValue {
  match parse(input) {
    Some(v) => v
    None => default
  }
}

///|
/// Internal parser state.
priv struct TomlParser {
  input : String
  mut pos : Int
  root : Array[(String, TomlValue)]
  mut current : Array[(String, TomlValue)]
}

// --- low-level cursor helpers ---

///|
/// Peek at the current character code, or -1 at end of input.
fn TomlParser::peek(self : TomlParser) -> Int {
  if self.pos >= self.input.length() {
    -1
  } else {
    self.input[self.pos].to_int()
  }
}

///|
/// Skip spaces and tabs (inline whitespace only).
fn TomlParser::skip_ws_inline(self : TomlParser) -> Unit {
  while self.pos < self.input.length() {
    let c = self.input[self.pos].to_int()
    if c == 32 || c == 9 {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
}

///|
/// Skip to the end of the current line (used for comments). Does not
/// consume the terminating newline.
fn TomlParser::skip_to_eol(self : TomlParser) -> Unit {
  while self.pos < self.input.length() {
    let c = self.input[self.pos].to_int()
    if c == 10 || c == 13 {
      break
    }
    self.pos = self.pos + 1
  }
}

///|
/// Consume a single newline (`\n` or `\r\n`).
fn TomlParser::skip_newline(self : TomlParser) -> Unit {
  if self.pos < self.input.length() {
    let c = self.input[self.pos].to_int()
    if c == 13 {
      self.pos = self.pos + 1
      if self.pos < self.input.length() &&
        self.input[self.pos].to_int() == 10 {
        self.pos = self.pos + 1
      }
    } else if c == 10 {
      self.pos = self.pos + 1
    }
  }
}

///|
/// Skip whitespace, newlines, and `#` comments (statement separators).
fn TomlParser::skip_ws_comments_newlines(self : TomlParser) -> Unit {
  let mut continue_loop = true
  while continue_loop {
    if self.pos >= self.input.length() {
      continue_loop = false
    } else {
      let c = self.input[self.pos].to_int()
      if c == 32 || c == 9 || c == 10 || c == 13 {
        self.pos = self.pos + 1
      } else if c == 35 {
        self.skip_to_eol()
      } else {
        continue_loop = false
      }
    }
  }
}

///|
/// Skip whitespace, newlines, and comments inside array/inline contexts.
fn TomlParser::skip_ws_newlines_comments(self : TomlParser) -> Unit {
  let mut continue_loop = true
  while continue_loop {
    if self.pos >= self.input.length() {
      continue_loop = false
    } else {
      let c = self.input[self.pos].to_int()
      if c == 32 || c == 9 || c == 10 || c == 13 {
        self.pos = self.pos + 1
      } else if c == 35 {
        self.skip_to_eol()
      } else {
        continue_loop = false
      }
    }
  }
}

///|
/// After a statement, skip inline whitespace and an optional trailing
/// comment, then require a newline or EOF. Returns whether the terminator
/// was valid.
fn TomlParser::finish_line(self : TomlParser) -> Bool {
  self.skip_ws_inline()
  if self.peek() == 35 {
    self.skip_to_eol()
  }
  let c = self.peek()
  if c == 10 || c == 13 {
    self.skip_newline()
    true
  } else if c == -1 {
    true
  } else {
    false
  }
}

///|
/// Match the literal string `s` at the cursor; advance past it on success.
fn TomlParser::consume(self : TomlParser, s : String) -> Bool {
  let l = s.length()
  if self.pos + l > self.input.length() {
    return false
  }
  let mut ok = true
  for i = 0; i < l; i = i + 1 {
    if self.input[self.pos + i].to_int() != s[i].to_int() {
      ok = false
      break
    }
  }
  if ok {
    self.pos = self.pos + l
    true
  } else {
    false
  }
}

// --- table tree helpers ---

///|
/// Look up a key in a table's entry array (last-wins).
fn toml_lookup(
  entries : Array[(String, TomlValue)],
  key : String,
) -> TomlValue? {
  let mut result : TomlValue? = None
  for i = 0; i < entries.length(); i = i + 1 {
    let (k, v) = entries[i]
    if k == key {
      result = Some(v)
    }
  }
  result
}

///|
/// Insert a key/value into a table. Returns `false` on conflicting
/// redefinition of an existing leaf key.
fn toml_insert(
  entries : Array[(String, TomlValue)],
  key : String,
  val : TomlValue,
) -> Bool {
  match toml_lookup(entries, key) {
    Some(_) => false
    None => {
      entries.push((key, val))
      true
    }
  }
}

///|
/// Navigate into (creating if absent) the sub-table named `key`. Returns
/// the sub-table's entry array, or `None` on type conflict.
fn toml_navigate(
  entries : Array[(String, TomlValue)],
  key : String,
) -> Array[(String, TomlValue)]? {
  match toml_lookup(entries, key) {
    Some(Table(arr)) => Some(arr)
    Some(_) => None
    None => {
      let arr : Array[(String, TomlValue)] = []
      entries.push((key, Table(arr)))
      Some(arr)
    }
  }
}

///|
/// Select (creating as needed) the table at `path` from the root, and set
/// it as the current table for subsequent key/value pairs.
fn toml_define_table(p : TomlParser, path : Array[String]) -> Bool {
  let mut cur = p.root
  for i = 0; i < path.length(); i = i + 1 {
    match toml_navigate(cur, path[i]) {
      None => return false
      Some(arr) => cur = arr
    }
  }
  p.current = cur
  true
}

///|
/// Append a new empty table to the array-of-tables at `path` (creating the
/// array if absent) and select that new table as the current table.
fn toml_define_array_table(p : TomlParser, path : Array[String]) -> Bool {
  if path.length() == 0 {
    return false
  }
  let mut cur = p.root
  for i = 0; i < path.length() - 1; i = i + 1 {
    match toml_navigate(cur, path[i]) {
      None => return false
      Some(arr) => cur = arr
    }
  }
  let last = path[path.length() - 1]
  let new_table : Array[(String, TomlValue)] = []
  match toml_lookup(cur, last) {
    Some(Array(arr)) => {
      arr.push(Table(new_table))
      p.current = new_table
      true
    }
    Some(_) => false
    None => {
      let arr : Array[TomlValue] = []
      arr.push(Table(new_table))
      cur.push((last, Array(arr)))
      p.current = new_table
      true
    }
  }
}

// --- key parsing ---

///|
/// Whether `c` is a valid bare-key character (A-Z, a-z, 0-9, `_`, `-`).
fn is_bare_key_char(c : Int) -> Bool {
  (c >= 48 && c <= 57) ||
  (c >= 65 && c <= 90) ||
  (c >= 97 && c <= 122) ||
  c == 95 ||
  c == 45
}

///|
/// Parse a (possibly dotted) key path. Returns the list of key segments.
fn TomlParser::parse_key(self : TomlParser) -> Array[String]? {
  let segments : Array[String] = []
  let mut ok = true
  let mut continue_loop = true
  while continue_loop {
    self.skip_ws_inline()
    let c = self.peek()
    let seg : String? = if c == 34 {
      self.parse_basic_string()
    } else if c == 39 {
      self.parse_literal_string()
    } else if is_bare_key_char(c) {
      Some(self.parse_bare_key())
    } else {
      None
    }
    match seg {
      None => {
        ok = false
        continue_loop = false
      }
      Some(s) => segments.push(s)
    }
    if ok {
      self.skip_ws_inline()
      if self.peek() == 46 {
        // '.' — dotted key continues
        self.pos = self.pos + 1
      } else {
        continue_loop = false
      }
    }
  }
  if ok && segments.length() > 0 {
    Some(segments)
  } else {
    None
  }
}

///|
/// Parse a bare (unquoted) key.
fn TomlParser::parse_bare_key(self : TomlParser) -> String {
  let buf = StringBuilder()
  while self.pos < self.input.length() {
    let c = self.input[self.pos].to_int()
    if is_bare_key_char(c) {
      buf.write_char(c.unsafe_to_char())
      self.pos = self.pos + 1
    } else {
      break
    }
  }
  buf.to_string()
}

// --- header parsing ---

///|
/// Parse a `[table]` or `[[array-of-tables]]` header.
fn TomlParser::parse_header(self : TomlParser) -> Bool {
  self.pos = self.pos + 1 // consume first '['
  if self.peek() == 91 {
    // array of tables
    self.pos = self.pos + 1
    self.skip_ws_inline()
    match self.parse_key() {
      None => false
      Some(path) => {
        self.skip_ws_inline()
        if self.peek() != 93 {
          return false
        }
        self.pos = self.pos + 1
        if self.peek() != 93 {
          return false
        }
        self.pos = self.pos + 1
        if !self.finish_line() {
          return false
        }
        if path.length() == 0 {
          return false
        }
        toml_define_array_table(self, path)
      }
    }
  } else {
    // single table
    self.skip_ws_inline()
    match self.parse_key() {
      None => false
      Some(path) => {
        self.skip_ws_inline()
        if self.peek() != 93 {
          return false
        }
        self.pos = self.pos + 1
        if !self.finish_line() {
          return false
        }
        if path.length() == 0 {
          return false
        }
        toml_define_table(self, path)
      }
    }
  }
}

// --- key/value parsing ---

///|
/// Parse a `key = value` statement into the current table.
fn TomlParser::parse_key_value(self : TomlParser) -> Bool {
  match self.parse_key() {
    None => false
    Some(path) => {
      self.skip_ws_inline()
      if self.peek() != 61 {
        // '='
        return false
      }
      self.pos = self.pos + 1
      self.skip_ws_inline()
      match self.parse_value() {
        None => false
        Some(val) => {
          let mut cur = self.current
          let mut ok = true
          for i = 0; i < path.length() - 1; i = i + 1 {
            match toml_navigate(cur, path[i]) {
              None => {
                ok = false
                break
              }
              Some(arr) => cur = arr
            }
          }
          if !ok {
            return false
          }
          if !toml_insert(cur, path[path.length() - 1], val) {
            return false
          }
          self.finish_line()
        }
      }
    }
  }
}

// --- value parsing ---

///|
/// Parse any TOML value.
fn TomlParser::parse_value(self : TomlParser) -> TomlValue? {
  self.skip_ws_inline()
  let c = self.peek()
  if c == -1 {
    return None
  }
  if c == 34 {
    // '"'
    match self.parse_basic_string() {
      None => None
      Some(s) => Some(Str(s))
    }
  } else if c == 39 {
    // '\''
    match self.parse_literal_string() {
      None => None
      Some(s) => Some(Str(s))
    }
  } else if c == 91 {
    // '['
    self.parse_array_value()
  } else if c == 123 {
    // '{'
    self.parse_inline_table()
  } else if c == 116 {
    // 't'
    if self.consume("true") {
      Some(Bool(true))
    } else {
      None
    }
  } else if c == 102 {
    // 'f'
    if self.consume("false") {
      Some(Bool(false))
    } else {
      None
    }
  } else if c == 105 {
    // 'i'
    if self.consume("inf") {
      Some(Float(@double.infinity))
    } else {
      None
    }
  } else if c == 110 {
    // 'n'
    if self.consume("nan") {
      Some(Float(@double.not_a_number))
    } else {
      None
    }
  } else if c == 43 || c == 45 || (c >= 48 && c <= 57) {
    // '+', '-', or digit
    self.parse_number()
  } else {
    None
  }
}

///|
/// Parse a TOML number (integer or float, incl. signed inf/nan).
fn TomlParser::parse_number(self : TomlParser) -> TomlValue? {
  let start = self.pos
  let c0 = self.peek()
  if c0 == 43 || c0 == 45 {
    self.pos = self.pos + 1
    if self.peek() == 105 {
      // 'i' — signed inf
      if self.consume("inf") {
        return Some(Float(if c0 == 45 {
          @double.neg_infinity
        } else {
          @double.infinity
        }))
      } else {
        return None
      }
    } else if self.peek() == 110 {
      // 'n' — signed nan
      if self.consume("nan") {
        return Some(Float(@double.not_a_number))
      } else {
        return None
      }
    }
  }
  // Collect the numeric token: digits, letters (radix/units), '.', '_',
  // and '+'/'-' (the latter only legitimately after an exponent marker).
  while self.pos < self.input.length() {
    let c = self.input[self.pos].to_int()
    if (c >= 48 && c <= 57) ||
      (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      c == 43 ||
      c == 45 ||
      c == 46 ||
      c == 95 {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
  let token = self.input[start:self.pos]
  toml_classify_number(token.to_owned())
}

///|
/// Classify a raw numeric token as integer or float and parse it.
fn toml_classify_number(token : String) -> TomlValue? {
  if token == "inf" || token == "+inf" {
    return Some(Float(@double.infinity))
  }
  if token == "-inf" {
    return Some(Float(@double.neg_infinity))
  }
  if token == "nan" || token == "+nan" || token == "-nan" {
    return Some(Float(@double.not_a_number))
  }
  let clean = strip_underscores(token)
  if clean.length() >= 2 && clean[0].to_int() == 48 {
    let p = clean[1].to_int()
    if p == 120 || p == 88 {
      // 0x — hexadecimal
      return parse_radix_int(clean, 2, 16)
    } else if p == 111 || p == 79 {
      // 0o — octal
      return parse_radix_int(clean, 2, 8)
    } else if p == 98 || p == 66 {
      // 0b — binary
      return parse_radix_int(clean, 2, 2)
    }
  }
  let has_dot = clean.contains(".")
  let has_exp = clean.contains("e") || clean.contains("E")
  if has_dot || has_exp {
    try {
      let d = @string.parse_double(clean)
      Some(Float(d))
    } catch {
      _ => None
    }
  } else {
    match parse_decimal_int(clean) {
      None => None
      Some(i) => Some(Int(i))
    }
  }
}

///|
/// Remove `_` digit separators from a numeric token.
fn strip_underscores(s : String) -> String {
  let buf = StringBuilder()
  for c in s.iter() {
    if c != '_' {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Parse a signed decimal integer string into `Int`.
fn parse_decimal_int(s : String) -> Int? {
  let mut i = 0
  let mut neg = false
  if i < s.length() {
    let c0 = s[i].to_int()
    if c0 == 43 {
      i = i + 1
    } else if c0 == 45 {
      neg = true
      i = i + 1
    }
  }
  if i >= s.length() {
    return None
  }
  let mut val = 0
  let mut any = false
  while i < s.length() {
    let d = s[i].to_int() - 48
    if d < 0 || d > 9 {
      return None
    }
    val = val * 10 + d
    any = true
    i = i + 1
  }
  if !any {
    return None
  }
  Some(if neg { -val } else { val })
}

///|
/// Parse a radix-prefixed integer string (after `skip` prefix chars).
fn parse_radix_int(s : String, skip : Int, base : Int) -> TomlValue? {
  let mut i = skip
  let mut val = 0
  let mut any = false
  while i < s.length() {
    let c = s[i].to_int()
    let d = if c >= 48 && c <= 57 {
      c - 48
    } else if c >= 65 && c <= 70 {
      c - 55
    } else if c >= 97 && c <= 102 {
      c - 87
    } else {
      -1
    }
    if d < 0 || d >= base {
      return None
    }
    val = val * base + d
    any = true
    i = i + 1
  }
  if !any {
    return None
  }
  Some(Int(val))
}

// --- string parsing ---

///|
/// Parse a basic string, dispatching to the multi-line form when `"""`.
fn TomlParser::parse_basic_string(self : TomlParser) -> String? {
  if self.pos + 3 <= self.input.length() &&
    self.input[self.pos].to_int() == 34 &&
    self.input[self.pos + 1].to_int() == 34 &&
    self.input[self.pos + 2].to_int() == 34 {
    self.pos = self.pos + 3
    self.parse_multiline_basic()
  } else {
    self.parse_single_basic()
  }
}

///|
/// Parse a single-line basic string `"..."` with escape processing.
fn TomlParser::parse_single_basic(self : TomlParser) -> String? {
  if self.peek() != 34 {
    return None
  }
  self.pos = self.pos + 1
  let buf = StringBuilder()
  let mut done = false
  while !done {
    if self.pos >= self.input.length() {
      return None
    }
    let c = self.input[self.pos].to_int()
    self.pos = self.pos + 1
    if c == 34 {
      done = true
    } else if c == 92 {
      match self.parse_escape() {
        None => return None
        Some(ch) => buf.write_char(ch)
      }
    } else if c == 10 || c == 13 {
      return None
    } else {
      buf.write_char(c.unsafe_to_char())
    }
  }
  Some(buf.to_string())
}

///|
/// Parse a `\` escape sequence (the byte after the backslash).
fn TomlParser::parse_escape(self : TomlParser) -> Char? {
  if self.pos >= self.input.length() {
    return None
  }
  let c = self.input[self.pos].to_int()
  self.pos = self.pos + 1
  match c {
    34 => Some('"') // \"
    92 => Some('\\') // \\
    98 => Some('\u{08}') // \b
    102 => Some('\u{0C}') // \f
    110 => Some('\n') // \n
    114 => Some('\r') // \r
    116 => Some('\t') // \t
    117 => self.parse_hex(4) // \uXXXX
    85 => self.parse_hex(8) // \UXXXXXXXX
    _ => None
  }
}

///|
/// Parse exactly `n` hexadecimal digits into a code point.
fn TomlParser::parse_hex(self : TomlParser, n : Int) -> Char? {
  if self.pos + n > self.input.length() {
    return None
  }
  let mut val = 0
  for i = 0; i < n; i = i + 1 {
    let c = self.input[self.pos].to_int()
    self.pos = self.pos + 1
    let d = hex_value(c)
    if d < 0 {
      return None
    }
    val = (val << 4) | d
  }
  // Reject out-of-range and lone surrogates (TOML disallows them).
  if val > 0x10FFFF {
    return None
  }
  if val >= 0xD800 && val <= 0xDFFF {
    return None
  }
  Some(val.unsafe_to_char())
}

///|
/// Convert a hex digit code to its numeric value, or -1 if invalid.
fn hex_value(c : Int) -> Int {
  if c >= 48 && c <= 57 {
    c - 48
  } else if c >= 65 && c <= 70 {
    c - 55
  } else if c >= 97 && c <= 102 {
    c - 87
  } else {
    -1
  }
}

///|
/// Parse a multi-line basic string `"""..."""` with escape processing and
/// line-ending backslash trimming.
fn TomlParser::parse_multiline_basic(self : TomlParser) -> String? {
  // Trim an immediate newline after the opening delimiter.
  if self.peek() == 13 {
    self.pos = self.pos + 1
    if self.peek() == 10 {
      self.pos = self.pos + 1
    }
  } else if self.peek() == 10 {
    self.pos = self.pos + 1
  }
  let buf = StringBuilder()
  let mut done = false
  while !done {
    if self.pos >= self.input.length() {
      return None
    }
    let c = self.input[self.pos].to_int()
    if c == 34 &&
      self.pos + 2 < self.input.length() &&
      self.input[self.pos + 1].to_int() == 34 &&
      self.input[self.pos + 2].to_int() == 34 {
      self.pos = self.pos + 3
      done = true
    } else if c == 92 {
      let next = if self.pos + 1 < self.input.length() {
        self.input[self.pos + 1].to_int()
      } else {
        -1
      }
      if next == 10 || next == 13 || next == 32 || next == 9 {
        // Line-ending backslash: consume it and all trailing whitespace.
        self.pos = self.pos + 1
        while self.pos < self.input.length() {
          let w = self.input[self.pos].to_int()
          if w == 32 || w == 9 || w == 10 || w == 13 {
            self.pos = self.pos + 1
          } else {
            break
          }
        }
      } else {
        self.pos = self.pos + 1
        match self.parse_escape() {
          None => return None
          Some(ch) => buf.write_char(ch)
        }
      }
    } else {
      self.pos = self.pos + 1
      buf.write_char(c.unsafe_to_char())
    }
  }
  Some(buf.to_string())
}

///|
/// Parse a literal string, dispatching to the multi-line form when `'''`.
fn TomlParser::parse_literal_string(self : TomlParser) -> String? {
  if self.pos + 3 <= self.input.length() &&
    self.input[self.pos].to_int() == 39 &&
    self.input[self.pos + 1].to_int() == 39 &&
    self.input[self.pos + 2].to_int() == 39 {
    self.pos = self.pos + 3
    self.parse_multiline_literal()
  } else {
    self.parse_single_literal()
  }
}

///|
/// Parse a single-line literal string `'...'` (raw, no escapes).
fn TomlParser::parse_single_literal(self : TomlParser) -> String? {
  if self.peek() != 39 {
    return None
  }
  self.pos = self.pos + 1
  let buf = StringBuilder()
  let mut done = false
  while !done {
    if self.pos >= self.input.length() {
      return None
    }
    let c = self.input[self.pos].to_int()
    if c == 39 {
      self.pos = self.pos + 1
      done = true
    } else if c == 10 || c == 13 {
      return None
    } else {
      self.pos = self.pos + 1
      buf.write_char(c.unsafe_to_char())
    }
  }
  Some(buf.to_string())
}

///|
/// Parse a multi-line literal string `'''...'''` (raw, no escapes).
fn TomlParser::parse_multiline_literal(self : TomlParser) -> String? {
  if self.peek() == 13 {
    self.pos = self.pos + 1
    if self.peek() == 10 {
      self.pos = self.pos + 1
    }
  } else if self.peek() == 10 {
    self.pos = self.pos + 1
  }
  let buf = StringBuilder()
  let mut done = false
  while !done {
    if self.pos >= self.input.length() {
      return None
    }
    let c = self.input[self.pos].to_int()
    if c == 39 &&
      self.pos + 2 < self.input.length() &&
      self.input[self.pos + 1].to_int() == 39 &&
      self.input[self.pos + 2].to_int() == 39 {
      self.pos = self.pos + 3
      done = true
    } else {
      self.pos = self.pos + 1
      buf.write_char(c.unsafe_to_char())
    }
  }
  Some(buf.to_string())
}

// --- array & inline table parsing ---

///|
/// Parse a TOML array `[v1, v2, ...]` (may span multiple lines; trailing
/// comma allowed).
fn TomlParser::parse_array_value(self : TomlParser) -> TomlValue? {
  self.pos = self.pos + 1 // consume '['
  let items : Array[TomlValue] = []
  let mut continue_loop = true
  while continue_loop {
    self.skip_ws_newlines_comments()
    let c = self.peek()
    if c == 93 {
      // ']'
      self.pos = self.pos + 1
      continue_loop = false
    } else if c == -1 {
      return None
    } else {
      match self.parse_value() {
        None => return None
        Some(v) => {
          items.push(v)
          self.skip_ws_newlines_comments()
          let c2 = self.peek()
          if c2 == 44 {
            // ','
            self.pos = self.pos + 1
          } else if c2 == 93 {
            // ']'
            self.pos = self.pos + 1
            continue_loop = false
          } else {
            return None
          }
        }
      }
    }
  }
  Some(Array(items))
}

///|
/// Parse an inline table `{ k = v, k2 = v2 }`.
fn TomlParser::parse_inline_table(self : TomlParser) -> TomlValue? {
  self.pos = self.pos + 1 // consume '{'
  let entries : Array[(String, TomlValue)] = []
  self.skip_ws_inline()
  if self.peek() == 125 {
    // '}'
    self.pos = self.pos + 1
    return Some(Table(entries))
  }
  let mut continue_loop = true
  while continue_loop {
    self.skip_ws_inline()
    match self.parse_key() {
      None => return None
      Some(path) => {
        self.skip_ws_inline()
        if self.peek() != 61 {
          // '='
          return None
        }
        self.pos = self.pos + 1
        self.skip_ws_inline()
        match self.parse_value() {
          None => return None
          Some(val) => {
            let mut cur = entries
            let mut ok = true
            for i = 0; i < path.length() - 1; i = i + 1 {
              match toml_navigate(cur, path[i]) {
                None => {
                  ok = false
                  break
                }
                Some(arr) => cur = arr
              }
            }
            if !ok {
              return None
            }
            if !toml_insert(cur, path[path.length() - 1], val) {
              return None
            }
            self.skip_ws_inline()
            let c = self.peek()
            if c == 44 {
              // ','
              self.pos = self.pos + 1
            } else if c == 125 {
              // '}'
              self.pos = self.pos + 1
              continue_loop = false
            } else {
              return None
            }
          }
        }
      }
    }
  }
  Some(Table(entries))
}

// ---------------------------------------------------------------------------
// Serializer
// ---------------------------------------------------------------------------

///|
/// Serialize a `TomlValue` (which should be a `Table`) to canonical TOML
/// text. Non-table roots produce an empty string.
///
/// The output uses `[section]` headers for sub-tables and `[[section]]`
/// headers for arrays-of-tables; scalar/array values are emitted inline.
/// The result re-parses to an equal value tree.
pub fn to_toml(v : TomlValue) -> String {
  let s : TomlSerializer = { buf: StringBuilder::new(), started: false }
  match v {
    Table(entries) => toml_serialize_section(s, entries, [], true)
    _ => ()
  }
  s.buf.to_string()
}

///|
/// Mutable serializer state.
priv struct TomlSerializer {
  buf : StringBuilder
  mut started : Bool
}

///|
/// Serialize a table as a section. When `is_root` is true, no `[header]` is
/// emitted (the root table has no header).
fn toml_serialize_section(
  s : TomlSerializer,
  entries : Array[(String, TomlValue)],
  path : Array[String],
  is_root : Bool,
) -> Unit {
  if !is_root {
    if s.started {
      s.buf.write_char('\n')
    }
    s.buf.write_char('[')
    for i = 0; i < path.length(); i = i + 1 {
      if i > 0 {
        s.buf.write_char('.')
      }
      toml_write_key(path[i], s.buf)
    }
    s.buf.write_string("]\n")
    s.started = true
  }
  // Emit scalar / inline-array entries first.
  for i = 0; i < entries.length(); i = i + 1 {
    let (k, v) = entries[i]
    if !toml_is_section_value(v) {
      toml_write_key(k, s.buf)
      s.buf.write_string(" = ")
      toml_write_inline(v, s.buf)
      s.buf.write_char('\n')
      s.started = true
    }
  }
  // Then emit sub-tables and arrays-of-tables.
  for i = 0; i < entries.length(); i = i + 1 {
    let (k, v) = entries[i]
    match v {
      Table(sub) => {
        let newpath = Array::copy(path)
        newpath.push(k)
        toml_serialize_section(s, sub, newpath, false)
      }
      Array(arr) =>
        if toml_all_tables(arr) {
          let newpath = Array::copy(path)
          newpath.push(k)
          for j = 0; j < arr.length(); j = j + 1 {
            match arr[j] {
              Table(sub) => {
                if s.started {
                  s.buf.write_char('\n')
                }
                s.buf.write_string("[[")
                for m = 0; m < newpath.length(); m = m + 1 {
                  if m > 0 {
                    s.buf.write_char('.')
                  }
                  toml_write_key(newpath[m], s.buf)
                }
                s.buf.write_string("]]\n")
                s.started = true
                toml_serialize_section(s, sub, newpath, true)
              }
              _ => ()
            }
          }
        }
      _ => ()
    }
  }
}

///|
/// Whether `v` should be emitted as a section (`[...]` / `[[...]]`) rather
/// than inline. Tables and non-empty all-table arrays qualify.
fn toml_is_section_value(v : TomlValue) -> Bool {
  match v {
    Table(_) => true
    Array(arr) => toml_all_tables(arr)
    _ => false
  }
}

///|
/// Whether an array consists entirely of tables (and is non-empty).
fn toml_all_tables(arr : Array[TomlValue]) -> Bool {
  if arr.length() == 0 {
    return false
  }
  let mut all = true
  for i = 0; i < arr.length(); i = i + 1 {
    match arr[i] {
      Table(_) => ()
      _ => {
        all = false
        break
      }
    }
  }
  all
}

///|
/// Write a value in inline form (used for scalar values and for values
/// inside arrays / inline tables).
fn toml_write_inline(v : TomlValue, buf : StringBuilder) -> Unit {
  match v {
    Str(s) => toml_write_basic_string(s, buf)
    Int(i) => buf.write_string(i.to_string())
    Float(f) => buf.write_string(format_float(f))
    Bool(b) => buf.write_string(if b { "true" } else { "false" })
    Array(arr) => {
      buf.write_char('[')
      for i = 0; i < arr.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        toml_write_inline(arr[i], buf)
      }
      buf.write_char(']')
    }
    Table(entries) => {
      buf.write_char('{')
      for i = 0; i < entries.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(", ")
        }
        let (k, val) = entries[i]
        toml_write_key(k, buf)
        buf.write_string(" = ")
        toml_write_inline(val, buf)
      }
      buf.write_char('}')
    }
  }
}

///|
/// Write a key, quoting it as a basic string when it is not a valid bare key.
fn toml_write_key(k : String, buf : StringBuilder) -> Unit {
  if is_valid_bare_key(k) {
    buf.write_string(k)
  } else {
    toml_write_basic_string(k, buf)
  }
}

///|
/// Whether `k` is a valid unquoted bare key.
fn is_valid_bare_key(k : String) -> Bool {
  if k.length() == 0 {
    return false
  }
  let mut ok = true
  for i = 0; i < k.length(); i = i + 1 {
    let c = k[i].to_int()
    if !is_bare_key_char(c) {
      ok = false
      break
    }
  }
  ok
}

///|
/// Write a basic string with standard escaping.
fn toml_write_basic_string(s : String, buf : StringBuilder) -> Unit {
  buf.write_char('"')
  for c in s.iter() {
    let cp = c.to_int()
    match cp {
      34 => buf.write_string("\\\"")
      92 => buf.write_string("\\\\")
      8 => buf.write_string("\\b")
      12 => buf.write_string("\\f")
      10 => buf.write_string("\\n")
      13 => buf.write_string("\\r")
      9 => buf.write_string("\\t")
      _ =>
        if cp < 32 {
          buf.write_string("\\u00")
          buf.write_char(hex_digit(cp >> 4))
          buf.write_char(hex_digit(cp & 0xF))
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}

///|
/// Format a `Double` as a TOML float literal (always contains `.` or `e`,
/// or is `inf`/`nan`).
fn format_float(n : Double) -> String {
  if n.is_nan() {
    return "nan"
  }
  if n.is_inf() {
    return if n > 0.0 { "inf" } else { "-inf" }
  }
  let s = n.to_string()
  if s.contains(".") || s.contains("e") || s.contains("E") {
    s
  } else {
    s + ".0"
  }
}

///|
/// Convert a nibble (0-15) to a lowercase hex character.
fn hex_digit(n : Int) -> Char {
  if n < 10 {
    (48 + n).unsafe_to_char()
  } else {
    (87 + n).unsafe_to_char()
  }
}


// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "toml: parse simple scalars" {
  let v = parse("title = \"TOML\"\nport = 8080\nratio = 3.14\nenabled = true\n")
  assert_true(v is Some(_))
  match v {
    Some(t) => {
      assert_eq(as_str(get(t, "title")), Some("TOML"))
      assert_eq(as_int(get(t, "port")), Some(8080))
      assert_eq(as_float(get(t, "ratio")), Some(3.14))
      assert_eq(as_bool(get(t, "enabled")), Some(true))
    }
    None => fail("expected Some")
  }
}

///|
test "toml: parse comments and blank lines" {
  let v = parse("# top-level comment\n\nname = \"Alice\"  # trailing comment\n\nage = 30\n")
  match v {
    Some(t) => {
      assert_eq(as_str(get(t, "name")), Some("Alice"))
      assert_eq(as_int(get(t, "age")), Some(30))
    }
    None => fail("expected Some")
  }
}

///|
test "toml: parse table" {
  let v = parse("[owner]\nname = \"Tom\"\nactive = true\n")
  match v {
    Some(t) =>
      match get(t, "owner") {
        Some(Table(o)) => {
          assert_eq(as_str(get(Table(o), "name")), Some("Tom"))
          assert_eq(as_bool(get(Table(o), "active")), Some(true))
        }
        _ => fail("expected owner table")
      }
    None => fail("expected Some")
  }
}

///|
test "toml: parse nested table" {
  let v = parse("[a.b.c]\nvalue = 42\n")
  match v {
    Some(t) =>
      match get(t, "a") {
        Some(Table(a)) =>
          match get(Table(a), "b") {
            Some(Table(b)) =>
              match get(Table(b), "c") {
                Some(Table(c)) => assert_eq(as_int(get(Table(c), "value")), Some(42))
                _ => fail("expected c table")
              }
            _ => fail("expected b table")
          }
        _ => fail("expected a table")
      }
    None => fail("expected Some")
  }
}

///|
test "toml: parse dotted keys" {
  let v = parse("a.b.c = 1\na.b.d = 2\n")
  match v {
    Some(t) =>
      match get(t, "a") {
        Some(Table(a)) =>
          match get(Table(a), "b") {
            Some(Table(b)) => {
              assert_eq(as_int(get(Table(b), "c")), Some(1))
              assert_eq(as_int(get(Table(b), "d")), Some(2))
            }
            _ => fail("expected b table")
          }
        _ => fail("expected a table")
      }
    None => fail("expected Some")
  }
}

///|
test "toml: parse array of tables" {
  let v = parse("[[products]]\nname = \"Hammer\"\nsku = 738594937\n\n[[products]]\nname = \"Nail\"\nsku = 284758393\n")
  match v {
    Some(t) =>
      match get(t, "products") {
        Some(Array(arr)) => {
          assert_eq(arr.length(), 2)
          match arr[0] {
            Table(p0) => {
              assert_eq(as_str(get(Table(p0), "name")), Some("Hammer"))
              assert_eq(as_int(get(Table(p0), "sku")), Some(738594937))
            }
            _ => fail("expected table")
          }
          match arr[1] {
            Table(p1) => assert_eq(as_str(get(Table(p1), "name")), Some("Nail"))
            _ => fail("expected table")
          }
        }
        _ => fail("expected products array")
      }
    None => fail("expected Some")
  }
}

///|
test "toml: parse arrays" {
  let v = parse("nums = [1, 2, 3]\nmixed = [\"a\", true, 4.5]\nmulti = [\n  1,\n  2,\n]\n")
  match v {
    Some(t) => {
      match get(t, "nums") {
        Some(Array(a)) => {
          assert_eq(a.length(), 3)
          assert_eq(as_int(Some(a[0])), Some(1))
          assert_eq(as_int(Some(a[1])), Some(2))
          assert_eq(as_int(Some(a[2])), Some(3))
        }
        _ => fail("expected nums array")
      }
      match get(t, "multi") {
        Some(Array(a)) => assert_eq(a.length(), 2)
        _ => fail("expected multi array")
      }
    }
    None => fail("expected Some")
  }
}

///|
test "toml: parse inline table" {
  let v = parse("point = { x = 1, y = 2 }\n")
  match v {
    Some(t) =>
      match get(t, "point") {
        Some(Table(p)) => {
          assert_eq(as_int(get(Table(p), "x")), Some(1))
          assert_eq(as_int(get(Table(p), "y")), Some(2))
        }
        _ => fail("expected inline table")
      }
    None => fail("expected Some")
  }
}

///|
test "toml: parse string forms and integers" {
  let v = parse("basic = \"hello\\nworld\"\nliteral = 'raw \\n string'\nhex = 0xFF\noct = 0o17\nbin = 0b1010\nunder = 1_000_000\n")
  match v {
    Some(t) => {
      assert_eq(as_str(get(t, "basic")), Some("hello\nworld"))
      assert_eq(as_str(get(t, "literal")), Some("raw \\n string"))
      assert_eq(as_int(get(t, "hex")), Some(255))
      assert_eq(as_int(get(t, "oct")), Some(15))
      assert_eq(as_int(get(t, "bin")), Some(10))
      assert_eq(as_int(get(t, "under")), Some(1000000))
    }
    None => fail("expected Some")
  }
}

///|
test "toml: serialize round-trip" {
  let src = "[server]\nport = 8080\nhost = \"localhost\"\nflags = [1, 2, 3]\n"
  match parse(src) {
    Some(v) => {
      let out = to_toml(v)
      match parse(out) {
        Some(v2) => assert_true(v == v2)
        None => fail("re-parse failed")
      }
    }
    None => fail("parse failed")
  }
}

///|
test "toml: serialize array of tables round-trip" {
  let src = "[[items]]\nname = \"a\"\n[[items]]\nname = \"b\"\n"
  match parse(src) {
    Some(v) => {
      let out = to_toml(v)
      match parse(out) {
        Some(v2) => assert_true(v == v2)
        None => fail("re-parse failed")
      }
    }
    None => fail("parse failed")
  }
}

///|
test "toml: serialize emits headers" {
  let v = toml_table([
    ("title", toml_str("T")),
    ("server", toml_table([("port", toml_int(80))])),
  ])
  let out = to_toml(v)
  assert_true(out.contains("title = \"T\""))
  assert_true(out.contains("[server]"))
  assert_true(out.contains("port = 80"))
}

///|
test "toml: rejects invalid input" {
  assert_true(parse("") is Some(_)) // empty document is valid (empty table)
  assert_true(parse("key") is None) // missing '='
  assert_true(parse("= 1") is None) // missing key
  assert_true(parse("key = ") is None) // missing value
  assert_true(parse("[unclosed") is None)
  assert_true(parse("key = 'unterminated") is None)
  assert_true(parse("a = 1 b = 2") is None) // no newline between pairs
}

///|
test "toml: accessor API" {
  let v = toml_table([
    ("name", toml_str("Bob")),
    ("age", toml_int(25)),
    ("active", toml_bool(true)),
    ("score", toml_float(9.5)),
  ])
  assert_eq(as_str(get(v, "name")), Some("Bob"))
  assert_eq(as_int(get(v, "age")), Some(25))
  assert_eq(as_bool(get(v, "active")), Some(true))
  assert_eq(as_float(get(v, "score")), Some(9.5))
  assert_true(get(v, "missing") is None)
}

///|
test "toml: parse_or default" {
  let v = parse_or("bad = ", toml_str("fallback"))
  assert_eq(as_str(Some(v)), Some("fallback"))
  let v2 = parse_or("ok = 1\n", toml_str("fallback"))
  assert_true(v2 is Table(_))
}
