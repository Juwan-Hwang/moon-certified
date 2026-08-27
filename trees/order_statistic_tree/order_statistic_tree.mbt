/// Order Statistic Tree — a Red-Black Tree augmented with subtree sizes
/// for O(log n) order-statistic queries.
///
/// An **Order Statistic Tree** (OST) is a balanced BST where each node
/// stores the **size** of its subtree (number of internal nodes). This
/// augmentation enables two fundamental operations beyond ordinary BSTs:
///
/// - **`select(k)`**: Find the k-th smallest key (1-indexed) — O(log n).
/// - **`rank(key)`**: Count the number of keys strictly less than `key` — O(log n).
///
/// ## Red-Black Properties
///
/// 1. Every node is Red or Black.
/// 2. The root is Black.
/// 3. Every leaf (None) is Black.
/// 4. A Red node has two Black children (no two consecutive Reds on a path).
/// 5. Every path from a node to a descendant leaf has the same number of
///    Black nodes (the **black-height**).
///
/// ## Complexity
///
/// | Operation   | Time     |
/// |-------------|----------|
/// | `insert`    | O(log n) |
/// | `remove`    | O(log n) |
/// | `contains`  | O(log n) |
/// | `select`    | O(log n) |
/// | `rank`      | O(log n) |
/// | `size`      | O(1)     |
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///|
priv enum Color {
  Red
  Black
}

///|
priv struct OstNode[T] {
  key : T
  mut left : OstNode[T]?
  mut right : OstNode[T]?
  mut parent : OstNode[T]?
  mut color : Color
  mut size : Int
}

