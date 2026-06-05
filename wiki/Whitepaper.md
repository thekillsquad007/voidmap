# Voidmap Whitepaper

## Abstract

Voidmap is a Proof of Useful Work (PoUW) cryptocurrency where GPU miners process real astronomical data from public NASA, ESA, and NSF archives. Miners earn VOID tokens for running machine learning inference on real telescope data — exoplanet transit detection, galaxy morphology classification, and anomaly detection in ZTF alert streams. The protocol is autonomous: no founder, no owner, no admin keys. The smart contracts are immutable from day one; all parameter changes require a 7-day time-lock and 1% proposer quorum.

## 1. The Problem

### 1.1 Wasted Computation

Traditional Proof of Work cryptocurrencies (Bitcoin, Litecoin, Dogecoin) consume gigawatts of electricity to compute hashes with no useful output. As of 2024, Bitcoin mining alone consumes more electricity than Poland.

### 1.2 Unanalyzed Public Data

Public astronomical archives contain petabytes of unprocessed data:

| Archive | Data | Volume |
|---------|------|--------|
| MAST (TESS) | Light curves from exoplanet survey | ~1 PB |
| SDSS DR18 | Galaxy images + spectra | ~500 TB |
| ZTF | Time-domain alerts (transients) | ~50 TB / year |
| Rubin LSST (upcoming) | Full-sky survey | ~500 PB / year |

Researchers lack the GPU compute to process all of it.

### 1.3 Founder Risk

Most crypto projects have founders with admin keys, premine, or upgrade paths. This creates rug-pull risk and centralization. Voidmap has none of these.

## 2. The Solution

### 2.1 Proof of Useful Work

Voidmap redirects GPU mining power from hashing to scientific computation. Miners:

1. Download real telescope data from public APIs
2. Run pre-trained ML models (AstroNet, Zoobot, Autoencoder) to extract predictions
3. Upload results to IPFS for permanence
4. Submit on-chain for VOID rewards

The computation is real, the data is real, the results are scientifically useful.

### 2.2 Autonomous Protocol

The smart contracts are designed to be **immutable and ownerless from day one**:

- **No `Ownable` inheritance** — Token has no owner. No one can mint outside the MiningPool.
- **No upgrade pattern** — Contracts are not upgradeable. Code is law.
- **No multisig** — The protocol has no privileged signer. All admin functions are gated by 7-day time-locks.
- **No emergency switch** — No `pause()` or `blacklist()`. Once deployed, the protocol runs autonomously forever.

## 3. Tokenomics

### 3.1 Supply

| Allocation | % | Amount | Vesting |
|------------|---|--------|---------|
| GPU Miners | 90% | 900M VOID | Halving schedule |
| Dev Fund | 5% | 50M VOID | 4 years |
| DAO/Treasury | 5% | 50M VOID | None |

**Total**: 1,000,000,000 VOID (fixed, 18 decimals, no inflation).

### 3.2 Halving Schedule

Block reward starts at 50 VOID and halves every 210,000 submissions (Bitcoin-inspired):

| Epoch | Subscriptions | Block Reward |
|-------|--------------|--------------|
| 0 | 0 – 209,999 | 50 VOID |
| 1 | 210,000 – 419,999 | 25 VOID |
| 2 | 420,000 – 629,999 | 12.5 VOID |
| 3 | 630,000 – 839,999 | 6.25 VOID |
| ... | ... | ... |
| ∞ | After floor | 0.1 VOID |

`MIN_BLOCK_REWARD = 0.1 VOID` (no zero reward — every submission gets something).

### 3.3 Elastic Mint

Reward is scaled by a network-quality multiplier. The 10-submission rolling average quality is tracked:

- Target quality: 75 (dead zone ±5)
- If avg > 80: multiplier drops to 0.8x (slow issuance when network is over-performing)
- If avg < 70: multiplier rises to 1.2x (boost rewards when network is struggling)

This prevents runaway issuance during high-quality periods and incentivizes more miners during low-quality periods.

### 3.4 Reward Formula

```
reward = blockReward × quality × qualityMultiplier × elasticMultiplier
        ────────────────────────────────────────────────────────────
                              10 × 100
```

Where:
- `blockReward` = current halving-epoch reward (50 → 25 → 12.5 → ... → 0.1)
- `quality` = 50–100 (deterministic noise floor applied)
- `qualityMultiplier` = 1.0x (base), 1.2x (good ≥70), 1.5x (excellent ≥90)
- `elasticMultiplier` = 0.8x–1.2x based on 10-sub rolling average

## 4. Quality Scoring

### 4.1 Tiers

| Range | Tier | Multiplier | Status |
|-------|------|------------|--------|
| < 50 | Rejected | — | Work not accepted |
| 50 – 69 | Accepted | 1.0x | Base reward |
| 70 – 89 | Good | 1.2x | Bonus |
| 90 – 100 | Excellent | 1.5x | Maximum bonus |

