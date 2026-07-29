///|
pub fn stable_matching(
  n : Int,
  men_prefs : Array[Array[Int]],
  women_prefs : Array[Array[Int]],
) -> Array[Int] {
  let result = Array::make(n, -1)
  let woman_match = Array::make(n, -1)
  let next_proposal = Array::make(n, 0)

  // Build woman rank table: rank[w][m] = preference rank of m for woman w
  let rank : Array[Array[Int]] = []
  for w in 0..<n {
    let row = Array::make(n, 0)
    for r in 0..<n {
      row[women_prefs[w][r]] = r
    }
    rank.push(row)
  }

  let mut free_count = n
  while free_count > 0 {
    // Find a free man who hasn't proposed to all women yet
    let mut m = -1
    for i in 0..<n {
      if result[i] == -1 && next_proposal[i] < n {
        m = i
        break
      }
    }
    if m == -1 {
      break
    }

    let w = men_prefs[m][next_proposal[m]]
    next_proposal[m] = next_proposal[m] + 1

    if woman_match[w] == -1 {
      // Woman is free — accept proposal
      result[m] = w
      woman_match[w] = m
      free_count = free_count - 1
    } else if rank[w][m] < rank[w][woman_match[w]] {
      // Woman prefers new suitor — trade up
      result[woman_match[w]] = -1
      result[m] = w
      woman_match[w] = m
    }
    // else: woman rejects, man stays free and tries next
  }

  result
}

///|
test "basic match" {
  let men = [[0, 1, 2], [1, 0, 2], [0, 1, 2]]
  let women = [[0, 1, 2], [1, 0, 2], [0, 1, 2]]
  assert_eq(stable_matching(3, men, women), [0, 1, 2])
}

///|
test "stability check" {
  let men = [[0, 1, 2], [2, 0, 1], [1, 0, 2]]
  let women = [[1, 0, 2], [0, 2, 1], [1, 0, 2]]
  assert_eq(stable_matching(3, men, women), [0, 2, 1])
}

///|
test "n=1" {
  let men = [[0]]
  let women = [[0]]
  assert_eq(stable_matching(1, men, women), [0])
}

///|
test "all men get their last choice" {
  // Women all prefer man 0, men all prefer woman 0
  // Man 0 gets woman 0, men 1 and 2 get their 2nd/3rd choices
  let men = [
    [0, 1, 2],
    [0, 1, 2],
    [0, 1, 2],
  ]
  let women = [
    [0, 1, 2],
    [0, 1, 2],
    [0, 1, 2],
  ]
  let result = stable_matching(3, men, women)
  // Man 0 should get woman 0 (both rank each other first)
  assert_eq(result[0], 0)
  // All men should be matched
  let mut all_matched = true
  for i = 0; i < 3; i = i + 1 {
    if result[i] < 0 {
      all_matched = false
    }
  }
  assert_true(all_matched)
}

///|
test "n=4 with conflicting preferences" {
  let men = [
    [3, 1, 2, 0],
    [1, 0, 2, 3],
    [0, 1, 3, 2],
    [2, 3, 0, 1],
  ]
  let women = [
    [2, 0, 3, 1],
    [1, 3, 0, 2],
    [3, 2, 1, 0],
    [0, 1, 2, 3],
  ]
  let result = stable_matching(4, men, women)
  // Verify all women are assigned exactly once
  let seen : Array[Bool] = [false, false, false, false]
  for i = 0; i < 4; i = i + 1 {
    assert_true(result[i] >= 0 && result[i] < 4)
    assert_false(seen[result[i]])
    seen[result[i]] = true
  }
}
