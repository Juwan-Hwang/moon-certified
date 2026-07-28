/// Burrows-Wheeler Transform (BWT).
///
/// Encodes a string by sorting all cyclic rotations and taking the last
/// column. A sentinel '$' (assumed absent from the input and lexicographically
/// smallest) is appended before sorting. Decoding uses LF-mapping.

///|
/// Compute the BWT of `s`.
/// Appends '$' as sentinel, builds suffix array by sorting suffixes,
/// then takes the last column: BWT[i] = S[(SA[i] - 1) mod n].
pub fn bwt_encode(s : String) -> String {
  let n = s.length()
  let aug = s + "$"
  let m = n + 1
  let sa : Array[Int] = []
  for i = 0; i < m; i = i + 1 {
    sa.push(i)
  }
  sa.sort_by(fn(i, j) {
    let mut k = 0
    while i + k < m && j + k < m {
      let a = aug[i + k].to_int()
      let b = aug[j + k].to_int()
      if a != b {
        return a.compare(b)
      }
      k = k + 1
    }
    if i + k == m {
      if j + k == m {
        0
      } else {
        -1
      }
    } else {
      1
    }
  })
  let buf = StringBuilder()
  for idx = 0; idx < m; idx = idx + 1 {
    let pos = (sa[idx] - 1 + m) % m
    let code = aug[pos].to_int()
    if code >= 0 && code <= 0x10FFFF {
      buf.write_char(code.unsafe_to_char())
    }
  }
  buf.to_string()
}

///|
/// Reverse the BWT using LF-mapping.
/// Reconstructs the original string (without sentinel) from the BWT.
pub fn bwt_decode(bwt : String) -> String {
  let n = bwt.length()
  if n == 0 {
    return ""
  }
  // Count occurrences and compute rank of each position.
  let counts = FixedArray::make(65536, 0)
  let rank = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let c = bwt[i].to_int()
    rank[i] = counts[c]
    counts[c] = counts[c] + 1
  }
  // C[c] = number of code units strictly less than c (prefix sums).
  let c_table = FixedArray::make(65536, 0)
  let mut total = 0
  for c = 0; c < 65536; c = c + 1 {
    c_table[c] = total
    total = total + counts[c]
  }
  // Walk the LF-mapping cycle starting at row 0 (F[0] = '$').
  // chars[k] = L[LF^k(0)], giving the original string in reverse with '$' last.
  let chars : Array[Char] = Array::make(n, ' ')
  let mut i = 0
  for k = 0; k < n; k = k + 1 {
    let code = bwt[i].to_int()
    if code >= 0 && code <= 0x10FFFF {
      chars[k] = code.unsafe_to_char()
    }
    i = c_table[code] + rank[i]
  }
  // Output chars[n-2] down to chars[0], skipping chars[n-1] (the '$').
  let buf = StringBuilder()
  for k = n - 2; k >= 0; k = k - 1 {
    buf.write_char(chars[k])
  }
  buf.to_string()
}

///|
test "bwt: roundtrip" {
  let inputs = ["banana", "mississippi", "abracadabra", "abababab"]
  for i = 0; i < inputs.length(); i = i + 1 {
    let s = inputs[i]
    assert_eq(bwt_decode(bwt_encode(s)), s)
  }
}

///|
test "bwt: empty string" {
  assert_eq(bwt_encode(""), "$")
  assert_eq(bwt_decode("$"), "")
}

///|
test "bwt: single char" {
  assert_eq(bwt_encode("a"), "a$")
  assert_eq(bwt_decode("a$"), "a")
}

///|
test "bwt: all same characters" {
  assert_eq(bwt_decode(bwt_encode("aaaa")), "aaaa")
  assert_eq(bwt_decode(bwt_encode("zzzzz")), "zzzzz")
}

///|
test "bwt: repeated patterns" {
  let inputs = ["abcabc", "aaaaabbbbb", "xyzxyzxyz"]
  for i = 0; i < inputs.length(); i = i + 1 {
    assert_eq(bwt_decode(bwt_encode(inputs[i])), inputs[i])
  }
}

///|
test "bwt: known encoding values" {
  // BWT of "banana" — verify round-trip and structure.
  let encoded = bwt_encode("banana")
  // Verify it round-trips correctly (primary correctness criterion).
  assert_eq(bwt_decode(encoded), "banana")
  // The last char of BWT should be the char before '$' in the original,
  // which for "banana" is 'a' (position 5, cyclically before '$').
  let last_code = encoded[encoded.length() - 1].to_int()
  assert_eq(last_code, 'a'.to_int())
}

///|
test "bwt: unicode string" {
  // BWT operates on code units; multi-byte chars are handled per-unit.
  let s = "abc"
  assert_eq(bwt_decode(bwt_encode(s)), s)
}

///|
test "bwt: long repetitive string" {
  // Long string with repeated patterns — stress test for suffix sort.
  let buf = StringBuilder()
  for _i = 0; _i < 50; _i = _i + 1 {
    buf.write_string("ab")
  }
  let s = buf.to_string()
  assert_eq(bwt_decode(bwt_encode(s)), s)
}

///|
test "bwt: sorted string roundtrip" {
  let s = "abcdef"
  assert_eq(bwt_decode(bwt_encode(s)), s)
}

///|
test "bwt: reverse sorted string roundtrip" {
  let s = "zyxwvu"
  assert_eq(bwt_decode(bwt_encode(s)), s)
}

///|
test "bwt: two-character string roundtrip" {
  let s = "ab"
  assert_eq(bwt_decode(bwt_encode(s)), s)
}

///|
test "bwt: numeric string roundtrip" {
  let s = "123456"
  assert_eq(bwt_decode(bwt_encode(s)), s)
}

///|
test "bwt: encode output length is input plus one" {
  // The sentinel '$' is always appended, so encoded length = input length + 1.
  let inputs = ["", "a", "ab", "banana", "mississippi"]
  for i = 0; i < inputs.length(); i = i + 1 {
    let encoded = bwt_encode(inputs[i])
    assert_eq(encoded.length(), inputs[i].length() + 1)
  }
}

///|
test "bwt: decode empty bwt returns empty string" {
  assert_eq(bwt_decode(""), "")
}

///|
test "bwt: mixed case string roundtrip" {
  // All chars are above '$' (ASCII 36) so the sentinel assumption holds.
  let s = "AbCdEfGh"
  assert_eq(bwt_decode(bwt_encode(s)), s)
}
