# Voidmap

**Proof of Useful Work.** A native L1 blockchain where miners process real astronomical data from NASA, ESA, and NSF surveys. Earn VOID tokens for running scientific ML inference on real telescope data.

```
  Real telescope data              Real ML models                Real science
       ↓                                ↓                            ↓
   MAST TESS  ───→  GPU Inference  ───→  Native chain  ───→  Exoplanets found
   SDSS Galaxies       (AstroNet)         (φ-PoW + VOID)        Galaxies classified
   ZTF Alerts          (Zoobot)                                 Anomalies flagged
```

## Why Voidmap

| Problem | Voidmap Solution |
|---------|------------------|
| PoW wastes energy on useless hashes | φ-PoW: Euler totient-based proof with real scientific work rewards |
| Public archives hold petabytes of unanalyzed data | Miners process it, get paid in VOID |
| GPUs are commoditized (NVIDIA/AMD) | Anti-ASIC design + elastic mint keeps mining fair |
| Token founders can rug | Token is ownerless from day one, autonomous governance |

## Architecture

Voidmap is a **native L1 blockchain** built from scratch in Rust. No EVM, no Solidity, no third-party chain dependencies.

```
voidmap-chain/
├── src/
│   ├── crypto/    — ed25519 keys, Blake3 hashing, signatures
│   ├── core/     — Block/Tx types, account model, State, reward formula
│   ├── pow/      — φ-PoW: Euler totient proof-of-work (num-bigint, Miller-Rabin)
│   ├── network/  — ChainStore, heaviest-chain selection, TCP wire protocol
│   └── node/     — Full node binary (keygen, query, mine, run)
└── Cargo.toml    — workspace root
```

### φ-PoW Consensus

Instead of SHA-256 hashing, Voidmap uses **φ-PoW**: a proof-of-work scheme based on Euler's totient function.

1. Each block header commits to a deterministic 1024-bit candidate number `n`
2. The miner trial-factors `n` by all primes up to 2^20
3. The residual must be 1 or a strong pseudoprime (Miller-Rabin, bases 2/3/5/7/11/13)
4. The disclosure hash (Blake3 of the factored representation) must meet the difficulty target

This is **computationally expensive** (BigUint arithmetic, ~8ms per nonce) but produces no wasted energy — the same hardware runs scientific ML inference for block rewards.

### Useful Work Rewards

Block rewards include **SubmitWork transactions** — astronomy ML results that produce real scientific value:

| Task | Data Source | Model | Output |
|------|-------------|-------|--------|
| Exoplanet Transit Detection | MAST TESS SPOC 2-min | AstroNetCNN (244K params, 89% acc) | Planet/FP/No-signal + confidence |
| Galaxy Morphology Classification | SDSS DR18 cutout | GalaxyClassifier (Zoobot-ready) | Spiral/Elliptical/Irregular/Merger |
| Astronomical Anomaly Detection | ZTF alerts via Fink | Autoencoder | Anomaly score + flag |

All data is **real** — miners download actual FITS files from MAST, galaxy images from SDSS, and alert streams from ZTF/Fink.

## Quick Start

### Build

```bash
cd voidmap-chain
cargo build --release
# Binary: target/release/voidmap-node
```

### Run a Single Node (solo mining)

```bash
./target/release/voidmap-node --data-dir /tmp/voidmap mine --blocks 10
```

### Run a Networked Node

```bash
# Node 1 (miner)
./target/release/voidmap-node --data-dir /tmp/node1 run --listen 8101

# Node 2 (connects to Node 1)
./target/release/voidmap-node --data-dir /tmp/node2 run --listen 8102 --peer 127.0.0.1:8101
```

### Query Chain State

```bash
./target/release/voidmap-node --data-dir /tmp/node1 query
```

Output:
```
blocks: 8
submissions: 7
total minted: 100003794 VOID
dev fund: 50000000 VOID | dao: 50000000 VOID
avg network quality: 85
best height: 7
```

### Generate a Key

```bash
./target/release/voidmap-node keygen
# Saves key.json in the data directory
```

## Multi-Node Testnet (Podman)

