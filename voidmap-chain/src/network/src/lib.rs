//! Chain state management and wire protocol types for the Voidmap native chain.
//!
//! Nodes exchange blocks over plain TCP using a 4-byte length-prefixed JSON
//! protocol. Chain selection follows the **heaviest chain** rule: the canonical
//! chain is the one with the greatest cumulative proof-of-work (sum of block
//! difficulties). Forks are retained and the tip switches on a heavier block,
//! which produces automatic reorgs.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

use voidmap_core::{genesis_block, genesis_state, Address, Block, BlockHeader, Hash, State, Tx};

/// Wire message exchanged between nodes.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum NetMsg {
    Block(Block),
    Tx(Tx),
    /// A node that just joined asks peers for their canonical chain.
    SyncRequest,
    /// Response carrying a peer's canonical chain (genesis-first).
    SyncResponse(Vec<Block>),
}

// ── length-prefixed JSON codec (4-byte BE length + JSON) ──────────────────

pub async fn read_json<T: serde::de::DeserializeOwned>(
    io: &mut (impl AsyncReadExt + Unpin),
) -> std::io::Result<T> {
    let mut len_buf = [0u8; 4];
    io.read_exact(&mut len_buf).await?;
    let len = u32::from_be_bytes(len_buf) as usize;
    let mut buf = vec![0u8; len];
    io.read_exact(&mut buf).await?;
    serde_json::from_slice(&buf).map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
}

pub async fn write_json<T: serde::Serialize>(
    io: &mut (impl AsyncWriteExt + Unpin),
    msg: &T,
) -> std::io::Result<()> {
    let data = serde_json::to_vec(msg)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    let len = (data.len() as u32).to_be_bytes();
    io.write_all(&len).await?;
    io.write_all(&data).await?;
    io.flush().await
}

// ── chain store ────────────────────────────────────────────────────────────

/// In-memory chain store with heaviest-chain tracking and reorg support.
pub struct ChainStore {
    pub blocks: HashMap<Hash, Block>,
    pub cum_diff: HashMap<Hash, u128>,
    pub best: Hash,
    pub dev: Address,
    pub dao: Address,
}

impl ChainStore {
    pub fn new(dev: Address, dao: Address, genesis_difficulty: u64) -> Self {
        let genesis = genesis_block(dev, dao, genesis_difficulty);
        let mut s = ChainStore {
            blocks: HashMap::new(),
            cum_diff: HashMap::new(),
            best: genesis.hash(),
            dev,
            dao,
        };
        s.blocks.insert(genesis.hash(), genesis.clone());
        s.cum_diff.insert(genesis.hash(), 0);
        s
    }

    pub fn genesis_state(&self) -> State {
        genesis_state(self.dev, self.dao)
    }

    pub fn best_tip(&self) -> &Block {
        &self.blocks[&self.best]
    }

    /// Return the canonical chain (genesis-first) as a list of blocks.
    pub fn canonical_blocks(&self) -> Vec<Block> {
        let mut chain = Vec::new();
        let mut cur = self.best;
        while let Some(b) = self.blocks.get(&cur) {
            chain.push(b.clone());
            if b.is_genesis() {
                break;
            }
            cur = b.header.parent;
        }
        chain.reverse();
        chain
    }

    /// Replay the canonical chain from genesis to `hash`, returning the post-state.
    pub fn replay_to(&self, hash: &Hash) -> State {
        let mut chain = Vec::new();
        let mut cur = *hash;
        while let Some(b) = self.blocks.get(&cur) {
            chain.push(b.clone());
            if b.is_genesis() {
                break;
            }
            cur = b.header.parent;
        }
        chain.reverse();
        let mut state = self.genesis_state();
        for b in &chain {
            state = state.apply_block(b).expect("replay canonical block");
        }
        state
    }

