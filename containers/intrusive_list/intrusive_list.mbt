/// Intrusive Doubly-Linked List
///
/// In an intrusive linked list, the list node *is part of* the data object,
/// not a wrapper around it. This design:
///
/// - Eliminates per-element allocation overhead (nodes are embedded).
/// - Allows O(1) removal given a direct node reference (no search needed).
/// - Enables an element to live in multiple lists simultaneously (each list
///   uses a different link field).
/// - Makes the list itself O(1) in space (just head/tail/count).
///
/// ## Complexity
/// - push_front / push_back / pop_front / pop_back: **O(1)**
/// - insert_before / insert_after / remove: **O(1)**
/// - get / index_of: **O(n)**
/// - size: **O(1)** (maintained incrementally)
///
/// `proof-enabled` is `false`.

///|
/// A doubly-linked intrusive list node. The user data is stored in `value`.
/// The `prev` / `next` fields are managed by `IntrusiveList`.
pub struct IntrusiveNode {
  /// User payload
  value : Int
  /// Link to previous node (None if head)
  mut prev : IntrusiveNode?
  /// Link to next node (None if tail)
  mut next : IntrusiveNode?
}

///|
/// Create a new standalone node with the given value.
pub fn IntrusiveNode::new(value : Int) -> IntrusiveNode {
  { value, prev: None, next: None }
}

///|
/// Intrusive doubly-linked list.
///
/// The list stores only head/tail/count; the nodes own their links.
/// Removing a node is O(1) given the node reference.
pub struct IntrusiveList {
  priv mut head : IntrusiveNode?
  priv mut tail : IntrusiveNode?
  priv mut len : Int
}

///|
/// Create a new empty intrusive list.
pub fn IntrusiveList::new() -> IntrusiveList {
  { head: None, tail: None, len: 0 }
}

///|
/// Number of elements in the list. O(1).
pub fn IntrusiveList::size(self : IntrusiveList) -> Int {
  self.len
}

///|
/// Is the list empty? O(1).
pub fn IntrusiveList::is_empty(self : IntrusiveList) -> Bool {
  self.len == 0
}

///|
/// Get the head node (None if empty).
pub fn IntrusiveList::front(self : IntrusiveList) -> IntrusiveNode? {
  self.head
}

///|
/// Get the tail node (None if empty).
pub fn IntrusiveList::back(self : IntrusiveList) -> IntrusiveNode? {
  self.tail
}

///|
/// Insert `node` at the front of the list. O(1).
pub fn IntrusiveList::push_front(
  self : IntrusiveList,
  node : IntrusiveNode,
) -> Unit {
  node.prev = None
  node.next = self.head
  match self.head {
    Some(h) => h.prev = Some(node)
    None => self.tail = Some(node)
  }
  self.head = Some(node)
  self.len = self.len + 1
}

///|
/// Insert `node` at the back of the list. O(1).
pub fn IntrusiveList::push_back(
  self : IntrusiveList,
  node : IntrusiveNode,
) -> Unit {
  node.next = None
  node.prev = self.tail
  match self.tail {
    Some(t) => t.next = Some(node)
    None => self.head = Some(node)
  }
  self.tail = Some(node)
  self.len = self.len + 1
}

///|
/// Remove and return the front node. Returns None if empty. O(1).
pub fn IntrusiveList::pop_front(self : IntrusiveList) -> IntrusiveNode? {
  match self.head {
    None => None
    Some(h) => {
      self.head = h.next
      match self.head {
        Some(new_h) => new_h.prev = None
        None => self.tail = None
      }
      h.next = None
      h.prev = None
      self.len = self.len - 1
      Some(h)
    }
  }
}

///|
/// Remove and return the back node. Returns None if empty. O(1).
pub fn IntrusiveList::pop_back(self : IntrusiveList) -> IntrusiveNode? {
  match self.tail {
    None => None
    Some(t) => {
      self.tail = t.prev
      match self.tail {
        Some(new_t) => new_t.next = None
        None => self.head = None
      }
      t.next = None
      t.prev = None
      self.len = self.len - 1
      Some(t)
    }
  }
}

