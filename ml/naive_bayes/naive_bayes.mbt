/// Naive Bayes classifiers.
///
/// This module provides three production-grade Naive Bayes implementations:
///
/// - **GaussianNB**: for continuous features assumed to follow a Gaussian
///   (normal) distribution per class. Suitable for real-valued sensor data,
///   biometrics, etc.
/// - **MultinomialNB**: for discrete count features (e.g., word counts in
///   text classification). Uses additive (Laplace/Lidstone) smoothing.
/// - **BernoulliNB**: for binary/boolean features.
///
/// ## Algorithm
///
/// Naive Bayes applies Bayes' theorem with the "naive" assumption of
/// conditional independence between features given the class:
///
/// ```text
/// P(y | x_1, ..., x_n) ∝ P(y) * ∏ P(x_i | y)
/// ```
///
/// The class with the highest posterior probability is chosen. The classifier
/// works in log-space to avoid numerical underflow:
///
/// ```text
/// log P(y | x) ∝ log P(y) + Σ log P(x_i | y)
/// ```
///
/// ## Smoothing
///
/// - **GaussianNB**: variance is floored at `var_smoothing` * max(variance) to
///   prevent division-by-zero on degenerate features.
/// - **MultinomialNB**: additive (Laplace) smoothing with parameter `alpha`
///   (default 1.0). Setting `alpha = 0` disables smoothing (not recommended).
/// - **BernoulliNB**: same additive smoothing, plus a binarization threshold.
///
/// ## Numerical stability
///
/// All probability computations are performed in log-space. The Gaussian
/// implementation uses the log-PDF to avoid overflow/underflow.
///
/// ## References
///
/// - Manning, Raghavan, Schütze. "Introduction to Information Retrieval,"
///   Ch. 13 (Naive Bayes text classification).
/// - Pedregosa et al. "scikit-learn: Machine Learning in Python" (GaussianNB,
///   MultinomialNB, BernoulliNB API design).
/// - Domingos & Pazzani (1997). "On the Optimality of the Simple
///   Bayesian Classifier under Zero-One Loss."
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Helper: create a fresh 2D array (each row is an independent allocation)
// ---------------------------------------------------------------------------

///|
/// Create a 2D array with `rows` rows and `cols` columns, each element
/// initialised to `init`.
///
/// Each row is a separate allocation so that modifying one row does not
/// affect others.
fn make_2d(rows : Int, cols : Int, init : Double) -> Array[Array[Double]] {
  let result : Array[Array[Double]] = []
  for _ in 0..<rows {
    result.push(Array::make(cols, init))
  }
  result
}

// ---------------------------------------------------------------------------
// Gaussian Naive Bayes
// ---------------------------------------------------------------------------

///|
/// Gaussian Naive Bayes classifier for continuous features.
///
/// Models each feature per class as a Gaussian distribution, parameterised
/// by the sample mean and sample variance of the training data.
pub struct GaussianNB {
  classes : Array[Int]
  class_priors : Array[Double] // log priors
  means : Array[Array[Double]] // [class][feature]
  variances : Array[Array[Double]] // [class][feature]
  n_features : Int
}

