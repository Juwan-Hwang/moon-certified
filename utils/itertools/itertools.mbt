/// Iterator combinator utilities — inspired by Python's `itertools`.
///
/// This module provides higher-order combinators that work with MoonBit's
/// `Iter[T]` type, extending the standard library with commonly needed
/// operations not already provided by `core/builtin`.
///
/// Functions already present in the standard library (e.g. `Iter::map`,
/// `Iter::filter`, `Iter::take`, `Iter::drop`, `Iter::zip`, `Iter::concat`,
/// `Iter::fold`, `Iter::count`, `Iter::to_array`, `Iter::filter_map`,
/// `Iter::flatten`, `Iter::take_while`, `Iter::drop_while`) are **not**
/// duplicated here.
///
/// `proof-enabled` is `false`.

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Create an iterator over a half-open integer range `[start, end)`.
///
/// Returns an empty iterator when `start >= end`.
pub fn range(start : Int, end : Int) -> Iter[Int] {
  let mut i = start
  Iter::new(fn() {
    if i < end {
      let v = i
      i = i + 1
      Some(v)
    } else {
      None
    }
  })
}

///|
/// Create an iterator that yields `value` exactly `count` times.
///
/// Returns an empty iterator when `count <= 0`.
/// (The standard library's `Iter::repeat` yields indefinitely; this variant
/// is finite.)
pub fn[T] repeat(value : T, count : Int) -> Iter[T] {
  let mut n = 0
  Iter::new(fn() {
    if n < count {
      n = n + 1
      Some(value)
    } else {
      None
    }
  })
}

// ---------------------------------------------------------------------------
// Composition (beyond stdlib's Iter::concat and Iter::zip)
// ---------------------------------------------------------------------------

///|
/// Interleave elements from two iterators: a1, b1, a2, b2, ...
/// Stops when both iterators are exhausted.
pub fn[T] interleave(ia : Iter[T], ib : Iter[T]) -> Iter[T] {
  let mut phase = 0 // 0 = a, 1 = b
  let mut a_done = false
  let mut b_done = false
  Iter::new(fn() {
    let mut result : T? = None
    let mut keep_going = true
    while keep_going {
      if a_done && b_done {
        keep_going = false
      } else if phase == 0 && !a_done {
        phase = 1
        match ia.next() {
          Some(v) => {
            result = Some(v)
            keep_going = false
          }
          None => a_done = true
        }
      } else if phase == 1 && !b_done {
        phase = 0
        match ib.next() {
          Some(v) => {
            result = Some(v)
            keep_going = false
          }
          None => b_done = true
        }
      } else if a_done {
        phase = 1
      } else {
        phase = 0
      }
    }
    result
  })
}

// ---------------------------------------------------------------------------
// Transformation (beyond stdlib)
// ---------------------------------------------------------------------------

///|
/// Pair each element with its zero-based index.
pub fn[T] enumerate(iter : Iter[T]) -> Iter[(Int, T)] {
  let mut i = 0
  Iter::new(fn() {
    match iter.next() {
      Some(v) => {
        let idx = i
        i = i + 1
        Some((idx, v))
      }
      None => None
    }
  })
}

// ---------------------------------------------------------------------------
// Grouping (not in stdlib)
// ---------------------------------------------------------------------------

///|
/// Sliding window of size `window_size`, advancing by 1 each step.
/// Returns an empty iterator if `window_size <= 0` or the input has fewer
/// than `window_size` elements.
pub fn[T] window(iter : Iter[T], window_size : Int) -> Iter[Array[T]] {
  if window_size <= 0 {
    return Iter::empty()
  }
  let buf : Array[T] = []
  Iter::new(fn() {
    let mut result : Array[T]? = None
    if buf.length() >= window_size {
      ignore(buf.remove(0))
    }
    while buf.length() < window_size {
      match iter.next() {
        Some(v) => buf.push(v)
        None => return None
      }
    }
    let arr = Array::make(window_size, buf[0])
    for i = 0; i < window_size; i = i + 1 {
      arr[i] = buf[i]
    }
    result = Some(arr)
    result
  })
}

///|
/// Chunk the iterator into groups of at most `chunk_size` elements.
/// The final chunk may be smaller than `chunk_size`.
pub fn[T] chunk(iter : Iter[T], chunk_size : Int) -> Iter[Array[T]] {
  if chunk_size <= 0 {
    return Iter::empty()
  }
  Iter::new(fn() {
    let group : Array[T] = []
    while group.length() < chunk_size {
      match iter.next() {
        Some(v) => group.push(v)
        None => {
          if group.length() == 0 {
            return None
          }
          return Some(group)
        }
      }
    }
    Some(group)
  })
}

