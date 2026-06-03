# Voidmap Whitepaper

## Proof of Useful Work: Mining the Universe

### Abstract

Voidmap introduces a hybrid Proof of Useful Work (PoUW) token where GPU mining
is directed toward astronomical analysis. Unlike PoW (energy waste) or PoS
(wealth concentration), Voidmap creates value from the mining process itself.

### How It Works

1. GPU miners download astronomical analysis tasks (voted by token holders)
2. GPUs process real scientific data (TESS, JWST, Hubble, ZTF)
3. Results are submitted with a proof of computation
4. Network verifies via spot-checking and cross-validation
5. Valid results earn VOID tokens proportional to data quality
6. Data is listed on the marketplace for researchers
7. Marketplace fees buy back & burn → sustainable value loop

### GPU Backend Support

| Backend | GPUs | Platform |
|---------|------|----------|
| CUDA | NVIDIA | Linux, Windows |
| ROCm | AMD RX/Pro/Instinct | Linux |
| MPS | Apple Silicon | macOS |
| OpenCL | AMD, Intel, NVIDIA | Linux, Windows, macOS |
| CPU Fallback | Any | Any |

### Tokenomics

| Metric | Value |
|--------|-------|
| Ticker | VOID |
| Max Supply | 1,000,000,000 |
| Dev Fund | 12% (4-yr vesting, 6-mo cliff) |
| Dev Fund Control | 3-of-5 multisig |

### Allocation

- **40%** GPU Mining Rewards (10-year emission schedule)
- **15%** Ecosystem DAO (community grants)
- **12%** Developer Fund (vested transparently)
- **10%** Public Sale
- **10%** Strategic Partners
- **8%** Liquidity Pool
- **5%** Community Airdrop

### Founder Transparency

The dev fund uses a 3-of-5 multisig wallet with published addresses. All
transactions are publicly visible on-chain. After the 4-year vesting period,
continued funding requires DAO approval.

### Smart Contracts

- **VoidmapToken.sol** — ERC-20 with vesting; ownership renounceable
- **DataMarketplace.sol** — P2P data exchange with escrow & arbitration
- **MiningPool.sol** — GPU work verification & reward distribution

### Fee Structure

| Action | Fee | Destination |
|--------|-----|-------------|
| Data Purchase | 1% | Treasury (buyback & burn) |

### No Roadmap. No Promises.

Voidmap exists as code, not promises. There is no company, no CEO, no
locked-in roadmap. The community runs the nodes, votes on tasks, and
decides the future through the DAO.
