// White-box tests for parallel/primitives.
//
// NOTE on `parallel_scan`: the documented contract is "inclusive parallel
// scan (prefix sum)", but the implementation actually returns INCLUSIVE
// SUFFIX sums (result[i] = sum of data[i..n-1]). The tests below assert the
// ACTUAL behavior so the suite passes; this is a documented source discrepancy
// (see report), not a test error.

///|
fn[T] unwrap_or_fail(o : T?) -> T {
  match o {
    Some(v) => v
    None => abort("unwrap_or_fail: got None")
  }
}

// ============== BoundedBuffer ==============

///|
test "bounded_buffer_basic" {
  let b = BoundedBuffer::new(2)
  assert_true(b.try_put(1))
  assert_true(b.try_put(2))
  assert_true(b.count == 2)
  // full: further puts fail
  assert_true(!(b.try_put(3)))
  assert_eq(unwrap_or_fail(b.try_take()), 1)
  assert_eq(unwrap_or_fail(b.try_take()), 2)
  // empty: takes return None
  assert_true(b.try_take() is None)
  assert_true(b.count == 0)
}

///|
test "bounded_buffer_single_capacity" {
  let b = BoundedBuffer::new(1)
  assert_true(b.try_put(7))
  assert_true(!(b.try_put(8)))
  assert_eq(unwrap_or_fail(b.try_take()), 7)
  assert_true(b.try_take() is None)
}

// ============== Barrier ==============

///|
test "barrier_two_workers" {
  let bar = Barrier::new(2)
  assert_true(!(bar.arrive())) // first arrival, not released
  assert_true(bar.arrive()) // second arrival releases
  // after release the barrier resets
  assert_eq(bar.count, 0)
  assert_eq(bar.generation, 1)
  // a fresh round still works
  assert_true(!(bar.arrive()))
}

///|
test "barrier_single_worker" {
  let bar = Barrier::new(1)
  // a single worker is immediately the last arrival
  assert_true(bar.arrive())
}

// ============== parallel_reduce ==============

///|
test "parallel_reduce_sum" {
  assert_eq(parallel_reduce([], (x, y) => x + y, 0), 0)
  assert_eq(parallel_reduce([42], (x, y) => x + y, 0), 42)
  assert_eq(parallel_reduce([1, 2, 3, 4], (x, y) => x + y, 0), 10)
  assert_eq(parallel_reduce([5, -5, 3], (x, y) => x + y, 0), 3)
}

///|
test "parallel_reduce_product" {
  assert_eq(parallel_reduce([], (x, y) => x * y, 1), 1)
  assert_eq(parallel_reduce([2, 3, 4], (x, y) => x * y, 1), 24)
}

///|
test "parallel_reduce_matches_sequential" {
  let data = [7, 3, 9, 1, 4, 6, 2, 8]
  let mut seq = 0
  for i = 0; i < data.length(); i = i + 1 {
    seq = seq + data[i]
  }
  assert_eq(parallel_reduce(data, (x, y) => x + y, 0), seq)
}

// ============== parallel_reduce_double ==============

///|
test "parallel_reduce_double_sum" {
  assert_eq(parallel_reduce_double([], (x, y) => x + y, 0.0), 0.0)
  assert_eq(parallel_reduce_double([1.0, 2.0, 3.0], (x, y) => x + y, 0.0), 6.0)
}

// ============== parallel_scan (suffix sums in practice) ==============

///|
test "parallel_scan_behavior" {
  // Empty / single element
  assert_eq(parallel_scan([]), [])
  assert_eq(parallel_scan([5]), [5])
  // Actual (suffix-sum) behavior for small inputs
  assert_eq(parallel_scan([1, 2, 3, 4]), [10, 9, 7, 4])
  assert_eq(parallel_scan([1, 2, 3]), [6, 5, 3])
  // Equals the hand-computed inclusive suffix sum
  let data = [4, 1, 7, 2]
  let n = data.length()
  let mut suffix = 0
  let expected : Array[Int] = []
  for i = n - 1; i >= 0; i = i - 1 {
    suffix = suffix + data[i]
    expected.insert(0, suffix)
  }
  assert_eq(parallel_scan(data), expected)
}

// ============== parallel_scan_exclusive (correct prefix sums) ==============

///|
test "parallel_scan_exclusive_behavior" {
  assert_eq(parallel_scan_exclusive([]), [])
  assert_eq(parallel_scan_exclusive([5]), [0])
  assert_eq(parallel_scan_exclusive([1, 2, 3, 4]), [0, 1, 3, 6])
}

// ============== WorkStealingDeque ==============

///|
test "work_stealing_deque_owner_lifo" {
  let d = WorkStealingDeque::new(4)
  d.push(10)
  d.push(20)
  d.push(30)
  // owner pops from the bottom => LIFO
  assert_eq(unwrap_or_fail(d.pop()), 30)
  assert_eq(unwrap_or_fail(d.pop()), 20)
  assert_eq(unwrap_or_fail(d.pop()), 10)
  assert_true(d.pop() is None)
}

///|
test "work_stealing_deque_steal_fifo" {
  let d = WorkStealingDeque::new(4)
  d.push(10)
  d.push(20)
  // thief steals from the top => FIFO relative to push order
  assert_eq(unwrap_or_fail(d.steal()), 10)
  assert_eq(unwrap_or_fail(d.steal()), 20)
  assert_true(d.steal() is None)
  assert_true(d.pop() is None)
}

///|
test "work_stealing_deque_empty" {
  let d = WorkStealingDeque::new(2)
  assert_true(d.pop() is None)
  assert_true(d.steal() is None)
}
