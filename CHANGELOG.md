# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-29

### Initial development release

> This project has not been formally released or used in production.
> Version 0.1.0 reflects the current state of ongoing development.

#### Formally verified packages (9)
- `binary_search`, `linear_search`, `max_element`, `min_element`, `is_sorted` — full correctness proofs via `moon prove` (Why3 + Z3)
- `array_sum`, `gcd`, `fast_power`, `dijkstra` — partial verification (non-negativity / bounds safety)

#### Sorting (14 packages)
- `insertion_sort`, `selection_sort`, `merge_sort`, `quick_sort` — generic `FixedArray[T]` + comparator
- `heap_sort`, `counting_sort`, `radix_sort`, `timsort`, `introsort`, `pdq_sort`, `bucket_sort`, `external_sort`
- `is_sorted` (verified), `bitonic_sort`, `pancake_sort`

#### Search (15 packages)
- `binary_search` (verified), `linear_search` (verified), `bound_search`, `interpolation_search`, `exponential_search`
- `fibonacci_search`, `jump_search`, `ternary_search`, `quickselect`
- `ball_tree`, `vp_tree`, `lsh`, `hnsw`
- `max_element` (verified), `min_element` (verified)

#### Trees (26 packages)
- `red_black_tree` (Okasaki + Kahrs), `avl`, `bst`, `btree`, `bplus_tree`, `treap`, `splay`
- `segment_tree`, `segment_tree_lazy`, `segment_tree_beats`, `fenwick`, `bit_2d`, `persistent_segment_tree`
- `trie`, `skip_list`, `sparse_table`, `link_cut`, `persistent_vector`, `hamt`
- `li_chao_tree`, `mo_algorithm`, `rope`, `interval_tree`, `range_tree`, `r_tree`, `fibonacci_heap`

#### Containers (26 packages)
- `binary_heap`, `hash_table`, `lru_cache`, `ttl_cache`, `w_tinylfu`, `bloom_filter`, `cuckoo_filter`
- `count_min_sketch`, `hyperloglog`, `union_find`, `priority_queue`, `monotonic`, `bitset`, `deque`
- `consistent_hash`, `crc`, `hash_utils`, `lsm_tree`, `roaring_bitmap`, `count_sketch`, `concurrent`
- `treiber_stack`, `mpmc_queue`, `concurrent_hash_map`, `work_stealing`, `lock_free_queue`

#### Graph (40 packages)
- `bfs_dfs`, `adj_list`, `topological_sort`, `topological_sort_adj`, `kruskal`, `prim`, `scc`, `dijkstra`, `dijkstra_heap`
- `johnson`, `bidirectional_bfs`, `a_star`, `max_flow`, `advanced` (Bellman-Ford + Floyd-Warshall), `min_cost_flow`
- `two_sat`, `dinic`, `lca`, `bridge_articulation`, `euler_path`, `hungarian`, `hopcroft_karp`, `stoer_wagner`
- `max_clique`, `edmonds_blossom`, `dominator_tree`, `gomory_hu`, `hlpp`, `hld`, `centroid_decomposition`
- `virtual_tree`, `min_steiner_tree`, `graph_coloring`, `flow_with_bounds`, `pagerank`, `chu_liu`
- `k_shortest_paths`, `network_simplex`, `tree_isomorphism`

#### String (20 packages)
- `kmp`, `rabin_karp`, `suffix_array`, `z_function`, `manacher`, `aho_corasick`, `boyer_moore`, `lcp_array`
- `suffix_automaton`, `suffix_tree`, `palindromic_tree`, `rolling_hash`, `lyndon`, `fm_index`, `wavelet_tree`
- `regex`, `dawg`, `sa_is`, `bwt`, `suffix_balanced_tree`

#### Number Theory (19 packages)
- `gcd` (partial verified), `fast_power` (partial verified), `int64_utils`, `prime`, `miller_rabin`, `crt`
- `bsgs`, `pollard_rho`, `euler_sieve`, `ntt`, `bigint`, `cipolla`, `finite_field`, `mobius`
- `polynomial`, `primitive_root`, `quadratic_residue`, `reed_solomon`, `pohlig_hellman`

