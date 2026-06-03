# Voidmap

**Proof of Useful Work.** GPU miners process real astronomical data from NASA, ESA, and NSF surveys. Earn VOID for running scientific computation.

## Quick Start

```bash
cd miner
pip install torch numpy astropy
python voidmap-miner.py --detect
python voidmap-miner.py --rounds 100
```

## Mining Tasks

| Task | What it does | Data source |
|------|-------------|-------------|
| Exoplanet Transit | Detect transits in TESS light curves (1D CNN) | MAST Archive |
| Galaxy Morphology | Classify SDSS/HST galaxies (EfficientNet) | SDSS DR18 |
| Anomaly Detection | Flag unusual transients (Autoencoder) | ZTF / IPAC |

## Tokenomics

| Metric | Value |
|--------|-------|
| VOID Supply | 1,000,000,000 |
| GPU Miners | 90% (900M) |
| Dev Fund | 5% (50M) — 4yr vesting |
| Treasury | 5% (50M) — community DAO |

## Real data, real computation

- Miners download real astronomical data from public archives
- Process it with actual ML models (not simulations)
- Quality scored by model confidence / reconstruction error
- Results are verifiable and scientifically useful

## Contracts

```
VoidmapToken.sol → ERC-20, 90% miner allocation, renounceable
MiningPool.sol   → Accepts work submissions, mints rewards
```

## Deployment

```bash
export DEPLOYER_PK=0x...
export DEV_ADDR=0x...
bash deploy.sh
```

## License

MIT