///|
/// Train a Gaussian Naive Bayes classifier.
///
/// - `X`: training samples, shape `[n_samples][n_features]`.
/// - `y`: class labels, length `n_samples`.
/// - `var_smoothing`: portion of the largest variance added to all variances
///   for numerical stability (default: `1e-9`).
///
/// Returns the trained classifier.
pub fn gaussian_fit(
  x : Array[Array[Double]],
  y : Array[Int],
  var_smoothing : Double,
) -> GaussianNB {
  let n_samples = x.length()
  let n_features = if n_samples > 0 { x[0].length() } else { 0 }
  // Collect unique classes (sorted).
  let class_set : Map[Int, Unit] = Map([])
  let classes : Array[Int] = []
  for i = 0; i < n_samples; i = i + 1 {
    let label = y[i]
    if !class_set.contains(label) {
      class_set[label] = ()
      classes.push(label)
    }
  }
  classes.sort_by(fn(a, b) { a.compare(b) })
  // Build class -> index lookup.
  let class_index : Map[Int, Int] = Map([])
  for i = 0; i < classes.length(); i = i + 1 {
    class_index[classes[i]] = i
  }
  let n_classes = classes.length()
  // Compute per-class feature sums and counts.
  let sums = make_2d(n_classes, n_features, 0.0)
  let sq_sums = make_2d(n_classes, n_features, 0.0)
  let counts : Array[Int] = Array::make(n_classes, 0)
  for i = 0; i < n_samples; i = i + 1 {
    let ci = class_index[y[i]]
    counts[ci] = counts[ci] + 1
    for j = 0; j < n_features; j = j + 1 {
      sums[ci][j] = sums[ci][j] + x[i][j]
      sq_sums[ci][j] = sq_sums[ci][j] + x[i][j] * x[i][j]
    }
  }
  // Compute means, variances, and log priors.
  let means = make_2d(n_classes, n_features, 0.0)
  let variances = make_2d(n_classes, n_features, 0.0)
  let class_priors : Array[Double] = Array::make(n_classes, 0.0)
  // Track max variance for smoothing.
  let mut max_var = 0.0
  for c = 0; c < n_classes; c = c + 1 {
    let n = counts[c].to_double()
    class_priors[c] = @math.ln(n / n_samples.to_double())
    for j = 0; j < n_features; j = j + 1 {
      let mean = sums[c][j] / n
      means[c][j] = mean
      let variance_val = sq_sums[c][j] / n - mean * mean
      variances[c][j] = variance_val
      if variance_val > max_var {
        max_var = variance_val
      }
    }
  }
  // Apply variance smoothing.
  // When max_var is 0 (degenerate: 1 sample per class), use var_smoothing
  // directly as a minimum variance floor to prevent ln(0) in log_gaussian_pdf.
  let eps = if max_var > 0.0 {
    var_smoothing * max_var
  } else {
    var_smoothing
  }
  for c = 0; c < n_classes; c = c + 1 {
    for j = 0; j < n_features; j = j + 1 {
      variances[c][j] = variances[c][j] + eps
    }
  }
  { classes, class_priors, means, variances, n_features }
}

///|
/// Predict the class label for a single sample.
///
/// Returns the class with the highest log-posterior probability.
pub fn gaussian_predict(model : GaussianNB, x : Array[Double]) -> Int {
  let (best_label, _) = gaussian_predict_log_proba(model, x)
  best_label
}

///|
/// Predict class labels for multiple samples.
pub fn gaussian_predict_batch(
  model : GaussianNB,
  x : Array[Array[Double]],
) -> Array[Int] {
  let result : Array[Int] = []
  for i = 0; i < x.length(); i = i + 1 {
    result.push(gaussian_predict(model, x[i]))
  }
  result
}

///|
/// Compute the log-posterior probability for each class.
///
/// Returns `(predicted_label, log_probabilities)` where `log_probabilities[i]`
/// is the unnormalised log-probability for `model.classes[i]`.
pub fn gaussian_predict_log_proba(
  model : GaussianNB,
  x : Array[Double],
) -> (Int, Array[Double]) {
  let n_classes = model.classes.length()
  let log_probs : Array[Double] = Array::make(n_classes, 0.0)
  for c = 0; c < n_classes; c = c + 1 {
    let mut lp = model.class_priors[c]
    for j = 0; j < model.n_features; j = j + 1 {
      lp = lp + log_gaussian_pdf(
        x[j],
        model.means[c][j],
        model.variances[c][j],
      )
    }
    log_probs[c] = lp
  }
  // Find best class.
  let mut best_idx = 0
  for c = 1; c < n_classes; c = c + 1 {
    if log_probs[c] > log_probs[best_idx] {
      best_idx = c
    }
  }
  (model.classes[best_idx], log_probs)
}

///|
/// Log of the Gaussian PDF: ln(N(x | μ, σ²)).
///
/// ln(pdf) = -0.5 * ln(2π σ²) - (x-μ)² / (2σ²)
fn log_gaussian_pdf(x : Double, mean : Double, variance : Double) -> Double {
  let pi = 3.14159265358979323846
  -0.5 * @math.ln(2.0 * pi * variance) - (x - mean) * (x - mean) / (2.0 * variance)
}

// ---------------------------------------------------------------------------
// Multinomial Naive Bayes
// ---------------------------------------------------------------------------

///|
/// Multinomial Naive Bayes classifier for discrete count features.
///
/// Commonly used for text classification with bag-of-words or TF features.
pub struct MultinomialNB {
  classes : Array[Int]
  class_log_priors : Array[Double]
  feature_log_probs : Array[Array[Double]] // [class][feature]
  n_features : Int
}

