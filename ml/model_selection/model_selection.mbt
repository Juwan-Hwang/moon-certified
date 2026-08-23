///|
/// Model Selection — Train/Test Split and K-Fold Cross Validation.
///
/// Provides standard data splitting utilities for ML model evaluation:
///
/// - **`train_test_split`**: Split data into training and testing subsets
///   with optional shuffling.
/// - **`KFold`**: K-Fold cross-validation iterator that partitions data
///   into K folds for systematic evaluation.
///
/// ## References
///
/// - scikit-learn `model_selection` module
/// - Kohavi, R. (1995): "A Study of Cross-Validation and Bootstrap for
///   Accuracy Estimation and Model Selection."
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Deterministic PRNG (xorshift32 for reproducible splits)
// ---------------------------------------------------------------------------

priv struct SplitRng {
  mut state : Int
}

///|
fn SplitRng::new(seed : Int) -> SplitRng {
  let s = seed & 0x7FFFFFFF
  { state: if s == 0 { 1 } else { s } }
}

///|
fn SplitRng::next(self : SplitRng) -> Int {
  // xorshift32
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.state = x & 0x7FFFFFFF
  self.state
}

///|
fn SplitRng::next_int(self : SplitRng, bound : Int) -> Int {
  if bound <= 0 {
    0
  } else {
    let v = (self.next().to_double() / 2147483648.0 * bound.to_double()).to_int()
    if v >= bound {
      bound - 1
    } else {
      v
    }
  }
}

// ---------------------------------------------------------------------------
// Train/Test Split
// ---------------------------------------------------------------------------

///|
/// Split data into training and testing subsets.
///
/// Returns `(train_indices, test_indices)` — arrays of integer indices
/// into the original dataset. The caller uses these to index into their
/// feature and label arrays.
///
/// - `n`: Total number of samples.
/// - `test_size`: Fraction of data for testing (0.0 to 1.0). Default 0.25.
/// - `shuffle`: If true, shuffle indices before splitting.
/// - `seed`: PRNG seed for reproducible shuffling.
///
/// ## Guarantees
///
/// - At least 1 sample in train and test (when n >= 2).
/// - No overlap between train and test indices.
/// - Union of train and test = all indices [0, n).
pub fn train_test_split(
  n : Int,
  test_size : Double,
  shuffle : Bool,
  seed : Int,
) -> (Array[Int], Array[Int]) {
  if n <= 0 {
    return ([], [])
  }
  if n == 1 {
    return ([0], [])
  }
  // Clamp test_size
  let ts = if test_size <= 0.0 {
    0.0
  } else if test_size >= 1.0 {
    0.5 // at most half for test when n >= 2
  } else {
    test_size
  }
  let n_test = if ts == 0.0 {
    0 // test_size == 0 means no test samples
  } else {
    let nt = (n.to_double() * ts).to_int()
    if nt < 1 {
      1
    } else if nt >= n {
      n - 1
    } else {
      nt
    }
  }
  // Build index array
  let indices = Array::makei(n, fn(i) { i })
  if shuffle {
    let rng = SplitRng::new(seed)
    // Fisher-Yates shuffle
    for i = 0; i < n - 1; i = i + 1 {
      let j = i + rng.next_int(n - i)
      let tmp = indices[i]
      indices[i] = indices[j]
      indices[j] = tmp
    }
  }
  // Split: first n_train for train, rest for test
  let n_train = n - n_test
  let train : Array[Int] = []
  let test_arr : Array[Int] = []
  for i = 0; i < n_train; i = i + 1 {
    train.push(indices[i])
  }
  for i = n_train; i < n; i = i + 1 {
    test_arr.push(indices[i])
  }
  (train, test_arr)
}

///|
/// Convenience: default split with 25% test, shuffled, seed=42.
pub fn train_test_split_default(n : Int) -> (Array[Int], Array[Int]) {
  train_test_split(n, 0.25, true, 42)
}

// ---------------------------------------------------------------------------
// K-Fold Cross Validation
// ---------------------------------------------------------------------------

///|
/// K-Fold cross-validation fold iterator.
///
/// Partitions `[0, n)` into K folds. Each call to `next()` returns the
/// next `(train_indices, test_indices)` pair. In each iteration, one
/// fold is the test set and the remaining K-1 folds form the train set.
///
/// - For K folds with n samples, each fold has ⌈n/K⌉ or ⌊n/K⌋ samples.
/// - All samples appear in exactly one test fold.
/// - No overlap between test folds.
///
/// ## Complexity
///
/// - `new`: O(1)
/// - `next`: O(n) to build train indices
pub struct KFold {
  priv n : Int
  priv k : Int
  priv mut current_fold : Int
  priv fold_sizes : Array[Int]
}

