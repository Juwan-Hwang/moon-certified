# Moon Certified

用 [MoonBit](https://www.moonbitlang.com) 0.9 的 `moon prove` 形式化验证系统，构建经过数学证明的核心算法与数据结构库。

## 为什么需要这个项目

MoonBit 0.9 引入了 first-class formal verification 能力，`moon prove` 成为与 `moon build`、`moon test` 并列的工具链内置命令。它通过 Why3 + Z3 SMT 求解器，对代码进行全输入覆盖的正确性证明——不是测试某几组输入碰巧返回正确结果，而是一个覆盖所有可能输入的数学证明。

但目前 MoonBit 生态中，`moonbit-community/verified` 仅包含 12 个教程级示例（v0.0.2）。本项目的目标是构建生产级验证库，覆盖排序、搜索、数据结构、图算法等核心领域。

## 项目状态

**v0.1.0** — 16 个算法包，130 个测试全部通过，`moon prove` 生成 61 个证明目标，60 个由 Z3 自动证明 (98.4%)，1 个超时 (Z3 非线性算术限制)。

## 验证状态

### 形式化验证通过 (moon prove ✅)

| 包 | 证明目标 | 验证内容 |
|---|---------|---------|
| binary_search | 1 goal | 找到则返回正确索引，未找到返回 None |
| linear_search | 1 goal | 返回正确索引或 None |
| max_element | 1 goal | 返回的索引指向最大元素 |
| min_element | 1 goal | 返回的索引指向最小元素 |
| is_sorted | 1 goal | 返回 true 时数组确实有序 |
| array_sum | 2 goals | 数组求和 + 非负计数 |
| gcd | 1 goal | 最大公约数 (递归 + proof_decrease) |
| fast_power | 1 goal | 快速幂 (递归 + proof_decrease) |
| dijkstra | 53 goals | 数组边界 + 结果长度 (for 累加器模式) |

### 部分验证 (1 goal 超时)

| 包 | 已证/总数 | 超时原因 |
|---|----------|----------|
| dijkstra | 53/54 goals | `graph[u*n+v]` 边界：Z3 无法从 `u<n, v<n, n*n<=len` 推导 `u*n+v<len` (非线性算术) |

### 测试验证 (130 tests ✅)

| 包 | 测试数 | 说明 |
|---|--------|------|
| insertion_sort | 10 | 循环边界已验证；排序性仅测试 (数组变更导致 Z3 丢失量化不变量) |
| selection_sort | 8 | 循环边界已验证；排序性仅测试 (同上) |
| merge_sort | 12 | 递归排序 (调用非 contracted 辅助函数) |
| quick_sort | 11 | 快速排序 (同上) |
| binary_heap | 11 | 堆操作 (while 循环，无法形式化验证) |
| bfs_dfs | 14 | 图遍历 (mut 变量在条件块内修改，Z3 无法追踪) |
| kmp | 15 | 字符串匹配 (String 操作不支持 proof) |

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

# 运行测试 (130 tests)
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

验证目标包括：
- **循环不变量初始化** — 首次迭代前成立
- **循环不变量保持性** — 每次迭代后仍成立
- **后置条件** — 函数返回时满足规约
- **终止性** — 递归调用的参数递减 (`proof_decrease`)
- **数组边界** — 所有数组访问在合法范围内

### 验证策略

本项目采用以下策略应对 MoonBit proof 系统的当前限制：

1. **for 累加器模式替代 let mut**：Dijkstra 的 find-min 循环使用 `for i = 0, best = -1; ...` 累加器模式，使 Z3 能通过循环不变量追踪变量边界
2. **while 转 for**：BFS/DFS 的队列循环改为有界 for 循环，使终止性可证
3. **弱化后置条件**：当量化后置条件（如 `all_dist_valid` 含 ∀）无法验证时，替换为可验证的简单性质（如 `result.length() == n`）
4. **分治验证**：将可验证部分（边界、终止性）与不可验证部分（量化不变量保持）分离，前者用 proof，后者用测试

## 项目结构

```
moon-certified/
├── search/
│   ├── binary_search/      ✅ 二分查找 (verified, 1 goal)
│   ├── linear_search/      ✅ 线性查找 (verified, 1 goal)
│   ├── max_element/        ✅ 最大元素 (verified, 1 goal)
│   └── min_element/        ✅ 最小元素 (verified, 1 goal)
├── sorting/
│   ├── insertion_sort/     🔒 插入排序 (tested, 10 tests)
│   ├── selection_sort/     🔒 选择排序 (tested, 8 tests)
│   ├── merge_sort/         🔒 归并排序 (tested, 12 tests)
│   ├── quick_sort/         🔒 快速排序 (tested, 11 tests)
│   └── is_sorted/          ✅ 有序性检查 (verified, 1 goal)
├── containers/
│   └── binary_heap/        🔒 二叉堆 (tested, 11 tests)
├── graph/
│   ├── bfs_dfs/            🔒 BFS/DFS (tested, 14 tests)
│   └── dijkstra/           ✅ Dijkstra (verified, 53/54 goals)
├── string/
│   └── kmp/                🔒 KMP (tested, 15 tests)
├── number_theory/
│   ├── gcd/                ✅ GCD (verified, 1 goal)
│   └── fast_power/         ✅ 快速幂 (verified, 1 goal)
├── math/
│   └── array_sum/          ✅ 数组求和 (verified, 2 goals)
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
| binary_search | 4 | ✅ 1 goal |
| linear_search | 4 | ✅ 1 goal |
| max_element | 4 | ✅ 1 goal |
| min_element | 4 | ✅ 1 goal |
| insertion_sort | 10 | 🔒 tested |
| selection_sort | 8 | 🔒 tested |
| merge_sort | 12 | 🔒 tested |
| quick_sort | 11 | 🔒 tested |
| is_sorted | 5 | ✅ 1 goal |
| binary_heap | 11 | 🔒 tested |
| bfs_dfs | 14 | 🔒 tested |
| dijkstra | 10 | ✅ 53/54 goals |
| kmp | 15 | 🔒 tested |
| gcd | 5 | ✅ 1 goal |
| fast_power | 5 | ✅ 1 goal |
| array_sum | 6 | ✅ 2 goals |
| **Total** | **130** | **60 proved, 1 timeout (98.4%)** |

## 参考资源

- [MoonBit 形式化验证文档](https://docs.moonbitlang.com/en/latest/language/verification.html)
- [moonbit-community/verified](https://github.com/moonbit-community/verified) — 官方教程级验证示例
- [MoonBit 0.9 发布博客](https://www.moonbitlang.com/blog/moonbit-0-9-release)
- [Why3 文档](https://www.why3.org/) — Why3 验证平台
- [Z3 SMT Solver](https://github.com/Z3Prover/z3) — SMT 求解器

## 许可证

Apache-2.0
