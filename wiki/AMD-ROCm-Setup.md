# AMD GPU / ROCm Setup Guide

Voidmap supports AMD GPUs via PyTorch ROCm and ONNX Runtime ROCm. This guide covers installation, troubleshooting, and known limitations.

---

## Quick Reference

| GPU Generation | Architecture | ROCm Support | Recommended Backend |
|----------------|--------------|--------------|---------------------|
| RX 7900 XTX / 7900 XT | RDNA 3 | ✅ Full (5.7+) | PyTorch ROCm 6.2 |
| RX 7800 XT / 7700 XT | RDNA 3 | ✅ Full (5.7+) | PyTorch ROCm 6.2 |
| RX 6800 XT / 6900 XT | RDNA 2 | ✅ Full (5.4+) | PyTorch ROCm 6.2 |
| RX 6700 XT / 6800M | RDNA 2 | ✅ Full (5.4+) | PyTorch ROCm 6.2 |
| RX 6600 XT / 6600 | RDNA 2 | ✅ Full (5.4+) | PyTorch ROCm 6.2 |
| RX 5700 XT / 5700 | RDNA 1 | ⚠ Partial (5.4+) | PyTorch ROCm 5.7 |
| RX Vega 64 / Vega 56 | GCN 5.0 | ⚠ Partial | PyTorch ROCm 5.4 |
| RX 590 / 580 | GCN 4.0 | ❌ EOL | Use ONNX CPU |
| Vega Cezanne iGPU | GCN 5.1 | ⚠ Limited | Use ONNX CPU |

---

## Installation

### HiveOS (Recommended for mining rigs)

ROCm is pre-installed on HiveOS. The `install_hiveos.sh` script auto-detects and configures it.

```bash
curl -fsSL https://raw.githubusercontent.com/thekillsquad007/voidmap/main/install_hiveos.sh | sudo bash
```

### Ubuntu / Debian

```bash
# 1. Install ROCm
wget https://repo.radeon.com/amdgpu-install/6.2/ubuntu/jammy/amdgpu-install_6.2.60200-1_all.deb
sudo apt-get install ./amdgpu-install_6.2.60200-1_all.deb
sudo amdgpu-install --usecase=rocm

# 2. Add user to groups
sudo usermod -aG video,render $USER
newgrp video
newgrp render

# 3. Verify
rocm-smi

# 4. Install Voidmap
curl -fsSL https://raw.githubusercontent.com/thekillsquad007/voidmap/main/install_local.sh | bash
```

### Fedora / RHEL

```bash
# 1. Install ROCm
sudo dnf install rocm ROCm

# 2. Add user to groups
sudo usermod -aG video,render $USER

# 3. Verify
rocm-smi

# 4. Install Voidmap
GPU_VENDOR=amd bash install_local.sh
```

### Arch / Manjaro

```bash
# 1. Install ROCm
sudo pacman -S rocm-hip-sdk

# 2. Add user to groups
sudo usermod -aG video,render $USER

# 3. Verify
rocm-smi

# 4. Install Voidmap
GPU_VENDOR=amd bash install_local.sh
```

---

## Critical Requirement: Python 3.10 or 3.11

**PyTorch ROCm wheels are only built for Python 3.10 and 3.11.**

If you have Python 3.12 or 3.13, you have two options:

### Option A: Install Python 3.11 alongside

```bash
# Ubuntu
sudo apt-get install python3.11 python3.11-venv python3.11-dev

# Fedora
sudo dnf install python3.11

# Arch
sudo pacman -S python311

# Then verify
python3.11 --version
```

Then run the installer — it will auto-detect the right Python:

```bash
GPU_VENDOR=amd bash install_local.sh
```

### Option B: Use ONNX CPU (slower, no Python restriction)

If you can't install Python 3.10/3.11, the miner falls back to ONNX CPU. This is slower but always works:

```bash
GPU_VENDOR=cpu bash install_local.sh
```

Performance: ~5-10x slower than ROCm, but still functional.

---

## HSA_OVERRIDE_GFX_VERSION

For some AMD GPUs, you need to set `HSA_OVERRIDE_GFX_VERSION` because the GPU's reported GFX version isn't supported by the installed ROCm.

| GPU | GFX Version | HSA_OVERRIDE_GFX_VERSION |
|-----|-------------|---------------------------|
| RX 6800 / 6800 XT / 6900 XT | 10.3.0 | 10.3.0 |
| RX 6700 XT | 10.3.0 | 10.3.0 |
| RX 6600 / 6600 XT | 10.3.0 | 10.3.0 |
| RX 7900 XTX / 7900 XT | 11.0.0 | (default) |
| RX 7800 XT / 7700 XT | 11.0.0 | (default) |
| RX 5700 XT / 5700 | 10.1.0 | 10.1.0 |

Set the env var in your shell rc:

```bash
echo 'export HSA_OVERRIDE_GFX_VERSION=10.3.0' >> ~/.bashrc
```

---

## Verifying Installation

After installation, run:

```bash
voidmap --detect
```

Expected output for AMD GPU:

