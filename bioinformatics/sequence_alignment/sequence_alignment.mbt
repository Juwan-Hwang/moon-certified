/// Sequence Alignment — Needleman-Wunsch, Smith-Waterman, and affine-gap alignment.
///
/// This package provides production-grade pairwise sequence alignment algorithms
/// used in bioinformatics for DNA, RNA, and protein sequence comparison.
///
/// ## Algorithms
///
/// ### Needleman-Wunsch (Global Alignment)
///
/// Finds the optimal **global** alignment of two sequences, maximizing the total
/// alignment score across the entire length of both sequences. Uses dynamic
/// programming with O(m·n) time and space, where m and n are the sequence lengths.
///
/// The recurrence is:
///
/// ```text
/// D[i][j] = max(
///   D[i-1][j-1] + s(a_i, b_j),    // match/mismatch (diagonal)
///   D[i-1][j]     + gap,           // deletion (up)
///   D[i][j-1]     + gap,           // insertion (left)
/// )
/// ```
///
/// ### Smith-Waterman (Local Alignment)
///
/// Finds the optimal **local** alignment — the highest-scoring contiguous
/// segment pair between two sequences. Unlike global alignment, local alignment
/// can align substrings, making it suitable for finding conserved domains.
///
/// The key difference from Needleman-Wunsch is the addition of a floor at 0:
///
/// ```text
/// D[i][j] = max(
///   0,                               // reset (no negative scores)
///   D[i-1][j-1] + s(a_i, b_j),      // match/mismatch
///   D[i-1][j]     + gap,             // deletion
///   D[i][j-1]     + gap,             // insertion
/// )
/// ```
///
/// ### Affine-Gap Penalty (Gotoh Algorithm)
///
/// Both global and local alignment support affine gap penalties, where the cost
/// of a gap of length k is `gap_open + (k - 1) * gap_extend`. This is more
/// biologically realistic than a linear gap penalty, as insertions/deletions
/// tend to occur in contiguous runs. Uses three DP matrices (M, I_x, I_y) with
/// O(m·n) time and space.
///
/// ## Scoring
///
/// The scoring function `s(a, b)` returns:
/// - `match_score` when `a == b` (default: +2)
/// - `mismatch_penalty` when `a != b` (default: -1)
/// - `gap_penalty` for insertions/deletions (default: -2 for linear, or
///   `gap_open = -5`, `gap_extend = -1` for affine)
///
/// ## Complexity
///
/// | Algorithm                    | Time  | Space |
/// |------------------------------|-------|-------|
/// | `needleman_wunsch`           | O(mn) | O(mn) |
/// | `smith_waterman`             | O(mn) | O(mn) |
/// | `needleman_wunsch_affine`    | O(mn) | O(mn) |
/// | `smith_waterman_affine`      | O(mn) | O(mn) |
///
/// ## References
///
/// - Needleman, S. B. & Wunsch, C. D. (1970). "A general method applicable to
///   the search for similarities in the amino acid sequence of two proteins."
///   *J. Mol. Biol.*, 48(3), 443–453.
/// - Smith, T. F. & Waterman, M. S. (1981). "Identification of common molecular
///   subsequences." *J. Mol. Biol.*, 147(1), 195–197.
/// - Gotoh, O. (1982). "An improved algorithm for matching biological sequences."
///   *J. Mol. Biol.*, 162(3), 705–708.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

///|
/// Alignment result: score + aligned sequences (with gap characters).
pub struct AlignmentResult {
  /// Alignment score (higher is better).
  score : Int
  /// First aligned sequence (may contain '-' gap characters).
  aligned_a : String
  /// Second aligned sequence (may contain '-' gap characters).
  aligned_b : String
  /// Start position in sequence A (0-based, for local alignment).
  start_a : Int
  /// Start position in sequence B (0-based, for local alignment).
  start_b : Int
  /// End position in sequence A (exclusive, for local alignment).
  end_a : Int
  /// End position in sequence B (exclusive, for local alignment).
  end_b : Int
}

