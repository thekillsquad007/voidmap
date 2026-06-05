# API Reference

## Results API

A REST API for querying mining results.

### Start the API Server

```bash
cd miner
python results_api.py --port 8547
```

---

## Endpoints

### GET /

API information.

```bash
curl http://localhost:8547/
```

**Response**:
```json
{
  "api": "Voidmap Results API",
  "version": "1.0",
  "endpoints": [
    "GET /results?task=exoplanet&min_quality=80",
    "GET /results/{id}",
    "GET /stats",
    "GET /targets",
    "GET /tasks"
  ]
}
```

---

### GET /results

List all mining results with optional filters.

```bash
# All results
curl http://localhost:8547/results

# Filter by task
curl "http://localhost:8547/results?task=exoplanet_transit"

# Filter by quality
curl "http://localhost:8547/results?min_quality=80"

# Filter by target
curl "http://localhost:8547/results?target=TOI-732"

# Combine filters
curl "http://localhost:8547/results?task=exoplanet_transit&min_quality=80&limit=10"
```

**Query Parameters**:

| Parameter | Type | Description |
|-----------|------|-------------|
| task | string | Filter by task type |
| miner | string | Filter by miner ID |
| min_quality | integer | Minimum quality score |
| target | string | Filter by target name (partial match) |
| limit | integer | Max results to return |

**Response**:
```json
[
  {
    "task": "exoplanet_transit",
    "target": "TOI-732",
    "tic_id": "TIC 307210830",
    "prediction": "PLANET",
    "confidence": 0.873,
    "quality_score": 87,
    "model": "AstroNetCNN",
    "data_source": "MAST TESS SPOC 2-min cadence",
    "timestamp": 1717440000,
    "_id": "exoplanet_TOI-732_1717440000"
  }
]
```

---

### GET /results/{id}

Get a specific result by ID.

```bash
curl http://localhost:8547/results/exoplanet_TOI-732_1717440000
```

**Response**:
```json
{
  "task": "exoplanet_transit",
  "target": "TOI-732",
  "prediction": "PLANET",
  "confidence": 0.873,
  "probabilities": {
    "planet": 0.873,
    "false_positive": 0.092,
    "no_signal": 0.035
  },
  "quality_score": 87,
  "data_points": 15000,
  "model": "AstroNetCNN",
  "data_source": "MAST TESS SPOC 2-min cadence",
  "timestamp": 1717440000,
  "_filepath": "/home/user/.voidmap/results/exoplanet_TOI-732_1717440000.json",
  "_id": "exoplanet_TOI-732_1717440000"
}
```

---

### GET /stats

Get pool statistics.

```bash
curl http://localhost:8547/stats
```

**Response**:
```json
{
  "total": 150,
  "by_task": {
    "exoplanet_transit": 80,
    "galaxy_morphology": 45,
    "anomaly_detection": 25
  },
  "avg_quality": 72.5,
  "min_quality": 52,
  "max_quality": 98,
  "unique_miners": 12,
  "unique_targets": 8,
  "targets": ["TOI-732", "TOI-1452", "TOI-700"]
}
```

---

### GET /targets

Get known TESS targets.

```bash
curl http://localhost:8547/targets
```

**Response**:
```json
[
  {
    "tic": "TIC 307210830",
    "name": "TOI-732",
    "planets": ["TOI-732 b", "TOI-732 c"]
  },
  {
    "tic": "TIC 261136679",
    "name": "TOI-1452",
    "planets": ["TOI-1452 b"]
  }
]
```

---

### GET /tasks

Get available mining tasks.

```bash
curl http://localhost:8547/tasks
```

**Response**:
```json
[
  {
    "id": 1,
    "name": "exoplanet_transit",
    "description": "Exoplanet transit detection from TESS light curves"
  },
  {
    "id": 2,
    "name": "galaxy_morphology",
    "description": "Galaxy morphology classification from SDSS images"
  },
  {
    "id": 3,
    "name": "anomaly_detection",
    "description": "Anomaly detection in ZTF alert streams"
  }
]
```

---

## IPFS Access

Results are also stored on IPFS. Access via:

```
https://ipfs.io/ipfs/{CID}
```

Example:
```bash
curl https://ipfs.io/ipfs/Qm1234567890
```

---

## Python Client

```python
import requests

API = "http://localhost:8547"

# Get all results
results = requests.get(f"{API}/results").json()

# Filter by task
exoplanet_results = requests.get(f"{API}/results", params={
    "task": "exoplanet_transit",
    "min_quality": 80
}).json()

# Get specific result
result = requests.get(f"{API}/results/exoplanet_TOI-732_1717440000").json()

# Get stats
stats = requests.get(f"{API}/stats").json()
print(f"Total results: {stats['total']}")
print(f"Average quality: {stats['avg_quality']}")
```

---

## JavaScript Client

```javascript
const API = "http://localhost:8547";

// Get all results
const results = await fetch(`${API}/results`).json();

// Filter by task
const exoplanetResults = await fetch(
  `${API}/results?task=exoplanet_transit&min_quality=80`
).json();

// Get stats
const stats = await fetch(`${API}/stats`).json();
console.log(`Total results: ${stats.total}`);
```

---

## cURL Examples

```bash
# Get high-quality exoplanet results
curl "http://localhost:8547/results?task=exoplanet_transit&min_quality=90&limit=5"

# Get results for specific target
curl "http://localhost:8547/results?target=TOI-732"

# Get pool statistics
curl http://localhost:8547/stats | jq .

# Get known targets
curl http://localhost:8547/targets | jq .
```

---

## Rate Limiting

- No rate limiting by default
- For production, consider adding rate limiting
- IPFS gateway may have its own rate limits

---

## CORS

The API includes CORS headers for web access:

```
Access-Control-Allow-Origin: *
```

This allows browser-based applications to query the API directly.
