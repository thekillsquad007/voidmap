"""
Voidmap Results API — Simple HTTP server for researchers to query mining results.

Provides RESTful access to:
- All mining results (filtered by task, miner, quality)
- Individual results by ID or CID
- IPFS gateway proxy (fetch results from IPFS without running a node)
- Statistics (total results, quality distribution, etc.)

Usage:
python results_api.py --port 8547

# Query examples:
GET /results                    # all results
GET /results?task=exoplanet     # filter by task
GET /results?min_quality=80     # filter by quality
GET /results/{id}               # specific result
GET /results/{id}/ipfs          # fetch from IPFS gateway
GET /ipfs/{cid}                 # fetch any IPFS CID
GET /stats                      # pool statistics
GET /targets                    # known TESS targets
"""
import json
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from urllib.request import urlopen, Request
from urllib.error import HTTPError

IPFS_GATEWAYS = [
    "https://ipfs.io/ipfs/",
    "https://dweb.link/ipfs/",
    "https://cloudflare-ipfs.com/ipfs/",
]

RESULTS_DIR = Path.home() / ".voidmap" / "results"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)


def fetch_from_ipfs(cid: str, timeout: int = 30) -> dict | None:
    """Fetch JSON data from IPFS via public gateways."""
    if cid.startswith("sha256:"):
        return None
    for gateway in IPFS_GATEWAYS:
        try:
            req = Request(f"{gateway}{cid}", headers={"Accept": "application/json"})
            with urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read())
        except Exception:
            continue
    return None

# Known TESS targets (from miner)
KNOWN_TARGETS = [
    {"tic": "TIC 307210830", "name": "TOI-732", "planets": ["TOI-732 b", "TOI-732 c"]},
    {"tic": "TIC 261136679", "name": "TOI-1452", "planets": ["TOI-1452 b"]},
    {"tic": "TIC 36724087", "name": "TOI-700", "planets": ["TOI-700 b", "TOI-700 c", "TOI-700 d", "TOI-700 e"]},
    {"tic": "TIC 150428135", "name": "TOI-1259", "planets": ["TOI-1259 A b"]},
    {"tic": "TIC 441462736", "name": "TOI-1444", "planets": ["TOI-1444 b"]},
]


def load_all_results() -> list:
    """Load all results from disk."""
    results = []
    for filepath in RESULTS_DIR.glob("*.json"):
        try:
            with open(filepath) as f:
                data = json.load(f)
                data["_filepath"] = str(filepath)
                data["_id"] = filepath.stem
                results.append(data)
        except Exception:
            pass
    return sorted(results, key=lambda x: x.get("timestamp", 0), reverse=True)


def filter_results(results: list, params: dict) -> list:
    """Filter results by query parameters."""
    filtered = results

    if "task" in params:
        task = params["task"][0]
        filtered = [r for r in filtered if r.get("task") == task]

    if "miner" in params:
        miner = params["miner"][0]
        filtered = [r for r in filtered if r.get("miner_id") == miner]

    if "min_quality" in params:
        min_q = int(params["min_quality"][0])
        filtered = [r for r in filtered if r.get("quality_score", 0) >= min_q]

    if "target" in params:
        target = params["target"][0]
        filtered = [r for r in filtered if target.lower() in r.get("target", "").lower()]

    if "limit" in params:
        limit = int(params["limit"][0])
        filtered = filtered[:limit]

    return filtered


def compute_stats(results: list) -> dict:
    """Compute statistics over all results."""
    if not results:
        return {"total": 0}

    tasks = {}
    qualities = []
    miners = set()
    targets = set()

    for r in results:
        task = r.get("task", "unknown")
        tasks[task] = tasks.get(task, 0) + 1
        qualities.append(r.get("quality_score", 0))
        miners.add(r.get("miner_id", "unknown"))
        if r.get("target"):
            targets.add(r["target"])

    return {
        "total": len(results),
        "by_task": tasks,
        "avg_quality": round(sum(qualities) / len(qualities), 2) if qualities else 0,
        "min_quality": min(qualities) if qualities else 0,
        "max_quality": max(qualities) if qualities else 0,
        "unique_miners": len(miners),
        "unique_targets": len(targets),
        "targets": list(targets),
    }


