# Pool Guide

## What is a Mining Pool?

A mining pool coordinates multiple miners to process astronomical data. Instead of each miner submitting directly to the blockchain (which can be slow and inconsistent), miners connect to a pool that:

1. Distributes work to miners
2. Validates shares (quality >= 50)
3. Batches submissions on-chain
4. Distributes rewards proportionally

---

## Pool Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Miner 1    │────▶│             │     │             │
│  (RTX 3080) │     │   Stratum   │     │  MiningPool │
└─────────────┘     │    Pool     │────▶│  Contract   │
┌─────────────┐     │   Server    │     │   (Base)    │
│  Miner 2    │────▶│             │     │             │
│  (RX 7900)  │     │   :3333     │     │  0x...      │
└─────────────┘     └─────────────┘     └─────────────┘
┌─────────────┐           │                   │
│  Miner 3    │───────────┘                   │
│  (M2 Pro)   │                               │
└─────────────┘                               ▼
                                        ┌─────────────┐
                                        │   VOID      │
                                        │   Tokens    │
                                        └─────────────┘
```

---

## Running a Pool

### Start the Pool Server

```bash
cd miner
python stratum_pool.py --port 3333
```

Output:
```
  ◆ VOIDMAP STRATUM POOL ◆
  Port: 3333
  Difficulty: 50-100
  Anti-ASIC: cnn
  Reward: 98% to miners

  Stratum pool listening on 0.0.0.0:3333
```

### Pool Configuration

Environment variables:

```bash
# Pool port
export VOIDMAP_STRATUM_PORT=3333

# Difficulty range
export VOIDMAP_MIN_DIFFICULTY=50
export VOIDMAP_MAX_DIFFICULTY=100

# Share difficulty
export VOIDMAP_SHARE_DIFFICULTY=16

# Job refresh interval (seconds)
export VOIDMAP_JOB_REFRESH=30
```

### Pool Features

- **Stratum protocol**: Standard JSON-RPC mining protocol
- **Dynamic difficulty**: Adjusts based on miner performance
- **Anti-ASIC**: Model rotation, random batch sizes, memory-hard operations
- **Share validation**: Quality threshold >= 50
- **Real-time stats**: Hashrate, acceptance rate, connected miners

---

## Joining a Pool

### Using Stratum Miner

```bash
python stratum_miner.py --pool ws://pool.voidmap.org:3333 --user YOUR_ADDRESS
```

Options:
- `--pool`: Pool WebSocket URL
- `--user`: Your wallet address or miner ID
- `--worker`: Worker name (default: worker1)

### Stratum Protocol Flow

1. **Connect**: Miner connects to pool via WebSocket
2. **Subscribe**: Miner subscribes to work notifications
3. **Authorize**: Miner authenticates with pool
4. **Receive work**: Pool sends work unit (task, model, batch size)
5. **Process**: Miner runs ML model on GPU
6. **Submit**: Miner submits share (quality, output hash)
7. **Accept/Reject**: Pool validates and responds

### Example Session

```
Miner → Pool: {"method": "mining.subscribe", "params": ["miner_1234"]}
Pool → Miner: {"result": [1, "extranonce", 4]}

Miner → Pool: {"method": "mining.authorize", "params": ["miner_1234", "worker1"]}
Pool → Miner: {"result": true}

Pool → Miner: {"method": "mining.notify", "params": ["job_001", ...]}
Miner → Pool: {"method": "mining.submit", "params": ["miner_1234", "job_001", ...]}
Pool → Miner: {"result": true}
```

---

## Pool Rewards

### Reward Distribution

- Pool keeps 2% fee
- 98% distributed to miners based on shares
- Quality-weighted: higher quality shares earn more

### Example

If 3 miners submit shares:
- Miner A: 100 shares, avg quality 80
- Miner B: 50 shares, avg quality 70
- Miner C: 200 shares, avg quality 90

Total quality-weighted shares:
- A: 100 × 80 = 8,000
- B: 50 × 70 = 3,500
- C: 200 × 90 = 18,000
- Total: 29,500

Reward distribution:
- A: (8,000 / 29,500) × 98% = 26.7%
- B: (3,500 / 29,500) × 98% = 11.6%
- C: (18,000 / 29,500) × 98% = 59.6%

---

## Pool Management

### Adding Miners

Pool operator can add miners:

```python
# Via contract
pool.createPool("My Pool", fee_recipient_address)
pool.addPoolMember(pool_id, miner_address)
```

### Monitoring

```bash
# View pool stats
curl http://localhost:3333/stats

# View connected miners
curl http://localhost:3333/miners
```

### Pool Fees

- Default: 2% (200 basis points)
- Configurable via contract
- Fees go to `feeRecipient` address

---

## Running Multiple Pools

You can run multiple pools with different configurations:

```bash
# Pool 1: High difficulty for experienced miners
VOIDMAP_STRATUM_PORT=3333 VOIDMAP_MIN_DIFFICULTY=70 python stratum_pool.py

# Pool 2: Low difficulty for newcomers
VOIDMAP_STRATUM_PORT=3334 VOIDMAP_MIN_DIFFICULTY=50 python stratum_pool.py
```

---

## Pool vs Solo Mining

| Aspect | Pool | Solo |
|--------|------|------|
| Reward consistency | Regular, proportional | Variable, all-or-nothing |
| Minimum payout | None | Full block reward |
| Fee | 2% | None |
| Complexity | Higher | Lower |
| Best for | Most miners | Large operations |

---

## Pool Security

- **Stratum authentication**: Miners must authorize
- **Share validation**: Quality threshold enforced
- **Rate limiting**: Prevents spam submissions
- **Connection limits**: Max miners configurable

---

## Troubleshooting

### "Connection refused"

- Pool server not running
- Check port is open
- Verify firewall settings

### "Authorization failed"

- Check miner ID is correct
- Pool may have access controls

### "Shares rejected"

- Quality below threshold
- Job ID mismatch (stale work)
- Invalid output hash

### "Low hashrate"

- Check GPU is available
- Verify PyTorch installation
- Reduce batch size if needed
