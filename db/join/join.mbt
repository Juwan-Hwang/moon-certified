/// Database Join Algorithms — Hash Join and Nested Loop Join
///
/// Implements the two most common join algorithms used in relational
/// database query execution.
///
/// ## Algorithms
/// - **Hash Join**: Build a hash table from the smaller (build) side,
///   then probe with the larger (probe) side. O(n + m) time.
/// - **Nested Loop Join**: For each row in the outer table, scan all
///   rows in the inner table. O(n × m) time. Used when no hash is possible
///   or one side is very small.
///
/// `proof-enabled` is `false`.

///|
/// A row in a database table.
pub struct Row {
  values : Array[Int]
}

///|
/// Hash join two tables on a key column.
///
/// ## Parameters
/// - `left`: left table rows (build side)
/// - `right`: right table rows (probe side)
/// - `left_key`: index of join key in left rows
/// - `right_key`: index of join key in right rows
///
/// ## Returns
/// Joined rows where left[left_key] == right[right_key]
pub fn hash_join(
  left : Array[Row],
  right : Array[Row],
  left_key : Int,
  right_key : Int,
) -> Array[Row] {
  // Build phase: hash the left (smaller) side
  let hash_table : Array[(Int, Array[Int])] = [] // (key, [row indices])
  for i = 0; i < left.length(); i = i + 1 {
    if left_key < left[i].values.length() {
      let key = left[i].values[left_key]
      let mut found = false
      for entry in hash_table {
        if entry.0 == key {
          entry.1.push(i)
          found = true
          break
        }
      }
      if !found {
        hash_table.push((key, [i]))
      }
    }
  }
  // Probe phase: scan the right side
  let result : Array[Row] = []
  for r in right {
    if right_key < r.values.length() {
      let key = r.values[right_key]
      // Look up in hash table
      for entry in hash_table {
        if entry.0 == key {
          // Match found: concatenate left + right values
          for lidx in entry.1 {
            let joined = { values: left[lidx].values + r.values, }
            result.push(joined)
          }
          break
        }
      }
    }
  }
  result
}

///|
/// Nested loop join two tables.
///
/// For each row in the outer table, scan all rows in the inner table.
/// O(n × m) time complexity.
pub fn nested_loop_join(
  outer : Array[Row],
  inner : Array[Row],
  outer_key : Int,
  inner_key : Int,
) -> Array[Row] {
  let result : Array[Row] = []
  for o in outer {
    if outer_key < o.values.length() {
      let key = o.values[outer_key]
      for i in inner {
        if inner_key < i.values.length() && i.values[inner_key] == key {
          let joined = { values: o.values + i.values, }
          result.push(joined)
        }
      }
    }
  }
  result
}

///|
/// Merge join two sorted tables.
///
/// Both inputs must be sorted on the join key. O(n + m) time.
pub fn merge_join(
  left : Array[Row],
  right : Array[Row],
  left_key : Int,
  right_key : Int,
) -> Array[Row] {
  let result : Array[Row] = []
  let mut i = 0
  let mut j = 0
  while i < left.length() && j < right.length() {
    let lval = if left_key < left[i].values.length() {
      left[i].values[left_key]
    } else {
      break
    }
    let rval = if right_key < right[j].values.length() {
      right[j].values[right_key]
    } else {
      break
    }
    if lval == rval {
      let joined = { values: left[i].values + right[j].values, }
      result.push(joined)
      j = j + 1
    } else if lval < rval {
      i = i + 1
    } else {
      j = j + 1
    }
  }
  result
}

///|
/// Semi-join: returns rows from left that have a match in right.
pub fn semi_join(
  left : Array[Row],
  right : Array[Row],
  left_key : Int,
  right_key : Int,
) -> Array[Row] {
  // Build set of right keys
  let right_keys : Array[Int] = []
  for r in right {
    if right_key < r.values.length() {
      right_keys.push(r.values[right_key])
    }
  }
  let result : Array[Row] = []
  for l in left {
    if left_key < l.values.length() {
      let key = l.values[left_key]
      if right_keys.contains(key) {
        result.push(l)
      }
    }
  }
  result
}

///|
/// Anti-join: returns rows from left that have NO match in right.
pub fn anti_join(
  left : Array[Row],
  right : Array[Row],
  left_key : Int,
  right_key : Int,
) -> Array[Row] {
  let right_keys : Array[Int] = []
  for r in right {
    if right_key < r.values.length() {
      right_keys.push(r.values[right_key])
    }
  }
  let result : Array[Row] = []
  for l in left {
    if left_key < l.values.length() {
      let key = l.values[left_key]
      if !right_keys.contains(key) {
        result.push(l)
      }
    }
  }
  result
}
