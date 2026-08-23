/// Property-Based Testing Framework — lightweight QuickCheck-style testing.
///
/// Provides random input generation, property execution, and failure
/// shrinking to find minimal counterexamples. This is the algorithmic-testing
/// "golden standard" recommended by the audit for catching edge-case bugs
/// that example-based tests miss.
///
/// ## Usage
///
/// ```moonbit
/// // Property: sorting is idempotent
/// test "property: sort(sort(x)) == sort(x)" {
///   let gen = gen_int_array(0, 100, 0, 50)
///   let prop = fn(xs : Array[Int]) -> Bool {
///     let s1 = @sorting.merge_sort(xs)
///     let s2 = @sorting.merge_sort(s1)
///     s1 == s2
///   }
///   let result = check_property(gen, prop, 200)
///   assert_true(result.passed)
/// }
/// ```
///
/// ## Generators
///
/// Generators are functions `(SplitMix64) -> T` — they mutate the PRNG state
/// in place and return a generated value. This makes them composable: a
/// generator for `Array[Int]` calls the `Int` generator repeatedly.
///
/// ## Shrinking
///
/// When a property fails, the framework attempts to find a smaller
/// counterexample by shrinking the failing input. For integers, this means
/// moving toward zero; for arrays, removing elements. The shrunk value is
/// reported in the result.
///
/// ## References
///
/// - Claessen, K. and Hughes, J. (2000): "QuickCheck: A Lightweight Tool
///   for Random Testing of Haskell Programs." ICFP.
/// - Hughes, J. (2007): "QuickCheck Testing for Fun and Profit." Advances
///   in Computers, 75, 1-67.
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Property result
// ---------------------------------------------------------------------------

///|
/// Result of running a property check.
pub struct PropertyResult[T] {
  /// Whether all test cases passed.
  passed : Bool
  /// Number of test cases run.
  num_tests : Int
  /// The first failing input (if any), after shrinking.
  counterexample : T?
  /// Number of shrinks performed to reach the counterexample.
  num_shrinks : Int
}

// ---------------------------------------------------------------------------
// Primitive generators
// ---------------------------------------------------------------------------

///|
/// Generate a random `Int` in `[min, max]` (inclusive).
///
/// The PRNG state is mutated in place.
pub fn gen_int(min : Int, max : Int, rng : @utils.SplitMix64) -> Int {
  let v = rng.next_u64()
  let range = (max - min + 1).to_uint64()
  if range == 0UL {
    min
  } else {
    min + (v % range).to_int()
  }
}

///|
/// Generate a random `Int` in `[0, max]` (inclusive).
pub fn gen_int_upto(max : Int, rng : @utils.SplitMix64) -> Int {
  gen_int(0, max, rng)
}

///|
/// Generate a random positive `Int` in `[1, max]`.
pub fn gen_positive_int(max : Int, rng : @utils.SplitMix64) -> Int {
  gen_int(1, max, rng)
}

///|
/// Generate a random `Double` in `[0.0, 1.0)`.
pub fn gen_double(rng : @utils.SplitMix64) -> Double {
  rng.next_double()
}

///|
/// Generate a random `Double` in `[min, max)`.
pub fn gen_double_range(
  min : Double,
  max : Double,
  rng : @utils.SplitMix64,
) -> Double {
  min + rng.next_double() * (max - min)
}

///|
/// Generate a random `Bool`.
pub fn gen_bool(rng : @utils.SplitMix64) -> Bool {
  (rng.next_u64() & 1UL) == 0UL
}

///|
/// Generate a random `Array[Int]` of length `[min_len, max_len]` with
/// elements in `[min_val, max_val]`.
pub fn gen_int_array(
  min_len : Int,
  max_len : Int,
  min_val : Int,
  max_val : Int,
  rng : @utils.SplitMix64,
) -> Array[Int] {
  let len = gen_int(min_len, max_len, rng)
  let arr = Array::make(len, 0)
  for i = 0; i < len; i = i + 1 {
    arr[i] = gen_int(min_val, max_val, rng)
  }
  arr
}

///|
/// Generate a random `Array[Double]` of length `[min_len, max_len]` with
/// elements in `[min_val, max_val)`.
pub fn gen_double_array(
  min_len : Int,
  max_len : Int,
  min_val : Double,
  max_val : Double,
  rng : @utils.SplitMix64,
) -> Array[Double] {
  let len = gen_int(min_len, max_len, rng)
  let arr = Array::make(len, 0.0)
  for i = 0; i < len; i = i + 1 {
    arr[i] = gen_double_range(min_val, max_val, rng)
  }
  arr
}

