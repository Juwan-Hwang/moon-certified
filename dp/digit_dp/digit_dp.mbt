/// Digit DP: count numbers in a range satisfying digit-based properties.
///
/// Digit DP is a dynamic programming technique that processes a number digit
/// by digit. Given an upper bound `n`, it counts how many numbers in `[0, n]`
/// satisfy a property defined on the decimal digits of the number (e.g., digit
/// sum equals a target, divisible by k, no repeated digits, etc.).
///
/// ## Algorithm
///
/// The core idea is the "digit-by-digit" approach:
///
/// 1. Decompose `n` into its decimal digits `d[0], d[1], ..., d[L-1]`.
/// 2. Iterate position by position from the most significant digit.
/// 3. At each position `i`, try every digit `c` from 0 to `d[i] - 1`. When
///    `c < d[i]`, the remaining `L - i - 1` positions are "free" (can be any
///    digit 0-9) and their contribution is precomputed.
/// 4. Then fix `c = d[i]` and continue to the next position (this is the
///    "tight" path that matches `n` exactly).
/// 5. Finally, check if `n` itself satisfies the property.
///
/// The precomputation table `free[len][state]` stores how many ways there are
/// to fill `len` free positions such that they produce a given state (e.g., a
/// specific digit sum or modular residue).
///
/// ## Complexity
///
/// - Precomputation: O(L * S * 10) where `S` is the state space size.
/// - Counting: O(L * 10).
/// - Total: O(L * S * 10).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
/// Parse a decimal string into an array of integer digits.
///
/// Example: `"123"` → `[1, 2, 3]`.
fn parse_digits(s : String) -> Array[Int] {
  let digits : Array[Int] = []
  for i = 0; i < s.length(); i = i + 1 {
    digits.push(s[i].to_int() - 48) // '0' = 48
  }
  digits
}

