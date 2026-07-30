/// Event-Driven Backtesting Engine.
///
/// This module implements a lightweight event-driven backtesting
/// framework for multi-asset trading strategies. It follows the
/// classic event-loop architecture popularised by QuantStart and
/// Zipline, where each market data update triggers a cascade of
/// events:
///
/// 1. **MarketEvent** — new price data arrives for one or more symbols.
/// 2. **SignalEvent** — the strategy inspects the market state and
///    emits buy/sell signals.
/// 3. **OrderEvent** — signals are converted into concrete orders.
/// 4. **FillEvent** — the simulated broker fills the order at the
///    current market price (minus commission).
///
/// ## Portfolio Management
///
/// The `Portfolio` struct tracks:
/// - Cash balance
/// - Open positions per symbol (quantity and average entry price)
/// - An equity curve sampled at each time step
///
/// Position updates use the weighted-average-cost method: when adding
/// to a position the average price is updated; when reducing, the
/// average price is unchanged and realised PnL is recorded.
///
/// ## Performance Metrics
///
/// - **Total return**: `(equity_final − capital) / capital`
/// - **Annualised return**: `(1 + r)^(periods_per_year / n) − 1`
/// - **Sharpe ratio**: `mean(r_t) / std(r_t) * √(periods_per_year)`
/// - **Maximum drawdown**: largest peak-to-trough decline in the
///   equity curve, expressed as a fraction.
///
/// ## References
///
/// - M. L. de Prado. "Advances in Financial Machine Learning."
///   Wiley, 2018. Chapter 7 (Cross-Validation in Finance).
/// - QuantStart. "Event-Driven Backtesting with Python." 2014.
/// - R. F. Engle. "Anticipating Correlations." Princeton, 2009.
///
/// `proof-enabled` is `false`; correctness is backed by test vectors.

// ---------------------------------------------------------------------------
// Data Types
// ---------------------------------------------------------------------------

///|
/// An order to buy or sell a symbol at market.
pub struct Order {
  symbol : String
  quantity : Double // positive = buy, negative = sell
}

///|
/// A fill confirmation from the simulated broker.
pub struct Fill {
  symbol : String
  quantity : Double // signed: positive buy, negative sell
  price : Double
  commission : Double
}

///|
/// A position in a single symbol.
pub struct Position {
  mut quantity : Double
  mut avg_price : Double
}

///|
/// Portfolio state: cash, positions, and equity history.
pub struct Portfolio {
  mut cash : Double
  initial_capital : Double
  positions : Array[(String, Position)]
  equity_history : Array[Double]
  mut realised_pnl : Double
  mut num_fills : Int
}

///|
/// Create a new portfolio with the given initial capital.
pub fn new_portfolio(initial_capital : Double) -> Portfolio {
  {
    cash: initial_capital,
    initial_capital,
    positions: [],
    equity_history: [],
    realised_pnl: 0.0,
    num_fills: 0,
  }
}

///|
/// Look up the position for a symbol, creating an empty one if absent.
fn get_or_create_position(portfolio : Portfolio, symbol : String) -> Position {
  for i = 0; i < portfolio.positions.length(); i = i + 1 {
    let (s, pos) = portfolio.positions[i]
    if s == symbol {
      return pos
    }
  }
  let pos : Position = { quantity: 0.0, avg_price: 0.0 }
  portfolio.positions.push((symbol, pos))
  pos
}

///|
/// Look up the quantity held for a symbol (0 if no position).
pub fn portfolio_quantity(portfolio : Portfolio, symbol : String) -> Double {
  for i = 0; i < portfolio.positions.length(); i = i + 1 {
    let (s, pos) = portfolio.positions[i]
    if s == symbol {
      return pos.quantity
    }
  }
  0.0
}

///|
/// Total market value of all open positions at the given prices.
///
/// - `prices`: Array of (symbol, current_price).
fn portfolio_market_value(
  portfolio : Portfolio,
  prices : Array[(String, Double)],
) -> Double {
  let mut mv = 0.0
  for i = 0; i < portfolio.positions.length(); i = i + 1 {
    let (symbol, pos) = portfolio.positions[i]
    if pos.quantity != 0.0 {
      let mut price = 0.0
      for j = 0; j < prices.length(); j = j + 1 {
        let (s, p) = prices[j]
        if s == symbol {
          price = p
          break
        }
      }
      mv = mv + pos.quantity * price
    }
  }
  mv
}

