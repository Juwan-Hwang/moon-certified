/// Inverted File Index (IVF) for Approximate Nearest Neighbor Search
///
/// Implements the IVF indexing structure from:
/// Jegou, Douze & Schmid (2011), "Product Quantization for Nearest
/// Neighbor Search," IEEE TPAMI 34(1), 117-128.
///
/// ## Overview
///
/// IVF partitions the vector space into `nlist` Voronoi cells using
/// k-means. At search time, only the `nprobe` nearest cells to the
/// query are scanned, yielding O(n * nprobe / nlist) average complexity
/// instead of O(n) for brute force.

// ===========================================================================
// Core data structures
// ===========================================================================

///|
/// An IVF index.
pub struct IVFIndex {
  dim : Int
  nlist : Int
  centroids : Array[Double]
  inverted_lists : Array[Array[Int]]
  vector_data : Array[Double]
  n_vectors : Int
}

///|
/// Search result from IVF query.
pub struct IVFSearchResult {
  index : Int
  distance : Double
}

// ===========================================================================
// K-means for cell centroid training
// ===========================================================================

///|
fn ivf_kmeans(
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
  let centroids = ivf_kmeans_pp_init(data, n, d, k, seed)
  let assignments = Array::make(n, 0)
  let sum = Array::make(k * d, 0.0)
  let counts = Array::make(k, 0)
  for _iter = 0; _iter < max_iters; _iter = _iter + 1 {
    let mut changed = false
    for i = 0; i < n; i = i + 1 {
      let best_c = ivf_nearest_centroid(data, i, d, k, centroids)
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
fn ivf_kmeans_pp_init(
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
fn ivf_nearest_centroid(
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

///|
fn ivf_sq_dist_l2(
  a : Array[Double],
  a_offset : Int,
  b : Array[Double],
  b_offset : Int,
  d : Int,
) -> Double {
  let mut dist = 0.0
  for j = 0; j < d; j = j + 1 {
    let diff = a[a_offset + j] - b[b_offset + j]
    dist = dist + diff * diff
  }
  dist
}

// ===========================================================================
// IVF build and search
// ===========================================================================

///|
/// Build an IVF index from a set of vectors.
pub fn ivf_build(
  data : Array[Double],
  n : Int,
  dim : Int,
  nlist : Int,
  max_iters : Int,
  seed : Int,
) -> IVFIndex {
  if n == 0 || dim == 0 || nlist <= 0 {
    return {
      dim,
      nlist: 0,
      centroids: [],
      inverted_lists: [],
      vector_data: data,
      n_vectors: n,
    }
  }
  let k = if nlist > n { n } else { nlist }
  let centroids = ivf_kmeans(data, n, dim, k, max_iters, seed)
  // Create distinct empty arrays (avoid Array::make aliasing bug)
  let inverted_lists : Array[Array[Int]] = []
  for c = 0; c < k; c = c + 1 {
    inverted_lists.push([])
  }
  for i = 0; i < n; i = i + 1 {
    let c = ivf_nearest_centroid(data, i, dim, k, centroids)
    inverted_lists[c].push(i)
  }
  { dim, nlist: k, centroids, inverted_lists, vector_data: data, n_vectors: n, }
}

///|
/// Find the nprobe nearest cells to the query vector.
fn ivf_find_nearest_cells(
  index : IVFIndex,
  query : Array[Double],
  nprobe : Int,
) -> Array[Int] {
  let k = index.nlist
  let d = index.dim
  let cell_dists = Array::make(k, 0.0)
  for c = 0; c < k; c = c + 1 {
    cell_dists[c] = ivf_sq_dist_l2(query, 0, index.centroids, c * d, d)
  }
  let np = if nprobe < k { nprobe } else { k }
  let cell_indices = Array::make(k, 0)
  for i = 0; i < k; i = i + 1 {
    cell_indices[i] = i
  }
  for i = 0; i < np; i = i + 1 {
    let mut min_idx = i
    let mut min_dist = cell_dists[cell_indices[i]]
    for j = i + 1; j < k; j = j + 1 {
      if cell_dists[cell_indices[j]] < min_dist {
        min_dist = cell_dists[cell_indices[j]]
        min_idx = j
      }
    }
    let tmp = cell_indices[i]
    cell_indices[i] = cell_indices[min_idx]
    cell_indices[min_idx] = tmp
  }
  let result = Array::make(np, 0)
  for i = 0; i < np; i = i + 1 {
    result[i] = cell_indices[i]
  }
  result
}

///|
/// Search for the k nearest neighbors of a query vector.
pub fn ivf_search(
  index : IVFIndex,
  query : Array[Double],
  k : Int,
  nprobe : Int,
) -> Array[IVFSearchResult] {
  if index.n_vectors == 0 || k <= 0 {
    return []
  }
  let d = index.dim
  let cells = ivf_find_nearest_cells(index, query, nprobe)
  let candidates : Array[Int] = []
  for ci = 0; ci < cells.length(); ci = ci + 1 {
    let cell = cells[ci]
    let lst = index.inverted_lists[cell]
    for vi = 0; vi < lst.length(); vi = vi + 1 {
      candidates.push(lst[vi])
    }
  }
  if candidates.length() == 0 {
    return []
  }
  let dists : Array[Double] = []
  for i = 0; i < candidates.length(); i = i + 1 {
    let vidx = candidates[i]
    let dist = ivf_sq_dist_l2(query, 0, index.vector_data, vidx * d, d)
    dists.push(dist)
  }
  let kk = if k < candidates.length() { k } else { candidates.length() }
  let cand_indices = Array::make(candidates.length(), 0)
  for i = 0; i < candidates.length(); i = i + 1 {
    cand_indices[i] = i
  }
  for i = 0; i < kk; i = i + 1 {
    let mut min_idx = i
    let mut min_dist = dists[cand_indices[i]]
    for j = i + 1; j < candidates.length(); j = j + 1 {
      if dists[cand_indices[j]] < min_dist {
        min_dist = dists[cand_indices[j]]
        min_idx = j
      }
    }
    let tmp = cand_indices[i]
    cand_indices[i] = cand_indices[min_idx]
    cand_indices[min_idx] = tmp
  }
  let result = Array::make(kk, { index: 0, distance: 0.0, })
  for i = 0; i < kk; i = i + 1 {
    result[i] = {
      index: candidates[cand_indices[i]],
      distance: dists[cand_indices[i]],
    }
  }
  result
}

///|
/// Get the number of vectors in the index.
pub fn ivf_n_vectors(index : IVFIndex) -> Int {
  index.n_vectors
}

///|
/// Get the dimension of vectors in the index.
pub fn ivf_dim(index : IVFIndex) -> Int {
  index.dim
}

///|
/// Get the number of Voronoi cells (lists).
pub fn ivf_nlist(index : IVFIndex) -> Int {
  index.nlist
}

///|
/// Get the number of vectors assigned to a specific cell.
pub fn ivf_cell_size(index : IVFIndex, cell_id : Int) -> Int {
  if cell_id < 0 || cell_id >= index.nlist {
    return 0
  }
  index.inverted_lists[cell_id].length()
}

///|
/// Compute the recall of IVF search against brute-force search.
pub fn ivf_recall(
  true_neighbors : Array[Int],
  ivf_results : Array[IVFSearchResult],
) -> Double {
  let n_true = true_neighbors.length()
  if n_true == 0 {
    return 1.0
  }
  let mut found = 0
  for i = 0; i < ivf_results.length(); i = i + 1 {
    for j = 0; j < n_true; j = j + 1 {
      if ivf_results[i].index == true_neighbors[j] {
        found = found + 1
        break
      }
    }
  }
  found.to_double() / n_true.to_double()
}
