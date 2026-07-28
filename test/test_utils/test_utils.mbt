/// Shared test utilities used across multiple algorithm test suites.
///
/// These functions are **test-only**: they exist to eliminate boilerplate
/// (e.g. the `str_cmp` comparator that was previously copy-pasted into 11+
/// test files) and are not part of the public algorithm library API.

///|
/// Lexicographic string comparator — thin wrapper around `@utils.str_cmp`.
///
/// Delegates to the canonical implementation in the `utils` package to
/// avoid code duplication. See `@utils.str_cmp` for details.
pub fn str_cmp(a : String, b : String) -> Int {
  @utils.str_cmp(a, b)
}

///|
/// Unwrap an `Option`, failing the test with a descriptive assertion if it
/// is `None`. Centralises the `match … { None => abort(…) }` pattern so
/// that every test reports failures uniformly.
///
/// # Example
/// ```moonbit
/// let s = @test_utils.expect_some(sieve(100), "sieve(100) should succeed")
/// ```
pub fn[T] expect_some(opt : T?, context : String) -> T {
  match opt {
    Some(v) => v
    None => abort("expect_some: expected Some but got None — " + context)
  }
}

///|
/// Assert that an `Option` is `None`, failing the test if it is `Some`.
/// The dual of [`expect_some`].
pub fn[T] expect_none(opt : T?, context : String) -> Unit {
  match opt {
    None => ()
    Some(_) => abort("expect_none: expected None but got Some — " + context)
  }
}
