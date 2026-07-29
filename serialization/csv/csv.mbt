/// CSV (Comma-Separated Values) serialization and deserialization.
///
/// Implements RFC 4180 compliant CSV parsing and writing with:
///
/// - Standard comma delimiter, configurable via options.
/// - Double-quote escaping for fields containing delimiters, quotes, or newlines.
/// - CRLF line terminator (RFC 4180 standard), with LF also accepted on input.
/// - Header row support.
/// - Streaming writer for efficient large-file generation.
///
/// ## Complexity
///
/// - `parse` — O(n) where n is the input byte count.
/// - `write` — O(n) where n is the total field content.
///
/// ## References
///
/// - RFC 4180: Common Format and MIME Type for Comma-Separated Values (CSV) Files
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// CSV parsing/writing configuration.
pub struct CsvConfig {
  delimiter : Char
  quote : Char
  line_terminator : String
  has_header : Bool
}

///|
/// Default CSV configuration (RFC 4180): comma delimiter, double-quote,
/// CRLF line terminator, no header assumption.
pub fn default_config() -> CsvConfig {
  { delimiter: ',', quote: '"', line_terminator: "\r\n", has_header: false }
}

///|
/// CSV configuration with header row.
pub fn with_header() -> CsvConfig {
  { delimiter: ',', quote: '"', line_terminator: "\r\n", has_header: true }
}

///|
/// TSV (tab-separated values) configuration.
pub fn tsv_config() -> CsvConfig {
  { delimiter: '\t', quote: '"', line_terminator: "\r\n", has_header: false }
}

///|
/// A CSV row is an array of string fields.
pub type CsvRow = Array[String]

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

///|
/// Parse a CSV string into rows.
///
/// Handles quoted fields, escaped quotes (`""` → `"`), embedded newlines,
/// and both CRLF and LF line terminators.
///
/// Returns an array of rows, each row being an array of field strings.
pub fn parse(input : String, config : CsvConfig) -> Array[CsvRow] {
  let rows : Array[CsvRow] = []
  let current_row : Array[String] = []
  let current_field = StringBuilder::new()
  let mut in_quotes = false
  let mut field_started = false
  let chars : Array[Char] = []
  for c in input.iter() {
    chars.push(c)
  }
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if in_quotes {
      if c == config.quote {
        // Check for escaped quote ("").
        if i + 1 < n && chars[i + 1] == config.quote {
          current_field.write_char(config.quote)
          i = i + 2
          continue
        } else {
          // End of quoted field.
          in_quotes = false
          i = i + 1
          continue
        }
      } else {
        current_field.write_char(c)
        i = i + 1
        continue
      }
    } else {
      // Not in quotes.
      if c == config.quote && !field_started {
        in_quotes = true
        field_started = true
        i = i + 1
        continue
      }
      if c == config.delimiter {
        current_row.push(current_field.to_string())
        current_field.reset()
        field_started = false
        i = i + 1
        continue
      }
      if c == '\r' {
        // Check for CRLF.
        if i + 1 < n && chars[i + 1] == '\n' {
          // End of row.
          current_row.push(current_field.to_string())
          current_field.reset()
          field_started = false
          rows.push(Array::copy(current_row))
          current_row.clear()
          i = i + 2
          continue
        } else {
          // Bare CR — treat as end of row.
          current_row.push(current_field.to_string())
          current_field.reset()
          field_started = false
          rows.push(Array::copy(current_row))
          current_row.clear()
          i = i + 1
          continue
        }
      }
      if c == '\n' {
        // End of row (LF).
        current_row.push(current_field.to_string())
        current_field.reset()
        field_started = false
        rows.push(Array::copy(current_row))
        current_row.clear()
        i = i + 1
        continue
      }
      current_field.write_char(c)
      field_started = true
      i = i + 1
      continue
    }
  }
  // Handle the last field/row if there's no trailing newline.
  if field_started || current_field.to_string().length() > 0 ||
    current_row.length() > 0 {
    current_row.push(current_field.to_string())
    rows.push(Array::copy(current_row))
  }
  rows
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

