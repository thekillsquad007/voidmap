# Mining Guide

## Prerequisites

- **GPU**: NVIDIA (CUDA), AMD (ROCm), Apple Silicon (MPS), or Intel (DirectML)
- **Python**: 3.10+
- **RAM**: 8GB minimum, 16GB recommended
- **Storage**: 10GB for models and cached data
- **Internet**: Required for downloading data from MAST/SDSS/ZTF

---

## Quick Start

### 1. Install Dependencies

```bash
git clone https://github.com/thekillsquad007/voidmap.git
cd voidmap/miner
pip install -r requirements.txt
```

**Multi-backend support** — `requirements.txt` installs the right PyTorch for your hardware:

```bash
# NVIDIA (default)
pip install -r requirements.txt

# AMD (ROCm 6.2)
pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm6.2
pip install onnxruntime onnx

# Apple Silicon (MPS)
pip install -r requirements.txt  # MPS included in stock PyTorch

# Intel/AMD (DirectML via ONNX)
pip install -r requirements.txt
pip install onnxruntime-directml

# CPU only
pip install -r requirements.txt  # works on CPU as fallback
```

### 2. Detect Your GPU

```bash
python voidmap-miner.py --detect
```

Output:
```
  PyTorch: 2.1.0
  GPU 0: NVIDIA GeForce RTX 3080 (10.0 GB)
  Backend: ONNX (CUDA)
  ONNX providers: ['CUDAExecutionProvider', 'CPUExecutionProvider']
  lightkurve: OK
  astropy: OK
  Device: cuda
  Results: /home/user/.voidmap/results
```

The miner auto-selects the best backend in this priority order:
1. **PyTorch CUDA** (NVIDIA) — fastest
2. **PyTorch ROCm** (AMD)
3. **ONNX DirectML** (Intel/AMD on Windows)
4. **ONNX CPU** (anywhere, always works)
5. **PyTorch CPU** (fallback)

### 3. Start Mining

```bash
# Solo mode: mine and save results locally (no on-chain submission)
python voidmap-miner.py --task exoplanet --rounds 10

# Submit mode: mine and submit directly to MiningPool on-chain
python voidmap-miner.py --task exoplanet --rounds 10 --submit \
  --rpc https://mainnet.base.org \
  --pk 0xYOUR_PRIVATE_KEY

# Run continuously until interrupted
python voidmap-miner.py --task exoplanet --submit --rpc https://mainnet.base.org --pk 0x...

# Mine all three task types in rotation
python voidmap-miner.py --task all --submit --rpc https://mainnet.base.org --pk 0x...
```

### 4. View Your Results

```bash
python voidmap-miner.py --list-results
```

Output:
```
  Recent Results (5 total):

  exoplanet_TOI-732_1717440000.json
    Target: TOI-732 | Prediction: PLANET (87.3%)
    Quality: 87/100 | Backend: onnx-cuda | Source: MAST TESS SPOC 2-min cadence
    Submitted: tx 0xabc...def (block 12345)

  galaxy_NGC_4565_1717439000.json
    Galaxy: NGC 4565 | Class: Spiral (92.1%)
    Quality: 92/100 | Backend: pytorch-rocm | Source: SDSS DR18 cutout
```

---

## Mining Modes

### Solo Mining (Default)

Mine and save results locally without on-chain submission:

```bash
python voidmap-miner.py --task exoplanet --rounds 100
```

- No blockchain transaction fees
- No wallet needed
- Results stored at `~/.voidmap/results/`
- Useful for testing, development, or contributing to research without claiming rewards

### Solo + Submit (Mainnet)

Mine AND submit each valid result directly to the MiningPool contract:

```bash
python voidmap-miner.py --task exoplanet --submit \
  --rpc https://mainnet.base.org \
  --pk $VOIDMAP_PK
```

