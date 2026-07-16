//! Cryptographic primitives for the Voidmap native chain.
//!
//! - `Hash`: 32-byte Blake3 digest used for block/tx/state commitments.
//! - `KeyPair` / `PublicKey`: ed25519 signing for transaction authorization.
//! - `Address`: 32-byte account identifier derived from a public key.

use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use serde::{Deserialize, Deserializer, Serialize, Serializer};


pub const HASH_LEN: usize = 32;

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Default, Serialize, Deserialize)]
pub struct Hash([u8; HASH_LEN]);

impl Hash {
    pub fn from_bytes(b: [u8; HASH_LEN]) -> Self {
        Hash(b)
    }
    pub fn as_bytes(&self) -> &[u8; HASH_LEN] {
        &self.0
    }
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }
    pub fn zero() -> Self {
        Hash([0u8; HASH_LEN])
    }
    /// Blake3 hash of an arbitrary byte slice.
    pub fn digest(data: &[u8]) -> Self {
        let h = blake3::hash(data);
        Hash(h.into())
    }
}

impl std::fmt::Debug for Hash {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Hash({})", &self.to_hex()[..12])
    }
}
impl std::fmt::Display for Hash {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_hex())
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct PublicKey([u8; 32]);

impl PublicKey {
    pub fn from_bytes(b: [u8; 32]) -> Self {
        PublicKey(b)
    }
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }
    pub fn address(&self) -> Address {
        // On the native chain the account id IS the ed25519 public key.
        Address::from_bytes(self.0)
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, Ord, PartialOrd, Default, Serialize, Deserialize)]
pub struct Address([u8; HASH_LEN]);

impl Address {
    pub fn from_bytes(b: [u8; HASH_LEN]) -> Self {
        Address(b)
    }
    pub fn as_bytes(&self) -> &[u8; HASH_LEN] {
        &self.0
    }
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }
    pub fn zero() -> Self {
        Address([0u8; HASH_LEN])
    }
}

impl std::fmt::Debug for Address {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Addr({})", &self.to_hex()[..12])
    }
}

impl std::fmt::Display for Address {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_hex())
    }
}

#[derive(Clone)]
pub struct KeyPair {
    signing: SigningKey,
    verifying: VerifyingKey,
}

impl KeyPair {
    pub fn generate() -> Self {
        let mut csprng = rand::thread_rng();
        let signing = SigningKey::generate(&mut csprng);
        let verifying = signing.verifying_key();
        KeyPair { signing, verifying }
    }

    pub fn from_seed(seed: [u8; 32]) -> Self {
        let signing = SigningKey::from_bytes(&seed);
        let verifying = signing.verifying_key();
        KeyPair { signing, verifying }
    }

    pub fn public_key(&self) -> PublicKey {
        PublicKey::from_bytes(self.verifying.to_bytes())
    }

    pub fn address(&self) -> Address {
        self.public_key().address()
    }

    pub fn secret_key_bytes(&self) -> [u8; 32] {
        self.signing.to_bytes()
    }

    /// Sign a pre-hashed message digest.
    pub fn sign(&self, msg: &[u8]) -> Sig {
        let sig: Signature = self.signing.sign(msg);
        Sig::from_bytes(sig.to_bytes())
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Sig([u8; 64]);

impl Sig {
    pub fn from_bytes(b: [u8; 64]) -> Self {
        Sig(b)
    }
    pub fn as_bytes(&self) -> &[u8; 64] {
        &self.0
    }
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }
}

impl Serialize for Sig {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_bytes(&self.0)
    }
}

impl<'de> Deserialize<'de> for Sig {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let v = Vec::<u8>::deserialize(d)?;
        if v.len() != 64 {
            return Err(serde::de::Error::custom("Sig must be 64 bytes"));
        }
        let mut arr = [0u8; 64];
        arr.copy_from_slice(&v);
        Ok(Sig(arr))
    }
}

/// Verify an ed25519 signature over `msg` against a public key.
pub fn verify(pk: &PublicKey, msg: &[u8], sig: &Sig) -> bool {
    let vk = match VerifyingKey::from_bytes(pk.as_bytes()) {
        Ok(v) => v,
        Err(_) => return false,
    };
    let s = Signature::from_bytes(sig.as_bytes());
    match vk.verify(msg, &s) {
        Ok(_) => true,
        Err(_) => false,
    }
}
