# Mining Guide

## Prerequisites

- **GPU**: NVIDIA (CUDA), AMD (ROCm), Apple Silicon (MPS), or Intel (OpenCL)
- **Python**: 3.10+
- **RAM**: 8GB minimum, 16GB recommended
- **Storage**: 10GB for models and cached data
- **Internet**: Required for downloading data from MAST/SDSS/ZTF

---

## Quick Start

### 1. Install Dependencies

```bash
# Clone the repository
git clone https://github.com/thekillsquad007/voidmap.git
cd voidmap/miner

# Install Python packages
pip install -r requirements.txt
```

### 2. Detect Your GPU

```bash
python voidmap-miner.py --detect
```

Output:
```
  PyTorch: 2.1.0
  GPU 0: NVIDIA GeForce RTX 3080 (10.0 GB)
  lightkurve: OK
  astropy: OK
  huggingface_hub: OK
  Device: cuda
  Results: /home/user/.voidmap/results
```

### 3. Start Mining

```bash
# Mine exoplanet transit detection (real TESS data)
python voidmap-miner.py --task exoplanet --rounds 10

# Mine galaxy morphology classification (real SDSS data)
python voidmap-miner.py --task galaxy --rounds 10

# Mine anomaly detection (real ZTF data)
python voidmap-miner.py --task anomaly --rounds 10
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
    Quality: 87/100 | Source: MAST TESS SPOC 2-min cadence

  galaxy_NGC_4565_1717439000.json
    Galaxy: NGC 4565 | Class: Spiral (92.1%)
    Quality: 92/100 | Source: SDSS DR18 cutout
```

---

## Mining Modes

### Standalone Mining

Mine directly to the blockchain:

```bash
python voidmap-miner.py --task exoplanet --rounds 100
```

- No pool required
- Rewards go directly to your address
- Full control over which tasks to mine

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
1. Downloads real TESS light curve from MAST
2. Preprocesses (quality filter, normalize, phase-fold)
3. Runs AstroNetCNN model
4. Outputs: PLANET / FALSE_POSITIVE / NO_SIGNAL

**Known targets** (pre-verified):
- TOI-732 (2 planets)
- TOI-1452 (1 planet)
- TOI-700 (4 planets)

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
1. Downloads galaxy image from SDSS DR18
2. Resizes to 224x224 RGB
3. Runs ConvNeXT classifier
4. Outputs: Spiral / Elliptical / Irregular / Merger / Unknown

### Anomaly Detection

```bash
python voidmap-miner.py --task anomaly --rounds 10
```

**What happens**:
1. Downloads ZTF alerts from Fink broker
2. Extracts features
3. Runs autoencoder
4. Outputs: anomaly scores + flags

---

## Configuration

### Environment Variables

```bash
# Results directory
export VOIDMAP_RESULTS_DIR=~/.voidmap/results

# Model cache
export VOIDMAP_MODEL_DIR=~/.voidmap/models

# IPFS (optional)
export PINATA_API_KEY=your_key
export PINATA_API_SECRET=your_secret

# Pool settings
export VOIDMAP_POOL_PORT=3333
```

### Command Line Options

```bash
python voidmap-miner.py --help

Options:
  --task {exoplanet,galaxy,anomaly}  Mining task
  --rounds N                         Number of rounds
  --batch N                          Batch size
  --target-idx N                     Specific target index
  --detect                           Show GPU info
  --list-tasks                       Show available tasks
  --list-results                     Show past results
  --list-targets                     Show known targets
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
  "data_source": "MAST TESS SPOC 2-min cadence",
  "timestamp": 1717440000
}
```

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

---

## Next Steps

- [Join a pool](pool.md) for more consistent rewards
- [Read about anti-ASIC](anti-asic.md) measures
- [Query results via API](api.md)
- [Deploy contracts](contracts.md) to earn on-chain
