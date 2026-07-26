fn stable_matching(n: Int, men_prefs: Array[Array[Int]], women_prefs: Array[Array[Int]]) -> Array[Int] {
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

test "basic match" {
  let men = [[0, 1, 2], [1, 0, 2], [0, 1, 2]]
  let women = [[0, 1, 2], [1, 0, 2], [0, 1, 2]]
  assert_eq(stable_matching(3, men, women), [0, 1, 2])
}

test "stability check" {
  let men = [[0, 1, 2], [2, 0, 1], [1, 0, 2]]
  let women = [[1, 0, 2], [0, 2, 1], [1, 0, 2]]
  assert_eq(stable_matching(3, men, women), [0, 2, 1])
}

test "n=1" {
  let men = [[0]]
  let women = [[0]]
  assert_eq(stable_matching(1, men, women), [0])
}
