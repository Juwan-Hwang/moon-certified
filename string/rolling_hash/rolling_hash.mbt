/// Rolling hash with dual moduli for collision-resistant string hashing.
///
/// This module implements a **double-modulus polynomial rolling hash** that
/// computes forward and reverse hashes of a string in O(n) preprocessing
/// time, enabling O(1) substring hash queries.
///
/// By using **two independent prime moduli** (1e9+7 and 1e9+9), the collision
/// probability is reduced to approximately 1/(1e18), which is effectively
/// zero for practical purposes. Single-modulus hashes have a collision
/// probability of ~1/modulus per comparison, which is too high for adversarial
/// inputs or large-scale deduplication.
///
/// ## Features
///
/// - **Forward hash**: standard left-to-right polynomial hash
/// - **Reverse hash**: right-to-left hash for palindrome detection
/// - **Substring query**: O(1) hash of any substring [l, r)
/// - **Palindrome check**: O(1) using forward + reverse hashes
/// - **Pattern matching**: find all occurrences of a pattern in O(n+m)
/// - **Equality check**: compare two substrings in O(1)
///
/// ## Hash function
///
/// `hash(s[l..r)) = (s[l]*B^(r-l-1) + s[l+1]*B^(r-l-2) + ... + s[r-1]) mod M`
///
/// where `B` is the base (91138233) and `M` is one of the two primes.
///
/// ## Complexity
///
/// - Construction: O(n)
/// - `substring_hash`: O(1)
/// - `is_palindrome`: O(1)
/// - `equals`: O(1)
/// - `find_all`: O(n + m)
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// The first prime modulus: 1,000,000,007.
const MOD1 : Int = 1_000_000_007

///|
/// The second prime modulus: 1,000,000,009.
const MOD2 : Int = 1_000_000_009

///|
/// The base for polynomial hashing. Chosen as a prime larger than the
/// alphabet size (256 for byte strings).
const BASE : Int = 911_382_33

///|
/// A double-modulus rolling hash over a string.
///
/// Precomputes forward and reverse hash arrays plus power tables for both
/// moduli, enabling O(1) substring hash queries.
pub struct RollingHash {
  priv n : Int
  // Forward hash arrays: fwd1[i] = hash of s[0..i) mod MOD1
  priv fwd1 : FixedArray[Int]
  priv fwd2 : FixedArray[Int]
  // Reverse hash arrays: rev1[i] = hash of s[n-i..n) mod MOD1
  priv rev1 : FixedArray[Int]
  priv rev2 : FixedArray[Int]
  // Power tables: pow1[i] = BASE^i mod MOD1
  priv pow1 : FixedArray[Int]
  priv pow2 : FixedArray[Int]
}

///|
/// Build a rolling hash over the given string.
///
/// Preprocessing is O(n) where n = s.length().
pub fn RollingHash::new(s : String) -> RollingHash {
  let n = s.length()
  let fwd1 = FixedArray::make(n + 1, 0)
  let fwd2 = FixedArray::make(n + 1, 0)
  let rev1 = FixedArray::make(n + 1, 0)
  let rev2 = FixedArray::make(n + 1, 0)
  let pow1 = FixedArray::make(n + 1, 1)
  let pow2 = FixedArray::make(n + 1, 1)
  // Compute power tables.
  for i = 1; i <= n; i = i + 1 {
    pow1[i] = mod_mul(pow1[i - 1], BASE, MOD1)
    pow2[i] = mod_mul(pow2[i - 1], BASE, MOD2)
  }
  // Forward hashes: fwd[i] = (fwd[i-1] * BASE + s[i-1]) mod M
  for i = 1; i <= n; i = i + 1 {
    let c = s[i - 1].to_int()
    fwd1[i] = (mod_mul(fwd1[i - 1], BASE, MOD1) + c) % MOD1
    fwd2[i] = (mod_mul(fwd2[i - 1], BASE, MOD2) + c) % MOD2
  }
  // Reverse hashes: rev[i] = hash of s[n-1], s[n-2], ..., s[n-i]
  for i = 1; i <= n; i = i + 1 {
    let c = s[n - i].to_int()
    rev1[i] = (mod_mul(rev1[i - 1], BASE, MOD1) + c) % MOD1
    rev2[i] = (mod_mul(rev2[i - 1], BASE, MOD2) + c) % MOD2
  }
  { n, fwd1, fwd2, rev1, rev2, pow1, pow2, }
}

///|
/// Modular multiplication using Int64 to avoid 32-bit overflow.
/// `a * b mod m` where a, b < m ≈ 1e9; product ≈ 1e18 fits in Int64.
fn mod_mul(a : Int, b : Int, m : Int) -> Int {
  let r = a.to_int64() * b.to_int64() % m.to_int64()
  r.to_int()
}

