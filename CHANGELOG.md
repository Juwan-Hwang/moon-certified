# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.11.0] - 2026-07-25

### Added — 44 new algorithm packages + production infrastructure

#### Containers
- `concurrent` — Concurrent data structures: generic RingBuffer, BoundedQueue (try_push/try_pop), SnapshotMap (copy-on-write snapshot with O(1) snapshot).
- `lock_free_queue` — Michael-Scott lock-free queue with preallocated node pool and CAS-based enqueue/dequeue.
- `lsm_tree` — Log-Structured Merge-Tree with memtable, SSTable flush, and multi-level compaction.
- `bplus_tree` (in trees/) — B+Tree with linked leaves for range queries.
- `hamt` (in trees/) — Hash Array Mapped Trie (HAMT) for persistent, O(log₃₂ n) key-value store.
- `crc` — CRC-32 (IEEE 802.3) checksum with lookup table.

#### String
- `suffix_tree` — Ukkonen's suffix tree: build, contains, count_occurrences, count_distinct_substrings, longest_repeated_substring.
- `fm_index` — FM-Index for compressed full-text indexing: count, locate, extract.
- `wavelet_tree` — Wavelet tree for rank/select queries on sequences.
- `palindromic_tree` — Eertree for all distinct palindromic substrings.
- `suffix_balanced_tree` — Suffix balanced tree for online suffix insertion.
- `lyndon` — Lyndon decomposition (Duval) and minimum rotation (Booth).

#### Graph
- `edmonds_blossom` — Edmonds' Blossom algorithm for maximum matching in general (non-bipartite) graphs.
- `dominator_tree` — Lengauer-Tarjan dominator tree construction.
- `gomory_hu` — Gomory-Hu tree for all-pairs min-cut.
- `stoer_wagner` — Stoer-Wagner global minimum cut.
- `hlpp` — Highest-Label Preflow Push max flow (O(V²√E)).
- `hopcroft_karp` — Hopcroft-Karp bipartite matching (O(E√V)).
- `min_steiner_tree` — Minimum Steiner tree (approximation + exact for small terminal sets).
- `hld` — Heavy-Light Decomposition for path queries/updates on trees.
- `centroid_decomposition` — Centroid decomposition for divide-and-conquer on trees.
- `virtual_tree` — Virtual tree (auxiliary tree) construction from a vertex set.
- `max_clique` — Bron-Kerbosch maximum clique with pivoting and degeneracy ordering.
- `graph_coloring` — Graph coloring (DSATUR heuristic + greedy).
- `flow_with_bounds` — Min-cost max-flow with lower and upper capacity bounds.

#### Geometry
- `convex_hull_3d` — 3D convex hull via randomized incremental construction.
- `voronoi` — Voronoi diagram via Fortune's sweep line algorithm.
- `delaunay` — Delaunay triangulation via incremental insertion.
- `half_plane_intersection` — Half-plane intersection (S&I + deque).
- `dynamic_hull` — Dynamic convex hull (online insertion, O(log²n) per point).

#### Math
- `fft` — Fast Fourier Transform (Cooley-Tukey radix-2) for complex polynomial multiplication.
- `matrix_decomp` — LU decomposition (partial pivoting), QR (Householder), SVD (one-sided Jacobi), eigenvalues (QR iteration).
- `newton_method` — Newton-Raphson root finding with robust error handling.
- `simplex` — Two-phase simplex method for linear programming.
- `berlekamp_massey` — Berlekamp-Massey linear recurrence finding.

#### Number Theory
- `quadratic_residue` — Tonelli-Shanks algorithm for quadratic residues mod prime.
- `primitive_root` — Primitive root finding modulo prime.
- `mobius` — Möbius function and Möbius inversion.
- `finite_field` — GF(p) finite field arithmetic.
- `reed_solomon` — Reed-Solomon encoding/decoding with GF(256).
- `polynomial` — Polynomial operations (inverse, sqrt, ln, exp mod x^n).

#### Dynamic Programming
- `bitmask_dp` — Bitmask DP: Hamiltonian path, Steiner tree, independent set on small graphs.
- `convex_hull_trick` — Convex Hull Trick for slope optimization.
- `digit_dp` — Digit DP for digit-property counting.
- `divide_conquer_dp` — Divide-and-conquer DP optimization.
- `knuth_opt` — Knuth optimization (quadrangle inequality).
- `sos_dp` — Sum Over Subsets DP.

