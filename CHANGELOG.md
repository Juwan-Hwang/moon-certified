# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-27

### First official release

> First formally published version. Quality gates at release time:
> `moon check --deny-warn` 0 errors / 0 warnings, `moon test` 6432/6432
> passing, `moon prove` 17/17 proved packages, `moon fmt --check` clean,
> on MoonBit 0.1.20260819 (the exact toolchain pinned in CI).
>
> Stability: 9 packages in the Verified tier, 254 in the Stable tier,
> 74 in the Experimental tier (APIs not yet frozen). See
> `docs/API_STABILITY.md`.
>
> Distribution: published to mooncakes.io as `Juwan-Hwang/moon-certified`
> (`moon add Juwan-Hwang/moon-certified`), and as a GitHub Release with
> source tarball + SHA256 checksums. Tagging `v*` triggers CI release
> automation including `moon publish`.

#### Hardening since the 0.1.0 development snapshot
- Rewrote 12 packages that were placeholder implementations into spec-conformant ones: `crypto/kyber` (FIPS 203 ML-KEM), `crypto/dilithium` (FIPS 204 ML-DSA), `crypto/sphincs_plus` (SLH-DSA shape), `crypto/hpke` (RFC 9180), `crypto/tls13` (RFC 8446 record layer + handshake), `crypto/threshold_sig` (Shamir + threshold Schnorr), `crypto/mpc` (BGW honest-majority), `crypto/fhe` (BFV), `crypto/bulletproofs`, `compression/paq`, `containers/mass_tree`, `containers/counted_btree`
- Independent-review fixes (P3-88): ML-DSA `SampleInBall` sign-bit extraction (32-bit aliasing on wasm32), ML-DSA `ExpandS` rejection sampling, continuous SHAKE XOF streams in ML-KEM/ML-DSA sampling, constant-time ML-KEM implicit-rejection comparison, TLS 1.3 sequence-number reset at key change (RFC 8446 §5.3)
- Proof fixes: removed Why3 reserved-word conflict (`val` parameter in `math/array_sum`), corrected the `divides` predicate and dropped an unprovable divisibility goal in `number_theory/gcd`, honest axiomatized index-bound lemma for `math/matrix::transpose_int`, structural postcondition for `trees/red_black_tree::size`
- Migrated 151 deprecated `StringBuilder::new()` call sites to `StringBuilder()` across 66 files (0 warnings under the pinned toolchain)
- CI: pinned MoonBit to 0.1.20260819, per-job timeouts, CodeQL switched to GitHub Actions analysis

#### Formally verified packages (9 Verified tier; 17 packages pass `moon prove`)
- `binary_search`, `linear_search`, `max_element`, `min_element`, `is_sorted` — full correctness proofs via `moon prove` (Why3 + Z3)
- `array_sum`, `gcd`, `fast_power`, `dijkstra` — partial verification (non-negativity / bounds safety; nonlinear properties documented as unproven)

#### Sorting (13 packages)
- `insertion_sort`, `selection_sort`, `merge_sort`, `quick_sort` — generic `FixedArray[T]` + comparator
- `heap_sort`, `counting_sort`, `radix_sort`, `timsort`, `introsort`, `pdq_sort`, `bucket_sort`, `external_sort`
- `is_sorted` (verified)

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

#### Containers (30 packages)
- `binary_heap`, `hash_table`, `lru_cache`, `ttl_cache`, `w_tinylfu`, `bloom_filter`, `cuckoo_filter`
- `count_min_sketch`, `hyperloglog`, `union_find`, `priority_queue`, `monotonic`, `bitset`, `deque`
- `consistent_hash`, `crc`, `hash_utils`, `lsm_tree`, `roaring_bitmap`, `count_sketch`, `concurrent`
- `treiber_stack`, `mpmc_queue`, `concurrent_hash_map`, `work_stealing`, `lock_free_queue`
- `bimap` (bidirectional map), `counting_bloom` (counting Bloom filter), `cuckoo_hashmap` (cuckoo hash table), `skip_list` (probabilistic skip list)

