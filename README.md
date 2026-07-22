# Moon Certified

用 [MoonBit](https://www.moonbitlang.com) 0.9 的 `moon prove` 形式化验证系统，构建经过数学证明的核心算法与数据结构库。

## 为什么需要这个项目

MoonBit 0.9 引入了 first-class formal verification 能力，`moon prove` 成为与 `moon build`、`moon test` 并列的工具链内置命令。它通过 Why3 + Z3 SMT 求解器，对代码进行全输入覆盖的正确性证明——不是测试某几组输入碰巧返回正确结果，而是一个覆盖所有可能输入的数学证明。

但目前 MoonBit 生态中，`moonbit-community/verified` 仅包含 12 个教程级示例（v0.0.2）。本项目的目标是构建生产级验证库，覆盖排序、搜索、数据结构、图算法等核心领域。

## 项目状态

开发中 — 已完成 13 个验证算法包，130 个测试全部通过。

## 已验证的算法

### 搜索算法 (4)
- [x] **Binary Search** — 证明找到则返回正确索引，未找到返回 None
- [x] **Linear Search** — 证明返回正确索引或 None
- [x] **Max Element** — 证明返回的索引指向最大元素
- [x] **Min Element** — 证明返回的索引指向最小元素

### 排序算法 (4)
- [x] **Insertion Sort** — 证明输出有序 (sorted_range 不变量)
- [x] **Selection Sort** — 证明输出有序 (partitioned 不变量)
- [x] **Merge Sort** — 证明输出有序 (递归分治 + merge)
- [x] **Quick Sort** — 证明输出有序 (Lomuto 分区)
- [x] **Is Sorted** — 证明返回 true 时数组确实有序

### 数据结构 (1)
- [x] **Binary Heap** — 构建堆、插入、弹出、堆排序 (sift_up/sift_down)

### 图算法 (2)
- [x] **BFS / DFS** — 广度优先/深度优先遍历，最短跳数距离
- [x] **Dijkstra** — 单源最短路径算法

### 字符串算法 (1)
- [x] **KMP** — Knuth-Morris-Pratt 字符串匹配 (build_lps + search + search_all)

### 数论算法 (2)
- [x] **GCD (Euclid)** — 最大公约数 (递归 + proof_decrease)
- [x] **Fast Power** — 快速幂 (递归 + proof_decrease)

### 数学算法 (1)
- [x] **Array Sum** — 数组求和 + 非负计数

## 使用方式

### 环境要求

- MoonBit 0.9+
- [Why3](https://why3.lri.fr/) 1.7.2 (推荐通过 opam 安装：`opam install why3.1.7.2`)
- [Z3](https://github.com/Z3Prover/z3) SMT 求解器

### 运行

```bash
# 克隆仓库
git clone https://github.com/Juwan-Hwang/moon-certified.git
cd moon-certified

# 类型检查
moon check

# 运行测试 (130 tests)
moon test

# 运行形式化验证 (需要 Why3 + Z3)
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
  @quick_sort.quick_sort(arr)
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

## 项目结构

```
moon-certified/
├── search/
│   ├── binary_search/      ✅ 二分查找
│   ├── linear_search/      ✅ 线性查找
│   ├── max_element/        ✅ 最大元素
│   └── min_element/        ✅ 最小元素
├── sorting/
│   ├── insertion_sort/     ✅ 插入排序
│   ├── selection_sort/     ✅ 选择排序
│   ├── merge_sort/         ✅ 归并排序
│   ├── quick_sort/         ✅ 快速排序
│   └── is_sorted/          ✅ 有序性检查
├── containers/
│   └── binary_heap/        ✅ 二叉堆 (push/pop/sort)
├── graph/
│   ├── bfs_dfs/            ✅ BFS/DFS 遍历
│   └── dijkstra/           ✅ Dijkstra 最短路径
├── string/
│   └── kmp/                ✅ KMP 字符串匹配
├── number_theory/
│   ├── gcd/                ✅ 最大公约数
│   └── fast_power/         ✅ 快速幂
├── math/
│   └── array_sum/          ✅ 数组求和 + 计数
├── .github/workflows/
│   └── ci.yml              ✅ GitHub Actions CI
├── moon.mod.json
├── LICENSE
└── README.md
```

## 测试统计

| 包 | 测试数 |
|---|--------|
| binary_search | 4 |
| linear_search | 4 |
| max_element | 4 |
| min_element | 4 |
| insertion_sort | 10 |
| selection_sort | 8 |
| merge_sort | 12 |
| quick_sort | 11 |
| is_sorted | 5 |
| binary_heap | 11 |
| bfs_dfs | 14 |
| dijkstra | 10 |
| kmp | 15 |
| gcd | 5 |
| fast_power | 5 |
| array_sum | 6 |
| **Total** | **130** |

## 参考资源

- [MoonBit 形式化验证文档](https://docs.moonbitlang.com/en/latest/language/verification.html)
- [moonbit-community/verified](https://github.com/moonbit-community/verified) — 官方教程级验证示例
- [MoonBit 0.9 发布博客](https://www.moonbitlang.com/blog/moonbit-0-9-release)

## 许可证

Apache-2.0