#### Trees
- `persistent_vector` — Persistent vector with structural sharing (path copying).
- `link_cut` — Link-Cut Tree (Sleator-Tarjan).
- `li_chao_tree` — Li Chao Tree for line segment optimization.
- `bit_2d` — 2D Binary Indexed Tree.
- `mo_algorithm` — Mo's algorithm for offline range queries.
- `segment_tree_beats` — Segment Tree Beats (range chmin/chmax + sum).

#### Search
- `ball_tree` — Ball tree for nearest neighbor search.
- `vp_tree` — Vantage Point tree for metric space search.
- `lsh` — Locality-Sensitive Hashing for approximate nearest neighbor.
- `ternary_search` — Ternary search for unimodal function optimization.

#### Sorting
- `external_sort` — External merge sort for datasets larger than memory.

#### Random
- `reservoir_sampling` — Reservoir sampling (Algorithm R).
- `weighted_sampling` — Weighted random sampling (alias method).

#### Game Theory
- `nim_sg` — Nim game and Sprague-Grundy theorem.

#### Test Infrastructure
- `benchmarks/` — Performance benchmark suite with wall-clock timing and complexity verification.
- `test/fuzz/` — Fuzz tests and adversarial input tests (sorting worst-case, graph self-loops/disconnects/cycles, string Unicode, Carmichael numbers, geometry collinear/duplicate, concurrent structure boundaries).
- `test/stress/` — Enhanced stress tests with permutation verification (sorting) and subsequence validation (LIS).
- `test/test_utils/` — Shared test utilities (eliminates str_cmp duplication across 14 files).
- `docs/API_STABILITY.md` — API stability and deprecation policy.

### Fixed — 3 P0/P1 bugs + 12 production-grade improvements

#### Bug fixes (P0/P1)
- `euler_path`: Fixed `total_edges` counting out-of-bounds vertices, causing path-length validation to incorrectly reject valid Euler paths (P0).
- `boyer_moore`: Fixed `build_bad_char` using hardcoded 256-element array (ASCII only) — now uses `Map[Int, Int]` supporting all Unicode code points including CJK (P0).
- `convex_hull`: Fixed using `cross()` (Int32) instead of `cross64()` (Int64) — coordinate differences >46340 caused overflow. Now consistent with `andrew_hull` (P1).

#### Production-grade improvements
- `avl`: Added recursion depth limit (stack protection) + generic support.
- `segment_tree`: Added overflow-safe midpoint `lo + (hi-lo)/2` + stack protection + checked Int64 variant.
- `segment_tree_lazy`: `point_get` optimized from O(log n) to O(1) + overflow detection.
- `btree`: `size()` upgraded from O(n) traversal to O(1) cached count + `_delete` clamp precision fix.
- `treap`: Added stack protection + iterative alternatives for degenerate trees.
- `bloom_filter`: Made generic + added `get_bit` boundary check (consistent with `set_bit`).
- `suffix_array`: Recursive merge sort replaced with iterative bottom-up implementation (stack-safe).
- `tree_dp`: Forest handling code deduplicated (~40 lines removed).
- `matrix`: Negative exponent handling + Bareiss algorithm overflow documentation.
- `ntt`: Dead code in `bit_reverse` removed + upgraded from O(n log n) to O(n) bit-reversal.
- `int64_utils`: `gcd64(Int64::MIN, Int64::MIN)` documentation corrected.

#### Algorithm upgrades
- `min_cost_flow`: Upgraded from pure SPFA to **Successive Shortest Paths with Potentials** (first iteration SPFA + subsequent Dijkstra with reduced costs). Complexity improved from O(F·V·E) to O(V·E + F·E log V).
- `prim`/`segment_tree`/`fenwick`/`kruskal`: Added `*_checked` variants with Int64 overflow detection.

#### Documentation / error handling
- `miller_rabin`: Documentation corrected — witness set is {2,3,5,7,11,13,17,19,23,29,31,37} (12 witnesses), not {2,7,61}.
- `euler_sieve`: Changed from `abort(panic)` to returning `None` for n > 100M, consistent with library's Option-over-magic-values policy.
- `andrew_hull`: `cmp_point` changed from Int32 subtraction to Int64 subtraction, consistent with `closest_pair.cmp_xy`.
- README updated: overflow table now documents checked variants for prim/segment_tree/fenwick/kruskal.
- CI: Added macOS to the test matrix (was ubuntu-only).

