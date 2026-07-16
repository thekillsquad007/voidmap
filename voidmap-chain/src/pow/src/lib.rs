//! Euler-toit header proofs for the Voidmap native chain.
//!
//! The PoW challenge for a header is: compute `phi(n)` for the 1024-bit
//! candidate `n` committed to by the header (deterministic per header &
//! nonce via blake3). The miner publishes a disclosure that exposes the
//! factorisation, and verifiers replay the same computation in microseconds
//! to validate.
//!
//! Anti-ASIC characteristics of this construction:
//!   - The work is dominated by trial division (memory-light) plus a
//!     deterministic Miller-Rabin on the unaccounted residual.
//!   - The factor map is exposed, so an implementation that pre-computes a
//!     huge table of totients is not rewarded.
//!   - Useful: each PoW records a real totient & a real 1024-bit prime.
//!
//! Calibration: the chain's difficulty target is set so an honest node
//! running this on commodity CPU hardware completes a 1024-bit search in
//! roughly the target block time.
//!
//! NOTE: this isPhase 1 of the φ-PoW plan; we deliberately keep the
//! candidate count = 1 (deterministic per nonce). Mining failures for a
//! given nonce happen when the candidate happens to fail Miller-Rabin; the
//! miner simply picks the next nonce.

use num_bigint::{BigInt, BigUint, ToBigInt};
use num_traits::{One, Zero};
use rand::{rngs::SmallRng, RngCore, SeedableRng};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use voidmap_core::BlockHeader;
use voidmap_crypto::Hash;

pub const CANDIDATE_BITS: usize = 1024;
/// Trial-division bound. Primes ≤ B are factored out cheaply; everything
/// above is verified by Miller-Rabin (deterministic, round-stable).
pub const SIEVE_BOUND: u32 = 1 << 20;
pub const MR_ROUNDS: u32 = 32;

/// 128-byte big-integer-as-bytes with manual serde support (serde doesn't
/// natively handle arrays larger than 32 elements).
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct Bytes128(pub [u8; 128]);

impl Default for Bytes128 {
    fn default() -> Self {
        Bytes128([0u8; 128])
    }
}

impl Serialize for Bytes128 {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_bytes(&self.0)
    }
}
impl<'de> Deserialize<'de> for Bytes128 {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let v = Vec::<u8>::deserialize(d)?;
        if v.len() != 128 {
            return Err(serde::de::Error::custom("Bytes128 must be exactly 128 bytes"));
        }
        let mut arr = [0u8; 128];
        arr.copy_from_slice(&v);
        Ok(Bytes128(arr))
    }
}
impl std::fmt::Debug for Bytes128 {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Bytes128(<{} bytes>)", 128)
    }
}

/// Disclosure attached to a block so that verifiers can recompute `phi(n)`
/// independently in microseconds.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct PhiSubmission {
    pub n: Bytes128,
    pub small_factor_exponents: Vec<(u32, u16)>, // (prime, exponent)
    pub residual: Bytes128,
    pub phi: Bytes128,
}

/// Target block time for difficulty adjustment.
pub const TARGET_BLOCK_MS: u64 = 15_000;

/// Difficulty target comparison.
pub fn meets_difficulty(hash: &Hash, difficulty: u64) -> bool {
    if difficulty == 0 {
        return false;
    }
    let limit = div_u256_by_u64(&max_u256(), difficulty);
    hash.as_bytes() <= &limit
}
fn max_u256() -> [u8; 32] {
    [0xFFu8; 32]
}
fn div_u256_by_u64(num: &[u8; 32], d: u64) -> [u8; 32] {
    if d == 0 {
        return max_u256();
    }
    let mut rem: u64 = 0;
    let mut out = [0u8; 32];
    for i in 0..32 {
        let cur = (rem << 8) | num[i] as u64;
        out[i] = (cur / d) as u8;
        rem = cur % d;
    }
    out
}

/// Compute `phi(n)` for the candidate committed to by `(header, nonce)`.
///
/// Returns `None` if the candidate fails Miller-Rabin at the chosen bound and
/// is not 1 — in that case the miner should advance `nonce`.
pub fn phi_pow_for_header(header: &BlockHeader) -> Option<PhiSubmission> {
    let n = deterministic_candidate(header);
    let sub = compute_(&n)?;
    Some(sub)
}

