/// YAML serialization (subset).
///
/// Supports a practical subset of YAML 1.2: scalars (string, int, float,
/// bool, null), mappings, and sequences. Indentation-based parsing with
/// `- ` for list items and `key: value` for mappings.
///
/// Does NOT support: anchors/aliases, multi-document streams, flow style
/// `{a: b}`, tags, complex keys, multi-line folded scalars.
///
/// `proof-enabled` is `false`.

///|
/// YAML value type.
pub enum YamlValue {
  YamlNull
  YamlBool(Bool)
  YamlInt(Int)
  YamlFloat(Double)
  YamlStr(String)
  YamlSeq(Array[YamlValue])
  YamlMap(Array[(String, YamlValue)])
}

///|
/// Parse a YAML document string into a YamlValue.
/// Returns None on parse error.
pub fn parse_yaml(input : String) -> YamlValue? {
  let lines : Array[String] = []
  let mut current = ""
  for ch in input {
    if ch == '\n' {
      lines.push(current)
      current = ""
    } else if ch != '\r' {
      current += ch.to_string()
    }
  }
  if current != "" {
    lines.push(current)
  }
  // Remove trailing empty lines
  while lines.length() > 0 && lines[lines.length() - 1].trim() == "" {
    lines.pop() |> ignore
  }
  if lines.length() == 0 {
    return Some(YamlNull)
  }
  let result = parse_block(lines, 0, indent_of(lines[0]))
  match result {
    None => None
    Some((v, _)) => Some(v)
  }
}

///|
/// Get indentation level (number of leading spaces).
fn indent_of(line : String) -> Int {
  let mut n = 0
  for ch in line {
    if ch == ' ' {
      n = n + 1
    } else {
      break
    }
  }
  n
}

///|
/// Extract a substring [start, end) from a String.
fn str_substring(s : String, start : Int, end_ : Int) -> String {
  let chars = s.to_array()
  let e = if end_ > chars.length() { chars.length() } else { end_ }
  let buf = StringBuilder::new()
  for i = start; i < e; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// Parse a block of lines starting at index `start` with indentation `indent`.
/// Returns (value, next_index).
fn parse_block(
  lines : Array[String],
  start : Int,
  indent : Int,
) -> (YamlValue, Int)? {
  if start >= lines.length() {
    return None
  }
  let line = lines[start]
  let trimmed = line.trim().to_owned()
  if trimmed == "" {
    return parse_block(lines, start + 1, indent)
  }
  // Check if it's a sequence (starts with "- ")
  if trimmed.has_prefix("- ") || trimmed == "-" {
    parse_sequence(lines, start, indent)
  } else {
    parse_mapping(lines, start, indent)
  }
}

///|
/// Parse a sequence block.
fn parse_sequence(
  lines : Array[String],
  start : Int,
  indent : Int,
) -> (YamlValue, Int)? {
  let items : Array[YamlValue] = []
  let mut i = start
  while i < lines.length() {
    let line = lines[i]
    let trimmed = line.trim().to_owned()
    if trimmed == "" {
      i = i + 1
      continue
    }
    let cur_indent = indent_of(line)
    if cur_indent < indent {
      break
    }
    if cur_indent > indent {
      // Should not happen at sequence start
      i = i + 1
      continue
    }
    if !trimmed.has_prefix("- ") && trimmed != "-" {
      break
    }
    let rest = if trimmed == "-" { "" } else { str_substring(trimmed, 2, trimmed.length()) }
    if rest == "" {
      // Nested block
      let next = parse_block(lines, i + 1, indent + 2)
      match next {
        None => i = i + 1
        Some((v, ni)) => {
          items.push(v)
          i = ni
        }
      }
    } else if rest.contains(": ") || (rest.has_suffix(":") && !rest.contains(": ")) {
      // Inline mapping after "- "
      let sub_lines : Array[String] = []
      sub_lines.push(String::make(indent + 2, ' ') + rest)
      let mut j = i + 1
      while j < lines.length() {
        let l = lines[j]
        if l.trim() == "" {
          j = j + 1
          continue
        }
        if indent_of(l) > indent {
          sub_lines.push(l)
          j = j + 1
        } else {
          break
        }
      }
      let parsed = parse_block(sub_lines, 0, indent + 2)
      match parsed {
        None => i = i + 1
        Some((v, _)) => {
          items.push(v)
          i = j
        }
      }
    } else {
      // Scalar item
      items.push(parse_scalar(rest))
      i = i + 1
    }
  }
  Some((YamlSeq(items), i))
}

///|
/// Parse a mapping block.
fn parse_mapping(
  lines : Array[String],
  start : Int,
  indent : Int,
) -> (YamlValue, Int)? {
  let pairs : Array[(String, YamlValue)] = []
  let mut i = start
  while i < lines.length() {
    let line = lines[i]
    let trimmed = line.trim().to_owned()
    if trimmed == "" {
      i = i + 1
      continue
    }
    let cur_indent = indent_of(line)
    if cur_indent < indent {
      break
    }
    if cur_indent > indent {
      i = i + 1
      continue
    }
    // Find ": " separator
    let colon_idx = find_colon(trimmed)
    if colon_idx < 0 {
      break
    }
    let key = str_substring(trimmed, 0, colon_idx)
    let val_str = str_substring(trimmed, colon_idx + 1, trimmed.length())
    if val_str == "" {
      // Nested block
      let mut j = i + 1
      while j < lines.length() && lines[j].trim() == "" {
        j = j + 1
      }
      if j < lines.length() && indent_of(lines[j]) > indent {
        let next = parse_block(lines, j, indent_of(lines[j]))
        match next {
          None => i = i + 1
          Some((v, ni)) => {
            pairs.push((key, v))
            i = ni
          }
        }
      } else {
        pairs.push((key, YamlNull))
        i = i + 1
      }
    } else {
      pairs.push((key, parse_scalar(val_str)))
      i = i + 1
    }
  }
  Some((YamlMap(pairs), i))
}

///|
/// Find the first ": " separator in a line (not inside quotes).
fn find_colon(s : String) -> Int {
  let mut in_squote = false
  let mut in_dquote = false
  let chars = s.to_array()
  for idx = 0; idx < chars.length() - 1; idx = idx + 1 {
    let c = chars[idx]
    if c == '\'' && !in_dquote {
      in_squote = !in_squote
    } else if c == '"' && !in_squote {
      in_dquote = !in_dquote
    } else if c == ':' && !in_squote && !in_dquote && chars[idx + 1] == ' ' {
      return idx
    }
  }
  // Check for trailing colon (key:)
  if chars.length() > 0 && chars[chars.length() - 1] == ':' && !in_squote && !in_dquote {
    return chars.length() - 1
  }
  -1
}

///|
/// Try to parse an integer from a string.
fn try_parse_int(s : String) -> Int? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut idx = 0
  let mut neg = false
  if chars[0] == '-' {
    neg = true
    idx = 1
  } else if chars[0] == '+' {
    idx = 1
  }
  if idx >= chars.length() {
    return None
  }
  let mut result = 0
  while idx < chars.length() {
    let c = chars[idx]
    if c < '0' || c > '9' {
      return None
    }
    result = result * 10 + (c.to_int() - 48)
    idx = idx + 1
  }
  Some(if neg { -result } else { result })
}

