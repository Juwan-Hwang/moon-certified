test "confusion_matrix: perfect prediction" {
  let cm = confusion_matrix([0, 1, 0, 1], [0, 1, 0, 1], 1)
  assert_eq(cm.tp, 2)
  assert_eq(cm.fp, 0)
  assert_eq(cm.tn, 2)
  assert_eq(cm.fneg, 0)
}

test "confusion_matrix: all wrong" {
  let cm = confusion_matrix([0, 1, 0, 1], [1, 0, 1, 0], 1)
  assert_eq(cm.tp, 0)
  assert_eq(cm.fp, 2)
  assert_eq(cm.tn, 0)
  assert_eq(cm.fneg, 2)
}

test "accuracy: perfect and imperfect" {
  let perfect = confusion_matrix([0, 1], [0, 1], 1)
  assert_eq(accuracy(perfect), 1.0)
  let imperfect = make_confusion_matrix(3, 1, 4, 2)
  // (3+4)/(3+1+4+2) = 7/10 = 0.7
  assert_eq(accuracy(imperfect), 0.7)
}

test "precision: known values" {
  let cm = make_confusion_matrix(8, 2, 80, 10)
  // P = 8/(8+2) = 0.8
  assert_true(precision(cm) > 0.7999 && precision(cm) < 0.8001)
  // Edge: no positive predictions
  let cm2 = make_confusion_matrix(0, 0, 10, 5)
  assert_eq(precision(cm2), 0.0)
}

test "recall: known values" {
  let cm = make_confusion_matrix(8, 2, 80, 10)
  // R = 8/(8+10) = 0.4444...
  let r = recall(cm)
  assert_true(r > 0.4443 && r < 0.4445)
}

test "f1_score: known values" {
  let cm = make_confusion_matrix(8, 2, 80, 10)
  // P = 0.8, R = 8/18 ≈ 0.4444
  // F1 = 2*0.8*0.4444/(0.8+0.4444) ≈ 0.5714
  let f1 = f1_score(cm)
  assert_true(f1 > 0.5710 && f1 < 0.5720)
}

test "fbeta_score: F2 vs F0.5" {
  let cm = make_confusion_matrix(8, 2, 80, 10)
  // P=0.8 > R≈0.444, so F0.5 (precision-weighted) > F2 (recall-weighted)
  let f2 = fbeta_score(cm, 2.0)
  let f05 = fbeta_score(cm, 0.5)
  assert_true(f05 > f2)
}

test "specificity: known values" {
  let cm = make_confusion_matrix(8, 2, 80, 10)
  // Specificity = 80/(80+2) = 0.9756...
  let s = specificity(cm)
  assert_true(s > 0.9755 && s < 0.9757)
}

test "balanced_accuracy: known values" {
  let cm = make_confusion_matrix(8, 2, 80, 10)
  // recall ≈ 0.4444, specificity ≈ 0.9756
  // balanced = (0.4444 + 0.9756)/2 ≈ 0.71
  let ba = balanced_accuracy(cm)
  assert_true(ba > 0.7099 && ba < 0.7101)
}

test "mcc: perfect prediction" {
  let cm = make_confusion_matrix(10, 0, 10, 0)
  assert_eq(mcc(cm), 1.0)
}

test "mcc: all wrong" {
  let cm = make_confusion_matrix(0, 10, 0, 10)
  assert_eq(mcc(cm), -1.0)
}

test "mcc: random prediction" {
  let cm = make_confusion_matrix(5, 5, 5, 5)
  let m = mcc(cm)
  assert_true(m > -0.01 && m < 0.01)
}

test "cohen_kappa: perfect agreement" {
  let cm = make_confusion_matrix(10, 0, 10, 0)
  let k = cohen_kappa(cm)
  assert_true(k > 0.999)
}

test "cohen_kappa: partial agreement" {
  let cm = make_confusion_matrix(8, 2, 80, 10)
  let k = cohen_kappa(cm)
  assert_true(k > 0.0 && k < 1.0)
}

