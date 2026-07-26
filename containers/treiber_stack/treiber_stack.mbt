/// Treiber Stack — Lock-Free LIFO Stack (Single-Threaded Simulation).
///
/// The Treiber stack is the foundational lock-free concurrent stack
/// algorithm: a singly-linked list where push and pop are done via
/// compare-and-swap (CAS) on the head pointer.
///
/// ## Algorithm
///
/// ### Push(item)
///   1. Allocate node `n` with `n.value = item`.
///   2. `n.next = head`  (read current head)
///   3. **CAS**: `head: old_head -> n` (if head still == old_head)
///
/// ### Pop() -> T?
///   1. `old_head = head`
///   2. If `old_head == NULL`, return `None`.
///   3. Read `value = old_head.value`, `next = old_head.next`
///   4. **CAS**: `head: old_head -> next`
///
/// In a multi-threaded setting, ABA can occur; production implementations
/// use tagged pointers or hazard pointers. This simulation is
/// single-threaded (MoonBit compiles to Wasm/JS), so CAS always succeeds.
///
/// For **real mutual exclusion** in MoonBit's async runtime today, use
/// `@async.Mutex` from `moonbitlang/async`. See `containers/concurrent`'s
/// `AsyncQueue[T]` for a mutex-protected production variant.
///
/// ## Complexity
/// - Time: O(1) push and pop.
/// - Space: O(n) for n elements.
///
/// Reference: R.K. Treiber, "Systems programming: Coping with parallelism"
/// (IBM, 1986).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// A bounded Treiber stack using a pre-allocated node pool.
///
/// Nodes live in a `FixedArray` pool; no per-operation heap allocation.
/// `push` returns `false` when the pool is exhausted.
pub struct TreiberStack[T] {
  priv values : FixedArray[T?]
  priv nexts : FixedArray[Int]
  priv free_stack : FixedArray[Int]
  priv mut free_top : Int
  priv mut head : Int
  priv mut count : Int
  priv mut cas_count : Int
  priv capacity : Int
}

///|
/// Create a bounded Treiber stack with the given `capacity`.
///
/// Negative capacity is clamped to 0. Internally allocates `capacity`
/// nodes in a pool for O(1) push/pop with zero per-operation allocation.
pub fn[T] treiber_stack_new(capacity : Int) -> TreiberStack[T] {
  let cap = if capacity < 0 { 0 } else { capacity }
  let values : FixedArray[T?] = FixedArray::make(cap, None)
  let nexts = FixedArray::make(cap, -1)
  let free_stack = FixedArray::make(cap, 0)
  for i = 0; i < cap; i = i + 1 {
    free_stack[i] = cap - 1 - i
  }
  {
    values,
    nexts,
    free_stack,
    free_top: cap,
    head: -1,
    count: 0,
    cas_count: 0,
    capacity: cap,
  }
}

///|
/// Push `item` onto the stack.
///
/// Returns `true` on success, `false` if the pool is full.
///
/// Simulated CAS: `head: old_head -> new_node`.
pub fn[T] treiber_stack_push(stack : TreiberStack[T], item : T) -> Bool {
  if stack.free_top == 0 {
    return false
  }
  stack.free_top = stack.free_top - 1
  let node = stack.free_stack[stack.free_top]
  stack.values[node] = Some(item)
  // CAS#1: read head, set new node's next, CAS head.
  let old_head = stack.head
  stack.nexts[node] = old_head
  stack.cas_count = stack.cas_count + 1
  stack.head = node
  stack.count = stack.count + 1
  true
}

///|
/// Pop the top element from the stack.
///
/// Returns `Some(item)` on success, `None` if the stack is empty.
///
/// Simulated CAS: `head: old_head -> old_head.next`.
pub fn[T] treiber_stack_pop(stack : TreiberStack[T]) -> T? {
  let old_head = stack.head
  if old_head < 0 {
    return None
  }
  let value = stack.values[old_head]
  let next = stack.nexts[old_head]
  stack.cas_count = stack.cas_count + 1
  stack.head = next
  stack.values[old_head] = None
  stack.free_stack[stack.free_top] = old_head
  stack.free_top = stack.free_top + 1
  stack.count = stack.count - 1
  value
}

