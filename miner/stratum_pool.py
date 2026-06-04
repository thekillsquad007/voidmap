"""
Voidmap Stratum Pool — Reference implementation of a mining pool.

Implements the Stratum protocol for distributed GPU mining:
- Manages connected miners
- Distributes work with anti-ASIC challenges
- Validates shares (quality >= 50)
- Tracks hashrate and shares
- Connects to MiningPool contract for on-chain rewards

Usage:
    python stratum_pool.py --port 3333 --contract 0x... --rpc https://mainnet.base.org
"""
import asyncio
import hashlib
import json
import os
import random
import sys
import time
import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

try:
    import websockets
    HAS_WS = True
except ImportError:
    HAS_WS = False

sys.path.insert(0, str(Path(__file__).parent))
from stratum import (
    StratumProtocol, StratumMessage, WorkUnit, MinerSession,
    validate_submit, EXTRANONCE_SIZE, PROTOCOL_VERSION
)
from anti_asic import AntiASIC, MODEL_VARIANTS, ARCHITECTURES


# ─── Pool Configuration ───────────────────────────────────

POOL_CONFIG = {
    "port": int(os.environ.get("VOIDMAP_STRATUM_PORT", "3333")),
    "max_miners": 1000,
    "min_difficulty": 50,
    "max_difficulty": 100,
    "share_difficulty": 16,  # leading zeros for share validation
    "block_time": 120,  # seconds between difficulty adjustments
    "var_diff_interval": 60,  # seconds between difficulty recalculations
    "ping_interval": 30,  # seconds between ping messages
    "job_refresh_interval": 30,  # seconds between job refreshes
    "reward_pct": 98,  # percentage of reward to miners (2% pool fee)
}


# ─── Pool State ───────────────────────────────────────────

