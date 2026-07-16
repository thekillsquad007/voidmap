# Welcome to Voidmap

**Proof of Useful Work — GPU miners process real astronomical data**

Voidmap is a native L1 blockchain where GPU miners earn VOID by processing real astronomical data from NASA, ESA, and NSF surveys. Unlike traditional Proof of Work, Voidmap's computation produces scientifically useful results.

The protocol is **ownerless from day one** — no admin keys, no multisig, no upgrade path. Halving, elastic mint, and governance are all enforced by the native Rust consensus (φ-PoW).

---

## Quick Links

| Section | Description |
|---------|-------------|
| [Mainnet Features](mainnet-features.md) | Halving, elastic mint, challenge/slash, time-locked governance |
| [Mining Guide](mining.md) | How to set up and run a node |
| [AMD/ROCm Setup](rocm-setup.md) | AMD GPU + ROCm install guide |
| [Data Sources](data-sources.md) | Where the astronomical data comes from |
| [FAQ](faq.md) | Frequently asked questions |

---

## How It Works

1. **Miner downloads** real data from NASA MAST, SDSS, or ZTF
2. **GPU runs** a pre-trained ML model (transit detection, galaxy classification, anomaly detection)
3. **Results stored** as SubmitWork transactions on the Voidmap chain
4. **Quality scored** by actual model metrics (confidence, reconstruction error)
5. **VOID rewarded** based on quality × halving epoch × elastic multiplier
6. **φ-PoW consensus** validates blocks using Euler totient-based proof-of-work

---

## Architecture

Voidmap runs as a native L1 blockchain built from scratch in Rust:

- **5-crate workspace**: crypto, core, pow, network, node
- **φ-PoW consensus**: Euler totient-based proof-of-work (1024-bit candidates, trial factoring, Miller-Rabin)
- **TCP networking**: length-prefixed JSON protocol, persistent gossip, chain sync
- **Heaviest chain selection**: forks retained, automatic reorgs

---

## Token Distribution

| Allocation | Percentage | Vesting |
|------------|------------|---------|
| GPU Miners | 90% (900M VOID) | Halving schedule (continuous) |
| Developer Fund | 5% (50M VOID) | Pre-allocated at genesis |
| Treasury/DAO | 5% (50M VOID) | Pre-allocated at genesis |

**No premine. No ICO. No team allocation. The dev mines their own coins.**

---

## Contributing

Voidmap is open-source. Issues, PRs, and feedback welcome on GitHub.

- **Code**: github.com/thekillsquad007/voidmap
- **Models**: Hugging Face (sarojpatil16/exoplanet-transit-detector, etc.)
- **Data**: NASA MAST, SDSS, ZTF (free public archives)

---

## License

MIT. The data is CC-BY-4.0. The science is open.
