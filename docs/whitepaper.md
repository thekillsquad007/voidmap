# Voidmap Whitepaper

## Proof of Useful Work

GPU miners process real astronomical data. Earn VOID tokens. Contribute to science.

### The Problem

- PoW mining wastes energy on hashing with zero useful output
- Public astronomical archives (NASA TESS, SDSS, ZTF) hold petabytes of unprocessed data
- Researchers lack GPU compute to process it all

### The Solution

Voidmap directs GPU mining power toward actual scientific computation:
- Download real data from public archives
- Run real ML models (CNNs, EfficientNets, Autoencoders)
- Quality scores reflect real model performance
- Results are verifiable and reproducible

### Tokenomics

| Allocation | % | Amount |
|------------|---|--------|
| GPU Miners | 90% | 900M VOID |
| Developer Fund | 5% | 50M VOID |
| Treasury | 5% | 50M VOID |

Dev fund vests over 4 years with all wallet addresses published at genesis.

### Mining Tasks

1. **Exoplanet Transit Detection**
   - Model: 1D CNN (TransitCNN)
   - Data: TESS 2-minute cadence light curves (MAST)
   - Output: Transit confidence scores

2. **Galaxy Morphology Classification**
   - Model: EfficientNet-V2
   - Data: SDSS DR18 and HST imagery
   - Output: Galaxy class + confidence (Spiral, Elliptical, Irregular, Merger)

3. **Astronomical Anomaly Detection**
   - Model: Autoencoder (AnomalyAE)
   - Data: ZTF alert stream
   - Output: Anomaly scores based on reconstruction error

### Smart Contracts

- **VoidmapToken** — ERC-20 with 90% miner allocation, transparent dev fund
- **MiningPool** — Accepts GPU work submissions, distributes rewards

### Governance

Future DAO will control:
- Task selection (what gets computed)
- Reward multipliers per task
- Treasury grants for ecosystem development

### No Promises. Just Code.

Voidmap has no company, no CEO, no roadmap. It exists as open-source code on GitHub. The contracts are deployable by anyone. The value is in the computation.