///|
/// Modular subtraction: (a - b) mod m, always non-negative.
fn mod_sub(a : Int, b : Int, m : Int) -> Int {
  let r = a - b
  if r < 0 {
    r + m
  } else {
    r
  }
}

///|
/// Compute the forward hash of substring s[l..r) under MOD1.
/// O(1). `l` and `r` must satisfy 0 <= l <= r <= n.
fn RollingHash::fwd_hash1(self : RollingHash, l : Int, r : Int) -> Int {
  if l >= r {
    return 0
  }
  mod_sub(self.fwd1[r], mod_mul(self.fwd1[l], self.pow1[r - l], MOD1), MOD1)
}

///|
/// Compute the forward hash of substring s[l..r) under MOD2.
/// O(1).
fn RollingHash::fwd_hash2(self : RollingHash, l : Int, r : Int) -> Int {
  if l >= r {
    return 0
  }
  mod_sub(self.fwd2[r], mod_mul(self.fwd2[l], self.pow2[r - l], MOD2), MOD2)
}

///|
/// Compute the reverse hash of substring s[l..r) under MOD1.
///
/// The reverse hash treats the substring as if read right-to-left, so
/// `fwd_hash(l, r) == rev_hash(l, r)` iff the substring is a palindrome.
fn RollingHash::rev_hash1(self : RollingHash, l : Int, r : Int) -> Int {
  if l >= r {
    return 0
  }
  // rev[i] = hash of s[n-1], ..., s[n-i]
  // For substring s[l..r), the reverse is s[r-1], ..., s[l]
  // = rev[n-l] - rev[n-r] * pow[r-l]
  let i1 = self.n - l
  let i2 = self.n - r
  mod_sub(self.rev1[i1], mod_mul(self.rev1[i2], self.pow1[r - l], MOD1), MOD1)
}

///|
/// Compute the reverse hash of substring s[l..r) under MOD2.
fn RollingHash::rev_hash2(self : RollingHash, l : Int, r : Int) -> Int {
  if l >= r {
    return 0
  }
  let i1 = self.n - l
  let i2 = self.n - r
  mod_sub(self.rev2[i1], mod_mul(self.rev2[i2], self.pow2[r - l], MOD2), MOD2)
}

///|
/// A 128-bit hash represented as a pair of (mod1_hash, mod2_hash).
/// Two substrings with the same DoubleHash are almost certainly identical.
pub struct DoubleHash {
  priv h1 : Int
  priv h2 : Int
}

///|
/// Get the double hash of substring s[l..r).
///
/// Returns a `DoubleHash` combining both moduli for collision resistance.
/// O(1). Requires 0 <= l <= r <= n.
pub fn RollingHash::substring_hash(
  self : RollingHash,
  l : Int,
  r : Int,
) -> DoubleHash {
  { h1: self.fwd_hash1(l, r), h2: self.fwd_hash2(l, r), }
}

///|
/// Check if substring s[l..r) is a palindrome.
///
/// Compares forward and reverse hashes under both moduli. O(1).
pub fn RollingHash::is_palindrome(self : RollingHash, l : Int, r : Int) -> Bool {
  if l >= r {
    return true
  }
  self.fwd_hash1(l, r) == self.rev_hash1(l, r) &&
  self.fwd_hash2(l, r) == self.rev_hash2(l, r)
}

///|
/// Check if two substrings s[l1..r1) and s[l2..r2) are equal.
///
/// O(1). The substrings must have the same length (r1-l1 == r2-l2).
pub fn RollingHash::equals(
  self : RollingHash,
  l1 : Int,
  r1 : Int,
  l2 : Int,
  r2 : Int,
) -> Bool {
  if r1 - l1 != r2 - l2 {
    return false
  }
  self.fwd_hash1(l1, r1) == self.fwd_hash1(l2, r2) &&
  self.fwd_hash2(l1, r1) == self.fwd_hash2(l2, r2)
}