    /// Validate and insert a block. Updates the best tip on a heavier chain.
    /// Returns Ok(true) if the tip changed.
    pub fn add_block(&mut self, b: Block) -> Result<bool, String> {
        let hash = b.hash();
        if self.blocks.contains_key(&hash) {
            return Ok(false);
        }

        if b.is_genesis() {
            self.blocks.insert(hash, b);
            self.cum_diff.insert(hash, 0);
            return Ok(false);
        }

        // Parent must be known.
        let parent = self.blocks.get(&b.header.parent).ok_or("orphan block")?;

        // Difficulty must match the adjustment algorithm.
        let elapsed = b.header.timestamp_ms.saturating_sub(parent.header.timestamp_ms);
        let expected_diff = voidmap_pow::adjust_difficulty(
            parent.header.difficulty,
            elapsed,
            voidmap_pow::TARGET_BLOCK_MS,
        );
        if b.header.difficulty != expected_diff {
            return Err(format!(
                "difficulty mismatch: expected {}, got {}",
                expected_diff, b.header.difficulty
            ));
        }

        // Proof-of-work validity.
        if !voidmap_pow::header_meets_difficulty(&b.header, b.header.difficulty) {
            return Err("block does not meet difficulty".into());
        }

        // State-root validity (also validates txs + reward emission).
        let parent_state = self.replay_to(&b.header.parent);
        let _ = parent_state.apply_block(&b)?;

        let parent_cum = *self.cum_diff.get(&b.header.parent).unwrap_or(&0);
        let cum = parent_cum + b.header.difficulty as u128;

        self.blocks.insert(hash, b);
        self.cum_diff.insert(hash, cum);

        let prev_best_cum = *self.cum_diff.get(&self.best).unwrap_or(&0);
        if cum > prev_best_cum {
            self.best = hash;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    /// Adopt a peer's canonical chain if it is heavier than ours.
    pub fn adopt(&mut self, chain: &[Block]) -> Result<bool, String> {
        let mut changed = false;
        for b in chain {
            if self.add_block(b.clone())? {
                changed = true;
            }
        }
        Ok(changed)
    }
}

/// Build the candidate header for mining on top of the current best tip.
pub fn candidate_header(
    store: &ChainStore,
    miner: Address,
    difficulty: u64,
    tx_root: Hash,
    state_root: Hash,
    timestamp_ms: u64,
) -> BlockHeader {
    let tip = store.best_tip();
    BlockHeader {
        version: 1,
        height: tip.header.height + 1,
        timestamp_ms,
        parent: tip.hash(),
        state_root,
        tx_root,
        difficulty,
        nonce: 0,
        miner,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use voidmap_crypto::KeyPair;

    fn test_store() -> ChainStore {
        let dev = KeyPair::from_seed([42u8; 32]).address();
        let dao = KeyPair::from_seed([43u8; 32]).address();
        ChainStore::new(dev, dao, 1000)
    }

    /// Mine a valid block at difficulty 1 on top of `store` using `mine()`.
    fn mine_valid_block(store: &ChainStore, miner: Address) -> Block {
        let tip = store.best_tip();
        let parent_state = store.replay_to(&tip.hash());
        let now = 1_000_000u64;
        let elapsed = now.saturating_sub(tip.header.timestamp_ms);
        let difficulty = voidmap_pow::adjust_difficulty(
            tip.header.difficulty,
            elapsed,
            voidmap_pow::TARGET_BLOCK_MS,
        );
        let mut header = candidate_header(
            store,
            miner,
            difficulty,
            Hash::digest(&[]),
            Hash::zero(),
            now,
        );
        let tentative = Block {
            header: header.clone(),
            txs: vec![],
        };
        let next_state = parent_state.execute(&tentative).expect("exec tentative");
        header.state_root = next_state.state_root();

        let (nonce, _) = voidmap_pow::mine(header.clone(), difficulty, 100_000)
            .expect("mine should find a nonce at low difficulty");
        header.nonce = nonce;
        Block { header, txs: vec![] }
    }

    #[test]
    fn add_block_accepts_valid_difficulty() {
        let store = test_store();
        let mut store = store;
        let miner = KeyPair::from_seed([99u8; 32]).address();
        let block = mine_valid_block(&store, miner);
        let result = store.add_block(block);
        assert!(result.is_ok(), "valid block should be accepted");
        assert!(result.unwrap(), "tip should change");
    }

    #[test]
    fn add_block_rejects_wrong_difficulty() {
        let store = test_store();
        let mut store = store;
        let miner = KeyPair::from_seed([99u8; 32]).address();
        let mut block = mine_valid_block(&store, miner);

        // Tamper with difficulty — set to a value that doesn't match adjustment.
        block.header.difficulty = 1;
        let result = store.add_block(block);
        assert!(result.is_err(), "block with wrong difficulty should be rejected");
        assert!(
            result.unwrap_err().contains("difficulty mismatch"),
            "error should mention difficulty mismatch"
        );
    }

    #[test]
    fn add_block_rejects_without_pow() {
        let store = test_store();
        let mut store = store;
        let miner = KeyPair::from_seed([99u8; 32]).address();
        let mut block = mine_valid_block(&store, miner);

        // Tamper with nonce so PoW no longer validates.
        block.header.nonce = 999_999;
        let result = store.add_block(block);
        assert!(result.is_err(), "block without valid PoW should be rejected");
    }

    #[test]
    fn adopt_syncs_chain_from_peer() {
        let store1 = test_store();
        let mut store1 = store1;
        let miner = KeyPair::from_seed([99u8; 32]).address();
        let block = mine_valid_block(&store1, miner);
        store1.add_block(block.clone()).expect("add");

        // A fresh peer with only genesis adopts blocks from store1.
        let mut store2 = test_store();
        let chain = store1.canonical_blocks();
        let changed = store2.adopt(&chain).expect("adopt");
        assert!(changed, "adopt should change tip");
        assert_eq!(
            store2.best_tip().header.height,
            store1.best_tip().header.height,
            "both stores should converge to same height"
        );
        assert_eq!(
            store2.best_tip().hash(),
            store1.best_tip().hash(),
            "both stores should have the same tip"
        );
    }
}
