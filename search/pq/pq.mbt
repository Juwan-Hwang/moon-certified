/// Product Quantization (PQ) for Approximate Nearest Neighbor Search
///
/// Implements PQ from Jegou, Douze & Schmid (2011):
/// "Product Quantization for Nearest Neighbor Search." IEEE TPAMI 34(1).

// ===========================================================================
// Core data structures
// ===========================================================================

///|
/// A trained Product Quantization model.
pub struct PQModel {
  sub_dim : Int
  n_subquantizers : Int
  n_centroids : Int
  centroids : Array[Double]
}

///|
/// A PQ-encoded vector: one code per sub-quantizer.
pub struct PQCode {
  codes : Array[Int]
}

///|
/// Construct a PQCode from raw code values.
pub fn pq_code(codes : Array[Int]) -> PQCode {
  { codes, }
}

// ===========================================================================
// K-means (Lloyd algorithm) for sub-quantizer training
// ===========================================================================

///|
fn kmeans(
  data : Array[Double],
  n : Int,
  d : Int,
  k : Int,
  max_iters : Int,
  seed : Int,
) -> Array[Double] {
  if n == 0 || d == 0 || k == 0 {
    return Array::make(k * d, 0.0)
  }
  if k >= n {
    let result = Array::make(k * d, 0.0)
    for i = 0; i < k; i = i + 1 {
      let src = if i < n { i } else { i % n }
      for j = 0; j < d; j = j + 1 {
        result[i * d + j] = data[src * d + j]
      }
    }
    return result
  }
  let centroids = kmeans_pp_init(data, n, d, k, seed)
  let assignments = Array::make(n, 0)
  let sum = Array::make(k * d, 0.0)
  let counts = Array::make(k, 0)
  for _iter = 0; _iter < max_iters; _iter = _iter + 1 {
    let mut changed = false
    for i = 0; i < n; i = i + 1 {
      let best_c = nearest_centroid(data, i, d, k, centroids)
      if assignments[i] != best_c {
        changed = true
        assignments[i] = best_c
      }
    }
    if !changed && _iter > 0 {
      break
    }
    for j = 0; j < k * d; j = j + 1 {
      sum[j] = 0.0
    }
    for j = 0; j < k; j = j + 1 {
      counts[j] = 0
    }
    for i = 0; i < n; i = i + 1 {
      let c = assignments[i]
      counts[c] = counts[c] + 1
      for j = 0; j < d; j = j + 1 {
        sum[c * d + j] = sum[c * d + j] + data[i * d + j]
      }
    }
    for c = 0; c < k; c = c + 1 {
      if counts[c] > 0 {
        for j = 0; j < d; j = j + 1 {
          centroids[c * d + j] = sum[c * d + j] / counts[c].to_double()
        }
      }
    }
  }
  centroids
}

///|
fn kmeans_pp_init(
  data : Array[Double],
  n : Int,
  d : Int,
  k : Int,
  seed : Int,
) -> Array[Double] {
  let centroids = Array::make(k * d, 0.0)
  let mut state = seed
  fn next_rand() -> Double {
    state = (state * 1103515245 + 12345) & 0x7FFFFFFF
    state.to_double() / 2147483647.0
  }
  let first = (next_rand() * n.to_double()).to_int()
  let idx = if first >= n { n - 1 } else { first }
  for j = 0; j < d; j = j + 1 {
    centroids[j] = data[idx * d + j]
  }
  let dist = Array::make(n, 1.0e30)
  for c = 1; c < k; c = c + 1 {
    let prev = c - 1
    for i = 0; i < n; i = i + 1 {
      let mut dd = 0.0
      for j = 0; j < d; j = j + 1 {
        let diff = data[i * d + j] - centroids[prev * d + j]
        dd = dd + diff * diff
      }
      if dd < dist[i] {
        dist[i] = dd
      }
    }
    let mut total = 0.0
    for i = 0; i < n; i = i + 1 {
      total = total + dist[i]
    }
    let r = next_rand() * total
    let mut acc = 0.0
    let mut chosen = 0
    for i = 0; i < n; i = i + 1 {
      acc = acc + dist[i]
      if acc >= r {
        chosen = i
        break
      }
      chosen = i
    }
    for j = 0; j < d; j = j + 1 {
      centroids[c * d + j] = data[chosen * d + j]
    }
  }
  centroids
}

///|
fn nearest_centroid(
  data : Array[Double],
  point_idx : Int,
  d : Int,
  k : Int,
  centroids : Array[Double],
) -> Int {
  let mut best = 0
  let mut best_dist = 1.0e30
  for c = 0; c < k; c = c + 1 {
    let mut dd = 0.0
    for j = 0; j < d; j = j + 1 {
      let diff = data[point_idx * d + j] - centroids[c * d + j]
      dd = dd + diff * diff
    }
    if dd < best_dist {
      best_dist = dd
      best = c
    }
  }
  best
}

