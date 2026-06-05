#!/usr/bin/env bash
#
# Voidmap Miner — Local Linux Installer (Ubuntu/Debian/Fedora/Arch)
#
# Installs Voidmap miner with ROCm support for AMD GPUs.
# Use this on a desktop or workstation, NOT on HiveOS (use install_hiveos.sh).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/thekillsquad007/voidmap/main/install_local.sh | bash
#
# Or with options:
#   GPU_VENDOR=auto bash install_local.sh
#   GPU_VENDOR=amd bash install_local.sh
#   GPU_VENDOR=nvidia bash install_local.sh
#   GPU_VENDOR=cpu bash install_local.sh
#
set -e

REPO_URL="https://github.com/thekillsquad007/voidmap.git"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.voidmap-install}"
VENV_DIR="$INSTALL_DIR/venv"
GPU_VENDOR="${GPU_VENDOR:-auto}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Voidmap Miner — Local Installer                   ║"
echo "║   Proof of Useful Work: Real astronomy data → VOID tokens   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ─── GPU Detection ───────────────────────────────────────

if [ "$GPU_VENDOR" = "auto" ]; then
    echo "[1/6] Detecting GPU..."
    if command -v lspci >/dev/null 2>&1; then
        if lspci | grep -qi nvidia; then
            GPU_VENDOR="nvidia"
            GPU_NAME=$(lspci | grep -i nvidia | head -1 | sed 's/.*: //')
        elif lspci | grep -qiE 'amd|radeon|ati'; then
            GPU_VENDOR="amd"
            GPU_NAME=$(lspci | grep -iE 'amd|radeon' | grep -i vga | head -1 | sed 's/.*: //')
        elif lspci | grep -qi intel; then
            GPU_VENDOR="intel"
            GPU_NAME=$(lspci | grep -i intel | grep -i vga | head -1 | sed 's/.*: //')
        else
            GPU_VENDOR="cpu"
            GPU_NAME="None detected"
        fi
    else
        GPU_VENDOR="cpu"
        GPU_NAME="lspci not available"
    fi
    echo "  Detected: $GPU_NAME ($GPU_VENDOR)"
else
    echo "[1/6] Using GPU_VENDOR=$GPU_VENDOR (auto-detection skipped)"
    GPU_NAME="(specified)"
fi

# ─── Python Check ────────────────────────────────────────

echo ""
echo "[2/6] Checking Python..."

PYTHON=""
for py in python3.11 python3.10 python3.12 python3; do
    if command -v $py >/dev/null 2>&1; then
        version=$($py -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        # ROCm wheels available for 3.10 and 3.11
        if [ "$GPU_VENDOR" = "amd" ]; then
            if [ "$version" = "3.10" ] || [ "$version" = "3.11" ]; then
                PYTHON=$py
                break
            fi
        else
            # CPU/CUDA wheels for all versions
            PYTHON=$py
            break
        fi
    fi
done

if [ -z "$PYTHON" ]; then
    echo "  ✗ No compatible Python found"
    echo "    For AMD GPU: install Python 3.10 or 3.11"
    echo "    For other GPUs: any Python 3.10+ works"
    exit 1
fi
echo "  Using: $PYTHON ($($PYTHON --version 2>&1))"

# ─── System Dependencies ─────────────────────────────────

echo ""
echo "[3/6] Installing system dependencies..."

if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y python3-venv git wget curl \
        libglib2.0-0 libsm6 libxext6 libxrender-dev libgl1 \
        libnuma1 libpciaccess0 pciutils
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y python3-virtualenv git wget curl \
        glib2 libSM libXext libXrender mesa-libGL \
        numactl libpciaccess pciutils
elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm python-virtualenv git wget curl \
        glib2 libsm libxext libxrender mesa \
        numactl libpciaccess pciutils
else
    echo "  ⚠ Unknown package manager. Install dependencies manually:"
    echo "    git python3-pip python3-venv libgl libnuma libpciaccess"
fi

# ─── ROCm Setup (AMD only) ──────────────────────────────

if [ "$GPU_VENDOR" = "amd" ]; then
    echo ""
    echo "[4/6] Checking ROCm installation..."

    ROCM_PATH=""
    for path in /opt/rocm /usr/lib/rocm /opt/rocm-6.2.0; do
        if [ -d "$path" ]; then
            ROCM_PATH="$path"
            break
        fi
    done

    if [ -n "$ROCM_PATH" ]; then
        echo "  ✓ ROCm found at $ROCM_PATH"
        export PATH="$ROCM_PATH/bin:$PATH"
        export LD_LIBRARY_PATH="$ROCM_PATH/lib:$ROCM_PATH/lib64:$LD_LIBRARY_PATH"

        # Detect GFX version
        GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-10.3.0}"
        echo "  Using HSA_OVERRIDE_GFX_VERSION=$GFX_VERSION"
        export HSA_OVERRIDE_GFX_VERSION="$GFX_VERSION"

        # Check for /dev/kfd
        if [ ! -e /dev/kfd ]; then
            echo "  ⚠ /dev/kfd not found. ROCm may not work."
            echo "    Add yourself to the 'video' and 'render' groups:"
            echo "    sudo usermod -aG video,render $USER"
        fi
    else
        echo "  ⚠ ROCm not installed. Installing..."
        echo ""
        echo "  For Ubuntu:"
        echo "    sudo apt-get install -y wget"
        echo "    wget https://repo.radeon.com/amdgpu-install/6.2/ubuntu/jammy/amdgpu-install_6.2.60200-1_all.deb"
        echo "    sudo apt-get install ./amdgpu-install_6.2.60200-1_all.deb"
        echo "    sudo amdgpu-install --usecase=rocm"
        echo ""
        echo "  For Fedora:"
        echo "    sudo dnf install rocm ROCm"
        echo ""
        echo "  For Arch:"
        echo "    sudo pacman -S rocm-hip-sdk"
        echo ""
        echo "  Falling back to ONNX-CPU for now..."
    fi