///|
/// Total equity = cash + market value of positions.
pub fn portfolio_equity(
  portfolio : Portfolio,
  prices : Array[(String, Double)],
) -> Double {
  portfolio.cash + portfolio_market_value(portfolio, prices)
}

///|
/// Apply a fill to the portfolio, updating cash and positions.
///
/// Uses weighted-average-cost accounting:
/// - Buying: avg_price is updated to reflect the blended cost.
/// - Selling: realised PnL = (fill_price − avg_price) × |qty|.
/// - Commission reduces cash.
fn apply_fill(portfolio : Portfolio, fill : Fill) -> Unit {
  let pos = get_or_create_position(portfolio, fill.symbol)
  let trade_value = fill.quantity * fill.price
  if fill.quantity > 0.0 {
    // Increasing long (or decreasing short)
    if pos.quantity >= 0.0 {
      // Adding to long: update weighted average cost.
      let total_cost = pos.avg_price * pos.quantity + fill.price * fill.quantity
      pos.quantity = pos.quantity + fill.quantity
      if pos.quantity > 0.0 {
        pos.avg_price = total_cost / pos.quantity
      } else {
        pos.avg_price = 0.0
      }
    } else {
      // Reducing short: realise PnL.
      let closing_qty = if fill.quantity > -pos.quantity {
        -pos.quantity
      } else {
        fill.quantity
      }
      portfolio.realised_pnl = portfolio.realised_pnl +
        (pos.avg_price - fill.price) * closing_qty
      pos.quantity = pos.quantity + fill.quantity
      if pos.quantity >= 0.0 {
        pos.avg_price = fill.price
      }
    }
  } else if fill.quantity < 0.0 {
    // Selling (or shorting)
    if pos.quantity > 0.0 {
      // Reducing long: realise PnL.
      let closing_qty = if -fill.quantity > pos.quantity {
        pos.quantity
      } else {
        -fill.quantity
      }
      portfolio.realised_pnl = portfolio.realised_pnl +
        (fill.price - pos.avg_price) * closing_qty
      pos.quantity = pos.quantity + fill.quantity
      if pos.quantity <= 0.0 {
        pos.avg_price = fill.price
      }
    } else {
      // Adding to short: update weighted average short price.
      let total_cost = pos.avg_price * -pos.quantity +
        fill.price * -fill.quantity
      pos.quantity = pos.quantity + fill.quantity
      if pos.quantity < 0.0 {
        pos.avg_price = total_cost / -pos.quantity
      } else {
        pos.avg_price = 0.0
      }
    }
  }
  // Cash: buying costs money, selling brings money. Commission always
  // reduces cash.
  portfolio.cash = portfolio.cash - trade_value - fill.commission
  portfolio.num_fills = portfolio.num_fills + 1
}

// ---------------------------------------------------------------------------
// Commission Models
// ---------------------------------------------------------------------------

///|
/// Fixed cost per share (e.g. $0.005/share).
pub fn per_share_commission(rate : Double) -> (Double, Double) -> Double {
  fn(quantity : Double, _price : Double) -> Double { quantity.abs() * rate }
}

///|
/// Percentage of notional (e.g. 0.1% → 0.001).
pub fn percent_commission(rate : Double) -> (Double, Double) -> Double {
  fn(quantity : Double, price : Double) -> Double {
    (quantity * price).abs() * rate
  }
}

///|
/// Zero commission.
pub fn zero_commission() -> (Double, Double) -> Double {
  fn(_quantity : Double, _price : Double) -> Double { 0.0 }
}

// ---------------------------------------------------------------------------
// Slippage Models
// ---------------------------------------------------------------------------

/// Slippage model function type: given (quantity, price, ADV), returns
/// the fill price adjusted for market impact and friction.
///
/// Production backtests must account for slippage — the difference between
/// the expected fill price (e.g. close price) and the actual execution
/// price. Without slippage, backtests systematically overestimate returns.

///|
/// Zero slippage — fills at the exact reference price.
///
/// Equivalent to the original behaviour. Use only for sanity checks.
pub fn zero_slippage() -> (Double, Double, Double) -> Double {
  fn(_qty : Double, price : Double, _adv : Double) -> Double { price }
}

