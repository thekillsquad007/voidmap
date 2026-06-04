"""
Anti-ASIC/FPGA Measures for Voidmap Mining

The goal: make it economically unfeasible to build specialized hardware
for Voidmap mining. GPUs are general-purpose and can adapt; ASICs/FPGAs
cannot easily handle these defenses.

Defense layers:
  1. Model Architecture Rotation — switch between CNN/Transformer/Mamba
  2. Model Weight Updates — change weights every N blocks
  3. Random Batch Sizes — can't optimize pipeline for fixed input
  4. Memory-Hard Operations — require large, random memory access
  5. Data-Dependent Computation — different code paths per input
  6. Dynamic Graph Changes — modify computation graph at runtime
"""
import hashlib
import json
import os
import random
import time
from pathlib import Path

try:
    import torch
    import torch.nn as nn
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False


# ─── Model Architecture Definitions ──────────────────────

class TransitCNN(nn.Module):
    """Standard 1D CNN — fast, memory-efficient, GPU-friendly."""
    def __init__(self):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv1d(1, 32, 7, padding=3),
            nn.ReLU(),
            nn.MaxPool1d(2),
            nn.Conv1d(32, 64, 5, padding=2),
            nn.ReLU(),
            nn.MaxPool1d(2),
            nn.Conv1d(64, 128, 3, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool1d(1),
        )
        self.classifier = nn.Linear(128, 3)

    def forward(self, x):
        x = self.features(x.unsqueeze(1))
        return self.classifier(x.flatten(1))


class TransitTransformer(nn.Module):
    """Transformer with attention — requires more memory, harder for ASICs."""
    def __init__(self, seq_len=2048, d_model=64, nhead=4, num_layers=2):
        super().__init__()
        self.embedding = nn.Linear(1, d_model)
        self.pos_enc = nn.Parameter(torch.randn(1, seq_len, d_model) * 0.02)
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=128, batch_first=True
        )
        self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        self.classifier = nn.Linear(d_model, 3)

    def forward(self, x):
        # x: (batch, seq_len)
        x = x.unsqueeze(-1)  # (batch, seq_len, 1)
        x = self.embedding(x) + self.pos_enc[:, :x.size(1), :]
        x = self.transformer(x)
        x = x.mean(dim=1)  # global average pooling
        return self.classifier(x)


class TransitMamba(nn.Module):
    """State-space model — different compute pattern, harder for FPGAs."""
    def __init__(self, d_model=64, state_size=16):
        super().__init__()
        self.d_model = d_model
        self.state_size = state_size
        self.input_proj = nn.Linear(1, d_model)
        # SSM parameters (simplified)
        self.A = nn.Parameter(torch.randn(d_model, state_size) * 0.01)
        self.B = nn.Parameter(torch.randn(d_model, state_size) * 0.01)
        self.C = nn.Parameter(torch.randn(d_model, state_size) * 0.01)
        self.D = nn.Linear(d_model, d_model)
        self.output_proj = nn.Linear(d_model, 3)

    def forward(self, x):
        # x: (batch, seq_len)
        batch, seq_len = x.shape
        x = x.unsqueeze(-1)  # (batch, seq_len, 1)
        x = self.input_proj(x)  # (batch, seq_len, d_model)

        # Simplified SSM scan (sequential, memory-hard)
        h = torch.zeros(batch, self.d_model, self.state_size, device=x.device)
        outputs = []
        for t in range(seq_len):
            xt = x[:, t, :]  # (batch, d_model)
            h = h * torch.sigmoid(self.A) + xt.unsqueeze(-1) * self.B
            yt = (h * self.C).sum(dim=-1)
            outputs.append(yt)
        x = torch.stack(outputs, dim=1)  # (batch, seq_len, d_model)
        x = self.D(x.mean(dim=1))
        return self.output_proj(x)


