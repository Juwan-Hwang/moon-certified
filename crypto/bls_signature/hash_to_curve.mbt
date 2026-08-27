/// Hash-to-curve for BLS12-381 G1 (RFC 9380)
///
/// Full production implementation of the suite
/// `BLS12381G1_XMD:SHA-256_SSWU_RO_` from RFC 9380 §8.8.1:
///
/// - `expand_message_xmd` (§5.3.1) with SHA-256, L = 64
/// - `hash_to_field` (§5.2) producing two base-field elements
/// - Simplified SWU mapping (§6.6.2) onto the isogenous curve
///   E': y² = x³ + A'x + B' with Z = 11
/// - The 11-isogeny map E' → E from RFC 9380 Appendix E.2
/// - Cofactor clearing by scalar multiplication with h_eff = 0xd201000000010001

///|
/// Domain separation tag (default ciphersuite ID of the BLS signature spec).
let h2c_dst : String = "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_"

///|
/// Parse a hex constant, aborting on malformed input (module-internal
/// constants only; never reached by user data).
fn parse_h2c(s : String) -> @bigint.BigInt {
  match @bigint.from_string(s) {
    Some(v) => v
    None => abort("FATAL: invalid hash-to-curve constant")
  }
}

// ---------------------------------------------------------------------------
// E' curve parameters (RFC 9380 §8.8.1)
// ---------------------------------------------------------------------------

///|
/// A' of the isogenous curve E'
let h2c_ap : @bigint.BigInt = parse_h2c(
  "0x144698a3b8e9433d693a02c96d4982b0ea985383ee66a8d8e8981aefd881ac98936f8da0e0f97f5cf428082d584c1d",
)

///|
/// B' of the isogenous curve E'
let h2c_bp : @bigint.BigInt = parse_h2c(
  "0x12e2908d11688030018b12e8753eee3b2016c1f0f24f4070a0b9c14fcef35ef55a23215a316ceaa5d1cc48e98e172be0",
)

///|
/// SSWU parameter Z = 11
let h2c_z : @bigint.BigInt = @bigint.from_int_value(11)

///|
/// Effective cofactor for clearing (RFC 9380 §8.8.1).
let h2c_h_eff : @bigint.BigInt = parse_h2c("0xd201000000010001")

// ---------------------------------------------------------------------------
// 11-isogeny map constants (RFC 9380 Appendix E.2)
// ---------------------------------------------------------------------------

///|
/// Coefficients k_(1,0)..k_(1,11) for x_num.
let iso_xnum : Array[@bigint.BigInt] = [
  parse_h2c(
    "0x11a05f2b1e833340b809101dd99815856b303e88a2d7005ff2627b56cdb4e2c85610c2d5f2e62d6eaeac1662734649b7",
  ),
  parse_h2c(
    "0x17294ed3e943ab2f0588bab22147a81c7c17e75b2f6a8417f565e33c70d1e86b4838f2a6f318c356e834eef1b3cb83bb",
  ),
  parse_h2c(
    "0xd54005db97678ec1d1048c5d10a9a1bce032473295983e56878e501ec68e25c958c3e3d2a09729fe0179f9dac9edcb0",
  ),
  parse_h2c(
    "0x1778e7166fcc6db74e0609d307e55412d7f5e4656a8dbf25f1b33289f1b330835336e25ce3107193c5b388641d9b6861",
  ),
  parse_h2c(
    "0xe99726a3199f4436642b4b3e4118e5499db995a1257fb3f086eeb65982fac18985a286f301e77c451154ce9ac8895d9",
  ),
  parse_h2c(
    "0x1630c3250d7313ff01d1201bf7a74ab5db3cb17dd952799b9ed3ab9097e68f90a0870d2dcae73d19cd13c1c66f652983",
  ),
  parse_h2c(
    "0xd6ed6553fe44d296a3726c38ae652bfb11586264f0f8ce19008e218f9c86b2a8da25128c1052ecaddd7f225a139ed84",
  ),
  parse_h2c(
    "0x17b81e7701abdbe2e8743884d1117e53356de5ab275b4db1a682c62ef0f2753339b7c8f8c8f475af9ccb5618e3f0c88e",
  ),
  parse_h2c(
    "0x80d3cf1f9a78fc47b90b33563be990dc43b756ce79f5574a2c596c928c5d1de4fa295f296b74e956d71986a8497e317",
  ),
  parse_h2c(
    "0x169b1f8e1bcfa7c42e0c37515d138f22dd2ecb803a0c5c99676314baf4bb1b7fa3190b2edc0327797f241067be390c9e",
  ),
  parse_h2c(
    "0x10321da079ce07e272d8ec09d2565b0dfa7dccdde6787f96d50af36003b14866f69b771f8c285decca67df3f1605fb7b",
  ),
  parse_h2c(
    "0x6e08c248e260e70bd1e962381edee3d31d79d7e22c837bc23c0bf1bc24c6b68c24b1b80b64d391fa9c8ba2e8ba2d229",
  ),
]

