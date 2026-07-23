# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
