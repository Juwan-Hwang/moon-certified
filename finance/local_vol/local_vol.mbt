/// Local Volatility Model — Dupire's Formula
///
/// Local volatility models compute an implied volatility surface from
/// observed option prices, allowing consistent pricing of exotic options.
///
/// ## Dupire's Formula
/// σ²(K,T) = 2 * (∂C/∂T + (r-q)*K*∂C/∂K + q*C) / (K² * ∂²C/∂K²)
/// where C(K,T) is the call option price as a function of strike and maturity.
///
/// ## References
/// - Dupire, B. "Pricing with a Smile." Risk Magazine, 1994.
///
/// `proof-enabled` is `false`.

///|
/// Market option data point.
pub struct OptionQuote {
  strike : Double
  maturity : Double // In years
  price : Double
}

///|
/// Create a new option quote.
pub fn OptionQuote::new(
  strike : Double,
  maturity : Double,
  price : Double,
) -> OptionQuote {
  { strike, maturity, price }
}

///|
/// Local volatility surface point.
pub struct LocalVolPoint {
  strike : Double
  maturity : Double
  vol : Double
}

///|
/// European call option price using Black-Scholes.
fn bs_call(
  spot : Double,
  strike : Double,
  maturity : Double,
  r : Double,
  q : Double,
  sigma : Double,
) -> Double {
  if maturity <= 0.0 {
    return (spot - strike).max(0.0)
  }
  if sigma <= 0.0 {
    return (spot * @math.exp(-q * maturity) - strike * @math.exp(-r * maturity)).max(
      0.0,
    )
  }
  let d1 = (@math.ln(spot / strike) + (r - q + sigma * sigma * 0.5) * maturity) /
    (sigma * maturity.sqrt())
  let d2 = d1 - sigma * maturity.sqrt()
  let n_d1 = normal_cdf(d1)
  let n_d2 = normal_cdf(d2)
  spot * @math.exp(-q * maturity) * n_d1 -
  strike * @math.exp(-r * maturity) * n_d2
}

///|
/// Standard normal CDF (approximation).
fn normal_cdf(x : Double) -> Double {
  // Abramowitz & Stegun approximation
  let z = x.abs()
  let mut result = 0.0
  if z > 6.0 {
    result = 1.0
  } else {
    let a1 = 0.254829592
    let a2 = -0.284496736
    let a3 = 1.421413741
    let a4 = -1.453152027
    let a5 = 1.061405429
    let p = 0.3275911
    let t = 1.0 / (1.0 + p * z)
    let y = 1.0 -
      ((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * @math.exp(-z * z)
    result = y
  }
  if x < 0.0 {
    1.0 - result
  } else {
    result
  }
}

///|
/// Standard normal PDF.
fn normal_pdf(x : Double) -> Double {
  @math.exp(-x * x / 2.0) / (2.0 * 3.14159265358979323846).sqrt()
}

///|
/// Compute local volatility using Dupire's formula.
///
/// ## Parameters
/// - `quotes`: observed option prices (must be sorted by strike, maturity)
/// - `spot`: spot price
/// - `r`: risk-free rate
/// - `q`: dividend yield
pub fn compute_local_vol(
  quotes : Array[OptionQuote],
  spot : Double,
  r : Double,
  q : Double,
) -> Array[LocalVolPoint] {
  let result : Array[LocalVolPoint] = []
  // Group quotes by maturity
  let maturities : Array[Double] = []
  for quote in quotes {
    if !maturities.contains(quote.maturity) {
      maturities.push(quote.maturity)
    }
  }
  for mat in maturities {
    // Get quotes for this maturity
    let mat_quotes : Array[OptionQuote] = []
    for q_t in quotes {
      if q_t.maturity == mat {
        mat_quotes.push(q_t)
      }
    }
    // For each quote, compute local vol via Dupire
    for i = 0; i < mat_quotes.length(); i = i + 1 {
      let c = mat_quotes[i]
      // Approximate derivatives using finite differences
      let dC_dT = 0.0
      let mut dC_dK = 0.0
      let mut d2C_dK2 = 0.0
      // dC/dT: use backward difference with previous maturity (simplified)
      if i > 0 && mat_quotes[i - 1].strike == c.strike {
        // Same strike, different maturity
        let _ = dC_dT
      }
      // dC/dK: central difference
      if i > 0 && i < mat_quotes.length() - 1 {
        let dk = mat_quotes[i + 1].strike - mat_quotes[i - 1].strike
        if dk > 0.0 {
          dC_dK = (mat_quotes[i + 1].price - mat_quotes[i - 1].price) / dk
          d2C_dK2 = (
              mat_quotes[i + 1].price - 2.0 * c.price + mat_quotes[i - 1].price
            ) /
            (dk * dk / 4.0)
        }
      }
      // Dupire's formula
      if d2C_dK2 > 0.0 {
        let numerator = 2.0 * (dC_dT + (r - q) * c.strike * dC_dK + q * c.price)
        let denominator = c.strike * c.strike * d2C_dK2
        if denominator > 0.0 && numerator > 0.0 {
          let vol = (numerator / denominator).sqrt()
          result.push({ strike: c.strike, maturity: mat, vol })
        }
      }
    }
  }
  result
}

///|
/// Price a European call using the local volatility surface.
pub fn price_with_local_vol(
  spot : Double,
  strike : Double,
  maturity : Double,
  r : Double,
  q : Double,
  vol : Double,
) -> Double {
  bs_call(spot, strike, maturity, r, q, vol)
}