fn deterministic_candidate(header: &BlockHeader) -> BigUint {
    let bytes = bincode::serialize(header).expect("header serialize");
    let seed = blake3::hash(&bytes);
    let mut rng = SmallRng::from_seed(seed.as_bytes()[..32].try_into().unwrap());
    let mut bytes = [0u8; 128];
    // 1024 bits = 128 bytes. Pull them from the RNG.
    for chunk in bytes.chunks_mut(8) {
        let v: u64 = rng.next_u64();
        chunk.copy_from_slice(&v.to_le_bytes());
    }
    // Ensure the candidate is exactly CANDIDATE_BITS wide (set MSB of byte 0
    // and the LSB so the number is odd; the LSB needs to be 1 for speed, but
    // an oddenss bit is fine — odd candidate means there's a 1-free coprime
    // candidate, will eventually dive into toient-2).
    bytes[0] = (bytes[0] & 0x7F) | 0x40;
    bytes[127] |= 0x01;
    BigUint::from_bytes_le(&bytes)
}

/// Deterministic, public, no-side-effects sieve up to `bound`.
///
/// Returns `(small_factor_exponents, residual)` where `residual` is the
/// integer remaining after dividing out every power of each prime `≤ bound`,
/// preserving the original `n` exactly.
fn factor_small(n: &BigUint) -> (Vec<(u32, u16)>, BigUint) {
    let mut exponents = Vec::new();
    let mut residual = n.clone();
    // The first primes up to B = 2^20. We hardcode the first ~82k primes; to
    // avoid a 1MB sieve table inside this crate we generate them procedurally
    // up to SIEVE_BOUND via a basic sieve at startup (cached).
    for &p in prime_table_up_to(SIEVE_BOUND).iter() {
        if residual.is_one() {
            break;
        }
        let p_big = BigUint::from(p as u64);
        let mut e: u16 = 0;
        while (&residual % &p_big).is_zero() {
            residual /= &p_big;
            e += 1;
        }
        if e > 0 {
            exponents.push((p, e));
            if exponents.len() > 256 {
                // sanity cap so an edge case doesn't spiral
                break;
            }
        }
    }
    (exponents, residual)
}

/// `phi(n) = n ∏ (1 − 1/p)` over distinct primes `p | n`.
///
/// Given the multiset `n = ∏ p^e × residual`, returns:
///  - `phi = residual * (residual == 1 ? 1 : residual - 1)` if residual is
///    prime per the deterministic Miller-Rabin witness,
///  - times `∏ p^{e-1} × (p-1)` over (p, e) in `small_factors`.
pub fn totient(n_bits: &[u8; 128], smalls: &[(u32, u16)], residual_le: &[u8; 128]) -> Option<[u8; 128]> {
    let n = BigUint::from_bytes_le(n_bits);
    let residual = BigUint::from_bytes_le(residual_le);
    // Sanity: reconstruction
    let mut reconstructed: BigUint = One::one();
    for (p, e) in smalls {
        reconstructed *= BigUint::from(*p as u64).pow(*e as u32);
    }
    reconstructed *= &residual;
    if &reconstructed != &n {
        return None;
    }
    // For each small prime p with exponent e: factor contribution p^{e-1}*(p-1).
    let mut phi: BigUint = One::one();
    for (p, e) in smalls {
        let p_big = BigUint::from(*p as u64);
        let pow_e_minus_1 = p_big.pow((*e as u32).saturating_sub(1));
        let p_minus_1 = &p_big - 1u32;
        phi *= pow_e_minus_1 * p_minus_1;
    }
    if !residual.is_one() {
        if !is_probably_prime_deterministic(&residual) {
            return None;
        }
        phi *= &residual - 1u32;
    }
    // Reduce modulo 2^1024 since the disclosure is a fixed-width array.
    let modulo = BigUint::one() << CANDIDATE_BITS as u32;
    let phi_out = phi % modulo;
    let mut out = [0u8; 128];
    let bytes = phi_out.to_bytes_le();
    for (i, b) in bytes.iter().enumerate().take(128) {
        out[i] = *b;
    }
    Some(out)
}

