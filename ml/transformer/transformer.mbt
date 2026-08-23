/// Transformer Architecture — Self-Attention + Feed-Forward Network
///
/// Implements the core Transformer components from "Attention is All You Need"
/// (Vaswani et al., 2017):
/// - Scaled dot-product self-attention
/// - Multi-head attention
/// - Position-wise feed-forward network
/// - Layer normalization
/// - Positional encoding (sinusoidal)
///
/// `proof-enabled` is `false`.

///|
/// Hyperbolic tangent (tanh) implementation.
fn tanh_impl(x : Double) -> Double {
  // tanh(x) = (e^x - e^(-x)) / (e^x + e^(-x))
  // For numerical stability, use the sign-aware formula
  if x > 20.0 {
    return 1.0
  }
  if x < -20.0 {
    return -1.0
  }
  let exp_2x = @math.exp(2.0 * x)
  (exp_2x - 1.0) / (exp_2x + 1.0)
}

///|
/// Compute the GELU activation function.
fn gelu(x : Double) -> Double {
  0.5 * x * (1.0 + tanh_impl(0.7978845608028654 * (x + 0.044715 * x * x * x)))
}

///|
/// Softmax function.
fn softmax(x : Array[Double]) -> Array[Double] {
  let mut max_val = x[0]
  for v in x {
    if v > max_val {
      max_val = v
    }
  }
  let mut sum = 0.0
  let result = Array::make(x.length(), 0.0)
  for i = 0; i < x.length(); i = i + 1 {
    result[i] = @math.exp(x[i] - max_val)
    sum = sum + result[i]
  }
  for i = 0; i < x.length(); i = i + 1 {
    result[i] = result[i] / sum
  }
  result
}

///|
/// Layer normalization: (x - mean) / sqrt(var + eps) * gamma + beta.
fn layer_norm(
  x : Array[Double],
  gamma : Array[Double],
  beta : Array[Double],
  eps : Double,
) -> Array[Double] {
  let n = x.length().to_double()
  let mut mean = 0.0
  for v in x {
    mean = mean + v
  }
  mean = mean / n
  let mut variance = 0.0
  for v in x {
    let d = v - mean
    variance = variance + d * d
  }
  variance = variance / n
  let std = (variance + eps).sqrt()
  let result = Array::make(x.length(), 0.0)
  for i = 0; i < x.length(); i = i + 1 {
    result[i] = (x[i] - mean) / std * gamma[i] + beta[i]
  }
  result
}

///|
/// Scaled dot-product attention.
///
/// Q, K, V are matrices of shape [seq_len, d_k].
/// Returns attention(Q, K, V) = softmax(Q·K^T / sqrt(d_k)) · V
pub fn scaled_dot_product_attention(
  q : Array[Array[Double]],
  k : Array[Array[Double]],
  v : Array[Array[Double]],
  mask : Array[Array[Double]]?,
) -> Array[Array[Double]] {
  let seq_len = q.length()
  let d_k = q[0].length()
  // Compute scores = Q · K^T / sqrt(d_k)
  let scores : Array[Array[Double]] = []
  for _i = 0; _i < seq_len; _i = _i + 1 {
    scores.push(Array::make(k.length(), 0.0))
  }
  for i = 0; i < seq_len; i = i + 1 {
    for j = 0; j < k.length(); j = j + 1 {
      let mut dot = 0.0
      for d = 0; d < d_k; d = d + 1 {
        dot = dot + q[i][d] * k[j][d]
      }
      scores[i][j] = dot / d_k.to_double().sqrt()
    }
    // Apply mask if provided
    match mask {
      Some(m) =>
        if i < m.length() {
          for j = 0; j < k.length() && j < m[i].length(); j = j + 1 {
            if m[i][j] == 0.0 {
              scores[i][j] = -1.0e9
            }
          }
        }
      None => ()
    }
    // Softmax over keys
    let sm = softmax(scores[i])
    for j = 0; j < k.length(); j = j + 1 {
      scores[i][j] = sm[j]
    }
  }
  // Compute attention_output = scores · V
  let d_v = v[0].length()
  let output : Array[Array[Double]] = []
  for _i = 0; _i < seq_len; _i = _i + 1 {
    output.push(Array::make(d_v, 0.0))
  }
  for i = 0; i < seq_len; i = i + 1 {
    for j = 0; j < d_v; j = j + 1 {
      let mut sum = 0.0
      for m = 0; m < k.length(); m = m + 1 {
        sum = sum + scores[i][m] * v[m][j]
      }
      output[i][j] = sum
    }
  }
  output
}