#### Graph (43 packages)
- `bfs_dfs`, `adj_list`, `topological_sort`, `topological_sort_adj`, `kruskal`, `prim`, `scc`, `dijkstra`, `dijkstra_heap`
- `johnson`, `bidirectional_bfs`, `a_star`, `max_flow`, `advanced` (Bellman-Ford + Floyd-Warshall), `min_cost_flow`
- `two_sat`, `dinic`, `lca`, `bridge_articulation`, `euler_path`, `hungarian`, `hopcroft_karp`, `stoer_wagner`
- `max_clique`, `edmonds_blossom`, `dominator_tree`, `gomory_hu`, `hlpp`, `hld`, `centroid_decomposition`
- `virtual_tree`, `min_steiner_tree`, `graph_coloring`, `flow_with_bounds`, `pagerank`, `chu_liu`
- `k_shortest_paths`, `min_cost_flow`, `tree_isomorphism`, `graph_utils` (shared graph utilities)
- `push_relabel` (max flow via push-relabel), `planar_test` (planarity testing), `isomorphism` (VF2 graph isomorphism)

#### String (22 packages)
- `kmp`, `rabin_karp`, `suffix_array`, `z_function`, `manacher`, `aho_corasick`, `boyer_moore`, `lcp_array`
- `suffix_automaton`, `suffix_tree`, `palindromic_tree`, `rolling_hash`, `lyndon`, `fm_index`, `wavelet_tree`
- `regex`, `dawg`, `sa_is`, `bwt`, `suffix_balanced_tree`
- `unicode_normalization` (NFC/NFD/NFKC/NFKD), `encoding_conversion` (UTF-8/UTF-16/GBK)

#### Number Theory (23 packages)
- `gcd` (partial verified), `fast_power` (partial verified), `int64_utils`, `prime`, `miller_rabin`, `crt`
- `bsgs`, `pollard_rho`, `euler_sieve`, `ntt`, `bigint`, `cipolla`, `finite_field`, `mobius`
- `polynomial`, `primitive_root`, `quadratic_residue`, `reed_solomon`, `pohlig_hellman`
- `carmichael` (Carmichael function), `aks` (AKS deterministic primality), `quadratic_sieve` (quadratic sieve factoring), `lehman_factor` (Lehman factoring)

#### Math (25 packages)
- `array_sum` (partial verified), `combinatorics`, `matrix`, `matrix_decomp`, `newton_method`, `berlekamp_massey`
- `fft`, `simplex`, `fwht`, `numerical_integration`, `ode_solver`, `interpolation`, `least_squares`
- `special_functions`, `conjugate_gradient`, `gmres`, `lbfgs`, `autodiff`, `sparse_matrix`
- `eigenvalue` (Jacobi eigenvalue decomposition), `qr_pivoting` (column-pivoted QR), `groebner` (Gröbner basis via Buchberger), `polynomial_factor` (polynomial factorization), `ilp` (integer linear programming), `sdp` (semidefinite programming)

#### Geometry (19 packages)
- `convex_hull`, `andrew_hull`, `convex_hull_3d`, `half_plane_intersection`, `kd_tree`, `rotating_calipers`
- `closest_pair`, `segment_ops`, `delaunay`, `voronoi`, `dynamic_hull`, `min_enclosing_circle`
- `minkowski_sum`, `polygon_boolean`, `segment_intersection`, `point_in_polygon`, `polygon_ops`
- `bentley_ottmann`, `geometry_utils` (shared geometry primitives)

#### Dynamic Programming (16 packages)
- `dp`, `lis`, `interval_dp`, `tree_dp`, `digit_dp`, `aliens_trick`, `knapsack_opt`, `matrix_chain`
- `monotone_queue_dp`, `smawk`, `bitmask_dp`, `convex_hull_trick`, `divide_conquer_dp`, `knuth_opt`
- `plug_dp`, `sos_dp`

