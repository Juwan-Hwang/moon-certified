/// Mo's Algorithm for offline range queries.
///
/// Mo's algorithm processes a batch of range queries `[l, r]` on an array
/// by reordering them so that consecutive queries share most of their range,
/// allowing an incremental "add element" / "remove element" approach.
///
/// ## Algorithm
///
/// 1. Divide the array into blocks of size `√n`.
/// 2. Sort queries by `(l / block_size, r)` — queries in the same block
///    share a similar `l`, so we sort by `r` within each block.
///    For even blocks, sort `r` ascending; for odd blocks, descending.
///    This "hilbert-curve-like" ordering reduces pointer movement.
/// 3. Process queries in order, maintaining a sliding window `[cur_l, cur_r]`
///    and calling `add`/`remove` callbacks to update the running answer.
///
/// ## Complexity
///
/// - Sorting: O(Q log Q)
/// - Processing: O((N + Q) · √N) with O(1) add/remove.
///
/// ## Usage
///
/// The caller provides `add(idx)` and `remove(idx)` callbacks and an initial
/// answer. The algorithm returns the answers in the original query order.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A range query `[l, r]` (inclusive, 0-indexed) with its original index.
pub struct Query {
  l : Int
  r : Int
  idx : Int
}

///|
/// Construct a query.
pub fn query(l : Int, r : Int, idx : Int) -> Query {
  { l, r, idx }
}

// ---------------------------------------------------------------------------
// Mo's algorithm
// ---------------------------------------------------------------------------