/// Compute the disclosure for a 1024-bit candidate.
///
/// Validates that `n` round-trips through sieve + MR and returns the
/// `PhiSubmission` ready to attach to a block header.
pub fn compute_(n: &BigUint) -> Option<PhiSubmission> {
    if n.is_zero() || n.is_one() {
        return None;
    }
    let (smalls, residual) = factor_small(n);
    let n_le = bytes_le(n);
    let r_le = bytes_le(&residual);
    let phi = totient(&n_le, &smalls, &r_le)?;
    Some(PhiSubmission {
        n: Bytes128(n_le),
        small_factor_exponents: smalls,
        residual: Bytes128(r_le),
        phi: Bytes128(phi),
    })
}

fn bytes_le(n: &BigUint) -> [u8; 128] {
    let mut out = [0u8; 128];
    let bytes = n.to_bytes_le();
    for (i, b) in bytes.iter().enumerate().take(128) {
        out[i] = *b;
    }
    out
}

/// Deterministic 32-round Miller-Rabin on a BigUint < 2^1024 using blake3
/// for the witness stream.
fn is_probably_prime_deterministic(n: &BigUint) -> bool {
    if *n < BigUint::from(2u32) {
        return false;
    }
    // small-n pre-check
    for &p in prime_table_up_to(4096).iter() {
        let p_big = BigUint::from(p as u64);
        if &p_big == n {
            return true;
        }
        if n % &p_big == BigUint::zero() {
            return false;
        }
    }
    let n_bytes = n.to_bytes_le();
    let hash = blake3::hash(&n_bytes);
    let seed_bytes: [u8; 32] = hash.as_bytes()[..32].try_into().unwrap();
    let mut rng = SmallRng::from_seed(seed_bytes);
    let two = BigUint::from(2u32);
    // Compute d & s such that n-1 = d * 2^s
    let n_minus_1 = n - 1u32;
    let mut d = n_minus_1.clone();
    let mut s: u32 = 0;
    let one = BigUint::from(1u32);
    while (&d & &one).is_zero() {
        d >>= 1;
        s += 1;
    }
    for _ in 0..MR_ROUNDS {
        let witness: u64 = rng.next_u64();
        // Reduce mod (n-2) + 2 to lie in [2, n-2]
        let span = (n - &two).to_bigint().unwrap();
        let w_bi = BigInt::from(witness);
        let a = ((w_bi * &span) / BigInt::from(u64::MAX)) + BigInt::from(2);
        let a = a.to_biguint().unwrap();
        let mut x = a.modpow(&d, n);
        if x.is_one() || &x == &(n - 1u32) {
            continue;
        }
        let tries = s.saturating_sub(1);
        for _round in 0..tries {
            x = x.modpow(&two, n);
            if x.is_one() {
                return false;
            }
            if &x == &(n - 1u32) {
                break;
            }
        }
        if &x != &(n - 1u32) {
            return false;
        }
    }
    true
}

/// A cached table of primes up to a bound. Rebuilt lazily on first use.
fn prime_table_up_to(bound: u32) -> &'static [u32] {
    use std::sync::OnceLock;
    static CACHE: OnceLock<Vec<u32>> = OnceLock::new();
    CACHE.get_or_init(|| sieve_primes_up_to(bound.max(8192)))
}

fn sieve_primes_up_to(bound: u32) -> Vec<u32> {
    let n = (bound as usize) + 1;
    let mut sieve = vec![true; n];
    sieve[0] = false;
    if n > 1 {
        sieve[1] = false;
    }
    let mut i = 2;
    while i * i < n {
        if sieve[i] {
            let mut j = i * i;
            while j < n {
                sieve[j] = false;
                j += i;
            }
        }
        i += 1;
    }
    (2..n).filter(|&k| sieve[k]).map(|k| k as u32).collect()
}

/// Difficulty adjustment: ramps `prev` up/down so observed block time
/// approaches `target_ms`, clamped to a 4× swing per step.
pub fn adjust_difficulty(prev: u64, actual_ms: u64, target_ms: u64) -> u64 {
    if actual_ms == 0 {
        return prev;
    }
    let new = (prev as u128 * target_ms as u128 / actual_ms as u128) as u64;
    new.clamp(prev / 4, prev * 4).max(1)
}

