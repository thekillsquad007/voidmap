"""
Voidmap IPFS — Upload mining results to IPFS for public access.

Results are stored on IPFS and the CID is recorded on-chain.
Anyone can access results via https://ipfs.io/ipfs/{CID}

Usage:
    from ipfs_upload import upload_result, upload_batch
    
    cid = upload_result(result_dict)
    print(f"Result at: https://ipfs.io/ipfs/{cid}")
"""
import hashlib
import json
import os
import time
from pathlib import Path

try:
    import ipfshttpclient
    HAS_IPFS = True
except ImportError:
    HAS_IPFS = False

# ─── IPFS Configuration ───────────────────────────────────
# Free IPFS pinning services:
# - Pinata (free tier: 100MB, 100 pins/month)
# - NFT.Storage (free, unlimited for CIDs)
# - web3.storage (free, 10GB)

RESULTS_DIR = Path.home() / ".voidmap" / "results"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)


def upload_to_ipfs(data: dict) -> str:
    """Upload data to IPFS and return CID."""
    if not HAS_IPFS:
        # Fallback: save locally and return path
        return save_locally(data)

    try:
        # Try local IPFS daemon first
        client = ipfshttpclient.connect('/ip4/127.0.0.1/tcp/5001')
        result = client.add_json(data)
        return result
    except Exception:
        pass

    # Fallback: use Pinata API (free tier)
    pinata_key = os.environ.get("PINATA_API_KEY")
    pinata_secret = os.environ.get("PINATA_API_SECRET")
    
    if pinata_key and pinata_secret:
        return upload_to_pinata(data, pinata_key, pinata_secret)

    # Fallback: save locally
    return save_locally(data)


def upload_to_pinata(data: dict, api_key: str, api_secret: str) -> str:
    """Upload to Pinata IPFS pinning service."""
    import urllib.request
    import urllib.parse

    url = "https://api.pinata.cloud/pinning/pinJSONToIPFS"
    payload = json.dumps({
        "pinataContent": data,
        "pinataMetadata": {
            "name": f"voidmap_result_{int(time.time())}",
            "keyvalues": {
                "task": data.get("task", "unknown"),
                "miner": data.get("miner_id", "unknown"),
                "timestamp": str(int(time.time())),
            }
        }
    }).encode()

    req = urllib.request.Request(url, data=payload, headers={
        "Content-Type": "application/json",
        "pinata_api_key": api_key,
        "pinata_secret_api_key": api_secret,
    })

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
            return result.get("IpfsHash")
    except Exception as e:
        print(f"Pinata upload failed: {e}")
        return save_locally(data)


def save_locally(data: dict) -> str:
    """Save result locally as fallback. Returns a content-based hash
    (sha256 of the JSON data) so on-chain records always contain a
    valid hash, not a file path."""
    filename = f"result_{data.get('task', 'unknown')}_{int(time.time())}.json"
    filepath = RESULTS_DIR / filename
    content = json.dumps(data, sort_keys=True)
    with open(filepath, "w") as f:
        f.write(content)
    content_hash = hashlib.sha256(content.encode()).hexdigest()
    return f"sha256:{content_hash}"


def upload_result(result: dict, miner_id: str = "unknown") -> str:
    """Upload a single mining result to IPFS."""
    result["miner_id"] = miner_id
    result["uploaded_at"] = int(time.time())
    result["version"] = "1.0"
    
    cid = upload_to_ipfs(result)
    result["ipfs_cid"] = cid
    
    # Save locally with CID reference
    filename = f"result_{result.get('task', 'unknown')}_{int(time.time())}.json"
    filepath = RESULTS_DIR / filename
    with open(filepath, "w") as f:
        json.dump(result, f, indent=2)
    
    return cid


def upload_batch(results: list, miner_id: str = "unknown") -> list:
    """Upload multiple results to IPFS."""
    cids = []
    for result in results:
        cid = upload_result(result, miner_id)
        cids.append(cid)
    return cids


def get_result_url(cid: str) -> str:
    """Get URL to access result on IPFS gateway."""
    if cid.startswith("sha256:"):
        return f"local:{cid}"
    return f"https://ipfs.io/ipfs/{cid}"


if __name__ == "__main__":
    # Test IPFS upload
    test_result = {
        "task": "exoplanet_transit",
        "target": "TOI-732",
        "prediction": "PLANET",
        "confidence": 0.87,
        "quality_score": 87,
        "timestamp": int(time.time()),
    }
    
    cid = upload_result(test_result, "test_miner")
    print(f"Uploaded to IPFS: {cid}")
    print(f"Access at: {get_result_url(cid)}")
