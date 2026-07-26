# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 0.11.x  | Yes       |
| 0.10.x  | No        |
| < 0.10  | No        |

## Reporting a Vulnerability

If you discover a security vulnerability in moon-certified, please report it
responsibly:

1. **Do not open a public GitHub issue** for security vulnerabilities.
2. Email the maintainer at: juwan.hwang@example.com
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
input. No public function calls `abort()` or `panic()` — invalid input will
never crash the calling process.

### Random Number Generation

Random number generators (Mersenne Twister, PCG, Xoshiro, SplitMix64) are
**not cryptographically secure**. Do not use them for security-sensitive
applications (password generation, session tokens, cryptographic keys).

### Concurrency

Concurrent data structures (Treiber Stack, MPMC Queue, Concurrent HashMap,
Work-Stealing Queue) are algorithmic reference implementations. MoonBit's
current runtime is single-threaded — these structures cannot be used for
true multi-threaded concurrency until MoonBit adds multi-threading support.
