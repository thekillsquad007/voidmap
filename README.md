# Voidmap

**Proof of Useful Work.** GPU miners process real astronomical data from NASA, ESA, and NSF surveys. Earn VOID tokens for running scientific ML computation on real telescope data.

## How It Works

```
Miner downloads real data → Runs pre-trained ML model → Uploads result to IPFS
     ↓                                    ↓                        ↓
  MAST/SDSS/ZTF              Transit/Galaxy/Anomaly        CID stored on-chain
     ↓                                    ↓                        ↓
  Real FITS files          Quality score (50-100)        Pool submits → VOID minted
```

**Miners never touch the blockchain.** The pool operator handles all on-chain submissions. Miners just run GPU inference.

## Quick Start

```bash
cd miner
pip install -r requirements.txt
python voidmap-miner.py --detect          # verify GPU + dependencies
python voidmap-miner.py --list-targets    # show known TESS targets
python voidmap-miner.py --task exoplanet --rounds 10
python voidmap-miner.py --list-results    # view your outputs
```

### Requirements

- Python 3.10+
- NVIDIA GPU (CUDA) or Apple Silicon (MPS) or CPU (slow)
- 4GB+ VRAM for ConvNeXT galaxy model

### Dependencies

```
torch>=2.0       numpy>=1.24       astropy>=5.0
lightkurve>=2.4  huggingface_hub   safetensors>=0.4
ipfshttpclient   Pillow>=9.0       requests>=2.28
websockets>=11   scikit-learn>=1.2
```

## Mining Tasks

| # | Task | Data Source | Model | Output |
|---|------|-------------|-------|--------|
| 1 | Exoplanet Transit Detection | MAST TESS SPOC 2-min | AstroNetCNN (244K params) | Planet/FP/No-signal + confidence |
| 2 | Galaxy Morphology Classification | SDSS DR18 cutout API | GalaxyConvNeXT / Zoobot (15.6M params) | Spiral/Elliptical/Irregular/Merger + confidence |
| 3 | Astronomical Anomaly Detection | ZTF alerts via Fink broker | Autoencoder | Anomaly score + flag |

All data is real. Miners download actual FITS files from MAST, galaxy images from SDSS, and alert streams from ZTF/Fink. No simulations.

### Known TESS Targets

| TIC | Name | Planets |
|-----|------|---------|
| TIC 307210830 | TOI-732 | b, c |
| TIC 261136679 | TOI-1452 | b |
| TIC 36724087 | TOI-700 | b, c, d, e |
| TIC 150428135 | TOI-1259 | A b |
| TIC 441462736 | TOI-1444 | b |

## Quality Scoring

| Range | Tier | Reward Multiplier |
|-------|------|-------------------|
| < 50 | Rejected | — (work not accepted) |
| 50–69 | Accepted | 1x |
| 70–89 | Good | 1.2x |
| 90–100 | Excellent | 1.5x |

Quality is derived from model confidence with a deterministic noise factor (from input/output hashes) to prevent gaming. A 12-second cooldown between submissions limits spam.

## Anti-ASIC Measures

Voidmap enforces GPU-only mining through five defense layers:

