# Frequently Asked Questions

## General

### What is Voidmap?

Voidmap is a cryptocurrency where GPU miners earn VOID tokens by processing real astronomical data from NASA, ESA, and NSF surveys. Unlike Bitcoin, the computation produces scientifically useful results.

### How is this different from Bitcoin?

| Aspect | Bitcoin | Voidmap |
|--------|---------|---------|
| Computation | SHA-256 hashing | ML inference |
| Output | Hash collisions | Scientific predictions |
| Usefulness | None | Exoplanet detection |
| Hardware | ASICs only | GPUs only |
| Centralization | High | Low |

### Is this Proof of Work?

Yes, but **Proof of Useful Work**. Instead of wasting energy on hash puzzles, miners process real astronomical data with real ML models.

### Who created Voidmap?

Voidmap is an open-source project. There is no company, no CEO, no central authority. The code is public on GitHub.

---

## Mining

### What GPU do I need?

Any modern GPU works:
- NVIDIA GTX 10xx or newer (CUDA)
- AMD RX 5000 or newer (ROCm)
- Apple M1/M2/M3 (MPS)
- Intel Arc (partial OpenCL support)

Minimum: 4GB VRAM. Recommended: 8GB+.

### How much can I earn?

Earnings depend on:
- GPU performance
- Quality of your results
- Network difficulty
- Current VOID price

Higher quality results earn more VOID (1.5x bonus for 90+ quality).

### Can I mine with an ASIC?

No. Voidmap uses anti-ASIC measures:
- Model architecture rotation
- Random batch sizes
- Weight perturbation
- Memory-hard operations

These force the use of general-purpose GPUs.

### Can I mine with an FPGA?

No. The same anti-ASIC measures apply:
- FPGAs can't handle architecture switching
- Memory requirements exceed typical FPGA capacity
- Dynamic challenges prevent pre-computation

### How do I check my results?

```bash
python voidmap-miner.py --list-results
```

Results are saved to `~/.voidmap/results/` as JSON files.

### What if my quality is low?

Shares with quality < 50 are rejected. This can happen with:
- Noisy data
- Model uncertainty
- Bad preprocessing

The miner will try different data until it gets quality >= 50.

---

## Pools

### What is a mining pool?

A pool coordinates multiple miners. Instead of each miner submitting directly to the blockchain, miners connect to a pool that:
1. Distributes work
2. Validates shares
3. Batches submissions
4. Distributes rewards

### Should I join a pool?

**Join a pool if**:
- You want consistent rewards
- You have a smaller GPU
- You don't want to manage transactions

**Mine solo if**:
- You have a large GPU farm
- You want to avoid pool fees
- You want full control

### How do I join a pool?

```bash
python stratum_miner.py --pool ws://pool.voidmap.org:3333 --user YOUR_ADDRESS
```

### What is the pool fee?

2% of rewards. This covers:
- Pool server costs
- Transaction fees
- Development

### Can I run my own pool?

Yes. See the [Pool Guide](Pool-Guide).

---

## Technical

### What ML models do you use?

| Task | Model | Accuracy |
|------|-------|----------|
| Exoplanet transit | AstroNetCNN | 89% |
| Galaxy morphology | ConvNeXT | ~85% |
| Anomaly detection | Autoencoder | N/A |

### Where does the data come from?

- **TESS light curves**: NASA MAST archive
- **SDSS galaxy images**: SDSS DR18
- **ZTF alerts**: Fink broker

All data is public and free to access.

### How do you prevent cheating?

1. **Quality threshold**: Work must score >= 50
2. **IPFS verification**: Results stored on IPFS
3. **On-chain hashes**: Input/output hashes recorded
4. **Model verification**: Model weights hashed

### What if I lose internet?

The miner will:
1. Complete current work
2. Save results locally
3. Reconnect when internet is available
4. Submit accumulated shares

### What if my GPU crashes?

Results are saved locally after each batch. You won't lose work.

---

## Tokenomics

### How many VOID tokens exist?

1,000,000,000 (1 billion) total.

### How are they distributed?

- 90% to GPU miners
- 5% to developer fund (4-year vesting)
- 5% to treasury (DAO governance)

### Is there a pre-sale?

No. 90% goes directly to miners. No VC allocation, no pre-sale, no ICO.

### When can I sell?

VOID will be tradeable on decentralized exchanges (Uniswap) after deployment. There is no lock-up period for miners.

### Is this a rug pull?

No:
- Ownership renounced (immutable contracts)
- 90% to miners (no hidden allocations)
- Transparent vesting (dev fund public)
- Open-source code (verifiable)

---

## Troubleshooting

### "No TESS data found"

- Target may not have TESS observations
- Try a different target index
- Check MAST portal for available data

### "CUDA out of memory"

- Reduce batch size: `--batch 16`
- Close other GPU applications
- Use a GPU with more VRAM

### "Connection refused"

- Pool server may be down
- Check firewall settings
- Try a different pool

### "Shares rejected"

- Quality below threshold
- Job ID mismatch (stale work)
- Invalid output hash

### How do I report bugs?

Open an issue on GitHub: https://github.com/thekillsquad007/voidmap/issues

---

## Legal

### Is this legal?

Yes. Processing public astronomical data with your own GPU is legal in most jurisdictions.

### Do I owe taxes?

Mining VOID is taxable income in most countries. Consult a tax professional.

### Is this securities?

VOID is a utility token used for:
- Mining rewards
- Pool fees
- Governance

It is not an investment contract. There is no company, no profits, no dividends.

---

## Community

### Where can I discuss Voidmap?

- GitHub: https://github.com/thekillsquad007/voidmap
- Discord: (coming soon)
- Twitter: (coming soon)

### How can I contribute?

- Mine VOID
- Run a pool
- Improve the code
- Report bugs
- Write documentation
- Build tools

### Is there a roadmap?

No. Voidmap exists as open-source code. There is no company, no CEO, no roadmap. The value is in the computation.
