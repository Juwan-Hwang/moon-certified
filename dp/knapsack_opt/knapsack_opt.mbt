/// Knapsack Problem Optimizations.
///
/// Production-grade implementations of three knapsack variants:
///
/// 1. **Multiple Knapsack** (bounded): each item can be used up to `count[i]`
///    times. Uses binary decomposition for O(n × W × log(count)) time.
/// 2. **2D Knapsack**: two capacity constraints (weight + volume).
/// 3. **Monotone Queue Knapsack**: single-item bounded knapsack in
///    O(n × W) using monotone deque optimization.
///
/// ## Complexity
/// - Multiple: O(n × W × log(max_count)).
/// - 2D: O(n × W × V).
/// - Monotone queue: O(n × W).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Multiple (bounded) knapsack via binary decomposition.
///
/// Decomposes each item with count `c` into log(c) "meta-items" of sizes
/// 1, 2, 4, ..., then runs 0/1 knapsack. This achieves O(n × W × log(c))
/// instead of the naive O(n × W × c).
///
/// ## Parameters
/// - `weights`: item weights (1-indexed not needed; 0-indexed).
/// - `values`: item values.
/// - `counts`: max uses per item.
/// - `capacity`: knapsack capacity.
///
/// ## Returns
/// Maximum total value achievable.
pub fn multiple_knapsack(
  weights : Array[Int],
  values : Array[Int],
  counts : Array[Int],
  capacity : Int,
) -> Int {
  let n = weights.length()
  if n == 0 || capacity <= 0 {
    return 0
  }
  // dp[w] = max value with capacity w.
  let dp = FixedArray::make(capacity + 1, 0)
  for i = 0; i < n; i = i + 1 {
    let w = weights[i]
    let v = values[i]
    let c = counts[i]
    if w <= 0 {
      continue
    }
    // Binary decomposition: split count into powers of 2.
    let mut remaining = c
    let mut k = 1
    while remaining > 0 {
      let take = if k > remaining { remaining } else { k }
      let bw = w * take
      let bv = v * take
      // 0/1 knapsack for this meta-item (reverse order).
      let mut cap = capacity
      while cap >= bw {
        if dp[cap - bw] + bv > dp[cap] {
          dp[cap] = dp[cap - bw] + bv
        }
        cap = cap - 1
      }
      remaining = remaining - take
      k = k * 2
    }
  }
  dp[capacity]
}

///|
/// 2D Knapsack (two capacity constraints).
///
/// Classic knapsack with both weight and volume limits.
///
/// ## Parameters
/// - `weights`: item weights.
/// - `volumes`: item volumes.
/// - `values`: item values.
/// - `weight_cap`: weight capacity.
/// - `volume_cap`: volume capacity.
///
/// ## Returns
/// Maximum total value.
pub fn knapsack_2d(
  weights : Array[Int],
  volumes : Array[Int],
  values : Array[Int],
  weight_cap : Int,
  volume_cap : Int,
) -> Int {
  let n = weights.length()
  if n == 0 || weight_cap <= 0 || volume_cap <= 0 {
    return 0
  }
  // dp[w][v] = max value with weight cap w and volume cap v.
  let dp = FixedArray::make((weight_cap + 1) * (volume_cap + 1), 0)
  let idx = fn(w : Int, v : Int) -> Int { w * (volume_cap + 1) + v }
  for i = 0; i < n; i = i + 1 {
    let wi = weights[i]
    let vi = volumes[i]
    let val = values[i]
    if wi <= 0 || vi <= 0 {
      continue
    }
    // Reverse order for 0/1 knapsack.
    let mut w = weight_cap
    while w >= wi {
      let mut v = volume_cap
      while v >= vi {
        let without = dp[idx(w - wi, v - vi)] + val
        if without > dp[idx(w, v)] {
          dp[idx(w, v)] = without
        }
        v = v - 1
      }
      w = w - 1
    }
  }
  dp[idx(weight_cap, volume_cap)]
}

