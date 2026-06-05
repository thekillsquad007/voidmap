# Welcome to Voidmap

**Proof of Useful Work — GPU miners process real astronomical data**

Voidmap is an ERC-20 token on Base where GPU miners earn VOID by processing real astronomical data from NASA, ESA, and NSF surveys. Unlike traditional Proof of Work, Voidmap's computation produces scientifically useful results.

The protocol is **ownerless from day one** — no admin keys, no multisig, no upgrade path. Halving, elastic mint, challenge/slash, and time-locked governance are all enforced in immutable smart contracts.

---

## Quick Links

| Section | Description |
|---------|-------------|
| [Tokenomics](tokenomics.md) | Token supply, halving schedule, elastic mint, vesting |
| [Proof of Useful Work](pouw.md) | How mining works, quality scoring |
| [Mainnet Features](mainnet-features.md) | Halving, elastic mint, challenge/slash, time-locked governance |
| [Mining Guide](mining.md) | How to set up and run a miner (multi-backend, HiveOS) |
| [Pool Guide](pool.md) | How to join or run a mining pool |
| [Anti-ASIC](anti-asic.md) | 5 layers preventing ASIC/FPGA centralization |
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
5. **VOID rewarded** based on quality × halving epoch × elastic multiplier
6. **Other miners** can challenge any submission within 6 hours (slash if provably below quality floor)

---

## The Problem

Traditional PoW wastes energy on hash puzzles with zero useful output. Public astronomical archives hold petabytes of unprocessed data. Researchers lack GPU compute to process it.

## The Solution

Voidmap directs GPU mining power toward actual scientific computation. Miners process real data, produce real predictions, and earn VOID for contributing to science.

---

## Mainnet Features

- **Halving** — Block reward halves every 210,000 submissions (Bitcoin-style). 50 VOID → 25 → 12.5 → ... → 0.1 VOID floor.
- **Elastic Mint** — Reward scaled by rolling 10-submission average quality (0.8x–1.2x). Network self-balances toward quality 75.
- **Challenge/Slash** — Any miner can challenge a submission within 6 hours. If quality < 50, submitter loses 20% of reward.
- **Time-Lock Governance** — Parameter changes require 1% proposer stake + 7-day delay.
- **Ownerless** — No `Ownable`, no multisig, no upgrade path. Both contracts immutable from day one.
- **Multi-Backend GPU** — PyTorch CUDA, PyTorch ROCm, ONNX DirectML, ONNX CPU, PyTorch CPU. NVIDIA, AMD, Intel, Apple all supported.
- **HiveOS Ready** — One-command Docker install, plus native installer with auto GPU detection.
- **Anti-ASIC** — 5 layers: real data pipeline, dynamic ML models, 2s compute attestation, hardware detection, architecture rotation.

See [Mainnet Features](mainnet-features.md) for full details.

---

## Start Mining

```bash
# Install dependencies
pip install -r miner/requirements.txt

# Detect your GPU
python miner/voidmap-miner.py --detect

# Mine with real TESS data
python miner/voidmap-miner.py --task exoplanet --rounds 10

# Submit directly to Base mainnet
python miner/voidmap-miner.py --task exoplanet --submit \
  --rpc https://mainnet.base.org --pk 0xYOUR_PRIVATE_KEY

# Or connect to a pool
python miner/stratum_miner.py --pool ws://pool.voidmap.org:3333 --user YOUR_ADDRESS
```

For HiveOS, see the [Mining Guide](mining.md#hiveos--docker-deployment).

---

## Token Distribution

| Allocation | Percentage | Vesting |
|------------|------------|---------|
| GPU Miners | 90% (900M VOID) | Halving schedule (continuous) |
| Developer Fund | 5% (50M VOID) | 4 years linear |
| Treasury/DAO | 5% (50M VOID) | None (unlocked at genesis) |

**No premine. No ICO. No team allocation. The dev mines their own coins.**

---

## Contract Addresses

After deployment, add your contract addresses here:

| Contract | Address | Chain |
|----------|---------|-------|
| VoidmapToken (ERC-20) | `0x...` | Base (mainnet) |
| MiningPool | `0x...` | Base (mainnet) |
| VoidmapToken (testnet) | `0x...` | Base Sepolia |
| MiningPool (testnet) | `0x...` | Base Sepolia |

The on-chain state after mainnet launch is fully ownerless: no `Ownable`, no multisig, no upgrade path, no team tokens. The full source is in `contracts/`; forge tests cover every protocol invariant.

---

## Contributing

Voidmap is open-source. Issues, PRs, and feedback welcome on GitHub.

- **Code**: github.com/thekillsquad007/voidmap
- **Models**: Hugging Face (sarojpatil16/exoplanet-transit-detector, etc.)
- **Data**: NASA MAST, SDSS, ZTF (free public archives)
- **Results**: IPFS + on-chain Result Registry (in development)

---

## License

MIT. The data is CC-BY-4.0. The science is open.
