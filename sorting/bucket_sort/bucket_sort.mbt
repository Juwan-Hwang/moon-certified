/// Bucket Sort — distribution-based sorting.
///
/// Distributes elements into buckets, sorts each bucket, then concatenates.
/// Achieves O(n) average case when input is uniformly distributed.
///
/// ## Complexity
/// - Time:  O(n + k) average, O(n²) worst (k = bucket count).
/// - Space: O(n + k).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

/// Sort an array of doubles into evenly spaced buckets.
///
/// `min_val` and `max_val` define the value range. Elements outside
/// this range are clamped to the nearest bucket.
pub fn bucket_sort(
  arr : Array[Double],
  min_val : Double,
  max_val : Double,
) -> Array[Double] {
  let n = arr.length()
  if n <= 1 {
    return arr.copy()
  }
  let bucket_count = if n > 1000 { 1000 } else { n }
  let buckets : Array[Array[Double]] = FixedArray::makei(bucket_count, fn(_) { [] }) |> fn(fa) {
    let a : Array[Array[Double]] = []
    for i = 0; i < bucket_count; i = i + 1 {
      a.push(fa[i])
    }
    a
  }
  let range = max_val - min_val
  let scale = if range > 0.0 { (bucket_count.to_double() - 1.0) / range } else { 0.0 }
  for i = 0; i < n; i = i + 1 {
    let v = arr[i]
    let idx = if v <= min_val {
      0
    } else if v >= max_val {
      bucket_count - 1
    } else {
      ((v - min_val) * scale).to_int()
    }
    buckets[idx].push(v)
  }
  let result : Array[Double] = []
  for i = 0; i < bucket_count; i = i + 1 {
    insertion_sort_dbl(buckets[i])
    for j = 0; j < buckets[i].length(); j = j + 1 {
      result.push(buckets[i][j])
    }
  }
  result
}

fn insertion_sort_dbl(a : Array[Double]) -> Unit {
  for i = 1; i < a.length(); i = i + 1 {
    let key = a[i]
    let mut j = i - 1
    while j >= 0 && a[j] > key {
      a[j + 1] = a[j]
      j = j - 1
    }
    a[j + 1] = key
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "bucket_sort: sorted output" {
  let arr = [0.78, 0.17, 0.39, 0.26, 0.72, 0.94, 0.21, 0.12, 0.23, 0.68]
  let sorted = bucket_sort(arr, 0.0, 1.0)
  for i = 1; i < sorted.length(); i = i + 1 {
    assert_true(sorted[i - 1] <= sorted[i])
  }
}

test "bucket_sort: empty and single" {
  let empty : Array[Double] = []
  assert_eq(bucket_sort(empty, 0.0, 1.0).length(), 0)
  assert_eq(bucket_sort([3.14], 0.0, 10.0).length(), 1)
}

test "bucket_sort: uniform distribution" {
  let arr = [5.0, 1.0, 4.0, 2.0, 3.0, 9.0, 7.0, 8.0, 6.0, 0.0]
  let sorted = bucket_sort(arr, 0.0, 10.0)
  for i = 0; i < sorted.length(); i = i + 1 {
    assert_eq(sorted[i], i.to_double())
  }
}