///|
/// Fixed basis-point slippage.
///
/// Applies a constant spread cost in basis points. For buys, the fill
/// price is inflated by `bps / 1e4`; for sells, it's deflated.
///
/// - `bps`: Slippage in basis points (e.g. 5.0 = 5 bps = 0.05%).
pub fn fixed_bps_slippage(bps : Double) -> (Double, Double, Double) -> Double {
  fn(qty : Double, price : Double, _adv : Double) -> Double {
    let frac = bps / 1.0e4
    if qty > 0.0 {
      price * (1.0 + frac)
    } else if qty < 0.0 {
      price * (1.0 - frac)
    } else {
      price
    }
  }
}

///|
/// Square-root market impact slippage (Almgren-Chriss / Kissell model).
///
/// Empirical studies show that price impact scales with the square root
/// of participation rate. This model is used by many buy-side desks.
///
/// `impact_bps = coefficient · √(|qty| / ADV) · 1e4`
///
/// For buys, fill price is inflated; for sells, deflated.
///
/// - `coefficient`: Impact coefficient (e.g. 0.5 for liquid stocks).
/// - `adv`: Average daily volume (passed per-fill via the slippage callback).
pub fn sqrt_impact_slippage(coefficient : Double) -> (Double, Double, Double) -> Double {
  fn(qty : Double, price : Double, adv : Double) -> Double {
    if adv <= 0.0 || qty == 0.0 {
      return price
    }
    let participation = qty.abs() / adv
    if participation <= 0.0 {
      return price
    }
    let impact_bps = coefficient * participation.sqrt() * 1.0e4
    let frac = impact_bps / 1.0e4
    if qty > 0.0 {
      price * (1.0 + frac)
    } else {
      price * (1.0 - frac)
    }
  }
}

///|
/// Linear market impact slippage.
///
/// `impact_bps = coefficient · (|qty| / ADV) · 1e4`
///
/// Simpler than square-root but overestimates impact for large orders.
pub fn linear_impact_slippage(coefficient : Double) -> (Double, Double, Double) -> Double {
  fn(qty : Double, price : Double, adv : Double) -> Double {
    if adv <= 0.0 || qty == 0.0 {
      return price
    }
    let participation = qty.abs() / adv
    let impact_bps = coefficient * participation * 1.0e4
    let frac = impact_bps / 1.0e4
    if qty > 0.0 {
      price * (1.0 + frac)
    } else {
      price * (1.0 - frac)
    }
  }
}

// ---------------------------------------------------------------------------
// Backtest Engine
// ---------------------------------------------------------------------------

///|
/// Backtest result containing the equity curve and performance metrics.
pub struct BacktestResult {
  equity_curve : Array[Double]
  total_return : Double
  annualised_return : Double
  sharpe_ratio : Double
  max_drawdown : Double
  num_fills : Int
  final_equity : Double
}

///|
/// Run a backtest over a sequence of market bars.
///
/// The market data is supplied as an array of time steps, where each
/// time step is an array of `(symbol, close_price)` pairs. At each
/// step the engine:
///
/// 1. Builds the current price map.
/// 2. Calls `strategy(step_index, prices, portfolio)` to obtain orders.
/// 3. Fills each order at the current price (minus commission).
/// 4. Records portfolio equity.
///
/// After all steps the performance metrics are computed.
///
/// - `market_data`: Array of time steps, each being `Array[(String, Double)]`.
/// - `initial_capital`: Starting cash.
/// - `periods_per_year`: Number of time steps per year (252 for daily,
///   12 for monthly). Used for annualisation.
/// - `commission`: Commission model.
/// - `strategy`: Callback `(step, prices, portfolio) -> Array[Order]`.
pub fn run_backtest(
  market_data : Array[Array[(String, Double)]],
  initial_capital : Double,
  periods_per_year : Int,
  commission : (Double, Double) -> Double,
  strategy : (Int, Array[(String, Double)], Portfolio) -> Array[Order],
) -> BacktestResult {
  run_backtest_with_slippage(
    market_data,
    initial_capital,
    periods_per_year,
    commission,
    zero_slippage(),
    0.0, // ADV = 0 → slippage disabled
    strategy,
  )
}

