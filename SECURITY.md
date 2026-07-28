# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.12.x  | Yes       |
| 0.11.x  | Yes       |
| < 0.11  | No        |

## Reporting a Vulnerability

If you discover a security vulnerability in moon-certified, please report it
responsibly:

1. **Do not open a public GitHub issue** for security vulnerabilities.
2. Email the maintainer at: juwan.hwang@proton.me
3. Include a description of the vulnerability, a minimal reproduction, and
   the potential impact.
4. You will receive a response within 48 hours.

## Security Considerations

### Integer Overflow

This library uses `Int32` for most integer operations. For algorithms where
overflow is a concern (graph distances, flow capacities, combinatorial counts),
`Int64` variants or `*_checked` functions are provided. See
`docs/API_STABILITY.md` Appendix B for the full overflow safety contract.

### Input Validation

Public API functions validate inputs and return `Option` types for invalid
input. No public API function calls `abort()` or `panic()` on invalid user
input — invalid data returns `None` or a `*_checked` variant.

A small number of internal helper functions use `abort()` as a defensive
guard for code paths that are provably unreachable when invariants hold
(e.g., exhausting a `match` on an enum that has been pre-validated). These
guards cannot be triggered by any valid or invalid user input to a public
API function. Test code also uses `abort()` for assertions, but test code
is not included in production builds.

### Random Number Generation

Random number generators (Mersenne Twister, PCG, Xoshiro, SplitMix64) are
**not cryptographically secure**. Do not use them for security-sensitive
applications (password generation, session tokens, cryptographic keys).

### Concurrency

Concurrent data structures (Treiber Stack, MPMC Queue, Concurrent HashMap,
Work-Stealing Queue) are algorithmic reference implementations. MoonBit's
current runtime is single-threaded — these structures cannot be used for
true multi-threaded concurrency until MoonBit adds multi-threading support.

### Cryptographic Modules

The `crypto/` packages (AES, ChaCha20, SHA-256, SHA-512, SHA-3, Poly1305,
ChaCha20-Poly1305 AEAD, HMAC, HKDF, PBKDF2, scrypt, CSPRNG/HMAC-DRBG, Base64)
implement standard algorithms per their respective FIPS/RFC specifications.
Test vectors from NIST and IETF RFCs are used to verify correctness.

**AES side-channel limitation**: The AES implementation uses precomputed
S-box table lookups, which are **not constant-time** and are vulnerable to
cache-timing attacks on platforms with shared caches. In MoonBit's current
WebAssembly target, this is not exploitable (Wasm linear memory has no
shared-cache side channel). Do not use this AES implementation in
environments where side-channel attacks are a concern.

**Key material in memory**: MoonBit has a garbage collector, so the
`zeroize` function (in `crypto/pbkdf2`) can only clear the mutable buffer
reference it receives — it cannot guarantee that all GC copies are cleared.
This is a platform limitation.

**These modules have not been audited by a third-party security firm.**
They are suitable for educational purposes, prototyping, and non-critical
applications. For production security-critical systems, use established
audited libraries (OpenSSL, ring, BoringSSL).

### Static Analysis & Supply Chain

- **Dependency Review**: Pull requests are automatically scanned for known
  vulnerabilities via GitHub's dependency review action.
- **Nightly Builds**: Tests run 3× per OS (Ubuntu, macOS, Windows) every
  night to detect flaky tests and regressions.
- **Release Checksums**: Each GitHub Release includes a SHA-256 checksum
  file for the source tarball.
- **SAST Limitation**: CodeQL does not support MoonBit. Static analysis
  is limited to `moon check --deny-warn` (type safety with zero warnings)
  and the formal verification pipeline (`moon prove` with Z3 + Why3).
