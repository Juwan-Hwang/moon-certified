/// Multi-Layer Perceptron (MLP) — feed-forward neural network.
///
/// A fully-connected network trained by mini-batch stochastic gradient
/// descent with back-propagation. Hidden layers use ReLU or Sigmoid; the
/// output layer depends on the task:
///
/// - **Regression** (MSE loss): linear output.
/// - **Binary classification** (1 output, binary cross-entropy): sigmoid.
/// - **Multi-class classification** (>1 outputs, categorical cross-entropy):
///   softmax.
///
/// Thanks to the well-known loss/activation cancellations, the output-layer
/// delta simplifies to `a_out − y` for all three settings, so back-prop is
/// uniform.
///
/// ## Algorithm
/// - **Forward**: `z[l] = W[l]·a[l−1] + b[l]`, `a[l] = act(z[l])`.
/// - **Backward**: `δ[L] = a[L] − y`; for hidden `l`,
///   `δ[l] = (W[l+1]ᵀ δ[l+1]) ⊙ act′(z[l])`; gradients
///   `∇W[l] = δ[l] ⊗ a[l−1]`, `∇b[l] = δ[l]`.
/// - **Update**: parameters are averaged over the mini-batch and stepped by
///   `−η · ∇`.
///
/// Weights are He-initialised (`U(±√(2/fan_in))`); biases start at zero.
///
/// ## Complexity
/// - Training: `O(epochs × n × Σ_l n_l·n_{l+1})`.
/// - Prediction: `O(Σ_l n_l·n_{l+1})` per row.
///
/// No external dependency: `exp`, `ln`, and the PRNG are implemented locally.
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Local transcendentals
// ---------------------------------------------------------------------------

///|
/// Natural exponential via argument halving + Taylor series (~1e-15).
fn exp_double(x : Double) -> Double {
  if x >= 700.0 {
    return 1.7976931348623157e308
  }
  if x <= -745.0 {
    return 0.0
  }
  let mut r = x
  let mut n = 0
  while r > 0.5 || r < -0.5 {
    r = r / 2.0
    n = n + 1
  }
  let mut term = 1.0
  let mut sum = 1.0
  for i = 1; i < 20; i = i + 1 {
    term = term * r / i.to_double()
    sum = sum + term
    if term < 0.0 {
      if -term < 1.0e-18 * sum {
        break
      }
    } else if term < 1.0e-18 * sum {
      break
    }
  }
  let mut result = sum
  for _i = 0; _i < n; _i = _i + 1 {
    result = result * result
  }
  result
}

///|
/// Natural logarithm via range reduction + atanh series (~1e-15).
fn ln_double(x : Double) -> Double {
  if x <= 0.0 {
    return -700.0
  }
  let mut m = x
  let mut k = 0
  while m >= 2.0 {
    m = m / 2.0
    k = k + 1
  }
  while m < 1.0 {
    m = m * 2.0
    k = k - 1
  }
  let z = (m - 1.0) / (m + 1.0)
  let z2 = z * z
  let mut term = z
  let mut sum = z
  for i = 1; i < 40; i = i + 1 {
    term = term * z2
    let inc = term / (2 * i + 1).to_double()
    sum = sum + inc
    if inc < 0.0 {
      if -inc < 1.0e-18 {
        break
      }
    } else if inc < 1.0e-18 {
      break
    }
  }
  k.to_double() * 0.6931471805599453 + 2.0 * sum
}

///|
/// Logistic sigmoid, clamped against overflow.
fn sigmoid(z : Double) -> Double {
  if z >= 35.0 {
    1.0
  } else if z <= -35.0 {
    0.0
  } else {
    1.0 / (1.0 + exp_double(-z))
  }
}

///|
/// Clamp a Double into `[lo, hi]`.
fn clampd(x : Double, lo : Double, hi : Double) -> Double {
  if x < lo {
    lo
  } else if x > hi {
    hi
  } else {
    x
  }
}

// ---------------------------------------------------------------------------
// Deterministic PRNG (31-bit LCG; range reduction uses the well-mixed high
// bits to avoid the weak low-bit periodicity of LCGs).
// ---------------------------------------------------------------------------

