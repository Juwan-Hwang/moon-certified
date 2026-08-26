/// BLS12-381 Base Field Arithmetic (Fp)
///
/// The base field Fp where p is the 381-bit BLS12-381 prime.
/// All arithmetic uses BigInt for full 381-bit precision.

///|
/// BLS12-381 base field prime p (381 bits)
/// p = 0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab
pub let bls_p : @bigint.BigInt = match(
  @bigint.from_string(
    "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab",
  ),
) {
  Some(v) => v
  None => abort("FATAL: invalid BLS12-381 prime p")
}

///|
/// BLS12-381 scalar field order r (255 bits)
/// r = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001
pub let bls_r : @bigint.BigInt = match(
  @bigint.from_string(
    "0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001",
  ),
) {
  Some(v) => v
  None => abort("FATAL: invalid BLS12-381 order r")
}

///|
/// (a + b) mod p
pub fn fp_add(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let sum = @bigint.add(a, b)
  match @bigint.divmod(sum, bls_p) {
    Some((_, r)) => r
    None => sum
  }
}

///|
/// (a - b) mod p (result always non-negative)
pub fn fp_sub(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  let diff = @bigint.sub(a, b)
  if @bigint.compare(diff, @bigint.zero()) < 0 {
    @bigint.add(diff, bls_p)
  } else {
    diff
  }
}

///|
/// (a * b) mod p
pub fn fp_mul(a : @bigint.BigInt, b : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.divmod(@bigint.mul(a, b), bls_p) {
    Some((_, r)) => r
    None => @bigint.zero()
  }
}

///|
/// a^2 mod p
pub fn fp_sqr(a : @bigint.BigInt) -> @bigint.BigInt {
  fp_mul(a, a)
}

///|
/// a^exp mod p
pub fn fp_pow(a : @bigint.BigInt, exp : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.mod_pow(a, exp, bls_p) {
    Some(r) => r
    None => @bigint.zero()
  }
}

///|
/// a^(-1) mod p via Fermat: a^(p-2) mod p
pub fn fp_inv(a : @bigint.BigInt) -> @bigint.BigInt {
  let exp = @bigint.sub(bls_p, @bigint.from_int_value(2))
  fp_pow(a, exp)
}

///|
/// Reduce a mod p
pub fn fp_reduce(a : @bigint.BigInt) -> @bigint.BigInt {
  match @bigint.divmod(a, bls_p) {
    Some((_, r)) => r
    None => a
  }
}