// ===========================================================================
// PQ training and encoding
// ===========================================================================

///|
/// Train a Product Quantization model from training vectors.
pub fn pq_train(
  data : Array[Double],
  n : Int,
  dim : Int,
  n_subquantizers : Int,
  n_centroids : Int,
  max_iters : Int,
  seed : Int,
) -> PQModel {
  if n_subquantizers <= 0 || dim % n_subquantizers != 0 {
    return { sub_dim: 0, n_subquantizers: 0, n_centroids: 0, centroids: [], }
  }
  let sub_dim = dim / n_subquantizers
  let total_centroids = n_subquantizers * n_centroids * sub_dim
  let centroids = Array::make(total_centroids, 0.0)
  let sub_data = Array::make(n * sub_dim, 0.0)
  for sq = 0; sq < n_subquantizers; sq = sq + 1 {
    let offset = sq * sub_dim
    for i = 0; i < n; i = i + 1 {
      for j = 0; j < sub_dim; j = j + 1 {
        sub_data[i * sub_dim + j] = data[i * dim + offset + j]
      }
    }
    let sub_centroids = kmeans(
      sub_data,
      n,
      sub_dim,
      n_centroids,
      max_iters,
      seed + sq,
    )
    for idx = 0; idx < n_centroids * sub_dim; idx = idx + 1 {
      centroids[sq * n_centroids * sub_dim + idx] = sub_centroids[idx]
    }
  }
  { sub_dim, n_subquantizers, n_centroids, centroids, }
}

///|
/// Encode a single vector into a PQ code.
pub fn pq_encode(model : PQModel, vector : Array[Double]) -> PQCode {
  let codes = Array::make(model.n_subquantizers, 0)
  for sq = 0; sq < model.n_subquantizers; sq = sq + 1 {
    let offset = sq * model.sub_dim
    let mut best = 0
    let mut best_dist = 1.0e30
    for c = 0; c < model.n_centroids; c = c + 1 {
      let mut dd = 0.0
      for j = 0; j < model.sub_dim; j = j + 1 {
        let diff = vector[offset + j] -
          model.centroids[sq * model.n_centroids * model.sub_dim +
          c * model.sub_dim +
          j]
        dd = dd + diff * diff
      }
      if dd < best_dist {
        best_dist = dd
        best = c
      }
    }
    codes[sq] = best
  }
  { codes, }
}

///|
/// Encode a batch of vectors into PQ codes.
pub fn pq_encode_batch(
  model : PQModel,
  data : Array[Double],
  n : Int,
) -> Array[PQCode] {
  let result = Array::make(n, { codes: [], })
  let dim = model.sub_dim * model.n_subquantizers
  for i = 0; i < n; i = i + 1 {
    let vec = Array::make(dim, 0.0)
    for j = 0; j < dim; j = j + 1 {
      vec[j] = data[i * dim + j]
    }
    result[i] = pq_encode(model, vec)
  }
  result
}

///|
/// Reconstruct (decode) a PQ code back to an approximate vector.
pub fn pq_decode(model : PQModel, code : PQCode) -> Array[Double] {
  let dim = model.sub_dim * model.n_subquantizers
  let result = Array::make(dim, 0.0)
  for sq = 0; sq < model.n_subquantizers; sq = sq + 1 {
    let c = if sq < code.codes.length() { code.codes[sq] } else { 0 }
    let centroid_idx = sq * model.n_centroids * model.sub_dim +
      c * model.sub_dim
    for j = 0; j < model.sub_dim; j = j + 1 {
      result[sq * model.sub_dim + j] = model.centroids[centroid_idx + j]
    }
  }
  result
}

// ===========================================================================
// Distance computation
// ===========================================================================

///|
/// Asymmetric Distance Computation (ADC): distance from query to PQ code.
pub fn pq_adc_distance(
  model : PQModel,
  query : Array[Double],
  code : PQCode,
) -> Double {
  let m = model.n_subquantizers
  let k = model.n_centroids
  let d = model.sub_dim
  let table = Array::make(m * k, 0.0)
  for sq = 0; sq < m; sq = sq + 1 {
    let offset = sq * d
    for c = 0; c < k; c = c + 1 {
      let mut dist = 0.0
      for j = 0; j < d; j = j + 1 {
        let diff = query[offset + j] - model.centroids[sq * k * d + c * d + j]
        dist = dist + diff * diff
      }
      table[sq * k + c] = dist
    }
  }
  let mut total = 0.0
  for sq = 0; sq < m; sq = sq + 1 {
    let c = if sq < code.codes.length() { code.codes[sq] } else { 0 }
    total = total + table[sq * k + c]
  }
  total
}