///|
/// Coefficients k_(2,0)..k_(2,9) for x_den (leading term x'^10 is monic).
let iso_xden : Array[@bigint.BigInt] = [
  parse_h2c(
    "0x8ca8d548cff19ae18b2e62f4bd3fa6f01d5ef4ba35b48ba9c9588617fc8ac62b558d681be343df8993cf9fa40d21b1c",
  ),
  parse_h2c(
    "0x12561a5deb559c4348b4711298e536367041e8ca0cf0800c0126c2588c48bf5713daa8846cb026e9e5c8276ec82b3bff",
  ),
  parse_h2c(
    "0xb2962fe57a3225e8137e629bff2991f6f89416f5a718cd1fca64e00b11aceacd6a3d0967c94fedcfcc239ba5cb83e19",
  ),
  parse_h2c(
    "0x3425581a58ae2fec83aafef7c40eb545b08243f16b1655154cca8abc28d6fd04976d5243eecf5c4130de8938dc62cd8",
  ),
  parse_h2c(
    "0x13a8e162022914a80a6f1d5f43e7a07dffdfc759a12062bb8d6b44e833b306da9bd29ba81f35781d539d395b3532a21e",
  ),
  parse_h2c(
    "0xe7355f8e4e667b955390f7f0506c6e9395735e9ce9cad4d0a43bcef24b8982f7400d24bc4228f11c02df9a29f6304a5",
  ),
  parse_h2c(
    "0x772caacf16936190f3e0c63e0596721570f5799af53a1894e2e073062aede9cea73b3538f0de06cec2574496ee84a3a",
  ),
  parse_h2c(
    "0x14a7ac2a9d64a8b230b3f5b074cf01996e7f63c21bca68a81996e1cdf9822c580fa5b9489d11e2d311f7d99bbdcc5a5e",
  ),
  parse_h2c(
    "0xa10ecf6ada54f825e920b3dafc7a3cce07f8d1d7161366b74100da67f39883503826692abba43704776ec3a79a1d641",
  ),
  parse_h2c(
    "0x95fc13ab9e92ad4476d6e3eb3a56680f682b4ee96f7d03776df533978f31c1593174e4b4b7865002d6384d168ecdd0a",
  ),
]