///|
/// Scoring parameters for sequence alignment.
pub struct Scoring {
  /// Score for matching characters (positive).
  match_score : Int
  /// Penalty for mismatching characters (negative or zero).
  mismatch_penalty : Int
  /// Linear gap penalty per position (negative).
  gap_penalty : Int
  /// Affine gap opening penalty (negative, for Gotoh algorithm).
  gap_open : Int
  /// Affine gap extension penalty (negative, for Gotoh algorithm).
  gap_extend : Int
}

///|
/// Default scoring: match=+2, mismatch=-1, gap=-2, gap_open=-5, gap_extend=-1.
pub fn default_scoring() -> Scoring {
  {
    match_score: 2,
    mismatch_penalty: -1,
    gap_penalty: -2,
    gap_open: -5,
    gap_extend: -1,
  }
}

///|
/// Create custom scoring parameters.
pub fn scoring(
  match_score : Int,
  mismatch_penalty : Int,
  gap_penalty : Int,
) -> Scoring {
  {
    match_score,
    mismatch_penalty,
    gap_penalty,
    gap_open: gap_penalty,
    gap_extend: gap_penalty,
  }
}

///|
/// Create custom affine scoring parameters.
pub fn affine_scoring(
  match_score : Int,
  mismatch_penalty : Int,
  gap_open : Int,
  gap_extend : Int,
) -> Scoring {
  {
    match_score,
    mismatch_penalty,
    gap_penalty: gap_open,
    gap_open,
    gap_extend,
  }
}

// ---------------------------------------------------------------------------
// Scoring helper
// ---------------------------------------------------------------------------

///|
/// Score for aligning character `a` with character `b`.
fn score_pair(a : Int, b : Int, s : Scoring) -> Int {
  if a == b {
    s.match_score
  } else {
    s.mismatch_penalty
  }
}

// ---------------------------------------------------------------------------
// Needleman-Wunsch (Global Alignment)
// ---------------------------------------------------------------------------

///|
/// Compute global alignment of two sequences using Needleman-Wunsch.
///
/// Sequences are integer arrays (e.g., map DNA characters to 0-3, or amino
/// acid codes to integers). Returns the optimal global alignment.
///
/// **Time**: O(m·n), **Space**: O(m·n).
pub fn needleman_wunsch(
  seq_a : Array[Int],
  seq_b : Array[Int],
  scoring : Scoring,
) -> AlignmentResult {
  let m = seq_a.length()
  let n = seq_b.length()
  // DP matrix
  let dp = Array::make((m + 1) * (n + 1), 0)
  // Traceback matrix: 0=diagonal, 1=up (deletion), 2=left (insertion)
  let tb = Array::make((m + 1) * (n + 1), 0)
  let idx = fn(i : Int, j : Int) -> Int { i * (n + 1) + j }
  // Initialize first row and column
  for i = 0; i <= m; i = i + 1 {
    dp[idx(i, 0)] = i * scoring.gap_penalty
    tb[idx(i, 0)] = 1 // up
  }
  for j = 0; j <= n; j = j + 1 {
    dp[idx(0, j)] = j * scoring.gap_penalty
    tb[idx(0, j)] = 2 // left
  }
  tb[idx(0, 0)] = 0
  // Fill DP matrix
  for i = 1; i <= m; i = i + 1 {
    for j = 1; j <= n; j = j + 1 {
      let diag = dp[idx(i - 1, j - 1)] +
        score_pair(seq_a[i - 1], seq_b[j - 1], scoring)
      let up = dp[idx(i - 1, j)] + scoring.gap_penalty
      let left = dp[idx(i, j - 1)] + scoring.gap_penalty
      if diag >= up && diag >= left {
        dp[idx(i, j)] = diag
        tb[idx(i, j)] = 0
      } else if up >= left {
        dp[idx(i, j)] = up
        tb[idx(i, j)] = 1
      } else {
        dp[idx(i, j)] = left
        tb[idx(i, j)] = 2
      }
    }
  }
  // Traceback
  let aligned_a : Array[Int] = []
  let aligned_b : Array[Int] = []
  let mut i = m
  let mut j = n
  while i > 0 || j > 0 {
    let dir = tb[idx(i, j)]
    if dir == 0 && i > 0 && j > 0 {
      aligned_a.push(seq_a[i - 1])
      aligned_b.push(seq_b[j - 1])
      i = i - 1
      j = j - 1
    } else if dir == 1 && i > 0 {
      aligned_a.push(seq_a[i - 1])
      aligned_b.push(-1) // gap
      i = i - 1
    } else {
      aligned_a.push(-1) // gap
      aligned_b.push(seq_b[j - 1])
      j = j - 1
    }
  }
  // Reverse (we built it backwards)
  reverse_int_array(aligned_a)
  reverse_int_array(aligned_b)
  {
    score: dp[idx(m, n)],
    aligned_a: ints_to_gap_string(aligned_a),
    aligned_b: ints_to_gap_string(aligned_b),
    start_a: 0,
    start_b: 0,
    end_a: m,
    end_b: n,
  }
}

