"""Public Python API for Voidmap mining — for programmatic use."""
from __future__ import annotations

from .engine import MineEngine, MineResult, KNOWN_TARGETS, RESULTS_DIR
from .hardware import detect_hardware, HardwareInfo, Backend, GPU


def mine(task: str = "exoplanet", rounds: int = 1, submit: bool = False,
         rpc: str = None, pk: str = None, target_idx: int = None,
         hw: HardwareInfo = None) -> list[MineResult]:
    """Mine N rounds. Returns list of MineResult.

    Simple Python API:

    ```python
    from voidmap_miner import mine

    results = mine("exoplanet", rounds=10)
    for r in results:
        print(f"{r.target}: {r.prediction} ({r.confidence:.1%})")
    ```
    """
    engine = MineEngine(hw=hw)
    results = []
    for _ in range(rounds):
        try:
            r = engine.mine_one(task, target_idx=target_idx)
            r.save()
            if submit and rpc and pk:
                try:
                    from .submit import submit_result
                    tx = submit_result(r, rpc, pk)
                    r.extra["tx_hash"] = tx
                except Exception:
                    pass
            results.append(r)
        except Exception as e:
            print(f"Mining error: {e}")
    return results


def list_targets() -> list[dict]:
    """Return list of known TESS exoplanet targets."""
    return KNOWN_TARGETS


def list_results(limit: int = 20) -> list[dict]:
    """Return recent mining results from disk."""
    import json
    results = []
    for f in sorted(RESULTS_DIR.glob("*.json"), reverse=True)[:limit]:
        with open(f) as fp:
            results.append(json.load(fp))
    return results


def detect() -> HardwareInfo:
    """Detect hardware + best backend."""
    return detect_hardware(force=True)


__all__ = ["mine", "list_targets", "list_results", "detect", "MineEngine", "MineResult"]