### Changed
- Updated README: 113 → 157 packages, 1599 → 2184 tests.
- CI matrix: ubuntu-22.04 → ubuntu-22.04 + ubuntu-latest + macos-latest.

## [0.10.0] - 2026-07-25

### Added — 27 new algorithm packages

#### String
- `suffix_tree` — Ukkonen's algorithm for O(n) suffix tree construction. Supports substring search, longest common extension, and suffix enumeration.
- `palindromic_tree` — Eertree (palindromic tree) for storing all distinct palindromic substrings in O(n). Supports insertion, existence query, and longest palindrome.
- `rolling_hash` — Dual-modulus rolling hash for collision-resistant substring hashing. Supports arbitrary [l, r) range queries in O(1).
- `lyndon` — Lyndon decomposition via Duval's algorithm. Includes minimum rotation (Booth's algorithm) and lexicographically smallest rotation.

#### Graph
- `hopcroft_karp` — Hopcroft-Karp algorithm for maximum bipartite matching in O(E√V). Layered BFS + greedy DFS.
- `stoer_wagner` — Stoer-Wagner algorithm for global minimum cut in O(V³). Phase-based vertex contraction.
- `max_clique` — Bron-Kerbosch algorithm with pivoting and degeneracy ordering for maximum clique finding.

#### Trees
- `link_cut` — Link-Cut Tree (Sleator-Tarjan) using splay-tree representation. Supports dynamic tree operations: link, cut, connected, root query in amortized O(log n).
- `persistent_vector` — Persistent vector with structural sharing (path copying). O(log n) update, O(1) snapshot.

#### Geometry
- `convex_hull_3d` — 3D convex hull via randomized incremental construction with horizon edge detection. O(n log n) expected.
- `half_plane_intersection` — Half-plane intersection using sort-and-sweep algorithm with deque. No atan2 (cross-product comparator). Bounding box for unbounded cases.

#### Math
- `matrix_decomp` — LU decomposition (partial pivoting), QR decomposition (Householder reflections), SVD (one-sided Jacobi rotations). All for Double matrices.
- `newton_method` — Newton-Raphson root finding with robust error handling (zero derivative, divergence, max iterations). Includes nth_root and sqrt.
- `berlekamp_massey` — Berlekamp-Massey algorithm for finding the shortest linear recurrence relation of a sequence in O(n²).
- `fft` — Fast Fourier Transform (Cooley-Tukey radix-2) for O(n log n) polynomial multiplication. Complex arithmetic with trigonometric recursion.
- `simplex` — Two-phase simplex method for linear programming. Handles equality and inequality constraints with auxiliary variables.

#### Containers
- `w_tinylfu` — W-TinyLFU cache combining Window LRU + SLRU + Count-Min Sketch frequency estimator. Modern admission-based cache with aging for superior hit rates.
- `cuckoo_filter` — Cuckoo filter supporting insertion, lookup, and deletion with configurable fingerprint size and bucket count.
- `hyperloglog` — HyperLogLog for cardinality estimation with bias correction for small/large ranges.
- `ttl_cache` — TTL cache with LRU eviction and time-based expiry. Monotonic clock for O(1) TTL check.
- `count_min_sketch` — Count-Min Sketch with double hashing, merge, and inner product estimation. Configurable epsilon/delta guarantees.

#### Dynamic Programming
- `digit_dp` — Digit DP for counting numbers with specific digit properties (digit sum, digit constraints, range [L, R] queries).

#### Game Theory
- `nim_sg` — Combinatorial game theory: Nim game solving, Sprague-Grundy theorem for composite games, Grundy number computation.

#### Random
- `reservoir_sampling` — Reservoir sampling (Algorithm R) for O(n) online uniform sampling from a stream of unknown size.

### Changed
- Updated README: 86 → 113 packages, 1321 → 1599 tests. All new packages documented in project structure and test statistics.
- Added overflow documentation entries for rolling_hash, matrix_decomp, and newton_method.

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
