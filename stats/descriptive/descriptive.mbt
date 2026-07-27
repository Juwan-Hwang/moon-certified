/// Descriptive Statistics — Basic Statistical Functions.
///
/// Provides mean, variance, standard deviation, median, quantiles,
/// min, max, range, sum, and mode for arrays of Double values.
///
/// ## Complexity
/// - mean, variance, stddev, sum, min, max, range: O(n) time, O(1) space.
/// - median, quantile, mode: O(n log n) time (sorting), O(n) space.
///
/// ## Empty-array policy
/// - `sum_val` returns `0.0` (the identity element of addition).
/// - `mean`, `variance`, `stddev` return `0.0` (following project convention).
/// - `sample_variance`, `sample_stddev` return `NaN` (Bessel's correction
///   requires n >= 2).
/// - `median`, `quantile`, `min_val`, `max_val`, `range_val`, `mode` return
///   `NaN` (no meaningful result for an empty set).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Compute the sum of all elements in the data array.
///
/// Returns `0.0` for an empty array.
pub fn sum_val(data : Array[Double]) -> Double {
  let mut sum = 0.0
  for i = 0; i < data.length(); i = i + 1 {
    sum = sum + data[i]
  }
  sum
}

///|
/// Compute the arithmetic mean (average) of the data.
///
/// Returns `0.0` for an empty array.
pub fn mean(data : Array[Double]) -> Double {
  let n = data.length()
  if n == 0 {
    return 0.0
  }
  sum_val(data) / n.to_double()
}

///|
/// Compute the population variance: sum((xi - mu)^2) / n.
///
/// Returns `0.0` for an empty array.
pub fn variance(data : Array[Double]) -> Double {
  let n = data.length()
  if n == 0 {
    return 0.0
  }
  let m = mean(data)
  let mut sum_sq = 0.0
  for i = 0; i < n; i = i + 1 {
    let diff = data[i] - m
    sum_sq = sum_sq + diff * diff
  }
  sum_sq / n.to_double()
}

///|
/// Compute the sample variance (Bessel's correction): sum((xi - x_bar)^2) / (n-1).
///
/// Returns `NaN` for arrays with fewer than 2 elements.
pub fn sample_variance(data : Array[Double]) -> Double {
  let n = data.length()
  if n < 2 {
    return 0.0 / 0.0 // NaN
  }
  let m = mean(data)
  let mut sum_sq = 0.0
  for i = 0; i < n; i = i + 1 {
    let diff = data[i] - m
    sum_sq = sum_sq + diff * diff
  }
  sum_sq / (n - 1).to_double()
}

///|
/// Compute the population standard deviation: sqrt(variance).
///
/// Returns `0.0` for an empty array.
pub fn stddev(data : Array[Double]) -> Double {
  variance(data).sqrt()
}

///|
/// Compute the sample standard deviation: sqrt(sample_variance).
///
/// Returns `NaN` for arrays with fewer than 2 elements.
pub fn sample_stddev(data : Array[Double]) -> Double {
  sample_variance(data).sqrt()
}

///|
/// Compute the median (middle value) of the data.
///
/// Sorts a copy of the data, then:
/// - If n is odd, returns the middle element.
/// - If n is even, returns the average of the two middle elements.
///
/// Returns `NaN` for an empty array.
pub fn median(data : Array[Double]) -> Double {
  let n = data.length()
  if n == 0 {
    return 0.0 / 0.0 // NaN
  }
  let sorted = data.copy()
  sorted.sort()
  let mid = n / 2
  if n % 2 == 1 {
    sorted[mid]
  } else {
    (sorted[mid - 1] + sorted[mid]) / 2.0
  }
}

///|
/// Compute the q-th quantile of the data (0.0 <= q <= 1.0).
///
/// Uses linear interpolation between closest ranks (R type 7, the default
/// in R and NumPy). For `q = 0.0` returns the minimum, for `q = 1.0` returns
/// the maximum, for `q = 0.5` returns the median.
///
/// Returns `NaN` for an empty array.
pub fn quantile(data : Array[Double], q : Double) -> Double {
  let n = data.length()
  if n == 0 {
    return 0.0 / 0.0 // NaN
  }
  let sorted = data.copy()
  sorted.sort()
  if q <= 0.0 {
    return sorted[0]
  }
  if q >= 1.0 {
    return sorted[n - 1]
  }
  // Linear interpolation: pos = q * (n - 1)
  let pos = q * (n - 1).to_double()
  let lo = pos.to_int()
  let hi = if lo + 1 < n { lo + 1 } else { lo }
  let frac = pos - lo.to_double()
  sorted[lo] + (sorted[hi] - sorted[lo]) * frac
}

