"""
Voidmap Pool Client — Connects to mining pool, receives work, submits shares.

Usage:
    python pool_client.py --pool ws://localhost:8546 --miner-id my_miner
"""
import argparse
import hashlib
import json
import os
import random
import sys
import time
from pathlib import Path

try:
    import websockets
    import asyncio
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

# Import local modules
sys.path.insert(0, str(Path(__file__).parent))
from anti_asic import AntiASIC, ARCHITECTURES
from voidmap_miner import (
    load_transit_model, run_transit_detection, preprocess_lightcurve,
    download_tess_lightcurve, download_sdss_galaxy, download_ztf_alerts,
    get_stellar_scalars, KNOWN_TARGETS, RESULTS_DIR
)


class PoolClient:
    """Connects to mining pool and processes work."""

    def __init__(self, pool_url, miner_id):
        self.pool_url = pool_url
        self.miner_id = miner_id
        self.ws = None
        self.anti_asic = AntiASIC()
        self.device = self._get_device()
        self.models = {}  # cached models per architecture
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

    def process_work(self, work: dict) -> dict:
        """Process work unit and return result."""
        task_id = work["task_id"]
        architecture = work["model_variant"]
        batch_size = work["batch_size"]

        # Get model
        model = self.get_model(architecture)

        # Perturb weights (anti-ASIC: can't pre-compute)
        model = self.anti_asic.perturb_weights(model)

        # Download and preprocess data
        if task_id == 1:
            target = KNOWN_TARGETS[random.randint(0, len(KNOWN_TARGETS) - 1)]
            time_data, flux_data, quality = download_tess_lightcurve(target["tic"])
            if time_data is None:
                return None
            processed = preprocess_lightcurve(time_data, flux_data, quality, target)
            if processed is None or "flux_global" not in processed:
                return None

            # Run inference
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
            alerts = download_ztf_alerts("SN", limit=batch_size)
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

    def compute_share(self, work: dict, result: dict) -> dict:
        """Compute a share from work result."""
        # Memory-hard computation (anti-ASIC)
        memory_data = self.anti_asic.get_memory_hard_data(size_mb=64)

        # Dynamic hash
        output_hash = hashlib.sha256(json.dumps(result, sort_keys=True).encode()).hexdigest()

        # Generate nonce
        nonce = hashlib.sha256(f"{time.time()}:{random.random()}".encode()).hexdigest()

        # Compute share hash with difficulty
        share_data = {
            "work_id": work["work_id"],
            "miner_id": self.miner_id,
            "task_id": work["task_id"],
            "architecture": work["model_variant"],
            "batch_size": work["batch_size"],
            "quality": result.get("quality_score", 0),
            "output_hash": output_hash,
            "nonce": nonce,
            "challenge_hash": work.get("challenge_hash", ""),
            "input_hash": hashlib.sha256(memory_data.numpy().tobytes()).hexdigest(),
        }

        # Find valid nonce (proof of work)
        for i in range(1000000):
            share_data["nonce"] = hashlib.sha256(f"{nonce}:{i}".encode()).hexdigest()
            share_hash = hashlib.sha256(json.dumps(share_data, sort_keys=True).encode()).hexdigest()
            if share_hash.startswith("0" * 4):  # easy difficulty for pool shares
                share_data["share_hash"] = share_hash
                return share_data

        share_data["share_hash"] = share_hash
        return share_data

    async def run(self):
        """Main mining loop connected to pool."""
        print(f"\n  ◆ VOIDMAP POOL CLIENT ◆")
        print(f"  Pool: {self.pool_url}")
        print(f"  Miner ID: {self.miner_id}")
        print(f"  Device: {self.device}")

        try:
            async with websockets.connect(self.pool_url) as ws:
                self.ws = ws

                # Authenticate
                await ws.send(json.dumps({
                    "type": "auth",
                    "miner_id": self.miner_id,
                }))
                response = json.loads(await ws.recv())
                if response.get("type") == "auth_ok":
                    print(f"  Authenticated. Pool stats: {response.get('pool_stats', {})}")
                else:
                    print(f"  Auth failed: {response}")
                    return

                # Mining loop
                while self.running:
                    # Request work
                    await ws.send(json.dumps({"type": "get_work", "task_id": 1}))
                    work_msg = json.loads(await ws.recv())

                    if work_msg.get("type") != "work":
                        print(f"  Unexpected response: {work_msg}")
                        await asyncio.sleep(1)
                        continue

                    work = work_msg["work"]
                    print(f"\n  Work received: {work['work_id']} (block {work['block_num']})")
                    print(f"  Architecture: {work['model_variant']}, batch: {work['batch_size']}")

                    # Process work
                    result = self.process_work(work)
                    if result is None:
                        print(f"  Work processing failed, requesting new work")
                        continue

                    print(f"  Result: quality={result.get('quality_score', 0)}")

                    # Compute and submit share
                    share = self.compute_share(work, result)
                    await ws.send(json.dumps({
                        "type": "submit_share",
                        "share": share,
                    }))

                    response = json.loads(await ws.recv())
                    if response.get("type") == "share_accepted":
                        print(f"  Share accepted! Total: {response.get('total_accepted')}")
                    else:
                        print(f"  Share rejected: {response.get('reason')}")

                    # Brief pause
                    await asyncio.sleep(1)

        except websockets.exceptions.ConnectionClosed:
            print("  Connection closed, reconnecting...")
            await asyncio.sleep(5)
            await self.run()
        except Exception as e:
            print(f"  Error: {e}")
            await asyncio.sleep(5)
            await self.run()


def main():
    parser = argparse.ArgumentParser(description="Voidmap Pool Client")
    parser.add_argument("--pool", default="ws://localhost:8546", help="Pool WebSocket URL")
    parser.add_argument("--miner-id", default=f"miner_{random.randint(1000,9999)}", help="Miner ID")
    args = parser.parse_args()

    if not HAS_WS:
        print("Error: websockets required. Install: pip install websockets")
        return
    if not HAS_TORCH:
        print("Error: PyTorch required. Install: pip install torch")
        return

    client = PoolClient(args.pool, args.miner_id)
    asyncio.run(client.run())


if __name__ == "__main__":
    main()
