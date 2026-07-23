/// 2-SAT: satisfiability of 2-CNF boolean formulas.
///
/// Determines whether a set of clauses, each being a disjunction (OR) of two
/// literals, is satisfiable, and if so, produces a satisfying assignment.
///
/// **Literal encoding.** Variable `x_i` (0-indexed) has two literals:
/// - `2*i`     — positive literal (x_i is true)
/// - `2*i + 1` — negative literal (x_i is false, i.e. ¬x_i)
/// Negation of literal `l` is `l ^ 1` (XOR 1).
///
/// **Clause (a ∨ b).** Adds two implications:
/// - ¬a → b  (edge from `a^1` to `b`)
/// - ¬b → a  (edge from `b^1` to `a`)
///
/// **Algorithm.** Build the implication graph (2n nodes), find strongly
/// connected components (SCCs) via iterative Tarjan's algorithm, then check
/// for each variable whether `x_i` and `¬x_i` are in the same SCC. If they
/// are, the formula is unsatisfiable. Otherwise, set `x_i = true` when
/// `comp[2*i] < comp[2*i+1]` (the positive literal's SCC has a lower Tarjan
/// index = is topologically later = should be set true).
///
/// **Complexity.** O(n + m) where n is the number of variables and m is the
/// number of clauses.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Mutable state for iterative Tarjan's SCC algorithm.
priv struct TSState {
  adj : Array[Array[Int]] // implication graph adjacency list
  mut index_counter : Int
  indices : FixedArray[Int] // -1 = unvisited
  lowlink : FixedArray[Int]
  on_stack : FixedArray[Bool]
  stack : FixedArray[Int] // Tarjan stack
  mut stack_top : Int
  comp : FixedArray[Int] // SCC ID assigned to each node
  mut comp_count : Int
}

fn ts_new_state(n : Int) -> TSState {
  let adj : Array[Array[Int]] = []
  for _i = 0; _i < n; _i = _i + 1 {
    adj.push([])
  }
  {
    adj,
    index_counter: 0,
    indices: FixedArray::make(n, -1),
    lowlink: FixedArray::make(n, 0),
    on_stack: FixedArray::make(n, false),
    stack: FixedArray::make(n, 0),
    stack_top: 0,
    comp: FixedArray::make(n, -1),
    comp_count: 0,
  }
}

/// Iterative Tarjan's strongconnect using an explicit DFS stack.
/// Follows the same pattern as `graph/scc/scc.mbt` but with adjacency list.
fn ts_strongconnect(state : TSState, start : Int) -> Unit {
  let dfs_stack : Array[(Int, Int)] = [(start, 0)]
  state.indices[start] = state.index_counter
  state.lowlink[start] = state.index_counter
  state.index_counter = state.index_counter + 1
  state.stack[state.stack_top] = start
  state.stack_top = state.stack_top + 1
  state.on_stack[start] = true
  while dfs_stack.length() > 0 {
    let top_idx = dfs_stack.length() - 1
    let (v, next_w) = dfs_stack[top_idx]
    let neighbors = state.adj[v]
    if next_w < neighbors.length() {
      let w = neighbors[next_w]
      dfs_stack[top_idx] = (v, next_w + 1)
      if state.indices[w] == -1 {
        state.indices[w] = state.index_counter
        state.lowlink[w] = state.index_counter
        state.index_counter = state.index_counter + 1
        state.stack[state.stack_top] = w
        state.stack_top = state.stack_top + 1
        state.on_stack[w] = true
        dfs_stack.push((w, 0))
      } else if state.on_stack[w] {
        if state.indices[w] < state.lowlink[v] {
          state.lowlink[v] = state.indices[w]
        }
      }
    } else {
      ignore(dfs_stack.pop())
      // Update parent's lowlink.
      if dfs_stack.length() > 0 {
        let parent_idx = dfs_stack.length() - 1
        let (parent, _) = dfs_stack[parent_idx]
        if state.lowlink[v] < state.lowlink[parent] {
          state.lowlink[parent] = state.lowlink[v]
        }
      }
      // If v is an SCC root, pop the stack and assign component IDs.
      if state.lowlink[v] == state.indices[v] {
        let mut w = -1
        while w != v {
          state.stack_top = state.stack_top - 1
          w = state.stack[state.stack_top]
          state.on_stack[w] = false
          state.comp[w] = state.comp_count
        }
        state.comp_count = state.comp_count + 1
      }
    }
  }
}

