# Mining Guide

Voidmap uses a native L1 blockchain (Rust) with φ-PoW consensus. This guide covers building the node, solo mining, and running a multi-node testnet.

---

## Build

```bash
cd voidmap-chain
cargo build --release
# Binary: target/release/voidmap-node
```

---

## Solo Mining (no network)

```bash
./target/release/voidmap-node --data-dir /tmp/voidmap mine --blocks 10
```

This creates a genesis block, mines 10 blocks with φ-PoW, and saves to `chain.json`.

---

## Query Chain State

```bash
./target/release/voidmap-node --data-dir /tmp/voidmap query
```

Output:
```
blocks: 5
submissions: 4
total minted: 100002246 VOID
dev fund: 50000000 VOID | dao: 50000000 VOID
avg network quality: 88
best height: 4
```

---

## Networked Mining

### Node 1 (miner)

```bash
./target/release/voidmap-node --data-dir /tmp/node1 run --listen 8101
```

### Node 2 (connects to Node 1)

```bash
./target/release/voidmap-node --data-dir /tmp/node2 run --listen 8102 --peer 127.0.0.1:8101
```

Both nodes mine blocks, gossip new blocks via TCP, and periodically re-sync (every 10 seconds). The heaviest chain wins automatically.

---

## Multi-Node Testnet (Podman)

```bash
# Create containers
podman run -d --name vmnode1 --network host \
  -v /tmp/vmchain1:/data:z ubuntu:24.04 sleep infinity
podman run -d --name vmnode2 --network host \
  -v /tmp/vmchain2:/data:z ubuntu:22.04 sleep infinity

# Deploy binary
podman cp target/release/voidmap-node vmnode1:/usr/local/bin/
podman cp target/release/voidmap-node vmnode2:/usr/local/bin/

# Start nodes
podman exec -d vmnode1 /usr/local/bin/voidmap-node --data-dir /data run --listen 8101
podman exec -d vmnode2 /usr/local/bin/voidmap-node --data-dir /data run --listen 8102 --peer 127.0.0.1:8101
```

**Note**: Use `:z` on the volume mount to relabel for container access (SELinux).

After 180 seconds, both containers should have identical chains.

---

## Generate a Key

```bash
./target/release/voidmap-node --data-dir /tmp/voidmap keygen
# Creates key.json in the data directory
```

---

## How Mining Works

1. The miner builds a candidate block containing a SubmitWork transaction (astronomy ML results)
2. The block header is hashed to produce a deterministic 1024-bit candidate number
3. The candidate is trial-factored by all primes up to 2^20
4. The residual must be 1 or a strong pseudoprime (Miller-Rabin, bases 2/3/5/7/11/13)
5. The disclosure hash (Blake3) must meet the difficulty target
6. If found, the block is added to the chain and broadcast to peers

Average time per block at difficulty 250: ~40 seconds (varies).

---

## Difficulty Adjustment

After genesis (which starts at `INITIAL_DIFFICULTY = 1000`), the first mined block gets difficulty 250 (clamped to `current/4` due to genesis timestamp=0). Subsequent blocks adjust to target 15-second block times using:

```
new_difficulty = prev_difficulty × (target_ms / actual_ms)
```

Clamped to `[prev/4, prev×4]`.

---

## Network Protocol

Plain TCP with length-prefixed JSON messages:

| Byte | Message | Purpose |
|------|---------|---------|
| 0x01 | Block, Tx, SyncRequest, SyncResponse | Persistent gossip channel |
| 0x02 | SyncRequest, SyncResponse | Periodic re-sync (every 10s) |

Chain selection: heaviest chain (maximum cumulative difficulty). Automatic reorgs.

---

## GPU Setup for SubmitWork Transactions

The node mines blocks with φ-PoW, but to include useful work (astronomy ML results) in blocks, a separate GPU miner is needed. The Python GPU miner runs inference on real telescope data and submits results as SubmitWork transactions to the node's mempool.

### Requirements

- GPU: NVIDIA (CUDA), AMD (ROCm), Apple Silicon (MPS), or Intel (DirectML)
- Python: 3.10+
- RAM: 8GB minimum

### Run the GPU Miner

```bash
cd voidmap_miner
pip install -e .
python -m voidmap_miner --task exoplanet --rounds 10
```

The GPU miner connects to the node's TCP port and submits SubmitWork transactions that get included in mined blocks.

---

## Data Sources

| Archive | URL | Data |
|---------|-----|------|
| MAST | portal.mast.stsci.edu | TESS SPOC 2-min light curves (FITS) |
| SDSS DR18 | skyserver.sdss.org | Galaxy cutout images (JPEG) |
| ZTF/Fink | fink-portal.org | Alert streams (JSON) |
