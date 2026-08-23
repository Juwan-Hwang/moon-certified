/// Write-Ahead Log (WAL) — Durability for Database Systems
///
/// A WAL ensures durability by recording all modifications to a log file
/// before applying them to the database. On crash recovery, the log is
/// replayed to restore the database to a consistent state.
///
/// `proof-enabled` is `false`.

///|
/// WAL record type.
pub enum WalRecordType {
  Begin // Transaction begin
  Commit // Transaction commit
  Abort // Transaction abort
  Data // Data modification
  Checkpoint // Checkpoint marker
}

///|
/// WAL record.
pub struct WalRecord {
  /// Log sequence number
  lsn : Int
  /// Transaction ID
  txn_id : Int
  /// Record type
  rtype : Int
  /// Page/table ID
  page_id : Int
  /// Old value (for undo)
  old_value : Bytes
  /// New value (for redo)
  new_value : Bytes
}

///|
/// Write-Ahead Log.
pub struct Wal {
  /// In-memory log records (in production: backed by a file)
  records : Array[WalRecord]
  /// Next LSN to assign
  mut next_lsn : Int
  /// Active transactions
  active_txns : Array[Int]
  /// Last checkpoint LSN
  mut checkpoint_lsn : Int
}

///|
/// Create a new WAL.
pub fn Wal::new() -> Wal {
  { records: [], next_lsn: 0, active_txns: [], checkpoint_lsn: 0 }
}

///|
/// Log a transaction begin.
pub fn Wal::begin_txn(self : Wal, txn_id : Int) -> Int {
  let lsn = self.next_lsn
  self.records.push({
    lsn,
    txn_id,
    rtype: 0, // Begin
    page_id: -1,
    old_value: Bytes::make(0, 0),
    new_value: Bytes::make(0, 0),
  })
  self.next_lsn = self.next_lsn + 1
  self.active_txns.push(txn_id)
  lsn
}

///|
/// Log a data modification.
pub fn Wal::log_data(
  self : Wal,
  txn_id : Int,
  page_id : Int,
  old_value : Bytes,
  new_value : Bytes,
) -> Int {
  let lsn = self.next_lsn
  self.records.push({
    lsn,
    txn_id,
    rtype: 3, // Data
    page_id,
    old_value,
    new_value,
  })
  self.next_lsn = self.next_lsn + 1
  lsn
}

///|
/// Log a transaction commit.
pub fn Wal::commit_txn(self : Wal, txn_id : Int) -> Int {
  let lsn = self.next_lsn
  self.records.push({
    lsn,
    txn_id,
    rtype: 1, // Commit
    page_id: -1,
    old_value: Bytes::make(0, 0),
    new_value: Bytes::make(0, 0),
  })
  self.next_lsn = self.next_lsn + 1
  // Remove from active transactions
  let mut i = 0
  while i < self.active_txns.length() {
    if self.active_txns[i] == txn_id {
      ignore(self.active_txns.remove(i))
    } else {
      i = i + 1
    }
  }
  lsn
}

///|
/// Log a checkpoint.
pub fn Wal::checkpoint(self : Wal) -> Int {
  let lsn = self.next_lsn
  self.records.push({
    lsn,
    txn_id: -1,
    rtype: 4, // Checkpoint
    page_id: -1,
    old_value: Bytes::make(0, 0),
    new_value: Bytes::make(0, 0),
  })
  self.checkpoint_lsn = lsn
  self.next_lsn = self.next_lsn + 1
  lsn
}

///|
/// Replay the log for crash recovery.
///
/// Returns the list of committed transactions that need redo.
pub fn Wal::recover(self : Wal) -> Array[Int] {
  let committed_txns : Array[Int] = []
  for record in self.records {
    if record.rtype == 1 {
      // Commit
      committed_txns.push(record.txn_id)
    }
  }
  committed_txns
}

///|
/// Get all records for a specific transaction.
pub fn Wal::get_txn_records(self : Wal, txn_id : Int) -> Array[WalRecord] {
  let result : Array[WalRecord] = []
  for record in self.records {
    if record.txn_id == txn_id {
      result.push(record)
    }
  }
  result
}

///|
/// Get total record count.
pub fn Wal::size(self : Wal) -> Int {
  self.records.length()
}