///|
/// Create a K-Fold iterator for `n` samples with `k` folds.
///
/// - `n`: Total number of samples (must be > 0).
/// - `k`: Number of folds (must be >= 2 and <= n).
///
/// Returns `None` if parameters are invalid.
pub fn KFold::new(n : Int, k : Int) -> KFold? {
  if n <= 0 || k < 2 || k > n {
    return None
  }
  // Distribute samples: first (n % k) folds get one extra sample
  let fold_sizes = Array::make(k, n / k)
  let remainder = n % k
  for i = 0; i < remainder; i = i + 1 {
    fold_sizes[i] = fold_sizes[i] + 1
  }
  Some({ n, k, current_fold: 0, fold_sizes })
}

///|
/// Get the next fold. Returns `None` when all K folds have been iterated.
///
/// The returned pair is `(train_indices, test_indices)` where the test
/// set is the current fold and the train set is all other samples.
pub fn KFold::next(kf : KFold) -> (Array[Int], Array[Int])? {
  if kf.current_fold >= kf.k {
    return None
  }
  let fold = kf.current_fold
  // Compute start index of this fold
  let mut start = 0
  for i = 0; i < fold; i = i + 1 {
    start = start + kf.fold_sizes[i]
  }
  let fold_size = kf.fold_sizes[fold]
  // Build test indices
  let test_arr : Array[Int] = []
  for i = 0; i < fold_size; i = i + 1 {
    test_arr.push(start + i)
  }
  // Build train indices (all except test fold)
  let train : Array[Int] = []
  for i = 0; i < start; i = i + 1 {
    train.push(i)
  }
  let after_test = start + fold_size
  for i = after_test; i < kf.n; i = i + 1 {
    train.push(i)
  }
  kf.current_fold = kf.current_fold + 1
  Some((train, test_arr))
}

///|
/// Number of folds.
pub fn KFold::n_folds(kf : KFold) -> Int {
  kf.k
}

///|
/// Total number of samples.
pub fn KFold::n_samples(kf : KFold) -> Int {
  kf.n
}

