/// Parallel Primitives — Producer-Consumer, Barrier, Reduction, Scan
///
/// Provides building blocks for parallel/distributed computation
/// in a single-threaded simulation. These primitives demonstrate the
/// algorithmic patterns used in high-performance computing.
///
/// `proof-enabled` is `false`.

// ============== Producer-Consumer ==============

///|
/// Bounded buffer for producer-consumer pattern.
pub struct BoundedBuffer {
  buf : Array[Int]
  mut head : Int
  mut tail : Int
  mut count : Int
  capacity : Int
}

///|
/// Create a bounded buffer.
pub fn BoundedBuffer::new(capacity : Int) -> BoundedBuffer {
  { buf: Array::make(capacity, 0), head: 0, tail: 0, count: 0, capacity, }
}

///|
/// Try to put an item into the buffer (non-blocking).
pub fn BoundedBuffer::try_put(self : BoundedBuffer, item : Int) -> Bool {
  if self.count >= self.capacity {
    return false
  }
  self.buf[self.tail] = item
  self.tail = (self.tail + 1) % self.capacity
  self.count = self.count + 1
  true
}

///|
/// Try to take an item from the buffer (non-blocking).
pub fn BoundedBuffer::try_take(self : BoundedBuffer) -> Int? {
  if self.count == 0 {
    return None
  }
  let item = self.buf[self.head]
  self.head = (self.head + 1) % self.capacity
  self.count = self.count - 1
  Some(item)
}

// ============== Barrier ==============

///|
/// A barrier that waits for n workers to arrive before proceeding.
pub struct Barrier {
  mut count : Int
  mut generation : Int
  n_workers : Int
}

///|
/// Create a barrier for n workers.
pub fn Barrier::new(n_workers : Int) -> Barrier {
  { count: 0, generation: 0, n_workers, }
}

///|
/// Arrive at the barrier. Returns true if this was the last arrival
/// (which triggers the barrier release).
pub fn Barrier::arrive(self : Barrier) -> Bool {
  self.count = self.count + 1
  if self.count >= self.n_workers {
    self.count = 0
    self.generation = self.generation + 1
    return true
  }
  false
}

// ============== Parallel Reduction ==============

///|
/// Parallel reduction (sum) using a tree-based approach.
///
/// Reduces an array of values using the given binary operator.
/// The tree structure ensures O(log n) depth, suitable for parallel
/// execution.
pub fn parallel_reduce(
  data : Array[Int],
  op : (Int, Int) -> Int,
  identity : Int,
) -> Int {
  if data.length() == 0 {
    return identity
  }
  if data.length() == 1 {
    return data[0]
  }
  // Tree reduction: split in half, reduce each half, combine
  let mid = data.length() / 2
  let left : Array[Int] = []
  let right : Array[Int] = []
  for i = 0; i < mid; i = i + 1 {
    left.push(data[i])
  }
  for i = mid; i < data.length(); i = i + 1 {
    right.push(data[i])
  }
  let l_result = parallel_reduce(left, op, identity)
  let r_result = parallel_reduce(right, op, identity)
  op(l_result, r_result)
}

///|
/// Parallel reduction for doubles.
pub fn parallel_reduce_double(
  data : Array[Double],
  op : (Double, Double) -> Double,
  identity : Double,
) -> Double {
  if data.length() == 0 {
    return identity
  }
  if data.length() == 1 {
    return data[0]
  }
  let mid = data.length() / 2
  let left : Array[Double] = []
  let right : Array[Double] = []
  for i = 0; i < mid; i = i + 1 {
    left.push(data[i])
  }
  for i = mid; i < data.length(); i = i + 1 {
    right.push(data[i])
  }
  let l_result = parallel_reduce_double(left, op, identity)
  let r_result = parallel_reduce_double(right, op, identity)
  op(l_result, r_result)
}

// ============== Parallel Scan (Prefix Sum) ==============

///|
/// Inclusive parallel scan (prefix sum) using Blelloch's algorithm.
///
/// This two-phase algorithm (up-sweep + down-sweep) has O(n) work
/// and O(log n) depth, making it suitable for parallel execution.
///
/// ## Phases
/// 1. Up-sweep: reduce phase that builds a binary tree of partial sums
/// 2. Down-sweep: distribute phase that computes prefix sums
pub fn parallel_scan(data : Array[Int]) -> Array[Int] {
  let n = data.length()
  if n == 0 {
    return []
  }
  if n == 1 {
    return [data[0]]
  }
  // Round up to next power of 2
  let mut m = 1
  while m < n {
    m = m * 2
  }
  // Pad with identity (0 for sum)
  let tree = Array::make(m, 0)
  for i = 0; i < n; i = i + 1 {
    tree[i] = data[i]
  }
  // Up-sweep (reduction phase)
  let mut d = 1
  while d < m {
    let mut i = 0
    while i < m {
      tree[i] = tree[i] + tree[i + d]
      i = i + 2 * d
    }
    d = d * 2
  }
  // tree[0] now holds the total sum
  // Down-sweep phase
  tree[0] = 0 // Identity for inclusive scan adjustment
  d = m / 2
  while d > 0 {
    let mut i = 0
    while i < m {
      let temp = tree[i]
      tree[i] = tree[i] + tree[i + d] // Left child gets sum
      tree[i + d] = temp // Right child gets left's value
      i = i + 2 * d
    }
    d = d / 2
  }
  // Extract result (shift by 1 for inclusive scan)
  let result = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    result[i] = tree[i] + data[i]
  }
  result
}

///|
/// Exclusive parallel scan (prefix sum).
pub fn parallel_scan_exclusive(data : Array[Int]) -> Array[Int] {
  let n = data.length()
  if n == 0 {
    return []
  }
  // Result[i] = sum of data[0..i-1]
  let result = Array::make(n + 1, 0)
  for i = 0; i < n; i = i + 1 {
    result[i + 1] = result[i] + data[i]
  }
  // Truncate to n elements (exclusive scan)
  let output = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    output[i] = result[i]
  }
  output
}

// ============== Work Stealing ==============

///|
/// Simple work-stealing deque (single-owner, many-thieves).
pub struct WorkStealingDeque {
  buf : Array[Int?]
  mut top : Int
  mut bottom : Int
  capacity : Int
}

///|
/// Create a work-stealing deque.
pub fn WorkStealingDeque::new(capacity : Int) -> WorkStealingDeque {
  { buf: Array::make(capacity, None), top: 0, bottom: 0, capacity, }
}

///|
/// Push work (called by owner).
pub fn WorkStealingDeque::push(self : WorkStealingDeque, work : Int) -> Unit {
  self.buf[self.bottom % self.capacity] = Some(work)
  self.bottom = self.bottom + 1
}

///|
/// Pop work from the bottom (called by owner).
pub fn WorkStealingDeque::pop(self : WorkStealingDeque) -> Int? {
  if self.bottom == self.top {
    return None
  }
  self.bottom = self.bottom - 1
  let work = self.buf[self.bottom % self.capacity]
  self.buf[self.bottom % self.capacity] = None
  work
}

///|
/// Steal work from the top (called by other workers).
pub fn WorkStealingDeque::steal(self : WorkStealingDeque) -> Int? {
  if self.top >= self.bottom {
    return None
  }
  let work = self.buf[self.top % self.capacity]
  self.top = self.top + 1
  work
}