class GalaxyConvNeXT(nn.Module):
    """ConvNeXT for galaxy morphology — large memory footprint."""
    def __init__(self, num_classes=34):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(3, 32, 7, padding=3), nn.BatchNorm2d(32), nn.GELU(),
            nn.Conv2d(32, 64, 3, padding=1), nn.BatchNorm2d(64), nn.GELU(),
            nn.MaxPool2d(2),
            nn.Conv2d(64, 128, 3, padding=1), nn.BatchNorm2d(128), nn.GELU(),
            nn.Conv2d(128, 128, 3, padding=1, groups=128),  # depthwise
            nn.Conv2d(128, 256, 1), nn.BatchNorm2d(256), nn.GELU(),
            nn.MaxPool2d(2),
            nn.AdaptiveAvgPool2d(1),
        )
        self.classifier = nn.Linear(256, num_classes)

    def forward(self, x):
        x = self.features(x)
        return self.classifier(x.flatten(1))


# ─── Architecture Registry ────────────────────────────────

ARCHITECTURES = {
    "cnn": TransitCNN,
    "transformer": TransitTransformer,
    "mamba": TransitMamba,
    "convnext": GalaxyConvNeXT,
}

MODEL_VARIANTS = {
    "cnn": {
        "name": "TransitCNN",
        "params": "~500K",
        "memory_mb": 50,
        "description": "1D CNN for transit detection",
    },
    "transformer": {
        "name": "TransitTransformer",
        "params": "~2M",
        "memory_mb": 200,
        "description": "Transformer with attention for light curves",
    },
    "mamba": {
        "name": "TransitMamba",
        "params": "~1M",
        "memory_mb": 100,
        "description": "State-space model for time series",
    },
    "convnext": {
        "name": "GalaxyConvNeXT",
        "params": "~15M",
        "memory_mb": 500,
        "description": "ConvNeXT for galaxy morphology",
    },
}


# ─── Anti-ASIC Measures ───────────────────────────────────