///|
/// Multi-head attention layer.
///
/// ## Parameters
/// - `x`: input [seq_len, d_model]
/// - `w_q, w_k, w_v`: weight matrices [d_model, d_k * n_heads]
/// - `w_o`: output projection [d_k * n_heads, d_model]
/// - `n_heads`: number of attention heads
pub fn multi_head_attention(
  x : Array[Array[Double]],
  w_q : Array[Array[Double]],
  w_k : Array[Array[Double]],
  w_v : Array[Array[Double]],
  w_o : Array[Array[Double]],
  n_heads : Int,
) -> Array[Array[Double]] {
  let seq_len = x.length()
  let d_model = x[0].length()
  let d_k = w_q[0].length() / n_heads
  // Project to Q, K, V
  let q = matmul(x, w_q)
  let k = matmul(x, w_k)
  let v = matmul(x, w_v)
  // Split into heads and compute attention
  let head_outputs : Array[Array[Array[Double]]] = []
  for h = 0; h < n_heads; h = h + 1 {
    // Extract head h from Q, K, V
    let q_h : Array[Array[Double]] = []
    for _i = 0; _i < seq_len; _i = _i + 1 {
      q_h.push(Array::make(d_k, 0.0))
    }
    let k_h : Array[Array[Double]] = []
    for _i = 0; _i < seq_len; _i = _i + 1 {
      k_h.push(Array::make(d_k, 0.0))
    }
    let v_h : Array[Array[Double]] = []
    for _i = 0; _i < seq_len; _i = _i + 1 {
      v_h.push(Array::make(d_k, 0.0))
    }
    for i = 0; i < seq_len; i = i + 1 {
      for j = 0; j < d_k; j = j + 1 {
        q_h[i][j] = q[i][h * d_k + j]
        k_h[i][j] = k[i][h * d_k + j]
        v_h[i][j] = v[i][h * d_k + j]
      }
    }
    head_outputs.push(scaled_dot_product_attention(q_h, k_h, v_h, None))
  }
  // Concatenate heads
  let concat : Array[Array[Double]] = []
  for _i = 0; _i < seq_len; _i = _i + 1 {
    concat.push(Array::make(n_heads * d_k, 0.0))
  }
  for h = 0; h < n_heads; h = h + 1 {
    for i = 0; i < seq_len; i = i + 1 {
      for j = 0; j < d_k; j = j + 1 {
        concat[i][h * d_k + j] = head_outputs[h][i][j]
      }
    }
  }
  // Output projection
  matmul(concat, w_o)
}

///|
/// Matrix multiplication C = A · B where A is [m×k] and B is [k×n].
fn matmul(
  a : Array[Array[Double]],
  b : Array[Array[Double]],
) -> Array[Array[Double]] {
  let m = a.length()
  let k = a[0].length()
  let n = b[0].length()
  let c : Array[Array[Double]] = []
  for _i = 0; _i < m; _i = _i + 1 {
    c.push(Array::make(n, 0.0))
  }
  for i = 0; i < m; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let mut sum = 0.0
      for l = 0; l < k; l = l + 1 {
        sum = sum + a[i][l] * b[l][j]
      }
      c[i][j] = sum
    }
  }
  c
}

