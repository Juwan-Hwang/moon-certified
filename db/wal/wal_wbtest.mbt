// White-box tests for db/wal
//
// Exercises the in-memory WAL: begin_txn, log_data, commit_txn,
// checkpoint, recover, get_txn_records, size, and LSN assignment.
// WalRecordType enum values: Begin=0, Commit=1, Abort=2, Data=3,
// Checkpoint=4.

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
fn assert_bytes_eq(actual : Bytes, expected : Bytes) -> Unit raise {
  assert_true(bytes_eq(actual, expected))
}

///|
fn b(data : Array[Byte]) -> Bytes {
  Bytes::from_array(data)
}

// ---------------------------------------------------------------------------
// new / size / lsn
// ---------------------------------------------------------------------------

///|
test "wal_new_empty" {
  let w = Wal::new()
  assert_eq(w.size(), 0)
  assert_eq(w.next_lsn, 0)
  assert_eq(w.checkpoint_lsn, 0)
}

///|
test "wal_lsn_monotonic" {
  let w = Wal::new()
  assert_eq(w.begin_txn(1), 0)
  assert_eq(w.log_data(1, 1, b([]), b([])), 1)
  assert_eq(w.commit_txn(1), 2)
  assert_eq(w.checkpoint(), 3)
  assert_eq(w.next_lsn, 4)
}

///|
test "wal_size_grows" {
  let w = Wal::new()
  assert_eq(w.size(), 0)
  let _ = w.begin_txn(1)
  assert_eq(w.size(), 1)
  let _ = w.log_data(1, 0, b([]), b([]))
  assert_eq(w.size(), 2)
}

// ---------------------------------------------------------------------------
// begin_txn
// ---------------------------------------------------------------------------

///|
test "wal_begin_txn_record" {
  let w = Wal::new()
  let lsn = w.begin_txn(1)
  assert_eq(lsn, 0)
  assert_eq(w.size(), 1)
  assert_eq(w.next_lsn, 1)
  let recs = w.get_txn_records(1)
  assert_eq(recs.length(), 1)
  assert_eq(recs[0].rtype, 0) // Begin
  assert_eq(recs[0].lsn, 0)
  assert_eq(recs[0].txn_id, 1)
}

// ---------------------------------------------------------------------------
// log_data round-trip
// ---------------------------------------------------------------------------

///|
test "wal_log_data_roundtrip" {
  let w = Wal::new()
  let _ = w.begin_txn(7)
  let lsn = w.log_data(7, 5, b([b'o']), b([b'n']))
  assert_eq(lsn, 1)
  assert_eq(w.size(), 2)
  assert_eq(w.next_lsn, 2)
  let recs = w.get_txn_records(7)
  assert_eq(recs.length(), 2)
  let data_rec = recs[1]
  assert_eq(data_rec.rtype, 3) // Data
  assert_eq(data_rec.page_id, 5)
  assert_eq(data_rec.txn_id, 7)
  assert_bytes_eq(data_rec.old_value, b([b'o']))
  assert_bytes_eq(data_rec.new_value, b([b'n']))
}

// ---------------------------------------------------------------------------
// commit_txn
// ---------------------------------------------------------------------------

///|
test "wal_commit_txn_record" {
  let w = Wal::new()
  let _ = w.begin_txn(3)
  let _ = w.log_data(3, 1, b([]), b([b'a']))
  let lsn = w.commit_txn(3)
  assert_eq(lsn, 2)
  assert_eq(w.size(), 3)
  let recs = w.get_txn_records(3)
  assert_eq(recs.length(), 3)
  assert_eq(recs[2].rtype, 1) // Commit
}

// ---------------------------------------------------------------------------
// checkpoint
// ---------------------------------------------------------------------------

///|
test "wal_checkpoint_record" {
  let w = Wal::new()
  let _ = w.begin_txn(1)
  let _ = w.commit_txn(1)
  let lsn = w.checkpoint()
  assert_eq(lsn, 2)
  assert_eq(w.checkpoint_lsn, 2)
  assert_eq(w.size(), 3)
  let recs = w.get_txn_records(-1) // checkpoint txn_id is -1
  assert_eq(recs.length(), 1)
  assert_eq(recs[0].rtype, 4) // Checkpoint
}

// ---------------------------------------------------------------------------
// recover (committed transactions)
// ---------------------------------------------------------------------------

///|
test "wal_recover_returns_only_committed" {
  let w = Wal::new()
  let _ = w.begin_txn(1)
  let _ = w.log_data(1, 1, b([]), b([b'a']))
  let _ = w.commit_txn(1)
  // uncommitted transaction
  let _ = w.begin_txn(2)
  let _ = w.log_data(2, 1, b([]), b([b'b']))
  let committed = w.recover()
  assert_eq(committed.length(), 1)
  assert_eq(committed[0], 1)
}

///|
test "wal_recover_multiple_commits_order" {
  let w = Wal::new()
  let _ = w.begin_txn(10)
  let _ = w.commit_txn(10)
  let _ = w.begin_txn(20)
  let _ = w.commit_txn(20)
  let c = w.recover()
  assert_eq(c.length(), 2)
  assert_eq(c[0], 10)
  assert_eq(c[1], 20)
}

// ---------------------------------------------------------------------------
// get_txn_records edge cases
// ---------------------------------------------------------------------------

///|
test "wal_get_txn_records_empty_for_unknown" {
  let w = Wal::new()
  let _ = w.begin_txn(5)
  let recs = w.get_txn_records(99)
  assert_eq(recs.length(), 0)
}

///|
test "wal_get_txn_records_all_phases" {
  let w = Wal::new()
  let _ = w.begin_txn(4)
  let _ = w.log_data(4, 2, b([b'x']), b([b'y']))
  let _ = w.commit_txn(4)
  let recs = w.get_txn_records(4)
  // begin + data + commit
  assert_eq(recs.length(), 3)
  assert_eq(recs[0].rtype, 0)
  assert_eq(recs[1].rtype, 3)
  assert_eq(recs[2].rtype, 1)
}
