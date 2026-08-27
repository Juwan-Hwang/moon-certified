# Moon Certified

用 [MoonBit](https://www.moonbitlang.com) 0.9 的 `moon prove` 形式化验证系统，构建经过数学证明的核心算法与数据结构库。

## 为什么需要这个项目

MoonBit 0.9 引入了 first-class formal verification 能力，`moon prove` 成为与 `moon build`、`moon test` 并列的工具链内置命令。它通过 Why3 + Z3 SMT 求解器，对代码进行全输入覆盖的正确性证明——不是测试某几组输入碰巧返回正确结果，而是一个覆盖所有可能输入的数学证明。

但目前 MoonBit 生态中，`moonbit-community/verified` 仅包含 12 个教程级示例（v0.0.2）。本项目的目标是构建生产级验证库，覆盖排序、搜索、数据结构、图算法等核心领域。

## 项目状态

**0.1.0**（首个正式发布版本，2026-08-27）— 337 个算法包 + 共享工具模块。发布时质量门槛：`moon check --deny-warn` 0 errors / 0 warnings，`moon test` **6432 个测试全部通过**，`moon fmt --check` 干净，`moon prove` **17 个包全部证明通过**（其中 9 个为 Verified tier）。

稳定性分层（详见 [docs/API_STABILITY.md](docs/API_STABILITY.md)）：

| 层级 | 包数 | 说明 |
|------|------|------|
| Verified | 9 | `proof-enabled = true`，`moon prove`（Why3 + Z3）通过 |
| Stable | 254 | 完整测试覆盖，主版本内 API 冻结 |
| Experimental | 74 | 正确（测试全过）但 API 未冻结，小版本可能变更 |

### 功能概览

- **337 个算法包**，覆盖核心算法全领域：
  - **并发数据结构**：RingBuffer、BoundedQueue、SnapshotMap (COW 快照) — Michael-Scott/Vyukov/Treiber 等并发算法的单线程模拟 (MoonBit 编译至 Wasm/JS, 无原生 CAS; 自旋锁提供真实互斥)
  - **持久化/外部算法**：External Sort、LSM-Tree、B+Tree、Persistent Vector、HAMT
  - **字符串高级结构**：Suffix Tree、FM-Index、Wavelet Tree、Palindromic Tree、Lyndon 分解、Suffix Balanced Tree
  - **图高级算法**：Edmonds Blossom (一般图最大匹配)、Dominator Tree、Gomory-Hu Tree、Stoer-Wagner 全局最小割、HLPP 最大流、Hopcroft-Karp、Min Steiner Tree、HLD、重心分解、虚树、最大团 (Bron-Kerbosch)、图着色、下界限制流
  - **几何进阶**：3D 凸包、Voronoi 图、Delaunay 三角剖分、半平面交、动态凸包
  - **数学/数值**：FFT (复数)、单纯形法 (LP)、LU/QR/SVD 分解、特征值、Newton 迭代、Berlekamp-Massey、共轭梯度法、GMRES、L-BFGS、自动微分
  - **概率/近似结构**：Count-Min Sketch、HyperLogLog、Cuckoo Filter、W-TinyLFU、TTL Cache
  - **数论进阶**：二次剩余、原根、Möbius 反演、有限域、Reed-Solomon 编码、多项式运算
  - **DP 进阶**：数位 DP、状压 DP、凸壳技巧 (CHT)、分治 DP、Knuth 优化、SOS DP
  - **搜索/ML 基础**：Ball-Tree、VP-Tree、LSH、Ternary Search
  - **其他**：Nim 博弈 (Sprague-Grundy)、水库采样、加权随机采样、CRC、Mo 算法、李超树、二维树状数组、Segment Tree Beats、External Sort

- **生产级设计**：
  - 所有魔术值消除，使用 `Option`/`SPResult` 类型替代 `-1`/空数组等歧义返回值
  - 关键算法使用 Int64 溢出保护（dijkstra_heap、convex_hull、max_flow、dinic、min_cost_flow 等）
  - 自平衡树（AVL、红黑树、BTree、Treap）依赖结构不变量保证 O(log n) 递归深度，无需人为深度限制
  - `swap` 集中在 `@utils`（消除 7 处重复）
  - `SplitMix64`/`XorShift64` 集中在 `@utils/prng`（消除多包重复）
  - 每实例随机种子 `@utils.fresh_seed()`（替代全局固定种子）

- **测试/验证基础设施**：
  - **benchmarks/** 目录：性能基准测试，含排序/树/图/数论/字符串/几何的 wall-clock 时间测量与复杂度验证
  - **test/fuzz/** 目录：Fuzz 测试 + 对抗性输入测试（排序最坏情况、图自环/断开/环检测、字符串 Unicode、Carmichael 数、几何共线/重复点、并发结构边界）
  - **test/stress/** 增强：排序压力测试验证置换性质（非仅有序性），LIS 压力测试重构实际子序列验证（非仅平凡边界）
  - **test/property_test/** QuickCheck 风格属性测试框架（随机输入生成 + 反例缩减）
  - **test/test_utils/** 共享测试工具（消除 14 个文件的 str_cmp 重复）
  - **docs/API_STABILITY.md** API 稳定性策略

- **算法实现策略**：
  - 最小费用最大流：**Successive Shortest Paths with Potentials**（首迭代 SPFA + 后续 Dijkstra），复杂度 O(V·E + F·E log V)
  - prim/segment_tree/fenwick/kruskal：提供 checked 变体 (Int64 溢出检测)
  - miller_rabin：确定性 12 见证集 {2,3,5,7,...,37}（覆盖全 Int64 范围，Sorenson & Webster 2015）
  - euler_sieve：返回 None 而非 abort，与全库 Option 策略一致
  - andrew_hull cmp_point：Int64 减法防溢出，与 closest_pair 一致

## 验证状态

### 验证深度分级

| 级别 | 包 | 验证内容 |
|------|---|---------|
| ✅ 完整正确性 | binary_search | 找到则返回正确索引，未找到返回 None |
| ✅ 完整正确性 | linear_search | 返回正确索引或 None |
| ✅ 完整正确性 | max_element | 返回的索引指向最大元素 |
| ✅ 完整正确性 | min_element | 返回的索引指向最小元素 |
| ✅ 完整正确性 | is_sorted | 返回 true 时数组有序；返回 false 时存在逆序对 |
| 🔶 增强验证 | array_sum | 非负性 + 有界求和 [n·lo, n·hi] + 均匀数组精确等式 n·val |
| 🔶 增强验证 | gcd | 非负性 + 整除自反性 d|d + 零整除性 d|0 |
| 🔶 增强验证 | fast_power | 非负性 + base≥1 时 result≥1 + base≥1 exp≥1 时 result≥base |
| ⚠️ 部分验证 | dijkstra | 数组边界 + 结果长度，最短路径最优性未验证（公理引理已诚实标注） |
| ⚠️ 部分验证 | binary_heap | 索引边界 (parent/left/right child) |
| ⚠️ 部分验证 | bitset | 容量非负 |
| ⚠️ 部分验证 | union_find | self_parent 初始化正确性 |
| ⚠️ 部分验证 | red_black_tree | empty() 返回空树、size() 结构等值（缓存字段非负性由构造保证，不在证明范围） |
| ⚠️ 部分验证 | kruskal | MST 边数 ≤ n-1 |
| ⚠️ 部分验证 | topological_sort | edge_index 非负性（上界为非线性算术，由测试覆盖，未声明为已证） |
| ⚠️ 部分验证 | kmp | LPS 数组长度 == pattern 长度 |
| ⚠️ 部分验证 | combinatorics | 阶乘结果 ≥ 1 |
| ⚠️ 部分验证 | matrix | identity_int 长度 n² + transpose_int 长度 n·m（索引边界使用诚实标注的公理引理） |
| ⚠️ 部分验证 | insertion_sort | n≤1 时 sorted_asc vacuously true |
| ⚠️ 部分验证 | merge_sort | n≤1 时 sorted_asc vacuously true |

**重要说明**：
- ✅ 完整正确性：Z3 证明了算法的核心正确性（找到正确结果或正确判断有序性）
- 🔶 增强验证：在部分验证基础上，新增了更强的性质验证（如精确等式、单调性、整除性等）
- ⚠️ 部分验证：Z3 证明了部分性质（非负性、边界安全），但完整正确性需要非线性算术推理，超出 Z3 自动证明能力
- `proof_axiomatized` 引理 `graph_index_bound`（dijkstra 中使用）是一个数学上正确但被假设而非证明的非线性算术事实（涉及两个变量相乘 `u * n`，Z3 线性算术求解器无法自动证明）。保留此公理是为了让 Z3 能验证它力所能及的部分——数组长度属性 `result.length() == n`
- **泛型版本均未形式化验证**：表中标注"✅ verified + generic"的包，其 ✅ 仅指已验证的 Int 版本，泛型伴随函数（`search_generic[T]` 等）不做验证，注释中明确标注
- 所有"部分验证"和"仅测试验证"的包都通过详尽的测试套件验证正确性，包括边界情况和随机输入

### 溢出说明

形式化验证将 `Int` 建模为数学整数，但运行时 `Int` 是 32 位有符号整数。以下函数在结果超出 2³¹−1 时会发生静默溢出：

| 函数 | 溢出行为 | 安全替代 |
|------|---------|---------|
| `fast_power` | 结果可能变为负数 | `fast_power_checked`（返回 `Int?`，已修复溢出检测） |
| `gcd` | 输入安全（Int::MIN 使用 Int64 精确计算，仅 gcd(Int::MIN,Int::MIN) 钳位至 Int::MAX） | — |
| `array_sum` | 大数组求和可能溢出 | 调用者需确保和不溢出 |
| `sieve` | n > 10⁷ 时返回 `None`（OOM 保护） | 返回 `FixedArray[Int]?` |
| `dijkstra_heap` | 距离使用 Int64 累积，溢出时返回 `None` | 已添加溢出防护 |
| `convex_hull` | 叉积使用 Int64 计算 | 已添加溢出防护 |
| `max_flow` | `total_flow` 使用 Int64 累积，返回 `Int64?` 区分无效输入 | 已添加溢出防护 |
| `knapsack` | n × capacity > 10⁷ 时返回 `None` | 已添加 OOM 保护 |
| `lcs` | n × m > 10⁷ 时返回 `None` | 返回 `Int?`，滚动数组优化 O(min(n,m)) 空间 |
| `edit_distance` | n × m > 10⁷ 时返回 `None` | 返回 `Int?`，滚动数组优化 O(min(n,m)) 空间 |
| `counting_sort` | 负值或 k > 10⁷ 时返回 `None` | 返回 `FixedArray[Int]?` |
| `pollard_rho` | 失败（素数或无法分解）时返回 `None` | 返回 `Int?`，与素数结果可区分 |
| `prim` | `total_weight` 累加使用 `Int64` 防溢出 | `prim_mst` 返回 `(FixedArray[Int], Int64)` |
| `segment_tree` | 区间和可能溢出 Int32 | 文档已标注；`SegmentTree64` 提供 checked 变体返回 `Int?` |
| `fenwick` | 前缀和可能溢出 Int32 | 文档已标注；`Fenwick64` 提供 checked 变体返回 `Int?` |
| `kruskal` | `total_weight` 可能溢出 Int32 | 文档已标注；`kruskal_mst_checked` 返回 `(FixedArray[Edge], Int64)?` |
| `min_cost_flow` | `total_flow`/`total_cost` 使用 Int64 累积，返回 `(Int64,Int64)?` | 已添加溢出防护 + 负环检测 |
| `dinic` | 所有容量和流量使用 Int64，返回 `Int64?` | 已添加溢出防护 + 迭代 DFS |
| `interpolation_search` | 减法使用 Int64 防止跨 Int32 范围溢出 | 已添加溢出防护 |
| `gcd64` | 正确处理 `Int64::MIN`（不做预先取绝对值） | 已修复 |
| `is_prime64` | 见证集扩展到全 Int64 范围（Sorenson & Webster 2015） | 已修复 |
| `array_sum` | `array_sum_checked` 返回 `Int?`（溢出返回 None） | 已添加安全版本 |
| `matrix` | `matmul_int_checked` 返回 `FixedArray[Int]?`（溢出返回 None） | 已添加安全版本 |
| `combinatorics` | binomial 先乘后除（Int64 中间），stirling2 预检查溢出 | 已修复 |
| `rolling_hash` | 双模数哈希使用 Int64 中间运算，大字符串仍可能溢出 | 文档已标注，调用者需注意 |
| `matrix_decomp` | 使用 Double 浮点运算，无整数溢出风险 | 浮点精度限制 |
| `newton_method` | 使用 Double 浮点运算，无整数溢出风险 | 浮点精度限制 |

### 泛型架构

| 包 | 泛型支持 | 说明 |
|---|---------|------|
| insertion_sort | ✅ `FixedArray[T]` + cmp | 完全泛型，支持任意类型 |
| selection_sort | ✅ `FixedArray[T]` + cmp | 完全泛型，支持任意类型 |
| merge_sort | ✅ `FixedArray[T]` + cmp | 完全泛型，支持任意类型 |
| quick_sort | ✅ `FixedArray[T]` + cmp | 完全泛型，三取中 pivot |
| binary_search | ✅ verified (Int) + generic (unverified) | 保留已验证 Int 版本 + `search_generic[T]` |
| linear_search | ✅ verified (Int) + generic (unverified) | 保留已验证 Int 版本 + `search_generic[T]` |
| max_element | ✅ verified (Int) + generic (unverified) | 保留已验证 Int 版本 + `max_element_generic[T]` |
| min_element | ✅ verified (Int) + generic (unverified) | 保留已验证 Int 版本 + `min_element_generic[T]` |
| is_sorted | ✅ verified (Int) + generic (unverified) | 保留已验证 Int 版本 + `is_sorted_generic[T]` |
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

# 运行测试 (6432 tests)
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
│   ├── binary_search/        ✅ 二分查找 (verified Int) + generic (unverified)
│   ├── bound_search/         🔒 lower_bound/upper_bound (generic)
│   ├── linear_search/        ✅ 线性查找 (verified Int) + generic (unverified)
│   ├── max_element/          ✅ 最大元素 (verified Int) + generic (unverified)
│   ├── min_element/          ✅ 最小元素 (verified Int) + generic (unverified)
│   ├── interpolation_search/🔒 插值搜索 (Int64 防溢出)
│   └── exponential_search/   🔒 指数搜索 (galloping search)
│   ├── fibonacci_search/    🔒 斐波那契搜索 (8 tests)
│   ├── jump_search/         🔒 跳跃搜索 (8 tests)
│   ├── ternary_search/      🔒 三分搜索 (单峰函数极值, 7 tests)
│   ├── quickselect/         🔒 快速选择 (第 k 小, 8 tests)
│   ├── ball_tree/           🔒 Ball-Tree (度量空间近邻, 8 tests)
│   ├── vp_tree/             🔒 VP-Tree (vantage point 树, 8 tests)
│   ├── lsh/                 🔒 LSH 局部敏感哈希 (近似近邻, 7 tests)
│   └── hnsw/                🔒 HNSW (分层可导航小世界图, 8 tests)
├── sorting/
│   ├── insertion_sort/       🔒 插入排序 (generic, 12 tests)
│   ├── selection_sort/       🔒 选择排序 (generic, 10 tests)
│   ├── merge_sort/           🔒 归并排序 (generic, 15 tests, 稳定性已验证)
│   ├── quick_sort/           🔒 快速排序 (generic, 15 tests)
│   ├── heap_sort/            🔒 堆排序 (generic, 12 tests)
│   ├── counting_sort/        🔒 计数排序 (OOM 防护, 12 tests)
│   ├── radix_sort/           🔒 基数排序 LSD (stable, 11 tests)
│   └── is_sorted/            ✅ 有序性检查 (verified Int) + generic (unverified)
│   ├── external_sort/      🔒 外部排序 (k 路归并, binary_heap 复用, 8 tests)
├── containers/
│   ├── binary_heap/          🔒 二叉堆 (Heap 封装 + HeapG[T] + decrease_key, 17 tests)
│   ├── hash_table/           🔒 哈希表 K,V 泛型 (StringHashTable 封装, 19 tests)
│   ├── lru_cache/            🔒 LRU Cache O(1) (HashMap+双向链表, 8 tests)
│   ├── ttl_cache/            🔒 TTL Cache (过期清理 + LRU, 10 tests)
│   ├── w_tinylfu/            🔒 W-TinyLFU 缓存 (Window+SLRU+CMS, 11 tests)
│   ├── bloom_filter/         🔒 布隆过滤器 (最优参数, 9 tests)
│   ├── cuckoo_filter/        🔒 布谷鸟过滤器 (支持删除, 8 tests)
│   ├── count_min_sketch/     🔒 Count-Min Sketch (双哈希+合并, 10 tests)
│   ├── hyperloglog/          🔒 HyperLogLog 基数估计 (10 tests)
│   ├── union_find/           🔒 并查集 (pub struct, find→Int?, 16 tests)
│   ├── priority_queue/       🔒 优先队列 (HeapG[T], 动态扩容, decrease_key, 15 tests)
│   ├── monotonic/            🔒 单调栈/单调队列 (next greater/smaller, 滑动窗口, 21 tests)
│   ├── bitset/             🔒 位集 (位运算, 8 tests)
│   ├── deque/              🔒 双端队列 (环形缓冲区, 8 tests)
│   ├── consistent_hash/    🔒 一致性哈希 (虚拟节点, 7 tests)
│   ├── crc/                🔒 CRC 校验 (CRC32, 7 tests)
│   ├── hash_utils/         🔒 哈希工具 (next_pow2, Fibonacci 哈希, 6 tests)
│   ├── lsm_tree/           🔒 LSM-Tree (内存 MemTable+SSTable+Bloom, 10 tests)
│   ├── roaring_bitmap/     🔒 Roaring Bitmap (压缩位图, 8 tests)
│   ├── count_sketch/       🔒 Count Sketch (频率估计, 7 tests)
│   └── concurrent/         🔒 并发原语 (RingBuffer/BoundedQueue/SnapshotMap, 9 tests)
├── trees/
│   ├── bst/                  🔒 二叉搜索树 (迭代实现, 无栈溢出风险, 22 tests)
│   ├── avl/                  🔒 AVL 平衡树 (O(1) size, 17 tests)
│   ├── red_black_tree/       🔒 红黑树 Okasaki+Kahrs (generic, 23 tests)
│   ├── btree/                🔒 B-Tree (16 tests)
│   ├── segment_tree/         🔒 线段树 + LazySegTree (19 tests)
│   ├── fenwick/              🔒 树状数组 (14 tests)
│   ├── trie/                 🔒 字典树 (sparse children, autocomplete, wildcard search, 17 tests)
│   ├── skip_list/            🔒 跳表 (O(log n) expected, 13 tests)
│   ├── treap/                🔒 Treap (per-instance RNG, O(log n) expected, 13 tests)
│   ├── splay/              🔒 伸展树 (iterative bottom-up, amortized O(log n), 10 tests)
│   ├── sparse_table/       🔒 Sparse Table RMQ (泛型, O(1) 幂等查询, 13 tests)
│   ├── segment_tree_lazy/  🔒 线段树 Lazy Propagation (区间修改+区间查询, 9 tests)
│   ├── link_cut/           🔒 Link-Cut Tree (Sleator-Tarjan splay, 12 tests)
│   ├── persistent_vector/ 🔒 Persistent Vector (结构共享, O(log n), 9 tests)
│   ├── bplus_tree/        🔒 B+ Tree (叶子链表, 范围查询, 10 tests)
│   ├── hamt/              🔒 HAMT (Hash Array Mapped Trie, 10 tests)
│   ├── li_chao_tree/      🔒 李超树 (线段维护一次函数最大值, 8 tests)
│   ├── persistent_segment_tree/ 🔒 可持久化线段树 (k 大值查询, 8 tests)
│   ├── segment_tree_beats/ 🔒 Segment Tree Beats (区间最值取 chmax/chmin, 8 tests)
│   ├── bit_2d/            🔒 二维树状数组 (8 tests)
│   └── mo_algorithm/      🔒 Mo 算法 (离线区间查询, 8 tests)
├── graph/
│   ├── bfs_dfs/              🔒 BFS/DFS 邻接矩阵版 (Option 返回, 34 tests)
│   ├── adj_list/             🔒 邻接表稀疏图 (O(V+E) 空间, 23 tests)
│   ├── topological_sort/     🔒 拓扑排序 邻接矩阵版 (Option 返回, 12 tests)
│   ├── topological_sort_adj/ 🔒 拓扑排序 邻接表版 Kahn (16 tests)
│   ├── kruskal/              🔒 最小生成树 (14 tests)
│   ├── prim/                 🔒 Prim MST (11 tests)
│   ├── scc/                  🔒 Tarjan SCC 迭代版 (12 tests)
│   ├── dijkstra/             ⚠️ Dijkstra (partial verified: array bounds only, FixedArray[Int?])
│   ├── dijkstra_heap/        🔒 堆优化 Dijkstra (Int64 溢出防护, 11 tests)
│   ├── johnson/              🔒 Johnson 全源最短路 (负权+负环检测, 11 tests)
│   ├── bidirectional_bfs/    🔒 双向 BFS (13 tests)
│   ├── a_star/               🔒 A* 搜索 (二叉堆+路径重建, 11 tests)
│   ├── max_flow/             🔒 Edmonds-Karp 最大流 (12 tests)
│   ├── advanced/             🔒 Bellman-Ford + Floyd-Warshall (SPResult, 19 tests)
│   ├── min_cost_flow/      🔒 最小费用最大流 SPFA (linked-forward-star, 9 tests)
│   └── two_sat/            🔒 2-SAT (implication graph + Tarjan SCC, 8 tests)
│   ├── dinic/              🔒 Dinic 最大流 (level graph + iterative blocking flow, 8 tests)
│   ├── lca/               🔒 LCA 最近公共祖先 (binary lifting, O(log n) query, 11 tests)
│   ├── bridge_articulation/ 🔒 桥+割点 (Tarjan, 多重边处理, 15 tests)
│   ├── euler_path/          🔒 欧拉路径/回路 (Hierholzer, 迭代实现, 14 tests)
│   ├── hungarian/           🔒 匈牙利算法 (二分图最优匹配, O(n³), 10 tests)
│   ├── hopcroft_karp/       🔒 Hopcroft-Karp 二分匹配 (O(E√V), 9 tests)
│   ├── stoer_wagner/        🔒 Stoer-Wagner 全局最小割 (O(V³), 10 tests)
│   ├── max_clique/          🔒 Bron-Kerbosch 最大团 (pivot+退化度, 12 tests)
│   ├── edmonds_blossom/    🔒 Edmonds 一般图最大匹配 (BFS 增广, 8 tests)
│   ├── dominator_tree/     🔒 支配树 (Lengauer-Tarjan, 8 tests)
│   ├── gomory_hu/          🔒 Gomory-Hu 树 (全对最小割, 8 tests)
│   ├── hlpp/               🔒 HLPP 最大流 (预流推进, 8 tests)
│   ├── hld/                🔒 重链剖分 (路径修改/查询, 8 tests)
│   ├── centroid_decomposition/ 🔒 重心分解 (点分治, 8 tests)
│   ├── virtual_tree/       🔒 虚树 (关键点压缩, 8 tests)
│   ├── min_steiner_tree/   🔒 最小 Steiner 树 (DP, 8 tests)
│   ├── graph_coloring/     🔒 图着色 (DSATUR 启发式, 8 tests)
│   ├── flow_with_bounds/   🔒 上下界网络流 (8 tests)
│   └── pagerank/           🔒 PageRank (幂迭代, 7 tests)
├── string/
│   ├── kmp/                  🔒 KMP (17 tests)
│   ├── rabin_karp/           🔒 Rabin-Karp (25 tests)
│   ├── suffix_array/         🔒 后缀数组 (15 tests)
│   ├── z_function/           🔒 Z 算法 (z_array + z_search, 19 tests)
│   ├── manacher/             🔒 Manacher 回文 (longest/count/radii, 23 tests)
│   ├── aho_corasick/       🔒 Aho-Corasick 多模式匹配 (sparse children, CJK 安全, 12 tests)
│   ├── boyer_moore/         🔒 Boyer-Moore 字符串搜索 (bad-char + good-suffix, 14 tests)
│   ├── lcp_array/           🔒 LCP 数组 (Kasai 算法, O(n), 13 tests)
│   ├── suffix_automaton/    🔒 后缀自动机 SAM (子串查询, 不同子串计数, 12 tests)
│   ├── suffix_tree/         🔒 后缀树 (Ukkonen O(n), 12 tests)
│   ├── palindromic_tree/    🔒 回文树 Eertree (所有回文子串, 11 tests)
│   ├── rolling_hash/        🔒 滚动哈希 (双模数防碰撞, 12 tests)
│   ├── lyndon/              🔒 Lyndon 分解 (Duval 算法, 最小表示, 13 tests)
│   ├── fm_index/            🔒 FM-Index (计数/定位, 8 tests)
│   ├── wavelet_tree/        🔒 Wavelet Tree (rank/select, 8 tests)
│   └── regex/               🔒 正则表达式引擎 (Thompson NFA, 10 tests)
│   /// **字符串算法缺失声明**：当前 22 个字符串包覆盖了核心模式匹配和后缀结构，
│   /// 但以下算法尚未实现：de Bruijn 序列、Lyndon suffix array 构造 (LA factor)、
│   /// runs (Lempel-Ziv 解析)、Suffix Array ↔ Tree 互转工具函数。
├── number_theory/
│   ├── gcd/                  ⚠️ GCD (partial verified, handles Int::MIN)
│   ├── fast_power/           ⚠️ 快速幂 (partial verified + checked variant)
│   ├── int64_utils/          🔒 Int64 工具 (mod64/gcd64/pow_mod64/is_prime64, 21 tests)
│   ├── prime/                🔒 素数筛 + 扩展欧几里得 (OOM 防护, 18 tests)
│   ├── miller_rabin/         🔒 Miller-Rabin 素性检验 (deterministic, 11 tests)
│   ├── crt/                  🔒 中国剩余定理 (coprime + non-coprime, 20 tests)
│   ├── bsgs/               🔒 BSGS 离散对数 (O(√p), 8 tests)
│   ├── pollard_rho/        🔒 Pollard-Rho 整数分解 (Miller-Rabin + Brent, 10 tests)
│   ├── euler_sieve/        🔒 Euler 线性筛 (O(n) + O(log n) 因式分解, 11 tests)
│   └── ntt/                🔒 数论变换 NTT (O(n log n) 多项式乘法, 11 tests)
│   ├── bigint/             🔒 大整数运算 (加减乘除, 10 tests)
│   ├── cipolla/            🔒 Cipolla 平方根 (模素数, 17 tests)
│   ├── finite_field/       🔒 有限域 GF(p) 运算 (7 tests)
│   ├── mobius/             🔒 Möbius 反演 (7 tests)
│   ├── polynomial/         🔒 多项式运算 (NTT 乘法, 8 tests)
│   ├── primitive_root/     🔒 原根 (7 tests)
│   ├── quadratic_residue/  🔒 二次剩余 (Tonelli-Shanks, 7 tests)
│   ├── reed_solomon/       🔒 Reed-Solomon 编解码 (8 tests)
│   └── pohlig_hellman/     🔒 Pohlig-Hellman 离散对数 (16 tests)
│   ├── carmichael/         🔒 Carmichael 函数 (5 tests)
│   ├── aks/                🔒 AKS 确定性素数测试 (5 tests)
│   ├── quadratic_sieve/    🔒 二次筛法因式分解 (5 tests)
│   └── lehman_factor/      🔒 Lehman 因式分解 (5 tests)
├── math/
│   ├── array_sum/            ⚠️ 数组求和 (partial verified + checked variant)
│   ├── combinatorics/        🔒 组合数学 (组合数/Catalan/Stirling, Int64 防溢出, 15 tests)
│   ├── matrix/               🔒 矩阵运算 (乘法+高斯消元+行列式, checked variant, 12 tests)
│   ├── matrix_decomp/        🔒 矩阵分解 LU/QR/SVD (部分主元/Householder/Jacobi, 16 tests)
│   ├── newton_method/        🔒 Newton 迭代法 (根求解+n次根+平方根, 23 tests)
│   ├── berlekamp_massey/     🔒 Berlekamp-Massey 线性递推 (O(n²), 10 tests)
│   ├── fft/                  🔒 FFT 快速傅里叶变换 (Cooley-Tukey, 11 tests)
│   └── simplex/              🔒 单纯形法 线性规划 (两阶段, 10 tests)
├── dp/
│   ├── dp/                   🔒 LCS + 编辑距离 + 背包 (OOM 防护, 21 tests)
│   ├── lis/                  🔒 LIS O(n log n) (14 tests)
│   ├── interval_dp/          🔒 区间 DP (矩阵链乘+最优BST+burst balloons+石子合并, 22 tests)
│   ├── tree_dp/              🔒 树形 DP (最大独立集+直径+匹配+树背包, 迭代DFS, 19 tests)
│   └── digit_dp/            🔒 数位 DP (计数+各位数字和+不含某数字, 11 tests)
├── geometry/
│   ├── convex_hull/          🔒 Graham 凸包 (Int64 防溢出, 9 tests)
│   ├── andrew_hull/          🔒 Andrew 单调链凸包 (Int64 防溢出, 11 tests)
│   ├── convex_hull_3d/       🔒 3D 凸包 (随机增量法+地平线边, 12 tests)
│   ├── half_plane_intersection/ 🔒 半平面交 (S&I 算法+双端队列, 9 tests)
│   ├── kd_tree/            🔒 KD-Tree 2D 空间索引 (NN + range search, 13 tests)
│   ├── rotating_calipers/  🔒 旋转卡壳 (凸包直径+宽度, CCW/CW, 14 tests)
│   ├── closest_pair/       🔒 最近点对 (分治 O(n log n), 9 tests)
│   ├── segment_ops/       🔒 线段相交+点在多边形内 (精确整数叉积, 33 tests)
│   ├── delaunay/          🔒 Delaunay 三角剖分 (增量法, 8 tests)
│   ├── voronoi/           🔒 Voronoi 图 (Delaunay 对偶, 7 tests)
│   ├── dynamic_hull/      🔒 动态凸包 (在线插入, 8 tests)
│   ├── min_enclosing_circle/ 🔒 最小包围圆 (随机增量, 7 tests)
│   ├── minkowski_sum/     🔒 Minkowski 和 (凸多边形, 8 tests)
│   └── polygon_boolean/   🔒 多边形布尔运算 (并/交/差, 8 tests)
├── game_theory/
│   ├── nim_sg/               🔒 Nim 博弈 (Sprague-Grundy 定理, 13 tests)
│   ├── alpha_beta/           🔒 Alpha-Beta 剪枝 / Negamax (Tic-Tac-Toe 验证, 7 tests)
│   ├── mcts/                 🔒 Monte Carlo Tree Search (UCT, 7 tests)
│   ├── gale_shapley/         🔒 Gale-Shapley 稳定匹配 (10 tests)
│   └── shapley_value/        🔒 Shapley 值 (精确+Monte Carlo, 5 tests)
│   ├── negamax/             🔒 Negamax 搜索 (Alpha-Beta 剪枝, 3 tests)
│   └── transposition_table/ 🔒 置换表 (Zobrist 哈希, 6 tests)
├── random/
│   ├── reservoir_sampling/   🔒 水库采样 (O(n) 在线采样, 8 tests)
│   ├── weighted_sampling/    🔒 Alias Method + 加权水库采样 (SplitMix64, 8 tests)
│   ├── fisher_yates/         🔒 Fisher-Yates 洗牌 (Partial Shuffle, 7 tests)
│   ├── mersenne_twister/     🔒 Mersenne Twister MT19937 (32/64-bit, 8 tests)
│   ├── pcg/                  🔒 PCG 随机数生成器 (32/64-bit, 6 tests)
│   ├── xoshiro/              🔒 Xoshiro256**/512** PRNG (8 tests)
│   ├── gaussian_sampling/    🔒 Box-Muller 高斯采样 (6 tests)
│   ├── zobrist_hash/         🔒 Zobrist 哈希 (棋盘状态哈希, 5 tests)
│   └── mcmc/                 🔒 Metropolis-Hastings MCMC (14 tests)
│   └── monte_carlo/        🔒 Monte Carlo 积分 (7 tests)
├── sorting/
│   ├── timsort/              🔒 TimSort (run 检测+归并栈, 稳定, 12 tests)
│   ├── introsort/            🔒 Introsort (快排+堆排+插入排, 10 tests)
│   ├── pdq_sort/             🔒 Pattern-Defeating Quicksort (10 tests)
│   └── bucket_sort/          🔒 桶排序 (10 tests)
├── containers/
│   ├── treiber_stack/        🔒 Treiber 栈 (单线程 CAS 模拟, 8 tests)
│   ├── mpmc_queue/           🔒 MPMC 队列 (单线程 CAS 模拟, Vyukov, 8 tests)
│   ├── concurrent_hash_map/  🔒 Concurrent HashMap (单线程分段锁模拟, 9 tests)
│   └── work_stealing/        🔒 Work-Stealing 队列 (单线程模拟, Chase-Lev, 8 tests)
│   ├── lock_free_queue/    🔒 无锁队列 (单线程模拟, 8 tests)
│   ├── skip_list/          🔒 跳表 (独立包, 4 tests)
│   ├── counting_bloom/     🔒 计数布隆过滤器 (5 tests)
│   ├── cuckoo_hashmap/    🔒 布谷鸟哈希表 (6 tests)
│   └── bimap/             🔒 双向映射 (5 tests)
│   └── monotonic/            🔒 单调栈/单调队列 (21 tests)
├── trees/
│   ├── rope/                 🔒 Rope (平衡树字符串, O(log n), 12 tests)
│   ├── interval_tree/        🔒 区间树 (重叠查询, 10 tests)
│   ├── range_tree/           🔒 范围树 (2D 正交范围查询, 8 tests)
│   ├── r_tree/               🔒 R-Tree (空间索引, 10 tests)
│   └── fibonacci_heap/       🔒 Fibonacci 堆 (O(1) decrease-key, 12 tests)
├── graph/
│   ├── chu_liu/              🔒 Chu-Liu 最小树形图 (Edmonds, 8 tests)
│   ├── k_shortest_paths/     🔒 K 最短路 (Yen 算法, 8 tests)
│   ├── min_cost_flow/        🔒 最小费用流 (SSP+SPFA, 9 tests)
│   └── tree_isomorphism/     🔒 树同构 (AHU 算法, 7 tests)
│   ├── push_relabel/       🔒 Push-Relabel 最大流 (5 tests)
│   ├── planar_test/        🔒 平面图判定 (5 tests)
│   └── isomorphism/        🔒 图同构 (VF2 算法, 5 tests)
├── string/
│   ├── dawg/                 🔒 DAWG (压缩字典, 10 tests)
│   ├── sa_is/                🔒 SA-IS 后缀数组 (O(n), 17 tests)
│   ├── bwt/                  🔒 Burrows-Wheeler 变换 (15 tests)
│   └── suffix_balanced_tree/ 🔒 后缀平衡树 (归并排序, 8 tests)
│   ├── unicode_normalization/ 🔒 Unicode 规范化 (NFC/NFD/NFKC/NFKD, 6 tests)
│   └── encoding_conversion/  🔒 编码转换 (UTF-8/UTF-16/GBK, 6 tests)
├── geometry/
│   ├── segment_intersection/🔒 通用线段求交 (Bentley-Ottmann, 10 tests)
│   ├── point_in_polygon/     🔒 点在多边形内 (射线法, 8 tests)
│   ├── polygon_ops/          🔒 多边形操作 (面积/重心/裁剪, 10 tests)
│   └── bentley_ottmann/      🔒 扫描线线段求交 (8 tests)
├── dp/
│   ├── aliens_trick/         🔒 Aliens' Trick (拉格朗日松弛, 8 tests)
│   ├── knapsack_opt/         🔒 背包优化 (多重/二维/单调队列, 10 tests)
│   ├── matrix_chain/        🔒 矩阵链乘 DP (8 tests)
│   ├── monotone_queue_dp/   🔒 单调队列优化 DP (8 tests)
│   └── smawk/               🔒 SMAWK 算法 (完全单调矩阵行最小, 10 tests)
│   ├── bitmask_dp/        🔒 状压 DP (TSP/集合覆盖, 10 tests)
│   ├── convex_hull_trick/  🔒 凸壳技巧 DP (斜率优化, 8 tests)
│   ├── divide_conquer_dp/  🔒 分治 DP (8 tests)
│   ├── knuth_opt/          🔒 Knuth 优化 DP (8 tests)
│   ├── plug_dp/            🔒 插头 DP (轮廓线, 7 tests)
│   └── sos_dp/             🔒 SOS DP (子集和, 8 tests)
├── math/
│   ├── fwht/                🔒 快速 Walsh-Hadamard 变换 (7 tests)
│   ├── numerical_integration/🔒 数值积分 (梯形/Simpson/自适应/Romberg, 9 tests)
│   ├── ode_solver/          🔒 ODE 求解器 (Euler/RK4/RK45, 8 tests)
│   ├── interpolation/       🔒 插值 (Lagrange/Newton, 7 tests)
│   ├── least_squares/       🔒 最小二乘法 (线性/多项式, 8 tests)
│   ├── special_functions/   🔒 特殊函数 (Gamma/Erf/Bessel, 10 tests)
│   ├── conjugate_gradient/  🔒 共轭梯度法 (SPD 线性系统求解, 7 tests)
│   ├── gmres/               🔒 GMRES (非对称线性系统求解, 6 tests)
│   ├── lbfgs/               🔒 L-BFGS 拟牛顿优化器 (大规模优化, 9 tests)
│   ├── autodiff/            🔒 自动微分 (前向模式, 双数, 19 tests)
│   └── sparse_matrix/       🔒 稀疏矩阵 (CSR 格式, 7 tests)
│   ├── eigenvalue/          🔒 特征值分解 (Jacobi 方法, 5 tests)
│   ├── qr_pivoting/         🔒 QR 分解 (列主元, 5 tests)
│   ├── groebner/            🔒 Gröbner 基 (Buchberger 算法, 5 tests)
│   ├── polynomial_factor/   🔒 多项式因式分解 (5 tests)
│   ├── ilp/                 🔒 整数线性规划 (5 tests)
│   └── sdp/                 🔒 半正定规划 (Jacobi 特征值, 7 tests)
├── crypto/
│   ├── sha256/              🔒 SHA-256 哈希 (10 tests)
│   ├── sha512/              🔒 SHA-512 哈希 (8 tests)
│   ├── sha3/                🔒 SHA-3 (Keccak) 哈希 (8 tests)
│   ├── sha1/                🔒 SHA-1 哈希 (10 tests)
│   ├── blake2/              🔒 BLAKE2 哈希 (8 tests)
│   ├── blake3/              🔒 BLAKE3 哈希 (8 tests)
│   ├── hmac/                🔒 HMAC 消息认证 (7 tests)
│   ├── chacha20/            🔒 ChaCha20 流密码 (8 tests)
│   ├── chacha20_poly1305/   🔒 ChaCha20-Poly1305 AEAD (7 tests)
│   ├── xchacha20/           🔒 XChaCha20 (HChaCha20 + ChaCha20, 8 tests)
│   ├── poly1305/            🔒 Poly1305 MAC (7 tests)
│   ├── hkdf/                🔒 HKDF 密钥派生 (7 tests)
│   ├── pbkdf2/              🔒 PBKDF2 密码派生 (6 tests)
│   ├── scrypt/              🔒 scrypt 密码哈希 (6 tests)
│   ├── bcrypt/              🔒 bcrypt 密码哈希 (8 tests)
│   ├── argon2/              🔒 Argon2 密码哈希 (6 tests)
│   ├── aes/                 🔒 AES 对称加密 (constant-time S-box, 8 tests)
│   ├── aes_ccm/             🔒 AES-CCM AEAD (7 tests)
│   ├── rsa/                 🔒 RSA 非对称加密 (OAEP/PSS, 7 tests)
│   ├── ecdsa/               🔒 ECDSA P-256 (RFC 6979, 13 tests)
│   ├── ed25519/             🔒 Ed25519 签名 (RFC 8032, 13 tests)
│   ├── x25519/              🔒 X25519 密钥交换 (RFC 7748, 8 tests)
│   ├── secp256k1/           🔒 secp256k1 (Bitcoin/Ethereum, 10 tests)
│   ├── csprng/              🔒 CSPRNG 安全随机数 (6 tests)
│   ├── base64/              🔒 Base64 编码 (7 tests)
│   ├── base32/              🔒 Base32 编码 (9 tests)
│   └── hex/                 🔒 Hex 编解码 (14 tests)
├── compression/
│   ├── huffman/             🔒 Huffman 编码 (8 tests)
│   ├── lz4/                 🔒 LZ4 压缩 (7 tests)
│   ├── lz77/                🔒 LZ77 压缩 (7 tests)
│   ├── lzw/                 🔒 LZW 压缩 (7 tests)
│   ├── arithmetic_coding/   🔒 算术编码 (7 tests)
│   ├── bwt_compress/        🔒 BWT 压缩 (6 tests)
│   ├── deflate/             🔒 DEFLATE 压缩 (RFC 1951, 8 tests)
│   ├── gzip/                🔒 gzip 容器 (RFC 1952, 7 tests)
│   ├── zlib/                🔒 zlib 容器 (RFC 1950, 7 tests)
│   ├── snappy/              🔒 Snappy 压缩 (7 tests)
│   ├── zstd/                🔒 Zstandard 压缩 (6 tests)
│   └── brotli/              🔒 Brotli 压缩 (7 tests)
├── ml/
│   ├── kmeans/              🔒 K-Means++ 聚类 (8 tests)
│   ├── knn/                 🔒 K-近邻 (KD-Tree 加速, 8 tests)
│   ├── dbscan/              🔒 DBSCAN 密度聚类 (7 tests)
│   ├── pca/                 🔒 主成分分析 PCA (8 tests)
│   ├── svm/                 🔒 支持向量机 SVM (8 tests)
│   ├── logistic_regression/ 🔒 逻辑回归 (8 tests)
│   ├── decision_tree/       🔒 决策树 CART (8 tests)
│   ├── random_forest/       🔒 随机森林 (分类+回归+OOB, 8 tests)
│   ├── gradient_boosting/   🔒 梯度提升 (GBDT, 7 tests)
│   ├── adaboost/            🔒 AdaBoost (6 tests)
│   ├── mlp/                 🔒 多层感知机 MLP (8 tests)
│   ├── gmm/                 🔒 高斯混合模型 GMM (EM, 7 tests)
│   ├── hierarchical_clustering/ 🔒 层次聚类 (7 tests)
│   ├── gaussian_process/    🔒 高斯过程回归 (6 tests)
│   ├── naive_bayes/         🔒 朴素贝叶斯 (8 tests)
│   └── model_evaluation/    🔒 模型评估 (accuracy/precision/recall/F1/AUC, 10 tests)
├── stats/
│   ├── descriptive/         🔒 描述统计 (9 tests)
│   ├── linear_regression/   🔒 线性回归 (8 tests)
│   ├── hypothesis_testing/  🔒 假设检验 (8 tests)
│   ├── correlation/         🔒 相关系数 (Pearson/Spearman, 7 tests)
│   ├── confidence_interval/ 🔒 置信区间 (7 tests)
│   ├── bootstrap/           🔒 Bootstrap 重采样 (7 tests)
│   ├── distributions/       🔒 概率分布 (Normal/Exp/Binomial/Poisson/Beta/t/Chi2/F/Gamma, 38 tests)
│   ├── anova/               🔒 方差分析 ANOVA (8 tests)
│   └── nonparametric/       🔒 非参数检验 (Mann-Whitney/Wilcoxon/Kruskal-Wallis, 8 tests)
├── serialization/
│   ├── json/                🔒 JSON 编解码 (7 tests)
│   ├── msgpack/             🔒 MessagePack 编解码 (7 tests)
│   ├── csv/                 🔒 CSV 编解码 (6 tests)
│   ├── toml/                🔒 TOML 1.0.0 解析器 (15 tests)
│   ├── yaml/                🔒 YAML 解析器 (8 tests)
│   ├── cbor/                🔒 CBOR 编解码 (7 tests)
│   └── protobuf/            🔒 Protobuf 编解码 (6 tests)
├── time/
│   └── chrono/              🔒 日期时间库 (ISO 8601, Duration, 时区, 15 tests)
├── utils/
│   ├── (utils)              🔒 共享工具 (swap/str_cmp/next_pow2/encoding/approx_eq)
│   ├── prng/                🔒 PRNG (SplitMix64/XorShift64/LCG)
│   ├── itertools/           🔒 itertools (range/repeat/enumerate/window/chunk/fold)
│   ├── structured_logging/  🔒 结构化日志 (6 tests)
│   └── error_chain/         🔒 错误链 (5 tests)
├── test/
│   ├── property_test/       🔒 QuickCheck 风格属性测试框架 (随机输入生成 + 反例缩减)
│   ├── fuzz/                🔒 Fuzz 测试 + 对抗性输入测试
│   ├── stress/              🔒 压力测试 (排序置换验证, LIS 子序列验证)
│   ├── test_utils/          🔒 共享测试工具 (消除 str_cmp 重复)
│   └── coverage/            🔒 测试覆盖率报告
├── finance/
│   ├── black_scholes/       🔒 Black-Scholes 期权定价 (11 tests)
│   ├── portfolio_optimization/ 🔒 投资组合优化 (Markowitz/Black-Litterman, 8 tests)
│   ├── risk_management/     🔒 风险管理 (VaR/CVaR/压力测试, 8 tests)
│   ├── greeks/              🔒 Greeks 风险敏感度 (Delta/Gamma/Vega/Theta/Rho, 9 tests)
│   ├── time_series/         🔒 时间序列分析 (ARIMA/GARCH/ADF, 12 tests)
│   ├── execution/           🔒 执行算法 (TWAP/VWAP/Implementation Shortfall, 8 tests)
│   └── backtest/            🔒 回测框架 (事件驱动/绩效分析, 9 tests)
├── docs/
│   └── API_STABILITY.md     📋 API 稳定性策略与版本历史
├── benchmarks/              🔒 性能基准测试 (wall-clock + 复杂度验证)
├── .github/workflows/
│   ├── ci.yml                ✅ GitHub Actions CI (check + test + prove, Ubuntu/macOS/Windows)
│   ├── codeql.yml            ✅ CodeQL 安全分析
│   ├── dependency-review.yml ✅ 依赖审查
│   ├── nightly.yml           ✅ 每日构建 (flaky test 检测)
│   └── release.yml           ✅ 发布流程 (checksums + tag)
├── CHANGELOG.md              📋 Semantic Versioning changelog
├── moon.mod
├── LICENSE
└── README.md
```

图例：✅ = 完整正确性验证 | 🔶 = 增强验证 | ⚠️ = 部分验证 | 🔒 = 仅测试验证

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
| insertion_sort | 12 | ⚠️ 部分验证 | ✅ generic |
| selection_sort | 10 | 🔒 tested | ✅ generic |
| merge_sort | 15 | ⚠️ 部分验证 | ✅ generic |
| quick_sort | 15 | 🔒 tested | ✅ generic |
| heap_sort | 12 | 🔒 tested | ✅ generic |
| counting_sort | 12 | 🔒 tested | ❌ |
| radix_sort | 11 | 🔒 tested | ❌ |
| is_sorted | 10 | ✅ 完整正确性 | ✅ generic |
| binary_heap | 17 | ⚠️ 部分验证 | ✅ HeapG[T] |
| hash_table | 19 | 🔒 tested | ✅ HashTable[K,V] |
| lru_cache | 8 | 🔒 tested | ❌ |
| bloom_filter | 9 | 🔒 tested | ❌ |
| union_find | 16 | ⚠️ 部分验证 | ❌ (pub struct) |
| bst | 19 | 🔒 tested | ❌ |
| avl | 17 | 🔒 tested | ❌ |
| red_black_tree | 23 | ⚠️ 部分验证 | ✅ generic |
| btree | 16 | 🔒 tested | ❌ |
| segment_tree | 19 | 🔒 tested | ❌ |
| fenwick | 14 | 🔒 tested | ❌ |
| trie | 17 | 🔒 tested | ✅ String |
| skip_list | 13 | 🔒 tested | ❌ |
| treap | 13 | 🔒 tested | ❌ |
| bfs_dfs | 34 | 🔒 tested | ❌ |
| adj_list | 23 | 🔒 tested | ❌ |
| topological_sort | 12 | ⚠️ 部分验证 | ❌ |
| topological_sort_adj | 16 | 🔒 tested | ❌ |
| kruskal | 14 | ⚠️ 部分验证 | ❌ |
| prim | 11 | 🔒 tested | ❌ |
| scc | 12 | 🔒 tested | ❌ |
| dijkstra | 11 | ⚠️ 部分验证 | ❌ |
| dijkstra_heap | 11 | 🔒 tested | ❌ |
| johnson | 11 | 🔒 tested | ❌ |
| bidirectional_bfs | 13 | 🔒 tested | ❌ |
| a_star | 11 | 🔒 tested | ❌ |
| max_flow | 12 | 🔒 tested | ❌ |
| advanced | 19 | 🔒 tested | ❌ |
| kmp | 17 | ⚠️ 部分验证 | ❌ |
| rabin_karp | 25 | 🔒 tested | ❌ |
| suffix_array | 15 | 🔒 tested | ❌ |
| z_function | 19 | 🔒 tested | ❌ |
| manacher | 23 | 🔒 tested | ❌ |
| gcd | 8 | 🔶 增强验证 | ❌ |
| fast_power | 12 | 🔶 增强验证 | ❌ |
| prime | 18 | 🔒 tested | ❌ |
| miller_rabin | 11 | 🔒 tested | ❌ |
| crt | 20 | 🔒 tested | ❌ |
| array_sum | 7 | 🔶 增强验证 | ❌ |
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
| euler_sieve | 11 | 🔒 tested | ❌ |
| sparse_table | 13 | 🔒 tested | ✅ generic |
| lca | 11 | 🔒 tested | ❌ |
| dinic | 8 | 🔒 tested | ❌ |
| closest_pair | 9 | 🔒 tested | ❌ |
| segment_ops | 33 | 🔒 tested | ❌ |
| combinatorics | 15 | ⚠️ 部分验证 | ❌ |
| matrix | 12 | ⚠️ 部分验证 | ❌ |
| priority_queue | 15 | 🔒 tested | ✅ HeapG[T] |
| monotonic | 21 | 🔒 tested | ❌ |
| interval_dp | 22 | 🔒 tested | ❌ |
| tree_dp | 19 | 🔒 tested | ❌ |
| bridge_articulation | 15 | 🔒 tested | ❌ |
| euler_path | 14 | 🔒 tested | ❌ |
| hungarian | 10 | 🔒 tested | ❌ |
| ntt | 11 | 🔒 tested | ❌ |
| boyer_moore | 14 | 🔒 tested | ❌ |
| lcp_array | 13 | 🔒 tested | ❌ |
| suffix_automaton | 12 | 🔒 tested | ❌ |
| segment_tree_lazy | 9 | 🔒 tested | ❌ |
| suffix_tree | 12 | 🔒 tested | ❌ |
| palindromic_tree | 11 | 🔒 tested | ❌ |
| rolling_hash | 12 | 🔒 tested | ❌ |
| lyndon | 13 | 🔒 tested | ❌ |
| link_cut | 12 | 🔒 tested | ❌ |
| persistent_vector | 9 | 🔒 tested | ❌ |
| hopcroft_karp | 9 | 🔒 tested | ❌ |
| stoer_wagner | 10 | 🔒 tested | ❌ |
| max_clique | 12 | 🔒 tested | ❌ |
| convex_hull_3d | 12 | 🔒 tested | ❌ |
| half_plane_intersection | 9 | 🔒 tested | ❌ |
| matrix_decomp | 16 | 🔒 tested | ❌ |
| newton_method | 23 | 🔒 tested | ❌ |
| berlekamp_massey | 10 | 🔒 tested | ❌ |
| fft | 11 | 🔒 tested | ❌ |
| simplex | 10 | 🔒 tested | ❌ |
| digit_dp | 11 | 🔒 tested | ❌ |
| w_tinylfu | 11 | 🔒 tested | ❌ |
| ttl_cache | 10 | 🔒 tested | ❌ |
| cuckoo_filter | 8 | 🔒 tested | ❌ |
| count_min_sketch | 10 | 🔒 tested | ❌ |
| hyperloglog | 10 | 🔒 tested | ❌ |
| nim_sg | 13 | 🔒 tested | ❌ |
| reservoir_sampling | 8 | 🔒 tested | ❌ |
| int64_utils | 21 | 🔒 tested | ❌ |
| **Total** | **6432** | **17 包通过 moon prove（5 完整, 3 增强, 9 部分）, 其余仅测试验证** | **17 generic** |

> 注：上表仅列出部分代表性包。完整 337 个包的测试统计请运行 `moon test` 查看。

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
