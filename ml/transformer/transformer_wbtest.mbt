// White-box tests for ml/transformer.
// Covers attention, multi-head attention, feed-forward, positional encoding,
// cross-entropy, plus private helpers (softmax, layer_norm, matmul, gelu).

///|
fn approx_d(a : Double, b : Double, eps : Double) -> Bool {
  (a - b).abs() < eps
}

///|
test "softmax_sums_to_one" {
  let s = softmax([1.0, 2.0, 3.0])
  let mut sum = 0.0
  for v in s {
    sum = sum + v
    assert_true(v > 0.0 && v < 1.0)
  }
  assert_true(approx_d(sum, 1.0, 1.0e-9))
}

///|
test "softmax_constant_vector" {
  let s = softmax([0.0, 0.0, 0.0])
  for v in s {
    assert_true(approx_d(v, 1.0 / 3.0, 1.0e-9))
  }
}

///|
test "softmax_numerical_stability" {
  // very large logits must not overflow -> uniform
  let s = softmax([1000.0, 1000.0, 1000.0])
  for v in s {
    assert_true(approx_d(v, 1.0 / 3.0, 1.0e-9))
  }
}

///|
test "attention_shape_and_deterministic" {
  let q = [[1.0, 0.0], [0.0, 1.0]]
  let k = [[1.0, 0.0], [0.0, 1.0]]
  let v = [[1.0, 0.0], [0.0, 1.0]]
  let out = scaled_dot_product_attention(q, k, v, None)
  assert_eq(out.length(), 2)
  for row in out {
    assert_eq(row.length(), 2)
  }
  let out2 = scaled_dot_product_attention(q, k, v, None)
  for i = 0; i < 2; i = i + 1 {
    for j = 0; j < 2; j = j + 1 {
      assert_true(approx_d(out[i][j], out2[i][j], 1.0e-9))
    }
  }
}

///|
test "attention_mask_zeroes_key" {
  let q = [[1.0, 0.0], [0.0, 1.0]]
  let k = [[1.0, 0.0], [0.0, 1.0]]
  let v = [[1.0, 0.0], [0.0, 1.0]]
  let mask = Some([[1.0, 0.0], [1.0, 1.0]])
  let out = scaled_dot_product_attention(q, k, v, mask)
  // row 0 masks key 1 -> output equals v[0]
  assert_true(approx_d(out[0][0], 1.0, 1.0e-9))
  assert_true(approx_d(out[0][1], 0.0, 1.0e-9))
}

///|
test "multi_head_attention_identity_single_head" {
  // n_heads=1, identity projections, single token: output == input
  let x = [[1.0, 2.0]]
  let w = [[1.0, 0.0], [0.0, 1.0]]
  let out = multi_head_attention(x, w, w, w, w, 1)
  assert_eq(out.length(), 1)
  assert_eq(out[0].length(), 2)
  assert_true(approx_d(out[0][0], 1.0, 1.0e-9))
  assert_true(approx_d(out[0][1], 2.0, 1.0e-9))
}

///|
test "multi_head_attention_two_heads" {
  let x = [[1.0, 0.0, 0.0, 0.0]]
  let w = [
    [1.0, 0.0, 0.0, 0.0],
    [0.0, 1.0, 0.0, 0.0],
    [0.0, 0.0, 1.0, 0.0],
    [0.0, 0.0, 0.0, 1.0],
  ]
  let out = multi_head_attention(x, w, w, w, w, 2)
  assert_eq(out.length(), 1)
  assert_eq(out[0].length(), 4)
  assert_true(approx_d(out[0][0], 1.0, 1.0e-9))
  assert_true(approx_d(out[0][1], 0.0, 1.0e-9))
}

///|
test "feed_forward_exact_bias" {
  // zero input + zero weights -> output equals bias b2
  let x = [[0.0, 0.0]]
  let w1 = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
  let b1 = [0.0, 0.0, 0.0]
  let w2 = [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]
  let b2 = [5.0, 6.0]
  let out = feed_forward(x, w1, b1, w2, b2)
  assert_eq(out.length(), 1)
  assert_eq(out[0].length(), 2)
  assert_true(approx_d(out[0][0], 5.0, 1.0e-9))
  assert_true(approx_d(out[0][1], 6.0, 1.0e-9))
}

///|
test "positional_encoding_shape" {
  let pe = positional_encoding(3, 4)
  assert_eq(pe.length(), 3)
  for row in pe {
    assert_eq(row.length(), 4)
  }
}

///|
test "positional_encoding_known_values" {
  let pe = positional_encoding(3, 4)
  // pos 0 -> sin(0)=0, cos(0)=1
  assert_true(approx_d(pe[0][0], 0.0, 1.0e-9))
  assert_true(approx_d(pe[0][1], 1.0, 1.0e-9))
  // pos 1, i=0 -> angle=1 -> sin(1), cos(1)
  assert_true(approx_d(pe[1][0], @math.sin(1.0), 1.0e-9))
  assert_true(approx_d(pe[1][1], @math.cos(1.0), 1.0e-9))
}

///|
test "cross_entropy_basic" {
  let pred = [1.0, 2.0, 3.0]
  let loss = cross_entropy_loss(pred, 0)
  let s = softmax(pred)
  let expected = -@math.ln(s[0])
  assert_true(approx_d(loss, expected, 1.0e-9))
  assert_true(loss > 0.0)
}

///|
test "cross_entropy_out_of_range" {
  assert_true(approx_d(cross_entropy_loss([1.0, 2.0, 3.0], 10), 0.0, 1.0e-12))
  assert_true(approx_d(cross_entropy_loss([1.0, 2.0, 3.0], -1), 0.0, 1.0e-12))
}

///|
test "cross_entropy_uniform" {
  let loss = cross_entropy_loss([0.0, 0.0, 0.0], 0)
  assert_true(approx_d(loss, @math.ln(3.0), 1.0e-9))
}

///|
test "layer_norm_zero_mean" {
  let x = [1.0, 2.0, 3.0]
  let g = [1.0, 1.0, 1.0]
  let b = [0.0, 0.0, 0.0]
  let out = layer_norm(x, g, b, 1.0e-5)
  let mut sum = 0.0
  for v in out {
    sum = sum + v
  }
  assert_true(approx_d(sum, 0.0, 1.0e-9))
}

///|
test "matmul_identity" {
  let a = [[1.0, 2.0], [3.0, 4.0]]
  let id = [[1.0, 0.0], [0.0, 1.0]]
  let c = matmul(a, id)
  for i = 0; i < 2; i = i + 1 {
    for j = 0; j < 2; j = j + 1 {
      assert_true(approx_d(c[i][j], a[i][j], 1.0e-9))
    }
  }
}

///|
test "gelu_zero" {
  assert_true(approx_d(gelu(0.0), 0.0, 1.0e-9))
}