#### Game Theory (7 packages)
- `nim_sg`, `alpha_beta`, `mcts`, `gale_shapley`, `shapley_value`
- `negamax` (negamax search with alpha-beta pruning), `transposition_table` (Zobrist hashing)

#### Random (10 packages)
- `reservoir_sampling`, `weighted_sampling`, `fisher_yates`, `mersenne_twister`, `pcg`, `xoshiro`
- `gaussian_sampling`, `zobrist_hash`, `mcmc`, `monte_carlo`

#### Crypto (55 packages)
- `sha256`, `sha512`, `sha3`, `sha1`, `blake2`, `blake3`, `hmac`, `chacha20`, `chacha20_poly1305`, `poly1305`
- `xchacha20` (extended-nonce ChaCha20 via HChaCha20)
- `hkdf`, `pbkdf2`, `scrypt`, `bcrypt`, `argon2` (RFC 9106), `aes` (constant-time S-box), `aes_ccm` (AES-CCM AEAD), `rsa` (OAEP/PSS, CRT, constant-time unpadding), `csprng` (CTR_DRBG)
- `ecdsa` (P-256, RFC 6979), `ecdsa_p384_p521`, `ecdsa_der`, `ed25519` (RFC 8032), `ed448_x448`, `x25519` (RFC 7748), `secp256k1` (BIP-340 Schnorr), `dsa`
- Post-quantum: `kyber` (FIPS 203 ML-KEM), `dilithium` (FIPS 204 ML-DSA), `sphincs_plus` (SLH-DSA shape)
- Pairing-based: `pairing` (BLS12-381), `bls_signature` (hash-to-curve, RFC 9380)
- Protocols & advanced: `hpke` (RFC 9180), `tls13` (RFC 8446), `jose` (JWT/JWS), `x509`, `asn1` (DER), `threshold_sig`, `mpc` (BGW), `fhe` (BFV), `bulletproofs`, `merkle_tree`
- Encoding: `base64`, `base32`, `hex`

#### Compression (16 packages)
- `huffman`, `lz4` (block + frame format), `lz77`, `lzw`, `arithmetic_coding`, `bwt_compress`, `deflate` (RFC 1951 incl. dynamic Huffman), `gzip` (RFC 1952), `zlib` (RFC 1950), `snappy`
- `lzma` (LZMA + xz container), `bzip2` (full format), `ans` (rANS + tANS), `paq` (context mixing)
- `zstd`, `brotli` — zstd/brotli-**inspired custom formats** (custom magic, explicitly documented as NOT RFC 8478 / RFC 7932 compatible)

#### Machine Learning (31 packages)
- `kmeans`, `knn`, `dbscan`, `pca`, `svm` (4 kernels + one-vs-rest multiclass), `logistic_regression`, `decision_tree`
- `random_forest` (classification + regression + OOB), `gradient_boosting` (GBDT), `adaboost` (AdaBoost SAMME)
- `mlp` (Adam + dropout), `gmm` (EM), `hierarchical_clustering` (agglomerative), `mean_shift`, `spectral_clustering`, `optics`
- `gaussian_process` (GP regression), `naive_bayes`, `isolation_forest`, `cnn` (educational-scale)
- `preprocessing` (StandardScaler/MinMaxScaler/OneHotEncoder), `model_selection` (train/test split, K-Fold CV), `model_evaluation` (classification + regression metrics)

#### Statistics (9 packages)
- `descriptive`, `linear_regression`, `hypothesis_testing`, `correlation`, `confidence_interval`, `bootstrap`, `distributions`
- `anova` (one-way/two-way ANOVA), `nonparametric` (Mann-Whitney/Wilcoxon/Kruskal-Wallis)

