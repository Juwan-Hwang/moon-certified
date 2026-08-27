/// JOSE — JSON Object Signing and Encryption (RFC 7515/7519).
///
/// This package implements **JWS** (JSON Web Signature, RFC 7515) compact
/// serialization and **JWT** (JSON Web Token, RFC 7519) with claim
/// validation.
///
/// ## Supported Algorithms
///
/// | Algorithm | Description                  |
/// |-----------|------------------------------|
/// | HS256     | HMAC-SHA-256 (RFC 2104)      |
/// | HS512     | HMAC-SHA-512 (RFC 2104)      |
/// | none      | Unsecured JWT (rejected by default) |
///
/// ## Security Notes
///
/// - **Algorithm confusion**: `verify` always re-derives the algorithm from
///   the token header and cross-checks it against the expected algorithm.
///   Passing `expected_alg` is mandatory — the caller must know which
///   algorithm they intend to use.
/// - **"none" algorithm**: Rejected by default.  Enable explicitly via
///   `JwtOptions { allow_none: true, .. }` **only** in non-production
///   testing contexts.
/// - **Constant-time comparison**: Signature verification uses
///   `@hmac.constant_time_eq` to prevent timing side-channels.
/// - **Clock skew**: `exp` and `nbf` claims tolerate configurable skew
///   (default 60 s) to account for clock drift between issuer and verifier.
///
/// ## References
///
/// - RFC 7515: JSON Web Signature (JWS)
/// - RFC 7519: JSON Web Token (JWT)
/// - RFC 7518: JSON Web Algorithms (JWA)
/// - RFC 2104: HMAC: Keyed-Hashing for Message Authentication
///
/// `proof-enabled` is `false`; correctness is backed by the test suite.

// ---------------------------------------------------------------------------
// Bas1.0e64URL helpers (RFC 4648 §5 — URL-safe alphabet, no padding per JOSE)
// ---------------------------------------------------------------------------

///|
/// Split a string by '.' into an array of owned Strings.
fn split_dot(s : String) -> Array[String] {
  let result : Array[String] = []
  let mut start = 0
  let chars = s.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '.' {
      result.push(s[start:i].to_owned())
      start = i + 1
    }
  }
  result.push(s[start:chars.length()].to_owned())
  result
}

///|
/// Initialize the bas1.0e64url alphabet (called once at module load).
fn init_b64url_alphabet() -> FixedArray[Char] {
  let a = FixedArray::make(64, '\u0000')
  let s = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
  let chars = s.to_array()
  for i = 0; i < 64 && i < chars.length(); i = i + 1 {
    a[i] = chars[i]
  }
  a
}

///|
/// Bas1.0e64URL-encode bytes without padding (JOSE convention).
fn b64url_encode(data : Bytes) -> String {
  let alpha = init_b64url_alphabet()
  let sb = StringBuilder()
  let len = data.length()
  let mut i = 0
  while i + 2 < len {
    let n = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    sb.write_char(alpha[(n >> 18) & 0x3F])
    sb.write_char(alpha[(n >> 12) & 0x3F])
    sb.write_char(alpha[(n >> 6) & 0x3F])
    sb.write_char(alpha[n & 0x3F])
    i = i + 3
  }
  if i < len {
    let rem = len - i
    let mut n = data[i].to_int() << 16
    if rem == 2 {
      n = n | (data[i + 1].to_int() << 8)
    }
    sb.write_char(alpha[(n >> 18) & 0x3F])
    sb.write_char(alpha[(n >> 12) & 0x3F])
    if rem == 2 {
      sb.write_char(alpha[(n >> 6) & 0x3F])
    }
    // No padding in JOSE bas1.0e64url
  }
  sb.to_string()
}

///|
/// Decode a Bas1.0e64URL string (with or without padding).
/// Returns `None` on invalid input.
fn b64url_decode(s : String) -> Bytes? {
  // Build lookup table: char → 6-bit value.
  let lookup : FixedArray[Int] = FixedArray::make(128, -1)
  let alpha = init_b64url_alphabet()
  for i = 0; i < 64; i = i + 1 {
    let c = alpha[i].to_int()
    if c < 128 {
      lookup[c] = i
    }
  }
  // Strip padding if present.
  let chars = s.to_array()
  let mut end = chars.length()
  while end > 0 && chars[end - 1] == '=' {
    end = end - 1
  }
  // Decode.
  let out : Array[Byte] = []
  let mut i = 0
  while i + 3 < end {
    let v0 = b64url_val(lookup, chars[i])
    let v1 = b64url_val(lookup, chars[i + 1])
    let v2 = b64url_val(lookup, chars[i + 2])
    let v3 = b64url_val(lookup, chars[i + 3])
    if v0 < 0 || v1 < 0 || v2 < 0 || v3 < 0 {
      return None
    }
    let n = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3
    out.push(((n >> 16) & 0xFF).to_byte())
    out.push(((n >> 8) & 0xFF).to_byte())
    out.push((n & 0xFF).to_byte())
    i = i + 4
  }
  let rem = end - i
  if rem == 2 {
    let v0 = b64url_val(lookup, chars[i])
    let v1 = b64url_val(lookup, chars[i + 1])
    if v0 < 0 || v1 < 0 {
      return None
    }
    let n = (v0 << 18) | (v1 << 12)
    out.push(((n >> 16) & 0xFF).to_byte())
  } else if rem == 3 {
    let v0 = b64url_val(lookup, chars[i])
    let v1 = b64url_val(lookup, chars[i + 1])
    let v2 = b64url_val(lookup, chars[i + 2])
    if v0 < 0 || v1 < 0 || v2 < 0 {
      return None
    }
    let n = (v0 << 18) | (v1 << 12) | (v2 << 6)
    out.push(((n >> 16) & 0xFF).to_byte())
    out.push(((n >> 8) & 0xFF).to_byte())
  } else if rem == 1 {
    return None // Invalid bas1.0e64
  }
  Some(Bytes::from_array(out))
}

