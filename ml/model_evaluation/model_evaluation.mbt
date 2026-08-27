///|
/// Model evaluation metrics for machine learning.
///
/// This module provides standard classification and regression metrics used
/// to evaluate ML model performance:
///
/// ## Classification metrics
/// - **Confusion matrix**: TP, FP, TN, FN counts
/// - **Precision**: TP / (TP + FP) — positive predictive value
/// - **Recall (Sensitivity)**: TP / (TP + FN) — true positive rate
/// - **F1-score**: harmonic mean of precision and recall
/// - **Specificity**: TN / (TN + FP) — true negative rate
/// - **Accuracy**: (TP + TN) / (TP + TN + FP + FN)
/// - **Balanced accuracy**: (recall + specificity) / 2
/// - **MCC (Matthews Correlation Coefficient)**: balanced measure for imbalanced data
/// - **Cohen's Kappa**: agreement corrected for chance
///
/// ## Regression metrics
/// - **MSE (Mean Squared Error)**
/// - **RMSE (Root Mean Squared Error)**
/// - **MAE (Mean Absolute Error)**
/// - **R² (Coefficient of Determination)**
/// - **MAPE (Mean Absolute Percentage Error)**
///
/// ## Multi-class support
/// For multi-class problems, macro, micro, and weighted averages are provided.
///
/// ## References
///
/// - Powers, D.M.W. (2011). "Evaluation: From Precision, Recall and F-Measure
///   to ROC, Informedness, Markedness & Correlation."
/// - Chicco & Jurman (2020). "The advantages of the Matthews correlation
///   coefficient (MCC) over F1 score and accuracy in binary classification
///   evaluation."
/// - Cohen, J. (1960). "A Coefficient of Agreement for Nominal Scales."
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Local sqrt (Newton's method — @math.sqrt unavailable in MoonBit stdlib)
// ---------------------------------------------------------------------------

fn sqrt_double(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut guess = x
  if guess > 1.0 {
    guess = x / 2.0
  }
  for i = 0; i < 20; i = i + 1 {
    let next = (guess + x / guess) / 2.0
    let diff = next - guess
    if diff < 0.0 {
      if -diff < 1.0e-15 * guess {
        return next
      }
    } else if diff < 1.0e-15 * guess {
      return next
    }
    guess = next
  }
  guess
}

// ---------------------------------------------------------------------------
// Binary classification metrics
// ---------------------------------------------------------------------------

///|
/// Confusion matrix for binary classification.
///
/// - `tp`: true positives (predicted positive, actual positive)
/// - `fp`: false positives (predicted positive, actual negative)
/// - `tn`: true negatives (predicted negative, actual negative)
/// - `fn`: false negatives (predicted negative, actual positive)
pub struct ConfusionMatrix {
  tp : Int
  fp : Int
  tn : Int
  fneg : Int
}

///|
/// Create a confusion matrix from explicit counts.
///
/// Useful for testing or when counts are already known.
pub fn make_confusion_matrix(
  tp : Int,
  fp : Int,
  tn : Int,
  fneg : Int,
) -> ConfusionMatrix {
  { tp, fp, tn, fneg, }
}

///|
/// Compute the confusion matrix for binary classification.
///
/// `positive_label` is the label considered "positive"; all other labels
/// are treated as "negative".
pub fn confusion_matrix(
  y_true : Array[Int],
  y_pred : Array[Int],
  positive_label : Int,
) -> ConfusionMatrix {
  let mut tp = 0
  let mut fp = 0
  let mut tn = 0
  let mut fneg = 0
  for i = 0; i < y_true.length(); i = i + 1 {
    let actual = y_true[i] == positive_label
    let predicted = y_pred[i] == positive_label
    if actual && predicted {
      tp = tp + 1
    } else if !actual && predicted {
      fp = fp + 1
    } else if !actual && !predicted {
      tn = tn + 1
    } else {
      fneg = fneg + 1
    }
  }
  { tp, fp, tn, fneg, }
}

///|
/// Accuracy: (TP + TN) / (TP + TN + FP + FN).
///
/// Returns 0.0 if the total count is 0.
pub fn accuracy(cm : ConfusionMatrix) -> Double {
  let total = cm.tp + cm.tn + cm.fp + cm.fneg
  if total == 0 {
    return 0.0
  }
  (cm.tp + cm.tn).to_double() / total.to_double()
}

///|
/// Precision: TP / (TP + FP). Positive predictive value.
///
/// Returns 0.0 if TP + FP == 0 (no positive predictions).
pub fn precision(cm : ConfusionMatrix) -> Double {
  let denom = cm.tp + cm.fp
  if denom == 0 {
    return 0.0
  }
  cm.tp.to_double() / denom.to_double()
}

///|
/// Recall (sensitivity, true positive rate): TP / (TP + FN).
///
/// Returns 0.0 if TP + FN == 0 (no actual positives).
pub fn recall(cm : ConfusionMatrix) -> Double {
  let denom = cm.tp + cm.fneg
  if denom == 0 {
    return 0.0
  }
  cm.tp.to_double() / denom.to_double()
}

///|
/// Specificity (true negative rate): TN / (TN + FP).
///
/// Returns 0.0 if TN + FP == 0 (no actual negatives).
pub fn specificity(cm : ConfusionMatrix) -> Double {
  let denom = cm.tn + cm.fp
  if denom == 0 {
    return 0.0
  }
  cm.tn.to_double() / denom.to_double()
}

///|
/// F1-score: 2 * P * R / (P + R). Harmonic mean of precision and recall.
///
/// Returns 0.0 if P + R == 0.
pub fn f1_score(cm : ConfusionMatrix) -> Double {
  let p = precision(cm)
  let r = recall(cm)
  if p + r == 0.0 {
    return 0.0
  }
  2.0 * p * r / (p + r)
}

///|
/// F-beta score: weighted harmonic mean of precision and recall.
///
/// `beta > 1` weights recall more heavily; `beta < 1` weights precision more.
pub fn fbeta_score(cm : ConfusionMatrix, beta : Double) -> Double {
  let p = precision(cm)
  let r = recall(cm)
  let beta2 = beta * beta
  let denom = beta2 * p + r
  if denom == 0.0 {
    return 0.0
  }
  (1.0 + beta2) * p * r / denom
}

///|
/// Balanced accuracy: (recall + specificity) / 2.
///
/// Useful for imbalanced datasets where regular accuracy can be misleading.
pub fn balanced_accuracy(cm : ConfusionMatrix) -> Double {
  (recall(cm) + specificity(cm)) / 2.0
}

///|
/// Matthews Correlation Coefficient (MCC).
///
/// MCC = (TP*TN - FP*FN) / sqrt((TP+FP)(TP+FN)(TN+FP)(TN+FN))
///
/// Returns 0.0 if the denominator is 0 (degenerate case).
/// Range: [-1, +1]. +1 = perfect, 0 = random, -1 = inverse.
pub fn mcc(cm : ConfusionMatrix) -> Double {
  let tp = cm.tp.to_double()
  let tn = cm.tn.to_double()
  let fp = cm.fp.to_double()
  let fneg = cm.fneg.to_double()
  let numerator = tp * tn - fp * fneg
  let denom = sqrt_double((tp + fp) * (tp + fneg) * (tn + fp) * (tn + fneg))
  if denom == 0.0 {
    return 0.0
  }
  numerator / denom
}

///|
/// Cohen's Kappa: inter-rater agreement corrected for chance.
///
/// κ = (p_o - p_e) / (1 - p_e)
/// where p_o = observed agreement, p_e = expected (chance) agreement.
///
/// Range: [-1, +1]. 0 = chance agreement, 1 = perfect agreement.
pub fn cohen_kappa(cm : ConfusionMatrix) -> Double {
  let total = (cm.tp + cm.tn + cm.fp + cm.fneg).to_double()
  if total == 0.0 {
    return 0.0
  }
  let tp = cm.tp.to_double()
  let tn = cm.tn.to_double()
  let fp = cm.fp.to_double()
  let fneg = cm.fneg.to_double()
  // Observed agreement.
  let p_o = (tp + tn) / total
  // Expected (chance) agreement.
  let p_a_pos = (tp + fneg) / total // actual positive proportion
  let p_p_pos = (tp + fp) / total // predicted positive proportion
  let p_a_neg = (tn + fp) / total
  let p_p_neg = (tn + fneg) / total
  let p_e = p_a_pos * p_p_pos + p_a_neg * p_p_neg
  if p_e == 1.0 {
    return 0.0
  }
  (p_o - p_e) / (1.0 - p_e)
}

// ---------------------------------------------------------------------------
// Multi-class metrics
// ---------------------------------------------------------------------------

///|
/// Compute per-class confusion matrices for multi-class classification.
///
/// Returns a map from each label to its binary confusion matrix (treating
/// that label as positive and all others as negative).
pub fn multi_class_confusion(
  y_true : Array[Int],
  y_pred : Array[Int],
  labels : Array[Int],
) -> Map[Int, ConfusionMatrix] {
  let result : Map[Int, ConfusionMatrix] = Map([])
  for label in labels {
    result[label] = confusion_matrix(y_true, y_pred, label)
  }
  result
}

///|
/// Macro-averaged precision: average of per-class precision.
///
/// Each class is weighted equally regardless of support.
pub fn macro_precision(cms : Map[Int, ConfusionMatrix]) -> Double {
  let mut sum = 0.0
  let mut count = 0
  for label in cms.keys() {
    sum = sum + precision(cms[label])
    count = count + 1
  }
  if count == 0 {
    return 0.0
  }
  sum / count.to_double()
}

///|
/// Macro-averaged recall: average of per-class recall.
pub fn macro_recall(cms : Map[Int, ConfusionMatrix]) -> Double {
  let mut sum = 0.0
  let mut count = 0
  for label in cms.keys() {
    sum = sum + recall(cms[label])
    count = count + 1
  }
  if count == 0 {
    return 0.0
  }
  sum / count.to_double()
}

///|
/// Macro-averaged F1-score: average of per-class F1.
pub fn macro_f1(cms : Map[Int, ConfusionMatrix]) -> Double {
  let mut sum = 0.0
  let mut count = 0
  for label in cms.keys() {
    sum = sum + f1_score(cms[label])
    count = count + 1
  }
  if count == 0 {
    return 0.0
  }
  sum / count.to_double()
}

///|
/// Weighted-averaged precision: support-weighted average of per-class precision.
pub fn weighted_precision(
  cms : Map[Int, ConfusionMatrix],
  labels : Array[Int],
) -> Double {
  let mut total_weight = 0
  let mut weighted_sum = 0.0
  for label in labels {
    let cm = cms[label]
    let weight = cm.tp + cm.fneg // support = actual positives
    weighted_sum = weighted_sum + precision(cm) * weight.to_double()
    total_weight = total_weight + weight
  }
  if total_weight == 0 {
    return 0.0
  }
  weighted_sum / total_weight.to_double()
}

///|
/// Weighted-averaged recall: support-weighted average of per-class recall.
pub fn weighted_recall(
  cms : Map[Int, ConfusionMatrix],
  labels : Array[Int],
) -> Double {
  let mut total_weight = 0
  let mut weighted_sum = 0.0
  for label in labels {
    let cm = cms[label]
    let weight = cm.tp + cm.fneg
    weighted_sum = weighted_sum + recall(cm) * weight.to_double()
    total_weight = total_weight + weight
  }
  if total_weight == 0 {
    return 0.0
  }
  weighted_sum / total_weight.to_double()
}

///|
/// Weighted-averaged F1: support-weighted average of per-class F1.
pub fn weighted_f1(
  cms : Map[Int, ConfusionMatrix],
  labels : Array[Int],
) -> Double {
  let mut total_weight = 0
  let mut weighted_sum = 0.0
  for label in labels {
    let cm = cms[label]
    let weight = cm.tp + cm.fneg
    weighted_sum = weighted_sum + f1_score(cm) * weight.to_double()
    total_weight = total_weight + weight
  }
  if total_weight == 0 {
    return 0.0
  }
  weighted_sum / total_weight.to_double()
}

///|
/// Micro-averaged F1: computed from total TP, FP, FN across all classes.
///
/// For multi-class (single-label) classification, micro-F1 equals accuracy.
pub fn micro_f1(cms : Map[Int, ConfusionMatrix]) -> Double {
  let mut total_tp = 0
  let mut total_fp = 0
  let mut total_fn = 0
  for label in cms.keys() {
    let cm = cms[label]
    total_tp = total_tp + cm.tp
    total_fp = total_fp + cm.fp
    total_fn = total_fn + cm.fneg
  }
  if total_tp + total_fp == 0 || total_tp + total_fn == 0 {
    return 0.0
  }
  let p = total_tp.to_double() / (total_tp + total_fp).to_double()
  let r = total_tp.to_double() / (total_tp + total_fn).to_double()
  if p + r == 0.0 {
    return 0.0
  }
  2.0 * p * r / (p + r)
}

// ---------------------------------------------------------------------------
// Regression metrics
// ---------------------------------------------------------------------------

///|
/// Mean Squared Error (MSE).
///
/// MSE = (1/n) * Σ (y_true - y_pred)²
pub fn mse(y_true : Array[Double], y_pred : Array[Double]) -> Double {
  let n = y_true.length()
  if n == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let diff = y_true[i] - y_pred[i]
    sum = sum + diff * diff
  }
  sum / n.to_double()
}

