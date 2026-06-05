#!/usr/bin/env python3
"""
Multi-backend GPU support for Voidmap Miner.

Backend priority (first available wins):
1. PyTorch CUDA (NVIDIA GPUs)
2. PyTorch ROCm/HIP (AMD GPUs — via rocm PyTorch wheel)
3. ONNX Runtime DirectML (AMD/Intel/NVIDIA on Windows + Linux)
4. ONNX Runtime CPU (fallback everywhere)
5. PyTorch CPU (final fallback)

Usage:
    from model_backend import ModelBackend
    backend = ModelBackend.auto()
    result = backend.predict_transit(flux_global, flux_local, flux_odd, flux_even, scalars)
"""
import hashlib, json, os, subprocess, sys, time
from pathlib import Path

HAS_TORCH = False
try:
    import torch
    import torch.nn as nn
    import numpy as np
    HAS_TORCH = True
except Exception:
    pass

HAS_ONNX = False
try:
    import onnxruntime as ort
    HAS_ONNX = True
except Exception:
    pass

HAS_DML = False
try:
    if HAS_ONNX and "DmlExecutionProvider" in ort.get_available_providers():
        HAS_DML = True
except Exception:
    pass

HAS_ROCM = False
try:
    if HAS_TORCH and torch.cuda.is_available():
        for i in range(torch.cuda.device_count()):
            name = torch.cuda.get_device_name(i).lower()
            if "amd" in name or "radeon" in name or "rx " in name or "navi" in name:
                HAS_ROCM = True
                break
    if HAS_TORCH and hasattr(torch.backends, "hip") and torch.backends.hip.is_available():
        HAS_ROCM = True
except Exception:
    pass

MODEL_CACHE = Path.home() / ".voidmap" / "models"
MODEL_CACHE.mkdir(parents=True, exist_ok=True)

ONNX_MODEL_PATH = Path(__file__).parent / "astronet_cnn.onnx"


class FluxBranch1D(nn.Module):
    def __init__(self, pool_len):
        super().__init__()
        self.block1 = nn.Sequential(
            nn.Conv1d(1, 8, 5, padding=2), nn.BatchNorm1d(8), nn.ReLU(),
            nn.Conv1d(8, 8, 5, padding=2), nn.BatchNorm1d(8), nn.ReLU(),
            nn.Conv1d(8, 8, 5, padding=2), nn.BatchNorm1d(8),
        )
        self.block2 = nn.Sequential(
            nn.Conv1d(8, 16, 5, padding=2), nn.BatchNorm1d(16), nn.ReLU(),
            nn.Conv1d(16, 16, 5, padding=2), nn.BatchNorm1d(16), nn.ReLU(),
            nn.Conv1d(16, 16, 5, padding=2), nn.BatchNorm1d(16),
        )
        self.pool = nn.AdaptiveAvgPool1d(pool_len)
        self.fc = nn.Sequential(nn.Linear(16 * pool_len, 32))

    def forward(self, x):
        x = x.unsqueeze(1)
        x = self.block1(x)
        x = self.block2(x)
        x = self.pool(x)
        x = x.flatten(1)
        return self.fc(x)


class AstroNetCNN(nn.Module):
    def __init__(self, n_scalars=9, num_classes=3):
        super().__init__()
        self.even_branch = FluxBranch1D(50)
        self.global_branch = FluxBranch1D(50)
        self.local_branch = FluxBranch1D(20)
        self.odd_branch = FluxBranch1D(50)
        self.scalar_norm = nn.BatchNorm1d(n_scalars)
        self.scalar_branch = nn.Sequential(nn.Linear(n_scalars, 32))
        self.classifier = nn.Sequential(
            nn.Linear(160, 256), nn.ReLU(), nn.Dropout(0.3),
            nn.Linear(256, 256), nn.ReLU(), nn.Dropout(0.3),
            nn.Linear(256, 128), nn.ReLU(), nn.Dropout(0.3),
            nn.Linear(128, num_classes),
        )

    def forward(self, flux_global, flux_local, flux_odd, flux_even, scalars):
        e = self.even_branch(flux_even)
        g = self.global_branch(flux_global)
        l = self.local_branch(flux_local)
        o = self.odd_branch(flux_odd)
        s = self.scalar_branch(self.scalar_norm(scalars))
        s = torch.relu(s)
        combined = torch.cat([e, g, l, o, s], dim=1)
        return self.classifier(combined)