///|
/// Insert `new_node` before `target` in the list. O(1).
/// `target` must already be in the list.
pub fn IntrusiveList::insert_before(
  self : IntrusiveList,
  target : IntrusiveNode,
  new_node : IntrusiveNode,
) -> Unit {
  new_node.next = Some(target)
  new_node.prev = target.prev
  match target.prev {
    Some(p) => p.next = Some(new_node)
    None => self.head = Some(new_node)
  }
  target.prev = Some(new_node)
  self.len = self.len + 1
}

///|
/// Insert `new_node` after `target` in the list. O(1).
/// `target` must already be in the list.
pub fn IntrusiveList::insert_after(
  self : IntrusiveList,
  target : IntrusiveNode,
  new_node : IntrusiveNode,
) -> Unit {
  new_node.prev = Some(target)
  new_node.next = target.next
  match target.next {
    Some(n) => n.prev = Some(new_node)
    None => self.tail = Some(new_node)
  }
  target.next = Some(new_node)
  self.len = self.len + 1
}

///|
/// Remove `node` from the list in O(1). The node must be in this list.
/// After removal, the node's `prev` and `next` are set to None.
pub fn IntrusiveList::remove(
  self : IntrusiveList,
  node : IntrusiveNode,
) -> Unit {
  match node.prev {
    Some(p) => p.next = node.next
    None => self.head = node.next
  }
  match node.next {
    Some(n) => n.prev = node.prev
    None => self.tail = node.prev
  }
  node.prev = None
  node.next = None
  self.len = self.len - 1
}

///|
/// Get the element at `index` (0-based). Returns None if out of bounds. O(n).
pub fn IntrusiveList::get(self : IntrusiveList, index : Int) -> Int? {
  if index < 0 || index >= self.len {
    return None
  }
  let mut cur = self.head
  for _i = 0; _i < index; _i = _i + 1 {
    cur = match cur {
      Some(c) => c.next
      None => return None
    }
  }
  match cur {
    Some(c) => Some(c.value)
    None => None
  }
}

///|
/// Convert to an array of values. O(n).
pub fn IntrusiveList::to_array(self : IntrusiveList) -> Array[Int] {
  let result : Array[Int] = []
  let mut cur = self.head
  while cur is Some(node) {
    result.push(node.value)
    cur = node.next
  }
  result
}

///|
/// Clear the list (detach all nodes). O(n).
pub fn IntrusiveList::clear(self : IntrusiveList) -> Unit {
  let mut cur = self.head
  while cur is Some(node) {
    let nxt = node.next
    node.prev = None
    node.next = None
    cur = nxt
  }
  self.head = None
  self.tail = None
  self.len = 0
}