///|
/// Compute the minimum value in the data.
///
/// Returns `NaN` for an empty array.
pub fn min_val(data : Array[Double]) -> Double {
  let n = data.length()
  if n == 0 {
    return 0.0 / 0.0 // NaN
  }
  let mut result = data[0]
  for i = 1; i < n; i = i + 1 {
    if data[i] < result {
      result = data[i]
    }
  }
  result
}

///|
/// Compute the maximum value in the data.
///
/// Returns `NaN` for an empty array.
pub fn max_val(data : Array[Double]) -> Double {
  let n = data.length()
  if n == 0 {
    return 0.0 / 0.0 // NaN
  }
  let mut result = data[0]
  for i = 1; i < n; i = i + 1 {
    if data[i] > result {
      result = data[i]
    }
  }
  result
}

///|
/// Compute the range (max - min) of the data.
///
/// Returns `NaN` for an empty array.
pub fn range_val(data : Array[Double]) -> Double {
  let n = data.length()
  if n == 0 {
    return 0.0 / 0.0 // NaN
  }
  max_val(data) - min_val(data)
}

///|
/// Compute the mode (most frequent value) of the data.
///
/// Sorts a copy of the data, then scans for the longest run of equal values.
/// If multiple values share the highest frequency, returns the smallest one
/// (since the array is sorted ascending and ties are broken by first
/// occurrence).
///
/// Returns `NaN` for an empty array.
pub fn mode(data : Array[Double]) -> Double {
  let n = data.length()
  if n == 0 {
    return 0.0 / 0.0 // NaN
  }
  let sorted = data.copy()
  sorted.sort()
  let mut best_val = sorted[0]
  let mut best_count = 1
  let mut curr_val = sorted[0]
  let mut curr_count = 1
  for i = 1; i < n; i = i + 1 {
    if sorted[i] == curr_val {
      curr_count = curr_count + 1
    } else {
      if curr_count > best_count {
        best_val = curr_val
        best_count = curr_count
      }
      curr_val = sorted[i]
      curr_count = 1
    }
  }
  // Check the last run.
  if curr_count > best_count {
    best_val = curr_val
  }
  best_val
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "descriptive: sum_val basic" {
  assert_true((sum_val([1.0, 2.0, 3.0, 4.0, 5.0]) - 15.0).abs() < 1.0e-10)
  assert_true((sum_val([10.0, 20.0, 30.0]) - 60.0).abs() < 1.0e-10)
  assert_true((sum_val([-1.0, 1.0]) - 0.0).abs() < 1.0e-10)
}

///|
test "descriptive: sum_val single" {
  assert_true((sum_val([42.0]) - 42.0).abs() < 1.0e-10)
}

///|
test "descriptive: sum_val empty" {
  assert_true(sum_val([]).abs() < 1.0e-10)
}

///|
test "descriptive: mean basic" {
  assert_true((mean([1.0, 2.0, 3.0, 4.0, 5.0]) - 3.0).abs() < 1.0e-10)
  assert_true((mean([10.0, 20.0]) - 15.0).abs() < 1.0e-10)
  assert_true((mean([0.0, 0.0, 0.0]) - 0.0).abs() < 1.0e-10)
}

///|
test "descriptive: mean negative" {
  assert_true((mean([-2.0, -4.0, -6.0]) - -4.0).abs() < 1.0e-10)
  assert_true((mean([-5.0, 5.0]) - 0.0).abs() < 1.0e-10)
}

///|
test "descriptive: mean empty" {
  assert_true(mean([]).abs() < 1.0e-10)
}

///|
test "descriptive: variance population" {
  // [1,2,3,4,5]: mean=3, var = (4+1+0+1+4)/5 = 2.0
  assert_true((variance([1.0, 2.0, 3.0, 4.0, 5.0]) - 2.0).abs() < 1.0e-10)
}

///|
test "descriptive: variance constant data" {
  assert_true(variance([7.0, 7.0, 7.0]).abs() < 1.0e-10)
}

///|
test "descriptive: variance empty" {
  assert_true(variance([]).abs() < 1.0e-10)
}

///|
test "descriptive: sample_variance basic" {
  // [1,2,3,4,5]: mean=3, sample_var = (4+1+0+1+4)/4 = 2.5
  assert_true(
    (sample_variance([1.0, 2.0, 3.0, 4.0, 5.0]) - 2.5).abs() < 1.0e-10,
  )
}

///|
test "descriptive: sample_variance single element" {
  assert_true(sample_variance([42.0]).is_nan())
}

///|
test "descriptive: sample_variance empty" {
  assert_true(sample_variance([]).is_nan())
}

///|
test "descriptive: stddev population" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0]
  let sd = stddev(data)
  // sqrt(2.0) ~ 1.41421356
  assert_true((sd - 2.0.sqrt()).abs() < 1.0e-10)
}

