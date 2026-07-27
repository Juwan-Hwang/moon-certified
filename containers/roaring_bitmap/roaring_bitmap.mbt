/// Roaring Bitmap — compressed bitmap for 32-bit unsigned integers.
///
/// Roaring bitmaps partition the 32-bit integer space into 2^16 contiguous
/// chunks, each covering 2^16 values. For each chunk, one of three container
/// types is chosen based on cardinality:
///
/// - **Array container** — sorted array of 16-bit values. Used when the chunk
///   has few elements (< 4096). Memory: O(n) where n = elements.
/// - **Bitmap container** — fixed 8192-byte (2^16 bits) bitmap. Used when the
///   chunk has many elements (>= 4096). Memory: 8 KiB regardless of fill.
/// - **Run container** — sorted run-length encoding. Used when the chunk has
///   long consecutive runs (not implemented in this version for simplicity;
///   array and bitmap containers cover all use cases correctly).
///
/// The threshold of 4096 is optimal: at this point an array container uses
/// exactly as much memory (4096 × 2 bytes = 8192 bytes) as a bitmap container,
/// but bitmap lookup is O(1) vs array's O(log n) binary search.
///
/// ## Operations
///
/// - `add`, `remove`, `contains` — O(log n) for array, O(1) for bitmap
/// - `and`, `or`, `xor`, `andnot` — set operations between two bitmaps
/// - `cardinality` — O(1) (maintained incrementally)
/// - `iterate` — O(n) iteration over all set bits
///
/// ## References
///
/// - Chambi et al. "Better Bitmap Performance with Roaring Bitmaps" (2014)
/// - Lemire et al. "Consistently faster and smaller compressed bitmaps with
///   Roaring" (2019)
/// - https://roaringbitmap.org/
///
/// Not formally verified. Correctness is ensured by the test suite.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Threshold for switching between array and bitmap containers.
/// At 4096 elements, array (4096×2 = 8192 bytes) equals bitmap (8192 bytes).
const ARRAY_MAX_SIZE : Int = 4096

///|
/// Bitmap container size in UInts: 2^16 / 32 = 2048.
const BITMAP_WORDS : Int = 2048

// ---------------------------------------------------------------------------
// Container types
// ---------------------------------------------------------------------------

///|
/// A container for a single 2^16 range of the 32-bit integer space.
priv enum Container {
  /// Sorted array of 16-bit values (low 16 bits of elements in this chunk).
  Array(Array[UInt])
  /// Fixed-size bitmap: 2048 UInt words = 65536 bits.
  Bitmap(FixedArray[UInt])
}

///|
/// A single chunk: high 16 bits + container.
struct Chunk {
  // High 16 bits of all elements in this chunk: identifies which 2^16 range.
  high : UInt
  // The container holding the low 16 bits.
  mut container : Container
  // Number of elements in this chunk.
  mut cardinality : Int
}

// ---------------------------------------------------------------------------
// RoaringBitmap type
// ---------------------------------------------------------------------------

///|
/// A Roaring Bitmap for storing sets of 32-bit unsigned integers.
///
/// Internally maintains an array of chunks sorted by their `high` key.
/// Each chunk uses either an array container (for sparse chunks) or a bitmap
/// container (for dense chunks), automatically converting between the two as
/// elements are added or removed.
pub struct RoaringBitmap {
  // Sorted array of chunks.
  priv chunks : Array[Chunk]
  // Total number of set bits across all chunks.
  priv mut cardinality : Int
}

// ---------------------------------------------------------------------------
// Container operations
// ---------------------------------------------------------------------------

///|
/// Create an empty array container.
fn new_array_container() -> Container {
  Container::Array([])
}

