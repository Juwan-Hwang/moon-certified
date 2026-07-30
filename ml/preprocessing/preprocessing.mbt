/// Feature Preprocessing — StandardScaler, MinMaxScaler, OneHotEncoder.
///
/// Provides standard data transformation utilities used in ML pipelines:
///
/// - **`StandardScaler`**: Standardize features to zero mean and unit
///   variance (`z = (x - μ) / σ`). Essential for gradient-based methods
///   (SVM, MLP, logistic regression) and distance-based methods (KNN, K-Means).
///
/// - **`MinMaxScaler`**: Scale features to `[min, max]` range (default
///   `[0, 1]`). Preserves zero values and relationships, suitable for
///   sparse data and when bounded output is needed.
///
/// - **`OneHotEncoder`**: Encode categorical integer labels as one-hot
///   vectors. Each label `i` becomes a vector with 1 at position `i`
///   and 0 elsewhere.
///
/// ## API Pattern
///
/// All scalers follow the scikit-learn pattern:
/// 1. Create with `new()` / `with_range()`
/// 2. `fit(scaler, X)` — compute statistics from training data
/// 3. `transform(scaler, X)` — apply transformation
/// 4. `fit_transform(scaler, X)` — convenience: fit then transform
/// 5. `inverse_transform(scaler, X)` — reverse the transformation
///
/// ## References
///
/// - scikit-learn preprocessing documentation
/// - "Feature Scaling" in Bishop, "Pattern Recognition and Machine Learning"
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Local math helpers
// ---------------------------------------------------------------------------

fn sqrt_double(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut guess = x
  if guess > 1.0 {
    guess = x / 2.0
  }
  for i = 0; i < 30; i = i + 1 {
    guess = (guess + x / guess) / 2.0
  }
  guess
}

// ---------------------------------------------------------------------------
// StandardScaler
// ---------------------------------------------------------------------------

///|
/// Standardize features by removing the mean and scaling to unit variance.
///
/// `z = (x - μ) / σ` where μ is the mean and σ is the standard deviation
/// of the training samples. If σ is zero for a feature (constant column),
/// that feature is set to zero in the transformed output.
///
/// ## Complexity
///
/// - `fit`: O(n · d) where n = samples, d = features
/// - `transform`: O(n · d)
/// - `inverse_transform`: O(n · d)
pub struct StandardScaler {
  priv mut means : Array[Double]
  priv mut stds : Array[Double]
  priv mut fitted : Bool
  priv mut n_features : Int
}

///|
/// Create a StandardScaler. Call `fit` before `transform`.
pub fn StandardScaler::new() -> StandardScaler {
  { means: [], stds: [], fitted: false, n_features: 0 }
}

///|
/// Compute the mean and standard deviation for each feature.
///
/// `X` is an array of feature vectors (n_samples × n_features).
/// Returns `false` if `X` is empty.
pub fn StandardScaler::fit(
  scaler : StandardScaler,
  x : Array[Array[Double]],
) -> Bool {
  let n = x.length()
  if n == 0 {
    return false
  }
  let d = x[0].length()
  if d == 0 {
    return false
  }
  scaler.n_features = d
  // Compute means
  let means = Array::make(d, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < d; j = j + 1 {
      if j < x[i].length() {
        means[j] = means[j] + x[i][j]
      }
    }
  }
  for j = 0; j < d; j = j + 1 {
    means[j] = means[j] / n.to_double()
  }
  // Compute standard deviations (population std)
  let stds = Array::make(d, 0.0)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < d; j = j + 1 {
      if j < x[i].length() {
        let diff = x[i][j] - means[j]
        stds[j] = stds[j] + diff * diff
      }
    }
  }
  for j = 0; j < d; j = j + 1 {
    let variance = stds[j] / n.to_double()
    stds[j] = sqrt_double(variance)
    // Avoid division by zero: if std is 0, set to 1 (feature is constant)
    if stds[j] == 0.0 {
      stds[j] = 1.0
    }
  }
  scaler.means = means
  scaler.stds = stds
  scaler.fitted = true
  true
}

