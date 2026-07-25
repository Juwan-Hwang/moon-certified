/// Locality-Sensitive Hashing (LSH) for approximate nearest neighbour search.
///
/// LSH hashes input points so that nearby points tend to collide (get the same
/// hash) with higher probability than distant points. It is the standard
/// approach for approximate nearest neighbour search in high dimensions where
/// tree-based methods (KD-Tree, Ball-Tree) suffer from the curse of
/// dimensionality.
///
/// ## Algorithm
///
/// This implementation uses the **p-stable LSH** family for the L2 (Euclidean)
/// distance:
///
/// 1. Generate `L` hash tables, each with `k` random projection functions.
/// 2. Each projection is a random vector `a` drawn from a Gaussian
///    distribution; the hash value is `floor((a . x + b) / w)` where `b` is a
///    random offset in `[0, w)` and `w` is the bucket width.
/// 3. The composite hash for one table is the tuple of `k` individual hashes.
/// 4. Points with the same composite hash are stored in the same bucket.
/// 5. Query: compute the query's hash in each table and search the union of
///    all matching buckets for the nearest neighbour.
///
/// ## Complexity
///
/// - Build: O(n * L * k * d) where d is dimensionality.
/// - Query: O(L * k * d + candidate_count) -- sublinear in n for well-tuned
///   parameters.
///
/// ## Parameters
///
/// - `w` (bucket width): larger w -> more collisions -> higher recall, lower
///   precision. Typically set to ~4 * average nearest-neighbour distance.
/// - `k` (hash functions per table): larger k -> fewer collisions -> higher
///   precision, lower recall.
/// - `L` (number of tables): larger L -> higher recall.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// A single LSH hash table entry: composite hash key -> point indices.
pub struct Bucket {
  key : String
  indices : Array[Int]
}

/// A single LSH hash table.
pub struct LSHTable {
  projections : Array[Array[Double]]
  offsets : Array[Double]
  w : Double
  buckets : Array[Bucket]
}

/// The LSH index.
pub struct LSHIndex {
  tables : Array[LSHTable]
  k : Int
  l : Int
  w : Double
  d : Int
  points : Array[Array[Double]]
  seed : Int
}

/// A simple linear congruential generator for reproducible randomness.
priv struct LCG {
  mut state : Int64
}

fn lcg_new(seed : Int) -> LCG {
  { state: seed.to_int64() & 0x7FFFFFFFFFFFFFFFL }
}

fn lcg_next(lcg : LCG) -> Int64 {
  // Using glibc LCG parameters.
  lcg.state = (6364136223846793005L * lcg.state + 1442695040888963407L) &
    0x7FFFFFFFFFFFFFFFL
  lcg.state
}

fn lcg_next_double(lcg : LCG) -> Double {
  let v = lcg_next(lcg)
  v.to_double() / 9223372036854775807.0
}

// ---------------------------------------------------------------------------
// Math helpers (MoonBit @math lacks floor and ln)
// ---------------------------------------------------------------------------

fn lsh_floor(x : Double) -> Double {
  let i = x.to_int()
  if x < 0.0 && x != i.to_double() {
    (i - 1).to_double()
  } else {
    i.to_double()
  }
}

const LSH_LN2 : Double = 0.6931471805599453

fn lsh_ln(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut val = x
  let mut k = 0
  while val < 0.5 {
    val = val * 2.0
    k = k + 1
  }
  while val >= 1.0 {
    val = val / 2.0
    k = k - 1
  }
  let y = (val - 1.0) / (val + 1.0)
  let y2 = y * y
  let mut sum = 0.0
  let mut ypow = y
  let mut denom = 1.0
  let mut i = 0
  while i < 60 {
    sum = sum + ypow / denom
    ypow = ypow * y2
    denom = denom + 2.0
    i = i + 1
  }
  sum * 2.0 - k.to_double() * LSH_LN2
}

fn lsh_sqrt(x : Double) -> Double {
  if x <= 0.0 {
    return 0.0
  }
  let mut r = x
  let mut i = 0
  while i < 64 {
    r = (r + x / r) / 2.0
    i = i + 1
  }
  r
}

