# Moon Certified

用 [MoonBit](https://www.moonbitlang.com) 0.9 的 `moon prove` 形式化验证系统，构建经过数学证明的核心算法与数据结构库。

## 为什么需要这个项目

MoonBit 0.9 引入了 first-class formal verification 能力，`moon prove` 成为与 `moon build`、`moon test` 并列的工具链内置命令。它通过 Why3 + Z3 SMT 求解器，对代码进行全输入覆盖的正确性证明——不是测试某几组输入碰巧返回正确结果，而是一个覆盖所有可能输入的数学证明。

但目前 MoonBit 生态中，`moonbit-community/verified` 仅包含 12 个教程级示例（v0.0.2）。本项目的目标是构建生产级验证库，覆盖排序、搜索、数据结构、图算法等核心领域。

## 项目状态

**v0.4.0** — 43 个算法包，601 个测试全部通过，`moon prove` 9/9 包验证通过 (0 失败)。

### v0.4.0 变更亮点

- **新增 10 个算法包**：LRU Cache、Bloom Filter、B-Tree、A* 搜索、Edmonds-Karp 最大流、堆优化 Dijkstra (稀疏图)、LIS (O(n log n))、Graham 凸包、后缀数组、邻接表
- **压力测试**：新增 `test/stress` 包，12 个大规模测试覆盖 10³–10⁴ 量级输入，验证排序、红黑树、B-Tree、并查集、Dijkstra、Bloom Filter、LRU Cache、最大流、LIS、后缀数组、凸包的大规模正确性
- **公共 API 修复**：`red_black_tree.is_valid_rb` 声明为 `pub`，`convex_hull` 新增 `point()` 构造器，支持跨包调用
- **堆优化 Dijkstra**：O((V+E)log V)，邻接表表示，惰性删除优先队列，适用于稀疏图
- **Edmonds-Karp 最大流**：BFS 增广路，O(VE²) 保证，不修改原始容量矩阵

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
- `proof_axiomatized` 引理 `graph_index_bound`（dijkstra 中使用）是一个数学上正确但被假设而非证明的非线性算术事实
- 所有"部分验证"的包都通过详尽的测试套件验证正确性，包括边界情况和随机输入

### 溢出说明

形式化验证将 `Int` 建模为数学整数，但运行时 `Int` 是 32 位有符号整数。以下函数在结果超出 2³¹−1 时会发生静默溢出：

| 函数 | 溢出行为 | 安全替代 |
|------|---------|---------|
| `fast_power` | 结果可能变为负数 | `fast_power_checked`（返回 `Int?`） |
| `gcd` | 输入安全（已取绝对值） | — |
| `array_sum` | 大数组求和可能溢出 | 调用者需确保和不溢出 |
| `sieve` | n > 10⁹ 时返回空数组 | 已添加保护 |

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

# 运行测试 (489 tests)
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
2. **proof_axiomatized 引理**：对 Z3 无法自动证明的非线性算术事实，声明为公理引理（仅 dijkstra 的 `graph_index_bound`，数学上正确但被假设）
3. **分治验证**：将可验证部分（边界、终止性）与不可验证部分（量化不变量保持）分离
4. **输入校验**：所有可失败操作均做输入校验，使用 `Option`/`SPResult` 而非魔术值
5. **comparator 参数化**：binary_heap 的 sift 操作通过 `should_swap` 函数参数统一了 min-heap 和 max-heap 实现
6. **已验证 + 泛型双层架构**：搜索包保留已验证 Int 版本作为正确性参考，泛型版本扩展到任意类型

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
│   ├── binary_search/      ✅ 二分查找 (verified) + generic
│   ├── bound_search/       🔒 lower_bound/upper_bound (generic)
│   ├── linear_search/      ✅ 线性查找 (verified) + generic
│   ├── max_element/        ✅ 最大元素 (verified) + generic
│   └── min_element/        ✅ 最小元素 (verified) + generic
├── sorting/
│   ├── insertion_sort/     🔒 插入排序 (generic, 12 tests)
│   ├── selection_sort/     🔒 选择排序 (generic, 11 tests)
│   ├── merge_sort/         🔒 归并排序 (generic, 14 tests)
│   ├── quick_sort/         🔒 快速排序 (generic, 15 tests)
│   └── is_sorted/          ✅ 有序性检查 (verified) + generic
├── containers/
│   ├── binary_heap/        🔒 二叉堆 (Heap 封装, 16 tests)
│   ├── hash_table/         🔒 哈希表 K,V 泛型 (StringHashTable 封装, 19 tests)
│   └── union_find/         🔒 并查集 (pub struct, find→Int?, 16 tests)
├── trees/
│   ├── bst/                🔒 二叉搜索树 (19 tests)
│   ├── avl/                🔒 AVL 平衡树 (17 tests)
│   ├── red_black_tree/     🔒 红黑树 Okasaki+Kahrs (generic, 22 tests)
│   ├── segment_tree/       🔒 线段树 (12 tests)
│   ├── fenwick/            🔒 树状数组 (14 tests)
│   └── trie/               🔒 字典树 (size/enumerate/longest_prefix, 17 tests)
├── graph/
│   ├── bfs_dfs/            🔒 BFS/DFS 邻接矩阵版 (Option 返回, 36 tests)
│   ├── adj_list/           🔒 邻接表稀疏图 (O(V+E) 空间, 23 tests)
│   ├── topological_sort/   🔒 拓扑排序 (Option 返回, 13 tests)
│   ├── kruskal/            🔒 最小生成树 (14 tests)
│   ├── prim/               🔒 Prim MST (11 tests)
│   ├── scc/                🔒 Tarjan SCC (12 tests)
│   ├── dijkstra/           ⚠️ Dijkstra (partial verified, FixedArray[Int?])
│   └── advanced/           🔒 Bellman-Ford + Floyd-Warshall (SPResult, 20 tests)
├── string/
│   ├── kmp/                🔒 KMP (17 tests)
│   └── rabin_karp/         🔒 Rabin-Karp (25 tests)
├── number_theory/
│   ├── gcd/                ⚠️ GCD (partial verified, handles negatives)
│   ├── fast_power/         ⚠️ 快速幂 (partial verified + checked variant)
│   └── prime/              🔒 素数筛 + 扩展欧几里得 (mod_inverse→Int?)
├── math/
│   └── array_sum/          ⚠️ 数组求和 (partial verified)
├── dp/
│   └── dp/                 🔒 LCS + 编辑距离 + 背包 (20 tests)
├── .github/workflows/
│   └── ci.yml              ✅ GitHub Actions CI (check + test + prove)
├── moon.mod.json
├── LICENSE
└── README.md
```

图例：✅ = 完整正确性验证 | ⚠️ = 部分验证 | 🔒 = 仅测试验证

## 测试统计

| 包 | 测试数 | moon prove | 泛型 |
|---|--------|------------|------|
| binary_search | 8 | ✅ 完整正确性 | ✅ generic |
| bound_search | 8 | 🔒 tested | ✅ generic |
| linear_search | 9 | ✅ 完整正确性 | ✅ generic |
| max_element | 7 | ✅ 完整正确性 | ✅ generic |
| min_element | 7 | ✅ 完整正确性 | ✅ generic |
| insertion_sort | 12 | 🔒 tested | ✅ generic |
| selection_sort | 11 | 🔒 tested | ✅ generic |
| merge_sort | 14 | 🔒 tested | ✅ generic |
| quick_sort | 15 | 🔒 tested | ✅ generic |
| is_sorted | 9 | ✅ 完整正确性 | ✅ generic |
| binary_heap | 16 | 🔒 tested | ✅ Heap 封装 |
| hash_table | 19 | 🔒 tested | ✅ HashTable[K,V] |
| union_find | 16 | 🔒 tested | ❌ (pub struct) |
| bst | 19 | 🔒 tested | ❌ |
| avl | 17 | 🔒 tested | ❌ |
| red_black_tree | 22 | 🔒 tested | ✅ generic |
| segment_tree | 12 | 🔒 tested | ❌ |
| fenwick | 14 | 🔒 tested | ❌ |
| trie | 17 | 🔒 tested | ✅ String |
| bfs_dfs | 36 | 🔒 tested | ❌ |
| topological_sort | 13 | 🔒 tested | ❌ |
| kruskal | 14 | 🔒 tested | ❌ |
| prim | 11 | 🔒 tested | ❌ |
| scc | 12 | 🔒 tested | ❌ |
| advanced | 20 | 🔒 tested | ❌ |
| adj_list | 23 | 🔒 tested | ❌ |
| dijkstra | 9 | ⚠️ 部分验证 | ❌ |
| kmp | 17 | 🔒 tested | ❌ |
| rabin_karp | 25 | 🔒 tested | ❌ |
| gcd | 6 | ⚠️ 部分验证 | ❌ |
| fast_power | 9 | ⚠️ 部分验证 | ❌ |
| prime | 18 | 🔒 tested | ❌ |
| array_sum | 7 | ⚠️ 部分验证 | ❌ |
| dp | 20 | 🔒 tested | ❌ |
| **Total** | **489** | **5 完整, 4 部分, 25 tested** | **16 generic** |

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