///|
/// Run a backtest with slippage and market impact modelling.
///
/// This is the production-grade backtest function. Unlike `run_backtest`
/// (which fills at the exact close price), this function applies a
/// slippage model to each fill, simulating the friction between the
/// reference price and the actual execution price.
///
/// ## Slippage
///
/// The `slippage` callback receives `(quantity, reference_price, adv)`
/// and returns the adjusted fill price. For buys, the fill price is
/// typically higher than the reference; for sells, lower.
///
/// ## Abnormal Market Handling
///
/// - **Missing price**: If a symbol has no price in the current step,
///   the order for that symbol is skipped (not filled).
/// - **Zero or negative price**: Treated as a trading halt; the order
///   is skipped.
/// - **Zero quantity**: Silently skipped.
///
/// - `adv`: Average daily volume used by the slippage model. Pass 0.0
///   to disable volume-based impact (fixed-bps slippage still works).
pub fn run_backtest_with_slippage(
  market_data : Array[Array[(String, Double)]],
  initial_capital : Double,
  periods_per_year : Int,
  commission : (Double, Double) -> Double,
  slippage : (Double, Double, Double) -> Double,
  adv : Double,
  strategy : (Int, Array[(String, Double)], Portfolio) -> Array[Order],
) -> BacktestResult {
  let portfolio = new_portfolio(initial_capital)
  let n = market_data.length()
  for step = 0; step < n; step = step + 1 {
    let prices = market_data[step]
    // Strategy generates orders based on current state.
    let orders = strategy(step, prices, portfolio)
    // Fill each order at the current close price with slippage.
    for i = 0; i < orders.length(); i = i + 1 {
      let order = orders[i]
      let mut ref_price = 0.0
      for j = 0; j < prices.length(); j = j + 1 {
        let (s, p) = prices[j]
        if s == order.symbol {
          ref_price = p
          break
        }
      }
      // Skip if no price found (missing data) or price <= 0 (trading halt).
      if ref_price <= 0.0 || order.quantity == 0.0 {
        continue
      }
      let fill_price = slippage(order.quantity, ref_price, adv)
      let comm = commission(order.quantity, fill_price)
      apply_fill(portfolio, {
        symbol: order.symbol,
        quantity: order.quantity,
        price: fill_price,
        commission: comm,
      })
    }
    // Record equity at end of step.
    portfolio.equity_history.push(portfolio_equity(portfolio, prices))
  }
  compute_result(portfolio, periods_per_year, initial_capital)
}

// ---------------------------------------------------------------------------
// Performance Metrics
// ---------------------------------------------------------------------------

///|
/// Compute the maximum drawdown from an equity curve.
///
/// `MDD = max_t (peak_t − equity_t) / peak_t`
///
/// Returns a non-negative fraction (e.g. 0.20 for a 20% drawdown).
pub fn max_drawdown(equity_curve : Array[Double]) -> Double {
  let n = equity_curve.length()
  if n == 0 {
    return 0.0
  }
  let mut peak = equity_curve[0]
  let mut mdd = 0.0
  for i = 0; i < n; i = i + 1 {
    if equity_curve[i] > peak {
      peak = equity_curve[i]
    }
    if peak > 0.0 {
      let dd = (peak - equity_curve[i]) / peak
      if dd > mdd {
        mdd = dd
      }
    }
  }
  mdd
}

///|
/// Compute the Sharpe ratio from an equity curve.
///
/// `Sharpe = mean(r_t) / std(r_t) * √(periods_per_year)`
///
/// where `r_t` are the period-to-period returns. Uses sample
/// standard deviation (n−1 denominator).
pub fn sharpe_ratio(
  equity_curve : Array[Double],
  periods_per_year : Int,
) -> Double {
  let n = equity_curve.length()
  if n < 2 {
    return 0.0
  }
  // Period returns.
  let returns : Array[Double] = []
  for i = 1; i < n; i = i + 1 {
    if equity_curve[i - 1] != 0.0 {
      returns.push(
        (equity_curve[i] - equity_curve[i - 1]) / equity_curve[i - 1],
      )
    } else {
      returns.push(0.0)
    }
  }
  let m = returns.length()
  if m == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for i = 0; i < m; i = i + 1 {
    sum = sum + returns[i]
  }
  let mean_r = sum / m.to_double()
  let mut sq_sum = 0.0
  for i = 0; i < m; i = i + 1 {
    let d = returns[i] - mean_r
    sq_sum = sq_sum + d * d
  }
  let variance = sq_sum / (m - 1).to_double()
  if variance <= 0.0 {
    return 0.0
  }
  let std_r = variance.sqrt()
  mean_r / std_r * periods_per_year.to_double().sqrt()
}

