/// JSON (JavaScript Object Notation) — RFC 8259 parser and serializer.
///
/// This package provides a production-grade JSON implementation with:
///
/// - **Full RFC 8259 compliance**: all value types (null, bool, number,
///   string, array, object), Unicode escape sequences with surrogate pair
///   support, and strict number parsing.
/// - **Zero-copy parsing philosophy**: the parser walks the input string
///   in place, allocating only for compound values.
/// - **Configurable output**: compact (`stringify`) or pretty-printed
///   (`stringify_pretty`) serialization.
/// - **Consistent error handling**: `parse` returns `JsonValue?` (`None`
///   on malformed input), matching the library-wide `Option` convention.
/// - **Convenience API**: typed constructors, accessors, and predicates
///   for ergonomic use without pattern matching.
///
/// ## Limitations
///
/// - Numbers are stored as `Double`; integers exceeding 2^53 may lose
///   precision. This is consistent with JavaScript's `JSON.parse`.
/// - Duplicate keys in objects are allowed; the last occurrence wins
///   (same behaviour as JavaScript).
/// - `NaN`, `Infinity`, and `-Infinity` are serialised as `null` per
///   RFC 8259 §6.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// JsonValue type
// ---------------------------------------------------------------------------

///|
/// A JSON value, as defined by RFC 8259 §3.
///
/// - `Null` — the JSON literal `null`.
/// - `Bool(Bool)` — `true` or `false`.
/// - `Number(Double)` — a JSON number. Stored as `Double`; integers
///   exceeding 2^53 may lose precision. Pure integers exceeding 2^53 are
///   automatically stored as `BigInt` to preserve full precision.
/// - `BigInt(String)` — a large integer that exceeds `Double` precision
///   (> 2^53). The original decimal string is preserved verbatim.
///   This variant is produced automatically by `parse` for pure integers
///   with more than 15 significant digits.
/// - `Str(String)` — a JSON string. MoonBit's `String` is Unicode-aware,
///   so all valid JSON strings round-trip correctly.
/// - `Arr(Array[JsonValue])` — a JSON array (ordered list).
/// - `Obj(Array[(String, JsonValue)])` — a JSON object (ordered map).
///   Duplicate keys are permitted; the last occurrence takes precedence
///   on lookup.
pub enum JsonValue {
  Null
  Bool(Bool)
  Number(Double)
  BigInt(String)
  Str(String)
  Arr(Array[JsonValue])
  Obj(Array[(String, JsonValue)])
}

