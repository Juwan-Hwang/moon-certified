# Moon Certified

用 [MoonBit](https://www.moonbitlang.com) 0.9 的 `moon prove` 形式化验证系统，构建经过数学证明的核心算法与数据结构库。

## 为什么需要这个项目

MoonBit 0.9 引入了 first-class formal verification 能力，`moon prove` 成为与 `moon build`、`moon test` 并列的工具链内置命令。它通过 Why3 + Z3 SMT 求解器，对代码进行全输入覆盖的正确性证明——不是测试某几组输入碰巧返回正确结果，而是一个覆盖所有可能输入的数学证明。

但目前 MoonBit 生态中，`moonbit-community/verified` 仅包含 12 个教程级示例（v0.0.2）。本项目的目标是构建生产级验证库，覆盖排序、搜索、数据结构、图算法等核心领域。

## 项目状态

🚧 开发中 — 项目刚启动，正在逐步添加验证算法。

## 已验证 / 计划验证的算法

### 排序算法
- [ ] Insertion Sort — 证明输出有序
- [ ] Quick Sort — 证明分区正确性 + 输出有序
- [ ] Merge Sort — 证明稳定性 + 正确性
- [ ] Heap Sort — 证明堆性质维持 + 输出有序

### 搜索算法
- [x] Binary Search — 证明找到则返回正确索引，未找到返回 None
- [ ] Lower Bound — 证明下界位置正确
- [ ] Hash Table Lookup — 证明查找不变量

### 数据结构
- [ ] Red-Black Tree — 证明红黑性质 + BST 性质
- [ ] AVL Tree — 证明高度平衡 + BST 性质
- [ ] Binary Heap — 证明堆性质（父节点 ≤ 子节点）

### 图算法
- [ ] BFS / DFS — 证明遍历完整性
- [ ] Dijkstra — 证明返回确实是最短路径
- [ ] Minimum Spanning Tree (Kruskal) — 证明生成树最小
- [ ] Topological Sort — 证明拓扑序有效

### 字符串算法
- [ ] KMP — 证明匹配正确性
- [ ] Rabin-Karp — 证明哈希匹配正确性

### 数论
- [ ] GCD (Euclid) — 证明最大公约数正确性
- [ ] Fast Power — 证明快速幂正确性

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

# 运行所有验证
moon prove

# 运行测试
moon test

# 运行示例
moon run examples/binary_search_demo
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

## 项目结构

```
moon-certified/
├── sorting/
│   ├── insertion_sort/
│   ├── quick_sort/
│   ├── merge_sort/
│   └── heap_sort/
├── search/
│   ├── binary_search/
│   ├── lower_bound/
│   └── hash_lookup/
├── containers/
│   ├── red_black_tree/
│   ├── avl_tree/
│   └── binary_heap/
├── graph/
│   ├── bfs_dfs/
│   ├── dijkstra/
│   ├── mst/
│   └── topo_sort/
├── string/
│   ├── kmp/
│   └── rabin_karp/
├── number_theory/
│   ├── gcd/
│   ├── fast_power/
│   └── prime_sieve/
└── examples/
```

## 参考资源

- [MoonBit 形式化验证文档](https://docs.moonbitlang.com/en/latest/language/verification.html)
- [moonbit-community/verified](https://github.com/moonbit-community/verified) — 官方教程级验证示例
- [MoonBit 0.9 发布博客](https://www.moonbitlang.com/blog/moonbit-0-9-release)

## 许可证

Apache-2.0
