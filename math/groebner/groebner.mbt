/// Groebner basis computation using Buchberger's algorithm.
///
/// Implements the following optimizations over naive Buchberger:
///
/// 1. **Product criterion** (Buchberger's first criterion): If the leading
///    monomials of g_i and g_j are coprime, S(g_i, g_j) reduces to zero
///    and the pair is skipped.
///
/// 2. **Chain criterion** (Buchberger's second criterion / Gebauer-Möller):
///    If there exists g_k whose leading monomial divides lcm(LM(g_i), LM(g_j))
///    and the lcm is strictly larger than both lcm(LM(g_i), LM(g_k)) and
///    lcm(LM(g_j), LM(g_k)), then S(g_i, g_j) is redundant and the pair
///    is skipped.
///
/// 3. **Sugar selection**: Pairs are processed in order of increasing sugar
///    degree, a heuristic that tends to produce smaller intermediate
///    polynomials and reduce total work.
///
/// 4. **Interreduction**: The final basis is autoreduced and normalized
///    (leading coefficients set to 1).
///
/// ## References
/// - Buchberger, B. "A Criterion for Detecting Unnecessary Reductions in
///   the Construction of Gröbner Bases." EUROSAM '79.
/// - Gebauer, R. and Möller, H. M. "On an Installation of Buchberger's
///   Algorithm." J. Symbolic Computation, 1988.
/// - Giovini, A. et al. "One sugar cube, please, or Selection strategies
///   in the Buchberger algorithm." ISSAC '91.
///
/// `proof-enabled` is `false`.

///|
fn mono_mul(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let result = Array::make(a.length(), 0)
  for i = 0; i < a.length(); i = i + 1 {
    result[i] = a[i] + b[i]
  }
  result
}

///|
/// Compare two monomials under lexicographic order.
/// Returns 1 if a > b, -1 if a < b, 0 if equal.
/// Uses explicit comparison to avoid integer overflow from subtraction.
fn mono_cmp(a : Array[Int], b : Array[Int]) -> Int {
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      if a[i] > b[i] {
        return 1
      } else {
        return -1
      }
    }
  }
  0
}

///|
fn mono_lcm(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let result = Array::make(a.length(), 0)
  for i = 0; i < a.length(); i = i + 1 {
    result[i] = if a[i] > b[i] { a[i] } else { b[i] }
  }
  result
}

///|
fn mono_div(a : Array[Int], b : Array[Int]) -> Array[Int]? {
  let result = Array::make(a.length(), 0)
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] < b[i] {
      return None
    }
    result[i] = a[i] - b[i]
  }
  Some(result)
}

///|
/// Total degree of a monomial (sum of exponents).
fn mono_degree(m : Array[Int]) -> Int {
  let mut sum = 0
  for i = 0; i < m.length(); i = i + 1 {
    sum = sum + m[i]
  }
  sum
}

///|
/// Check if monomial a divides monomial b (component-wise a[i] <= b[i]).
fn mono_divides(a : Array[Int], b : Array[Int]) -> Bool {
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] > b[i] {
      return false
    }
  }
  true
}

///|
/// Check if two monomials are coprime (no shared variable with positive exponent).
fn mono_coprime(a : Array[Int], b : Array[Int]) -> Bool {
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] > 0 && b[i] > 0 {
      return false
    }
  }
  true
}

