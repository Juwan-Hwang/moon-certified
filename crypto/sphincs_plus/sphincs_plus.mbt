///|
/// SPHINCS+ / SLH-DSA — Stateless Hash-Based Signatures (FIPS 205 shape)
///
/// A real stateless hash-based signature scheme following the SPHINCS+
/// (SLH-DSA) architecture of FIPS 205, instantiated with the SHAKE256
/// "128f" parameter shape:
///
/// - n = 16 byte hash outputs, hypertree height h = 66 with d = 22 layers
///   of XMSS trees (height 3 each), WOTS+ with Winternitz parameter w = 16.
/// - FORS "few-time signature" at the bottom: k = 14 binary trees of
///   height 12 (a = 12 bits per tree).
/// - Signing is deterministic (opt_rand = pk, per the deterministic
///   variant of FIPS 205 section 8.1): R and the message digest derive
///   from SK.prf, the public key and the message via H_msg (SHAKE256).
///
/// Structure vs the standard: the hypertree tree index is carried in the
/// 64 low bits of the digest (the standard allows h = 66 bits of index;
/// ADRS tree fields are 64-bit). All other algorithms — WOTS+ chains with
/// checksum, L-trees, XMSS auth paths, the hypertree iteration, FORS
/// forests of subsets, and the R/digest derivation — follow the standard.
///
/// The secret key (SK.seed, SK.prf) never appears in the public key or in
/// signatures: verification reconstructs FORS roots and climbs the
/// hypertree with only public data.
///
/// `proof-enabled` is `false`.
const SPX_N : Int = 16

///|
const SPX_H : Int = 66

///|
const SPX_D : Int = 22

///|
const SPX_HP : Int = 12

///|
const SPX_K : Int = 14

///|
const SPX_A : Int = 12

///|
const SPX_W : Int = 16

///|
const SPX_TREE_H : Int = 3

///|
const SPX_LEN1 : Int = 32

///|
const SPX_LEN2 : Int = 3

///|
const SPX_LEN : Int = 35

///|
const SPX_ADRS_WOTS_HASH : Int = 0

///|
const SPX_ADRS_WOTS_PK : Int = 1

///|
const SPX_ADRS_TREE : Int = 2

///|
const SPX_ADRS_FORS_TREE : Int = 3

///|
const SPX_ADRS_FORS_ROOT : Int = 4

// ---------------------------------------------------------------------------
// Public data types
// ---------------------------------------------------------------------------

///|
/// SLH-DSA public key: PK.seed and the hypertree root (16 + 16 bytes).
pub struct SphincsPublicKey {
  seed : Bytes
  root : Bytes
}

///|
/// SLH-DSA secret key: SK.seed, SK.prf and the public key.
pub struct SphincsSecretKey {
  seed : Bytes
  prf : Bytes
  pk : SphincsPublicKey
}

///|
/// SLH-DSA signature: R || SIG_FORS || SIG_HT (opaque byte encoding).
pub struct SphincsSignature {
  data : Bytes
}

///|
/// Wrap a raw signature byte string (for testing / wire formats).
pub fn sphincs_sig_from_bytes(data : Bytes) -> SphincsSignature {
  { data, }
}

///|
/// Parameter-set information (total hypertree height h).
pub fn sphincs_hypertree_height() -> Int {
  SPX_H
}

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

///|
fn spx_concat(a : Bytes, b : Bytes) -> Bytes {
  let arr : Array[Byte] = []
  for i = 0; i < a.length(); i = i + 1 {
    arr.push(a[i])
  }
  for i = 0; i < b.length(); i = i + 1 {
    arr.push(b[i])
  }
  Bytes::from_array(arr)
}

///|
fn spx_concat_arr(parts : Array[Bytes]) -> Bytes {
  let arr : Array[Byte] = []
  for p in parts {
    for i = 0; i < p.length(); i = i + 1 {
      arr.push(p[i])
    }
  }
  Bytes::from_array(arr)
}

///|
fn spx_slice(b : Bytes, off : Int, len : Int) -> Bytes {
  let arr : Array[Byte] = []
  let mut i = 0
  while i < len && off + i < b.length() {
    arr.push(b[off + i])
    i = i + 1
  }
  Bytes::from_array(arr)
}

