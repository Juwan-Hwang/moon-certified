/// Rope — Efficient String Data Structure.
///
/// A rope is a binary tree of string fragments, providing O(log n)
/// concatenation, split, and indexing — far better than O(n) string
/// concatenation for large texts. Used in text editors (VS Code, Emacs),
/// CRDTs, and document processing.
///
/// ## Complexity
/// | Operation   | String | Rope   |
/// |-------------|--------|--------|
/// | concat      | O(n)   | O(1)   |
/// | index       | O(1)   | O(log n)|
/// | split       | O(n)   | O(log n)|
/// | insert      | O(n)   | O(log n)|
/// | delete      | O(n)   | O(log n)|
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// A rope node.
pub struct Rope {
  priv is_leaf : Bool
  priv val : String
  priv left : Rope?
  priv right : Rope?
  priv len : Int
  priv cached_depth : Int
}

/// Create a rope from a string.
pub fn rope_leaf(s : String) -> Rope {
  { is_leaf: true, val: s, left: None, right: None, len: s.length(), cached_depth: 1 }
}

/// Concatenate two ropes in O(1).
pub fn rope_concat(a : Rope, b : Rope) -> Rope {
  {
    is_leaf: false,
    val: "",
    left: Some(a),
    right: Some(b),
    len: a.len + b.len,
    cached_depth: max_depth(a) + 1,
  }
}

fn max_depth(r : Rope) -> Int {
  r.cached_depth
}

/// Length of the rope. O(1).
pub fn rope_len(r : Rope) -> Int {
  r.len
}

/// Get the character at index `i`. O(log n).
pub fn rope_index(r : Rope, i : Int) -> Char? {
  if i < 0 || i >= r.len {
    return None
  }
  if r.is_leaf {
    return Some(r.val.unsafe_get(i).to_int().to_char().unwrap())
  }
  match r.left {
    Some(l) =>
      if i < l.len {
        rope_index(l, i)
      } else {
        match r.right {
          Some(rt) => rope_index(rt, i - l.len)
          None => None
        }
      }
    None => None
  }
}

/// Convert the rope to a string. O(n).
pub fn rope_to_string(r : Rope) -> String {
  if r.is_leaf {
    return r.val
  }
  let buf = StringBuilder::new()
  rope_to_string_helper(r, buf)
  buf.to_string()
}

fn rope_to_string_helper(r : Rope, buf : StringBuilder) -> Unit {
  if r.is_leaf {
    buf.write_string(r.val)
    return
  }
  match r.left {
    Some(l) => rope_to_string_helper(l, buf)
    None => ()
  }
  match r.right {
    Some(rt) => rope_to_string_helper(rt, buf)
    None => ()
  }
}

/// Split the rope at index `i`, returning (left, right).
/// O(log n).
pub fn rope_split(r : Rope, i : Int) -> (Rope, Rope) {
  if i <= 0 {
    return (rope_leaf(""), r)
  }
  if i >= r.len {
    return (r, rope_leaf(""))
  }
  if r.is_leaf {
    return (rope_leaf(r.val[0:i].to_owned()), rope_leaf(r.val[i:r.val.length()].to_owned()))
  }
  let left_len = match r.left {
    Some(l) => l.len
    None => 0
  }
  if i < left_len {
    match r.left {
      Some(l) => {
        let (ll, lr) = rope_split(l, i)
        match r.right {
          Some(rt) => (ll, rope_concat(lr, rt))
          None => (ll, lr)
        }
      }
      None => (rope_leaf(""), r)
    }
  } else {
    match r.right {
      Some(rt) => {
        let (rl, rr) = rope_split(rt, i - left_len)
        match r.left {
          Some(l) => (rope_concat(l, rl), rr)
          None => (rl, rr)
        }
      }
      None => (r, rope_leaf(""))
    }
  }
}

/// Insert a string at position `i`. O(log n).
pub fn rope_insert(r : Rope, i : Int, s : String) -> Rope {
  let (left, right) = rope_split(r, i)
  rope_concat(rope_concat(left, rope_leaf(s)), right)
}

/// Delete the range [start, end). O(log n).
pub fn rope_delete(r : Rope, start : Int, end : Int) -> Rope {
  let (left, mid) = rope_split(r, start)
  let (_, right) = rope_split(mid, end - start)
  rope_concat(left, right)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "rope: basic leaf" {
  let r = rope_leaf("hello")
  assert_eq(rope_len(r), 5)
  assert_eq(rope_index(r, 0), Some('h'))
  assert_eq(rope_index(r, 4), Some('o'))
  assert_eq(rope_to_string(r), "hello")
}

test "rope: concat" {
  let a = rope_leaf("hello ")
  let b = rope_leaf("world")
  let r = rope_concat(a, b)
  assert_eq(rope_len(r), 11)
  assert_eq(rope_to_string(r), "hello world")
  assert_eq(rope_index(r, 5), Some(' '))
  assert_eq(rope_index(r, 10), Some('d'))
}

test "rope: index across boundary" {
  let a = rope_leaf("abc")
  let b = rope_leaf("def")
  let r = rope_concat(a, b)
  for i = 0; i < 6; i = i + 1 {
    assert_true(rope_index(r, i) != None)
  }
  assert_eq(rope_index(r, 2), Some('c'))
  assert_eq(rope_index(r, 3), Some('d'))
}

test "rope: split" {
  let r = rope_concat(rope_leaf("hello"), rope_leaf("world"))
  let (l, right) = rope_split(r, 3)
  assert_eq(rope_to_string(l), "hel")
  assert_eq(rope_to_string(right), "loworld")
}

test "rope: insert" {
  let r = rope_leaf("helloworld")
  let r2 = rope_insert(r, 5, " ")
  assert_eq(rope_to_string(r2), "hello world")
}

test "rope: delete" {
  let r = rope_leaf("hello world")
  let r2 = rope_delete(r, 5, 6)
  assert_eq(rope_to_string(r2), "helloworld")
}

test "rope: large concatenation" {
  let parts = ["The", " ", "quick", " ", "brown", " ", "fox"]
  let mut r = rope_leaf("")
  for i = 0; i < parts.length(); i = i + 1 {
    r = rope_concat(r, rope_leaf(parts[i]))
  }
  assert_eq(rope_to_string(r), "The quick brown fox")
}

test "rope: out of bounds" {
  let r = rope_leaf("abc")
  assert_eq(rope_index(r, -1), None)
  assert_eq(rope_index(r, 3), None)
}

test "rope: nested concat" {
  let r = rope_concat(
    rope_concat(rope_leaf("a"), rope_leaf("b")),
    rope_concat(rope_leaf("c"), rope_leaf("d")),
  )
  assert_eq(rope_to_string(r), "abcd")
  assert_eq(rope_index(r, 0), Some('a'))
  assert_eq(rope_index(r, 3), Some('d'))
}