#### Math (19 packages)
- `array_sum` (partial verified), `combinatorics`, `matrix`, `matrix_decomp`, `newton_method`, `berlekamp_massey`
- `fft`, `simplex`, `fwht`, `numerical_integration`, `ode_solver`, `interpolation`, `least_squares`
- `special_functions`, `conjugate_gradient`, `gmres`, `lbfgs`, `autodiff`, `sparse_matrix`

#### Geometry (19 packages)
- `convex_hull`, `andrew_hull`, `convex_hull_3d`, `half_plane_intersection`, `kd_tree`, `rotating_calipers`
- `closest_pair`, `segment_ops`, `delaunay`, `voronoi`, `dynamic_hull`, `min_enclosing_circle`
- `minkowski_sum`, `polygon_boolean`, `segment_intersection`, `point_in_polygon`, `polygon_ops`
- `bentley_ottmann`

#### Dynamic Programming (16 packages)
- `dp`, `lis`, `interval_dp`, `tree_dp`, `digit_dp`, `aliens_trick`, `knapsack_opt`, `matrix_chain`
- `monotone_queue_dp`, `smawk`, `bitmask_dp`, `convex_hull_trick`, `divide_conquer_dp`, `knuth_opt`
- `plug_dp`, `sos_dp`

#### Game Theory (5 packages)
- `nim_sg`, `alpha_beta`, `mcts`, `gale_shapley`, `shapley_value`

#### Random (10 packages)
- `reservoir_sampling`, `weighted_sampling`, `fisher_yates`, `mersenne_twister`, `pcg`, `xoshiro`
- `gaussian_sampling`, `zobrist_hash`, `mcmc`, `monte_carlo`

#### Crypto (18 packages)
- `sha256`, `sha512`, `sha3`, `blake2`, `blake3`, `hmac`, `chacha20`, `chacha20_poly1305`, `poly1305`
- `hkdf`, `pbkdf2`, `scrypt`, `bcrypt`, `argon2`, `aes`, `rsa`, `csprng`, `base64`

#### Compression (10 packages)
- `huffman`, `lz4`, `lz77`, `lzw`, `arithmetic_coding`, `bwt_compress`, `deflate`, `gzip`, `zlib`, `snappy`

#### Machine Learning (7 packages)
- `kmeans`, `knn`, `dbscan`, `pca`, `svm`, `logistic_regression`, `decision_tree`

#### Statistics (7 packages)
- `descriptive`, `linear_regression`, `hypothesis_testing`, `correlation`, `confidence_interval`, `bootstrap`, `distributions`

#### Serialization (2 packages)
- `json`, `msgpack`

#### Time (1 package)
- `chrono`

#### Utilities (2 packages)
- `utils` (swap, str_cmp, next_pow2, encoding, fresh_seed)
- `prng` (SplitMix64, XorShift64, LCG)
- `itertools` (range, repeat, enumerate, window, chunk, fold)

#### Test Infrastructure
- `test/property_test` — QuickCheck-style property-based testing framework
- `test/fuzz` — adversarial-input fuzz tests
- `test/stress` — large-scale stress tests
- `test/test_utils` — shared test utilities
- `benchmarks/` — performance benchmarks with complexity verification

#### CI/CD
- GitHub Actions CI: check + test + prove on Ubuntu/macOS/Windows
- CodeQL security analysis
- Dependency review
- Nightly builds with flaky test detection
- Benchmark regression detection with baseline comparison (25% threshold)
- Release workflow with SHA256 checksums

#### Type safety
- All magic values eliminated in favor of `Option`/`SPResult` types
- ~30 public functions migrated from `abort()` to `Option` returns
- Overflow protection via Int64 for critical algorithms
- Recursive depth protection for balanced trees (AVL, RB-tree, BTree, Treap)

#### Code quality
- `swap` centralized in `@utils` (was duplicated 7 times)
- `SplitMix64`/`XorShift64` centralized in `@utils/prng` (was duplicated across multiple packages)
- Per-instance random seeds via `@utils.fresh_seed()` (replaces global fixed seed)
- `bloom_filter` reused by `lsm_tree` (was reimplemented)
- `binary_heap` reused by `external_sort` (was reimplemented)
