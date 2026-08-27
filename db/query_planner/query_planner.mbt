/// SQL Query Planner — Cost-Based Plan Selection
///
/// Implements a simplified cost-based query optimizer that selects
/// execution plans based on estimated I/O and CPU costs.
///
/// ## Plan Selection
/// - Table scan: cost = n_rows
/// - Index scan: cost = log(n_rows) + n_result_rows
/// - Hash join: cost = n_left + n_right
/// - Nested loop join: cost = n_left * n_right
/// - Sort: cost = n * log(n)
///
/// `proof-enabled` is `false`.

///|
/// Scan method.
pub enum ScanMethod {
  FullScan // Sequential scan
  IndexScan // Index lookup
}

///|
/// Join method.
pub enum JoinMethod {
  HashJoin
  NestedLoopJoin
  MergeJoin // Sort-merge join
}

///|
/// Table statistics.
pub struct TableStats {
  name : String
  n_rows : Int
  n_pages : Int
  indexes : Array[String]
}

///|
/// Query plan node.
pub enum PlanNode {
  TableScan(String, ScanMethod)
  Filter(String, PlanNode) // predicate, child
  Join(JoinMethod, String, PlanNode, PlanNode) // method, condition, left, right
  Sort(String, PlanNode) // sort key, child
  Project(Array[String], PlanNode) // columns, child
}

///|
/// Estimated cost of a plan.
pub struct PlanCost {
  cpu_cost : Double
  io_cost : Double
  total_cost : Double
  cardinality : Int
}

///|
/// Natural logarithm via Newton's method (Taylor series fallback for small x).
fn log_double(x : Double) -> Double {
  if x <= 0.0 {
    return -999999.0
  }
  // Reduce x to x = m * 2^e where 1 <= m < 2
  let mut e = 0
  let mut m = x
  while m >= 2.0 {
    m = m / 2.0
    e = e + 1
  }
  while m < 1.0 {
    m = m * 2.0
    e = e - 1
  }
  // ln(m) via atanh series: ln((1+y)/(1-y)) = 2*(y + y^3/3 + y^5/5 + ...)
  let y = (m - 1.0) / (m + 1.0)
  let mut result = 0.0
  let mut term = y
  let mut k = 1
  while k < 50 {
    result = result + term / k.to_double()
    term = term * y * y
    k = k + 2
  }
  result * 2.0 + e.to_double() * 0.6931471805599453
}

///|
/// Find table statistics by name.
fn find_table_stats(stats : Array[TableStats], name : String) -> TableStats? {
  for i in 0..<stats.length() {
    if stats[i].name == name {
      return Some(stats[i])
    }
  }
  None
}

///|
/// Estimate the cost of a plan node.
pub fn estimate_cost(node : PlanNode, stats : Array[TableStats]) -> PlanCost {
  match node {
    TableScan(name, scan_method) => {
      let table_stats = find_table_stats(stats, name)
      match table_stats {
        Some(s) =>
          match scan_method {
            FullScan => {
              let cost = s.n_rows.to_double()
              {
                cpu_cost: cost,
                io_cost: s.n_pages.to_double(),
                total_cost: cost + s.n_pages.to_double(),
                cardinality: s.n_rows,
              }
            }
            IndexScan => {
              let cost = log_double(s.n_rows.to_double()) +
                s.n_rows.to_double() * 0.1
              {
                cpu_cost: cost,
                io_cost: cost * 0.1,
                total_cost: cost * 1.1,
                cardinality: s.n_rows / 10,
              }
            }
          }
        None =>
          {
            cpu_cost: 1000.0,
            io_cost: 1000.0,
            total_cost: 2000.0,
            cardinality: 1000,
          }
      }
    }
    Filter(_, child) => {
      let child_cost = estimate_cost(child, stats)
      let card = child_cost.cardinality / 3 // Selectivity ~0.33
      {
        cpu_cost: child_cost.cpu_cost + child_cost.cardinality.to_double(),
        io_cost: child_cost.io_cost,
        total_cost: child_cost.total_cost + child_cost.cardinality.to_double(),
        cardinality: card,
      }
    }
    Join(join_method, _, left, right) => {
      let lc = estimate_cost(left, stats)
      let rc = estimate_cost(right, stats)
      match join_method {
        HashJoin => {
          let cost = lc.total_cost +
            rc.total_cost +
            lc.cardinality.to_double() +
            rc.cardinality.to_double()
          {
            cpu_cost: lc.cpu_cost +
            rc.cpu_cost +
            lc.cardinality.to_double() +
            rc.cardinality.to_double(),
            io_cost: lc.io_cost + rc.io_cost,
            total_cost: cost,
            cardinality: lc.cardinality.max(rc.cardinality),
          }
        }
        NestedLoopJoin => {
          let cost = lc.total_cost + rc.total_cost * lc.cardinality.to_double()
          {
            cpu_cost: lc.cpu_cost + rc.cpu_cost * lc.cardinality.to_double(),
            io_cost: lc.io_cost + rc.io_cost * lc.cardinality.to_double(),
            total_cost: cost,
            cardinality: lc.cardinality.max(rc.cardinality),
          }
        }
        MergeJoin => {
          let sort_cost = lc.cardinality.to_double() *
            log_double(lc.cardinality.to_double()) +
            rc.cardinality.to_double() * log_double(rc.cardinality.to_double())
          let cost = lc.total_cost + rc.total_cost + sort_cost
          {
            cpu_cost: lc.cpu_cost + rc.cpu_cost + sort_cost,
            io_cost: lc.io_cost + rc.io_cost,
            total_cost: cost,
            cardinality: lc.cardinality.max(rc.cardinality),
          }
        }
      }
    }
    Sort(_, child) => {
      let cc = estimate_cost(child, stats)
      let sort_cost = cc.cardinality.to_double() *
        log_double(cc.cardinality.to_double())
      {
        cpu_cost: cc.cpu_cost + sort_cost,
        io_cost: cc.io_cost,
        total_cost: cc.total_cost + sort_cost,
        cardinality: cc.cardinality,
      }
    }
    Project(_, child) => {
      let cc = estimate_cost(child, stats)
      {
        cpu_cost: cc.cpu_cost + cc.cardinality.to_double() * 0.01,
        io_cost: cc.io_cost,
        total_cost: cc.total_cost + cc.cardinality.to_double() * 0.01,
        cardinality: cc.cardinality,
      }
    }
  }
}

///|
/// Choose the best join method based on estimated costs.
pub fn choose_join_method(
  left_stats : TableStats,
  right_stats : TableStats,
) -> JoinMethod {
  // If one side is small, use hash join
  if left_stats.n_rows < 1000 || right_stats.n_rows < 1000 {
    HashJoin
  } else if left_stats.n_rows * right_stats.n_rows < 100000 {
    NestedLoopJoin
  } else {
    MergeJoin
  }
}

///|
/// Choose scan method based on table stats and selectivity.
pub fn choose_scan_method(
  _table : TableStats,
  has_index : Bool,
  selectivity : Double,
) -> ScanMethod {
  if has_index && selectivity < 0.1 {
    IndexScan
  } else {
    FullScan
  }
}

///|
/// Build a sample plan tree for API documentation and type validation.
fn _sample_plan() -> PlanNode {
  let t : TableStats = { name: "t", n_rows: 100, n_pages: 10, indexes: [], }
  let _ = t
  Project(
    ["id"],
    Sort(
      "id",
      Filter(
        "id > 0",
        Join(
          HashJoin,
          "a.id=b.id",
          TableScan("a", FullScan),
          TableScan("b", IndexScan),
        ),
      ),
    ),
  )
}
