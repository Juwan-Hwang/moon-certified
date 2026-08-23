/// Sample Sort — multi-pivot parallel-friendly comparison sort.
///
/// Sample Sort (a.k.a. *distribution sort* with sampling) generalises
/// quicksort by using **k − 1 splitters** instead of a single pivot, creating
/// **k buckets** in one pass. Well-chosen splitters produce near-equal buckets,
/// giving O(n log n / log k) expected depth — deeper parallelism than
/// quicksort's binary recursion tree.
///
/// ## Algorithm
///
/// 1. **Sample**: Draw `k · oversample` random elements from the array and
///    sort them.  Pick every `oversample`-th element as a splitter.
/// 2. **Partition**: Scan the array once, placing each element into one of
///    `k` buckets delimited by the splitters.
/// 3. **Recurse**: Sort each bucket recursively (with insertion sort for
///    small buckets).
///
/// ## Complexity
///
/// | Case     | Comparisons       | Space    |
/// |----------|-------------------|----------|
/// | Average  | O(n log n)        | O(n)     |
/// | Worst    | O(n²) (degenerate)| O(n)     |
///
/// With k = Θ(log n) splitters the expected depth is O(log n / log log n).
///
/// ## References
///
/// - Frazer, W. D. & McKellar, A. C. (1970). "Samplesort: A Sampling
///   Approach to Minimal Storage Tree Sorting." *JACM* 17(3), 496–507.
/// - Sanders, P. (1998). "Randomized Priority Queues for Fast Parallel
///   Access." *Technical Report*, Universität Karlsruhe.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Number of splitters per recursion level (bucket count = splitters + 1).
const NUM_SPLITS : Int = 8

///|
/// Oversampling ratio: sample `NUM_SPLITS * OVERSAMPLE` elements.
const OVERSAMPLE : Int = 16

///|
/// Threshold below which insertion sort is used directly.
const INSERTION_THRESHOLD : Int = 32

///|
/// Sort an array of integers in ascending order using sample sort.
///
/// Returns a **new** sorted array; the input is not modified.
pub fn sample_sort(arr : Array[Int]) -> Array[Int] {
  let n = arr.length()
  if n <= 1 {
    return Array::copy(arr)
  }
  let buf = Array::copy(arr)
  sample_sort_range(buf, 0, n)
  buf
}

///|
/// Sort `buf[lo..hi)` in place.
fn sample_sort_range(buf : Array[Int], lo : Int, hi : Int) -> Unit {
  let n = hi - lo
  if n <= INSERTION_THRESHOLD {
    insertion_sort(buf, lo, hi)
    return
  }
  if n <= NUM_SPLITS * OVERSAMPLE {
    // For small arrays, just use insertion sort
    insertion_sort(buf, lo, hi)
    return
  }
  // --- Step 1: Sample splitters ---
  let k = NUM_SPLITS // number of splitters
  let sample_count = k * OVERSAMPLE
  // Collect samples
  let samples : Array[Int] = []
  let step = if n > sample_count { n / sample_count } else { 1 }
  let mut s_idx = 0
  while samples.length() < sample_count && s_idx < n {
    samples.push(buf[lo + s_idx])
    s_idx = s_idx + step
  }
  // Sort samples to find good splitters
  insertion_sort(samples, 0, samples.length())
  // Pick k evenly-spaced splitters from sorted samples
  let splitters : Array[Int] = []
  for i = 0; i < k; i = i + 1 {
    let idx = (i + 1) * OVERSAMPLE
    if idx < samples.length() {
      splitters.push(samples[idx])
    }
  }
  let actual_k = splitters.length()
  if actual_k == 0 {
    insertion_sort(buf, lo, hi)
    return
  }
  // --- Step 2: Partition into k+1 buckets ---
  let bucket_count = actual_k + 1
  let buckets : Array[Array[Int]] = []
  for _ in 0..<bucket_count {
    buckets.push([])
  }
  for i = 0; i < n; i = i + 1 {
    let val = buf[lo + i]
    // Binary search for the right bucket
    let mut b = 0
    let mut left = 0
    let mut right = actual_k - 1
    while left <= right {
      let mid = (left + right) / 2
      if val < splitters[mid] {
        right = mid - 1
      } else {
        left = mid + 1
      }
    }
    b = left
    buckets[b].push(val)
  }
  // --- Step 3: Recursively sort each bucket and write back ---
  // Guard against infinite recursion when all elements are equal (all land
  // in the same bucket that's as large as the input).
  let mut max_bucket = 0
  for i = 0; i < bucket_count; i = i + 1 {
    let bl = buckets[i].length()
    if bl > max_bucket {
      max_bucket = bl
    }
  }
  if max_bucket == n {
    insertion_sort(buf, lo, hi)
    return
  }
  let mut pos = lo
  for i = 0; i < bucket_count; i = i + 1 {
    let bucket = buckets[i]
    if bucket.length() > 0 {
      sample_sort_range(bucket, 0, bucket.length())
      for j = 0; j < bucket.length(); j = j + 1 {
        buf[pos] = bucket[j]
        pos = pos + 1
      }
    }
  }
}

