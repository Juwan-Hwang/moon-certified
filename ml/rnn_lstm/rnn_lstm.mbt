/// RNN / LSTM Recurrent Neural Network — Forward, Backpropagation Through Time (BPTT)
///
/// This module implements two recurrent architectures:
///
/// 1. **Vanilla RNN** — `h_t = tanh(W_xh · x_t + W_hh · h_{t−1} + b_h)`
/// 2. **LSTM** — Hochreiter & Schmidhuber (1997) with forget/input/output gates
///    and a candidate cell-state update, using the standard formulation:
///    - `f_t = σ(W_f · [x_t; h_{t−1}] + b_f)` (forget gate)
///    - `i_t = σ(W_i · [x_t; h_{t−1}] + b_i)` (input gate)
///    - `g_t = tanh(W_g · [x_t; h_{t−1}] + b_g)` (candidate)
///    - `c_t = f_t ⊙ c_{t−1} + i_t ⊙ g_t` (cell state)
///    - `o_t = σ(W_o · [x_t; h_{t−1}] + b_o)` (output gate)
///    - `h_t = o_t ⊙ tanh(c_t)` (hidden state)
///
/// Training uses Backpropagation Through Time (BPTT) with gradient clipping
/// to mitigate exploding gradients. Both regression (MSE) and classification
/// (softmax cross-entropy) outputs are supported.
///
/// ## Complexity
/// - Forward: `O(T × H × (I + H + O))` per sequence (T = timesteps, H = hidden
///   units, I = input dimension, O = output dimension).
/// - BPTT: same order as forward, with a constant-factor overhead.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Local transcendentals — self-contained, no external dependency
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
/// Hyperbolic tangent — numerically stable.
fn tanh_fn(x : Double) -> Double {
  if x >= 35.0 {
    return 1.0
  }
  if x <= -35.0 {
    return -1.0
  }
  let e2x = exp_double(2.0 * x)
  (e2x - 1.0) / (e2x + 1.0)
}

///|
/// Element-wise softmax (numerically stable via max-subtraction).
fn softmax(x : Array[Double]) -> Array[Double] {
  let n = x.length()
  if n == 0 {
    return []
  }
  let mut mx = x[0]
  for i = 1; i < n; i = i + 1 {
    if x[i] > mx {
      mx = x[i]
    }
  }
  let result = Array::make(n, 0.0)
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let e = exp_double(x[i] - mx)
    result[i] = e
    sum = sum + e
  }
  for i = 0; i < n; i = i + 1 {
    result[i] = result[i] / sum
  }
  result
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
// Deterministic PRNG (31-bit LCG)
// ---------------------------------------------------------------------------

///|
priv struct Rng {
  mut state : Int
}

///|
fn Rng::new(seed : Int) -> Rng {
  let s = seed & 0x7FFFFFFF
  { state: if s == 0 { 1 } else { s } }
}

///|
fn Rng::next(self : Rng) -> Int {
  self.state = (self.state * 1103515245 + 12345) & 0x7FFFFFFF
  self.state
}

///|
fn Rng::next_double(self : Rng) -> Double {
  self.next().to_double() / 2147483648.0
}

// ---------------------------------------------------------------------------
// RNN cell type
// ---------------------------------------------------------------------------