///|
/// Transform `X` using the fitted mean and std.
/// Returns `None` if `fit` has not been called.
pub fn StandardScaler::transform(
  scaler : StandardScaler,
  x : Array[Array[Double]],
) -> Array[Array[Double]]? {
  if !scaler.fitted {
    return None
  }
  let d = scaler.n_features
  let result : Array[Array[Double]] = []
  for i = 0; i < x.length(); i = i + 1 {
    let row = Array::make(d, 0.0)
    for j = 0; j < d && j < x[i].length(); j = j + 1 {
      row[j] = (x[i][j] - scaler.means[j]) / scaler.stds[j]
    }
    result.push(row)
  }
  Some(result)
}

///|
/// Fit and transform in one step.
pub fn StandardScaler::fit_transform(
  scaler : StandardScaler,
  x : Array[Array[Double]],
) -> Array[Array[Double]]? {
  if !StandardScaler::fit(scaler, x) {
    return None
  }
  StandardScaler::transform(scaler, x)
}

///|
/// Reverse the transformation: `x = z * σ + μ`.
pub fn StandardScaler::inverse_transform(
  scaler : StandardScaler,
  z : Array[Array[Double]],
) -> Array[Array[Double]]? {
  if !scaler.fitted {
    return None
  }
  let d = scaler.n_features
  let result : Array[Array[Double]] = []
  for i = 0; i < z.length(); i = i + 1 {
    let row = Array::make(d, 0.0)
    for j = 0; j < d && j < z[i].length(); j = j + 1 {
      row[j] = z[i][j] * scaler.stds[j] + scaler.means[j]
    }
    result.push(row)
  }
  Some(result)
}

///|
/// Get the fitted means (empty if not fitted).
pub fn StandardScaler::means(scaler : StandardScaler) -> Array[Double] {
  Array::copy(scaler.means)
}

///|
/// Get the fitted standard deviations (empty if not fitted).
pub fn StandardScaler::stds(scaler : StandardScaler) -> Array[Double] {
  Array::copy(scaler.stds)
}

// ---------------------------------------------------------------------------
// MinMaxScaler
// ---------------------------------------------------------------------------

///|
/// Scale features to a given range (default [0, 1]).
///
/// `z = (x - min) / (max - min) * (range_max - range_min) + range_min`
///
/// If `max == min` for a feature (constant column), the transformed
/// value is set to `range_min`.
///
/// ## Complexity
///
/// - `fit`: O(n · d)
/// - `transform`: O(n · d)
pub struct MinMaxScaler {
  priv mut mins : Array[Double]
  priv mut maxs : Array[Double]
  priv mut fitted : Bool
  priv mut n_features : Int
  priv range_min : Double
  priv range_max : Double
}

///|
/// Create a MinMaxScaler with default range [0, 1].
pub fn MinMaxScaler::new() -> MinMaxScaler {
  { mins: [], maxs: [], fitted: false, n_features: 0, range_min: 0.0, range_max: 1.0 }
}

///|
/// Create a MinMaxScaler with a custom output range.
pub fn MinMaxScaler::with_range(min : Double, max : Double) -> MinMaxScaler {
  let lo = if min < max { min } else { 0.0 }
  let hi = if min < max { max } else { 1.0 }
  { mins: [], maxs: [], fitted: false, n_features: 0, range_min: lo, range_max: hi }
}

///|
/// Compute min and max for each feature.
pub fn MinMaxScaler::fit(
  scaler : MinMaxScaler,
  x : Array[Array[Double]],
) -> Bool {
  let n = x.length()
  if n == 0 {
    return false
  }
  let d = x[0].length()
  if d == 0 {
    return false
  }
  scaler.n_features = d
  // Initialize min/max from the first sample's actual column values
  let mins = Array::make(d, 0.0)
  let maxs = Array::make(d, 0.0)
  for j = 0; j < d; j = j + 1 {
    if j < x[0].length() {
      mins[j] = x[0][j]
      maxs[j] = x[0][j]
    }
  }
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < d && j < x[i].length(); j = j + 1 {
      if x[i][j] < mins[j] {
        mins[j] = x[i][j]
      }
      if x[i][j] > maxs[j] {
        maxs[j] = x[i][j]
      }
    }
  }
  scaler.mins = mins
  scaler.maxs = maxs
  scaler.fitted = true
  true
}