fn lsh_cos(x : Double) -> Double {
  // Taylor series for cos(x), reduced to [-pi, pi].
  let pi = 3.14159265358979323846
  let two_pi = 2.0 * pi
  let mut val = x
  while val > pi {
    val = val - two_pi
  }
  while val < -pi {
    val = val + two_pi
  }
  let x2 = val * val
  let mut result = 1.0
  let mut term = 1.0
  let mut i = 1
  while i <= 20 {
    term = term * x2 / (2.0 * i.to_double() * (2.0 * i.to_double() - 1.0))
    let sign = if i % 2 == 0 { 1.0 } else { -1.0 }
    result = result + sign * term
    i = i + 1
  }
  result
}

/// Sample from a standard Gaussian distribution using the Box-Muller transform.
fn gaussian(rng : LCG) -> Double {
  let u1 = lcg_next_double(rng)
  let u2 = lcg_next_double(rng)
  let u1_safe = if u1 < 1.0e-10 { 1.0e-10 } else { u1 }
  lsh_sqrt(-2.0 * lsh_ln(u1_safe)) * lsh_cos(2.0 * 3.14159265358979323846 * u2)
}

// ---------------------------------------------------------------------------
// String join helper (MoonBit Array lacks join for String)
// ---------------------------------------------------------------------------

fn join_strings(parts : Array[String], sep : String) -> String {
  let mut buf = ""
  for i = 0; i < parts.length(); i = i + 1 {
    if i > 0 {
      buf = buf + sep + parts[i]
    } else {
      buf = parts[i]
    }
  }
  buf
}

// ---------------------------------------------------------------------------
// Bucket lookup helper
// ---------------------------------------------------------------------------

fn bucket_get(table : LSHTable, key : String) -> Array[Int]? {
  for i = 0; i < table.buckets.length(); i = i + 1 {
    if table.buckets[i].key == key {
      return Some(table.buckets[i].indices)
    }
  }
  None
}

fn bucket_get_or_create(table : LSHTable, key : String) -> Array[Int] {
  match bucket_get(table, key) {
    Some(bucket) => bucket
    None => {
      let bucket : Array[Int] = []
      table.buckets.push({ key, indices: bucket })
      bucket
    }
  }
}

// ---------------------------------------------------------------------------
// Core operations
// ---------------------------------------------------------------------------

/// Build an LSH index from a set of points.
///
/// # Parameters
/// - `points`: array of points, each an array of `Double` coordinates.
/// - `w`: bucket width. Larger values give more collisions.
/// - `k`: number of hash functions per table.
/// - `l`: number of hash tables.
/// - `seed`: random seed for reproducibility.
pub fn build(
  points : Array[Array[Double]],
  w : Double,
  k : Int,
  l : Int,
  seed : Int,
) -> LSHIndex {
  let n = points.length()
  let d = if n > 0 { points[0].length() } else { 0 }
  let tables : Array[LSHTable] = []
  let rng = lcg_new(seed)
  for ti = 0; ti < l; ti = ti + 1 {
    let projections : Array[Array[Double]] = []
    let offsets : Array[Double] = []
    for ki = 0; ki < k; ki = ki + 1 {
      let proj : Array[Double] = []
      for di = 0; di < d; di = di + 1 {
        proj.push(gaussian(rng))
      }
      projections.push(proj)
      offsets.push(lcg_next_double(rng) * w)
    }
    let table : LSHTable = {
      projections,
      offsets,
      w,
      buckets: [],
    }
    // Insert all points into this table.
    for i = 0; i < n; i = i + 1 {
      let h = hash_point(table, points[i])
      let bucket = bucket_get_or_create(table, h)
      bucket.push(i)
    }
    tables.push(table)
  }
  { tables, k, l, w, d, points, seed }
}

/// Compute the composite hash of a point for a given table.
fn hash_point(table : LSHTable, point : Array[Double]) -> String {
  let parts : Array[String] = []
  for i = 0; i < table.projections.length(); i = i + 1 {
    let proj = table.projections[i]
    let mut dot = 0.0
    for j = 0; j < point.length() && j < proj.length(); j = j + 1 {
      dot = dot + point[j] * proj[j]
    }
    let h = lsh_floor((dot + table.offsets[i]) / table.w).to_int()
    parts.push(h.to_string())
  }
  join_strings(parts, "|")
}

