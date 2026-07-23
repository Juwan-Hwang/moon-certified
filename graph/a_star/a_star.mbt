/// A* pathfinding algorithm on a 2D grid.
///
/// The grid is a 1D `FixedArray[Int]` of length `width * height`, indexed by
/// `grid[row * width + col]`. A value of `0` means passable; `1` means wall.
///
/// Movement is 4-directional (up, down, left, right), each step costing 1.
/// The heuristic is Manhattan distance, which is admissible for 4-directional
/// movement on a uniform-cost grid, guaranteeing that A* finds the shortest path.
///
/// The priority queue is a binary min-heap of `(f_score, node)` pairs,
/// giving O(E log V) extraction instead of the O(V²) linear-scan approach.
/// Lazy deletion is used: stale entries (with f > current best) are skipped.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite below.
///
/// **Overflow**: `f_score = g_score + manhattan_distance` is accumulated as
/// 32-bit `Int`. Since each step costs 1 and the grid is at most
/// `width * height` cells, `g_score` is bounded by `width + height`.
/// For grids where `width + height > Int::max_value` (extremely unlikely),
/// overflow could occur. In practice, grid sizes are far below this limit.

/// Manhattan distance between two grid points `(x1, y1)` and `(x2, y2)`.
fn manhattan(x1 : Int, y1 : Int, x2 : Int, y2 : Int) -> Int {
  let dx = if x1 > x2 { x1 - x2 } else { x2 - x1 }
  let dy = if y1 > y2 { y1 - y2 } else { y2 - y1 }
  dx + dy
}

/// A min-heap entry: (f_score, node_index).
priv struct PQEntry {
  f : Int
  node : Int
}

/// Binary min-heap keyed on `f`.
priv struct PriorityQueue {
  data : Array[PQEntry]
}

fn PriorityQueue::new() -> PriorityQueue {
  { data: [] }
}

fn PriorityQueue::len(pq : PriorityQueue) -> Int {
  pq.data.length()
}

/// Push a (f, node) pair. Sifts up to restore heap property. O(log n).
fn PriorityQueue::push(pq : PriorityQueue, f : Int, node : Int) -> Unit {
  pq.data.push({ f, node })
  let mut i = pq.data.length() - 1
  while i > 0 {
    let parent = (i - 1) / 2
    if pq.data[i].f < pq.data[parent].f {
      let tmp = pq.data[i]
      pq.data[i] = pq.data[parent]
      pq.data[parent] = tmp
      i = parent
    } else {
      break
    }
  }
}

/// Pop the minimum entry. Returns None if empty. Sifts down. O(log n).
fn PriorityQueue::pop(pq : PriorityQueue) -> PQEntry? {
  let n = pq.data.length()
  if n == 0 {
    return None
  }
  let result = pq.data[0]
  pq.data[0] = pq.data[n - 1]
  let _ = pq.data.pop()
  let len = pq.data.length()
  let mut i = 0
  while true {
    let left = 2 * i + 1
    let right = 2 * i + 2
    let mut smallest = i
    if left < len && pq.data[left].f < pq.data[smallest].f {
      smallest = left
    }
    if right < len && pq.data[right].f < pq.data[smallest].f {
      smallest = right
    }
    if smallest != i {
      let tmp = pq.data[i]
      pq.data[i] = pq.data[smallest]
      pq.data[smallest] = tmp
      i = smallest
    } else {
      break
    }
  }
  Some(result)
}

/// Outcome of an A* search.
///
/// `goal_g` is `Some(g)` when the goal was reached in `g` steps, or `None`
/// when the input is invalid or no path exists. `came_from` is the
/// predecessor map populated during the search (`came_from[n]` is the node
/// from which `n` was first reached on the optimal path); it is only
/// meaningful when `goal_g` is `Some`.
priv struct AStarResult {
  goal_g : Int?
  came_from : FixedArray[Int]
}

