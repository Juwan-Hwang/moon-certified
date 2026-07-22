# Moon Certified

用 [MoonBit](https://www.moonbitlang.com) 0.9 的 `moon prove` 形式化验证系统，构建经过数学证明的核心算法与数据结构库。

## 为什么需要这个项目

MoonBit 0.9 引入了 first-class formal verification 能力，`moon prove` 成为与 `moon build`、`moon test` 并列的工具链内置命令。它通过 Why3 + Z3 SMT 求解器，对代码进行全输入覆盖的正确性证明——不是测试某几组输入碰巧返回正确结果，而是一个覆盖所有可能输入的数学证明。

但目前 MoonBit 生态中，`moonbit-community/verified` 仅包含 12 个教程级示例（v0.0.2）。本项目的目标是构建生产级验证库，覆盖排序、搜索、数据结构、图算法等核心领域。

## 项目状态

**v0.1.0** — 19 个算法包，201 个测试全部通过，`moon prove` 9/9 包验证通过 (0 失败)。

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
- array_sum、gcd、fast_power 验证了结果非负性（非完整正确性证明）
- dijkstra 验证了数组边界安全性，使用 `proof_axiomatized` 引理处理 Z3 无法自动证明的非线性算术
- 所有 proof 合约均通过 `moon prove`，0 超时，0 失败

### 测试验证 (201 tests ✅)

| 包 | 测试数 | 说明 |
|---|--------|------|
| insertion_sort | 11 | 含置换测试 |
| selection_sort | 9 | 含置换测试 |
| merge_sort | 13 | 含置换测试 |
| quick_sort | 12 | 含置换测试 |
| binary_heap | 12 | 含输入校验、容量检查、置换测试 |
| bfs_dfs | 33 | 含输入校验、早退路径、自环 |
| kmp | 18 | 含重叠匹配、LPS 验证 |

### 新增算法包

| 包 | 测试数 | 说明 |
|---|--------|------|
| union_find | 16 | 并查集 (路径压缩 + 按秩合并) |
| topological_sort | 12 | 拓扑排序 (Kahn 算法，含环检测) |
| bst | 19 | 二叉搜索树 (插入/搜索/删除/中序遍历) |

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

# 运行测试 (200 tests)
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
  // Binary search
  let xs = FixedArray::makei(10, fn(i) { i })
  let result = @binary_search.search(xs, 5)
  println(result) // Some(5)

  // Sorting
  let arr = FixedArray::makei(5, fn(i) { 5 - i })
  @insertion_sort.insertion_sort(arr)
  println(arr) // [1, 2, 3, 4, 5]

  // KMP string matching
  let pos = @kmp.kmp_search("hello world", "world")
  println(pos) // 6

  // GCD
  let g = @gcd.gcd(12, 8)
  println(g) // 4

  // Union-Find
  let uf = @union_find.new(10)
  @union_find.union(uf, 0, 1)
  @union_find.union(uf, 2, 3)
  println(@union_find.connected(uf, 0, 1)) // true

  // Topological sort
  let n = 4
  let graph = FixedArray::make(n * n, 0)
  graph[0 * n + 1] = 1
  graph[1 * n + 2] = 1
  graph[2 * n + 3] = 1
  let order = @topological_sort.topo_sort(graph, n)
  println(order.length()) // 4

  // BST
  let tree = @bst.insert(@bst.insert(@bst.Node::Empty, 5), 3)
  println(@bst.search(tree, 5)) // true
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

本项目采用以下策略应对 MoonBit proof 系统的当前限制：

1. **for 累加器模式替代 let mut**：Dijkstra 的 find-min 循环使用 `for i = 0, best = -1; ...` 累加器模式，使 Z3 能通过循环不变量追踪变量边界
2. **proof_axiomatized 引理**：对 Z3 无法自动证明的非线性算术事实（如 `u*n+v < len` 从 `u<n, v<n, n*n<=len`），声明为 `proof_axiomatized` 引理，使验证器直接采信。引理本身是数学恒等式，Z3 无法证明是求解器限制而非正确性风险
3. **分治验证**：将可验证部分（边界、终止性）与不可验证部分（量化不变量保持）分离，前者用 proof，后者用测试
4. **输入校验**：所有可失败操作均做输入校验（`heap_push` 返回 -1 表示满，`heap_pop` 返回 None 表示空，图算法校验 src/dst 范围）

## 项目结构

```
moon-certified/
├── search/
│   ├── binary_search/      ✅ 二分查找 (verified)
│   ├── linear_search/      ✅ 线性查找 (verified)
│   ├── max_element/        ✅ 最大元素 (verified)
│   └── min_element/        ✅ 最小元素 (verified)
├── sorting/
│   ├── insertion_sort/     🔒 插入排序 (tested, 10 tests)
│   ├── selection_sort/     🔒 选择排序 (tested, 8 tests)
│   ├── merge_sort/         🔒 归并排序 (tested, 12 tests)
│   ├── quick_sort/         🔒 快速排序 (tested, 11 tests)
│   └── is_sorted/          ✅ 有序性检查 (verified)
├── containers/
│   ├── binary_heap/        🔒 二叉堆 (tested, 15 tests)
│   └── union_find/         🔒 并查集 (tested, 16 tests)
├── trees/
│   └── bst/                🔒 二叉搜索树 (tested, 19 tests)
├── graph/
│   ├── bfs_dfs/            🔒 BFS/DFS (tested, 33 tests)
│   ├── topological_sort/   🔒 拓扑排序 (tested, 12 tests)
│   └── dijkstra/           ✅ Dijkstra (verified)
├── string/
│   └── kmp/                🔒 KMP (tested, 18 tests)
├── number_theory/
│   ├── gcd/                ✅ GCD (verified)
│   └── fast_power/         ✅ 快速幂 (verified)
├── math/
│   └── array_sum/          ✅ 数组求和 (verified)
├── .github/workflows/
│   └── ci.yml              ✅ GitHub Actions CI (check + test + prove)
├── moon.mod.json
├── LICENSE
└── README.md
```

图例：✅ = moon prove 验证通过 | 🔒 = 仅测试验证

## 测试统计

| 包 | 测试数 | moon prove |
|---|--------|------------|
| binary_search | 4 | ✅ verified |
| linear_search | 4 | ✅ verified |
| max_element | 4 | ✅ verified |
| min_element | 4 | ✅ verified |
| insertion_sort | 11 | 🔒 tested |
| selection_sort | 9 | 🔒 tested |
| merge_sort | 13 | 🔒 tested |
| quick_sort | 12 | 🔒 tested |
| is_sorted | 5 | ✅ verified |
| binary_heap | 12 | 🔒 tested |
| union_find | 16 | 🔒 tested |
| bfs_dfs | 33 | 🔒 tested |
| topological_sort | 12 | 🔒 tested |
| dijkstra | 10 | ✅ verified |
| kmp | 18 | 🔒 tested |
| gcd | 5 | ✅ verified |
| fast_power | 5 | ✅ verified |
| array_sum | 6 | ✅ verified |
| bst | 19 | 🔒 tested |
| **Total** | **201** | **9 verified, 10 tested** |

## 参考资源

- [MoonBit 形式化验证文档](https://docs.moonbitlang.com/en/latest/language/verification.html)
- [moonbit-community/verified](https://github.com/moonbit-community/verified) — 官方教程级验证示例
- [MoonBit 0.9 发布博客](https://www.moonbitlang.com/blog/moonbit-0-9-release)
- [Why3 文档](https://www.why3.org/) — Why3 验证平台
- [Z3 SMT Solver](https://github.com/Z3Prover/z3) — SMT 求解器

## 许可证

Apache-2.0