///|
/// Apply `f` to each element value. O(n).
pub fn IntrusiveList::for_each(self : IntrusiveList, f : (Int) -> Unit) -> Unit {
  let mut cur = self.head
  while cur is Some(node) {
    f(node.value)
    cur = node.next
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "intrusive_list: push_back and iterate" {
  let list = IntrusiveList::new()
  list.push_back(IntrusiveNode::new(10))
  list.push_back(IntrusiveNode::new(20))
  list.push_back(IntrusiveNode::new(30))
  assert_eq(list.size(), 3)
  let arr = list.to_array()
  assert_eq(arr, [10, 20, 30])
}

///|
test "intrusive_list: push_front and iterate" {
  let list = IntrusiveList::new()
  list.push_front(IntrusiveNode::new(1))
  list.push_front(IntrusiveNode::new(2))
  list.push_front(IntrusiveNode::new(3))
  assert_eq(list.size(), 3)
  let arr = list.to_array()
  assert_eq(arr, [3, 2, 1])
}

///|
test "intrusive_list: pop_front and pop_back" {
  let list = IntrusiveList::new()
  list.push_back(IntrusiveNode::new(1))
  list.push_back(IntrusiveNode::new(2))
  list.push_back(IntrusiveNode::new(3))
  let front = list.pop_front()
  assert_eq(front.unwrap().value, 1)
  let back = list.pop_back()
  assert_eq(back.unwrap().value, 3)
  assert_eq(list.size(), 1)
  assert_eq(list.to_array(), [2])
}

///|
test "intrusive_list: insert_before" {
  let list = IntrusiveList::new()
  let n1 = IntrusiveNode::new(10)
  let n2 = IntrusiveNode::new(20)
  let n3 = IntrusiveNode::new(15)
  list.push_back(n1)
  list.push_back(n2)
  list.insert_before(n2, n3)
  assert_eq(list.to_array(), [10, 15, 20])
  assert_eq(list.size(), 3)
}

///|
test "intrusive_list: insert_after" {
  let list = IntrusiveList::new()
  let n1 = IntrusiveNode::new(10)
  let n2 = IntrusiveNode::new(20)
  let n3 = IntrusiveNode::new(15)
  list.push_back(n1)
  list.push_back(n2)
  list.insert_after(n1, n3)
  assert_eq(list.to_array(), [10, 15, 20])
  assert_eq(list.size(), 3)
}

///|
test "intrusive_list: remove by node reference O(1)" {
  let list = IntrusiveList::new()
  let n1 = IntrusiveNode::new(10)
  let n2 = IntrusiveNode::new(20)
  let n3 = IntrusiveNode::new(30)
  list.push_back(n1)
  list.push_back(n2)
  list.push_back(n3)
  list.remove(n2)
  assert_eq(list.size(), 2)
  assert_eq(list.to_array(), [10, 30])
  // Removed node should be detached
  assert_true(n2.prev is None)
  assert_true(n2.next is None)
}

///|
test "intrusive_list: remove head and tail" {
  let list = IntrusiveList::new()
  let n1 = IntrusiveNode::new(1)
  let n2 = IntrusiveNode::new(2)
  let n3 = IntrusiveNode::new(3)
  list.push_back(n1)
  list.push_back(n2)
  list.push_back(n3)
  list.remove(n1)
  assert_eq(list.to_array(), [2, 3])
  list.remove(n3)
  assert_eq(list.to_array(), [2])
  assert_eq(list.size(), 1)
}

///|
test "intrusive_list: get by index" {
  let list = IntrusiveList::new()
  for i = 0; i < 5; i = i + 1 {
    list.push_back(IntrusiveNode::new(i * 10))
  }
  assert_eq(list.get(0).unwrap(), 0)
  assert_eq(list.get(2).unwrap(), 20)
  assert_eq(list.get(4).unwrap(), 40)
  assert_true(list.get(5) is None)
  assert_true(list.get(-1) is None)
}

///|
test "intrusive_list: empty operations" {
  let list = IntrusiveList::new()
  assert_true(list.is_empty())
  assert_eq(list.size(), 0)
  assert_true(list.pop_front() is None)
  assert_true(list.pop_back() is None)
  assert_true(list.front() is None)
  assert_true(list.back() is None)
}

///|
test "intrusive_list: clear" {
  let list = IntrusiveList::new()
  for i = 0; i < 10; i = i + 1 {
    list.push_back(IntrusiveNode::new(i))
  }
  list.clear()
  assert_eq(list.size(), 0)
  assert_true(list.is_empty())
  assert_true(list.front() is None)
  assert_true(list.back() is None)
}

///|
test "intrusive_list: for_each" {
  let list = IntrusiveList::new()
  for i = 0; i < 5; i = i + 1 {
    list.push_back(IntrusiveNode::new(i))
  }
  let sum : Array[Int] = []
  list.for_each(fn(v) { sum.push(v) })
  assert_eq(sum, [0, 1, 2, 3, 4])
}

///|
test "intrusive_list: front and back accessors" {
  let list = IntrusiveList::new()
  let n1 = IntrusiveNode::new(100)
  let n2 = IntrusiveNode::new(200)
  list.push_back(n1)
  list.push_back(n2)
  assert_eq(list.front().unwrap().value, 100)
  assert_eq(list.back().unwrap().value, 200)
}

///|
test "intrusive_list: stress test" {
  let list = IntrusiveList::new()
  // Push 100 elements
  for i = 0; i < 100; i = i + 1 {
    list.push_back(IntrusiveNode::new(i))
  }
  assert_eq(list.size(), 100)
  // Remove every other element from front
  for _i = 0; _i < 50; _i = _i + 1 {
    let _ = list.pop_front()
    let _ = list.pop_front()
    list.push_back(IntrusiveNode::new(-1))
  }
  assert_eq(list.size(), 50)
}