///|
/// Feed-forward network (2-layer MLP with GELU).
pub fn feed_forward(
  x : Array[Array[Double]],
  w1 : Array[Array[Double]],
  b1 : Array[Double],
  w2 : Array[Array[Double]],
  b2 : Array[Double],
) -> Array[Array[Double]] {
  let h = matmul(x, w1) // [seq, d_ff]
  // Add bias + GELU
  for i = 0; i < h.length(); i = i + 1 {
    for j = 0; j < h[i].length(); j = j + 1 {
      h[i][j] = gelu(h[i][j] + b1[j])
    }
  }
  let out = matmul(h, w2) // [seq, d_model]
  // Add bias
  for i = 0; i < out.length(); i = i + 1 {
    for j = 0; j < out[i].length(); j = j + 1 {
      out[i][j] = out[i][j] + b2[j]
    }
  }
  out
}

///|
/// Sinusoidal positional encoding.
pub fn positional_encoding(
  seq_len : Int,
  d_model : Int,
) -> Array[Array[Double]] {
  let pe : Array[Array[Double]] = []
  for _i = 0; _i < seq_len; _i = _i + 1 {
    pe.push(Array::make(d_model, 0.0))
  }
  for pos = 0; pos < seq_len; pos = pos + 1 {
    for i = 0; i < d_model / 2; i = i + 1 {
      let angle = pos.to_double() /
        10000.0.pow(2.0 * i.to_double() / d_model.to_double())
      pe[pos][2 * i] = @math.sin(angle)
      pe[pos][2 * i + 1] = @math.cos(angle)
    }
  }
  pe
}

///|
/// Transformer encoder layer forward pass.
pub fn transformer_encoder_forward(
  x : Array[Array[Double]],
  w_q : Array[Array[Double]],
  w_k : Array[Array[Double]],
  w_v : Array[Array[Double]],
  w_o : Array[Array[Double]],
  n_heads : Int,
  w1 : Array[Array[Double]],
  b1 : Array[Double],
  w2 : Array[Array[Double]],
  b2 : Array[Double],
  gamma1 : Array[Double],
  beta1 : Array[Double],
  gamma2 : Array[Double],
  beta2 : Array[Double],
  eps : Double,
) -> Array[Array[Double]] {
  // 1. Self-attention + residual + layer norm
  let attn_out = multi_head_attention(x, w_q, w_k, w_v, w_o, n_heads)
  // Residual connection + layer norm
  let norm1 : Array[Array[Double]] = []
  for _i = 0; _i < x.length(); _i = _i + 1 {
    norm1.push(Array::make(x[0].length(), 0.0))
  }
  for i = 0; i < x.length(); i = i + 1 {
    for j = 0; j < x[i].length(); j = j + 1 {
      norm1[i][j] = x[i][j] + attn_out[i][j]
    }
    let ln = layer_norm(norm1[i], gamma1, beta1, eps)
    for j = 0; j < ln.length(); j = j + 1 {
      norm1[i][j] = ln[j]
    }
  }
  // 2. Feed-forward + residual + layer norm
  let ffn_out = feed_forward(norm1, w1, b1, w2, b2)
  let result : Array[Array[Double]] = []
  for _i = 0; _i < x.length(); _i = _i + 1 {
    result.push(Array::make(x[0].length(), 0.0))
  }
  for i = 0; i < x.length(); i = i + 1 {
    for j = 0; j < x[i].length(); j = j + 1 {
      result[i][j] = norm1[i][j] + ffn_out[i][j]
    }
    let ln = layer_norm(result[i], gamma2, beta2, eps)
    for j = 0; j < ln.length(); j = j + 1 {
      result[i][j] = ln[j]
    }
  }
  result
}

///|
/// Cross-entropy loss for language modeling.
pub fn cross_entropy_loss(
  predicted : Array[Double],
  target_idx : Int,
) -> Double {
  if target_idx < 0 || target_idx >= predicted.length() {
    return 0.0
  }
  let probs = softmax(predicted)
  if probs[target_idx] > 0.0 {
    -@math.ln(probs[target_idx])
  } else {
    1.0e10
  }
}