def _detect_gpu_vendor():
    """Return (vendor, name, device_str) for best available GPU."""
    if not HAS_TORCH:
        if HAS_DML:
            return ("AMD/Intel", "DirectML GPU", "dml")
        return ("CPU", "CPU", "cpu")

    if torch.cuda.is_available():
        name = torch.cuda.get_device_name(0)
        lower = name.lower()
        if any(k in lower for k in ("amd", "radeon", "rx ", "navi", "gfx")):
            return ("AMD", name, "cuda")
        return ("NVIDIA", name, "cuda")

    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return ("Apple", "Apple Silicon", "mps")

    if HAS_DML:
        return ("AMD/Intel", "DirectML GPU", "dml")

    return ("CPU", "CPU", "cpu")


def is_fpga_platform(gpu_name):
    lower = (gpu_name or "").lower()
    return any(f in lower for f in ("emulated", "fpga", "simulated", "virtual", "software renderer"))


class PyTorchBackend:
    name = "PyTorch"

    def __init__(self, device_str="cpu"):
        self.device = torch.device(device_str) if HAS_TORCH else None
        self.model = None

    def load_transit_model(self):
        if not HAS_TORCH:
            return False
        self.model = AstroNetCNN(n_scalars=9, num_classes=3).to(self.device)
        try:
            from huggingface_hub import hf_hub_download
            from safetensors.torch import load_file
            model_path = hf_hub_download("sarojpatil16/exoplanet-transit-detector", "model.safetensors")
            weights = load_file(model_path)
            self.model.load_state_dict(weights)
        except Exception:
            try:
                from huggingface_hub import hf_hub_download
                path = hf_hub_download("sarojpatil16/exoplanet-transit-detector", "model_state_dict.pt")
                sd = torch.load(path, map_location="cpu", weights_only=True)
                self.model.load_state_dict(sd)
            except Exception:
                pass
        self.model.eval()
        return True

    def predict_transit(self, flux_global, flux_local, flux_odd, flux_even, scalars):
        if self.model is None:
            return None
        t = lambda a: torch.tensor(a, dtype=torch.float32).unsqueeze(0).to(self.device)
        with torch.no_grad():
            logits = self.model(t(flux_global), t(flux_local), t(flux_odd), t(flux_even), t(scalars))
            probs = torch.softmax(logits, dim=-1)
        probs_np = probs.cpu().numpy().flatten()
        return probs_np

    def predict_galaxy(self, img_np):
        return None

    def predict_anomaly(self, features_np):
        return None


class ONNXBackend:
    name = "ONNX Runtime"

    def __init__(self, provider="CPUExecutionProvider"):
        self.provider = provider
        self.session = None

    def load_transit_model(self):
        if not HAS_ONNX:
            return False
        model_path = str(ONNX_MODEL_PATH) if ONNX_MODEL_PATH.exists() else None
        if model_path is None:
            return False
        providers = [self.provider, "CPUExecutionProvider"]
        try:
            sess_opts = ort.SessionOptions()
            sess_opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            self.session = ort.InferenceSession(model_path, sess_opts=sess_opts, providers=providers)
            return True
        except Exception:
            try:
                self.session = ort.InferenceSession(model_path, providers=["CPUExecutionProvider"])
                return True
            except Exception:
                return False

    def predict_transit(self, flux_global, flux_local, flux_odd, flux_even, scalars):
        if self.session is None:
            return None
        inputs = {
            "flux_global": np.array(flux_global, dtype=np.float32).reshape(1, -1),
            "flux_local": np.array(flux_local, dtype=np.float32).reshape(1, -1),
            "flux_odd": np.array(flux_odd, dtype=np.float32).reshape(1, -1),
            "flux_even": np.array(flux_even, dtype=np.float32).reshape(1, -1),
            "scalars": np.array(scalars, dtype=np.float32).reshape(1, -1),
        }
        out = self.session.run(None, inputs)
        logits = out[0]
        exp_logits = np.exp(logits - np.max(logits, axis=-1, keepdims=True))
        probs = exp_logits / exp_logits.sum(axis=-1, keepdims=True)
        return probs.flatten()