///|
/// Try to parse a double from a string.
fn try_parse_double(s : String) -> Double? {
  let chars = s.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut idx = 0
  let mut neg = false
  if chars[0] == '-' {
    neg = true
    idx = 1
  } else if chars[0] == '+' {
    idx = 1
  }
  let mut int_part = 0.0
  let mut has_digits = false
  while idx < chars.length() && chars[idx] >= '0' && chars[idx] <= '9' {
    int_part = int_part * 10.0 + (chars[idx].to_int() - 48).to_double()
    has_digits = true
    idx = idx + 1
  }
  let mut frac = 0.0
  if idx < chars.length() && chars[idx] == '.' {
    idx = idx + 1
    let mut scale = 0.1
    while idx < chars.length() && chars[idx] >= '0' && chars[idx] <= '9' {
      frac = frac + (chars[idx].to_int() - 48).to_double() * scale
      scale = scale * 0.1
      has_digits = true
      idx = idx + 1
    }
  }
  if !has_digits {
    return None
  }
  let mut result = int_part + frac
  if idx < chars.length() && (chars[idx] == 'e' || chars[idx] == 'E') {
    idx = idx + 1
    let mut exp_neg = false
    if idx < chars.length() && chars[idx] == '-' {
      exp_neg = true
      idx = idx + 1
    } else if idx < chars.length() && chars[idx] == '+' {
      idx = idx + 1
    }
    let mut exp = 0
    while idx < chars.length() && chars[idx] >= '0' && chars[idx] <= '9' {
      exp = exp * 10 + (chars[idx].to_int() - 48)
      idx = idx + 1
    }
    if exp > 0 {
      let mut multiplier = 1.0
      for e = 0; e < exp; e = e + 1 {
        multiplier = multiplier * 10.0
      }
      if exp_neg {
        result = result / multiplier
      } else {
        result = result * multiplier
      }
    }
  }
  if idx < chars.length() {
    return None
  }
  Some(if neg { -result } else { result })
}

///|
/// Parse a scalar value into the appropriate YamlValue.
fn parse_scalar(s : String) -> YamlValue {
  let t = s.trim().to_owned()
  if t == "null" || t == "~" || t == "" {
    return YamlNull
  }
  if t == "true" || t == "True" || t == "TRUE" {
    return YamlBool(true)
  }
  if t == "false" || t == "False" || t == "FALSE" {
    return YamlBool(false)
  }
  // Try int
  match try_parse_int(t) {
    Some(n) => return YamlInt(n)
    None => ()
  }
  // Try float
  match try_parse_double(t) {
    Some(f) => return YamlFloat(f)
    None => ()
  }
  // String (strip quotes)
  if t.length() >= 2 {
    if t[0] == '"' && t[t.length() - 1] == '"' {
      return YamlStr(str_substring(t, 1, t.length() - 1))
    }
    if t[0] == '\'' && t[t.length() - 1] == '\'' {
      return YamlStr(str_substring(t, 1, t.length() - 1))
    }
  }
  YamlStr(t)
}