///|
pub struct OrderStatisticTree[T] {
  priv mut root : OstNode[T]?
  priv compare : (T, T) -> Int
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
pub fn[T] OrderStatisticTree::new(
  compare : (T, T) -> Int,
) -> OrderStatisticTree[T] {
  { root: None, compare, }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
fn[T] size_of(n : OstNode[T]?) -> Int {
  match n {
    Some(node) => node.size
    None => 0
  }
}

///|
fn color_is_red(c : Color) -> Bool {
  match c {
    Red => true
    Black => false
  }
}

///|
fn[T] node_is_red(n : OstNode[T]?) -> Bool {
  match n {
    Some(node) => color_is_red(node.color)
    None => false
  }
}

///|
fn[T] is_black(n : OstNode[T]?) -> Bool {
  !node_is_red(n)
}

///|
fn[T] update_size(n : OstNode[T]) -> Unit {
  n.size = size_of(n.left) + size_of(n.right) + 1
}

///|
/// Check if `child` is the left child of `parent` using the BST property.
/// Since keys are unique, `child.key < parent.key` iff child is the left child.
fn[T] OrderStatisticTree::is_left_child(
  self : OrderStatisticTree[T],
  parent : OstNode[T],
  child : OstNode[T],
) -> Bool {
  (self.compare)(child.key, parent.key) < 0
}

// ---------------------------------------------------------------------------
// Basic queries
// ---------------------------------------------------------------------------

///|
pub fn[T] OrderStatisticTree::size(self : OrderStatisticTree[T]) -> Int {
  size_of(self.root)
}

///|
pub fn[T] OrderStatisticTree::is_empty(self : OrderStatisticTree[T]) -> Bool {
  self.root is None
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

///|
pub fn[T] OrderStatisticTree::contains(
  self : OrderStatisticTree[T],
  key : T,
) -> Bool {
  let mut cur = self.root
  while cur is Some(_) {
    match cur {
      Some(n) => {
        let c = (self.compare)(key, n.key)
        if c == 0 {
          return true
        } else if c < 0 {
          cur = n.left
        } else {
          cur = n.right
        }
      }
      None => return false
    }
  }
  false
}

///|
pub fn[T] OrderStatisticTree::find_min(self : OrderStatisticTree[T]) -> T? {
  match self.root {
    None => None
    Some(root) => {
      let mut cur = root
      while cur.left is Some(_) {
        match cur.left {
          Some(l) => cur = l
          None => break
        }
      }
      Some(cur.key)
    }
  }
}

///|
pub fn[T] OrderStatisticTree::find_max(self : OrderStatisticTree[T]) -> T? {
  match self.root {
    None => None
    Some(root) => {
      let mut cur = root
      while cur.right is Some(_) {
        match cur.right {
          Some(r) => cur = r
          None => break
        }
      }
      Some(cur.key)
    }
  }
}

// ---------------------------------------------------------------------------
// Order statistics
// ---------------------------------------------------------------------------

///|
/// Find the k-th smallest key (1-indexed). Returns `None` if out of range.
pub fn[T] OrderStatisticTree::select(
  self : OrderStatisticTree[T],
  k : Int,
) -> T? {
  if k < 1 || k > size_of(self.root) {
    return None
  }
  let mut cur = self.root
  let mut k = k
  while cur is Some(_) {
    match cur {
      Some(n) => {
        let left_size = size_of(n.left)
        if k == left_size + 1 {
          return Some(n.key)
        } else if k <= left_size {
          cur = n.left
        } else {
          k = k - left_size - 1
          cur = n.right
        }
      }
      None => return None
    }
  }
  None
}

///|
/// Count the number of keys strictly less than `key`. O(log n).
pub fn[T] OrderStatisticTree::rank(
  self : OrderStatisticTree[T],
  key : T,
) -> Int {
  let mut count = 0
  let mut cur = self.root
  while cur is Some(_) {
    match cur {
      Some(n) => {
        let c = (self.compare)(key, n.key)
        if c <= 0 {
          cur = n.left
        } else {
          count = count + size_of(n.left) + 1
          cur = n.right
        }
      }
      None => break
    }
  }
  count
}

///|
/// Count the number of keys ≤ `key`. O(log n).
pub fn[T] OrderStatisticTree::count_less_equal(
  self : OrderStatisticTree[T],
  key : T,
) -> Int {
  let mut count = 0
  let mut cur = self.root
  while cur is Some(_) {
    match cur {
      Some(n) => {
        let c = (self.compare)(key, n.key)
        if c < 0 {
          cur = n.left
        } else {
          count = count + size_of(n.left) + 1
          cur = n.right
        }
      }
      None => break
    }
  }
  count
}

// ---------------------------------------------------------------------------
// Rotations
// ---------------------------------------------------------------------------

///|
fn[T] OrderStatisticTree::left_rotate(
  self : OrderStatisticTree[T],
  x : OstNode[T],
) -> Unit {
  let y = match x.right {
    Some(n) => n
    None => return
  }
  x.right = y.left
  match y.left {
    Some(yl) => yl.parent = Some(x)
    None => ()
  }
  y.parent = x.parent
  match x.parent {
    None => self.root = Some(y)
    Some(p) =>
      if self.is_left_child(p, x) {
        p.left = Some(y)
      } else {
        p.right = Some(y)
      }
  }
  y.left = Some(x)
  x.parent = Some(y)
  update_size(x)
  update_size(y)
}

///|
fn[T] OrderStatisticTree::right_rotate(
  self : OrderStatisticTree[T],
  y : OstNode[T],
) -> Unit {
  let x = match y.left {
    Some(n) => n
    None => return
  }
  y.left = x.right
  match x.right {
    Some(xr) => xr.parent = Some(y)
    None => ()
  }
  x.parent = y.parent
  match y.parent {
    None => self.root = Some(x)
    Some(p) =>
      if self.is_left_child(p, y) {
        p.left = Some(x)
      } else {
        p.right = Some(x)
      }
  }
  x.right = Some(y)
  y.parent = Some(x)
  update_size(y)
  update_size(x)
}

// ---------------------------------------------------------------------------
// Insertion
// ---------------------------------------------------------------------------

///|
pub fn[T] OrderStatisticTree::insert(
  self : OrderStatisticTree[T],
  key : T,
) -> Bool {
  let mut parent : OstNode[T]? = None
  let mut cur = self.root
  while cur is Some(_) {
    match cur {
      Some(n) => {
        parent = Some(n)
        let c = (self.compare)(key, n.key)
        if c == 0 {
          return false
        } else if c < 0 {
          cur = n.left
        } else {
          cur = n.right
        }
      }
      None => break
    }
  }
  let new_node : OstNode[T] = {
    key,
    left: None,
    right: None,
    parent,
    color: Red,
    size: 1,
  }
  match parent {
    None => self.root = Some(new_node)
    Some(p) => {
      let c = (self.compare)(key, p.key)
      if c < 0 {
        p.left = Some(new_node)
      } else {
        p.right = Some(new_node)
      }
    }
  }
  let mut ancestor = parent
  while ancestor is Some(_) {
    match ancestor {
      Some(a) => {
        a.size = a.size + 1
        ancestor = a.parent
      }
      None => break
    }
  }
  self.insert_fixup(new_node)
  true
}

///|
fn[T] OrderStatisticTree::insert_fixup(
  self : OrderStatisticTree[T],
  start_node : OstNode[T],
) -> Unit {
  let mut node = start_node
  while node.parent is Some(_) {
    let parent = match node.parent {
      Some(p) => p
      None => break
    }
    let grandparent = match parent.parent {
      Some(gp) => gp
      None => break
    }
    if !color_is_red(parent.color) {
      break
    }
    // Parent is Red → violation. Grandparent must exist and be Black.
    if self.is_left_child(grandparent, parent) {
      // Parent is left child
      let uncle = grandparent.right
      if node_is_red(uncle) {
        // Case 1: Uncle is Red
        parent.color = Black
        match uncle {
          Some(u) => u.color = Black
          None => ()
        }
        grandparent.color = Red
        node = grandparent
      } else if !self.is_left_child(parent, node) {
        // Case 2: node is right child
        node = parent
        self.left_rotate(node)
        // Re-fetch parent and grandparent after rotation
        let new_parent = match node.parent {
          Some(p) => p
          None => break
        }
        let new_gp = match new_parent.parent {
          Some(gp) => gp
          None => break
        }
        // Case 3
        new_parent.color = Black
        new_gp.color = Red
        self.right_rotate(new_gp)
      } else {
        // Case 3: node is left child
        parent.color = Black
        grandparent.color = Red
        self.right_rotate(grandparent)
      }
    } else {
      // Parent is right child — symmetric
      let uncle = grandparent.left
      if node_is_red(uncle) {
        parent.color = Black
        match uncle {
          Some(u) => u.color = Black
          None => ()
        }
        grandparent.color = Red
        node = grandparent
      } else if self.is_left_child(parent, node) {
        // Case 2: node is left child
        node = parent
        self.right_rotate(node)
        let new_parent = match node.parent {
          Some(p) => p
          None => break
        }
        let new_gp = match new_parent.parent {
          Some(gp) => gp
          None => break
        }
        new_parent.color = Black
        new_gp.color = Red
        self.left_rotate(new_gp)
      } else {
        // Case 3: node is right child
        parent.color = Black
        grandparent.color = Red
        self.left_rotate(grandparent)
      }
    }
  }
  match self.root {
    Some(r) => r.color = Black
    None => ()
  }
}

// ---------------------------------------------------------------------------
// Deletion
// ---------------------------------------------------------------------------

///|
fn[T] OrderStatisticTree::transplant(
  self : OrderStatisticTree[T],
  u : OstNode[T],
  v : OstNode[T]?,
) -> Unit {
  match u.parent {
    None => self.root = v
    Some(p) => if self.is_left_child(p, u) { p.left = v } else { p.right = v }
  }
  match v {
    Some(vn) => vn.parent = u.parent
    None => ()
  }
}

///|
fn[T] minimum_node(node : OstNode[T]) -> OstNode[T] {
  let mut cur = node
  while cur.left is Some(_) {
    match cur.left {
      Some(l) => cur = l
      None => break
    }
  }
  cur
}

///|
pub fn[T] OrderStatisticTree::remove(
  self : OrderStatisticTree[T],
  key : T,
) -> Bool {
  let mut target = self.root
  while target is Some(_) {
    match target {
      Some(n) => {
        let c = (self.compare)(key, n.key)
        if c == 0 {
          target = Some(n)
          break
        } else if c < 0 {
          target = n.left
        } else {
          target = n.right
        }
      }
      None => break
    }
  }
  let z = match target {
    Some(n) => n
    None => return false
  }
  self.delete_node(z)
  true
}

///|
fn[T] OrderStatisticTree::delete_node(
  self : OrderStatisticTree[T],
  z : OstNode[T],
) -> Unit {
  let mut y_original_color : Color = z.color
  let mut x : OstNode[T]? = None
  let mut x_parent : OstNode[T]? = None
  let mut x_is_left = false
  let mut size_fixup_start : OstNode[T]? = None

  if z.left is None {
    x = z.right
    x_parent = z.parent
    match z.parent {
      Some(p) => x_is_left = self.is_left_child(p, z)
      None => x_is_left = false
    }
    size_fixup_start = z.parent
    self.transplant(z, z.right)
  } else if z.right is None {
    x = z.left
    x_parent = z.parent
    match z.parent {
      Some(p) => x_is_left = self.is_left_child(p, z)
      None => x_is_left = false
    }
    size_fixup_start = z.parent
    self.transplant(z, z.left)
  } else {
    let z_right = match z.right {
      Some(r) => r
      None => return
    }
    let y = minimum_node(z_right)
    y_original_color = y.color
    x = y.right
    let y_is_direct_child = match y.parent {
      Some(yp) => (self.compare)(yp.key, z.key) == 0
      None => false
    }
    if y_is_direct_child {
      x_parent = Some(y)
      x_is_left = false
    } else {
      x_parent = y.parent
      x_is_left = true
      self.transplant(y, y.right)
      y.right = z.right
      match y.right {
        Some(r) => r.parent = Some(y)
        None => ()
      }
    }
    size_fixup_start = if y_is_direct_child { Some(y) } else { x_parent }
    self.transplant(z, Some(y))
    y.left = z.left
    match y.left {
      Some(l) => l.parent = Some(y)
      None => ()
    }
    y.color = z.color
    update_size(y)
  }

  let mut ancestor = size_fixup_start
  while ancestor is Some(_) {
    match ancestor {
      Some(a) => {
        update_size(a)
        ancestor = a.parent
      }
      None => break
    }
  }

  let need_fixup = match y_original_color {
    Black => true
    Red => false
  }
  if need_fixup {
    self.delete_fixup(x, x_parent, x_is_left)
  }
}

///|
fn[T] OrderStatisticTree::delete_fixup(
  self : OrderStatisticTree[T],
  x_start : OstNode[T]?,
  x_parent_start : OstNode[T]?,
  x_is_left_start : Bool,
) -> Unit {
  let mut x = x_start
  let mut x_parent = x_parent_start
  let mut x_is_left = x_is_left_start

  while is_black(x) && x_parent is Some(_) {
    let p = match x_parent {
      Some(p) => p
      None => break
    }
    if x_is_left {
      // x is left child; sibling is right child
      let w = match p.right {
        Some(w) => w
        None => break
      }
      if color_is_red(w.color) {
        // Case 1: sibling is Red
        w.color = Black
        p.color = Red
        self.left_rotate(p)
      }
      // Re-fetch sibling
      let w2 = match p.right {
        Some(w) => w
        None => break
      }
      if is_black(w2.left) && is_black(w2.right) {
        // Case 2
        w2.color = Red
        x = Some(p)
        x_parent = p.parent
        match p.parent {
          Some(pp) => x_is_left = self.is_left_child(pp, p)
          None => x_is_left = false
        }
      } else {
        if is_black(w2.right) {
          // Case 3: far child Black, near child Red
          match w2.left {
            Some(wl) => wl.color = Black
            None => ()
          }
          w2.color = Red
          self.right_rotate(w2)
        }
        // Case 4: far child Red
        let w3 = match p.right {
          Some(w) => w
          None => break
        }
        w3.color = p.color
        p.color = Black
        match w3.right {
          Some(wr) => wr.color = Black
          None => ()
        }
        self.left_rotate(p)
        x = self.root
        x_parent = None
      }
    } else {
      // Symmetric: x is right child; sibling is left child
      let w = match p.left {
        Some(w) => w
        None => break
      }
      if color_is_red(w.color) {
        w.color = Black
        p.color = Red
        self.right_rotate(p)
      }
      let w2 = match p.left {
        Some(w) => w
        None => break
      }
      if is_black(w2.right) && is_black(w2.left) {
        // Case 2
        w2.color = Red
        x = Some(p)
        x_parent = p.parent
        match p.parent {
          Some(pp) => x_is_left = self.is_left_child(pp, p)
          None => x_is_left = false
        }
      } else {
        if is_black(w2.left) {
          // Case 3: far child (left) Black, near child (right) Red
          match w2.right {
            Some(wr) => wr.color = Black
            None => ()
          }
          w2.color = Red
          self.left_rotate(w2)
        }
        // Case 4
        let w3 = match p.left {
          Some(w) => w
          None => break
        }
        w3.color = p.color
        p.color = Black
        match w3.left {
          Some(wl) => wl.color = Black
          None => ()
        }
        self.right_rotate(p)
        x = self.root
        x_parent = None
      }
    }
  }
  match x {
    Some(n) => n.color = Black
    None => ()
  }
}

// ---------------------------------------------------------------------------
// Traversal & validation
// ---------------------------------------------------------------------------

///|
pub fn[T] OrderStatisticTree::to_sorted_array(
  self : OrderStatisticTree[T],
) -> Array[T] {
  let result : Array[T] = []
  self.inorder(self.root, result)
  result
}

///|
fn[T] OrderStatisticTree::inorder(
  self : OrderStatisticTree[T],
  node : OstNode[T]?,
  result : Array[T],
) -> Unit {
  match node {
    None => ()
    Some(n) => {
      self.inorder(n.left, result)
      result.push(n.key)
      self.inorder(n.right, result)
    }
  }
}

///|
/// Verify all RB properties and size invariants. Returns `true` if valid.
pub fn[T] OrderStatisticTree::is_valid(self : OrderStatisticTree[T]) -> Bool {
  match self.root {
    None => true
    Some(root) => {
      if color_is_red(root.color) {
        return false
      }
      let bh = self.check_rb(Some(root))
      bh >= 0
    }
  }
}

///|
/// Returns black-height if valid, -1 if not.
fn[T] OrderStatisticTree::check_rb(
  self : OrderStatisticTree[T],
  node : OstNode[T]?,
) -> Int {
  match node {
    None => 1
    Some(n) => {
      // Red node must have Black children
      if color_is_red(n.color) {
        if node_is_red(n.left) || node_is_red(n.right) {
          return -1
        }
      }
      // Size invariant
      if n.size != size_of(n.left) + size_of(n.right) + 1 {
        return -1
      }
      // BST property
      match n.left {
        Some(l) => if (self.compare)(l.key, n.key) >= 0 { return -1 }
        None => ()
      }
      match n.right {
        Some(r) => if (self.compare)(r.key, n.key) <= 0 { return -1 }
        None => ()
      }
      let lbh = self.check_rb(n.left)
      let rbh = self.check_rb(n.right)
      if lbh < 0 || rbh < 0 || lbh != rbh {
        return -1
      }
      match n.color {
        Black => lbh + 1
        Red => lbh
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
fn cmp_int(a : Int, b : Int) -> Int {
  a - b
}

///|
test "ost: empty tree" {
  let t = OrderStatisticTree::new(cmp_int)
  assert_true(t.is_empty())
  assert_true(t.size() == 0)
  assert_true(t.contains(0) == false)
  assert_true(t.select(1) == None)
  assert_true(t.find_min() == None)
  assert_true(t.find_max() == None)
  assert_true(t.rank(0) == 0)
  assert_true(t.is_valid())
}

///|
test "ost: insert and search" {
  let t = OrderStatisticTree::new(cmp_int)
  assert_true(t.insert(5))
  assert_true(t.insert(3))
  assert_true(t.insert(8))
  assert_true(t.insert(1))
  assert_true(t.insert(4))
  assert_true(t.size() == 5)
  assert_true(t.contains(3))
  assert_true(t.contains(8))
  assert_true(t.contains(1))
  assert_true(t.contains(4))
  assert_true(t.contains(5))
  assert_true(t.contains(0) == false)
  assert_true(t.contains(6) == false)
  assert_true(t.is_valid())
}

///|
test "ost: insert duplicate" {
  let t = OrderStatisticTree::new(cmp_int)
  assert_true(t.insert(5))
  assert_true(t.insert(3))
  assert_true(t.insert(5) == false)
  assert_true(t.size() == 2)
  assert_true(t.is_valid())
}

///|
test "ost: select k-th" {
  let t = OrderStatisticTree::new(cmp_int)
  for i = 0; i < 10; i = i + 1 {
    ignore(t.insert(i * 3 + 7))
  }
  assert_true(t.size() == 10)
  for i = 1; i <= 10; i = i + 1 {
    let v = t.select(i)
    assert_true(v == Some((i - 1) * 3 + 7))
  }
  assert_true(t.select(0) == None)
  assert_true(t.select(11) == None)
  assert_true(t.is_valid())
}

///|
test "ost: rank" {
  let t = OrderStatisticTree::new(cmp_int)
  let vals = [50, 30, 70, 20, 40, 60, 80]
  for i = 0; i < vals.length(); i = i + 1 {
    ignore(t.insert(vals[i]))
  }
  assert_true(t.rank(10) == 0)
  assert_true(t.rank(20) == 0)
  assert_true(t.rank(25) == 1)
  assert_true(t.rank(50) == 3)
  assert_true(t.rank(80) == 6)
  assert_true(t.rank(90) == 7)
  assert_true(t.is_valid())
}

///|
test "ost: count_less_equal" {
  let t = OrderStatisticTree::new(cmp_int)
  let vals = [50, 30, 70, 20, 40, 60, 80]
  for i = 0; i < vals.length(); i = i + 1 {
    ignore(t.insert(vals[i]))
  }
  assert_true(t.count_less_equal(10) == 0)
  assert_true(t.count_less_equal(20) == 1)
  assert_true(t.count_less_equal(50) == 4)
  assert_true(t.count_less_equal(80) == 7)
  assert_true(t.count_less_equal(90) == 7)
  assert_true(t.is_valid())
}

///|
test "ost: find_min find_max" {
  let t = OrderStatisticTree::new(cmp_int)
  assert_true(t.find_min() == None)
  assert_true(t.find_max() == None)
  ignore(t.insert(5))
  assert_true(t.find_min() == Some(5))
  assert_true(t.find_max() == Some(5))
  ignore(t.insert(3))
  ignore(t.insert(8))
  assert_true(t.find_min() == Some(3))
  assert_true(t.find_max() == Some(8))
  assert_true(t.is_valid())
}

///|
test "ost: remove leaf" {
  let t = OrderStatisticTree::new(cmp_int)
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(8))
  assert_true(t.remove(3))
  assert_true(t.size() == 2)
  assert_true(t.contains(3) == false)
  assert_true(t.contains(5))
  assert_true(t.contains(8))
  assert_true(t.is_valid())
}

///|
test "ost: remove node with one child" {
  let t = OrderStatisticTree::new(cmp_int)
  ignore(t.insert(5))
  ignore(t.insert(3))
  ignore(t.insert(8))
  ignore(t.insert(9))
  assert_true(t.remove(8))
  assert_true(t.size() == 3)
  assert_true(t.contains(8) == false)
  assert_true(t.contains(9))
  assert_true(t.is_valid())
}

///|
test "ost: remove node with two children" {
  let t = OrderStatisticTree::new(cmp_int)
  let vals = [50, 30, 70, 20, 40, 60, 80]
  for i = 0; i < vals.length(); i = i + 1 {
    ignore(t.insert(vals[i]))
  }
  assert_true(t.remove(50))
  assert_true(t.size() == 6)
  assert_true(t.contains(50) == false)
  let sorted = t.to_sorted_array()
  assert_true(sorted.length() == 6)
  assert_true(sorted[0] == 20)
  assert_true(sorted[5] == 80)
  assert_true(t.is_valid())
}

///|
test "ost: remove root" {
  let t = OrderStatisticTree::new(cmp_int)
  ignore(t.insert(5))
  assert_true(t.remove(5))
  assert_true(t.is_empty())
  assert_true(t.is_valid())
}

///|
test "ost: remove nonexistent" {
  let t = OrderStatisticTree::new(cmp_int)
  ignore(t.insert(5))
  ignore(t.insert(3))
  assert_true(t.remove(10) == false)
  assert_true(t.size() == 2)
  assert_true(t.is_valid())
}

///|
test "ost: remove all and reinsert" {
  let t = OrderStatisticTree::new(cmp_int)
  for i = 0; i < 20; i = i + 1 {
    ignore(t.insert(i))
  }
  for i = 0; i < 20; i = i + 1 {
    assert_true(t.remove(i))
    assert_true(t.is_valid())
  }
  assert_true(t.is_empty())
  for i = 0; i < 20; i = i + 1 {
    ignore(t.insert(i * 2))
  }
  assert_true(t.size() == 20)
  assert_true(t.is_valid())
  for i = 1; i <= 20; i = i + 1 {
    assert_true(t.select(i) == Some((i - 1) * 2))
  }
}

///|
test "ost: stress test 1000 elements" {
  let t = OrderStatisticTree::new(cmp_int)
  let mut seed = 42
  let inserted : Array[Int] = []
  for i = 0; i < 1000; i = i + 1 {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    let val = seed % 10000
    if t.insert(val) {
      inserted.push(val)
    }
  }
  assert_true(t.size() == inserted.length())
  assert_true(t.is_valid())
  let sorted = t.to_sorted_array()
  for i = 0; i < sorted.length(); i = i + 1 {
    assert_true(t.select(i + 1) == Some(sorted[i]))
    assert_true(t.rank(sorted[i]) == i)
  }
  let half = inserted.length() / 2
  for i = 0; i < half; i = i + 1 {
    assert_true(t.remove(inserted[i]))
  }
  assert_true(t.is_valid())
  assert_true(t.size() == inserted.length() - half)
  for i = half; i < inserted.length(); i = i + 1 {
    assert_true(t.remove(inserted[i]))
  }
  assert_true(t.is_empty())
  assert_true(t.is_valid())
}

///|
test "ost: reverse insertion order" {
  let t = OrderStatisticTree::new(cmp_int)
  for i = 100; i >= 1; i = i - 1 {
    ignore(t.insert(i))
  }
  assert_true(t.size() == 100)
  assert_true(t.is_valid())
  for i = 1; i <= 100; i = i + 1 {
    assert_true(t.select(i) == Some(i))
    assert_true(t.rank(i) == i - 1)
  }
}

///|
test "ost: remove every other element" {
  let t = OrderStatisticTree::new(cmp_int)
  for i = 0; i < 100; i = i + 1 {
    ignore(t.insert(i))
  }
  for i = 0; i < 100; i = i + 2 {
    assert_true(t.remove(i))
    assert_true(t.is_valid())
  }
  assert_true(t.size() == 50)
  for i = 1; i <= 50; i = i + 1 {
    assert_true(t.select(i) == Some(2 * i - 1))
  }
}

///|
test "ost: to_sorted_array" {
  let t = OrderStatisticTree::new(cmp_int)
  let vals = [5, 3, 8, 1, 9, 2, 7, 4, 6, 0]
  for i = 0; i < vals.length(); i = i + 1 {
    ignore(t.insert(vals[i]))
  }
  let sorted = t.to_sorted_array()
  for i = 0; i < sorted.length(); i = i + 1 {
    assert_true(sorted[i] == i)
  }
}
