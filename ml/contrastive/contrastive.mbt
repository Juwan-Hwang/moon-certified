/// Contrastive Learning — Loss Functions for Metric Learning
///
/// Implements common contrastive loss functions used in self-supervised
/// and metric learning:
/// - InfoNCE (used in CLIP, SimCLR)
/// - Triplet loss (used in FaceNet)
/// - NT-Xent loss (normalized temperature-scaled cross-entropy)
/// - SupCon (Supervised Contrastive Loss)
///
/// ## References
/// - Chen et al. "SimCLR: A Simple Framework for Contrastive Learning." ICML 2020.
/// - Radford et al. "CLIP." ICML 2021.
/// - Khosla et al. "Supervised Contrastive Learning." NeurIPS 2020.
/// - Schroff et al. "FaceNet." CVPR 2015.
///
/// `proof-enabled` is `false`.

///|
/// Cosine similarity between two vectors.
pub fn cosine_similarity(a : Array[Double], b : Array[Double]) -> Double {
  let mut dot = 0.0
  let mut norm_a = 0.0
  let mut norm_b = 0.0
  for i = 0; i < a.length() && i < b.length(); i = i + 1 {
    dot = dot + a[i] * b[i]
    norm_a = norm_a + a[i] * a[i]
    norm_b = norm_b + b[i] * b[i]
  }
  let denom = norm_a.sqrt() * norm_b.sqrt()
  if denom == 0.0 {
    0.0
  } else {
    dot / denom
  }
}

///|
/// L2 squared distance.
pub fn l2_squared(a : Array[Double], b : Array[Double]) -> Double {
  let mut sum = 0.0
  for i = 0; i < a.length() && i < b.length(); i = i + 1 {
    let d = a[i] - b[i]
    sum = sum + d * d
  }
  sum
}

///|
/// InfoNCE loss for contrastive learning.
///
/// Given a query and a set of candidates (with 1 positive and n negatives),
/// computes: -log(exp(sim(q, pos)/τ) / Σ exp(sim(q, i)/τ))
///
/// ## Parameters
/// - `query`: query embedding
/// - `positive`: positive sample embedding
/// - `negatives`: list of negative sample embeddings
/// - `temperature`: scaling factor τ
pub fn info_nce_loss(
  query : Array[Double],
  positive : Array[Double],
  negatives : Array[Array[Double]],
  temperature : Double,
) -> Double {
  let pos_sim = cosine_similarity(query, positive) / temperature
  let all_sims : Array[Double] = []
  all_sims.push(pos_sim)
  for neg in negatives {
    all_sims.push(cosine_similarity(query, neg) / temperature)
  }
  // Softmax: compute exp and normalize
  let mut max_sim = all_sims[0]
  for s in all_sims {
    if s > max_sim {
      max_sim = s
    }
  }
  let mut sum_exp = 0.0
  let exp_sims : Array[Double] = []
  for s in all_sims {
    let e = @math.exp(s - max_sim)
    exp_sims.push(e)
    sum_exp = sum_exp + e
  }
  // Loss = -log(softmax(pos))
  if exp_sims[0] > 0.0 && sum_exp > 0.0 {
    -@math.ln(exp_sims[0] / sum_exp)
  } else {
    0.0
  }
}

///|
/// NT-Xent loss (SimCLR style).
///
/// For a batch of N pairs (2N samples), compute the contrastive loss
/// where each sample's positive is its paired augmentation.
///
/// ## Parameters
/// - `embeddings`: 2N embeddings (N pairs)
/// - `pair_indices`: array of (i, j) pairs of positive indices
/// - `temperature`: temperature τ
pub fn nt_xent_loss(
  embeddings : Array[Array[Double]],
  pair_indices : Array[(Int, Int)],
  temperature : Double,
) -> Double {
  let n = embeddings.length()
  let mut total_loss = 0.0
  for pair in pair_indices {
    let i = pair.0
    let j = pair.1
    // sim(i, j) / τ
    let pos_sim = cosine_similarity(embeddings[i], embeddings[j]) / temperature
    // Compute denominator: sum over all k != i
    let mut max_val = pos_sim
    let neg_sims : Array[Double] = []
    neg_sims.push(pos_sim)
    for k = 0; k < n; k = k + 1 {
      if k != i && k != j {
        let s = cosine_similarity(embeddings[i], embeddings[k]) / temperature
        neg_sims.push(s)
        if s > max_val {
          max_val = s
        }
      }
    }
    let mut sum_exp = 0.0
    let exp_vals : Array[Double] = []
    for s in neg_sims {
      let e = @math.exp(s - max_val)
      exp_vals.push(e)
      sum_exp = sum_exp + e
    }
    if exp_vals[0] > 0.0 && sum_exp > 0.0 {
      total_loss = total_loss + -@math.ln(exp_vals[0] / sum_exp)
    }
  }
  total_loss / pair_indices.length().to_double()
}