// ---------------------------------------------------------------------------
// Smith-Waterman (Local Alignment)
// ---------------------------------------------------------------------------

///|
/// Compute local alignment of two sequences using Smith-Waterman.
///
/// Returns the highest-scoring local alignment (contiguous segment pair).
///
/// **Time**: O(m·n), **Space**: O(m·n).
pub fn smith_waterman(
  seq_a : Array[Int],
  seq_b : Array[Int],
  scoring : Scoring,
) -> AlignmentResult {
  let m = seq_a.length()
  let n = seq_b.length()
  let dp = Array::make((m + 1) * (n + 1), 0)
  let tb = Array::make((m + 1) * (n + 1), 0)
  let idx = fn(i : Int, j : Int) -> Int { i * (n + 1) + j }
  let mut best_score = 0
  let mut best_i = 0
  let mut best_j = 0
  for i = 1; i <= m; i = i + 1 {
    for j = 1; j <= n; j = j + 1 {
      let diag = dp[idx(i - 1, j - 1)] +
        score_pair(seq_a[i - 1], seq_b[j - 1], scoring)
      let up = dp[idx(i - 1, j)] + scoring.gap_penalty
      let left = dp[idx(i, j - 1)] + scoring.gap_penalty
      if diag <= 0 && up <= 0 && left <= 0 {
        dp[idx(i, j)] = 0
        tb[idx(i, j)] = 3 // reset
      } else if diag >= up && diag >= left {
        dp[idx(i, j)] = diag
        tb[idx(i, j)] = 0
      } else if up >= left {
        dp[idx(i, j)] = up
        tb[idx(i, j)] = 1
      } else {
        dp[idx(i, j)] = left
        tb[idx(i, j)] = 2
      }
      if dp[idx(i, j)] > best_score {
        best_score = dp[idx(i, j)]
        best_i = i
        best_j = j
      }
    }
  }
  // Traceback from best cell until hitting 0
  let aligned_a : Array[Int] = []
  let aligned_b : Array[Int] = []
  let mut i = best_i
  let mut j = best_j
  let end_a = best_i
  let end_b = best_j
  while i > 0 && j > 0 && dp[idx(i, j)] > 0 {
    let dir = tb[idx(i, j)]
    if dir == 0 {
      aligned_a.push(seq_a[i - 1])
      aligned_b.push(seq_b[j - 1])
      i = i - 1
      j = j - 1
    } else if dir == 1 {
      aligned_a.push(seq_a[i - 1])
      aligned_b.push(-1)
      i = i - 1
    } else if dir == 2 {
      aligned_a.push(-1)
      aligned_b.push(seq_b[j - 1])
      j = j - 1
    } else {
      break
    }
  }
  let start_a = i
  let start_b = j
  reverse_int_array(aligned_a)
  reverse_int_array(aligned_b)
  {
    score: best_score,
    aligned_a: ints_to_gap_string(aligned_a),
    aligned_b: ints_to_gap_string(aligned_b),
    start_a,
    start_b,
    end_a,
    end_b,
  }
}

