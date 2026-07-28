///|
/// Cipolla's algorithm for modular square root.
///
/// Finds x with x^2 = n (mod p) for an odd prime p. Returns Some(x) (where
/// both x and p-x are valid roots) or None when n is a quadratic non-residue.
///
/// **Algorithm.** Find a with a^2-n a quadratic non-residue, set w^2 = a^2-n,
/// and compute (a+w)^((p+1)/2) in F_p[w]/(w^2-(a^2-n)); the real part is sqrt(n).
///
/// All arithmetic uses Int64 internally to avoid overflow (p^2 < 2^62 < 2^63).
fn mod64(a : Int64, m : Int64) -> Int64 {
  let r = a % m
  if r < 0L {
    r + m
  } else {
    r
  }
}

///|
fn pow_mod(base : Int64, exp : Int64, m : Int64) -> Int64 {
  let mut result = 1L
  let mut b = mod64(base, m)
  let mut e = exp
  while e > 0L {
    if e % 2L == 1L {
      result = result * b % m
    }
    e = e / 2L
    b = b * b % m
  }
  result
}

///|
/// Multiply (x1+y1*w)(x2+y2*w) in F_p[w]/(w^2-w2), returning (real, omega).
fn mul_fp2(
  x1 : Int64,
  y1 : Int64,
  x2 : Int64,
  y2 : Int64,
  w2 : Int64,
  p : Int64,
) -> (Int64, Int64) {
  let x = (x1 * x2 % p + y1 * y2 % p * w2 % p) % p
  let y = (x1 * y2 % p + x2 * y1 % p) % p
  (mod64(x, p), mod64(y, p))
}

///|
pub fn cipolla(n : Int, p : Int) -> Int? {
  let p64 = p.to_int64()
  let n64 = mod64(n.to_int64(), p64)
  if n64 == 0L {
    return Some(0)
  }
  if p == 2 {
    return Some(n64.to_int())
  }
  // Euler's criterion: n is a QR iff n^((p-1)/2) = 1 (mod p).
  if pow_mod(n64, (p64 - 1L) / 2L, p64) != 1L {
    return None
  }
  // Find a with a^2-n a quadratic non-residue.
  let mut a = 0L
  let mut w2 = 0L
  for ai = 0L; ai < p64; ai = ai + 1L {
    let w = mod64(ai * ai - n64, p64)
    if pow_mod(w, (p64 - 1L) / 2L, p64) == p64 - 1L {
      a = ai
      w2 = w
      break
    }
  }
  // Compute (a+w)^((p+1)/2) via binary exponentiation in F_p^2.
  let exp = (p64 + 1L) / 2L
  let mut rx = 1L // result: 1 + 0w
  let mut ry = 0L
  let mut bx = a // base: a + 1w
  let mut by = 1L
  let mut e = exp
  while e > 0L {
    if e % 2L == 1L {
      let (nx, ny) = mul_fp2(rx, ry, bx, by, w2, p64)
      rx = nx
      ry = ny
    }
    e = e / 2L
    let (nx, ny) = mul_fp2(bx, by, bx, by, w2, p64)
    bx = nx
    by = ny
  }
  Some(mod64(rx, p64).to_int())
}

///|
test "cipolla: n=2, p=7 (solution 3 or 4)" {
  let r = cipolla(2, 7)
  assert_true(r is Some(_))
  match r {
    Some(x) => assert_eq(x * x % 7, 2)
    None => ()
  }
}

///|
test "cipolla: n=1, p=7" {
  let r = cipolla(1, 7)
  assert_true(r is Some(_))
  match r {
    Some(x) => assert_eq(x * x % 7, 1)
    None => ()
  }
}

///|
test "cipolla: n=3, p=7 (no solution)" {
  assert_true(cipolla(3, 7) is None)
}

///|
test "cipolla: n=0, p=11 (trivial root)" {
  assert_eq(cipolla(0, 11), Some(0))
}

///|
test "cipolla: n=1, p=2 (p=2 special case)" {
  let r = cipolla(1, 2)
  assert_eq(r, Some(1))
}

///|
test "cipolla: large prime p=1000000007" {
  // 4 is a perfect square mod any odd prime.
  let r = cipolla(4, 1000000007)
  assert_true(r is Some(_))
  match r {
    Some(x) => assert_eq(x * x % 1000000007, 4)
    None => ()
  }
}

///|
test "cipolla: multiple QRs mod 11" {
  // Quadratic residues mod 11: 1, 3, 4, 5, 9
  for n in [1, 3, 4, 5, 9] {
    let r = cipolla(n, 11)
    assert_true(r is Some(_))
    match r {
      Some(x) => assert_eq(x * x % 11, n)
      None => ()
    }
  }
}