/// Sentinel result for searches that do not reach the goal (invalid input or
/// no path). The `came_from` array is empty and never indexed by callers.
fn no_path() -> AStarResult {
  { goal_g: None, came_from: FixedArray::make(0, 0) }
}

/// Core A* search shared by `a_star` and `a_star_path`.
///
/// Validates the input, runs the heap-driven A* loop, and returns the goal's
/// g-score together with the `came_from` predecessor map. The two public
/// entry points differ only in how they turn this result into their return
/// value: `a_star` discards `came_from`; `a_star_path` reconstructs the
/// actual path from it.
fn a_star_search(
  grid : FixedArray[Int],
  width : Int,
  height : Int,
  start_x : Int,
  start_y : Int,
  goal_x : Int,
  goal_y : Int,
) -> AStarResult {
  if width <= 0 || height <= 0 {
    return no_path()
  }
  if start_x < 0 || start_x >= width || start_y < 0 || start_y >= height {
    return no_path()
  }
  if goal_x < 0 || goal_x >= width || goal_y < 0 || goal_y >= height {
    return no_path()
  }
  if grid.length() < width * height {
    return no_path()
  }
  let start_idx = start_y * width + start_x
  let goal_idx = goal_y * width + goal_x
  if grid[start_idx] != 0 || grid[goal_idx] != 0 {
    return no_path()
  }
  if start_idx == goal_idx {
    return { goal_g: Some(0), came_from: FixedArray::make(0, 0) }
  }
  let total = width * height
  let g_score = FixedArray::make(total, -1)
  let came_from = FixedArray::make(total, -1)
  let closed = FixedArray::make(total, false)
  let pq = PriorityQueue::new()
  g_score[start_idx] = 0
  PriorityQueue::push(pq, manhattan(start_x, start_y, goal_x, goal_y), start_idx)
  let dx = [1, -1, 0, 0]
  let dy = [0, 0, 1, -1]
  while PriorityQueue::len(pq) > 0 {
    match PriorityQueue::pop(pq) {
      Some({ f: _, node: current }) => {
        if closed[current] {
          continue  // Skip stale entries (lazy deletion)
        }
        let current_g = g_score[current]
        if current == goal_idx {
          return { goal_g: Some(current_g), came_from }
        }
        closed[current] = true
        let cur_x = current % width
        let cur_y = current / width
        for d = 0; d < 4; d = d + 1 {
          let nx = cur_x + dx[d]
          let ny = cur_y + dy[d]
          if nx >= 0 && nx < width && ny >= 0 && ny < height {
            let nidx = ny * width + nx
            if grid[nidx] == 0 && !closed[nidx] {
              let tentative_g = current_g + 1
              if g_score[nidx] == -1 || tentative_g < g_score[nidx] {
                g_score[nidx] = tentative_g
                came_from[nidx] = current
                let f = tentative_g + manhattan(nx, ny, goal_x, goal_y)
                PriorityQueue::push(pq, f, nidx)
              }
            }
          }
        }
      }
      None => break
    }
  }
  no_path()
}

/// Compute the shortest path length from `(start_x, start_y)` to
/// `(goal_x, goal_y)` on the grid using A* search.
///
/// Returns `Some(length)` where `length` is the number of steps, or `None`
/// if no path exists or the input is invalid.
pub fn a_star(
  grid : FixedArray[Int],
  width : Int,
  height : Int,
  start_x : Int,
  start_y : Int,
  goal_x : Int,
  goal_y : Int,
) -> Int? {
  a_star_search(grid, width, height, start_x, start_y, goal_x, goal_y).goal_g
}

