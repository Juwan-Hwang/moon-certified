# Contributing to moon-certified

Thank you for your interest in contributing to moon-certified! This document
outlines the process for contributing algorithms, fixes, and improvements.

## Development Setup

```bash
git clone https://github.com/Juwan-Hwang/moon-certified.git
cd moon-certified
moon check   # Type check (must pass with 0 errors)
moon test    # Run all tests (must pass)
moon prove   # Formal verification (requires Why3 1.7.2 + Z3 4.12.x)
```

## Code Standards

### Algorithm Implementation Requirements

1. **Production-grade quality**: Every algorithm must be a complete, correct
   implementation — not a simplified or toy version. If a production-grade
   implementation is not feasible (e.g., due to MoonBit runtime limitations),
   document the limitation clearly in the module header.

2. **Error handling**: Use `Option` return types for fallible operations.
   Never call `abort()` or `panic()` on public API functions — invalid input
   should return `None` or an `Result` type.

3. **Overflow safety**: Use `Int64` for arithmetic that may overflow `Int32`
   (graph distances, flow capacities, combinatorial counts). Document any
   remaining overflow risks.

4. **Stack safety**: Recursive implementations must include a `guard_depth`
   parameter or equivalent protection against stack overflow on degenerate
   inputs. Prefer iterative implementations where practical.

5. **Testing**: Every public function must have at least one test. Include:
   - Basic functionality test
   - Edge case test (empty input, single element, boundary values)
   - Correctness cross-check (compare with brute force where feasible)

### Package Structure

Each algorithm package lives in its own directory:

```
category/algorithm_name/
├── moon.pkg.json    # Package manifest
├── algorithm_name.mbt  # Implementation + tests
```

The `moon.pkg.json` should set `"proof-enabled": false` unless the package
has formal verification proofs.

### Code Style

- Match existing style in the codebase
- Use `///` doc comments for all public functions
- Include complexity annotations (Time/Space) in doc comments
- Prefer `FixedArray` over `Array` for performance-critical code

## Pull Request Process

1. **Open an issue** describing the algorithm or fix you want to contribute.
2. **Fork and branch**: `git checkout -b feature/your-algorithm`
3. **Implement** following the standards above
4. **Test**: `moon check && moon test` must pass with 0 errors
5. **Document**: Update README.md project structure and CHANGELOG.md
6. **Submit PR**: Include a description of the algorithm, complexity, and
   test coverage

## Formal Verification

Packages with `"proof-enabled": true` are formally verified using `moon prove`
(Why3 + Z3). If you want to add formal verification to a package:

1. Ensure the implementation is pure (no side effects, no I/O)
2. Add verification conditions (preconditions, postconditions, invariants)
3. Run `moon prove` and ensure all goals are discharged
4. Document whether the proof is full correctness or partial (e.g., only
   non-negativity, only bounds)

## License

By contributing, you agree that your contributions are licensed under Apache-2.0.