test "multi_class: macro precision" {
  let y_true = [0, 0, 1, 1, 2, 2]
  let y_pred = [0, 0, 1, 2, 2, 2]
  let cms = multi_class_confusion(y_true, y_pred, [0, 1, 2])
  let mp = macro_precision(cms)
  // Class 0: P=1.0, Class 1: P=1.0, Class 2: P=2/3≈0.667
  // Macro = (1.0 + 1.0 + 0.667)/3 ≈ 0.8889
  assert_true(mp > 0.8888 && mp < 0.8890)
}

test "multi_class: macro recall" {
  let y_true = [0, 0, 1, 1, 2, 2]
  let y_pred = [0, 0, 1, 2, 2, 2]
  let cms = multi_class_confusion(y_true, y_pred, [0, 1, 2])
  let mr = macro_recall(cms)
  // Class 0: R=1.0, Class 1: R=0.5, Class 2: R=1.0
  // Macro = (1.0 + 0.5 + 1.0)/3 = 0.8333...
  assert_true(mr > 0.8332 && mr < 0.8334)
}

test "multi_class: micro_f1 equals accuracy" {
  let y_true = [0, 0, 1, 1, 2, 2]
  let y_pred = [0, 0, 1, 2, 2, 2]
  let cms = multi_class_confusion(y_true, y_pred, [0, 1, 2])
  let mf1 = micro_f1(cms)
  // 5 correct out of 6 = 0.8333
  assert_true(mf1 > 0.8332 && mf1 < 0.8334)
}

test "multi_class: weighted averages" {
  let y_true = [0, 0, 1, 1, 2, 2]
  let y_pred = [0, 0, 1, 2, 2, 2]
  let labels = [0, 1, 2]
  let cms = multi_class_confusion(y_true, y_pred, labels)
  // All classes have support 2, so weighted == macro
  let wp = weighted_precision(cms, labels)
  let mp = macro_precision(cms)
  assert_true(wp > mp - 0.001 && wp < mp + 0.001)
}

test "mse: known values" {
  assert_eq(mse([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]), 0.0)
  // (1+0+1)/3 = 0.6667
  let m = mse([1.0, 2.0, 3.0], [2.0, 2.0, 2.0])
  assert_true(m > 0.6666 && m < 0.6668)
}

test "rmse: known values" {
  let r = rmse([1.0, 2.0, 3.0], [2.0, 2.0, 2.0])
  // sqrt(2/3) ≈ 0.8165
  assert_true(r > 0.8164 && r < 0.8166)
}

test "mae: known values" {
  assert_eq(mae([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]), 0.0)
  // (1+0+1)/3 = 0.6667
  let m = mae([1.0, 2.0, 3.0], [2.0, 2.0, 2.0])
  assert_true(m > 0.6666 && m < 0.6668)
}

test "r2_score: perfect prediction" {
  assert_eq(r2_score([1.0, 2.0, 3.0], [1.0, 2.0, 3.0]), 1.0)
}

test "r2_score: mean prediction" {
  // Predicting the mean should give R²=0
  let r = r2_score([1.0, 2.0, 3.0], [2.0, 2.0, 2.0])
  assert_true(r > -0.001 && r < 0.001)
}

test "r2_score: worse than mean" {
  let r = r2_score([1.0, 2.0, 3.0], [10.0, 10.0, 10.0])
  assert_true(r < 0.0)
}

test "mape: known values" {
  // |1-2|/1 + |2-2|/2 + |3-2|/3 = 1 + 0 + 0.333 = 1.333
  // MAPE = 100 * 1.333/3 = 44.44
  let m = mape([1.0, 2.0, 3.0], [2.0, 2.0, 2.0])
  assert_true(m > 44.43 && m < 44.45)
}

test "mape: ignores zero true values" {
  let m = mape([0.0, 1.0, 2.0], [1.0, 1.0, 2.0])
  // Only 2 samples: |1-1|/1 + |2-2|/2 = 0
  assert_eq(m, 0.0)
}

test "empty arrays return zero" {
  assert_eq(mse([], []), 0.0)
  assert_eq(mae([], []), 0.0)
  assert_eq(r2_score([], []), 0.0)
  assert_eq(mape([], []), 0.0)
}