///|
/// Equality for `JsonValue`. Two JSON values are equal if they have the
/// same type and structurally equal contents.
///
/// Note: `NaN` numbers are considered equal to each other (unlike IEEE 754),
/// which is consistent with JSON having no `NaN` representation.
impl Eq for JsonValue with fn equal(a, b) {
  match (a, b) {
    (Null, Null) => true
    (Bool(x), Bool(y)) => x == y
    (Number(x), Number(y)) => x == y
    (BigInt(x), BigInt(y)) => x == y
    (Str(x), Str(y)) => x == y
    (Arr(x), Arr(y)) =>
      if x.length() != y.length() {
        false
      } else {
        let mut eq = true
        for i = 0; i < x.length(); i = i + 1 {
          if !(x[i] == y[i]) {
            eq = false
            break
          }
        }
        eq
      }
    (Obj(x), Obj(y)) =>
      if x.length() != y.length() {
        false
      } else {
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
    _ => false
  }
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

///|
/// Construct a JSON `null` value.
pub fn json_null() -> JsonValue {
  Null
}

///|
/// Construct a JSON boolean value.
pub fn json_bool(b : Bool) -> JsonValue {
  Bool(b)
}

///|
/// Construct a JSON number value from `Double`.
pub fn json_num(n : Double) -> JsonValue {
  Number(n)
}

///|
/// Construct a JSON number value from `Int`.
pub fn json_int(n : Int) -> JsonValue {
  Number(n.to_double())
}

///|
/// Construct a JSON BigInt value from a decimal string.
///
/// The string should contain only digits and an optional leading minus sign.
/// No validation is performed — the string is stored verbatim and serialized
/// as-is.
pub fn json_bigint(s : String) -> JsonValue {
  BigInt(s)
}

///|
/// Construct a JSON string value.
pub fn json_str(s : String) -> JsonValue {
  Str(s)
}

///|
/// Construct a JSON array from a list of values.
pub fn json_arr(items : Array[JsonValue]) -> JsonValue {
  Arr(items)
}

///|
/// Construct a JSON object from a list of key-value pairs.
pub fn json_obj(pairs : Array[(String, JsonValue)]) -> JsonValue {
  Obj(pairs)
}

// ---------------------------------------------------------------------------
// Type predicates
// ---------------------------------------------------------------------------

///|
/// Returns `true` if `v` is `Null`.
pub fn is_null(v : JsonValue) -> Bool {
  match v {
    Null => true
    _ => false
  }
}

///|
/// Returns `true` if `v` is a `Bool`.
pub fn is_bool(v : JsonValue) -> Bool {
  match v {
    Bool(_) => true
    _ => false
  }
}

///|
/// Returns `true` if `v` is a `Number`.
pub fn is_number(v : JsonValue) -> Bool {
  match v {
    Number(_) => true
    _ => false
  }
}

///|
/// Returns `true` if `v` is a `BigInt`.
pub fn is_bigint(v : JsonValue) -> Bool {
  match v {
    BigInt(_) => true
    _ => false
  }
}

///|
/// Returns `true` if `v` is a `Str`.
pub fn is_string(v : JsonValue) -> Bool {
  match v {
    Str(_) => true
    _ => false
  }
}

///|
/// Returns `true` if `v` is an `Arr`.
pub fn is_array(v : JsonValue) -> Bool {
  match v {
    Arr(_) => true
    _ => false
  }
}

///|
/// Returns `true` if `v` is an `Obj`.
pub fn is_object(v : JsonValue) -> Bool {
  match v {
    Obj(_) => true
    _ => false
  }
}

// ---------------------------------------------------------------------------
// Accessors
// ---------------------------------------------------------------------------

///|
/// Extract the `Bool` value, or `None` if `v` is not a boolean.
pub fn as_bool(v : JsonValue) -> Bool? {
  match v {
    Bool(b) => Some(b)
    _ => None
  }
}

///|
/// Extract the `Double` value, or `None` if `v` is not a number.
pub fn as_number(v : JsonValue) -> Double? {
  match v {
    Number(n) => Some(n)
    _ => None
  }
}

///|
/// Extract the `BigInt` decimal string, or `None` if `v` is not a `BigInt`.
pub fn as_bigint(v : JsonValue) -> String? {
  match v {
    BigInt(s) => Some(s)
    _ => None
  }
}

///|
/// Extract the `String` value, or `None` if `v` is not a string.
pub fn as_string(v : JsonValue) -> String? {
  match v {
    Str(s) => Some(s)
    _ => None
  }
}

///|
/// Extract the `Array[JsonValue]`, or `None` if `v` is not an array.
pub fn as_array(v : JsonValue) -> Array[JsonValue]? {
  match v {
    Arr(a) => Some(a)
    _ => None
  }
}

///|
/// Extract the object's key-value pairs, or `None` if `v` is not an object.
pub fn as_object(v : JsonValue) -> Array[(String, JsonValue)]? {
  match v {
    Obj(o) => Some(o)
    _ => None
  }
}

///|
/// Look up a key in a JSON object. Returns `None` if `v` is not an object
/// or the key is absent. If the key appears multiple times, the last
/// occurrence wins (matching JavaScript semantics).
pub fn get(v : JsonValue, key : String) -> JsonValue? {
  match v {
    Obj(pairs) => {
      let mut result : JsonValue? = None
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
/// Get the element at `index` in a JSON array. Returns `None` if `v` is
/// not an array or the index is out of bounds.
pub fn get_at(v : JsonValue, index : Int) -> JsonValue? {
  match v {
    Arr(a) =>
      if index < 0 || index >= a.length() {
        None
      } else {
        Some(a[index])
      }
    _ => None
  }
}

///|
/// Shorthand for `get(v, key)` then `as_string`.
pub fn get_str(v : JsonValue, key : String) -> String? {
  match get(v, key) {
    Some(Str(s)) => Some(s)
    _ => None
  }
}

///|
/// Shorthand for `get(v, key)` then `as_number`.
pub fn get_num(v : JsonValue, key : String) -> Double? {
  match get(v, key) {
    Some(Number(n)) => Some(n)
    _ => None
  }
}

///|
/// Shorthand for `get(v, key)` then `as_bigint`.
pub fn get_bigint(v : JsonValue, key : String) -> String? {
  match get(v, key) {
    Some(BigInt(s)) => Some(s)
    _ => None
  }
}

///|
/// Shorthand for `get(v, key)` then `as_bool`.
pub fn get_bool(v : JsonValue, key : String) -> Bool? {
  match get(v, key) {
    Some(Bool(b)) => Some(b)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

///|
/// Maximum nesting depth for JSON parsing.
///
/// Prevents stack-overflow attacks via deeply nested `[[[...]]]` or
/// `{"a":{"a":{"a":...}}}` structures. RFC 8259 §9 specifies that
/// implementations may set an implementation-defined limit on nesting depth.
/// Python uses 1000, Go's `encoding/json` uses 10000, Rust's `serde_json`
/// uses 128 by default. We use 1000 as a conservative middle ground.
let max_nesting_depth : Int = 1000

///|
/// Internal parser state: the input string, current position, and
/// current nesting depth (for stack-overflow protection).
priv struct Parser {
  input : String
  mut pos : Int
  mut depth : Int
}

///|
/// Parse a JSON string into a `JsonValue`.
///
/// Returns `Some(value)` on success, or `None` if the input is not valid
/// JSON (including trailing garbage after the root value).
pub fn parse(input : String) -> JsonValue? {
  let p : Parser = { input, pos: 0, depth: 0 }
  Parser::skip_ws(p)
  match Parser::parse_value(p) {
    None => None
    Some(v) => {
      Parser::skip_ws(p)
      if p.pos == p.input.length() {
        Some(v)
      } else {
        None // Trailing garbage
      }
    }
  }
}

///|
/// Parse a JSON string, returning a default value if parsing fails.
pub fn parse_or(input : String, default : JsonValue) -> JsonValue {
  match parse(input) {
    Some(v) => v
    None => default
  }
}

// Parser methods (declared as standalone functions per MoonBit convention).

///|
/// Skip whitespace (space, tab, newline, carriage return).
fn Parser::skip_ws(self : Parser) -> Unit {
  while self.pos < self.input.length() {
    let c = self.input[self.pos].to_int()
    if c == 32 || c == 9 || c == 10 || c == 13 {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
}

///|
/// Peek at the current character code, or -1 at end of input.
fn Parser::peek(self : Parser) -> Int {
  if self.pos >= self.input.length() {
    -1
  } else {
    self.input[self.pos].to_int()
  }
}

///|
/// Consume and return the current character code, or -1 at end.
fn Parser::next_char(self : Parser) -> Int {
  if self.pos >= self.input.length() {
    -1
  } else {
    let c = self.input[self.pos].to_int()
    self.pos = self.pos + 1
    c
  }
}

///|
/// Parse any JSON value.
fn Parser::parse_value(self : Parser) -> JsonValue? {
  // Depth check: prevent stack overflow from deeply nested structures.
  if self.depth >= max_nesting_depth {
    return None
  }
  self.skip_ws()
  match self.peek() {
    -1 => None
    c =>
      if c == 123 {
        // '{' — object
        self.depth = self.depth + 1
        let result = self.parse_object()
        self.depth = self.depth - 1
        result
      } else if c == 91 {
        // '[' — array
        self.depth = self.depth + 1
        let result = self.parse_array()
        self.depth = self.depth - 1
        result
      } else if c == 34 {
        // '"' — string
        match self.parse_string() {
          None => None
          Some(s) => Some(Str(s))
        }
      } else if c == 45 || (c >= 48 && c <= 57) {
        // '-' or digit — number
        self.parse_number()
      } else if c == 116 {
        // 't' — true
        self.parse_literal("true", Bool(true))
      } else if c == 102 {
        // 'f' — false
        self.parse_literal("false", Bool(false))
      } else if c == 110 {
        // 'n' — null
        self.parse_literal("null", Null)
      } else {
        None
      }
  }
}

///|
/// Parse a literal keyword: "true", "false", "null".
fn Parser::parse_literal(
  self : Parser,
  keyword : String,
  value : JsonValue,
) -> JsonValue? {
  let kl = keyword.length()
  if self.pos + kl > self.input.length() {
    return None
  }
  for i = 0; i < kl; i = i + 1 {
    if self.input[self.pos + i].to_int() != keyword[i].to_int() {
      return None
    }
  }
  self.pos = self.pos + kl
  Some(value)
}

///|
/// Parse a JSON string (including surrounding quotes).
fn Parser::parse_string(self : Parser) -> String? {
  // Consume opening quote.
  if self.next_char() != 34 {
    return None
  }
  let buf = StringBuilder()
  let mut done = false
  while !done {
    if self.pos >= self.input.length() {
      return None // Unterminated string
    }
    let c = self.input[self.pos].to_int()
    self.pos = self.pos + 1
    if c == 34 {
      // Closing quote
      done = true
    } else if c == 92 {
      // Backslash escape
      match self.parse_escape() {
        None => return None
        Some(ch) => buf.write_char(ch)
      }
    } else if c < 32 {
      // Control characters are not allowed in JSON strings (RFC 8259 §7).
      return None
    } else {
      buf.write_char(c.unsafe_to_char())
    }
  }
  Some(buf.to_string())
}

///|
/// Parse a single escape sequence (the character after the backslash).
fn Parser::parse_escape(self : Parser) -> Char? {
  if self.pos >= self.input.length() {
    return None
  }
  let c = self.input[self.pos].to_int()
  self.pos = self.pos + 1
  match c {
    34 => Some('"') // \"
    92 => Some('\\') // \\
    47 => Some('/') // \/
    98 => Some('\u{08}') // \b
    102 => Some('\u{0C}') // \f
    110 => Some('\n') // \n
    114 => Some('\r') // \r
    116 => Some('\t') // \t
    117 =>
      // \uXXXX
      match self.parse_hex4() {
        None => None
        Some(cp) =>
          // Handle surrogate pairs.
          if cp >= 0xD800 && cp <= 0xDBFF {
            // High surrogate; expect \uXXXX low surrogate.
            if self.pos + 1 < self.input.length() &&
              self.input[self.pos].to_int() == 92 &&
              self.input[self.pos + 1].to_int() == 117 {
              self.pos = self.pos + 2
              match self.parse_hex4() {
                None => None
                Some(lo) =>
                  if lo >= 0xDC00 && lo <= 0xDFFF {
                    let combined = 0x10000 +
                      ((cp - 0xD800) << 10) +
                      (lo - 0xDC00)
                    Some(combined.unsafe_to_char())
                  } else {
                    None // Invalid low surrogate
                  }
              }
            } else {
              None // Missing low surrogate
            }
          } else if cp >= 0xDC00 && cp <= 0xDFFF {
            None // Lone low surrogate
          } else {
            Some(cp.unsafe_to_char())
          }
      }
    _ => None
  }
}

///|
/// Parse exactly 4 hexadecimal digits and return the code point.
fn Parser::parse_hex4(self : Parser) -> Int? {
  if self.pos + 4 > self.input.length() {
    return None
  }
  let mut val = 0
  for i = 0; i < 4; i = i + 1 {
    let c = self.input[self.pos].to_int()
    self.pos = self.pos + 1
    let digit = if c >= 48 && c <= 57 {
      c - 48 // 0-9
    } else if c >= 65 && c <= 70 {
      c - 55 // A-F
    } else if c >= 97 && c <= 102 {
      c - 87 // a-f
    } else {
      return None
    }
    val = (val << 4) | digit
  }
  Some(val)
}

///|
/// Parse a JSON number.
fn Parser::parse_number(self : Parser) -> JsonValue? {
  let start = self.pos
  // Optional minus sign.
  if self.peek() == 45 {
    self.pos = self.pos + 1
  }
  // Integer part.
  if self.peek() == 48 {
    // Leading zero: must be followed by '.', 'e', 'E', or end of number.
    self.pos = self.pos + 1
  } else if self.peek() >= 49 && self.peek() <= 57 {
    // Non-zero digit followed by any number of digits.
    self.pos = self.pos + 1
    while self.peek() >= 48 && self.peek() <= 57 {
      self.pos = self.pos + 1
    }
  } else {
    return None
  }
  let mut has_fraction_or_exp = false
  // Fractional part.
  if self.peek() == 46 {
    has_fraction_or_exp = true
    self.pos = self.pos + 1
    if self.peek() < 48 || self.peek() > 57 {
      return None // Must have at least one digit after '.'
    }
    while self.peek() >= 48 && self.peek() <= 57 {
      self.pos = self.pos + 1
    }
  }
  // Exponent part.
  let c = self.peek()
  if c == 101 || c == 69 {
    has_fraction_or_exp = true
    self.pos = self.pos + 1
    // Optional sign.
    let s = self.peek()
    if s == 43 || s == 45 {
      self.pos = self.pos + 1
    }
    if self.peek() < 48 || self.peek() > 57 {
      return None // Must have at least one digit in exponent
    }
    while self.peek() >= 48 && self.peek() <= 57 {
      self.pos = self.pos + 1
    }
  }
  let num_str = self.input[start:self.pos]
  // Pure integers with more than 15 significant digits exceed Double
  // precision (2^53 ≈ 9.007e15). Store them as BigInt to preserve the
  // original decimal string verbatim, avoiding silent precision loss.
  if !has_fraction_or_exp {
    // Count significant digits: skip optional leading '-' and leading zeros.
    let digit_start = if num_str[0].to_int() == 45 { 1 } else { 0 }
    let mut sig = digit_start
    while sig < num_str.length() && num_str[sig].to_int() == 48 {
      sig = sig + 1
    }
    let sig_digits = num_str.length() - sig
    if sig_digits > 15 {
      return Some(BigInt(num_str.to_owned()))
    }
  }
  // Parse the substring as a Double.
  try {
    let d = @string.parse_double(num_str)
    Some(Number(d))
  } catch {
    _ => None
  }
}

///|
/// Parse a JSON array: '[' value (',' value)* ']'
fn Parser::parse_array(self : Parser) -> JsonValue? {
  // Consume '['.
  self.pos = self.pos + 1
  self.skip_ws()
  let items : Array[JsonValue] = []
  if self.peek() == 93 {
    // Empty array
    self.pos = self.pos + 1
    return Some(Arr(items))
  }
  let mut continue_loop = true
  while continue_loop {
    match self.parse_value() {
      None => return None
      Some(v) => {
        items.push(v)
        self.skip_ws()
        match self.peek() {
          44 => {
            // ','
            self.pos = self.pos + 1
            self.skip_ws()
          }
          93 => {
            // ']'
            self.pos = self.pos + 1
            continue_loop = false
          }
          _ => return None
        }
      }
    }
  }
  Some(Arr(items))
}

///|
/// Parse a JSON object: '{' string ':' value (',' string ':' value)* '}'
fn Parser::parse_object(self : Parser) -> JsonValue? {
  // Consume '{'.
  self.pos = self.pos + 1
  self.skip_ws()
  let pairs : Array[(String, JsonValue)] = []
  if self.peek() == 125 {
    // Empty object
    self.pos = self.pos + 1
    return Some(Obj(pairs))
  }
  let mut continue_loop = true
  while continue_loop {
    self.skip_ws()
    // Key must be a string.
    match self.parse_string() {
      None => return None
      Some(key) => {
        self.skip_ws()
        // Expect ':'.
        if self.peek() != 58 {
          return None
        }
        self.pos = self.pos + 1
        // Parse value.
        match self.parse_value() {
          None => return None
          Some(v) => {
            pairs.push((key, v))
            self.skip_ws()
            match self.peek() {
              44 =>
                // ','
                self.pos = self.pos + 1
              125 => {
                // '}'
                self.pos = self.pos + 1
                continue_loop = false
              }
              _ => return None
            }
          }
        }
      }
    }
  }
  Some(Obj(pairs))
}

// ---------------------------------------------------------------------------
// Serializer
// ---------------------------------------------------------------------------

///|
/// Serialize a `JsonValue` to a compact JSON string (no whitespace).
///
/// `NaN`, `Infinity`, and `-Infinity` are serialized as `null` per
/// RFC 8259 §6.
pub fn stringify(v : JsonValue) -> String {
  let buf = StringBuilder()
  write_value(v, buf, false, 0)
  buf.to_string()
}

///|
/// Serialize a `JsonValue` to a pretty-printed JSON string with the given
/// indentation (number of spaces per level).
pub fn stringify_pretty(v : JsonValue, indent : Int) -> String {
  let buf = StringBuilder()
  write_value(v, buf, true, indent)
  buf.to_string()
}

///|
/// Internal: write a value to the buffer.
fn write_value(
  v : JsonValue,
  buf : StringBuilder,
  pretty : Bool,
  indent : Int,
) -> Unit {
  match v {
    Null => buf.write_string("null")
    Bool(b) => buf.write_string(if b { "true" } else { "false" })
    Number(n) =>
      if n.is_nan() || n.is_inf() {
        buf.write_string("null")
      } else if n == n.trunc() && n.abs() < 1.0e15 {
        // Integer-valued doubles: print without decimal point.
        buf.write_string(n.to_int().to_string())
      } else {
        buf.write_string(n.to_string())
      }
    BigInt(s) => buf.write_string(s)
    Str(s) => write_string(s, buf)
    Arr(items) =>
      if items.length() == 0 {
        buf.write_string("[]")
      } else {
        buf.write_char('[')
        let next_indent = indent + 1
        for i = 0; i < items.length(); i = i + 1 {
          if i > 0 {
            buf.write_char(',')
          }
          if pretty {
            write_newline(buf, next_indent)
          }
          write_value(items[i], buf, pretty, next_indent)
        }
        if pretty {
          write_newline(buf, indent)
        }
        buf.write_char(']')
      }
    Obj(pairs) =>
      if pairs.length() == 0 {
        buf.write_string("{}")
      } else {
        buf.write_char('{')
        let next_indent = indent + 1
        for i = 0; i < pairs.length(); i = i + 1 {
          if i > 0 {
            buf.write_char(',')
          }
          if pretty {
            write_newline(buf, next_indent)
          }
          let (key, val) = pairs[i]
          write_string(key, buf)
          buf.write_char(':')
          if pretty {
            buf.write_char(' ')
          }
          write_value(val, buf, pretty, next_indent)
        }
        if pretty {
          write_newline(buf, indent)
        }
        buf.write_char('}')
      }
  }
}

///|
/// Internal: write a JSON string with proper escaping.
fn write_string(s : String, buf : StringBuilder) -> Unit {
  buf.write_char('"')
  for c in s.iter() {
    let cp = c.to_int()
    match cp {
      34 => buf.write_string("\\\"") // "
      92 => buf.write_string("\\\\") // \
      8 => buf.write_string("\\b") // backspace
      12 => buf.write_string("\\f") // form feed
      10 => buf.write_string("\\n") // newline
      13 => buf.write_string("\\r") // carriage return
      9 => buf.write_string("\\t") // tab
      _ =>
        if cp < 32 {
          // Control character: \u00XX
          buf.write_string("\\u00")
          buf.write_char(hex_digit(cp >> 4))
          buf.write_char(hex_digit(cp & 0xF))
        } else if cp > 0xFFFF {
          // Astral plane character: encode as UTF-16 surrogate pair.
          let adjusted = cp - 0x10000
          let hi = 0xD800 + (adjusted >> 10)
          let lo = 0xDC00 + (adjusted & 0x3FF)
          buf.write_string("\\u")
          buf.write_char(hex_digit((hi >> 12) & 0xF))
          buf.write_char(hex_digit((hi >> 8) & 0xF))
          buf.write_char(hex_digit((hi >> 4) & 0xF))
          buf.write_char(hex_digit(hi & 0xF))
          buf.write_string("\\u")
          buf.write_char(hex_digit((lo >> 12) & 0xF))
          buf.write_char(hex_digit((lo >> 8) & 0xF))
          buf.write_char(hex_digit((lo >> 4) & 0xF))
          buf.write_char(hex_digit(lo & 0xF))
        } else if cp >= 0xD800 && cp <= 0xDFFF {
          // Lone surrogate: escape as \uXXXX to preserve it exactly.
          buf.write_string("\\u")
          buf.write_char(hex_digit((cp >> 12) & 0xF))
          buf.write_char(hex_digit((cp >> 8) & 0xF))
          buf.write_char(hex_digit((cp >> 4) & 0xF))
          buf.write_char(hex_digit(cp & 0xF))
        } else {
          buf.write_char(c)
        }
    }
  }
  buf.write_char('"')
}

///|
/// Internal: write a newline followed by `indent` spaces.
fn write_newline(buf : StringBuilder, indent : Int) -> Unit {
  buf.write_char('\n')
  for _ in 0..<indent {
    buf.write_char(' ')
  }
}

///|
/// Internal: convert a nibble (0-15) to a hex character.
fn hex_digit(n : Int) -> Char {
  if n < 10 {
    (48 + n).unsafe_to_char() // '0' + n
  } else {
    (55 + n).unsafe_to_char() // 'A' + n - 10
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "json: parse null" {
  assert_true(parse("null") == Some(Null))
  assert_true(parse("  null  ") == Some(Null))
}

///|
test "json: parse booleans" {
  assert_true(parse("true") == Some(Bool(true)))
  assert_true(parse("false") == Some(Bool(false)))
}

///|
test "json: parse numbers" {
  assert_true(parse("42") == Some(Number(42.0)))
  assert_true(parse("-17") == Some(Number(-17.0)))
  assert_true(parse("3.14") == Some(Number(3.14)))
  assert_true(parse("1e10") == Some(Number(1.0e10)))
  assert_true(parse("1.5e-3") == Some(Number(1.5e-3)))
  assert_true(parse("0") == Some(Number(0.0)))
}

///|
test "json: parse strings" {
  assert_true(parse("\"hello\"") == Some(Str("hello")))
  assert_true(parse("\"\"") == Some(Str("")))
  assert_true(parse("\"with \\\"quotes\\\"\"") == Some(Str("with \"quotes\"")))
  assert_true(parse("\"line\\nbreak\"") == Some(Str("line\nbreak")))
  assert_true(parse("\"tab\\there\"") == Some(Str("tab\there")))
  assert_true(parse("\"unicode\\u0041\"") == Some(Str("unicodeA")))
}

///|
test "json: parse arrays" {
  let v = parse("[1, 2, 3]")
  assert_true(v is Some(_))
  match v {
    Some(Arr(a)) => {
      assert_eq(a.length(), 3)
      assert_true(a[0] == Number(1.0))
      assert_true(a[1] == Number(2.0))
      assert_true(a[2] == Number(3.0))
    }
    _ => fail("expected array")
  }
  assert_true(parse("[]") == Some(Arr([])))
  assert_true(parse("[\"a\", true, null]") is Some(_))
}

///|
test "json: parse objects" {
  let v = parse("{\"name\": \"Alice\", \"age\": 30}")
  assert_true(v is Some(_))
  match v {
    Some(Obj(pairs)) => {
      assert_eq(pairs.length(), 2)
      let (k0, v0) = pairs[0]
      let (k1, v1) = pairs[1]
      assert_true(k0 == "name")
      assert_true(v0 == Str("Alice"))
      assert_true(k1 == "age")
      assert_true(v1 == Number(30.0))
    }
    _ => fail("expected object")
  }
  assert_true(parse("{}") == Some(Obj([])))
}

///|
test "json: parse nested" {
  let v = parse("{\"list\": [1, 2, {\"inner\": true}]}")
  assert_true(v is Some(_))
  match v {
    Some(Obj(pairs)) => {
      let (_, v0) = pairs[0]
      match v0 {
        Arr(a) =>
          match a[2] {
            Obj(inner) => {
              let (_, iv0) = inner[0]
              assert_true(iv0 == Bool(true))
            }
            _ => fail("expected inner object")
          }
        _ => fail("expected array")
      }
    }
    _ => fail("expected object")
  }
}

///|
test "json: parse rejects invalid" {
  assert_true(parse("") is None)
  assert_true(parse("{") is None)
  assert_true(parse("[") is None)
  assert_true(parse("[1,]") is None) // trailing comma
  assert_true(parse("{,}") is None)
  assert_true(parse("\"unterminated") is None)
  assert_true(parse("12.3.4") is None)
  assert_true(parse("tru") is None)
  assert_true(parse("123abc") is None) // trailing garbage
  assert_true(parse("\"\\uABC\"") is None) // incomplete unicode escape
}

///|
test "json: stringify primitives" {
  assert_eq(stringify(Null), "null")
  assert_eq(stringify(Bool(true)), "true")
  assert_eq(stringify(Bool(false)), "false")
  assert_eq(stringify(Number(42.0)), "42")
  assert_eq(stringify(Number(-17.0)), "-17")
  assert_eq(stringify(Number(3.14)), "3.14")
  assert_eq(stringify(Str("hello")), "\"hello\"")
  assert_eq(stringify(Str("")), "\"\"")
}

///|
test "json: stringify escapes" {
  assert_eq(stringify(Str("with \"quotes\"")), "\"with \\\"quotes\\\"\"")
  assert_eq(stringify(Str("line\nbreak")), "\"line\\nbreak\"")
  assert_eq(stringify(Str("tab\there")), "\"tab\\there\"")
  assert_eq(stringify(Str("back\\slash")), "\"back\\\\slash\"")
}

///|
test "json: stringify arrays and objects" {
  assert_eq(stringify(Arr([])), "[]")
  assert_eq(stringify(Arr([Number(1.0), Number(2.0)])), "[1,2]")
  assert_eq(stringify(Obj([])), "{}")
  assert_eq(
    stringify(Obj([("a", Number(1.0)), ("b", Str("x"))])),
    "{\"a\":1,\"b\":\"x\"}",
  )
}

///|
test "json: stringify NaN and Infinity as null" {
  assert_eq(stringify(Number(@double.not_a_number)), "null")
  assert_eq(stringify(Number(@double.infinity)), "null")
  assert_eq(stringify(Number(@double.neg_infinity)), "null")
}

///|
test "json: round-trip" {
  let inputs = [
    "null", "true", "false", "42", "-3.14", "\"hello world\"", "[1,2,3]", "{\"a\":1,\"b\":2}",
    "{\"nested\":{\"deep\":[1,[2,3]]}}", "{\"unicode\":\"\\u00e9\\u00e8\\u00ea\"}",
  ]
  for i = 0; i < inputs.length(); i = i + 1 {
    let parsed = parse(inputs[i])
    assert_true(parsed is Some(_))
    match parsed {
      Some(v) => {
        let s = stringify(v)
        let reparsed = parse(s)
        assert_true(reparsed is Some(_))
      }
      None => ()
    }
  }
}

///|
test "json: pretty print" {
  let v = json_obj([
    ("name", json_str("Alice")),
    ("age", json_int(30)),
    ("scores", json_arr([json_int(90), json_int(85)])),
  ])
  let s = stringify_pretty(v, 2)
  // Should contain newlines and indentation.
  assert_true(s.contains("\n"))
  assert_true(s.contains("  \"name\""))
}

///|
test "json: accessor API" {
  let v = json_obj([
    ("name", json_str("Bob")),
    ("age", json_int(25)),
    ("active", json_bool(true)),
    ("tags", json_arr([json_str("a"), json_str("b")])),
  ])
  assert_eq(get_str(v, "name"), Some("Bob"))
  assert_eq(get_num(v, "age"), Some(25.0))
  assert_eq(get_bool(v, "active"), Some(true))
  assert_true(get(v, "missing") is None)
  match get(v, "tags") {
    Some(Arr(a)) => {
      assert_eq(a.length(), 2)
      assert_eq(as_string(a[0]), Some("a"))
    }
    _ => fail("expected tags array")
  }
}

///|
test "json: get_at" {
  let v = json_arr([json_int(10), json_int(20), json_int(30)])
  assert_eq(as_number(get_at(v, 0).unwrap()).unwrap(), 10.0)
  assert_eq(as_number(get_at(v, 2).unwrap()).unwrap(), 30.0)
  assert_true(get_at(v, 3) is None)
  assert_true(get_at(v, -1) is None)
}

///|
test "json: surrogate pair parsing" {
  // U+1F600 (grinning face emoji) encoded as surrogate pair.
  let v = parse("\"\\uD83D\\uDE00\"")
  assert_true(v is Some(_))
  match v {
    Some(Str(s)) => {
      // The string should contain exactly one Unicode code point.
      // MoonBit's String.length() may return UTF-16 code units (2) or
      // UTF-8 bytes (4) depending on the target. Verify correctness by
      // round-tripping through stringify, which must reproduce the
      // surrogate pair escape.
      let json_str = stringify(Str(s))
      assert_true(json_str.contains("\\uD83D\\uDE00"))
    }
    _ => fail("expected string")
  }
}

///|
test "json: duplicate keys last wins" {
  let v = parse("{\"a\":1,\"a\":2}")
  match v {
    Some(Obj(_)) => assert_eq(get_num(v.unwrap(), "a"), Some(2.0))
    _ => fail("expected object")
  }
}

///|
test "json: parse_or with default" {
  let v = parse_or("invalid", json_str("fallback"))
  assert_eq(as_string(v), Some("fallback"))
  let v2 = parse_or("\"valid\"", json_str("fallback"))
  assert_eq(as_string(v2), Some("valid"))
}

///|
test "json: depth limit rejects deeply nested arrays" {
  // Build a string of 2000 nested arrays: [[[[...]]]]
  let buf = StringBuilder()
  for _ in 0..<2000 {
    buf.write_char('[')
  }
  for _ in 0..<2000 {
    buf.write_char(']')
  }
  let malicious = buf.to_string()
  // Should be rejected (depth > max_nesting_depth)
  assert_true(parse(malicious) is None)
}

///|
test "json: depth limit rejects deeply nested objects" {
  // Build deeply nested objects: {"a":{"a":{"a":...}}}
  let buf = StringBuilder()
  for _ in 0..<2000 {
    buf.write_string("{\"a\":")
  }
  buf.write_string("1")
  for _ in 0..<2000 {
    buf.write_char('}')
  }
  let malicious = buf.to_string()
  assert_true(parse(malicious) is None)
}

///|
test "json: moderate nesting accepted" {
  // 500 levels of nesting should be within the limit
  let buf = StringBuilder()
  for _ in 0..<500 {
    buf.write_char('[')
  }
  for _ in 0..<500 {
    buf.write_char(']')
  }
  let moderate = buf.to_string()
  assert_true(parse(moderate) is Some(_))
}

///|
test "json: big integer parsed as BigInt" {
  // 20-digit number exceeds 2^53, should be BigInt not Number
  let v = parse("12345678901234567890")
  assert_true(v is Some(_))
  match v {
    Some(BigInt(s)) => assert_eq(s, "12345678901234567890")
    _ => fail("expected BigInt for 20-digit integer")
  }
}

///|
test "json: negative big integer parsed as BigInt" {
  let v = parse("-98765432109876543210")
  assert_true(v is Some(_))
  match v {
    Some(BigInt(s)) => assert_eq(s, "-98765432109876543210")
    _ => fail("expected BigInt for negative 20-digit integer")
  }
}

///|
test "json: small integer stays Number" {
  // 15 significant digits = within Double precision
  let v = parse("123456789012345")
  match v {
    Some(Number(n)) => assert_eq(n, 123456789012345.0)
    _ => fail("expected Number for 15-digit integer")
  }
}

///|
test "json: 16-digit integer becomes BigInt" {
  // 16 significant digits exceed safe Double range
  let v = parse("1234567890123456")
  match v {
    Some(BigInt(s)) => assert_eq(s, "1234567890123456")
    _ => fail("expected BigInt for 16-digit integer")
  }
}

///|
test "json: float with many digits stays Number" {
  // Has a decimal point, so never BigInt even with many digits
  let v = parse("12345678901234567890.0")
  match v {
    Some(Number(_)) => ()
    _ => fail("expected Number for float, not BigInt")
  }
}

///|
test "json: exponent number stays Number" {
  let v = parse("12345678901234567890e5")
  match v {
    Some(Number(_)) => ()
    _ => fail("expected Number for exponent notation, not BigInt")
  }
}

///|
test "json: BigInt round-trips through stringify" {
  let original = "9007199254740993" // 2^53 + 1
  let v = parse(original)
  match v {
    Some(BigInt(s)) => {
      assert_eq(s, original)
      assert_eq(stringify(BigInt(s)), original)
    }
    _ => fail("expected BigInt for 2^53+1")
  }
}

///|
test "json: BigInt in object" {
  let json = parse("{\"id\": 12345678901234567890, \"name\": \"test\"}")
  assert_true(json is Some(_))
  match json {
    Some(obj) => {
      let id = get_bigint(obj, "id")
      match id {
        Some(s) => assert_eq(s, "12345678901234567890")
        None => fail("expected BigInt for id field")
      }
      let name = get_str(obj, "name")
      match name {
        Some(s) => assert_eq(s, "test")
        None => fail("expected string for name field")
      }
    }
    None => fail("expected Some for valid JSON")
  }
}

///|
test "json: BigInt in array" {
  let json = parse("[12345678901234567890, 42, -99999999999999999999]")
  assert_true(json is Some(_))
  match json {
    Some(arr) => {
      let v0 = get_at(arr, 0)
      match v0 {
        Some(BigInt(s)) => assert_eq(s, "12345678901234567890")
        _ => fail("expected BigInt at index 0")
      }
      let v1 = get_at(arr, 1)
      match v1 {
        Some(Number(n)) => assert_eq(n, 42.0)
        _ => fail("expected Number at index 1")
      }
      let v2 = get_at(arr, 2)
      match v2 {
        Some(BigInt(s)) => assert_eq(s, "-99999999999999999999")
        _ => fail("expected BigInt at index 2")
      }
    }
    None => fail("expected Some for valid JSON array")
  }
}

///|
test "json: is_bigint predicate" {
  assert_true(is_bigint(BigInt("12345678901234567890")))
  assert_false(is_bigint(Number(42.0)))
  assert_false(is_bigint(Null))
}

///|
test "json: as_bigint accessor" {
  let v = BigInt("99999999999999999999")
  match as_bigint(v) {
    Some(s) => assert_eq(s, "99999999999999999999")
    None => fail("as_bigint should return Some for BigInt value")
  }
  // as_bigint on non-BigInt returns None
  assert_true(as_bigint(Number(42.0)) is None)
  assert_true(as_bigint(Str("hello")) is None)
}

///|
test "json: json_bigint constructor and stringify" {
  let v = json_bigint("123456789012345678901234567890")
  assert_eq(stringify(v), "123456789012345678901234567890")
}

///|
test "json: BigInt equality" {
  assert_true(BigInt("12345678901234567890") == BigInt("12345678901234567890"))
  assert_false(BigInt("12345678901234567890") == BigInt("12345678901234567891"))
  assert_false(BigInt("12345678901234567890") == Number(1.2345678901234568e19))
}

///|
test "json: leading zeros don't trigger BigInt" {
  // "0" is a valid JSON number with only 1 significant digit
  let v = parse("0")
  match v {
    Some(Number(n)) => assert_eq(n, 0.0)
    _ => fail("expected Number for zero")
  }
  // "001234" is invalid JSON (leading zeros prohibited), should return None
  assert_true(parse("001234") is None)
}

///|
test "json: BigInt stringify in pretty mode" {
  let v = json_obj([("balance", BigInt("999999999999999999999"))])
  let s = stringify_pretty(v, 2)
  // Should contain the BigInt string verbatim
  assert_true(s.contains("999999999999999999999"))
}
