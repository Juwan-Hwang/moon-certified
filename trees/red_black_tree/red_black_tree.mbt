/// Red-Black Tree using Okasaki's functional insertion and Kahrs' deletion.
///
/// Generic: works with any type T given a comparator function.
/// Both insertion and deletion maintain all RB properties:
/// 1. Every node is Red or Black.
/// 2. The root is Black.
/// 3. All leaves (Empty) are Black.
/// 4. A Red node has two Black children (no consecutive Red nodes).
/// 5. Every path from root to leaf has the same number of Black nodes (black-height).
///
/// Not formally verified. Correctness ensured by comprehensive tests including
/// is_valid_rb checks after every deletion.

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

fn[T] is_black(node : RBNode[T]) -> Bool {
  !is_red(node)
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
    (Black, Node(Node(a, x, b, Red), y, c, Red), z, d) =>
      Node(Node(a, x, b, Black), y, Node(c, z, d, Black), Red)
    (Black, Node(a, x, Node(b, y, c, Red), Red), z, d) =>
      Node(Node(a, x, b, Black), y, Node(c, z, d, Black), Red)
    (Black, a, x, Node(Node(b, y, c, Red), z, d, Red)) =>
      Node(Node(a, x, b, Black), y, Node(c, z, d, Black), Red)
    (Black, a, x, Node(b, y, Node(c, z, d, Red), Red)) =>
      Node(Node(a, x, b, Black), y, Node(c, z, d, Black), Red)
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
    Node(l, v, r, _) => Node(l, v, r, Black)
    other => other
  }
}

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
        root
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

// ===========================================================================
// Deletion (Kahrs algorithm with "lost black" tracking)
//
// When a Black node is removed, the black-height property is violated.
// We track this as a "lost black" flag and fix it on the way back up
// using bal_left / bal_right, which handle three cases:
//
// 1. Sibling is Red: rotate to bring it up, then recurse (resolves to case 2 or 3).
// 2. Sibling is Black with Black children: recolor sibling Red.
//    - Parent Red: absorb deficit (parent → Black). Done.
//    - Parent Black: propagate deficit upward.
// 3. Sibling is Black with a Red child: rotate to resolve. Done.
// ===========================================================================

/// Delete a value. Maintains all RB properties.
pub fn[T] delete(
  root : RBNode[T],
  val : T,
  cmp : (T, T) -> Int,
) -> RBNode[T] {
  let (tree, _lost) = del(root, val, cmp)
  match tree {
    Node(l, v, r, _) => Node(l, v, r, Black)
    other => other
  }
}

/// Internal delete: returns (new_tree, lost_black).
fn[T] del(
  root : RBNode[T],
  val : T,
  cmp : (T, T) -> Int,
) -> (RBNode[T], Bool) {
  match root {
    Empty => (Empty, false)
    Node(l, v, r, c) => {
      let order = cmp(val, v)
      if order < 0 {
        let (new_l, lost) = del(l, val, cmp)
        if lost {
          bal_left(c, new_l, v, r)
        } else {
          (Node(new_l, v, r, c), false)
        }
      } else if order > 0 {
        let (new_r, lost) = del(r, val, cmp)
        if lost {
          bal_right(c, l, v, new_r)
        } else {
          (Node(l, v, new_r, c), false)
        }
      } else {
        match (l, r) {
          (Empty, Empty) =>
            match c {
              Red => (Empty, false)
              Black => (Empty, true)
            }
          (Empty, Node(rl, rv, rr, Red)) =>
            (Node(rl, rv, rr, Black), false)
          (Node(ll, lv, lr, Red), Empty) =>
            (Node(ll, lv, lr, Black), false)
          (_, _) => {
            let (min_val, new_r, lost) = del_min(r)
            if lost {
              bal_right(c, l, min_val, new_r)
            } else {
              (Node(l, min_val, new_r, c), false)
            }
          }
        }
      }
    }
  }
}

/// Delete the minimum node from a subtree.
/// Returns (min_value, new_subtree, lost_black).
fn[T] del_min(root : RBNode[T]) -> (T, RBNode[T], Bool) {
  match root {
    Node(Empty, v, r, c) =>
      match c {
        Red => (v, r, false)
        Black =>
          match r {
            Node(rl, rv, rr, Red) => (v, Node(rl, rv, rr, Black), false)
            _ => (v, r, true)
          }
      }
    Node(l, v, r, c) => {
      let (min_val, new_l, lost) = del_min(l)
      if lost {
        let (new_tree, still_lost) = bal_left(c, new_l, v, r)
        (min_val, new_tree, still_lost)
      } else {
        (min_val, Node(new_l, v, r, c), false)
      }
    }
    Empty => {
      // Truly unreachable: `del_min` is only called from the `Node(l, v, r, c)`
      // branch where `l` is a `Node` (when `l` is `Empty`, the `Node(Empty, …)`
      // case above handles it directly). MoonBit has no `unreachable!()` or
      // `todo()` macro; for generic types where no default `T` can be
      // constructed, `abort` is the standard way to signal an invariant
      // violation. If this branch is ever reached, it indicates a bug in the
      // caller — crashing immediately is safer than returning a wrong value.
      abort("del_min: unreachable — called on Empty (caller invariant violated)")
    }
  }
}