///|
test "cipolla: non-residues mod 11" {
  // Quadratic non-residues mod 11: 2, 6, 7, 8, 10
  for n in [2, 6, 7, 8, 10] {
    assert_true(cipolla(n, 11) is None)
  }
}

///|
test "cipolla: p=13 comprehensive" {
  // Check all n in [0, 13) and verify x^2 = n (mod 13) or None.
  let qr = [0, 1, 3, 4, 9, 10, 12]
  for n in 0..<13 {
    let r = cipolla(n, 13)
    let is_qr = qr.contains(n)
    assert_true((r is Some(_)) == is_qr)
    match r {
      Some(x) => assert_eq(x * x % 13, n)
      None => ()
    }
  }
}

///|
test "cipolla: p=17 all residues" {
  // Quadratic residues mod 17: 0,1,2,4,8,9,13,15,16
  let qr = [0, 1, 2, 4, 8, 9, 13, 15, 16]
  for n in 0..<17 {
    let r = cipolla(n, 17)
    let is_qr = qr.contains(n)
    assert_true((r is Some(_)) == is_qr)
    match r {
      Some(x) => assert_eq(x * x % 17, n)
      None => ()
    }
  }
}

///|
test "cipolla: negative n handled via modular reduction" {
  // n = -1 mod 5 = 4, which is a QR (2^2 = 4 mod 5).
  let r = cipolla(-1, 5)
  assert_true(r is Some(_))
  match r {
    Some(x) => assert_eq(x * x % 5, 4)
    None => ()
  }
}

///|
test "cipolla: n >= p wraps correctly" {
  // n = 10 mod 7 = 3, which is a QNR mod 7.
  assert_true(cipolla(10, 7) is None)
  // n = 8 mod 7 = 1, which is a QR mod 7.
  let r = cipolla(8, 7)
  assert_true(r is Some(_))
  match r {
    Some(x) => assert_eq(x * x % 7, 1)
    None => ()
  }
}

///|
test "cipolla: p=3 smallest odd prime" {
  // QRs mod 3: 0 (0^2), 1 (1^2, 2^2=4 mod 3=1). n=2 is QNR.
  assert_eq(cipolla(0, 3), Some(0))
  let r1 = cipolla(1, 3)
  assert_true(r1 is Some(_))
  match r1 {
    Some(x) => assert_eq(x * x % 3, 1)
    None => ()
  }
  assert_true(cipolla(2, 3) is None)
}

///|
test "cipolla: p=5 all residues" {
  // QRs mod 5: 0, 1, 4. QNRs: 2, 3.
  let qr = [0, 1, 4]
  for n in 0..<5 {
    let r = cipolla(n, 5)
    let is_qr = qr.contains(n)
    assert_true((r is Some(_)) == is_qr)
    match r {
      Some(x) => assert_eq(x * x % 5, n)
      None => ()
    }
  }
}

///|
test "cipolla: returned root is in range [0, p)" {
  let cases = [(2, 7), (1, 11), (4, 13), (9, 17), (4, 1000000007)]
  for i = 0; i < cases.length(); i = i + 1 {
    let (n, p) = cases[i]
    let r = cipolla(n, p)
    assert_true(r is Some(_))
    match r {
      Some(x) => {
        assert_true(x >= 0)
        assert_true(x < p)
        assert_eq(x * x % p, n)
      }
      None => ()
    }
  }
}

///|
test "cipolla: both roots x and p-x are valid" {
  let cases = [(4, 11), (9, 13), (2, 17), (5, 11)]
  for i = 0; i < cases.length(); i = i + 1 {
    let (n, p) = cases[i]
    let r = cipolla(n, p)
    assert_true(r is Some(_))
    match r {
      Some(x) => {
        assert_eq(x * x % p, n)
        let other = p - x
        assert_eq(other * other % p, n)
      }
      None => ()
    }
  }
}

///|
test "cipolla: Euler's criterion for n = p-1 (=-1 mod p)" {
  // -1 is a QR mod p iff p = 1 (mod 4).
  // p=5: 5 = 1 (mod 4), -1 = 4 is QR.
  assert_true(cipolla(4, 5) is Some(_))
  // p=7: 7 = 3 (mod 4), -1 = 6 is QNR.
  assert_true(cipolla(6, 7) is None)
  // p=13: 13 = 1 (mod 4), -1 = 12 is QR.
  assert_true(cipolla(12, 13) is Some(_))
  // p=3: 3 = 3 (mod 4), -1 = 2 is QNR.
  assert_true(cipolla(2, 3) is None)
}