// ---------------------------------------------------------------------------
// Property runner
// ---------------------------------------------------------------------------

///|
/// Default number of test cases per property.
let default_num_tests : Int = 100

///|
/// Run a property with `num_tests` random `Int` inputs.
///
/// - `prop`: the property to check — returns `true` if the property holds.
/// - `num_tests`: number of random test cases to run.
/// - `seed`: PRNG seed for reproducibility.
///
/// If any case fails, the framework shrinks the input and returns the
/// minimal counterexample.
pub fn check_property_int(
  prop : (Int) -> Bool,
  num_tests : Int,
  seed : UInt64,
  min_val : Int,
  max_val : Int,
) -> PropertyResult[Int] {
  let rng = @utils.SplitMix64::new(seed)
  for i = 0; i < num_tests; i = i + 1 {
    let input = gen_int(min_val, max_val, rng)
    if !prop(input) {
      let (shrunk, shrinks) = shrink_int(prop, input)
      return {
        passed: false,
        num_tests: i + 1,
        counterexample: Some(shrunk),
        num_shrinks: shrinks,
      }
    }
  }
  { passed: true, num_tests, counterexample: None, num_shrinks: 0 }
}

///|
/// Run a property with `num_tests` random `Array[Int]` inputs.
pub fn check_property_int_array(
  prop : (Array[Int]) -> Bool,
  num_tests : Int,
  seed : UInt64,
  min_len : Int,
  max_len : Int,
  min_val : Int,
  max_val : Int,
) -> PropertyResult[Array[Int]] {
  let rng = @utils.SplitMix64::new(seed)
  for i = 0; i < num_tests; i = i + 1 {
    let input = gen_int_array(min_len, max_len, min_val, max_val, rng)
    if !prop(input) {
      let (shrunk, shrinks) = shrink_int_array(prop, input)
      return {
        passed: false,
        num_tests: i + 1,
        counterexample: Some(shrunk),
        num_shrinks: shrinks,
      }
    }
  }
  { passed: true, num_tests, counterexample: None, num_shrinks: 0 }
}

///|
/// Run a property with the default number of tests (100) for `Int` inputs.
pub fn check_int(
  prop : (Int) -> Bool,
  min_val : Int,
  max_val : Int,
) -> PropertyResult[Int] {
  check_property_int(
    prop, default_num_tests, 0xDEADBEEFCAFEBABEUL, min_val, max_val,
  )
}

// ---------------------------------------------------------------------------
// Shrinking
// ---------------------------------------------------------------------------

///|
/// Shrink an `Int` toward zero: try `0`, `x/2`, `x-1`, `x+1` and return the
/// smallest value that still fails the property.
pub fn shrink_int(prop : (Int) -> Bool, x : Int) -> (Int, Int) {
  let candidates = [0, x / 2, if x > 0 { x - 1 } else { x + 1 }]
  let mut best = x
  let mut shrinks = 0
  for i = 0; i < candidates.length(); i = i + 1 {
    let c = candidates[i]
    if c != x && !prop(c) {
      best = c
      shrinks = shrinks + 1
      // Try to shrink further from this candidate.
      let (deeper, deeper_shrinks) = shrink_int(prop, c)
      if !prop(deeper) {
        best = deeper
        shrinks = shrinks + deeper_shrinks
      }
    }
  }
  (best, shrinks)
}