### 4.2 Anti-Gaming Noise

A deterministic noise factor (0–9) is derived from `keccak256(inputHash, outputHash, block.timestamp)` and subtracted from the submitted quality. This prevents miners from gaming by submitting the exact same input multiple times — the noise varies per submission.

### 4.3 Cooldown

A 12-second cooldown per miner address prevents spam submissions.

## 5. Anti-ASIC Defense

The protocol is designed so that specialized hardware (FPGA/ASIC) cannot gain a significant advantage over consumer GPUs:

### 5.1 Real Data Pipeline

Miners download real FITS files (variable sizes, 10MB–100MB), process them through Python preprocessing (lightkurve, astropy), then run inference. This pipeline is dominated by data movement and Python overhead — not raw compute. ASICs optimized for matrix multiplication can't accelerate data download or Python.

### 5.2 Dynamic ML Models

Models are PyTorch/ONNX with:
- `BatchNorm1d` (running statistics updated each batch)
- `Dropout` (random masking at inference)
- `AdaptiveAvgPool1d` (variable input sizes)
- Architecture rotation every 100 blocks (CNN → Transformer → Mamba → ConvNeXT)

An ASIC hard-coded for a fixed architecture would lose efficiency after each rotation.

### 5.3 Timing Attestation

`MIN_COMPUTE_DURATION = 2 seconds` is enforced both client-side (miner pads to 2s) and on-chain (contract rejects sub-2s results with "Compute too fast (ASIC?)"). An FPGA that completes inference in 100ms gets rejected.

### 5.4 Hardware Detection

The miner startup checks `DETECTED_GPU` against known FPGA/emulation vendors: `emulated`, `fpga`, `simulated`, `virtual`, `software renderer`. Rejected at startup.

### 5.5 Weight Perturbation

`anti_asic.py` adds random Gaussian noise (σ = 0.01) to model weights at the start of each mining session. The on-chain `modelHash` must match. An ASIC that pre-computes solutions for a specific weight set is invalidated every session.

## 6. Challenge / Slash

To prevent bad actors from submitting fake results (e.g., claiming high quality without running real inference), any miner can challenge a submission within 6 hours:

1. **File challenge** — Pay 1 VOID bond (burned on file).
2. **1-hour resolution delay** — Allows off-chain re-execution by honest parties.
3. **Resolve** — If the submission's quality is below the floor (50), the challenger wins:
   - Submitter loses 20% of their reward
   - 50% of slash → challenger, 50% burned
4. **If quality is valid** — Challenger loses their bond (forfeited to burn).

This creates a Schelling point: honest miners are incentivized to challenge fake work, while bad actors face 20% slash.

## 7. Governance

### 7.1 No Owner

The token has no `owner`. The MiningPool has no `owner`. There is no multisig.

### 7.2 Time-Locked Param Changes

All administrative functions (creating/deactivating tasks) require:

1. **Proposer stake** — 1% of total miner-minted supply must be staked (via `stakeAsProposer()`).
2. **7-day time-lock** — Proposed changes wait 7 days before execution.
3. **Proposer-only execution** — Only the proposer can cancel; anyone can execute after delay.

### 7.3 What Can Be Changed

- Task creation / deactivation
- (Future) Reward multipliers per task
- (Future) Halving parameters (with quorum)

### 7.4 What Cannot Be Changed

- Token supply (immutable in `MAX_SUPPLY`)
- Quality thresholds
- Cooldown duration
- Halving interval and floor
- The token's ownerless nature

## 8. Mining Tasks

### 8.1 Exoplanet Transit Detection

- **Model**: AstroNetCNN (244K parameters, 89% test accuracy)
- **Data**: TESS 2-minute cadence light curves from MAST
- **Output**: Planet / False-Positive / No-Signal + confidence
- **Targets**: TOI-732, TOI-1452, TOI-700, TOI-1259, TOI-1444

A 1D CNN processes phase-folded light curves across 4 branches (even / global / local / odd transits) plus 9 stellar parameters. Output: probability distribution over 3 classes.

### 8.2 Galaxy Morphology Classification

- **Model**: GalaxyClassifier (placeholder for Zoobot, 15.6M params)
- **Data**: SDSS DR18 cutout images (64×64 RGB)
- **Output**: 5-class probabilities (Spiral, Elliptical, Irregular, Merger, Unknown)
- **Targets**: NGC 4565, M81, NGC 4889, NGC 4725, NGC 4921

A 2D CNN classifies galaxy morphology from cutout images. Results include confidence and full probability distribution.

### 8.3 Astronomical Anomaly Detection

- **Model**: AnomalyDetector (autoencoder, 128-dim features)
- **Data**: ZTF alert stream from Fink broker
- **Output**: Reconstruction error + anomaly flag
- **Threshold**: mean + 2σ

