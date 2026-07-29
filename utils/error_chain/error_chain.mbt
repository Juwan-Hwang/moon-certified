/// Error Chain / Error Context.
///
/// Provides a way to build chains of errors with context, similar to
/// Rust's `anyhow` or Go's error wrapping. Each error in the chain
/// can have a message, source error, and optional key-value context.
///
/// ## Usage
///
/// Start with a root error, then wrap it with additional context as
/// it propagates up the call stack. The full chain can be printed
/// for debugging.
///
/// `proof-enabled` is `false`.

///|
/// A single error in an error chain.
pub struct ChainError {
  message : String
  context : Array[(String, String)]
  source : ChainError?
}

///|
/// Create a new root error.
pub fn new(message : String) -> ChainError {
  { message, context: [], source: None }
}

///|
/// Wrap an existing error with a new message, creating a chain.
pub fn wrap(source : ChainError, message : String) -> ChainError {
  { message, context: [], source: Some(source) }
}

///|
/// Add a key-value context pair to an error.
pub fn with_context(err : ChainError, key : String, value : String) -> ChainError {
  err.context.push((key, value))
  err
}

///|
/// Get the root message (innermost error).
pub fn root_message(err : ChainError) -> String {
  match err.source {
    None => err.message
    Some(src) => root_message(src)
  }
}

///|
/// Get the root error.
pub fn root_error(err : ChainError) -> ChainError {
  match err.source {
    None => err
    Some(src) => root_error(src)
  }
}

///|
/// Get the depth of the error chain (number of wraps).
pub fn depth(err : ChainError) -> Int {
  match err.source {
    None => 1
    Some(src) => 1 + depth(src)
  }
}

///|
/// Format the full error chain as a multi-line string.
pub fn format_chain(err : ChainError) -> String {
  let buf = StringBuilder::new()
  format_chain_impl(err, 0, buf)
  buf.to_string()
}

fn format_chain_impl(err : ChainError, indent : Int, buf : StringBuilder) -> Unit {
  for i = 0; i < indent; i = i + 1 {
    buf.write("  ")
  }
  buf.write("Error: ")
  buf.write(err.message)
  for i = 0; i < err.context.length(); i = i + 1 {
    buf.write(" [")
    buf.write(err.context[i].0)
    buf.write("=")
    buf.write(err.context[i].1)
    buf.write("]")
  }
  buf.write('\n')
  match err.source {
    None => ()
    Some(src) => {
      buf.write("Caused by:\n")
      format_chain_impl(src, indent, buf)
    }
  }
}

///|
/// Collect all messages in the chain (from outermost to innermost).
pub fn messages(err : ChainError) -> Array[String] {
  let result : Array[String] = []
  result.push(err.message)
  match err.source {
    None => ()
    Some(src) => {
      for m in messages(src) {
        result.push(m)
      }
    }
  }
  result
}

///|
/// Check if the error chain contains a given message substring.
pub fn contains_message(err : ChainError, needle : String) -> Bool {
  if err.message.contains(needle) {
    return true
  }
  match err.source {
    None => false
    Some(src) => contains_message(src, needle)
  }
}

///|
/// Find a context value by key anywhere in the chain.
pub fn find_context(err : ChainError, key : String) -> String? {
  for i = 0; i < err.context.length(); i = i + 1 {
    if err.context[i].0 == key {
      return Some(err.context[i].1)
    }
  }
  match err.source {
    None => None
    Some(src) => find_context(src, key)
  }
}

///|
test "error_chain: simple error" {
  let err = new("file not found")
  assert_eq(root_message(err), "file not found")
  assert_eq(depth(err), 1)
}

///|
test "error_chain: wrapped chain" {
  let root = new("connection refused")
  let mid = wrap(root, "failed to connect to database")
  let top = wrap(mid, "unable to initialize app")
  assert_eq(depth(top), 3)
  assert_eq(root_message(top), "connection refused")
  let msgs = messages(top)
  assert_eq(msgs.length(), 3)
  assert_eq(msgs[0], "unable to initialize app")
  assert_eq(msgs[2], "connection refused")
}

///|
test "error_chain: context" {
  let err = new("read error")
  ignore(with_context(err, "file", "/etc/config"))
  ignore(with_context(err, "line", "42"))
  assert_eq(find_context(err, "file"), Some("/etc/config"))
  assert_eq(find_context(err, "line"), Some("42"))
  assert_eq(find_context(err, "missing"), None)
}

///|
test "error_chain: context in chain" {
  let root = new("disk full")
  let top = wrap(root, "write failed")
  ignore(with_context(root, "device", "/dev/sda1"))
  assert_eq(find_context(top, "device"), Some("/dev/sda1"))
}

///|
test "error_chain: contains message" {
  let root = new("timeout")
  let top = wrap(root, "request failed")
  assert_true(contains_message(top, "timeout"))
  assert_true(contains_message(top, "request failed"))
  assert_false(contains_message(top, "missing"))
}

///|
test "error_chain: format" {
  let root = new("EACCES")
  let top = wrap(root, "permission denied")
  let formatted = format_chain(top)
  assert_true(formatted.contains("permission denied"))
  assert_true(formatted.contains("Caused by"))
  assert_true(formatted.contains("EACCES"))
}