```
  GPU: AMD Radeon RX 6800 XT (amd)
  Backend: pytorch-rocm
  PyTorch: 2.5.0+rocm6.2
  Platform: Linux-6.x.x
```

If you see "Backend: onnx-cpu" instead of "pytorch-rocm", check the troubleshooting below.

---

## Troubleshooting

### "ROCm not found" / PyTorch installed but not using GPU

**Cause:** PyTorch is using CPU version, not ROCm version.

**Fix:**
```bash
# Reinstall with ROCm
pip uninstall -y torch torchvision
pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm6.2
```

### "No HIP runtime" / "hipErrorNoBinaryForGpu"

**Cause:** Your GPU's GFX version isn't supported by installed ROCm.

**Fix:** Set `HSA_OVERRIDE_GFX_VERSION`:
```bash
export HSA_OVERRIDE_GFX_VERSION=10.3.0
```

### "/dev/kfd not found"

**Cause:** KFD (Kernel Fusion Driver) not loaded.

**Fix:**
```bash
sudo modprobe amdgpu
sudo modprobe kfd

# Check
ls -la /dev/kfd
```

If `/dev/kfd` still doesn't exist, your kernel may not support KFD. Update to kernel 5.15+.

### "Permission denied" on /dev/kfd

**Cause:** User not in `video` and `render` groups.

**Fix:**
```bash
sudo usermod -aG video,render $USER
newgrp video
newgrp render

# Log out and back in for changes to take effect
```

### GPU detected but Backend = pytorch-cpu

**Cause:** PyTorch ROCm wheel not installed (Python version mismatch).

**Fix:** Check Python version:
```bash
python3 --version
```

If 3.12+, install Python 3.11 and reinstall:
```bash
sudo apt-get install python3.11
python3.11 -m pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm6.2
```

### "HSA status out of resources"

**Cause:** GPU out of memory.

**Fix:** Reduce batch size:
```bash
voidmap-mine --task exoplanet --batch 8
```

### Mining crashes with "RuntimeError: HIP error"

**Cause:** Various ROCm issues. Often fixed by updating drivers.

**Fix:**
```bash
# Ubuntu
sudo amdgpu-install --usecase=rocm

# Or try the latest ROCm 6.3
wget https://repo.radeon.com/amdgpu-install/6.3/ubuntu/jammy/amdgpu-install_6.3.60300-1_all.deb
```

### Old GPU (RX 500 series) not supported

**Cause:** GCN 4.0 and earlier are EOL in ROCm 5.4+.

**Fix:** Use ONNX CPU backend. The miner auto-falls back, but you can force it:
```bash
voidmap-mine --task exoplanet --backend onnx-cpu
```

### Integrated GPU (Vega Cezanne) detected but not used

**Cause:** Integrated GPUs have limited ROCm support.

**Fix:** Use a discrete GPU. Or run ONNX CPU (integrated GPUs are slower than discrete even with ROCm).

---

## Performance Comparison (RX 6800 XT)

| Backend | Round time | Submissions/hr | Notes |
|---------|-----------|----------------|-------|
| PyTorch ROCm 6.2 | 5.5s | 182 | Fastest |
| ONNX ROCm | 7.2s | 138 | Good fallback |
| ONNX DirectML | 10.1s | 99 | Windows only |
| ONNX CPU | 35s | 28 | Slow but works |

(12s on-chain cooldown not included in round time.)

---

## HiveOS-Specific Notes

HiveOS uses `/hive-config` for configuration. To enable ROCm in HiveOS:

1. **Flight Sheet:** Custom miner config:
   ```
   Miner: voidmap
   URL: -
   Wallet: 0xYOUR_ADDRESS
   Extra args: --task exoplanet --submit --rpc https://mainnet.base.org --pk YOUR_PK
   ```

2. **HiveOS ROCm toggle:** `rocm` on the rig config.

3. **Test:** SSH into rig and run:
   ```bash
   rocm-smi
   /opt/voidmap-miner/venv/bin/python -c "import torch; print(torch.cuda.is_available())"
   ```
   Both should return successfully.

---

## Known Issues

### Python 3.12+ no ROCm wheels

PyTorch team has not released ROCm wheels for Python 3.12+ as of mid-2026. Workarounds:
- Use Python 3.11 (recommended)
- Use ONNX CPU (slower)

### ROCm 6.2 + RX 7900 series

ROCm 6.2 has full support for RDNA 3 (RX 7900 series). Use `HSA_OVERRIDE_GFX_VERSION=11.0.0` if not auto-detected.

### iGPU + dGPU hybrid systems

If your system has both an integrated GPU (Vega Cezanne) and a discrete GPU (RX 6800), the miner will use the discrete GPU by default. To force the integrated GPU (not recommended — slower):

```bash
CUDA_VISIBLE_DEVICES=0 voidmap --task exoplanet
```

---

## See Also

- [Mining Guide](Mining-Guide) — General mining setup
- [HiveOS Installer](../install_hiveos.sh) — HiveOS-specific install
- [Local Installer](../install_local.sh) — Desktop/workstation install
- [Docker Setup](../Dockerfile) — Containerized mining
