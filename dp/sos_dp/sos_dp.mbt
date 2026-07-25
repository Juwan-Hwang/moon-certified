/// Sum Over Subsets (SOS) dynamic programming.
///
/// Given an array `f` of size `2^n` indexed by subset masks, compute for every
/// mask `m`:
///
/// ```text
///   F(m) = sum_{sub ⊆ m} f(sub)
/// ```
///
/// ## Algorithm
///
/// The standard O(n * 2^n) DP iterates over each bit position `i` and, for every
/// mask `m` that has bit `i` set, adds the contribution of the mask with that
/// bit cleared:
///
/// ```text
///   for i in 0 .. n-1:
///     for m in 0 .. 2^n - 1:
///       if m & (1 << i):
///         f[m] += f[m ^ (1 << i)]
/// ```
///
/// After all bits are processed, `f[m]` contains the sum over all subsets of `m`.
///
/// ## Complexity
///
/// - Time:  O(n * 2^n) where `n = log2(len)`.
/// - Space: O(2^n) in place (the input array is modified).
///
/// ## Overflow safety
///
/// All sums accumulate in `Int64`. The function returns an `Int64` array so
/// that large totals (up to `2^n * Int::max`) do not silently wrap.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Compute `F(m) = sum_{sub ⊆ m} f(sub)` for all masks `m`.
///
/// Returns a new `Int64` array of the same length as the input. The input is
/// not modified.
///
/// # Parameters
/// - `f`: array of `Int` values indexed by subset mask. Length must be a
///   power of two. Returns an empty array if `f` is empty.
///
/// # Returns
/// `Int64` array `F` where `F[m] = sum_{sub ⊆ m} f[sub]`.
pub fn sos_sum(f : FixedArray[Int]) -> FixedArray[Int64] {
  let len = f.length()
  if len == 0 {
    return FixedArray::make(0, 0L)
  }
  // Verify len is a power of two.
  if (len & (len - 1)) != 0 {
    return FixedArray::make(0, 0L)
  }
  // Widen to Int64 and copy.
  let dp = FixedArray::make(len, 0L)
  for i = 0; i < len; i = i + 1 {
    dp[i] = f[i].to_int64()
  }
  let n = log2_floor(len)
  for i = 0; i < n; i = i + 1 {
    let bit = 1 << i
    for m = 0; m < len; m = m + 1 {
      if (m & bit) != 0 {
        dp[m] = dp[m] + dp[m ^ bit]
      }
    }
  }
  dp
}

/// Compute `F(m) = sum_{super ⊇ m} f(super)` for all masks `m` (superset sum).
///
/// This is the dual of [`sos_sum`]: instead of summing over subsets, we sum
/// over supersets.
///
/// Returns a new `Int64` array. The input is not modified.
pub fn sos_superset_sum(f : FixedArray[Int]) -> FixedArray[Int64] {
  let len = f.length()
  if len == 0 {
    return FixedArray::make(0, 0L)
  }
  if (len & (len - 1)) != 0 {
    return FixedArray::make(0, 0L)
  }
  let dp = FixedArray::make(len, 0L)
  for i = 0; i < len; i = i + 1 {
    dp[i] = f[i].to_int64()
  }
  let n = log2_floor(len)
  for i = 0; i < n; i = i + 1 {
    let bit = 1 << i
    for m = 0; m < len; m = m + 1 {
      if (m & bit) == 0 {
        dp[m] = dp[m] + dp[m | bit]
      }
    }
  }
  dp
}

