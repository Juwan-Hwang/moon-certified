// PageRank — the link-analysis algorithm made famous by Google.
//
// A random surfer at page `i` follows one of its out-links uniformly at
// random with probability `damping`; otherwise the surfer teleports to a
// uniformly random page. Pages with no out-links ("dangling" pages) are
// treated as linking to *every* page, so their rank mass is redistributed
// uniformly — this keeps the total probability mass conserved and makes
// the underlying Markov chain ergodic, guaranteeing a unique stationary
// distribution that power iteration converges to.
//
// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// PageRank
// ---------------------------------------------------------------------------

///|
/// Compute PageRank scores for a directed graph via power iteration.
///
/// # Parameters
/// - `n` — number of nodes, indexed `0 .. n - 1`.
/// - `edges` — directed edges as `(from, to)` pairs. Edges whose endpoints
///   fall outside `[0, n)` are silently ignored. Duplicate and self-loop
///   edges are handled naturally (each contributes its share of rank).
/// - `damping` — probability that the surfer follows a link rather than
///   teleporting (typically `0.85`).
/// - `max_iter` — maximum number of power-iteration steps.
/// - `tolerance` — convergence threshold: iteration stops as soon as the
///   L1 norm of the rank-change vector drops below this value
///   (typically `1e-6`).
///
/// # Returns
/// An `Array[Double]` of length `n` holding the PageRank of each node.
/// The scores are non-negative and sum to `1.0` (up to floating-point
/// error, corrected by a final renormalisation). For `n <= 0` an empty
/// array is returned.
///
/// # Algorithm
/// Initialise every rank to `1 / n`, then repeat:
///
/// ```text
/// base     = (1 - damping) / n  +  damping * dangling_sum / n
/// new[i]   = base  +  damping * Σ_{j → i} rank[j] / out_degree[j]
/// ```
///
/// where `dangling_sum` is the total rank held by nodes with no out-links.
/// Iteration halts when `Σ |new[i] - rank[i]| < tolerance` or after
/// `max_iter` steps, whichever comes first.
///
/// # Complexity
/// - Time:  `O(max_iter * (n + m))`  where `m = edges.length()`.
/// - Space: `O(n + m)`  for the reverse adjacency list and rank vectors.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.
pub fn pagerank(
  n : Int,
  edges : Array[(Int, Int)],
  damping : Double,
  max_iter : Int,
  tolerance : Double,
) -> Array[Double] {
  // No nodes → nothing to rank.
  if n <= 0 {
    return Array::make(0, 0.0)
  }
  let nd = n.to_double()
  // -----------------------------------------------------------------------
  // Build the out-degree table and the reverse adjacency list.
  //   out_degree[i]  — number of edges leaving node i.
  //   in_links[i]    — every node j such that edge (j, i) exists.
  // Each entry of in_links is an independent array; building them with push
  // (rather than Array::make(n, [])) avoids aliasing a single shared list.
  // -----------------------------------------------------------------------
  let out_degree = Array::make(n, 0)
  let in_links : Array[Array[Int]] = []
  for i = 0; i < n; i = i + 1 {
    in_links.push([])
  }
  let m = edges.length()
  for e = 0; e < m; e = e + 1 {
    let (src, dst) = edges[e]
    if src >= 0 && src < n && dst >= 0 && dst < n {
      out_degree[src] = out_degree[src] + 1
      in_links[dst].push(src)
    }
  }
  // -----------------------------------------------------------------------
  // Initialise ranks uniformly and allocate the next-iteration buffer.
  // -----------------------------------------------------------------------
  let rank = Array::make(n, 1.0 / nd)
  let new_rank = Array::make(n, 0.0)
  // -----------------------------------------------------------------------
  // Power iteration.
  // -----------------------------------------------------------------------
  let mut iter = 0
  while iter < max_iter {
    iter = iter + 1
    // Rank mass parked on dangling nodes (out-degree 0).
    let mut dangling = 0.0
    for i = 0; i < n; i = i + 1 {
      if out_degree[i] == 0 {
        dangling = dangling + rank[i]
      }
    }
    // Teleport contribution plus uniform dangling redistribution.
    let base = (1.0 - damping) / nd + damping * dangling / nd
    // Propagate rank along edges: new_rank[i] = base + damping * Σ rank[j]/deg(j).
    for i = 0; i < n; i = i + 1 {
      new_rank[i] = base
    }
    for i = 0; i < n; i = i + 1 {
      let sources = in_links[i]
      let klen = sources.length()
      let mut s = 0.0
      for k = 0; k < klen; k = k + 1 {
        let j = sources[k]
        // out_degree[j] >= 1 here: j was added to in_links only when an
        // edge leaving j was counted, so the division is always safe.
        s = s + rank[j] / out_degree[j].to_double()
      }
      new_rank[i] = new_rank[i] + damping * s
    }
    // L1 convergence test; copy new_rank back into rank as we go.
    let mut diff = 0.0
    for i = 0; i < n; i = i + 1 {
      diff = diff + (new_rank[i] - rank[i]).abs()
      rank[i] = new_rank[i]
    }
    if diff < tolerance {
      break
    }
  }
  // -----------------------------------------------------------------------
  // Final renormalisation to cancel floating-point drift. The iteration
  // preserves Σ rank = 1 in exact arithmetic, so this only nudges the
  // result back onto the probability simplex.
  // -----------------------------------------------------------------------
  let mut total = 0.0
  for i = 0; i < n; i = i + 1 {
    total = total + rank[i]
  }
  if total > 0.0 {
    let inv = 1.0 / total
    for i = 0; i < n; i = i + 1 {
      rank[i] = rank[i] * inv
    }
  }
  rank
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

///|
/// Compare two doubles for approximate equality.
///
/// Passes when the absolute difference is below `eps`, or when the relative
/// difference (against the combined magnitude) is below `eps`. This guards
/// against floating-point drift accumulated over many power-iteration steps.
fn approx_eq(a : Double, b : Double, eps : Double) -> Bool {
  let diff = (a - b).abs()
  diff < eps || diff < eps * (a.abs() + b.abs())
}

///|
/// Sum the elements of a double array.
fn sum_ranks(arr : Array[Double]) -> Double {
  let mut total = 0.0
  for i = 0; i < arr.length(); i = i + 1 {
    total = total + arr[i]
  }
  total
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "pagerank: single node" {
  let r = pagerank(1, [], 0.85, 100, 1.0e-6)
  assert_eq(r.length(), 1)
  assert_true(approx_eq(r[0], 1.0, 1.0e-9))
}

///|
test "pagerank: two-node cycle gives equal ranks" {
  // 0 <-> 1. Both pages link to each other → symmetric → equal rank.
  let r = pagerank(2, [(0, 1), (1, 0)], 0.85, 100, 1.0e-6)
  assert_eq(r.length(), 2)
  assert_true(approx_eq(r[0], 0.5, 1.0e-9))
  assert_true(approx_eq(r[1], 0.5, 1.0e-9))
  assert_true(approx_eq(sum_ranks(r), 1.0, 1.0e-9))
}

///|
test "pagerank: simple chain" {
  // 0 -> 1 -> 2 -> 3. Node 3 is dangling.
  // Rank accumulates toward the end of the chain.
  let r = pagerank(4, [(0, 1), (1, 2), (2, 3)], 0.85, 200, 1.0e-10)
  assert_eq(r.length(), 4)
  assert_true(approx_eq(sum_ranks(r), 1.0, 1.0e-6))
  // All ranks positive.
  for i = 0; i < 4; i = i + 1 {
    assert_true(r[i] > 0.0)
  }
  // Monotonically increasing along the chain.
  assert_true(r[0] < r[1])
  assert_true(r[1] < r[2])
  assert_true(r[2] < r[3])
}

///|
test "pagerank: star graph (hub with back-links)" {
  // Hub 0 links to every spoke; every spoke links back to the hub.
  // The hub should dominate the rank, and the four spokes should be equal.
  let edges = [(0, 1), (0, 2), (0, 3), (0, 4), (1, 0), (2, 0), (3, 0), (4, 0)]
  let r = pagerank(5, edges, 0.85, 200, 1.0e-10)
  assert_eq(r.length(), 5)
  assert_true(approx_eq(sum_ranks(r), 1.0, 1.0e-6))
  // Hub has the highest rank.
  for i = 1; i < 5; i = i + 1 {
    assert_true(r[0] > r[i])
  }
  // Spokes are symmetric → equal ranks.
  for i = 1; i < 5; i = i + 1 {
    assert_true(approx_eq(r[i], r[1], 1.0e-9))
  }
}

///|
test "pagerank: dangling node mass conservation" {
  // 0 -> 2, 1 -> 2. Node 2 is dangling (no out-links) yet receives all
  // the link flow. Its rank mass must still be conserved (sum = 1) and
  // redistributed uniformly on the next step.
  let r = pagerank(3, [(0, 2), (1, 2)], 0.85, 200, 1.0e-10)
  assert_eq(r.length(), 3)
  assert_true(approx_eq(sum_ranks(r), 1.0, 1.0e-6))
  // The dangling sink collects the most rank.
  assert_true(r[2] > r[0])
  assert_true(r[2] > r[1])
  // Nodes 0 and 1 are symmetric → equal ranks.
  assert_true(approx_eq(r[0], r[1], 1.0e-9))
  // Each rank is positive.
  for i = 0; i < 3; i = i + 1 {
    assert_true(r[i] > 0.0)
  }
}

///|
test "pagerank: convergence (iteration improves the estimate)" {
  // On a chain, one iteration is far from the fixed point; many iterations
  // converge. The two must differ, and the converged result sums to 1.
  let edges = [(0, 1), (1, 2), (2, 3)]
  let r_one = pagerank(4, edges, 0.85, 1, 0.0)
  let r_full = pagerank(4, edges, 0.85, 500, 1.0e-12)
  // One iteration is not yet converged.
  assert_true((r_one[0] - r_full[0]).abs() > 0.01)
  // The fully-iterated result is a probability distribution.
  assert_true(approx_eq(sum_ranks(r_full), 1.0, 1.0e-6))
  // Re-running is deterministic.
  let r_full2 = pagerank(4, edges, 0.85, 500, 1.0e-12)
  for i = 0; i < 4; i = i + 1 {
    assert_true(approx_eq(r_full[i], r_full2[i], 1.0e-12))
  }
}

///|
test "pagerank: complete graph gives uniform ranks" {
  // K4: every node links to every other node. By symmetry all ranks = 1/4.
  let edges : Array[(Int, Int)] = []
  for i = 0; i < 4; i = i + 1 {
    for j = 0; j < 4; j = j + 1 {
      if i != j {
        edges.push((i, j))
      }
    }
  }
  let r = pagerank(4, edges, 0.85, 200, 1.0e-10)
  for i = 0; i < 4; i = i + 1 {
    assert_true(approx_eq(r[i], 0.25, 1.0e-9))
  }
}

///|
test "pagerank: no edges gives uniform ranks" {
  // With no links every node is dangling; rank is distributed uniformly.
  let r = pagerank(4, [], 0.85, 100, 1.0e-6)
  for i = 0; i < 4; i = i + 1 {
    assert_true(approx_eq(r[i], 0.25, 1.0e-9))
  }
}

///|
test "pagerank: invalid n returns empty" {
  assert_eq(pagerank(0, [], 0.85, 100, 1.0e-6).length(), 0)
  assert_eq(pagerank(-3, [(0, 1)], 0.85, 100, 1.0e-6).length(), 0)
}

///|
test "pagerank: out-of-bounds edges are ignored" {
  // Only the valid edge (0, 1) counts; the rest are dropped.
  let r = pagerank(2, [(0, 1), (0, 5), (-1, 1), (7, 8)], 0.85, 200, 1.0e-10)
  assert_eq(r.length(), 2)
  assert_true(approx_eq(sum_ranks(r), 1.0, 1.0e-6))
  // Node 1 is a dangling sink of the single edge 0->1, so it ranks higher.
  assert_true(r[1] > r[0])
}

///|
test "pagerank: ranks sum to one on a general graph" {
  // A small web: 0->1, 0->2, 1->2, 2->0, 3->0, 3->2.
  let edges = [(0, 1), (0, 2), (1, 2), (2, 0), (3, 0), (3, 2)]
  let r = pagerank(4, edges, 0.85, 300, 1.0e-10)
  assert_eq(r.length(), 4)
  assert_true(approx_eq(sum_ranks(r), 1.0, 1.0e-6))
  for i = 0; i < 4; i = i + 1 {
    assert_true(r[i] > 0.0)
    assert_true(r[i] < 1.0)
  }
}
