"""Hardware detection + ML backend selection for Voidmap miner.

Backend priority (auto-selected):
    1. PyTorch CUDA (NVIDIA)
    2. PyTorch ROCm (AMD)
    3. ONNX DirectML (Intel/AMD on Windows)
    4. ONNX CUDA (NVIDIA via ONNX)
    5. ONNX CPU (always works)
    6. PyTorch CPU (last resort)
"""
from __future__ import annotations

import os
import platform
import shutil
import subprocess
import psutil
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class Backend(Enum):
    PYTORCH_CUDA = "pytorch-cuda"
    PYTORCH_ROCM = "pytorch-rocm"
    PYTORCH_MPS = "pytorch-mps"
    PYTORCH_CPU = "pytorch-cpu"
    ONNX_CUDA = "onnx-cuda"
    ONNX_ROCM = "onnx-rocm"
    ONNX_DML = "onnx-dml"
    ONNX_CPU = "onnx-cpu"
    NONE = "none"


class GPU(Enum):
    NVIDIA = "nvidia"
    AMD = "amd"
    INTEL = "intel"
    APPLE = "apple"
    NONE = "none"


@dataclass
class HardwareInfo:
    """Detected hardware + selected backend."""
    gpu: GPU
    gpu_name: str
    backend: Backend
    pytorch_version: Optional[str]
    onnx_version: Optional[str]
    onnx_providers: list[str] = field(default_factory=list)
    platform: str = ""
    is_hiveos: bool = False
    notes: list[str] = field(default_factory=list)

    def __str__(self) -> str:
        s = f"GPU: {self.gpu_name} ({self.gpu.value})\n"
        s += f"Backend: {self.backend.value}\n"
        if self.pytorch_version:
            s += f"PyTorch: {self.pytorch_version}\n"
        if self.onnx_version:
            s += f"ONNX Runtime: {self.onnx_version}\n"
        if self.onnx_providers:
            s += f"ONNX Providers: {', '.join(self.onnx_providers)}\n"
        s += f"Platform: {self.platform}"
        if self.is_hiveos:
            s += " (HiveOS)"
        return s

    def is_system_idle(self, cpu_threshold: float = 15.0, gpu_threshold: float = 10.0) -> bool:
        """Check if the system is idle enough to mine.
        Returns True if CPU and GPU usage are below thresholds.
        """
        cpu_usage = psutil.cpu_percent(interval=0.1)
        if cpu_usage > cpu_threshold:
            return False
        
        # GPU usage detection (backend dependent)
        if self.gpu == GPU.NVIDIA:
            try:
                # Use nvidia-smi to get utilization
                out = subprocess.check_output(
                    ["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"],
                    timeout=2, stderr=subprocess.DEVNULL
                ).decode().strip()
                if float(out.split("\n")[0]) > gpu_threshold:
                    return False
            except Exception:
                pass
        elif self.gpu == GPU.AMD:
            try:
                # Use rocm-smi
                rocm_smi = shutil.which("rocm-smi") or "/opt/rocm/bin/rocm-smi"
                out = subprocess.check_output(
                    [rocm_smi, "--showuse"],
                    timeout=2, stderr=subprocess.DEVNULL
                ).decode()
                # Parse "GPU Use: 5%"
                for line in out.split("\n"):
                    if "GPU Use" in line:
                        usage = float(line.split(":")[1].strip().replace("%", ""))
                        if usage > gpu_threshold:
                            return False
            except Exception:
                pass
        
        return True


def _detect_gpu() -> tuple[GPU, str]:
    """Detect the primary GPU. Returns (gpu_type, gpu_name)."""
    system = platform.system()

    # Try nvidia-smi first
    nvidia_smi = shutil.which("nvidia-smi")
    if nvidia_smi:
        try:
            out = subprocess.check_output(
                [nvidia_smi, "--query-gpu=name", "--format=csv,noheader"],
                timeout=5,
                stderr=subprocess.DEVNULL,
            ).decode().strip().split("\n")[0]
            return GPU.NVIDIA, out
        except Exception:
            pass

    # Try rocm-smi
    rocm_smi = shutil.which("rocm-smi") or shutil.which("/opt/rocm/bin/rocm-smi")
    if rocm_smi:
        try:
            out = subprocess.check_output(
                [rocm_smi, "--showproductname"],
                timeout=5,
                stderr=subprocess.DEVNULL,
            ).decode()
            for line in out.split("\n"):
                if "Card" in line and ":" in line:
                    return GPU.AMD, line.split(":", 1)[1].strip()
        except Exception:
            pass

    # Try lspci (Linux)
    if system == "Linux":
        lspci = shutil.which("lspci")
        if lspci:
            try:
                out = subprocess.check_output(
                    [lspci, "-mm"],
                    timeout=5,
                    stderr=subprocess.DEVNULL,
                ).decode().lower()
                for line in out.split("\n"):
                    if "vga" in line or "3d" in line:
                        if "nvidia" in line:
                            return GPU.NVIDIA, line.split('"')[3] if '"' in line else "NVIDIA"
                        if "amd" in line or "radeon" in line or "ati" in line:
                            return GPU.AMD, line.split('"')[3] if '"' in line else "AMD"
                        if "intel" in line:
                            return GPU.INTEL, line.split('"')[3] if '"' in line else "Intel"
            except Exception:
                pass

    # Apple Silicon
    if system == "Darwin" and platform.machine() == "arm64":
        return GPU.APPLE, "Apple Silicon"

    # Fallback: try PyTorch
    try:
        import torch
        if torch.cuda.is_available():
            return GPU.NVIDIA, torch.cuda.get_device_name(0)
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return GPU.APPLE, "Apple Silicon"
    except Exception:
        pass

    return GPU.NONE, "CPU only"