///|
/// Transform `X` to the configured range.
pub fn MinMaxScaler::transform(
  scaler : MinMaxScaler,
  x : Array[Array[Double]],
) -> Array[Array[Double]]? {
  if !scaler.fitted {
    return None
  }
  let d = scaler.n_features
  let span = scaler.range_max - scaler.range_min
  let result : Array[Array[Double]] = []
  for i = 0; i < x.length(); i = i + 1 {
    let row = Array::make(d, 0.0)
    for j = 0; j < d && j < x[i].length(); j = j + 1 {
      let range = scaler.maxs[j] - scaler.mins[j]
      if range == 0.0 {
        row[j] = scaler.range_min
      } else {
        row[j] = (x[i][j] - scaler.mins[j]) / range * span + scaler.range_min
      }
    }
    result.push(row)
  }
  Some(result)
}

///|
/// Fit and transform in one step.
pub fn MinMaxScaler::fit_transform(
  scaler : MinMaxScaler,
  x : Array[Array[Double]],
) -> Array[Array[Double]]? {
  if !MinMaxScaler::fit(scaler, x) {
    return None
  }
  MinMaxScaler::transform(scaler, x)
}

///|
/// Reverse the transformation.
pub fn MinMaxScaler::inverse_transform(
  scaler : MinMaxScaler,
  z : Array[Array[Double]],
) -> Array[Array[Double]]? {
  if !scaler.fitted {
    return None
  }
  let d = scaler.n_features
  let span = scaler.range_max - scaler.range_min
  let result : Array[Array[Double]] = []
  for i = 0; i < z.length(); i = i + 1 {
    let row = Array::make(d, 0.0)
    for j = 0; j < d && j < z[i].length(); j = j + 1 {
      let range = scaler.maxs[j] - scaler.mins[j]
      if range == 0.0 {
        row[j] = scaler.mins[j]
      } else {
        row[j] = (z[i][j] - scaler.range_min) / span * range + scaler.mins[j]
      }
    }
    result.push(row)
  }
  Some(result)
}

// ---------------------------------------------------------------------------
// OneHotEncoder
// ---------------------------------------------------------------------------

///|
/// Encode categorical integer labels as one-hot vectors.
///
/// Given `n_classes` possible labels (0 to n_classes-1), encodes each
/// label `i` as a vector of length `n_classes` with 1 at position `i`
/// and 0 elsewhere.
///
/// ## Complexity
///
/// - `transform`: O(n · d) where n = samples, d = n_classes
pub struct OneHotEncoder {
  priv n_classes : Int
}

///|
/// Create a OneHotEncoder for labels in `[0, n_classes)`.
/// If `n_classes <= 0`, it is set to 1.
pub fn OneHotEncoder::new(n_classes : Int) -> OneHotEncoder {
  let nc = if n_classes <= 0 { 1 } else { n_classes }
  { n_classes: nc }
}

///|
/// Encode a single label as a one-hot vector.
/// If the label is out of range `[0, n_classes)`, the vector is all zeros.
pub fn OneHotEncoder::encode(encoder : OneHotEncoder, label : Int) -> Array[Double] {
  let v = Array::make(encoder.n_classes, 0.0)
  if label >= 0 && label < encoder.n_classes {
    v[label] = 1.0
  }
  v
}

///|
/// Encode an array of labels as one-hot vectors.
pub fn OneHotEncoder::transform(
  encoder : OneHotEncoder,
  labels : Array[Int],
) -> Array[Array[Double]] {
  let result : Array[Array[Double]] = []
  for i = 0; i < labels.length(); i = i + 1 {
    result.push(OneHotEncoder::encode(encoder, labels[i]))
  }
  result
}

///|
/// Decode a one-hot vector back to a label (argmax).
/// Returns -1 if the vector is empty.
pub fn OneHotEncoder::decode(
  _encoder : OneHotEncoder,
  vec : Array[Double],
) -> Int {
  let n = vec.length()
  if n == 0 {
    return -1
  }
  let mut best = 0
  let mut best_val = vec[0]
  for i = 1; i < n; i = i + 1 {
    if vec[i] > best_val {
      best_val = vec[i]
      best = i
    }
  }
  best
}

///|
/// Number of classes this encoder was configured for.
pub fn OneHotEncoder::n_classes(encoder : OneHotEncoder) -> Int {
  encoder.n_classes
}