- Costs ~0.00001 ETH per submission (Base gas is cheap)
- Earns VOID rewards based on quality + halving + elastic multiplier
- 12-second cooldown enforced on-chain between submissions per miner
- Min 2-second compute duration enforced on-chain (anti-ASIC)
- Quality must be ≥ 50 to be accepted

### Pool Mining (Stratum)

Connect to a mining pool for more consistent rewards:

```bash
python stratum_miner.py --pool ws://pool.voidmap.org:3333 --user YOUR_ADDRESS
```

- Work distributed by pool
- Shares validated locally
- Rewards split among pool members
- 2% pool fee

---

## Task Details

### Exoplanet Transit Detection

```bash
python voidmap-miner.py --task exoplanet --rounds 10
```

**What happens**:
1. Downloads real TESS light curve from MAST (NASA)
2. Preprocesses (quality filter, normalize, phase-fold)
3. Runs AstroNetCNN model
4. Outputs: PLANET / FALSE_POSITIVE / NO_SIGNAL

**Known targets** (pre-verified):
- TOI-732 (2 planets)
- TOI-1452 (1 planet)
- TOI-700 (4 planets)
- TOI-1259, TOI-1444

```bash
# List known targets
python voidmap-miner.py --list-targets

# Mine specific target
python voidmap-miner.py --task exoplanet --target-idx 0
```

### Galaxy Morphology Classification

```bash
python voidmap-miner.py --task galaxy --rounds 10
```

**What happens**:
1. Downloads galaxy image from SDSS DR18 (NSF)
2. Resizes to 224x224 RGB
3. Runs ConvNeXT classifier
4. Outputs: Spiral / Elliptical / Irregular / Merger / Unknown

### Anomaly Detection

```bash
python voidmap-miner.py --task anomaly --rounds 10
```

**What happens**:
1. Downloads ZTF alerts from Fink broker (NSF)
2. Extracts features
3. Runs autoencoder
4. Outputs: anomaly scores + flags

### Mining All Tasks

```bash
python voidmap-miner.py --task all --rounds 30
```

Rotates through all 3 task types. Each task processed in turn.

---

## Multi-Backend Support

The miner auto-selects the best ML backend for your hardware.

### Backend Selection Priority

```python
ModelBackend.auto()
  → PyTorchBackend(cuda)        # NVIDIA GPU
  → PyTorchBackend(rocm)        # AMD GPU
  → ONNXBackend(providers=['DmlExecutionProvider'])  # Intel/AMD on Windows
  → ONNXBackend(providers=['CUDAExecutionProvider']) # NVIDIA via ONNX
  → ONNXBackend(providers=['CPUExecutionProvider'])   # any CPU
  → PyTorchBackend(cpu)         # PyTorch CPU fallback
```

### Backend Comparison

| Backend | Speed | Hardware | Notes |
|---------|-------|----------|-------|
| `pytorch-cuda` | ★★★★★ | NVIDIA | Fastest, requires CUDA toolkit |
| `pytorch-rocm` | ★★★★ | AMD | Requires ROCm 6.2 |
| `onnx-cuda` | ★★★★ | NVIDIA | ONNX runtime, no CUDA toolkit needed |
| `onnx-dml` | ★★★ | Intel/AMD | DirectML on Windows |
| `onnx-cpu` | ★★ | any CPU | Slowest but always works |
| `pytorch-cpu` | ★★ | any CPU | Last resort fallback |

### ONNX Model

The pre-trained model is exported to ONNX (`miner/astronet_cnn.onnx`, 15MB) for cross-platform compatibility. Max inference difference vs PyTorch: 0.00000191 (negligible).

### Manual Backend Override

```bash
# Force a specific backend
python voidmap-miner.py --task exoplanet --backend onnx-cpu
```

Available backends: `pytorch-cuda`, `pytorch-rocm`, `pytorch-mps`, `pytorch-cpu`, `onnx-cuda`, `onnx-rocm`, `onnx-dml`, `onnx-cpu`.

---

## HiveOS / Docker Deployment

### Option A: Docker (Recommended)