///|
fn b64url_val(lookup : FixedArray[Int], c : Char) -> Int {
  let v = c.to_int()
  if v >= 0 && v < 128 {
    lookup[v]
  } else {
    -1
  }
}

// ---------------------------------------------------------------------------
// HMAC-SHA-512 (block size 128, output 64)
// ---------------------------------------------------------------------------

///|
const SHA512_BLOCK_SIZE : Int = 128

///|
const SHA512_OUTPUT_SIZE : Int = 64

///|
/// Compute HMAC-SHA-512.
///
/// RFC 2104 construction with SHA-512 as the underlying hash.
fn hmac_sha512(key : Bytes, message : Bytes) -> Bytes {
  // Normalize key: if longer than block size, hash it first.
  let normalized_key = if key.length() > SHA512_BLOCK_SIZE {
    @sha512.sha512(key)
  } else {
    key
  }
  // Pad key to block size and build ipad/opad.
  let k_buf : Array[Byte] = Array::make(SHA512_BLOCK_SIZE, b'\x00')
  for i = 0; i < normalized_key.length(); i = i + 1 {
    k_buf[i] = normalized_key[i]
  }
  // inner = H(ipad || message)
  let inner : Array[Byte] = Array::make(
    SHA512_BLOCK_SIZE + message.length(),
    b'\x00',
  )
  for i = 0; i < SHA512_BLOCK_SIZE; i = i + 1 {
    inner[i] = (k_buf[i].to_int() ^ 0x36).to_byte()
  }
  for i = 0; i < message.length(); i = i + 1 {
    inner[SHA512_BLOCK_SIZE + i] = message[i]
  }
  let inner_hash = @sha512.sha512(Bytes::from_array(inner))
  // outer = H(opad || inner)
  let outer : Array[Byte] = Array::make(
    SHA512_BLOCK_SIZE + SHA512_OUTPUT_SIZE,
    b'\x00',
  )
  for i = 0; i < SHA512_BLOCK_SIZE; i = i + 1 {
    outer[i] = (k_buf[i].to_int() ^ 0x5C).to_byte()
  }
  for i = 0; i < SHA512_OUTPUT_SIZE; i = i + 1 {
    outer[SHA512_BLOCK_SIZE + i] = inner_hash[i]
  }
  @sha512.sha512(Bytes::from_array(outer))
}

// ---------------------------------------------------------------------------
// Signing function
// ---------------------------------------------------------------------------

///|
/// Compute the signature for a signing input using the specified algorithm.
///
/// Returns `None` for unsupported algorithms or if the key is empty.
fn compute_signature(
  alg : String,
  key : Bytes,
  signing_input : Bytes,
) -> Bytes? {
  if key.length() == 0 {
    return None
  }
  match alg {
    "HS256" => Some(@hmac.hmac_sha256(key, signing_input))
    "HS512" => Some(hmac_sha512(key, signing_input))
    _ => None
  }
}

// ---------------------------------------------------------------------------
// JWS (RFC 7515) — Compact Serialization
// ---------------------------------------------------------------------------

///|
/// JWS header parameters (subset of RFC 7515 §4.1).
pub struct JwsHeader {
  alg : String // §4.1.1 — algorithm (required)
  typ : String? // §4.1.9 — type (e.g. "JWT")
  cty : String? // §4.1.10 — content type
  kid : String? // §4.1.4 — key ID
}

///|
/// Create a JWS header with the given algorithm.
pub fn JwsHeader::new(alg : String) -> JwsHeader {
  { alg, typ: None, cty: None, kid: None, }
}

///|
/// Set the `typ` header parameter.
pub fn JwsHeader::with_typ(self : JwsHeader, typ : String) -> JwsHeader {
  { ..self, typ: Some(typ), }
}

///|
/// Set the `kid` header parameter.
pub fn JwsHeader::with_kid(self : JwsHeader, kid : String) -> JwsHeader {
  { ..self, kid: Some(kid), }
}

