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
    buf.write_char(aug[pos].to_int().unsafe_to_char())
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
    chars[k] = bwt[i].to_int().unsafe_to_char()
    i = c_table[bwt[i].to_int()] + rank[i]
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
