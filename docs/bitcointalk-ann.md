# Voidmap — Bitcointalk ANN

**Category:** Altcoins | **Launch:** June 2026 | **Ticker:** VOID

---

## [ANN] Voidmap — Proof of Useful Work. Mine exoplanets with your GPU.

Hello everyone,

I'm announcing **Voidmap** — a cryptocurrency where miners do *real science* with their GPUs. Every mining round processes real astronomical data from NASA, ESA, and NSF archives, producing predictions that are permanently recorded on-chain and made available to researchers.

### What is it?

Voidmap uses a consensus mechanism called **Proof of Useful Work**. Instead of burning electricity on hash puzzles, miners run pre-trained machine learning models on real data:

- **Exoplanet transit detection** on TESS light curves (NASA)
- **Galaxy morphology classification** on SDSS images (NSF)
- **Anomaly detection** on ZTF alerts (NSF)

Every accepted result is recorded on-chain in a permanent **Result Registry** that researchers can query and cite in academic papers. The work is verifiable: each submission includes hashes of input data, output predictions, and the model used.

### Why does this matter?

Traditional Proof of Work wastes energy. Bitcoin alone consumes ~150 TWh per year. Meanwhile, public astronomical archives hold petabytes of unprocessed data that researchers lack GPU compute to analyze.

Voidmap redirects that GPU power toward actual science. **Your computer discovers exoplanets while you sleep.**

### Tokenomics

- **Symbol:** VOID
- **Total supply:** 1,000,000,000 (fixed, immutable)
- **Distribution:**
  - 90% (900M) to GPU miners
  - 5% (50M) to developer fund (4-year vesting)
  - 5% (50M) to treasury
- **Halving:** Every 210,000 accepted submissions, the block reward halves (Bitcoin-style)
  - Epoch 0: 50 VOID
  - Epoch 1: 25 VOID
  - Epoch 2: 12.5 VOID
  - ... floor at 0.1 VOID

### Mainnet features (not your average token)

- **Ownerless from day one.** No `Ownable`, no multisig, no upgrade path. Both contracts are immutable.
- **Halving** every 210K submissions.
- **Elastic mint** — reward scales with network quality (0.8x-1.2x). Self-balances toward quality 75.
- **Challenge/slash** — any miner can challenge a submission within 6 hours. Bad actors lose 20% of their reward.
- **Time-locked governance** — parameter changes require 1% proposer stake + 7-day delay.
- **Result Registry** — permanent, queryable record of all mining results for scientific citation.

### How to mine

```bash
# Install
pip install voidmap
pip install voidmap[all]  # with PyTorch + lightkurve + ONNX

# Detect your GPU
voidmap-detect

# Mine (full TUI dashboard)
voidmap

# Or non-TUI
voidmap-mine --task exoplanet --rounds 10

# Submit on-chain to Base mainnet
voidmap-mine --task exoplanet --submit \
  --rpc https://mainnet.base.org --pk YOUR_PRIVATE_KEY
```

### Hardware support

- **NVIDIA** (CUDA, fastest)
- **AMD** (ROCm)
- **Apple Silicon** (MPS)
- **Intel/AMD** on Windows (DirectML via ONNX)
- **CPU** (always works, slowest)

HiveOS support via Docker image.

### Why should you care?

1. **Earn passive income** while contributing to science
2. **No premine, no ICO, no team allocation** — the dev mines their own coins
3. **Citable contributions** — your mining results can be cited in academic papers
4. **Truly ownerless** — no rug pull possible, the code is the team
5. **Multi-GPU, multi-platform** — works on whatever hardware you have

### The team

Just me. One person. No VC, no foundation, no company. I built this because I think the wasted energy of traditional crypto is a tragedy, and public scientific archives are an obvious place to direct that compute.

### Links

- **Website:** https://voidmap.org
- **GitHub:** https://github.com/thekillsquad007/voidmap
- **Twitter:** https://twitter.com/voidmap
- **Discord:** None (intentional — see FAQ)
- **Explorer:** https://explorer.voidmap.org
- **Whitepaper:** https://github.com/thekillsquad007/voidmap/blob/main/docs/whitepaper.md
- **arXiv paper:** https://github.com/thekillsquad007/voidmap/blob/main/docs/arxiv-paper.md

### Contracts (Base mainnet, post-deploy)

Will be added here after launch. Testnet is currently live on Base Sepolia.

### Roadmap

- ✅ Testnet deployment (Base Sepolia, March 2026)
- ✅ Mainnet contract features (halving, elastic, challenge, timelock)
- ✅ Result Registry (queryable scientific record)
- ✅ Multi-backend GPU support
- ✅ HiveOS Docker image
- ⏳ Mainnet launch (Q3 2026)
- ⏳ arXiv methods paper submission
- ⏳ Bug bounty program

### FAQ

**Why no Discord/Telegram?**
I want this to be open, transparent, and based on public code, not private chat. Bitcointalk and Twitter are public; Discord and Telegram are not. If you want to talk to me, Bitcointalk is the right place.

**Why Base L2?**
Cheap transactions, Ethereum security, easy onboarding. I considered building my own L1 but it would have taken years and added risk.

**Why no premine?**
I believe in fair launches. The 5% dev allocation is from emissions, not premined, and vests over 4 years. If I wanted to get rich, I'd just take 20% like everyone else. I want to build a useful network.

**Is the dev allocation a "team" allocation?**
No. It's a single dev (me). There is no team. The code is the team. If I die, the network continues.

**What if you rug?**
I can't. The contracts are ownerless. I have no admin keys. The timelock requires 1% proposer stake + 7-day delay, which I cannot bypass. The code is open source and verified on BaseScan.

---

I'll be hanging out in this thread for questions. Let me know what you think.

— Voidmap

---

*License: MIT. Data: CC-BY-4.0. Science: open.*