// ---------------------------------------------------------------------------
// Deduplication (not in stdlib)
// ---------------------------------------------------------------------------

///|
/// Remove consecutive duplicate elements (keeping the first occurrence).
/// Non-consecutive duplicates are preserved.
pub fn[T] dedup(iter : Iter[T], eq : (T, T) -> Bool) -> Iter[T] {
  let mut prev : T? = None
  Iter::new(fn() {
    let mut result : T? = None
    let mut keep_going = true
    while keep_going {
      match iter.next() {
        Some(v) =>
          match prev {
            Some(p) =>
              if eq(p, v) {
                ()
              } else {
                prev = Some(v)
                result = Some(v)
                keep_going = false
              }
            None => {
              prev = Some(v)
              result = Some(v)
              keep_going = false
            }
          }
        None => keep_going = false
      }
    }
    result
  })
}

// ---------------------------------------------------------------------------
// Aggregation helpers (convenience wrappers beyond stdlib)
// ---------------------------------------------------------------------------

///|
/// Reduce an iterator to a single value using a binary operator, starting
/// from `initial`.
pub fn[T, U] fold(iter : Iter[T], initial : U, f : (U, T) -> U) -> U {
  let mut acc = initial
  let mut keep_going = true
  while keep_going {
    match iter.next() {
      Some(v) => acc = f(acc, v)
      None => keep_going = false
    }
  }
  acc
}

///|
/// Collect all elements into an `Array`.
pub fn[T] collect(iter : Iter[T]) -> Array[T] {
  let arr : Array[T] = []
  let mut keep_going = true
  while keep_going {
    match iter.next() {
      Some(v) => arr.push(v)
      None => keep_going = false
    }
  }
  arr
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "range: basic" {
  let result = collect(range(0, 5))
  assert_eq(result.length(), 5)
  assert_eq(result[0], 0)
  assert_eq(result[4], 4)
}

///|
test "range: empty" {
  let result = collect(range(5, 5))
  assert_eq(result.length(), 0)
}

///|
test "enumerate" {
  let result = collect(enumerate(["x", "y", "z"].iter()))
  assert_eq(result.length(), 3)
  assert_eq(result[0].0, 0)
  assert_eq(result[0].1, "x")
  assert_eq(result[2].0, 2)
}

///|
test "window: size 3" {
  let result = collect(window([1, 2, 3, 4, 5].iter(), 3))
  assert_eq(result.length(), 3)
  assert_eq(result[0].length(), 3)
  assert_eq(result[0][0], 1)
  assert_eq(result[0][2], 3)
  assert_eq(result[1][0], 2)
  assert_eq(result[2][2], 5)
}

///|
test "chunk: size 3" {
  let result = collect(chunk(range(0, 10), 3))
  assert_eq(result.length(), 4)
  assert_eq(result[0].length(), 3)
  assert_eq(result[3].length(), 1)
}

///|
test "dedup: consecutive" {
  let result = collect(
    dedup([1, 1, 2, 2, 2, 3, 1, 1].iter(), fn(a, b) { a == b }),
  )
  assert_eq(result.length(), 4)
  assert_eq(result[0], 1)
  assert_eq(result[1], 2)
  assert_eq(result[2], 3)
  assert_eq(result[3], 1)
}

///|
test "fold: sum" {
  let sum = fold(range(1, 6), 0, fn(acc, x) { acc + x })
  assert_eq(sum, 15)
}

///|
test "repeat" {
  let result = collect(repeat(42, 3))
  assert_eq(result.length(), 3)
  assert_eq(result[0], 42)
  assert_eq(result[2], 42)
}

///|
test "interleave" {
  let result = collect(interleave([1, 3, 5].iter(), [2, 4, 6].iter()))
  assert_eq(result.length(), 6)
  assert_eq(result[0], 1)
  assert_eq(result[1], 2)
  assert_eq(result[5], 6)
}

///|
test "interleave: unequal lengths" {
  let result = collect(interleave([1, 3, 5, 7].iter(), [2, 4].iter()))
  assert_eq(result.length(), 6)
  assert_eq(result[0], 1)
  assert_eq(result[1], 2)
  assert_eq(result[2], 3)
  assert_eq(result[3], 4)
  assert_eq(result[4], 5)
  assert_eq(result[5], 7)
}