///|
/// Triplet loss (FaceNet style).
///
/// Loss = max(0, d(a, p) - d(a, n) + margin)
/// where d is squared Euclidean distance.
///
/// ## Parameters
/// - `anchor`: anchor embedding
/// - `positive`: positive embedding (same class)
/// - `negative`: negative embedding (different class)
/// - `margin`: margin hyperparameter
pub fn triplet_loss(
  anchor : Array[Double],
  positive : Array[Double],
  negative : Array[Double],
  margin : Double,
) -> Double {
  let d_pos = l2_squared(anchor, positive)
  let d_neg = l2_squared(anchor, negative)
  let loss = d_pos - d_neg + margin
  if loss > 0.0 {
    loss
  } else {
    0.0
  }
}

///|
/// SupCon (Supervised Contrastive Loss).
///
/// For a batch with labels, pull together same-class samples and push
/// apart different-class samples.
///
/// ## Parameters
/// - `embeddings`: batch of embeddings
/// - `labels`: class labels for each embedding
/// - `temperature`: temperature τ
pub fn supcon_loss(
  embeddings : Array[Array[Double]],
  labels : Array[Int],
  temperature : Double,
) -> Double {
  let n = embeddings.length()
  let mut total_loss = 0.0
  let mut num_valid = 0
  for i = 0; i < n; i = i + 1 {
    // Find positives (same class) and negatives (different class)
    let pos_sims : Array[Double] = []
    let all_sims : Array[Double] = []
    for j = 0; j < n; j = j + 1 {
      if i != j {
        let sim = cosine_similarity(embeddings[i], embeddings[j]) / temperature
        all_sims.push(sim)
        if labels[j] == labels[i] {
          pos_sims.push(sim)
        }
      }
    }
    if pos_sims.length() == 0 {
      continue
    }
    num_valid = num_valid + 1
    // Compute max for numerical stability
    let mut max_val = all_sims[0]
    for s in all_sims {
      if s > max_val {
        max_val = s
      }
    }
    // Compute log-sum-exp for all
    let mut sum_exp_all = 0.0
    for s in all_sims {
      sum_exp_all = sum_exp_all + @math.exp(s - max_val)
    }
    // Compute sum of exp for positives
    let mut sum_exp_pos = 0.0
    for s in pos_sims {
      sum_exp_pos = sum_exp_pos + @math.exp(s - max_val)
    }
    // Loss for this sample = -(1/|P|) * Σ_pos log(exp(pos) / Σ_all exp)
    if sum_exp_all > 0.0 && sum_exp_pos > 0.0 {
      let log_prob = @math.ln(sum_exp_pos / sum_exp_all)
      total_loss = total_loss + -log_prob / pos_sims.length().to_double()
    }
  }
  if num_valid == 0 {
    0.0
  } else {
    total_loss / num_valid.to_double()
  }
}

///|
/// Contrastive loss (pairwise, simple version).
///
/// For a pair of samples: loss = y * d² + (1-y) * max(0, margin - d)²
/// where y = 1 for same class, d = distance.
pub fn contrastive_loss(
  a : Array[Double],
  b : Array[Double],
  same_class : Bool,
  margin : Double,
) -> Double {
  let d = l2_squared(a, b).sqrt() // Euclidean distance
  if same_class {
    d * d
  } else {
    let m = margin - d
    if m > 0.0 {
      m * m
    } else {
      0.0
    }
  }
}