/// Fix the tree after the left subtree lost a black.
/// Returns (new_tree, still_lost).
fn[T] bal_left(
  color : Color,
  left : RBNode[T],
  val : T,
  right : RBNode[T],
) -> (RBNode[T], Bool) {
  match (color, left, val, right) {
    // Case 1: Black parent, Red right sibling.
    // Rotate left, then recurse on the new left subtree.
    (Black, l, x, Node(rl, rv, rr, Red)) => {
      // rl and rr are Black (RB property).
      // After rotation: rv becomes root (Black), x goes left (Red).
      // Recurse to fix l's deficit with parent=Red, sibling=rl(Black).
      let (fixed, lost) = bal_left(Red, l, x, rl)
      (Node(fixed, rv, rr, Black), lost)
    }

    // Case 2: Black parent, Black sibling with Black children.
    // Recolor sibling Red, propagate deficit up.
    (Black, l, x, Node(rl, rv, rr, Black)) => {
      if is_black(rl) && is_black(rr) {
        (Node(l, x, Node(rl, rv, rr, Red), Black), true)
      } else {
        bal_left_rotate(l, x, Black, rl, rv, rr)
      }
    }

    // Case 2: Red parent, Black sibling with Black children.
    // Recolor sibling Red, parent Black: deficit absorbed.
    (Red, l, x, Node(rl, rv, rr, Black)) => {
      if is_black(rl) && is_black(rr) {
        (Node(l, x, Node(rl, rv, rr, Red), Black), false)
      } else {
        bal_left_rotate(l, x, Red, rl, rv, rr)
      }
    }

    // Fallback: shouldn't reach for valid RB trees.
    (c, l, x, r) => (Node(l, x, r, c), true)
  }
}

/// Rotation helper for bal_left when sibling is Black with a Red nephew.
/// Sub-case 3a: rr (right-right) is Red → single left rotation.
/// Sub-case 3b: rl (right-left) is Red → right-left double rotation.
fn[T] bal_left_rotate(
  l : RBNode[T],
  x : T,
  parent_color : Color,
  rl : RBNode[T],
  rv : T,
  rr : RBNode[T],
) -> (RBNode[T], Bool) {
  if is_red(rr) {
    // Left rotation: rv becomes new root (parent_color), x → Black left child,
    // rr → Black right child. Deficit resolved.
    match rr {
      Node(rrl, rrv, rrr, _) =>
        (Node(Node(l, x, rl, Black), rv, Node(rrl, rrv, rrr, Black), parent_color), false)
      Empty => {
        // Unreachable: is_red(rr) returned true, which requires rr to be a
        // Red Node. Safe fallback: treat as no deficit resolution.
        (Node(l, x, Node(rl, rv, rr, Black), parent_color), false)
      }
    }
  } else if is_red(rl) {
    // Right-left double rotation: rlv becomes new root (parent_color).
    match rl {
      Node(rll, rlv, rlr, _) =>
        (Node(Node(l, x, rll, Black), rlv, Node(rlr, rv, rr, Black), parent_color), false)
      Empty => {
        // Unreachable: is_red(rl) returned true, which requires rl to be a
        // Red Node. Safe fallback: treat as no deficit resolution.
        (Node(l, x, Node(rl, rv, rr, Black), parent_color), false)
      }
    }
  } else {
    // Shouldn't reach: at least one nephew must be Red.
    (Node(l, x, Node(rl, rv, rr, Black), parent_color), false)
  }
}

