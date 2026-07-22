# moon-certified 项目申报书

**项目名称**：moon-certified：基于 moon prove 的形式化验证核心算法库

**GitHub 仓库**：`https://github.com/Juwan-Hwang/moon-certified`

**项目方向**：基础数据结构与算法（moon prove 验证的通用算法库）

**是否为原创项目**：是。算法本身是经典算法，但使用 MoonBit 0.9 的 moon prove 对其进行形式化验证是原创工作。参考了官方 `moonbit-community/verified`（Apache-2.0）的验证写法和风格，但本项目是独立实现，覆盖范围和验证深度远超该教程级种子包。

## 项目简介

MoonBit 0.9 引入了 first-class formal verification 能力，`moon prove` 成为与 `moon build`、`moon test` 并列的工具链内置命令。它通过 Why3 + Z3 SMT 求解器对代码进行全输入覆盖的正确性证明——不是测试某几组输入碰巧返回正确结果，而是覆盖所有可能输入的数学证明。

但目前 MoonBit 生态中，`moonbit-community/verified` 仅包含 12 个教程级示例（v0.0.2），没有生产级的验证算法库。本项目旨在填补这个空白：构建一个覆盖排序、搜索、数据结构、图算法等核心领域的验证库，每个算法都附带形式化证明，确保在所有合法输入下行为正确。

## 适用场景

- **MoonBit 标准库候选**：经过形式化验证的算法可以直接作为标准库的可靠实现
- **AI 生成代码的质量保障**：MoonBit 官方强调"验证即发布"——当 AI 大规模生成 MoonBit 代码时，验证过的核心库是可信基石
- **教学与推广**：作为 moon prove 的完整实践案例，帮助社区理解形式化验证的实际工程用法
- **其他生态库的依赖**：后续的图算法库、ORM、网络框架等都可以依赖经过验证的基础算法

## 拟实现的核心功能

1. **排序算法验证**：插入排序、快速排序、归并排序、堆排序——证明输出有序、元素不变
2. **搜索算法验证**：二分查找（含泛型版本）、下界查找、哈希表查找——证明返回正确索引或 None
3. **数据结构验证**：红黑树（红黑性质 + BST 性质）、AVL 树（高度平衡 + BST 性质）、二叉堆（堆性质）——使用 model-based verification 模式
4. **图算法验证**：BFS/DFS（遍历完整性）、Dijkstra（最短路径正确性）、拓扑排序（拓扑序有效性）、最小生成树 Kruskal（生成树最小）
5. **字符串算法验证**：KMP 匹配、Rabin-Karp 哈希匹配——证明匹配正确性
6. **数论算法验证**：GCD（欧几里得算法）、快速幂——证明结果正确性
7. **在线证明可视化 Demo**：算法执行 + 证明状态同步展示
8. 发布到 mooncakes.io，提供完整测试、CI、README 和可运行示例

## 参考说明

- `moonbit-community/verified`（Apache-2.0）：参考其 moon prove 写法、谓词风格和验证流程，作为技术起点
- MoonBit 官方形式化验证文档：参考 `proof_require`/`proof_ensure`/`proof_invariant` 语法和 model-based verification 模式
- 经典算法实现参考 CLRS《算法导论》中的伪代码和不变量描述
- 本项目所有代码为独立编写，许可证为 Apache-2.0
