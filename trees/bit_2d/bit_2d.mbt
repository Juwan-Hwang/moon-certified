/// 2D Binary Indexed Tree (Fenwick Tree) for 2D range sum queries.
///
/// Supports point updates and range sum queries on a 2D grid in O(log R · log C)
/// time, where R is the number of rows and C is the number of columns.
///
/// ## Algorithm
///
/// A 2D BIT is a BIT of BITs: `tree[i][j]` stores the sum of a sub-rectangle
/// of the original matrix. The update and query operations nest two 1D BIT
/// loops, giving O(log R · log C) per operation.
///
/// ## Complexity
///
/// - Construction: O(R · C)
/// - Point update: O(log R · log C)
/// - Prefix sum query: O(log R · log C)
/// - Range sum query: O(log R · log C)
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
/// A 2D Binary Indexed Tree for Int values.
///
/// Supports point updates and 2D range sum queries.
pub struct BIT2D {
  rows : Int
  cols : Int
  // 1-indexed internal tree. tree[i][j] covers a sub-rectangle.
  tree : FixedArray[FixedArray[Int64]]
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create a 2D BIT of size `rows × cols`, initialised to 0.
///
/// Uses 1-indexed internal storage, so the actual array is `(rows+1) × (cols+1)`.
pub fn new(rows : Int, cols : Int) -> BIT2D {
  // Each row must be a separate FixedArray — if we passed a single inner
  // array to `FixedArray::make`, every row would alias the same storage.
  let tree : FixedArray[FixedArray[Int64]] = FixedArray::make(
    rows + 1,
    FixedArray::make(0, 0L),
  )
  for i = 0; i <= rows; i = i + 1 {
    tree[i] = FixedArray::make(cols + 1, 0L)
  }
  { rows, cols, tree, }
}

///|
/// Build a 2D BIT from an initial 2D value array (0-indexed).
pub fn build(
  values : FixedArray[FixedArray[Int64]],
  rows : Int,
  cols : Int,
) -> BIT2D {
  let bit = new(rows, cols)
  for i = 0; i < rows; i = i + 1 {
    for j = 0; j < cols; j = j + 1 {
      update(bit, i, j, values[i][j])
    }
  }
  bit
}

// ---------------------------------------------------------------------------
// Operations
// ---------------------------------------------------------------------------

///|
/// Add `delta` to position `(row, col)` (0-indexed).
///
/// # Complexity
/// O(log R · log C).
pub fn update(bit : BIT2D, row : Int, col : Int, delta : Int64) -> Unit {
  // Convert to 1-indexed.
  let mut i = row + 1
  while i <= bit.rows {
    let mut j = col + 1
    while j <= bit.cols {
      bit.tree[i][j] = bit.tree[i][j] + delta
      j = j + (j & -j)
    }
    i = i + (i & -i)
  }
}

///|
/// Query the sum of the rectangle from (0, 0) to `(row, col)` inclusive
/// (0-indexed). Returns 0 for negative indices.
///
/// # Complexity
/// O(log R · log C).
pub fn prefix_sum(bit : BIT2D, row : Int, col : Int) -> Int64 {
  if row < 0 || col < 0 {
    return 0L
  }
  let mut sum = 0L
  let mut i = row + 1
  while i > 0 {
    let mut j = col + 1
    while j > 0 {
      sum = sum + bit.tree[i][j]
      j = j - (j & -j)
    }
    i = i - (i & -i)
  }
  sum
}

///|
/// Query the sum of the rectangle from `(r1, c1)` to `(r2, c2)` inclusive
/// (0-indexed). Requires `r1 <= r2` and `c1 <= c2`.
///
/// # Complexity
/// O(log R · log C).
pub fn range_sum(bit : BIT2D, r1 : Int, c1 : Int, r2 : Int, c2 : Int) -> Int64 {
  prefix_sum(bit, r2, c2) -
  prefix_sum(bit, r1 - 1, c2) -
  prefix_sum(bit, r2, c1 - 1) +
  prefix_sum(bit, r1 - 1, c1 - 1)
}

///|
/// Get the value at position `(row, col)` (0-indexed).
pub fn get(bit : BIT2D, row : Int, col : Int) -> Int64 {
  range_sum(bit, row, col, row, col)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "bit2d: basic update and query" {
  let bit = new(3, 3)
  update(bit, 0, 0, 5L)
  update(bit, 1, 1, 10L)
  update(bit, 2, 2, 15L)
  assert_eq(prefix_sum(bit, 0, 0), 5L)
  assert_eq(prefix_sum(bit, 2, 2), 30L)
  assert_eq(prefix_sum(bit, 1, 1), 15L)
}

///|
test "bit2d: range sum" {
  let bit = new(4, 4)
  // Fill with 1s.
  for i = 0; i < 4; i = i + 1 {
    for j = 0; j < 4; j = j + 1 {
      update(bit, i, j, 1L)
    }
  }
  // Sum of entire 4x4 = 16.
  assert_eq(range_sum(bit, 0, 0, 3, 3), 16L)
  // Sum of 2x2 top-left = 4.
  assert_eq(range_sum(bit, 0, 0, 1, 1), 4L)
  // Sum of 2x2 bottom-right = 4.
  assert_eq(range_sum(bit, 2, 2, 3, 3), 4L)
  // Single cell.
  assert_eq(range_sum(bit, 1, 1, 1, 1), 1L)
}

///|
test "bit2d: build from array" {
  // Each row must be a distinct FixedArray to avoid aliasing.
  let values = FixedArray::make(3, FixedArray::make(0, 0L))
  for i = 0; i < 3; i = i + 1 {
    values[i] = FixedArray::make(3, 0L)
    for j = 0; j < 3; j = j + 1 {
      values[i][j] = (i * 3 + j).to_int64()
    }
  }
  let bit = build(values, 3, 3)
  // Sum of all = 0+1+...+8 = 36.
  assert_eq(range_sum(bit, 0, 0, 2, 2), 36L)
  // Sum of [0,0]-[1,1] = 0+1+3+4 = 8.
  assert_eq(range_sum(bit, 0, 0, 1, 1), 8L)
  // Get individual values.
  assert_eq(get(bit, 1, 2), 5L)
}

///|
test "bit2d: negative values" {
  let bit = new(3, 3)
  update(bit, 0, 0, -5L)
  update(bit, 2, 2, 10L)
  assert_eq(range_sum(bit, 0, 0, 2, 2), 5L)
  assert_eq(get(bit, 0, 0), -5L)
  assert_eq(get(bit, 2, 2), 10L)
}

///|
test "bit2d: single cell" {
  let bit = new(1, 1)
  update(bit, 0, 0, 42L)
  assert_eq(prefix_sum(bit, 0, 0), 42L)
  assert_eq(range_sum(bit, 0, 0, 0, 0), 42L)
}

///|
test "bit2d: stress test 100x100" {
  let n = 100
  let bit = new(n, n)
  // Fill with row*col pattern.
  let expected = FixedArray::make(n * n, 0L)
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < n; j = j + 1 {
      let v = (i * n + j).to_int64()
      update(bit, i, j, v)
      expected[i * n + j] = v
    }
  }
  // Verify a few range sums against brute force.
  // Sum of [0,0]-[9,9]
  let mut brute = 0L
  for i = 0; i < 10; i = i + 1 {
    for j = 0; j < 10; j = j + 1 {
      brute = brute + expected[i * n + j]
    }
  }
  assert_eq(range_sum(bit, 0, 0, 9, 9), brute)
  // Sum of [50,50]-[99,99]
  let mut brute2 = 0L
  for i = 50; i < 100; i = i + 1 {
    for j = 50; j < 100; j = j + 1 {
      brute2 = brute2 + expected[i * n + j]
    }
  }
  assert_eq(range_sum(bit, 50, 50, 99, 99), brute2)
}

///|
test "bit2d: incremental updates" {
  let bit = new(5, 5)
  update(bit, 2, 3, 10L)
  assert_eq(get(bit, 2, 3), 10L)
  update(bit, 2, 3, 5L)
  assert_eq(get(bit, 2, 3), 15L)
  update(bit, 2, 3, -3L)
  assert_eq(get(bit, 2, 3), 12L)
}

///|
test "bit2d: row and column prefix sums" {
  let bit = new(3, 3)
  update(bit, 0, 0, 1L)
  update(bit, 0, 1, 2L)
  update(bit, 0, 2, 3L)
  update(bit, 1, 0, 4L)
  update(bit, 1, 1, 5L)
  update(bit, 1, 2, 6L)
  update(bit, 2, 0, 7L)
  update(bit, 2, 1, 8L)
  update(bit, 2, 2, 9L)
  // Row 0 sum = 1+2+3 = 6
  assert_eq(range_sum(bit, 0, 0, 0, 2), 6L)
  // Column 0 sum = 1+4+7 = 12
  assert_eq(range_sum(bit, 0, 0, 2, 0), 12L)
  // Entire matrix sum = 45
  assert_eq(range_sum(bit, 0, 0, 2, 2), 45L)
}