///|
/// Coefficients k_(3,0)..k_(3,15) for y_num.
let iso_ynum : Array[@bigint.BigInt] = [
  parse_h2c(
    "0x90d97c81ba24ee0259d1f094980dcfa11ad138e48a869522b52af6c956543d3cd0c7aee9b3ba3c2be9845719707bb33",
  ),
  parse_h2c(
    "0x134996a104ee5811d51036d776fb46831223e96c254f383d0f906343eb67ad34d6c56711962fa8bfe097e75a2e41c696",
  ),
  parse_h2c(
    "0xcc786baa966e66f4a384c86a3b49942552e2d658a31ce2c344be4b91400da7d26d521628b00523b8dfe240c72de1f6",
  ),
  parse_h2c(
    "0x1f86376e8981c217898751ad8746757d42aa7b90eeb791c09e4a3ec03251cf9de405aba9ec61deca6355c77b0e5f4cb",
  ),
  parse_h2c(
    "0x8cc03fdefe0ff135caf4fe2a21529c4195536fbe3ce50b879833fd221351adc2ee7f8dc099040a841b6daecf2e8fedb",
  ),
  parse_h2c(
    "0x16603fca40634b6a2211e11db8f0a6a074a7d0d4afadb7bd76505c3d3ad5544e203f6326c95a807299b23ab13633a5f0",
  ),
  parse_h2c(
    "0x4ab0b9bcfac1bbcb2c977d027796b3ce75bb8ca2be184cb5231413c4d634f3747a87ac2460f415ec961f8855fe9d6f2",
  ),
  parse_h2c(
    "0x987c8d5333ab86fde9926bd2ca6c674170a05bfe3bdd81ffd038da6c26c842642f64550fedfe935a15e4ca31870fb29",
  ),
  parse_h2c(
    "0x9fc4018bd96684be88c9e221e4da1bb8f3abd16679dc26c1e8b6e6a1f20cabe69d65201c78607a360370e577bdba587",
  ),
  parse_h2c(
    "0xe1bba7a1186bdb5223abde7ada14a23c42a0ca7915af6fe06985e7ed1e4d43b9b3f7055dd4eba6f2bafaaebca731c30",
  ),
  parse_h2c(
    "0x19713e47937cd1be0dfd0b8f1d43fb93cd2fcbcb6caf493fd1183e416389e61031bf3a5cce3fbafce813711ad011c132",
  ),
  parse_h2c(
    "0x18b46a908f36f6deb918c143fed2edcc523559b8aaf0c2462e6bfe7f911f643249d9cdf41b44d606ce07c8a4d0074d8e",
  ),
  parse_h2c(
    "0xb182cac101b9399d155096004f53f447aa7b12a3426b08ec02710e807b4633f06c851c1919211f20d4c04f00b971ef8",
  ),
  parse_h2c(
    "0x245a394ad1eca9b72fc00ae7be315dc757b3b080d4c158013e6632d3c40659cc6cf90ad1c232a6442d9d3f5db980133",
  ),
  parse_h2c(
    "0x5c129645e44cf1102a159f748c4a3fc5e673d81d7e86568d9ab0f5d396a7ce46ba1049b6579afb7866b1e715475224b",
  ),
  parse_h2c(
    "0x15e6be4e990f03ce4ea50b3b42df2eb5cb181d8f84965a3957add4fa95af01b2b665027efec01c7704b456be69c8b604",
  ),
]

///|
/// Coefficients k_(4,0)..k_(4,14) for y_den (leading term x'^15 is monic).
let iso_yden : Array[@bigint.BigInt] = [
  parse_h2c(
    "0x16112c4c3a9c98b252181140fad0eae9601a6de578980be6eec3232b5be72e7a07f3688ef60c206d01479253b03663c1",
  ),
  parse_h2c(
    "0x1962d75c2381201e1a0cbd6c43c348b885c84ff731c4d59ca4a10356f453e01f78a4260763529e3532f6102c2e49a03d",
  ),
  parse_h2c(
    "0x58df3306640da276faaae7d6e8eb15778c4855551ae7f310c35a5dd279cd2eca6757cd636f96f891e2538b53dbf67f2",
  ),
  parse_h2c(
    "0x16b7d288798e5395f20d23bf89edb4d1d115c5dbddbcd30e123da489e726af41727364f2c28297ada8d26d98445f5416",
  ),
  parse_h2c(
    "0xbe0e079545f43e4b00cc912f8228ddcc6d19c9f0f69bbb0542eda0fc9dec916a20b15dc0fd2ededda39142311a5001d",
  ),
  parse_h2c(
    "0x8d9e5297186db2d9fb266eaac783182b70152c65550d881c5ecd87b6f0f5a6449f38db9dfa9cce202c6477faaf9b7ac",
  ),
  parse_h2c(
    "0x166007c08a99db2fc3ba8734ace9824b5eecfdfa8d0cf8ef5dd365bc400a0051d5fa9c01a58b1fb93d1a1399126a775c",
  ),
  parse_h2c(
    "0x16a3ef08be3ea7ea03bcddfabba6ff6ee5a4375efa1f4fd7feb34fd206357132b920f5b00801dee460ee415a15812ed9",
  ),
  parse_h2c(
    "0x1866c8ed336c61231a1be54fd1d74cc4f9fb0ce4c6af5920abc5750c4bf39b4852cfe2f7bb9248836b233d9d55535d4a",
  ),
  parse_h2c(
    "0x167a55cda70a6e1cea820597d94a84903216f763e13d87bb5308592e7ea7d4fbc7385ea3d529b35e346ef48bb8913f55",
  ),
  parse_h2c(
    "0x4d2f259eea405bd48f010a01ad2911d9c6dd039bb61a6290e591b36e636a5c871a5c29f4f83060400f8b49cba8f6aa8",
  ),
  parse_h2c(
    "0xaccbb67481d033ff5852c1e48c50c477f94ff8aefce42d28c0f9a88cea7913516f968986f7ebbea9684b529e2561092",
  ),
  parse_h2c(
    "0xad6b9514c767fe3c3613144b45f1496543346d98adf02267d5ceef9a00d9b8693000763e3b90ac11e99b138573345cc",
  ),
  parse_h2c(
    "0x2660400eb2e4f3b628bdd0d53cd76f2bf565b94e72927c1cb748df27942480e420517bd8714cc80d1fadc1326ed06f7",
  ),
  parse_h2c(
    "0xe0fa1d816ddc03e6b24255e0d7819c171c40f65e273b853324efcd6356caa205ca2f570f13497804415473a1d634b8f",
  ),
]

