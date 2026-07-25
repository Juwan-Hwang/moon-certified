# API Stability Policy

**Project:** moon-certified — Formally verified core algorithms and data structures for MoonBit
**Repository:** https://github.com/Juwan-Hwang/moon-certified
**License:** Apache-2.0
**Current released version:** 0.10.0
**Document version:** 1.0
**Last updated:** 2026-07-25

---

## Table of Contents

1. [Purpose and Scope](#1-purpose-and-scope)
2. [API Stability Policy](#2-api-stability-policy)
   - [2.1 Semantic Versioning Compliance](#21-semantic-versioning-compliance)
   - [2.2 Public vs. Private API Distinction](#22-public-vs-private-api-distinction)
   - [2.3 Stability Tiers](#23-stability-tiers)
3. [Deprecation Policy](#3-deprecation-policy)
4. [Migration Guide](#4-migration-guide)
5. [Breaking Change Protocol](#5-breaking-change-protocol)
6. [Package Categorization](#6-package-categorization)
7. [Testing Guarantee](#7-testing-guarantee)
8. [Appendix A: Version History Summary](#appendix-a-version-history-summary)
9. [Appendix B: Overflow Safety Contract](#appendix-b-overflow-safety-contract)

---

## 1. Purpose and Scope

This document defines the API stability commitments that `moon-certified` makes to
its consumers. `moon-certified` is a MoonBit library of core algorithms and data
structures — sorting, searching, trees, graphs, strings, number theory, geometry,
dynamic programming, and containers — a subset of which are **formally verified**
with MoonBit 0.9's `moon prove` (Why3 + Z3 SMT solver).

Because the library is intended as a dependable foundation for downstream
MoonBit projects (including as a candidate for standard-library-level use), API
stability is not a courtesy but a contract. This document specifies:

- what is considered part of the public API,
- which stability tier each package belongs to,
- how breaking changes are versioned and communicated,
- how deprecations and removals are handled,
- how to migrate across the historical breaking boundaries, and
- the testing guarantees that back every stability claim.

**Scope.** This policy applies to all packages published under the
`moon-certified` module. It does not cover the formal-verification toolchain
itself (MoonBit, Why3, Z3), whose behaviour is governed by their own projects.

**Verification status disclaimer.** Formal verification models `Int` as
mathematical integers, while the runtime `Int` is a 32-bit signed integer.
Stability of the *contract* does not imply absence of integer overflow at
runtime; see [Appendix B](#appendix-b-overflow-safety-contract) for the full
overflow safety contract.

---

## 2. API Stability Policy

### 2.1 Semantic Versioning Compliance

`moon-certified` adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).
The version string `MAJOR.MINOR.PATCH` is interpreted as follows:

| Version component | Bumped when | Backwards compatibility |
|-------------------|-------------|-------------------------|
| `MAJOR` | A breaking change to the public API is introduced. | **No** compatibility guarantee across a major boundary. |
| `MINOR` | New functionality is added in a backwards-compatible manner: new packages, new public functions, new types, performance improvements, new verification results. | **Full** backwards compatibility. Code targeting `0.x.y` continues to compile and behave identically on `0.x.(y+1)`. |
| `PATCH` | Backwards-compatible bug fixes, documentation improvements, test additions, or internal refactors with no observable behaviour change. | **Full** backwards compatibility, including identical observable output. |

**Pre-1.0 caveat.** The project is currently in the `0.x` series. Under SemVer,
`0.x` releases may, in principle, contain breaking changes in a minor bump.
`moon-certified` nonetheless treats `0.x` minor releases as if they were `1.x`
minor releases: **breaking changes require a major version bump even before
1.0**, and minor releases are reserved for backwards-compatible additions.
Historical breaking changes (see [Section 4](#4-migration-guide)) were confined
to the `0.2`–`0.5` window during early stabilisation and were each accompanied
by a migration guide; no breaking changes have been introduced since `0.5.0`.

**Versioning of verified contracts.** When a package's formal-verification
contract (its `proof_require` / `proof_ensure` / `proof_invariant` annotations
and `.mbtp` predicate definitions) changes, the change is treated as a public
API change: strengthening a contract is a *minor* bump; weakening or removing a
proven property is a *major* bump. Verified packages are subject to the
[Verified tier](#verified-tier) rules in addition to the standard SemVer rules.

### 2.2 Public vs. Private API Distinction

The public API of `moon-certified` is precisely the set of declarations
explicitly marked with the `pub` keyword at the top level of a package. Anything
not marked `pub` is private implementation detail and may change without notice,
without a version bump, and without a changelog entry.

| MoonBit declaration | Public API? | Stability guarantee |
|---------------------|-------------|---------------------|
| `pub fn name(...) -> ...` | **Yes** | Covered by this policy. |
| `pub struct Name { ... }` (the type itself) | **Yes** | Covered by this policy. |
| `pub enum Name { ... }` | **Yes** | Covered by this policy. |
| `pub type Name` / `pub typealias Name` | **Yes** | Covered by this policy. |
| Fields marked `priv` inside a `pub struct` | **No** | Private; encapsulated. |
| `fn name(...)` (no `pub`) | **No** | Private helper. |
| `struct Name` / `enum Name` (no `pub`) | **No** | Private internal type. |
| `const NAME` / `let name` (no `pub`) | **No** | Private constant. |
| `.mbt` test blocks (`test "..." { ... }`) | **No** | Not part of the API. |
| `.mbtp` predicate/lemma definitions | **No** (internal to verification) | May be restructured freely; only the *proven properties* they establish are part of the contract. |

**Encapsulation policy.** As of `v0.9.0`, all struct fields across
`binary_heap`, `hash_table`, `bloom_filter`, `btree`, `treap`, `lru_cache`,
`skip_list`, `trie`, `monotonic`, `priority_queue`, `segment_tree_lazy`, and
`suffix_automaton` were made `priv`. Consumers interact with these types
exclusively through their public methods, which preserves internal invariants
(e.g., the heap property, hash-table load factor, RB-tree balance). Direct field
access is **not** part of the public API and is blocked by the type system.

**Generated interface files.** The `pkg.generated.mbti` files in each package
are machine-generated by `moon info` and represent the *current* public surface.
They are authoritative for "what is public today" but are not themselves a
stability commitment beyond what this policy states.

### 2.3 Stability Tiers

Every package in `moon-certified` is assigned to exactly one of three stability
tiers. The tier governs the strength of the compatibility guarantee and is
declared per-package. A package may be **promoted** to a higher tier (Experimental
→ Stable → Verified) but is **never demoted** within a minor version; a demotion
requires a major version bump and a migration guide.

#### Verified tier

A package whose correctness is established by a machine-checked formal proof via
`moon prove` (Why3 + Z3), with `"proof-enabled": true` in its `moon.pkg.json`.

- **Guarantee.** The proven properties hold for **all** legal inputs, not merely
  tested inputs. The proof contract (preconditions, postconditions, loop
  invariants) is an **immutable part of the API**.
- **Change rules.**
  - The *signature* of a verified function may only change in a **major**
    version. Within the same major version, the signature is frozen.
  - The *contract* (proven postconditions) may be **strengthened** in a minor
    version (proving more than before) but may **never be weakened or removed**
    without a major version bump. Weakening a proven property is, by definition,
    a regression of a guaranteed behaviour.
  - A function may not move *out* of the Verified tier (lose its proof) without a
    major version bump.
- **Honesty labelling.** Verification depth is reported honestly. A package may
  be Verified yet only **partially** verified (e.g., non-negativity is proven but
  full correctness is not, because it requires nonlinear arithmetic reasoning
  beyond Z3's automatic capability). The exact set of proven properties is
  documented per-package and is part of the contract.

#### Stable tier

A package that is not formally verified but ships with comprehensive test
coverage and whose public API is considered settled.

- **Guarantee.** No breaking changes to the public API within a minor version.
  Signatures, public type shapes, and observable semantics are frozen for the
  major version. New functionality may be added; existing functionality will not
  be removed or re-shaped.
- **Change rules.** Behaviour-preserving refactors, performance improvements,
  and bug fixes are permitted freely (subject to [Section 5](#5-breaking-change-protocol)).
  A Stable package may be promoted to Verified when a proof is added; this is a
  non-breaking minor bump.
- **Coverage requirement.** Every public function has at least one functional
  test, plus stress and/or fuzz coverage where applicable (see
  [Section 7](#7-testing-guarantee)).

#### Experimental tier

A package that is newly added and whose API is still settling. These packages
implement advanced or niche algorithms whose interfaces may be refined based on
real-world usage before being frozen.

- **Guarantee.** **None** with respect to API shape. The package is correct (it
  passes the full test suite) but its signatures, return types, and naming may
  change in any minor version.
- **Change rules.** Experimental packages may receive breaking changes in a
  minor bump. Such changes are still recorded in the changelog with a clear
  `BREAKING` marker and, where the API is non-trivial, a short migration note.
- **Promotion.** An Experimental package is promoted to Stable after it has
  shipped in at least one released minor version with no API churn and has
  complete test coverage. The promotion itself is a non-breaking documentation
  change (patch or minor bump).

---

## 3. Deprecation Policy

When a public API element must eventually be removed, it is first **deprecated**.
Removal never happens without a deprecation period.

### 3.1 Deprecation lifetime

- A deprecated public function, type, or enum variant **remains available for at
  least two minor versions** following the version in which it was deprecated,
  before it may be removed.
- Removal occurs in a **major** version bump. A deprecated element is never
  removed in a minor or patch release.
- During the deprecation window, the element continues to compile and behave
  exactly as before — deprecation is advisory, not a behavioural change.

Worked example: if `foo` is deprecated in `0.11.0`, it remains in `0.11.x` and
`0.12.x` and may be removed no earlier than `1.0.0`.

### 3.2 The `@deprecated` annotation plan

MoonBit does not yet provide a first-class `@deprecated` annotation with
compiler-emitted warnings. `moon-certified` uses the following conventions in the
interim:

- **Documentation-based deprecation.** The doc-comment of a deprecated element
  begins with `/// DEPRECATED:` followed by the version of deprecation, the
  recommended replacement, and a one-line reason. Example (from `fast_power`):

  ```moonbit
  /// DEPRECATED (since v0.9.0): prefer `fast_power_checked`, which returns
  /// `Int?` and detects Int32 overflow. `fast_power` silently wraps on overflow.
  pub fn fast_power(base : Int, exp : Int) -> Int { ... }
  ```

- **Changelog marking.** Every deprecation is recorded in `CHANGELOG.md` under a
  `Deprecated` sub-section of the releasing version, naming the element, the
  replacement, and the earliest removal version.

- **Future compiler integration.** When MoonBit introduces a `@deprecated`
  attribute (or an equivalent lint), all existing documentation-based
  deprecations will be upgraded to the compiler attribute in a single patch
  release. This is a non-breaking change because the attribute only adds a
  warning; it does not alter behaviour or signatures.

### 3.3 Migration guides for breaking changes

Every breaking change — whether in a major version or in an Experimental package
within a minor version — is accompanied by:

1. A `BREAKING` entry in `CHANGELOG.md` describing the old and new API.
2. A concrete before/after code snippet.
3. The rationale (why the change is necessary).
4. A pointer to the replacement API, if any.

The historical breaking changes and their migrations are documented in
[Section 4](#4-migration-guide).

---

## 4. Migration Guide

This section catalogues the key API migrations in the project's history. Only
changes that affected the public API are listed; internal refactors are omitted.

### v0.3.0 (2024-12-01) — Elimination of magic values

**Theme.** Sentinel values (`-1`, empty arrays) used to signal "not found" or
"invalid input" were replaced with `Option` types and a dedicated `SPResult`
enum. This was the project's largest breaking change to return-type semantics.

| Package | Old return | New return | Migration |
|---------|-----------|-----------|-----------|
| `dijkstra` | `FixedArray[Int]` with `-1` meaning "unreachable" | `FixedArray[Int?]` with `None` meaning "unreachable" | Replace `if dist[i] == -1` with `match dist[i] { Some(d) => ...; None => ... }`. |
| `bound_search` | `-1` on empty array | `0` (equals array length; semantically consistent) | Remove `-1` checks on empty input; the result is now always a valid index in `[0, len]`. |
| `mod_inverse` | `-1` when no inverse exists | `Int?` (`None` = no inverse or invalid input) | Replace `if r == -1` with `match r { Some(inv) => ...; None => ... }`. |
| `union_find.find` | `-1` on out-of-bounds index | `Int?` (`None` = out of bounds) | Replace `if r == -1` with `match r { Some(root) => ...; None => ... }`. |
| `bellman_ford` / `floyd_warshall` (`advanced`) | empty array or `-1` | `SPResult?` | `None` = invalid input; `Some(NegativeCycle)` = negative cycle detected; `Some(Distances(arr))` = success, where `arr` is `FixedArray[Int?]`. |
| `topological_sort` | empty array on cycle | `FixedArray[Int]?` (`None` = cycle or invalid input) | Replace length-zero checks with `Option` matching. |
| `bfs_distances` | empty array on invalid input | `FixedArray[Int]?` (`None` = invalid input; `-1` retained *only* as the BFS "unreachable" hop marker, since hop count is always ≥ 0) | Distinguish "invalid input" (`None`) from "unreachable node" (`Some(arr)` containing `-1`). |

The `SPResult` enum is now part of the public API of the `advanced` package:

```moonbit
pub enum SPResult {
  Distances(FixedArray[Int?])  // Some(d) = reachable, None = unreachable
  NegativeCycle                // a negative cycle was detected
}
```

**Why.** Magic values conflated valid results with error conditions (e.g., a
path of weight `-1` was indistinguishable from "no path"), making correct usage
error-prone. Algebraic types make failure modes explicit and unrepresentable
when mishandled.

### v0.5.0 (2026-07-23) — Int64 overflow protection

**Theme.** Critical algorithms whose intermediate computations can exceed the
32-bit `Int` range were upgraded to use `Int64` internally and to return
`Int64` (or `Option`) results that distinguish overflow / invalid input from
legitimate zero values.

| Package / function | Change | Migration |
|--------------------|--------|-----------|
| `dijkstra_heap` | Distances accumulated in `Int64`; returns `None` on overflow instead of a wrong result. | If you previously treated the result as `Int`, it is now `Int64?`; unwrap and convert with `.to_int()` only after confirming the value fits. |
| `convex_hull` (and `andrew_hull`) | Cross products computed in `Int64` to prevent overflow for large coordinates. | No signature change for the public `convex_hull` entry point; the protection is internal. Point coordinates remain `Int`. |
| `max_flow` | `total_flow` accumulated in `Int64`; returns `Int64?` (`None` = invalid input, `Some(0L)` = valid zero flow). | Replace equality checks against `0` with `Option` matching; `Some(0L)` is a *valid* result, distinct from `None`. |
| `dinic` | All capacities and flows use `Int64`; returns `Int64?`. | Same as `max_flow`: distinguish `None` (invalid) from `Some(0L)` (zero flow). |
| `min_cost_flow` | `total_flow` / `total_cost` accumulated in `Int64`; returns `(Int64, Int64)?`; SPFA negative-cycle detection added. | Result is now `(flow, cost)?`; `None` = invalid input or negative cycle. |
| `fast_power_checked` (new) | Returns `Int?` (`None` on overflow). | Prefer this over `fast_power` for untrusted exponents. |
| `gcd` | Safe handling of `Int::MIN` via `Int64`; only `gcd(Int::MIN, Int::MIN)` clamps to `Int::MAX`. | No action needed unless you relied on the old (buggy) `Int::MIN` behaviour. |

**Why.** Silent 32-bit overflow produced incorrect results for inputs that are
valid in the mathematical sense but exceed the machine integer range. The
`Int64` upgrades and `Option` returns make overflow an explicit, detectable
condition rather than a silent correctness bug.

### v0.9.0 (2026-07-24) — Shared `int64_utils` module extraction

**Theme.** Number-theory packages had each maintained private copies of `Int64`
modular-arithmetic helpers. These were extracted into a single shared
`int64_utils` package to eliminate duplication and ensure a single, tested,
overflow-correct implementation.

- **New public package:** `number_theory/int64_utils`, exporting:

  ```moonbit
  pub fn mod64(Int64, Int64) -> Int64       // non-negative modulo
  pub fn gcd64(Int64, Int64) -> Int64       // handles Int64::MIN correctly
  pub fn mul_mod(Int64, Int64, Int64) -> Int64
  pub fn pow_mod64(Int64, Int64, Int64) -> Int64
  pub fn is_prime64(Int64) -> Bool          // full Int64 range witness set
  ```

- **Affected packages:** `bsgs`, `crt`, `pollard_rho`, and `miller_rabin` now
  `import` `int64_utils` instead of carrying private copies.

- **Migration.** This was a **non-breaking** change for consumers of `bsgs`,
  `crt`, `pollard_rho`, and `miller_rabin`: their public signatures are
  unchanged. Consumers who had copied the private helpers should switch to
  `@int64_utils`. Two correctness fixes rode along with the consolidation:
  - `gcd64` no longer overflows on `Int64::MIN` (it runs the Euclidean algorithm
    on signed inputs and normalises at the end, rather than taking a buggy
    absolute value first).
  - `is_prime64`'s Miller-Rabin witness set was expanded from `{2, 7, 61}`
    (valid only for `n < 2³²`) to the 12-witness set
    `{2,3,5,7,11,13,17,19,23,29,31,37}` (valid for the full `Int64` range,
    per Sorenson & Webster, 2015).

### v0.10.0 (2026-07-25) — 27 new packages (non-breaking)

**Theme.** A large additive release. No existing public API was changed,
removed, or renamed. Test count rose from 1321 to 1599; package count rose from
86 to 113.

New packages spanned string algorithms (suffix tree, palindromic tree, rolling
hash, Lyndon decomposition), graph algorithms (Hopcroft-Karp, Stoer-Wagner,
Bron-Kerbosch max clique), tree structures (Link-Cut tree, persistent vector),
geometry (3D convex hull, half-plane intersection), mathematics (matrix
decompositions, Newton's method, Berlekamp-Massey, FFT, simplex), containers
(W-TinyLFU, cuckoo filter, HyperLogLog, TTL cache, Count-Min Sketch), digit DP,
Nim/Sprague-Grundy game theory, and reservoir sampling.

**Migration.** None required. Existing code continues to compile and behave
identically. New `import` paths are additive only.

### Unreleased / development branch — Experimental packages and fuzz testing

**Theme.** The development branch adds a new **Experimental** tier of packages
and a dedicated fuzz-test suite. These are correct (they pass `moon test`) but
their public APIs are not yet frozen.

New Experimental packages (10):

| Package | Domain | Summary |
|---------|--------|---------|
| `containers/concurrent` | Concurrency | `RingBuffer[T]`, `BoundedQueue[T]`, `SnapshotMap[K,V]` (copy-on-write). Designed for current single-threaded MoonBit with a forward path to lock-free primitives when multi-threading lands. |
| `graph/gomory_hu` | Graph theory | Gomory-Hu tree for all-pairs min-cut in O(n) max-flow computations. Built on `@max_flow`. |
| `graph/dominator_tree` | Graph theory | Lengauer-Tarjan dominator tree construction. |
| `graph/min_steiner_tree` | Graph theory | Minimum Steiner tree (NP-hard; exact for small terminal sets). |
| `graph/flow_with_bounds` | Graph theory | Maximum flow with lower and upper capacity bounds (circulation with demands). |
| `containers/lsm_tree` | Containers | Log-Structured Merge-tree (memtable + SSTable levels + compaction). |
| `string/fm_index` | String | FM-index for O(m) backward search and count over the BWT. |
| `string/wavelet_tree` | String | Wavelet tree for rank/select and range-count queries. |
| `number_theory/reed_solomon` | Number theory | Reed-Solomon error-correction coding over GF(2⁸) (encode + decode with up to ⌊(n−k)/2⌋ symbol corrections). |
| `sorting/external_sort` | Sorting | External merge sort for datasets larger than memory (in-memory simulation of run generation + k-way merge). |

New test infrastructure:

- `test/fuzz` — adversarial-input fuzz tests across sorting, data structures,
  graphs, strings, number theory, geometry, and concurrent structures. Uses a
  deterministic xorshift64 PRNG for reproducible failures.

**Migration.** None required for existing Stable/Verified code. Consumers who
adopt an Experimental package should be prepared for API changes in subsequent
minor versions until the package is promoted to Stable.

---

## 5. Breaking Change Protocol

This section defines what constitutes a breaking change, which version bump it
requires, and the process for releasing one.

### 5.1 Definition of a breaking change

A change is **breaking** if any of the following holds:

- **Signature change.** A public function's parameter count, parameter types,
  parameter order, or return type is altered. (Adding a *new* optional parameter
  is not yet expressible in MoonBit; therefore any parameter change is breaking.)
- **Removed function or type.** A `pub fn`, `pub struct`, `pub enum`, or `pub type`
  is deleted.
- **Changed semantics.** A public function's observable behaviour changes for any
  input that was previously legal, even if the signature is unchanged. This
  includes: changed return values, changed error conditions, changed complexity
  class in a way that breaks documented time bounds, and changed side effects.
- **Enum variant change.** A variant is removed from a `pub enum`, or the
  payload type of an existing variant changes. (Adding a new variant is
  non-breaking for exhaustive `match` only if MoonBit's exhaustiveness rules
  permit; otherwise it is treated as breaking and requires a major bump.)
- **Contract change for a Verified package.** A proven postcondition is weakened
  or removed (see [Verified tier](#verified-tier)).
- **Struct field exposure change.** A previously `pub` field is made `priv`, or
  a `priv` field is made `pub` (the latter is technically additive but changes
  the encapsulation contract; it is treated as a minor bump with a changelog
  note).

### 5.2 Definition of a non-breaking change

The following are **not** breaking and require at most a minor bump:

- Adding a new package.
- Adding a new `pub fn`, `pub struct`, `pub enum`, or `pub type`.
- Adding a new enum variant (subject to the caveat above).
- Performance improvements that preserve the documented complexity bound and
  observable output.
- Bug fixes that change incorrect output to correct output (a bug fix is never
  "breaking" of a *correct* contract; if callers relied on the buggy behaviour,
  this is noted in the changelog but does not block a patch/minor release).
- Strengthening a Verified contract (proving more than before).
- Internal refactors that leave the public surface and observable behaviour
  unchanged (patch bump).
- Documentation improvements (patch bump).

### 5.3 Version-bump decision table

| Change | Required bump | Changelog section |
|--------|--------------|-------------------|
| Signature change to a public function | Major | `BREAKING` |
| Removed public function / type | Major | `BREAKING` |
| Changed observable semantics | Major | `BREAKING` |
| Weakened/removed a Verified contract | Major | `BREAKING` |
| Removed enum variant | Major | `BREAKING` |
| New package | Minor | `Added` |
| New public function / type (non-breaking) | Minor | `Added` |
| Performance improvement (same complexity bound) | Minor | `Changed` |
| Strengthened Verified contract | Minor | `Changed` |
| Bug fix (incorrect → correct) | Patch | `Fixed` |
| Documentation improvement | Patch | `Changed` |
| Internal refactor (no observable change) | Patch | `Changed` |
| Deprecation of a public element | Minor | `Deprecated` |
| Removal of a long-deprecated element | Major | `Removed` |

### 5.4 Release process for a breaking change

1. **Open an issue** proposing the breaking change, with rationale and the
   proposed replacement API.
2. **Deprecate first** (where feasible): in the current minor version, mark the
   old API deprecated per [Section 3](#3-deprecation-policy) and introduce the
   new API alongside it.
3. **Bump the major version** in `moon.mod.json` and add a `BREAKING` section to
   `CHANGELOG.md` with before/after snippets.
4. **Update this document** if any tier assignments change.
5. **Ensure CI is green**: `moon check --deny-warn`, `moon test`, and `moon prove`
   must all pass on the release commit.

---

## 6. Package Categorization

The current development tree contains **152 algorithm packages** (excluding the
`test/` and `benchmarks/` infrastructure packages). Each is assigned to exactly
one stability tier. The released `v0.10.0` contained 113 packages; the
additional packages are in development and will appear in the next minor release.

### Verified tier (9 packages)

These packages have `"proof-enabled": true` and pass `moon prove` (9/9, 0
failures) under Why3 1.7.2 + Z3 4.12.x. Their proof contracts are immutable
within the major version.

| Package | Path | Verification depth | Proven property |
|---------|------|--------------------|-----------------|
| `binary_search` | `search/binary_search` | Full correctness | Returns the correct index when found; returns `None` when not found. |
| `linear_search` | `search/linear_search` | Full correctness | Returns the correct index or `None`. |
| `max_element` | `search/max_element` | Full correctness | The returned index points to a maximum element. |
| `min_element` | `search/min_element` | Full correctness | The returned index points to a minimum element. |
| `is_sorted` | `sorting/is_sorted` | Full correctness | Returns `true` ⇒ array is sorted; returns `false` ⇒ an inversion exists. |
| `dijkstra` | `graph/dijkstra` | Partial | Array bounds and result length are proven (`result.length() == n`). Shortest-path optimality is **not** proven (requires nonlinear arithmetic). One `proof_axiomatized` lemma (`graph_index_bound`) is honestly labelled as assumed, not proven. |
| `array_sum` | `math/array_sum` | Partial | Result is non-negative for non-negative inputs. Full correctness is **not** proven (nonlinear arithmetic). A tested `array_sum_checked` variant returns `Int?` to surface overflow. |
| `gcd` | `number_theory/gcd` | Partial | Result is non-negative for non-negative inputs. Divisibility and maximality are **not** proven. Handles `Int::MIN` via `Int64`. |
| `fast_power` | `number_theory/fast_power` | Partial | Result is non-negative for non-negative inputs. `base^exp` correctness is **not** proven. A tested `fast_power_checked` variant returns `Int?`. |

**Note on generics.** The generic companion functions (`search_generic[T]`,
`max_element_generic[T]`, `min_element_generic[T]`, `is_sorted_generic[T]`) are
**not** formally verified; only the `Int` versions carry proofs. The generic
versions are validated by testing only.

### Stable tier (133 packages)

All non-verified, non-experimental packages with comprehensive test coverage.
Their public APIs are frozen within the major version. This tier spans every
domain: sorting (`insertion_sort`, `merge_sort`, `quick_sort`, `heap_sort`,
`counting_sort`, `radix_sort`, `selection_sort`), search (`bound_search`,
`interpolation_search`, `exponential_search`, `ternary_search`, `ball_tree`,
`vp_tree`, `lsh`), trees (`red_black_tree`, `avl`, `bst`, `btree`, `bplus_tree`,
`segment_tree`, `segment_tree_lazy`, `segment_tree_beats`, `fenwick`, `bit_2d`,
`trie`, `skip_list`, `treap`, `splay`, `sparse_table`, `link_cut`,
`persistent_vector`, `hamt`, `mo_algorithm`, `li_chao_tree`),
graphs (`bfs_dfs`, `dijkstra_heap`, `johnson`, `kruskal`, `prim`, `scc`, `lca`,
`max_flow`, `dinic`, `min_cost_flow`, `a_star`, `bridge_articulation`,
`euler_path`, `hungarian`, `hopcroft_karp`, `stoer_wagner`, `max_clique`,
`hld`, `centroid_decomposition`, `virtual_tree`, `two_sat`, `graph_coloring`,
`edmonds_blossom`), strings (`kmp`, `rabin_karp`, `suffix_array`, `z_function`,
`manacher`, `aho_corasick`, `boyer_moore`, `lcp_array`, `suffix_tree`,
`palindromic_tree`, `rolling_hash`, `lyndon`, `suffix_automaton`), number theory (`prime`,
`miller_rabin`, `crt`, `bsgs`, `pollard_rho`, `euler_sieve`, `ntt`,
`int64_utils`, `finite_field`, `mobius`, `polynomial`, `primitive_root`,
`quadratic_residue`), math (`combinatorics`, `matrix`, `matrix_decomp`,
`newton_method`, `berlekamp_massey`, `fft`, `simplex`), geometry (`convex_hull`,
`andrew_hull`, `convex_hull_3d`, `half_plane_intersection`, `kd_tree`,
`rotating_calipers`, `closest_pair`, `segment_ops`, `delaunay`, `voronoi`,
`dynamic_hull`), dynamic programming (`dp`, `lis`, `interval_dp`, `tree_dp`,
`digit_dp`, `knuth_opt`, `divide_conquer_dp`, `convex_hull_trick`, `sos_dp`),
containers (`binary_heap`, `hash_table`, `lru_cache`, `ttl_cache`, `w_tinylfu`,
`bloom_filter`, `cuckoo_filter`, `count_min_sketch`, `hyperloglog`,
`union_find`, `priority_queue`, `monotonic`, `crc`), game theory (`nim_sg`),
and random (`reservoir_sampling`, `weighted_sampling`).

Each of these packages satisfies the [Testing Guarantee](#7-testing-guarantee)
for the Stable tier.

### Experimental tier (10 packages)

Newly added packages whose APIs are not yet frozen. They are correct (they pass
`moon test`) but may change in any minor version until promoted to Stable.

| Package | Path | Domain |
|---------|------|--------|
| `concurrent` | `containers/concurrent` | SPSC ring buffer, bounded queue, copy-on-write snapshot map |
| `gomory_hu` | `graph/gomory_hu` | All-pairs min-cut via Gomory-Hu tree |
| `dominator_tree` | `graph/dominator_tree` | Lengauer-Tarjan dominators |
| `min_steiner_tree` | `graph/min_steiner_tree` | Minimum Steiner tree |
| `flow_with_bounds` | `graph/flow_with_bounds` | Flow with lower/upper capacity bounds |
| `lsm_tree` | `containers/lsm_tree` | Log-Structured Merge-tree |
| `fm_index` | `string/fm_index` | FM-index backward search |
| `wavelet_tree` | `string/wavelet_tree` | Wavelet tree rank/select |
| `reed_solomon` | `number_theory/reed_solomon` | Reed-Solomon codes over GF(2⁸) |
| `external_sort` | `sorting/external_sort` | External merge sort |

All Experimental packages have `"proof-enabled": false`; their correctness is
backed by the test suite, including fuzz coverage for the concurrent structures
and Reed-Solomon round-trip/error-correction paths.

---

## 7. Testing Guarantee

`moon-certified` backs its stability claims with a multi-layered test strategy.
At the released `v0.10.0` the suite comprises **1599 tests**; the development
branch adds further fuzz and stress coverage. The guarantees below apply to every
package, with tier-specific additions.

### 7.1 Functional tests

- **Every public function has at least one functional test.** This is a
  hard requirement for the Stable and Experimental tiers; it is enforced by code
  review and is a blocker for release.
- Tests cover: the happy path, boundary conditions (empty input, single element,
  minimum/maximum values), and documented edge cases (e.g., `Int::MIN` for `gcd`,
  Carmichael numbers for `miller_rabin`, collinear points for `convex_hull`).
- For functions returning `Option` or `SPResult`, both the `Some` and `None`
  branches are exercised.

### 7.2 Stress tests

- Located in `test/stress`. Inputs are sized at **10³–10⁴ elements** to verify
  that algorithms scale without stack overflow, timeout, or correctness
  degradation.
- Stress targets include sorting (10,000-element random arrays with permutation
  verification), graph algorithms on large adjacency structures, and data
  structures under sustained insert/delete workloads.
- Recursive algorithms that were converted to iterative implementations (e.g.,
  `scc`, `splay`, `dinic`, `bst`) are specifically stress-tested on degenerate
  inputs that would have caused stack overflow in a recursive formulation.

### 7.3 Fuzz tests

- Located in `test/fuzz`. These target **adversarial inputs** that random testing
  tends to miss, using a deterministic xorshift64 PRNG (fixed seeds) so that any
  failure is reproducible.
- Categories covered:
  1. **Sorting adversarial** — sorted, reverse-sorted, all-equal, pivot-hostile
     patterns, duplicate-heavy multisets (with multiset-equality verification).
  2. **Data-structure adversarial** — sequential insert/delete (rebalancing
     storms), alternating min/max (degenerate tree shapes), cache thrashing.
  3. **Graph adversarial** — self-loops, disconnected components, chains, star
     graphs, flow networks with adversarial capacities, cycle detection.
  4. **String adversarial** — highly repetitive strings, Unicode/CJK safety,
     empty and whitespace inputs, pattern-longer-than-text.
  5. **Number-theory adversarial** — Carmichael numbers (561, 1105, 1729),
     perfect powers, Fermat pseudoprimes, `Int32` boundary values.
  6. **Geometry adversarial** — collinear points, duplicate points, large
     coordinates near the `Int32` cross-product overflow threshold.
  7. **Concurrent-structure adversarial** — ring-buffer overflow/underflow,
     snapshot-map consistency across mutations.
  8. **Randomised property-based** — sort idempotence, Fenwick inverse property,
     segment-tree range-query consistency, LIS bounds, NTT round-trip,
     bloom-filter false-positive rate.

### 7.4 Benchmarks and complexity verification

- Located in `benchmarks`. These verify the **documented asymptotic complexity**
  of major algorithms by measuring runtime across increasing input sizes and
  confirming the growth rate matches the claimed bound (e.g., O(n log n) for
  merge sort, O(n) for radix sort, O(log n) per operation for balanced trees).
- Complexity claims documented in package doc-comments are treated as part of the
  public contract: a regression in the complexity class (e.g., an accidental
  O(n²) in a function documented as O(n log n)) is a breaking change requiring a
  major bump or a documented fix.

### 7.5 Formal verification (Verified tier only)

- The 9 Verified packages are checked by `moon prove` (Why3 + Z3) in CI on every
  push and pull request. A failed proof is a release blocker.
- Verification is **honest**: the exact set of proven properties is documented
  per-package (see the [Verified tier](#verified-tier) table). Properties that
  cannot be proven automatically (typically those requiring nonlinear arithmetic
  reasoning) are explicitly marked as unproven rather than falsely claimed.

### 7.6 CI enforcement

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs three jobs on every
push to `main` and every pull request:

1. **`moon check --deny-warn`** — type checking with zero warnings required.
2. **`moon test`** — the full functional, stress, and fuzz suite.
3. **`moon prove`** — formal verification of all 9 Verified packages
   (Why3 1.7.2 + Z3 4.12.6.0, MoonBit pinned for reproducibility).

A green CI is a prerequisite for any release.

---

## Appendix A: Version History Summary

| Version | Date | Packages | Tests | Verified | Theme |
|---------|------|----------|-------|----------|-------|
| 0.1.0 | 2024-10-15 | 25 | — | 5 full | Initial release; verification infrastructure. |
| 0.2.0 | 2024-11-01 | 33 | — | 5 full | Generic sorting/search; `SPResult`/`Option` error handling; red-black tree (Okasaki). |
| 0.3.0 | 2024-12-01 | — | — | 5 full + partial | Magic values eliminated; RB-tree Kahrs deletion; data-structure encapsulation. |
| 0.4.0 | 2025-01-15 | 43 | 601 | — | LRU, Bloom filter, B-Tree, A*, Edmonds-Karp; stress-test package. |
| 0.5.0 | 2026-07-23 | 58 | 830 | — | 15 new packages; 13 P0 fixes; Int64 overflow protection. |
| 0.6.0 | 2026-07-24 | 66 | 958 | — | 8 new packages (Aho-Corasick, MCMF, Splay, BSGS, Pollard-Rho, KD-Tree, rotating calipers, 2-SAT). |
| 0.7.0 | 2026-07-24 | — | — | — | P0 quality fixes (gcd `Int::MIN`, 0 warnings, CJK safety, per-instance RNG). |
| 0.8.0 | 2026-07-24 | — | — | — | 8 new packages (euler_sieve, sparse_table, lca, dinic, closest_pair, segment_ops, combinatorics, matrix). |
| 0.9.0 | 2026-07-24 | 86 | 1321 | — | 12 new packages; `int64_utils` shared module; encapsulation hardening; overflow fixes. |
| 0.10.0 | 2026-07-25 | 113 | 1599 | 9/9 | 27 new packages (additive, non-breaking). |
| Unreleased | 2026-07-25 | 152 | 1599+ | 9/9 | 10 Experimental packages + fuzz suite + additional stable packages. |

Notes:
- "Verified" counts packages with `"proof-enabled": true` passing `moon prove`.
  The 9 consist of 5 full-correctness proofs and 4 partial proofs.
- Package counts exclude the `test/` and `benchmarks/` infrastructure packages.
- The Unreleased row reflects the current development tree and is subject to
  change before the next tagged release.

---

## Appendix B: Overflow Safety Contract

Formal verification models `Int` as an unbounded mathematical integer; the
runtime `Int` is a 32-bit signed integer. The following contract documents, per
function, the overflow behaviour and the safe alternative. This is part of the
public API: a change to an entry in this table is a (possibly breaking) contract
change.

| Function | Overflow behaviour | Safe alternative |
|----------|--------------------|------------------|
| `fast_power` | Result may wrap to negative on overflow. | `fast_power_checked` → `Int?`. |
| `gcd` | Safe; `Int::MIN` handled via `Int64` (only `gcd(Int::MIN, Int::MIN)` clamps to `Int::MAX`). | — |
| `array_sum` | Large-array sum may overflow. | `array_sum_checked` → `Int?`. |
| `matrix.matmul_int` | Element-wise products may overflow. | `matmul_int_checked` → `FixedArray[Int]?`. |
| `dijkstra_heap` | Distances use `Int64`; returns `None` on overflow. | Built-in protection. |
| `convex_hull` / `andrew_hull` | Cross products use `Int64`. | Built-in protection. |
| `max_flow` / `dinic` | Flow accumulated in `Int64`; returns `Int64?` (`None` = invalid input). | Built-in protection. |
| `min_cost_flow` | Flow/cost in `Int64`; returns `(Int64, Int64)?`. | Built-in protection. |
| `interpolation_search` | Subtraction uses `Int64`. | Built-in protection. |
| `combinatorics.binomial` | Multiply-then-divide in `Int64` (exact). | Built-in protection. |
| `int64_utils.gcd64` | Correctly handles `Int64::MIN`. | — |
| `int64_utils.is_prime64` | Witness set valid for full `Int64` range. | — |
| `sieve` | Returns `None` for `n > 10⁷` (OOM protection). | `FixedArray[Int]?`. |
| `knapsack` / `lcs` / `edit_distance` | Returns `None` when `n × capacity > 10⁷`. | `Int?`. |
| `counting_sort` | Returns `None` for negatives or `k > 10⁷`. | `FixedArray[Int]?`. |
| `pollard_rho` | Returns `None` on failure (prime or unfactorable). | `Int?`. |
| `prim` / `segment_tree` / `fenwick` / `kruskal` | Aggregated sums may overflow `Int32`; documented. | Caller must ensure no overflow. |
| `rolling_hash` | Dual-modulus `Int64` intermediates; very large strings may still overflow. | Caller must ensure bounded input. |
| `matrix_decomp` / `newton_method` | Use `Double`; no integer overflow (floating-point precision limits apply). | — |

**Guarantee.** A function listed as having "built-in protection" will never
silently return an incorrect result due to overflow: it either uses `Int64`
internally with sufficient headroom, or returns `None`/`Option` when the result
cannot be represented. A function listed as "caller must ensure" documents the
overflow risk but does not guard against it; callers are responsible for
constraining inputs. This categorisation is part of the stability contract and
will not be weakened without a major version bump.
