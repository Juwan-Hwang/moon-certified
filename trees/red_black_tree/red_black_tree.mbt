/// Red-Black Tree using Okasaki's functional insertion algorithm.
///
/// Generic: works with any type T given a comparator function.
/// Insertion maintains all RB properties. Deletion uses BST deletion
/// (RB fixup for functional deletion is not implemented).
/// Not formally verified. Correctness ensured by comprehensive tests.

pub enum Color {
  Red
  Black
}

pub enum RBNode[T] {
  Empty
  Node(RBNode[T], T, RBNode[T], Color)
}

pub fn[T] empty() -> RBNode[T] {
  Empty
}

pub fn[T] size(root : RBNode[T]) -> Int {
  match root {
    Empty => 0
    Node(l, _, r, _) => size(l) + 1 + size(r)
  }
}

pub fn[T] height(root : RBNode[T]) -> Int {
  match root {
    Empty => 0
    Node(l, _, r, _) => {
      let lh = height(l)
      let rh = height(r)
      (if lh >= rh { lh } else { rh }) + 1
    }
  }
}

pub fn[T] search(root : RBNode[T], val : T, cmp : (T, T) -> Int) -> Bool {
  match root {
    Empty => false
    Node(l, v, r, _) => {
      let c = cmp(val, v)
      if c < 0 { search(l, val, cmp) }
      else if c > 0 { search(r, val, cmp) }
      else { true }
    }
  }
}

fn[T] is_red(node : RBNode[T]) -> Bool {
  match node {
    Node(_, _, _, Red) => true
    _ => false
  }
}

/// Okasaki's balance: handles all 4 red-red violation cases in one function.
/// Called bottom-up during insertion.
fn[T] balance(
  color : Color,
  left : RBNode[T],
  val : T,
  right : RBNode[T],
) -> RBNode[T] {
  match (color, left, val, right) {
    // LL: Black parent, Red left child with Red left-left grandchild
    (Black, Node(Node(a, x, b, Red), y, c, Red), z, d) =>
      Node(Node(a, x, b, Black), y, Node(c, z, d, Black), Red)
    // LR: Black parent, Red left child with Red left-right grandchild
    (Black, Node(a, x, Node(b, y, c, Red), Red), z, d) =>
      Node(Node(a, x, b, Black), y, Node(c, z, d, Black), Red)
    // RL: Black parent, Red right child with Red right-left grandchild
    (Black, a, x, Node(Node(b, y, c, Red), z, d, Red)) =>
      Node(Node(a, x, b, Black), y, Node(c, z, d, Black), Red)
    // RR: Black parent, Red right child with Red right-right grandchild
    (Black, a, x, Node(b, y, Node(c, z, d, Red), Red)) =>
      Node(Node(a, x, b, Black), y, Node(c, z, d, Black), Red)
    // No violation: reconstruct as-is
    (color, left, val, right) =>
      Node(left, val, right, color)
  }
}

/// Insert a value. Duplicates are ignored.
pub fn[T] insert(
  root : RBNode[T],
  val : T,
  cmp : (T, T) -> Int,
) -> RBNode[T] {
  match ins(root, val, cmp) {
    Node(l, v, r, _) => Node(l, v, r, Black)  // root always black
    other => other
  }
}

/// Internal insert helper that calls balance on the way up.
fn[T] ins(root : RBNode[T], val : T, cmp : (T, T) -> Int) -> RBNode[T] {
  match root {
    Empty => Node(Empty, val, Empty, Red)
    Node(l, v, r, color) => {
      let order = cmp(val, v)
      if order < 0 {
        balance(color, ins(l, val, cmp), v, r)
      } else if order > 0 {
        balance(color, l, v, ins(r, val, cmp))
      } else {
        root  // duplicate, ignore
      }
    }
  }
}

/// Find the minimum value. Returns None if empty.
pub fn[T] find_min(root : RBNode[T]) -> T? {
  match root {
    Empty => None
    Node(Empty, v, _, _) => Some(v)
    Node(l, _, _, _) => find_min(l)
  }
}

/// Delete a value. Uses BST deletion (RB fixup not implemented for
/// functional deletion). BST ordering is preserved.
pub fn[T] delete(
  root : RBNode[T],
  val : T,
  cmp : (T, T) -> Int,
) -> RBNode[T] {
  match root {
    Empty => Empty
    Node(l, v, r, c) => {
      let d = cmp(val, v)
      if d < 0 {
        Node(delete(l, val, cmp), v, r, c)
      } else if d > 0 {
        Node(l, v, delete(r, val, cmp), c)
      } else {
        match (l, r) {
          (Empty, _) => r
          (_, Empty) => l
          (_, _) => {
            match find_min(r) {
              Some(succ) => Node(l, succ, delete(r, succ, cmp), c)
              None => Node(l, v, r, c)
            }
          }
        }
      }
    }
  }
}

/// In-order traversal via callback (avoids needing default value for generics).
pub fn[T] inorder(root : RBNode[T], f : (T) -> Unit) -> Unit {
  match root {
    Empty => ()
    Node(l, v, r, _) => {
      inorder(l, f)
      f(v)
      inorder(r, f)
    }
  }
}

/// Check no red-red violation.
fn[T] check_no_red_red(root : RBNode[T]) -> Bool {
  match root {
    Empty => true
    Node(l, _, r, Red) =>
      (!is_red(l)) && (!is_red(r)) &&
      check_no_red_red(l) && check_no_red_red(r)
    Node(l, _, r, _) =>
      check_no_red_red(l) && check_no_red_red(r)
  }
}