1. **Architecture Rotation** — switches between CNN / Transformer / Mamba / ConvNeXT every 100 blocks
2. **Weight Perturbation** — random noise added to model weights each rotation (can't pre-compute solutions)
3. **Random Batch Sizes** — 16–128, can't optimize pipeline for fixed input
4. **Memory-Hard Operations** — 512MB random-access data allocation, too large for ASIC SRAM
5. **Cryptographic Seeds** — `os.urandom(32)` for weight seeds, not `time.time()` (which is pre-computable)

## Architecture

```
voidmap/
├── contracts/
│   ├── VoidmapToken.sol     # ERC-20, 90% miner allocation, renounceable
│   ├── MiningPool.sol       # Work submissions, quality scoring, pool support, reward minting
│   ├── Voidmap.t.sol        # 31 forge tests
│   └── foundry.toml
├── miner/
│   ├── voidmap-miner.py     # Solo miner (hyphenated name, direct run)
│   ├── voidmap_miner.py     # Same (underscore, for Python imports)
│   ├── anti_asic.py         # Architecture rotation, weight perturbation, memory-hard ops
│   ├── stratum.py           # Stratum protocol messages
│   ├── stratum_pool.py      # Stratum pool server (for pool operators)
│   ├── pool.py              # WebSocket pool server (legacy)
│   ├── pool_client.py       # Pool client (connects to pool, receives work, submits shares)
│   ├── ipfs_upload.py       # Upload results to IPFS (Pinata fallback, sha256 content hash if offline)
│   ├── results_api.py       # REST API for researchers to query results
│   └── requirements.txt
├── web/
│   └── index.html           # Dashboard (live data from API, wallet connect)
├── docs/                    # GitBook documentation (11 pages)
├── deploy.sh                # Deploy contracts to Base
└── .github/workflows/
    └── test-contracts.yml   # CI: forge build + forge test
```

## Contracts

### VoidmapToken (ERC-20)

- 1B max supply, 18 decimals
- 900M VOID (90%) minted to miners via `mintMinerReward()`
- 50M VOID (5%) minted to dev fund at deploy, 4-year vesting
- 50M VOID (5%) minted to DAO/treasury at deploy (no vesting)
- `renounce()` — permanently disables minting + renounces ownership
- `devClaim(address to)` — dev transfers vested tokens after 4 years

### MiningPool

- Task management: `createTask()`, `deactivateTask()`
- Solo mining: `submitWork()` — anyone can submit
- Pool mining: `submitPoolWork()` — pool operator submits on behalf of members
- Quality scoring with anti-gaming noise
- 2% pool fee, withdrawable by operator via `withdrawPoolFees()`
- 12-second submission cooldown per miner
- Member share tracking with cleanup on `removePoolMember()`

## Tokenomics

| Allocation | Amount | Details |
|------------|--------|---------|
| GPU Miners | 900M VOID (90%) | Minted per submission, quality-based |
| Dev Fund | 50M VOID (5%) | 4-year vesting, claimable after |
| DAO/Treasury | 50M VOID (5%) | Minted at deploy, no vesting |

Reward formula: `1 VOID × quality × multiplier / 10`

- Base (50-69): 1x → 5–6.9 VOID
- Good (70-89): 1.2x → 8.4–10.68 VOID
- Excellent (90-100): 1.5x → 13.5–15 VOID

Pool submissions: 2% fee deducted, accumulated for operator withdrawal.

## Deployment (Base L2)

### Prerequisites

- [Foundry](https://book.getfoundry.sh) installed (`curl -L https://foundry.paradigm.xyz | bash`)
- Deployer wallet with ETH on Base (~0.0001 ETH recommended)
- RPC endpoint (public: `https://mainnet.base.org`)

### Deploy

```bash
export DEPLOYER_PK=0x...your_private_key...
export DEV_ADDR=0x...your_dev_fund_address...
export DAO_ADDR=0x...your_dao_treasury_address...  # optional, defaults to DEV_ADDR
export RPC_URL=https://mainnet.base.org            # optional

bash deploy.sh
```

This deploys VoidmapToken, MiningPool, and transfers token ownership to the pool contract. Gas cost: ~3.15M gas (~0.00006 ETH at 19 Gwei).

### Verify on BaseScan

```bash
forge verify-contract <TOKEN_ADDRESS> VoidmapToken.sol:VoidmapToken \
  --verifier blockscout --verifier-url https://api.basescan.org/api

forge verify-contract <POOL_ADDRESS> MiningPool.sol:MiningPool \
  --verifier blockscout --verifier-url https://api.basescan.org/api
```

## Pool Setup (for pool operators)

### WebSocket Pool (legacy)

```bash
pip install websockets
python pool.py  # starts on ws://0.0.0.0:8546
```

### Stratum Pool (recommended)

```bash
pip install websockets
python stratum_pool.py --port 3333
```

Pool operators need:
- RPC endpoint (`https://mainnet.base.org` or Alchemy/Infura)
- Wallet with ETH for gas (to submit `submitWork`/`submitPoolWork` on-chain)
- MiningPool contract address (from deployment)

### Pool Client (for miners connecting to a pool)

```bash
python pool_client.py --pool ws://pool.example.com:8546 --miner-id my_rig_1
```

Miners connecting to a pool do **not** need ETH or an RPC endpoint. The pool pays all gas.

## IPFS Setup (for result storage)

Results are uploaded to IPFS so researchers can access them. Options:

1. **Local IPFS daemon** — install [Kubo](https://docs.ipfs.tech/install/), run `ipfs daemon`
2. **Pinata (free tier)** — 100 pins/month, set `PINATA_API_KEY` + `PINATA_API_SECRET`
3. **Offline fallback** — results saved locally with `sha256:` content hash

```bash
# With IPFS daemon running:
pip install ipfshttpclient
# Results auto-upload when you mine

# With Pinata:
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
| `GET /results?task=exoplanet&min_quality=80` | Filter by task, quality, miner, target |
| `GET /results/{id}` | Specific result |
| `GET /results/{id}/ipfs` | Fetch from IPFS gateway |
| `GET /stats` | Aggregate statistics |
| `GET /targets` | Known TESS targets |
| `GET /tasks` | Available mining tasks |

### Query examples

```bash
# Get high-quality exoplanet detections
curl http://localhost:8547/results?task=exoplanet&min_quality=80

# Get all results for a specific target
curl http://localhost:8547/results?target=TOI-700

# Fetch a result from IPFS gateway
curl http://localhost:8547/results/result_exoplanet_1234567890/ipfs

# Pool statistics
curl http://localhost:8547/stats
```

## Website

```bash
# Static, just open in browser
open web/index.html
# Or serve it:
python -m http.server 8080 --directory web
```

The dashboard shows network stats, active tasks, quality thresholds, the data pipeline, and researcher info. Live leaderboard/submissions populate from the Results API when the network is active. Includes MetaMask wallet connect.

## Testing

```bash
cd contracts
forge test --skip "lib/openzeppelin-contracts/fv" -vv   # 31 tests
forge test --gas-report                                  # gas usage
forge build --sizes                                      # contract sizes
```

## Data Sources (for researchers)

All data comes from public, open-access archives:

| Archive | API | Data |
|---------|-----|------|
| MAST | portal.mast.stsci.edu | TESS SPOC 2-min light curves (FITS) |
| SDSS DR18 | skyserver.sdss.org | Galaxy cutout images (JPEG/PNG) |
| ZTF/Fink | fink-portal.org | Alert streams (JSON) |
| SIMBAD | simbad.cds.unistra.fr | Object metadata |
| NED | ned.ipac.caltech.edu | Redshift, cross-ids |
| VizieR | vizier.cds.unistra.fr | Published catalog data |
| NASA ADS | ui.adsabs.harvard.edu | Literature references |

## License

MIT
