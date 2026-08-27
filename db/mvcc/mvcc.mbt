/// MVCC (Multi-Version Concurrency Control)
///
/// MVCC allows multiple transactions to read and write concurrently
/// by maintaining multiple versions of each row. Each transaction sees
/// a consistent snapshot of the data as of its start timestamp.
///
/// ## Isolation Levels
/// - Snapshot Isolation: each txn reads the latest committed version
///   as of txn start time
/// - Serializable: additionally checks for write-write conflicts
///
/// `proof-enabled` is `false`.

///|
/// A versioned row in MVCC.
pub struct MvccVersion {
  /// Version data
  data : Bytes
  /// Transaction that created this version
  created_by : Int
  /// Transaction that deleted this version (0 = not deleted)
  deleted_by : Int
  /// Creation timestamp
  mut begin_ts : Int
  /// Deletion timestamp (0 = still valid)
  end_ts : Int
}

///|
/// MVCC transaction state.
pub struct MvccTransaction {
  txn_id : Int
  begin_ts : Int // Snapshot timestamp
  mut commit_ts : Int // Commit timestamp (0 if not committed)
  mut is_active : Bool
}

///|
/// MVCC storage.
pub struct MvccStore {
  /// Versions per key
  versions : Array[(Int, Array[MvccVersion])]
  /// Active transactions
  txns : Array[MvccTransaction]
  /// Next transaction ID
  mut next_txn_id : Int
  /// Global timestamp counter
  mut global_ts : Int
}

///|
/// Create a new MVCC store.
pub fn MvccStore::new() -> MvccStore {
  { versions: [], txns: [], next_txn_id: 1, global_ts: 1, }
}

///|
/// Begin a new transaction.
pub fn MvccStore::begin_txn(self : MvccStore) -> Int {
  let txn_id = self.next_txn_id
  self.next_txn_id = self.next_txn_id + 1
  let ts = self.global_ts
  let txn = { txn_id, begin_ts: ts, commit_ts: 0, is_active: true, }
  self.txns.push(txn)
  txn_id
}

///|
/// Read a key under snapshot isolation.
///
/// Returns the most recent committed version visible to the transaction.
pub fn MvccStore::read(self : MvccStore, txn_id : Int, key : Int) -> Bytes? {
  let txn = self.get_txn(txn_id)
  if txn is None {
    return None
  }
  let begin_ts = txn.unwrap().begin_ts
  // Find versions for this key
  for entry in self.versions {
    if entry.0 == key {
      // Find the latest version visible to this transaction
      for i = entry.1.length() - 1; i >= 0; i = i - 1 {
        let v = entry.1[i]
        // Version is visible if: begin_ts <= snapshot_ts AND
        // (not deleted OR deleted_by's commit_ts > snapshot_ts)
        if v.begin_ts <= begin_ts {
          if v.end_ts == 0 || v.end_ts > begin_ts {
            return Some(v.data)
          }
        }
      }
    }
  }
  None
}

///|
/// Write a new version of a key.
pub fn MvccStore::write(
  self : MvccStore,
  txn_id : Int,
  key : Int,
  data : Bytes,
) -> Bool {
  // Create new version
  let new_version = {
    data,
    created_by: txn_id,
    deleted_by: 0,
    begin_ts: self.global_ts, // Will be updated on commit
    end_ts: 0,
  }
  // Find existing versions for this key
  let mut found = false
  for entry in self.versions {
    if entry.0 == key {
      // Check for write-write conflict
      for v in entry.1 {
        if v.end_ts == 0 && v.created_by != txn_id {
          // Another transaction has an uncommitted write
          let other_txn = self.get_txn(v.created_by)
          match other_txn {
            Some(t) if t.is_active => return false // Write-write conflict
            _ => ()
          }
        }
      }
      entry.1.push(new_version)
      found = true
      break
    }
  }
  if !found {
    self.versions.push((key, [new_version]))
  }
  true
}

///|
/// Commit a transaction.
pub fn MvccStore::commit_txn(self : MvccStore, txn_id : Int) -> Bool {
  let ts = self.global_ts + 1
  self.global_ts = ts
  for txn in self.txns {
    if txn.txn_id == txn_id {
      txn.commit_ts = ts
      txn.is_active = false
      // Update version timestamps
      for entry in self.versions {
        for v in entry.1 {
          if v.created_by == txn_id && v.begin_ts == 0 {
            v.begin_ts = ts
          }
        }
      }
      return true
    }
  }
  false
}

///|
/// Abort a transaction.
pub fn MvccStore::abort_txn(self : MvccStore, txn_id : Int) -> Unit {
  for txn in self.txns {
    if txn.txn_id == txn_id {
      txn.is_active = false
      // Remove versions created by this transaction
      for entry in self.versions {
        let filtered : Array[MvccVersion] = []
        for v in entry.1 {
          if v.created_by != txn_id {
            filtered.push(v)
          }
        }
        // Replace
        entry.1.clear()
        for v in filtered {
          entry.1.push(v)
        }
      }
      return
    }
  }
}

///|
/// Get a transaction by ID.
fn MvccStore::get_txn(self : MvccStore, txn_id : Int) -> MvccTransaction? {
  for txn in self.txns {
    if txn.txn_id == txn_id {
      return Some(txn)
    }
  }
  None
}
