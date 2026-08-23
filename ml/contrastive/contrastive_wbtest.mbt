// White-box tests for ml/contrastive.
// Exercises every public loss function with representative tiny inputs and edges.

///|
fn approx(a : Double, b : Double, eps : Double) -> Bool {
  (a - b).abs() < eps
}

///|
test "cosine_similarity_identical" {
  assert_true(approx(cosine_similarity([1.0, 0.0], [1.0, 0.0]), 1.0, 1.0e-12))
  // scalar multiple -> still 1
  assert_true(approx(cosine_similarity([2.0, 0.0], [1.0, 0.0]), 1.0, 1.0e-12))
}

///|
test "cosine_similarity_orthogonal" {
  assert_true(approx(cosine_similarity([1.0, 0.0], [0.0, 1.0]), 0.0, 1.0e-12))
}

///|
test "cosine_similarity_opposite" {
  assert_true(approx(cosine_similarity([1.0, 0.0], [-1.0, 0.0]), -1.0, 1.0e-12))
}

///|
test "cosine_similarity_zero_vector" {
  // zero denominator returns 0.0
  assert_true(approx(cosine_similarity([0.0, 0.0], [1.0, 0.0]), 0.0, 1.0e-12))
}

///|
test "cosine_similarity_min_length" {
  // only compares up to the shorter vector's length
  assert_true(
    approx(cosine_similarity([1.0, 2.0, 3.0], [1.0, 2.0]), 1.0, 1.0e-12),
  )
}

///|
test "l2_squared_basic" {
  assert_true(approx(l2_squared([0.0, 0.0], [3.0, 4.0]), 25.0, 1.0e-12))
  assert_true(approx(l2_squared([1.0, 1.0], [1.0, 1.0]), 0.0, 1.0e-12))
}

///|
test "l2_squared_min_length" {
  assert_true(approx(l2_squared([1.0, 2.0, 3.0], [1.0, 2.0]), 0.0, 1.0e-12))
}

///|
test "info_nce_basic" {
  let loss = info_nce_loss([1.0, 0.0], [1.0, 0.0], [[0.0, 1.0]], 1.0)
  let e1 = @math.exp(1.0)
  let expected = -@math.ln(e1 / (e1 + @math.exp(0.0)))
  assert_true(approx(loss, expected, 1.0e-9))
  assert_true(loss > 0.0)
}

///|
test "info_nce_orthogonal_positive_larger_loss" {
  let loss_ident = info_nce_loss([1.0, 0.0], [1.0, 0.0], [[0.0, 1.0]], 1.0)
  let loss_orth = info_nce_loss([1.0, 0.0], [0.0, 1.0], [[1.0, 0.0]], 1.0)
  assert_true(loss_orth > loss_ident)
}

///|
test "info_nce_empty_negatives" {
  // only the positive -> softmax prob 1 -> loss 0
  let loss = info_nce_loss([1.0, 0.0], [1.0, 0.0], [], 1.0)
  assert_true(approx(loss, 0.0, 1.0e-12))
}

///|
test "nt_xent_basic" {
  let e0 = [1.0, 0.0]
  let e1 = [1.0, 0.0]
  let e2 = [0.0, 1.0]
  let e3 = [0.0, 1.0]
  let loss = nt_xent_loss([e0, e1, e2, e3], [(0, 1), (2, 3)], 1.0)
  // each pair: pos_sim=1, two orthogonal negatives sim 0 -> -ln(e/(e+2))
  let e1v = @math.exp(1.0)
  let expected = -@math.ln(e1v / (e1v + 2.0 * @math.exp(0.0)))
  assert_true(approx(loss, expected, 1.0e-9))
  assert_true(loss > 0.0 && loss < 1.0)
}

///|
test "nt_xent_single_pair_no_neg" {
  // 2 embeddings, paired: no other keys to serve as negatives -> loss 0
  let loss = nt_xent_loss([[1.0, 0.0], [1.0, 0.0]], [(0, 1)], 1.0)
  assert_true(approx(loss, 0.0, 1.0e-12))
}

///|
test "triplet_loss_close_negative" {
  // d_pos=2, d_neg=1, margin 1 -> max(0, 2-1+1)=2
  let l = triplet_loss([0.0, 0.0], [1.0, 1.0], [1.0, 0.0], 1.0)
  assert_true(approx(l, 2.0, 1.0e-12))
}

///|
test "triplet_loss_far_negative" {
  let l = triplet_loss([0.0, 0.0], [1.0, 1.0], [10.0, 10.0], 1.0)
  assert_true(approx(l, 0.0, 1.0e-12))
}

///|
test "triplet_loss_margin_zero" {
  let l = triplet_loss([0.0, 0.0], [1.0, 1.0], [1.0, 0.0], 0.0)
  assert_true(approx(l, 1.0, 1.0e-12))
}

///|
test "supcon_basic" {
  let e0 = [1.0, 0.0]
  let e1 = [1.0, 0.0]
  let e2 = [0.0, 1.0]
  let loss = supcon_loss([e0, e1, e2], [0, 0, 1], 1.0)
  assert_true(loss > 0.0 && loss < 1.0)
}

///|
test "supcon_all_identical_same_label" {
  let e = [1.0, 0.0]
  let loss = supcon_loss([e, e, e], [0, 0, 0], 1.0)
  assert_true(approx(loss, 0.0, 1.0e-12))
}

///|
test "supcon_distinct_labels" {
  // every label unique -> no positives -> loss 0
  let loss = supcon_loss([[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]], [0, 1, 2], 1.0)
  assert_true(approx(loss, 0.0, 1.0e-12))
}

///|
test "contrastive_loss_same_class" {
  // same class -> squared distance
  let l = contrastive_loss([0.0, 0.0], [3.0, 4.0], true, 2.0)
  assert_true(approx(l, 25.0, 1.0e-12))
}

///|
test "contrastive_loss_diff_class_margin_not_exceeded" {
  // d=1, margin=2 -> (2-1)^2 = 1
  let l = contrastive_loss([0.0, 0.0], [1.0, 0.0], false, 2.0)
  assert_true(approx(l, 1.0, 1.0e-12))
}

///|
test "contrastive_loss_diff_class_margin_exceeded" {
  // d=1, margin=0.5 -> negative -> 0
  let l = contrastive_loss([0.0, 0.0], [1.0, 0.0], false, 0.5)
  assert_true(approx(l, 0.0, 1.0e-12))
}