///|
/// Set the `cty` header parameter.
pub fn JwsHeader::with_cty(self : JwsHeader, cty : String) -> JwsHeader {
  { ..self, cty: Some(cty), }
}

///|
/// Serialize a JwsHeader to a JSON object string (compact, no whitespace).
fn header_to_json(h : JwsHeader) -> String {
  let pairs : Array[(String, @json.JsonValue)] = []
  pairs.push(("alg", @json.json_str(h.alg)))
  match h.typ {
    Some(t) => pairs.push(("typ", @json.json_str(t)))
    None => ()
  }
  match h.kid {
    Some(k) => pairs.push(("kid", @json.json_str(k)))
    None => ()
  }
  match h.cty {
    Some(c) => pairs.push(("cty", @json.json_str(c)))
    None => ()
  }
  @json.stringify(@json.json_obj(pairs))
}

///|
/// Parse a JSON string into a JwsHeader.
fn parse_header(json_str : String) -> JwsHeader? {
  match @json.parse(json_str) {
    Some(v) =>
      match @json.get_str(v, "alg") {
        Some(alg) => {
          let typ = @json.get_str(v, "typ")
          let kid = @json.get_str(v, "kid")
          let cty = @json.get_str(v, "cty")
          Some({ alg, typ, kid, cty, })
        }
        None => None
      }
    None => None
  }
}

///|
/// Sign a payload and produce a JWS compact serialization token.
///
/// `header` specifies the algorithm and optional parameters.
/// `payload` is the raw payload bytes (e.g. JSON claims).
/// `key` is the HMAC signing key.
///
/// Returns the compact JWS string `bas1.0e64url(header).bas1.0e64url(payload).bas1.0e64url(signature)`,
/// or `None` if the algorithm is unsupported or the key is empty.
pub fn jws_sign(header : JwsHeader, payload : Bytes, key : Bytes) -> String? {
  if header.alg == "none" {
    // "none" algorithm: no signature, empty third segment.
    let header_json = header_to_json(header)
    let header_b64 = b64url_encode(@utils.string_to_bytes(header_json))
    let payload_b64 = b64url_encode(payload)
    Some(header_b64 + "." + payload_b64 + ".")
  } else {
    let header_json = header_to_json(header)
    let header_b64 = b64url_encode(@utils.string_to_bytes(header_json))
    let payload_b64 = b64url_encode(payload)
    let signing_input = @utils.string_to_bytes(header_b64 + "." + payload_b64)
    match compute_signature(header.alg, key, signing_input) {
      Some(sig) =>
        Some(header_b64 + "." + payload_b64 + "." + b64url_encode(sig))
      None => None
    }
  }
}

///|
/// Verification result for a JWS token.
pub struct JwsVerifyResult {
  header : JwsHeader
  payload : Bytes // raw payload bytes
  valid : Bool
}

///|
/// Verify a JWS compact serialization token.
///
/// `token` is the full `header.payload.signature` string.
/// `key` is the HMAC verification key.
/// `expected_alg` is the algorithm the caller expects (e.g. "HS256").
///   This is **mandatory** — never pass the algorithm from the token itself
///   without comparison, as that enables algorithm-confusion attacks.
///
/// Returns `None` if the token is malformed.  Returns a result with
/// `valid=false` if the signature does not match or the algorithm mismatches.
pub fn jws_verify(
  token : String,
  key : Bytes,
  expected_alg : String,
) -> JwsVerifyResult? {
  // Split into three parts.
  let parts = split_dot(token)
  if parts.length() != 3 {
    return None
  }
  let header_b64 = parts[0]
  let payload_b64 = parts[1]
  let signature_b64 = parts[2]
  // Decode header.
  let header_bytes = match b64url_decode(header_b64) {
    Some(b) => b
    None => return None
  }
  let header_json = @utils.bytes_to_string(header_bytes)
  let header = match parse_header(header_json) {
    Some(h) => h
    None => return None
  }
  // Decode payload.
  let payload = match b64url_decode(payload_b64) {
    Some(b) => b
    None => return None
  }
  // Algorithm cross-check (prevents algorithm confusion).
  if header.alg != expected_alg {
    return Some({ header, payload, valid: false, })
  }
  // Handle "none" algorithm.
  if header.alg == "none" {
    // Valid only if signature segment is empty.
    let valid = signature_b64.length() == 0
    return Some({ header, payload, valid, })
  }
  // Decode signature.
  let provided_sig = match b64url_decode(signature_b64) {
    Some(b) => b
    None => return Some({ header, payload, valid: false, })
  }
  // Recompute signature.
  let signing_input = @utils.string_to_bytes(header_b64 + "." + payload_b64)
  let expected_sig = match compute_signature(header.alg, key, signing_input) {
    Some(s) => s
    None => return Some({ header, payload, valid: false, })
  }
  // Constant-time comparison.
  if expected_sig.length() != provided_sig.length() {
    return Some({ header, payload, valid: false, })
  }
  let valid = @hmac.constant_time_eq(expected_sig, provided_sig)
  Some({ header, payload, valid, })
}

