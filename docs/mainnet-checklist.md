# Mainnet Launch Checklist

This is the deployment checklist for Voidmap mainnet on Base L2. **Do not deploy until all items are checked.**

---

## Pre-Launch (Code)

- [x] `VoidmapToken` ownerless from day one (no `Ownable`, no `renounce()`)
- [x] `VoidmapToken` has `migrateMinter()` (one-time only, locked after first call)
- [x] `MiningPool` ownerless (no `Ownable`, all admin via timelock)
- [x] `MiningPool` has halving logic (210K interval, 50 → 0.1 VOID)
- [x] `MiningPool` has elastic mint (0.8x-1.2x, ±5 dead zone around 75)
- [x] `MiningPool` has challenge/slash (6h window, 1 VOID bond, 20% slash)
- [x] `MiningPool` has time-locked governance (7-day delay, 1% quorum)
- [x] `ResultRegistry` is autonomous (renounceable owner, recorder allowlist)
- [x] `MiningPool` calls `registry.recordResult()` after each submission
- [x] All 62 forge tests passing (counted: `function test_` = 62)
- [x] E2E live tests passing
- [x] Multi-backend GPU support (NVIDIA, AMD, Apple, Intel, CPU)
- [x] HiveOS Docker image
- [x] TUI miner with Rich dashboard
- [x] Discovery Card generator
- [x] Block explorer
- [x] Daily Twitter stats bot

## Pre-Launch (Documentation)

- [x] Whitepaper
- [x] Tokenomics doc
- [x] Mainnet Features doc
- [x] Smart Contracts doc
- [x] Result Registry doc
- [x] Mining Guide
- [x] ROCm Setup Guide
- [x] arXiv methods paper
- [x] Bitcointalk ANN
- [x] Twitter launch thread
- [x] Daily stats bot README
- [x] All docs in `docs/SUMMARY.md`

## Pre-Launch (Operational)

- [ ] Wallet funded with > 0.005 ETH on Base mainnet (~$15 at current prices)
- [ ] Deployer key available (hardware wallet via frame/ledger recommended)
- [ ] `DEV_ADDR` decided (recommend multisig for 4-year vesting)
- [ ] `DAO_ADDR` decided (recommend Safe multisig for treasury)
- [ ] Twitter @voidmap account created
- [ ] Bitcointalk account ready (post ANN after deploy)
- [ ] arXiv submission ready (post-Saturday)
- [ ] Website live at voidmap.org
- [ ] Block explorer live at explorer.voidmap.org
- [ ] Twitter API credentials ready for daily bot

## Pre-Launch (Security)

- [ ] Smart contracts audited (or at minimum reviewed by 2+ experienced Solidity devs)
- [ ] Bug bounty program announced (immunefi or code4rena)
- [ ] `forge verify-contract` tested on BaseScan
- [ ] Deploy script tested on testnet (Base Sepolia)
- [ ] No leftover `console.log` or test code in contracts
- [ ] Compiler optimization enabled (200 runs)
- [ ] Solidity 0.8.27+ (latest stable)
- [ ] OpenZeppelin ReentrancyGuard used where needed
- [ ] All custom errors (no string reverts in mainnet)
- [ ] All numeric types checked for overflow
- [ ] All external calls checked (try/catch where needed)

## Pre-Launch (Community)

- [ ] Twitter followers: 0 (organic growth)
- [ ] Bitcointalk ANN scheduled
- [ ] GitHub repo public
- [ ] Discord/Telegram: NONE (intentional)
- [ ] Bug bounty live
- [ ] Public Telegram/Discord for security only (via multisig, not chat)

## Deploy Steps (when ready)

### 1. Final test on testnet (Base Sepolia)

```bash
cd contracts
forge test -vv
# Verify all addresses
# Verify token symbol = VOID
# Verify minter = pool
# Verify 3 tasks created
# Verify result registry recording
```

### 2. Deploy to mainnet (Base)

```bash
# See private operational runbook (not in this repo).
# After deploy, save addresses to docs/contracts.md
# Save addresses to README.md
# Save addresses to web/index.html
```

### 3. Verify on BaseScan

