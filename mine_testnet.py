#!/usr/bin/env python3
"""Voidmap Testnet Miner — downloads real TESS data, computes periodogram, submits on-chain."""
import hashlib, json, time, sys, os, subprocess
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "miner"))
from voidmap_miner import download_tess_lightcurve, KNOWN_TARGETS, preprocess_lightcurve

RPC = os.environ.get("RPC_URL", "https://sepolia.base.org")
PK = os.environ.get("DEPLOYER_PK", "")
POOL = os.environ.get("POOL", "0x3768e25aFc129D4455e267819801f2b2914fA4A2")
TASK_ID = 1

def _find_cast():
    for p in [
        os.path.expanduser("~/.var/app/ai.opencode.opencode/config/.foundry/bin/cast"),
        os.path.expanduser("~/.foundry/bin/cast"),
        "cast",
    ]:
        if os.path.isfile(p) or (p == "cast" and subprocess.run(["which", p], capture_output=True).returncode == 0):
            return p
    return "cast"

def sha256_bytes(data: np.ndarray) -> str:
    return "0x" + hashlib.sha256(data.tobytes()).hexdigest()

def submit_work(input_hash, output_hash, model_hash, cid, quality, duration, memory):
    cast_bin = _find_cast()
    cmd = [
        cast_bin, "send", POOL,
        "submitWork(uint256,bytes32,bytes32,bytes32,string,uint256,uint256,uint256)",
        str(TASK_ID), input_hash, output_hash, model_hash, cid,
        str(quality), str(duration), str(memory),
        "--rpc-url", RPC, "--private-key", PK,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        return f"FAILED: {result.stderr[:200]}"
    if "success" in result.stdout:
        return "SUCCESS"
    return f"UNKNOWN: {result.stdout[:200]}"

def main():
    if not PK:
        print("Set DEPLOYER_PK environment variable")
        sys.exit(1)

    print("◆ Voidmap Testnet Miner")
    target = KNOWN_TARGETS[0]
    print(f"  Target: {target['name']} ({target['tic']})")

    t0 = time.time()
    time_data, flux_data, quality = download_tess_lightcurve(target["tic"])
    print(f"  Downloaded: {len(time_data)} cadences ({time.time()-t0:.1f}s)")

    ts = time.time()
    processed = preprocess_lightcurve(time_data, flux_data, quality, target)
    if processed is None:
        print("  Preprocessing failed")
        sys.exit(1)
    print(f"  Preprocessed: {len(processed['flux'])} points ({time.time()-ts:.1f}s)")

    flux_raw = processed["flux_raw"]
    flux_norm = (flux_raw - np.median(flux_raw)) / np.std(flux_raw)

    # Compute periodogram (real computation)
    ts = time.time()
    from scipy.signal import lombscargle
    freqs = np.linspace(0.1, 50, 20000)
    power = lombscargle(np.arange(len(flux_norm)), flux_norm, freqs)
    best_period = 1.0 / freqs[np.argmax(power)]
    print(f"  Periodogram computed ({time.time()-ts:.1f}s)")
    print(f"  Best period: {best_period:.4f} days")

    quantum = time.time() - t0
    memory = flux_raw.nbytes

    # Quality score based on signal-to-noise of detected period
    quality_score = min(100, max(50, int(np.max(power) * 20)))

    # Hashes
    input_hash = sha256_bytes(flux_data.astype(np.float32))
    output_hash = sha256_bytes(power.astype(np.float32))
    model_hash = "0x" + hashlib.sha256(b"lombscargle_periodogram").hexdigest()
    cid = f"sha256:{hashlib.sha256(flux_raw.tobytes()).hexdigest()}"

    print(f"\n  Submitting to contract...")
    print(f"  Quality: {quality_score}")
    print(f"  Duration: {int(quantum*1000)}ms")
    print(f"  Memory: {memory} bytes")
    print(f"  Input hash: {input_hash[:20]}...")
    print(f"  Output hash: {output_hash[:20]}...")

    result = submit_work(input_hash, output_hash, model_hash, cid, quality_score, int(quantum*1000), memory)
    print(f"  Result: {result}")

    if "SUCCESS" in result:
        print(f"\n  ✓ Work submitted! Verify:")
        print(f"  https://sepolia.basescan.org/address/{POOL}")
        # Save result
        out = {
            "target": target["name"], "period": float(best_period),
            "quality": quality_score, "duration_ms": int(quantum*1000),
            "input_hash": input_hash, "output_hash": output_hash,
            "timestamp": int(time.time()),
        }
        os.makedirs(os.path.expanduser("~/.voidmap/results"), exist_ok=True)
        path = os.path.expanduser(f"~/.voidmap/results/miner_{int(time.time())}.json")
        with open(path, "w") as f:
            json.dump(out, f, indent=2)
        print(f"  Saved: {path}")

if __name__ == "__main__":
    main()
