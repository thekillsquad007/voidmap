# Voidmap

**Proof of Useful Work.** GPU miners process real astronomical data from NASA, ESA, and NSF surveys. Earn VOID tokens for running scientific ML inference on real telescope data.

```
  Real telescope data              Real ML models                Real science
       ↓                                ↓                            ↓
   MAST TESS  ───→  GPU Inference  ───→  IPFS + on-chain  ───→  Exoplanets found
   SDSS Galaxies       (AstroNet)         (verifiable)            Galaxies classified
   ZTF Alerts          (Zoobot)                                  Anomalies flagged
```

## Why Voidmap

| Problem | Voidmap Solution |
|---------|------------------|
| PoW wastes energy on useless hashes | Computation produces real scientific results |
| Public archives hold petabytes of unanalyzed data | Miners process it, get paid in VOID |
| GPUs are commoditized (NVIDIA/AMD) | Anti-ASIC design + elastic mint keeps mining fair |
| Token founders can rug | Token is ownerless from day one, autonomous governance |

## Quick Start

### Test (no wallet needed)

```bash
cd miner
pip install -r requirements.txt
python voidmap_miner.py --detect          # verify GPU + dependencies
python voidmap_miner.py --task exoplanet --rounds 1
```

### Mine & Submit to Testnet (Base Sepolia)

```bash
# Get free Sepolia ETH from https://www.alchemy.com/faucets/base-sepolia
python voidmap_miner.py --task exoplanet --rounds 1 --submit \
  --rpc-url https://sepolia.base.org \
  --pool-address 0x3768e25aFc129D4455e267819801f2b2914fA4A2 \
  --private-key 0xYOUR_PRIVATE_KEY
```

### HiveOS / Docker (AMD + NVIDIA)

```bash
# One-liner install
bash <(curl -s https://raw.githubusercontent.com/thekillsquad007/voidmap/main/install_hiveos.sh)
voidmap --task exoplanet --rounds 1000 --submit --private-key 0x... --rpc-url https://mainnet.base.org

# Or Docker
docker compose up -d voidmap-miner        # NVIDIA
docker compose up -d voidmap-miner-amd    # AMD (Radeon, ROCm)
```

## What Just Got Built (v1.0 Mainnet)

The smart contracts are now production-ready with full autonomy:

- **Ownerless from day one** — Token has no owner. No one can mint outside the MiningPool. No one can change params without a 7-day timelock.
- **Bitcoin-style halving** — Block reward starts at 50 VOID, halves every 210,000 submissions. Floor at 0.1 VOID.
- **Elastic supply** — Reward scales with network quality. High quality → 0.8x dampener (slow issuance). Low quality → 1.2x boost (attract more miners).
- **Challenge/slash** — Any miner can challenge a submission within 6 hours. If quality is below floor, submitter loses 20% of reward. 50% to challenger, 50% burned.
- **Time-locked governance** — Param changes require 7-day delay + proposer must stake 1% of miner supply.

See `docs/mainnet-features.md` for the full specification.

## Mining Tasks

| # | Task | Data Source | Model | Output | Task ID |
|---|------|-------------|-------|--------|---------|
| 1 | Exoplanet Transit Detection | MAST TESS SPOC 2-min | AstroNetCNN (244K params, 89% acc) | Planet/FP/No-signal + confidence | 1 |
| 2 | Galaxy Morphology Classification | SDSS DR18 cutout | GalaxyClassifier (Zoobot-ready) | Spiral/Elliptical/Irregular/Merger | 2 |
| 3 | Astronomical Anomaly Detection | ZTF alerts via Fink | Autoencoder | Anomaly score + flag | 3 |

All data is **real**. Miners download actual FITS files from MAST, galaxy images from SDSS, and alert streams from ZTF/Fink. No simulations.

### Known TESS Targets

| TIC | Name | Planets |
|-----|------|---------|
| TIC 307210830 | TOI-732 | b, c |
| TIC 261136679 | TOI-1452 | b |
| TIC 36724087 | TOI-700 | b, c, d, e |
| TIC 150428135 | TOI-1259 | A b |
| TIC 441462736 | TOI-1444 | b |

## Reward Formula

```
reward = blockReward × quality × qualityMultiplier × elasticMultiplier
        ───────────────────────────────────────────────────────────
                              10 × 100
```