///|
/// Number of elements. O(1).
pub fn[T] treiber_stack_size(stack : TreiberStack[T]) -> Int {
  stack.count
}

///|
/// True if the stack is empty. O(1).
pub fn[T] treiber_stack_is_empty(stack : TreiberStack[T]) -> Bool {
  stack.head < 0
}

///|
/// True if the stack is full (pool exhausted). O(1).
pub fn[T] treiber_stack_is_full(stack : TreiberStack[T]) -> Bool {
  stack.free_top == 0
}

///|
/// Maximum capacity. O(1).
pub fn[T] treiber_stack_capacity(stack : TreiberStack[T]) -> Int {
  stack.capacity
}

///|
/// Total simulated CAS operations performed. O(1).
pub fn[T] treiber_stack_cas_count(stack : TreiberStack[T]) -> Int {
  stack.cas_count
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "treiber_stack: basic push and pop" {
  let s : TreiberStack[Int] = treiber_stack_new(4)
  assert_true(treiber_stack_is_empty(s))
  assert_eq(treiber_stack_pop(s), None)
  assert_true(treiber_stack_push(s, 10))
  assert_true(treiber_stack_push(s, 20))
  assert_eq(treiber_stack_size(s), 2)
  assert_eq(treiber_stack_pop(s), Some(20))
  assert_eq(treiber_stack_pop(s), Some(10))
  assert_true(treiber_stack_is_empty(s))
}

///|
test "treiber_stack: LIFO order" {
  let s : TreiberStack[Int] = treiber_stack_new(100)
  for i = 0; i < 50; i = i + 1 {
    assert_true(treiber_stack_push(s, i))
  }
  for i = 49; i >= 0; i = i - 1 {
    assert_eq(treiber_stack_pop(s), Some(i))
  }
  assert_true(treiber_stack_is_empty(s))
}

///|
test "treiber_stack: full stack" {
  let s : TreiberStack[Int] = treiber_stack_new(3)
  assert_true(treiber_stack_push(s, 1))
  assert_true(treiber_stack_push(s, 2))
  assert_true(treiber_stack_push(s, 3))
  assert_true(treiber_stack_is_full(s))
  assert_false(treiber_stack_push(s, 99))
  assert_eq(treiber_stack_pop(s), Some(3))
  assert_false(treiber_stack_is_full(s))
  assert_true(treiber_stack_push(s, 99))
}

///|
test "treiber_stack: cas count" {
  let s : TreiberStack[Int] = treiber_stack_new(10)
  ignore(treiber_stack_push(s, 1))
  ignore(treiber_stack_push(s, 2))
  ignore(treiber_stack_pop(s))
  assert_eq(treiber_stack_cas_count(s), 3)
}

///|
test "treiber_stack: generic with String" {
  let s : TreiberStack[String] = treiber_stack_new(5)
  ignore(treiber_stack_push(s, "a"))
  ignore(treiber_stack_push(s, "b"))
  ignore(treiber_stack_push(s, "c"))
  assert_eq(treiber_stack_pop(s), Some("c"))
  assert_eq(treiber_stack_pop(s), Some("b"))
  assert_eq(treiber_stack_pop(s), Some("a"))
}

///|
test "treiber_stack: interleave push and pop" {
  let s : TreiberStack[Int] = treiber_stack_new(10)
  ignore(treiber_stack_push(s, 1))
  ignore(treiber_stack_push(s, 2))
  assert_eq(treiber_stack_pop(s), Some(2))
  ignore(treiber_stack_push(s, 3))
  assert_eq(treiber_stack_pop(s), Some(3))
  assert_eq(treiber_stack_pop(s), Some(1))
  assert_true(treiber_stack_is_empty(s))
}