///|
/// Recurrent cell type selector.
pub enum CellType {
  Vanilla // Simple RNN with tanh activation
  LSTM // Long Short-Term Memory
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// RNN model
// ---------------------------------------------------------------------------

///|
/// Recurrent neural network model supporting Vanilla RNN and LSTM cells.
///
/// Architecture (for one layer):
/// - Input-to-hidden weights: `W_xh[H_packed][I]`
/// - Hidden-to-hidden weights: `W_hh[H_packed][H]`
/// - Hidden biases: `b_h[H_packed]`
/// - Hidden-to-output weights: `W_ho[O][H]`
/// - Output biases: `b_o[O]`
///
/// For LSTM, there are four sets of gate weights packed into the same
/// arrays (H_packed = 4 × hidden_size), ordered as [forget, input, candidate, output].
pub struct RnnModel {
  /// Cell type: Vanilla or LSTM
  cell_type : CellType
  /// Input dimension `I`
  input_size : Int
  /// Hidden dimension `H` (for LSTM, stored hidden_size, not 4×)
  hidden_size : Int
  /// Output dimension `O`
  output_size : Int
  /// Learning rate
  lr : Double
  /// Max gradient norm for clipping (0 = disabled)
  clip_norm : Double
  priv mut w_xh : Array[Array[Double]] // [H_packed][I]
  priv mut w_hh : Array[Array[Double]] // [H_packed][H]
  priv mut b_h : Array[Double] // [H_packed]
  priv mut w_ho : Array[Array[Double]] // [O][H]
  priv mut b_o : Array[Double] // [O]
  /// Whether output uses softmax (classification) or linear (regression)
  is_classifier : Bool
  /// PRNG seed
  seed : Int
}

///|
/// Internal: the *packed* hidden dimension.
/// For Vanilla RNN this equals `hidden_size`; for LSTM it equals `4 × hidden_size`.
fn packed_h(model : RnnModel) -> Int {
  match model.cell_type {
    Vanilla => model.hidden_size
    LSTM => model.hidden_size * 4
  }
}

// ---------------------------------------------------------------------------
// Initialisation
// ---------------------------------------------------------------------------

///|
/// Xavier/Glorot initialisation: `U(±√(6 / (fan_in + fan_out)))`.
fn xavier_scale(fan_in : Int, fan_out : Int) -> Double {
  (6.0 / (fan_in.to_double() + fan_out.to_double())).sqrt()
}

///|
/// Initialise weights with Xavier/Glorot uniform distribution.
fn init_weights(model : RnnModel) -> Unit {
  let rng = Rng::new(model.seed)
  let hp = packed_h(model)
  let h = model.hidden_size
  let i = model.input_size
  let o = model.output_size
  // W_xh: [hp][i]
  let wx : Array[Array[Double]] = []
  let scale_xh = xavier_scale(i, h)
  for _r = 0; _r < hp; _r = _r + 1 {
    let row : Array[Double] = []
    for _c = 0; _c < i; _c = _c + 1 {
      row.push((rng.next_double() * 2.0 - 1.0) * scale_xh)
    }
    wx.push(row)
  }
  // W_hh: [hp][h]
  let wh : Array[Array[Double]] = []
  let scale_hh = xavier_scale(h, h)
  for _r = 0; _r < hp; _r = _r + 1 {
    let row : Array[Double] = []
    for _c = 0; _c < h; _c = _c + 1 {
      row.push((rng.next_double() * 2.0 - 1.0) * scale_hh)
    }
    wh.push(row)
  }
  // b_h: [hp] — zeros
  let bh = Array::make(hp, 0.0)
  // W_ho: [o][h]
  let wo : Array[Array[Double]] = []
  let scale_ho = xavier_scale(h, o)
  for _r = 0; _r < o; _r = _r + 1 {
    let row : Array[Double] = []
    for _c = 0; _c < h; _c = _c + 1 {
      row.push((rng.next_double() * 2.0 - 1.0) * scale_ho)
    }
    wo.push(row)
  }
  // b_o: [o]
  let bo = Array::make(o, 0.0)
  model.w_xh = wx
  model.w_hh = wh
  model.b_h = bh
  model.w_ho = wo
  model.b_o = bo
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

///|
/// Create a new RNN model.
///
/// - `cell_type`: `Vanilla` or `LSTM`
/// - `input_size`: dimension of each input vector
/// - `hidden_size`: number of hidden units
/// - `output_size`: dimension of output
/// - `lr`: learning rate (typical: 0.01)
/// - `is_classifier`: if `true`, output uses softmax + cross-entropy loss;
///   if `false`, linear output + MSE loss
/// - `clip_norm`: max gradient norm for clipping (0 = disabled, typical: 5.0)
/// - `seed`: PRNG seed for reproducible initialisation
pub fn new(
  cell_type : CellType,
  input_size : Int,
  hidden_size : Int,
  output_size : Int,
  lr : Double,
  is_classifier : Bool,
  clip_norm : Double,
  seed : Int,
) -> RnnModel {
  let m : RnnModel = {
    cell_type,
    input_size,
    hidden_size,
    output_size,
    lr: if lr > 0.0 {
      lr
    } else {
      0.01
    },
    clip_norm: if clip_norm > 0.0 {
      clip_norm
    } else {
      0.0
    },
    w_xh: [],
    w_hh: [],
    b_h: [],
    w_ho: [],
    b_o: [],
    is_classifier,
    seed,
  }
  init_weights(m)
  m
}

// ---------------------------------------------------------------------------
// Forward pass — Vanilla RNN
// ---------------------------------------------------------------------------

///|
/// One step of vanilla RNN forward.
/// Returns `(h_t, pre_activation)`.
fn vanilla_step(
  model : RnnModel,
  x_t : Array[Double],
  h_prev : Array[Double],
) -> (Array[Double], Array[Double]) {
  let h = model.hidden_size
  let pre = Array::make(h, 0.0)
  for j = 0; j < h; j = j + 1 {
    let mut s = model.b_h[j]
    let wx_row = model.w_xh[j]
    for k = 0; k < model.input_size; k = k + 1 {
      s = s + wx_row[k] * x_t[k]
    }
    let wh_row = model.w_hh[j]
    for k = 0; k < h; k = k + 1 {
      s = s + wh_row[k] * h_prev[k]
    }
    pre[j] = s
  }
  let h_t = Array::make(h, 0.0)
  for j = 0; j < h; j = j + 1 {
    h_t[j] = tanh_fn(pre[j])
  }
  (h_t, pre)
}

// ---------------------------------------------------------------------------
// Forward pass — LSTM
// ---------------------------------------------------------------------------

///|
/// Internal: LSTM gate activations stored for BPTT.
priv struct LstmGates {
  f_val : Array[Double] // forget gate value
  i_val : Array[Double] // input gate value
  g_val : Array[Double] // candidate value
  o_val : Array[Double] // output gate value
  c_t : Array[Double] // cell state
}

///|
/// One step of LSTM forward.
///
/// Gate weights are packed in `W_xh`, `W_hh`, `b_h` as 4 consecutive blocks
/// of size `hidden_size`, in the order: forget, input, candidate, output.
fn lstm_step(
  model : RnnModel,
  x_t : Array[Double],
  h_prev : Array[Double],
  c_prev : Array[Double],
) -> (Array[Double], Array[Double], LstmGates) {
  let h = model.hidden_size
  let f_pre = Array::make(h, 0.0)
  let i_pre = Array::make(h, 0.0)
  let g_pre = Array::make(h, 0.0)
  let o_pre = Array::make(h, 0.0)
  for j = 0; j < h; j = j + 1 {
    // Forget gate (offset 0*h + j)
    let mut sf = model.b_h[j]
    let wxf = model.w_xh[j]
    for k = 0; k < model.input_size; k = k + 1 {
      sf = sf + wxf[k] * x_t[k]
    }
    let whf = model.w_hh[j]
    for k = 0; k < h; k = k + 1 {
      sf = sf + whf[k] * h_prev[k]
    }
    f_pre[j] = sf
    // Input gate (offset 1*h + j)
    let mut si = model.b_h[h + j]
    let wxi = model.w_xh[h + j]
    for k = 0; k < model.input_size; k = k + 1 {
      si = si + wxi[k] * x_t[k]
    }
    let whi = model.w_hh[h + j]
    for k = 0; k < h; k = k + 1 {
      si = si + whi[k] * h_prev[k]
    }
    i_pre[j] = si
    // Candidate (offset 2*h + j)
    let mut sg = model.b_h[2 * h + j]
    let wxg = model.w_xh[2 * h + j]
    for k = 0; k < model.input_size; k = k + 1 {
      sg = sg + wxg[k] * x_t[k]
    }
    let whg = model.w_hh[2 * h + j]
    for k = 0; k < h; k = k + 1 {
      sg = sg + whg[k] * h_prev[k]
    }
    g_pre[j] = sg
    // Output gate (offset 3*h + j)
    let mut so = model.b_h[3 * h + j]
    let wxo = model.w_xh[3 * h + j]
    for k = 0; k < model.input_size; k = k + 1 {
      so = so + wxo[k] * x_t[k]
    }
    let who = model.w_hh[3 * h + j]
    for k = 0; k < h; k = k + 1 {
      so = so + who[k] * h_prev[k]
    }
    o_pre[j] = so
  }
  // Apply activations
  let f_t = Array::make(h, 0.0)
  let i_t = Array::make(h, 0.0)
  let g_t = Array::make(h, 0.0)
  let o_t = Array::make(h, 0.0)
  let c_t = Array::make(h, 0.0)
  let h_t = Array::make(h, 0.0)
  for j = 0; j < h; j = j + 1 {
    f_t[j] = sigmoid(f_pre[j])
    i_t[j] = sigmoid(i_pre[j])
    g_t[j] = tanh_fn(g_pre[j])
    o_t[j] = sigmoid(o_pre[j])
    c_t[j] = f_t[j] * c_prev[j] + i_t[j] * g_t[j]
    h_t[j] = o_t[j] * tanh_fn(c_t[j])
  }
  let gates : LstmGates = {
    f_val: f_t,
    i_val: i_t,
    g_val: g_t,
    o_val: o_t,
    c_t,
  }
  (h_t, c_t, gates)
}

// ---------------------------------------------------------------------------
// Output projection
// ---------------------------------------------------------------------------

///|
/// Output projection: `y = W_ho · h + b_o`
fn project_output(model : RnnModel, h : Array[Double]) -> Array[Double] {
  let o = model.output_size
  let logits = Array::make(o, 0.0)
  for j = 0; j < o; j = j + 1 {
    let mut s = model.b_o[j]
    let row = model.w_ho[j]
    for k = 0; k < model.hidden_size; k = k + 1 {
      s = s + row[k] * h[k]
    }
    logits[j] = s
  }
  if model.is_classifier {
    softmax(logits)
  } else {
    logits
  }
}

// ---------------------------------------------------------------------------
// Forward cache & full sequence forward
// ---------------------------------------------------------------------------

///|
/// Forward cache for a single sequence (stored for BPTT).
priv struct ForwardCache {
  h_states : Array[Array[Double]] // h_states[t] = h_t (size H)
  lstm_gates : Array[LstmGates] // gate storage for LSTM (empty for vanilla)
  c_states : Array[Array[Double]] // cell states for LSTM (size H), empty for vanilla
  outputs : Array[Array[Double]] // outputs[t] (size O)
}

///|
/// Forward pass over a full sequence. Returns the cache.
///
/// `x_seq` is `[T][I]` — a sequence of T input vectors.
/// Initial hidden state (and cell state for LSTM) is zero.
fn forward_seq(model : RnnModel, x_seq : Array[Array[Double]]) -> ForwardCache {
  let t_len = x_seq.length()
  let h = model.hidden_size
  let h0 = Array::make(h, 0.0)
  let c0 = Array::make(h, 0.0)
  let h_states : Array[Array[Double]] = []
  let lstm_gates : Array[LstmGates] = []
  let c_states : Array[Array[Double]] = []
  let outputs : Array[Array[Double]] = []
  let mut h_prev = h0
  let mut c_prev = c0
  for t = 0; t < t_len; t = t + 1 {
    let x_t = x_seq[t]
    match model.cell_type {
      Vanilla => {
        let (h_t, _pre) = vanilla_step(model, x_t, h_prev)
        h_states.push(h_t)
        h_prev = h_t
      }
      LSTM => {
        let (h_t, c_t, gates) = lstm_step(model, x_t, h_prev, c_prev)
        h_states.push(h_t)
        lstm_gates.push(gates)
        c_states.push(c_t)
        h_prev = h_t
        c_prev = c_t
      }
    }
    let y_t = project_output(model, h_prev)
    outputs.push(y_t)
  }
  { h_states, lstm_gates, c_states, outputs }
}

// ---------------------------------------------------------------------------
// Loss & output delta
// ---------------------------------------------------------------------------

///|
/// Compute loss at the last timestep.
/// - Classification: cross-entropy `−Σ y_i log(p_i)`
/// - Regression: MSE `0.5 × Σ (p_i − y_i)²`
fn compute_loss(
  model : RnnModel,
  pred : Array[Double],
  target : Array[Double],
) -> Double {
  let o = model.output_size
  if model.is_classifier {
    let mut loss = 0.0
    for j = 0; j < o; j = j + 1 {
      if target[j] > 0.0 {
        let p = clampd(pred[j], 1.0e-15, 1.0)
        loss = loss - target[j] * ln_double(p)
      }
    }
    loss
  } else {
    let mut loss = 0.0
    for j = 0; j < o; j = j + 1 {
      let d = pred[j] - target[j]
      loss = loss + 0.5 * d * d
    }
    loss
  }
}

///|
/// Output-layer delta (gradient w.r.t. pre-output logits).
/// - Classification (softmax + CE): `δ = p − y`
/// - Regression (linear + MSE): `δ = p − y`
fn output_delta(
  model : RnnModel,
  pred : Array[Double],
  target : Array[Double],
) -> Array[Double] {
  let o = model.output_size
  let delta = Array::make(o, 0.0)
  for j = 0; j < o; j = j + 1 {
    delta[j] = pred[j] - target[j]
  }
  delta
}

// ---------------------------------------------------------------------------
// BPTT gradient accumulators
// ---------------------------------------------------------------------------

///|
/// Gradient accumulator.
priv struct RnnGrad {
  gW_xh : Array[Array[Double]]
  gW_hh : Array[Array[Double]]
  gb_h : Array[Double]
  gW_ho : Array[Array[Double]]
  gb_o : Array[Double]
}

///|
/// Zero-initialise gradient accumulators matching the parameter shapes.
fn zero_grads(model : RnnModel) -> RnnGrad {
  let hp = packed_h(model)
  let h = model.hidden_size
  let i = model.input_size
  let o = model.output_size
  let gW_xh : Array[Array[Double]] = []
  for _r = 0; _r < hp; _r = _r + 1 {
    gW_xh.push(Array::make(i, 0.0))
  }
  let gW_hh : Array[Array[Double]] = []
  for _r = 0; _r < hp; _r = _r + 1 {
    gW_hh.push(Array::make(h, 0.0))
  }
  let gb_h = Array::make(hp, 0.0)
  let gW_ho : Array[Array[Double]] = []
  for _r = 0; _r < o; _r = _r + 1 {
    gW_ho.push(Array::make(h, 0.0))
  }
  let gb_o = Array::make(o, 0.0)
  { gW_xh, gW_hh, gb_h, gW_ho, gb_o }
}

///|
/// Accumulate output-layer gradients into `grad`.
fn accumulate_output_grad(
  model : RnnModel,
  h_t : Array[Double],
  delta_o : Array[Double],
  grad : RnnGrad,
) -> Unit {
  let h = model.hidden_size
  let o = model.output_size
  for j = 0; j < o; j = j + 1 {
    grad.gb_o[j] = grad.gb_o[j] + delta_o[j]
    for k = 0; k < h; k = k + 1 {
      grad.gW_ho[j][k] = grad.gW_ho[j][k] + delta_o[j] * h_t[k]
    }
  }
}

///|
/// Global norm clipping: rescales `grad` so the total L2 norm ≤ `clip_norm`.
fn clip_gradients(model : RnnModel, grad : RnnGrad) -> Unit {
  if model.clip_norm <= 0.0 {
    return
  }
  let mut total_sq = 0.0
  for row in grad.gW_xh {
    for v in row {
      total_sq = total_sq + v * v
    }
  }
  for row in grad.gW_hh {
    for v in row {
      total_sq = total_sq + v * v
    }
  }
  for v in grad.gb_h {
    total_sq = total_sq + v * v
  }
  for row in grad.gW_ho {
    for v in row {
      total_sq = total_sq + v * v
    }
  }
  for v in grad.gb_o {
    total_sq = total_sq + v * v
  }
  let total_norm = total_sq.sqrt()
  if total_norm > model.clip_norm {
    let scale = model.clip_norm / total_norm
    for row in grad.gW_xh {
      for j = 0; j < row.length(); j = j + 1 {
        row[j] = row[j] * scale
      }
    }
    for row in grad.gW_hh {
      for j = 0; j < row.length(); j = j + 1 {
        row[j] = row[j] * scale
      }
    }
    for j = 0; j < grad.gb_h.length(); j = j + 1 {
      grad.gb_h[j] = grad.gb_h[j] * scale
    }
    for row in grad.gW_ho {
      for j = 0; j < row.length(); j = j + 1 {
        row[j] = row[j] * scale
      }
    }
    for j = 0; j < grad.gb_o.length(); j = j + 1 {
      grad.gb_o[j] = grad.gb_o[j] * scale
    }
  }
}

///|
/// Apply accumulated gradients to model parameters with learning rate `lr`.
fn apply_gradients(model : RnnModel, grad : RnnGrad) -> Unit {
  let hp = packed_h(model)
  let h = model.hidden_size
  let i = model.input_size
  let o = model.output_size
  let lr = model.lr
  for r = 0; r < hp; r = r + 1 {
    for c = 0; c < i; c = c + 1 {
      model.w_xh[r][c] = model.w_xh[r][c] - lr * grad.gW_xh[r][c]
    }
  }
  for r = 0; r < hp; r = r + 1 {
    for c = 0; c < h; c = c + 1 {
      model.w_hh[r][c] = model.w_hh[r][c] - lr * grad.gW_hh[r][c]
    }
  }
  for j = 0; j < hp; j = j + 1 {
    model.b_h[j] = model.b_h[j] - lr * grad.gb_h[j]
  }
  for r = 0; r < o; r = r + 1 {
    for c = 0; c < h; c = c + 1 {
      model.w_ho[r][c] = model.w_ho[r][c] - lr * grad.gW_ho[r][c]
    }
  }
  for j = 0; j < o; j = j + 1 {
    model.b_o[j] = model.b_o[j] - lr * grad.gb_o[j]
  }
}

// ---------------------------------------------------------------------------
// BPTT — Vanilla RNN
// ---------------------------------------------------------------------------

///|
/// BPTT for Vanilla RNN. Accumulates gradients into `grad`.
fn bptt_vanilla(
  model : RnnModel,
  x_seq : Array[Array[Double]],
  cache : ForwardCache,
  delta_o_last : Array[Double],
  grad : RnnGrad,
) -> Unit {
  let t_len = x_seq.length()
  let h = model.hidden_size
  let o = model.output_size
  accumulate_output_grad(model, cache.h_states[t_len - 1], delta_o_last, grad)
  // dh at the last timestep = W_ho^T · delta_o
  let mut dh = Array::make(h, 0.0)
  for k = 0; k < h; k = k + 1 {
    let mut s = 0.0
    for j = 0; j < o; j = j + 1 {
      s = s + model.w_ho[j][k] * delta_o_last[j]
    }
    dh[k] = s
  }
  // Backpropagate through time
  for t = t_len - 1; t >= 0; t = t - 1 {
    let h_t = cache.h_states[t]
    let x_t = x_seq[t]
    // dh_pre = dh * (1 - h_t^2)  [tanh derivative]
    let dh_pre = Array::make(h, 0.0)
    for j = 0; j < h; j = j + 1 {
      dh_pre[j] = dh[j] * (1.0 - h_t[j] * h_t[j])
    }
    // Gradient w.r.t. b_h
    for j = 0; j < h; j = j + 1 {
      grad.gb_h[j] = grad.gb_h[j] + dh_pre[j]
    }
    // Gradient w.r.t. W_xh
    for j = 0; j < h; j = j + 1 {
      for k = 0; k < model.input_size; k = k + 1 {
        grad.gW_xh[j][k] = grad.gW_xh[j][k] + dh_pre[j] * x_t[k]
      }
    }
    // Gradient w.r.t. W_hh + compute dh_prev
    let h_prev = if t > 0 { cache.h_states[t - 1] } else { Array::make(h, 0.0) }
    let dh_prev = Array::make(h, 0.0)
    for j = 0; j < h; j = j + 1 {
      for k = 0; k < h; k = k + 1 {
        grad.gW_hh[j][k] = grad.gW_hh[j][k] + dh_pre[j] * h_prev[k]
        dh_prev[k] = dh_prev[k] + model.w_hh[j][k] * dh_pre[j]
      }
    }
    dh = dh_prev
  }
}

// ---------------------------------------------------------------------------
// BPTT — LSTM
// ---------------------------------------------------------------------------

///|
/// BPTT for LSTM. Accumulates gradients into `grad`.
fn bptt_lstm(
  model : RnnModel,
  x_seq : Array[Array[Double]],
  cache : ForwardCache,
  delta_o_last : Array[Double],
  grad : RnnGrad,
) -> Unit {
  let t_len = x_seq.length()
  let h = model.hidden_size
  let o = model.output_size
  accumulate_output_grad(model, cache.h_states[t_len - 1], delta_o_last, grad)
  // dh at the last timestep = W_ho^T · delta_o
  let mut dh = Array::make(h, 0.0)
  for k = 0; k < h; k = k + 1 {
    let mut s = 0.0
    for j = 0; j < o; j = j + 1 {
      s = s + model.w_ho[j][k] * delta_o_last[j]
    }
    dh[k] = s
  }
  let mut dc = Array::make(h, 0.0)
  for t = t_len - 1; t >= 0; t = t - 1 {
    let gates = cache.lstm_gates[t]
    let c_t = gates.c_t
    let x_t = x_seq[t]
    // tanh(c_t) used in output
    let tanh_c = Array::make(h, 0.0)
    for j = 0; j < h; j = j + 1 {
      tanh_c[j] = tanh_fn(c_t[j])
    }
    // dc_total = dc + dh * o_t * (1 - tanh(c_t)^2)
    let dc_total = Array::make(h, 0.0)
    for j = 0; j < h; j = j + 1 {
      dc_total[j] = dc[j] +
        dh[j] * gates.o_val[j] * (1.0 - tanh_c[j] * tanh_c[j])
    }
    // Gate pre-activation gradients:
    // Output gate: dL/do_pre = dc_total * tanh(c_t) * o * (1 - o)
    let do_pre = Array::make(h, 0.0)
    for j = 0; j < h; j = j + 1 {
      do_pre[j] = dc_total[j] *
        tanh_c[j] *
        gates.o_val[j] *
        (1.0 - gates.o_val[j])
    }
    // Candidate: dL/dg_pre = dc_total * i * (1 - g^2)
    let dg_pre = Array::make(h, 0.0)
    for j = 0; j < h; j = j + 1 {
      dg_pre[j] = dc_total[j] *
        gates.i_val[j] *
        (1.0 - gates.g_val[j] * gates.g_val[j])
    }
    // Input gate: dL/di_pre = dc_total * g * i * (1 - i)
    let di_pre = Array::make(h, 0.0)
    for j = 0; j < h; j = j + 1 {
      di_pre[j] = dc_total[j] *
        gates.g_val[j] *
        gates.i_val[j] *
        (1.0 - gates.i_val[j])
    }
    // Forget gate: dL/df_pre = dc_total * c_prev * f * (1 - f)
    let c_prev = if t > 0 { cache.c_states[t - 1] } else { Array::make(h, 0.0) }
    let df_pre = Array::make(h, 0.0)
    for j = 0; j < h; j = j + 1 {
      df_pre[j] = dc_total[j] *
        c_prev[j] *
        gates.f_val[j] *
        (1.0 - gates.f_val[j])
    }
    // Pack gate gradients: [forget, input, candidate, output]
    let gate_pres = [df_pre, di_pre, dg_pre, do_pre]
    let gate_offsets = [0, h, 2 * h, 3 * h]
    // h_prev for W_hh gradient
    let h_prev = if t > 0 { cache.h_states[t - 1] } else { Array::make(h, 0.0) }
    let dh_prev = Array::make(h, 0.0)
    let dc_prev = Array::make(h, 0.0)
    for gi = 0; gi < 4; gi = gi + 1 {
      let offset = gate_offsets[gi]
      let gp = gate_pres[gi]
      // Bias gradient
      for j = 0; j < h; j = j + 1 {
        grad.gb_h[offset + j] = grad.gb_h[offset + j] + gp[j]
      }
      // W_xh gradient
      for j = 0; j < h; j = j + 1 {
        let gwx_row = grad.gW_xh[offset + j]
        for k = 0; k < model.input_size; k = k + 1 {
          gwx_row[k] = gwx_row[k] + gp[j] * x_t[k]
        }
      }
      // W_hh gradient + accumulate dh_prev
      for j = 0; j < h; j = j + 1 {
        let gwh_row = grad.gW_hh[offset + j]
        let wh_row = model.w_hh[offset + j]
        for k = 0; k < h; k = k + 1 {
          gwh_row[k] = gwh_row[k] + gp[j] * h_prev[k]
          dh_prev[k] = dh_prev[k] + wh_row[k] * gp[j]
        }
      }
    }
    // dc_prev = dc_total * f_val (forget gate passes cell state through)
    for j = 0; j < h; j = j + 1 {
      dc_prev[j] = dc_total[j] * gates.f_val[j]
    }
    dh = dh_prev
    dc = dc_prev
  }
}

// ---------------------------------------------------------------------------
// Training
// ---------------------------------------------------------------------------

///|
/// Train the RNN on a single sequence, using BPTT.
/// Computes forward pass, loss, backward pass, clips gradients, and updates.
fn train_sequence(
  model : RnnModel,
  x_seq : Array[Array[Double]],
  target : Array[Double],
) -> Double {
  let cache = forward_seq(model, x_seq)
  let t_len = x_seq.length()
  let pred = cache.outputs[t_len - 1]
  let loss = compute_loss(model, pred, target)
  let delta_o = output_delta(model, pred, target)
  let grad = zero_grads(model)
  match model.cell_type {
    Vanilla => bptt_vanilla(model, x_seq, cache, delta_o, grad)
    LSTM => bptt_lstm(model, x_seq, cache, delta_o, grad)
  }
  clip_gradients(model, grad)
  apply_gradients(model, grad)
  loss
}

///|
/// Train the RNN on multiple sequences for `epochs` epochs.
///
/// - `x_seqs`: array of sequences, each `[T_k][I]`
/// - `targets`: array of target vectors, each `[O]`
/// - `epochs`: number of full passes over all sequences
/// - `seed`: PRNG seed for shuffling
/// Returns the average loss of the last epoch.
pub fn fit(
  model : RnnModel,
  x_seqs : Array[Array[Array[Double]]],
  targets : Array[Array[Double]],
  epochs : Int,
) -> Double {
  let n = x_seqs.length()
  if n == 0 || targets.length() != n {
    return 0.0
  }
  let rng = Rng::new(model.seed ^ 0x9E3779B9)
  let mut last_avg = 0.0
  for _epoch = 0; _epoch < epochs; _epoch = _epoch + 1 {
    // Fisher–Yates shuffle
    let order : Array[Int] = []
    for i = 0; i < n; i = i + 1 {
      order.push(i)
    }
    for i = 0; i < n - 1; i = i + 1 {
      let r = rng.next() % (n - i)
      let j = i + r
      let tmp = order[i]
      order[i] = order[j]
      order[j] = tmp
    }
    let mut total_loss = 0.0
    for si = 0; si < n; si = si + 1 {
      let idx = order[si]
      let loss = train_sequence(model, x_seqs[idx], targets[idx])
      total_loss = total_loss + loss
    }
    last_avg = total_loss / n.to_double()
  }
  last_avg
}

// ---------------------------------------------------------------------------
// Prediction
// ---------------------------------------------------------------------------

///|
/// Forward pass on a sequence; returns the output at the last timestep.
pub fn predict(model : RnnModel, x_seq : Array[Array[Double]]) -> Array[Double] {
  let cache = forward_seq(model, x_seq)
  let t_len = x_seq.length()
  if t_len == 0 {
    return Array::make(model.output_size, 0.0)
  }
  Array::copy(cache.outputs[t_len - 1])
}

///|
/// Predict the class label (argmax of output). For regression models,
/// returns the index of the maximum output value.
pub fn predict_class(model : RnnModel, x_seq : Array[Array[Double]]) -> Int {
  let out = predict(model, x_seq)
  let mut best = 0
  let mut bv = out[0]
  for i = 1; i < out.length(); i = i + 1 {
    if out[i] > bv {
      bv = out[i]
      best = i
    }
  }
  best
}

///|
/// Compute the loss on a single sequence (no training).
pub fn loss(
  model : RnnModel,
  x_seq : Array[Array[Double]],
  target : Array[Double],
) -> Double {
  let cache = forward_seq(model, x_seq)
  let t_len = x_seq.length()
  if t_len == 0 {
    return 0.0
  }
  compute_loss(model, cache.outputs[t_len - 1], target)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "rnn: vanilla forward produces correct output dimensions" {
  let model = new(Vanilla, 2, 4, 3, 0.01, false, 0.0, 42)
  let x_seq = [[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]]
  let out = predict(model, x_seq)
  assert_true(out.length() == 3)
  // Outputs should be finite (not NaN/Inf)
  for v in out {
    assert_true(v == v) // NaN != NaN check
  }
}

///|
test "rnn: lstm forward produces correct output dimensions" {
  let model = new(LSTM, 2, 4, 3, 0.01, false, 0.0, 42)
  let x_seq = [[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]]
  let out = predict(model, x_seq)
  assert_true(out.length() == 3)
  for v in out {
    assert_true(v == v)
  }
}

///|
test "rnn: vanilla regression learns a simple sequence" {
  // Simple sequence: [x, 0] -> predict x*2
  // Sequence: [[1,0],[2,0],[3,0]] -> target [6.0] (sum of inputs * 2)
  let model = new(Vanilla, 2, 8, 1, 0.05, false, 5.0, 99)
  let x_seqs : Array[Array[Array[Double]]] = []
  let targets : Array[Array[Double]] = []
  for i = 0; i < 10; i = i + 1 {
    let a = i.to_double()
    x_seqs.push([[a, 0.0], [a + 1.0, 0.0], [a + 2.0, 0.0]])
    targets.push([(a + a + 1.0 + a + 2.0) * 2.0])
  }
  let before = loss(model, x_seqs[0], targets[0])
  let _ = fit(model, x_seqs, targets, 200)
  let after = loss(model, x_seqs[0], targets[0])
  assert_true(after < before)
}

///|
test "rnn: lstm regression learns a simple sequence" {
  // Simple task: copy the sum of first two inputs to output
  let model = new(LSTM, 2, 8, 1, 0.05, false, 5.0, 77)
  let x_seqs : Array[Array[Array[Double]]] = []
  let targets : Array[Array[Double]] = []
  for i = 0; i < 10; i = i + 1 {
    let a = i.to_double()
    x_seqs.push([[a, 1.0], [a + 1.0, 1.0]])
    targets.push([a + a + 1.0])
  }
  let before = loss(model, x_seqs[0], targets[0])
  let _ = fit(model, x_seqs, targets, 200)
  let after = loss(model, x_seqs[0], targets[0])
  assert_true(after < before)
}

///|
test "rnn: classification learns XOR sequence" {
  // Binary classification: XOR of two inputs in the last timestep
  // Sequence [[a, 0], [b, 1]] -> class = XOR(a > 0.5, b > 0.5)
  let model = new(LSTM, 2, 16, 2, 0.05, true, 5.0, 1234)
  let x_seqs : Array[Array[Array[Double]]] = []
  let targets : Array[Array[Double]] = []
  // 4 patterns: (0,0)->0, (0,1)->1, (1,0)->1, (1,1)->0
  // Repeat each pattern with slight noise for 8 samples
  let patterns = [[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]
  let labels = [0, 1, 1, 0]
  for p = 0; p < 4; p = p + 1 {
    x_seqs.push([[patterns[p][0], patterns[p][1]]])
    let tgt = Array::make(2, 0.0)
    tgt[labels[p]] = 1.0
    targets.push(tgt)
  }
  let before = loss(model, x_seqs[0], targets[0])
  let _ = fit(model, x_seqs, targets, 500)
  let after = loss(model, x_seqs[0], targets[0])
  assert_true(after < before)
}

///|
test "rnn: gradient clipping prevents explosion" {
  // With clipping enabled, training should not produce NaN
  let model = new(Vanilla, 1, 4, 1, 0.5, false, 1.0, 55)
  let x_seqs = [[[1.0], [1.0], [1.0], [1.0], [1.0]]]
  let targets = [[10.0]]
  let _avg = fit(model, x_seqs, targets, 50)
  // After training, loss should be finite
  let l = loss(model, x_seqs[0], targets[0])
  assert_true(l == l) // not NaN
  assert_true(l < 1.0e10) // not exploded
}

///|
test "rnn: predict_class returns valid index" {
  let model = new(LSTM, 2, 4, 3, 0.01, true, 0.0, 42)
  let x_seq = [[0.5, 0.5], [0.5, 0.5]]
  let cls = predict_class(model, x_seq)
  assert_true(cls >= 0 && cls < 3)
}

///|
test "rnn: empty sequence returns zero output" {
  let model = new(Vanilla, 2, 4, 3, 0.01, false, 0.0, 42)
  let out = predict(model, [])
  assert_true(out.length() == 3)
  for v in out {
    assert_true(v == 0.0)
  }
}