```bash
# Token
forge verify-contract $TOKEN_ADDR src/VoidmapToken.sol:VoidmapToken \
  --verifier blockscout --verifier-url https://api.basescan.org/api

# Pool
forge verify-contract $POOL_ADDR src/MiningPool.sol:MiningPool \
  --verifier blockscout --verifier-url https://api.basescan.org/api

# Registry
forge verify-contract $REGISTRY_ADDR src/ResultRegistry.sol:ResultRegistry \
  --verifier blockscout --verifier-url https://api.basescan.org/api
```

### 4. Publish

In order:

1. **GitHub:** Push all code, update README with mainnet addresses
2. **Website:** Update voidmap.org with mainnet addresses
3. **Block Explorer:** Update explorer.voidmap.org with mainnet addresses
4. **Bitcointalk:** Post the ANN thread (see `docs/bitcointalk-ann.md`)
5. **Twitter:** Post the launch thread (see `docs/twitter-thread.md`)
6. **arXiv:** Submit the methods paper (see `docs/arxiv-paper.md`)
7. **Daily bot:** Enable systemd timer for daily stats

### 5. Wait

- 24h: monitor for any issues, check Twitter for feedback
- 1 week: first halving epoch statistics, first challenge/slash events
- 1 month: first arXiv citations (maybe!)
- 3 months: first major protocol upgrade (if needed, via timelock)

---

## Mainnet Parameters (Final)

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Initial Block Reward | 50 VOID | Bitcoin-style, well-understood |
| Halving Interval | 210,000 submissions | Bitcoin-style, ~7-30 days depending on throughput |
| Floor Reward | 0.1 VOID | Ensures mining always viable |
| Quality Floor | 50 | Rejects noise, low-effort work |
| Quality Multiplier | 10 / 12 / 15 | Base / good / excellent |
| Elastic Range | 0.8x – 1.2x | Self-balancing |
| Elastic Window | 10 submissions | Smooth, not too jittery |
| Elastic Target | 75 | Reachable, encourages quality |
| Elastic Epsilon | 5 | Dead zone prevents oscillation |
| Submission Cooldown | 12s | Spam prevention |
| Min Compute | 2s | Anti-ASIC |
| Challenge Window | 6h | Long enough to detect fraud |
| Challenge Bond | 1 VOID | Cost of false challenges |
| Resolution Delay | 1h | Time for submitter to defend |
| Slash BPS | 20% | Significant but not catastrophic |
| Burn BPS | 50% of slash | Deflationary pressure |
| Timelock Delay | 7 days | Plenty of warning for changes |
| Proposer Quorum | 1% of miner-minted | Sybil-resistant |
| Dev Vesting | 4 years | Standard, fair |
| Dev Share | 5% | Lower than typical |
| Treasury Share | 5% | Standard |
| Miner Share | 90% | Higher than typical |
| Total Supply | 1,000,000,000 VOID | Fixed, no inflation |

---

## Post-Mainnet (Days 1-30)

### Day 1
- [ ] Monitor Twitter for feedback
- [ ] Watch for first real submission
- [ ] Watch for first challenge/slash event
- [ ] Verify daily stats bot works
- [ ] Post "mainnet is live" tweet

### Day 2-7
- [ ] First halving-related discussion (if epoch transition)
- [ ] First elastic mint event (visible in stats)
- [ ] First IPFS upload from a miner
- [ ] First miner-to-miner challenge
- [ ] Monitor for any contract issues

### Day 8-30
- [ ] First cross-miner pool
- [ ] First external researcher cites a ResultRegistry entry
- [ ] First time-locked proposal (if any)
- [ ] First arXiv feedback

### Day 30+
- [ ] First major protocol upgrade vote (if needed)
- [ ] First millionth submission
- [ ] First halving epoch transition

---

## Risk Mitigations

| Risk | Mitigation |
|------|-----------|
| Smart contract bug | Audited code, bug bounty, ownerless architecture (no key theft risk) |
| Miner centralization | Pool fees capped at 2%, anyone can create pool |
| Governance attack | 1% quorum + 7-day timelock, proposer stake at risk |
| Halving too fast | 210K interval is conservative; could be 420K+ if needed |
| Inflation bug | `MAX_SUPPLY` constant in code, enforced in `mintMinerReward` |
| Front-running | Block builders could front-run submissions; mitigate with private mempools |
| Sybil attacks | Cooldown per address, bond for challenges, stake for proposals |
| Death of single dev | Code is open source, contracts immutable, anyone can fork |

---

## This is the final deploy checklist. The dev should review each item before broadcasting.