// ---------------------------------------------------------------------------
// Fp helpers
// ---------------------------------------------------------------------------

///|
/// Negation in Fp.
fn fp_neg(a : @bigint.BigInt) -> @bigint.BigInt {
  @pairing.fp_sub(@bigint.zero(), a)
}

///|
/// sgn0 for GF(p) (RFC 9380 §4.1): the sign is the parity of the value.
fn sgn0(a : @bigint.BigInt) -> Bool {
  @bigint.is_odd(a)
}

///|
/// Euler criterion: x is a square in Fp iff x^((p-1)/2) ∈ {0, 1}.
fn fp_is_square(x : @bigint.BigInt) -> Bool {
  let p = @pairing.bls_p
  let exp = match
    @bigint.divmod(@bigint.sub(p, @bigint.one()), @bigint.from_int_value(2)) {
    Some((q, _)) => q
    None => @bigint.zero()
  }
  let e = @pairing.fp_pow(x, exp)
  @bigint.equal(e, @bigint.zero()) || @bigint.equal(e, @bigint.one())
}

///|
/// Square root in Fp. Valid because p ≡ 3 (mod 4): sqrt(x) = x^((p+1)/4).
fn fp_sqrt(x : @bigint.BigInt) -> @bigint.BigInt {
  let p = @pairing.bls_p
  let exp = match
    @bigint.divmod(@bigint.add(p, @bigint.one()), @bigint.from_int_value(4)) {
    Some((q, _)) => q
    None => @bigint.zero()
  }
  @pairing.fp_pow(x, exp)
}

// ---------------------------------------------------------------------------
// expand_message_xmd (RFC 9380 §5.3.1) with SHA-256
// ---------------------------------------------------------------------------

///|
/// Byte-wise XOR of two equal-length byte strings.
fn bytes_xor(a : Bytes, b : Bytes) -> Array[Byte] {
  let n = a.length()
  let out = Array::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    out[i] = ((a[i].to_int() ^ b[i].to_int()) & 0xFF).to_byte()
  }
  out
}

///|
/// Concatenate byte arrays into a single Bytes value.
fn bytes_concat(parts : Array[Bytes]) -> Bytes {
  let out : Array[Byte] = []
  for p in parts {
    for i = 0; i < p.length(); i = i + 1 {
      out.push(p[i])
    }
  }
  Bytes::from_array(out)
}

