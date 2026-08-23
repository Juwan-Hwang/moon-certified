// ===========================================================================
// GCounter Tests
// ===========================================================================

///|
test "gcounter_basic" {
  let c = gcounter_new(0, 3)
  assert_eq(gcounter_value(c), 0)
  let c1 = gcounter_increment(c)
  assert_eq(gcounter_value(c1), 1)
  let c2 = gcounter_increment(c1)
  assert_eq(gcounter_value(c2), 2)
}

///|
test "gcounter_merge" {
  // Node 0 increments 3 times, node 1 increments 2 times
  let c0 = gcounter_increment(
    gcounter_increment(gcounter_increment(gcounter_new(0, 3))),
  )
  let c1 = gcounter_increment(gcounter_increment(gcounter_new(1, 3)))
  let merged = gcounter_merge(c0, c1)
  assert_eq(gcounter_value(merged), 5)
}

///|
test "gcounter_idempotent_merge" {
  let c = gcounter_increment(gcounter_new(0, 3))
  let merged = gcounter_merge(c, c)
  assert_eq(gcounter_value(merged), 1)
}

///|
test "gcounter_commutative_merge" {
  let c0 = gcounter_increment(gcounter_new(0, 3))
  let c1 = gcounter_increment(gcounter_new(1, 3))
  let m01 = gcounter_merge(c0, c1)
  let m10 = gcounter_merge(c1, c0)
  assert_eq(gcounter_value(m01), gcounter_value(m10))
}

// ===========================================================================
// PNCounter Tests
// ===========================================================================

///|
test "pncounter_basic" {
  let c = pncounter_new(0, 3)
  assert_eq(pncounter_value(c), 0)
  let c1 = pncounter_increment(c)
  assert_eq(pncounter_value(c1), 1)
  let c2 = pncounter_decrement(c1)
  assert_eq(pncounter_value(c2), 0)
}

///|
test "pncounter_merge" {
  let c0 = pncounter_increment(pncounter_increment(pncounter_new(0, 3)))
  let c1 = pncounter_decrement(pncounter_new(1, 3))
  let merged = pncounter_merge(c0, c1)
  assert_eq(pncounter_value(merged), 1)
}

///|
test "pncounter_negative_value" {
  let c = pncounter_decrement(pncounter_decrement(pncounter_new(0, 3)))
  assert_eq(pncounter_value(c), -2)
}

// ===========================================================================
// GSet Tests
// ===========================================================================

///|
test "gset_basic" {
  let s = gset_new()
  assert_eq(gset_size(s), 0)
  let s1 = gset_insert(s, 42)
  assert_eq(gset_size(s1), 1)
  assert_true(gset_contains(s1, 42))
  assert_false(gset_contains(s1, 99))
}

///|
test "gset_duplicate_insert" {
  let s = gset_insert(gset_insert(gset_new(), 1), 1)
  assert_eq(gset_size(s), 1)
}

///|
test "gset_merge" {
  let a = gset_insert(gset_insert(gset_new(), 1), 2)
  let b = gset_insert(gset_insert(gset_new(), 2), 3)
  let merged = gset_merge(a, b)
  assert_eq(gset_size(merged), 3)
  assert_true(gset_contains(merged, 1))
  assert_true(gset_contains(merged, 2))
  assert_true(gset_contains(merged, 3))
}

// ===========================================================================
// TwoPhaseSet Tests
// ===========================================================================

///|
test "twophase_basic" {
  let s = twophase_new()
  let s1 = twophase_add(s, 1)
  assert_true(twophase_contains(s1, 1))
  let s2 = twophase_remove(s1, 1)
  assert_false(twophase_contains(s2, 1))
}

///|
test "twophase_no_resurrect" {
  // Once removed, cannot re-add
  let s = twophase_remove(twophase_add(twophase_new(), 1), 1)
  let s2 = twophase_add(s, 1)
  assert_false(twophase_contains(s2, 1))
}

///|
test "twophase_merge" {
  let a = twophase_add(twophase_new(), 1)
  let b = twophase_remove(twophase_add(twophase_new(), 2), 2)
  let merged = twophase_merge(a, b)
  assert_true(twophase_contains(merged, 1))
  assert_false(twophase_contains(merged, 2))
}

// ===========================================================================
// LWWMap Tests
// ===========================================================================

///|
test "lwwmap_basic" {
  let m = lwwmap_new(0)
  assert_eq(lwwmap_get(m, 1), -1)
  let m1 = lwwmap_put(m, 1, 100, 1)
  assert_eq(lwwmap_get(m1, 1), 100)
}

///|
test "lwwmap_last_writerWins" {
  let m = lwwmap_put(lwwmap_new(0), 1, 100, 1)
  let m2 = lwwmap_put(m, 1, 200, 2)
  assert_eq(lwwmap_get(m2, 1), 200)
  // Older write doesn't override
  let m3 = lwwmap_put(m2, 1, 300, 1)
  assert_eq(lwwmap_get(m3, 1), 200)
}

///|
test "lwwmap_merge" {
  let a = lwwmap_put(lwwmap_new(0), 1, 100, 2)
  let b = lwwmap_put(lwwmap_new(1), 1, 200, 3)
  let merged = lwwmap_merge(a, b)
  assert_eq(lwwmap_get(merged, 1), 200)
}

// ===========================================================================
// ORSet Tests
// ===========================================================================

///|
test "orset_basic" {
  let s = orset_new(0)
  let s1 = orset_add(s, 1)
  assert_true(orset_contains(s1, 1))
  assert_eq(orset_size(s1), 1)
  let s2 = orset_remove(s1, 1)
  assert_false(orset_contains(s2, 1))
  assert_eq(orset_size(s2), 0)
}

///|
test "orset_add_after_remove" {
  // ORSet supports add-after-remove (unlike 2P-Set)
  let s = orset_remove(orset_add(orset_new(0), 1), 1)
  let s2 = orset_add(s, 1)
  assert_true(orset_contains(s2, 1))
}

///|
test "orset_merge" {
  let a = orset_add(orset_new(0), 1)
  let b = orset_add(orset_new(1), 2)
  let merged = orset_merge(a, b)
  assert_true(orset_contains(merged, 1))
  assert_true(orset_contains(merged, 2))
}

///|
test "orset_merge_with_remove" {
  // Node 0 adds 1, node 1 removes 1 (but hasn't seen it yet)
  let a = orset_add(orset_new(0), 1)
  let b = orset_remove(orset_add(orset_new(1), 1), 1)
  let merged = orset_merge(a, b)
  // After merge, 1 should be removed (the tag from b's add is tombstoned)
  assert_false(orset_contains(merged, 1))
}