///|
/// Insertion sort for small subarrays.
fn insertion_sort(arr : Array[Int], lo : Int, hi : Int) -> Unit {
  for i = lo + 1; i < hi; i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= lo && arr[j] > key {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}

///|
/// Sort an array of doubles using sample sort.
pub fn sample_sort_double(arr : Array[Double]) -> Array[Double] {
  let n = arr.length()
  if n <= 1 {
    return Array::copy(arr)
  }
  let buf = Array::copy(arr)
  sample_sort_double_range(buf, 0, n)
  buf
}

///|
fn sample_sort_double_range(buf : Array[Double], lo : Int, hi : Int) -> Unit {
  let n = hi - lo
  if n <= INSERTION_THRESHOLD {
    insertion_sort_double(buf, lo, hi)
    return
  }
  if n <= NUM_SPLITS * OVERSAMPLE {
    insertion_sort_double(buf, lo, hi)
    return
  }
  let k = NUM_SPLITS
  let sample_count = k * OVERSAMPLE
  let samples : Array[Double] = []
  let step = if n > sample_count { n / sample_count } else { 1 }
  let mut s_idx = 0
  while samples.length() < sample_count && s_idx < n {
    samples.push(buf[lo + s_idx])
    s_idx = s_idx + step
  }
  insertion_sort_double(samples, 0, samples.length())
  let splitters : Array[Double] = []
  for i = 0; i < k; i = i + 1 {
    let idx = (i + 1) * OVERSAMPLE
    if idx < samples.length() {
      splitters.push(samples[idx])
    }
  }
  let actual_k = splitters.length()
  if actual_k == 0 {
    insertion_sort_double(buf, lo, hi)
    return
  }
  let bucket_count = actual_k + 1
  let buckets : Array[Array[Double]] = []
  for _ in 0..<bucket_count {
    buckets.push([])
  }
  for i = 0; i < n; i = i + 1 {
    let val = buf[lo + i]
    let mut left = 0
    let mut right = actual_k - 1
    while left <= right {
      let mid = (left + right) / 2
      if val < splitters[mid] {
        right = mid - 1
      } else {
        left = mid + 1
      }
    }
    buckets[left].push(val)
  }
  // Guard against infinite recursion when all elements are equal (all land
  // in the same bucket that's as large as the input).
  let mut max_bucket = 0
  for i = 0; i < bucket_count; i = i + 1 {
    let bl = buckets[i].length()
    if bl > max_bucket {
      max_bucket = bl
    }
  }
  if max_bucket == n {
    insertion_sort_double(buf, lo, hi)
    return
  }
  let mut pos = lo
  for i = 0; i < bucket_count; i = i + 1 {
    let bucket = buckets[i]
    if bucket.length() > 0 {
      sample_sort_double_range(bucket, 0, bucket.length())
      for j = 0; j < bucket.length(); j = j + 1 {
        buf[pos] = bucket[j]
        pos = pos + 1
      }
    }
  }
}

///|
fn insertion_sort_double(arr : Array[Double], lo : Int, hi : Int) -> Unit {
  for i = lo + 1; i < hi; i = i + 1 {
    let key = arr[i]
    let mut j = i - 1
    while j >= lo && arr[j] > key {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
  }
}
