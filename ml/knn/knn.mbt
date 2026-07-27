/// K-Nearest-Neighbours classifier.
///
/// A non-parametric, instance-based learner: the training set is stored
/// verbatim, and a query is classified by a majority vote over its `k`
/// nearest training points under the (squared) Euclidean metric.
///
/// ## Distance
/// Squared Euclidean distance is used for neighbour selection. Because sqrt
/// is monotonic, the set of `k` nearest neighbours is identical to the one
/// obtained with true Euclidean distance, yet no square root is evaluated.
///
/// ## Tie-breaking
/// - *Distance ties at the k-th boundary* are broken lexicographically by
///   `(distance, label, index)` so the selected neighbour set is fully
///   deterministic for a given training order.
/// - *Vote ties* (two labels with equal counts among the `k` nearest) are
///   broken by the **lowest label value**, as required by the spec.
///
/// ## Dimension safety
/// `knn_sq_dist` returns `+∞` for vectors of differing length, so a training
/// point whose dimension disagrees with the query is simply pushed to the
/// back of the neighbour ranking and never selected (unless `k` exceeds the
/// number of dimension-matching points). No `abort` is ever raised.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Constants & helpers
// ---------------------------------------------------------------------------

///|
/// Positive-infinity sentinel: a dimension-mismatched training point is
/// treated as infinitely far from the query, so it is never preferred over a
/// finite-distance neighbour. IEEE-754 `+∞` compares greater than every finite
/// `Double`.
let knn_inf : Double = 1.0 / 0.0

///|
/// A labelled training instance. `label` is the class to predict; `coords`
/// is the feature vector, whose dimension should match the query for the
/// point to be selectable as a neighbour.
pub struct KNNEntry {
  label : Int
  coords : Array[Double]
}

///|
/// Squared Euclidean distance between two equal-length vectors. Returns
/// `+∞` when the vectors differ in length so dimension-mismatched points are
/// never chosen as nearest neighbours.
fn knn_sq_dist(a : Array[Double], b : Array[Double]) -> Double {
  let n = a.length()
  if b.length() != n {
    return knn_inf
  }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = a[i] - b[i]
    s = s + d * d
  }
  s
}

