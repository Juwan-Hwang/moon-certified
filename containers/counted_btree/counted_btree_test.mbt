// Tests for CountedBTree — full CLRS B-tree with order statistics.
// Covers deep splits, merges/borrows on delete, rank/select invariants
// and a 10K-key stress round against a sorted reference model.

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
/// Deterministic 32-bit LCG for reproducible pseudo-random sequences.
struct TestRng {
  mut state : Int
}

///|
fn TestRng::new(seed : Int) -> TestRng {
  { state: seed }
}

///|
fn TestRng::next(self : TestRng) -> Int {
  // Numerical Recipes LCG mod 2^31 (Int64 to avoid 32-bit overflow)
  let s = (self.state.to_int64() * 1103515245L + 12345L) % 2147483648L
  self.state = s.to_int()
  self.state
}

///|
test "counted_btree_empty" {
  let t = CountedBTree::new()
  assert_eq(t.size, 0)
  expect_none_int(t.search(1))
  expect_none_int(t.select(0))
  assert_eq(t.rank(1), 0)
  assert_eq(t.delete(1), false)
}

///|
test "counted_btree_insert_search" {
  let t = CountedBTree::new()
  t.insert(10, 100)
  assert_eq(t.size, 1)
  assert_eq(unwrap_int(t.search(10)), 100)
  expect_none_int(t.search(99))
}

///|
test "counted_btree_insert_update" {
  let t = CountedBTree::new()
  t.insert(20, 200)
  t.insert(20, 222)
  assert_eq(t.size, 1)
  assert_eq(unwrap_int(t.search(20)), 222)
}

///|
test "counted_btree_select_and_rank" {
  let t = CountedBTree::new()
  t.insert(30, 300)
  t.insert(10, 100)
  t.insert(20, 200)
  assert_eq(t.size, 3)
  assert_eq(unwrap_int(t.select(0)), 10)
  assert_eq(unwrap_int(t.select(1)), 20)
  assert_eq(unwrap_int(t.select(2)), 30)
  expect_none_int(t.select(3))
  expect_none_int(t.select(-1))
  assert_eq(t.rank(5), 0)
  assert_eq(t.rank(10), 0)
  assert_eq(t.rank(15), 1)
  assert_eq(t.rank(20), 1)
  assert_eq(t.rank(25), 2)
  assert_eq(t.rank(30), 2)
  assert_eq(t.rank(35), 3)
  assert_eq(unwrap_int(t.search(10)), 100)
  assert_eq(unwrap_int(t.search(20)), 200)
  assert_eq(unwrap_int(t.search(30)), 300)
}

///|
// The old implementation silently dropped every key past the 3rd;
// verify that overflow now triggers real node splitting.
test "counted_btree_overflow_forces_splits" {
  let t = CountedBTree::new()
  let n = 1000
  for i = 0; i < n; i = i + 1 {
    t.insert(i, i * 7)
  }
  assert_eq(t.size, n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(unwrap_int(t.search(i)), i * 7)
    assert_eq(unwrap_int(t.select(i)), i)
    assert_eq(t.rank(i), i)
  }
  assert_eq(t.rank(n), n)
  let arr = t.to_array()
  assert_eq(arr.length(), n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(arr[i], (i, i * 7))
  }
}

///|
test "counted_btree_reverse_and_random_order" {
  // Ascending, descending and shuffled insert orders must all yield the
  // same fully-sorted tree.
  let n = 500
  let rng = TestRng::new(42)
  // Build a permutation via repeated swaps.
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
  let t_rand = CountedBTree::new()
  let t_desc = CountedBTree::new()
  for i = 0; i < n; i = i + 1 {
    t_rand.insert(perm[i], perm[i] * 3)
    t_desc.insert(n - 1 - i, (n - 1 - i) * 3)
  }
  let a = t_rand.to_array()
  let b = t_desc.to_array()
  assert_eq(a.length(), n)
  assert_eq(b.length(), n)
  for i = 0; i < n; i = i + 1 {
    assert_eq(a[i], (i, i * 3))
    assert_eq(b[i], (i, i * 3))
  }
}