///|
/// Train a Multinomial Naive Bayes classifier.
///
/// - `X`: count features, shape `[n_samples][n_features]` (non-negative).
/// - `y`: class labels, length `n_samples`.
/// - `alpha`: additive (Laplace/Lidstone) smoothing parameter (default: 1.0).
///
/// Returns the trained classifier.
pub fn multinomial_fit(
  x : Array[Array[Double]],
  y : Array[Int],
  alpha : Double,
) -> MultinomialNB {
  let n_samples = x.length()
  let n_features = if n_samples > 0 { x[0].length() } else { 0 }
  // Collect unique classes (sorted).
  let class_set : Map[Int, Unit] = Map([])
  let classes : Array[Int] = []
  for i = 0; i < n_samples; i = i + 1 {
    let label = y[i]
    if !class_set.contains(label) {
      class_set[label] = ()
      classes.push(label)
    }
  }
  classes.sort_by(fn(a, b) { a.compare(b) })
  let class_index : Map[Int, Int] = Map([])
  for i = 0; i < classes.length(); i = i + 1 {
    class_index[classes[i]] = i
  }
  let n_classes = classes.length()
  // Per-class feature counts.
  let feature_counts = make_2d(n_classes, n_features, 0.0)
  let class_counts : Array[Int] = Array::make(n_classes, 0)
  for i = 0; i < n_samples; i = i + 1 {
    let ci = class_index[y[i]]
    class_counts[ci] = class_counts[ci] + 1
    for j = 0; j < n_features; j = j + 1 {
      feature_counts[ci][j] = feature_counts[ci][j] + x[i][j]
    }
  }
  // Compute feature log probabilities with smoothing.
  let feature_log_probs = make_2d(n_classes, n_features, 0.0)
  let class_log_priors : Array[Double] = Array::make(n_classes, 0.0)
  for c = 0; c < n_classes; c = c + 1 {
    class_log_priors[c] = @math.ln(
      class_counts[c].to_double() / n_samples.to_double(),
    )
    let mut total = 0.0
    for j = 0; j < n_features; j = j + 1 {
      total = total + feature_counts[c][j] + alpha
    }
    for j = 0; j < n_features; j = j + 1 {
      feature_log_probs[c][j] = @math.ln(
        (feature_counts[c][j] + alpha) / total,
      )
    }
  }
  { classes, class_log_priors, feature_log_probs, n_features }
}

///|
/// Predict the class label for a single sample.
pub fn multinomial_predict(
  model : MultinomialNB,
  x : Array[Double],
) -> Int {
  let (best_label, _) = multinomial_predict_log_proba(model, x)
  best_label
}

///|
/// Predict class labels for multiple samples.
pub fn multinomial_predict_batch(
  model : MultinomialNB,
  x : Array[Array[Double]],
) -> Array[Int] {
  let result : Array[Int] = []
  for i = 0; i < x.length(); i = i + 1 {
    result.push(multinomial_predict(model, x[i]))
  }
  result
}

///|
/// Compute the log-posterior probability for each class.
///
/// Returns `(predicted_label, log_probabilities)`.
pub fn multinomial_predict_log_proba(
  model : MultinomialNB,
  x : Array[Double],
) -> (Int, Array[Double]) {
  let n_classes = model.classes.length()
  let log_probs : Array[Double] = Array::make(n_classes, 0.0)
  for c = 0; c < n_classes; c = c + 1 {
    let mut lp = model.class_log_priors[c]
    for j = 0; j < model.n_features; j = j + 1 {
      lp = lp + x[j] * model.feature_log_probs[c][j]
    }
    log_probs[c] = lp
  }
  let mut best_idx = 0
  for c = 1; c < n_classes; c = c + 1 {
    if log_probs[c] > log_probs[best_idx] {
      best_idx = c
    }
  }
  (model.classes[best_idx], log_probs)
}

// ---------------------------------------------------------------------------
// Bernoulli Naive Bayes
// ---------------------------------------------------------------------------

///|
/// Bernoulli Naive Bayes classifier for binary features.
///
/// Each feature is treated as a Bernoulli (0/1) random variable.
pub struct BernoulliNB {
  classes : Array[Int]
  class_log_priors : Array[Double]
  feature_log_probs : Array[Array[Double]] // log P(x_i=1 | y)
  feature_log_neg_probs : Array[Array[Double]] // log P(x_i=0 | y)
  n_features : Int
  binarize : Double // threshold for binarizing features (>0 means active)
}