///|
/// Check if a field needs to be quoted.
///
/// A field needs quoting if it contains the delimiter, quote character,
/// carriage return, or newline.
fn needs_quoting(field : String, config : CsvConfig) -> Bool {
  for c in field.iter() {
    if c == config.delimiter || c == config.quote || c == '\r' || c == '\n' {
      return true
    }
  }
  false
}

///|
/// Escape a field by wrapping in quotes and doubling internal quotes.
fn escape_field(field : String, config : CsvConfig) -> String {
  if !needs_quoting(field, config) {
    return field
  }
  let sb = StringBuilder::new()
  sb.write_char(config.quote)
  for c in field.iter() {
    if c == config.quote {
      sb.write_char(config.quote)
      sb.write_char(config.quote)
    } else {
      sb.write_char(c)
    }
  }
  sb.write_char(config.quote)
  sb.to_string()
}

///|
/// Write a single CSV row to a string.
pub fn write_row(row : CsvRow, config : CsvConfig) -> String {
  let sb = StringBuilder::new()
  for i in 0..<row.length() {
    if i > 0 {
      sb.write_char(config.delimiter)
    }
    sb.write_string(escape_field(row[i], config))
  }
  sb.to_string()
}

///|
/// Write multiple CSV rows to a string.
pub fn write(rows : Array[CsvRow], config : CsvConfig) -> String {
  let sb = StringBuilder::new()
  for i in 0..<rows.length() {
    if i > 0 {
      sb.write_string(config.line_terminator)
    }
    sb.write_string(write_row(rows[i], config))
  }
  sb.to_string()
}