// ---------------------------------------------------------------------------
// Tests: StandardScaler
// ---------------------------------------------------------------------------

///|
test "standard_scaler: basic fit_transform" {
  let scaler = StandardScaler::new()
  let x : Array[Array[Double]] = [[1.0, 10.0], [3.0, 30.0], [5.0, 50.0]]
  let result = StandardScaler::fit_transform(scaler, x)
  match result {
    Some(z) => {
      // Mean of col0 = 3, std = sqrt((4+0+4)/3) = sqrt(8/3) ≈ 1.6330
      // (1-3)/1.6330 ≈ -1.2247, (3-3)/1.6330 = 0, (5-3)/1.6330 ≈ 1.2247
      assert_true(z[0][0] < -1.0 && z[0][0] > -1.5)
      assert_true(z[1][0] > -0.1 && z[1][0] < 0.1)
      assert_true(z[2][0] > 1.0 && z[2][0] < 1.5)
    }
    None => assert_true(false)
  }
}

///|
test "standard_scaler: zero mean and unit variance" {
  let scaler = StandardScaler::new()
  let x : Array[Array[Double]] = [[2.0], [4.0], [6.0], [8.0]]
  ignore(StandardScaler::fit(scaler, x))
  // Mean = 5, std = sqrt((9+1+1+9)/4) = sqrt(5) ≈ 2.236
  let means = StandardScaler::means(scaler)
  let stds = StandardScaler::stds(scaler)
  assert_true(means[0] > 4.9 && means[0] < 5.1)
  assert_true(stds[0] > 2.0 && stds[0] < 2.5)
}

