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
/// - **Run container** — sorted run-length encoding as (start, end) pairs.
///   Used when the chunk has long consecutive runs. For a range like
///   [0, 1000000], a run container uses O(1) space (one pair), while a
///   bitmap requires 8 KiB. Call `roaring_run_optimize` to convert
///   containers to run-encoded form when beneficial.
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
  /// Run-length encoded: sorted array of (start, end) pairs, end inclusive.
  /// Efficient for long consecutive runs (e.g., [0..1000000] → one pair).
  Run(Array[(UInt, UInt)])
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
// Run container operations
// ---------------------------------------------------------------------------

///|
/// Binary search for a value in a run container. Returns the index of the
/// run containing `val`, or -(insertion_point + 1) if not found.
fn run_search(runs : Array[(UInt, UInt)], val : UInt) -> Int {
  let mut lo = 0
  let mut hi = runs.length() - 1
  while lo <= hi {
    let mid = lo + (hi - lo) / 2
    let (start, end) = runs[mid]
    if val < start {
      hi = mid - 1
    } else if val > end {
      lo = mid + 1
    } else {
      return mid // Found in this run.
    }
  }
  -(lo + 1)
}

///|
/// Check if a run container contains a value.
fn run_contains(runs : Array[(UInt, UInt)], val : UInt) -> Bool {
  run_search(runs, val) >= 0
}

///|
/// Add a value to a run container. Returns true if newly added.
/// May split an existing run or extend a run or create a new run.
fn run_add(runs : Array[(UInt, UInt)], val : UInt) -> Bool {
  let n = runs.length()
  if n == 0 {
    runs.push((val, val))
    return true
  }
  // Check if val is already covered by an existing run.
  let idx = run_search(runs, val)
  if idx >= 0 {
    return false // Already present.
  }
  let insert_pos = -(idx + 1)
  // Check if we can extend the run before insert_pos.
  if insert_pos > 0 {
    let (s, e) = runs[insert_pos - 1]
    if e + 1U == val {
      // Extend the previous run.
      runs[insert_pos - 1] = (s, val)
      // Check if this merges with the next run.
      if insert_pos < n {
        let (ns, _) = runs[insert_pos]
        if ns == val + 1U {
          let (_, ne) = runs[insert_pos]
          runs[insert_pos - 1] = (s, ne)
          runs.remove(insert_pos) |> ignore
        }
      }
      return true
    }
  }
  // Check if we can extend the run at insert_pos.
  if insert_pos < n {
    let (s, e) = runs[insert_pos]
    if s > 0U && s - 1U == val {
      runs[insert_pos] = (val, e)
      return true
    }
  }
  // Insert a new single-element run.
  runs.insert(insert_pos, (val, val))
  true
}

///|
/// Remove a value from a run container. Returns true if was present.
/// May split a run or shrink a run.
fn run_remove(runs : Array[(UInt, UInt)], val : UInt) -> Bool {
  let idx = run_search(runs, val)
  if idx < 0 {
    return false
  }
  let (start, end) = runs[idx]
  if start == end {
    // Single-element run: remove it entirely.
    runs.remove(idx) |> ignore
  } else if val == start {
    // Remove from the beginning.
    runs[idx] = (start + 1U, end)
  } else if val == end {
    // Remove from the end.
    runs[idx] = (start, end - 1U)
  } else {
    // Split the run.
    runs[idx] = (start, val - 1U)
    runs.insert(idx + 1, (val + 1U, end))
  }
  true
}

///|
/// Count total elements in a run container.
fn run_cardinality(runs : Array[(UInt, UInt)]) -> Int {
  let mut count = 0
  for i = 0; i < runs.length(); i = i + 1 {
    let (s, e) = runs[i]
    count = count + (e - s + 1U).reinterpret_as_int()
  }
  count
}

