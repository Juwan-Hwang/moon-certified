/// Conflict-free Replicated Data Types (CRDTs)
///
/// Implements state-based (CvRDT) and operation-based (CmRDT) CRDTs
/// for distributed systems. CRDTs allow eventual consistency without
/// coordination: replicas can independently accept updates and converge
/// to the same state after all updates propagate.
///
/// ## Implemented Types
///
/// - **GCounter** (Grow-only Counter): monotonically increasing counter
/// - **PNCounter** (Positive-Negative Counter): counter with increments
///   and decrements (two G-Counters)
/// - **GSet** (Grow-only Set): set supporting only add
/// - **TwoPhaseSet** (2P-Set): set with add/remove (tombstone-based)
/// - **LWWMap** (Last-Writer-Wins Map): key-value store with LWW semantics
/// - **ORSet** (Observed-Remove Set): set with remove that only
///   removes elements seen before the remove
///
/// ## References
///
/// - Shapiro, M., Preguica, N., Baquero, C., Zawirski, M. (2011).
///   "A Comprehensive Study of Convergent and Commutative Replicated
///   Data Types." INRIA Research Report 7506.
/// - Baquero, C. (2017). "Practical demystification of CRDTs."
///   Tech Report, HASLab, University of Minho.

// ===========================================================================
// 1. GCounter (Grow-only Counter)
// ===========================================================================

///|
/// Grow-only Counter (CvRDT).
///
/// Each replica maintains a counter per-node. Merge takes the
/// element-wise max. Value is the sum of all node counters.
pub struct GCounter {
  node_id : Int
  counts : Array[Int]
}

///|
/// Create a new GCounter for a cluster of `n` nodes.
pub fn gcounter_new(node_id : Int, n_nodes : Int) -> GCounter {
  { node_id, counts: Array::make(n_nodes, 0), }
}

///|
/// Increment the counter for this node.
pub fn gcounter_increment(c : GCounter) -> GCounter {
  let result = { ..c, counts: Array::copy(c.counts), }
  result.counts[c.node_id] = result.counts[c.node_id] + 1
  result
}

///|
/// Get the total value of the counter (sum of all node counters).
pub fn gcounter_value(c : GCounter) -> Int {
  let mut sum = 0
  for i = 0; i < c.counts.length(); i = i + 1 {
    sum = sum + c.counts[i]
  }
  sum
}

///|
/// Merge two GCounters (element-wise max).
pub fn gcounter_merge(a : GCounter, b : GCounter) -> GCounter {
  let n = if a.counts.length() > b.counts.length() {
    a.counts.length()
  } else {
    b.counts.length()
  }
  let counts = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let va = if i < a.counts.length() { a.counts[i] } else { 0 }
    let vb = if i < b.counts.length() { b.counts[i] } else { 0 }
    counts[i] = if va > vb { va } else { vb }
  }
  { node_id: a.node_id, counts, }
}

// ===========================================================================
// 2. PNCounter (Positive-Negative Counter)
// ===========================================================================

///|
/// Positive-Negative Counter (CvRDT).
///
/// Maintains two GCounters: one for increments, one for decrements.
/// Value = P.value - N.value.
pub struct PNCounter {
  node_id : Int
  p : Array[Int]
  n : Array[Int]
}

///|
/// Create a new PNCounter for `n` nodes.
pub fn pncounter_new(node_id : Int, n_nodes : Int) -> PNCounter {
  { node_id, p: Array::make(n_nodes, 0), n: Array::make(n_nodes, 0), }
}

///|
/// Increment the counter.
pub fn pncounter_increment(c : PNCounter) -> PNCounter {
  let result = { ..c, p: Array::copy(c.p), n: Array::copy(c.n), }
  result.p[c.node_id] = result.p[c.node_id] + 1
  result
}