///|
priv struct Rng {
  mut state : Int
}

fn Rng::new(seed : Int) -> Rng {
  let s = seed & 0x7FFFFFFF
  { state: if s == 0 { 1 } else { s } }
}

fn Rng::next(self : Rng) -> Int {
  self.state = (self.state * 1103515245 + 12345) & 0x7FFFFFFF
  self.state
}

fn Rng::next_double(self : Rng) -> Double {
  self.next().to_double() / 2147483648.0
}

fn Rng::next_int(self : Rng, bound : Int) -> Int {
  if bound <= 0 {
    0
  } else {
    let v = (self.next_double() * bound.to_double()).to_int()
    if v >= bound {
      bound - 1
    } else {
      v
    }
  }
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

///|
/// Feed-forward network. Build with `new_regression` or `new_classifier`;
/// the architecture is the full layer list, e.g. `[2, 16, 1]`.
pub struct MLP {
  priv mut weights : Array[Array[Array[Double]]] // weights[l][i][j]
  priv mut biases : Array[Array[Double]] // biases[l][i]
  priv layers : Array[Int]
  priv lr : Double
  priv epochs : Int
  priv batch_size : Int
  priv mut hidden_is_relu : Bool
  priv is_classifier : Bool
  priv seed : Int
}

///|
/// Number of weight matrices (= `layers.length() − 1`).
fn n_weight_layers(mlp : MLP) -> Int {
  mlp.layers.length() - 1
}

///|
/// He-initialise weights `U(±√(2/fan_in))`, zero biases.
fn init_weights(mlp : MLP) -> Unit {
  let rng = Rng::new(mlp.seed)
  let nl = n_weight_layers(mlp)
  mlp.weights = []
  mlp.biases = []
  for l = 0; l < nl; l = l + 1 {
    let n_in = mlp.layers[l]
    let n_out = mlp.layers[l + 1]
    let scale = (2.0 / n_in.to_double()).sqrt()
    let w : Array[Array[Double]] = Array::makei(
      n_out,
      fn(_i) {
        Array::makei(n_in, fn(_j) { (rng.next_double() * 2.0 - 1.0) * scale })
      },
    )
    mlp.weights.push(w)
    mlp.biases.push(Array::make(n_out, 0.0))
  }
}

///|
/// Create a regression network (MSE loss, linear output, ReLU hidden).
///
/// - `layers`: full architecture `[n_in, hidden..., n_out]`.
/// - `lr`: learning rate (typical: 0.01). `<= 0` → 0.01.
/// - `epochs`: training epochs (typical: 500).
/// - `batch_size`: mini-batch size. `<= 0` → 1.
/// - `seed`: PRNG seed for reproducible initialisation.
pub fn new_regression(
  layers : Array[Int],
  lr : Double,
  epochs : Int,
  batch_size : Int,
  seed : Int,
) -> MLP {
  let m : MLP = {
    weights: [],
    biases: [],
    layers: Array::copy(layers),
    lr: if lr > 0.0 { lr } else { 0.01 },
    epochs: if epochs > 0 { epochs } else { 100 },
    batch_size: if batch_size > 0 { batch_size } else { 1 },
    is_classifier: false,
    hidden_is_relu: true,
    seed,
  }
  init_weights(m)
  m
}

///|
/// Create a classification network (cross-entropy loss). With one output the
/// loss is binary cross-entropy (sigmoid); with several outputs it is
/// categorical cross-entropy (softmax). Hidden activation is ReLU.
pub fn new_classifier(
  layers : Array[Int],
  lr : Double,
  epochs : Int,
  batch_size : Int,
  seed : Int,
) -> MLP {
  let m : MLP = {
    weights: [],
    biases: [],
    layers: Array::copy(layers),
    lr: if lr > 0.0 { lr } else { 0.01 },
    epochs: if epochs > 0 { epochs } else { 100 },
    batch_size: if batch_size > 0 { batch_size } else { 1 },
    is_classifier: true,
    hidden_is_relu: true,
    seed,
  }
  init_weights(m)
  m
}

///|
/// Switch hidden-layer activation to sigmoid (default is ReLU). Call before
/// `fit` / `fit_classifier`.
pub fn set_hidden_sigmoid(mlp : MLP) -> Unit {
  mlp.hidden_is_relu = false
}

///|
/// Switch hidden-layer activation back to ReLU.
pub fn set_hidden_relu(mlp : MLP) -> Unit {
  mlp.hidden_is_relu = true
}

// ---------------------------------------------------------------------------
// Forward / backward
// ---------------------------------------------------------------------------

///|
/// Run a forward pass. Returns `(activations, preacts)` where
/// `activations[0] = x` and `activations[L]` is the output; `preacts[l]` is
/// the pre-activation of layer `l+1`.
fn forward(
  mlp : MLP,
  x : Array[Double],
) -> (Array[Array[Double]], Array[Array[Double]]) {
  let nl = n_weight_layers(mlp)
  let activations : Array[Array[Double]] = Array::makei(nl + 1, fn(_i) { [] })
  let preacts : Array[Array[Double]] = Array::makei(nl, fn(_i) { [] })
  activations[0] = Array::copy(x)
  for l = 0; l < nl; l = l + 1 {
    let n_out = mlp.layers[l + 1]
    let n_in = mlp.layers[l]
    let z = Array::make(n_out, 0.0)
    for i = 0; i < n_out; i = i + 1 {
      let mut s = mlp.biases[l][i]
      for j = 0; j < n_in; j = j + 1 {
        s = s + mlp.weights[l][i][j] * activations[l][j]
      }
      z[i] = s
    }
    preacts[l] = z
    let a = Array::make(n_out, 0.0)
    if l == nl - 1 {
      // output layer
      if mlp.is_classifier {
        if n_out == 1 {
          a[0] = sigmoid(z[0])
        } else {
          // numerically stable softmax
          let mut mx = z[0]
          for i = 1; i < n_out; i = i + 1 {
            if z[i] > mx {
              mx = z[i]
            }
          }
          let mut sum = 0.0
          for i = 0; i < n_out; i = i + 1 {
            a[i] = exp_double(z[i] - mx)
            sum = sum + a[i]
          }
          for i = 0; i < n_out; i = i + 1 {
            a[i] = a[i] / sum
          }
        }
      } else {
        // linear output
        for i = 0; i < n_out; i = i + 1 {
          a[i] = z[i]
        }
      }
    } else if mlp.hidden_is_relu {
      for i = 0; i < n_out; i = i + 1 {
        a[i] = if z[i] > 0.0 {
          z[i]
        } else {
          0.0
        }
      }
    } else {
      for i = 0; i < n_out; i = i + 1 {
        a[i] = sigmoid(z[i])
      }
    }
    activations[l + 1] = a
  }
  (activations, preacts)
}

///|
/// Hidden-layer activation derivative at pre-activation `z` with activation
/// value `a`.
fn hidden_deriv(mlp : MLP, z : Double, a : Double) -> Double {
  if mlp.hidden_is_relu {
    if z > 0.0 {
      1.0
    } else {
      0.0
    }
  } else {
    a * (1.0 - a)
  }
}

///|
/// Back-propagate one sample, accumulating into `grad_w` / `grad_b`.
fn backward(
  mlp : MLP,
  activations : Array[Array[Double]],
  preacts : Array[Array[Double]],
  target : Array[Double],
  grad_w : Array[Array[Array[Double]]],
  grad_b : Array[Array[Double]],
) -> Unit {
  let nl = n_weight_layers(mlp)
  let deltas : Array[Array[Double]] = Array::makei(nl, fn(_i) { [] })
  // output delta: a_out − y (valid for linear/MSE, sigmoid/BCE, softmax/CE)
  let out = activations[nl]
  let d_out = Array::make(out.length(), 0.0)
  for i = 0; i < out.length(); i = i + 1 {
    d_out[i] = out[i] - target[i]
  }
  deltas[nl - 1] = d_out
  // hidden deltas
  let mut l = nl - 2
  while l >= 0 {
    let n_cur = mlp.layers[l + 1]
    let n_next = mlp.layers[l + 2]
    let d = Array::make(n_cur, 0.0)
    for i = 0; i < n_cur; i = i + 1 {
      let mut s = 0.0
      for k = 0; k < n_next; k = k + 1 {
        s = s + mlp.weights[l + 1][k][i] * deltas[l + 1][k]
      }
      d[i] = s * hidden_deriv(mlp, preacts[l][i], activations[l + 1][i])
    }
    deltas[l] = d
    l = l - 1
  }
  // accumulate gradients
  for li = 0; li < nl; li = li + 1 {
    let n_out = mlp.layers[li + 1]
    let n_in = mlp.layers[li]
    for i = 0; i < n_out; i = i + 1 {
      for j = 0; j < n_in; j = j + 1 {
        grad_w[li][i][j] = grad_w[li][i][j] + deltas[li][i] * activations[li][j]
      }
      grad_b[li][i] = grad_b[li][i] + deltas[li][i]
    }
  }
}

///|
/// Allocate zeroed gradient accumulators matching the architecture.
fn zero_grads(
  layers : Array[Int],
) -> (Array[Array[Array[Double]]], Array[Array[Double]]) {
  let nl = layers.length() - 1
  let gw : Array[Array[Array[Double]]] = Array::makei(
    nl,
    fn(li) {
      Array::makei(layers[li + 1], fn(_i) { Array::make(layers[li], 0.0) })
    },
  )
  let gb : Array[Array[Double]] = Array::makei(
    nl,
    fn(li) { Array::make(layers[li + 1], 0.0) },
  )
  (gw, gb)
}

///|
/// Fisher–Yates shuffle of `[0, n)`.
fn shuffle(n : Int, rng : Rng) -> Array[Int] {
  let order = Array::makei(n, fn(i) { i })
  for i = 0; i < n - 1; i = i + 1 {
    let j = i + rng.next_int(n - i)
    let tmp = order[i]
    order[i] = order[j]
    order[j] = tmp
  }
  order
}

// ---------------------------------------------------------------------------
// Training
// ---------------------------------------------------------------------------

///|
/// Train on regression targets. `y` is an array of target vectors, each of
/// length equal to the output size.
pub fn fit(
  mlp : MLP,
  x : Array[Array[Double]],
  y : Array[Array[Double]],
) -> Unit {
  let n = x.length()
  if n == 0 || y.length() != n {
    return
  }
  let nl = n_weight_layers(mlp)
  let rng = Rng::new(mlp.seed ^ 0x9E3779B9)
  for _epoch = 0; _epoch < mlp.epochs; _epoch = _epoch + 1 {
    let order = shuffle(n, rng)
    let mut start = 0
    while start < n {
      let end = if start + mlp.batch_size < n {
        start + mlp.batch_size
      } else {
        n
      }
      let bs = (end - start).to_double()
      let (grad_w, grad_b) = zero_grads(mlp.layers)
      for si = start; si < end; si = si + 1 {
        let idx = order[si]
        let (act, pre) = forward(mlp, x[idx])
        backward(mlp, act, pre, y[idx], grad_w, grad_b)
      }
      for l = 0; l < nl; l = l + 1 {
        let n_out = mlp.layers[l + 1]
        let n_in = mlp.layers[l]
        for i = 0; i < n_out; i = i + 1 {
          for j = 0; j < n_in; j = j + 1 {
            mlp.weights[l][i][j] = mlp.weights[l][i][j] -
              mlp.lr *
              grad_w[l][i][j] /
              bs
          }
          mlp.biases[l][i] = mlp.biases[l][i] - mlp.lr * grad_b[l][i] / bs
        }
      }
      start = end
    }
  }
}

///|
/// Train on classification labels. With one output, labels are 0/1; with
/// several outputs, labels are class indices `0 .. n_out−1` (one-hot encoded
/// internally).
pub fn fit_classifier(
  mlp : MLP,
  x : Array[Array[Double]],
  y : Array[Int],
) -> Unit {
  let n = x.length()
  if n == 0 || y.length() != n {
    return
  }
  let n_out = mlp.layers[mlp.layers.length() - 1]
  let targets : Array[Array[Double]] = Array::makei(
    n,
    fn(_i) { Array::make(n_out, 0.0) },
  )
  for i = 0; i < n; i = i + 1 {
    if n_out == 1 {
      targets[i][0] = y[i].to_double()
    } else {
      let c = y[i]
      if c >= 0 && c < n_out {
        targets[i][c] = 1.0
      }
    }
  }
  fit(mlp, x, targets)
}

// ---------------------------------------------------------------------------
// Prediction
// ---------------------------------------------------------------------------

///|
/// Output vector for a row (regression value or class probabilities).
fn output_of(mlp : MLP, x : Array[Double]) -> Array[Double] {
  let (act, _pre) = forward(mlp, x)
  Array::copy(act[act.length() - 1])
}

///|
/// Regression prediction (output vector).
pub fn predict_regress(mlp : MLP, x : Array[Double]) -> Array[Double] {
  output_of(mlp, x)
}

///|
/// Class probabilities (sigmoid for binary, softmax for multi-class).
pub fn predict_proba(mlp : MLP, x : Array[Double]) -> Array[Double] {
  output_of(mlp, x)
}

///|
/// Predicted class label. For a single output, threshold at 0.5; otherwise
/// argmax.
pub fn predict_class(mlp : MLP, x : Array[Double]) -> Int {
  let out = output_of(mlp, x)
  let n_out = out.length()
  if n_out == 1 {
    if out[0] >= 0.5 {
      1
    } else {
      0
    }
  } else {
    let mut best = 0
    let mut bv = out[0]
    for i = 1; i < n_out; i = i + 1 {
      if out[i] > bv {
        bv = out[i]
        best = i
      }
    }
    best
  }
}

// ---------------------------------------------------------------------------
// Losses (for inspection / testing)
// ---------------------------------------------------------------------------

///|
/// Mean squared error over all samples and outputs.
pub fn mse_loss(
  mlp : MLP,
  x : Array[Array[Double]],
  y : Array[Array[Double]],
) -> Double {
  let n = x.length()
  if n == 0 {
    return 0.0
  }
  let mut total = 0.0
  for i = 0; i < n; i = i + 1 {
    let out = output_of(mlp, x[i])
    for k = 0; k < out.length(); k = k + 1 {
      let d = out[k] - y[i][k]
      total = total + d * d
    }
  }
  total / n.to_double()
}

///|
/// Mean cross-entropy. `y` holds integer class labels.
pub fn cross_entropy_loss(
  mlp : MLP,
  x : Array[Array[Double]],
  y : Array[Int],
) -> Double {
  let n = x.length()
  if n == 0 {
    return 0.0
  }
  let n_out = mlp.layers[mlp.layers.length() - 1]
  let mut total = 0.0
  for i = 0; i < n; i = i + 1 {
    let out = output_of(mlp, x[i])
    if n_out == 1 {
      let p = clampd(out[0], 1.0e-12, 1.0 - 1.0e-12)
      let yi = y[i].to_double()
      total = total - (yi * ln_double(p) + (1.0 - yi) * ln_double(1.0 - p))
    } else {
      let c = y[i]
      let p = clampd(out[c], 1.0e-12, 1.0)
      total = total - ln_double(p)
    }
  }
  total / n.to_double()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mlp: XOR with ReLU hidden" {
  let mlp = new_classifier([2, 16, 1], 0.3, 3000, 4, 7)
  let x : Array[Array[Double]] = [
    [0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0],
  ]
  let y = [0, 1, 1, 0]
  fit_classifier(mlp, x, y)
  assert_eq(predict_class(mlp, [0.0, 0.0]), 0)
  assert_eq(predict_class(mlp, [0.0, 1.0]), 1)
  assert_eq(predict_class(mlp, [1.0, 0.0]), 1)
  assert_eq(predict_class(mlp, [1.0, 1.0]), 0)
}

///|
test "mlp: XOR with sigmoid hidden" {
  let mlp = new_classifier([2, 8, 1], 0.5, 4000, 4, 123)
  set_hidden_sigmoid(mlp)
  let x : Array[Array[Double]] = [
    [0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0],
  ]
  let y = [0, 1, 1, 0]
  fit_classifier(mlp, x, y)
  assert_eq(predict_class(mlp, [0.0, 0.0]), 0)
  assert_eq(predict_class(mlp, [0.0, 1.0]), 1)
  assert_eq(predict_class(mlp, [1.0, 0.0]), 1)
  assert_eq(predict_class(mlp, [1.0, 1.0]), 0)
}

///|
test "mlp: binary classification on a threshold" {
  let mlp = new_classifier([1, 12, 1], 0.2, 1500, 4, 99)
  let x : Array[Array[Double]] = []
  let y : Array[Int] = []
  for i = 0; i < 8; i = i + 1 {
    x.push([i.to_double()])
    y.push(if i < 4 { 0 } else { 1 })
  }
  fit_classifier(mlp, x, y)
  assert_eq(predict_class(mlp, [0.0]), 0)
  assert_eq(predict_class(mlp, [1.0]), 0)
  assert_eq(predict_class(mlp, [6.0]), 1)
  assert_eq(predict_class(mlp, [7.0]), 1)
}

///|
test "mlp: multi-class softmax classification" {
  // Three well-separated 1-D classes centred at 0, 5, 10.
  let mlp = new_classifier([1, 16, 3], 0.1, 2000, 6, 2024)
  let x : Array[Array[Double]] = []
  let y : Array[Int] = []
  let centres = [0.0, 5.0, 10.0]
  for c = 0; c < 3; c = c + 1 {
    for d = 0; d < 4; d = d + 1 {
      x.push([centres[c] + d.to_double() * 0.5])
      y.push(c)
    }
  }
  fit_classifier(mlp, x, y)
  assert_eq(predict_class(mlp, [0.0]), 0)
  assert_eq(predict_class(mlp, [5.0]), 1)
  assert_eq(predict_class(mlp, [10.0]), 2)
}

///|
test "mlp: regression fits a smooth function" {
  // Target y = x0 + x1 over a small grid.
  let mlp = new_regression([2, 16, 1], 0.02, 2000, 8, 55)
  let x : Array[Array[Double]] = []
  let y : Array[Array[Double]] = []
  for i = 0; i < 5; i = i + 1 {
    for j = 0; j < 5; j = j + 1 {
      x.push([i.to_double(), j.to_double()])
      y.push([i.to_double() + j.to_double()])
    }
  }
  let before = mse_loss(mlp, x, y)
  fit(mlp, x, y)
  let after = mse_loss(mlp, x, y)
  assert_true(after < before)
  assert_true(after < 1.0)
  // Predictions track the targets.
  let p02 = predict_regress(mlp, [0.0, 2.0])[0]
  let p33 = predict_regress(mlp, [3.0, 3.0])[0]
  assert_true((p02 - 2.0).abs() < 1.5)
  assert_true((p33 - 6.0).abs() < 1.5)
}

///|
test "mlp: cross-entropy decreases with training" {
  let mlp = new_classifier([2, 8, 1], 0.3, 1, 4, 31)
  let x = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]
  let y = [0, 1, 1, 0]
  let before = cross_entropy_loss(mlp, x, y)
  fit_classifier(mlp, x, y)
  let after = cross_entropy_loss(mlp, x, y)
  assert_true(after < before)
}

///|
test "mlp: probabilities are valid" {
  let mlp = new_classifier([2, 8, 3], 0.1, 100, 4, 8)
  let x = [[0.0, 0.0], [1.0, 1.0], [0.0, 1.0]]
  let y = [0, 1, 2]
  fit_classifier(mlp, x, y)
  for i = 0; i < 3; i = i + 1 {
    let p = predict_proba(mlp, x[i])
    let mut sum = 0.0
    for k = 0; k < p.length(); k = k + 1 {
      assert_true(p[k] >= 0.0 && p[k] <= 1.0)
      sum = sum + p[k]
    }
    assert_true((sum - 1.0).abs() < 1.0e-9)
  }
}

///|
test "mlp: local exp/ln are accurate" {
  assert_true((exp_double(0.0) - 1.0).abs() < 1.0e-12)
  assert_true((exp_double(1.0) - 2.718281828459045).abs() < 1.0e-12)
  assert_true((ln_double(2.718281828459045) - 1.0).abs() < 1.0e-12)
  assert_true(ln_double(1.0).abs() < 1.0e-12)
}