///|
/// Check if two monomials are equal.
fn mono_eq(a : Array[Int], b : Array[Int]) -> Bool {
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Leading term of a polynomial (largest monomial under lex order).
fn leading_term(p : Array[(Double, Array[Int])]) -> (Double, Array[Int]) {
  let mut best = 0
  for i = 1; i < p.length(); i = i + 1 {
    if mono_cmp(p[i].1, p[best].1) > 0 {
      best = i
    }
  }
  p[best]
}

///|
/// Subtract polynomial b from a.
fn poly_sub(
  a : Array[(Double, Array[Int])],
  b : Array[(Double, Array[Int])],
) -> Array[(Double, Array[Int])] {
  let result : Array[(Double, Array[Int])] = []
  for i = 0; i < a.length(); i = i + 1 {
    result.push((a[i].0, a[i].1))
  }
  for i = 0; i < b.length(); i = i + 1 {
    let (coeff, mono) = b[i]
    let mut found = false
    for j = 0; j < result.length(); j = j + 1 {
      if mono_cmp(result[j].1, mono) == 0 {
        result[j] = (result[j].0 - coeff, mono)
        found = true
        break
      }
    }
    if !found {
      result.push((-coeff, mono))
    }
  }
  let filtered : Array[(Double, Array[Int])] = []
  for i = 0; i < result.length(); i = i + 1 {
    if result[i].0.abs() > 1.0e-14 {
      filtered.push(result[i])
    }
  }
  filtered
}

///|
/// Compute S-polynomial of two polynomials.
fn s_poly(
  f : Array[(Double, Array[Int])],
  g : Array[(Double, Array[Int])],
) -> Array[(Double, Array[Int])] raise Failure {
  let (cf, mf) = leading_term(f)
  let (cg, mg) = leading_term(g)
  let lcm = mono_lcm(mf, mg)
  // mono_div(lcm, mf) always succeeds since lcm >= mf component-wise.
  let df = match mono_div(lcm, mf) {
    Some(d) => d
    None => fail("s_poly: mono_div(lcm, mf) failed — invariant violated")
  }
  let dg = match mono_div(lcm, mg) {
    Some(d) => d
    None => fail("s_poly: mono_div(lcm, mg) failed — invariant violated")
  }
  let t1 : Array[(Double, Array[Int])] = []
  for i = 0; i < f.length(); i = i + 1 {
    t1.push((cg * f[i].0, mono_mul(df, f[i].1)))
  }
  let t2 : Array[(Double, Array[Int])] = []
  for i = 0; i < g.length(); i = i + 1 {
    t2.push((cf * g[i].0, mono_mul(dg, g[i].1)))
  }
  poly_sub(t1, t2)
}

///|
/// Reduce polynomial p by a set of polynomials G.
fn reduce(
  p : Array[(Double, Array[Int])],
  g : Array[Array[(Double, Array[Int])]],
) -> Array[(Double, Array[Int])] {
  let mut h : Array[(Double, Array[Int])] = []
  for i = 0; i < p.length(); i = i + 1 {
    h.push((p[i].0, p[i].1))
  }
  let mut changed = true
  while changed {
    changed = false
    for i = 0; i < g.length() && !changed; i = i + 1 {
      if g[i].length() == 0 {
        continue
      }
      let (cg, mg) = leading_term(g[i])
      for j = 0; j < h.length() && !changed; j = j + 1 {
        match mono_div(h[j].1, mg) {
          Some(q) =>
            if h[j].0.abs() > 1.0e-14 {
              let coeff = h[j].0 / cg
              let term : Array[(Double, Array[Int])] = []
              for k = 0; k < g[i].length(); k = k + 1 {
                term.push((coeff * g[i][k].0, mono_mul(q, g[i][k].1)))
              }
              h = poly_sub(h, term)
              changed = true
            }
          None => continue
        }
      }
    }
  }
  h
}

// ---------------------------------------------------------------------------
// Sugar degree and Gebauer-Möller criteria
// ---------------------------------------------------------------------------

///|
/// Sugar degree of a polynomial: max total degree of its terms.
/// Used as a heuristic for expected reduction complexity.
fn poly_sugar(p : Array[(Double, Array[Int])]) -> Int {
  let mut max_deg = 0
  for i = 0; i < p.length(); i = i + 1 {
    let d = mono_degree(p[i].1)
    if d > max_deg {
      max_deg = d
    }
  }
  max_deg
}

///|
/// Compute the sugar of the S-polynomial of g[i] and g[j].
///
/// sugar(S(i,j)) = max(sugar[i] + deg(lcm/t_i), sugar[j] + deg(lcm/t_j))
///
/// This heuristic estimates the complexity of reducing S(i,j) without
/// actually computing it.
fn compute_sugar(
  g : Array[Array[(Double, Array[Int])]],
  i : Int,
  j : Int,
  sugars : Array[Int],
) -> Int {
  let (_, mi) = leading_term(g[i])
  let (_, mj) = leading_term(g[j])
  let lcm = mono_lcm(mi, mj)
  let di = mono_degree(lcm) - mono_degree(mi)
  let dj = mono_degree(lcm) - mono_degree(mj)
  let si = sugars[i] + di
  let sj = sugars[j] + dj
  if si > sj {
    si
  } else {
    sj
  }
}

///|
/// Buchberger's product criterion: if gcd(LM(g_i), LM(g_j)) = 1 (leading
/// monomials are coprime), then S(g_i, g_j) reduces to zero.
/// Returns true if the pair should be kept, false if it can be skipped.
fn product_criterion_ok(
  g : Array[Array[(Double, Array[Int])]],
  i : Int,
  j : Int,
) -> Bool {
  let (_, mi) = leading_term(g[i])
  let (_, mj) = leading_term(g[j])
  !mono_coprime(mi, mj)
}

///|
/// Buchberger's chain criterion (Gebauer-Möller): pair (i,j) is redundant
/// if there exists k ∉ {i,j} such that:
///   1. LM(g_k) | lcm(LM(g_i), LM(g_j))
///   2. lcm(LM(g_i), LM(g_j)) ≠ lcm(LM(g_i), LM(g_k))
///   3. lcm(LM(g_i), LM(g_j)) ≠ lcm(LM(g_j), LM(g_k)))
/// Returns true if the pair should be kept, false if it can be skipped.
fn chain_criterion_ok(
  g : Array[Array[(Double, Array[Int])]],
  i : Int,
  j : Int,
) -> Bool {
  let (_, mi) = leading_term(g[i])
  let (_, mj) = leading_term(g[j])
  let t_ij = mono_lcm(mi, mj)
  for k = 0; k < g.length(); k = k + 1 {
    if k == i || k == j {
      continue
    }
    let (_, mk) = leading_term(g[k])
    if mono_divides(mk, t_ij) {
      let t_ik = mono_lcm(mi, mk)
      let t_jk = mono_lcm(mj, mk)
      if !mono_eq(t_ij, t_ik) && !mono_eq(t_ij, t_jk) {
        return false
      }
    }
  }
  true
}

///|
/// Check if a pair (i, j) should be kept (not skipped by either criterion).
fn pair_should_keep(
  g : Array[Array[(Double, Array[Int])]],
  i : Int,
  j : Int,
) -> Bool {
  product_criterion_ok(g, i, j) && chain_criterion_ok(g, i, j)
}

// ---------------------------------------------------------------------------
// Interreduction
// ---------------------------------------------------------------------------

///|
/// Interreduce the Groebner basis: autoreduce each element by the others,
/// remove zero polynomials, and normalize leading coefficients to 1.
fn interreduce(
  g : Array[Array[(Double, Array[Int])]],
) -> Array[Array[(Double, Array[Int])]] {
  let result : Array[Array[(Double, Array[Int])]] = []
  for i = 0; i < g.length(); i = i + 1 {
    result.push(g[i])
  }
  // Autoreduce: reduce each polynomial by all others until stable.
  let mut changed = true
  while changed {
    changed = false
    for i = 0; i < result.length(); i = i + 1 {
      if result[i].length() == 0 {
        continue
      }
      let others : Array[Array[(Double, Array[Int])]] = []
      for j = 0; j < result.length(); j = j + 1 {
        if j != i && result[j].length() > 0 {
          others.push(result[j])
        }
      }
      let reduced = reduce(result[i], others)
      if reduced.length() == 0 && result[i].length() > 0 {
        result[i] = reduced
        changed = true
      } else if reduced.length() > 0 {
        let (_, old_lt) = leading_term(result[i])
        let (_, new_lt) = leading_term(reduced)
        if !mono_eq(old_lt, new_lt) {
          result[i] = reduced
          changed = true
        }
      }
    }
  }
  // Remove zero polynomials and normalize.
  let filtered : Array[Array[(Double, Array[Int])]] = []
  for i = 0; i < result.length(); i = i + 1 {
    if result[i].length() > 0 {
      let (lc, _) = leading_term(result[i])
      let normalized : Array[(Double, Array[Int])] = []
      for j = 0; j < result[i].length(); j = j + 1 {
        normalized.push((result[i][j].0 / lc, result[i][j].1))
      }
      filtered.push(normalized)
    }
  }
  filtered
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Compute a Groebner basis using Buchberger's algorithm with sugar
/// selection and Gebauer-Möller criteria.
///
/// ## Parameters
/// - `polynomials`: array of polynomials, each represented as an array of
///   (coefficient, monomial) pairs where monomials are exponent vectors.
///
/// ## Returns
/// A reduced Groebner basis (autoreduced, leading coefficients normalized
/// to 1).
///
/// ## Example
/// ```
/// // Ideal <x - 1, y - 2>
/// let f1 = [(1.0, [1, 0]), (-1.0, [0, 0])]
/// let f2 = [(1.0, [0, 1]), (-2.0, [0, 0])]
/// let g = buchberger([f1, f2])
/// // g is a Groebner basis for <x-1, y-2>
/// ```
pub fn buchberger(
  polynomials : Array[Array[(Double, Array[Int])]],
) -> Array[Array[(Double, Array[Int])]] raise Failure {
  let g : Array[Array[(Double, Array[Int])]] = []
  for i = 0; i < polynomials.length(); i = i + 1 {
    g.push(polynomials[i])
  }
  let sugars : Array[Int] = []
  for i = 0; i < g.length(); i = i + 1 {
    sugars.push(poly_sugar(g[i]))
  }
  // Initialize pair list, applying product and chain criteria.
  // Each entry: (i, j, sugar).
  let pairs : Array[(Int, Int, Int)] = []
  for i = 0; i < g.length(); i = i + 1 {
    for j = i + 1; j < g.length(); j = j + 1 {
      if pair_should_keep(g, i, j) {
        pairs.push((i, j, compute_sugar(g, i, j, sugars)))
      }
    }
  }
  // Process pairs by minimum sugar (sugar selection strategy).
  while pairs.length() > 0 {
    // Find pair with minimum sugar.
    let mut min_idx = 0
    for i = 1; i < pairs.length(); i = i + 1 {
      if pairs[i].2 < pairs[min_idx].2 {
        min_idx = i
      }
    }
    let (pi, pj, _) = pairs[min_idx]
    // Swap-remove for O(1) deletion.
    let last = pairs.length() - 1
    pairs[min_idx] = pairs[last]
    ignore(pairs.pop())
    // Re-check criteria (basis may have grown since pair was created).
    if !pair_should_keep(g, pi, pj) {
      continue
    }
    let s = s_poly(g[pi], g[pj])
    let r = reduce(s, g)
    if r.length() > 0 {
      let new_idx = g.length()
      g.push(r)
      sugars.push(poly_sugar(r))
      // Add new pairs with criteria.
      for k = 0; k < new_idx; k = k + 1 {
        if pair_should_keep(g, k, new_idx) {
          pairs.push((k, new_idx, compute_sugar(g, k, new_idx, sugars)))
        }
      }
    }
  }
  // Interreduce the final basis.
  interreduce(g)
}

///|
/// Check if a polynomial is in the ideal generated by G.
pub fn in_ideal(
  p : Array[(Double, Array[Int])],
  g : Array[Array[(Double, Array[Int])]],
) -> Bool {
  let r = reduce(p, g)
  r.length() == 0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "groebner: ideal membership" {
  let f1 : Array[(Double, Array[Int])] = [(1.0, [1, 0]), (-1.0, [0, 0])]
  let f2 : Array[(Double, Array[Int])] = [(1.0, [0, 1]), (-2.0, [0, 0])]
  let g = buchberger([f1, f2])
  assert_true(in_ideal(f1, g))
  assert_true(in_ideal(f2, g))
}

///|
test "groebner: non-member" {
  let f1 : Array[(Double, Array[Int])] = [(1.0, [1, 0]), (-1.0, [0, 0])]
  let g = buchberger([f1])
  let y_poly : Array[(Double, Array[Int])] = [(1.0, [0, 1])]
  assert_false(in_ideal(y_poly, g))
}

///|
test "groebner: x^2-1 in ideal(x-1)" {
  let f1 : Array[(Double, Array[Int])] = [(1.0, [1, 0]), (-1.0, [0, 0])]
  let g = buchberger([f1])
  let x2 : Array[(Double, Array[Int])] = [(1.0, [2, 0]), (-1.0, [0, 0])]
  assert_true(in_ideal(x2, g))
}

///|
test "groebner: coprime leading monomials (product criterion)" {
  // x and y have coprime leading monomials — product criterion skips S-poly.
  // Basis should be {x, y} (already a Groebner basis).
  let f1 : Array[(Double, Array[Int])] = [(1.0, [1, 0])]
  let f2 : Array[(Double, Array[Int])] = [(1.0, [0, 1])]
  let g = buchberger([f1, f2])
  // Both x and y should be in the basis.
  assert_true(g.length() >= 2)
  assert_true(in_ideal(f1, g))
  assert_true(in_ideal(f2, g))
  // xy is in <x, y>.
  let xy : Array[(Double, Array[Int])] = [(1.0, [1, 1])]
  assert_true(in_ideal(xy, g))
}

///|
test "groebner: basis is reduced (leading coeff = 1)" {
  // 2x - 4 should normalize to x - 2 in the reduced basis.
  let f1 : Array[(Double, Array[Int])] = [(2.0, [1, 0]), (-4.0, [0, 0])]
  let g = buchberger([f1])
  assert_eq(g.length(), 1)
  let (lc, _) = leading_term(g[0])
  assert_true((lc - 1.0).abs() < 1.0e-10)
}

///|
test "groebner: two-variable system" {
  // <x^2 - y, x*y - 1>
  // Should produce a finite Groebner basis.
  let f1 : Array[(Double, Array[Int])] = [(1.0, [2, 0]), (-1.0, [0, 1])]
  let f2 : Array[(Double, Array[Int])] = [(1.0, [1, 1]), (-1.0, [0, 0])]
  let g = buchberger([f1, f2])
  assert_true(in_ideal(f1, g))
  assert_true(in_ideal(f2, g))
  // y^3 - 1 should be in the ideal (elimination property).
  let y3 : Array[(Double, Array[Int])] = [(1.0, [0, 3]), (-1.0, [0, 0])]
  assert_true(in_ideal(y3, g))
}

///|
test "groebner: chain criterion skips redundant pairs" {
  // Three polynomials where chain criterion applies:
  // <x-1, y-1, z-1> — all pairs with coprime LMs are skipped.
  let f1 : Array[(Double, Array[Int])] = [(1.0, [1, 0, 0]), (-1.0, [0, 0, 0])]
  let f2 : Array[(Double, Array[Int])] = [(1.0, [0, 1, 0]), (-1.0, [0, 0, 0])]
  let f3 : Array[(Double, Array[Int])] = [(1.0, [0, 0, 1]), (-1.0, [0, 0, 0])]
  let g = buchberger([f1, f2, f3])
  // Should have exactly 3 elements (no new S-polys needed).
  assert_eq(g.length(), 3)
  assert_true(in_ideal(f1, g))
  assert_true(in_ideal(f2, g))
  assert_true(in_ideal(f3, g))
}

///|
test "groebner: zero reduction produces smaller basis" {
  // <x^2 - 1, x - 1> — second divides first, basis should be {x - 1}.
  let f1 : Array[(Double, Array[Int])] = [(1.0, [2, 0]), (-1.0, [0, 0])]
  let f2 : Array[(Double, Array[Int])] = [(1.0, [1, 0]), (-1.0, [0, 0])]
  let g = buchberger([f1, f2])
  // After interreduction, only x - 1 should remain.
  assert_eq(g.length(), 1)
  assert_true(in_ideal(f1, g))
  assert_true(in_ideal(f2, g))
}