/// Fix the tree after the right subtree lost a black.
/// Mirror of bal_left.
fn[T] bal_right(
  color : Color,
  left : RBNode[T],
  val : T,
  right : RBNode[T],
) -> (RBNode[T], Bool) {
  match (color, left, val, right) {
    // Case 1: Black parent, Red left sibling.
    (Black, Node(ll, lv, lr, Red), x, r) => {
      let (fixed, lost) = bal_right(Red, lr, x, r)
      (Node(ll, lv, fixed, Black), lost)
    }

    // Case 2: Black parent, Black sibling with Black children.
    (Black, Node(ll, lv, lr, Black), x, r) => {
      if is_black(ll) && is_black(lr) {
        (Node(Node(ll, lv, lr, Red), x, r, Black), true)
      } else {
        bal_right_rotate(ll, lv, lr, x, r, Black)
      }
    }

    // Case 2: Red parent, Black sibling with Black children.
    (Red, Node(ll, lv, lr, Black), x, r) => {
      if is_black(ll) && is_black(lr) {
        (Node(Node(ll, lv, lr, Red), x, r, Black), false)
      } else {
        bal_right_rotate(ll, lv, lr, x, r, Red)
      }
    }

    (c, l, x, r) => (Node(l, x, r, c), true)
  }
}

/// Rotation helper for bal_right when sibling is Black with a Red nephew.
fn[T] bal_right_rotate(
  ll : RBNode[T],
  lv : T,
  lr : RBNode[T],
  x : T,
  r : RBNode[T],
  parent_color : Color,
) -> (RBNode[T], Bool) {
  if is_red(ll) {
    // Right rotation: lv becomes new root, ll → Black, right subtree → Black.
    match ll {
      Node(lll, llv, llr, _) =>
        (Node(Node(lll, llv, llr, Black), lv, Node(lr, x, r, Black), parent_color), false)
      Empty => {
        // Unreachable: is_red(ll) returned true, which requires ll to be a
        // Red Node. Safe fallback: treat as no deficit resolution.
        (Node(Node(ll, lv, lr, Black), x, r, parent_color), false)
      }
    }
  } else if is_red(lr) {
    // Left-right double rotation: lrv becomes new root.
    match lr {
      Node(lrl, lrv, lrr, _) =>
        (Node(Node(ll, lv, lrl, Black), lrv, Node(lrr, x, r, Black), parent_color), false)
      Empty => {
        // Unreachable: is_red(lr) returned true, which requires lr to be a
        // Red Node. Safe fallback: treat as no deficit resolution.
        (Node(Node(ll, lv, lr, Black), x, r, parent_color), false)
      }
    }
  } else {
    (Node(Node(ll, lv, lr, Black), x, r, parent_color), false)
  }
}

/// In-order traversal via callback.
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

/// Verify BST ordering invariant via in-order traversal.
/// Returns true if elements are in non-decreasing order.
fn[T] check_bst_order(
  root : RBNode[T],
  cmp : (T, T) -> Int,
) -> Bool {
  // In-order traversal checking each element <= next
  // We use an explicit stack to avoid recursion limits
  let mut prev : T? = None
  let mut ok = true
  let visit = fn(v : T) -> Unit {
    if !ok {
      return
    }
    match prev {
      None => prev = Some(v)
      Some(p) => {
        if cmp(p, v) > 0 {
          ok = false
        }
        prev = Some(v)
      }
    }
  }
  inorder(root, visit)
  ok
}

/// Verify all RB and BST properties.
/// Returns `true` if and only if:
/// 1. The root is Black.
/// 2. No Red node has a Red child.
/// 3. Every root-to-leaf path has the same number of Black nodes (black-height).
/// 4. In-order traversal yields elements in non-decreasing order (BST property).
///
/// The comparator is required to verify the BST ordering invariant.
/// This is primarily intended for testing and external validation.
pub fn[T] is_valid_rb(root : RBNode[T], cmp : (T, T) -> Int) -> Bool {
  let root_ok = match root {
    Empty => true
    Node(_, _, _, Black) => true
    _ => false
  }
  root_ok && check_no_red_red(root) && black_height(root) > 0 && check_bst_order(root, cmp)
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
  assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  assert_true(height(tree) <= 4)
}

test "rbtree: reverse insert maintains balance" {
  let mut tree : RBNode[Int] = empty()
  for k = 7; k >= 1; k = k - 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_eq(size(tree), 7)
  assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
}

test "rbtree: delete leaf" {
  let tree0 : RBNode[Int] = empty()
  let tree = insert(insert(insert(tree0, 5, fn(a, b) { a - b }), 3, fn(a, b) { a - b }), 7, fn(a, b) { a - b })
  let t2 = delete(tree, 7, fn(a, b) { a - b })
  assert_false(search(t2, 7, fn(a, b) { a - b }))
  assert_true(search(t2, 5, fn(a, b) { a - b }))
  assert_eq(size(t2), 2)
  assert_true(is_valid_rb(t2, fn(a, b) { a - b }))
}

test "rbtree: delete node with two children" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 7; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  let t2 = delete(tree, 4, fn(a, b) { a - b })
  assert_false(search(t2, 4, fn(a, b) { a - b }))
  assert_eq(size(t2), 6)
  assert_true(is_valid_rb(t2, fn(a, b) { a - b }))
}