class ModelBackend:
    """Auto-selecting multi-backend inference engine."""

    def __init__(self, backend, gpu_vendor, gpu_name, device_str):
        self.backend = backend
        self.gpu_vendor = gpu_vendor
        self.gpu_name = gpu_name
        self.device_str = device_str

    @classmethod
    def auto(cls, force_backend=None):
        """Auto-detect best available backend."""
        vendor, gpu_name, device_str = _detect_gpu_vendor()

        if force_backend:
            return cls._make(force_backend, vendor, gpu_name, device_str)

        if HAS_TORCH and device_str in ("cuda", "mps"):
            return cls._make("pytorch", vendor, gpu_name, device_str)

        if HAS_DML:
            return cls._make("onnx_dml", "AMD/Intel", "DirectML GPU", "dml")

        if HAS_ONNX:
            return cls._make("onnx_cpu", "CPU", "CPU", "cpu")

        if HAS_TORCH:
            return cls._make("pytorch", "CPU", "CPU", "cpu")

        return cls._make("none", "None", "None", "none")

    @classmethod
    def _make(cls, kind, vendor, gpu_name, device_str):
        if kind == "pytorch":
            b = PyTorchBackend(device_str)
        elif kind == "onnx_dml":
            b = ONNXBackend("DmlExecutionProvider")
        elif kind == "onnx_cpu":
            b = ONNXBackend("CPUExecutionProvider")
        else:
            b = None
        return cls(b, vendor, gpu_name, device_str)

    def load_transit_model(self):
        if self.backend is None:
            return False
        ok = self.backend.load_transit_model()
        if ok:
            print(f" Backend: {self.backend.name} ({self.gpu_name})")
        return ok

    def predict_transit(self, flux_global, flux_local, flux_odd, flux_even, scalars):
        if self.backend is None:
            return None
        return self.backend.predict_transit(flux_global, flux_local, flux_odd, flux_even, scalars)

    @property
    def has_gpu(self):
        return self.device_str not in ("cpu", "none")

    @property
    def info(self):
        return {
            "backend": self.backend.name if self.backend else "none",
            "gpu_vendor": self.gpu_vendor,
            "gpu_name": self.gpu_name,
            "device": self.device_str,
            "has_rocm": HAS_ROCM,
            "has_dml": HAS_DML,
            "has_onnx": HAS_ONNX,
            "has_torch": HAS_TORCH,
        }


def detect_hardware():
    """Backward-compatible wrapper returning (name, device_str, has_gpu)."""
    vendor, gpu_name, device_str = _detect_gpu_vendor()
    has_gpu = device_str not in ("cpu", "none")
    if vendor == "NVIDIA":
        return (f"NVIDIA {gpu_name}", device_str, has_gpu)
    if vendor == "AMD":
        return (f"AMD {gpu_name}", device_str, has_gpu)
    if vendor == "Apple":
        return (f"Apple {gpu_name}", device_str, has_gpu)
    if vendor == "AMD/Intel":
        return (f"{gpu_name} (DirectML)", device_str, has_gpu)
    return ("CPU", "cpu", False)


if __name__ == "__main__":
    b = ModelBackend.auto()
    print(f"\n Voidmap Backend Detection")
    print(f" Vendor  : {b.gpu_vendor}")
    print(f" GPU     : {b.gpu_name}")
    print(f" Device  : {b.device_str}")
    print(f" Backend : {b.backend.name if b.backend else 'none'}")
    print(f" ROCm    : {HAS_ROCM}")
    print(f" DirectML: {HAS_DML}")
    print(f" ONNX RT : {HAS_ONNX}")
    print(f" PyTorch : {HAS_TORCH}")

    if b.load_transit_model():
        fg = np.random.randn(201).astype(np.float32)
        fl = np.random.randn(81).astype(np.float32)
        fo = np.random.randn(201).astype(np.float32)
        fe = np.random.randn(201).astype(np.float32)
        sc = np.random.randn(9).astype(np.float32)
        probs = b.predict_transit(fg, fl, fo, fe, sc)
        if probs is not None:
            labels = ["PLANET", "FALSE_POSITIVE", "NO_SIGNAL"]
            pred = int(np.argmax(probs))
            print(f"\n Test prediction: {labels[pred]} ({probs[pred]:.2%})")
            print(f" All probs: {dict(zip(labels, probs))}")
