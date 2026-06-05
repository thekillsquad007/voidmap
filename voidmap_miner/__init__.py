"""Voidmap GPU Miner — Real astronomical data, real ML models.

A one-command, Rich-powered TUI miner that processes real NASA/ESA/NSF data
and earns VOID tokens on Base L2.

Public API:
    mine(task, submit, ...)   — Mine in non-TUI mode
    MineEngine               — Programmatic mining engine
    HardwareInfo              — Detected hardware + backend
"""

__version__ = "0.1.0"

from .engine import MineEngine, MineResult, HardwareInfo
from .api import mine, list_targets, list_results, detect

__all__ = [
    "MineEngine",
    "MineResult",
    "HardwareInfo",
    "mine",
    "list_targets",
    "list_results",
    "detect",
]
