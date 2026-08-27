/// YAML serialization (subset).
///
/// Supports a practical subset of YAML 1.2: scalars (string, int, float,
/// bool, null), mappings, sequences, anchors (`&name`), aliases (`*name`),
/// and merge keys (`<<: *name`).
///
/// Does NOT support: multi-document streams, flow style `{a: b}`, tags,
/// complex keys, multi-line folded scalars.
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
/// Anchor table: maps anchor names to their parsed values.
/// Uses linear search (typical YAML files have few anchors).
priv struct YamlAnchors {
  entries : Array[(String, YamlValue)]
}

///|
fn YamlAnchors::new() -> YamlAnchors {
  { entries: [] }
}

///|
/// Store an anchor → value mapping.
fn YamlAnchors::set(
  self : YamlAnchors,
  name : String,
  value : YamlValue,
) -> Unit {
  self.entries.push((name, value))
}

///|
/// Look up an anchor by name. Returns `None` if not found.
fn YamlAnchors::get(self : YamlAnchors, name : String) -> YamlValue? {
  let mut i = self.entries.length() - 1
  while i >= 0 {
    let (n, v) = self.entries[i]
    if n == name {
      return Some(v)
    }
    i = i - 1
  }
  None
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
  let anchors = YamlAnchors::new()
  let result = parse_block(lines, 0, indent_of(lines[0]), anchors)
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
  let buf = StringBuilder()
  for i = start; i < e; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// Extract an anchor declaration (`&name`) from the start of a string.
/// Returns `(anchor_name, rest)`. If no anchor is present, returns
/// `("", original_string)`.
///
/// Example: `"&defaults adapter: postgres"` → `("defaults", "adapter: postgres")`
/// Example: `"hello"` → `("", "hello")`
fn extract_anchor(s : String) -> (String, String) {
  let trimmed = s.trim().to_owned()
  if !trimmed.has_prefix("&") {
    return ("", s)
  }
  // Find the end of the anchor name (whitespace or end of string)
  let chars = trimmed.to_array()
  let mut idx = 1 // skip '&'
  while idx < chars.length() && chars[idx] != ' ' && chars[idx] != '\t' {
    idx = idx + 1
  }
  let anchor_name = str_substring(trimmed, 1, idx)
  let rest = if idx < chars.length() {
    str_substring(trimmed, idx, trimmed.length()).trim().to_owned()
  } else {
    ""
  }
  (anchor_name, rest)
}

///|
/// Parse a block of lines starting at index `start` with indentation `indent`.
/// Returns (value, next_index).
fn parse_block(
  lines : Array[String],
  start : Int,
  indent : Int,
  anchors : YamlAnchors,
) -> (YamlValue, Int)? {
  if start >= lines.length() {
    return None
  }
  let line = lines[start]
  let trimmed = line.trim().to_owned()
  if trimmed == "" {
    return parse_block(lines, start + 1, indent, anchors)
  }
  // Check if it's a sequence (starts with "- ")
  if trimmed.has_prefix("- ") || trimmed == "-" {
    parse_sequence(lines, start, indent, anchors)
  } else {
    parse_mapping(lines, start, indent, anchors)
  }
}

///|
/// Parse a sequence block.
fn parse_sequence(
  lines : Array[String],
  start : Int,
  indent : Int,
  anchors : YamlAnchors,
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
    let rest = if trimmed == "-" {
      ""
    } else {
      str_substring(trimmed, 2, trimmed.length())
    }
    // Check for alias: *name
    if rest.has_prefix("*") {
      let alias_name = str_substring(rest, 1, rest.length()).trim().to_owned()
      match anchors.get(alias_name) {
        Some(v) => items.push(v)
        None => return None // Undefined alias is a parse error
      }
      i = i + 1
      continue
    }
    // Check for anchor: &name [value]
    let (anchor_name, actual_rest) = extract_anchor(rest)
    if rest == "" {
      // Nested block
      let next = parse_block(lines, i + 1, indent + 2, anchors)
      match next {
        None => i = i + 1
        Some((v, ni)) => {
          if anchor_name != "" {
            anchors.set(anchor_name, v)
          }
          items.push(v)
          i = ni
        }
      }
    } else if actual_rest.contains(": ") ||
      (actual_rest.has_suffix(":") && !actual_rest.contains(": ")) {
      // Inline mapping after "- "
      let sub_lines : Array[String] = []
      sub_lines.push(String::make(indent + 2, ' ') + actual_rest)
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
      let parsed = parse_block(sub_lines, 0, indent + 2, anchors)
      match parsed {
        None => i = i + 1
        Some((v, _)) => {
          if anchor_name != "" {
            anchors.set(anchor_name, v)
          }
          items.push(v)
          i = j
        }
      }
    } else {
      // Scalar item (possibly with anchor)
      let v = parse_scalar(actual_rest)
      if anchor_name != "" {
        anchors.set(anchor_name, v)
      }
      items.push(v)
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
  anchors : YamlAnchors,
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
      .trim()
      .to_owned()
    // Handle alias value: *name
    if val_str.has_prefix("*") {
      let alias_name = str_substring(val_str, 1, val_str.length())
        .trim()
        .to_owned()
      // Merge key: <<: *name
      if key == "<<" {
        match anchors.get(alias_name) {
          Some(YamlMap(merged)) =>
            for k = 0; k < merged.length(); k = k + 1 {
              pairs.push(merged[k])
            }
          Some(YamlSeq(merged_items)) =>
            // Merge sequence of mappings
            for k = 0; k < merged_items.length(); k = k + 1 {
              match merged_items[k] {
                YamlMap(merged) =>
                  for m = 0; m < merged.length(); m = m + 1 {
                    pairs.push(merged[m])
                  }
                _ => ()
              }
            }
          Some(_) => () // Non-map merge: ignore
          None => return None // Undefined alias
        }
      } else {
        // Regular alias
        match anchors.get(alias_name) {
          Some(v) => pairs.push((key, v))
          None => return None
        }
      }
      i = i + 1
      continue
    }
    // Handle flow-style merge: <<: [*a, *b]
    if key == "<<" && val_str.has_prefix("[") && val_str.has_suffix("]") {
      let inner = str_substring(val_str, 1, val_str.length() - 1)
      let parts : Array[String] = []
      let mut current = ""
      for ch in inner {
        if ch == ',' {
          parts.push(current)
          current = ""
        } else {
          current += ch.to_string()
        }
      }
      if current.trim() != "" {
        parts.push(current)
      }
      for p = 0; p < parts.length(); p = p + 1 {
        let part = parts[p].trim().to_owned()
        if part.has_prefix("*") {
          let alias_name = str_substring(part, 1, part.length())
            .trim()
            .to_owned()
          match anchors.get(alias_name) {
            Some(YamlMap(merged)) =>
              for k = 0; k < merged.length(); k = k + 1 {
                pairs.push(merged[k])
              }
            _ => () // Ignore non-map or undefined
          }
        }
      }
      i = i + 1
      continue
    }
    // Extract anchor from value: &name [value]
    let (anchor_name, actual_val) = extract_anchor(val_str)
    if actual_val == "" {
      // Nested block
      let mut j = i + 1
      while j < lines.length() && lines[j].trim() == "" {
        j = j + 1
      }
      if j < lines.length() && indent_of(lines[j]) > indent {
        let next = parse_block(lines, j, indent_of(lines[j]), anchors)
        match next {
          None => i = i + 1
          Some((v, ni)) => {
            if anchor_name != "" {
              anchors.set(anchor_name, v)
            }
            pairs.push((key, v))
            i = ni
          }
        }
      } else {
        let v = YamlNull
        if anchor_name != "" {
          anchors.set(anchor_name, v)
        }
        pairs.push((key, v))
        i = i + 1
      }
    } else {
      let v = parse_scalar(actual_val)
      if anchor_name != "" {
        anchors.set(anchor_name, v)
      }
      pairs.push((key, v))
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
  if chars.length() > 0 &&
    chars[chars.length() - 1] == ':' &&
    !in_squote &&
    !in_dquote {
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
  let buf = StringBuilder()
  dump_value(v, 0, buf)
  buf.to_string()
}

///|
fn dump_value(v : YamlValue, indent : Int, buf : StringBuilder) -> Unit {
  match v {
    YamlNull => buf.write("null")
    YamlBool(b) => buf.write(if b { "true" } else { "false" })
    YamlInt(n) => buf.write(n.to_string())
    YamlFloat(f) => buf.write(f.to_string())
    YamlStr(s) => dump_string(s, buf)
    YamlSeq(items) =>
      for i = 0; i < items.length(); i = i + 1 {
        buf.write(String::make(indent, ' '))
        buf.write("- ")
        dump_value_inline(items[i], indent + 2, buf)
        buf.write('\n')
      }
    YamlMap(pairs) =>
      for i = 0; i < pairs.length(); i = i + 1 {
        buf.write(String::make(indent, ' '))
        buf.write(pairs[i].0)
        buf.write(": ")
        dump_value_inline(pairs[i].1, indent + 2, buf)
        buf.write('\n')
      }
  }
}

///|
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

///|
fn dump_string(s : String, buf : StringBuilder) -> Unit {
  // Quote if needed (contains special chars)
  let needs_quote = s == "" ||
    s == "null" ||
    s == "true" ||
    s == "false" ||
    s.contains(": ") ||
    s.contains("#") ||
    s.has_prefix("- ") ||
    s.has_prefix("? ") ||
    s.has_prefix("! ")
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
test "yaml: anchor and alias on scalar" {
  let yaml = "default: &def hello\ngreeting: *def\n"
  let v = parse_yaml(yaml)
  match v {
    Some(YamlMap(pairs)) => {
      assert_eq(pairs.length(), 2)
      match pairs[1].1 {
        YamlStr(s) => assert_eq(s, "hello")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "yaml: anchor and alias on mapping" {
  let yaml = "defaults: &def\n  adapter: postgres\n  host: localhost\ndevelopment:\n  database: dev_db\n  <<: *def\n"
  let v = parse_yaml(yaml)
  match v {
    Some(YamlMap(pairs)) =>
      // pairs[0] = ("defaults", map)
      // pairs[1] = ("development", map with merged entries)
      match pairs[1].1 {
        YamlMap(dev_pairs) => {
          // Should have: database, adapter, host (merged from defaults)
          let mut has_database = false
          let mut has_adapter = false
          let mut has_host = false
          for i = 0; i < dev_pairs.length(); i = i + 1 {
            match dev_pairs[i].0 {
              "database" => has_database = true
              "adapter" => has_adapter = true
              "host" => has_host = true
              _ => ()
            }
          }
          assert_true(has_database)
          assert_true(has_adapter)
          assert_true(has_host)
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "yaml: alias in sequence" {
  let yaml = "first: &a one\nsecond: &b two\nitems:\n  - *a\n  - *b\n  - *a\n"
  let v = parse_yaml(yaml)
  match v {
    Some(YamlMap(pairs)) =>
      match pairs[2].1 {
        YamlSeq(items) => {
          assert_eq(items.length(), 3)
          match items[0] {
            YamlStr(s) => assert_eq(s, "one")
            _ => assert_true(false)
          }
          match items[1] {
            YamlStr(s) => assert_eq(s, "two")
            _ => assert_true(false)
          }
          match items[2] {
            YamlStr(s) => assert_eq(s, "one")
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "yaml: anchor on nested mapping" {
  let yaml = "config: &cfg\n  timeout: 30\n  retries: 3\noverride:\n  <<: *cfg\n  timeout: 60\n"
  let v = parse_yaml(yaml)
  match v {
    Some(YamlMap(pairs)) =>
      match pairs[1].1 {
        YamlMap(merged) => {
          // Should have: timeout (from override), retries (from cfg)
          let mut timeout_val = 0
          let mut has_retries = false
          for i = 0; i < merged.length(); i = i + 1 {
            match merged[i].0 {
              "timeout" =>
                match merged[i].1 {
                  YamlInt(n) => timeout_val = n
                  _ => ()
                }
              "retries" => has_retries = true
              _ => ()
            }
          }
          assert_eq(timeout_val, 60)
          assert_true(has_retries)
        }
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "yaml: undefined alias returns None" {
  let yaml = "value: *undefined_anchor\n"
  let v = parse_yaml(yaml)
  assert_true(v is None)
}

///|
test "yaml: anchor with inline scalar" {
  let yaml = "name: &n Alice\nalias: *n\n"
  let v = parse_yaml(yaml)
  match v {
    Some(YamlMap(pairs)) =>
      match pairs[1].1 {
        YamlStr(s) => assert_eq(s, "Alice")
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "yaml: merge multiple mappings via sequence" {
  let yaml = "base1: &b1\n  a: 1\nbase2: &b2\n  b: 2\ncombined:\n  <<: [*b1, *b2]\n  c: 3\n"
  let v = parse_yaml(yaml)
  match v {
    Some(YamlMap(pairs)) =>
      match pairs[2].1 {
        YamlMap(merged) => {
          let mut has_a = false
          let mut has_b = false
          let mut has_c = false
          for i = 0; i < merged.length(); i = i + 1 {
            match merged[i].0 {
              "a" => has_a = true
              "b" => has_b = true
              "c" => has_c = true
              _ => ()
            }
          }
          assert_true(has_a)
          assert_true(has_b)
          assert_true(has_c)
        }
        _ => assert_true(false)
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