///|
/// Decrement the counter.
pub fn pncounter_decrement(c : PNCounter) -> PNCounter {
  let result = { ..c, p: Array::copy(c.p), n: Array::copy(c.n), }
  result.n[c.node_id] = result.n[c.node_id] + 1
  result
}

///|
/// Get the total value: sum(P) - sum(N).
pub fn pncounter_value(c : PNCounter) -> Int {
  let mut sp = 0
  let mut sn = 0
  for i = 0; i < c.p.length(); i = i + 1 {
    sp = sp + c.p[i]
  }
  for i = 0; i < c.n.length(); i = i + 1 {
    sn = sn + c.n[i]
  }
  sp - sn
}

///|
/// Merge two PNCounters.
pub fn pncounter_merge(a : PNCounter, b : PNCounter) -> PNCounter {
  let n = if a.p.length() > b.p.length() { a.p.length() } else { b.p.length() }
  let p = Array::make(n, 0)
  let n_arr = Array::make(n, 0)
  for i = 0; i < n; i = i + 1 {
    let pa = if i < a.p.length() { a.p[i] } else { 0 }
    let pb = if i < b.p.length() { b.p[i] } else { 0 }
    p[i] = if pa > pb { pa } else { pb }
    let na = if i < a.n.length() { a.n[i] } else { 0 }
    let nb = if i < b.n.length() { b.n[i] } else { 0 }
    n_arr[i] = if na > nb { na } else { nb }
  }
  { node_id: a.node_id, p, n: n_arr, }
}

// ===========================================================================
// 3. GSet (Grow-only Set)
// ===========================================================================

///|
/// Grow-only Set (CvRDT).
///
/// Supports only insert. Merge is union. Lookup is membership test.
pub struct GSet {
  elements : Array[Int]
}

///|
/// Create an empty GSet.
pub fn gset_new() -> GSet {
  { elements: [], }
}

///|
/// Insert an element into the GSet.
pub fn gset_insert(s : GSet, elem : Int) -> GSet {
  if gset_contains(s, elem) {
    return s
  }
  let result = { elements: Array::copy(s.elements), }
  result.elements.push(elem)
  result
}

///|
/// Check if an element is in the GSet.
pub fn gset_contains(s : GSet, elem : Int) -> Bool {
  for i = 0; i < s.elements.length(); i = i + 1 {
    if s.elements[i] == elem {
      return true
    }
  }
  false
}

///|
/// Get the size of the GSet.
pub fn gset_size(s : GSet) -> Int {
  s.elements.length()
}

///|
/// Get all elements as an array.
pub fn gset_elements(s : GSet) -> Array[Int] {
  Array::copy(s.elements)
}

///|
/// Merge two GSets (union).
pub fn gset_merge(a : GSet, b : GSet) -> GSet {
  let result = { elements: Array::copy(a.elements), }
  for i = 0; i < b.elements.length(); i = i + 1 {
    if !gset_contains(result, b.elements[i]) {
      result.elements.push(b.elements[i])
    }
  }
  result
}

// ===========================================================================
// 4. TwoPhaseSet (2P-Set)
// ===========================================================================

///|
/// Two-Phase Set (CvRDT).
///
/// Two GSets: adds and removes (tombstones). An element is in the set
/// if it was added and not removed. Once removed, an element cannot be
/// re-added (add-after-remove is not supported).
pub struct TwoPhaseSet {
  adds : GSet
  removes : GSet
}

///|
/// Create an empty 2P-Set.
pub fn twophase_new() -> TwoPhaseSet {
  { adds: gset_new(), removes: gset_new(), }
}

///|
/// Add an element.
pub fn twophase_add(s : TwoPhaseSet, elem : Int) -> TwoPhaseSet {
  { adds: gset_insert(s.adds, elem), removes: s.removes, }
}

///|
/// Remove an element (must have been added first).
pub fn twophase_remove(s : TwoPhaseSet, elem : Int) -> TwoPhaseSet {
  { adds: s.adds, removes: gset_insert(s.removes, elem), }
}