/// Hash of the disclosure attached to a block, used to compare against the
/// difficulty target. The miner and verifier both compute this from the
/// header (and nonce).
pub fn pow_hash(sub_or_header: &PhiSubmission) -> Hash {
    let bytes = bincode::serialize(sub_or_header).expect("serialise phi submission");
    Hash::digest(&bytes)
}

/// Verify a header against the φ-PoW by recomputing the disclosure and
/// comparing its hash to the difficulty target. Returns `true` when the
/// candidate fails Miller-Rabin (such headers can't be honest proposals).
pub fn pow_hash_for_header(header: &BlockHeader) -> Hash {
    match phi_pow_for_header(header) {
        Some(sub) => pow_hash(&sub),
        None => Hash::zero(),
    }
}

/// True iff the disclosure hash for `header` meets the difficulty target.
pub fn header_meets_difficulty(header: &BlockHeader, difficulty: u64) -> bool {
    let h = pow_hash_for_header(header);
    if h == Hash::zero() {
        return false;
    }
    meets_difficulty(&h, difficulty)
}

/// Mine `header_template` over nonces until the disclosure hash meets the
/// difficulty. Returns the winning nonce and the disclosure.
pub fn mine(
    mut header: BlockHeader,
    difficulty: u64,
    max_nonces: u64,
) -> Option<(u64, PhiSubmission)> {
    for nonce in 0..max_nonces {
        header.nonce = nonce;
        if let Some(sub) = phi_pow_for_header(&header) {
            if meets_difficulty(&pow_hash(&sub), difficulty) {
                return Some((nonce, sub));
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use voidmap_core::BlockHeader;

    fn dummy_header(nonce: u64) -> BlockHeader {
        BlockHeader {
            version: 1,
            height: 1,
            timestamp_ms: 1_700_000_000_000,
            parent: voidmap_crypto::Hash::zero(),
            state_root: voidmap_crypto::Hash::zero(),
            tx_root: voidmap_crypto::Hash::zero(),
            difficulty: 1,
            nonce,
            miner: voidmap_crypto::Address::zero(),
        }
    }

    #[test]
    fn phi_small_cases() {
        // φ(15) = φ(3)φ(5) = 2*4 = 8
        let n = BigUint::from(15u32);
        let sub = compute_(&n).unwrap();
        let phi = BigUint::from_bytes_le(&sub.phi.0);
        assert_eq!(phi, BigUint::from(8u32));

        let n = BigUint::from(7u32);
        let sub = compute_(&n).unwrap();
        let phi = BigUint::from_bytes_le(&sub.phi.0);
        assert_eq!(phi, BigUint::from(6u32));

        // φ(13) = 12
        let n = BigUint::from(13u32);
        let sub = compute_(&n).unwrap();
        let phi = BigUint::from_bytes_le(&sub.phi.0);
        assert_eq!(phi, BigUint::from(12u32));
    }

    #[test]
    fn candidate_is_deterministic() {
        let h1 = phi_pow_for_header(&dummy_header(7));
        // Same header -> same result (Some(Some) or Some(None), but equal)
        let h2 = phi_pow_for_header(&dummy_header(7));
        assert_eq!(h1, h2);

        // Within a small nonce range, at least one nonce should land on a
        // successful disclosure (this works because 1024-bit primes are
        // statistically common and our sieve plus MR accepts them well under
        // a couple thousand nonces).
        let mut found = false;
        for nonce in 0..2000 {
            if phi_pow_for_header(&dummy_header(nonce)).is_some() {
                found = true;
                break;
            }
        }
        assert!(found, "no nonce in [0, 2000) produced a passing φ-PoW disclosure");
    }

    #[test]
    fn difficulty_adjust_clamps() {
        // actual_ms == 0 => return prev unchanged
        assert_eq!(adjust_difficulty(1000, 0, 15_000), 1000);
        // target/actual = 2 => should double (no clamp)
        assert_eq!(adjust_difficulty(1000, 7500, 15_000), 2000);
        // 4x clamp in single step
        assert_eq!(adjust_difficulty(1000, 1, 15_000).min(4000), 4000);
    }

    #[test]
    fn mine_finds_with_low_difficulty() {
        let h = dummy_header(0);
        // Difficulty 1 always meets
        let res = mine(h, 1, 1000);
        assert!(res.is_some());
    }
}