/// Solve a 2-SAT problem.
///
/// **Parameters.**
/// - `n`: number of boolean variables x_0, ..., x_{n-1}.
/// - `clauses`: array of `(literal_a, literal_b)` pairs, each representing
///   the clause `literal_a ∨ literal_b`. Literals are encoded as `2*i` (x_i)
///   or `2*i + 1` (¬x_i), so `0 ≤ literal < 2*n`.
///
/// **Returns.** `Some(assignment)` where `assignment[i]` is the value of
/// `x_i`, or `None` if the formula is unsatisfiable or the input is invalid
/// (n ≤ 0, or any literal is out of range `[0, 2*n)`).
pub fn two_sat(n : Int, clauses : Array[(Int, Int)]) -> FixedArray[Bool]? {
  if n <= 0 {
    return None
  }
  let num_nodes = 2 * n
  let state = ts_new_state(num_nodes)
  // Build implication graph: for clause (a ∨ b), add edges ¬a → b and ¬b → a.
  for i = 0; i < clauses.length(); i = i + 1 {
    let (a, b) = clauses[i]
    // Validate literal range.
    if a < 0 || a >= num_nodes || b < 0 || b >= num_nodes {
      return None
    }
    state.adj[a ^ 1].push(b) // ¬a → b
    state.adj[b ^ 1].push(a) // ¬b → a
  }
  // Run Tarjan's SCC on all unvisited nodes.
  for v = 0; v < num_nodes; v = v + 1 {
    if state.indices[v] == -1 {
      ts_strongconnect(state, v)
    }
  }
  // Check for contradictions: x_i and ¬x_i in the same SCC.
  for i = 0; i < n; i = i + 1 {
    if state.comp[2 * i] == state.comp[2 * i + 1] {
      return None
    }
  }
  // Build assignment: x_i = true when comp[2*i] < comp[2*i+1].
  let assignment = FixedArray::make(n, false)
  for i = 0; i < n; i = i + 1 {
    assignment[i] = state.comp[2 * i] < state.comp[2 * i + 1]
  }
  Some(assignment)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Verify that an assignment satisfies all clauses.
fn check_assignment(
  clauses : Array[(Int, Int)],
  assign : FixedArray[Bool],
) -> Bool {
  for i = 0; i < clauses.length(); i = i + 1 {
    let (a, b) = clauses[i]
    let va = if a % 2 == 0 {
      assign[a / 2]
    } else {
      !assign[a / 2]
    }
    let vb = if b % 2 == 0 {
      assign[b / 2]
    } else {
      !assign[b / 2]
    }
    if !va && !vb {
      return false
    }
  }
  true
}

test "two_sat: trivially satisfiable (x_0 ∨ x_1)" {
  // x_0 ∨ x_1: always satisfiable.
  let clauses = [(0, 2)] // literal 0 = x_0, literal 2 = x_1
  let result = two_sat(2, clauses)
  assert_true(result is Some(_))
  assert_true(check_assignment(clauses, result.unwrap()))
}

test "two_sat: force x_0 = true" {
  // (x_0 ∨ x_0) ∧ (x_0 ∨ x_1)
  let clauses = [(0, 0), (0, 2)]
  let result = two_sat(2, clauses)
  assert_true(result is Some(_))
  let assign = result.unwrap()
  assert_eq(assign[0], true)
  assert_true(check_assignment(clauses, assign))
}

test "two_sat: unsatisfiable (x_0 ∧ ¬x_0)" {
  // (x_0 ∨ x_0) ∧ (¬x_0 ∨ ¬x_0)
  let clauses = [(0, 0), (1, 1)]
  let result = two_sat(2, clauses)
  assert_true(result is None)
}

test "two_sat: x_0 = x_1" {
  // (x_0 ∨ x_1) ∧ (¬x_0 ∨ ¬x_1): exactly one is true.
  let clauses = [(0, 2), (1, 3)]
  let result = two_sat(2, clauses)
  assert_true(result is Some(_))
  let assign = result.unwrap()
  // Either x_0 = true, x_1 = false, or x_0 = false, x_1 = true.
  assert_true(assign[0] != assign[1])
  assert_true(check_assignment(clauses, assign))
}

test "two_sat: implication chain" {
  // x_0 → x_1 → x_2 (encoded as (¬x_0 ∨ x_1) ∧ (¬x_1 ∨ x_2))
  // With x_0 = true: all must be true.
  // Add (x_0 ∨ x_0) to force x_0 = true.
  let clauses = [
    (0, 0), // x_0
    (1, 2), // ¬x_0 ∨ x_1
    (3, 4), // ¬x_1 ∨ x_2
  ]
  let result = two_sat(3, clauses)
  assert_true(result is Some(_))
  let assign = result.unwrap()
  assert_eq(assign[0], true)
  assert_eq(assign[1], true)
  assert_eq(assign[2], true)
  assert_true(check_assignment(clauses, assign))
}

test "two_sat: empty clauses" {
  let result = two_sat(3, [])
  assert_true(result is Some(_))
  let assign = result.unwrap()
  // Any assignment works; check all are valid booleans.
  for i = 0; i < 3; i = i + 1 {
    assert_true(assign[i] == true || assign[i] == false)
  }
}

test "two_sat: single variable" {
  // x_0 must be true.
  let result = two_sat(1, [(0, 0)])
  assert_true(result is Some(_))
  assert_eq(result.unwrap()[0], true)
  // x_0 must be false.
  let result2 = two_sat(1, [(1, 1)])
  assert_true(result2 is Some(_))
  assert_eq(result2.unwrap()[0], false)
}

test "two_sat: complex satisfiable" {
  // 4 variables with multiple constraints.
  // x_0 ∨ x_1, ¬x_0 ∨ x_2, ¬x_1 ∨ x_2, x_2 ∨ x_3, ¬x_2 ∨ ¬x_3
  let clauses = [
    (0, 2), // x_0 ∨ x_1
    (1, 4), // ¬x_0 ∨ x_2
    (3, 4), // ¬x_1 ∨ x_2
    (4, 6), // x_2 ∨ x_3
    (5, 7), // ¬x_2 ∨ ¬x_3
  ]
  let result = two_sat(4, clauses)
  assert_true(result is Some(_))
  assert_true(check_assignment(clauses, result.unwrap()))
}

test "two_sat: complex unsatisfiable" {
  // x_0, ¬x_0, x_1, ¬x_1 — all four forced, contradiction.
  let clauses = [
    (0, 0), // x_0
    (1, 1), // ¬x_0
    (2, 2), // x_1
    (3, 3), // ¬x_1
  ]
  let result = two_sat(2, clauses)
  assert_true(result is None)
}

test "two_sat: invalid input" {
  // n = 0
  assert_true(two_sat(0, []) is None)
  // Literal out of range
  assert_true(two_sat(2, [(0, 5)]) is None) // 5 >= 2*2 = 4
  assert_true(two_sat(2, [(-1, 0)]) is None)
}

test "two_sat: large satisfiable" {
  // n = 100 variables. Each clause forces x_i = true for even i, x_i = false
  // for odd i. No contradictions.
  let n = 100
  let clauses : Array[(Int, Int)] = []
  for i = 0; i < n; i = i + 1 {
    if i % 2 == 0 {
      clauses.push((2 * i, 2 * i)) // x_i ∨ x_i → x_i = true
    } else {
      clauses.push((2 * i + 1, 2 * i + 1)) // ¬x_i ∨ ¬x_i → x_i = false
    }
  }
  let result = two_sat(n, clauses)
  assert_true(result is Some(_))
  let assign = result.unwrap()
  for i = 0; i < n; i = i + 1 {
    if i % 2 == 0 {
      assert_eq(assign[i], true)
    } else {
      assert_eq(assign[i], false)
    }
  }
  assert_true(check_assignment(clauses, assign))
}

test "two_sat: all variables unconstrained except one" {
  // x_0 ∨ x_0 forces x_0 = true; x_1 through x_9 are free.
  let n = 10
  let clauses = [(0, 0)]
  let result = two_sat(n, clauses)
  assert_true(result is Some(_))
  let assign = result.unwrap()
  assert_eq(assign[0], true)
  assert_true(check_assignment(clauses, assign))
}

test "two_sat: XOR constraint" {
  // x_0 ⊕ x_1 = 1 (exactly one is true).
  // (x_0 ∨ x_1) ∧ (¬x_0 ∨ ¬x_1)
  let clauses = [(0, 2), (1, 3)]
  let result = two_sat(2, clauses)
  assert_true(result is Some(_))
  let assign = result.unwrap()
  assert_true(assign[0] != assign[1])
  assert_true(check_assignment(clauses, assign))
}

test "two_sat: implication cycle" {
  // x_0 → x_1 → x_0 (so x_0 = x_1), plus x_0 = true.
  // (¬x_0 ∨ x_1) ∧ (¬x_1 ∨ x_0) ∧ (x_0 ∨ x_0)
  let clauses = [
    (1, 2), // ¬x_0 ∨ x_1
    (3, 0), // ¬x_1 ∨ x_0
    (0, 0), // x_0
  ]
  let result = two_sat(2, clauses)
  assert_true(result is Some(_))
  let assign = result.unwrap()
  assert_eq(assign[0], true)
  assert_eq(assign[1], true)
  assert_true(check_assignment(clauses, assign))
}
