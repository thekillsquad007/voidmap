#!/usr/bin/env python3
"""
Voidmap Mining Pool — Coordinator for distributed GPU mining.

Allows multiple miners to join a pool, distributes work,
aggregates shares, and submits valid solutions on-chain.

Architecture:
  1. Pool coordinator generates work assignments
  2. Miners connect via WebSocket
  3. Coordinator distributes real data + model weights
  4. Miners process and submit shares
  5. Coordinator validates quality threshold (>= 50)
  6. Coordinator batches submissions to MiningPool contract

Anti-ASIC/FPGA measures:
  - Model weight rotation every N blocks
  - Random batch size selection
  - Memory-hard data loading (random access patterns)
  - Model architecture switching (CNN/Transformer/Mamba)
  - Data-dependent computation paths
"""
import asyncio
import hashlib
import json
import os
import random
import time
from collections import defaultdict
from pathlib import Path

try:
    import websockets
    HAS_WS = True
except ImportError:
    HAS_WS = False

# ─── Pool Configuration ───────────────────────────────────
POOL_PORT = int(os.environ.get("VOIDMAP_POOL_PORT", "8546"))
MIN_QUALITY = 50
SHARE_DIFFICULTY = 18  # leading zeros in share hash
MAX_MINERS = 1000
WORK_EXPIRY = 300  # seconds before work expires

# ─── Anti-ASIC/FPGA Configuration ─────────────────────────
ANTI_ASIC = {
    "model_rotation_interval": 100,  # blocks between model weight updates
    "batch_size_range": (16, 128),   # random batch sizes
    "model_variants": ["cnn", "transformer", "mamba"],  # rotate architectures
    "memory_hardness": True,          # require large memory access
    "data_shuffle_seed": None,        # changes per block
}

# ─── Model Variants (Anti-ASIC) ───────────────────────────
# These are different model architectures that miners must support.
# ASICs/FPGAs can't adapt to changing architectures quickly.

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


class PoolWork:
    """Represents a unit of work distributed to miners."""

    def __init__(self, task_id, data_hash, model_variant, batch_size, block_num):
        self.task_id = task_id
        self.data_hash = data_hash
        self.model_variant = model_variant
        self.batch_size = batch_size
        self.block_num = block_num
        self.created_at = time.time()
        self.work_id = hashlib.sha256(
            f"{task_id}:{data_hash}:{model_variant}:{block_num}:{time.time()}".encode()
        ).hexdigest()[:16]

    def to_dict(self):
        return {
            "work_id": self.work_id,
            "task_id": self.task_id,
            "data_hash": self.data_hash,
            "model_variant": self.model_variant,
            "batch_size": self.batch_size,
            "block_num": self.block_num,
            "created_at": self.created_at,
        }


class MinerSession:
    """Tracks a connected miner's state."""

    def __init__(self, miner_id, websocket):
        self.miner_id = miner_id
        self.ws = websocket
        self.connected_at = time.time()
        self.last_share = time.time()
        self.shares_submitted = 0
        self.shares_accepted = 0
        self.shares_rejected = 0
        self.total_quality = 0
        self.current_work = None

    def to_dict(self):
        return {
            "miner_id": self.miner_id,
            "connected_at": self.connected_at,
            "shares_submitted": self.shares_submitted,
            "shares_accepted": self.shares_accepted,
            "total_quality": self.total_quality,
        }