///|
/// Train a Bernoulli Naive Bayes classifier.
///
/// - `X`: binary features, shape `[n_samples][n_features]` (values should be 0 or 1).
/// - `y`: class labels, length `n_samples`.
/// - `alpha`: additive smoothing parameter (default: 1.0).
/// - `binarize`: if > 0, features are thresholded to 0/1 at this value.
///   If <= 0, features are assumed already binary.
///
/// Returns the trained classifier.
pub fn bernoulli_fit(
  x : Array[Array[Double]],
  y : Array[Int],
  alpha : Double,
  binarize : Double,
) -> BernoulliNB {
  let n_samples = x.length()
  let n_features = if n_samples > 0 { x[0].length() } else { 0 }
  // Collect unique classes (sorted).
  let class_set : Map[Int, Unit] = Map([])
  let classes : Array[Int] = []
  for i = 0; i < n_samples; i = i + 1 {
    let label = y[i]
    if !class_set.contains(label) {
      class_set[label] = ()
      classes.push(label)
    }
  }
  classes.sort_by(fn(a, b) { a.compare(b) })
  let class_index : Map[Int, Int] = Map([])
  for i = 0; i < classes.length(); i = i + 1 {
    class_index[classes[i]] = i
  }
  let n_classes = classes.length()
  // Count feature occurrences per class.
  let feature_true = make_2d(n_classes, n_features, 0.0)
  let class_counts : Array[Int] = Array::make(n_classes, 0)
  for i = 0; i < n_samples; i = i + 1 {
    let ci = class_index[y[i]]
    class_counts[ci] = class_counts[ci] + 1
    for j = 0; j < n_features; j = j + 1 {
      let val = if binarize > 0.0 {
        if x[i][j] > binarize { 1.0 } else { 0.0 }
      } else {
        if x[i][j] > 0.0 { 1.0 } else { 0.0 }
      }
      feature_true[ci][j] = feature_true[ci][j] + val
    }
  }
  // Compute log probabilities.
  let feature_log_probs = make_2d(n_classes, n_features, 0.0)
  let feature_log_neg_probs = make_2d(n_classes, n_features, 0.0)
  let class_log_priors : Array[Double] = Array::make(n_classes, 0.0)
  for c = 0; c < n_classes; c = c + 1 {
    class_log_priors[c] = @math.ln(
      class_counts[c].to_double() / n_samples.to_double(),
    )
    let n = class_counts[c].to_double()
    for j = 0; j < n_features; j = j + 1 {
      let p1 = (feature_true[c][j] + alpha) / (n + 2.0 * alpha)
      feature_log_probs[c][j] = @math.ln(p1)
      feature_log_neg_probs[c][j] = @math.ln(1.0 - p1)
    }
  }
  {
    classes,
    class_log_priors,
    feature_log_probs,
    feature_log_neg_probs,
    n_features,
    binarize,
  }
}

///|
/// Predict the class label for a single sample.
pub fn bernoulli_predict(model : BernoulliNB, x : Array[Double]) -> Int {
  let (best_label, _) = bernoulli_predict_log_proba(model, x)
  best_label
}

///|
/// Predict class labels for multiple samples.
pub fn bernoulli_predict_batch(
  model : BernoulliNB,
  x : Array[Array[Double]],
) -> Array[Int] {
  let result : Array[Int] = []
  for i = 0; i < x.length(); i = i + 1 {
    result.push(bernoulli_predict(model, x[i]))
  }
  result
}

///|
/// Compute the log-posterior probability for each class.
///
/// Returns `(predicted_label, log_probabilities)`.
pub fn bernoulli_predict_log_proba(
  model : BernoulliNB,
  x : Array[Double],
) -> (Int, Array[Double]) {
  let n_classes = model.classes.length()
  let log_probs : Array[Double] = Array::make(n_classes, 0.0)
  for c = 0; c < n_classes; c = c + 1 {
    let mut lp = model.class_log_priors[c]
    for j = 0; j < model.n_features; j = j + 1 {
      // Apply binarization if threshold is set.
      let is_present = if model.binarize > 0.0 {
        x[j] > model.binarize
      } else {
        x[j] > 0.0
      }
      if is_present {
        lp = lp + model.feature_log_probs[c][j]
      } else {
        lp = lp + model.feature_log_neg_probs[c][j]
      }
    }
    log_probs[c] = lp
  }
  let mut best_idx = 0
  for c = 1; c < n_classes; c = c + 1 {
    if log_probs[c] > log_probs[best_idx] {
      best_idx = c
    }
  }
  (model.classes[best_idx], log_probs)
}

// ---------------------------------------------------------------------------
// Utility: accuracy
// ---------------------------------------------------------------------------

///|
/// Compute classification accuracy: fraction of correct predictions.
pub fn accuracy(y_true : Array[Int], y_pred : Array[Int]) -> Double {
  let n = y_true.length()
  if n == 0 {
    return 0.0
  }
  let mut correct = 0
  for i = 0; i < n; i = i + 1 {
    if y_true[i] == y_pred[i] {
      correct = correct + 1
    }
  }
  correct.to_double() / n.to_double()
}
