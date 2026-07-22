# Moon Certified

用 [MoonBit](https://www.moonbitlang.com) 0.9 的 `moon prove` 形式化验证系统，构建经过数学证明的核心算法与数据结构库。

## 为什么需要这个项目

MoonBit 0.9 引入了 first-class formal verification 能力，`moon prove` 成为与 `moon build`、`moon test` 并列的工具链内置命令。它通过 Why3 + Z3 SMT 求解器，对代码进行全输入覆盖的正确性证明——不是测试某几组输入碰巧返回正确结果，而是一个覆盖所有可能输入的数学证明。

但目前 MoonBit 生态中，`moonbit-community/verified` 仅包含 12 个教程级示例（v0.0.2）。本项目的目标是构建生产级验证库，覆盖排序、搜索、数据结构、图算法等核心领域。

## 项目状态

开发中 — 已完成 8 个验证算法包，正在持续添加更多。

## 已验证 / 计划验证的算法

### 搜索算法
- [x] **Binary Search** — 证明找到则返回正确索引，未找到返回 None
- [x] **Linear Search** — 证明返回正确索引或 None
- [x] **Max Element** — 证明返回的索引指向最大元素
- [x] **Min Element** — 证明返回的索引指向最小元素
- [ ] Lower Bound — 证明下界位置正确
- [ ] Hash Table Lookup — 证明查找不变量

### 排序算法
- [x] **Is Sorted** — 证明返回 true 时数组确实有序
- [ ] Insertion Sort — 证明输出有序
- [ ] Quick Sort — 证明分区正确性 + 输出有序
- [ ] Merge Sort — 证明稳定性 + 正确性
- [ ] Heap Sort — 证明堆性质维持 + 输出有序

### 数论算法
- [x] **GCD (Euclid)** — 证明结果非负（递归 + proof_decrease）
- [x] **Fast Power** — 证明结果非负（递归 + proof_decrease）
- [ ] Prime Sieve — 证明筛法正确性

### 数学算法
- [x] **Array Sum** — 证明非负数组之和非负
- [x] **Count Non-Negative** — 证明计数在 [0, length] 范围内

### 数据结构（计划中）
- [ ] Red-Black Tree — 证明红黑性质 + BST 性质
- [ ] AVL Tree — 证明高度平衡 + BST 性质
- [ ] Binary Heap — 证明堆性质（父节点 ≤ 子节点）

### 图算法（计划中）
- [ ] BFS / DFS — 证明遍历完整性
- [ ] Dijkstra — 证明返回确实是最短路径
- [ ] Minimum Spanning Tree (Kruskal) — 证明生成树最小
- [ ] Topological Sort — 证明拓扑序有效

### 字符串算法（计划中）
- [ ] KMP — 证明匹配正确性
- [ ] Rabin-Karp — 证明哈希匹配正确性

## 使用方式

### 环境要求

- MoonBit 0.9+
- [Why3](https://why3.lri.fr/) 1.7.2（推荐通过 opam 安装：`opam install why3.1.7.2`）
- [Z3](https://github.com/Z3Prover/z3) SMT 求解器

### 运行验证

```bash
# 克隆仓库
git clone https://github.com/Juwan-Hwang/moon-certified.git
cd moon-certified

# 运行所有形式化验证
moon prove

# 运行测试
moon test

# 类型检查
moon check
```

### 在项目中使用

```bash
moon add Juwan-Hwang/moon-certified
```

```moonbit
fn main {
  let xs = FixedArray::make(10, fn(i) { i })
  let result = @binary_search.search(xs, 5)
  println(result) // Some(5)

  let mx = @max_element.max_element(xs)
  println(mx) // 9

  let g = @gcd.gcd(12, 8)
  println(g) // 4
}
```

## 技术原理

每个验证算法包含两类文件：

- **`.mbt`** — 可执行的 MoonBit 代码 + 契约（`proof_require` / `proof_ensure`）+ 循环不变量（`proof_invariant`）
- **`.mbtp`** — 逻辑谓词定义和引理

验证流程：

```
.mbt + .mbtp  →  moonc prove  →  Why3 + Z3
源代码 + 谓词     生成 WhyML       证明所有目标
```

验证目标包括：
- 循环不变量初始化（首次迭代前成立）
- 循环不变量保持性（每次迭代后仍成立）
- 后置条件（函数返回时满足规约）
- 终止性（递归调用的参数递减）
- 数组边界（所有数组访问在合法范围内）

## 项目结构

```
moon-certified/
├── search/
│   ├── binary_search/      ✅ 二分查找
│   ├── linear_search/      ✅ 线性查找
│   ├── max_element/        ✅ 最大元素
│   └── min_element/        ✅ 最小元素
├── sorting/
│   └── is_sorted/          ✅ 有序性检查
├── number_theory/
│   ├── gcd/                ✅ 最大公约数
│   └── fast_power/         ✅ 快速幂
├── math/
│   └── array_sum/          ✅ 数组求和 + 非负计数
├── containers/             📋 计划中
├── graph/                   📋 计划中
└── string/                 📋 计划中
```

## 参考资源

- [MoonBit 形式化验证文档](https://docs.moonbitlang.com/en/latest/language/verification.html)
- [moonbit-community/verified](https://github.com/moonbit-community/verified) — 官方教程级验证示例
- [MoonBit 0.9 发布博客](https://www.moonbitlang.com/blog/moonbit-0-9-release)

## 许可证

Apache-2.0