/// Compute the shortest path from `(start_x, start_y)` to
/// `(goal_x, goal_y)` on the grid, returning the actual path.
///
/// Returns `Some(path)` where `path` is a `FixedArray[Int]` of grid indices
/// from start to goal (inclusive), or `None` if no path exists.
pub fn a_star_path(
  grid : FixedArray[Int],
  width : Int,
  height : Int,
  start_x : Int,
  start_y : Int,
  goal_x : Int,
  goal_y : Int,
) -> FixedArray[Int]? {
  let r = a_star_search(grid, width, height, start_x, start_y, goal_x, goal_y)
  match r.goal_g {
    None => None
    Some(g) => {
      let goal_idx = goal_y * width + goal_x
      let path_len = g + 1
      let path = FixedArray::make(path_len, 0)
      let mut node = goal_idx
      for i = path_len - 1; i >= 0; i = i - 1 {
        path[i] = node
        // For the trivial `start == goal` case `g == 0`, the loop runs once
        // with `i == 0`, so `came_from` is never indexed (it is empty).
        if i > 0 {
          node = r.came_from[node]
        }
      }
      Some(path)
    }
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "a_star: basic path" {
  let grid = FixedArray::make(9, 0)
  assert_eq(a_star(grid, 3, 3, 0, 0, 2, 2), Some(4))
}

test "a_star: no path - wall blocks" {
  let grid = FixedArray::make(9, 0)
  grid[0 * 3 + 1] = 1
  grid[1 * 3 + 1] = 1
  grid[2 * 3 + 1] = 1
  assert_true(a_star(grid, 3, 3, 0, 0, 2, 0) is None)
}

test "a_star: straight line" {
  let grid = FixedArray::make(5, 0)
  assert_eq(a_star(grid, 5, 1, 0, 0, 4, 0), Some(4))
}

test "a_star: around obstacle" {
  let grid = FixedArray::make(9, 0)
  grid[1 * 3 + 0] = 1
  grid[1 * 3 + 1] = 1
  assert_eq(a_star(grid, 3, 3, 0, 0, 0, 2), Some(6))
}

test "a_star: diagonal goal" {
  let grid = FixedArray::make(25, 0)
  assert_eq(a_star(grid, 5, 5, 0, 0, 4, 4), Some(8))
}

test "a_star: start equals goal" {
  let grid = FixedArray::make(9, 0)
  assert_eq(a_star(grid, 3, 3, 1, 1, 1, 1), Some(0))
}

test "a_star: large grid 20x20" {
  let grid = FixedArray::make(400, 0)
  assert_eq(a_star(grid, 20, 20, 0, 0, 19, 19), Some(38))
}

test "a_star: shortest path optimization" {
  let grid = FixedArray::make(25, 0)
  grid[1 * 5 + 0] = 1
  grid[2 * 5 + 0] = 1
  grid[3 * 5 + 0] = 1
  assert_eq(a_star(grid, 5, 5, 0, 0, 0, 4), Some(6))
}

test "a_star_path: basic path reconstruction" {
  let grid = FixedArray::make(9, 0)
  let path = a_star_path(grid, 3, 3, 0, 0, 2, 2)
  match path {
    Some(p) => {
      assert_eq(p.length(), 5) // 4 steps + start
      assert_eq(p[0], 0)       // start at (0,0) = index 0
      assert_eq(p[4], 8)       // goal at (2,2) = index 8
    }
    None => abort("expected a path")
  }
}

test "a_star_path: no path returns None" {
  let grid = FixedArray::make(9, 0)
  grid[0 * 3 + 1] = 1
  grid[1 * 3 + 1] = 1
  grid[2 * 3 + 1] = 1
  assert_true(a_star_path(grid, 3, 3, 0, 0, 2, 0) is None)
}

test "a_star_path: start equals goal" {
  let grid = FixedArray::make(9, 0)
  let path = a_star_path(grid, 3, 3, 1, 1, 1, 1)
  match path {
    Some(p) => {
      assert_eq(p.length(), 1)
      assert_eq(p[0], 4) // index of (1,1) in 3x3 grid
    }
    None => abort("expected a path")
  }
}