///|
/// expand_message_xmd(msg, DST, len_in_bytes) with H = SHA-256
/// (b_in_bytes = 32, s_in_bytes = 64).
fn expand_message_xmd(msg : Bytes, dst : Bytes, len_in_bytes : Int) -> Bytes {
  let b_in_bytes = 32
  let s_in_bytes = 64
  let ell = (len_in_bytes + b_in_bytes - 1) / b_in_bytes
  // DST_prime = DST || I2OSP(len(DST), 1)
  let dst_len_arr : Array[Byte] = []
  for i = 0; i < dst.length(); i = i + 1 {
    dst_len_arr.push(dst[i])
  }
  dst_len_arr.push((dst.length() & 0xFF).to_byte())
  let dst_prime = Bytes::from_array(dst_len_arr)
  // msg_prime = Z_pad || msg || I2OSP(len_in_bytes, 2) || I2OSP(0, 1) || DST_prime
  let z_pad = Bytes::from_array(Array::make(s_in_bytes, b'\x00'))
  let lib_arr : Array[Byte] = [
    ((len_in_bytes >> 8) & 0xFF).to_byte(),
    (len_in_bytes & 0xFF).to_byte(),
    b'\x00',
  ]
  let msg_prime = bytes_concat([
    z_pad,
    msg,
    Bytes::from_array(lib_arr),
    dst_prime,
  ])
  let b0 = @sha256.sha256(msg_prime)
  // b_1 = H(b_0 || I2OSP(1, 1) || DST_prime)
  let mut prev = @sha256.sha256(
    bytes_concat([b0, Bytes::from_array([b'\x01']), dst_prime]),
  )
  let blocks : Array[Bytes] = [prev]
  for i = 2; i <= ell; i = i + 1 {
    let xored = Bytes::from_array(bytes_xor(b0, prev))
    prev = @sha256.sha256(
      bytes_concat([xored, Bytes::from_array([(i & 0xFF).to_byte()]), dst_prime]),
    )
    blocks.push(prev)
  }
  let all_bytes = bytes_concat(blocks)
  // Truncate to the requested length.
  let out_arr : Array[Byte] = []
  for i = 0; i < len_in_bytes; i = i + 1 {
    out_arr.push(all_bytes[i])
  }
  Bytes::from_array(out_arr)
}

///|
/// Big-endian byte string to an element of Fp (OS2IP followed by mod p).
fn os2ip_mod_p(data : Bytes, offset : Int, len : Int) -> @bigint.BigInt {
  let mut v = @bigint.zero()
  let two56 = @bigint.from_int_value(256)
  for i = 0; i < len; i = i + 1 {
    let byte_val = data[offset + i].to_int() & 0xFF
    v = @bigint.add(@bigint.mul(v, two56), @bigint.from_int_value(byte_val))
  }
  match @bigint.divmod(v, @pairing.bls_p) {
    Some((_, r)) => r
    None => v
  }
}

///|
/// hash_to_field (RFC 9380 §5.2) with count = 2, m = 1, L = 64.
fn hash_to_field_g1(msg : Bytes) -> (@bigint.BigInt, @bigint.BigInt) {
  let dst = @utf8.encode(h2c_dst)
  let uniform = expand_message_xmd(msg, dst, 128)
  (os2ip_mod_p(uniform, 0, 64), os2ip_mod_p(uniform, 64, 64))
}

// ---------------------------------------------------------------------------
// Simplified SWU mapping onto E' (RFC 9380 §6.6.2)
// ---------------------------------------------------------------------------

///|
/// g'(x) = x³ + A'x + B' on the isogenous curve E'.
fn g_prime(x : @bigint.BigInt) -> @bigint.BigInt {
  let x3 = @pairing.fp_mul(@pairing.fp_sqr(x), x)
  @pairing.fp_add(@pairing.fp_add(x3, @pairing.fp_mul(h2c_ap, x)), h2c_bp)
}