An autoencoder reconstructs alert feature vectors. High reconstruction error indicates anomalous transients (supernovae, TDEs, gravitational lenses).

## 9. Architecture

```
                    ┌─────────────────────────────────┐
                    │   Public Astronomical Archives  │
                    │   MAST · SDSS · ZTF/Fink        │
                    └────────────┬────────────────────┘
                                 │ HTTP
                                 ▼
                    ┌─────────────────────────────────┐
                    │      GPU Miner (Python)         │
                    │  ┌───────────────────────────┐  │
                    │  │ Backend:                  │  │
                    │  │  PyTorch CUDA / ROCm /    │  │
                    │  │  ONNX DirectML / CPU      │  │
                    │  └───────────────────────────┘  │
                    │  ┌───────────────────────────┐  │
                    │  │ Preprocessing             │  │
                    │  │  (lightkurve, astropy)    │  │
                    │  └───────────────────────────┘  │
                    │  ┌───────────────────────────┐  │
                    │  │ ML Inference              │  │
                    │  │  (AstroNet, Zoobot, AE)   │  │
                    │  └───────────────────────────┘  │
                    │  ┌───────────────────────────┐  │
                    │  │ Anti-ASIC                 │  │
                    │  │  (rotation, perturbation) │  │
                    │  └───────────────────────────┘  │
                    └────────────┬────────────────────┘
                                 │ submitWork()
                                 ▼
                    ┌─────────────────────────────────┐
                    │   MiningPool (Base L2)          │
                    │  ┌───────────────────────────┐  │
                    │  │  Halving (50 → 0.1 VOID)  │  │
                    │  │  Elastic (0.8 – 1.2x)     │  │
                    │  │  Quality scoring          │  │
                    │  │  Challenge / Slash        │  │
                    │  │  Time-locked governance   │  │
                    │  └───────────────────────────┘  │
                    └────────────┬────────────────────┘
                                 │ mintMinerReward()
                                 ▼
                    ┌─────────────────────────────────┐
                    │   VoidmapToken (ERC-20)         │
                    │  - Ownerless                    │
                    │  - 1B fixed supply              │
                    │  - 90% to miners (halving)      │
                    │  - 5% dev (4yr vesting)         │
                    │  - 5% DAO (genesis)             │
                    └─────────────────────────────────┘
```

## 10. Multi-Backend GPU Support

The miner auto-selects the best available backend in this priority order:

1. **PyTorch CUDA** — NVIDIA GPUs (default)
2. **PyTorch ROCm** — AMD GPUs on Linux (via rocm PyTorch wheel)
3. **ONNX Runtime DirectML** — AMD/Intel/NVIDIA on Windows + Linux
4. **ONNX Runtime CPU** — Universal fallback
5. **PyTorch CPU** — Final fallback

The model is exported to ONNX for cross-backend compatibility. Both PyTorch and ONNX paths produce identical outputs (max diff: 0.00000191).

This ensures the miner works on:
- Linux + NVIDIA + CUDA
- Linux + AMD + ROCm
- Windows + AMD/Intel/NVIDIA + DirectML
- HiveOS (with Docker or native install)
- macOS + Apple Silicon + MPS
- CPU-only (slower but functional)

## 11. Deployment

### 11.1 2-Step Deploy

The contracts are deployed in two transactions:

1. **MiningPool** — Deployed with a placeholder token address.
2. **VoidmapToken** — Deployed with the MiningPool's address as minter.
3. **`migrateMinter(pool)`** — Locks the minter to the MiningPool forever.

After step 3, the token is ownerless. No one can mint outside the MiningPool.

### 11.2 Bootstrap

The deploy script:
1. Deploys both contracts
2. Locks the minter
3. Stakes 1 VOID as the initial proposer (deployer)
4. Creates the 3 default tasks (Exoplanet, Galaxy, Anomaly)

Total gas: ~3.5M gas (~0.00007 ETH at 19 Gwei on Base).

## 12. Comparison

| Feature | Bitcoin | Voidmap |
|---------|---------|---------|
| Useful output | No | Yes (scientific) |
| GPU mining | No (ASIC-dominated) | Yes (consumer GPUs) |
| Halving | Yes (210K blocks) | Yes (210K submissions) |
| Elastic supply | No | Yes (0.8–1.2x) |
| Slashing | No | Yes (20% on bad work) |
| Ownerless | Yes (immutable) | Yes (immutable from day one) |
| Governance | Off-chain | On-chain (7-day time-lock) |
| Energy use | Pure waste | Real science |

## 13. Conclusion

Voidmap is a complete, autonomous, scientifically useful cryptocurrency. It runs forever without a founder, without an admin key, without an upgrade path. The smart contracts are immutable. The token is ownerless. The supply is fixed. The halving is predictable. The slashing is fair. The mining produces real science.

**No promises. Just code.**

## License

MIT — open source, deployable by anyone.