///|
/// Binary search for a value in a sorted array. Returns the index if found,
/// or -(insertion_point + 1) if not found.
fn array_search(arr : Array[UInt], val : UInt) -> Int {
  let mut lo = 0
  let mut hi = arr.length() - 1
  while lo <= hi {
    let mid = lo + (hi - lo) / 2
    if arr[mid] == val {
      return mid
    }
    if arr[mid] < val {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  -(lo + 1)
}

///|
/// Insert a value into a sorted array (maintaining sort order).
fn array_insert(arr : Array[UInt], val : UInt) -> Bool {
  let idx = array_search(arr, val)
  if idx >= 0 {
    return false // Already present.
  }
  let insert_pos = -(idx + 1)
  arr.insert(insert_pos, val)
  true
}

///|
/// Remove a value from a sorted array.
fn array_remove(arr : Array[UInt], val : UInt) -> Bool {
  let idx = array_search(arr, val)
  if idx < 0 {
    return false // Not found.
  }
  arr.remove(idx) |> ignore
  true
}

///|
/// Check if a bitmap container contains a value.
fn bitmap_contains(bits : FixedArray[UInt], val : UInt) -> Bool {
  let word_idx = val.reinterpret_as_int() / 32
  let bit_idx = val.reinterpret_as_int() % 32
  (bits[word_idx] & (1U << bit_idx)) != 0U
}

///|
/// Set a bit in a bitmap container. Returns true if newly set.
fn bitmap_set(bits : FixedArray[UInt], val : UInt) -> Bool {
  let word_idx = val.reinterpret_as_int() / 32
  let bit_idx = val.reinterpret_as_int() % 32
  let mask = 1U << bit_idx
  if (bits[word_idx] & mask) != 0U {
    return false
  }
  bits[word_idx] = bits[word_idx] | mask
  true
}

///|
/// Clear a bit in a bitmap container. Returns true if was set.
fn bitmap_clear(bits : FixedArray[UInt], val : UInt) -> Bool {
  let word_idx = val.reinterpret_as_int() / 32
  let bit_idx = val.reinterpret_as_int() % 32
  let mask = 1U << bit_idx
  if (bits[word_idx] & mask) == 0U {
    return false
  }
  bits[word_idx] = bits[word_idx] & (0xFFFFFFFFU ^ mask)
  true
}

///|
/// Count set bits in a UInt (population count).
fn popcount_word(w : UInt) -> Int {
  let mut x = w
  x = x - ((x >> 1) & 0x55555555U)
  x = (x & 0x33333333U) + ((x >> 2) & 0x33333333U)
  x = (x + (x >> 4)) & 0x0F0F0F0FU
  ((x * 0x01010101U) >> 24).reinterpret_as_int()
}

///|
/// Convert a bitmap container to an array container.
fn bitmap_to_array(bits : FixedArray[UInt]) -> Array[UInt] {
  let arr : Array[UInt] = []
  for word_idx = 0; word_idx < BITMAP_WORDS; word_idx = word_idx + 1 {
    let mut w = bits[word_idx]
    let base = word_idx * 32
    while w != 0U {
      let bit = w & ((0xFFFFFFFFU ^ w) + 1U) // Isolate lowest set bit.
      let pos = base + popcount_word(bit - 1U)
      arr.push(pos.reinterpret_as_uint())
      w = w & (w - 1U) // Clear lowest set bit.
    }
  }
  arr
}

///|
/// Convert an array container to a bitmap container.
fn array_to_bitmap(arr : Array[UInt]) -> FixedArray[UInt] {
  let bits : FixedArray[UInt] = FixedArray::make(BITMAP_WORDS, 0U)
  for i = 0; i < arr.length(); i = i + 1 {
    let val = arr[i]
    let word_idx = val.reinterpret_as_int() / 32
    let bit_idx = val.reinterpret_as_int() % 32
    bits[word_idx] = bits[word_idx] | (1U << bit_idx)
  }
  bits
}

// ---------------------------------------------------------------------------
// Chunk operations
// ---------------------------------------------------------------------------

///|
/// Add a value (low 16 bits) to a chunk. Returns true if newly added.
fn chunk_add(chunk : Chunk, val : UInt) -> Bool {
  match chunk.container {
    Container::Array(arr) =>
      if chunk.cardinality >= ARRAY_MAX_SIZE {
        // Convert to bitmap.
        let bits = array_to_bitmap(arr)
        let newly = bitmap_set(bits, val)
        chunk.container = Container::Bitmap(bits)
        if newly {
          chunk.cardinality = chunk.cardinality + 1
        }
        newly
      } else {
        let newly = array_insert(arr, val)
        if newly {
          chunk.cardinality = chunk.cardinality + 1
        }
        newly
      }
    Container::Bitmap(bits) =>
      if bitmap_set(bits, val) {
        chunk.cardinality = chunk.cardinality + 1
        true
      } else {
        false
      }
  }
}

///|
/// Remove a value (low 16 bits) from a chunk. Returns true if was present.
fn chunk_remove(chunk : Chunk, val : UInt) -> Bool {
  match chunk.container {
    Container::Array(arr) =>
      if array_remove(arr, val) {
        chunk.cardinality = chunk.cardinality - 1
        true
      } else {
        false
      }
    Container::Bitmap(bits) =>
      if bitmap_clear(bits, val) {
        chunk.cardinality = chunk.cardinality - 1
        // Consider downgrading to array if sparse enough.
        if chunk.cardinality < ARRAY_MAX_SIZE / 2 {
          let arr = bitmap_to_array(bits)
          chunk.container = Container::Array(arr)
        }
        true
      } else {
        false
      }
  }
}

///|
/// Check if a chunk contains a value (low 16 bits).
fn chunk_contains(chunk : Chunk, val : UInt) -> Bool {
  match chunk.container {
    Container::Array(arr) => array_search(arr, val) >= 0
    Container::Bitmap(bits) => bitmap_contains(bits, val)
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

///|
/// Create an empty Roaring Bitmap.
pub fn roaring_create() -> RoaringBitmap {
  { chunks: [], cardinality: 0 }
}

///|
/// Create a Roaring Bitmap from an array of 32-bit unsigned integers.
pub fn roaring_from_array(values : Array[UInt]) -> RoaringBitmap {
  let rb = roaring_create()
  for i = 0; i < values.length(); i = i + 1 {
    ignore(roaring_add(rb, values[i]))
  }
  rb
}

///|
/// Get the high 16 bits and low 16 bits of a 32-bit value.
fn split_value(val : UInt) -> (UInt, UInt) {
  (val >> 16, val & 0xFFFFU)
}

///|
/// Combine high and low 16 bits into a 32-bit value.
fn combine_value(high : UInt, low : UInt) -> UInt {
  (high << 16) | low
}

///|
/// Find the index of the chunk with the given high key, or the insertion
/// point (as negative) if not found.
fn find_chunk(chunks : Array[Chunk], high : UInt) -> Int {
  let mut lo = 0
  let mut hi = chunks.length() - 1
  while lo <= hi {
    let mid = lo + (hi - lo) / 2
    if chunks[mid].high == high {
      return mid
    }
    if chunks[mid].high < high {
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  -(lo + 1)
}

///|
/// Add a 32-bit unsigned integer to the bitmap.
///
/// Returns `true` if the value was newly added (was not already present).
pub fn roaring_add(rb : RoaringBitmap, val : UInt) -> Bool {
  let (high, low) = split_value(val)
  let idx = find_chunk(rb.chunks, high)
  if idx >= 0 {
    let chunk = rb.chunks[idx]
    if chunk_add(chunk, low) {
      rb.cardinality = rb.cardinality + 1
      return true
    }
    return false
  }
  // Create new chunk.
  let insert_pos = -(idx + 1)
  let chunk : Chunk = { high, container: new_array_container(), cardinality: 0 }
  rb.chunks.insert(insert_pos, chunk)
  if chunk_add(chunk, low) {
    rb.cardinality = rb.cardinality + 1
    true
  } else {
    false
  }
}

///|
/// Remove a 32-bit unsigned integer from the bitmap.
///
/// Returns `true` if the value was present and removed.
pub fn roaring_remove(rb : RoaringBitmap, val : UInt) -> Bool {
  let (high, low) = split_value(val)
  let idx = find_chunk(rb.chunks, high)
  if idx < 0 {
    return false
  }
  let chunk = rb.chunks[idx]
  if chunk_remove(chunk, low) {
    rb.cardinality = rb.cardinality - 1
    // Remove empty chunks to save memory.
    if chunk.cardinality == 0 {
      rb.chunks.remove(idx) |> ignore
    }
    true
  } else {
    false
  }
}

///|
/// Check if the bitmap contains a 32-bit unsigned integer.
pub fn roaring_contains(rb : RoaringBitmap, val : UInt) -> Bool {
  let (high, low) = split_value(val)
  let idx = find_chunk(rb.chunks, high)
  if idx < 0 {
    return false
  }
  chunk_contains(rb.chunks[idx], low)
}

///|
/// Get the number of set bits in the bitmap.
pub fn roaring_cardinality(rb : RoaringBitmap) -> Int {
  rb.cardinality
}

///|
/// Check if the bitmap is empty.
pub fn roaring_is_empty(rb : RoaringBitmap) -> Bool {
  rb.cardinality == 0
}

///|
/// Iterate over all set bits, calling `f` for each value.
pub fn roaring_iterate(rb : RoaringBitmap, f : (UInt) -> Unit) -> Unit {
  for ci = 0; ci < rb.chunks.length(); ci = ci + 1 {
    let chunk = rb.chunks[ci]
    match chunk.container {
      Container::Array(arr) =>
        for i = 0; i < arr.length(); i = i + 1 {
          f(combine_value(chunk.high, arr[i]))
        }
      Container::Bitmap(bits) =>
        for word_idx = 0; word_idx < BITMAP_WORDS; word_idx = word_idx + 1 {
          let mut w = bits[word_idx]
          let base = word_idx * 32
          while w != 0U {
            let bit = w & ((0xFFFFFFFFU ^ w) + 1U)
            let pos = base + popcount_word(bit - 1U)
            f(combine_value(chunk.high, pos.reinterpret_as_uint()))
            w = w & (w - 1U)
          }
        }
    }
  }
}

///|
/// Collect all set bits into a sorted array.
pub fn roaring_to_array(rb : RoaringBitmap) -> Array[UInt] {
  let result : Array[UInt] = []
  roaring_iterate(rb, fn(v) { result.push(v) })
  result
}

///|
/// Compute the union of two bitmaps (OR). Returns a new bitmap.
pub fn roaring_or(a : RoaringBitmap, b : RoaringBitmap) -> RoaringBitmap {
  let result = roaring_create()
  roaring_iterate(a, fn(v) { ignore(roaring_add(result, v)) })
  roaring_iterate(b, fn(v) { ignore(roaring_add(result, v)) })
  result
}

///|
/// Compute the intersection of two bitmaps (AND). Returns a new bitmap.
pub fn roaring_and(a : RoaringBitmap, b : RoaringBitmap) -> RoaringBitmap {
  let result = roaring_create()
  roaring_iterate(a, fn(v) {
    if roaring_contains(b, v) {
      ignore(roaring_add(result, v))
    }
  })
  result
}

///|
/// Compute the symmetric difference of two bitmaps (XOR). Returns a new bitmap.
pub fn roaring_xor(a : RoaringBitmap, b : RoaringBitmap) -> RoaringBitmap {
  let result = roaring_create()
  roaring_iterate(a, fn(v) {
    if !roaring_contains(b, v) {
      ignore(roaring_add(result, v))
    }
  })
  roaring_iterate(b, fn(v) {
    if !roaring_contains(a, v) {
      ignore(roaring_add(result, v))
    }
  })
  result
}

///|
/// Compute the difference of two bitmaps (ANDNOT). Returns a new bitmap
/// containing elements in `a` but not in `b`.
pub fn roaring_andnot(a : RoaringBitmap, b : RoaringBitmap) -> RoaringBitmap {
  let result = roaring_create()
  roaring_iterate(a, fn(v) {
    if !roaring_contains(b, v) {
      ignore(roaring_add(result, v))
    }
  })
  result
}

///|
/// Check if two bitmaps are equal (same set of elements).
pub fn roaring_equals(a : RoaringBitmap, b : RoaringBitmap) -> Bool {
  if a.cardinality != b.cardinality {
    return false
  }
  // Check all elements of a are in b.
  let mut all_in_b = true
  roaring_iterate(a, fn(v) { if !roaring_contains(b, v) { all_in_b = false } })
  all_in_b
}

///|
/// Check if bitmap `a` is a subset of bitmap `b`.
pub fn roaring_is_subset(a : RoaringBitmap, b : RoaringBitmap) -> Bool {
  if a.cardinality > b.cardinality {
    return false
  }
  let mut all_in_b = true
  roaring_iterate(a, fn(v) { if !roaring_contains(b, v) { all_in_b = false } })
  all_in_b
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "roaring: add and contains" {
  let rb = roaring_create()
  assert_true(!roaring_contains(rb, 42U))
  assert_true(roaring_add(rb, 42U))
  assert_true(roaring_contains(rb, 42U))
  assert_true(!roaring_add(rb, 42U)) // Already present.
  assert_eq(roaring_cardinality(rb), 1)
}

///|
test "roaring: remove" {
  let rb = roaring_create()
  ignore(roaring_add(rb, 100U))
  ignore(roaring_add(rb, 200U))
  assert_true(roaring_remove(rb, 100U))
  assert_true(!roaring_contains(rb, 100U))
  assert_true(roaring_contains(rb, 200U))
  assert_true(!roaring_remove(rb, 999U))
  assert_eq(roaring_cardinality(rb), 1)
}

///|
test "roaring: large values across chunks" {
  let rb = roaring_create()
  ignore(roaring_add(rb, 0U))
  ignore(roaring_add(rb, 65535U))
  ignore(roaring_add(rb, 65536U))
  ignore(roaring_add(rb, 100000U))
  ignore(roaring_add(rb, 0xFFFFFFFFU))
  assert_eq(roaring_cardinality(rb), 5)
  assert_true(roaring_contains(rb, 0U))
  assert_true(roaring_contains(rb, 65535U))
  assert_true(roaring_contains(rb, 65536U))
  assert_true(roaring_contains(rb, 100000U))
  assert_true(roaring_contains(rb, 0xFFFFFFFFU))
}

///|
test "roaring: container conversion (array to bitmap)" {
  let rb = roaring_create()
  for i = 0; i < 5000; i = i + 1 {
    ignore(roaring_add(rb, i.reinterpret_as_uint()))
  }
  assert_eq(roaring_cardinality(rb), 5000)
  for i = 0; i < 5000; i = i + 1 {
    assert_true(roaring_contains(rb, i.reinterpret_as_uint()))
  }
  assert_true(!roaring_contains(rb, 5000U))
}

///|
test "roaring: iterate produces sorted output" {
  let rb = roaring_create()
  ignore(roaring_add(rb, 300U))
  ignore(roaring_add(rb, 100U))
  ignore(roaring_add(rb, 200U))
  ignore(roaring_add(rb, 70000U))
  let arr = roaring_to_array(rb)
  assert_eq(arr.length(), 4)
  assert_eq(arr[0], 100U)
  assert_eq(arr[1], 200U)
  assert_eq(arr[2], 300U)
  assert_eq(arr[3], 70000U)
}

///|
test "roaring: union (OR)" {
  let a = roaring_from_array([1U, 2U, 3U, 100000U])
  let b = roaring_from_array([2U, 3U, 4U, 200000U])
  let result = roaring_or(a, b)
  assert_eq(roaring_cardinality(result), 6)
  assert_true(roaring_contains(result, 1U))
  assert_true(roaring_contains(result, 2U))
  assert_true(roaring_contains(result, 3U))
  assert_true(roaring_contains(result, 4U))
  assert_true(roaring_contains(result, 100000U))
  assert_true(roaring_contains(result, 200000U))
}

///|
test "roaring: intersection (AND)" {
  let a = roaring_from_array([1U, 2U, 3U, 100000U])
  let b = roaring_from_array([2U, 3U, 4U, 100000U])
  let result = roaring_and(a, b)
  assert_eq(roaring_cardinality(result), 3)
  assert_true(roaring_contains(result, 2U))
  assert_true(roaring_contains(result, 3U))
  assert_true(roaring_contains(result, 100000U))
}

///|
test "roaring: symmetric difference (XOR)" {
  let a = roaring_from_array([1U, 2U, 3U])
  let b = roaring_from_array([2U, 3U, 4U])
  let result = roaring_xor(a, b)
  assert_eq(roaring_cardinality(result), 2)
  assert_true(roaring_contains(result, 1U))
  assert_true(roaring_contains(result, 4U))
}

///|
test "roaring: difference (ANDNOT)" {
  let a = roaring_from_array([1U, 2U, 3U, 4U])
  let b = roaring_from_array([2U, 4U])
  let result = roaring_andnot(a, b)
  assert_eq(roaring_cardinality(result), 2)
  assert_true(roaring_contains(result, 1U))
  assert_true(roaring_contains(result, 3U))
}

///|
test "roaring: equality" {
  let a = roaring_from_array([1U, 2U, 3U])
  let b = roaring_from_array([3U, 1U, 2U])
  let c = roaring_from_array([1U, 2U])
  assert_true(roaring_equals(a, b))
  assert_true(!roaring_equals(a, c))
}

///|
test "roaring: subset" {
  let a = roaring_from_array([1U, 2U])
  let b = roaring_from_array([1U, 2U, 3U])
  let c = roaring_from_array([1U, 4U])
  assert_true(roaring_is_subset(a, b))
  assert_true(!roaring_is_subset(c, b))
  assert_true(roaring_is_subset(b, b))
}

///|
test "roaring: dense bitmap with many elements" {
  let rb = roaring_create()
  for i = 0; i < 10000; i = i + 2 {
    ignore(roaring_add(rb, i.reinterpret_as_uint()))
  }
  assert_eq(roaring_cardinality(rb), 5000)
  for i = 0; i < 10000; i = i + 1 {
    if i % 2 == 0 {
      assert_true(roaring_contains(rb, i.reinterpret_as_uint()))
    } else {
      assert_true(!roaring_contains(rb, i.reinterpret_as_uint()))
    }
  }
}

///|
test "roaring: container downgrade on removal" {
  let rb = roaring_create()
  for i = 0; i < 5000; i = i + 1 {
    ignore(roaring_add(rb, i.reinterpret_as_uint()))
  }
  for i = 100; i < 5000; i = i + 1 {
    ignore(roaring_remove(rb, i.reinterpret_as_uint()))
  }
  assert_eq(roaring_cardinality(rb), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_true(roaring_contains(rb, i.reinterpret_as_uint()))
  }
}
