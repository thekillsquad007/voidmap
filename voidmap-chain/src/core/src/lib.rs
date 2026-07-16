//! Core data types and state machine for the Voidmap native chain.
//!
//! Model: account-based ledger. VOID is stored in integer "micro-VOID"
//! units (1 VOID = 1_000_000_000 micro). Total fixed supply is 1e18 micro.
//!
//! Block production is secured by a custom memory-hard PoW (see `voidmap-pow`).
//! The "useful work" (astronomical ML inference) is an application-layer
//! activity: a `SubmitWork` transaction carries a result commitment + quality
//! score, and inclusion in a valid block mints VOID to the submitter per the
//! halving / elastic / quality reward formula.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub use voidmap_crypto::{Address, Hash, PublicKey, Sig};

/// 1 VOID expressed in the integer ledger unit.
pub const MICRO: u64 = 1_000_000_000;
/// Fixed total supply: 1,000,000,000 VOID.
pub const TOTAL_SUPPLY_MICRO: u64 = 1_000_000_000 * MICRO;

pub const DEV_FUND_VOID: u64 = 50_000_000;
pub const DAO_TREASURY_VOID: u64 = 50_000_000;

/// Halving interval, measured in accepted submissions (not blocks).
pub const HALVING_INTERVAL: u64 = 210_000;
pub const INITIAL_BLOCK_REWARD_VOID: u64 = 50;
pub const MIN_BLOCK_REWARD_VOID: u64 = 0; // floor applied to per-submission reward
pub const MIN_SUBMISSION_REWARD_VOID_X10: u64 = 1; // 0.1 VOID floor (×10 for fixed math)

/// Elastic mint tuning.
pub const TARGET_QUALITY: u16 = 75;
pub const ELASTIC_DEAD_ZONE: u16 = 5;
pub const ELASTIC_MIN_NUM: u64 = 80; // 0.8x
pub const ELASTIC_MAX_NUM: u64 = 120; // 1.2x

/// Minimum useful-work compute time (ms) enforced on-chain (anti-ASIC layer 3).
pub const MIN_COMPUTE_MS: u64 = 2000;

pub type Amount = u64;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum Tx {
    /// Transfer VOID between accounts. Signed by `from`.
    Transfer {
        from: Address,
        to: Address,
        amount: Amount,
        nonce: u64,
        fee: Amount,
        sig: Sig,
    },
    /// Submit a useful-work result. Signed by `miner`.
    /// `result_commit` is a commitment to the model output + input id.
    /// `quality` is 0..=100. `timing_ms` is attested compute time.
    SubmitWork {
        miner: Address,
        task_id: u32,
        result_commit: Hash,
        quality: u16,
        timing_ms: u64,
        fee: Amount,
        sig: Sig,
    },
}

impl Tx {
    /// Canonical bytes that are signed (everything except the signature).
    pub fn signing_bytes(&self) -> Vec<u8> {
        match self {
            Tx::Transfer { from, to, amount, nonce, fee, .. } => {
                let mut v = vec![0u8];
                v.extend_from_slice(from.as_bytes());
                v.extend_from_slice(to.as_bytes());
                v.extend_from_slice(&amount.to_le_bytes());
                v.extend_from_slice(&nonce.to_le_bytes());
                v.extend_from_slice(&fee.to_le_bytes());
                v
            }
            Tx::SubmitWork { miner, task_id, result_commit, quality, timing_ms, fee, .. } => {
                let mut v = vec![1u8];
                v.extend_from_slice(miner.as_bytes());
                v.extend_from_slice(&task_id.to_le_bytes());
                v.extend_from_slice(result_commit.as_bytes());
                v.extend_from_slice(&quality.to_le_bytes());
                v.extend_from_slice(&timing_ms.to_le_bytes());
                v.extend_from_slice(&fee.to_le_bytes());
                v
            }
        }
    }

    pub fn signer(&self) -> Address {
        match self {
            Tx::Transfer { from, .. } => *from,
            Tx::SubmitWork { miner, .. } => *miner,
        }
    }

    pub fn fee(&self) -> Amount {
        match self {
            Tx::Transfer { fee, .. } => *fee,
            Tx::SubmitWork { fee, .. } => *fee,
        }
    }

