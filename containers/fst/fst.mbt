/// FST (Finite State Transducer) — Automaton-based Key-Value Store
///
/// A Finite State Transducer maps a set of strings (keys) to values.
/// When keys share common prefixes, the automaton representation is
/// much more compact than a trie or hash table.
///
/// ## Complexity
/// - Build: O(n·L) where n = #keys, L = max key length
/// - Lookup: O(L)
/// - Space: O(Σ states)
///
/// ## References
/// - Mihov & Schulz. "Faster and Smaller N-Gram Language Models." 2013.
/// - Chidambaram & Kwon. "FST for Lucene." 2014.
///
/// `proof-enabled` is `false`.

///|
/// FST node (state in the automaton).
struct FstState {
  /// Transitions: (byte, next_state, output_value)
  transitions : Array[(Int, Int, Int)]
  /// Whether this state is final (end of a key)
  mut is_final : Bool
  /// Output value (for final states)
  mut final_output : Int
}

///|
/// Finite State Transducer for string-to-int mapping.
pub struct Fst {
  /// States
  states : Array[FstState]
  /// Root state index
  root : Int
}

///|
/// Build an FST from sorted key-value pairs.
///
/// Keys must be sorted lexicographically for correct construction.
pub fn Fst::build(entries : Array[(String, Int)]) -> Fst {
  // Simplified: build a trie (not a minimal transducer)
  let states : Array[FstState] = [
    { transitions: [], is_final: false, final_output: 0 },
  ]
  for entry in entries {
    let key = entry.0
    let value = entry.1
    let mut curr = 0 // root
    for i = 0; i < key.length(); i = i + 1 {
      let ch = key[i].to_int()
      // Find existing transition
      let mut found = false
      for t in states[curr].transitions {
        if t.0 == ch {
          curr = t.1
          found = true
          break
        }
      }
      if !found {
        // Create new state
        states.push({ transitions: [], is_final: false, final_output: 0 })
        let new_idx = states.length() - 1
        states[curr].transitions.push((ch, new_idx, value))
        curr = new_idx
      }
    }
    states[curr].is_final = true
    states[curr].final_output = value
  }
  { states, root: 0 }
}

///|
/// Look up a key in the FST.
pub fn Fst::search(self : Fst, key : String) -> Int? {
  let mut curr = self.root
  for i = 0; i < key.length(); i = i + 1 {
    let ch = key[i].to_int()
    let mut found = false
    for t in self.states[curr].transitions {
      if t.0 == ch {
        curr = t.1
        found = true
        break
      }
    }
    if !found {
      return None
    }
  }
  if self.states[curr].is_final {
    Some(self.states[curr].final_output)
  } else {
    None
  }
}

///|
/// Get all keys in the FST.
pub fn Fst::keys(self : Fst) -> Array[String] {
  let result : Array[String] = []
  let path : Array[Char] = []
  // DFS traversal
  fn dfs(
    self : Fst,
    state : Int,
    path : Array[Char],
    result : Array[String],
  ) -> Unit {
    if self.states[state].is_final {
      let sb = StringBuilder()
      for c in path {
        sb.write_char(c)
      }
      result.push(sb.to_string())
    }
    for t in self.states[state].transitions {
      path.push(t.0.unsafe_to_char())
      dfs(self, t.1, path, result)
      ignore(path.remove(path.length() - 1))
    }
  }
  dfs(self, self.root, path, result)
  result
}