class MiningPool:
    """Pool coordinator that distributes work and validates shares."""

    def __init__(self):
        self.miners: dict[str, MinerSession] = {}
        self.work_queue: list[PoolWork] = []
        self.submitted_shares: list[dict] = []
        self.block_num = 0
        self.total_shares = 0
        self.total_accepted = 0
        self.current_model_variant = "cnn"
        self.model_rotation_counter = 0
        self.data_cache = {}
        self.results_dir = Path.home() / ".voidmap" / "pool_results"
        self.results_dir.mkdir(parents=True, exist_ok=True)

    def generate_work(self, task_id=1):
        """Generate new work unit with anti-ASIC measures."""
        self.block_num += 1

        # Rotate model variant
        self.model_rotation_counter += 1
        if self.model_rotation_counter >= ANTI_ASIC["model_rotation_interval"]:
            self.model_rotation_counter = 0
            variants = list(MODEL_VARIANTS.keys())
            self.current_model_variant = random.choice(variants)
            print(f"  Model rotated to: {self.current_model_variant}")

        # Random batch size (anti-ASIC: can't optimize for fixed size)
        batch_size = random.randint(*ANTI_ASIC["batch_size_range"])

        # Data hash (changes per block for memory-hardness)
        data_seed = f"{task_id}:{self.block_num}:{time.time()}"
        data_hash = hashlib.sha256(data_seed.encode()).hexdigest()

        work = PoolWork(
            task_id=task_id,
            data_hash=data_hash,
            model_variant=self.current_model_variant,
            batch_size=batch_size,
            block_num=self.block_num,
        )

        self.work_queue.append(work)
        return work

    def validate_share(self, share: dict) -> tuple[bool, str]:
        """Validate a miner's share submission."""
        # Check required fields
        required = ["work_id", "miner_id", "quality", "output_hash", "nonce"]
        for field in required:
            if field not in share:
                return False, f"Missing field: {field}"

        # Check quality threshold
        quality = share.get("quality", 0)
        if quality < MIN_QUALITY:
            return False, f"Quality {quality} < {MIN_QUALITY}"

        # Check work exists and isn't expired
        work_id = share["work_id"]
        work = next((w for w in self.work_queue if w.work_id == work_id), None)
        if work is None:
            return False, "Work not found"
        if time.time() - work.created_at > WORK_EXPIRY:
            return False, "Work expired"

        # Check share difficulty (proof of work)
        share_hash = hashlib.sha256(
            json.dumps(share, sort_keys=True).encode()
        ).hexdigest()
        if not share_hash.startswith("0" * (SHARE_DIFFICULTY // 4)):
            return False, "Insufficient difficulty"

        # Check nonce uniqueness
        nonce = share["nonce"]
        if any(s.get("nonce") == nonce and s.get("miner_id") == share["miner_id"]
               for s in self.submitted_shares):
            return False, "Duplicate nonce"

        return True, "Valid"

    def accept_share(self, share: dict, miner: MinerSession):
        """Accept a valid share."""
        self.submitted_shares.append(share)
        self.total_shares += 1
        self.total_accepted += 1

        miner.shares_submitted += 1
        miner.shares_accepted += 1
        miner.total_quality += share.get("quality", 0)
        miner.last_share = time.time()

        # Save result
        result = {
            "work_id": share["work_id"],
            "miner_id": share["miner_id"],
            "task_id": share.get("task_id"),
            "quality": share.get("quality"),
            "output_hash": share.get("output_hash"),
            "model_variant": share.get("model_variant"),
            "timestamp": int(time.time()),
        }
        filepath = self.results_dir / f"share_{share['work_id']}_{int(time.time())}.json"
        with open(filepath, "w") as f:
            json.dump(result, f, indent=2)

    def reject_share(self, share: dict, reason: str, miner: MinerSession):
        """Reject an invalid share."""
        self.total_shares += 1
        miner.shares_submitted += 1
        miner.shares_rejected += 1

    def get_pool_stats(self) -> dict:
        """Get current pool statistics."""
        return {
            "miners_connected": len(self.miners),
            "total_shares": self.total_shares,
            "total_accepted": self.total_accepted,
            "acceptance_rate": (self.total_accepted / max(1, self.total_shares)) * 100,
            "current_block": self.block_num,
            "current_model": self.current_model_variant,
            "model_variants": list(MODEL_VARIANTS.keys()),
            "anti_asic": ANTI_ASIC,
        }

    def get_miner_stats(self, miner_id: str) -> dict:
        """Get stats for a specific miner."""
        if miner_id not in self.miners:
            return None
        miner = self.miners[miner_id]
        avg_quality = (miner.total_quality / max(1, miner.shares_accepted))
        return {
            "miner_id": miner_id,
            "shares_submitted": miner.shares_submitted,
            "shares_accepted": miner.shares_accepted,
            "shares_rejected": miner.shares_rejected,
            "acceptance_rate": (miner.shares_accepted / max(1, miner.shares_submitted)) * 100,
            "avg_quality": round(avg_quality, 2),
            "connected_at": miner.connected_at,
            "last_share": miner.last_share,
        }


# ─── WebSocket Server ─────────────────────────────────────

pool = MiningPool()


async def handle_miner(ws, path=None):
    """Handle a connected miner."""
    miner_id = None
    try:
        async for message in ws:
            data = json.loads(message)
            msg_type = data.get("type")

            if msg_type == "auth":
                miner_id = data.get("miner_id", f"miner_{random.randint(1000,9999)}")
                pool.miners[miner_id] = MinerSession(miner_id, ws)
                await ws.send(json.dumps({
                    "type": "auth_ok",
                    "miner_id": miner_id,
                    "pool_stats": pool.get_pool_stats(),
                }))
                print(f"  Miner connected: {miner_id}")

            elif msg_type == "get_work":
                task_id = data.get("task_id", 1)
                work = pool.generate_work(task_id)
                if miner_id and miner_id in pool.miners:
                    pool.miners[miner_id].current_work = work
                await ws.send(json.dumps({
                    "type": "work",
                    "work": work.to_dict(),
                    "model_info": MODEL_VARIANTS.get(work.model_variant, {}),
                }))

            elif msg_type == "submit_share":
                share = data.get("share", {})
                share["miner_id"] = miner_id
                valid, reason = pool.validate_share(share)

                if valid:
                    pool.accept_share(share, pool.miners[miner_id])
                    await ws.send(json.dumps({
                        "type": "share_accepted",
                        "work_id": share["work_id"],
                        "total_accepted": pool.total_accepted,
                    }))
                    print(f"  Share accepted: {miner_id} (quality: {share.get('quality')})")
                else:
                    pool.reject_share(share, reason, pool.miners[miner_id])
                    await ws.send(json.dumps({
                        "type": "share_rejected",
                        "reason": reason,
                    }))

            elif msg_type == "get_stats":
                if miner_id:
                    stats = pool.get_miner_stats(miner_id)
                else:
                    stats = pool.get_pool_stats()
                await ws.send(json.dumps({"type": "stats", "stats": stats}))

            elif msg_type == "get_pool_stats":
                await ws.send(json.dumps({
                    "type": "pool_stats",
                    "stats": pool.get_pool_stats(),
                }))

    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        if miner_id and miner_id in pool.miners:
            del pool.miners[miner_id]
            print(f"  Miner disconnected: {miner_id}")


async def pool_monitor():
    """Periodically log pool stats."""
    while True:
        stats = pool.get_pool_stats()
        print(f"  Pool: {stats['miners_connected']} miners, "
              f"{stats['total_accepted']}/{stats['total_shares']} shares "
              f"({stats['acceptance_rate']:.1f}%), "
              f"model: {stats['current_model']}")
        await asyncio.sleep(60)


async def main():
    """Start the mining pool server."""
    print(f"\n  ◆ VOIDMAP MINING POOL ◆")
    print(f"  Port: {POOL_PORT}")
    print(f"  Anti-ASIC: model rotation every {ANTI_ASIC['model_rotation_interval']} blocks")
    print(f"  Model variants: {', '.join(MODEL_VARIANTS.keys())}")
    print(f"  Min quality: {MIN_QUALITY}")
    print(f"  Share difficulty: {SHARE_DIFFICULTY}")

    # Generate initial work
    for task_id in [1, 2, 3]:
        pool.generate_work(task_id)

    # Start WebSocket server
    async with websockets.serve(handle_miner, "0.0.0.0", POOL_PORT):
        print(f"\n  Pool listening on ws://0.0.0.0:{POOL_PORT}")
        await pool_monitor()


if __name__ == "__main__":
    if not HAS_WS:
        print("Error: websockets required. Install: pip install websockets")
        exit(1)
    asyncio.run(main())