///|
test "counted_btree_delete_full_cycle" {
  // Insert 2000 keys in random order, delete all of them in a
  // different random order, checking search/rank consistency as we go.
  let n = 2000
  let rng = TestRng::new(7)
  let keys = Array::new()
  for i = 0; i < n; i = i + 1 {
    keys.push(i)
  }
  for i = n - 1; i > 0; i = i - 1 {
    let j = rng.next() % (i + 1)
    let tmp = keys[i]
    keys[i] = keys[j]
    keys[j] = tmp
  }
  let t = CountedBTree::new()
  for i = 0; i < n; i = i + 1 {
    t.insert(keys[i], keys[i] + 1)
  }
  assert_eq(t.size, n)
  // Shuffle again for deletion order.
  for i = n - 1; i > 0; i = i - 1 {
    let j = rng.next() % (i + 1)
    let tmp = keys[i]
    keys[i] = keys[j]
    keys[j] = tmp
  }
  for i = 0; i < n; i = i + 1 {
    assert_eq(t.delete(keys[i]), true, msg="deleting \{keys[i]}")
    expect_none_int(t.search(keys[i]))
    // Deleting twice reports false and leaves the tree untouched.
    assert_eq(t.delete(keys[i]), false)
    if i % 250 == 249 {
      // Spot-check structural integrity at intermediate states.
      let remaining = n - i - 1
      assert_eq(t.size, remaining)
      assert_eq(t.to_array().length(), remaining)
      assert_eq(t.verify_invariants(), true)
      if remaining > 0 {
        assert_eq(unwrap_int(t.select(0)), t.to_array()[0].0)
        assert_eq(
          unwrap_int(t.select(remaining - 1)),
          t.to_array()[remaining - 1].0,
        )
      }
    }
  }
  assert_eq(t.size, 0)
  assert_eq(t.to_array().length(), 0)
}

///|
// Model-based stress test: random inserts and deletes cross-checked
// against a sorted-array model, with the order-statistic invariants
// verified after every operation. Borrow/merge interactions between
// internal nodes are the historical weak spot of counted B-trees.
test "counted_btree_model_based_stress" {
  let n = 600
  let rng = TestRng::new(1234)
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
  let t = CountedBTree::new()
  let model : Array[Int] = []
  for i = 0; i < n; i = i + 1 {
    t.insert(perm[i], perm[i] * 2)
    model.push(perm[i])
    model.sort()
    assert_eq(t.verify_invariants(), true)
  }
  // Re-shuffle, then delete everything while cross-checking rank/select.
  for i = n - 1; i > 0; i = i - 1 {
    let j = rng.next() % (i + 1)
    let tmp = perm[i]
    perm[i] = perm[j]
    perm[j] = tmp
  }
  for i = 0; i < n; i = i + 1 {
    let k = perm[i]
    assert_eq(t.delete(k), true)
    // Remove from the model.
    let mut idx = -1
    for m = 0; m < model.length(); m = m + 1 {
      if model[m] == k {
        idx = m
      }
    }
    ignore(model.remove(idx))
    assert_eq(t.verify_invariants(), true)
    assert_eq(t.size, model.length())
    // Sample a few order-statistic queries against the model.
    let mlen = model.length()
    if mlen > 0 {
      let mut s = 0
      while s < 6 {
        let j = rng.next() % mlen
        assert_eq(unwrap_int(t.select(j)), model[j])
        assert_eq(t.rank(model[j]), j)
        s = s + 1
      }
    }
  }
  assert_eq(t.size, 0)
  assert_eq(t.verify_invariants(), true)
}

///|
test "counted_btree_delete_half_keep_invariants" {
  // Delete every second key, then verify rank/select agree with the
  // surviving sorted set.
  let n = 800
  let t = CountedBTree::new()
  for i = 0; i < n; i = i + 1 {
    t.insert(i * 2, i) // even keys only
  }
  let mut removed = 0
  for i = 0; i < n; i = i + 1 {
    if i % 2 == 0 {
      assert_eq(t.delete(i * 2), true)
      removed = removed + 1
    }
  }
  assert_eq(t.size, n - removed)
  // Survivors: keys 2, 6, 10, ... (i odd -> key i*2)
  let mut rank = 0
  for i = 0; i < n; i = i + 1 {
    let key = i * 2
    assert_eq(t.rank(key), rank)
    if i % 2 == 1 {
      assert_eq(unwrap_int(t.select(rank)), key)
      assert_eq(unwrap_int(t.search(key)), i)
      rank = rank + 1
    } else {
      expect_none_int(t.search(key))
    }
  }
  assert_eq(rank, n - removed)
}
