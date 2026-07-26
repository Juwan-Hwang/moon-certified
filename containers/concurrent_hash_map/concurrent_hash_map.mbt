/// Concurrent Hash Map — Open Addressing (Single-Threaded Simulation).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

pub struct Slot[K, V] {
  mut key : K?
  mut value : V?
  mut state : Int
}

pub struct ConcurrentHashMap[K, V] {
  priv mut slots : FixedArray[Slot[K, V]]
  priv mut size : Int
  priv mut used : Int
  priv mut capacity : Int
  priv hash_fn : (K) -> Int
  priv eq_fn : (K, K) -> Bool
}

pub fn[K, V] concurrent_hash_map_new(
  capacity : Int,
  hash_fn : (K) -> Int,
  eq_fn : (K, K) -> Bool,
) -> ConcurrentHashMap[K, V] {
  let cap = if capacity < 8 { 8 } else { next_pow2(capacity) }
  let slots = FixedArray::makei(cap, fn(_) { Slot::{ key: None, value: None, state: 0 } })
  { slots, size: 0, used: 0, capacity: cap, hash_fn, eq_fn }
}

fn next_pow2(n : Int) -> Int {
  let mut p = 1
  while p < n {
    p = p * 2
  }
  p
}

fn[K, V] ConcurrentHashMap::find_slot(
  self : ConcurrentHashMap[K, V],
  key : K,
) -> (Int, Bool) {
  let h = (self.hash_fn)(key)
  let mask = self.capacity - 1
  let mut idx = h & mask
  if idx < 0 {
    idx = idx + self.capacity
  }
  let mut first_tombstone = -1
  for _ in 0..<self.capacity {
    let slot = self.slots[idx]
    if slot.state == 0 {
      if first_tombstone >= 0 {
        return (first_tombstone, false)
      }
      return (idx, false)
    }
    if slot.state == 1 {
      match slot.key {
        Some(k) =>
          if (self.eq_fn)(k, key) {
            return (idx, true)
          }
        None => ()
      }
    } else if slot.state == 2 && first_tombstone < 0 {
      first_tombstone = idx
    }
    idx = (idx + 1) & mask
  }
  if first_tombstone >= 0 {
    return (first_tombstone, false)
  }
  (-1, false)
}

pub fn[K, V] ConcurrentHashMap::put(
  self : ConcurrentHashMap[K, V],
  key : K,
  value : V,
) -> Unit {
  let (idx, found) = self.find_slot(key)
  if idx < 0 {
    self.resize()
    self.put(key, value)
    return
  }
  let slot = self.slots[idx]
  if !found {
    if slot.state != 1 {
      self.used = self.used + 1
    }
    slot.key = Some(key)
    slot.state = 1
    self.size = self.size + 1
  }
  slot.value = Some(value)
  if self.used * 4 > self.capacity * 3 {
    self.resize()
  }
}

pub fn[K, V] ConcurrentHashMap::get(
  self : ConcurrentHashMap[K, V],
  key : K,
) -> V? {
  let (idx, found) = self.find_slot(key)
  if !found || idx < 0 {
    return None
  }
  self.slots[idx].value
}

pub fn[K, V] ConcurrentHashMap::remove(
  self : ConcurrentHashMap[K, V],
  key : K,
) -> Bool {
  let (idx, found) = self.find_slot(key)
  if !found || idx < 0 {
    return false
  }
  let slot = self.slots[idx]
  slot.state = 2
  slot.value = None
  self.size = self.size - 1
  true
}

pub fn[K, V] ConcurrentHashMap::len(self : ConcurrentHashMap[K, V]) -> Int {
  self.size
}

pub fn[K, V] ConcurrentHashMap::is_empty(self : ConcurrentHashMap[K, V]) -> Bool {
  self.size == 0
}

fn[K, V] ConcurrentHashMap::resize(self : ConcurrentHashMap[K, V]) -> Unit {
  let old_slots = self.slots
  let old_cap = self.capacity
  let new_cap = old_cap * 2
  let new_slots = FixedArray::makei(new_cap, fn(_) { Slot::{ key: None, value: None, state: 0 } })
  self.slots = new_slots
  self.capacity = new_cap
  self.size = 0
  self.used = 0
  for i = 0; i < old_cap; i = i + 1 {
    let slot = old_slots[i]
    if slot.state == 1 {
      match slot.key {
        Some(k) =>
          match slot.value {
            Some(v) => self.put(k, v)
            None => ()
          }
        None => ()
      }
    }
  }
}

fn str_hash(s : String) -> Int {
  let mut h = 0
  for i = 0; i < s.length(); i = i + 1 {
    h = h * 31 + s[i].to_int()
  }
  h
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "concurrent_hash_map: basic put and get" {
  let m = concurrent_hash_map_new(8, str_hash, fn(a, b) { a == b })
  m.put("a", 1)
  m.put("b", 2)
  m.put("c", 3)
  assert_eq(m.get("a"), Some(1))
  assert_eq(m.get("b"), Some(2))
  assert_eq(m.get("c"), Some(3))
  assert_eq(m.get("d"), None)
  assert_eq(m.len(), 3)
}

test "concurrent_hash_map: update existing key" {
  let m = concurrent_hash_map_new(8, str_hash, fn(a, b) { a == b })
  m.put("x", 10)
  m.put("x", 20)
  assert_eq(m.get("x"), Some(20))
  assert_eq(m.len(), 1)
}

test "concurrent_hash_map: delete" {
  let m = concurrent_hash_map_new(8, str_hash, fn(a, b) { a == b })
  m.put("a", 1)
  m.put("b", 2)
  assert_true(m.remove("a"))
  assert_eq(m.get("a"), None)
  assert_eq(m.get("b"), Some(2))
  assert_eq(m.len(), 1)
  assert_false(m.remove("z"))
}

test "concurrent_hash_map: resize" {
  let m = concurrent_hash_map_new(8, str_hash, fn(a, b) { a == b })
  for i = 0; i < 100; i = i + 1 {
    m.put(i.to_string(), i * 2)
  }
  assert_eq(m.len(), 100)
  for i = 0; i < 100; i = i + 1 {
    assert_eq(m.get(i.to_string()), Some(i * 2))
  }
}

test "concurrent_hash_map: delete and reinsert" {
  let m = concurrent_hash_map_new(8, str_hash, fn(a, b) { a == b })
  m.put("a", 1)
  ignore(m.remove("a"))
  m.put("a", 2)
  assert_eq(m.get("a"), Some(2))
  assert_eq(m.len(), 1)
}

test "concurrent_hash_map: many operations" {
  let m = concurrent_hash_map_new(16, fn(k) { k }, fn(a, b) { a == b })
  for i = 0; i < 50; i = i + 1 {
    m.put(i, i * i)
  }
  for i = 0; i < 50; i = i + 2 {
    ignore(m.remove(i))
  }
  for i = 0; i < 50; i = i + 1 {
    if i % 2 == 0 {
      assert_eq(m.get(i), None)
    } else {
      assert_eq(m.get(i), Some(i * i))
    }
  }
}

test "concurrent_hash_map: empty" {
  let m : ConcurrentHashMap[String, Int] = concurrent_hash_map_new(
    8, str_hash, fn(a, b) { a == b },
  )
  assert_true(m.is_empty())
  assert_eq(m.get("nothing"), None)
  assert_false(m.remove("nothing"))
}