///|
/// Symmetric Distance Computation (SDC): distance between two PQ codes.
pub fn pq_sdc_distance(
  model : PQModel,
  code_a : PQCode,
  code_b : PQCode,
) -> Double {
  let m = model.n_subquantizers
  let k = model.n_centroids
  let d = model.sub_dim
  let mut total = 0.0
  for sq = 0; sq < m; sq = sq + 1 {
    let ca = if sq < code_a.codes.length() { code_a.codes[sq] } else { 0 }
    let cb = if sq < code_b.codes.length() { code_b.codes[sq] } else { 0 }
    let offset = sq * k * d
    for j = 0; j < d; j = j + 1 {
      let diff = model.centroids[offset + ca * d + j] -
        model.centroids[offset + cb * d + j]
      total = total + diff * diff
    }
  }
  total
}

///|
/// Build the ADC lookup table for a query vector.
pub fn pq_adc_table(model : PQModel, query : Array[Double]) -> Array[Double] {
  let m = model.n_subquantizers
  let k = model.n_centroids
  let d = model.sub_dim
  let table = Array::make(m * k, 0.0)
  for sq = 0; sq < m; sq = sq + 1 {
    let offset = sq * d
    for c = 0; c < k; c = c + 1 {
      let mut dist = 0.0
      for j = 0; j < d; j = j + 1 {
        let diff = query[offset + j] - model.centroids[sq * k * d + c * d + j]
        dist = dist + diff * diff
      }
      table[sq * k + c] = dist
    }
  }
  table
}

///|
/// Compute ADC distance using a pre-built lookup table.
pub fn pq_adc_distance_table(
  model : PQModel,
  table : Array[Double],
  code : PQCode,
) -> Double {
  let m = model.n_subquantizers
  let k = model.n_centroids
  let mut total = 0.0
  for sq = 0; sq < m; sq = sq + 1 {
    let c = if sq < code.codes.length() { code.codes[sq] } else { 0 }
    total = total + table[sq * k + c]
  }
  total
}

// ===========================================================================
// Approximate nearest neighbor search
// ===========================================================================

///|
/// Result of a nearest neighbor search.
pub struct PQSearchResult {
  index : Int
  distance : Double
}

///|
/// Search for the k nearest neighbors using ADC.
pub fn pq_search(
  model : PQModel,
  query : Array[Double],
  codes : Array[PQCode],
  k : Int,
) -> Array[PQSearchResult] {
  let n = codes.length()
  if n == 0 || k <= 0 {
    return []
  }
  let table = pq_adc_table(model, query)
  let distances = Array::make(n, 0.0)
  for i = 0; i < n; i = i + 1 {
    distances[i] = pq_adc_distance_table(model, table, codes[i])
  }
  let kk = if k < n { k } else { n }
  let indices = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    indices[i] = i
  }
  for i = 0; i < kk; i = i + 1 {
    let mut min_idx = i
    let mut min_dist = distances[indices[i]]
    for j = i + 1; j < n; j = j + 1 {
      if distances[indices[j]] < min_dist {
        min_dist = distances[indices[j]]
        min_idx = j
      }
    }
    let tmp = indices[i]
    indices[i] = indices[min_idx]
    indices[min_idx] = tmp
  }
  let result = Array::make(kk, { index: 0, distance: 0.0, })
  for i = 0; i < kk; i = i + 1 {
    result[i] = { index: indices[i], distance: distances[indices[i]], }
  }
  result
}

///|
/// Compute mean reconstruction error (quantization distortion).
pub fn pq_reconstruction_error(
  model : PQModel,
  data : Array[Double],
  n : Int,
) -> Double {
  if n == 0 {
    return 0.0
  }
  let dim = model.sub_dim * model.n_subquantizers
  let mut total_error = 0.0
  for i = 0; i < n; i = i + 1 {
    let vec = Array::make(dim, 0.0)
    for j = 0; j < dim; j = j + 1 {
      vec[j] = data[i * dim + j]
    }
    let code = pq_encode(model, vec)
    let recon = pq_decode(model, code)
    let mut err = 0.0
    for j = 0; j < dim; j = j + 1 {
      let diff = vec[j] - recon[j]
      err = err + diff * diff
    }
    total_error = total_error + err
  }
  total_error / n.to_double()
}

///|
/// Get the dimension of vectors this model expects.
pub fn pq_vector_dim(model : PQModel) -> Int {
  model.sub_dim * model.n_subquantizers
}

///|
/// Get the number of sub-quantizers.
pub fn pq_num_subquantizers(model : PQModel) -> Int {
  model.n_subquantizers
}

///|
/// Get the number of centroids per sub-quantizer.
pub fn pq_num_centroids(model : PQModel) -> Int {
  model.n_centroids
}