///|
/// Execute a batch of range queries using Mo's algorithm.
///
/// # Parameters
/// - `n`: array length.
/// - `queries`: the queries to process (will be reordered internally).
/// - `add`: called with an index to add `arr[idx]` to the current window.
/// - `remove`: called with an index to remove `arr[idx]` from the window.
/// - `get_answer`: called to snapshot the current answer.
/// - `initial_answer`: the answer for an empty window.
///
/// # Returns
/// An array of answers, indexed by the original query order.
///
/// # Complexity
/// O((N + Q) · √N) with O(1) add/remove.
pub fn[T] mo(
  n : Int,
  queries : Array[Query],
  add : (Int) -> Unit,
  remove : (Int) -> Unit,
  get_answer : () -> T,
  initial_answer : T,
) -> Array[T] {
  let q = queries.length()
  if q == 0 {
    return []
  }
  let block_size = if n > 0 {
    // √n, at least 1.
    let mut bs = 1
    while bs * bs < n {
      bs = bs + 1
    }
    bs
  } else {
    1
  }
  // Copy and sort queries.
  let sorted : Array[Query] = []
  for i = 0; i < q; i = i + 1 {
    sorted.push(queries[i])
  }
  sorted.sort_by(fn(a, b) {
    let ba = a.l / block_size
    let bb = b.l / block_size
    if ba != bb {
      ba - bb
      // Odd blocks: sort r descending; even blocks: ascending.
    } else if ba % 2 == 0 {
      a.r - b.r
    } else {
      b.r - a.r
    }
  })
  // Process queries.
  let answers : Array[T] = []
  for i = 0; i < q; i = i + 1 {
    answers.push(initial_answer)
  }
  let mut cur_l = 0
  let mut cur_r = -1 // empty window
  for i = 0; i < q; i = i + 1 {
    let ql = sorted[i].l
    let qr = sorted[i].r
    // Expand/contract the window to match [ql, qr].
    while cur_l > ql {
      cur_l = cur_l - 1
      add(cur_l)
    }
    while cur_r < qr {
      cur_r = cur_r + 1
      add(cur_r)
    }
    while cur_l < ql {
      remove(cur_l)
      cur_l = cur_l + 1
    }
    while cur_r > qr {
      remove(cur_r)
      cur_r = cur_r - 1
    }
    answers[sorted[i].idx] = get_answer()
  }
  answers
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "mo: range sum queries" {
  // Array: [3, 1, 4, 1, 5, 9, 2, 6]
  let arr = [3, 1, 4, 1, 5, 9, 2, 6]
  let n = arr.length()
  let queries : Array[Query] = [
    query(0, 3, 0), // 3+1+4+1 = 9
    query(2, 5, 1), // 4+1+5+9 = 19
    query(0, 7, 2), // 3+1+4+1+5+9+2+6 = 31
    query(4, 4, 3), // 5
    query(1, 6, 4), // 1+4+1+5+9+2 = 22
  ]
  let mut current_sum = 0
  let add = fn(idx) { current_sum = current_sum + arr[idx] }
  let remove = fn(idx) { current_sum = current_sum - arr[idx] }
  let get_answer = fn() { current_sum }
  let answers = mo(n, queries, add, remove, get_answer, 0)
  assert_eq(answers[0], 9)
  assert_eq(answers[1], 19)
  assert_eq(answers[2], 31)
  assert_eq(answers[3], 5)
  assert_eq(answers[4], 22)
}

///|
test "mo: range distinct count" {
  // Array: [1, 2, 1, 3, 2, 1, 4]
  let arr = [1, 2, 1, 3, 2, 1, 4]
  let n = arr.length()
  let freq = FixedArray::make(5, 0) // values are 1..4
  let mut distinct = 0
  let add = fn(idx) {
    let v = arr[idx]
    if freq[v] == 0 {
      distinct = distinct + 1
    }
    freq[v] = freq[v] + 1
  }
  let remove = fn(idx) {
    let v = arr[idx]
    freq[v] = freq[v] - 1
    if freq[v] == 0 {
      distinct = distinct - 1
    }
  }
  let get_answer = fn() { distinct }
  let queries : Array[Query] = [
    query(0, 6, 0), // all: {1,2,3,4} = 4
    query(0, 2, 1), // {1,2} = 2
    query(2, 4, 2), // {1,3,2} = 3
    query(5, 5, 3), // {1} = 1
    query(0, 0, 4), // {1} = 1
  ]
  let answers = mo(n, queries, add, remove, get_answer, 0)
  assert_eq(answers[0], 4)
  assert_eq(answers[1], 2)
  assert_eq(answers[2], 3)
  assert_eq(answers[3], 1)
  assert_eq(answers[4], 1)
}

///|
test "mo: single element queries" {
  let arr = [42, 17, 99]
  let n = arr.length()
  let mut sum = 0
  let queries : Array[Query] = [query(0, 0, 0), query(1, 1, 1), query(2, 2, 2)]
  let answers = mo(
    n,
    queries,
    fn(idx) { sum = sum + arr[idx] },
    fn(idx) { sum = sum - arr[idx] },
    fn() { sum },
    0,
  )
  assert_eq(answers[0], 42)
  assert_eq(answers[1], 17)
  assert_eq(answers[2], 99)
}

///|
test "mo: full range query" {
  let arr = [1, 2, 3, 4, 5]
  let n = arr.length()
  let mut sum = 0
  let queries : Array[Query] = [query(0, 4, 0)]
  let answers = mo(
    n,
    queries,
    fn(idx) { sum = sum + arr[idx] },
    fn(idx) { sum = sum - arr[idx] },
    fn() { sum },
    0,
  )
  assert_eq(answers[0], 15)
}

///|
test "mo: overlapping queries" {
  let arr = [5, 3, 8, 1, 9, 2, 7, 4, 6]
  let n = arr.length()
  let mut sum = 0
  let queries : Array[Query] = [
    query(0, 8, 0), // 45
    query(0, 4, 1), // 5+3+8+1+9 = 26
    query(4, 8, 2), // 9+2+7+4+6 = 28
    query(2, 6, 3), // 8+1+9+2+7 = 27
    query(3, 5, 4), // 1+9+2 = 12
  ]
  let answers = mo(
    n,
    queries,
    fn(idx) { sum = sum + arr[idx] },
    fn(idx) { sum = sum - arr[idx] },
    fn() { sum },
    0,
  )
  assert_eq(answers[0], 45)
  assert_eq(answers[1], 26)
  assert_eq(answers[2], 28)
  assert_eq(answers[3], 27)
  assert_eq(answers[4], 12)
}

///|
test "mo: stress test 1000 elements" {
  let n = 1000
  let arr : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    arr.push((i * 7 + 3) % 100)
  }
  let queries : Array[Query] = []
  // 100 random-ish queries.
  for i = 0; i < 100; i = i + 1 {
    let l = (i * 13 + 7) % n
    let r = (i * 17 + 11) % n
    let (ql, qr) = if l <= r { (l, r) } else { (r, l) }
    queries.push(query(ql, qr, i))
  }
  let mut sum = 0
  let answers = mo(
    n,
    queries,
    fn(idx) { sum = sum + arr[idx] },
    fn(idx) { sum = sum - arr[idx] },
    fn() { sum },
    0,
  )
  // Verify against brute force.
  for i = 0; i < queries.length(); i = i + 1 {
    let mut brute = 0
    for j = queries[i].l; j <= queries[i].r; j = j + 1 {
      brute = brute + arr[j]
    }
    assert_eq(answers[i], brute)
  }
}

///|
test "mo: empty query list" {
  let answers : Array[Int] = mo(
    5,
    [],
    fn(_idx) {  },
    fn(_idx) {  },
    fn() { 0 },
    0,
  )
  assert_eq(answers.length(), 0)
}
