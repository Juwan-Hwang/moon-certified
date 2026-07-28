/// Coverage smoke test — imports and exercises one public function from every
/// package that is not otherwise imported by a test or benchmark target.
///
/// This ensures that:
/// 1. Every package compiles successfully in the **library** target (not just test).
/// 2. A `pkg.generated.mbti` interface file is generated for every package,
///    making it importable by downstream users.
/// 3. Basic sanity (no crash on trivial input) is verified.

///|
/// Minimal game for alpha_beta smoke test.
priv struct TrivialGame {
  done : Bool
}

///|
impl @alpha_beta.Game for TrivialGame with fn is_terminal(self) {
  self.done
}

///|
impl @alpha_beta.Game for TrivialGame with fn evaluate(_) {
  0
}

///|
impl @alpha_beta.Game for TrivialGame with fn generate_moves(_) {
  []
}

///|
impl @alpha_beta.Game for TrivialGame with fn make_move(_, _m) {
  { done: true }
}

///|
impl @alpha_beta.Game for TrivialGame with fn current_player(_) {
  0
}

///|
pub fn smoke_test() -> Unit {
  // compression
  ignore(@huffman.build_tree("hello"))
  ignore(@lz4.compress(b"hello"))
  ignore(@lz77.compress(b"hello"))
  ignore(@lzw.compress(b"hello"))
  ignore(@deflate.deflate(b"hello"))

  // containers
  ignore(@bitset.bitset_new(64))
  ignore(@count_sketch.new(100, 5, fn(s) { @hash_utils.poly31_hash(s) }))
  let _chm : @concurrent_hash_map.ConcurrentHashMap[Int, Int] = @concurrent_hash_map.concurrent_hash_map_new(
    16,
    fn(k) { k },
    fn(a, b) { a == b },
  )
  ignore(@consistent_hash.new())
  let _dq : @deque.Deque[Int] = @deque.deque_new()
  ignore(@hash_utils.fmix64(42L))
  let _mpmc : @mpmc_queue.MPMCQueue[Int] = @mpmc_queue.mpmc_queue_new(8)
  ignore(@roaring_bitmap.roaring_create())
  let _ts : @treiber_stack.TreiberStack[Int] = @treiber_stack.treiber_stack_new(
    8,
  )
  let _ws : @work_stealing.WorkStealingDeque[Int] = @work_stealing.ws_deque_new(
    8,
  )

  // crypto
  ignore(
    @aes.new_key(FixedArray::make(16, b'\x00')).map(fn(k) {
      @aes.encrypt_block(k, FixedArray::make(16, b'\x00'))
    }),
  )
  ignore(@base64.encode(FixedArray::make(0, b'\x00')))
  ignore(
    @chacha20.create_cipher(
      b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
      b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    ),
  )
  ignore(@hkdf.hkdf(b"ikm", b"salt", b"info", 32))
  ignore(@hmac.hmac_sha256(b"key", b"msg"))
  ignore(@pbkdf2.pbkdf2_sha256(b"pass", b"salt", 1, 32))
  ignore(@poly1305.poly1305(b"key", b"msg"))
  ignore(@sha256.sha256(b"hello"))
  ignore(@sha3.sha3_256(b"hello"))
  ignore(@sha512.sha512(b"hello"))

  // dp
  ignore(@aliens_trick.aliens_trick(3, [1, 2, 3], 2))
  ignore(@knapsack_opt.multiple_knapsack([1, 2], [3, 4], [1, 1], 3))
  ignore(@matrix_chain.matrix_chain_order([10, 20, 30]))
  ignore(@matrix_chain.matrix_chain_parenthesization([10, 20, 30]))
  ignore(@monotone_queue_dp.sliding_window_max([1, 3, 2, 5, 4], 3))
  ignore(@plug_dp.PlugState::new([0, 1, 2]))
  ignore(@smawk.smawk_matrix([FixedArray::make(3, 0)]))

  // game_theory
  ignore(@alpha_beta.alpha_beta({ done: false }, 1, -1000, 1000))
  ignore(@gale_shapley.stable_matching(1, [[0]], [[0]]))
  ignore(@mcts.new(42))
  ignore(@shapley_value.shapley_exact(fn(_) { 0.0 }, 2))

  // geometry
  ignore(@bentley_ottmann.find_intersections([(0.0, 0.0, 1.0, 1.0)]))
  ignore(@min_enclosing_circle.min_enclosing_circle([(0.0, 0.0), (1.0, 0.0)]))
  ignore(@minkowski_sum.minkowski_sum([(0, 0), (1, 0)], [(0, 0), (0, 1)]))
  ignore(@point_in_polygon.point_in_polygon(0, 0, [(0, 0), (1, 0), (0, 1)]))
  ignore(
    @polygon_ops.sutherland_hodgman([(0, 0), (1, 0), (0, 1)], [
      (0, 0),
      (1, 0),
      (1, 1),
      (0, 1),
    ]),
  )
  ignore(@segment_intersection.segments_intersect(0, 0, 1, 1, 0, 1, 1, 0))
  ignore(
    @polygon_boolean.intersection(
      [
        @polygon_boolean.ipoint(0, 0),
        @polygon_boolean.ipoint(2, 0),
        @polygon_boolean.ipoint(2, 2),
        @polygon_boolean.ipoint(0, 2),
      ],
      [
        @polygon_boolean.ipoint(1, 1),
        @polygon_boolean.ipoint(3, 1),
        @polygon_boolean.ipoint(3, 3),
        @polygon_boolean.ipoint(1, 3),
      ],
    ),
  )

  // graph
  ignore(@chu_liu.min_arborescence(2, [(0, 1, 5)], 0))
  ignore(
    @k_shortest_paths.k_shortest_paths(
      2,
      [[@k_shortest_paths.k_edge(1, 1)]],
      0,
      1,
      1,
    ),
  )
  ignore(
    @network_simplex.min_cost_flow(
      2,
      FixedArray::make(1, 0),
      FixedArray::make(1, 1),
      FixedArray::make(1, 1),
      FixedArray::make(1, 1),
      FixedArray::make(2, 0),
    ),
  )
  ignore(@tree_isomorphism.are_trees_isomorphic(2, [(0, 1)], [(0, 1)]))

  // math
  ignore(@fwht.fwht([1.0, 0.0]))
  ignore(@interpolation.lagrange_interpolate([(0.0, 0.0), (1.0, 1.0)], 0.5))
  ignore(@least_squares.linear_fit([(0.0, 0.0), (1.0, 1.0)]))
  ignore(@numerical_integration.trapezoidal(fn(_) { 1.0 }, 0.0, 1.0, 10))
  ignore(@ode_solver.rk4(fn(_, _) { 1.0 }, 0.0, 0.0, 1.0, 10))
  ignore(@special_functions.gamma(5.0))
  ignore(@sparse_matrix.from_triplets(2, 2, [(0, 0, 1.0), (1, 1, 1.0)]))

  // ml
  ignore(@kmeans.kmeans([[0.0, 0.0], [1.0, 1.0]], 2, 10))
  ignore(@dbscan.dbscan([], 1.0, 1))
  ignore(@decision_tree.new(3, 2))
  ignore(@knn.knn_classify([], [1.0], 1))
  ignore(@logistic_regression.new(0.1, 1))
  ignore(@pca.pca([], 1))

  // number_theory
  ignore(@bigint.from_int_value(42))
  ignore(@cipolla.cipolla(10, 13))
  ignore(@pohlig_hellman.pohlig_hellman(2, 3, 5))

  // random
  ignore(@fisher_yates.make_lcg(42))
  ignore(@gaussian_sampling.box_muller(fn() { 0.5 }))
  ignore(@mcmc.metropolis_hastings(fn(_) { 1.0 }, 0.0, 10, 1.0, fn() { 0.5 }))
  ignore(@mersenne_twister.new(42U))
  ignore(@monte_carlo.XorShift64::new(42L))
  ignore(@pcg.new(42UL, 54UL))
  ignore(@xoshiro.new(42UL))
  ignore(@zobrist_hash.new(19))

  // search
  ignore(@fibonacci_search.fibonacci_search([1, 2, 3], 2))
  ignore(@jump_search.jump_search([1, 2, 3], 2))
  ignore(@quickselect.quickselect([3, 1, 2], 0))
  ignore(@hnsw.new(4, 16))

  // sorting
  ignore(@bucket_sort.bucket_sort([1.0, 2.0], 0.0, 3.0))
  let xs_introsort : FixedArray[Int] = FixedArray::make(5, 0)
  @introsort.sort_int(xs_introsort)
  let xs_pdq : Array[Int] = [3, 1, 2]
  @pdq_sort.pdq_sort_int(xs_pdq)
  let xs_tim : FixedArray[Int] = FixedArray::make(5, 0)
  @timsort.sort_int(xs_tim)

  // stats
  ignore(@descriptive.mean([1.0, 2.0, 3.0]))
  ignore(@hypothesis_testing.confidence_interval_95([1.0, 2.0, 3.0]))
  ignore(@linear_regression.fit_linear([0.0, 1.0], [0.0, 1.0]))

  // string
  ignore(@bwt.bwt_encode("banana"))
  ignore(@dawg.new())
  ignore(@sa_is.sa_is([1, 2, 3]))

  // trees
  ignore(@fibonacci_heap.fib_heap_new())
  ignore(@interval_tree.new())
  ignore(@persistent_segment_tree.new(100))
  ignore(@r_tree.rtree_new(16))
  ignore(@range_tree.new())
  ignore(@rope.rope_leaf("hello"))

  // utils
  ignore(@utils.str_cmp("a", "b"))
  ignore(@utils.SplitMix64::new(42UL).next_u64())
  ignore(@utils.XorShift64::new(42UL).next_u64())
  ignore(@itertools.collect(@itertools.range(0, 5)))
}

///|
test "coverage: all packages compile and generate mbti" {
  smoke_test()
  assert_true(true)
}