///|
/// Root Mean Squared Error (RMSE).
///
/// RMSE = sqrt(MSE)
pub fn rmse(y_true : Array[Double], y_pred : Array[Double]) -> Double {
  sqrt_double(mse(y_true, y_pred))
}

///|
/// Mean Absolute Error (MAE).
///
/// MAE = (1/n) * Σ |y_true - y_pred|
pub fn mae(y_true : Array[Double], y_pred : Array[Double]) -> Double {
  let n = y_true.length()
  if n == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for i = 0; i < n; i = i + 1 {
    let diff = y_true[i] - y_pred[i]
    sum = sum + (if diff >= 0.0 { diff } else { -diff })
  }
  sum / n.to_double()
}

///|
/// R² (Coefficient of Determination).
///
/// R² = 1 - SS_res / SS_tot
/// where SS_res = Σ (y_true - y_pred)² and SS_tot = Σ (y_true - mean)².
///
/// Range: (-∞, 1]. 1.0 = perfect prediction, 0.0 = predicting the mean.
/// Can be negative if the model is worse than predicting the mean.
pub fn r2_score(y_true : Array[Double], y_pred : Array[Double]) -> Double {
  let n = y_true.length()
  if n == 0 {
    return 0.0
  }
  // Compute mean of y_true.
  let mut mean = 0.0
  for i = 0; i < n; i = i + 1 {
    mean = mean + y_true[i]
  }
  mean = mean / n.to_double()
  // Compute SS_res and SS_tot.
  let mut ss_res = 0.0
  let mut ss_tot = 0.0
  for i = 0; i < n; i = i + 1 {
    let res = y_true[i] - y_pred[i]
    ss_res = ss_res + res * res
    let tot = y_true[i] - mean
    ss_tot = ss_tot + tot * tot
  }
  if ss_tot == 0.0 {
    return 1.0 // All y_true are the same; perfect if pred matches.
  }
  1.0 - ss_res / ss_tot
}

///|
/// Mean Absolute Percentage Error (MAPE).
///
/// MAPE = (100/n) * Σ |y_true - y_pred| / |y_true|
///
/// Returns 0.0 if n == 0. Ignores samples where y_true == 0.
pub fn mape(y_true : Array[Double], y_pred : Array[Double]) -> Double {
  let n = y_true.length()
  if n == 0 {
    return 0.0
  }
  let mut sum = 0.0
  let mut count = 0
  for i = 0; i < n; i = i + 1 {
    if y_true[i] != 0.0 {
      let diff = y_true[i] - y_pred[i]
      let abs_diff = if diff >= 0.0 { diff } else { -diff }
      let abs_true = if y_true[i] >= 0.0 { y_true[i] } else { -y_true[i] }
      sum = sum + abs_diff / abs_true
      count = count + 1
    }
  }
  if count == 0 {
    return 0.0
  }
  100.0 * sum / count.to_double()
}