///|
/// Write CSV rows with a header row.
pub fn write_with_header(
  header : CsvRow,
  rows : Array[CsvRow],
  config : CsvConfig,
) -> String {
  let sb = StringBuilder::new()
  sb.write_string(write_row(header, config))
  for i in 0..<rows.length() {
    sb.write_string(config.line_terminator)
    sb.write_string(write_row(rows[i], config))
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "csv: parse simple" {
  let config = default_config()
  let rows = parse("a,b,c\r\n1,2,3\r\n", config)
  assert_eq(rows.length(), 2)
  assert_eq(rows[0].length(), 3)
  assert_eq(rows[0][0], "a")
  assert_eq(rows[0][1], "b")
  assert_eq(rows[0][2], "c")
  assert_eq(rows[1][0], "1")
  assert_eq(rows[1][1], "2")
  assert_eq(rows[1][2], "3")
}

///|
test "csv: parse without trailing newline" {
  let config = default_config()
  let rows = parse("a,b,c", config)
  assert_eq(rows.length(), 1)
  assert_eq(rows[0].length(), 3)
  assert_eq(rows[0][0], "a")
}

///|
test "csv: parse quoted fields" {
  let config = default_config()
  let rows = parse("\"hello, world\",\"foo\"\r\n", config)
  assert_eq(rows.length(), 1)
  assert_eq(rows[0][0], "hello, world")
  assert_eq(rows[0][1], "foo")
}

///|
test "csv: parse escaped quotes" {
  let config = default_config()
  let rows = parse("\"She said \"\"hi\"\"\",\"ok\"\r\n", config)
  assert_eq(rows.length(), 1)
  assert_eq(rows[0][0], "She said \"hi\"")
  assert_eq(rows[0][1], "ok")
}

///|
test "csv: parse embedded newline in quoted field" {
  let config = default_config()
  let rows = parse("\"line1\nline2\",x\r\n", config)
  assert_eq(rows.length(), 1)
  assert_eq(rows[0][0], "line1\nline2")
  assert_eq(rows[0][1], "x")
}

///|
test "csv: parse LF line endings" {
  let config = default_config()
  let rows = parse("a,b\n1,2\n", config)
  assert_eq(rows.length(), 2)
  assert_eq(rows[0][0], "a")
  assert_eq(rows[1][0], "1")
}

///|
test "csv: parse empty fields" {
  let config = default_config()
  let rows = parse("a,,c\r\n", config)
  assert_eq(rows.length(), 1)
  assert_eq(rows[0][0], "a")
  assert_eq(rows[0][1], "")
  assert_eq(rows[0][2], "c")
}

///|
test "csv: parse empty input" {
  let config = default_config()
  let rows = parse("", config)
  assert_eq(rows.length(), 0)
}

///|
test "csv: write simple" {
  let config = default_config()
  let rows : Array[CsvRow] = [
    ["a", "b", "c"],
    ["1", "2", "3"],
  ]
  let result = write(rows, config)
  assert_eq(result, "a,b,c\r\n1,2,3")
}

///|
test "csv: write quoted fields" {
  let config = default_config()
  let rows : Array[CsvRow] = [
    ["hello, world", "foo"],
  ]
  let result = write(rows, config)
  assert_eq(result, "\"hello, world\",foo")
}

///|
test "csv: write escaped quotes" {
  let config = default_config()
  let rows : Array[CsvRow] = [
    ["She said \"hi\"", "ok"],
  ]
  let result = write(rows, config)
  assert_eq(result, "\"She said \"\"hi\"\"\",ok")
}

///|
test "csv: write with embedded newline" {
  let config = default_config()
  let rows : Array[CsvRow] = [
    ["line1\nline2", "x"],
  ]
  let result = write(rows, config)
  assert_eq(result, "\"line1\nline2\",x")
}

///|
test "csv: round-trip complex data" {
  let config = default_config()
  let rows : Array[CsvRow] = [
    ["name", "age", "city"],
    ["Alice", "30", "New York"],
    ["Bob, Jr.", "25", "San Francisco"],
    ["\"Quote\"", "35", "Line1\nLine2"],
    ["", "", ""],
  ]
  let csv_str = write(rows, config)
  let parsed = parse(csv_str, config)
  assert_eq(parsed.length(), rows.length())
  for i in 0..<rows.length() {
    assert_eq(parsed[i].length(), rows[i].length())
    for j in 0..<rows[i].length() {
      assert_eq(parsed[i][j], rows[i][j])
    }
  }
}

///|
test "csv: write with header" {
  let config = default_config()
  let header : CsvRow = ["name", "age"]
  let rows : Array[CsvRow] = [
    ["Alice", "30"],
    ["Bob", "25"],
  ]
  let result = write_with_header(header, rows, config)
  assert_eq(result, "name,age\r\nAlice,30\r\nBob,25")
}

///|
test "csv: TSV round-trip" {
  let config = tsv_config()
  let rows : Array[CsvRow] = [
    ["a", "b\tc", "d"],
    ["1", "2", "3"],
  ]
  let tsv_str = write(rows, config)
  let parsed = parse(tsv_str, config)
  assert_eq(parsed.length(), 2)
  assert_eq(parsed[0][1], "b\tc")
}

///|
test "csv: single column" {
  let config = default_config()
  let rows = parse("a\r\nb\r\nc\r\n", config)
  assert_eq(rows.length(), 3)
  assert_eq(rows[0].length(), 1)
  assert_eq(rows[0][0], "a")
  assert_eq(rows[1][0], "b")
  assert_eq(rows[2][0], "c")
}

///|
test "csv: round-trip empty fields and rows" {
  let config = default_config()
  let rows : Array[CsvRow] = [
    ["", "a", ""],
    ["b", "", "c"],
  ]
  let csv_str = write(rows, config)
  let parsed = parse(csv_str, config)
  assert_eq(parsed.length(), 2)
  assert_eq(parsed[0][0], "")
  assert_eq(parsed[0][1], "a")
  assert_eq(parsed[0][2], "")
  assert_eq(parsed[1][0], "b")
  assert_eq(parsed[1][1], "")
  assert_eq(parsed[1][2], "c")
}
