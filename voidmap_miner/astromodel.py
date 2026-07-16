"""AstroNetCNN — multi-branch 1D CNN for exoplanet transit detection.

Architecture matches sarojpatil16/exoplanet-transit-detector on HuggingFace:
  - 4 flux branches (global, local, odd, even) → 1D conv stacks
  - 1 scalar branch → MLP
  - Concatenate → MLP classifier
"""
from __future__ import annotations
import torch
import torch.nn as nn
from huggingface_hub import hf_hub_download
import os


class FluxBranch1D(nn.Module):
    """Single 1D CNN branch for flux processing."""

    def __init__(self, pool_len: int):
        super().__init__()
        self.block1 = nn.Sequential(
            nn.Conv1d(1, 8, kernel_size=5, padding=2),
            nn.BatchNorm1d(8),
            nn.ReLU(),
            nn.Conv1d(8, 8, kernel_size=5, padding=2),
            nn.BatchNorm1d(8),
            nn.ReLU(),
            nn.Conv1d(8, 8, kernel_size=5, padding=2),
            nn.BatchNorm1d(8),
            nn.ReLU(),
        )
        self.block2 = nn.Sequential(
            nn.Conv1d(8, 16, kernel_size=5, padding=2),
            nn.BatchNorm1d(16),
            nn.ReLU(),
            nn.Conv1d(16, 16, kernel_size=5, padding=2),
            nn.BatchNorm1d(16),
            nn.ReLU(),
            nn.Conv1d(16, 16, kernel_size=5, padding=2),
            nn.BatchNorm1d(16),
            nn.ReLU(),
        )
        self.pool = nn.AdaptiveAvgPool1d(1)
        self.fc = nn.Linear(16 * pool_len, 32)

    def forward(self, x):
        x = self.block1(x)
        x = self.block2(x)
        x = self.pool(x).squeeze(-1)
        x = self.fc(x)
        return x


class AstroNetCNN(nn.Module):
    """Multi-branch 1D CNN for exoplanet transit detection.

    Args:
        n_scalars: Number of scalar features (default 9)
        num_classes: Number of output classes (default 3: PLANET, FP, NO_SIGNAL)
    """

    def __init__(self, n_scalars: int = 9, num_classes: int = 3,
                 pool_lens: dict = None):
        super().__init__()
        if pool_lens is None:
            pool_lens = {"global": 50, "local": 20, "odd": 50, "even": 50}
        self.global_branch = FluxBranch1D(pool_lens["global"])
        self.local_branch = FluxBranch1D(pool_lens["local"])
        self.odd_branch = FluxBranch1D(pool_lens["odd"])
        self.even_branch = FluxBranch1D(pool_lens["even"])

        # Scalar branch
        self.scalar_norm = nn.BatchNorm1d(n_scalars)
        self.scalar_branch = nn.Sequential(
            nn.Linear(n_scalars, 32),
            nn.ReLU(),
        )

        # Classifier
        feat_dim = 32 * 4 + 32  # 4 flux branches * 32 + 32 scalar
        self.classifier = nn.Sequential(
            nn.Linear(feat_dim, 256),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(256, 256),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(256, 128),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(128, num_classes),
        )

    def forward(self, flux_global, flux_local, flux_odd, flux_even, scalars):
        fg = self.global_branch(flux_global)
        fl = self.local_branch(flux_local)
        fo = self.odd_branch(flux_odd)
        fe = self.even_branch(flux_even)
        sc = self.scalar_branch(self.scalar_norm(scalars))
        x = torch.cat([fg, fl, fo, fe, sc], dim=1)
        return self.classifier(x)

    def load_weights(self, repo_id: str = "sarojpatil16/exoplanet-transit-detector", filename: str = "model.pth"):
        """Download and load pre-trained weights from HuggingFace."""
        try:
            path = hf_hub_download(repo_id=repo_id, filename=filename)
            state_dict = torch.load(path, map_location="cpu")
            if "state_dict" in state_dict:
                state_dict = state_dict["state_dict"]
            clean_dict = {k.replace("module.", ""): v for k, v in state_dict.items()}
            self.load_state_dict(clean_dict, strict=False)
            return True
        except Exception as e:
            print(f"Weight load failed: {e}")
            return False