// ---------------------------------------------------------------------------
// JWT (RFC 7519) — Claims and Validation
// ---------------------------------------------------------------------------

///|
/// Standard JWT registered claims (RFC 7519 §4.1).
pub struct JwtClaims {
  iss : String? // §4.1.1 — issuer
  sub : String? // §4.1.2 — subject
  aud : String? // §4.1.3 — audience (single value)
  exp : Int64? // §4.1.4 — expiration time (Unix seconds)
  nbf : Int64? // §4.1.5 — not before (Unix seconds)
  iat : Int64? // §4.1.6 — issued at (Unix seconds)
  jti : String? // §4.1.7 — JWT ID
}

///|
/// Create empty JWT claims.
pub fn JwtClaims::new() -> JwtClaims {
  {
    iss: None,
    sub: None,
    aud: None,
    exp: None,
    nbf: None,
    iat: None,
    jti: None,
  }
}

///|
/// Set the `iss` (issuer) claim.
pub fn JwtClaims::with_iss(self : JwtClaims, iss : String) -> JwtClaims {
  { ..self, iss: Some(iss), }
}

///|
/// Set the `sub` (subject) claim.
pub fn JwtClaims::with_sub(self : JwtClaims, sub : String) -> JwtClaims {
  { ..self, sub: Some(sub), }
}

///|
/// Set the `aud` (audience) claim.
pub fn JwtClaims::with_aud(self : JwtClaims, aud : String) -> JwtClaims {
  { ..self, aud: Some(aud), }
}

///|
/// Set the `exp` (expiration time) claim.
pub fn JwtClaims::with_exp(self : JwtClaims, exp : Int64) -> JwtClaims {
  { ..self, exp: Some(exp), }
}

///|
/// Set the `nbf` (not before) claim.
pub fn JwtClaims::with_nbf(self : JwtClaims, nbf : Int64) -> JwtClaims {
  { ..self, nbf: Some(nbf), }
}

///|
/// Set the `iat` (issued at) claim.
pub fn JwtClaims::with_iat(self : JwtClaims, iat : Int64) -> JwtClaims {
  { ..self, iat: Some(iat), }
}

///|
/// Set the `jti` (JWT ID) claim.
pub fn JwtClaims::with_jti(self : JwtClaims, jti : String) -> JwtClaims {
  { ..self, jti: Some(jti), }
}

///|
/// Serialize JwtClaims to a JSON string.
///
/// Numeric claims (exp, nbf, iat) are encoded as JSON numbers.
fn claims_to_json(c : JwtClaims) -> String {
  let pairs : Array[(String, @json.JsonValue)] = []
  match c.iss {
    Some(v) => pairs.push(("iss", @json.json_str(v)))
    None => ()
  }
  match c.sub {
    Some(v) => pairs.push(("sub", @json.json_str(v)))
    None => ()
  }
  match c.aud {
    Some(v) => pairs.push(("aud", @json.json_str(v)))
    None => ()
  }
  match c.exp {
    Some(v) => pairs.push(("exp", @json.json_num(v.to_double())))
    None => ()
  }
  match c.nbf {
    Some(v) => pairs.push(("nbf", @json.json_num(v.to_double())))
    None => ()
  }
  match c.iat {
    Some(v) => pairs.push(("iat", @json.json_num(v.to_double())))
    None => ()
  }
  match c.jti {
    Some(v) => pairs.push(("jti", @json.json_str(v)))
    None => ()
  }
  @json.stringify(@json.json_obj(pairs))
}

///|
/// Parse a JSON string into JwtClaims.
///
/// Also extracts any non-standard claims into the returned `extra` map.
fn parse_claims(json_str : String) -> JwtClaims? {
  match @json.parse(json_str) {
    Some(v) =>
      match @json.as_object(v) {
        Some(obj) => {
          let mut claims = JwtClaims::new()
          for i = 0; i < obj.length(); i = i + 1 {
            let (key, val) = obj[i]
            match key {
              "iss" =>
                match @json.as_string(val) {
                  Some(s) => claims = { ..claims, iss: Some(s), }
                  None => ()
                }
              "sub" =>
                match @json.as_string(val) {
                  Some(s) => claims = { ..claims, sub: Some(s), }
                  None => ()
                }
              "aud" =>
                match @json.as_string(val) {
                  Some(s) => claims = { ..claims, aud: Some(s), }
                  None => ()
                }
              "exp" =>
                match @json.as_number(val) {
                  Some(n) => claims = { ..claims, exp: Some(n.to_int64()), }
                  None => ()
                }
              "nbf" =>
                match @json.as_number(val) {
                  Some(n) => claims = { ..claims, nbf: Some(n.to_int64()), }
                  None => ()
                }
              "iat" =>
                match @json.as_number(val) {
                  Some(n) => claims = { ..claims, iat: Some(n.to_int64()), }
                  None => ()
                }
              "jti" =>
                match @json.as_string(val) {
                  Some(s) => claims = { ..claims, jti: Some(s), }
                  None => ()
                }
              _ => () // non-standard claims ignored
            }
          }
          Some(claims)
        }
        None => None
      }
    None => None
  }
}

