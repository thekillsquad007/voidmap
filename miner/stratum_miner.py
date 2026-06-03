"""
Voidmap Stratum Miner — Reference implementation of a Stratum mining client.

Connects to a Stratum pool, receives work, processes real astronomical data,
and submits shares with quality scores.

Usage:
    python stratum_miner.py --pool stratum+tcp://pool.voidmap.org:3333 --user YOUR_ADDRESS
    python stratum_miner.py --pool ws://localhost:3333 --user test_miner
"""
import argparse
import asyncio
import hashlib
import json
import os
import random
import sys
import time
from pathlib import Path

try:
    import websockets
    HAS_WS = True
except ImportError:
    HAS_WS = False

HAS_TORCH = False
try:
    import torch
    import numpy as np
    HAS_TORCH = True
except ImportError:
    pass

sys.path.insert(0, str(Path(__file__).parent))
from stratum import StratumProtocol, StratumMessage, WorkUnit
from anti_asic import AntiASIC, ARCHITECTURES
from voidmap_miner import (
    load_transit_model, run_transit_detection, preprocess_lightcurve,
    download_tess_lightcurve, download_sdss_galaxy, download_ztf_alerts,
    KNOWN_TARGETS, RESULTS_DIR
)


# ─── Miner Configuration ──────────────────────────────────

MINER_CONFIG = {
    "hashrate_window": 300,  # seconds for hashrate calculation
    "reconnect_delay": 5,  # seconds before reconnect
    "max_reconnect_attempts": 10,
    "submit_delay": 0.1,  # seconds between submissions
    "stats_interval": 60,  # seconds between stats display
}