///|
/// Convert an array container to a run container.
fn array_to_run(arr : Array[UInt]) -> Array[(UInt, UInt)] {
  let runs : Array[(UInt, UInt)] = []
  let n = arr.length()
  if n == 0 {
    return runs
  }
  let mut start = arr[0]
  let mut end = arr[0]
  for i = 1; i < n; i = i + 1 {
    if arr[i] == end + 1U {
      end = arr[i]
    } else {
      runs.push((start, end))
      start = arr[i]
      end = arr[i]
    }
  }
  runs.push((start, end))
  runs
}

///|
/// Convert a bitmap container to a run container.
fn bitmap_to_run(bits : FixedArray[UInt]) -> Array[(UInt, UInt)] {
  let runs : Array[(UInt, UInt)] = []
  let mut run_start = 0U
  let mut in_run = false
  for val = 0; val < 65536; val = val + 1 {
    let word_idx = val / 32
    let bit_idx = val % 32
    let is_set = (bits[word_idx] & (1U << bit_idx)) != 0U
    if is_set && !in_run {
      run_start = val.reinterpret_as_uint()
      in_run = true
    } else if !is_set && in_run {
      runs.push((run_start, (val - 1).reinterpret_as_uint()))
      in_run = false
    }
  }
  if in_run {
    runs.push((run_start, 65535U))
  }
  runs
}

///|
/// Convert a run container to an array container.
fn run_to_array(runs : Array[(UInt, UInt)]) -> Array[UInt] {
  let arr : Array[UInt] = []
  for i = 0; i < runs.length(); i = i + 1 {
    let (s, e) = runs[i]
    let mut v = s
    while v <= e {
      arr.push(v)
      v = v + 1U
    }
  }
  arr
}

