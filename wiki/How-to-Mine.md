# How to Mine VOID

A complete step-by-step guide. From zero to your first VOID token in about 5 minutes.

---

## Table of Contents

1. [Check your hardware](#1-check-your-hardware)
2. [Install the miner](#2-install-the-miner)
3. [Set up your wallet](#3-set-up-your-wallet)
4. [Run your first round](#4-run-your-first-round)
5. [Submit on-chain](#5-submit-on-chain)
6. [Keep mining](#6-keep-mining)
7. [Troubleshooting](#troubleshooting)

---

## 1. Check your hardware

Voidmap works on virtually any GPU or CPU. Find out what you have:

**Windows (PowerShell):**
```powershell
wmic path win32_VideoController get name
# Or Device Manager → Display Adapters
```

**macOS:**
```bash
system_profiler SPDisplaysDataType | grep "Chipset Model"
```

**Linux:**
```bash
lspci | grep -iE "vga|3d|display"
```

### What works

| Hardware | Notes |
|----------|-------|
| **NVIDIA** | Any GPU from GTX 1050 and up |
| **AMD** | RX 400 series and newer (RDNA / GCN 5.0+) |
| **Apple Silicon** | M1, M2, M3, M4 (any) |
| **Intel** | Arc GPUs (A380, A770) or CPU |
| **CPU only** | Always works, slowest |

> No GPU? No problem. The miner runs on CPU too — it's just slower.

---

## 2. Install the miner

### Option A: One command (recommended)

```bash
pip install voidmap
pip install voidmap[all]   # include PyTorch, lightkurve, ONNX
```

That's it. You now have four new commands: `voidmap`, `voidmap-detect`, `voidmap-mine`, `voidmap-card`.

### Option B: From source

```bash
git clone https://github.com/thekillsquad007/voidmap.git
cd voidmap
pip install -e ".[all]"
```

### Option C: Docker

```bash
# NVIDIA
docker run -d --gpus all \
  -e VOIDMAP_PK=0xYOUR_KEY \
  -e VOIDMAP_RPC=https://mainnet.base.org \
  thekillsquad007/voidmap-miner:latest

# AMD
docker run -d --device /dev/kfd --device /dev/dri \
  -e VOIDMAP_PK=0xYOUR_KEY \
  -e VOIDMAP_RPC=https://mainnet.base.org \
  thekillsquad007/voidmap-miner:latest
```

### Verify the install

```bash
voidmap-detect
```

You should see something like:

```
  GPU: NVIDIA GeForce RTX 3080 (nvidia)
  Backend: pytorch-cuda
  PyTorch: 2.5.0+cu124
  Platform: Linux-6.x.x
```

---

## 3. Set up your wallet

To receive VOID tokens, you need a wallet on Base L2.

### Recommended: Coinbase Wallet or MetaMask

1. Install [Coinbase Wallet](https://www.coinbase.com/wallet) or [MetaMask](https://metamask.io)
2. Add the Base network:
   - Network: Base
   - RPC: `https://mainnet.base.org`
   - Chain ID: `8453`
   - Currency: ETH
   - Explorer: `https://basescan.org`
3. Fund with at least 0.001 ETH for gas (~$3)

### Export your private key

The miner needs your private key to sign transactions. **Use a fresh wallet for mining** — never your main wallet.

> ⚠️ **Security:** The private key is stored in your shell environment. Never commit it to git, never share it, never use a wallet with significant funds.

To export from MetaMask:

1. Click your account icon → Account details
2. Click "Export Private Key"
3. Enter your password
4. Copy the key (starts with `0x`)

```bash
# Save it to your environment
export VOIDMAP_PK=0xYOUR_PRIVATE_KEY_HERE

# Or pass it directly to the miner
voidmap-mine --pk 0xYOUR_KEY
```

---

## 4. Run your first round

### Try the TUI dashboard

```bash
voidmap
```

You'll see a live dashboard showing your GPU, current task, predictions, and earnings. Keyboard shortcuts:

- `q` — quit
- `p` — pause/resume
- `t` — switch task
- `d` — show discoveries
- `r` — show recent rounds
- `Enter` — mine one round

### Or use the non-TUI miner

```bash
# Mine 10 exoplanet rounds
voidmap-mine --task exoplanet --rounds 10

# Mine all 3 task types
voidmap-mine --task all --rounds 30

# Run forever
voidmap-mine --task exoplanet
```

Sample output:

```
  ◆ VOIDMAP MINER — Non-TUI Mode
  GPU: NVIDIA GeForce RTX 3080
  Backend: pytorch-cuda
  Task: exoplanet
  Rounds: 3

  [1/3] TOI-700: NO_SIGNAL (60.0%) Q=54 4521ms
  [2/3] TOI-732: PLANET (87.3%) Q=89 4102ms
    ★ DISCOVERY!
  [3/3] TOI-1452: NO_SIGNAL (60.0%) Q=57 4287ms

  Done. 3 rounds, 142.50 VOID est., 1 discoveries.
```

> ★ DISCOVERY! means the model is ≥85% confident it found a real exoplanet. The miner will play a sound and you can generate a Discovery Card.

---

## 5. Submit on-chain

By default, results are saved locally. To earn VOID tokens, submit them on-chain:

```bash
voidmap-mine --task exoplanet --rounds 10 --submit \
  --rpc https://mainnet.base.org \
  --pk $VOIDMAP_PK
```

Each round:

1. Mines the data (~5 seconds on RTX 3080)
2. Computes hashes and prepares the transaction
3. Waits 12 seconds (on-chain cooldown per miner)
4. Submits to the MiningPool contract
5. Mints VOID to your wallet based on quality + halving + elastic

### Track your submissions

Each submission is recorded in the on-chain **Result Registry**. View your work at:

- [Explorer](https://explorer.voidmap.org)
- [BaseScan](https://basescan.org)

---

## 6. Keep mining

### Run it in the background

**Linux / macOS:**
```bash
nohup voidmap-mine --task all --submit \
  --rpc https://mainnet.base.org \
  --pk $VOIDMAP_PK \
  > ~/.voidmap/miner.log 2>&1 &
```

**Windows (PowerShell):**
```powershell
Start-Process voidmap-mine -ArgumentList "--task","all","--submit","--rpc","https://mainnet.base.org","--pk","$env:VOIDMAP_PK" -WindowStyle Hidden
```

**systemd service (Linux):**
```bash
sudo tee /etc/systemd/system/voidmap.service > /dev/null <<EOF
[Unit]
Description=Voidmap Miner
After=network.target

[Service]
User=$USER
Environment=VOIDMAP_PK=0xYOUR_KEY
ExecStart=/usr/bin/voidmap-mine --task all --submit --rpc https://mainnet.base.org
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable voidmap
sudo systemctl start voidmap
sudo systemctl status voidmap
```

### HiveOS (mining rig)

```bash
curl -fsSL https://raw.githubusercontent.com/thekillsquad007/voidmap/main/install_hiveos.sh | sudo bash
```

The installer auto-detects your GPU vendor, installs the right PyTorch (CUDA for NVIDIA, ROCm for AMD), creates a `voidmap` wrapper, and sets up a systemd service.

### Docker (any platform)

See [docker-compose.yml](https://github.com/thekillsquad007/voidmap/blob/main/docker-compose.yml) for NVIDIA + AMD profiles.

---

## Troubleshooting

### "Backend: onnx-cpu" when I have a GPU

**Cause:** PyTorch didn't install with GPU support.

**Fix (NVIDIA):** `pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124`

**Fix (AMD):** Install Python 3.10 or 3.11, then `pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm6.2`

### "Cannot find cast"

**Cause:** Foundry not installed.

**Fix:** `curl -L https://foundry.paradigm.xyz | bash && foundryup`

### "No TESS data found for TIC X"

**Cause:** The target doesn't have TESS observations, or MAST is down.

**Fix:** Try a different target, or wait and retry. The miner will fall back to synthetic data.

### "Cooldown" error on every submission

**Cause:** The on-chain cooldown (12 seconds) is enforced.

**Fix:** This is normal — you can only submit one round every 12 seconds per miner.

### Need more help?

- [GitHub](https://github.com/thekillsquad007/voidmap) — file an issue
- [Twitter](https://twitter.com/voidmap) — for quick questions
- [AMD/ROCm Setup](AMD-ROCm-Setup) — if you have an AMD GPU

---

## See also

- [Mining Guide](Mining-Guide) — full reference
- [Tokenomics](Tokenomics) — reward formula and halving
- [Mainnet Features](Mainnet-Features) — halving, elastic, challenge, timelock
- [Smart Contracts](Smart-Contracts) — on-chain details
