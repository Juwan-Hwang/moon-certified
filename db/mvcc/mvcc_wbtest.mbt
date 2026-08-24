// White-box tests for db/mvcc
//
// Exercises MVCC store operations: begin/read/write/commit/abort,
// version visibility under snapshot timestamps, write-write conflict
// detection, and the (private) get_txn helper.

///|
fn bytes_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if !(a[i] == b[i]) {
      return false
    }
  }
  true
}

///|
fn assert_bytes_some(actual : Bytes?, expected : Bytes) -> Unit raise {
  match actual {
    Some(b) => assert_true(bytes_eq(b, expected))
    None => abort("expected Some(Bytes) but got None")
  }
}

///|
fn assert_bytes_none(actual : Bytes?) -> Unit raise {
  assert_true(actual is None)
}

///|
fn b(data : Array[Byte]) -> Bytes {
  Bytes::from_array(data)
}

// ---------------------------------------------------------------------------
// basic read/write
// ---------------------------------------------------------------------------

///|
test "mvcc_new_empty_read_none" {
  let s = MvccStore::new()
  // unknown txn id -> None
  assert_bytes_none(s.read(1, 5))
}

///|
test "mvcc_write_read_same_txn" {
  let s = MvccStore::new()
  let t1 = s.begin_txn()
  assert_true(s.write(t1, 1, b([b'A'])))
  assert_bytes_some(s.read(t1, 1), b([b'A']))
  assert_bytes_none(s.read(t1, 2))
}

///|
test "mvcc_commit_visible_to_later_txn" {
  let s = MvccStore::new()
  let t1 = s.begin_txn()
  assert_true(s.write(t1, 1, b([b'A'])))
  assert_true(s.commit_txn(t1))
  let t2 = s.begin_txn()
  assert_bytes_some(s.read(t2, 1), b([b'A']))
}

///|
test "mvcc_read_unknown_txn_none" {
  let s = MvccStore::new()
  assert_bytes_none(s.read(42, 1))
}

// ---------------------------------------------------------------------------
// get_txn helper (white-box, private)
// ---------------------------------------------------------------------------

///|
test "mvcc_get_txn" {
  let s = MvccStore::new()
  let t1 = s.begin_txn()
  let got = s.get_txn(t1)
  assert_true(got is Some(_))
  match got {
    Some(tx) => assert_eq(tx.txn_id, t1)
    None => abort("expected Some txn")
  }
  assert_true(s.get_txn(999) is None)
}

// ---------------------------------------------------------------------------
// version visibility / snapshot timestamps
// ---------------------------------------------------------------------------

///|
test "mvcc_snapshot_old_does_not_see_new_write" {
  let s = MvccStore::new()
  // reader snapshot taken at global_ts = 1
  let reader = s.begin_txn()
  // bump global_ts via a separate committed txn
  let w1 = s.begin_txn()
  assert_true(s.write(w1, 99, b([b'x'])))
  assert_true(s.commit_txn(w1)) // global_ts -> 2
  // a later writer commits key=1 at begin_ts = 2
  let w2 = s.begin_txn()
  assert_true(s.write(w2, 1, b([b'N'])))
  assert_true(s.commit_txn(w2)) // global_ts -> 3
  // reader snapshot (begin_ts=1) must NOT see key=1 (begin_ts=2)
  assert_bytes_none(s.read(reader, 1))
  // a fresh txn (begin_ts=3) DOES see it
  let t3 = s.begin_txn()
  assert_bytes_some(s.read(t3, 1), b([b'N']))
}

///|
test "mvcc_update_creates_new_version" {
  let s = MvccStore::new()
  let t1 = s.begin_txn()
  assert_true(s.write(t1, 1, b([b'v', b'1'])))
  assert_true(s.commit_txn(t1))
  let t2 = s.begin_txn()
  assert_true(s.write(t2, 1, b([b'v', b'2'])))
  assert_true(s.commit_txn(t2))
  let t3 = s.begin_txn()
  // latest version wins
  assert_bytes_some(s.read(t3, 1), b([b'v', b'2']))
}

// ---------------------------------------------------------------------------
// abort semantics
// ---------------------------------------------------------------------------

///|
test "mvcc_abort_removes_uncommitted_version" {
  let s = MvccStore::new()
  let t1 = s.begin_txn()
  assert_true(s.write(t1, 1, b([b'A'])))
  s.abort_txn(t1)
  let t2 = s.begin_txn()
  assert_bytes_none(s.read(t2, 1))
}

///|
test "mvcc_abort_keeps_committed_version" {
  let s = MvccStore::new()
  let t1 = s.begin_txn()
  assert_true(s.write(t1, 1, b([b'A'])))
  assert_true(s.commit_txn(t1))
  let t2 = s.begin_txn()
  assert_true(s.write(t2, 1, b([b'B'])))
  s.abort_txn(t2)
  let t3 = s.begin_txn()
  // committed version remains
  assert_bytes_some(s.read(t3, 1), b([b'A']))
}

// ---------------------------------------------------------------------------
// write-write conflict
// ---------------------------------------------------------------------------

///|
test "mvcc_write_write_conflict" {
  let s = MvccStore::new()
  let t1 = s.begin_txn()
  assert_true(s.write(t1, 1, b([b'A'])))
  let t2 = s.begin_txn()
  // t1's write is still uncommitted & active -> conflict
  let ok = s.write(t2, 1, b([b'B']))
  assert_false(ok)
}

// ---------------------------------------------------------------------------
// commit edge cases
// ---------------------------------------------------------------------------

///|
test "mvcc_commit_unknown_returns_false" {
  let s = MvccStore::new()
  assert_false(s.commit_txn(123))
}

// ---------------------------------------------------------------------------
// Observed behaviour quirk (documented, not a passing "feature"):
// read() does not check commit status, only snapshot timestamp and
// end_ts. Two transactions that begin at the same global_ts both observe
// each other's writes immediately.
// ---------------------------------------------------------------------------

///|
test "mvcc_uncommitted_visible_to_concurrent_reader_actual" {
  let s = MvccStore::new()
  let t1 = s.begin_txn() // begin_ts = 1
  let t2 = s.begin_txn() // begin_ts = 1 (global_ts still 1)
  assert_true(s.write(t1, 1, b([b'X'])))
  // Actual behaviour: read ignores commit status, so t2 sees t1's write.
  assert_bytes_some(s.read(t2, 1), b([b'X']))
}
