/// Pohlig-Hellman discrete logarithm.
///
/// Solves g^x = h (mod p) for x, where p is prime. Returns Some(x) or None
/// when no solution exists. Factors p-1, solves in each prime-power subgroup
/// via Pohlig-Hellman lifting, then combines partial results via CRT.
/// Uses Int64 internally to avoid overflow (p^2 < 2^62 < 2^63).

fn mod64(a : Int64, m : Int64) -> Int64 {
  let r = a % m
  if r < 0L { r + m } else { r }
}

fn pow_mod(base : Int64, exp : Int64, m : Int64) -> Int64 {
  let mut result = 1L
  let mut b = mod64(base, m)
  let mut e = exp
  while e > 0L {
    if e % 2L == 1L { result = result * b % m }
    e = e / 2L
    b = b * b % m
  }
  result
}

fn mod_inv(a : Int64, m : Int64) -> Int64 {
  let mut old_r = a
  let mut r = m
  let mut old_s = 1L
  let mut s = 0L
  while r != 0L {
    let q = old_r / r
    let t = old_r - q * r
    old_r = r
    r = t
    let u = old_s - q * s
    old_s = s
    s = u
  }
  mod64(old_s, m)
}

fn factorize_pe(n : Int) -> Array[(Int, Int)] {  // trial division
  let result : Array[(Int, Int)] = []
  let mut m = n
  let mut d = 2
  while d * d <= m {
    if m % d == 0 {
      let mut e = 0
      while m % d == 0 {
        m = m / d
        e = e + 1
      }
      result.push((d, e))
    }
    d = d + 1
  }
  if m > 1 { result.push((m, 1)) }
  result
}

pub fn pohlig_hellman(g : Int, h : Int, p : Int) -> Int? {
  if p <= 0 { return None }
  if p == 1 { return Some(0) }
  let p64 = p.to_int64()
  let g64 = mod64(g.to_int64(), p64)
  let h64 = mod64(h.to_int64(), p64)
  if h64 == 1L { return Some(0) }
  if g64 == 0L { return None }
  let order = p - 1
  let factors = factorize_pe(order)
  let mut result = 0L
  let mut modulus = 1L
  for i = 0; i < factors.length(); i = i + 1 {
    let (q, e) = factors[i]
    let q64 = q.to_int64()
    let q_pows : Array[Int64] = [1L]
    for j = 0; j < e; j = j + 1 { q_pows.push(q_pows[j] * q64) }
    let qe = q_pows[e]
    let g_q = pow_mod(g64, order.to_int64() / qe, p64)
    let gamma = pow_mod(g64, order.to_int64() / q64, p64)
    let h_q = pow_mod(h64, order.to_int64() / qe, p64)
    let g_q_inv = mod_inv(g_q, p64)
    let mut x_q = 0L
    let mut h_cur = h_q
    for k = 0; k < e; k = k + 1 {
      let h_k = pow_mod(h_cur, q_pows[e - 1 - k], p64)
      let mut d_k = -1L
      let mut g_pow = 1L
      for dj = 0; dj < q && d_k < 0L; dj = dj + 1 {
        if g_pow == h_k { d_k = dj.to_int64() }
        g_pow = g_pow * gamma % p64
      }
      if d_k < 0L { return None }
      x_q = x_q + d_k * q_pows[k]
      h_cur = h_cur * pow_mod(g_q_inv, d_k * q_pows[k], p64) % p64
    }
    let inv = mod_inv(modulus, qe)
    result = mod64(result + modulus * mod64((x_q - result) * inv, qe), modulus * qe)
    modulus = modulus * qe
  }
  if pow_mod(g64, result, p64) != h64 { return None }
  Some(result.to_int())
}

test "pohlig_hellman: basic discrete log" {
  // 2^3 = 8 = 3 (mod 5), so x = 3.
  assert_eq(pohlig_hellman(2, 3, 5), Some(3))
}

test "pohlig_hellman: generator test" {
  // 3 is a primitive root mod 7; 3^3 = 27 = 6 (mod 7).
  assert_eq(pohlig_hellman(3, 6, 7), Some(3))
}

test "pohlig_hellman: no solution" {
  // 2 generates {1,2,4} mod 7; 3 is not in the subgroup.
  assert_true(pohlig_hellman(2, 3, 7) is None)
}