#### Serialization (7 packages)
- `json`, `msgpack`
- `csv` (RFC 4180), `toml` (TOML 1.0.0), `yaml` (YAML 1.1 subset), `cbor` (RFC 8949), `protobuf` (Protocol Buffers wire format)

#### Time (1 package)
- `chrono`

#### Utilities (4 packages)
- `utils` (swap, str_cmp, next_pow2, encoding, approx_eq, fresh_seed)
- `prng` (SplitMix64, XorShift64, LCG)
- `itertools` (range, repeat, enumerate, window, chunk, fold)
- `structured_logging` (structured key-value logging), `error_chain` (error context chaining)

#### Finance (15 packages)
- `black_scholes` (pricing + implied volatility), `portfolio_optimization` (Markowitz + Black-Litterman), `risk_management` (VaR/CVaR/stress testing), `greeks`
- `time_series` (ARIMA with Hannan-Rissanen MA estimation, GARCH, ADF), `execution` (TWAP/VWAP/IS), `backtest` (event-driven)
- `monte_carlo_var` (GBM + Merton jump-diffusion + multi-asset), `heston` (Fourier inversion + QE discretization), `sabr` (Hagan + Obłój), `local_vol` (Dupire)
- `interest_rate_models` (Vasicek/CIR/Hull-White), `xva`

#### Additional domains
- `consensus/` — `raft` (leader election + log replication), `gossip`, `crdt` (6 CvRDTs)
- `db/` — `wal`, `mvcc`, `query_planner`, `join`
- `net/` — `dns` and networking helpers
- `optimization/` — `tabu_search`, `genetic_algorithm`, `branch_and_bound`, `tsp` (Christofides + LK), simulated annealing and more
- `serialization/` additions — `avro`, `thrift`, `flatbuffers`
- `signal_processing/` — filter design (FIR/IIR), spectral analysis, wavelets (DWT)
- `audio_processing/` — WAV codec + MFCC features
- `image_processing/` — convolution, edge detection (Canny), morphology, Otsu thresholding
- `nlp/text_processing` — tokenization, n-grams, TF-IDF
- `bioinformatics/sequence_alignment` — Needleman-Wunsch, Smith-Waterman, Gotoh affine gaps

#### Test Infrastructure
- `test/property_test` — QuickCheck-style property-based testing framework
- `test/fuzz` — adversarial-input fuzz tests
- `test/stress` — large-scale stress tests
- `test/test_utils` — shared test utilities
- `test/coverage` — test coverage reporting
- `benchmarks/` — performance benchmarks with complexity verification

#### CI/CD
- GitHub Actions CI: `moon check --deny-warn` + `moon fmt --check` + `.mbti` freshness + `moon test` on Ubuntu/macOS/Windows, `moon prove` on Ubuntu (MoonBit 0.1.20260819 pinned, per-job timeouts)
- CodeQL security analysis (GitHub Actions workflows)
- Dependency review
- Nightly builds with flaky test detection (3 iterations)
- Benchmark regression detection with baseline comparison (25% threshold)
- Release workflow with SHA256 checksums

#### Type safety
- All magic values eliminated in favor of `Option`/`SPResult` types
- ~30 public functions migrated from `abort()` to `Option` returns; production code has no `.unwrap()` calls
- Overflow protection via Int64 for critical algorithms (systematic 32-bit wasm32 audit of crypto modular arithmetic)
- Self-balancing trees (AVL, RB-tree, BTree, Treap) rely on structural invariants for O(log n) recursion depth instead of arbitrary depth limits

#### Code quality
- `swap` centralized in `@utils` (was duplicated 7 times)
- `SplitMix64`/`XorShift64` centralized in `@utils/prng` (was duplicated across multiple packages)
- Per-instance random seeds via `@utils.fresh_seed()` (replaces global fixed seed)
- `bloom_filter` reused by `lsm_tree` (was reimplemented)
- `binary_heap` reused by `external_sort` (was reimplemented)