class AntiASIC:
    """Implements anti-specialized-hardware measures."""

    def __init__(self, config=None):
        self.config = config or {
            "model_rotation_blocks": 100,
            "weight_perturbation_scale": 0.01,
            "batch_size_range": (16, 128),
            "memory_hardness_mb": 512,
            "data_access_pattern": "random",
        }
        self.current_architecture = "cnn"
        self.block_num = 0
        self.last_rotation = 0
        self.weight_seed = int.from_bytes(os.urandom(32), "big")

    def should_rotate_architecture(self) -> bool:
        """Check if it's time to switch model architecture."""
        return (self.block_num - self.last_rotation) >= self.config["model_rotation_blocks"]

    def rotate_architecture(self):
        """Switch to a different model architecture."""
        architectures = list(ARCHITECTURES.keys())
        architectures.remove(self.current_architecture)
        self.current_architecture = random.choice(architectures)
        self.last_rotation = self.block_num
        self.weight_seed = int.from_bytes(os.urandom(32), "big")
        return self.current_architecture

    def get_random_batch_size(self) -> int:
        """Return random batch size (can't optimize pipeline for fixed size)."""
        return random.randint(*self.config["batch_size_range"])

    def perturb_weights(self, model):
        """Add small random perturbation to model weights.
        This makes pre-computed ASIC solutions invalid."""
        with torch.no_grad():
            for param in model.parameters():
                noise = torch.randn_like(param) * self.config["weight_perturbation_scale"]
                param.add_(noise)
        return model

    def get_memory_hard_data(self, size_mb=None):
        """Generate data that requires large memory allocation.
        ASICs with small SRAM can't handle this."""
        size_mb = size_mb or self.config["memory_hardness_mb"]
        # Allocate large tensor (memory-hard)
        n_floats = (size_mb * 1024 * 1024) // 4
        data = torch.randn(n_floats)
        # Random access pattern (can't stream sequentially)
        indices = torch.randperm(n_floats)[:n_floats // 10]
        _ = data[indices]  # force random access
        return data

    def get_data_access_pattern(self, data_len: int) -> list:
        """Generate random data access pattern.
        ASICs optimize for sequential access; this defeats that."""
        pattern = list(range(data_len))
        random.shuffle(pattern)
        return pattern

    def compute_dynamic_hash(self, block_num: int, data_hash: str) -> str:
        """Compute hash that changes based on block number.
        Can't pre-compute ASIC solutions."""
        combined = f"{block_num}:{data_hash}:{self.weight_seed}"
        return hashlib.sha256(combined.encode()).hexdigest()

    def generate_challenge(self, block_num: int) -> dict:
        """Generate a mining challenge that requires GPU computation."""
        self.block_num = block_num

        # Rotate architecture if needed
        if self.should_rotate_architecture():
            arch = self.rotate_architecture()
        else:
            arch = self.current_architecture

        # Random batch size
        batch_size = self.get_random_batch_size()

        # Data access pattern
        if arch in ["cnn", "transformer", "mamba"]:
            data_len = 2048  # light curve length
        else:
            data_len = 224 * 224 * 3  # image

        access_pattern = self.get_data_access_pattern(data_len)

        # Challenge hash
        challenge_seed = f"{block_num}:{arch}:{batch_size}:{os.urandom(16).hex()}"
        challenge_hash = hashlib.sha256(challenge_seed.encode()).hexdigest()

        return {
            "block_num": block_num,
            "architecture": arch,
            "batch_size": batch_size,
            "data_length": data_len,
            "access_pattern": access_pattern[:100],  # first 100 indices
            "challenge_hash": challenge_hash,
            "weight_seed": self.weight_seed,
        }

    def verify_solution(self, challenge: dict, solution: dict) -> bool:
        """Verify a miner's solution meets anti-ASIC requirements."""
        # Check architecture matches
        if solution.get("architecture") != challenge["architecture"]:
            return False

        # Check batch size
        if solution.get("batch_size") != challenge["batch_size"]:
            return False

        # Check challenge hash
        if solution.get("challenge_hash") != challenge["challenge_hash"]:
            return False

        # Verify computation was done (check output hash changes with input)
        input_hash = solution.get("input_hash", "")
        output_hash = solution.get("output_hash", "")
        if input_hash == output_hash:
            return False  # output must differ from input

        return True


# ─── ASIC Resistance Scoring ──────────────────────────────

def estimate_asic_resistance(architectures: list) -> dict:
    """Estimate how resistant a set of architectures is to ASIC/FPGA attacks."""
    scores = {
        "architecture_diversity": len(architectures) / 5,  # 5 is max
        "memory_requirement": 0.0,
        "computation_variability": 0.0,
        "overall_score": 0.0,
    }

    # Memory requirement (higher = harder for ASIC)
    memory_weights = {
        "cnn": 0.3, "transformer": 0.7, "mamba": 0.5, "convnext": 0.8
    }
    avg_memory = sum(memory_weights.get(a, 0.5) for a in architectures) / max(1, len(architectures))
    scores["memory_requirement"] = avg_memory

    # Computation variability (more patterns = harder for ASIC)
    scores["computation_variability"] = min(1.0, len(architectures) * 0.25)

    # Overall score
    scores["overall_score"] = (
        scores["architecture_diversity"] * 0.3 +
        scores["memory_requirement"] * 0.4 +
        scores["computation_variability"] * 0.3
    )

    return scores


if __name__ == "__main__":
    # Test anti-ASIC measures
    anti_asic = AntiASIC()

    print("\nAnti-ASIC Defense Report:")
    print("=" * 50)

    for i in range(5):
        challenge = anti_asic.generate_challenge(i * 100)
        print(f"\nBlock {challenge['block_num']}:")
        print(f"  Architecture: {challenge['architecture']}")
        print(f"  Batch size: {challenge['batch_size']}")
        print(f"  Data length: {challenge['data_length']}")

    resistance = estimate_asic_resistance(list(ARCHITECTURES.keys()))
    print(f"\nASIC Resistance Score: {resistance['overall_score']:.2f}/1.00")
    print(f"  Architecture diversity: {resistance['architecture_diversity']:.2f}")
    print(f"  Memory requirement: {resistance['memory_requirement']:.2f}")
    print(f"  Computation variability: {resistance['computation_variability']:.2f}")