    pub fn hash(&self) -> Hash {
        Hash::digest(&bincode::serialize(self).expect("tx serialize"))
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct BlockHeader {
    pub version: u32,
    pub height: u64,
    pub timestamp_ms: u64,
    pub parent: Hash,
    pub state_root: Hash,
    pub tx_root: Hash,
    pub difficulty: u64,
    pub nonce: u64,
    pub miner: Address,
}

impl BlockHeader {
    pub fn hash(&self) -> Hash {
        Hash::digest(&bincode::serialize(self).expect("header serialize"))
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Block {
    pub header: BlockHeader,
    pub txs: Vec<Tx>,
}

impl Block {
    pub fn hash(&self) -> Hash {
        self.header.hash()
    }
    pub fn is_genesis(&self) -> bool {
        self.header.height == 0
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Account {
    pub balance: Amount,
    pub nonce: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Submission {
    pub id: u64,
    pub miner: Address,
    pub task_id: u32,
    pub result_commit: Hash,
    pub quality: u16,
    pub block_height: u64,
}

/// Rolling window of recent submission qualities, used for elastic mint.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct State {
    pub accounts: HashMap<Address, Account>,
    pub submissions: Vec<Submission>,
    pub total_submissions: u64,
    pub total_mined_micro: u64,
    pub quality_window: Vec<u16>, // last 10 accepted qualities
}

impl State {
    pub fn new() -> Self {
        State::default()
    }

    pub fn balance(&self, a: &Address) -> Amount {
        self.accounts.get(a).map(|x| x.balance).unwrap_or(0)
    }

    pub fn nonce(&self, a: &Address) -> u64 {
        self.accounts.get(a).map(|x| x.nonce).unwrap_or(0)
    }

    fn mint(&mut self, to: &Address, amount: Amount) {
        if amount == 0 {
            return;
        }
        // Enforce fixed total supply.
        let room = TOTAL_SUPPLY_MICRO.saturating_sub(self.total_mined_micro);
        let amt = amount.min(room);
        if amt == 0 {
            return;
        }
        let acc = self.accounts.entry(*to).or_default();
        acc.balance += amt;
        self.total_mined_micro += amt;
    }

    /// Execute a block's transactions against the current state and return the
    /// resulting state. Does NOT validate the header `state_root` (use
    /// `apply_block` for that). Genesis blocks return the state unchanged.
    pub fn execute(&self, block: &Block) -> Result<State, String> {
        let mut s = self.clone();

        if block.is_genesis() {
            return Ok(s);
        }

        // 1. Validate + apply transactions.
        for tx in &block.txs {
            match tx {
                Tx::Transfer { from, to, amount, nonce, fee, sig } => {
                    if !voidmap_crypto::verify(&PublicKey::from_bytes(*from.as_bytes()), &tx.signing_bytes(), sig) {
                        return Err("bad transfer signature".into());
                    }
                    let acc = s.accounts.get(from).ok_or("transfer: unknown sender")?;
                    if *nonce != acc.nonce {
                        return Err("transfer: bad nonce".into());
                    }
                    if acc.balance < amount + fee {
                        return Err("transfer: insufficient funds".into());
                    }
                    s.accounts.get_mut(from).unwrap().balance -= amount + fee;
                    s.accounts.get_mut(from).unwrap().nonce += 1;
                    s.accounts.entry(*to).or_default().balance += amount;
                }
                Tx::SubmitWork { miner, task_id, result_commit, quality, timing_ms, fee, sig } => {
                    if *quality > 100 {
                        return Err("submit: quality out of range".into());
                    }
                    if *timing_ms < MIN_COMPUTE_MS {
                        return Err("submit: compute time below attestation floor".into());
                    }
                    if !voidmap_crypto::verify(&PublicKey::from_bytes(*miner.as_bytes()), &tx.signing_bytes(), sig) {
                        return Err("bad submit signature".into());
                    }
                    if *fee > 0 {
                        let bal = s.accounts.get(miner).map(|a| a.balance).unwrap_or(0);
                        if bal < *fee {
                            return Err("submit: cannot pay fee".into());
                        }
                        s.accounts.get_mut(miner).unwrap().balance -= *fee;
                    }

                    if *quality >= 50 {
                        let reward = s.submission_reward(*quality);
                        let id = s.total_submissions;
                        s.submissions.push(Submission {
                            id,
                            miner: *miner,
                            task_id: *task_id,
                            result_commit: *result_commit,
                            quality: *quality,
                            block_height: block.header.height,
                        });
                        s.total_submissions += 1;
                        s.quality_window.push(*quality);
                        if s.quality_window.len() > 10 {
                            s.quality_window.remove(0);
                        }
                        s.mint(miner, reward);
                    }
                }
            }
        }

        // 2. Coinbase: block producer earns the current halving block reward.
        let coinbase = s.block_reward_micro();
        s.mint(&block.header.miner, coinbase);

        Ok(s)
    }

    /// Apply a block: execute it, then verify the resulting state root matches
    /// the header's `state_root`. This is the canonical state-transition entry
    /// point used when accepting blocks from the network.
    pub fn apply_block(&self, block: &Block) -> Result<State, String> {
        let s = self.execute(block)?;
        if block.is_genesis() {
            return Ok(s);
        }
        let root = s.state_root();
        if root != block.header.state_root {
            return Err(format!(
                "state root mismatch: computed {} header {}",
                root, block.header.state_root
            ));
        }
        Ok(s)
    }

    pub fn state_root(&self) -> Hash {
        let mut keys: Vec<&Address> = self.accounts.keys().collect();
        keys.sort();
        let mut buf = Vec::new();
        for k in &keys {
            buf.extend_from_slice(k.as_bytes());
            let a = &self.accounts[*k];
            buf.extend_from_slice(&a.balance.to_le_bytes());
            buf.extend_from_slice(&a.nonce.to_le_bytes());
        }
        buf.extend_from_slice(&self.total_submissions.to_le_bytes());
        buf.extend_from_slice(&self.total_mined_micro.to_le_bytes());
        Hash::digest(&buf)
    }

    /// Current per-submission reward (micro-VOID) for a given quality, using the
    /// halving epoch and the elastic multiplier from the rolling quality window.
    pub fn submission_reward(&self, quality: u16) -> Amount {
        let block_reward_micro = self.block_reward_micro();
        let qmult_num = quality_multiplier_num(quality);
        let emult_num = self.elastic_multiplier_num();
        // reward_micro = blockReward_micro * quality * qmult_num * emult_num / 100_000
        let raw = block_reward_micro as u128
            * quality as u128
            * qmult_num as u128
            * emult_num as u128
            / 100_000u128;
        let floor = (MIN_SUBMISSION_REWARD_VOID_X10 as u128 * MICRO as u128) / 10;
        let reward = raw.max(floor);
        reward.min(TOTAL_SUPPLY_MICRO as u128) as u64
    }

    /// Halving-epoch block reward in micro-VOID (paid to block producer).
    pub fn block_reward_micro(&self) -> Amount {
        let epoch = self.total_submissions / HALVING_INTERVAL;
        let mut reward_vo = INITIAL_BLOCK_REWARD_VOID;
        for _ in 0..epoch {
            reward_vo /= 2;
            if reward_vo == 0 {
                break;
            }
        }
        reward_vo * MICRO
    }

    /// Elastic multiplier numerator (80..=120) from rolling quality window.
    pub fn elastic_multiplier_num(&self) -> u64 {
        if self.quality_window.is_empty() {
            return 100;
        }
        let sum: u32 = self.quality_window.iter().map(|q| *q as u32).sum();
        let avg = sum / self.quality_window.len() as u32;
        if avg + ELASTIC_DEAD_ZONE as u32 <= TARGET_QUALITY as u32 {
            ELASTIC_MAX_NUM
        } else if avg as u16 >= TARGET_QUALITY + ELASTIC_DEAD_ZONE {
            ELASTIC_MIN_NUM
        } else {
            100
        }
    }

    pub fn avg_network_quality(&self) -> u16 {
        if self.quality_window.is_empty() {
            return 0;
        }
        (self.quality_window.iter().map(|q| *q as u32).sum::<u32>() / self.quality_window.len() as u32) as u16
    }
}

/// Quality tier multiplier numerator: <70 => 100, 70-89 => 120, 90-100 => 150.
pub fn quality_multiplier_num(quality: u16) -> u64 {
    if quality >= 90 {
        150
    } else if quality >= 70 {
        120
    } else {
        100
    }
}

/// Build the genesis state with dev fund + DAO treasury pre-allocated.
pub fn genesis_state(dev: Address, dao: Address) -> State {
    let mut s = State::new();
    s.mint(&dev, DEV_FUND_VOID * MICRO);
    s.mint(&dao, DAO_TREASURY_VOID * MICRO);
    s
}

/// Build the genesis block. The genesis `state_root` is derived from the
/// pre-allocated dev/dao accounts.
pub fn genesis_block(dev: Address, dao: Address, difficulty: u64) -> Block {
    let state = genesis_state(dev, dao);
    let header = BlockHeader {
        version: 1,
        height: 0,
        timestamp_ms: 0,
        parent: Hash::zero(),
        state_root: state.state_root(),
        tx_root: Hash::digest(&[]),
        difficulty,
        nonce: 0,
        miner: Address::zero(),
    };
    Block { header, txs: vec![] }
}

/// Current unix time in milliseconds (used for block timestamps + genesis).
pub fn now_ms() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
}

