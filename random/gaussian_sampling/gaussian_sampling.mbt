///|
/// Gaussian (normal) sampling via the Box-Muller transform.
///
/// Box-Muller converts a pair of independent uniform [0, 1) samples into a
/// pair of independent standard normal N(0, 1) samples:
///   r = sqrt(-2 ln u1),  theta = 2 pi u2
///   z0 = r cos(theta),   z1 = r sin(theta)
/// Both z0 and z1 are exactly N(0, 1) and mutually independent. `u1` is mapped
/// into (0, 1] (via `1 - rng()`) so `ln(u1)` is always defined, even when the
/// rng returns 0.
///
/// Complexity: O(1) per sample. `proof-enabled` is `false`; correctness is
/// backed by the test suite.

// Test PRNG: uses @utils.XorShift64 for uniform Double in [0, 1).
// Callers of `box_muller`/`gaussian_sample` may supply any uniform [0, 1) rng.
fn make_rng(seed : Int64) -> () -> Double {
  let rng = @utils.XorShift64::new(seed.reinterpret_as_uint64())
  fn() { rng.next_double() }
}

///|
/// Generate two independent standard normal N(0, 1) samples from two uniform
/// [0, 1) draws of `rng` using the Box-Muller transform.
pub fn box_muller(rng : () -> Double) -> (Double, Double) {
  // Map u1 into (0, 1] so that ln(u1) is defined for every rng output.
  let u1 = 1.0 - rng()
  let u2 = rng()
  let r = (-2.0 * @math.ln(u1)).sqrt()
  let theta = 2.0 * @math.PI * u2
  (r * @math.cos(theta), r * @math.sin(theta))
}

///|
/// Draw one sample from N(mean, std^2). The second Box-Muller output is
/// discarded.
pub fn gaussian_sample(
  mean : Double,
  std : Double,
  rng : () -> Double,
) -> Double {
  let (z0, _) = box_muller(rng)
  mean + std * z0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "box_muller: mean is near 0" {
  let rng = make_rng(42L)
  let n = 100000
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let (z0, z1) = box_muller(rng)
    sum = sum + z0 + z1
  }
  let mean = sum / (2 * n).to_double()
  assert_true(mean.abs() < 0.05)
}

///|
test "box_muller: std is near 1" {
  let rng = make_rng(7L)
  let n = 100000
  let mut sum = 0.0
  let mut sum_sq = 0.0
  for i = 0; i < n; i = i + 1 {
    let (z0, z1) = box_muller(rng)
    sum = sum + z0 + z1
    sum_sq = sum_sq + z0 * z0 + z1 * z1
  }
  let count = (2 * n).to_double()
  let mean = sum / count
  let variance = sum_sq / count - mean * mean
  let v = if variance < 0.0 { 0.0 } else { variance }
  let std = v.sqrt()
  assert_true((std - 1.0).abs() < 0.05)
}

///|
test "gaussian_sample: shifts mean and std correctly" {
  let rng = make_rng(123L)
  let mean = 5.0
  let std = 3.0
  let n = 100000
  let mut sum = 0.0
  let mut sum_sq = 0.0
  for i = 0; i < n; i = i + 1 {
    let x = gaussian_sample(mean, std, rng)
    sum = sum + x
    sum_sq = sum_sq + x * x
  }
  let nd = n.to_double()
  let m = sum / nd
  let variance = sum_sq / nd - m * m
  let v = if variance < 0.0 { 0.0 } else { variance }
  let s = v.sqrt()
  assert_true((m - mean).abs() < 0.1)
  assert_true((s - std).abs() < 0.1)
}