///|
/// Check if an element is in the set.
pub fn twophase_contains(s : TwoPhaseSet, elem : Int) -> Bool {
  gset_contains(s.adds, elem) && !gset_contains(s.removes, elem)
}

///|
/// Merge two 2P-Sets.
pub fn twophase_merge(a : TwoPhaseSet, b : TwoPhaseSet) -> TwoPhaseSet {
  {
    adds: gset_merge(a.adds, b.adds),
    removes: gset_merge(a.removes, b.removes),
  }
}

// ===========================================================================
// 5. LWWMap (Last-Writer-Wins Map)
// ===========================================================================

///|
/// A timestamped value entry.
pub struct LWWEntry {
  value : Int
  timestamp : Int
  node_id : Int
}

///|
/// Last-Writer-Wins Map (CvRDT).
///
/// Key-value store where conflicts are resolved by timestamp.
/// Ties are broken by node_id for determinism.
pub struct LWWMap {
  node_id : Int
  entries : Array[(Int, LWWEntry)]
}

///|
/// Create an empty LWWMap.
pub fn lwwmap_new(node_id : Int) -> LWWMap {
  { node_id, entries: [], }
}

///|
/// Put a key-value pair with the given timestamp.
pub fn lwwmap_put(
  m : LWWMap,
  key : Int,
  value : Int,
  timestamp : Int,
) -> LWWMap {
  let entry = { value, timestamp, node_id: m.node_id, }
  let result = { ..m, entries: [], }
  let mut found = false
  for i = 0; i < m.entries.length(); i = i + 1 {
    let (k, e) = m.entries[i]
    if k == key {
      found = true
      // Keep the entry with the higher timestamp
      if entry.timestamp > e.timestamp ||
        (entry.timestamp == e.timestamp && entry.node_id > e.node_id) {
        result.entries.push((key, entry))
      } else {
        result.entries.push((key, e))
      }
    } else {
      result.entries.push((k, e))
    }
  }
  if !found {
    result.entries.push((key, entry))
  }
  result
}

///|
/// Get the value for a key, returns -1 if not found.
pub fn lwwmap_get(m : LWWMap, key : Int) -> Int {
  for i = 0; i < m.entries.length(); i = i + 1 {
    let (k, e) = m.entries[i]
    if k == key {
      return e.value
    }
  }
  -1
}

///|
/// Merge two LWWMaps.
pub fn lwwmap_merge(a : LWWMap, b : LWWMap) -> LWWMap {
  let result = { node_id: a.node_id, entries: Array::copy(a.entries), }
  for i = 0; i < b.entries.length(); i = i + 1 {
    let (k, e_b) = b.entries[i]
    let mut found = false
    for j = 0; j < result.entries.length(); j = j + 1 {
      let (_, e_a) = result.entries[j]
      if result.entries[j].0 == k {
        found = true
        if e_b.timestamp > e_a.timestamp ||
          (e_b.timestamp == e_a.timestamp && e_b.node_id > e_a.node_id) {
          result.entries[j] = (k, e_b)
        }
        break
      }
    }
    if !found {
      result.entries.push((k, e_b))
    }
  }
  result
}

// ===========================================================================
// 6. ORSet (Observed-Remove Set)
// ===========================================================================

///|
/// Observed-Remove Set (CvRDT).
///
/// Each add assigns a unique tag. Remove removes only the observed tags.
/// Add-after-remove is supported (re-adding with a new tag).
pub struct ORSet {
  node_id : Int
  counter : Int
  // elements: (value, tag) pairs
  elements : Array[(Int, Int)]
  // tombstones: removed tags
  tombstones : Array[Int]
}

///|
/// Create an empty ORSet.
pub fn orset_new(node_id : Int) -> ORSet {
  { node_id, counter: 0, elements: [], tombstones: [], }
}