// ---------------------------------------------------------------------------
// Affine-Gap Alignment (Gotoh Algorithm)
// ---------------------------------------------------------------------------

///|
/// Global alignment with affine gap penalty (Gotoh algorithm).
///
/// Gap cost = gap_open + (k-1) * gap_extend for a gap of length k.
///
/// **Time**: O(m·n), **Space**: O(m·n).
pub fn needleman_wunsch_affine(
  seq_a : Array[Int],
  seq_b : Array[Int],
  scoring : Scoring,
) -> AlignmentResult {
  let m = seq_a.length()
  let n = seq_b.length()
  let neg_inf = -1000000
  let idx = fn(i : Int, j : Int) -> Int { i * (n + 1) + j }
  // Three matrices: M (match), X (gap in A / deletion), Y (gap in B / insertion)
  let m_mat = Array::make((m + 1) * (n + 1), neg_inf)
  let x_mat = Array::make((m + 1) * (n + 1), neg_inf) // gap in seq_a (deletion)
  let y_mat = Array::make((m + 1) * (n + 1), neg_inf) // gap in seq_b (insertion)
  // Traceback: 0=M(diag), 1=X(up), 2=Y(left)
  let tb = Array::make((m + 1) * (n + 1), 0)
  m_mat[idx(0, 0)] = 0
  for i = 1; i <= m; i = i + 1 {
    x_mat[idx(i, 0)] = scoring.gap_open + (i - 1) * scoring.gap_extend
    tb[idx(i, 0)] = 1
  }
  for j = 1; j <= n; j = j + 1 {
    y_mat[idx(0, j)] = scoring.gap_open + (j - 1) * scoring.gap_extend
    tb[idx(0, j)] = 2
  }
  for i = 1; i <= m; i = i + 1 {
    for j = 1; j <= n; j = j + 1 {
      // X matrix: gap in seq_a (deletion)
      let x_from_m = m_mat[idx(i - 1, j)] + scoring.gap_open
      let x_from_x = x_mat[idx(i - 1, j)] + scoring.gap_extend
      x_mat[idx(i, j)] = if x_from_m >= x_from_x { x_from_m } else { x_from_x }
      // Y matrix: gap in seq_b (insertion)
      let y_from_m = m_mat[idx(i, j - 1)] + scoring.gap_open
      let y_from_y = y_mat[idx(i, j - 1)] + scoring.gap_extend
      y_mat[idx(i, j)] = if y_from_m >= y_from_y { y_from_m } else { y_from_y }
      // M matrix: match/mismatch
      let m_val = m_mat[idx(i - 1, j - 1)] +
        score_pair(seq_a[i - 1], seq_b[j - 1], scoring)
      m_mat[idx(i, j)] = m_val
      // Choose best
      let best = if m_mat[idx(i, j)] >= x_mat[idx(i, j)] &&
        m_mat[idx(i, j)] >= y_mat[idx(i, j)] {
        tb[idx(i, j)] = 0
        m_mat[idx(i, j)]
      } else if x_mat[idx(i, j)] >= y_mat[idx(i, j)] {
        tb[idx(i, j)] = 1
        x_mat[idx(i, j)]
      } else {
        tb[idx(i, j)] = 2
        y_mat[idx(i, j)]
      }
      // Update M with the best value for future references
      m_mat[idx(i, j)] = best
    }
  }
  // Traceback
  let aligned_a : Array[Int] = []
  let aligned_b : Array[Int] = []
  let mut i = m
  let mut j = n
  while i > 0 || j > 0 {
    let dir = tb[idx(i, j)]
    if dir == 0 && i > 0 && j > 0 {
      aligned_a.push(seq_a[i - 1])
      aligned_b.push(seq_b[j - 1])
      i = i - 1
      j = j - 1
    } else if dir == 1 && i > 0 {
      aligned_a.push(seq_a[i - 1])
      aligned_b.push(-1)
      i = i - 1
    } else {
      aligned_a.push(-1)
      aligned_b.push(seq_b[j - 1])
      j = j - 1
    }
  }
  reverse_int_array(aligned_a)
  reverse_int_array(aligned_b)
  let final_score = if m_mat[idx(m, n)] >= x_mat[idx(m, n)] &&
    m_mat[idx(m, n)] >= y_mat[idx(m, n)] {
    m_mat[idx(m, n)]
  } else if x_mat[idx(m, n)] >= y_mat[idx(m, n)] {
    x_mat[idx(m, n)]
  } else {
    y_mat[idx(m, n)]
  }
  {
    score: final_score,
    aligned_a: ints_to_gap_string(aligned_a),
    aligned_b: ints_to_gap_string(aligned_b),
    start_a: 0,
    start_b: 0,
    end_a: m,
    end_b: n,
  }
}