/// Squared Euclidean distance between two points.
fn euclidean_sq(a : Array[Double], b : Array[Double]) -> Double {
  let mut sum = 0.0
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < n; i = i + 1 {
    let diff = a[i] - b[i]
    sum = sum + diff * diff
  }
  sum
}

/// Find the approximate nearest neighbour of a query point.
///
/// Searches all buckets that the query hashes to and returns the closest
/// point found. Returns -1 if no candidates are found.
pub fn nearest_neighbor(index : LSHIndex, query : Array[Double]) -> Int {
  let mut best_idx = -1
  let mut best_dist = 1.0e18
  let seen = FixedArray::make(index.points.length(), false)
  for t = 0; t < index.l; t = t + 1 {
    let table = index.tables[t]
    let h = hash_point(table, query)
    match bucket_get(table, h) {
      Some(bucket) =>
        for bi = 0; bi < bucket.length(); bi = bi + 1 {
          let idx = bucket[bi]
          if !seen[idx] {
            seen[idx] = true
            let d = euclidean_sq(query, index.points[idx])
            if d < best_dist {
              best_dist = d
              best_idx = idx
            }
          }
        }
      None => ()
    }
  }
  best_idx
}

/// Find all approximate neighbours within `radius` of the query.
pub fn range_search(
  index : LSHIndex,
  query : Array[Double],
  radius : Double,
) -> Array[Int] {
  let result : Array[Int] = []
  let seen = FixedArray::make(index.points.length(), false)
  let radius_sq = radius * radius
  for t = 0; t < index.l; t = t + 1 {
    let table = index.tables[t]
    let h = hash_point(table, query)
    match bucket_get(table, h) {
      Some(bucket) =>
        for bi = 0; bi < bucket.length(); bi = bi + 1 {
          let idx = bucket[bi]
          if !seen[idx] {
            seen[idx] = true
            let d = euclidean_sq(query, index.points[idx])
            if d <= radius_sq {
              result.push(idx)
            }
          }
        }
      None => ()
    }
  }
  result
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "lsh: basic nearest neighbor" {
  let points : Array[Array[Double]] = [
    [0.0, 0.0], [1.0, 1.0], [10.0, 10.0], [11.0, 11.0],
  ]
  let index = build(points, 4.0, 3, 10, 42)
  let nn = nearest_neighbor(index, [0.5, 0.5])
  assert_true(nn == 0 || nn == 1)
}

test "lsh: empty index" {
  let points : Array[Array[Double]] = []
  let index = build(points, 4.0, 3, 5, 42)
  let nn = nearest_neighbor(index, [0.0, 0.0])
  assert_eq(nn, -1)
}

test "lsh: exact match query" {
  let points : Array[Array[Double]] = [
    [1.0, 2.0], [3.0, 4.0], [5.0, 6.0],
  ]
  let index = build(points, 4.0, 2, 10, 42)
  let nn = nearest_neighbor(index, [3.0, 4.0])
  assert_eq(nn, 1)
}

test "lsh: well-separated clusters" {
  let points : Array[Array[Double]] = [
    [0.0, 0.0], [1.0, 0.0], [0.0, 1.0],
    [100.0, 100.0], [101.0, 100.0], [100.0, 101.0],
  ]
  let index = build(points, 4.0, 3, 20, 42)
  let nn = nearest_neighbor(index, [0.5, 0.5])
  assert_true(nn >= 0 && nn < 3)
  let nn2 = nearest_neighbor(index, [100.5, 100.5])
  assert_true(nn2 >= 3 && nn2 < 6)
}

test "lsh: range search" {
  let points : Array[Array[Double]] = [
    [0.0, 0.0], [1.0, 0.0], [2.0, 0.0],
    [100.0, 100.0],
  ]
  let index = build(points, 4.0, 2, 20, 42)
  let result = range_search(index, [1.0, 0.0], 3.0)
  assert_true(result.length() >= 1)
}

test "lsh: high dimensional" {
  let points : Array[Array[Double]] = []
  for i = 0; i < 20; i = i + 1 {
    let p : Array[Double] = []
    for j = 0; j < 10; j = j + 1 {
      p.push((i * 10 + j).to_double())
    }
    points.push(p)
  }
  let index = build(points, 50.0, 5, 10, 42)
  let nn = nearest_neighbor(index, points[5])
  assert_true(nn >= 0)
}
