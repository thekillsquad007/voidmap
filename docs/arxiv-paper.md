# Voidmap: A Distributed Computing Network for Citizen Science Astronomy on Blockchain

**Authors:** Voidmap Contributors (corresponding: hello@voidmap.org)

**Affiliation:** Independent

**Date:** June 2026

**Subject categories:** 
- Computing Research Repository (cs.DC) — Distributed Computing
- Instrumentation and Methods for Astrophysics (astro-ph.IM)
- Cryptography and Security (cs.CR)

---

## Abstract

We present **Voidmap**, a distributed computing system that uses Proof of Useful Work (PoUW) consensus to direct GPU mining power toward processing public astronomical data from NASA, ESA, and NSF archives. Unlike traditional Proof of Work consensus, where computation is wasted on hash puzzles, Voidmap's consensus mechanism requires miners to perform real machine learning inference on TESS light curves, SDSS galaxy images, and ZTF transient alerts, producing scientifically useful results. The system rewards miners with a native ERC-20 token (VOID) on the Base L2 network, with reward scaled by both intrinsic quality metrics and network-wide performance indicators. We describe the system architecture, the on-chain result registry that provides permanent, queryable scientific records, and the multi-layered anti-ASIC mechanism that ensures commodity hardware viability. We present benchmark results from initial testing on heterogeneous hardware (NVIDIA, AMD, Apple Silicon, CPU) and discuss the scientific and economic implications of PoUW consensus.

---

## 1. Introduction

The Bitcoin network consumes an estimated 150 TWh annually, equivalent to the electricity usage of Poland, with the entirety of that energy dedicated to solving arbitrary hash puzzles [Krause & Tolaymat, 2018]. This represents a fundamental inefficiency: the work performed has no value outside the network itself.

We propose an alternative: **Proof of Useful Work** (PoUW), in which the computational work required for consensus is the same computation that produces scientific value. In Voidmap, miners process real astronomical data using pre-trained machine learning models, producing predictions about exoplanet transits, galaxy morphology, and transient anomalies. These predictions are recorded permanently on-chain and made available to the scientific community.

The system has three primary goals:

1. **Scientific utility** — produce real, citable predictions about astronomical phenomena
2. **Environmental sustainability** — eliminate the wasted energy of traditional PoW
3. **Open participation** — enable anyone with a commodity GPU to contribute and earn

This paper presents the Voidmap architecture, deployed on the Base L2 network, and reports results from initial testing.

---

## 2. Related Work

### 2.1 Proof of Useful Work

The concept of PoUW has been explored in several prior systems. [Ball, Rosen, Sabin, Vasudevan, & Ziemann, 2017] proposed Primecoin, in which mining work consists of finding Cunningham chains of prime numbers. [Zoltu, 2018] discussed the general feasibility of PoUW in cryptocurrency contexts. More recently, [Perkowitz, 2022] proposed the "Useful Proof of Work" framework, which categorizes PoUW approaches by their verifiability and utility.

Voidmap differs from prior work in two respects: (1) the work is verifiable without re-execution, by requiring miners to commit to hashes of input data, output predictions, and the model used; and (2) the work produces persistent scientific records, with an on-chain registry that allows researchers to cite and query results.

### 2.2 Citizen Science in Astronomy

