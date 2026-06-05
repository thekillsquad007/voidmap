#!/bin/bash
# Voidmap Miner - HiveOS Installer
# Run as root on HiveOS: bash <(curl -s https://raw.githubusercontent.com/thekillsquad007/voidmap/main/install_hiveos.sh)

set -e

REPO_URL="https://github.com/thekillsquad007/voidmap.git"
INSTALL_DIR="/opt/voidmap-miner"
VENV_DIR="$INSTALL_DIR/venv"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Voidmap Miner - HiveOS Installer                  ║"
echo "║   Proof of Useful Work: Real astronomy data → VOID tokens   ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

# Detect GPU
echo ""
echo "[1/7] Detecting GPU..."
if lspci | grep -qi nvidia; then
    GPU_VENDOR="NVIDIA"
    GPU_NAME=$(lspci | grep -i nvidia | head -1 | cut -d: -f3- | xargs)
    echo "  Found: $GPU_NAME (NVIDIA)"
elif lspci | grep -qiE 'amd|radeon'; then
    GPU_VENDOR="AMD"
    GPU_NAME=$(lspci | grep -iE 'amd|radeon' | grep -i vga | head -1 | cut -d: -f3- | xargs)
    echo "  Found: $GPU_NAME (AMD)"
elif lspci | grep -qi intel; then
    GPU_VENDOR="INTEL"
    GPU_NAME=$(lspci | grep -i intel | grep -i vga | head -1 | cut -d: -f3- | xargs)
    echo "  Found: $GPU_NAME (Intel)"
else
    GPU_VENDOR="CPU"
    GPU_NAME="None detected"
    echo "  No GPU found - will run on CPU"
fi

# Install system dependencies
echo ""
echo "[2/7] Installing system dependencies..."
apt-get update
apt-get install -y python3 python3-pip python3-venv git wget curl \
    libglib2.0-0 libsm6 libxext6 libxrender-dev libgl1-mesa-glx \
    libnuma1 libpciaccess0 2>/dev/null

# ROCm setup for AMD
if [ "$GPU_VENDOR" = "AMD" ]; then
    echo "[3/7] Setting up ROCm for AMD GPU..."
    # HiveOS usually has ROCm pre-installed at /opt/rocm
    if [ -d /opt/rocm ]; then
        echo "  ROCm found at /opt/rocm"
        export PATH="/opt/rocm/bin:$PATH"
        export LD_LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/lib64:$LD_LIBRARY_PATH"
        export HSA_OVERRIDE_GFX_VERSION="10.3.0"
        echo 'export PATH="/opt/rocm/bin:$PATH"' >> /etc/profile.d/rocm.sh
        echo 'export LD_LIBRARY_PATH="/opt/rocm/lib:/opt/rocm/lib64:$LD_LIBRARY_PATH"' >> /etc/profile.d/rocm.sh
        echo 'export HSA_OVERRIDE_GFX_VERSION="10.3.0"' >> /etc/profile.d/rocm.sh
    else
        echo "  WARNING: ROCm not found. Install HiveOS ROCm package or use Docker."
    fi
else
    echo "[3/7] Skipping ROCm setup (non-AMD GPU)"
fi

# Clone repository
echo ""
echo "[4/7] Cloning Voidmap repository..."
rm -rf "$INSTALL_DIR"
git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create virtual environment
echo ""
echo "[5/7] Creating Python virtual environment..."
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

# Upgrade pip
pip install --upgrade pip

# Install PyTorch based on GPU
echo ""
echo "[6/7] Installing PyTorch and dependencies..."
if [ "$GPU_VENDOR" = "NVIDIA" ]; then
    echo "  Installing PyTorch CUDA..."
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
elif [ "$GPU_VENDOR" = "AMD" ]; then
    echo "  Installing PyTorch ROCm..."
    pip install torch torchvision --index-url https://download.pytorch.org/whl/rocm6.2
else
    echo "  Installing PyTorch CPU..."
    pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
fi

# Install ONNX Runtime (works as fallback for all GPUs)
pip install onnxruntime onnx

# Install remaining requirements
pip install -r miner/requirements.txt

# Pre-cache model
echo ""
echo "[7/7] Pre-caching model weights..."
mkdir -p /root/.voidmap/models
python3 -c "
from huggingface_hub import hf_hub_download
try:
    hf_hub_download('sarojpatil16/exoplanet-transit-detector', 'model.safetensors', cache_dir='/root/.voidmap/models')
    print('  Model cached successfully')
except Exception as e:
    print(f'  Model cache warning: {e}')
"

# Create wrapper script
cat > /usr/local/bin/voidmap << 'EOF'
#!/bin/bash
source /opt/voidmap-miner/venv/bin/activate
cd /opt/voidmap-miner
exec python3 miner/voidmap_miner.py "$@"
EOF
chmod +x /usr/local/bin/voidmap

# Create systemd service for auto-start
cat > /etc/systemd/system/voidmap-miner.service << 'EOF'
[Unit]
Description=Voidmap Miner
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/voidmap-miner
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/voidmap-miner/venv/bin/python miner/voidmap_miner.py --task exoplanet --rounds 1000
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Installation Complete!                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Usage:"
echo "  voidmap --detect                    # Check GPU and backend"
echo "  voidmap --task exoplanet --rounds 1  # Single mining round"
echo "  voidmap --task galaxy --rounds 1     # Galaxy classification"
echo "  voidmap --task anomaly --rounds 1    # Anomaly detection"
echo ""
echo "For on-chain submission:"
echo "  voidmap --task exoplanet --rounds 1 --submit \\"
echo "      --rpc-url https://sepolia.base.org \\"
echo "      --pool-address 0x3768e25aFc129D4455e267819801f2b2914fA4A2 \\"
echo "      --private-key YOUR_PRIVATE_KEY"
echo ""
echo "To run as a service (auto-start on boot):"
echo "  systemctl enable --now voidmap-miner"
echo "  journalctl -u voidmap-miner -f    # View logs"
echo ""
echo "Results saved to: /root/.voidmap/results/"
echo ""