else
    echo ""
    echo "[4/6] Skipping ROCm setup (non-AMD GPU)"
fi

# ─── Clone & Install ─────────────────────────────────────

echo ""
echo "[5/6] Cloning Voidmap..."
rm -rf "$INSTALL_DIR"
git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo ""
echo "  Creating venv..."
$PYTHON -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

echo "  Upgrading pip..."
pip install --upgrade pip

echo ""
echo "[6/6] Installing PyTorch and dependencies..."

case "$GPU_VENDOR" in
    nvidia)
        echo "  Installing PyTorch CUDA..."
        pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
        ;;
    amd)
        echo "  Installing PyTorch ROCm..."
        if [ -n "$ROCM_PATH" ]; then
            pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm6.2
        else
            echo "  ROCm not found, falling back to PyTorch CPU + ONNX..."
            pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
        fi
        ;;
    intel)
        echo "  Installing PyTorch CPU + ONNX DirectML..."
        pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
        pip install onnxruntime-directml
        ;;
    cpu)
        echo "  Installing PyTorch CPU..."
        pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
        ;;
esac

echo "  Installing ONNX Runtime (cross-platform fallback)..."
pip install onnxruntime onnx

echo "  Installing package in editable mode..."
pip install -e ".[data]"

# ─── Verify ──────────────────────────────────────────────

echo ""
echo "Verifying installation..."
$PYTHON -c "
from voidmap_miner import detect
hw = detect()
print(f'  GPU: {hw.gpu_name} ({hw.gpu.value})')
print(f'  Backend: {hw.backend.value}')
print(f'  PyTorch: {hw.pytorch_version or \"—\"}')
print(f'  ONNX: {hw.onnx_version or \"—\"}')
"

# ─── Create Wrapper ──────────────────────────────────────

cat > "$HOME/.local/bin/voidmap" << EOF
#!/bin/bash
source "$VENV_DIR/bin/activate"
cd "$INSTALL_DIR"
exec $PYTHON -m voidmap_miner.tui "\$@"
EOF
mkdir -p "$HOME/.local/bin"
chmod +x "$HOME/.local/bin/voidmap"
echo ""
echo "  Created wrapper: ~/.local/bin/voidmap"

# ─── Done ────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Installation Complete!                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Quick start:"
echo ""
echo "    # Add to PATH (one-time)"
echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
echo "    # Detect GPU"
echo "    voidmap --detect"
echo ""
echo "    # Start mining (TUI)"
echo "    voidmap --task exoplanet"
echo ""
echo "    # Or non-TUI"
echo "    voidmap-mine --task exoplanet --rounds 10"
echo ""
echo "  Submit on-chain:"
echo ""
echo "    voidmap-mine --task exoplanet --rounds 10 --submit \\"
echo "      --rpc https://mainnet.base.org --pk \$YOUR_PK"
echo ""
echo "  Add \$HOME/.local/bin to your shell rc (~/.bashrc) for permanent access."
echo ""
echo "  Docs: https://github.com/thekillsquad007/voidmap"
