// White-box tests for db/query_planner
//
// Exercises estimate_cost over every PlanNode variant, plus
// choose_join_method and choose_scan_method. Note: choose_join_method's
// NestedLoopJoin branch is currently unreachable (see report); only
// HashJoin and MergeJoin are producible from the implementation.

///|
fn stats(
  name : String,
  n_rows : Int,
  n_pages : Int,
  indexes : Array[String],
) -> TableStats {
  { name, n_rows, n_pages, indexes, }
}

// Enums here don't implement Eq/Debug, so compare via a stable Int mapping.

///|
fn scan_method_id(m : ScanMethod) -> Int {
  match m {
    FullScan => 0
    IndexScan => 1
  }
}

///|
fn join_method_id(m : JoinMethod) -> Int {
  match m {
    HashJoin => 0
    NestedLoopJoin => 1
    MergeJoin => 2
  }
}

// ---------------------------------------------------------------------------
// estimate_cost: TableScan
// ---------------------------------------------------------------------------

///|
test "qp_table_scan_full" {
  let s = stats("t", 100, 10, [])
  let c = estimate_cost(TableScan("t", FullScan), [s])
  assert_eq(c.cpu_cost, 100.0)
  assert_eq(c.io_cost, 10.0)
  assert_eq(c.total_cost, 110.0)
  assert_eq(c.cardinality, 100)
}

///|
test "qp_table_scan_index" {
  let s = stats("t", 100, 10, ["idx"])
  let c = estimate_cost(TableScan("t", IndexScan), [s])
  // cardinality = n_rows / 10
  assert_eq(c.cardinality, 10)
  // exact relationships from the cost formula
  assert_true(c.io_cost == c.cpu_cost * 0.1)
  assert_true(c.total_cost == c.cpu_cost * 1.1)
  assert_true(c.total_cost > 0.0)
}

///|
test "qp_table_scan_unknown_table" {
  let c = estimate_cost(TableScan("missing", FullScan), [])
  assert_eq(c.cpu_cost, 1000.0)
  assert_eq(c.io_cost, 1000.0)
  assert_eq(c.total_cost, 2000.0)
  assert_eq(c.cardinality, 1000)
}

// ---------------------------------------------------------------------------
// estimate_cost: Filter
// ---------------------------------------------------------------------------

///|
test "qp_filter_selectivity" {
  let s = stats("t", 300, 10, [])
  let c = estimate_cost(Filter("p", TableScan("t", FullScan)), [s])
  // child cardinality 300 -> filter cardinality 100 (selectivity ~0.33)
  assert_eq(c.cardinality, 100)
  // child (FullScan 300 rows) total = 300 + 10 = 310
  // filter total = child.total + child.cardinality = 310 + 300 = 610
  assert_eq(c.total_cost, 610.0)
}

// ---------------------------------------------------------------------------
// estimate_cost: Join
// ---------------------------------------------------------------------------

///|
test "qp_join_hash" {
  let s = stats("a", 100, 10, [])
  let t = stats("b", 50, 5, [])
  let node = Join(
    HashJoin,
    "a.id=b.id",
    TableScan("a", FullScan),
    TableScan("b", FullScan),
  )
  let c = estimate_cost(node, [s, t])
  // cardinality = max(100, 50) = 100
  assert_eq(c.cardinality, 100)
  // lc.total = 110, rc.total = 55, lc.card = 100, rc.card = 50
  // total = 110 + 55 + 100 + 50 = 315
  assert_eq(c.total_cost, 315.0)
}

///|
test "qp_join_nested_loop" {
  let s = stats("a", 100, 10, [])
  let t = stats("b", 50, 5, [])
  let node = Join(
    NestedLoopJoin,
    "a.id=b.id",
    TableScan("a", FullScan),
    TableScan("b", FullScan),
  )
  let c = estimate_cost(node, [s, t])
  assert_eq(c.cardinality, 100)
  // total = lc.total + rc.total * lc.card = 110 + 55 * 100 = 5610
  assert_eq(c.total_cost, 5610.0)
}

///|
test "qp_join_merge" {
  let s = stats("a", 100, 10, [])
  let t = stats("b", 50, 5, [])
  let node = Join(
    MergeJoin,
    "a.id=b.id",
    TableScan("a", FullScan),
    TableScan("b", FullScan),
  )
  let c = estimate_cost(node, [s, t])
  assert_eq(c.cardinality, 100)
  let lc = estimate_cost(TableScan("a", FullScan), [s])
  let rc = estimate_cost(TableScan("b", FullScan), [t])
  // merge join adds sort cost, so total exceeds the sum of scan totals
  assert_true(c.total_cost > lc.total_cost + rc.total_cost)
}

// ---------------------------------------------------------------------------
// estimate_cost: Sort / Project
// ---------------------------------------------------------------------------

///|
test "qp_sort" {
  let s = stats("a", 100, 10, [])
  let node = Sort("a.id", TableScan("a", FullScan))
  let c = estimate_cost(node, [s])
  assert_eq(c.cardinality, 100)
  let cc = estimate_cost(TableScan("a", FullScan), [s])
  // sort adds cost
  assert_true(c.total_cost > cc.total_cost)
}

///|
test "qp_project" {
  let s = stats("a", 100, 10, [])
  let node = Project(["a.id", "a.v"], TableScan("a", FullScan))
  let c = estimate_cost(node, [s])
  assert_eq(c.cardinality, 100)
  // child total = 110, project adds card * 0.01 = 1.0 -> 111.0
  assert_eq(c.total_cost, 111.0)
}

// ---------------------------------------------------------------------------
// choose_join_method
// ---------------------------------------------------------------------------

///|
test "qp_choose_join_method_small_side" {
  let small = stats("a", 100, 10, [])
  let big = stats("b", 5000, 100, [])
  assert_eq(join_method_id(choose_join_method(small, big)), 0) // HashJoin
  assert_eq(join_method_id(choose_join_method(big, small)), 0) // HashJoin
}

///|
test "qp_choose_join_method_large_both" {
  let a = stats("a", 5000, 100, [])
  let b = stats("b", 5000, 100, [])
  // both >= 1000 -> product >= 1e6 > 1e5 -> MergeJoin
  assert_eq(join_method_id(choose_join_method(a, b)), 2) // MergeJoin
}

// ---------------------------------------------------------------------------
// choose_scan_method
// ---------------------------------------------------------------------------

///|
test "qp_choose_scan_index_selective" {
  let t = stats("a", 100, 10, ["i"])
  assert_eq(scan_method_id(choose_scan_method(t, true, 0.05)), 1) // IndexScan
}

///|
test "qp_choose_scan_index_not_selective" {
  let t = stats("a", 100, 10, ["i"])
  assert_eq(scan_method_id(choose_scan_method(t, true, 0.5)), 0) // FullScan
}

///|
test "qp_choose_scan_no_index" {
  let t = stats("a", 100, 10, [])
  assert_eq(scan_method_id(choose_scan_method(t, false, 0.01)), 0) // FullScan
  assert_eq(scan_method_id(choose_scan_method(t, false, 0.5)), 0) // FullScan
}
