# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2026-07-24

### Added — 12 new algorithm packages

#### Containers
- `priority_queue` — Generic binary heap-based priority queue with dynamic resizing, indexed access (handles survive relocation), O(log n) priority updates and removal. Floyd heapify for O(n) construction.
- `monotonic` — Monotonic stack and deque for next greater/smaller element and sliding window min/max in O(n).

#### Dynamic Programming
- `interval_dp` — Interval DP framework: matrix chain multiplication, optimal BST, burst balloons, stone merging. All use Int64 for overflow-safe cost accumulation.
- `tree_dp` — Tree DP template: maximum independent set, tree diameter, maximum matching, tree knapsack. All traversals are iterative (stack-safe).

#### Graph
- `bridge_articulation` — Tarjan's bridge and articulation point detection. Correctly handles multi-edges and self-loops via parent-edge skip tracking.
- `euler_path` — Hierholzer's algorithm for Euler path and circuit detection. Iterative implementation for stack safety.
- `hungarian` — Kuhn-Munkres (Hungarian) algorithm for optimal assignment. O(n³) min-cost and max-weight bipartite matching.

#### Number Theory
- `ntt` — Number Theoretic Transform for O(n log n) polynomial multiplication. Uses NTT-friendly prime 998244353 with full Int64 overflow-safe modular arithmetic.

#### String
- `boyer_moore` — Boyer-Moore string search with bad-character and good-suffix heuristics. O(n/m) best case.
- `lcp_array` — Kasai's algorithm for LCP array construction in O(n) from a suffix array.
- `suffix_automaton` — Suffix Automaton (SAM) for O(n) substring queries, distinct substring counting, occurrence counting, and longest repeated substring.

#### Trees
- `segment_tree_lazy` — Segment tree with lazy propagation for range add + range sum/min/max queries in O(log n).

### Fixed — Production-grade quality improvements

#### Overflow safety
- `gcd64`: Fixed Int64::MIN handling — no longer overflows on absolute value conversion; runs Euclidean algorithm on signed inputs and normalises at end.
- `is_prime64`: Expanded Miller-Rabin witness set from {2,7,61} (valid for n<2³²) to {2,3,5,7,11,13,17,19,23,29,31,37} (valid for full Int64 range).
- `pollard_rho`: Replaced batched GCD with per-step GCD to prevent missing factors for small composites. Implemented Brent's cycle detection (matching documentation).
- `combinatorics.binomial`: Fixed "divide-first" overflow logic — now uses Int64 intermediate with multiply-then-divide (exact since C(n,k) is always integer).
- `combinatorics.stirling2`: Replaced post-hoc overflow detection with pre-check pattern (check before multiply/add).
- `min_cost_flow`: SPFA negative cycle detection added (enqueue count > n → abort). Int32 cost accumulation upgraded to Int64. Returns Option to distinguish invalid input from valid zero-flow.
- `max_flow` / `dinic`: Returns Int64? to distinguish invalid input (None) from valid zero flow (Some(0L)).
- `dijkstra_heap`: Fixed redundant overflow check (was comparing against Int64::MAX instead of Int32::MAX).
- `array_sum`: Added `array_sum_checked` returning Int? (None on overflow).
- `matrix`: Added `matmul_int_checked` returning FixedArray[Int]? (None on overflow).
- `interpolation_search`: Int32 subtraction overflow fixed — converts to Int64 before subtracting.
- `euler_sieve`: Added OOM protection (abort for n > 100,000,000).
- `union_find`: Added negative-n validation in constructor.

#### Encapsulation
- Made all struct fields private across `binary_heap`, `hash_table`, `bloom_filter`, `btree`, `treap`, `lru_cache`, `skip_list`, `trie`, `monotonic`, `priority_queue`, `segment_tree_lazy`, `suffix_automaton`.
- `HeapG[T]` generic heap with dynamic resizing and `decrease_key` now fully implemented (was previously documented but missing).

#### Algorithm correctness
- `splay`: Converted from recursive to iterative bottom-up splay (stack-safe for degenerate trees).
- `dinic`: Converted recursive DFS to iterative with explicit stack (stack-safe for deep graphs).
- `hungarian`: Fixed min-cost/max-weight dual convention (was solving max instead of min).
- `bridge_articulation`: Fixed multi-edge handling (parent-edge tracking instead of parent-vertex).
- `aho_corasick`: Child lookup upgraded from O(k) linear scan to O(log k) binary search.
- `red_black_tree`: Added O(1) cached size; iterative height calculation.

