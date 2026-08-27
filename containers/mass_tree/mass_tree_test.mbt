// Tests for MassTree — a real B+ tree with splits, lazy collapse on
// delete and separator routing. Includes model-based stress testing
// against a sorted-array model.

///|
fn unwrap_int(opt : Int?) -> Int raise {
  match opt {
    Some(v) => v
    None => fail("expected Some, got None")
  }
}

///|
fn expect_none_int(opt : Int?) -> Unit raise {
  match opt {
    Some(_) => fail("expected None, got Some")
    None => ()
  }
}

///|
struct MassTestRng {
  mut state : Int
}

///|
fn MassTestRng::new(seed : Int) -> MassTestRng {
  { state: seed }
}

///|
fn MassTestRng::next(self : MassTestRng) -> Int {
  let s = (self.state.to_int64() * 1103515245L + 12345L) % 2147483648L
  self.state = s.to_int()
  self.state
}

///|
test "mass_tree_empty" {
  let t = MassTree::new()
  assert_eq(t.size, 0)
  expect_none_int(t.search(1))
  assert_eq(t.to_array().length(), 0)
  assert_eq(t.delete(1), false)
  assert_eq(t.verify_invariants(), true)
}

///|
test "mass_tree_basic" {
  let t = MassTree::new()
  t.insert(10, 100)
  assert_eq(t.size, 1)
  assert_eq(unwrap_int(t.search(10)), 100)
  expect_none_int(t.search(11))
  t.insert(10, 111) // update in place
  assert_eq(t.size, 1)
  assert_eq(unwrap_int(t.search(10)), 111)
  assert_eq(t.delete(10), true)
  assert_eq(t.size, 0)
  assert_eq(t.delete(10), false)
}

///|
// The old implementation silently dropped every key past the 8th.
// Verify that overflow now triggers real leaf splits and multi-level
// growth.
test "mass_tree_overflow_forces_splits" {
  let t = MassTree::new()
  let n = 2000
  for i = 0; i < n; i = i + 1 {
    t.insert(i, i * 3)
    assert_eq(t.verify_invariants(), true)
  }
  assert_eq(t.size, n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(unwrap_int(t.search(i)), i * 3)
  }
  let arr = t.to_array()
  assert_eq(arr.length(), n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(arr[i], (i, i * 3))
  }
}

///|
test "mass_tree_random_order_and_delete_all" {
  let n = 1500
  let rng = MassTestRng::new(99)
  let perm = Array::new()
  for i = 0; i < n; i = i + 1 {
    perm.push(i)
  }
  for i = n - 1; i > 0; i = i - 1 {
    let j = rng.next() % (i + 1)
    let tmp = perm[i]
    perm[i] = perm[j]
    perm[j] = tmp
  }
  let t = MassTree::new()
  for i = 0; i < n; i = i + 1 {
    t.insert(perm[i], perm[i] + 100)
  }
  assert_eq(t.size, n)
  assert_eq(t.verify_invariants(), true)
  let arr = t.to_array()
  for i = 0; i < n; i = i + 1 {
    assert_eq(arr[i], (i, i + 100))
  }
  // Re-shuffle and delete everything; the tree must collapse cleanly.
  for i = n - 1; i > 0; i = i - 1 {
    let j = rng.next() % (i + 1)
    let tmp = perm[i]
    perm[i] = perm[j]
    perm[j] = tmp
  }
  for i = 0; i < n; i = i + 1 {
    assert_eq(t.delete(perm[i]), true, msg="deleting \{perm[i]}")
    expect_none_int(t.search(perm[i]))
    assert_eq(t.delete(perm[i]), false)
    if i % 200 == 199 {
      assert_eq(t.verify_invariants(), true)
      assert_eq(t.size, n - i - 1)
      assert_eq(t.to_array().length(), n - i - 1)
    }
  }
  assert_eq(t.size, 0)
  assert_eq(t.to_array().length(), 0)
  assert_eq(t.verify_invariants(), true)
  // Reusable after being drained.
  t.insert(5, 50)
  assert_eq(unwrap_int(t.search(5)), 50)
}

///|
// Model-based stress: interleaved random inserts/deletes cross-checked
// against a sorted-array model.
test "mass_tree_model_based_stress" {
  let ops = 3000
  let rng = MassTestRng::new(2026)
  let t = MassTree::new()
  let model : Array[(Int, Int)] = []
  let mut next_key = 0
  for op = 0; op < ops; op = op + 1 {
    let action = rng.next() % 10
    if action < 6 || model.length() == 0 {
      // Insert a fresh key.
      let k = next_key
      next_key = next_key + 1
      t.insert(k, k * 2)
      model.push((k, k * 2))
      model.sort()
    } else {
      // Delete a random existing key.
      let idx = rng.next() % model.length()
      let k = model[idx].0
      ignore(model.remove(idx))
      assert_eq(t.delete(k), true, msg="op \{op} delete \{k}")
    }
    assert_eq(t.size, model.length())
    if op % 100 == 99 {
      assert_eq(t.verify_invariants(), true)
      let arr = t.to_array()
      assert_eq(arr.length(), model.length())
      for i = 0; i < model.length(); i = i + 1 {
        assert_eq(arr[i], model[i])
      }
    }
  }
  assert_eq(t.verify_invariants(), true)
  let arr = t.to_array()
  assert_eq(arr.length(), model.length())
  for i = 0; i < model.length(); i = i + 1 {
    assert_eq(arr[i], model[i])
  }
}