///|
/// Decrement a decimal string representation by 1.
///
/// Used to compute `[l, r]` via `count(r) - count(l - 1)`.
/// Returns `"0"` if the input is `"0"` or `"1"`.
fn decrement_str(s : String) -> String {
  if s == "0" || s == "1" {
    return "0"
  }
  let digits = parse_digits(s)
  let n = digits.length()
  // Borrow
  digits[n - 1] = digits[n - 1] - 1
  let mut i = n - 1
  while i > 0 && digits[i] < 0 {
    digits[i] = digits[i] + 10
    digits[i - 1] = digits[i - 1] - 1
    i = i - 1
  }
  // Strip leading zeros
  let mut start = 0
  while start < n - 1 && digits[start] == 0 {
    start = start + 1
  }
  let digit_strs = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
  let buf = StringBuilder::new()
  for i = start; i < n; i = i + 1 {
    buf.write_string(digit_strs[digits[i]])
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// Count by digit sum
// ---------------------------------------------------------------------------

///|
/// Count numbers in `[0, n]` whose digit sum equals `target`.
///
/// `n_str` is the decimal string representation of `n` (e.g., `"123"`).
/// Returns the count as `Int64` to handle large results.
///
/// Leading zeros are treated as zeros (they contribute 0 to the sum), so
/// each number is counted exactly once.
///
/// Time: O(L^2 * 10), Space: O(L^2) where L = number of digits.
pub fn count_digit_sum(n_str : String, target : Int) -> Int64 {
  let digits = parse_digits(n_str)
  let n = digits.length()
  if target < 0 || target > n * 9 {
    return 0L
  }
  // Precompute: free[len][sum] = number of ways to fill `len` positions
  // with digits 0-9 such that their sum is `sum`.
  let max_sum = n * 9
  // Use makei to avoid shared references between rows.
  let free : Array[Array[Int64]] = Array::makei(n + 1, fn(_) {
    Array::make(max_sum + 1, 0L)
  })
  free[0][0] = 1L
  for len = 1; len <= n; len = len + 1 {
    for s = 0; s <= max_sum; s = s + 1 {
      for d = 0; d <= 9 && d <= s; d = d + 1 {
        free[len][s] = free[len][s] + free[len - 1][s - d]
      }
    }
  }
  // Count numbers in [0, n] with digit sum == target.
  // At each position i, try each digit d < digits[i], then use free[]
  // for the remaining positions.
  let mut result : Int64 = 0L
  let mut prefix_sum = 0
  for i = 0; i < n; i = i + 1 {
    let limit = digits[i]
    let remaining = n - i - 1
    for d = 0; d < limit; d = d + 1 {
      let current_sum = prefix_sum + d
      let needed = target - current_sum
      if needed >= 0 && needed <= remaining * 9 {
        result = result + free[remaining][needed]
      }
    }
    prefix_sum = prefix_sum + limit
  }
  // Check if n itself has digit sum == target
  if prefix_sum == target {
    result = result + 1L
  }
  result
}

///|
/// Count numbers in `[l, r]` whose digit sum equals `target`.
///
/// Both `l` and `r` are decimal string representations.
/// Uses the inclusion-exclusion: `count(r) - count(l - 1)`.
pub fn count_digit_sum_range(
  l_str : String,
  r_str : String,
  target : Int,
) -> Int64 {
  count_digit_sum(r_str, target) - count_digit_sum(decrement_str(l_str), target)
}

// ---------------------------------------------------------------------------
// Count divisible by k
// ---------------------------------------------------------------------------

///|
/// Count numbers in `[0, n]` that are divisible by `k` (i.e., ≡ 0 mod k).
///
/// `n_str` is the decimal string representation of `n`.
/// `k` must be a positive integer.
///
/// Uses digit DP with modular arithmetic:
/// - Tracks the prefix value mod k as digits are processed left to right.
/// - Precomputes `free[len][mod]` = number of `len`-digit sequences whose
///   value ≡ `mod` (mod k).
///
/// Time: O(L * k * 10), Space: O(L * k).
pub fn count_divisible(n_str : String, k : Int) -> Int64 {
  if k <= 0 {
    return 0L
  }
  let digits = parse_digits(n_str)
  let n = digits.length()
  // Precompute pow10[i] = 10^i mod k
  let pow10 : Array[Int] = Array::make(n + 1, 0)
  pow10[0] = 1 % k
  for i = 1; i <= n; i = i + 1 {
    pow10[i] = pow10[i - 1] * 10 % k
  }
  // Precompute: free[len][mod] = number of `len`-digit sequences whose
  // value ≡ mod (mod k).
  // Use makei to avoid shared references between rows.
  let free : Array[Array[Int64]] = Array::makei(n + 1, fn(_) {
    Array::make(k, 0L)
  })
  free[0][0] = 1L
  for len = 1; len <= n; len = len + 1 {
    for mod_val = 0; mod_val < k; mod_val = mod_val + 1 {
      for d = 0; d <= 9; d = d + 1 {
        let sub_mod = (mod_val - d * pow10[len - 1] % k + k * 10) % k
        free[len][mod_val] = free[len][mod_val] + free[len - 1][sub_mod]
      }
    }
  }
  // Count numbers in [0, n] divisible by k.
  // current_mod tracks the prefix value mod k.
  let mut result : Int64 = 0L
  let mut current_mod = 0
  for i = 0; i < n; i = i + 1 {
    let limit = digits[i]
    let remaining = n - i - 1
    for d = 0; d < limit; d = d + 1 {
      let new_mod = (current_mod * 10 + d) % k
      // After choosing digit d at position i, we have `remaining` free positions.
      // final_mod = (new_mod * pow10[remaining] + suffix_value) % k
      // We want final_mod == 0:
      // suffix_value ≡ (k - new_mod * pow10[remaining] % k) % k
      let contribution = new_mod * pow10[remaining] % k
      let needed_mod = (k - contribution) % k
      result = result + free[remaining][needed_mod]
    }
    current_mod = (current_mod * 10 + limit) % k
  }
  // Check if n itself is divisible by k
  if current_mod == 0 {
    result = result + 1L
  }
  result
}

///|
/// Count numbers in `[l, r]` that are divisible by `k`.
pub fn count_divisible_range(l_str : String, r_str : String, k : Int) -> Int64 {
  count_divisible(r_str, k) - count_divisible(decrement_str(l_str), k)
}

// ---------------------------------------------------------------------------
// Count without repeated digits
// ---------------------------------------------------------------------------

///|
/// Count numbers in `[0, n]` that have no repeated digits.
///
/// Uses a combination of combinatorial counting for numbers with fewer digits
/// than `n`, and digit DP for numbers with exactly as many digits as `n`.
///
/// Since there are only 10 digits (0-9), any number with > 10 digits must have
/// a repeated digit (pigeonhole principle).
///
/// Time: O(L * 1024 * 10), Space: O(1024) for the free-count precomputation.
pub fn count_no_repeated_digits(n_str : String) -> Int64 {
  let digits = parse_digits(n_str)
  let n = digits.length()
  if n > 10 {
    return count_no_repeated_digits("9999999999")
  }
  let mut result : Int64 = 0L
  // Count the number 0 (always valid — single digit, no repeat).
  result = result + 1L
  // Count numbers with fewer digits than n (1-digit, 2-digit, ..., (n-1)-digit).
  // k-digit number with no repeated digits:
  //   first digit: 1-9 (9 choices)
  //   second digit: 0-9 except first (9 choices)
  //   third digit: 0-9 except first two (8 choices)
  //   ... (k <= 10)
  for len = 1; len < n; len = len + 1 {
    let mut count : Int64 = 9L
    let mut available = 9 // digits available after first (0-9 minus first)
    for j = 1; j < len; j = j + 1 {
      count = count * available.to_int64()
      available = available - 1
    }
    result = result + count
  }
  // Count numbers with exactly n digits (from 10...0 to n).
  // Digit DP: process position by position.
  // mask tracks which digits have been used in the prefix.
  let mut mask = 0
  for i = 0; i < n; i = i + 1 {
    let limit = digits[i]
    // First digit can't be 0 (otherwise it would have fewer digits).
    let start_d = if i == 0 { 1 } else { 0 }
    for d = start_d; d < limit; d = d + 1 {
      let bit = 1 << d
      if (mask & bit) == 0 {
        let new_mask = mask | bit
        let remaining = n - i - 1
        result = result + count_no_repeated_free(remaining, new_mask)
      }
    }
    // Fix digit to limit and continue.
    let bit = 1 << limit
    if (mask & bit) != 0 {
      // n itself has a repeated digit — stop here.
      return result
    }
    mask = mask | bit
  }
  // n itself has no repeated digits.
  result = result + 1L
  result
}

///|
/// Count `len`-digit sequences (with possible leading zeros) that use only
/// digits NOT in `used_mask` and have no repeats among themselves.
///
/// This is the number of ways to choose `len` distinct digits from the
/// available set (digits not in `used_mask`) and arrange them in order.
///
/// Computed recursively: at each position, try each available digit.
fn count_no_repeated_free(len : Int, used_mask : Int) -> Int64 {
  if len == 0 {
    return 1L
  }
  let mut result : Int64 = 0L
  for d = 0; d <= 9; d = d + 1 {
    let bit = 1 << d
    if (used_mask & bit) == 0 {
      result = result + count_no_repeated_free(len - 1, used_mask | bit)
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "count_digit_sum: basic" {
  // Numbers 0-12 with digit sum 3: {3, 12} → 2
  assert_eq(count_digit_sum("12", 3), 2L)
  // Numbers 0-12 with digit sum 1: {1, 10} → 2
  assert_eq(count_digit_sum("12", 1), 2L)
  // Numbers 0-9 with digit sum 5: {5} → 1
  assert_eq(count_digit_sum("9", 5), 1L)
  // Numbers 0-0 with digit sum 0: {0} → 1
  assert_eq(count_digit_sum("0", 0), 1L)
}

///|
test "count_digit_sum: large range" {
  // Count numbers 0-99 with digit sum 10
  // These are: 19, 28, 37, 46, 55, 64, 73, 82, 91 → 9
  assert_eq(count_digit_sum("99", 10), 9L)
  // Count numbers 0-999 with digit sum 2
  // With leading zeros (3-digit): 002, 011, 020, 101, 110, 200 → 6
  assert_eq(count_digit_sum("999", 2), 6L)
}

///|
test "count_digit_sum: target too large" {
  // Can't have digit sum > 9*4 = 36 for 4-digit number
  assert_eq(count_digit_sum("9999", 40), 0L)
}

///|
test "count_digit_sum_range: basic" {
  // Numbers 1-12 with digit sum 3: {3, 12} → 2
  assert_eq(count_digit_sum_range("1", "12", 3), 2L)
  // Numbers 5-15 with digit sum 6: {6, 15} → 2
  assert_eq(count_digit_sum_range("5", "15", 6), 2L)
}

///|
test "count_divisible: basic" {
  // Numbers 0-9 divisible by 3: {0, 3, 6, 9} → 4
  assert_eq(count_divisible("9", 3), 4L)
  // Numbers 0-12 divisible by 3: {0, 3, 6, 9, 12} → 5
  assert_eq(count_divisible("12", 3), 5L)
  // Numbers 0-20 divisible by 7: {0, 7, 14} → 3
  assert_eq(count_divisible("20", 7), 3L)
}

///|
test "count_divisible: large" {
  // Numbers 0-99 divisible by 4: 0, 4, 8, ..., 96 → 25
  assert_eq(count_divisible("99", 4), 25L)
  // Numbers 0-1000 divisible by 10: 0, 10, 20, ..., 1000 → 101
  assert_eq(count_divisible("1000", 10), 101L)
}

///|
test "count_divisible_range: basic" {
  // Numbers 1-10 divisible by 3: {3, 6, 9} → 3
  assert_eq(count_divisible_range("1", "10", 3), 3L)
  // Numbers 10-20 divisible by 5: {10, 15, 20} → 3
  assert_eq(count_divisible_range("10", "20", 5), 3L)
}

///|
test "count_no_repeated_digits: basic" {
  // Numbers 0-9 with no repeated digits: all 10 → 10
  assert_eq(count_no_repeated_digits("9"), 10L)
  // Numbers 0-12 with no repeated digits:
  // 0-9: 10, 10, 12 → 12 (11 has repeated digit 1)
  assert_eq(count_no_repeated_digits("12"), 12L)
  // Numbers 0-99 with no repeated digits:
  // 1-digit: 0-9 → 10
  // 2-digit: 10-99, excluding 11,22,...,99 → 90 - 9 = 81
  // Total: 10 + 81 = 91
  assert_eq(count_no_repeated_digits("99"), 91L)
}

///|
test "count_no_repeated_digits: 100" {
  // Numbers 0-100 with no repeated digits:
  // 0-99: 91 (from above)
  // 100: repeated digit 0 → excluded
  // Total: 91
  assert_eq(count_no_repeated_digits("100"), 91L)
}

///|
test "count_no_repeated_digits: large" {
  // Numbers 0-999 with no repeated digits:
  // 0: 1
  // 1-digit: 9 (1-9)
  // 2-digit: 9*9 = 81
  // 3-digit: 9*9*8 = 648
  // Total: 1 + 9 + 81 + 648 = 739
  assert_eq(count_no_repeated_digits("999"), 739L)
}

///|
test "decrement_str: basic" {
  assert_eq(decrement_str("1"), "0")
  assert_eq(decrement_str("10"), "9")
  assert_eq(decrement_str("100"), "99")
  assert_eq(decrement_str("1000"), "999")
  assert_eq(decrement_str("0"), "0")
  assert_eq(decrement_str("123"), "122")
}