///|
test "descriptive: stddev constant" {
  assert_true(stddev([3.0, 3.0, 3.0]).abs() < 1.0e-10)
}

///|
test "descriptive: stddev empty" {
  assert_true(stddev([]).abs() < 1.0e-10)
}

///|
test "descriptive: sample_stddev basic" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0]
  let sd = sample_stddev(data)
  // sqrt(2.5) ~ 1.58118883
  assert_true((sd - 2.5.sqrt()).abs() < 1.0e-10)
}

///|
test "descriptive: sample_stddev single" {
  assert_true(sample_stddev([1.0]).is_nan())
}

///|
test "descriptive: median odd count" {
  assert_true((median([1.0, 2.0, 3.0, 4.0, 5.0]) - 3.0).abs() < 1.0e-10)
  assert_true((median([5.0, 3.0, 1.0, 4.0, 2.0]) - 3.0).abs() < 1.0e-10)
}

///|
test "descriptive: median even count" {
  // [1,2,3,4] sorted → median = (2+3)/2 = 2.5
  assert_true((median([1.0, 2.0, 3.0, 4.0]) - 2.5).abs() < 1.0e-10)
  // [4,3,2,1] sorted → [1,2,3,4] → median = 2.5
  assert_true((median([4.0, 3.0, 2.0, 1.0]) - 2.5).abs() < 1.0e-10)
}

///|
test "descriptive: median single" {
  assert_true((median([42.0]) - 42.0).abs() < 1.0e-10)
}

///|
test "descriptive: median empty" {
  assert_true(median([]).is_nan())
}

///|
test "descriptive: median does not mutate input" {
  let data = [5.0, 3.0, 1.0, 4.0, 2.0]
  let _ = median(data)
  // Original array should be unchanged.
  assert_true((data[0] - 5.0).abs() < 1.0e-10)
  assert_true((data[4] - 2.0).abs() < 1.0e-10)
}

///|
test "descriptive: quantile min and max" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0]
  assert_true((quantile(data, 0.0) - 1.0).abs() < 1.0e-10)
  assert_true((quantile(data, 1.0) - 5.0).abs() < 1.0e-10)
}

///|
test "descriptive: quantile median" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0]
  assert_true((quantile(data, 0.5) - 3.0).abs() < 1.0e-10)
}

///|
test "descriptive: quantile quartiles odd" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0]
  // pos = 0.25 * 4 = 1.0 → sorted[1] = 2.0
  assert_true((quantile(data, 0.25) - 2.0).abs() < 1.0e-10)
  // pos = 0.75 * 4 = 3.0 → sorted[3] = 4.0
  assert_true((quantile(data, 0.75) - 4.0).abs() < 1.0e-10)
}

///|
test "descriptive: quantile interpolation even" {
  let data = [1.0, 2.0, 3.0, 4.0]
  // q=0.5: pos = 0.5*3 = 1.5, lo=1, hi=2, frac=0.5 → 2 + (3-2)*0.5 = 2.5
  assert_true((quantile(data, 0.5) - 2.5).abs() < 1.0e-10)
  // q=0.25: pos = 0.25*3 = 0.75, lo=0, hi=1, frac=0.75 → 1 + (2-1)*0.75 = 1.75
  assert_true((quantile(data, 0.25) - 1.75).abs() < 1.0e-10)
  // q=0.75: pos = 0.75*3 = 2.25, lo=2, hi=3, frac=0.25 → 3 + (4-3)*0.25 = 3.25
  assert_true((quantile(data, 0.75) - 3.25).abs() < 1.0e-10)
}

///|
test "descriptive: quantile empty" {
  assert_true(quantile([], 0.5).is_nan())
}

///|
test "descriptive: quantile does not mutate input" {
  let data = [5.0, 1.0, 3.0]
  let _ = quantile(data, 0.5)
  assert_true((data[0] - 5.0).abs() < 1.0e-10)
}