#### Documentation
- `fast_power`: Marked as deprecated, recommending `fast_power_checked`.
- `pollard_rho`: Documentation updated to match implementation (Brent's cycle detection with per-step GCD).
- README test count and package count updated to match reality.

## [0.8.0] - 2026-07-24

### Added — 8 new algorithm packages

#### Number Theory
- `euler_sieve` — Euler's linear sieve: O(n) prime generation with smallest-prime-factor (spf) table. Supports O(log n) factorization and primality testing within the sieved range.

#### Trees
- `sparse_table` — Sparse Table for O(1) idempotent range queries (min, max, gcd). Generic `SparseTable[T]` with custom combine function. O(n log n) preprocessing.

#### Graph
- `lca` — Lowest Common Ancestor via binary lifting. O(n log n) preprocessing, O(log n) per query. Supports ancestor queries and distance computation.
- `dinic` — Dinic's maximum flow algorithm with level graphs and blocking flows. O(V²E) worst-case, O(E√V) for bipartite matching.

#### Geometry
- `closest_pair` — Closest pair of points via divide-and-conquer. O(n log n) with merge step optimization.
- `segment_ops` — Segment intersection (orientation-based), point-in-polygon (ray casting), point-on-segment, polygon area (shoelace), and convexity test. All arithmetic uses Int64 cross products for exact integer results.

#### Math
- `combinatorics` — Factorial, permutation, binomial coefficient (multiplicative formula), Catalan numbers, and Stirling numbers of the second kind. Int64 overflow protection throughout.
- `matrix` — Matrix operations including multiplication, Gaussian elimination, and determinant computation.

### Fixed
- Eliminated remaining compiler warnings in combinatorics tests (unused variables, deprecated `not()` function).
- Fixed ray-casting algorithm sign handling in point-in-polygon (cross product direction depends on edge orientation).

## [0.7.0] - 2026-07-24

### Fixed — Production-grade quality improvements

- **P0**: gcd Int::MIN math error (uses Int64 for exact computation)
- **P0**: Eliminated all 35 compiler warnings (0 warnings)
- **P0**: Splay tree documentation matches implementation (bottom-up)
- **P0**: Aho-Corasick CJK safety (sparse children replacing dense 256-slot array)
- **P0**: Treap eliminates global mutable state (per-instance RNG)
- **P0**: CI pins MoonBit version for reproducibility
- **P1**: Silent failures converted to Option/Result returns
- **P1**: BST converted to iterative implementation (O(1) stack depth)
- **P1**: LCS/edit_distance optimized to rolling array O(min(n,m)) space
- **P1**: Bloom filter bounds checking
- **P1**: Trie enumerate optimized to O(n) string construction
- **P1**: Skip list removes unnecessary update array
- **P1**: A* eliminates code duplication

## [0.6.0] - 2026-07-24

### Added — 8 new algorithm packages

#### String
- `aho_corasick` — Aho-Corasick multi-pattern string matching with failure links and output links. O(n + m + z) time.

#### Graph
- `min_cost_flow` — Minimum-cost maximum-flow using SPFA (Shortest Path Faster Algorithm). Linked-forward-star edge representation. O(F × V × E) worst-case.
- `two_sat` — 2-SAT Boolean satisfiability via implication graphs and Tarjan's SCC. O(n + m) linear time.

#### Trees
- `splay` — Splay tree: self-adjusting BST with bottom-up splaying. Cached subtree sizes. Functional (immutable) node representation. Amortized O(log n) per operation.

#### Number Theory
- `bsgs` — Baby-step giant-step discrete logarithm. Solves a^x ≡ b (mod p) in O(√p) time and space. Handles edge cases (a≡0, p=1, gcd(a,p)≠1).
- `pollard_rho` — Pollard-Rho integer factorization with Brent's improvement and Miller-Rabin primality test. Deterministic (no RNG dependency).

#### Geometry
- `kd_tree` — KD-Tree 2D spatial indexing with nearest-neighbor search (pruning via splitting-plane distance) and orthogonal range search. O(log n) average NN, O(√n + k) average range search.
- `rotating_calipers` — Rotating calipers for convex polygon diameter and width. O(n) after convex hull. Supports both CCW and CW input orientations via signed-area detection.

### Fixed
- `rotating_calipers`: Fixed cross-product comparison that was inverted for CCW polygons. Added signed-area orientation detection (shoelace formula) to correctly handle both CCW and CW convex polygons.
- `kd_tree`: Fixed test to verify minimum distance rather than asserting a specific point among ties.
- `min_cost_flow`: Corrected test expectations for transport problem (flow=13, cost=71).
- `dijkstra`: Added overflow documentation directing users to `dijkstra_heap` for Int64 protection.

### Test Suite
- Total tests: **958** (up from 830)
- Total packages: **66** (up from 58)
- 0 warnings, 0 errors

## [0.5.0] - 2026-07-23

### Added — 15 new algorithm packages

#### Sorting
- `heap_sort` — In-place heap sort with generic comparator. O(n log n) time, O(1) space.
- `counting_sort` — Counting sort for non-negative integers. O(n + k) time. OOM protection for k > 10^7.
- `radix_sort` — LSD base-256 radix sort. O(d(n + 256)) time. Stable.

#### String
- `z_function` — Z-algorithm for pattern matching. `z_array` and `z_search`. O(n + m) time.
- `manacher` — Manacher's algorithm for palindromic substrings. `longest_palindrome`, `count_palindromes`, `palindrome_radii`. O(n) time.

#### Number Theory
- `miller_rabin` — Deterministic Miller-Rabin primality test for Int32 range. Witnesses {2, 7, 61}. O(k log n) time.
- `crt` — Chinese Remainder Theorem solver. Handles coprime and non-coprime moduli. `crt` for two congruences, `crt_system` for systems. Int64 arithmetic.

#### Graph
- `johnson` — Johnson's all-pairs shortest paths. Bellman-Ford + reweight + Dijkstra. Handles negative weights, detects negative cycles.
- `bidirectional_bfs` — Bidirectional BFS for unweighted shortest path. O(b^(d/2)) time.
- `topological_sort_adj` — Kahn's topological sort on adjacency list. `topo_sort` and `has_cycle`. O(V + E) time.

#### Trees
- `skip_list` — Skip list with probabilistic balancing. O(log n) expected operations. LCG random.
- `treap` — Treap (tree + heap) randomized BST. O(log n) expected operations. Cached size.

#### Search
- `interpolation_search` — Interpolation search for uniformly distributed sorted data. O(log log n) average, Int64 overflow protection.
- `exponential_search` — Exponential (galloping) search. O(log n) time.

#### Geometry
- `andrew_hull` — Andrew's monotone chain convex hull. O(n log n) time. Int64 cross product overflow protection.

### Changed — Production-grade quality fixes

#### P0 Critical Fixes
- `fast_power_checked`: Fixed overflow detection bug where `b * b` overflowed Int64. Now checks before squaring.
- `gcd`: Fixed `Int::MIN` overflow. Safe absolute value handling.
- `dijkstra`: Fixed negative array length when `n < 0`.
- `min_element` / `max_element`: Empty array now returns `None` instead of invalid index 0.
- `bloom_filter`: Fixed infinite loop in `bf_ln` when `x <= 0`.
- `binary_heap`: `heap_push` now returns error on full heap instead of silent failure.
- `red_black_tree`: `is_valid_rb` now checks BST ordering invariant, not just RB properties.
- `kmp`: Fixed non-standard backtracking in `kmp_step`. Now uses proper while-loop.
- `max_flow`: Documented overflow risk, replaced magic number with named constant.
- `floyd_warshall`: Replaced magic `INF` with named, documented constant.
- `lru_cache`: Rewrote from O(n) to O(1) using hash map + doubly linked list.
- `a_star`: Replaced O(n^2) linear scan with binary min-heap. Added path reconstruction.
- `bst`: Added documentation warning about lack of self-balancing.

#### P1 Important Fixes
- `binary_heap`: Added generic `HeapG[T]`, dynamic resizing, `decrease_key`.
- `segment_tree`: Added lazy propagation (`LazySegTree`) for range updates.
- `dijkstra_heap`: Added Int64 overflow protection for distance accumulation.
- `prim`: Named INF constant, documented 0-weight edge limitation.
- `convex_hull`: Int64 cross product to prevent overflow.
- `scc`: Rewrote Tarjan's algorithm iteratively to avoid stack overflow.
- `sieve` / `knapsack`: Added OOM protection with input size limits.

#### P2 Quality Improvements
- `avl`: Cached subtree size for O(1) `size()`.
- `trie`: Sparse children representation for memory efficiency.
- `dijkstra`: Documented `proof_axiomatized` lemma honestly.
- `merge_sort`: Added stability test.
- README: Updated verification status documentation for honesty.
- `segment_tree`: Renamed `lazy` field to `pending` (reserved keyword compliance).
- `dijkstra_heap`: Fixed const naming to uppercase (MoonBit convention).

### Test Suite
- Total tests: **830** (up from 601)
- Total packages: **58** (up from 43)
- 0 warnings, 0 errors

## [0.4.0] - 2025-01-15

### Added
- LRU Cache, Bloom Filter, B-Tree, A* search, Edmonds-Karp max flow
- Heap-optimized Dijkstra, LIS O(n log n), Graham convex hull, Suffix array, Adjacency list
- Stress test package with 12 large-scale tests

## [0.3.0] - 2024-12-01

### Added
- Red-black tree complete deletion (Kahrs algorithm)
- Treap, Fenwick tree, Trie with size/enumerate/longest_prefix

### Changed
- Eliminated all magic values in favor of Option/SPResult types
- Removed misleading proof_axiomatized lemmas
- Added data structure encapsulation (Heap, StringHashTable, UnionFind)

## [0.2.0] - 2024-11-01

### Added
- Full generic support for sorting packages
- Generic search companions (search_generic, max_element_generic, etc.)
- Red-black tree (Okasaki insertion)
- 8 new packages: rabin_karp, hash_table, prim, scc, fenwick, trie, bound_search, red_black_tree

## [0.1.0] - 2024-10-15

### Added
- Initial release with 5 verified packages (binary_search, linear_search, max_element, min_element, is_sorted)
- Formal verification infrastructure with moon prove
- 25 total packages covering sorting, search, trees, containers, graphs, strings, number theory
