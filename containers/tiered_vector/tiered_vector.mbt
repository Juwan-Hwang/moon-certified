/// Tiered Vector — A Dynamic Array with O(sqrt(n)) Insert/Delete
///
/// `proof-enabled` is `false`.

///|
/// Tiered vector.
pub struct TieredVector {
  mut tier_count : Int
  tier_capacity : Int
  data : Array[Array[Int]]
  mut size : Int
}

///|
/// Create a new tiered vector.
pub fn TieredVector::new(initial_capacity : Int) -> TieredVector {
  let tier_cap = initial_capacity.to_double().sqrt().to_int() + 1
  if tier_cap < 4 {
    return {
      tier_count: 1,
      tier_capacity: 4,
      data: [Array::make(4, 0)],
      size: 0,
    }
  }
  let tc = tier_cap
  let data : Array[Array[Int]] = []
  for i = 0; i < tc; i = i + 1 {
    data.push(Array::make(tc, 0))
  }
  { tier_count: tc, tier_capacity: tc, data, size: 0, }
}

///|
/// Get element at index.
pub fn TieredVector::get(self : TieredVector, index : Int) -> Int {
  if index < 0 || index >= self.size {
    abort("TieredVector: index out of bounds")
  }
  let tier_idx = index / self.tier_capacity
  let local_idx = index % self.tier_capacity
  self.data[tier_idx][local_idx]
}

///|
/// Set element at index.
pub fn TieredVector::set(self : TieredVector, index : Int, value : Int) -> Unit {
  if index < 0 || index >= self.size {
    abort("TieredVector: index out of bounds")
  }
  let tier_idx = index / self.tier_capacity
  let local_idx = index % self.tier_capacity
  self.data[tier_idx][local_idx] = value
}

///|
/// Push back an element.
pub fn TieredVector::push_back(self : TieredVector, value : Int) -> Unit {
  let tier_idx = self.size / self.tier_capacity
  let local_idx = self.size % self.tier_capacity
  if tier_idx >= self.tier_count {
    self.data.push(Array::make(self.tier_capacity, 0))
    self.tier_count = self.tier_count + 1
  }
  self.data[tier_idx][local_idx] = value
  self.size = self.size + 1
}

///|
/// Insert element at position, shifting subsequent elements right.
pub fn TieredVector::insert_at(
  self : TieredVector,
  index : Int,
  value : Int,
) -> Unit {
  if index < 0 || index > self.size {
    abort("TieredVector: index out of bounds")
  }
  if self.size >= self.tier_count * self.tier_capacity {
    self.data.push(Array::make(self.tier_capacity, 0))
    self.tier_count = self.tier_count + 1
  }
  // Shift elements right from end to index
  let mut i = self.size
  while i > index {
    let src_tier = (i - 1) / self.tier_capacity
    let src_local = (i - 1) % self.tier_capacity
    let dst_tier = i / self.tier_capacity
    let dst_local = i % self.tier_capacity
    self.data[dst_tier][dst_local] = self.data[src_tier][src_local]
    i = i - 1
  }
  let tier_idx = index / self.tier_capacity
  let local_idx = index % self.tier_capacity
  self.data[tier_idx][local_idx] = value
  self.size = self.size + 1
}

///|
/// Remove element at position, shifting subsequent elements left.
pub fn TieredVector::remove_at(self : TieredVector, index : Int) -> Int {
  if index < 0 || index >= self.size {
    abort("TieredVector: index out of bounds")
  }
  let tier_idx = index / self.tier_capacity
  let local_idx = index % self.tier_capacity
  let value = self.data[tier_idx][local_idx]
  let mut i = index
  while i < self.size - 1 {
    let src_tier = (i + 1) / self.tier_capacity
    let src_local = (i + 1) % self.tier_capacity
    let dst_tier = i / self.tier_capacity
    let dst_local = i % self.tier_capacity
    self.data[dst_tier][dst_local] = self.data[src_tier][src_local]
    i = i + 1
  }
  self.size = self.size - 1
  value
}

///|
/// Convert to array.
pub fn TieredVector::to_array(self : TieredVector) -> Array[Int] {
  let result = Array::make(self.size, 0)
  for i = 0; i < self.size; i = i + 1 {
    result[i] = self.get(i)
  }
  result
}