HiveOS has Docker support built in. One command and you're mining.

**NVIDIA GPUs:**
```bash
# Pull the image (after release)
docker pull thekillsquad007/voidmap-miner:latest

# Run with your wallet
docker run -d \
  --name voidmap-miner \
  --restart unless-stopped \
  --gpus all \
  -e VOIDMAP_PK=0xYOUR_PRIVATE_KEY \
  -e VOIDMAP_RPC=https://mainnet.base.org \
  -e VOIDMAP_TASK=all \
  thekillsquad007/voidmap-miner:latest
```

**AMD GPUs:**
```bash
docker run -d \
  --name voidmap-miner \
  --restart unless-stopped \
  --device /dev/kfd \
  --device /dev/dri \
  --security-opt seccomp=unconfined \
  -e VOIDMAP_PK=0xYOUR_PRIVATE_KEY \
  -e VOIDMAP_RPC=https://mainnet.base.org \
  -e VOIDMAP_TASK=all \
  thekillsquad007/voidmap-miner:latest
```

**Docker Compose:**
```bash
# NVIDIA
docker compose up -d voidmap-miner

# AMD
docker compose --profile amd up -d voidmap-miner-amd
```

### Option B: Native Install

```bash
# SSH into your HiveOS rig
ssh hive@YOUR_RIG_IP

# Run the installer
curl -fsSL https://raw.githubusercontent.com/thekillsquad007/voidmap/main/install_hiveos.sh | sudo bash

# Configure
export VOIDMAP_PK=0xYOUR_PRIVATE_KEY
export VOIDMAP_RPC=https://mainnet.base.org
export VOIDMAP_TASK=all

# Start
sudo systemctl start voidmap-miner
sudo systemctl status voidmap-miner

# Use the `voidmap` wrapper
voidmap --detect
voidmap --task exoplanet --rounds 10
```

The installer:
- Auto-detects GPU vendor (NVIDIA / AMD / Intel)
- Installs ROCm PyTorch for AMD GPUs
- Installs ONNX Runtime
- Creates a `voidmap` wrapper at `/usr/local/bin/voidmap`
- Installs systemd service `voidmap-miner.service`
- Configures auto-start on boot

---

## Configuration

### Environment Variables

```bash
# Wallet
export VOIDMAP_PK=0xYOUR_PRIVATE_KEY  # for --submit mode

# RPC endpoint
export VOIDMAP_RPC=https://mainnet.base.org

# Results directory
export VOIDMAP_RESULTS_DIR=~/.voidmap/results

# Model cache
export VOIDMAP_MODEL_DIR=~/.voidmap/models

# IPFS (optional, for storing results off-chain)
export PINATA_API_KEY=your_key
export PINATA_API_SECRET=your_secret

# Mining config
export VOIDMAP_TASK=exoplanet  # exoplanet | galaxy | anomaly | all
export VOIDMAP_COOLDOWN=12    # seconds between submissions (min 12 enforced on-chain)

# Pool settings (if using pool mining)
export VOIDMAP_POOL_PORT=3333
```

### Command Line Options

```bash
python voidmap-miner.py --help

Options:
  --task {exoplanet,galaxy,anomaly,all}  Mining task
  --rounds N                            Number of rounds (default: infinite)
  --batch N                             Batch size
  --target-idx N                        Specific target index
  --backend {pytorch-cuda,pytorch-rocm,pytorch-cpu,onnx-cuda,onnx-dml,onnx-cpu}
                                         Force specific ML backend
  --submit                              Submit results on-chain to MiningPool
  --rpc URL                             Base RPC endpoint
  --pk KEY                              Wallet private key (for --submit)
  --detect                              Show hardware + backend info
  --list-tasks                          Show available tasks
  --list-results                        Show past results
  --list-targets                        Show known exoplanet targets
```

---

## Output Format

Results are saved as JSON at `~/.voidmap/results/`:

```json
{
  "task": "exoplanet_transit",
  "target": "TOI-732",
  "tic_id": "TIC 307210830",
  "prediction": "PLANET",
  "confidence": 0.873,
  "probabilities": {
    "planet": 0.873,
    "false_positive": 0.092,
    "no_signal": 0.035
  },
  "quality_score": 87,
  "model": "AstroNetCNN (sarojpatil16/exoplanet-transit-detector)",
  "backend": "onnx-cuda",
  "data_source": "MAST TESS SPOC 2-min cadence",
  "input_hash": "0xabc123...",
  "output_hash": "0xdef456...",
  "model_hash": "0x789abc...",
  "samples": 2048,
  "duration_ms": 4521,
  "gpu": "NVIDIA GeForce RTX 3080",
  "ipfs_cid": "QmXxx...",
  "timestamp": 1717440000,
  "tx_hash": "0x123abc...def"  // only if --submit
}
```

---

## Anti-ASIC Checks

The miner automatically enforces the on-chain anti-ASIC rules:

| Check | Threshold | Failure Mode |
|-------|-----------|--------------|
| Quality floor | ≥ 50 | Reject submission |
| Compute duration | ≥ 2s | Reject submission (reverted on-chain) |
| Submission cooldown | ≥ 12s | Skip submission |
| Hardware signature | GPU detected | Mark as suspicious |
| Data integrity | Hash matches | Reject submission |

If `--submit` mode detects that your work would be rejected on-chain, it skips the transaction to save gas.

---

## Troubleshooting

### "No TESS data found for TIC X"

- Target may not have TESS observations
- Try a different target index
- Check MAST portal for available data

### "Download failed"

- Check internet connection
- MAST may be temporarily unavailable
- Try again in a few minutes

### "Quality too low"

- Model confidence was below 50
- This can happen with noisy data
- The share will be rejected by the pool

### "CUDA out of memory"

- Reduce batch size: `--batch 16`
- Close other GPU applications
- Use a GPU with more VRAM

### "Backend not found" / "No GPU detected"

The miner auto-falls back to ONNX-CPU. To force a specific backend:

```bash
python voidmap-miner.py --backend onnx-cpu --task exoplanet
```

### "Submit reverted: Compute too fast"

Your result was rejected for being under 2 seconds. The miner should have caught this before sending. If it didn't, file an issue.

### AMD GPU not detected in Docker

Ensure you've added `--device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined` flags. Also check that ROCm is installed on the host (HiveOS supports ROCm out of the box for many cards).

### Submitting on testnet

```bash
# Testnet (Base Sepolia)
python voidmap-miner.py --task exoplanet --submit \
  --rpc https://sepolia.base.org \
  --pk $VOIDMAP_PK
```

---

## Hardware Performance Guide

Approximate submissions per hour (exoplanet task, single GPU):

| GPU | VRAM | Backend | Submissions/hr |
|-----|------|---------|----------------|
| RTX 4090 | 24GB | pytorch-cuda | ~300 |
| RTX 3080 | 10GB | pytorch-cuda | ~200 |
| RTX 3060 | 12GB | pytorch-cuda | ~150 |
| RX 7900 XTX | 24GB | pytorch-rocm | ~250 |
| RX 6800 XT | 16GB | pytorch-rocm | ~180 |
| Apple M2 Max | 32GB | pytorch-mps | ~100 |
| Intel Arc A770 | 16GB | onnx-dml | ~120 |
| CPU (32 cores) | n/a | pytorch-cpu | ~10 |

Numbers assume 12s cooldown per submission. Higher quality = more VOID per submission.

---

## Next Steps

- [Join a pool](Pool-Guide) for more consistent rewards
- [Read about anti-ASIC](Anti-ASIC) measures
- [Query results via API](API-Reference)
- [Read about mainnet features](Mainnet-Features) (halving, elastic mint, challenge/slash, timelock)
- [Deploy contracts](Smart-Contracts) to earn on-chain