```bash
# Create containers with SELinux-compatible volume mounts
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

Verified: both nodes converge to identical chains (same SHA256 hash for chain.json) within 180 seconds.

## Testing

```bash
cd voidmap-chain
cargo test
# 8 tests: 4 pow (difficulty adjustment, φ small cases, mine, deterministic candidate)
#          4 network (valid/invalid difficulty, PoW validation, chain sync)
```

## Tokenomics

| Allocation | Amount | Vesting | Recipient |
|------------|--------|---------|-----------|
| GPU Miners | 900M VOID (90%) | Halving schedule | Minted per block via φ-PoW |
| Dev Fund | 50M VOID (5%) | Pre-allocated at genesis | Dev address |
| DAO/Treasury | 50M VOID (5%) | Pre-allocated at genesis | DAO address |

**Total supply**: 1B VOID (1,000,000,000). Fixed. No inflation.

### Halving Schedule

| Epoch | Submissions | Block Reward | Notes |
|-------|-------------|--------------|-------|
| 0 | 0 – 209,999 | 50 VOID | Genesis |
| 1 | 210,000 – 419,999 | 25 VOID | First halving |
| 2 | 420,000 – 629,999 | 12.5 VOID | Second halving |
| ... | ... | ... | Halve every 210K |
| ∞ | After floor | 0.1 VOID | MIN_BLOCK_REWARD floor |

## Reward Formula

```
reward = blockReward × quality × qualityMultiplier × elasticMultiplier
```

Where:
- `blockReward` = current halving-epoch reward (50 → 25 → 12.5 → ... VOID)
- `quality` = 0–100 (submitted by miner with scientific work)
- `qualityMultiplier` = 1.0x (<70), 1.2x (70–89), 1.5x (90–100)
- `elasticMultiplier` = 0.8x–1.2x based on 10-submission rolling average quality

### Quality Tiers

| Range | Tier | Multiplier | Status |
|-------|------|------------|--------|
| < 70 | Accepted | 1.0x | Base reward |
| 70–89 | Good | 1.2x | Bonus |
| 90–100 | Excellent | 1.5x | Maximum bonus |

Target quality = 75. Elastic mint dampens issuance when quality is high, boosts when low.

## Chain Parameters

| Parameter | Value |
|-----------|-------|
| 1 VOID | 1,000,000,000 micro-VOID |
| Total supply | 1,000,000,000 VOID |
| Initial difficulty | 1000 |
| Target block time | 15 seconds |
| Halving interval | 210,000 submissions |
| Initial block reward | 50 VOID |
| Min block reward | 0.1 VOID |
| Dev fund | 50,000,000 VOID (pre-allocated) |
| DAO treasury | 50,000,000 VOID (pre-allocated) |
| Genesis difficulty floor | max(current/4, 1) |
| φ-PoW candidate size | 1024 bits |
| φ-PoW sieve bound | 2^20 |
| φ-PoW primality | Miller-Rabin (bases 2,3,5,7,11,13) |

## Networking

Plain TCP with length-prefixed JSON protocol. No libp2p.

- **Protocol byte**: 0x01 = persistent gossip, 0x02 = sync
- **Messages**: Block, Tx, SyncRequest, SyncResponse
- **Chain selection**: Heaviest chain (maximum cumulative difficulty)
- **Re-sync**: Every 10 seconds, nodes re-sync with peers
- **Reorgs**: Automatic — fork with more cumulative work wins

## Data Sources (Open Access)

| Archive | URL | Data |
|---------|-----|------|
| MAST | portal.mast.stsci.edu | TESS SPOC 2-min light curves (FITS) |
| SDSS DR18 | skyserver.sdss.org | Galaxy cutout images (JPEG) |
| ZTF/Fink | fink-portal.org | Alert streams (JSON) |
| SIMBAD | simbad.cds.unistra.fr | Object metadata |
| NED | ned.ipac.caltech.edu | Redshift, cross-ids |
| VizieR | vizier.cds.unistra.fr | Published catalog data |
| NASA ADS | ui.adsabs.harvard.edu | Literature references |

## Documentation

User-facing documentation lives on the **[GitHub wiki](https://github.com/thekillsquad007/voidmap/wiki)**.

## License

MIT