///|
/// Add an element with a unique tag.
pub fn orset_add(s : ORSet, elem : Int) -> ORSet {
  let tag = s.counter * 1000000 + s.node_id
  let result = {
    ..s,
    counter: s.counter + 1,
    elements: Array::copy(s.elements),
    tombstones: Array::copy(s.tombstones),
  }
  result.elements.push((elem, tag))
  result
}

///|
/// Remove all instances of an element (removes observed tags).
pub fn orset_remove(s : ORSet, elem : Int) -> ORSet {
  let new_elements : Array[(Int, Int)] = []
  let new_tombstones = Array::copy(s.tombstones)
  for i = 0; i < s.elements.length(); i = i + 1 {
    let (v, tag) = s.elements[i]
    if v == elem {
      // Move to tombstones
      let mut already_tombstoned = false
      for t = 0; t < new_tombstones.length(); t = t + 1 {
        if new_tombstones[t] == tag {
          already_tombstoned = true
          break
        }
      }
      if !already_tombstoned {
        new_tombstones.push(tag)
      }
    } else {
      new_elements.push((v, tag))
    }
  }
  {
    node_id: s.node_id,
    counter: s.counter,
    elements: new_elements,
    tombstones: new_tombstones,
  }
}

///|
/// Check if an element is in the ORSet.
pub fn orset_contains(s : ORSet, elem : Int) -> Bool {
  for i = 0; i < s.elements.length(); i = i + 1 {
    if s.elements[i].0 == elem {
      return true
    }
  }
  false
}

///|
/// Get the size of the ORSet (distinct elements).
pub fn orset_size(s : ORSet) -> Int {
  let seen : Array[Int] = []
  for i = 0; i < s.elements.length(); i = i + 1 {
    let v = s.elements[i].0
    let mut found = false
    for j = 0; j < seen.length(); j = j + 1 {
      if seen[j] == v {
        found = true
        break
      }
    }
    if !found {
      seen.push(v)
    }
  }
  seen.length()
}

///|
/// Merge two ORSets.
pub fn orset_merge(a : ORSet, b : ORSet) -> ORSet {
  let all_tags : Array[Int] = []
  for i = 0; i < a.tombstones.length(); i = i + 1 {
    all_tags.push(a.tombstones[i])
  }
  for i = 0; i < b.tombstones.length(); i = i + 1 {
    let mut found = false
    for j = 0; j < all_tags.length(); j = j + 1 {
      if all_tags[j] == b.tombstones[i] {
        found = true
        break
      }
    }
    if !found {
      all_tags.push(b.tombstones[i])
    }
  }

  let mut counter = if a.counter > b.counter { a.counter } else { b.counter }
  let merged : Array[(Int, Int)] = []
  // Add elements from a that are not tombstoned
  for i = 0; i < a.elements.length(); i = i + 1 {
    let (v, tag) = a.elements[i]
    let mut tombstoned = false
    for j = 0; j < all_tags.length(); j = j + 1 {
      if all_tags[j] == tag {
        tombstoned = true
        break
      }
    }
    if !tombstoned {
      merged.push((v, tag))
    }
  }
  // Add elements from b that are not tombstoned and not duplicates
  for i = 0; i < b.elements.length(); i = i + 1 {
    let (v, tag) = b.elements[i]
    let mut tombstoned = false
    for j = 0; j < all_tags.length(); j = j + 1 {
      if all_tags[j] == tag {
        tombstoned = true
        break
      }
    }
    if !tombstoned {
      let mut already_present = false
      for j = 0; j < merged.length(); j = j + 1 {
        if merged[j].1 == tag {
          already_present = true
          break
        }
      }
      if !already_present {
        merged.push((v, tag))
      }
    }
  }

  // Update counter for merged result
  counter = if counter > a.counter { counter } else { a.counter }
  { node_id: a.node_id, counter, elements: merged, tombstones: all_tags, }
}