///|
/// Serialize a YamlValue to a YAML string.
pub fn dump_yaml(v : YamlValue) -> String {
  let buf = StringBuilder::new()
  dump_value(v, 0, buf)
  buf.to_string()
}

fn dump_value(v : YamlValue, indent : Int, buf : StringBuilder) -> Unit {
  match v {
    YamlNull => buf.write("null")
    YamlBool(b) => buf.write(if b { "true" } else { "false" })
    YamlInt(n) => buf.write(n.to_string())
    YamlFloat(f) => buf.write(f.to_string())
    YamlStr(s) => dump_string(s, buf)
    YamlSeq(items) => {
      for i = 0; i < items.length(); i = i + 1 {
        buf.write(String::make(indent, ' '))
        buf.write("- ")
        dump_value_inline(items[i], indent + 2, buf)
        buf.write('\n')
      }
    }
    YamlMap(pairs) => {
      for i = 0; i < pairs.length(); i = i + 1 {
        buf.write(String::make(indent, ' '))
        buf.write(pairs[i].0)
        buf.write(": ")
        dump_value_inline(pairs[i].1, indent + 2, buf)
        buf.write('\n')
      }
    }
  }
}

fn dump_value_inline(
  v : YamlValue,
  child_indent : Int,
  buf : StringBuilder,
) -> Unit {
  match v {
    YamlNull => buf.write("null")
    YamlBool(b) => buf.write(if b { "true" } else { "false" })
    YamlInt(n) => buf.write(n.to_string())
    YamlFloat(f) => buf.write(f.to_string())
    YamlStr(s) => dump_string(s, buf)
    YamlSeq(_) | YamlMap(_) => {
      // Multi-line: newline then nested block
      buf.write('\n')
      dump_value(v, child_indent, buf)
    }
  }
}

fn dump_string(s : String, buf : StringBuilder) -> Unit {
  // Quote if needed (contains special chars)
  let needs_quote = s == "" || s == "null" || s == "true" || s == "false" || s.contains(": ") || s.contains("#") || s.has_prefix("- ") || s.has_prefix("? ") || s.has_prefix("! ")
  if needs_quote {
    buf.write('"')
    buf.write(s)
    buf.write('"')
  } else {
    buf.write(s)
  }
}

///|
test "yaml: simple mapping" {
  let yaml = "name: Alice\nage: 30\nactive: true\n"
  let v = parse_yaml(yaml)
  match v {
    Some(YamlMap(pairs)) => {
      assert_eq(pairs.length(), 3)
      assert_eq(pairs[0].0, "name")
      match pairs[0].1 {
        YamlStr(s) => assert_eq(s, "Alice")
        _ => assert_true(false)
      }
      match pairs[1].1 {
        YamlInt(n) => assert_eq(n, 30)
        _ => assert_true(false)
      }
      match pairs[2].1 {
        YamlBool(b) => assert_true(b)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "yaml: nested mapping" {
  let yaml = "server:\n  host: localhost\n  port: 8080\n"
  let v = parse_yaml(yaml)
  match v {
    Some(YamlMap(pairs)) =>
      match pairs[0].1 {
        YamlMap(inner) => {
          assert_eq(inner.length(), 2)
          match inner[0].1 {
            YamlStr(s) => assert_eq(s, "localhost")
            _ => assert_true(false)
          }
          match inner[1].1 {
            YamlInt(n) => assert_eq(n, 8080)
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "yaml: sequence" {
  let yaml = "items:\n  - apple\n  - banana\n  - cherry\n"
  let v = parse_yaml(yaml)
  match v {
    Some(YamlMap(pairs)) =>
      match pairs[0].1 {
        YamlSeq(items) => {
          assert_eq(items.length(), 3)
          match items[0] {
            YamlStr(s) => assert_eq(s, "apple")
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "yaml: top-level sequence" {
  let yaml = "- 1\n- 2\n- 3\n"
  let v = parse_yaml(yaml)
  match v {
    Some(YamlSeq(items)) => {
      assert_eq(items.length(), 3)
      match items[0] {
        YamlInt(n) => assert_eq(n, 1)
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "yaml: dump and reparse" {
  let v = YamlMap([
    ("name", YamlStr("test")),
    ("value", YamlInt(42)),
    ("flag", YamlBool(true)),
  ])
  let dumped = dump_yaml(v)
  let reparsed = parse_yaml(dumped)
  match reparsed {
    Some(YamlMap(pairs)) => {
      assert_eq(pairs.length(), 3)
      assert_eq(pairs[0].0, "name")
    }
    _ => assert_true(false)
  }
}
