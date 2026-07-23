/// A* pathfinding algorithm on a 2D grid.
///
/// The grid is a 1D `FixedArray[Int]` of length `width * height`, indexed by
/// `grid[row * width + col]`. A value of `0` means passable; `1` means wall.
///
/// Movement is 4-directional (up, down, left, right), each step costing 1.
/// The heuristic is Manhattan distance, which is admissible for 4-directional
/// movement on a uniform-cost grid, guaranteeing that A* finds the shortest path.
///
/// The priority queue is a simple unsorted array with linear-search extraction
/// of the minimum f-score. This keeps the implementation straightforward; for
/// production use a binary heap would be preferred.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.

/// Manhattan distance between two grid points `(x1, y1)` and `(x2, y2)`.
fn manhattan(x1 : Int, y1 : Int, x2 : Int, y2 : Int) -> Int {
  let dx = if x1 > x2 { x1 - x2 } else { x2 - x1 }
  let dy = if y1 > y2 { y1 - y2 } else { y2 - y1 }
  dx + dy
}

/// Compute the shortest path length from `(start_x, start_y)` to
/// `(goal_x, goal_y)` on the grid using A* search.
///
/// Returns `Some(length)` where `length` is the number of steps, or `None`
/// if no path exists or the input is invalid (non-positive dimensions,
/// out-of-bounds coordinates, start or goal on a wall, undersized grid).
pub fn a_star(
  grid : FixedArray[Int],
  width : Int,
  height : Int,
  start_x : Int,
  start_y : Int,
  goal_x : Int,
  goal_y : Int,
) -> Int? {
  // Validate dimensions
  if width <= 0 || height <= 0 {
    return None
  }
  // Validate coordinates
  if start_x < 0 || start_x >= width || start_y < 0 || start_y >= height {
    return None
  }
  if goal_x < 0 || goal_x >= width || goal_y < 0 || goal_y >= height {
    return None
  }
  // Check grid size
  if grid.length() < width * height {
    return None
  }

  let start_idx = start_y * width + start_x
  let goal_idx = goal_y * width + goal_x

  // Start and goal must be passable
  if grid[start_idx] != 0 || grid[goal_idx] != 0 {
    return None
  }

  // Trivial case: start is goal
  if start_idx == goal_idx {
    return Some(0)
  }

  let total = width * height
  // g_score[node] = cost from start to node; -1 = not yet reached
  let g_score = FixedArray::make(total, -1)
  // closed[node] = true if node has been fully processed
  let closed = FixedArray::make(total, false)

  // Open set: parallel arrays storing f-score and node index.
  // Extraction finds the minimum f-score by linear scan.
  let open_f : Array[Int] = []
  let open_idx : Array[Int] = []

  g_score[start_idx] = 0
  open_f.push(manhattan(start_x, start_y, goal_x, goal_y))
  open_idx.push(start_idx)

  // Direction vectors: right, left, down, up
  let dx = [1, -1, 0, 0]
  let dy = [0, 0, 1, -1]

  while open_idx.length() > 0 {
    // Extract node with minimum f-score (linear search)
    let mut min_pos = 0
    for i = 1; i < open_f.length(); i = i + 1 {
      if open_f[i] < open_f[min_pos] {
        min_pos = i
      }
    }

    let current = open_idx[min_pos]
    let current_g = g_score[current]

    // Remove from open set: swap with last element, then pop
    let last = open_f.length() - 1
    open_f[min_pos] = open_f[last]
    open_idx[min_pos] = open_idx[last]
    let _ = open_f.pop()
    let _ = open_idx.pop()

    // Skip if already closed (duplicates may exist in open set)
    if !closed[current] {
      // Goal reached — g_score is the shortest path length
      if current == goal_idx {
        return Some(current_g)
      }

      closed[current] = true

      let cur_x = current % width
      let cur_y = current / width

      // Explore 4 neighbors
      for d = 0; d < 4; d = d + 1 {
        let nx = cur_x + dx[d]
        let ny = cur_y + dy[d]
        if nx >= 0 && nx < width && ny >= 0 && ny < height {
          let nidx = ny * width + nx
          if grid[nidx] == 0 && !closed[nidx] {
            let tentative_g = current_g + 1
            if g_score[nidx] == -1 || tentative_g < g_score[nidx] {
              g_score[nidx] = tentative_g
              let f = tentative_g + manhattan(nx, ny, goal_x, goal_y)
              open_f.push(f)
              open_idx.push(nidx)
            }
          }
        }
      }
    }
  }

  None
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "a_star: basic path" {
  // 3x3 open grid, path from (0,0) to (2,2)
  // 0 0 0
  // 0 0 0
  // 0 0 0
  let grid = FixedArray::make(9, 0)
  assert_eq(a_star(grid, 3, 3, 0, 0, 2, 2), Some(4))
}

test "a_star: no path - wall blocks" {
  // 3x3 grid with a wall column in the middle
  // 0 1 0
  // 0 1 0
  // 0 1 0
  let grid = FixedArray::make(9, 0)
  grid[0 * 3 + 1] = 1
  grid[1 * 3 + 1] = 1
  grid[2 * 3 + 1] = 1
  assert_true(a_star(grid, 3, 3, 0, 0, 2, 0) is None)
}

test "a_star: straight line" {
  // 1x5 grid (single row), path from (0,0) to (4,0)
  let grid = FixedArray::make(5, 0)
  assert_eq(a_star(grid, 5, 1, 0, 0, 4, 0), Some(4))
}

test "a_star: around obstacle" {
  // 3x3 grid:
  // 0 0 0
  // 1 1 0
  // 0 0 0
  // Path from (0,0) to (0,2) must go around the wall
  let grid = FixedArray::make(9, 0)
  grid[1 * 3 + 0] = 1
  grid[1 * 3 + 1] = 1
  // Shortest: (0,0)->(1,0)->(2,0)->(2,1)->(2,2)->(1,2)->(0,2) = 6 steps
  assert_eq(a_star(grid, 3, 3, 0, 0, 0, 2), Some(6))
}

test "a_star: diagonal goal" {
  // 5x5 open grid, path from (0,0) to (4,4)
  let grid = FixedArray::make(25, 0)
  assert_eq(a_star(grid, 5, 5, 0, 0, 4, 4), Some(8))
}

test "a_star: start equals goal" {
  let grid = FixedArray::make(9, 0)
  assert_eq(a_star(grid, 3, 3, 1, 1, 1, 1), Some(0))
}

test "a_star: large grid 20x20" {
  // 20x20 open grid, from corner to opposite corner
  let grid = FixedArray::make(400, 0)
  assert_eq(a_star(grid, 20, 20, 0, 0, 19, 19), Some(38))
}

test "a_star: shortest path optimization" {
  // 5x5 grid with a wall column at x=0, rows 1-3:
  // 0 0 0 0 0
  // 1 0 0 0 0
  // 1 0 0 0 0
  // 1 0 0 0 0
  // 0 0 0 0 0
  // Path from (0,0) to (0,4): must detour around walls, shortest = 6 steps
  let grid = FixedArray::make(25, 0)
  grid[1 * 5 + 0] = 1
  grid[2 * 5 + 0] = 1
  grid[3 * 5 + 0] = 1
  assert_eq(a_star(grid, 5, 5, 0, 0, 0, 4), Some(6))
}