///|
/// Find all starting positions of `pattern` in the hashed string.
///
/// Returns an array of indices where pattern occurs. O(n + m) where
/// n = string length and m = pattern length.
pub fn RollingHash::find_all(
  self : RollingHash,
  pattern : String,
) -> Array[Int] {
  let m = pattern.length()
  if m == 0 || m > self.n {
    return []
  }
  // Compute pattern hash under both moduli.
  // Use mod_mul to avoid Int32 overflow: ph * BASE ≈ 1e9 * 9e7 ≈ 9e16.
  let mut ph1 = 0
  let mut ph2 = 0
  for i = 0; i < m; i = i + 1 {
    let c = pattern[i].to_int()
    ph1 = (mod_mul(ph1, BASE, MOD1) + c) % MOD1
    ph2 = (mod_mul(ph2, BASE, MOD2) + c) % MOD2
  }
  let result = []
  for i = 0; i + m <= self.n; i = i + 1 {
    if self.fwd_hash1(i, i + m) == ph1 && self.fwd_hash2(i, i + m) == ph2 {
      result.push(i)
    }
  }
  result
}

///|
/// Length of the hashed string.
pub fn RollingHash::length(self : RollingHash) -> Int {
  self.n
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "rolling_hash: basic substring hash" {
  let rh = RollingHash::new("hello")
  // Same substring should give same hash
  let h1 = rh.substring_hash(0, 3) // "hel"
  let h2 = rh.substring_hash(0, 3)
  assert_eq(h1.h1, h2.h1)
  assert_eq(h1.h2, h2.h2)
}

///|
test "rolling_hash: equal substrings" {
  let rh = RollingHash::new("ababcabab")
  // "ab" at positions 0,2,5,7 should all be equal
  assert_true(rh.equals(0, 2, 2, 4))
  assert_true(rh.equals(0, 2, 5, 7))
  assert_true(rh.equals(0, 2, 7, 9))
  // "ab" != "ba"
  assert_false(rh.equals(0, 2, 1, 3))
}

///|
test "rolling_hash: palindrome check" {
  let rh = RollingHash::new("racecar")
  assert_true(rh.is_palindrome(0, 7)) // "racecar"
  assert_true(rh.is_palindrome(0, 1)) // "r"
  assert_true(rh.is_palindrome(3, 4)) // "e"
  assert_false(rh.is_palindrome(0, 6)) // "raceca"
  assert_true(rh.is_palindrome(1, 6)) // "aceca"
  assert_true(rh.is_palindrome(2, 5)) // "cec"
}

///|
test "rolling_hash: find_all" {
  let rh = RollingHash::new("abracadabra")
  let pos = rh.find_all("abra")
  assert_eq(pos.length(), 2)
  assert_eq(pos[0], 0)
  assert_eq(pos[1], 7)
}

///|
test "rolling_hash: find_all overlapping" {
  let rh = RollingHash::new("aaaa")
  let pos = rh.find_all("aa")
  assert_eq(pos.length(), 3)
  assert_eq(pos[0], 0)
  assert_eq(pos[1], 1)
  assert_eq(pos[2], 2)
}

///|
test "rolling_hash: find_all no match" {
  let rh = RollingHash::new("hello world")
  let pos = rh.find_all("xyz")
  assert_eq(pos.length(), 0)
}

///|
test "rolling_hash: find_all empty pattern" {
  let rh = RollingHash::new("hello")
  let pos = rh.find_all("")
  assert_eq(pos.length(), 0)
}

///|
test "rolling_hash: full string palindrome" {
  let rh = RollingHash::new("level")
  assert_true(rh.is_palindrome(0, 5))
  let rh2 = RollingHash::new("hello")
  assert_false(rh2.is_palindrome(0, 5))
}

///|
test "rolling_hash: single char" {
  let rh = RollingHash::new("a")
  assert_eq(rh.length(), 1)
  assert_true(rh.is_palindrome(0, 1))
  let h = rh.substring_hash(0, 1)
  assert_true(h.h1 >= 0)
}

///|
test "rolling_hash: empty string" {
  let rh = RollingHash::new("")
  assert_eq(rh.length(), 0)
  let h = rh.substring_hash(0, 0)
  assert_eq(h.h1, 0)
  assert_eq(h.h2, 0)
}

///|
test "rolling_hash: long string equality" {
  // Build "abcdefghij" repeated 10 times
  let buf = StringBuilder()
  for _ in 0..<10 {
    buf.write_string("abcdefghij")
  }
  let s = buf.to_string()
  let rh = RollingHash::new(s)
  // Check that non-overlapping equal substrings hash equally
  for i = 0; i < 10; i = i + 1 {
    assert_true(rh.equals(0, 10, i * 10, i * 10 + 10))
  }
}

///|
test "rolling_hash: collision resistance" {
  // Two different substrings of same length should have different hashes
  let rh = RollingHash::new("abcdefgh")
  let h1 = rh.substring_hash(0, 3) // "abc"
  let h2 = rh.substring_hash(1, 4) // "bcd"
  assert_true(h1.h1 != h2.h1 || h1.h2 != h2.h2)
}
