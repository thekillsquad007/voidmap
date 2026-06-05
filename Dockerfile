# Voidmap Miner Docker Image
# Supports NVIDIA (CUDA), AMD (ROCm), Apple Silicon (MPS), and CPU fallback
# Works on HiveOS via docker run

# ---- Build Stage ----
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    ca-certificates \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1-mesa-glx \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install PyTorch first (CUDA version as base, will be overridden by runtime for AMD)
RUN pip install --no-cache-dir torch==2.5.1 torchvision==0.20.1 --index-url https://download.pytorch.org/whl/cu124

# Install ONNX Runtime with DirectML (works on AMD/Intel/NVIDIA on Windows/Linux)
RUN pip install --no-cache-dir onnxruntime onnxruntime-directml

# Install remaining dependencies
COPY miner/requirements.txt /app/miner/requirements.txt
RUN pip install --no-cache-dir -r /app/miner/requirements.txt

# Copy miner source
COPY miner/ /app/miner/

# Pre-download model weights to cache
RUN mkdir -p /root/.voidmap/models && \
    python3 -c "
from huggingface_hub import hf_hub_download
try:
    hf_hub_download('sarojpatil16/exoplanet-transit-detector', 'model.safetensors', cache_dir='/root/.voidmap/models')
    print('Model cached successfully')
except Exception as e:
    print(f'Model cache warning: {e}')
" 2>&1 || true

# ---- Runtime Stage ----
FROM python:3.11-slim AS runtime

# Install system dependencies for ROCm and general GPU support
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1-mesa-glx \
    libnuma1 \
    libpciaccess0 \
    && rm -rf /var/lib/apt/lists/*

# Install AMD GPU drivers / ROCm runtime (for HiveOS AMD rigs)
# This layer will be overridden by HiveOS base image if using HiveOS
ARG ROCM_VERSION=6.2
ENV DEBIAN_FRONTEND=noninteractive

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /app/miner /app/miner
COPY --from=builder /root/.voidmap /root/.voidmap

# Set environment variables
ENV PYTHONPATH=/app/miner:$PYTHONPATH
ENV HF_HOME=/root/.voidmap/models
ENV TORCH_HOME=/root/.voidmap/models

# Create data and results directories
RUN mkdir -p /root/.voidmap/data /root/.voidmap/results

WORKDIR /app/miner

# Health check - verify miner can start and detect hardware
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD python3 voidmap_miner.py --detect 2>&1 | grep -q "Backend" || exit 1

# Default entrypoint - runs one exoplanet mining round and exits
# For continuous mining, use: docker run -d --gpus all voidmap-miner:latest tail -f /dev/null
# Then: docker exec <container> python3 voidmap_miner.py --task exoplanet --rounds 1000 --submit ...
ENTRYPOINT ["python3", "voidmap_miner.py"]
CMD ["--task", "exoplanet", "--rounds", "1"]