///|
/// Strict total order on `(distance, label, index)` triples: lexicographic by
/// distance, then label, then original index. `index` makes the order a true
/// total order (no two distinct training points compare equal), which keeps
/// boundary-tie selection deterministic.
fn knn_before(a : (Double, Int, Int), b : (Double, Int, Int)) -> Bool {
  let (da, la, ia) = a
  let (db, lb, ib) = b
  if da != db {
    da < db
  } else if la != lb {
    la < lb
  } else {
    ia < ib
  }
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

///|
/// Predict the label of `query` by majority vote over its `k` nearest
/// training points.
///
/// **Parameters.**
/// - `train` — the labelled training set, in any order.
/// - `query` — the feature vector to classify.
/// - `k`     — neighbourhood size; clamped to `[1, |train|]`.
///
/// **Return value.** The predicted label. The label with the highest count
/// among the `k` nearest wins; ties are broken by the lowest label value.
///
/// **Edge cases.**
/// - Empty training set → `0` (no information to predict from).
/// - `k <= 0` → treated as `k = 1` (nearest neighbour only).
/// - `k > |train|` → clamped down to `|train|` (use every point).
/// - When fewer than `k` training points share the query's dimension, the
///   `+∞`-distance mismatched points still occupy trailing slots; the vote
///   then proceeds over whatever `k` points are ranked first, which may
///   include mismatched points. Callers should keep dimensions consistent.
///
/// **Determinism.** For a fixed training order the result is a pure function
/// of `(train, query, k)`: neighbour selection is a total order and the vote
/// tie-break is the lowest label, so identical inputs always classify
/// identically.
pub fn knn_classify(
  train : Array[KNNEntry],
  query : Array[Double],
  k : Int,
) -> Int {
  let n = train.length()
  if n == 0 {
    return 0
  }
  let kk = if k < 1 { 1 } else if k > n { n } else { k }
  // Rank every training point by (distance, label, index).
  let entries : Array[(Double, Int, Int)] = Array::make(n, (0.0, 0, 0))
  for i = 0; i < n; i = i + 1 {
    entries[i] = (knn_sq_dist(query, train[i].coords), train[i].label, i)
  }
  // Partial selection sort: bring the `kk` smallest entries to the front.
  // O(n * kk), and kk <= n, so at most O(n^2) — fine for moderate training
  // sets and free of any external sort dependency.
  for i = 0; i < kk; i = i + 1 {
    let mut best = i
    for j = i + 1; j < n; j = j + 1 {
      if knn_before(entries[j], entries[best]) {
        best = j
      }
    }
    if best != i {
      let tmp = entries[i]
      entries[i] = entries[best]
      entries[best] = tmp
    }
  }
  // Majority vote over the kk nearest. A double loop counts each label's
  // occurrences; the highest count wins, ties broken by the lowest label.
  let mut best_label = entries[0].1
  let mut best_count = -1
  for i = 0; i < kk; i = i + 1 {
    let li = entries[i].1
    let mut cnt = 0
    for j = 0; j < kk; j = j + 1 {
      if entries[j].1 == li {
        cnt = cnt + 1
      }
    }
    if cnt > best_count || (cnt == best_count && li < best_label) {
      best_count = cnt
      best_label = li
    }
  }
  best_label
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "knn: empty training set returns default label 0" {
  assert_eq(knn_classify([], [1.0, 2.0], 3), 0)
}

///|
test "knn: single training point echoes its label" {
  let train = [{ label: 7, coords: [0.0, 0.0] }]
  assert_eq(knn_classify(train, [10.0, 10.0], 1), 7)
}

///|
test "knn: query near its own class is classified correctly" {
  // Two classes on the x-axis: label 1 near x=0, label 2 near x=10.
  let train = [
    { label: 1, coords: [0.0] },
    { label: 1, coords: [0.5] },
    { label: 1, coords: [1.0] },
    { label: 2, coords: [10.0] },
    { label: 2, coords: [10.5] },
    { label: 2, coords: [11.0] },
  ]
  assert_eq(knn_classify(train, [0.2], 3), 1) // near the left blob
  assert_eq(knn_classify(train, [10.8], 3), 2) // near the right blob
}

///|
test "knn: k=1 picks the single nearest neighbour" {
  let train = [
    { label: 1, coords: [0.0, 0.0] },
    { label: 2, coords: [3.0, 0.0] },
    { label: 3, coords: [5.0, 0.0] },
  ]
  // Query at x=4.5 is closest to label 3 (dist^2 0.25), then label 2 (dist^2
  // 2.25), then label 1 (dist^2 20.25); no distance tie at the boundary.
  assert_eq(knn_classify(train, [4.5, 0.0], 1), 3)
}

///|
test "knn: vote tie is broken by the lowest label" {
  // Two equidistant neighbours with different labels; with k=2 the vote is
  // 1-1, so the lowest label (1) must win.
  let train = [{ label: 1, coords: [0.0] }, { label: 2, coords: [2.0] }]
  // Query at x=1 is exactly equidistant (dist^2 = 1) from both.
  assert_eq(knn_classify(train, [1.0], 2), 1)
}

///|
test "knn: three-way vote tie picks the lowest label" {
  // Three 2-D points all exactly distance 1 from the query, with labels
  // 5, 3, 9. With k=3 every label votes once, so the lowest label (3) wins.
  let train = [
    { label: 5, coords: [1.0, 0.0] },
    { label: 3, coords: [-1.0, 0.0] },
    { label: 9, coords: [0.0, 1.0] },
  ]
  assert_eq(knn_classify(train, [0.0, 0.0], 3), 3)
}

///|
test "knn: k greater than training size is clamped" {
  let train = [
    { label: 1, coords: [0.0] },
    { label: 1, coords: [1.0] },
    { label: 2, coords: [9.0] },
  ]
  // k=100 -> clamped to 3; majority of {1,1,2} is label 1.
  assert_eq(knn_classify(train, [0.5], 100), 1)
}

///|
test "knn: k <= 0 is treated as k = 1" {
  let train = [{ label: 1, coords: [0.0] }, { label: 2, coords: [9.0] }]
  assert_eq(knn_classify(train, [0.2], 0), 1)
  assert_eq(knn_classify(train, [8.9], -5), 2)
}

///|
test "knn: 2-D classification with overlapping-ish classes" {
  // Class 0 around (0,0), class 1 around (4,4); query near (0,0) -> 0.
  let train : Array[KNNEntry] = []
  for i = 0; i < 5; i = i + 1 {
    train.push({ label: 0, coords: [i.to_double() * 0.1, 0.0] })
  }
  for i = 0; i < 5; i = i + 1 {
    train.push({ label: 1, coords: [4.0 + i.to_double() * 0.1, 4.0] })
  }
  assert_eq(knn_classify(train, [0.05, 0.0], 3), 0)
  assert_eq(knn_classify(train, [4.05, 4.0], 3), 1)
}

///|
test "knn: majority overrides a single nearest outlier" {
  // Nearest neighbour is label 2, but the next four are label 1, so k=5 votes
  // 4-to-1 for label 1.
  let train = [
    { label: 2, coords: [0.9] }, // closest to query 1.0 (dist^2 0.01)
    { label: 1, coords: [1.1] }, // dist^2 0.01 (tie, lower label first)
    { label: 1, coords: [1.2] }, // dist^2 0.04
    { label: 1, coords: [1.3] }, // dist^2 0.09
    { label: 1, coords: [1.4] }, // dist^2 0.16
  ]
  assert_eq(knn_classify(train, [1.0], 5), 1)
}

///|
test "knn: dimension-mismatched training point is never preferred" {
  // The 3-D point would be "nearest" by raw coordinate value, but its
  // dimension disagrees with the query, so it is ranked last (+inf) and the
  // 2-D points decide the vote.
  let train = [
    { label: 9, coords: [0.0, 0.0, 0.0] }, // wrong dim -> +inf
    { label: 1, coords: [0.0, 0.0] }, // dist^2 1.0
    { label: 1, coords: [1.0, 1.0] }, // dist^2 0.0 -> nearest
  ]
  assert_eq(knn_classify(train, [1.0, 1.0], 1), 1)
}
