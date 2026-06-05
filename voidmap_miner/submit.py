"""On-chain submission of mining results to MiningPool contract."""
from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Optional

from .engine import MineResult


# Default contract addresses
DEFAULT_TOKEN_BASE = "0x8AF20228A724d7420434791EAEA5F7D037865d35"  # Base Sepolia
DEFAULT_POOL_BASE = "0x3768e25aFc129D4455e267819801f2b2914fA4A2"    # Base Sepolia


def _find_cast() -> str:
    """Find the cast binary (anvil/forge tool)."""
    candidates = [
        os.environ.get("CAST_BIN"),
        shutil_which("cast"),
        os.path.expanduser("~/.foundry/bin/cast"),
        os.path.expanduser("~/.var/app/ai.opencode.opencode/config/.foundry/bin/cast"),
        "/usr/local/bin/cast",
        "/usr/bin/cast",
    ]
    for c in candidates:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    # Last resort: assume on PATH
    return "cast"


def shutil_which(cmd: str) -> Optional[str]:
    import shutil
    return shutil.which(cmd)


def _run_cast(args: list[str], timeout: int = 30) -> str:
    cast = _find_cast()
    cmd = [cast] + args
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=True,
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"cast failed: {e.stderr}") from e
    except FileNotFoundError as e:
        raise RuntimeError(f"cast not found. Install Foundry: curl -L https://foundry.paradigm.xyz | bash") from e


def submit_result(result: MineResult, rpc: str, pk: str,
                  pool: Optional[str] = None,
                  ipfs_cid: Optional[str] = None) -> str:
    """Submit a mining result to the MiningPool contract.

    Returns the transaction hash.
    """
    if pool is None:
        pool = DEFAULT_POOL_BASE

    # Build parameters for submitWork()
    # (taskId, inputHash, outputHash, modelHash, ipfsCID, quality, samples, durationMs)
    task_id = 0  # Default task; in production, look up active task
    ipfs_cid = ipfs_cid or result.ipfs_cid or ""
    if not ipfs_cid:
        # Fall back to sha256 of the result file
        ipfs_cid = f"sha256:{result.output_hash.replace('0x', '')}"

    # Submit via cast
    args = [
        "send", pool, "submitWork((uint256,bytes32,bytes32,bytes32,string,uint256,uint256,uint256))",
        f"({task_id},{result.input_hash},{result.output_hash},{result.model_hash},\"{ipfs_cid}\",{result.quality_score},{result.samples},{result.duration_ms})",
        "--rpc-url", rpc,
        "--private-key", pk,
        "--json",
    ]
    output = _run_cast(args, timeout=120)

    try:
        tx = json.loads(output)
        return tx.get("transactionHash", "")
    except json.JSONDecodeError:
        # Plain text output
        return output


def query_balance(address: str, rpc: str, token: Optional[str] = None) -> str:
    """Query VOID token balance."""
    if token is None:
        token = DEFAULT_TOKEN_BASE
    return _run_cast([
        "call", token, "balanceOf(address)(uint256)",
        address, "--rpc-url", rpc,
    ])


def query_pool_stats(pool: str, rpc: str) -> dict:
    """Query MiningPool stats."""
    out = {
        "submissionCount": _run_cast(["call", pool, "submissionCount()(uint256)", "--rpc-url", rpc]),
        "currentBlockReward": _run_cast(["call", pool, "getCurrentBlockReward()(uint256)", "--rpc-url", rpc]),
        "halvingEpoch": _run_cast(["call", pool, "getHalvingEpoch()(uint256)", "--rpc-url", rpc]),
    }
    return out