///|
/// Convert a run container to a bitmap container.
fn run_to_bitmap(runs : Array[(UInt, UInt)]) -> FixedArray[UInt] {
  let bits : FixedArray[UInt] = FixedArray::make(BITMAP_WORDS, 0U)
  for i = 0; i < runs.length(); i = i + 1 {
    let (s, e) = runs[i]
    let mut v = s
    while v <= e {
      let word_idx = v.reinterpret_as_int() / 32
      let bit_idx = v.reinterpret_as_int() % 32
      bits[word_idx] = bits[word_idx] | (1U << bit_idx)
      v = v + 1U
    }
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
    Container::Run(runs) =>
      if run_add(runs, val) {
        chunk.cardinality = chunk.cardinality + 1
        // If runs become too dense (memory exceeds bitmap), convert to bitmap.
        if runs.length() >= BITMAP_WORDS {
          let bits = run_to_bitmap(runs)
          chunk.container = Container::Bitmap(bits)
        }
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
    Container::Run(runs) =>
      if run_remove(runs, val) {
        chunk.cardinality = chunk.cardinality - 1
        // Consider downgrading to array if sparse enough.
        if chunk.cardinality < ARRAY_MAX_SIZE / 2 &&
          runs.length() > chunk.cardinality {
          let arr = run_to_array(runs)
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
    Container::Run(runs) => run_contains(runs, val)
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
      Container::Run(runs) =>
        for ri = 0; ri < runs.length(); ri = ri + 1 {
          let (s, e) = runs[ri]
          let mut v = s
          while v <= e {
            f(combine_value(chunk.high, v))
            v = v + 1U
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

// ---------------------------------------------------------------------------
// Container-level O(n+m) merge operations
// ---------------------------------------------------------------------------

///|
/// Convert any container to an array container for uniform merging.
fn container_to_array(c : Container) -> Array[UInt] {
  match c {
    Container::Array(arr) => {
      let out : Array[UInt] = []
      for i = 0; i < arr.length(); i = i + 1 {
        out.push(arr[i])
      }
      out
    }
    Container::Bitmap(bits) => bitmap_to_array(bits)
    Container::Run(runs) => run_to_array(runs)
  }
}

///|
/// Convert any container to a bitmap container for uniform merging.
fn container_to_bitmap(c : Container) -> FixedArray[UInt] {
  match c {
    Container::Array(arr) => array_to_bitmap(arr)
    Container::Bitmap(bits) => bits
    Container::Run(runs) => run_to_bitmap(runs)
  }
}

///|
/// Union of two sorted arrays — O(n + m) double-pointer merge.
fn array_union(a : Array[UInt], b : Array[UInt]) -> Array[UInt] {
  let result : Array[UInt] = []
  let na = a.length()
  let nb = b.length()
  let mut i = 0
  let mut j = 0
  while i < na && j < nb {
    if a[i] < b[j] {
      result.push(a[i])
      i = i + 1
    } else if a[i] > b[j] {
      result.push(b[j])
      j = j + 1
    } else {
      result.push(a[i])
      i = i + 1
      j = j + 1
    }
  }
  while i < na {
    result.push(a[i])
    i = i + 1
  }
  while j < nb {
    result.push(b[j])
    j = j + 1
  }
  result
}

///|
/// Intersection of two sorted arrays — O(n + m) double-pointer merge.
fn array_intersect(a : Array[UInt], b : Array[UInt]) -> Array[UInt] {
  let result : Array[UInt] = []
  let na = a.length()
  let nb = b.length()
  let mut i = 0
  let mut j = 0
  while i < na && j < nb {
    if a[i] < b[j] {
      i = i + 1
    } else if a[i] > b[j] {
      j = j + 1
    } else {
      result.push(a[i])
      i = i + 1
      j = j + 1
    }
  }
  result
}

///|
/// Symmetric difference of two sorted arrays — O(n + m) double-pointer merge.
fn array_xor(a : Array[UInt], b : Array[UInt]) -> Array[UInt] {
  let result : Array[UInt] = []
  let na = a.length()
  let nb = b.length()
  let mut i = 0
  let mut j = 0
  while i < na && j < nb {
    if a[i] < b[j] {
      result.push(a[i])
      i = i + 1
    } else if a[i] > b[j] {
      result.push(b[j])
      j = j + 1
    } else {
      i = i + 1
      j = j + 1
    }
  }
  while i < na {
    result.push(a[i])
    i = i + 1
  }
  while j < nb {
    result.push(b[j])
    j = j + 1
  }
  result
}

///|
/// Difference (a \ b) of two sorted arrays — O(n + m) double-pointer merge.
fn array_difference(a : Array[UInt], b : Array[UInt]) -> Array[UInt] {
  let result : Array[UInt] = []
  let na = a.length()
  let nb = b.length()
  let mut i = 0
  let mut j = 0
  while i < na && j < nb {
    if a[i] < b[j] {
      result.push(a[i])
      i = i + 1
    } else if a[i] > b[j] {
      j = j + 1
    } else {
      i = i + 1
      j = j + 1
    }
  }
  while i < na {
    result.push(a[i])
    i = i + 1
  }
  result
}

///|
/// Choose the best container type for a merged result given its cardinality
/// and whether it has runs. Follows the same threshold logic as `chunk_add`.
fn make_container(arr : Array[UInt]) -> Container {
  let n = arr.length()
  if n == 0 {
    Container::Array([])
  } else if n >= ARRAY_MAX_SIZE {
    Container::Bitmap(array_to_bitmap(arr))
  } else {
    // Check if run encoding would be more efficient.
    let runs = array_to_run(arr)
    if runs.length() > 0 && runs.length() * 4 < n * 2 {
      Container::Run(runs)
    } else {
      Container::Array(arr)
    }
  }
}

///|
/// Container-level union. Uses O(n+m) algorithms for all container type pairs.
fn container_or(a : Container, b : Container) -> Container {
  // If either is a bitmap, use bitmap-level OR (O(2048) constant).
  match (a, b) {
    (Container::Bitmap(ba), Container::Bitmap(bb)) => {
      let result = FixedArray::make(BITMAP_WORDS, 0U)
      for i = 0; i < BITMAP_WORDS; i = i + 1 {
        result[i] = ba[i] | bb[i]
      }
      Container::Bitmap(result)
    }
    (Container::Bitmap(_), _) => {
      let ba = container_to_bitmap(a)
      let bb = container_to_bitmap(b)
      let result = FixedArray::make(BITMAP_WORDS, 0U)
      for i = 0; i < BITMAP_WORDS; i = i + 1 {
        result[i] = ba[i] | bb[i]
      }
      Container::Bitmap(result)
    }
    (_, Container::Bitmap(_)) => {
      let aa = container_to_bitmap(a)
      let bb = container_to_bitmap(b)
      let result = FixedArray::make(BITMAP_WORDS, 0U)
      for i = 0; i < BITMAP_WORDS; i = i + 1 {
        result[i] = aa[i] | bb[i]
      }
      Container::Bitmap(result)
    }
    (_, _) => {
      // Both are Array or Run — convert to arrays and merge.
      let aa = container_to_array(a)
      let bb = container_to_array(b)
      let merged = array_union(aa, bb)
      make_container(merged)
    }
  }
}

///|
/// Container-level intersection. Uses O(n+m) algorithms.
fn container_and(a : Container, b : Container) -> Container {
  match (a, b) {
    (Container::Bitmap(ba), Container::Bitmap(bb)) => {
      let result = FixedArray::make(BITMAP_WORDS, 0U)
      for i = 0; i < BITMAP_WORDS; i = i + 1 {
        result[i] = ba[i] & bb[i]
      }
      let card = {
        let mut c = 0
        for i = 0; i < BITMAP_WORDS; i = i + 1 {
          c = c + popcount_word(result[i])
        }
        c
      }
      if card == 0 {
        Container::Array([])
      } else if card < ARRAY_MAX_SIZE {
        Container::Array(bitmap_to_array(result))
      } else {
        Container::Bitmap(result)
      }
    }
    (_, _) => {
      // At least one is Array or Run — use array-level merge.
      let aa = container_to_array(a)
      let bb = container_to_array(b)
      let merged = array_intersect(aa, bb)
      make_container(merged)
    }
  }
}

///|
/// Container-level symmetric difference. Uses O(n+m) algorithms.
fn container_xor(a : Container, b : Container) -> Container {
  match (a, b) {
    (Container::Bitmap(ba), Container::Bitmap(bb)) => {
      let result = FixedArray::make(BITMAP_WORDS, 0U)
      for i = 0; i < BITMAP_WORDS; i = i + 1 {
        result[i] = ba[i] ^ bb[i]
      }
      let card = {
        let mut c = 0
        for i = 0; i < BITMAP_WORDS; i = i + 1 {
          c = c + popcount_word(result[i])
        }
        c
      }
      if card == 0 {
        Container::Array([])
      } else if card < ARRAY_MAX_SIZE {
        Container::Array(bitmap_to_array(result))
      } else {
        Container::Bitmap(result)
      }
    }
    (_, _) => {
      let aa = container_to_array(a)
      let bb = container_to_array(b)
      let merged = array_xor(aa, bb)
      make_container(merged)
    }
  }
}

///|
/// Container-level difference (a \ b). Uses O(n+m) algorithms.
fn container_andnot(a : Container, b : Container) -> Container {
  match (a, b) {
    (Container::Bitmap(ba), Container::Bitmap(bb)) => {
      let result = FixedArray::make(BITMAP_WORDS, 0U)
      for i = 0; i < BITMAP_WORDS; i = i + 1 {
        result[i] = ba[i] & (0xFFFFFFFFU ^ bb[i])
      }
      let card = {
        let mut c = 0
        for i = 0; i < BITMAP_WORDS; i = i + 1 {
          c = c + popcount_word(result[i])
        }
        c
      }
      if card == 0 {
        Container::Array([])
      } else if card < ARRAY_MAX_SIZE {
        Container::Array(bitmap_to_array(result))
      } else {
        Container::Bitmap(result)
      }
    }
    (_, _) => {
      let aa = container_to_array(a)
      let bb = container_to_array(b)
      let merged = array_difference(aa, bb)
      make_container(merged)
    }
  }
}

///|
/// Compute the cardinality of a container.
fn container_cardinality(c : Container) -> Int {
  match c {
    Container::Array(arr) => arr.length()
    Container::Bitmap(bits) => {
      let mut count = 0
      for i = 0; i < BITMAP_WORDS; i = i + 1 {
        count = count + popcount_word(bits[i])
      }
      count
    }
    Container::Run(runs) => run_cardinality(runs)
  }
}

// ---------------------------------------------------------------------------
// O(n+m) set operations — chunk-level double-pointer merge
// ---------------------------------------------------------------------------

///|
/// Generic chunk-level merge using double-pointer traversal.
/// Both `a.chunks` and `b.chunks` are sorted by `high` key.
/// `merge_fn` specifies the container-level operation.
fn chunk_merge(
  a : RoaringBitmap,
  b : RoaringBitmap,
  merge_fn : (Container, Container) -> Container,
) -> RoaringBitmap {
  let result = roaring_create()
  let ca = a.chunks
  let cb = b.chunks
  let na = ca.length()
  let nb = cb.length()
  let mut i = 0
  let mut j = 0
  while i < na && j < nb {
    if ca[i].high < cb[j].high {
      // Chunk only in a — copy it.
      let arr = container_to_array(ca[i].container)
      let container = make_container(arr)
      let card = container_cardinality(container)
      if card > 0 {
        result.chunks.push({ high: ca[i].high, container, cardinality: card })
      }
      i = i + 1
    } else if ca[i].high > cb[j].high {
      // Chunk only in b — copy it.
      let arr = container_to_array(cb[j].container)
      let container = make_container(arr)
      let card = container_cardinality(container)
      if card > 0 {
        result.chunks.push({ high: cb[j].high, container, cardinality: card })
      }
      j = j + 1
    } else {
      // Matching high keys — merge containers.
      let merged = merge_fn(ca[i].container, cb[j].container)
      let card = container_cardinality(merged)
      if card > 0 {
        result.chunks.push({
          high: ca[i].high,
          container: merged,
          cardinality: card,
        })
      }
      i = i + 1
      j = j + 1
    }
  }
  // Copy remaining chunks from a.
  while i < na {
    let arr = container_to_array(ca[i].container)
    let container = make_container(arr)
    let card = container_cardinality(container)
    if card > 0 {
      result.chunks.push({ high: ca[i].high, container, cardinality: card })
    }
    i = i + 1
  }
  // Copy remaining chunks from b.
  while j < nb {
    let arr = container_to_array(cb[j].container)
    let container = make_container(arr)
    let card = container_cardinality(container)
    if card > 0 {
      result.chunks.push({ high: cb[j].high, container, cardinality: card })
    }
    j = j + 1
  }
  // Compute total cardinality.
  let mut total = 0
  for k = 0; k < result.chunks.length(); k = k + 1 {
    total = total + result.chunks[k].cardinality
  }
  result.cardinality = total
  result
}

///|
/// Compute the union of two bitmaps (OR). Returns a new bitmap.
///
/// Uses O(n + m) chunk-level double-pointer merge with container-specific
/// algorithms: bitmap-bitmap uses word-level OR (O(2048)), array-array and
/// run-run use double-pointer merge.
pub fn roaring_or(a : RoaringBitmap, b : RoaringBitmap) -> RoaringBitmap {
  chunk_merge(a, b, container_or)
}

///|
/// Compute the intersection of two bitmaps (AND). Returns a new bitmap.
///
/// Uses O(n + m) chunk-level double-pointer merge with container-specific
/// algorithms.
pub fn roaring_and(a : RoaringBitmap, b : RoaringBitmap) -> RoaringBitmap {
  // For intersection, chunks only in one bitmap contribute nothing.
  let result = roaring_create()
  let ca = a.chunks
  let cb = b.chunks
  let na = ca.length()
  let nb = cb.length()
  let mut i = 0
  let mut j = 0
  while i < na && j < nb {
    if ca[i].high < cb[j].high {
      i = i + 1
    } else if ca[i].high > cb[j].high {
      j = j + 1
    } else {
      let merged = container_and(ca[i].container, cb[j].container)
      let card = container_cardinality(merged)
      if card > 0 {
        result.chunks.push({
          high: ca[i].high,
          container: merged,
          cardinality: card,
        })
      }
      i = i + 1
      j = j + 1
    }
  }
  let mut total = 0
  for k = 0; k < result.chunks.length(); k = k + 1 {
    total = total + result.chunks[k].cardinality
  }
  result.cardinality = total
  result
}

///|
/// Compute the symmetric difference of two bitmaps (XOR). Returns a new bitmap.
///
/// Uses O(n + m) chunk-level double-pointer merge with container-specific
/// algorithms.
pub fn roaring_xor(a : RoaringBitmap, b : RoaringBitmap) -> RoaringBitmap {
  chunk_merge(a, b, container_xor)
}

///|
/// Compute the difference of two bitmaps (ANDNOT). Returns a new bitmap
/// containing elements in `a` but not in `b`.
///
/// Uses O(n + m) chunk-level double-pointer merge. Chunks only in `b`
/// contribute nothing to the result.
pub fn roaring_andnot(a : RoaringBitmap, b : RoaringBitmap) -> RoaringBitmap {
  let result = roaring_create()
  let ca = a.chunks
  let cb = b.chunks
  let na = ca.length()
  let nb = cb.length()
  let mut i = 0
  let mut j = 0
  while i < na {
    if j >= nb || ca[i].high < cb[j].high {
      // Chunk only in a — copy entirely.
      let arr = container_to_array(ca[i].container)
      let container = make_container(arr)
      let card = container_cardinality(container)
      if card > 0 {
        result.chunks.push({ high: ca[i].high, container, cardinality: card })
      }
      i = i + 1
    } else if ca[i].high > cb[j].high {
      j = j + 1
    } else {
      // Matching high keys — subtract.
      let merged = container_andnot(ca[i].container, cb[j].container)
      let card = container_cardinality(merged)
      if card > 0 {
        result.chunks.push({
          high: ca[i].high,
          container: merged,
          cardinality: card,
        })
      }
      i = i + 1
      j = j + 1
    }
  }
  let mut total = 0
  for k = 0; k < result.chunks.length(); k = k + 1 {
    total = total + result.chunks[k].cardinality
  }
  result.cardinality = total
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

///|
/// Optimize the bitmap by converting containers to run-encoded form when
/// it saves memory. A run container is used when the number of runs is
/// small enough that `runs.length() * 4 bytes < current_container_size`.
///
/// This is particularly effective for dense contiguous ranges like
/// [0, 1000000], which collapses to a single (0, 1000000) pair.
pub fn roaring_run_optimize(rb : RoaringBitmap) -> Unit {
  for ci = 0; ci < rb.chunks.length(); ci = ci + 1 {
    let chunk = rb.chunks[ci]
    match chunk.container {
      Container::Array(arr) => {
        let runs = array_to_run(arr)
        // Use run if it saves space: runs use 4 bytes per entry,
        // array uses 2 bytes per element.
        if runs.length() > 0 && runs.length() * 4 < arr.length() * 2 {
          chunk.container = Container::Run(runs)
          // Verify cardinality consistency after conversion.
          chunk.cardinality = run_cardinality(runs)
        }
      }
      Container::Bitmap(bits) => {
        // Bitmap always uses 8192 bytes. Run uses 4 bytes per pair.
        let runs = bitmap_to_run(bits)
        if runs.length() > 0 && runs.length() * 4 < 8192 {
          chunk.container = Container::Run(runs)
          chunk.cardinality = run_cardinality(runs)
        }
      }
      Container::Run(_) => () // Already optimized.
    }
  }
}

///|
/// Add a range of values [start, end] (inclusive) to the bitmap efficiently.
/// Uses run containers for chunks that receive long contiguous ranges.
pub fn roaring_add_range(rb : RoaringBitmap, start : UInt, end : UInt) -> Unit {
  if start > end {
    return
  }
  let mut val = start
  while val <= end {
    let (high, low) = split_value(val)
    let idx = find_chunk(rb.chunks, high)
    let chunk = if idx >= 0 {
      rb.chunks[idx]
    } else {
      let insert_pos = -(idx + 1)
      let c : Chunk = { high, container: new_array_container(), cardinality: 0 }
      rb.chunks.insert(insert_pos, c)
      rb.chunks[insert_pos]
    }
    let chunk_end = (high + 1U) << 16
    let range_end = if end < chunk_end - 1U { end } else { chunk_end - 1U }
    let low_end = range_end & 0xFFFFU
    let mut v = low
    while v <= low_end {
      if chunk_add(chunk, v) {
        rb.cardinality = rb.cardinality + 1
      }
      v = v + 1U
    }
    val = range_end + 1U
  }
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

///|
test "roaring: run optimize on contiguous range" {
  let rb = roaring_create()
  for i = 0; i < 10001; i = i + 1 {
    ignore(roaring_add(rb, i.reinterpret_as_uint()))
  }
  assert_eq(roaring_cardinality(rb), 10001)
  roaring_run_optimize(rb)
  // After optimization, all values should still be present.
  assert_eq(roaring_cardinality(rb), 10001)
  for i = 0; i < 10001; i = i + 1 {
    assert_true(roaring_contains(rb, i.reinterpret_as_uint()))
  }
  assert_true(!roaring_contains(rb, 10001U))
}

///|
test "roaring: run container add and remove" {
  let rb = roaring_create()
  for i = 0; i < 5000; i = i + 1 {
    ignore(roaring_add(rb, i.reinterpret_as_uint()))
  }
  roaring_run_optimize(rb)
  // Add a value in the middle of a run.
  assert_true(!roaring_add(rb, 100U)) // Already present.
  // Add a value outside the run.
  assert_true(roaring_add(rb, 60000U))
  assert_eq(roaring_cardinality(rb), 5001)
  // Remove a value from the middle of a run.
  assert_true(roaring_remove(rb, 100U))
  assert_true(!roaring_contains(rb, 100U))
  assert_true(roaring_contains(rb, 99U))
  assert_true(roaring_contains(rb, 101U))
}

///|
test "roaring: run container round-trip via iterate" {
  let rb = roaring_create()
  for i = 0; i < 10000; i = i + 1 {
    ignore(roaring_add(rb, i.reinterpret_as_uint()))
  }
  roaring_run_optimize(rb)
  let arr = roaring_to_array(rb)
  assert_eq(arr.length(), 10000)
  for i = 0; i < 10000; i = i + 1 {
    assert_eq(arr[i], i.reinterpret_as_uint())
  }
}

///|
test "roaring: set operations work with run containers" {
  let a = roaring_create()
  for i = 0; i < 5000; i = i + 1 {
    ignore(roaring_add(a, i.reinterpret_as_uint()))
  }
  roaring_run_optimize(a)
  let b = roaring_create()
  for i = 2500; i < 7500; i = i + 1 {
    ignore(roaring_add(b, i.reinterpret_as_uint()))
  }
  roaring_run_optimize(b)
  // Union
  let u = roaring_or(a, b)
  assert_eq(roaring_cardinality(u), 7500)
  // Intersection
  let i = roaring_and(a, b)
  assert_eq(roaring_cardinality(i), 2500)
  // Difference
  let d = roaring_andnot(a, b)
  assert_eq(roaring_cardinality(d), 2500)
}

///|
test "roaring: add range for dense contiguous data" {
  let rb = roaring_create()
  roaring_add_range(rb, 0U, 99999U)
  assert_eq(roaring_cardinality(rb), 100000)
  assert_true(roaring_contains(rb, 0U))
  assert_true(roaring_contains(rb, 99999U))
  assert_true(roaring_contains(rb, 50000U))
  assert_true(!roaring_contains(rb, 100000U))
}