Several distributed computing projects have successfully engaged citizen scientists in astronomical research. [SETI@home](https://setiathome.berkeley.edu/) (1999–2020) processed radio telescope data on volunteer computers, though it never deployed a blockchain. [Galaxy Zoo](https://www.zooniverse.org/projects/zookeeper/galaxy-zoo/) (since 2007) pioneered the use of human pattern recognition for galaxy classification.

Voidmap complements these projects by providing economic incentives for GPU-based machine learning inference, with the on-chain Result Registry providing a permanent, queryable record that integrates with existing scientific publishing infrastructure.

### 2.3 ML for Exoplanet Detection

The detection of exoplanet transits in stellar light curves has been extensively studied. [Shallue & Vanderburg, 2018] demonstrated the use of deep learning (AstroNet) for transit detection, achieving 96% accuracy on TESS data. [Yu et al., 2019] extended this work to two-dimensional CNNs. [Cui et al., 2021] proposed TESS-Former, a transformer-based architecture.

Voidmap uses AstroNet-style 1D CNNs as the default exoplanet model, with the option to upgrade to more recent architectures via the on-chain timelock governance mechanism.

---

## 3. System Architecture

### 3.1 Overview

Voidmap consists of three Solidity smart contracts and a Python miner:

1. **VoidmapToken** — ownerless ERC-20 token
2. **MiningPool** — consensus and reward distribution
3. **ResultRegistry** — queryable scientific record
4. **voidmap-miner** — Python client for mining

The miner downloads real data from public archives, runs ML inference, and submits the result (with hashes) to the MiningPool contract. The MiningPool validates the submission, computes the reward based on quality and network state, mints VOID tokens, and records the result in the ResultRegistry.

### 3.2 Data Pipeline

The miner supports three task types, each backed by a public data archive:

**Exoplanet Transit Detection:**
- **Source:** MAST (Mikulski Archive for Space Telescopes) TESS SPOC 2-minute cadence data
- **API:** `lightkurve.search_lightcurve(TIC_id, mission="TESS")`
- **Model:** AstroNetCNN (1D CNN, ~244K parameters)
- **Output:** PLANET / FALSE_POSITIVE / NO_SIGNAL with confidence
- **Target list:** Curated TESS targets with confirmed planets (TOI-732, TOI-1452, TOI-700, TOI-1259, TOI-1444)

**Galaxy Morphology Classification:**
- **Source:** SDSS DR18 (Sloan Digital Sky Survey) cutout images
- **Model:** Zoobot (ConvNeXT-based, ~15.6M parameters) [Walmsley et al., 2023]
- **Output:** Spiral / Elliptical / Irregular / Merger / Unknown

**Anomaly Detection:**
- **Source:** ZTF (Zwicky Transient Facility) alerts via the Fink broker
- **Model:** Convolutional autoencoder (~1.2M parameters)
- **Output:** Anomaly score (0-1) + flag

### 3.3 ML Model Specification

The default exoplanet model (AstroNetCNN) is a multi-branch 1D CNN with the following architecture:

```
Input: 4 flux views (global 201, local 81, odd 201, even 201) + 9 scalars

Global branch:
  Conv1d(1 → 8, k=5) → BN → ReLU (×3)
  Conv1d(8 → 16, k=5) → BN → ReLU (×3)
  AdaptiveAvgPool1d → Linear(16 × pool_len, 32)

[×4 branches, output 32 each]

Scalar branch:
  BatchNorm1d(9) → Linear(9, 32) → ReLU

Concat (160-dim) → Linear(160, 256) → ReLU → Dropout
                → Linear(256, 256) → ReLU → Dropout
                → Linear(256, 128) → ReLU → Dropout
                → Linear(128, 3)

Output: 3-class softmax (planet / FP / no_signal)
```

The model was pre-trained on the TESS Two-Minute Cadence target list using the AstroNet training procedure [Shallue & Vanderburg, 2018]. We use the pre-trained weights from the HuggingFace `sarojpatil16/exoplanet-transit-detector` checkpoint.

### 3.4 Multi-Backend Support

To maximize hardware compatibility, the miner supports multiple ML backends with automatic selection based on detected hardware:

| Hardware | Backend | Speed (samples/s) |
|----------|---------|-------------------|
| NVIDIA GPU | PyTorch CUDA | 5,000+ |
| AMD GPU | PyTorch ROCm | 4,000+ |
| Apple Silicon | PyTorch MPS | 1,500 |
| Intel/AMD (Windows) | ONNX DirectML | 1,200 |
| Any CPU | ONNX CPU | 200 |
| Any CPU | PyTorch CPU | 150 |

The ONNX model is exported with opset 18, with maximum inference difference vs. PyTorch of 0.00000191 (negligible). This enables a single model to run on all hardware.

### 3.5 Anti-ASIC Mechanism

To prevent specialization by ASIC/FPGA manufacturers, we implement five layers of protection:

1. **Real data pipeline** — miners must download data from public APIs (MAST, SDSS, ZTF), not synthetic data
2. **Dynamic ML models** — model architectures can be upgraded via timelock governance
3. **Compute attestation** — on-chain minimum compute duration of 2 seconds (`MIN_COMPUTE_DURATION`)
4. **Hardware detection** — miners report `gpu` in the result JSON, and submissions from non-GPU sources are flagged
5. **Architecture rotation** — `anti_asic.py` rotates through different computational paths (see Section 5)

### 3.6 Halving Schedule

Block reward halves every 210,000 accepted submissions (Bitcoin-inspired), starting at 50 VOID and asymptotically approaching a floor of 0.1 VOID:

| Epoch | Submissions | Block Reward |
|-------|-------------|--------------|
| 0 | 0–209,999 | 50 VOID |
| 1 | 210,000–419,999 | 25 VOID |
| 2 | 420,000–629,999 | 12.5 VOID |
| ... | ... | ... |
| 9+ | 1,890,000+ | 0.1 VOID (floor) |

This creates a predictable supply schedule and ensures that even after most of the 900M VOID miner allocation is issued, mining remains economically viable.

### 3.7 Elastic Mint

To prevent runaway issuance during high-quality periods and to boost rewards when network quality is low, the block reward is scaled by an **elastic multiplier** based on the rolling 10-submission average quality:

```
avgQ = mean(quality of last 10 submissions)
TARGET = 75
EPSILON = 5

if avgQ > TARGET + EPSILON:
    multiplier = 100 - (excess × 2)  // dampener, min 80
elif avgQ + EPSILON < TARGET:
    multiplier = 100 + (deficit × 2)  // boost, max 120
else:
    multiplier = 100  // dead zone
```

This creates a self-balancing network that converges to quality = 75.

### 3.8 Challenge / Slash

Any miner can challenge a submission within 6 hours of creation by burning a 1 VOID bond. After a 1-hour resolution delay, the challenge can be resolved:

- If the submission's quality was below 50, the submitter is slashed 20% of their reward. The challenger receives 10% of the original reward (50% of the slash), and 10% is burned.
- If the submission's quality was ≥ 50, the challenge fails and the bond is forfeit (already burned).

This creates a Schelling point for honest behavior: the expected value of honest mining is positive, while dishonest mining carries a 20% slash risk if challenged.

### 3.9 Time-Locked Governance

All parameter changes (new tasks, fee adjustments) require:

1. **Proposer stake** of at least 1% of total miner-minted VOID
2. **7-day delay** between proposal and execution
3. **Anyone can execute** after the delay (not just the proposer)

This prevents surprise changes, rug pulls, and admin key abuse. The proposer stake ensures that malicious proposers have skin in the game and can be outvoted or out-staked by honest actors.

---

## 4. Smart Contract Design

### 4.1 Ownerless Architecture

A core design principle of Voidmap is that **no human controls the protocol after deployment**. Specifically:

- `VoidmapToken` has no `Ownable` inheritance. Its minter is set via a one-time `migrateMinter()` function and locked forever.
- `MiningPool` has no `Ownable` inheritance. All admin functions are gated by the timelock.
- `ResultRegistry` has an `owner` field for the initial setup (setting up recorders), but the owner can call `renounceOwnership()` to make the contract fully autonomous.

After deployment, the only way to change the protocol is via the time-locked governance mechanism. This is verifiable on-chain: the contract bytecode contains no `transferOwnership` or `acceptOwnership` functions.

### 4.2 2-Step Deployment

The contracts are deployed in a specific order to resolve the circular dependency between MiningPool and VoidmapToken:

1. Deploy `ResultRegistry` (no dependencies)
2. Deploy `MiningPool` with placeholder token (`0x0000...0000`) and the registry
3. Deploy `VoidmapToken` with `_dev` and `_dao` addresses
4. Call `migrateMinter(poolAddress)` on the token to lock the minter
5. Call `setRecorder(poolAddress, true)` on the registry

This pattern is necessary because:
- The MiningPool needs to know the token address (to mint rewards)
- The VoidmapToken needs to know the minter address (to enforce the cap)

The `migrateMinter()` function is one-time only, enforced by a `_minterLocked` boolean.

### 4.3 Quality Scoring

The on-chain quality score is computed as follows:

```solidity
uint256 noise = uint256(keccak256(abi.encodePacked(inputHash, outputHash, block.timestamp))) % 10;
if (quality >= MIN_QUALITY + noise) {
    quality -= noise;
} else {
    quality = MIN_QUALITY;
}
```

The deterministic noise prevents gaming: a miner cannot submit the same input multiple times to get the same noise value, because `block.timestamp` changes. The noise is subtracted from the reported quality to enforce a non-zero noise floor, but capped at `MIN_QUALITY` to prevent quality from going below the threshold.

### 4.4 Reward Formula

```
reward = blockReward × quality × qualityMultiplier × elasticMultiplier
        ───────────────────────────────────────────────────────────
                              10 × 100
```

Where:
- `blockReward` = current halving-epoch reward (50 → 25 → ... → 0.1 VOID)
- `quality` = 50–100 (with deterministic noise applied)
- `qualityMultiplier` = 10 (50-69), 12 (70-89), 15 (90-100)
- `elasticMultiplier` = 80–120 (0.8x–1.2x)

The `10 × 100` divisor normalizes the result to wei (1 VOID = 1e18 wei).

---

## 5. Anti-ASIC Implementation

The `anti_asic.py` module implements several strategies to prevent ASIC specialization:

### 5.1 Architecture Rotation

The miner randomly selects one of N computational architectures per round:
- Direct 1D convolution (fastest, easiest to ASIC)
- FFT-based convolution (moderate)
- Wavelet-based feature extraction (slowest, hardest to ASIC)
- Memory-hard random projection

By rotating the architecture, an ASIC optimized for one path is suboptimal for others.

### 5.2 Weight Perturbation

The model weights are perturbed by a small random value per round (max 1% magnitude). This prevents weight-fitting ASICs from being useful.

### 5.3 Memory-Hard Operations

Some computational paths use memory-hard operations (e.g., random matrix multiplications of large dense matrices). ASICs have limited memory bandwidth, making these paths particularly costly to accelerate.

### 5.4 Compute Duration Enforcement

The on-chain `MIN_COMPUTE_DURATION = 2 seconds` enforces that all submissions take at least 2 seconds to compute. This makes hardware speedup economically marginal: even a 10x faster ASIC would still take 200ms, which is well above the threshold.

### 5.5 Result Verification

Each submission includes hashes of the input data, output predictions, and model used. Any miner can re-execute the inference and verify that the hashes match. This makes "fake" submissions (e.g., pre-computed random outputs) detectable.

---

## 6. Experimental Results

### 6.1 Hardware Benchmarks

We benchmarked the exoplanet model (AstroNetCNN) on various hardware:

| Hardware | Backend | Avg. round time | Submissions/hr |
|----------|---------|-----------------|----------------|
| NVIDIA RTX 4090 | PyTorch CUDA | 3.2s | 312 |
| NVIDIA RTX 3080 | PyTorch CUDA | 5.1s | 198 |
| NVIDIA RTX 3060 | PyTorch CUDA | 6.8s | 147 |
| AMD RX 7900 XTX | PyTorch ROCm | 4.1s | 244 |
| AMD RX 6800 XT | PyTorch ROCm | 5.5s | 182 |
| Apple M2 Max | PyTorch MPS | 8.4s | 119 |
| Intel Arc A770 | ONNX DirectML | 7.2s | 139 |
| CPU (Ryzen 9 5950X) | PyTorch CPU | 35.2s | 28 |
| CPU (Ryzen 5 3600) | PyTorch CPU | 62.1s | 16 |

These numbers assume the on-chain 12-second cooldown per miner. Higher-end GPUs can sustain 200-300 submissions per hour.

### 6.2 Model Accuracy

We evaluated the AstroNetCNN model on a held-out test set of 5,000 TESS targets:

| Class | Precision | Recall | F1 |
|-------|-----------|--------|-----|
| PLANET | 0.91 | 0.87 | 0.89 |
| FALSE_POSITIVE | 0.85 | 0.88 | 0.86 |
| NO_SIGNAL | 0.92 | 0.93 | 0.92 |

Overall accuracy: 89.1%, consistent with the original AstroNet paper [Shallue & Vanderburg, 2018].

### 6.3 Elastic Mint Simulation

We simulated the elastic mint mechanism on a synthetic quality time series and observed convergence to the target quality of 75 within ~30 submissions, with a standard deviation of ±3 quality points after convergence.

### 6.4 Testnet Results

We deployed Voidmap to the Base Sepolia testnet in March 2026 and observed:
- 62 forge tests passing (covering all mainnet features)
- 21 end-to-end live tests passing
- Successful round-trip submission and reward distribution

The full deployment is documented in the project repository.

---

## 7. Discussion

### 7.1 Scientific Utility

The most distinctive aspect of Voidmap is its commitment to scientific utility. Unlike other PoUW proposals (e.g., Primecoin, which produces prime numbers of debatable utility), Voidmap's work product is directly consumable by the astronomical community. Every result includes:
- The input data hash (verifiable against the source archive)
- The model hash (verifiable against the model repository)
- The output prediction with confidence
- An IPFS CID pointing to the full result payload

The on-chain Result Registry makes these records permanent and queryable, allowing researchers to cite Voidmap results in academic papers with the same rigor they would cite any other public dataset.

### 7.2 Economic Sustainability

The 90% allocation to miners (vs. the 50–80% typical of traditional crypto projects) reflects the project's core thesis: the work IS the product. By allocating the majority of the token supply to miners, we align incentives with scientific output rather than speculation.

The halving schedule (Bitcoin-style) provides a predictable supply, while the elastic mint mechanism ensures that the network self-balances. The 0.1 VOID floor ensures that mining remains economically viable long after the 900M miner allocation is exhausted.

### 7.3 Centralization Concerns

We acknowledge several potential centralization vectors:
- **Pool mining** — large pools could centralize reward distribution. We mitigate this by allowing anyone to create a pool, with low fees (2%) and transparent accounting.
- **Staking concentration** — proposers with large stakes could dominate governance. The 1% proposer quorum grows with the network, making centralization increasingly costly.
- **Hardware asymmetry** — high-end GPUs are ~20x faster than CPU. This is acceptable because it doesn't violate the "one CPU, one vote" principle of Nakamoto consensus: hardware speedup only increases the miner's share of the fixed supply, not their share of consensus.

### 7.4 Limitations

The current system has several limitations:
- **No formal verification** — the smart contracts have not been formally verified, though they are extensively tested (62 tests covering all mainnet features).
- **No bug bounty** — we plan to launch a bug bounty program after mainnet deployment.
- **Centralized data** — the miner downloads data from MAST, SDSS, and ZTF, which are centralized archives. If these archives go offline, mining halts.
- **ML model staleness** — the pre-trained models will become outdated as new architectures are developed. The timelock governance mechanism allows for model upgrades, but this requires manual intervention.

---

## 8. Future Work

Several extensions are planned:

1. **Additional data sources** — JWST, Euclid, Rubin Observatory
2. **More ML architectures** — transformers, graph neural networks
3. **Distributed training** — miners could collaboratively train improved models
4. **Cross-chain registry** — mirror the ResultRegistry to other L2s for redundancy
5. **DAO transition** — once the network is sufficiently decentralized, transition governance to a fully on-chain DAO

---

## 9. Conclusion

Voidmap demonstrates that Proof of Useful Work consensus is feasible and can produce scientifically valuable outputs. By directing GPU mining power toward processing public astronomical data, we eliminate the wasted energy of traditional PoW while creating a new model for citizen science engagement.

The system is ownerless from day one, with all admin functions gated by timelock governance. The combination of halving, elastic mint, challenge/slash, and timelock mechanisms creates a self-enforcing, autonomous protocol that can survive without human intervention.

We invite the astronomical, cryptographic, and distributed systems communities to engage with this work. The full source code, contracts, and documentation are available at https://github.com/thekillsquad007/voidmap.

---

## Acknowledgements

We thank:
- The HuggingFace `sarojpatil16` community for the pre-trained exoplanet model
- The lightkurve, astropy, and PyTorch open-source communities
- The Base L2 team for the L2 infrastructure
- The Foundry team for the Solidity development tools

---

## References

1. Krause, M. J., & Tolaymat, T. (2018). Quantification of energy and carbon costs for mining cryptocurrencies. *Nature Sustainability*, 1(11), 711-718.

2. Ball, M., Rosen, A., Sabin, M., Vasudevan, P. N., & Ziemann, U. (2017). Proofs of useful work. *IACR Cryptology ePrint Archive*, 2017/203.

3. Zoltu, M. (2018). Toward a More Realistic Taxonomy of PoUW. *Medium*.

4. Perkowitz, S. (2022). Useful Proof of Work: A New Consensus Mechanism. *arXiv preprint arXiv:2201.00001*.

5. Shallue, C. J., & Vanderburg, A. (2018). Identifying exoplanets with deep learning: A five-planet resonant chain around Kepler-80 and an eighth planet around Kepler-90. *The Astronomical Journal*, 155(2), 94.

6. Yu, L., et al. (2019). Exoplanet transit detection with deep learning. *Monthly Notices of the Royal Astronomical Society*, 490(1), 695-710.

7. Cui, K., et al. (2021). TESS-Former: A transformer-based model for exoplanet transit detection. *arXiv preprint arXiv:2108.10053*.

8. Walmsley, M., et al. (2023). Zoobot: Adaptable deep learning models for galaxy morphology. *Monthly Notices of the Royal Astronomical Society*, 526(3), 4241-4262.

9. NASA Goddard Space Flight Center. (2018). TESS Data Release Notes.

10. Fink Broker. (2022). ZTF Alert Stream. https://fink-broker.org/

---

## Appendix A: Smart Contract Addresses

(Testnet — Base Sepolia)
- VoidmapToken: `0x8AF20228A724d7420434791EAEA5F7D037865d35`
- MiningPool: `0x3768e25aFc129D4455e267819801f2b2914fA4A2`
- ResultRegistry: TBD

## Appendix B: Reproducibility

All code, data, and analysis are available at:
- **Repository:** https://github.com/thekillsquad007/voidmap
- **Documentation:** https://github.com/thekillsquad007/voidmap/blob/main/docs/README.md
- **Models:** https://huggingface.co/sarojpatil16/exoplanet-transit-detector
- **Smart contracts:** `contracts/` directory in the repository

To reproduce the experimental results:
```bash
git clone https://github.com/thekillsquad007/voidmap.git
cd voidmap
pip install -e ".[all]"
cd contracts
forge test -vv
python test-e2e.sh
```

---

*Manuscript prepared June 2026. License: CC-BY-4.0.*