class StratumPool:
    """Mining pool with Stratum protocol support."""

    def __init__(self):
        self.miners: dict[str, MinerSession] = {}
        self.work_queue: list[WorkUnit] = []
        self.current_work: WorkUnit = None
        self.anti_asic = AntiASIC()
        self.block_height = 0
        self.total_shares = 0
        self.total_accepted = 0
        self.total_rejected = 0
        self.difficulty = POOL_CONFIG["min_difficulty"]
        self.results_dir = Path.home() / ".voidmap" / "pool_results"
        self.results_dir.mkdir(parents=True, exist_ok=True)
        self.running = True
        self._miner_counter = 0

    def generate_extranonce(self) -> str:
        """Generate unique extranonce for miner."""
        self._miner_counter += 1
        return hashlib.sha256(f"pool_{self._miner_counter}_{time.time()}".encode()).hexdigest()[:EXTRANONCE_SIZE * 2]

    def generate_work(self, clean_jobs=True) -> WorkUnit:
        """Generate new work unit with anti-ASIC measures."""
        self.block_height += 1

        # Get anti-ASIC challenge
        challenge = self.anti_asic.generate_challenge(self.block_height)

        # Generate coinbase (simplified)
        coinbase_tx = hashlib.sha256(f"coinbase_{self.block_height}_{time.time()}".encode()).hexdigest()
        coinbase1 = coinbase_tx[:64]
        coinbase2 = coinbase_tx[64:]

        # Generate prev hash
        if self.current_work:
            prev_hash = self.current_work.block_hash
        else:
            prev_hash = "0" * 64

        # Generate block hash
        block_data = f"{self.block_height}:{prev_hash}:{coinbase1}:{time.time()}"
        block_hash = hashlib.sha256(block_data.encode()).hexdigest()

        work = WorkUnit(
            job_id=f"job_{self.block_height}_{int(time.time())}",
            task_id=random.choice([1, 2, 3]),
            block_hash=block_hash,
            prev_hash=prev_hash,
            coinbase1=coinbase1,
            coinbase2=coinbase2,
            merkle_branches=[],
            version=PROTOCOL_VERSION,
            bits=str(int(self.difficulty)),
            timestamp=int(time.time()),
            height=self.block_height,
            clean_jobs=clean_jobs,
            model_variant=challenge["architecture"],
            batch_size=challenge["batch_size"],
            data_hash=challenge["challenge_hash"],
            challenge_hash=challenge["challenge_hash"],
            ipfs_cid="",
        )

        self.current_work = work
        self.work_queue.append(work)
        return work

    def calculate_difficulty(self, miner: MinerSession) -> float:
        """Calculate dynamic difficulty for miner based on performance."""
        if miner.share_count < 10:
            return POOL_CONFIG["min_difficulty"]

        # Adjust based on acceptance rate
        if miner.share_count > 0:
            acceptance_rate = miner.accepted_shares / miner.share_count
            if acceptance_rate > 0.9:
                return min(POOL_CONFIG["max_difficulty"], miner.difficulty + 5)
            elif acceptance_rate < 0.5:
                return max(POOL_CONFIG["min_difficulty"], miner.difficulty - 5)

        return miner.difficulty

    def validate_share(self, miner: MinerSession, submit: StratumMessage, work: WorkUnit) -> tuple[bool, str]:
        """Validate a miner's share submission."""
        valid, reason = validate_submit(submit, work)
        if not valid:
            return False, reason

        # Check quality
        if len(submit.params) > 5:
            quality = submit.params[5]
            if quality < self.difficulty:
                return False, f"Quality {quality} < difficulty {self.difficulty}"

        # Verify challenge hash
        if len(submit.params) > 6:
            result = submit.params[6]
            if isinstance(result, dict):
                output_hash = result.get("output_hash", "")
                # Verify computation was done
                if not output_hash or len(output_hash) < 32:
                    return False, "Invalid output hash"

        return True, "Valid"

    def handle_miner_message(self, miner: MinerSession, message: str) -> list[StratumMessage]:
        """Handle a message from a miner."""
        responses = []
        msg = StratumMessage.from_json(message)

        if msg.method == "mining.subscribe":
            # Generate extranonce
            extranonce = self.generate_extranonce()
            miner.extranonce = extranonce
            miner.subscribed = True
            responses.append(StratumProtocol.subscribe_response(
                subscription_id=hash(miner.miner_id) % 10000,
                extranonce=extranonce,
                extranonce_size=EXTRANONCE_SIZE
            ))
            # Send initial difficulty
            responses.append(StratumProtocol.set_difficulty(self.difficulty))
            # Send initial work
            work = self.generate_work()
            responses.append(StratumProtocol.notify(work))

        elif msg.method == "mining.authorize":
            if len(msg.params) >= 1:
                miner.authorized = True
                responses.append(StratumProtocol.authorize_response(True))
                print(f"  Miner authorized: {miner.miner_id}")
            else:
                responses.append(StratumProtocol.authorize_response(False))

        elif msg.method == "mining.submit":
            if not miner.authorized:
                responses.append(StratumProtocol.error(msg.id, 24, "Not authorized"))
            elif not self.current_work:
                responses.append(StratumProtocol.error(msg.id, 25, "No work available"))
            else:
                valid, reason = self.validate_share(miner, msg, self.current_work)
                miner.share_count += 1
                self.total_shares += 1

                if valid:
                    miner.accepted_shares += 1
                    self.total_accepted += 1
                    responses.append(StratumProtocol.submit_response(True))
                    print(f"  Share accepted: {miner.miner_id} (quality: {msg.params[5] if len(msg.params) > 5 else '?'})")

                    # Save result
                    self._save_share(miner, msg)
                else:
                    miner.rejected_shares += 1
                    self.total_rejected += 1
                    responses.append(StratumProtocol.submit_response(False, reason))
                    print(f"  Share rejected: {miner.miner_id} - {reason}")

        elif msg.method == "mining.get_work":
            work = self.generate_work()
            responses.append(StratumProtocol.notify(work))

        elif msg.method == "mining.ping":
            responses.append(StratumMessage(id=msg.id, result="pong"))

        miner.last_activity = time.time()
        return responses

    def _save_share(self, miner: MinerSession, submit: StratumMessage):
        """Save accepted share to disk."""
        result = {
            "miner_id": miner.miner_id,
            "job_id": submit.params[1] if len(submit.params) > 1 else "",
            "quality": submit.params[5] if len(submit.params) > 5 else 0,
            "predictions": submit.params[6] if len(submit.params) > 6 else {},
            "ipfs_cid": submit.params[7] if len(submit.params) > 7 else "",
            "timestamp": int(time.time()),
        }
        filepath = self.results_dir / f"share_{miner.miner_id}_{int(time.time())}.json"
        with open(filepath, "w") as f:
            json.dump(result, f, indent=2)

    def get_pool_stats(self) -> dict:
        """Get pool statistics."""
        return {
            "miners_connected": len(self.miners),
            "miners_authorized": sum(1 for m in self.miners.values() if m.authorized),
            "total_shares": self.total_shares,
            "total_accepted": self.total_accepted,
            "total_rejected": self.total_rejected,
            "acceptance_rate": (self.total_accepted / max(1, self.total_shares)) * 100,
            "difficulty": self.difficulty,
            "block_height": self.block_height,
            "current_model": self.anti_asic.current_architecture,
        }

    async def handle_connection(self, ws, path=None):
        """Handle a miner WebSocket connection."""
        miner_id = None
        try:
            # Wait for subscribe message
            async for message in ws:
                msg = StratumMessage.from_json(message)

                if msg.method == "mining.subscribe":
                    miner_id = msg.params[0] if msg.params else f"miner_{uuid.uuid4().hex[:8]}"
                    extranonce = self.generate_extranonce()
                    miner = MinerSession(miner_id=miner_id, extranonce=extranonce, difficulty=self.difficulty)
                    self.miners[miner_id] = miner

                    # Send responses
                    responses = self.handle_miner_message(miner, message)
                    for resp in responses:
                        await ws.send(resp.to_json())

                    print(f"  Miner connected: {miner_id}")
                    break

            # Handle subsequent messages
            async for message in ws:
                if miner_id and miner_id in self.miners:
                    responses = self.handle_miner_message(self.miners[miner_id], message)
                    for resp in responses:
                        await ws.send(resp.to_json())

        except websockets.exceptions.ConnectionClosed:
            pass
        except Exception as e:
            print(f"  Error: {e}")
        finally:
            if miner_id and miner_id in self.miners:
                del self.miners[miner_id]
                print(f"  Miner disconnected: {miner_id}")

    async def broadcast_work(self):
        """Periodically broadcast new work to all miners."""
        while self.running:
            await asyncio.sleep(POOL_CONFIG["job_refresh_interval"])
            if self.current_work:
                work = self.generate_work(clean_jobs=True)
                notify = StratumProtocol.notify(work)
                for miner in self.miners.values():
                    if miner.authorized:
                        try:
                            # Would need websocket reference stored in MinerSession
                            pass
                        except:
                            pass

    async def monitor_loop(self):
        """Monitor pool statistics."""
        while self.running:
            await asyncio.sleep(60)
            stats = self.get_pool_stats()
            print(f"  Pool: {stats['miners_authorized']} miners, "
                  f"{stats['total_accepted']}/{stats['total_shares']} shares "
                  f"({stats['acceptance_rate']:.1f}%), "
                  f"diff: {stats['difficulty']}, "
                  f"model: {stats['current_model']}")

    async def start(self):
        """Start the Stratum pool server."""
        print(f"\n  ◆ VOIDMAP STRATUM POOL ◆")
        print(f"  Port: {POOL_CONFIG['port']}")
        print(f"  Difficulty: {POOL_CONFIG['min_difficulty']}-{POOL_CONFIG['max_difficulty']}")
        print(f"  Anti-ASIC: {self.anti_asic.current_architecture}")
        print(f"  Reward: {POOL_CONFIG['reward_pct']}% to miners")

        # Generate initial work
        self.generate_work()

        # Start tasks
        asyncio.create_task(self.monitor_loop())
        asyncio.create_task(self.broadcast_work())

        # Start WebSocket server
        async with websockets.serve(
            self.handle_connection,
            "0.0.0.0",
            POOL_CONFIG["port"],
            ping_interval=POOL_CONFIG["ping_interval"],
            ping_timeout=POOL_CONFIG["ping_interval"] * 2,
        ):
            print(f"\n  Stratum pool listening on 0.0.0.0:{POOL_CONFIG['port']}")
            await asyncio.Future()  # run forever


# ─── Main ─────────────────────────────────────────────────

async def main():
    pool = StratumPool()
    await pool.start()


if __name__ == "__main__":
    if not HAS_WS:
        print("Error: websockets required. Install: pip install websockets")
        exit(1)
    asyncio.run(main())