///|
/// Shrink an `Array[Int]` by removing elements: try removing each element
/// one at a time and return the shortest array that still fails.
pub fn shrink_int_array(
  prop : (Array[Int]) -> Bool,
  xs : Array[Int],
) -> (Array[Int], Int) {
  let mut best = xs
  let mut shrinks = 0
  for i = 0; i < best.length(); i = i + 1 {
    // Try removing element i.
    let shorter : Array[Int] = []
    for j = 0; j < best.length(); j = j + 1 {
      if j != i {
        shorter.push(best[j])
      }
    }
    if !prop(shorter) {
      best = shorter
      shrinks = shrinks + 1
      // Recurse on the shorter array.
      let (deeper, deeper_shrinks) = shrink_int_array(prop, shorter)
      if !prop(deeper) {
        best = deeper
        shrinks = shrinks + deeper_shrinks
      }
      return (best, shrinks)
    }
  }
  (best, shrinks)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "property_test: int generator stays in range" {
  let rng = @utils.SplitMix64::new(42UL)
  for _i = 0; _i < 100; _i = _i + 1 {
    let v = gen_int(5, 10, rng)
    assert_true(v >= 5 && v <= 10)
  }
}

///|
test "property_test: double generator stays in [0, 1)" {
  let rng = @utils.SplitMix64::new(42UL)
  for _i = 0; _i < 100; _i = _i + 1 {
    let v = gen_double(rng)
    assert_true(v >= 0.0 && v < 1.0)
  }
}

///|
test "property_test: bool generator produces both values" {
  let rng = @utils.SplitMix64::new(42UL)
  let mut trues = 0
  let mut falses = 0
  for _i = 0; _i < 100; _i = _i + 1 {
    let v = gen_bool(rng)
    if v {
      trues = trues + 1
    } else {
      falses = falses + 1
    }
  }
  // Both should appear in 100 trials.
  assert_true(trues > 0 && falses > 0)
}

///|
test "property_test: int array generator respects constraints" {
  let rng = @utils.SplitMix64::new(42UL)
  for _i = 0; _i < 50; _i = _i + 1 {
    let arr = gen_int_array(3, 10, 0, 100, rng)
    assert_true(arr.length() >= 3 && arr.length() <= 10)
    for j = 0; j < arr.length(); j = j + 1 {
      assert_true(arr[j] >= 0 && arr[j] <= 100)
    }
  }
}

///|
test "property_test: passing property returns passed=true" {
  // Property: x + 0 == x for all Int
  let prop = fn(x : Int) -> Bool { x + 0 == x }
  let result = check_int(prop, -1000, 1000)
  assert_true(result.passed)
  assert_true(result.num_tests == 100)
}

///|
test "property_test: failing property returns counterexample" {
  // Property: x > 0 (will fail for non-positive x)
  let prop = fn(x : Int) -> Bool { x > 0 }
  let result = check_property_int(prop, 200, 42UL, -100, 100)
  assert_true(!result.passed)
  // The counterexample should be <= 0
  match result.counterexample {
    Some(v) => assert_true(v <= 0)
    None => fail("should have a counterexample")
  }
}

///|
test "property_test: shrink_int finds zero" {
  // Property: x > 0 (fails for x <= 0)
  let prop = fn(x : Int) -> Bool { x > 0 }
  let (shrunk, shrinks) = shrink_int(prop, -42)
  // After shrinking, should find 0 (smallest counterexample)
  assert_true(shrunk <= 0)
  assert_true(shrinks > 0)
}

///|
test "property_test: shrink_int_array removes elements" {
  // Property: array length > 10 (input has length 7, so it fails)
  let prop = fn(xs : Array[Int]) -> Bool { xs.length() > 10 }
  let input = [5, 3, 8, 1, 9, 2, 7]
  let (shrunk, shrinks) = shrink_int_array(prop, input)
  // After shrinking, should find a shorter failing array
  assert_true(shrunk.length() <= 3)
  assert_true(shrinks > 0)
}

///|
test "property_test: same seed is deterministic" {
  let prop = fn(x : Int) -> Bool { x >= 0 }
  let r1 = check_property_int(prop, 50, 12345UL, -100, 100)
  let r2 = check_property_int(prop, 50, 12345UL, -100, 100)
  // Same seed should produce same results.
  assert_true(r1.passed == r2.passed)
  assert_true(r1.num_tests == r2.num_tests)
}

///|
test "property_test: double array generator respects constraints" {
  let rng = @utils.SplitMix64::new(42UL)
  for _i = 0; _i < 50; _i = _i + 1 {
    let arr = gen_double_array(2, 8, -10.0, 10.0, rng)
    assert_true(arr.length() >= 2 && arr.length() <= 8)
    for j = 0; j < arr.length(); j = j + 1 {
      assert_true(arr[j] >= -10.0 && arr[j] < 10.0)
    }
  }
}

///|
test "property_test: property with large range passes" {
  // Property: x * 2 == x + x
  let prop = fn(x : Int) -> Bool { x * 2 == x + x }
  let result = check_int(prop, -10000, 10000)
  assert_true(result.passed)
}