// ---------------------------------------------------------------------------
// Local Alignment with Affine Gap (Smith-Waterman + Gotoh)
// ---------------------------------------------------------------------------

///|
/// Local alignment with affine gap penalty.
///
/// Combines Smith-Waterman local alignment with Gotoh affine gap penalties.
///
/// **Time**: O(m·n), **Space**: O(m·n).
pub fn smith_waterman_affine(
  seq_a : Array[Int],
  seq_b : Array[Int],
  scoring : Scoring,
) -> AlignmentResult {
  let m = seq_a.length()
  let n = seq_b.length()
  let neg_inf = -1000000
  let idx = fn(i : Int, j : Int) -> Int { i * (n + 1) + j }
  let m_mat = Array::make((m + 1) * (n + 1), 0)
  let x_mat = Array::make((m + 1) * (n + 1), neg_inf)
  let y_mat = Array::make((m + 1) * (n + 1), neg_inf)
  let tb = Array::make((m + 1) * (n + 1), 0)
  let mut best_score = 0
  let mut best_i = 0
  let mut best_j = 0
  for i = 1; i <= m; i = i + 1 {
    for j = 1; j <= n; j = j + 1 {
      // X: gap in seq_a
      let x_from_m = m_mat[idx(i - 1, j)] + scoring.gap_open
      let x_from_x = x_mat[idx(i - 1, j)] + scoring.gap_extend
      x_mat[idx(i, j)] = if x_from_m >= x_from_x { x_from_m } else { x_from_x }
      if x_mat[idx(i, j)] < 0 {
        x_mat[idx(i, j)] = 0
      }
      // Y: gap in seq_b
      let y_from_m = m_mat[idx(i, j - 1)] + scoring.gap_open
      let y_from_y = y_mat[idx(i, j - 1)] + scoring.gap_extend
      y_mat[idx(i, j)] = if y_from_m >= y_from_y { y_from_m } else { y_from_y }
      if y_mat[idx(i, j)] < 0 {
        y_mat[idx(i, j)] = 0
      }
      // M: match/mismatch
      let m_val = m_mat[idx(i - 1, j - 1)] +
        score_pair(seq_a[i - 1], seq_b[j - 1], scoring)
      if m_val < 0 {
        m_mat[idx(i, j)] = 0
        tb[idx(i, j)] = 3
      } else {
        m_mat[idx(i, j)] = m_val
        tb[idx(i, j)] = 0
      }
      // Choose best among M, X, Y, 0
      let mut best = m_mat[idx(i, j)]
      let mut best_dir = tb[idx(i, j)]
      if x_mat[idx(i, j)] > best {
        best = x_mat[idx(i, j)]
        best_dir = 1
      }
      if y_mat[idx(i, j)] > best {
        best = y_mat[idx(i, j)]
        best_dir = 2
      }
      m_mat[idx(i, j)] = best
      tb[idx(i, j)] = best_dir
      if best > best_score {
        best_score = best
        best_i = i
        best_j = j
      }
    }
  }
  // Traceback
  let aligned_a : Array[Int] = []
  let aligned_b : Array[Int] = []
  let mut i = best_i
  let mut j = best_j
  let end_a = best_i
  let end_b = best_j
  while i > 0 && j > 0 && m_mat[idx(i, j)] > 0 {
    let dir = tb[idx(i, j)]
    if dir == 0 {
      aligned_a.push(seq_a[i - 1])
      aligned_b.push(seq_b[j - 1])
      i = i - 1
      j = j - 1
    } else if dir == 1 {
      aligned_a.push(seq_a[i - 1])
      aligned_b.push(-1)
      i = i - 1
    } else if dir == 2 {
      aligned_a.push(-1)
      aligned_b.push(seq_b[j - 1])
      j = j - 1
    } else {
      break
    }
  }
  let start_a = i
  let start_b = j
  reverse_int_array(aligned_a)
  reverse_int_array(aligned_b)
  {
    score: best_score,
    aligned_a: ints_to_gap_string(aligned_a),
    aligned_b: ints_to_gap_string(aligned_b),
    start_a,
    start_b,
    end_a,
    end_b,
  }
}

