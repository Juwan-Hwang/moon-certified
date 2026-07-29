/// Structured Logging.
///
/// Provides structured (key-value) logging with log levels, timestamps,
/// and structured fields. Output is human-readable by default and
/// can be formatted as JSON for machine consumption.
///
/// ## Log Levels
///
/// - TRACE: finest granularity
/// - DEBUG: debugging information
/// - INFO: general information
/// - WARN: warning messages
/// - ERROR: error messages
///
/// `proof-enabled` is `false`.

///|
/// Log level enumeration.
pub enum LogLevel {
  Trace
  Debug
  Info
  Warn
  Error
}

///|
/// Convert log level to string.
fn level_to_string(level : LogLevel) -> String {
  match level {
    Trace => "TRACE"
    Debug => "DEBUG"
    Info => "INFO "
    Warn => "WARN "
    Error => "ERROR"
  }
}

///|
/// Get numeric priority of a log level (higher = more important).
fn level_priority(level : LogLevel) -> Int {
  match level {
    Trace => 0
    Debug => 1
    Info => 2
    Warn => 3
    Error => 4
  }
}

///|
/// A structured log field.
pub struct LogField {
  key : String
  value : String
}

///|
/// Create a string log field.
pub fn field(key : String, value : String) -> LogField {
  { key, value }
}

///|
/// Create an int log field.
pub fn int_field(key : String, value : Int) -> LogField {
  { key, value: value.to_string() }
}

///|
/// Create a double log field.
pub fn double_field(key : String, value : Double) -> LogField {
  { key, value: value.to_string() }
}

///|
/// Create a bool log field.
pub fn bool_field(key : String, value : Bool) -> LogField {
  { key, value: if value { "true" } else { "false" } }
}

///|
/// A structured logger with configurable minimum level.
pub struct Logger {
  mut min_level : LogLevel
  fields : Array[LogField]
  use_json : Bool
}

///|
/// Create a new logger with default settings (INFO level, text format).
pub fn new() -> Logger {
  { min_level: Info, fields: [], use_json: false }
}

///|
/// Create a new logger with a specific minimum level.
pub fn with_level(level : LogLevel) -> Logger {
  { min_level: level, fields: [], use_json: false }
}

///|
/// Create a new JSON-format logger.
pub fn json_logger(level : LogLevel) -> Logger {
  { min_level: level, fields: [], use_json: true }
}

///|
/// Set the minimum log level.
pub fn set_level(logger : Logger, level : LogLevel) -> Unit {
  logger.min_level = level
}

///|
/// Add a persistent field to the logger (included in all log messages).
pub fn with_field(logger : Logger, f : LogField) -> Unit {
  logger.fields.push(f)
}

///|
/// Check if a log level would be emitted.
pub fn enabled(logger : Logger, level : LogLevel) -> Bool {
  level_priority(level) >= level_priority(logger.min_level)
}

///|
/// Format a log message as a human-readable string.
fn format_text(level : LogLevel, msg : String, fields : Array[LogField]) -> String {
  let buf = StringBuilder::new()
  buf.write(level_to_string(level))
  buf.write(" | ")
  buf.write(msg)
  for i = 0; i < fields.length(); i = i + 1 {
    buf.write(" ")
    buf.write(fields[i].key)
    buf.write("=")
    buf.write(fields[i].value)
  }
  buf.to_string()
}

///|
/// Format a log message as JSON.
fn format_json(level : LogLevel, msg : String, fields : Array[LogField]) -> String {
  let buf = StringBuilder::new()
  buf.write("{\"level\":\"")
  buf.write(level_to_string(level).trim())
  buf.write("\",\"message\":\"")
  buf.write(escape_json(msg))
  buf.write("\"")
  for i = 0; i < fields.length(); i = i + 1 {
    buf.write(",\"")
    buf.write(fields[i].key)
    buf.write("\":\"")
    buf.write(escape_json(fields[i].value))
    buf.write("\"")
  }
  buf.write("}")
  buf.to_string()
}

///|
/// Escape a string for JSON output.
fn escape_json(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '"' => { buf.write("\\"); buf.write("\"") }
      '\\' => { buf.write("\\"); buf.write("\\") }
      '\n' => { buf.write("\\"); buf.write("n") }
      '\t' => { buf.write("\\"); buf.write("t") }
      '\r' => { buf.write("\\"); buf.write("r") }
      _ => buf.write_char(ch)
    }
  }
  buf.to_string()
}

///|
/// Log a message at the given level with additional fields.
pub fn log(
  logger : Logger,
  level : LogLevel,
  msg : String,
  extra_fields : Array[LogField],
) -> String? {
  if !enabled(logger, level) {
    return None
  }
  // Combine persistent fields with extra fields
  let all_fields : Array[LogField] = []
  for i = 0; i < logger.fields.length(); i = i + 1 {
    all_fields.push(logger.fields[i])
  }
  for i = 0; i < extra_fields.length(); i = i + 1 {
    all_fields.push(extra_fields[i])
  }
  let formatted = if logger.use_json {
    format_json(level, msg, all_fields)
  } else {
    format_text(level, msg, all_fields)
  }
  Some(formatted)
}

///|
/// Log an info message.
pub fn info(logger : Logger, msg : String) -> String? {
  log(logger, Info, msg, [])
}

///|
/// Log a warning message.
pub fn warn(logger : Logger, msg : String) -> String? {
  log(logger, Warn, msg, [])
}

///|
/// Log an error message.
pub fn error(logger : Logger, msg : String) -> String? {
  log(logger, Error, msg, [])
}

///|
/// Log a debug message.
pub fn debug(logger : Logger, msg : String) -> String? {
  log(logger, Debug, msg, [])
}

///|
/// Log a trace message.
pub fn trace(logger : Logger, msg : String) -> String? {
  log(logger, Trace, msg, [])
}

///|
test "structured_logging: info message" {
  let logger = new()
  match info(logger, "Server started") {
    Some(s) => assert_true(s.contains("INFO") && s.contains("Server started"))
    None => assert_true(false)
  }
}

///|
test "structured_logging: level filtering" {
  let logger = with_level(Warn)
  assert_eq(info(logger, "should be filtered"), None)
  assert_true(warn(logger, "should pass") is Some(_))
  assert_true(error(logger, "should pass") is Some(_))
}

///|
test "structured_logging: fields in message" {
  let logger = new()
  match log(logger, Info, "Request received", [field("method", "GET"), int_field("status", 200)]) {
    Some(s) => {
      assert_true(s.contains("method=GET"))
      assert_true(s.contains("status=200"))
    }
    None => assert_true(false)
  }
}

///|
test "structured_logging: JSON format" {
  let logger = json_logger(Info)
  match info(logger, "test message") {
    Some(s) => {
      assert_true(s.has_prefix("{"))
      assert_true(s.contains("\"message\""))
      assert_true(s.contains("test message"))
    }
    None => assert_true(false)
  }
}

///|
test "structured_logging: persistent fields" {
  let logger = new()
  with_field(logger, field("service", "api"))
  match info(logger, "running") {
    Some(s) => assert_true(s.contains("service=api"))
    None => assert_true(false)
  }
}