Where:
- `blockReward` = current halving-epoch reward (50 → 25 → 12.5 → ... VOID)
- `quality` = 50–100 (with deterministic noise floor)
- `qualityMultiplier` = 1.0x (base), 1.2x (good), 1.5x (excellent)
- `elasticMultiplier` = 0.8x–1.2x based on 10-submission rolling average quality

### Example: Excellent work in first halving epoch (no elasticity)

```
quality = 95, qualityMultiplier = 1.5, elasticMultiplier = 1.0, blockReward = 50
reward = (50 × 95 × 15 × 100) / (10 × 100) = 712.5 VOID
```

### Quality Tiers

| Range | Tier | Multiplier | Status |
|-------|------|------------|--------|
| < 50 | Rejected | — | Work not accepted, no reward |
| 50–69 | Accepted | 1.0x | Base reward |
| 70–89 | Good | 1.2x | Bonus |
| 90–100 | Excellent | 1.5x | Maximum bonus |

12-second cooldown per miner. Pool submissions deduct 2% fee.

## Tokenomics

| Allocation | Amount | Vesting | Recipient |
|------------|--------|---------|-----------|
| GPU Miners | 900M VOID (90%) | Halving schedule | Minted per submission via MiningPool |
| Dev Fund | 50M VOID (5%) | 4 years | Dev address, claimable after vesting |
| DAO/Treasury | 50M VOID (5%) | None | DAO address, unlocked at genesis |

**Total supply**: 1B VOID (1,000,000,000). Fixed. No inflation.

**Token is ownerless**: No one can mint outside the MiningPool. No one can change the protocol without a 7-day timelock + 1% proposer quorum.

### Halving Schedule

| Epoch | Subscriptions | Block Reward | Notes |
|-------|--------------|--------------|-------|
| 0 | 0 – 209,999 | 50 VOID | Genesis |
| 1 | 210,000 – 419,999 | 25 VOID | First halving |
| 2 | 420,000 – 629,999 | 12.5 VOID | Second halving |
| 3 | 630,000 – 839,999 | 6.25 VOID | Third halving |
| ... | ... | ... | Halve every 210K |
| ∞ | After floor | 0.1 VOID | MIN_BLOCK_REWARD floor |

Total mined at genesis rate (no halvings): ~21M VOID over 4,200,000 submissions. At a real-world rate of 100K submissions/day, that's ~42 days to first halving. Halvings slow issuance; elastic mint rewards quality.

## Anti-ASIC Defense (5 Layers)

1. **Real Data Pipeline** — HTTP downloads, variable FITS/JPEG sizes, Python preprocessing. Can't be synthesized to fixed hardware.
2. **Dynamic ML Models** — PyTorch/ONNX with BatchNorm, Dropout, AdaptiveAvgPool. Variable input shapes.
3. **Timing Attestation** — `MIN_COMPUTE_DURATION = 2 seconds` enforced both client and on-chain. Sub-2s results rejected.
4. **Hardware Detection** — FPGA, emulated, virtual, software-renderer GPUs rejected at startup.
5. **Architecture Rotation** — `anti_asic.py` rotates between CNN/Transformer/Mamba/ConvNeXT every 100 blocks. Weight perturbation prevents pre-computation.

## Architecture

```
voidmap/
├── contracts/
│   ├── VoidmapToken.sol     # ERC-20, ownerless, halving-aware, 1-time minter migration
│   ├── MiningPool.sol       # Tasks, pools, halving, elastic mint, challenge/slash, timelock
│   └── Voidmap.t.sol        # 48 forge tests
├── miner/
│   ├── voidmap_miner.py     # Multi-backend miner (PyTorch CUDA/ROCm/MPS + ONNX DirectML/CPU)
│   ├── model_backend.py     # Backend auto-detection (CUDA → ROCm → DirectML → CPU)
│   ├── anti_asic.py         # Architecture rotation, weight perturbation, memory-hard ops
│   ├── stratum_pool.py      # Stratum protocol pool server
│   ├── pool_client.py       # Pool client (bounded retry)
│   ├── ipfs_upload.py       # IPFS upload (Pinata + sha256 fallback)
│   ├── results_api.py       # REST API for researchers
│   └── requirements.txt
├── web/
│   └── index.html           # Static dashboard with live stats, wallet connect
├── docs/                    # GitBook (whitepaper, contracts, mining, etc.)
├── deploy.sh                # Mainnet deploy to Base
├── deploy-testnet.sh        # Testnet deploy to Base Sepolia
├── Dockerfile               # CUDA + ONNX DirectML Docker image
├── Dockerfile.hiveos        # ROCm-optimized for HiveOS
├── docker-compose.yml       # One-command deploy (NVIDIA + AMD)
├── install_hiveos.sh        # Native HiveOS install script
└── test-e2e.sh              # 21 live testnet E2E checks
```