// ---------------------------------------------------------------------------
// Edit Distance (Levenshtein)
// ---------------------------------------------------------------------------

///|
/// Compute the edit distance (Levenshtein distance) between two sequences.
///
/// The minimum number of single-character edits (insertions, deletions,
/// substitutions) required to change one sequence into the other.
///
/// **Time**: O(m·n), **Space**: O(m·n) (can be reduced to O(min(m,n))).
pub fn edit_distance(seq_a : Array[Int], seq_b : Array[Int]) -> Int {
  let m = seq_a.length()
  let n = seq_b.length()
  let dp = Array::make((m + 1) * (n + 1), 0)
  let idx = fn(i : Int, j : Int) -> Int { i * (n + 1) + j }
  for i = 0; i <= m; i = i + 1 {
    dp[idx(i, 0)] = i
  }
  for j = 0; j <= n; j = j + 1 {
    dp[idx(0, j)] = j
  }
  for i = 1; i <= m; i = i + 1 {
    for j = 1; j <= n; j = j + 1 {
      if seq_a[i - 1] == seq_b[j - 1] {
        dp[idx(i, j)] = dp[idx(i - 1, j - 1)]
      } else {
        let del = dp[idx(i - 1, j)] + 1
        let ins = dp[idx(i, j - 1)] + 1
        let sub = dp[idx(i - 1, j - 1)] + 1
        dp[idx(i, j)] = if del <= ins && del <= sub {
          del
        } else if ins <= sub {
          ins
        } else {
          sub
        }
      }
    }
  }
  dp[idx(m, n)]
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
/// Reverse an integer array in place.
fn reverse_int_array(arr : Array[Int]) -> Unit {
  let mut i = 0
  let mut j = arr.length() - 1
  while i < j {
    let tmp = arr[i]
    arr[i] = arr[j]
    arr[j] = tmp
    i = i + 1
    j = j - 1
  }
}

///|
/// Convert integer array to string, using '-' for gap markers (-1).
/// Non-gap values are rendered as their integer value.
fn ints_to_gap_string(arr : Array[Int]) -> String {
  let buf : Array[Char] = []
  for i = 0; i < arr.length(); i = i + 1 {
    if arr[i] == -1 {
      buf.push((45).unsafe_to_char()) // '-'
    } else {
      // Render as single digit (0-9 for DNA/amino acid codes)
      buf.push((48 + arr[i]).unsafe_to_char())
    }
  }
  String::from_array(buf)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "seqalign: needleman_wunsch identical sequences" {
  let a = [0, 1, 2, 3]
  let s = default_scoring()
  let result = needleman_wunsch(a, a, s)
  assert_true(result.score == 8) // 4 matches * 2
  assert_true(result.aligned_a.length() == 4)
}

///|
test "seqalign: needleman_wunsch with gap" {
  // ACGT vs AGT (missing C)
  let a = [0, 1, 2, 3] // ACGT
  let b = [0, 2, 3] // AGT
  let s = default_scoring()
  let result = needleman_wunsch(a, b, s)
  // Best: ACGT / A-GT → match(A) + gap(C) + match(G) + match(T) = 2 + (-2) + 2 + 2 = 4
  assert_true(result.score == 4)
}

///|
test "seqalign: smith_waterman local alignment" {
  // Find best local alignment
  let a = [0, 1, 2, 3, 0, 1, 2, 3]
  let b = [0, 1, 2, 3]
  let s = default_scoring()
  let result = smith_waterman(a, b, s)
  // Should find 0123 as best local alignment
  assert_true(result.score == 8) // 4 matches * 2
}

///|
test "seqalign: smith_waterman no similarity" {
  let a = [0, 0, 0, 0]
  let b = [1, 1, 1, 1]
  let s = default_scoring()
  let result = smith_waterman(a, b, s)
  // No positive-scoring alignment
  assert_true(result.score == 0)
}

///|
test "seqalign: edit_distance basic" {
  assert_true(edit_distance([], []) == 0)
  assert_true(edit_distance([1], []) == 1)
  assert_true(edit_distance([], [1]) == 1)
  assert_true(edit_distance([1, 2, 3], [1, 2, 3]) == 0)
  assert_true(edit_distance([1, 2, 3], [1, 3]) == 1) // delete 2
  assert_true(edit_distance([1, 2, 3], [1, 4, 3]) == 1) // substitute 2->4
  assert_true(edit_distance([0, 1, 2, 3], [3, 2, 1, 0]) == 4) // reverse
}

///|
test "seqalign: needleman_wunsch_affine basic" {
  let a = [0, 1, 2, 3]
  let b = [0, 2, 3]
  let s = affine_scoring(2, -1, -5, -1)
  let result = needleman_wunsch_affine(a, b, s)
  // ACGT / A-GT: match(A) + gap_open(C) + match(G) + match(T) = 2 + (-5) + 2 + 2 = 1
  // Or: ACGT / -AGT: gap_open + match + match + match = -5 + 2 + 2 + 2 = 1
  assert_true(result.score == 1)
}

///|
test "seqalign: smith_waterman_affine local" {
  let a = [0, 1, 2, 3, 0, 1, 2, 3]
  let b = [0, 1, 2, 3]
  let s = affine_scoring(2, -1, -5, -1)
  let result = smith_waterman_affine(a, b, s)
  assert_true(result.score == 8)
}

///|
test "seqalign: needleman_wunsch completely different" {
  let a = [0, 0, 0, 0]
  let b = [1, 1, 1, 1]
  let s = default_scoring()
  let result = needleman_wunsch(a, b, s)
  // All mismatches or all gaps
  // 4 mismatches: 4 * (-1) = -4
  // All gaps in both: 4 * (-2) + 4 * (-2) = -16
  // So best is all mismatches: -4
  assert_true(result.score == -4)
}

///|
test "seqalign: alignment result fields" {
  let a = [0, 1, 2]
  let b = [0, 1, 2]
  let s = default_scoring()
  let result = needleman_wunsch(a, b, s)
  assert_true(result.start_a == 0)
  assert_true(result.start_b == 0)
  assert_true(result.end_a == 3)
  assert_true(result.end_b == 3)
}

///|
test "seqalign: edit_distance with gaps" {
  // Two sequences with 2 substitutions needed
  let a = [0, 1, 2, 2, 3, 4]
  let b = [5, 1, 2, 2, 1, 4]
  let d = edit_distance(a, b)
  assert_true(d == 2) // substitute 0->5 and 3->1
}