// ---------------------------------------------------------------------------
// JWT options
// ---------------------------------------------------------------------------

///|
/// Options for JWT verification.
pub struct JwtOptions {
  expected_alg : String // required: algorithm the caller expects
  allow_none : Bool // allow "none" algorithm (default: false)
  clock_skew : Int64 // tolerance for exp/nbf in seconds (default: 60)
  expected_iss : String? // expected issuer
  expected_aud : String? // expected audience
}

///|
/// Default JWT verification options.
///
/// Uses HS256, no "none", 60 s clock skew.
pub fn JwtOptions::default() -> JwtOptions {
  {
    expected_alg: "HS256",
    allow_none: false,
    clock_skew: 60L,
    expected_iss: None,
    expected_aud: None,
  }
}

///|
/// Set the expected algorithm.
pub fn JwtOptions::with_expected_alg(
  self : JwtOptions,
  alg : String,
) -> JwtOptions {
  { ..self, expected_alg: alg, }
}

///|
/// Set the expected issuer.
pub fn JwtOptions::with_expected_iss(
  self : JwtOptions,
  iss : String,
) -> JwtOptions {
  { ..self, expected_iss: Some(iss), }
}

///|
/// Set the expected audience.
pub fn JwtOptions::with_expected_aud(
  self : JwtOptions,
  aud : String,
) -> JwtOptions {
  { ..self, expected_aud: Some(aud), }
}

///|
/// Set the clock skew tolerance (seconds).
pub fn JwtOptions::with_clock_skew(
  self : JwtOptions,
  skew : Int64,
) -> JwtOptions {
  { ..self, clock_skew: skew, }
}

// ---------------------------------------------------------------------------
// JWT encode / decode / verify
// ---------------------------------------------------------------------------

///|
/// JWT verification error codes.
pub enum JwtError {
  Malformed // token structure is invalid
  InvalidSignature // signature verification failed
  AlgorithmMismatch // header alg ≠ expected
  NoneNotAllowed // "none" used but not permitted
  Expired // exp claim is in the past
  NotYetValid // nbf claim is in the future
  IssuerMismatch // iss claim ≠ expected
  AudienceMismatch // aud claim ≠ expected
}

///|
/// Verified JWT with decoded header and claims.
pub struct VerifiedJwt {
  header : JwsHeader
  claims : JwtClaims
  raw_payload : Bytes
}

///|
/// Encode (sign) a JWT token.
///
/// `claims` — the JWT claims to encode.
/// `key` — the HMAC signing key (must be non-empty for HS256/HS512).
/// `alg` — the signing algorithm ("HS256" or "HS512").
///
/// Returns the compact JWT string, or `None` if the algorithm is
/// unsupported or the key is empty.
pub fn jwt_encode(claims : JwtClaims, key : Bytes, alg : String) -> String? {
  let header = JwsHeader::new(alg).with_typ("JWT")
  let payload_json = claims_to_json(claims)
  let payload_bytes = @utils.string_to_bytes(payload_json)
  jws_sign(header, payload_bytes, key)
}

///|
/// Decode and verify a JWT token.
///
/// Performs full verification:
/// 1. Structural parsing (three bas1.0e64url segments)
/// 2. Signature verification (constant-time comparison)
/// 3. Algorithm cross-check (header alg must match `options.expected_alg`)
/// 4. "none" algorithm rejection (unless `options.allow_none`)
/// 5. `exp` claim validation (with clock skew tolerance)
/// 6. `nbf` claim validation (with clock skew tolerance)
/// 7. `iss` claim validation (if `options.expected_iss` is set)
/// 8. `aud` claim validation (if `options.expected_aud` is set)
///
/// Returns `Ok(VerifiedJwt)` on success, or `Err(JwtError)` on failure.
pub fn jwt_verify(
  token : String,
  key : Bytes,
  options : JwtOptions,
  now : Int64,
) -> Result[VerifiedJwt, JwtError] {
  // Step 1: JWS verification.
  let result = match jws_verify(token, key, options.expected_alg) {
    Some(r) => r
    None => return Err(Malformed)
  }
  // Step 2: Algorithm check.
  if !result.valid {
    // Could be algorithm mismatch or invalid signature.
    if result.header.alg != options.expected_alg {
      return Err(AlgorithmMismatch)
    }
    return Err(InvalidSignature)
  }
  // Step 3: "none" algorithm check.
  if result.header.alg == "none" && !options.allow_none {
    return Err(NoneNotAllowed)
  }
  // Step 4: Parse claims.
  let claims_json = @utils.bytes_to_string(result.payload)
  let claims = match parse_claims(claims_json) {
    Some(c) => c
    None => return Err(Malformed)
  }
  // Step 5: exp validation.
  match claims.exp {
    Some(exp) => if now > exp + options.clock_skew { return Err(Expired) }
    None => ()
  }
  // Step 6: nbf validation.
  match claims.nbf {
    Some(nbf) => if now + options.clock_skew < nbf { return Err(NotYetValid) }
    None => ()
  }
  // Step 7: iss validation.
  match options.expected_iss {
    Some(expected) =>
      match claims.iss {
        Some(actual) => if actual != expected { return Err(IssuerMismatch) }
        None => return Err(IssuerMismatch)
      }
    None => ()
  }
  // Step 8: aud validation.
  match options.expected_aud {
    Some(expected) =>
      match claims.aud {
        Some(actual) => if actual != expected { return Err(AudienceMismatch) }
        None => return Err(AudienceMismatch)
      }
    None => ()
  }
  Ok({ header: result.header, claims, raw_payload: result.payload, })
}