## Smart Contracts

### VoidmapToken (Ownerless ERC-20)

- **Fixed supply**: 1B VOID (1,000,000,000 × 10¹⁸)
- **90% (900M)**: Minted to miners by MiningPool via `mintMinerReward()`
- **5% (50M)**: Dev fund, 4-year vesting, claimable by dev address
- **5% (50M)**: DAO/Treasury, unlocked at genesis
- **No owner** — No `Ownable` inheritance. `minter` is set via one-time `migrateMinter()` then locked forever
- **Burns**: `burnFromMiner()` allows the pool to burn VOID (challenge bonds, slash burns)

### MiningPool (Autonomous)

**Core features:**
- `createTask(name, dataSource, modelSpec)` — Add new mining task (requires proposer quorum)
- `deactivateTask(taskId)` — Disable a task
- `submitWork(...)` — Solo miner submission
- `submitPoolWork(...)` — Pool operator submits on behalf of members (2% fee)

**Halving:**
- `HALVING_INTERVAL = 210,000` submissions
- `INITIAL_BLOCK_REWARD = 50 VOID`, halve each epoch
- `MIN_BLOCK_REWARD = 0.1 VOID` floor
- `getHalvingEpoch()` / `getHalvingProgress()` / `getCurrentBlockReward()`

**Elastic Mint:**
- 10-submission rolling quality window
- `TARGET_QUALITY = 75` (dead zone ±5)
- `MIN_ELASTIC_MULTIPLIER = 0.8x`, `MAX_ELASTIC_MULTIPLIER = 1.2x`
- `getAvgNetworkQuality()` / `getCurrentElasticMultiplier()`

**Challenge/Slash:**
- `CHALLENGE_WINDOW = 6 hours` to file a challenge
- `CHALLENGE_BOND = 1 VOID` (burned on file, refunded to winner)
- `CHALLENGE_RESOLUTION_DELAY = 1 hour` (allows re-execution)
- `SLASH_BPS = 20%` of submitter's reward
- `CHALLENGER_REWARD_BPS = 50%` of slash, 50% burned
- `fileChallenge(submissionId)` / `resolveChallenge(challengeId)`

**Time-Locked Governance:**
- `TIMELOCK_DELAY = 7 days`
- `PROPOSER_QUORUM_BPS = 1%` of total miner-minted
- `stakeAsProposer(amount)` / `unstakeProposer(amount)`
- `proposeTimelock(dataHash)` / `executeTimelock(id)` / `cancelTimelock(id)`

**Pool support:**
- `createPool(name, feeRecipient)` — Anyone can create a pool
- `addPoolMember()` / `removePoolMember()` — Operator manages members
- `withdrawPoolFees()` — Operator withdraws accumulated 2% fees

## Deployment (Base L2)

### Prerequisites