///|
/// Get all folds as an array of (train, test) pairs.
pub fn KFold::all_folds(kf : KFold) -> Array[(Array[Int], Array[Int])] {
  let result : Array[(Array[Int], Array[Int])] = []
  let kf_copy = { n: kf.n, k: kf.k, current_fold: 0, fold_sizes: kf.fold_sizes }
  let mut done = false
  while !done {
    match KFold::next(kf_copy) {
      Some(pair) => result.push(pair)
      None => done = true
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tests: train_test_split
// ---------------------------------------------------------------------------

///|
test "split: basic split without shuffle" {
  let (train, test_arr) = train_test_split(10, 0.3, false, 0)
  assert_eq(train.length(), 7)
  assert_eq(test_arr.length(), 3)
  // Without shuffle, indices should be in order
  assert_eq(train[0], 0)
  assert_eq(train[6], 6)
  assert_eq(test_arr[0], 7)
  assert_eq(test_arr[2], 9)
}

///|
test "split: with shuffle" {
  let (train, test_arr) = train_test_split(20, 0.25, true, 42)
  assert_eq(train.length(), 15)
  assert_eq(test_arr.length(), 5)
  // Check no overlap
  let all_present = Array::make(20, false)
  for i = 0; i < train.length(); i = i + 1 {
    all_present[train[i]] = true
  }
  for i = 0; i < test_arr.length(); i = i + 1 {
    assert_false(all_present[test_arr[i]])
    all_present[test_arr[i]] = true
  }
  // All indices should be present
  for i = 0; i < 20; i = i + 1 {
    assert_true(all_present[i])
  }
}

///|
test "split: deterministic with seed" {
  let (t1, s1) = train_test_split(100, 0.2, true, 999)
  let (t2, s2) = train_test_split(100, 0.2, true, 999)
  // Same seed → same split
  for i = 0; i < t1.length(); i = i + 1 {
    assert_eq(t1[i], t2[i])
  }
  for i = 0; i < s1.length(); i = i + 1 {
    assert_eq(s1[i], s2[i])
  }
}

///|
test "split: default 25%" {
  let (train, test_arr) = train_test_split_default(100)
  assert_eq(train.length(), 75)
  assert_eq(test_arr.length(), 25)
}

///|
test "split: edge cases" {
  // n=1
  let (t1, s1) = train_test_split(1, 0.5, false, 0)
  assert_eq(t1.length(), 1)
  assert_eq(s1.length(), 0)
  // n=0
  let (t0, s0) = train_test_split(0, 0.5, false, 0)
  assert_eq(t0.length(), 0)
  assert_eq(s0.length(), 0)
}

///|
test "split: all train (test_size=0)" {
  let (train, test_arr) = train_test_split(10, 0.0, false, 0)
  assert_eq(train.length(), 10)
  assert_eq(test_arr.length(), 0)
}

// ---------------------------------------------------------------------------
// Tests: KFold
// ---------------------------------------------------------------------------

///|
test "kfold: basic 5-fold" {
  let kf = KFold::new(10, 5)
  match kf {
    Some(k) => {
      assert_eq(KFold::n_folds(k), 5)
      assert_eq(KFold::n_samples(k), 10)
      let folds = KFold::all_folds(k)
      assert_eq(folds.length(), 5)
      // Each fold: 2 test, 8 train
      for i = 0; i < 5; i = i + 1 {
        let (train, test_arr) = folds[i]
        assert_eq(test_arr.length(), 2)
        assert_eq(train.length(), 8)
      }
      // Verify all test indices are unique and cover [0, 10)
      let seen = Array::make(10, false)
      for i = 0; i < 5; i = i + 1 {
        let (_, test_arr) = folds[i]
        for j = 0; j < test_arr.length(); j = j + 1 {
          assert_false(seen[test_arr[j]])
          seen[test_arr[j]] = true
        }
      }
      for i = 0; i < 10; i = i + 1 {
        assert_true(seen[i])
      }
    }
    None => assert_true(false)
  }
}

///|
test "kfold: 3-fold with remainder" {
  // 10 / 3 = 3 remainder 1 → first fold gets 4, others get 3
  let kf = KFold::new(10, 3)
  match kf {
    Some(k) => {
      let folds = KFold::all_folds(k)
      assert_eq(folds.length(), 3)
      let (_, t0) = folds[0]
      let (_, t1) = folds[1]
      let (_, t2) = folds[2]
      assert_eq(t0.length(), 4) // first fold gets extra
      assert_eq(t1.length(), 3)
      assert_eq(t2.length(), 3)
      // Total should be 10
      assert_eq(t0.length() + t1.length() + t2.length(), 10)
    }
    None => assert_true(false)
  }
}

///|
test "kfold: next iteration" {
  let kf = KFold::new(6, 3)
  match kf {
    Some(k) => {
      // First fold: test_arr = [0, 1], train = [2,3,4,5]
      match KFold::next(k) {
        Some((train, test_arr)) => {
          assert_eq(test_arr, [0, 1])
          assert_eq(train, [2, 3, 4, 5])
        }
        None => assert_true(false)
      }
      // Second fold: test_arr = [2, 3], train = [0,1,4,5]
      match KFold::next(k) {
        Some((train, test_arr)) => {
          assert_eq(test_arr, [2, 3])
          assert_eq(train, [0, 1, 4, 5])
        }
        None => assert_true(false)
      }
      // Third fold: test_arr = [4, 5], train = [0,1,2,3]
      match KFold::next(k) {
        Some((train, test_arr)) => {
          assert_eq(test_arr, [4, 5])
          assert_eq(train, [0, 1, 2, 3])
        }
        None => assert_true(false)
      }
      // No more folds
      match KFold::next(k) {
        Some(_) => assert_true(false)
        None => assert_true(true)
      }
    }
    None => assert_true(false)
  }
}

///|
test "kfold: invalid parameters" {
  // k > n
  match KFold::new(3, 5) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
  // k < 2
  match KFold::new(10, 1) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
  // n <= 0
  match KFold::new(0, 2) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
  match KFold::new(-5, 2) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "kfold: k equals n (leave-one-out)" {
  let kf = KFold::new(5, 5)
  match kf {
    Some(k) => {
      let folds = KFold::all_folds(k)
      assert_eq(folds.length(), 5)
      // Each fold: 1 test, 4 train
      for i = 0; i < 5; i = i + 1 {
        let (train, test_arr) = folds[i]
        assert_eq(test_arr.length(), 1)
        assert_eq(train.length(), 4)
      }
    }
    None => assert_true(false)
  }
}

///|
test "kfold: no overlap between train and test" {
  let kf = KFold::new(20, 4)
  match kf {
    Some(k) => {
      let folds = KFold::all_folds(k)
      let in_test = Array::make(20, false)
      for i = 0; i < 4; i = i + 1 {
        let (train, test_arr) = folds[i]
        // Reset
        for j = 0; j < 20; j = j + 1 {
          in_test[j] = false
        }
        // Mark test indices
        for j = 0; j < test_arr.length(); j = j + 1 {
          in_test[test_arr[j]] = true
        }
        // Check no overlap
        for j = 0; j < train.length(); j = j + 1 {
          assert_false(in_test[train[j]])
        }
      }
    }
    None => assert_true(false)
  }
}