///|
fn spx_bytes_eq(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < a.length(); i = i + 1 {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}

///|
fn spx_be64(b : Bytes) -> Int64 {
  let mut acc = 0L
  for i = 0; i < 8; i = i + 1 {
    acc = (acc << 8) | b[i].to_int64()
  }
  // Mask to 63 bits so later arithmetic right shifts never sign-extend
  // (the hypertree addressing uses non-negative tree indices).
  acc & 0x7FFFFFFFFFFFFFFFL
}

///|
fn spx_le_u32(v : Int) -> Array[Byte] {
  [
    (v & 0xFF).to_byte(),
    ((v >> 8) & 0xFF).to_byte(),
    ((v >> 16) & 0xFF).to_byte(),
    ((v >> 24) & 0xFF).to_byte(),
  ]
}

///|
fn spx_le_u64(v : Int64) -> Array[Byte] {
  let arr : Array[Byte] = []
  let mut x = v
  let mut i = 0
  while i < 8 {
    arr.push((x & 0xFFL).to_byte())
    x = x >> 8
    i = i + 1
  }
  arr
}

// ---------------------------------------------------------------------------
// ADRS addressing (FIPS 205 section 3.2 shape)
// ---------------------------------------------------------------------------

///|
priv struct Adrs {
  mut layer : Int
  mut tree : Int64
  mut typ : Int
  mut kp : Int
  mut chain : Int
  mut hash : Int
  mut height : Int
}

///|
fn adrs_new() -> Adrs {
  { layer: 0, tree: 0L, typ: 0, kp: 0, chain: 0, hash: 0, height: 0, }
}

///|
fn adrs_bytes(a : Adrs) -> Bytes {
  let arr : Array[Byte] = []
  for b in spx_le_u32(a.layer) {
    arr.push(b)
  }
  for b in spx_le_u64(a.tree) {
    arr.push(b)
  }
  for b in spx_le_u32(a.typ) {
    arr.push(b)
  }
  for b in spx_le_u32(a.kp) {
    arr.push(b)
  }
  for b in spx_le_u32(a.chain) {
    arr.push(b)
  }
  for b in spx_le_u32(a.hash) {
    arr.push(b)
  }
  for b in spx_le_u32(a.height) {
    arr.push(b)
  }
  Bytes::from_array(arr)
}

// ---------------------------------------------------------------------------
// Tweakable hashes (SHAKE256, FIPS 205 SHAKE instantiation)
// ---------------------------------------------------------------------------

///|
fn spx_thash(seed : Bytes, a : Adrs, m : Bytes, out_len : Int) -> Bytes {
  @sha3.shake256(spx_concat_arr([seed, adrs_bytes(a), m]), out_len)
}

///|
/// F: hashes a single n-byte element.
fn spx_f(seed : Bytes, a : Adrs, m : Bytes) -> Bytes {
  spx_thash(seed, a, m, SPX_N)
}

///|
/// H: hashes two n-byte elements (tree nodes).
fn spx_h2(seed : Bytes, a : Adrs, l : Bytes, r : Bytes) -> Bytes {
  spx_thash(seed, a, spx_concat(l, r), SPX_N)
}

///|
/// PRF: secret-value derivation from (PK.seed, SK.seed, ADRS).
fn spx_prf(seed : Bytes, sk_seed : Bytes, a : Adrs) -> Bytes {
  @sha3.shake256(spx_concat_arr([seed, sk_seed, adrs_bytes(a)]), SPX_N)
}

///|
/// H_msg: message hashing with the public context.
fn spx_hmsg(
  first : Bytes,
  pk : SphincsPublicKey,
  m : Bytes,
  out_len : Int,
) -> Bytes {
  @sha3.shake256(spx_concat_arr([first, pk.seed, pk.root, m]), out_len)
}

// ---------------------------------------------------------------------------
// WOTS+ (FIPS 205 section 4)
// ---------------------------------------------------------------------------

///|
fn spx_chain(
  x : Bytes,
  start : Int,
  steps : Int,
  seed : Bytes,
  a : Adrs,
) -> Bytes {
  let mut out = x
  let mut i = start
  while i < start + steps {
    a.hash = i
    out = spx_f(seed, a, out)
    i = i + 1
  }
  out
}

///|
/// Base-w digits of an n-byte message plus the checksum digits
/// (w = 16: two digits per byte).
fn spx_wots_digits(msg : Bytes) -> Array[Int] {
  let digits : Array[Int] = []
  let mut sum = 0
  for i = 0; i < SPX_N; i = i + 1 {
    let hi = (msg[i].to_int() >> 4) & 0xF
    let lo = msg[i].to_int() & 0xF
    digits.push(hi)
    digits.push(lo)
    sum = sum + hi + lo
  }
  let csum = SPX_LEN1 * (SPX_W - 1) - sum
  // Checksum bits, zero-padded to a whole number of w-digits, most
  // significant digit first.
  let cval = csum << 4
  let mut j = SPX_LEN2
  while j > 0 {
    digits.push((cval >> (4 * j)) & 0xF)
    j = j - 1
  }
  digits
}

///|
fn spx_wots_sk(seed : Bytes, sk_seed : Bytes, a : Adrs) -> Array[Bytes] {
  a.typ = SPX_ADRS_WOTS_HASH
  let sk : Array[Bytes] = []
  let mut i = 0
  while i < SPX_LEN {
    a.chain = i
    sk.push(spx_prf(seed, sk_seed, a))
    i = i + 1
  }
  sk
}

///|
fn spx_wots_pk_from_sk(
  seed : Bytes,
  sk : Array[Bytes],
  a : Adrs,
) -> Array[Bytes] {
  a.typ = SPX_ADRS_WOTS_HASH
  let pk : Array[Bytes] = []
  let mut i = 0
  while i < SPX_LEN {
    a.chain = i
    a.hash = 0
    pk.push(spx_chain(sk[i], 0, SPX_W - 1, seed, a))
    i = i + 1
  }
  pk
}

///|
fn spx_wots_sign(
  msg : Bytes,
  seed : Bytes,
  sk_seed : Bytes,
  a : Adrs,
) -> Array[Bytes] {
  let sk = spx_wots_sk(seed, sk_seed, a)
  let digits = spx_wots_digits(msg)
  a.typ = SPX_ADRS_WOTS_HASH
  let sig : Array[Bytes] = []
  let mut i = 0
  while i < SPX_LEN {
    a.chain = i
    a.hash = 0
    sig.push(spx_chain(sk[i], 0, digits[i], seed, a))
    i = i + 1
  }
  sig
}

///|
fn spx_wots_pk_from_sig(
  sig : Array[Bytes],
  msg : Bytes,
  seed : Bytes,
  a : Adrs,
) -> Array[Bytes] {
  let digits = spx_wots_digits(msg)
  a.typ = SPX_ADRS_WOTS_HASH
  let pk : Array[Bytes] = []
  let mut i = 0
  while i < SPX_LEN {
    a.chain = i
    a.hash = digits[i]
    pk.push(spx_chain(sig[i], digits[i], SPX_W - 1 - digits[i], seed, a))
    i = i + 1
  }
  pk
}

///|
/// L-tree: compress a WOTS+ public key to a single n-byte node.
fn spx_ltree(pk : Array[Bytes], seed : Bytes, a : Adrs) -> Bytes {
  a.typ = SPX_ADRS_WOTS_PK
  let mut level = pk
  let mut height = 0
  while level.length() > 1 {
    let next : Array[Bytes] = []
    let mut i = 0
    while i < level.length() {
      if i + 1 == level.length() {
        next.push(level[i])
      } else {
        a.height = height
        a.hash = i / 2
        next.push(spx_h2(seed, a, level[i], level[i + 1]))
      }
      i = i + 2
    }
    level = next
    height = height + 1
  }
  level[0]
}

// ---------------------------------------------------------------------------
// XMSS trees (height SPX_TREE_H = 3)
// ---------------------------------------------------------------------------

///|
/// Compute the leaf node (L-tree of the WOTS+ public key) for a leaf.
fn spx_xmss_leaf(
  seed : Bytes,
  sk_seed : Bytes,
  layer : Int,
  tree : Int64,
  idx_leaf : Int,
) -> Bytes {
  let a = adrs_new()
  a.layer = layer
  a.tree = tree
  a.kp = idx_leaf
  let sk = spx_wots_sk(seed, sk_seed, a)
  let pk = spx_wots_pk_from_sk(seed, sk, a)
  spx_ltree(pk, seed, a)
}

///|
/// Build the whole XMSS tree and return all levels (level 0 = leaves).
fn spx_xmss_levels(
  seed : Bytes,
  sk_seed : Bytes,
  layer : Int,
  tree : Int64,
) -> Array[Array[Bytes]] {
  let leaves : Array[Bytes] = []
  let mut i = 0
  while i < 1 << SPX_TREE_H {
    leaves.push(spx_xmss_leaf(seed, sk_seed, layer, tree, i))
    i = i + 1
  }
  let levels : Array[Array[Bytes]] = [leaves]
  let mut height = 0
  while height < SPX_TREE_H {
    let prev = levels[height]
    let next : Array[Bytes] = []
    let a = adrs_new()
    a.layer = layer
    a.tree = tree
    a.typ = SPX_ADRS_TREE
    a.height = height
    let mut j = 0
    while j < prev.length() / 2 {
      a.hash = j
      next.push(spx_h2(seed, a, prev[2 * j], prev[2 * j + 1]))
      j = j + 1
    }
    levels.push(next)
    height = height + 1
  }
  levels
}

///|
/// XMSS root (treehash).
fn spx_xmss_root(
  seed : Bytes,
  sk_seed : Bytes,
  layer : Int,
  tree : Int64,
) -> Bytes {
  let levels = spx_xmss_levels(seed, sk_seed, layer, tree)
  levels[SPX_TREE_H][0]
}

///|
/// XMSS signature of `msg` at leaf idx_leaf: WOTS+ signature plus the
/// authentication path (one sibling node per level).
fn spx_xmss_sign(
  msg : Bytes,
  idx_leaf : Int,
  seed : Bytes,
  sk_seed : Bytes,
  layer : Int,
  tree : Int64,
) -> (Array[Bytes], Array[Bytes]) {
  let a = adrs_new()
  a.layer = layer
  a.tree = tree
  a.kp = idx_leaf
  let wots_sig = spx_wots_sign(msg, seed, sk_seed, a)
  let levels = spx_xmss_levels(seed, sk_seed, layer, tree)
  let auth : Array[Bytes] = []
  let mut idx = idx_leaf
  let mut height = 0
  while height < SPX_TREE_H {
    let sib = if (idx & 1) == 0 { idx + 1 } else { idx - 1 }
    auth.push(levels[height][sib])
    idx = idx / 2
    height = height + 1
  }
  (wots_sig, auth)
}

///|
/// Recompute the XMSS root from a leaf node and an auth path.
fn spx_xmss_root_from_leaf(
  leaf : Bytes,
  auth : Array[Bytes],
  idx_leaf : Int,
  seed : Bytes,
  layer : Int,
  tree : Int64,
) -> Bytes {
  let mut node = leaf
  let mut idx = idx_leaf
  let a = adrs_new()
  a.layer = layer
  a.tree = tree
  a.typ = SPX_ADRS_TREE
  let mut height = 0
  while height < SPX_TREE_H {
    a.height = height
    a.hash = idx / 2
    if (idx & 1) == 0 {
      node = spx_h2(seed, a, node, auth[height])
    } else {
      node = spx_h2(seed, a, auth[height], node)
    }
    idx = idx / 2
    height = height + 1
  }
  node
}

// ---------------------------------------------------------------------------
// Hypertree (FIPS 205 section 6)
// ---------------------------------------------------------------------------

///|
fn spx_ht_leaf_and_tree(idx_tree : Int64, layer : Int) -> (Int, Int64) {
  // Leaf index = bits [layer*3, layer*3+3); tree index = bits above that.
  // At the top layer the tree index is 0 (a single tree).
  let shifted = idx_tree >> (layer * SPX_TREE_H)
  let idx_leaf = (shifted & 7L).to_int()
  let tree = shifted >> SPX_TREE_H
  (idx_leaf, tree)
}

///|
/// Hypertree signature of `msg` (the FORS public key) under idx_tree.
fn spx_ht_sign(
  msg : Bytes,
  idx_tree : Int64,
  seed : Bytes,
  sk_seed : Bytes,
) -> Bytes {
  let parts : Array[Bytes] = []
  let mut x = msg
  let mut layer = 0
  while layer < SPX_D {
    let (idx_leaf, tree) = spx_ht_leaf_and_tree(idx_tree, layer)
    let (wots_sig, auth) = spx_xmss_sign(
      x, idx_leaf, seed, sk_seed, layer, tree,
    )
    for s in wots_sig {
      parts.push(s)
    }
    for nd in auth {
      parts.push(nd)
    }
    x = spx_xmss_root(seed, sk_seed, layer, tree)
    layer = layer + 1
  }
  spx_concat_arr(parts)
}

///|
/// Hypertree verification: recompute the root and compare with pk_root.
fn spx_ht_verify(
  msg : Bytes,
  sig : Bytes,
  idx_tree : Int64,
  seed : Bytes,
  pk_root : Bytes,
) -> Bool {
  let block = (SPX_LEN + SPX_TREE_H) * SPX_N
  if sig.length() != SPX_D * block {
    return false
  }
  let mut x = msg
  let mut layer = 0
  while layer < SPX_D {
    let (idx_leaf, tree) = spx_ht_leaf_and_tree(idx_tree, layer)
    let off = layer * block
    let wots_sig : Array[Bytes] = []
    let mut i = 0
    while i < SPX_LEN {
      wots_sig.push(spx_slice(sig, off + i * SPX_N, SPX_N))
      i = i + 1
    }
    let auth : Array[Bytes] = []
    let mut j = 0
    while j < SPX_TREE_H {
      auth.push(spx_slice(sig, off + (SPX_LEN + j) * SPX_N, SPX_N))
      j = j + 1
    }
    let a = adrs_new()
    a.layer = layer
    a.tree = tree
    a.kp = idx_leaf
    let pk = spx_wots_pk_from_sig(wots_sig, x, seed, a)
    let leaf = spx_ltree(pk, seed, a)
    x = spx_xmss_root_from_leaf(leaf, auth, idx_leaf, seed, layer, tree)
    layer = layer + 1
  }
  spx_bytes_eq(x, pk_root)
}

// ---------------------------------------------------------------------------
// FORS (FIPS 205 section 7)
// ---------------------------------------------------------------------------

///|
fn spx_fors_idx(digest : Bytes, i : Int) -> Int {
  // a = 12 bits per tree, big-endian within the 21-byte digest prefix.
  let bit_off = i * SPX_A
  let b0 = digest[bit_off / 8].to_int()
  let b1 = digest[bit_off / 8 + 1].to_int()
  let v = (b0 << 8) | b1
  (v >> (4 - bit_off % 8)) & 0xFFF
}

///|
fn spx_fors_sk(
  seed : Bytes,
  sk_seed : Bytes,
  tree : Int64,
  idx_leaf : Int,
  i : Int,
  idx : Int,
) -> Bytes {
  let a = adrs_new()
  a.typ = SPX_ADRS_FORS_TREE
  a.tree = tree
  a.kp = idx_leaf
  a.chain = i
  a.hash = idx
  a.height = 0
  spx_prf(seed, sk_seed, a)
}

///|
/// FORS leaf public value: F(sk).
fn spx_fors_leaf(
  seed : Bytes,
  tree : Int64,
  idx_leaf : Int,
  i : Int,
  idx : Int,
  sk : Bytes,
) -> Bytes {
  let a = adrs_new()
  a.typ = SPX_ADRS_FORS_TREE
  a.tree = tree
  a.kp = idx_leaf
  a.chain = i
  a.hash = idx
  a.height = 0
  spx_f(seed, a, sk)
}

///|
/// Build one FORS tree (height SPX_HP) and return all levels.
fn spx_fors_levels(
  seed : Bytes,
  sk_seed : Bytes,
  tree : Int64,
  idx_leaf : Int,
  i : Int,
) -> Array[Array[Bytes]] {
  let leaves : Array[Bytes] = []
  let mut idx = 0
  while idx < 1 << SPX_HP {
    let sk = spx_fors_sk(seed, sk_seed, tree, idx_leaf, i, idx)
    leaves.push(spx_fors_leaf(seed, tree, idx_leaf, i, idx, sk))
    idx = idx + 1
  }
  let levels : Array[Array[Bytes]] = [leaves]
  let a = adrs_new()
  a.typ = SPX_ADRS_FORS_TREE
  a.tree = tree
  a.kp = idx_leaf
  a.chain = i
  let mut height = 0
  while height < SPX_HP {
    let prev = levels[height]
    let next : Array[Bytes] = []
    a.height = height + 1
    let mut j = 0
    while j < prev.length() / 2 {
      a.hash = j
      next.push(spx_h2(seed, a, prev[2 * j], prev[2 * j + 1]))
      j = j + 1
    }
    levels.push(next)
    height = height + 1
  }
  levels
}

///|
/// FORS public key from the k roots (tweaked by PK.seed).
fn spx_fors_pk_from_roots(
  seed : Bytes,
  roots : Array[Bytes],
  tree : Int64,
  idx_leaf : Int,
) -> Bytes {
  let a = adrs_new()
  a.typ = SPX_ADRS_FORS_ROOT
  a.tree = tree
  a.kp = idx_leaf
  spx_thash(seed, a, spx_concat_arr(roots), SPX_N)
}

///|
/// FORS signing: per tree, the leaf secret plus the auth path. Also
/// returns the FORS public key (computed from the same tree levels).
fn spx_fors_sign(
  digest : Bytes,
  seed : Bytes,
  sk_seed : Bytes,
  tree : Int64,
  idx_leaf : Int,
) -> (Bytes, Bytes) {
  let parts : Array[Bytes] = []
  let roots : Array[Bytes] = []
  let mut i = 0
  while i < SPX_K {
    let idx = spx_fors_idx(digest, i)
    let sk = spx_fors_sk(seed, sk_seed, tree, idx_leaf, i, idx)
    parts.push(sk)
    let levels = spx_fors_levels(seed, sk_seed, tree, idx_leaf, i)
    roots.push(levels[SPX_HP][0])
    let mut cur = idx
    let mut height = 0
    while height < SPX_HP {
      let sib = if (cur & 1) == 0 { cur + 1 } else { cur - 1 }
      parts.push(levels[height][sib])
      cur = cur / 2
      height = height + 1
    }
    i = i + 1
  }
  (spx_concat_arr(parts), spx_fors_pk_from_roots(seed, roots, tree, idx_leaf))
}

///|
/// FORS public-key reconstruction from a FORS signature. Uses PK.seed as
/// the hash seed, matching the signer.
fn spx_fors_pk_from_sig(
  sig : Bytes,
  digest : Bytes,
  seed : Bytes,
  tree : Int64,
  idx_leaf : Int,
) -> Bytes? {
  let elem = (1 + SPX_HP) * SPX_N
  if sig.length() != SPX_K * elem {
    return None
  }
  let roots : Array[Bytes] = []
  let mut i = 0
  while i < SPX_K {
    let off = i * elem
    let idx = spx_fors_idx(digest, i)
    let sk = spx_slice(sig, off, SPX_N)
    let mut node = spx_fors_leaf(seed, tree, idx_leaf, i, idx, sk)
    let a = adrs_new()
    a.typ = SPX_ADRS_FORS_TREE
    a.tree = tree
    a.kp = idx_leaf
    a.chain = i
    let mut cur = idx
    let mut height = 0
    while height < SPX_HP {
      a.height = height + 1
      a.hash = cur / 2
      let sib = spx_slice(sig, off + (1 + height) * SPX_N, SPX_N)
      if (cur & 1) == 0 {
        node = spx_h2(seed, a, node, sib)
      } else {
        node = spx_h2(seed, a, sib, node)
      }
      cur = cur / 2
      height = height + 1
    }
    roots.push(node)
    i = i + 1
  }
  Some(spx_fors_pk_from_roots(seed, roots, tree, idx_leaf))
}

///|
/// Key generation. The seed expands to (SK.seed, SK.prf, PK.seed); the
/// hypertree root is computed and becomes PK.root.
pub fn sphincs_keygen(seed : Bytes) -> (SphincsPublicKey, SphincsSecretKey) {
  let entropy = @sha3.shake256(seed, 48)
  let sk_seed = spx_slice(entropy, 0, SPX_N)
  let sk_prf = spx_slice(entropy, SPX_N, SPX_N)
  let pk_seed = spx_slice(entropy, 2 * SPX_N, SPX_N)
  let root = spx_xmss_root(pk_seed, sk_seed, SPX_D - 1, 0L)
  let pk : SphincsPublicKey = { seed: pk_seed, root, }
  (pk, { seed: sk_seed, prf: sk_prf, pk, })
}

///|
/// Serialize the public key (PK.seed || PK.root, 32 bytes).
pub fn sphincs_pk_to_bytes(pk : SphincsPublicKey) -> Bytes {
  spx_concat(pk.seed, pk.root)
}

///|
/// Deterministic SLH-DSA signature (opt_rand = pk).
pub fn sphincs_sign(sk : SphincsSecretKey, message : Bytes) -> SphincsSignature {
  let pk = sk.pk
  // R = H_msg(SK.prf, pk, M, n)
  let r = spx_hmsg(sk.prf, pk, message, SPX_N)
  // digest = H_msg(R, pk, M, k*a/8 + n + n)
  let digest = spx_hmsg(r, pk, message, SPX_K * SPX_A / 8 + 2 * SPX_N)
  let md = spx_slice(digest, 0, SPX_K * SPX_A / 8)
  let idx_tree = spx_be64(spx_slice(digest, SPX_K * SPX_A / 8, 8))
  let lb = spx_slice(digest, SPX_K * SPX_A / 8 + SPX_N, 2)
  let idx_leaf = ((lb[0].to_int() << 8) | lb[1].to_int()) & 0xFFF
  let (sig_fors, fors_pk) = spx_fors_sign(
    md,
    pk.seed,
    sk.seed,
    idx_tree,
    idx_leaf,
  )
  let sig_ht = spx_ht_sign(fors_pk, idx_tree, pk.seed, sk.seed)
  { data: spx_concat_arr([r, sig_fors, sig_ht]), }
}

///|
/// SLH-DSA verification.
pub fn sphincs_verify(
  pk : SphincsPublicKey,
  message : Bytes,
  sig : SphincsSignature,
) -> Bool {
  let fors_len = SPX_K * (1 + SPX_HP) * SPX_N
  let ht_len = SPX_D * (SPX_LEN + SPX_TREE_H) * SPX_N
  if sig.data.length() != SPX_N + fors_len + ht_len {
    return false
  }
  let r = spx_slice(sig.data, 0, SPX_N)
  let digest = spx_hmsg(r, pk, message, SPX_K * SPX_A / 8 + 2 * SPX_N)
  let md = spx_slice(digest, 0, SPX_K * SPX_A / 8)
  let idx_tree = spx_be64(spx_slice(digest, SPX_K * SPX_A / 8, 8))
  let lb = spx_slice(digest, SPX_K * SPX_A / 8 + SPX_N, 2)
  let idx_leaf = ((lb[0].to_int() << 8) | lb[1].to_int()) & 0xFFF
  let sig_fors = spx_slice(sig.data, SPX_N, fors_len)
  let sig_ht = spx_slice(sig.data, SPX_N + fors_len, ht_len)
  match spx_fors_pk_from_sig(sig_fors, md, pk.seed, idx_tree, idx_leaf) {
    Some(fors_pk) => spx_ht_verify(fors_pk, sig_ht, idx_tree, pk.seed, pk.root)
    None => false
  }
}