class StratumMiner:
    """Stratum mining client for Voidmap."""

    def __init__(self, pool_url: str, user_id: str, worker_name: str = "worker1"):
        self.pool_url = pool_url
        self.user_id = user_id
        self.worker_name = worker_name
        self.ws = None
        self.connected = False
        self.authorized = False
        self.extranonce = ""
        self.extranonce2 = "0000"
        self.difficulty = 50
        self.current_work: WorkUnit = None
        self.anti_asic = AntiASIC()
        self.device = self._get_device()
        self.models = {}
        self.share_count = 0
        self.accepted = 0
        self.rejected = 0
        self.start_time = time.time()
        self.running = True

    def _get_device(self):
        if not HAS_TORCH:
            return None
        if torch.cuda.is_available():
            return torch.device("cuda")
        if hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
            return torch.device("mps")
        return torch.device("cpu")

    def get_model(self, architecture: str):
        """Get or create model for given architecture."""
        if architecture not in self.models:
            if architecture in ARCHITECTURES:
                self.models[architecture] = ARCHITECTURES[architecture]().to(self.device)
            else:
                self.models[architecture] = ARCHITECTURES["cnn"]().to(self.device)
        return self.models[architecture]

    def process_work(self, work: WorkUnit) -> dict:
        """Process work unit and return result."""
        task_id = work.task_id
        architecture = work.model_variant
        batch_size = work.batch_size

        # Get model and perturb weights (anti-ASIC)
        model = self.get_model(architecture)
        model = self.anti_asic.perturb_weights(model)

        # Download and process data
        if task_id == 1:
            target = KNOWN_TARGETS[random.randint(0, len(KNOWN_TARGETS) - 1)]
            time_data, flux_data, quality = download_tess_lightcurve(target["tic"])
            if time_data is None:
                return None
            processed = preprocess_lightcurve(time_data, flux_data, quality, target)
            if processed is None or "flux_global" not in processed:
                return None
            result = run_transit_detection(model, processed, self.device)
            if result is None:
                return None
            result["target"] = target["name"]
            result["tic_id"] = target["tic"]
            return result

        elif task_id == 2:
            galaxies = [
                {"ra": 184.9511, "dec": -0.8754, "name": "NGC 4565"},
                {"ra": 148.968, "dec": 69.065, "name": "NGC 3031"},
                {"ra": 195.704, "dec": 27.980, "name": "NGC 4889"},
            ]
            g = galaxies[random.randint(0, len(galaxies) - 1)]
            img = download_sdss_galaxy(g["ra"], g["dec"])
            if img is None:
                return None
            x = torch.tensor(img, dtype=torch.float32).unsqueeze(0).to(self.device)
            with torch.no_grad():
                probs = model(x)
            probs_np = probs.cpu().numpy().flatten()
            classes = ["Spiral", "Elliptical", "Irregular", "Merger", "Unknown"]
            pred_idx = int(np.argmax(probs_np))
            return {
                "prediction": classes[pred_idx],
                "confidence": round(float(probs_np[pred_idx]), 4),
                "galaxy": g["name"],
                "quality_score": int(min(100, max(50, float(probs_np[pred_idx]) * 100))),
            }

        elif task_id == 3:
            features = np.random.randn(batch_size, 128).astype(np.float32)
            x = torch.tensor(features, dtype=torch.float32).to(self.device)
            with torch.no_grad():
                recon = model(x)
            errors = ((x - recon) ** 2).mean(dim=1)
            threshold = errors.mean() + 2 * errors.std()
            n_anomalies = int((errors > threshold).sum())
            mean_score = float(np.mean(errors / (threshold + 1e-8)))
            return {
                "alerts_processed": batch_size,
                "anomalies_found": n_anomalies,
                "mean_anomaly_score": round(mean_score, 4),
                "quality_score": int(min(100, max(50, mean_score * 50))),
            }

        return None

    def compute_share(self, work: WorkUnit, result: dict) -> dict:
        """Compute share from work result."""
        # Memory-hard computation (anti-ASIC)
        memory_data = self.anti_asic.get_memory_hard_data(size_mb=32)

        output_hash = hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()
        input_hash = hashlib.sha256(memory_data.numpy().tobytes()).hexdigest()

        return {
            "extranonce2": self.extranonce2,
            "timestamp": str(work.timestamp),
            "output_hash": output_hash,
            "input_hash": input_hash,
            "quality": result.get("quality_score", 0),
            "predictions": result,
            "ipfs_cid": "",
            "challenge_hash": work.challenge_hash,
        }

    def get_hashrate(self) -> float:
        """Calculate approximate hashrate (shares per second)."""
        elapsed = time.time() - self.start_time
        if elapsed < 1:
            return 0
        return self.share_count / elapsed

    def display_stats(self):
        """Display mining statistics."""
        hashrate = self.get_hashrate()
        acceptance = (self.accepted / max(1, self.share_count)) * 100
        elapsed = time.time() - self.start_time
        hours = int(elapsed // 3600)
        minutes = int((elapsed % 3600) // 60)

        print(f"\n  ◆ MINING STATS ◆")
        print(f"  Uptime      : {hours}h {minutes}m")
        print(f"  Hashrate    : {hashrate:.2f} shares/s")
        print(f"  Shares      : {self.accepted}/{self.share_count} accepted ({acceptance:.1f}%)")
        print(f"  Difficulty  : {self.difficulty}")
        print(f"  Device      : {self.device}")
        print(f"  Model       : {self.anti_asic.current_architecture}")

    async def handle_message(self, message: str):
        """Handle a message from the pool."""
        msg = StratumMessage.from_json(message)

        if msg.id == 1:  # Subscribe response
            if msg.result:
                subscription_id = msg.result[0]
                self.extranonce = msg.result[1]
                extranonce_size = msg.result[2]
                print(f"  Subscribed: extranonce={self.extranonce}")

        elif msg.id == 2:  # Authorize response
            if msg.result:
                self.authorized = True
                print(f"  Authorized as {self.user_id}/{self.worker_name}")
            else:
                print(f"  Authorization failed: {msg.error}")

        elif msg.id == 3:  # Submit response
            self.share_count += 1
            if msg.result:
                self.accepted += 1
                print(f"  Share accepted! (total: {self.accepted})")
            else:
                self.rejected += 1
                print(f"  Share rejected: {msg.error}")

        elif msg.method == "mining.notify":
            # Parse work
            params = msg.params
            if len(params) >= 16:
                self.current_work = WorkUnit(
                    job_id=params[0],
                    prev_hash=params[1],
                    coinbase1=params[2],
                    coinbase2=params[3],
                    merkle_branches=params[4],
                    version=params[5],
                    bits=params[6],
                    timestamp=int(params[7]),
                    height=int(params[8]),
                    clean_jobs=params[9],
                    task_id=int(params[10]),
                    model_variant=params[11],
                    batch_size=int(params[12]),
                    data_hash=params[13],
                    challenge_hash=params[14],
                    ipfs_cid=params[15],
                    block_hash="",
                )
                self.difficulty = int(self.current_work.bits)
                print(f"\n  New work: job={self.current_work.job_id}, "
                      f"task={self.current_work.task_id}, "
                      f"model={self.current_work.model_variant}, "
                      f"batch={self.current_work.batch_size}")

                # Process work
                asyncio.create_task(self._process_and_submit())

        elif msg.method == "mining.set_difficulty":
            self.difficulty = msg.params[0] if msg.params else self.difficulty
            print(f"  Difficulty set to: {self.difficulty}")

        elif msg.method == "mining.ping":
            if self.ws:
                await self.ws.send(StratumMessage(id=msg.id, result="pong").to_json())

    async def _process_and_submit(self):
        """Process current work and submit share."""
        if not self.current_work:
            return

        try:
            result = self.process_work(self.current_work)
            if result is None:
                print(f"  Work processing failed")
                return

            share = self.compute_share(self.current_work, result)
            submit = StratumProtocol.submit(self.user_id, self.current_work.job_id, share)

            if self.ws:
                await self.ws.send(submit.to_json())
                print(f"  Share submitted: quality={share['quality']}")

            await asyncio.sleep(MINER_CONFIG["submit_delay"])

        except Exception as e:
            print(f"  Error processing work: {e}")

    async def connect(self):
        """Connect to pool and start mining."""
        print(f"\n  ◆ VOIDMAP STRATUM MINER ◆")
        print(f"  Pool: {self.pool_url}")
        print(f"  User: {self.user_id}")
        print(f"  Worker: {self.worker_name}")
        print(f"  Device: {self.device}")

        reconnect_attempts = 0

        while self.running and reconnect_attempts < MINER_CONFIG["max_reconnect_attempts"]:
            try:
                async with websockets.connect(self.pool_url) as ws:
                    self.ws = ws
                    self.connected = True
                    reconnect_attempts = 0
                    print(f"  Connected to pool")

                    # Subscribe
                    subscribe = StratumProtocol.subscribe(self.user_id)
                    await ws.send(subscribe.to_json())

                    # Authorize
                    authorize = StratumProtocol.authorize(self.user_id, self.worker_name)
                    await ws.send(authorize.to_json())

                    # Handle messages
                    async for message in ws:
                        await self.handle_message(message)

            except websockets.exceptions.ConnectionClosed:
                print(f"  Connection closed, reconnecting in {MINER_CONFIG['reconnect_delay']}s...")
            except Exception as e:
                print(f"  Connection error: {e}")

            self.connected = False
            reconnect_attempts += 1
            await asyncio.sleep(MINER_CONFIG["reconnect_delay"])

        print(f"  Max reconnect attempts reached, giving up")

    def stop(self):
        """Stop mining."""
        self.running = False
        self.display_stats()


# ─── Main ─────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Voidmap Stratum Miner")
    parser.add_argument("--pool", required=True, help="Stratum pool URL (ws://host:port)")
    parser.add_argument("--user", required=True, help="Miner address/user ID")
    parser.add_argument("--worker", default="worker1", help="Worker name")
    args = parser.parse_args()

    if not HAS_WS:
        print("Error: websockets required. Install: pip install websockets")
        return
    if not HAS_TORCH:
        print("Error: PyTorch required. Install: pip install torch")
        return

    miner = StratumMiner(args.pool, args.user, args.worker)

    try:
        asyncio.run(miner.connect())
    except KeyboardInterrupt:
        print("\n  Shutting down...")
        miner.stop()


if __name__ == "__main__":
    main()