///|
test "standard_scaler: inverse_transform" {
  let scaler = StandardScaler::new()
  let x : Array[Array[Double]] = [[1.0, 10.0], [3.0, 30.0], [5.0, 50.0]]
  let z = StandardScaler::fit_transform(scaler, x)
  match z {
    Some(z_vals) => {
      let recovered = StandardScaler::inverse_transform(scaler, z_vals)
      match recovered {
        Some(r) => {
          for i = 0; i < x.length(); i = i + 1 {
            for j = 0; j < 2; j = j + 1 {
              assert_true((r[i][j] - x[i][j]).abs() < 0.0000000001)
            }
          }
        }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "standard_scaler: constant column" {
  let scaler = StandardScaler::new()
  let x : Array[Array[Double]] = [[5.0], [5.0], [5.0]]
  let result = StandardScaler::fit_transform(scaler, x)
  match result {
    Some(z) => {
      // Constant column → std set to 1, so z = (5-5)/1 = 0
      for i = 0; i < 3; i = i + 1 {
        assert_true(z[i][0] == 0.0)
      }
    }
    None => assert_true(false)
  }
}

///|
test "standard_scaler: empty input" {
  let scaler = StandardScaler::new()
  let x : Array[Array[Double]] = []
  assert_false(StandardScaler::fit(scaler, x))
}

///|
test "standard_scaler: transform before fit" {
  let scaler = StandardScaler::new()
  let x : Array[Array[Double]] = [[1.0, 2.0]]
  assert_eq(StandardScaler::transform(scaler, x), None)
}

// ---------------------------------------------------------------------------
// Tests: MinMaxScaler
// ---------------------------------------------------------------------------

///|
test "minmax_scaler: default range [0,1]" {
  let scaler = MinMaxScaler::new()
  let x : Array[Array[Double]] = [[0.0], [5.0], [10.0]]
  let result = MinMaxScaler::fit_transform(scaler, x)
  match result {
    Some(z) => {
      assert_true(z[0][0] == 0.0)
      assert_true(z[1][0] == 0.5)
      assert_true(z[2][0] == 1.0)
    }
    None => assert_true(false)
  }
}

///|
test "minmax_scaler: custom range [-1,1]" {
  let scaler = MinMaxScaler::with_range(-1.0, 1.0)
  let x : Array[Array[Double]] = [[0.0], [5.0], [10.0]]
  let result = MinMaxScaler::fit_transform(scaler, x)
  match result {
    Some(z) => {
      assert_true(z[0][0] == -1.0)
      assert_true(z[1][0] == 0.0)
      assert_true(z[2][0] == 1.0)
    }
    None => assert_true(false)
  }
}

///|
test "minmax_scaler: inverse_transform" {
  let scaler = MinMaxScaler::new()
  let x : Array[Array[Double]] = [[1.0, 10.0], [3.0, 30.0], [5.0, 50.0]]
  let z = MinMaxScaler::fit_transform(scaler, x)
  match z {
    Some(z_vals) => {
      let recovered = MinMaxScaler::inverse_transform(scaler, z_vals)
      match recovered {
        Some(r) => {
          for i = 0; i < x.length(); i = i + 1 {
            for j = 0; j < 2; j = j + 1 {
              assert_true((r[i][j] - x[i][j]).abs() < 0.0000000001)
            }
          }
        }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "minmax_scaler: constant column" {
  let scaler = MinMaxScaler::new()
  let x : Array[Array[Double]] = [[3.0], [3.0], [3.0]]
  let result = MinMaxScaler::fit_transform(scaler, x)
  match result {
    Some(z) => {
      // Constant → set to range_min (0.0)
      for i = 0; i < 3; i = i + 1 {
        assert_true(z[i][0] == 0.0)
      }
    }
    None => assert_true(false)
  }
}

///|
test "minmax_scaler: multi-feature" {
  let scaler = MinMaxScaler::new()
  let x : Array[Array[Double]] = [[0.0, 100.0], [10.0, 200.0], [20.0, 300.0]]
  let result = MinMaxScaler::fit_transform(scaler, x)
  match result {
    Some(z) => {
      assert_true(z[0][0] == 0.0)
      assert_true(z[0][1] == 0.0)
      assert_true(z[1][0] == 0.5)
      assert_true(z[1][1] == 0.5)
      assert_true(z[2][0] == 1.0)
      assert_true(z[2][1] == 1.0)
    }
    None => assert_true(false)
  }
}

// ---------------------------------------------------------------------------
// Tests: OneHotEncoder
// ---------------------------------------------------------------------------

///|
test "onehot: basic encode" {
  let enc = OneHotEncoder::new(3)
  let v0 = OneHotEncoder::encode(enc, 0)
  let v1 = OneHotEncoder::encode(enc, 1)
  let v2 = OneHotEncoder::encode(enc, 2)
  assert_eq(v0, [1.0, 0.0, 0.0])
  assert_eq(v1, [0.0, 1.0, 0.0])
  assert_eq(v2, [0.0, 0.0, 1.0])
}

///|
test "onehot: out of range" {
  let enc = OneHotEncoder::new(3)
  let v_neg = OneHotEncoder::encode(enc, -1)
  let v_over = OneHotEncoder::encode(enc, 5)
  assert_eq(v_neg, [0.0, 0.0, 0.0])
  assert_eq(v_over, [0.0, 0.0, 0.0])
}

///|
test "onehot: transform batch" {
  let enc = OneHotEncoder::new(4)
  let labels = [0, 2, 1, 3]
  let result = OneHotEncoder::transform(enc, labels)
  assert_eq(result[0], [1.0, 0.0, 0.0, 0.0])
  assert_eq(result[1], [0.0, 0.0, 1.0, 0.0])
  assert_eq(result[2], [0.0, 1.0, 0.0, 0.0])
  assert_eq(result[3], [0.0, 0.0, 0.0, 1.0])
}

///|
test "onehot: decode" {
  let enc = OneHotEncoder::new(3)
  assert_eq(OneHotEncoder::decode(enc, [1.0, 0.0, 0.0]), 0)
  assert_eq(OneHotEncoder::decode(enc, [0.0, 1.0, 0.0]), 1)
  assert_eq(OneHotEncoder::decode(enc, [0.0, 0.0, 1.0]), 2)
  assert_eq(OneHotEncoder::decode(enc, [0.1, 0.9, 0.0]), 1)
}

///|
test "onehot: n_classes" {
  let enc = OneHotEncoder::new(5)
  assert_eq(OneHotEncoder::n_classes(enc), 5)
}

///|
test "onehot: invalid n_classes" {
  let enc = OneHotEncoder::new(-3)
  assert_eq(OneHotEncoder::n_classes(enc), 1)
  let v = OneHotEncoder::encode(enc, 0)
  assert_eq(v, [1.0])
}
