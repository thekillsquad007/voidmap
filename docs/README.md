# Welcome to Voidmap

**Proof of Useful Work — GPU miners process real astronomical data**

Voidmap is an ERC-20 token on Base where GPU miners earn VOID by processing real astronomical data from NASA, ESA, and NSF surveys. Unlike traditional Proof of Work, Voidmap's computation produces scientifically useful results.

---

## Quick Links

| Section | Description |
|---------|-------------|
| [Tokenomics](tokenomics.md) | Token supply, distribution, vesting |
| [Proof of Useful Work](pouw.md) | How mining works, quality scoring |
| [Mining Guide](mining.md) | How to set up and run a miner |
| [Pool Guide](pool.md) | How to join or run a mining pool |
| [Anti-ASIC](anti-asic.md) | How we prevent ASIC/FPGA centralization |
| [Stratum Protocol](stratum.md) | Mining protocol specification |
| [API Reference](api.md) | REST API for querying results |
| [Smart Contracts](contracts.md) | On-chain contract details |
| [Data Sources](data-sources.md) | Where the astronomical data comes from |
| [FAQ](faq.md) | Frequently asked questions |

---

## How It Works

1. **Miner downloads** real data from NASA MAST, SDSS, or ZTF
2. **GPU runs** a pre-trained ML model (transit detection, galaxy classification, anomaly detection)
3. **Results stored** on IPFS with CID recorded on-chain
4. **Quality scored** by actual model metrics (confidence, reconstruction error)
5. **VOID rewarded** based on quality score (higher quality = more VOID)

---

## The Problem

Traditional PoW wastes energy on hash puzzles with zero useful output. Public astronomical archives hold petabytes of unprocessed data. Researchers lack GPU compute to process it.

## The Solution

Voidmap directs GPU mining power toward actual scientific computation. Miners process real data, produce real predictions, and earn VOID for contributing to science.

---

## Start Mining

```bash
# Install dependencies
pip install torch lightkurve astropy huggingface_hub safetensors

# Detect your GPU
python miner/voidmap-miner.py --detect

# Mine with real TESS data
python miner/voidmap-miner.py --task exoplanet --rounds 10

# Or connect to a pool
python miner/stratum_miner.py --pool ws://pool.voidmap.org:3333 --user YOUR_ADDRESS
```

---

## Contract Addresses

After deployment, add your contract addresses here:

| Contract | Address |
|----------|---------|
| VoidmapToken (ERC-20) | `0x...` |
| MiningPool | `0x...` |

Deploy with:
```bash
export DEPLOYER_PK=0x...
export DEV_ADDR=0x...
bash deploy.sh
```
