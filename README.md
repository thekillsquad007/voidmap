# Voidmap

**GPUs analyze space imagery → Earn VOID → Sell data → Value flows back to miners**

A hybrid Proof of Useful Work (PoUW) token. Miners run GPU-powered computer vision on public astronomical datasets (Hubble, JWST, TESS). The results — exoplanet transits, galaxy classifications, anomaly detections — are verified by the network and sold on the built-in data marketplace.

**Works on:** NVIDIA (CUDA), AMD (ROCm/OpenCL), Apple Silicon (MPS), Intel (OpenCL), CPU

## Quick Start

```bash
# Install the miner
cd miner
pip install -r requirements.txt

# Run it (auto-detects best GPU backend)
python voidmap-miner.py --address 0xYourWallet --rounds 10

# Or detect your hardware
python voidmap-miner.py --detect
```

## How It Works

```
GPU Miner runs astronomical analysis
        │
        ▼
  Submits proof of work (quality score 0-100)
        │
        ▼
  Network verifies (spot-check + cross-validation)
        │
        ▼
  Earns VOID tokens proportional to data quality
        │
        ▼
  Data listed on marketplace for researchers
        │
        ▼
  Fees buy back & burn → sustainable value loop
```

## GPU Mining Tasks (DAO-rotated)

| Task | Dataset | Model | GPU Load |
|------|---------|-------|----------|
| Exoplanet Transit Detection | TESS light curves | 1D CNN | Light |
| Galaxy Morphology | JWST/Hubble images | EfficientNet | Heavy |
| Anomaly Detection | ZTF alert stream | Autoencoder | Medium |

## Smart Contracts

| Contract | Address | Description |
|----------|---------|-------------|
| VoidmapToken | *deployed* | ERC-20 with vesting & renounce |
| DataMarketplace | *deployed* | Buy/sell verified astronomical data |
| MiningPool | *deployed* | GPU work submission & rewards |

## Tokenomics

| Supply | 1,000,000,000 VOID |
|--------|-------------------|
| GPU Miners | ~40% over 10 years |
| Dev Fund | 12% (4-year vesting, 6-month cliff) |
| Treasury | 15% (DAO-controlled grants) |
| Public/LP/Airdrop | 23% |
| Partners | 10% |

## Architecture

```
web/              → GitHub Pages (landing page)
explorer/         → GitHub Pages or Vercel (block explorer)
contracts/        → Solidity (Ethereum L2)
miner/            → Python GPU miner (any GPU)
```

## Deploy Contracts

```bash
cd contracts
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge build
forge script script/Deploy.s.sol --rpc-url <rpc> --broadcast
```

## License

MIT