- [Foundry](https://book.getfoundry.sh) installed (`curl -L https://foundry.paradigm.xyz | bash`)
- Deployer wallet with ETH on Base (~0.0001 ETH recommended)
- RPC endpoint (public: `https://mainnet.base.org` or Alchemy/Infura)

### Deploy to Testnet

```bash
export DEPLOYER_PK=0x...your_private_key...
export DEV_ADDR=0x...your_dev_fund_address...   # defaults to deployer
export DAO_ADDR=0x...your_dao_treasury...        # defaults to dev
export RPC_URL=https://sepolia.base.org          # optional

bash deploy-testnet.sh
```

This deploys both contracts in 2 steps:
1. MiningPool (with placeholder token)
2. VoidmapToken (with pool's address)
3. `migrateMinter(pool)` to lock the minter
4. Bootstrap proposer quorum with 1 VOID stake
5. Create the 3 default tasks (Exoplanet, Galaxy, Anomaly)

### Deploy to Mainnet

```bash
export DEPLOYER_PK=0x...your_mainnet_key...
export DEV_ADDR=0x...your_multisig_or_cold_wallet...
export RPC_URL=https://mainnet.base.org

bash deploy.sh
```

**After deploy, the token is ownerless.** Only the MiningPool can mint. Period.

### Verify on BaseScan

```bash
forge verify-contract <TOKEN_ADDRESS> VoidmapToken.sol:VoidmapToken \
  --verifier blockscout --verifier-url https://api.basescan.org/api

forge verify-contract <POOL_ADDRESS> MiningPool.sol:MiningPool \
  --verifier blockscout --verifier-url https://api.basescan.org/api
```

## Pool Setup (for pool operators)

### Stratum Pool (recommended)

```bash
pip install websockets
python stratum_pool.py --port 3333
```

Pool operators need:
- MiningPool contract address
- Wallet with ETH for gas (to submit on-chain)
- RPC endpoint

### Pool Client (for miners connecting to a pool)

```bash
python pool_client.py --pool ws://pool.example.com:8546 --miner-id my_rig_1
```

Miners connecting to a pool do **not** need ETH or an RPC. The pool handles on-chain submission.

## IPFS Setup

Results are uploaded to IPFS for permanent storage:

1. **Local IPFS daemon** — `ipfs daemon`
2. **Pinata (free tier)** — Set `PINATA_API_KEY` + `PINATA_API_SECRET`
3. **Offline fallback** — `sha256:<hash>` content hash (results saved locally)

```bash
# With Pinata
export PINATA_API_KEY=...
export PINATA_API_SECRET=...
```

## Results API (for researchers)

```bash
python results_api.py --port 8547
```

| Endpoint | Description |
|----------|-------------|
| `GET /` | API info |
| `GET /results` | All results |
| `GET /results?task=exoplanet&min_quality=80` | Filtered results |
| `GET /results/{id}` | Specific result |
| `GET /results/{id}/ipfs` | Fetch from IPFS gateway |
| `GET /stats` | Aggregate statistics |
| `GET /targets` | Known TESS targets |
| `GET /tasks` | Available mining tasks |

## Multi-Backend GPU Support

| Backend | GPU Type | Install |
|---------|----------|---------|
| PyTorch CUDA | NVIDIA | `pip install torch` (default) |
| PyTorch ROCm | AMD (Linux) | `pip install torch --index-url https://download.pytorch.org/whl/rocm6.2` |
| ONNX DirectML | AMD/Intel/NVIDIA | `pip install onnxruntime-directml` |
| ONNX CPU | Universal | `pip install onnxruntime` |

The miner auto-selects the best available backend. No code changes needed.

## Website

```bash
# Static
open web/index.html

# Or serve
python -m http.server 8080 --directory web
```

Dashboard includes:
- Live network stats (supply, halving, miners, tasks)
- Quality tier visualization
- Pipeline walkthrough
- Researcher info
- Wallet connect
- Recent submissions (from API when live)

## Testing

```bash
cd contracts
forge test -vv       # 48 tests
forge test --gas-report  # gas usage
forge build --sizes  # contract sizes
```

```bash
# End-to-end on live testnet
bash test-e2e.sh  # 21 checks
```

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

Source files (versioned with the repo) are in `wiki/`. To sync them to the GitHub wiki:

```bash
# One-time bootstrap: visit https://github.com/thekillsquad007/voidmap/wiki
# and click "Create the first page" (any content, just title: Home).
# Then re-run:
./scripts/publish-wiki.sh
```

The wiki includes:
- [How to Mine](https://github.com/thekillsquad007/voidmap/wiki/How-to-Mine) — step-by-step
- [Whitepaper](https://github.com/thekillsquad007/voidmap/wiki/Whitepaper)
- [Mainnet Features](https://github.com/thekillsquad007/voidmap/wiki/Mainnet-Features) — halving, elastic, challenge, timelock
- [Tokenomics](https://github.com/thekillsquad007/voidmap/wiki/Tokenomics)
- [Smart Contracts](https://github.com/thekillsquad007/voidmap/wiki/Smart-Contracts)
- [Mining Guide](https://github.com/thekillsquad007/voidmap/wiki/Mining-Guide)
- [AMD/ROCm Setup](https://github.com/thekillsquad007/voidmap/wiki/AMD-ROCm-Setup)
- [FAQ](https://github.com/thekillsquad007/voidmap/wiki/Frequently-Asked-Questions)
- See [the full sidebar](https://github.com/thekillsquad007/voidmap/wiki/_Sidebar) for everything

Developer-facing docs (tied to specific code versions) remain in `docs/`.

## License

MIT