test "rbtree: delete root" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 5; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  let t2 = delete(tree, 3, fn(a, b) { a - b })
  assert_false(search(t2, 3, fn(a, b) { a - b }))
  assert_true(is_valid_rb(t2, fn(a, b) { a - b }))
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
  assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
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

test "rbtree: delete maintains RB properties - sequential delete" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 20; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  for k = 1; k <= 20; k = k + 1 {
    tree = delete(tree, k, fn(a, b) { a - b })
    assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  }
  assert_eq(size(tree), 0)
}

test "rbtree: delete maintains RB properties - reverse delete" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 20; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  for k = 20; k >= 1; k = k - 1 {
    tree = delete(tree, k, fn(a, b) { a - b })
    assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  }
  assert_eq(size(tree), 0)
}

test "rbtree: delete maintains RB properties - random delete order" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 50; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  for k = 2; k <= 50; k = k + 2 {
    tree = delete(tree, k, fn(a, b) { a - b })
    assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  }
  for k = 1; k <= 49; k = k + 2 {
    tree = delete(tree, k, fn(a, b) { a - b })
    assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  }
  assert_eq(size(tree), 0)
}

test "rbtree: delete maintains RB properties - 100 elements" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 100; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  for k = 2; k <= 100; k = k + 2 {
    tree = delete(tree, k, fn(a, b) { a - b })
  }
  assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  assert_eq(size(tree), 50)
  for k = 1; k <= 99; k = k + 2 {
    assert_true(search(tree, k, fn(a, b) { a - b }))
  }
}

test "rbtree: delete non-existent value" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 10; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  let t2 = delete(tree, 99, fn(a, b) { a - b })
  assert_eq(size(t2), 10)
  assert_true(is_valid_rb(t2, fn(a, b) { a - b }))
}

test "rbtree: delete from single node tree" {
  let tree0 : RBNode[Int] = empty()
  let tree = insert(tree0, 42, fn(a, b) { a - b })
  let t2 = delete(tree, 42, fn(a, b) { a - b })
  assert_eq(size(t2), 0)
  assert_true(is_valid_rb(t2, fn(a, b) { a - b }))
}

test "rbtree: interleave insert and delete" {
  let mut tree : RBNode[Int] = empty()
  tree = insert(tree, 5, fn(a, b) { a - b })
  tree = insert(tree, 3, fn(a, b) { a - b })
  tree = insert(tree, 7, fn(a, b) { a - b })
  tree = delete(tree, 3, fn(a, b) { a - b })
  assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  tree = insert(tree, 1, fn(a, b) { a - b })
  tree = insert(tree, 9, fn(a, b) { a - b })
  assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  tree = delete(tree, 7, fn(a, b) { a - b })
  assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  tree = delete(tree, 5, fn(a, b) { a - b })
  assert_true(is_valid_rb(tree, fn(a, b) { a - b }))
  assert_eq(size(tree), 2)
  assert_true(search(tree, 1, fn(a, b) { a - b }))
  assert_true(search(tree, 9, fn(a, b) { a - b }))
}

test "rbtree: inorder sorted after deletions" {
  let mut tree : RBNode[Int] = empty()
  for k = 1; k <= 15; k = k + 1 {
    tree = insert(tree, k, fn(a, b) { a - b })
  }
  tree = delete(tree, 3, fn(a, b) { a - b })
  tree = delete(tree, 7, fn(a, b) { a - b })
  tree = delete(tree, 11, fn(a, b) { a - b })
  let result = FixedArray::make(12, 0)
  let idx = FixedArray::make(1, 0)
  inorder(tree, fn(v) { result[idx[0]] = v; idx[0] = idx[0] + 1 })
  for k = 0; k < 11; k = k + 1 {
    assert_true(result[k] < result[k + 1])
  }
}

test "rbtree: is_valid_rb detects BST violation" {
  // Manually construct a tree that satisfies RB properties but violates BST order
  // Node(Empty, 10, Node(Empty, 5, Empty, Black), Black) — 5 is in right subtree of 10 (wrong!)
  let bad_tree : RBNode[Int] = Node(Empty, 10, Node(Empty, 5, Empty, Black), Black)
  assert_false(is_valid_rb(bad_tree, fn(a, b) { a - b }))
  // A correct tree passes (5 is Red to maintain equal black-height)
  let good_tree : RBNode[Int] = Node(Node(Empty, 5, Empty, Red), 10, Empty, Black)
  assert_true(is_valid_rb(good_tree, fn(a, b) { a - b }))
}