// ---------------------------------------------------------------------------
// Utility: extract header from token without verification
// ---------------------------------------------------------------------------

///|
/// Extract the JWS header from a token **without verification**.
///
/// **Warning**: This does NOT verify the signature.  Use only for
/// inspection (e.g.to determine which key to use) before calling
/// `jwt_verify`.
pub fn jwt_decode_header(token : String) -> JwsHeader? {
  let parts = split_dot(token)
  if parts.length() < 2 {
    return None
  }
  let header_bytes = match b64url_decode(parts[0]) {
    Some(b) => b
    None => return None
  }
  let header_json = @utils.bytes_to_string(header_bytes)
  parse_header(header_json)
}

///|
/// Extract claims from a token **without verification**.
///
/// **Warning**: This does NOT verify the signature.  Use only for
/// debugging or after `jwt_verify` has succeeded.
pub fn jwt_decode_claims(token : String) -> JwtClaims? {
  let parts = split_dot(token)
  if parts.length() < 3 {
    return None
  }
  let payload_bytes = match b64url_decode(parts[1]) {
    Some(b) => b
    None => return None
  }
  let claims_json = @utils.bytes_to_string(payload_bytes)
  parse_claims(claims_json)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "jose: b64url encode/decode round-trip" {
  let data = Bytes::from_array([
    b'\x00', b'\x01', b'\x02', b'\xFE', b'\xFF', b'\x48', b'\x69',
  ])
  let encoded = b64url_encode(data)
  let decoded = b64url_decode(encoded)
  assert_true(decoded is Some(_))
  match decoded {
    Some(d) => {
      assert_eq(d.length(), data.length())
      for i = 0; i < data.length(); i = i + 1 {
        assert_eq(d[i], data[i])
      }
    }
    None => assert_true(false)
  }
}

///|
test "jose: hmac_sha512 matches known vector" {
  // RFC 4231 Test Case 1: key = 0x0b*20, data = "Hi There"
  let key = Bytes::make(20, b'\x0b')
  let data = @utils.string_to_bytes("Hi There")
  let result = hmac_sha512(key, data)
  // Expected HMAC-SHA-512 (first 8 bytes): 87 aa 7c de a5 ef 61 9d
  assert_eq(result.length(), 64)
  assert_eq(result[0].to_int(), 0x87)
  assert_eq(result[1].to_int(), 0xAA)
  assert_eq(result[2].to_int(), 0x7C)
  assert_eq(result[3].to_int(), 0xDE)
}

///|
test "jose: jws_sign/verify HS256 round-trip" {
  let header = JwsHeader::new("HS256").with_typ("JWT").with_kid("key-1")
  let payload = @utils.string_to_bytes("{\"sub\":\"alice\",\"iss\":\"test\"}")
  let key = @utils.string_to_bytes("secret-key-2024")
  let token = match jws_sign(header, payload, key) {
    Some(t) => t
    None => {
      assert_true(false)
      return // unreachable
    }
  }
  // Token should have 3 segments.
  assert_eq(split_dot(token).length(), 3)
  // Verify.
  let result = match jws_verify(token, key, "HS256") {
    Some(r) => r
    None => {
      assert_true(false)
      return
    }
  }
  assert_true(result.valid)
  assert_eq(result.header.alg, "HS256")
  assert_eq(result.header.kid, Some("key-1"))
}

///|
test "jose: jws_sign/verify HS512 round-trip" {
  let header = JwsHeader::new("HS512")
  let payload = @utils.string_to_bytes("{\"test\":true}")
  let key = @utils.string_to_bytes("my-secret")
  let token = match jws_sign(header, payload, key) {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  let result = match jws_verify(token, key, "HS512") {
    Some(r) => r
    None => {
      assert_true(false)
      return
    }
  }
  assert_true(result.valid)
  assert_eq(result.header.alg, "HS512")
}

///|
test "jose: jws_verify rejects wrong key" {
  let header = JwsHeader::new("HS256")
  let payload = @utils.string_to_bytes("test")
  let key = @utils.string_to_bytes("correct-key")
  let token = match jws_sign(header, payload, key) {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  let wrong_key = @utils.string_to_bytes("wrong-key")
  let result = match jws_verify(token, wrong_key, "HS256") {
    Some(r) => r
    None => {
      assert_true(false)
      return
    }
  }
  assert_false(result.valid)
}

///|
test "jose: jws_verify rejects algorithm confusion" {
  // Sign with HS256, try to verify with expected_alg="none"
  let header = JwsHeader::new("HS256")
  let payload = @utils.string_to_bytes("test")
  let key = @utils.string_to_bytes("secret")
  let token = match jws_sign(header, payload, key) {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  // Should fail because header alg (HS256) ≠ expected_alg (none)
  let result = jws_verify(token, key, "none")
  assert_true(result is Some(_))
  match result {
    Some(r) => assert_false(r.valid)
    None => ()
  }
}

///|
test "jose: jws_verify rejects malformed token" {
  let key = @utils.string_to_bytes("secret")
  // Not enough segments.
  assert_true(jws_verify("abc.def", key, "HS256") is None)
  // Too many segments.
  assert_true(jws_verify("a.b.c.d", key, "HS256") is None)
  // Empty token.
  assert_true(jws_verify("", key, "HS256") is None)
}

///|
test "jose: jwt_encode/verify full lifecycle" {
  let claims = JwtClaims::new()
    .with_iss("https://issuer.example.com")
    .with_sub("user-12345")
    .with_aud("my-api")
    .with_exp(2000000000L) // far future
    .with_iat(1000000000L)
    .with_jti("token-id-abc")

  let key = @utils.string_to_bytes("super-secret-key")
  let token = match jwt_encode(claims, key, "HS256") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  // Verify with correct options.
  let options = JwtOptions::default()
    .with_expected_iss("https://issuer.example.com")
    .with_expected_aud("my-api")

  match jwt_verify(token, key, options, 1500000000L) {
    Ok(verified) => {
      assert_eq(verified.header.alg, "HS256")
      assert_eq(verified.claims.iss, Some("https://issuer.example.com"))
      assert_eq(verified.claims.sub, Some("user-12345"))
      assert_eq(verified.claims.aud, Some("my-api"))
      assert_eq(verified.claims.jti, Some("token-id-abc"))
    }
    Err(e) => {
      // Will print the error
      assert_true(false)
      ignore(e)
    }
  }
}

///|
test "jose: jwt_verify rejects expired token" {
  let claims = JwtClaims::new().with_exp(1000000000L) // past
  let key = @utils.string_to_bytes("secret")
  let token = match jwt_encode(claims, key, "HS256") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  let options = JwtOptions::default()
  match jwt_verify(token, key, options, 1500000000L) {
    Ok(_) => assert_true(false) // should have failed
    Err(Expired) => assert_true(true)
    Err(_) => assert_true(false)
  }
}

///|
test "jose: jwt_verify respects clock skew for exp" {
  // Token expired 30 seconds ago, with 60s skew → still valid.
  let now = 1000000000L
  let claims = JwtClaims::new().with_exp(now - 30L)
  let key = @utils.string_to_bytes("secret")
  let token = match jwt_encode(claims, key, "HS256") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  let options = JwtOptions::default() // clock_skew = 60
  match jwt_verify(token, key, options, now) {
    Ok(_) => assert_true(true) // within skew
    Err(_) => assert_true(false)
  }
  // Token expired 120 seconds ago, with 60s skew → invalid.
  let claims2 = JwtClaims::new().with_exp(now - 120L)
  let token2 = match jwt_encode(claims2, key, "HS256") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  match jwt_verify(token2, key, options, now) {
    Ok(_) => assert_true(false) // beyond skew
    Err(Expired) => assert_true(true)
    Err(_) => assert_true(false)
  }
}

///|
test "jose: jwt_verify rejects not-yet-valid token" {
  let now = 1000000000L
  let claims = JwtClaims::new().with_nbf(now + 100L)
  let key = @utils.string_to_bytes("secret")
  let token = match jwt_encode(claims, key, "HS256") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  let options = JwtOptions::default()
  match jwt_verify(token, key, options, now) {
    Ok(_) => assert_true(false)
    Err(NotYetValid) => assert_true(true)
    Err(_) => assert_true(false)
  }
}

///|
test "jose: jwt_verify rejects wrong issuer" {
  let claims = JwtClaims::new().with_iss("real-issuer")
  let key = @utils.string_to_bytes("secret")
  let token = match jwt_encode(claims, key, "HS256") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  let options = JwtOptions::default().with_expected_iss("fake-issuer")
  match jwt_verify(token, key, options, 1500000000L) {
    Ok(_) => assert_true(false)
    Err(IssuerMismatch) => assert_true(true)
    Err(_) => assert_true(false)
  }
}

///|
test "jose: jwt_verify rejects wrong audience" {
  let claims = JwtClaims::new().with_aud("expected-audience")
  let key = @utils.string_to_bytes("secret")
  let token = match jwt_encode(claims, key, "HS256") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  let options = JwtOptions::default().with_expected_aud("wrong-audience")
  match jwt_verify(token, key, options, 1500000000L) {
    Ok(_) => assert_true(false)
    Err(AudienceMismatch) => assert_true(true)
    Err(_) => assert_true(false)
  }
}

///|
test "jose: jwt_verify rejects none algorithm by default" {
  let header = JwsHeader::new("none")
  let payload = @utils.string_to_bytes("{\"sub\":\"test\"}")
  let key = @utils.string_to_bytes("secret")
  // Sign with "none" (no key needed).
  let token = match jws_sign(header, payload, key) {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  // Default options should reject "none".
  let options = { ..JwtOptions::default(), expected_alg: "none", }
  match jwt_verify(token, key, options, 1500000000L) {
    Ok(_) => assert_true(false) // should reject
    Err(NoneNotAllowed) => assert_true(true)
    Err(_) => assert_true(false)
  }
}

///|
test "jose: jwt_verify allows none when explicitly enabled" {
  let header = JwsHeader::new("none")
  let payload = @utils.string_to_bytes("{\"sub\":\"test\"}")
  let key = @utils.string_to_bytes("unused")
  let token = match jws_sign(header, payload, key) {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  let options : JwtOptions = {
    expected_alg: "none",
    allow_none: true,
    clock_skew: 60L,
    expected_iss: None,
    expected_aud: None,
  }
  match jwt_verify(token, key, options, 1500000000L) {
    Ok(verified) => assert_eq(verified.claims.sub, Some("test"))
    Err(_) => assert_true(false)
  }
}

///|
test "jose: jwt_decode_header without verification" {
  let claims = JwtClaims::new().with_sub("alice")
  let key = @utils.string_to_bytes("secret")
  let token = match jwt_encode(claims, key, "HS256") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  match jwt_decode_header(token) {
    Some(h) => {
      assert_eq(h.alg, "HS256")
      assert_eq(h.typ, Some("JWT"))
    }
    None => assert_true(false)
  }
}

///|
test "jose: jwt_decode_claims without verification" {
  let claims = JwtClaims::new()
    .with_sub("bob")
    .with_iss("issuer")
    .with_exp(2000000000L)
  let key = @utils.string_to_bytes("secret")
  let token = match jwt_encode(claims, key, "HS256") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  match jwt_decode_claims(token) {
    Some(c) => {
      assert_eq(c.sub, Some("bob"))
      assert_eq(c.iss, Some("issuer"))
      assert_eq(c.exp, Some(2000000000L))
    }
    None => assert_true(false)
  }
}

///|
test "jose: jwt_encode HS512 round-trip" {
  let claims = JwtClaims::new().with_sub("user").with_exp(2000000000L)
  let key = @utils.string_to_bytes("secret-key")
  let token = match jwt_encode(claims, key, "HS512") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  let options : JwtOptions = {
    expected_alg: "HS512",
    allow_none: false,
    clock_skew: 60L,
    expected_iss: None,
    expected_aud: None,
  }
  match jwt_verify(token, key, options, 1500000000L) {
    Ok(verified) => assert_eq(verified.claims.sub, Some("user"))
    Err(_) => assert_true(false)
  }
}

///|
test "jose: tampered payload rejected" {
  let claims = JwtClaims::new().with_sub("alice")
  let key = @utils.string_to_bytes("secret")
  let token = match jwt_encode(claims, key, "HS256") {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  // Tamper with the payload segment: replace with a different bas1.0e64url string.
  let parts = split_dot(token)
  // Create a different payload.
  let tampered_payload = b64url_encode(
    @utils.string_to_bytes("{\"sub\":\"eve\"}"),
  )
  let tampered = parts[0] + "." + tampered_payload + "." + parts[2]
  let options = JwtOptions::default()
  match jwt_verify(tampered, key, options, 1500000000L) {
    Ok(_) => assert_true(false) // should reject
    Err(InvalidSignature) => assert_true(true)
    Err(_) => assert_true(false)
  }
}

///|
test "jose: empty key rejected for HMAC" {
  let header = JwsHeader::new("HS256")
  let payload = @utils.string_to_bytes("test")
  let empty_key = Bytes::make(0, b'\x00')
  assert_true(jws_sign(header, payload, empty_key) is None)
}

///|
test "jose: jws_sign produces compact JSON header" {
  let header = JwsHeader::new("HS256").with_typ("JWT")
  let payload = @utils.string_to_bytes("x")
  let key = @utils.string_to_bytes("k")
  let token = match jws_sign(header, payload, key) {
    Some(t) => t
    None => {
      assert_true(false)
      return
    }
  }
  let parts = split_dot(token)
  let header_bytes = match b64url_decode(parts[0]) {
    Some(b) => b
    None => {
      assert_true(false)
      return
    }
  }
  let header_json = @utils.bytes_to_string(header_bytes)
  // Should not contain whitespace (compact JSON).
  assert_false(header_json.contains(" "))
  assert_false(header_json.contains("\n"))
}