/// Compute `F(m) = count of sub ⊆ m with f[sub] != 0`.
///
/// Convenience wrapper: treats each nonzero entry as 1 and sums over subsets.
pub fn sos_count_nonzero(f : FixedArray[Int]) -> FixedArray[Int64] {
  let len = f.length()
  let binary = FixedArray::make(len, 0)
  for i = 0; i < len; i = i + 1 {
    if f[i] != 0 {
      binary[i] = 1
    }
  }
  sos_sum(binary)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Floor of log2 for positive powers of two. Returns 0 for len <= 1.
fn log2_floor(len : Int) -> Int {
  let mut n = 0
  let mut v = len
  while v > 1 {
    v = v >> 1
    n = n + 1
  }
  n
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "sos_dp: basic subset sum" {
  // f = [1, 2, 3, 4] (n=2, masks 0..3)
  // F(0) = f(0) = 1
  // F(1) = f(0)+f(1) = 3
  // F(2) = f(0)+f(2) = 4
  // F(3) = f(0)+f(1)+f(2)+f(3) = 10
  let f = FixedArray::make(4, 0)
  f[0] = 1
  f[1] = 2
  f[2] = 3
  f[3] = 4
  let result = sos_sum(f)
  assert_eq(result[0], 1L)
  assert_eq(result[1], 3L)
  assert_eq(result[2], 4L)
  assert_eq(result[3], 10L)
}

test "sos_dp: single element" {
  let f = FixedArray::make(1, 0)
  f[0] = 5
  let result = sos_sum(f)
  assert_eq(result[0], 5L)
}

test "sos_dp: empty input" {
  let f = FixedArray::make(0, 0)
  let result = sos_sum(f)
  assert_eq(result.length(), 0)
}

test "sos_dp: all zeros" {
  let f = FixedArray::make(8, 0)
  let result = sos_sum(f)
  for i = 0; i < 8; i = i + 1 {
    assert_eq(result[i], 0L)
  }
}

test "sos_dp: n=3 (8 elements)" {
  // f = [1,1,1,1,1,1,1,1]; F(m) = 2^popcount(m)
  let f = FixedArray::make(8, 1)
  let result = sos_sum(f)
  // F(0)=1, F(1)=2, F(2)=2, F(3)=4, F(4)=2, F(5)=4, F(6)=4, F(7)=8
  assert_eq(result[0], 1L)
  assert_eq(result[1], 2L)
  assert_eq(result[2], 2L)
  assert_eq(result[3], 4L)
  assert_eq(result[4], 2L)
  assert_eq(result[5], 4L)
  assert_eq(result[6], 4L)
  assert_eq(result[7], 8L)
}

test "sos_dp: non-power-of-two rejected" {
  let f = FixedArray::make(3, 1)
  let result = sos_sum(f)
  assert_eq(result.length(), 0)
}

test "sos_dp: input not modified" {
  let f = FixedArray::make(4, 0)
  f[0] = 1
  f[1] = 2
  f[2] = 3
  f[3] = 4
  let _ = sos_sum(f)
  // Verify input is unchanged.
  assert_eq(f[0], 1)
  assert_eq(f[1], 2)
  assert_eq(f[2], 3)
  assert_eq(f[3], 4)
}

test "sos_dp: superset sum basic" {
  // f = [1, 2, 3, 4] (n=2)
  // G(0) = sum of all = 10
  // G(1) = f(1)+f(3) = 6
  // G(2) = f(2)+f(3) = 7
  // G(3) = f(3) = 4
  let f = FixedArray::make(4, 0)
  f[0] = 1
  f[1] = 2
  f[2] = 3
  f[3] = 4
  let result = sos_superset_sum(f)
  assert_eq(result[0], 10L)
  assert_eq(result[1], 6L)
  assert_eq(result[2], 7L)
  assert_eq(result[3], 4L)
}

test "sos_dp: superset sum n=3" {
  // f = [1,0,0,0,0,0,0,0]; G(m) = sum of f(s) for s ⊇ m.
  // Only f(0)=1, and {0} is a superset of only the empty set.
  // So G(0) = 1 (all sets are supersets of ∅), G(m) = 0 for m ≠ 0.
  let f = FixedArray::make(8, 0)
  f[0] = 1
  let result = sos_superset_sum(f)
  assert_eq(result[0], 1L)
  for i = 1; i < 8; i = i + 1 {
    assert_eq(result[i], 0L)
  }
}

test "sos_dp: count nonzero" {
  // f = [0, 1, 0, 1] (n=2)
  // count(0)=1 (only f(1) is nonzero? no, count of subsets of 0 that are nonzero = 0)
  // Wait: sos_count_nonzero sums binary(1 for nonzero) over subsets.
  // f_bin = [0,1,0,1]
  // F(0) = f_bin(0) = 0
  // F(1) = f_bin(0)+f_bin(1) = 1
  // F(2) = f_bin(0)+f_bin(2) = 0
  // F(3) = f_bin(0)+f_bin(1)+f_bin(2)+f_bin(3) = 2
  let f = FixedArray::make(4, 0)
  f[0] = 0
  f[1] = 1
  f[2] = 0
  f[3] = 1
  let result = sos_count_nonzero(f)
  assert_eq(result[0], 0L)
  assert_eq(result[1], 1L)
  assert_eq(result[2], 0L)
  assert_eq(result[3], 2L)
}

test "sos_dp: overflow safety" {
  // Large values that would overflow Int32 when summed.
  let f = FixedArray::make(4, 0)
  f[0] = 1000000000
  f[1] = 1000000000
  f[2] = 1000000000
  f[3] = 1000000000
  let result = sos_sum(f)
  // F(3) = 4 * 10^9 = 4,000,000,000 which overflows Int32 (max ~2.1*10^9)
  assert_eq(result[3], 4000000000L)
}

test "sos_dp: brute force cross-check n=4" {
  // Cross-check with brute force O(3^n) on 16 elements.
  let n = 4
  let len = 1 << n
  let f = FixedArray::make(len, 0)
  for i = 0; i < len; i = i + 1 {
    f[i] = (i * 3 + 1) % 7
  }
  let result = sos_sum(f)
  // Brute force.
  for m = 0; m < len; m = m + 1 {
    let mut brute = 0L
    for sub = 0; sub <= m; sub = sub + 1 {
      if (sub & m) == sub {
        brute = brute + f[sub].to_int64()
      }
    }
    assert_eq(result[m], brute)
  }
}
