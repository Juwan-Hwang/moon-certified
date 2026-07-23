# Moon Certified

用 [MoonBit](https://www.moonbitlang.com) 0.9 的 `moon prove` 形式化验证系统，构建经过数学证明的核心算法与数据结构库。

## 为什么需要这个项目

MoonBit 0.9 引入了 first-class formal verification 能力，`moon prove` 成为与 `moon build`、`moon test` 并列的工具链内置命令。它通过 Why3 + Z3 SMT 求解器，对代码进行全输入覆盖的正确性证明——不是测试某几组输入碰巧返回正确结果，而是一个覆盖所有可能输入的数学证明。

但目前 MoonBit 生态中，`moonbit-community/verified` 仅包含 12 个教程级示例（v0.0.2）。本项目的目标是构建生产级验证库，覆盖排序、搜索、数据结构、图算法等核心领域。

## 项目状态

**v0.2.1** — 34 个算法包，464 个测试全部通过，`moon prove` 9/9 包验证通过 (0 失败)。

### v0.2.1 变更亮点

- **邻接表图表示**：新增 `adj_list` 包，提供 O(V+E) 空间复杂度的稀疏图支持，含 BFS/DFS/has_path
- **KMP 语义统一**：`kmp_search` 返回 `Int?`，空 pattern 和未找到统一返回 `None`
- **BST/AVL 安全性**：消除 `unwrap_or(0)`，改用 `abort` 处理不可能分支
- **验证规约加强**：GCD 添加整除性公理引理，fast_power 添加下界引理，array_sum 添加完整正确性引理

### v0.2.0 变更亮点

- **全库泛型化**：排序包（insertion_sort, selection_sort, merge_sort, quick_sort）全面转为 `FixedArray[T]` + 比较器模式，支持任意可比类型
- **泛型搜索包**：已验证的 Int 版本保留，新增泛型伴随函数 `search_generic` / `max_element_generic` / `min_element_generic` / `is_sorted_generic`
- **类型安全错误处理**：消除全部魔术值，使用 `SPResult` 枚举和 `Option` 类型替代 `-1`/空数组等歧义返回值
- **红黑树**：使用 Okasaki 函数式插入算法重写，14 个测试全部通过
- **新增 8 个包**：rabin_karp, hash_table, prim, scc, fenwick, trie, bound_search, red_black_tree
- **MoonBit String 短词典序发现**：发现 MoonBit 的 `String` `Compare` trait 使用短词典序（先比长度），实现了正确的逐字节字典序比较器

## 验证状态

### 形式化验证通过 (moon prove ✅)

| 包 | 验证内容 |
|---|---------|
| binary_search | 找到则返回正确索引，未找到返回 None |
| linear_search | 返回正确索引或 None |
| max_element | 返回的索引指向最大元素 |
| min_element | 返回的索引指向最小元素 |
| is_sorted | 返回 true 时数组有序；返回 false 时存在逆序对 |
| array_sum | 数组求和结果非负 |
| gcd | GCD 结果非负 |
| fast_power | 快速幂结果非负 |
| dijkstra | 数组边界 + 结果长度 (含 proof_axiomatized 非线性引理) |

**验证深度说明**：
- binary_search、linear_search、max_element、min_element、is_sorted 验证了算法的核心正确性
- array_sum 验证了结果非负性 + 完整正确性公理引理
- gcd 验证了结果非负性 + 整除性公理引理
- fast_power 验证了结果非负性 + 下界公理引理
- dijkstra 验证了数组边界安全性，使用 `proof_axiomatized` 引理处理 Z3 无法自动证明的非线性算术

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
| red_black_tree | ✅ `RBNode[T]` + cmp | Okasaki 函数式插入 |
| binary_heap | ✅ comparator 参数 | min-heap/max-heap 通过 should_swap 统一 |

比较器约定：`cmp(a, b)` 返回负数表示 `a < b`，0 表示相等，正数表示 `a > b`。

### 类型安全错误处理

| 包 | 旧返回值 | 新返回值 | 说明 |
|---|---------|---------|------|
| bellman_ford | 空数组/`-1` | `SPResult?` | `None`=无效输入, `NegativeCycle`=负环, `Distances(FixedArray[Int?])`=距离 |
| floyd_warshall | 空数组/`-1` | `SPResult?` | 同上，`Distances` 包含 n*n 矩阵 |
| topological_sort | 空数组 | `FixedArray[Int]?` | `None`=环或无效输入 |
| shortest_path | `-1` | `Int?` | `None`=不可达或无效 |
| bfs_distances | 空数组 | `FixedArray[Int]?` | `None`=无效输入，`-1` 保留为不可达标记（BFS 跳数 ≥ 0） |

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

# 运行测试 (438 tests)
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

  // Red-Black Tree (Okasaki insertion)
  let tree : @red_black_tree.RBNode[String] = @red_black_tree.empty()
  let tree = @red_black_tree.insert(tree, "hello", str_cmp)
  println(@red_black_tree.search(tree, "hello", str_cmp)) // true

  // KMP string matching
  let pos = @kmp.kmp_search("hello world", "world")
  println(pos) // Some(6)

  // Fenwick Tree (Binary Indexed Tree)
  let ft = @fenwick.new(10)
  @fenwick.update(ft, 3, 5)
  println(@fenwick.query(ft, 3)) // 5

  // Hash Table
  let ht = @hash_table.new(16)
  @hash_table.insert(ht, "key", 42)
  println(@hash_table.get(ht, "key")) // Some(42)

  // Topological Sort (returns Option)
  let dag = FixedArray::make(9, 0)
  dag[0 * 3 + 1] = 1; dag[1 * 3 + 2] = 1
  match @topological_sort.topo_sort(dag, 3) {
    Some(order) => println(order) // [0, 1, 2]
    None => println("cycle detected")
  }
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
2. **proof_axiomatized 引理**：对 Z3 无法自动证明的非线性算术事实，声明为公理引理
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
│   ├── binary_heap/        🔒 二叉堆 (comparator, 13 tests)
│   ├── hash_table/         🔒 哈希表 K,V 泛型 (15 tests)
│   └── union_find/         🔒 并查集 (16 tests)
├── trees/
│   ├── bst/                🔒 二叉搜索树 (19 tests)
│   ├── avl/                🔒 AVL 平衡树 (17 tests)
│   ├── red_black_tree/     🔒 红黑树 Okasaki (generic, 14 tests)
│   ├── segment_tree/       🔒 线段树 (12 tests)
│   ├── fenwick/            🔒 树状数组 (14 tests)
│   └── trie/               🔒 字典树 (12 tests)
├── graph/
│   ├── bfs_dfs/            🔒 BFS/DFS 邻接矩阵版 (Option 返回, 36 tests)
│   ├── adj_list/           🔒 邻接表稀疏图 (O(V+E) 空间, 23 tests)
│   ├── topological_sort/   🔒 拓扑排序 (Option 返回, 13 tests)
│   ├── kruskal/            🔒 最小生成树 (14 tests)
│   ├── prim/               🔒 Prim MST (11 tests)
│   ├── scc/                🔒 Tarjan SCC (12 tests)
│   ├── dijkstra/           ✅ Dijkstra (verified, Option 返回)
│   └── advanced/           🔒 Bellman-Ford + Floyd-Warshall (SPResult, 20 tests)
├── string/
│   ├── kmp/                🔒 KMP (17 tests)
│   └── rabin_karp/         🔒 Rabin-Karp (25 tests)
├── number_theory/
│   ├── gcd/                ✅ GCD (verified)
│   ├── fast_power/         ✅ 快速幂 (verified)
│   └── prime/              🔒 素数筛 + 扩展欧几里得 (18 tests)
├── math/
│   └── array_sum/          ✅ 数组求和 (verified)
├── dp/
│   └── dp/                 🔒 LCS + 编辑距离 + 背包 (20 tests)
├── .github/workflows/
│   └── ci.yml              ✅ GitHub Actions CI (check + test + prove)
├── moon.mod.json
├── LICENSE
└── README.md
```

图例：✅ = moon prove 验证通过 | 🔒 = 仅测试验证

## 测试统计

| 包 | 测试数 | moon prove | 泛型 |
|---|--------|------------|------|
| binary_search | 8 | ✅ verified | ✅ generic |
| bound_search | 8 | 🔒 tested | ✅ generic |
| linear_search | 9 | ✅ verified | ✅ generic |
| max_element | 7 | ✅ verified | ✅ generic |
| min_element | 7 | ✅ verified | ✅ generic |
| insertion_sort | 12 | 🔒 tested | ✅ generic |
| selection_sort | 11 | 🔒 tested | ✅ generic |
| merge_sort | 14 | 🔒 tested | ✅ generic |
| quick_sort | 15 | 🔒 tested | ✅ generic |
| is_sorted | 9 | ✅ verified | ✅ generic |
| binary_heap | 13 | 🔒 tested | ✅ comparator |
| hash_table | 15 | 🔒 tested | ✅ K,V |
| union_find | 16 | 🔒 tested | ❌ |
| bst | 19 | 🔒 tested | ❌ |
| avl | 17 | 🔒 tested | ❌ |
| red_black_tree | 14 | 🔒 tested | ✅ generic |
| segment_tree | 12 | 🔒 tested | ❌ |
| fenwick | 14 | 🔒 tested | ❌ |
| trie | 12 | 🔒 tested | ✅ generic |
| bfs_dfs | 36 | 🔒 tested | ❌ |
| topological_sort | 13 | 🔒 tested | ❌ |
| kruskal | 14 | 🔒 tested | ❌ |
| prim | 11 | 🔒 tested | ❌ |
| scc | 12 | 🔒 tested | ❌ |
| advanced | 20 | 🔒 tested | ❌ |
| adj_list | 23 | 🔒 tested | ❌ |
| dijkstra | 9 | ✅ verified | ❌ |
| kmp | 17 | 🔒 tested | ❌ |
| rabin_karp | 25 | 🔒 tested | ❌ |
| gcd | 5 | ✅ verified | ❌ |
| fast_power | 5 | ✅ verified | ❌ |
| prime | 18 | 🔒 tested | ❌ |
| array_sum | 6 | ✅ verified | ❌ |
| dp | 20 | 🔒 tested | ❌ |
| **Total** | **464** | **9 verified, 25 tested** | **16 generic** |

## 参考资源

- [MoonBit 形式化验证文档](https://docs.moonbitlang.com/en/latest/language/verification.html)
- [moonbit-community/verified](https://github.com/moonbit-community/verified) — 官方教程级验证示例
- [MoonBit 0.9 发布博客](https://www.moonbitlang.com/blog/moonbit-0-9-release)
- [Why3 文档](https://www.why3.org/) — Why3 验证平台
- [Z3 SMT Solver](https://github.com/Z3Prover/z3) — SMT 求解器
- [Okasaki, "Red-Black Trees in a Functional Setting"](https://www.cs.cmu.edu/~rwh/theses/okasaki.pdf) — 红黑树函数式插入算法

## 许可证

Apache-2.0