///|
/// Monotone-queue optimized bounded knapsack (single item).
///
/// For a single item with weight `w`, value `v`, count `c`, and capacity
/// `cap`, computes the optimal dp in O(cap) using a monotone deque.
///
/// The key insight: dp[j] depends on dp[j-w], dp[j-2w], ... dp[j-k*w],
/// all of which are in the same residue class mod w. Within each residue
/// class, we use a monotone deque to find the max in O(1) amortized.
pub fn monotone_queue_knapsack(
  weights : Array[Int],
  values : Array[Int],
  counts : Array[Int],
  capacity : Int,
) -> Int {
  let n = weights.length()
  if n == 0 || capacity <= 0 {
    return 0
  }
  let dp = FixedArray::make(capacity + 1, 0)
  for i = 0; i < n; i = i + 1 {
    let w = weights[i]
    let v = values[i]
    let c = counts[i]
    if w <= 0 {
      continue
    }
    // For each residue class mod w.
    for r = 0; r < w && r <= capacity; r = r + 1 {
      // Collect all positions in this residue class.
      let positions : Array[Int] = []
      let mut j = r
      while j <= capacity {
        positions.push(j)
        j = j + w
      }
      if positions.length() == 0 {
        continue
      }
      // Monotone deque: stores (index, adjusted_value).
      let deque_idx : Array[Int] = []
      let deque_val : Array[Int] = []
      let max_count = c
      for k = 0; k < positions.length(); k = k + 1 {
        let pos = positions[k]
        // The value we'd get by adding k items of this type.
        let adjusted = dp[pos] - k * v
        // Remove elements from back while they're <= adjusted.
        while deque_val.length() > 0 &&
              deque_val[deque_val.length() - 1] <= adjusted {
          deque_idx.remove(deque_idx.length() - 1) |> ignore
          deque_val.remove(deque_val.length() - 1) |> ignore
        }
        deque_idx.push(k)
        deque_val.push(adjusted)
        // Remove elements from front that are out of window (count limit).
        while deque_idx.length() > 0 && deque_idx[0] < k - max_count {
          deque_idx.remove(0) |> ignore
          deque_val.remove(0) |> ignore
        }
        // Best value for this position.
        if deque_val.length() > 0 {
          let best = deque_val[0] + k * v
          if best > dp[pos] {
            dp[pos] = best
          }
        }
      }
    }
  }
  dp[capacity]
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "multiple_knapsack: basic" {
  // 3 items, each usable once.
  let w = [2, 3, 4]
  let v = [3, 4, 5]
  let c = [1, 1, 1]
  assert_eq(multiple_knapsack(w, v, c, 5), 7) // items 0+1
}

///|
test "multiple_knapsack: multiple copies" {
  // Item: weight=2, value=3, count=3. Capacity=6.
  // Best: 3 copies = value 9.
  let w = [2]
  let v = [3]
  let c = [3]
  assert_eq(multiple_knapsack(w, v, c, 6), 9)
}

///|
test "multiple_knapsack: mixed" {
  let w = [1, 2, 3]
  let v = [1, 3, 5]
  let c = [2, 3, 1]
  // Capacity 7: 1×item2 (w3,v5) + 2×item1 (w4,v6) = 11
  assert_eq(multiple_knapsack(w, v, c, 7), 11)
}

///|
test "knapsack_2d: basic" {
  // Items: (w,v,val) = [(2,1,3), (1,2,4)]
  // Caps: weight=3, volume=3
  // Best: item0 + item1 = (w3, v3, val7)
  let w = [2, 1]
  let vol = [1, 2]
  let v = [3, 4]
  assert_eq(knapsack_2d(w, vol, v, 3, 3), 7)
}

///|
test "knapsack_2d: single constraint" {
  let w = [3, 4, 5]
  let vol = [1, 1, 1]
  let v = [4, 5, 6]
  // Weight cap 7, volume cap 3. Best: items 0+1 (w7,v2,val9).
  assert_eq(knapsack_2d(w, vol, v, 7, 3), 9)
}

///|
test "monotone_queue_knapsack: matches multiple knapsack" {
  let w = [2, 3, 4]
  let v = [3, 4, 5]
  let c = [1, 1, 1]
  assert_eq(monotone_queue_knapsack(w, v, c, 5), 7)
}

///|
test "monotone_queue_knapsack: multiple copies" {
  let w = [2]
  let v = [3]
  let c = [3]
  assert_eq(monotone_queue_knapsack(w, v, c, 6), 9)
}

///|
test "monotone_queue_knapsack: large counts" {
  let w = [1, 2]
  let v = [1, 3]
  let c = [10, 5]
  // Capacity 10: 5×item1 (w10,v15) = 15
  assert_eq(monotone_queue_knapsack(w, v, c, 10), 15)
}

///|
test "multiple_knapsack: empty" {
  let w : Array[Int] = []
  let v : Array[Int] = []
  let c : Array[Int] = []
  assert_eq(multiple_knapsack(w, v, c, 10), 0)
}

///|
test "knapsack_2d: empty" {
  let w : Array[Int] = []
  let vol : Array[Int] = []
  let v : Array[Int] = []
  assert_eq(knapsack_2d(w, vol, v, 10, 10), 0)
}