def _select_backend(gpu: GPU, gpu_name: str, notes: list[str]) -> tuple[Backend, str, list[str]]:
    """Select the best backend. Returns (backend, version, providers)."""
    # 1. Try PyTorch
    pytorch_version = None
    pytorch_has_cuda = False
    pytorch_has_rocm = False
    pytorch_has_mps = False
    try:
        import torch
        pytorch_version = torch.__version__
        pytorch_has_cuda = torch.cuda.is_available()
        pytorch_has_rocm = pytorch_version and "+rocm" in pytorch_version
        pytorch_has_mps = (
            hasattr(torch.backends, "mps") and torch.backends.mps.is_available()
        )
    except ImportError:
        notes.append("PyTorch not installed (pip install torch)")

    if gpu == GPU.NVIDIA and pytorch_has_cuda and not pytorch_has_rocm:
        return Backend.PYTORCH_CUDA, pytorch_version, []

    if gpu == GPU.AMD and pytorch_has_rocm:
        return Backend.PYTORCH_ROCM, pytorch_version, []

    if gpu == GPU.APPLE and pytorch_has_mps:
        return Backend.PYTORCH_MPS, pytorch_version, []

    # 2. Try ONNX Runtime
    onnx_version = None
    providers = []
    try:
        import onnxruntime as ort
        onnx_version = ort.__version__
        providers = ort.get_available_providers()
    except ImportError:
        notes.append("ONNX Runtime not installed (pip install onnxruntime)")

    if gpu == GPU.INTEL and "DmlExecutionProvider" in providers:
        return Backend.ONNX_DML, onnx_version, providers

    if gpu == GPU.NVIDIA and "CUDAExecutionProvider" in providers:
        return Backend.ONNX_CUDA, onnx_version, providers

    if gpu == GPU.AMD and "ROCMExecutionProvider" in providers:
        return Backend.ONNX_ROCM, onnx_version, providers

    if "CPUExecutionProvider" in providers:
        return Backend.ONNX_CPU, onnx_version, providers

    # 3. PyTorch CPU fallback
    if pytorch_version:
        return Backend.PYTORCH_CPU, pytorch_version, []

    return Backend.NONE, "", []


def detect_hardware(force: bool = False) -> HardwareInfo:
    """Detect hardware and select the best backend.

    Cached after first call unless force=True.
    """
    if not force and hasattr(detect_hardware, "_cache"):
        return detect_hardware._cache  # type: ignore[attr-defined]

    notes: list[str] = []
    gpu, gpu_name = _detect_gpu()
    backend, version, providers = _select_backend(gpu, gpu_name, notes)

    pytorch_version = None
    onnx_version = None
    if backend in (Backend.PYTORCH_CUDA, Backend.PYTORCH_ROCM, Backend.PYTORCH_MPS, Backend.PYTORCH_CPU):
        pytorch_version = version
    elif backend in (Backend.ONNX_CUDA, Backend.ONNX_ROCM, Backend.ONNX_DML, Backend.ONNX_CPU):
        onnx_version = version

    is_hiveos = os.path.exists("/hive") or os.path.exists("/hive-config") or "hive" in platform.release().lower()

    info = HardwareInfo(
        gpu=gpu,
        gpu_name=gpu_name,
        backend=backend,
        pytorch_version=pytorch_version,
        onnx_version=onnx_version,
        onnx_providers=providers,
        platform=platform.platform(),
        is_hiveos=is_hiveos,
        notes=notes,
    )
    detect_hardware._cache = info  # type: ignore[attr-defined]
    return info
