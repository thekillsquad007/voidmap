# voidmap-miner

The one-command, Rich-powered TUI miner for Voidmap.

## Install

```bash
# From PyPI (when published)
pip install voidmap
pip install voidmap[all]  # with all optional deps (torch, lightkurve, etc.)

# From source
git clone https://github.com/thekillsquad007/voidmap.git
cd voidmap
pip install -e ".[all]"
```

## Quick Start

```bash
# Detect your GPU + backend
voidmap-detect

# Solo mine (no on-chain, save results locally)
voidmap-mine --task exoplanet --rounds 10

# Submit on-chain
voidmap-mine --task exoplanet --submit \
  --rpc https://mainnet.base.org --pk $VOIDMAP_PK

# Full TUI dashboard
voidmap --task exoplanet
```

## Commands

After `pip install voidmap`, four console scripts are available:

| Command | Description |
|---------|-------------|
| `voidmap` | Full TUI dashboard (default) |
| `voidmap-detect` | Show hardware + backend info |
| `voidmap-mine` | Non-TUI batch mining |
| `voidmap-card` | Generate Discovery Cards from results |

### `voidmap` (TUI)

```bash
voidmap [options]

Options:
  --task {exoplanet,galaxy,anomaly,all}   Mining task (default: exoplanet)
  --rounds N                              0 = infinite (default)
  --submit                                Submit results on-chain
  --rpc URL                               Base RPC endpoint
  --pk KEY                                Wallet private key
  --idle                                  Idle mining mode
  --no-tui                                Non-TUI mode
  --detect                                Show hardware info
```

In the TUI:
- `q` quit
- `p` pause/resume
- `t` switch task
- `d` show discoveries board
- `r` show recent rounds
- `Enter` mine one round

### `voidmap-mine` (Non-TUI)

```bash
voidmap-mine --task exoplanet --rounds 100
voidmap-mine --task all --submit --rpc https://mainnet.base.org --pk $VOIDMAP_PK
```

### `voidmap-detect`

```bash
$ voidmap-detect
  GPU: NVIDIA GeForce RTX 3080 (nvidia)
  Backend: pytorch-cuda
  PyTorch: 2.1.0+cu121
  Platform: Linux-6.x.x
```

### `voidmap-card`

```bash
voidmap-card --target TOI-732 --task exoplanet_transit \
  --prediction PLANET --confidence 0.92 --quality 95 \
  --miner 0xYOUR_ADDRESS --output discovery.png
```

## Python API

```python
from voidmap_miner import mine, detect, list_targets

# Detect hardware
hw = detect()
print(f"GPU: {hw.gpu_name}, Backend: {hw.backend.value}")

# Mine
results = mine("exoplanet", rounds=10)
for r in results:
    print(f"{r.target}: {r.prediction} ({r.confidence:.1%})")
    if r.is_discovery:
        print(f"  ★ DISCOVERY! Quality {r.quality_score}/100")

# List known targets
for t in list_targets():
    print(f"{t['name']} ({t['tic']}): {len(t['planets'])} planets")
```

## Multi-Backend Support

The miner auto-selects the best backend for your hardware:

| Backend | Hardware | Speed |
|---------|----------|-------|
| `pytorch-cuda` | NVIDIA | ★★★★★ |
| `pytorch-rocm` | AMD | ★★★★ |
| `pytorch-mps` | Apple Silicon | ★★★ |
| `onnx-cuda` | NVIDIA (ONNX) | ★★★★ |
| `onnx-dml` | Intel/AMD (Windows) | ★★★ |
| `onnx-cpu` | any CPU | ★★ |
| `pytorch-cpu` | any CPU | ★ |

To force a specific backend, set the `VOIDMAP_BACKEND` env var or pass `--backend` to the CLI.

## Tasks

- **exoplanet** — Transit detection on TESS light curves (AstroNetCNN)
- **galaxy** — Morphology classification on SDSS images (Zoobot)
- **anomaly** — Anomaly detection on ZTF alerts (AnomalyAE)
- **all** — Rotate through all three

## Output

Results are saved as JSON to `~/.voidmap/results/`:

```json
{
  "task": "exoplanet_transit",
  "target": "TOI-732",
  "prediction": "PLANET",
  "confidence": 0.92,
  "quality_score": 95,
  "backend": "onnx-cuda",
  "model": "AstroNetCNN (sarojpatil16/exoplanet-transit-detector)",
  "data_source": "MAST TESS SPOC (TIC 307210830)",
  "input_hash": "0xabc...",
  "output_hash": "0xdef...",
  "model_hash": "0x789...",
  "samples": 2048,
  "duration_ms": 4521,
  "gpu": "NVIDIA GeForce RTX 3080",
  "timestamp": 1717440000,
  "extra": {
    "est_void": 71.25,
    "probabilities": {
      "planet": 0.92,
      "false_positive": 0.06,
      "no_signal": 0.02
    }
  }
}
```

## Discovery Chime

When a high-confidence planet (≥85% PLANET) is detected, the miner plays a short chord. This works on:

- **Linux**: requires `aplay` + a sound file (fallback to silent)
- **macOS**: uses `afplay` with system sound
- **Windows**: uses `winsound.MessageBeep`

To disable: set `VOIDMAP_NO_CHIME=1`.

## Idle Mining

Pass `--idle` to enable idle mining mode. The miner will:

- Detect when the system is idle (low CPU/GPU utilization)
- Auto-mine during idle periods
- Pause when you're using the computer

Coming soon: cross-platform idle detection.

## License

MIT