///|
/// Compute total return from an equity curve.
pub fn total_return(equity_curve : Array[Double]) -> Double {
  let n = equity_curve.length()
  if n == 0 {
    return 0.0
  }
  if equity_curve[0] == 0.0 {
    return 0.0
  }
  (equity_curve[n - 1] - equity_curve[0]) / equity_curve[0]
}

///|
/// Compute annualised return from an equity curve.
///
/// `(1 + r)^(periods_per_year / n) − 1`
pub fn annualised_return(
  equity_curve : Array[Double],
  periods_per_year : Int,
) -> Double {
  let n = equity_curve.length()
  if n < 2 || periods_per_year <= 0 || equity_curve[0] <= 0.0 {
    return 0.0
  }
  let r = total_return(equity_curve)
  let years = (n - 1).to_double() / periods_per_year.to_double()
  if years <= 0.0 {
    return r
  }
  @math.pow(1.0 + r, 1.0 / years) - 1.0
}

///|
/// Assemble a `BacktestResult` from the portfolio and equity curve.
fn compute_result(
  portfolio : Portfolio,
  periods_per_year : Int,
  initial_capital : Double,
) -> BacktestResult {
  let curve = portfolio.equity_history
  let tr = total_return(curve)
  let ar = annualised_return(curve, periods_per_year)
  let sr = sharpe_ratio(curve, periods_per_year)
  let mdd = max_drawdown(curve)
  let final_equity = if curve.length() > 0 {
    curve[curve.length() - 1]
  } else {
    initial_capital
  }
  {
    equity_curve: Array::copy(curve),
    total_return: tr,
    annualised_return: ar,
    sharpe_ratio: sr,
    max_drawdown: mdd,
    num_fills: portfolio.num_fills,
    final_equity,
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "backtest: buy and hold single asset" {
  // Price goes from 100 → 120 over 10 steps.
  let market_data : Array[Array[(String, Double)]] = []
  for i = 0; i < 10; i = i + 1 {
    let price = 100.0 + i.to_double() * 2.0
    market_data.push([("AAPL", price)])
  }
  let result = run_backtest(market_data, 10000.0, 252, zero_commission(), fn(
    step,
    _prices,
    portfolio,
  ) {
    // Buy on the first step with all cash.
    if step == 0 {
      let price = 100.0
      let qty = (portfolio.cash / price).floor()
      return [{ symbol: "AAPL", quantity: qty }]
    }
    []
  })
  // Final price is 118. Bought 100 shares at 100. Equity = 100*118 = 11800.
  assert_true((result.final_equity - 11800.0).abs() < 1.0)
  assert_true((result.total_return - 0.18).abs() < 0.001)
  assert_eq(result.num_fills, 1)
}

///|
test "backtest: multi-asset portfolio" {
  // Two assets: AAPL goes 100→110, GOOG goes 200→190.
  let market_data : Array[Array[(String, Double)]] = []
  for i = 0; i < 5; i = i + 1 {
    market_data.push([
      ("AAPL", 100.0 + i.to_double() * 2.5),
      ("GOOG", 200.0 - i.to_double() * 2.5),
    ])
  }
  let result = run_backtest(market_data, 10000.0, 252, zero_commission(), fn(
    step,
    prices,
    portfolio,
  ) {
    if step == 0 {
      // Split capital 50/50.
      let orders : Array[Order] = []
      for j = 0; j < prices.length(); j = j + 1 {
        let (sym, price) = prices[j]
        let qty = (portfolio.cash * 0.5 / price).floor()
        if qty > 0.0 {
          orders.push({ symbol: sym, quantity: qty })
        }
      }
      orders
    } else {
      []
    }
  })
  // AAPL: bought 50 shares at 100 → worth 50*110 = 5500
  // GOOG: bought 25 shares at 200 → worth 25*190 = 4750
  // Total equity = 5500 + 4750 = 10250 (but floor might cause rounding)
  assert_true(result.final_equity > 10200.0)
  assert_true(result.final_equity < 10300.0)
  assert_eq(result.num_fills, 2)
}

///|
test "backtest: commission reduces returns" {
  let market_data : Array[Array[(String, Double)]] = [
    [("AAPL", 100.0)],
    [("AAPL", 110.0)],
    [("AAPL", 120.0)],
  ]
  let result_no_comm = run_backtest(
    market_data,
    10000.0,
    252,
    zero_commission(),
    fn(step, _prices, portfolio) {
      if step == 0 {
        let qty = (portfolio.cash / 100.0).floor()
        [{ symbol: "AAPL", quantity: qty }]
      } else {
        []
      }
    },
  )
  let result_with_comm = run_backtest(
    market_data,
    10000.0,
    252,
    per_share_commission(0.1),
    fn(step, _prices, portfolio) {
      if step == 0 {
        let qty = (portfolio.cash / 100.0).floor()
        [{ symbol: "AAPL", quantity: qty }]
      } else {
        []
      }
    },
  )
  assert_true(result_no_comm.final_equity > result_with_comm.final_equity)
}

///|
test "metrics: max drawdown" {
  // Equity: 100, 120, 90, 110 → peak=120, trough=90, MDD = 30/120 = 0.25
  let curve = [100.0, 120.0, 90.0, 110.0]
  let mdd = max_drawdown(curve)
  assert_true((mdd - 0.25).abs() < 1.0e-10)
}

///|
test "metrics: max drawdown zero for monotonic increase" {
  let curve = [100.0, 110.0, 120.0, 130.0]
  let mdd = max_drawdown(curve)
  assert_true(mdd.abs() < 1.0e-10)
}

///|
test "metrics: sharpe ratio positive for gains" {
  // Steady gains should give a positive Sharpe.
  let curve = [100.0, 101.0, 102.0, 103.0, 104.0]
  let sr = sharpe_ratio(curve, 252)
  assert_true(sr > 0.0)
}

///|
test "metrics: sharpe ratio scales with frequency" {
  let curve = [100.0, 101.0, 102.0, 103.0, 104.0]
  let sr_daily = sharpe_ratio(curve, 252)
  let sr_monthly = sharpe_ratio(curve, 12)
  // Annualised Sharpe should be higher for daily (more periods).
  assert_true(sr_daily > sr_monthly)
}

///|
test "metrics: total return" {
  let curve = [10000.0, 10500.0, 11000.0]
  let tr = total_return(curve)
  assert_true((tr - 0.10).abs() < 1.0e-10)
}

///|
test "metrics: annualised return" {
  // 252 daily steps, 10% total return → ~10% annualised.
  let curve : Array[Double] = []
  for i = 0; i < 253; i = i + 1 {
    curve.push(10000.0 * (1.0 + 0.10 * i.to_double() / 252.0))
  }
  let ar = annualised_return(curve, 252)
  assert_true((ar - 0.10).abs() < 0.01)
}

///|
test "portfolio: short position" {
  let portfolio = new_portfolio(10000.0)
  apply_fill(portfolio, {
    symbol: "AAPL",
    quantity: -50.0,
    price: 100.0,
    commission: 0.0,
  })
  // Shorted 50 shares at $100 → cash increased by 5000.
  assert_true((portfolio.cash - 15000.0).abs() < 1.0e-10)
  assert_true((portfolio_quantity(portfolio, "AAPL") + 50.0).abs() < 1.0e-10)
  // Cover at $90 → realised PnL = 50 * (100-90) = 500.
  apply_fill(portfolio, {
    symbol: "AAPL",
    quantity: 50.0,
    price: 90.0,
    commission: 0.0,
  })
  assert_true((portfolio.realised_pnl - 500.0).abs() < 1.0e-10)
}

///|
test "portfolio: average cost updates on add" {
  let portfolio = new_portfolio(10000.0)
  apply_fill(portfolio, {
    symbol: "X",
    quantity: 100.0,
    price: 50.0,
    commission: 0.0,
  })
  apply_fill(portfolio, {
    symbol: "X",
    quantity: 100.0,
    price: 60.0,
    commission: 0.0,
  })
  // Avg cost = (100*50 + 100*60) / 200 = 55.
  for i = 0; i < portfolio.positions.length(); i = i + 1 {
    let (s, pos) = portfolio.positions[i]
    if s == "X" {
      assert_true((pos.avg_price - 55.0).abs() < 1.0e-10)
      assert_true((pos.quantity - 200.0).abs() < 1.0e-10)
    }
  }
}

///|
test "slippage: zero slippage fills at reference price" {
  let market_data : Array[Array[(String, Double)]] = [
    [("AAPL", 100.0)],
    [("AAPL", 110.0)],
  ]
  let result = run_backtest_with_slippage(
    market_data,
    10000.0,
    252,
    zero_commission(),
    zero_slippage(),
    0.0,
    fn(step, _prices, portfolio) {
      if step == 0 {
        let qty = (portfolio.cash / 100.0).floor()
        [{ symbol: "AAPL", quantity: qty }]
      } else {
        []
      }
    },
  )
  // Same as run_backtest with zero slippage
  assert_true((result.final_equity - 11000.0).abs() < 1.0)
}

///|
test "slippage: fixed bps increases buy cost" {
  let market_data : Array[Array[(String, Double)]] = [
    [("AAPL", 100.0)],
    [("AAPL", 110.0)],
  ]
  let result_no_slip = run_backtest_with_slippage(
    market_data,
    10000.0,
    252,
    zero_commission(),
    zero_slippage(),
    0.0,
    fn(step, _prices, portfolio) {
      if step == 0 {
        let qty = (portfolio.cash / 100.0).floor()
        [{ symbol: "AAPL", quantity: qty }]
      } else {
        []
      }
    },
  )
  let result_with_slip = run_backtest_with_slippage(
    market_data,
    10000.0,
    252,
    zero_commission(),
    fixed_bps_slippage(10.0), // 10 bps = 0.1%
    0.0,
    fn(step, _prices, portfolio) {
      if step == 0 {
        let qty = (portfolio.cash / 100.0).floor()
        [{ symbol: "AAPL", quantity: qty }]
      } else {
        []
      }
    },
  )
  // With slippage, buy price is higher → fewer shares bought → lower final equity
  assert_true(result_with_slip.final_equity < result_no_slip.final_equity)
}

///|
test "slippage: sqrt impact scales with order size" {
  let market_data : Array[Array[(String, Double)]] = [
    [("AAPL", 100.0)],
    [("AAPL", 100.0)],
  ]
  // Small order: 10 shares
  let result_small = run_backtest_with_slippage(
    market_data,
    100000.0,
    252,
    zero_commission(),
    sqrt_impact_slippage(0.5),
    10000.0, // ADV
    fn(_step, _prices, _portfolio) {
      [{ symbol: "AAPL", quantity: 10.0 }]
    },
  )
  // Large order: 1000 shares (10% of ADV)
  let result_large = run_backtest_with_slippage(
    market_data,
    100000.0,
    252,
    zero_commission(),
    sqrt_impact_slippage(0.5),
    10000.0, // ADV
    fn(_step, _prices, _portfolio) {
      [{ symbol: "AAPL", quantity: 1000.0 }]
    },
  )
  // Both buy at step 0, price stays at 100, so equity = cash - cost of buying
  // Large order has more impact → higher fill price → more cost → lower equity
  let small_impact_cost = 100000.0 - result_small.final_equity
  let large_impact_cost = 100000.0 - result_large.final_equity
  // Per-share impact cost should be higher for the large order
  assert_true(large_impact_cost / 1000.0 > small_impact_cost / 10.0)
}

///|
test "slippage: missing price skips order" {
  let market_data : Array[Array[(String, Double)]] = [
    [("AAPL", 100.0)],
    [("GOOG", 200.0)], // No AAPL price in step 1
    [("AAPL", 110.0)],
  ]
  let result = run_backtest_with_slippage(
    market_data,
    10000.0,
    252,
    zero_commission(),
    zero_slippage(),
    0.0,
    fn(step, _prices, portfolio) {
      if step == 0 {
        let qty = (portfolio.cash / 100.0).floor()
        [{ symbol: "AAPL", quantity: qty }]
      } else {
        []
      }
    },
  )
  // Order at step 0 fills normally, no orders at steps 1-2
  assert_eq(result.num_fills, 1)
}

///|
test "slippage: zero/negative price treated as halt" {
  let market_data : Array[Array[(String, Double)]] = [
    [("AAPL", 0.0)],  // Trading halt
    [("AAPL", 100.0)],
  ]
  let result = run_backtest_with_slippage(
    market_data,
    10000.0,
    252,
    zero_commission(),
    zero_slippage(),
    0.0,
    fn(step, _prices, portfolio) {
      if step == 0 {
        let qty = (portfolio.cash / 100.0).floor()
        [{ symbol: "AAPL", quantity: qty }]
      } else {
        []
      }
    },
  )
  // Order at step 0 should be skipped (price = 0, trading halt)
  assert_eq(result.num_fills, 0)
  // All cash preserved
  assert_true((result.final_equity - 10000.0).abs() < 1.0)
}
