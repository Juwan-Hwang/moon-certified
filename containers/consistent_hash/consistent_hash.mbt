/// Consistent Hashing — Distributed Hash Table Ring.
///
/// Consistent hashing is a distributed hashing scheme that provides
/// minimal key redistribution when nodes are added or removed. It is
/// the core algorithm behind systems like Amazon Dynamo, Cassandra,
/// and Memcached's consistent hashing library (libketama).
///
/// ## Algorithm
///
/// 1. Each node is hashed to multiple positions on a ring (virtual nodes
///    or "replicas") to ensure even distribution.
/// 2. A key is hashed to a position on the ring, and the responsible node
///    is the next node clockwise from that position.
/// 3. When a node is added/removed, only the keys between the new node's
///    position and the previous node's position need to be redistributed.
///
/// ## Complexity
/// - Add/remove node: O(V log N) where V = virtual nodes per physical node.
/// - Lookup: O(log N) via binary search on sorted ring.
/// - Space: O(N * V) for the ring.
///
/// ## Virtual Nodes (Replicas)
///
/// Using 150-200 virtual nodes per physical node ensures even key
/// distribution (standard deviation < 5% of mean). The default is 150
/// (libketama default).
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

///|
/// Default number of virtual nodes per physical node.
const DEFAULT_VNODES : Int = 150

///|
/// A node on the consistent hash ring.
pub struct RingNode {
  /// Position on the ring (0 to 2^31-1).
  hash : Int
  /// Name of the physical node.
  node_name : String
}

///|
/// A consistent hash ring.
pub struct ConsistentHash {
  // Sorted array of (hash, node_name) — the ring.
  mut ring : Array[RingNode]
  // Set of physical node names currently on the ring.
  nodes : Map[String, Unit]
  // Number of virtual nodes per physical node.
  num_vnodes : Int
}

///|
/// Create a new consistent hash ring with the default number of
/// virtual nodes (150) per physical node.
pub fn new() -> ConsistentHash {
  new_with_vnodes(DEFAULT_VNODES)
}

///|
/// Create a new consistent hash ring with a custom number of virtual
/// nodes per physical node. More virtual nodes give better distribution
/// but use more memory.
pub fn new_with_vnodes(num_vnodes : Int) -> ConsistentHash {
  let v = if num_vnodes < 1 { 1 } else { num_vnodes }
  { ring: [], nodes: Map([]), num_vnodes: v, }
}

///|
/// Hash function for node positions on the ring.
///
/// Uses FNV-1a (64-bit) followed by the MurmurHash3 fmix64 finalizer
/// to ensure excellent avalanche properties. This combination produces
/// uniformly distributed hash values, which is critical for consistent
/// hashing — poor distribution leads to severe load imbalance.
fn ring_hash(s : String) -> Int {
  // FNV-1a offset basis (64-bit) and prime.
  // Hex literal ensures correct bit pattern even though the value
  // exceeds Int64's signed range (MoonBit interprets it as two's complement).
  let mut h = 0xcbf29ce484222325L
  let prime = 0x00000100000001B3L
  for i = 0; i < s.length(); i = i + 1 {
    h = h ^ s[i].to_int64()
    h = h * prime
  }
  // MurmurHash3 fmix64 finalizer — avalanches all bits.
  h = h ^ (h.reinterpret_as_uint64() >> 33).reinterpret_as_int64()
  h = h * 0xff51afd7ed558ccdL
  h = h ^ (h.reinterpret_as_uint64() >> 33).reinterpret_as_int64()
  h = h * 0xc4ceb9fe1a85ec53L
  h = h ^ (h.reinterpret_as_uint64() >> 33).reinterpret_as_int64()
  (h.reinterpret_as_uint64() & 0x7FFFFFFFUL).to_int()
}

///|
/// Add a physical node to the ring.
///
/// Creates `num_vnodes` virtual nodes at positions determined by
/// hashing `node_name + ":" + replica_index`.
pub fn add_node(ch : ConsistentHash, node_name : String) -> Unit {
  if ch.nodes.contains(node_name) {
    return // Already on the ring
  }
  ch.nodes[node_name] = ()
  for i = 0; i < ch.num_vnodes; i = i + 1 {
    let key = node_name + ":" + i.to_string()
    let h = ring_hash(key)
    ch.ring.push({ hash: h, node_name, })
  }
  // Keep ring sorted by hash for binary search.
  ch.ring.sort_by(fn(a, b) { a.hash - b.hash })
}

///|
/// Remove a physical node from the ring.
///
/// Removes all virtual nodes belonging to the given physical node.
pub fn remove_node(ch : ConsistentHash, node_name : String) -> Unit {
  if !ch.nodes.contains(node_name) {
    return
  }
  ch.nodes.remove(node_name)
  // Filter out virtual nodes belonging to this physical node.
  let new_ring : Array[RingNode] = []
  for i = 0; i < ch.ring.length(); i = i + 1 {
    if ch.ring[i].node_name != node_name {
      new_ring.push(ch.ring[i])
    }
  }
  ch.ring = new_ring
}