class ResultsHandler(BaseHTTPRequestHandler):
    """HTTP request handler for results API."""

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)

        if path == "/results":
            results = load_all_results()
            filtered = filter_results(results, params)
            self.send_json(filtered)

        elif path.startswith("/results/") and path.endswith("/ipfs"):
            result_id = path.split("/results/")[1].replace("/ipfs", "")
            results = load_all_results()
            result = next((r for r in results if r.get("_id") == result_id), None)
            if not result:
                self.send_error(404, "Result not found")
                return
            cid = result.get("ipfs_cid", "")
            if not cid or cid.startswith("sha256:"):
                self.send_json({"error": "No IPFS CID available", "local_data": result})
                return
            ipfs_data = fetch_from_ipfs(cid)
            if ipfs_data:
                self.send_json(ipfs_data)
            else:
                self.send_json({"error": "Could not fetch from IPFS", "cid": cid, "gateway_urls": [f"{g}{cid}" for g in IPFS_GATEWAYS]})

        elif path.startswith("/ipfs/"):
            cid = path.split("/ipfs/")[1].split("?")[0]
            ipfs_data = fetch_from_ipfs(cid)
            if ipfs_data:
                self.send_json(ipfs_data)
            else:
                self.send_error(502, f"Could not fetch CID {cid} from any IPFS gateway")

        elif path.startswith("/results/"):
            result_id = path.split("/results/")[1]
            results = load_all_results()
            result = next((r for r in results if r.get("_id") == result_id), None)
            if result:
                self.send_json(result)
            else:
                self.send_error(404, "Result not found")

        elif path == "/stats":
            results = load_all_results()
            stats = compute_stats(results)
            self.send_json(stats)

        elif path == "/targets":
            self.send_json(KNOWN_TARGETS)

        elif path == "/tasks":
            tasks = [
                {"id": 1, "name": "exoplanet_transit", "description": "Exoplanet transit detection from TESS light curves"},
                {"id": 2, "name": "galaxy_morphology", "description": "Galaxy morphology classification from SDSS images"},
                {"id": 3, "name": "anomaly_detection", "description": "Anomaly detection in ZTF alert streams"},
            ]
            self.send_json(tasks)

        elif path == "/":
            self.send_json({
                "api": "Voidmap Results API",
                "version": "1.1",
                "endpoints": [
                    "GET /results?task=exoplanet&min_quality=80",
                    "GET /results/{id}",
                    "GET /results/{id}/ipfs",
                    "GET /ipfs/{cid}",
                    "GET /stats",
                    "GET /targets",
                    "GET /tasks",
                ],
                "ipfs_gateways": IPFS_GATEWAYS,
                "description": "Query mining results from Voidmap GPU miners. IPFS gateway proxy for researchers without IPFS nodes.",
            })

        else:
            self.send_error(404, "Not found")

    def send_json(self, data):
        response = json.dumps(data, indent=2)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(response.encode())

    def log_message(self, format, *args):
        print(f"  {args[0]}")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Voidmap Results API")
    parser.add_argument("--port", type=int, default=8547)
    parser.add_argument("--host", default="0.0.0.0")
    args = parser.parse_args()

    server = HTTPServer((args.host, args.port), ResultsHandler)
    print(f"\n ◆ VOIDMAP RESULTS API ◆")
    print(f" Listening on http://{args.host}:{args.port}")
    print(f" Results directory: {RESULTS_DIR}")
    print(f"\n Endpoints:")
    print(f" GET /results              # all results")
    print(f" GET /results?task=exoplanet&min_quality=80")
    print(f" GET /results/{{id}}         # specific result")
    print(f" GET /results/{{id}}/ipfs    # fetch from IPFS gateway")
    print(f" GET /ipfs/{{cid}}           # fetch any IPFS CID")
    print(f" GET /stats                # statistics")
    print(f" GET /targets              # known TESS targets")
    print(f" GET /tasks                # available tasks")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Shutting down...")
        server.shutdown()


if __name__ == "__main__":
    main()