///|
/// map_to_curve_simple_swu(u) → (x', y') on E'.
///
/// Exception free: inv0(0) = 0 triggers the x1 = B'/(Z·A') branch.
fn sswu_map(u : @bigint.BigInt) -> (@bigint.BigInt, @bigint.BigInt) {
  let z = h2c_z
  let u2 = @pairing.fp_sqr(u)
  let zu2 = @pairing.fp_mul(z, u2)
  let z2u4 = @pairing.fp_sqr(zu2)
  // tv1 = inv0(Z²·u⁴ + Z·u²)
  let tv1 = @pairing.fp_inv(@pairing.fp_add(z2u4, zu2))
  // x1 = (-B'/A') · (1 + tv1), or B'/(Z·A') in the exceptional case.
  let one = @bigint.one()
  let x1 = if @bigint.equal(tv1, @bigint.zero()) {
    @pairing.fp_mul(h2c_bp, @pairing.fp_inv(@pairing.fp_mul(z, h2c_ap)))
  } else {
    let neg_b_over_a = @pairing.fp_mul(fp_neg(h2c_bp), @pairing.fp_inv(h2c_ap))
    @pairing.fp_mul(neg_b_over_a, @pairing.fp_add(one, tv1))
  }
  let gx1 = g_prime(x1)
  let x2 = @pairing.fp_mul(zu2, x1)
  let gx2 = g_prime(x2)
  let (x, y_cand) = if fp_is_square(gx1) {
    (x1, fp_sqrt(gx1))
  } else {
    (x2, fp_sqrt(gx2))
  }
  // Sign of y: sgn0(y) must equal sgn0(u).
  let y = if sgn0(u) != sgn0(y_cand) { fp_neg(y_cand) } else { y_cand }
  (x, y)
}

// ---------------------------------------------------------------------------
// 11-isogeny map E' → E (RFC 9380 Appendix E.2)
// ---------------------------------------------------------------------------

///|
/// Horner evaluation of a polynomial with Fp coefficients (ascending order).
fn poly_eval(
  coeffs : Array[@bigint.BigInt],
  x : @bigint.BigInt,
) -> @bigint.BigInt {
  let mut acc = @bigint.zero()
  for i = coeffs.length() - 1; i >= 0; i = i - 1 {
    acc = @pairing.fp_add(@pairing.fp_mul(acc, x), coeffs[i])
  }
  acc
}

///|
/// Apply the 11-isogeny map to a point (x', y') on E', producing a point
/// on E: y² = x³ + 4. Returns the identity if a denominator vanishes
/// (the exceptional case mandated by RFC 9380 §6.6.3).
fn iso_map(xp : @bigint.BigInt, yp : @bigint.BigInt) -> @pairing.G1Point {
  // x_num(x'), and x_den(x') = x'^10 + Σ k_(2,i)·x'^i.
  let x_num = poly_eval(iso_xnum, xp)
  let mut pow10 = @bigint.one()
  for _ in 0..<10 {
    pow10 = @pairing.fp_mul(pow10, xp)
  }
  let x_den = @pairing.fp_add(pow10, poly_eval(iso_xden, xp))
  // y_num(x'), and y_den(x') = x'^15 + Σ k_(4,i)·x'^i.
  let y_num = poly_eval(iso_ynum, xp)
  // x'^15 = x'^10 · x'^5.
  let mut pow5 = @bigint.one()
  for _ in 0..<5 {
    pow5 = @pairing.fp_mul(pow5, xp)
  }
  let pow15 = @pairing.fp_mul(pow10, pow5)
  let y_den = @pairing.fp_add(pow15, poly_eval(iso_yden, xp))
  if @bigint.equal(x_den, @bigint.zero()) ||
    @bigint.equal(y_den, @bigint.zero()) {
    return @pairing.g1_identity()
  }
  let x = @pairing.fp_mul(x_num, @pairing.fp_inv(x_den))
  let y = @pairing.fp_mul(yp, @pairing.fp_mul(y_num, @pairing.fp_inv(y_den)))
  @pairing.g1_from_affine(x, y)
}

// ---------------------------------------------------------------------------
// hash_to_curve (RFC 9380 §3)
// ---------------------------------------------------------------------------

///|
/// Hash a message to a point of the prime-order subgroup G1, implementing
/// `BLS12381G1_XMD:SHA-256_SSWU_RO_`:
///
/// u0, u1 = hash_to_field(msg, 2); Q_i = iso_map(map_to_curve(u_i));
/// R = Q0 + Q1; P = clear_cofactor(R) = [h_eff]·R.
fn hash_to_curve_g1(msg : Bytes) -> @pairing.G1Point {
  let (u0, u1) = hash_to_field_g1(msg)
  let (x0, y0) = sswu_map(u0)
  let (x1, y1) = sswu_map(u1)
  let q0 = iso_map(x0, y0)
  let q1 = iso_map(x1, y1)
  let r = @pairing.g1_add(q0, q1)
  @pairing.g1_scalar_mul(h2c_h_eff, r)
}