///|
test "descriptive: min_val basic" {
  assert_true((min_val([3.0, 1.0, 4.0, 1.0, 5.0]) - 1.0).abs() < 1.0e-10)
  assert_true((min_val([10.0, 20.0, 30.0]) - 10.0).abs() < 1.0e-10)
}

///|
test "descriptive: min_val negative" {
  assert_true((min_val([-3.0, -1.0, -4.0]) - -4.0).abs() < 1.0e-10)
}

///|
test "descriptive: min_val single" {
  assert_true((min_val([42.0]) - 42.0).abs() < 1.0e-10)
}

///|
test "descriptive: min_val empty" {
  assert_true(min_val([]).is_nan())
}

///|
test "descriptive: max_val basic" {
  assert_true((max_val([3.0, 1.0, 4.0, 1.0, 5.0]) - 5.0).abs() < 1.0e-10)
  assert_true((max_val([10.0, 20.0, 30.0]) - 30.0).abs() < 1.0e-10)
}

///|
test "descriptive: max_val negative" {
  assert_true((max_val([-3.0, -1.0, -4.0]) - -1.0).abs() < 1.0e-10)
}

///|
test "descriptive: max_val single" {
  assert_true((max_val([42.0]) - 42.0).abs() < 1.0e-10)
}

///|
test "descriptive: max_val empty" {
  assert_true(max_val([]).is_nan())
}

///|
test "descriptive: range_val basic" {
  assert_true((range_val([3.0, 1.0, 4.0, 1.0, 5.0]) - 4.0).abs() < 1.0e-10)
  assert_true((range_val([10.0, 20.0, 30.0]) - 20.0).abs() < 1.0e-10)
}

///|
test "descriptive: range_val single" {
  assert_true(range_val([42.0]).abs() < 1.0e-10)
}

///|
test "descriptive: range_val empty" {
  assert_true(range_val([]).is_nan())
}

///|
test "descriptive: mode basic" {
  assert_true((mode([1.0, 2.0, 2.0, 3.0, 3.0, 3.0]) - 3.0).abs() < 1.0e-10)
  assert_true((mode([4.0, 4.0, 4.0, 1.0, 2.0]) - 4.0).abs() < 1.0e-10)
}

///|
test "descriptive: mode tie returns smallest" {
  // Both 1.0 and 2.0 appear twice; should return 1.0 (smallest).
  assert_true((mode([1.0, 1.0, 2.0, 2.0]) - 1.0).abs() < 1.0e-10)
}

///|
test "descriptive: mode all unique" {
  // All unique → every value has count 1; returns the smallest.
  assert_true((mode([3.0, 1.0, 2.0]) - 1.0).abs() < 1.0e-10)
}

///|
test "descriptive: mode single" {
  assert_true((mode([42.0]) - 42.0).abs() < 1.0e-10)
}

///|
test "descriptive: mode empty" {
  assert_true(mode([]).is_nan())
}

///|
test "descriptive: mode does not mutate input" {
  let data = [3.0, 1.0, 2.0, 1.0]
  let _ = mode(data)
  assert_true((data[0] - 3.0).abs() < 1.0e-10)
}

///|
test "descriptive: relationship variance and sample_variance" {
  let data = [1.0, 2.0, 3.0, 4.0, 5.0]
  let pop_var = variance(data)
  let samp_var = sample_variance(data)
  // sample_variance = pop_variance * n / (n-1)
  let n = 5.0
  assert_true((samp_var - pop_var * n / (n - 1.0)).abs() < 1.0e-10)
}

///|
test "descriptive: relationship stddev and variance" {
  let data = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
  assert_true((stddev(data) - variance(data).sqrt()).abs() < 1.0e-10)
  assert_true(
    (sample_stddev(data) - sample_variance(data).sqrt()).abs() < 1.0e-10,
  )
}

///|
test "descriptive: large dataset" {
  // 1 to 100: mean = 50.5, sum = 5050
  let data = Array::makei(100, fn(i) { (i + 1).to_double() })
  assert_true((sum_val(data) - 5050.0).abs() < 1.0e-8)
  assert_true((mean(data) - 50.5).abs() < 1.0e-10)
  assert_true((min_val(data) - 1.0).abs() < 1.0e-10)
  assert_true((max_val(data) - 100.0).abs() < 1.0e-10)
  assert_true((range_val(data) - 99.0).abs() < 1.0e-10)
  // Median of 1..100 (even count) = (50+51)/2 = 50.5
  assert_true((median(data) - 50.5).abs() < 1.0e-10)
}