///|
/// Find the node responsible for a given key.
///
/// Returns the name of the physical node that owns the key, or
/// None if the ring is empty.
pub fn get_node(ch : ConsistentHash, key : String) -> String? {
  if ch.ring.length() == 0 {
    return None
  }
  let h = ring_hash(key)
  // Binary search for the first node with hash >= h.
  let mut lo = 0
  let mut hi = ch.ring.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if ch.ring[mid].hash < h {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  // Wrap around if we went past the end.
  let idx = if lo >= ch.ring.length() { 0 } else { lo }
  Some(ch.ring[idx].node_name)
}

///|
/// Get all physical node names on the ring.
pub fn get_nodes(ch : ConsistentHash) -> Array[String] {
  let result : Array[String] = []
  for k, _ in ch.nodes {
    result.push(k)
  }
  result.sort_by(fn(a, b) { if a < b { -1 } else if a > b { 1 } else { 0 } })
  result
}

///|
/// Number of physical nodes on the ring.
pub fn node_count(ch : ConsistentHash) -> Int {
  ch.nodes.length()
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "consistent_hash: basic lookup" {
  let ch = new()
  add_node(ch, "node1")
  add_node(ch, "node2")
  add_node(ch, "node3")
  assert_eq(node_count(ch), 3)
  // Every key should map to some node.
  for i = 0; i < 100; i = i + 1 {
    match get_node(ch, "key" + i.to_string()) {
      Some(n) => assert_true(n == "node1" || n == "node2" || n == "node3")
      None => assert_true(false)
    }
  }
}

///|
test "consistent_hash: empty ring" {
  let ch = new()
  assert_eq(get_node(ch, "anykey"), None)
  assert_eq(node_count(ch), 0)
}

///|
test "consistent_hash: stability" {
  // Same key should always map to the same node (deterministic).
  let ch = new()
  add_node(ch, "A")
  add_node(ch, "B")
  add_node(ch, "C")
  let n1 = get_node(ch, "test_key")
  let n2 = get_node(ch, "test_key")
  assert_eq(n1, n2)
}

///|
test "consistent_hash: minimal redistribution on add" {
  let ch = new()
  add_node(ch, "node1")
  add_node(ch, "node2")
  // Record which node each key maps to.
  let keys : Array[String] = []
  for i = 0; i < 1000; i = i + 1 {
    keys.push("key" + i.to_string())
  }
  let original_map : Map[String, String] = Map([])
  for i = 0; i < keys.length(); i = i + 1 {
    match get_node(ch, keys[i]) {
      Some(n) => original_map[keys[i]] = n
      None => ()
    }
  }
  // Add a new node.
  add_node(ch, "node3")
  // Count how many keys moved.
  let mut moved = 0
  for i = 0; i < keys.length(); i = i + 1 {
    match get_node(ch, keys[i]) {
      Some(n) =>
        match original_map.get(keys[i]) {
          Some(old) => if old != n { moved = moved + 1 }
          None => ()
        }
      None => ()
    }
  }
  // With 3 nodes and adding a 4th, roughly 1/4 of keys should move.
  // With consistent hashing, it should be much less than all keys.
  assert_true(moved < keys.length() / 2)
}

///|
test "consistent_hash: remove node" {
  let ch = new()
  add_node(ch, "node1")
  add_node(ch, "node2")
  add_node(ch, "node3")
  remove_node(ch, "node2")
  assert_eq(node_count(ch), 2)
  // Remaining nodes should handle all keys.
  for i = 0; i < 50; i = i + 1 {
    match get_node(ch, "key" + i.to_string()) {
      Some(n) => assert_true(n == "node1" || n == "node3")
      None => assert_true(false)
    }
  }
}

///|
test "consistent_hash: add duplicate node" {
  let ch = new()
  add_node(ch, "node1")
  add_node(ch, "node1") // duplicate
  assert_eq(node_count(ch), 1)
}

///|
test "consistent_hash: distribution" {
  let ch = new_with_vnodes(200)
  add_node(ch, "A")
  add_node(ch, "B")
  add_node(ch, "C")
  // Check that keys are distributed across all nodes.
  let counts : Map[String, Int] = Map([])
  for i = 0; i < 3000; i = i + 1 {
    match get_node(ch, "key" + i.to_string()) {
      Some(n) =>
        match counts.get(n) {
          Some(c) => counts[n] = c + 1
          None => counts[n] = 1
        }
      None => ()
    }
  }
  // Each node should have at least some keys.
  assert_true(counts["A"] > 0)
  assert_true(counts["B"] > 0)
  assert_true(counts["C"] > 0)
  // Distribution should be roughly even (within 50% of 1000).
  assert_true(counts["A"] > 500 && counts["A"] < 1500)
  assert_true(counts["B"] > 500 && counts["B"] < 1500)
  assert_true(counts["C"] > 500 && counts["C"] < 1500)
}
