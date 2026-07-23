# Moon Certified

用 [MoonBit](https://www.moonbitlang.com) 0.9 的 `moon prove` 形式化验证系统，构建经过数学证明的核心算法与数据结构库。

## 为什么需要这个项目

MoonBit 0.9 引入了 first-class formal verification 能力，`moon prove` 成为与 `moon build`、`moon test` 并列的工具链内置命令。它通过 Why3 + Z3 SMT 求解器，对代码进行全输入覆盖的正确性证明——不是测试某几组输入碰巧返回正确结果，而是一个覆盖所有可能输入的数学证明。

但目前 MoonBit 生态中，`moonbit-community/verified` 仅包含 12 个教程级示例（v0.0.2）。本项目的目标是构建生产级验证库，覆盖排序、搜索、数据结构、图算法等核心领域。

## 项目状态

**v0.6.0** — 66 个算法包，958 个测试全部通过，`moon prove` 9/9 包验证通过 (0 失败)。

### v0.6.0 变更亮点

- **新增 8 个算法包**：Aho-Corasick 多模式匹配（字符串）；最小费用最大流 MCMF（图）；Splay 伸展树（树）；BSGS 离散对数、Pollard-Rho 整数分解（数论）；KD-Tree 空间索引、旋转卡壳（几何）；2-SAT（图）
- **Rotating Calipers 修复**：添加 CCW/CW 方向检测，正确处理逆时针和顺时针凸多边形
- **Dijkstra 溢出文档**：邻接矩阵版添加溢出说明，引导用户使用 dijkstra_heap 的 Int64 保护

### v0.5.0 变更亮点

- **新增 15 个算法包**：heap_sort、counting_sort、radix_sort（排序）；Z-function、Manacher 回文（字符串）；Miller-Rabin 素性检验、CRT 中国剩余定理（数论）；Johnson 全源最短路、双向 BFS、邻接表拓扑排序（图）；跳表、Treap（数据结构）；插值搜索、指数搜索（搜索）；Andrew 单调链凸包（几何）
- **生产级修复**：13 个 P0 关键 bug 修复（fast_power_checked 溢出、gcd Int::MIN、LRU Cache O(1) 重写、A* 二叉堆、SCC 迭代化等），7 个 P1 健壮性修复，5 个 P2 代码质量改进
- **溢出防护**：dijkstra_heap 使用 Int64 距离累积、convex_hull 使用 Int64 叉积、sieve/knapsack 添加 OOM 保护
- **文档诚实化**：所有验证状态、复杂度声明、局限性均如实标注
- **CHANGELOG.md**：遵循 Semantic Versioning 规范

### v0.3.0 变更亮点

- **红黑树完整删除**：实现 Kahrs 删除算法，含 "lost black" 跟踪和 bal_left/bal_right 修复，所有 RB 性质在删除后均得到保持（8 个新测试验证 is_valid_rb）
- **魔术值全部消除**：bound_search 空数组返回 0（非 -1），dijkstra 返回 `FixedArray[Int?]`（None=不可达），mod_inverse 返回 `Int?`（None=无逆元），union_find find 返回 `Int?`（None=越界）
- **验证诚实化**：移除误导性的 `proof_axiomatized` 引理（power_ge_one_lemma, gcd_divides_lemma, array_sum_correct_lemma），代码注释明确区分已验证性质与未验证性质
- **数据结构封装**：新增 `Heap` 结构体封装二叉堆（自动维护 size），`StringHashTable` 封装哈希表（自动存储 hash_fn/eq_fn），`UnionFind` 声明为 `pub struct`
- **Trie 功能增强**：新增 `size`、`enumerate`、`longest_prefix` 函数
- **整数溢出防护**：新增 `fast_power_checked` 使用 Int64 检测溢出，`gcd` 安全处理负数输入，sieve 添加 n+1 溢出保护
- **整数溢出文档**：所有涉及溢出的函数均添加明确文档说明

### v0.2.0 变更亮点

- **全库泛型化**：排序包（insertion_sort, selection_sort, merge_sort, quick_sort）全面转为 `FixedArray[T]` + 比较器模式，支持任意可比类型
- **泛型搜索包**：已验证的 Int 版本保留，新增泛型伴随函数 `search_generic` / `max_element_generic` / `min_element_generic` / `is_sorted_generic`
- **类型安全错误处理**：消除全部魔术值，使用 `SPResult` 枚举和 `Option` 类型替代 `-1`/空数组等歧义返回值
- **红黑树**：使用 Okasaki 函数式插入算法重写
- **新增 8 个包**：rabin_karp, hash_table, prim, scc, fenwick, trie, bound_search, red_black_tree
- **MoonBit String 短词典序发现**：发现 MoonBit 的 `String` `Compare` trait 使用短词典序（先比长度），实现了正确的逐字节字典序比较器

## 验证状态

### 验证深度分级

| 级别 | 包 | 验证内容 |
|------|---|---------|
| ✅ 完整正确性 | binary_search | 找到则返回正确索引，未找到返回 None |
| ✅ 完整正确性 | linear_search | 返回正确索引或 None |
| ✅ 完整正确性 | max_element | 返回的索引指向最大元素 |
| ✅ 完整正确性 | min_element | 返回的索引指向最小元素 |
| ✅ 完整正确性 | is_sorted | 返回 true 时数组有序；返回 false 时存在逆序对 |
| ⚠️ 部分验证 | array_sum | 结果非负（非负输入下），完整正确性未验证 |
| ⚠️ 部分验证 | gcd | 结果非负（非负输入下），整除性/最大性未验证 |
| ⚠️ 部分验证 | fast_power | 结果非负（非负输入下），base^exp 正确性未验证 |
| ⚠️ 部分验证 | dijkstra | 数组边界 + 结果长度，最短路径最优性未验证 |

**重要说明**：
- ✅ 完整正确性：Z3 证明了算法的核心正确性（找到正确结果或正确判断有序性）
- ⚠️ 部分验证：Z3 证明了部分性质（非负性、边界安全），但完整正确性需要非线性算术推理，超出 Z3 自动证明能力
- `proof_axiomatized` 引理 `graph_index_bound`（dijkstra 中使用）是一个数学上正确但被假设而非证明的非线性算术事实（涉及两个变量相乘 `u * n`，Z3 线性算术求解器无法自动证明）。保留此公理是为了让 Z3 能验证它力所能及的部分——数组长度属性 `result.length() == n`
- **泛型版本均未形式化验证**：表中标注"✅ verified + generic"的包，其 ✅ 仅指已验证的 Int 版本，泛型伴随函数（`search_generic[T]` 等）不做验证，注释中明确标注
- 所有"部分验证"和"仅测试验证"的包都通过详尽的测试套件验证正确性，包括边界情况和随机输入

### 溢出说明

形式化验证将 `Int` 建模为数学整数，但运行时 `Int` 是 32 位有符号整数。以下函数在结果超出 2³¹−1 时会发生静默溢出：

| 函数 | 溢出行为 | 安全替代 |
|------|---------|---------|
| `fast_power` | 结果可能变为负数 | `fast_power_checked`（返回 `Int?`，已修复溢出检测） |
| `gcd` | 输入安全（已处理 `Int::MIN`，返回 `Int::MAX`） | — |
| `array_sum` | 大数组求和可能溢出 | 调用者需确保和不溢出 |
| `sieve` | n > 10⁷ 时返回空数组 | 已添加 OOM 保护 |
| `dijkstra_heap` | 距离使用 Int64 累积，溢出时返回 `None` | 已添加溢出防护 |
| `convex_hull` | 叉积使用 Int64 计算 | 已添加溢出防护 |
| `max_flow` | `total_flow` 可能溢出 Int32 | 文档已标注，调用者需注意 |
| `knapsack` | n × capacity > 10⁷ 时返回 0 | 已添加 OOM 保护 |
| `lcs` | n × m > 10⁷ 时返回 0 | 已添加 OOM 保护 |
| `edit_distance` | n × m > 10⁷ 时返回 max(n,m) | 已添加 OOM 保护 |
| `prim` | `total_weight` 可能溢出 Int32 | 文档已标注，调用者需注意 |
| `segment_tree` | 区间和可能溢出 Int32 | 文档已标注，调用者需注意 |
| `fenwick` | 前缀和可能溢出 Int32 | 文档已标注，调用者需注意 |
| `kruskal` | `total_weight` 可能溢出 Int32 | 文档已标注，调用者需注意 |

### 泛型架构

| 包 | 泛型支持 | 说明 |
|---|---------|------|
| insertion_sort | ✅ `FixedArray[T]` + cmp | 完全泛型，支持任意类型 |
| selection_sort | ✅ `FixedArray[T]` + cmp | 完全泛型，支持任意类型 |
| merge_sort | ✅ `FixedArray[T]` + cmp | 完全泛型，支持任意类型 |
| quick_sort | ✅ `FixedArray[T]` + cmp | 完全泛型，三取中 pivot |
| binary_search | ✅ verified + generic | 保留已验证 Int 版本 + `search_generic[T]` |
| linear_search | ✅ verified + generic | 保留已验证 Int 版本 + `search_generic[T]` |
| max_element | ✅ verified + generic | 保留已验证 Int 版本 + `max_element_generic[T]` |
| min_element | ✅ verified + generic | 保留已验证 Int 版本 + `min_element_generic[T]` |
| is_sorted | ✅ verified + generic | 保留已验证 Int 版本 + `is_sorted_generic[T]` |
| bound_search | ✅ `FixedArray[T]` + cmp | lower_bound, upper_bound, binary_search_generic |
| red_black_tree | ✅ `RBNode[T]` + cmp | Okasaki 插入 + Kahrs 删除 |
| binary_heap | ✅ comparator + Heap 封装 | min-heap/max-heap 通过 should_swap 统一 |
| hash_table | ✅ `HashTable[K, V]` 泛型 | 开放寻址 + 线性探测，含 `StringHashTable` 封装 |
| trie | ✅ String | 含 size/enumerate/longest_prefix |

比较器约定：`cmp(a, b)` 返回负数表示 `a < b`，0 表示相等，正数表示 `a > b`。

### 类型安全错误处理

| 包 | 旧返回值 | 新返回值 | 说明 |
|---|---------|---------|------|
| bellman_ford | 空数组/`-1` | `SPResult?` | `None`=无效输入, `NegativeCycle`=负环, `Distances(FixedArray[Int?])`=距离 |
| floyd_warshall | 空数组/`-1` | `SPResult?` | 同上，`Distances` 包含 n*n 矩阵 |
| topological_sort | 空数组 | `FixedArray[Int]?` | `None`=环或无效输入 |
| dijkstra | `FixedArray[Int]` (-1=不可达) | `FixedArray[Int?]` | `None`=不可达 |
| shortest_path | `-1` | `Int?` | `None`=不可达或无效 |
| bfs_distances | 空数组 | `FixedArray[Int]?` | `None`=无效输入，`-1` 保留为不可达标记（BFS 跳数 ≥ 0） |
| bound_search | `-1` (空数组) | `0` | 空数组返回 0（= 数组长度），语义一致 |
| mod_inverse | `-1` (无逆元) | `Int?` | `None`=无逆元或无效输入 |
| union_find find | `-1` (越界) | `Int?` | `None`=越界 |

`SPResult` 枚举定义：
```moonbit
pub enum SPResult {
  Distances(FixedArray[Int?])  // Some(d)=可达, None=不可达
  NegativeCycle                // 检测到负环
}
```

## 使用方式

### 环境要求

- MoonBit 0.9+
- [Why3](https://why3.lri.fr/) 1.7.2 (推荐通过 opam 安装：`opam install why3.1.7.2`)
- [Z3](https://github.com/Z3Prover/z3) 4.12.x SMT 求解器

### 运行

```bash
# 克隆仓库
git clone https://github.com/Juwan-Hwang/moon-certified.git
cd moon-certified

# 类型检查
moon check

# 运行测试 (958 tests)
moon test

# 运行形式化验证 (需要 Why3 1.7.2 + Z3 4.12.x)
moon prove
```

### 在项目中使用

```bash
moon add Juwan-Hwang/moon-certified
```

```moonbit
fn main {
  // Binary search (verified)
  let xs = FixedArray::makei(10, fn(i) { i })
  let result = @binary_search.search(xs, 5)
  println(result) // Some(5)

  // Generic binary search with custom comparator
  let words = FixedArray::make(4, "")
  words[0] = "apple"; words[1] = "banana"; words[2] = "cherry"; words[3] = "date"
  let str_cmp = fn(a : String, b : String) -> Int {
    let la = a.length(); let lb = b.length()
    let min = if la < lb { la } else { lb }
    for k = 0; k < min; k = k + 1 {
      let c = a[k].to_int() - b[k].to_int()
      if c != 0 { return c }
    }
    la - lb
  }
  let idx = @binary_search.search_generic(words, "cherry", str_cmp)
  println(idx) // Some(2)

  // Generic sorting with comparator
  let arr = FixedArray::makei(5, fn(i) { 5 - i })
  @insertion_sort.insertion_sort(arr, fn(a, b) { a - b })
  println(arr) // [1, 2, 3, 4, 5]

  // Bellman-Ford with type-safe error handling
  let graph = FixedArray::make(9, 0)
  graph[0 * 3 + 1] = 4; graph[0 * 3 + 2] = 5; graph[1 * 3 + 2] = -3
  match @advanced.bellman_ford(graph, 3, 0) {
    Some(Distances(dist)) => println(dist[2]) // Some(1)
    Some(NegativeCycle) => println("negative cycle!")
    None => println("invalid input")
  }

  // Red-Black Tree (Okasaki insertion + Kahrs deletion)
  let tree : @red_black_tree.RBNode[String] = @red_black_tree.empty()
  let tree = @red_black_tree.insert(tree, "hello", str_cmp)
  let tree = @red_black_tree.delete(tree, "hello", str_cmp)
  println(@red_black_tree.search(tree, "hello", str_cmp)) // false

  // KMP string matching
  let pos = @kmp.kmp_search("hello world", "world")
  println(pos) // Some(6)

  // Fenwick Tree (Binary Indexed Tree)
  let arr = FixedArray::makei(10, fn(i) { i + 1 })
  let ft = @fenwick.build(arr)
  println(@fenwick.query(ft, 5)) // 15 (1+2+3+4+5)

  // Hash Table (encapsulated)
  let ht = @hash_table.hashtable_new_default(16)
  @hash_table.hashtable_insert(ht, "key", 42)
  println(@hash_table.hashtable_get(ht, "key")) // Some(42)

  // Binary Heap (encapsulated)
  let h = @binary_heap.heap_new(20)
  h.heap_push(5)
  h.heap_push(3)
  h.heap_push(7)
  println(h.heap_pop()) // Some(3)

  // Topological Sort (returns Option)
  let dag = FixedArray::make(9, 0)
  dag[0 * 3 + 1] = 1; dag[1 * 3 + 2] = 1
  match @topological_sort.topo_sort(dag, 3) {
    Some(order) => println(order) // [0, 1, 2]
    None => println("cycle detected")
  }

  // Dijkstra (returns FixedArray[Int?])
  let n = 3
  let g = FixedArray::make(n * n, 0)
  g[0 * n + 1] = 2; g[1 * n + 2] = 3
  let dist = @dijkstra.dijkstra(g, n, 0)
  println(dist[2]) // Some(5)

  // Fast power with overflow check
  match @fast_power.fast_power_checked(2, 30) {
    Some(r) => println(r) // 1073741824
    None => println("overflow!")
  }

  // Union-Find (find returns Int?)
  let uf = @union_find.new(5)
  let _ = @union_find.union(uf, 0, 1)
  println(@union_find.find(uf, 0)) // Some(0) or Some(1)
  println(@union_find.find(uf, 99)) // None (out of range)
}
```

## 技术原理

每个验证算法包含两类文件：

| 文件 | 内容 |
|------|------|
| `.mbt` | 可执行代码 + 契约 (`proof_require`/`proof_ensure`) + 循环不变量 (`proof_invariant`) |
| `.mbtp` | 逻辑谓词定义和引理 |

验证流程：

```
.mbt + .mbtp  →  moonc prove  →  Why3 + Z3
源代码 + 谓词     生成 WhyML       证明所有目标
```

### 验证策略

1. **for 累加器模式替代 let mut**：Dijkstra 的 find-min 循环使用累加器模式，使 Z3 能通过循环不变量追踪变量边界
2. **proof_axiomatized 引理（诚实标注）**：dijkstra 的 `graph_index_bound` 是唯一的公理引理。它假设一个涉及两变量相乘（`u * n`）的非线性算术事实。Z3 线性算术求解器无法证明非线性事实，因此该引理被假设而非证明。数学上正确（`u*n + v < n*n <= len`），但未通过 Z3 验证。保留此公理的收益：Z3 能验证数组长度属性 `result.length() == n`
3. **分治验证**：将可验证部分（边界、终止性、数组长度）与不可验证部分（量化不变量保持、最短路径最优性）分离
4. **输入校验**：所有可失败操作均做输入校验，使用 `Option`/`SPResult` 而非魔术值
5. **comparator 参数化**：binary_heap 的 sift 操作通过 `should_swap` 函数参数统一了 min-heap 和 max-heap 实现
6. **已验证 + 泛型双层架构**：搜索包保留已验证 Int 版本作为正确性参考，泛型版本扩展到任意类型。**注意：泛型版本本身不做形式化验证**，仅通过测试验证

### MoonBit String 比较注意事项

MoonBit 的 `String` 和 `Bytes` 类型的 `Compare` trait 使用**短词典序**（shortlex order）：先比较长度，长度短的更小。这与标准的字典序不同。

例如：`"date"` < `"apple"` 在 MoonBit 中为 `true`，因为 `"date"` 长度为 4，`"apple"` 长度为 5。

本项目在需要标准字典序的场景（红黑树、二分查找、排序的 String 测试）中使用自定义的逐字节比较器：

```moonbit
let str_cmp = fn(a : String, b : String) -> Int {
  let la = a.length(); let lb = b.length()
  let min = if la < lb { la } else { lb }
  for k = 0; k < min; k = k + 1 {
    let ca = a[k].to_int(); let cb = b[k].to_int()
    if ca < cb { return -1 }
    if ca > cb { return 1 }
  }
  la - lb
}
```

## 项目结构

```
moon-certified/
├── search/
│   ├── binary_search/        ✅ 二分查找 (verified) + generic
│   ├── bound_search/         🔒 lower_bound/upper_bound (generic)
│   ├── linear_search/        ✅ 线性查找 (verified) + generic
│   ├── max_element/          ✅ 最大元素 (verified) + generic
│   ├── min_element/          ✅ 最小元素 (verified) + generic
│   ├── interpolation_search/🔒 插值搜索 (Int64 防溢出)
│   └── exponential_search/   🔒 指数搜索 (galloping search)
├── sorting/
│   ├── insertion_sort/       🔒 插入排序 (generic, 12 tests)
│   ├── selection_sort/       🔒 选择排序 (generic, 10 tests)
│   ├── merge_sort/           🔒 归并排序 (generic, 15 tests, 稳定性已验证)
│   ├── quick_sort/           🔒 快速排序 (generic, 15 tests)
│   ├── heap_sort/            🔒 堆排序 (generic, 12 tests)
│   ├── counting_sort/        🔒 计数排序 (OOM 防护, 12 tests)
│   ├── radix_sort/           🔒 基数排序 LSD (stable, 11 tests)
│   └── is_sorted/            ✅ 有序性检查 (verified) + generic
├── containers/
│   ├── binary_heap/          🔒 二叉堆 (Heap 封装 + HeapG[T], 17 tests)
│   ├── hash_table/           🔒 哈希表 K,V 泛型 (StringHashTable 封装, 19 tests)
│   ├── lru_cache/            🔒 LRU Cache O(1) (HashMap+双向链表, 8 tests)
│   ├── bloom_filter/         🔒 布隆过滤器 (最优参数, 9 tests)
│   └── union_find/           🔒 并查集 (pub struct, find→Int?, 16 tests)
├── trees/
│   ├── bst/                  🔒 二叉搜索树 (教学示例, 19 tests)
│   ├── avl/                  🔒 AVL 平衡树 (O(1) size, 17 tests)
│   ├── red_black_tree/       🔒 红黑树 Okasaki+Kahrs (generic, 23 tests)
│   ├── btree/                🔒 B-Tree (16 tests)
│   ├── segment_tree/         🔒 线段树 + LazySegTree (19 tests)
│   ├── fenwick/              🔒 树状数组 (14 tests)
│   ├── trie/                 🔒 字典树 (sparse children, 17 tests)
│   ├── skip_list/            🔒 跳表 (O(log n) expected, 13 tests)
│   ├── treap/                🔒 Treap (O(log n) expected, 13 tests)
│   └── splay/              🔒 伸展树 (bottom-up splay, amortized O(log n), 10 tests)
├── graph/
│   ├── bfs_dfs/              🔒 BFS/DFS 邻接矩阵版 (Option 返回, 34 tests)
│   ├── adj_list/             🔒 邻接表稀疏图 (O(V+E) 空间, 23 tests)
│   ├── topological_sort/     🔒 拓扑排序 邻接矩阵版 (Option 返回, 12 tests)
│   ├── topological_sort_adj/ 🔒 拓扑排序 邻接表版 Kahn (16 tests)
│   ├── kruskal/              🔒 最小生成树 (14 tests)
│   ├── prim/                 🔒 Prim MST (11 tests)
│   ├── scc/                  🔒 Tarjan SCC 迭代版 (12 tests)
│   ├── dijkstra/             ⚠️ Dijkstra (partial verified, FixedArray[Int?])
│   ├── dijkstra_heap/        🔒 堆优化 Dijkstra (Int64 溢出防护, 11 tests)
│   ├── johnson/              🔒 Johnson 全源最短路 (负权+负环检测, 11 tests)
│   ├── bidirectional_bfs/    🔒 双向 BFS (13 tests)
│   ├── a_star/               🔒 A* 搜索 (二叉堆+路径重建, 11 tests)
│   ├── max_flow/             🔒 Edmonds-Karp 最大流 (12 tests)
│   ├── advanced/             🔒 Bellman-Ford + Floyd-Warshall (SPResult, 19 tests)
│   ├── min_cost_flow/      🔒 最小费用最大流 SPFA (linked-forward-star, 9 tests)
│   └── two_sat/            🔒 2-SAT (implication graph + Tarjan SCC, 8 tests)
├── string/
│   ├── kmp/                  🔒 KMP (17 tests)
│   ├── rabin_karp/           🔒 Rabin-Karp (25 tests)
│   ├── suffix_array/         🔒 后缀数组 (15 tests)
│   ├── z_function/           🔒 Z 算法 (z_array + z_search, 19 tests)
│   ├── manacher/             🔒 Manacher 回文 (longest/count/radii, 23 tests)
│   └── aho_corasick/       🔒 Aho-Corasick 多模式匹配 (failure links, 9 tests)
├── number_theory/
│   ├── gcd/                  ⚠️ GCD (partial verified, handles Int::MIN)
│   ├── fast_power/           ⚠️ 快速幂 (partial verified + checked variant)
│   ├── prime/                🔒 素数筛 + 扩展欧几里得 (OOM 防护, 18 tests)
│   ├── miller_rabin/         🔒 Miller-Rabin 素性检验 (deterministic, 11 tests)
│   ├── crt/                  🔒 中国剩余定理 (coprime + non-coprime, 20 tests)
│   ├── bsgs/               🔒 BSGS 离散对数 (O(√p), 8 tests)
│   └── pollard_rho/        🔒 Pollard-Rho 整数分解 (Miller-Rabin + Brent, 10 tests)
├── math/
│   └── array_sum/            ⚠️ 数组求和 (partial verified)
├── dp/
│   ├── dp/                   🔒 LCS + 编辑距离 + 背包 (OOM 防护, 21 tests)
│   └── lis/                  🔒 LIS O(n log n) (14 tests)
├── geometry/
│   ├── convex_hull/          🔒 Graham 凸包 (Int64 防溢出, 9 tests)
│   ├── andrew_hull/          🔒 Andrew 单调链凸包 (Int64 防溢出, 11 tests)
│   ├── kd_tree/            🔒 KD-Tree 2D 空间索引 (NN + range search, 13 tests)
│   └── rotating_calipers/  🔒 旋转卡壳 (凸包直径+宽度, CCW/CW, 14 tests)
├── .github/workflows/
│   └── ci.yml                ✅ GitHub Actions CI (check + test + prove)
├── CHANGELOG.md              📋 Semantic Versioning changelog
├── moon.mod.json
├── LICENSE
└── README.md
```

图例：✅ = 完整正确性验证 | ⚠️ = 部分验证 | 🔒 = 仅测试验证

## 测试统计

| 包 | 测试数 | moon prove | 泛型 |
|---|--------|------------|------|
| binary_search | 8 | ✅ 完整正确性 | ✅ generic |
| bound_search | 11 | 🔒 tested | ✅ generic |
| linear_search | 8 | ✅ 完整正确性 | ✅ generic |
| max_element | 7 | ✅ 完整正确性 | ✅ generic |
| min_element | 7 | ✅ 完整正确性 | ✅ generic |
| interpolation_search | 11 | 🔒 tested | ❌ |
| exponential_search | 11 | 🔒 tested | ❌ |
| insertion_sort | 12 | 🔒 tested | ✅ generic |
| selection_sort | 10 | 🔒 tested | ✅ generic |
| merge_sort | 15 | 🔒 tested | ✅ generic |
| quick_sort | 15 | 🔒 tested | ✅ generic |
| heap_sort | 12 | 🔒 tested | ✅ generic |
| counting_sort | 12 | 🔒 tested | ❌ |
| radix_sort | 11 | 🔒 tested | ❌ |
| is_sorted | 10 | ✅ 完整正确性 | ✅ generic |
| binary_heap | 17 | 🔒 tested | ✅ HeapG[T] |
| hash_table | 19 | 🔒 tested | ✅ HashTable[K,V] |
| lru_cache | 8 | 🔒 tested | ❌ |
| bloom_filter | 9 | 🔒 tested | ❌ |
| union_find | 16 | 🔒 tested | ❌ (pub struct) |
| bst | 19 | 🔒 tested | ❌ |
| avl | 17 | 🔒 tested | ❌ |
| red_black_tree | 23 | 🔒 tested | ✅ generic |
| btree | 16 | 🔒 tested | ❌ |
| segment_tree | 19 | 🔒 tested | ❌ |
| fenwick | 14 | 🔒 tested | ❌ |
| trie | 17 | 🔒 tested | ✅ String |
| skip_list | 13 | 🔒 tested | ❌ |
| treap | 13 | 🔒 tested | ❌ |
| bfs_dfs | 34 | 🔒 tested | ❌ |
| adj_list | 23 | 🔒 tested | ❌ |
| topological_sort | 12 | 🔒 tested | ❌ |
| topological_sort_adj | 16 | 🔒 tested | ❌ |
| kruskal | 14 | 🔒 tested | ❌ |
| prim | 11 | 🔒 tested | ❌ |
| scc | 12 | 🔒 tested | ❌ |
| dijkstra | 11 | ⚠️ 部分验证 | ❌ |
| dijkstra_heap | 11 | 🔒 tested | ❌ |
| johnson | 11 | 🔒 tested | ❌ |
| bidirectional_bfs | 13 | 🔒 tested | ❌ |
| a_star | 11 | 🔒 tested | ❌ |
| max_flow | 12 | 🔒 tested | ❌ |
| advanced | 19 | 🔒 tested | ❌ |
| kmp | 17 | 🔒 tested | ❌ |
| rabin_karp | 25 | 🔒 tested | ❌ |
| suffix_array | 15 | 🔒 tested | ❌ |
| z_function | 19 | 🔒 tested | ❌ |
| manacher | 23 | 🔒 tested | ❌ |
| gcd | 8 | ⚠️ 部分验证 | ❌ |
| fast_power | 12 | ⚠️ 部分验证 | ❌ |
| prime | 18 | 🔒 tested | ❌ |
| miller_rabin | 11 | 🔒 tested | ❌ |
| crt | 20 | 🔒 tested | ❌ |
| array_sum | 7 | ⚠️ 部分验证 | ❌ |
| dp | 21 | 🔒 tested | ❌ |
| lis | 14 | 🔒 tested | ❌ |
| convex_hull | 9 | 🔒 tested | ❌ |
| andrew_hull | 11 | 🔒 tested | ❌ |
| aho_corasick | 9 | 🔒 tested | ❌ |
| min_cost_flow | 9 | 🔒 tested | ❌ |
| two_sat | 8 | 🔒 tested | ❌ |
| splay | 10 | 🔒 tested | ❌ |
| bsgs | 8 | 🔒 tested | ❌ |
| pollard_rho | 10 | 🔒 tested | ❌ |
| kd_tree | 13 | 🔒 tested | ❌ |
| rotating_calipers | 14 | 🔒 tested | ❌ |
| **Total** | **958** | **5 完整, 4 部分, 57 tested** | **16 generic** |

## 参考资源

- [MoonBit 形式化验证文档](https://docs.moonbitlang.com/en/latest/language/verification.html)
- [moonbit-community/verified](https://github.com/moonbit-community/verified) — 官方教程级验证示例
- [MoonBit 0.9 发布博客](https://www.moonbitlang.com/blog/moonbit-0-9-release)
- [Why3 文档](https://www.why3.org/) — Why3 验证平台
- [Z3 SMT Solver](https://github.com/Z3Prover/z3) — SMT 求解器
- [Okasaki, "Red-Black Trees in a Functional Setting"](https://www.cs.cmu.edu/~rwh/theses/okasaki.pdf) — 红黑树函数式插入算法
- [Kahrs, "Red-Black Trees with Types"](https://www.cs.kent.ac.uk/people/staff/smk/redblack/redblack.pdf) — 红黑树函数式删除算法

## 许可证

Apache-2.0