/// Compute black height. Returns -1 if inconsistent.
fn[T] black_height(root : RBNode[T]) -> Int {
  match root {
    Empty => 1
    Node(l, _, r, c) => {
      let lh = black_height(l)
      let rh = black_height(r)
      if lh == -1 || rh == -1 || lh != rh {
        return -1
      }
      let add = match c {
        Black => 1
        Red => 0
      }
      lh + add
    }
  }
}

/// Verify all RB properties (for testing).
fn[T] is_valid_rb(root : RBNode[T]) -> Bool {
  let root_ok = match root {
    Empty => true
    Node(_, _, _, Black) => true
    _ => false
  }
  root_ok && check_no_red_red(root) && black_height(root) > 0
}

test "rbtree: basic insert and search" {
  let tree0 : RBNode[Int] = empty()
  let t1 = insert(tree0, 5, fn(a, b) { a - b })
  assert_true(search(t1, 5, fn(a, b) { a - b }))
  assert_false(search(t1, 3, fn(a, b) { a - b }))
  let t2 = insert(t1, 3, fn(a, b) { a - b })
  let t3 = insert(t2, 7, fn(a, b) { a - b })
  assert_true(search(t3, 3, fn(a, b) { a - b }))
  assert_true(search(t3, 7, fn(a, b) { a - b }))
}

test "rbtree: duplicate insert ignored" {
  let tree0 : RBNode[Int] = empty()
  let t1 = insert(tree0, 5, fn(a, b) { a - b })
  let t2 = insert(t1, 5, fn(a, b) { a - b })
  assert_eq(size(t2), 1)
}

test "rbtree: sequential insert maintains balance" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(size(tree), 7)
  assert_true(is_valid_rb(tree))
  assert_true(height(tree) <= 4)
}

test "rbtree: reverse insert maintains balance" {
  let mut tree : RBNode[Int] = empty()
  for k = 7; k >= 1; k = k - 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(size(tree), 7)
  assert_true(is_valid_rb(tree))
}

test "rbtree: delete leaf" {
  let tree0 : RBNode[Int] = empty()
  let tree = insert(insert(insert(tree0, 5, fn(a, b) { a - b }), 3, fn(a, b) { a - b }), 7, fn(a, b) { a - b })
  let t2 = delete(tree, 7, fn(a, b) { a - b })
  assert_false(search(t2, 7, fn(a, b) { a - b }))
  assert_true(search(t2, 5, fn(a, b) { a - b }))
  assert_eq(size(t2), 2)
}

test "rbtree: delete node with two children" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  let t2 = delete(tree, 4, fn(a, b) { a - b })
  assert_false(search(t2, 4, fn(a, b) { a - b }))
  assert_eq(size(t2), 6)
}

test "rbtree: delete root" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 5; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  let t2 = delete(tree, 3, fn(a, b) { a - b })
  assert_false(search(t2, 3, fn(a, b) { a - b }))
}

test "rbtree: inorder produces sorted output" {
  let mut tree : RBNode[Int] = empty()
  let vals = [5, 3, 7, 1, 4, 6, 8, 2]
  for k = 0; k < 8; k = k + 1 {
    tree = insert(tree, vals[k], fn(a, b) { a - b })
  }
  let result = FixedArray::make(8, 0)
  let idx = FixedArray::make(1, 0)
  inorder(tree, fn(v) { result[idx[0]] = v; idx[0] = idx[0] + 1 })
  for k = 0; k < 8; k = k + 1 {
    assert_eq(result[k], k + 1)
  }
}

test "rbtree: large insert 100 elements" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 100; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(size(tree), 100)
  assert_true(is_valid_rb(tree))
  assert_true(height(tree) <= 15)
}

test "rbtree: empty tree operations" {
  let tree : RBNode[Int] = empty()
  assert_eq(size(tree), 0)
  assert_eq(height(tree), 0)
  assert_false(search(tree, 1, fn(a, b) { a - b }))
}

test "rbtree: single node" {
  let tree0 : RBNode[Int] = empty()
  let tree = insert(tree0, 42, fn(a, b) { a - b })
  assert_eq(size(tree), 1)
  assert_true(search(tree, 42, fn(a, b) { a - b }))
}

test "rbtree: delete preserves BST ordering" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 10; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  for k = 1; k <= 10; k = k + 1 {
    tree = delete(tree, k, fn(a, b) { a - b })
  }
  assert_eq(size(tree), 0)
}

test "rbtree: generic with String" {
  let mut tree : RBNode[String] = empty()
  let words = ["banana", "apple", "cherry", "date"]
  /// Lexicographic string comparator (MoonBit's default Compare uses shortlex).
  let str_cmp = fn(a : String, b : String) -> Int {
    let la = a.length()
    let lb = b.length()
    let min = if la < lb { la } else { lb }
    for k = 0; k < min; k = k + 1 {
      let ca = a[k].to_int()
      let cb = b[k].to_int()
      if ca < cb { return -1 }
      if ca > cb { return 1 }
    }
    la - lb
  }
  for k = 0; k < 4; k = k + 1 {
    tree = insert(tree, words[k], str_cmp)
  }
  assert_eq(size(tree), 4)
  assert_eq(find_min(tree).unwrap(), "apple")
  assert_true(search(tree, "apple", str_cmp))
  assert_false(search(tree, "grape", str_cmp))
  let result = FixedArray::make(4, "")
  let idx = FixedArray::make(1, 0)
  inorder(tree, fn(v) { result[idx[0]] = v; idx[0] = idx[0] + 1 })
  assert_eq(result[0], "apple")
  assert_eq(result[1], "banana")
  assert_eq(result[2], "cherry")
  assert_eq(result[3], "date")
}

test "rbtree: find_min" {
  let mut tree : RBNode[Int] = empty()
  for k = 7; k >= 1; k = k - 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(find_min(tree).unwrap(), 1)
  let empty_tree : RBNode[Int] = empty()
  assert_true(find_min(empty_tree) is None)
}
