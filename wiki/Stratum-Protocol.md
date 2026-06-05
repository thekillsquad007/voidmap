# Stratum Protocol

## Overview

Voidmap uses a modified Stratum protocol for communication between miners and pools. Stratum is the standard mining protocol used in Bitcoin, adapted here for Proof of Useful Work.

---

## Protocol Specification

### Transport

- **Protocol**: WebSocket (ws:// or wss://)
- **Format**: JSON-RPC 2.0
- **Encoding**: UTF-8

### Message Format

**Request**:
```json
{
  "id": 1,
  "method": "mining.subscribe",
  "params": ["miner_id"]
}
```

**Response**:
```json
{
  "id": 1,
  "result": [1, "extranonce", 4],
  "error": null
}
```

**Notification** (server → client):
```json
{
  "method": "mining.notify",
  "params": [...]
}
```

---

## Methods

### mining.subscribe

Miner subscribes to work notifications.

**Request**:
```json
{
  "id": 1,
  "method": "mining.subscribe",
  "params": ["miner_id"]
}
```

**Response**:
```json
{
  "id": 1,
  "result": [
    ["mining.notify", 1],
    "extranonce_hex",
    4
  ],
  "error": null
}
```

**Fields**:
- `params[0]`: Miner ID (string)
- `result[0]`: Subscription IDs
- `result[1]`: Extranonce (hex string)
- `result[2]`: Extranonce size (bytes)

---

### mining.authorize

Miner authenticates with pool.

**Request**:
```json
{
  "id": 2,
  "method": "mining.authorize",
  "params": ["miner_id", "worker_name", "password"]
}
```

**Response**:
```json
{
  "id": 2,
  "result": true,
  "error": null
}
```

**Fields**:
- `params[0]`: Miner ID
- `params[1]`: Worker name
- `params[2]`: Password (optional)
- `result`: true if authorized

---

### mining.notify

Pool sends new work to miner.

**Notification**:
```json
{
  "method": "mining.notify",
  "params": [
    "job_id",
    "prev_hash",
    "coinbase1",
    "coinbase2",
    ["merkle_branches"],
    "version",
    "bits",
    "timestamp",
    "height",
    true,
    1,
    "cnn",
    32,
    "data_hash",
    "challenge_hash",
    "ipfs_cid"
  ]
}
```

**Fields**:
- `params[0]`: Job ID (string)
- `params[1]`: Previous block hash (hex)
- `params[2]`: Coinbase TX part 1 (hex)
- `params[3]`: Coinbase TX part 2 (hex)
- `params[4]`: Merkle branches (array of hex)
- `params[5]`: Version (string)
- `params[6]`: Bits/difficulty (string)
- `params[7]`: Timestamp (integer)
- `params[8]`: Block height (integer)
- `params[9]`: Clean jobs (boolean)
- `params[10]`: Task ID (integer: 1=exoplanet, 2=galaxy, 3=anomaly)
- `params[11]`: Model variant (string: cnn/transformer/mamba/convnext)
- `params[12]`: Batch size (integer: 16-128)
- `params[13]`: Data hash (hex)
- `params[14]`: Challenge hash (hex)
- `params[15]`: IPFS CID (string)

---

### mining.submit

Miner submits completed work.

**Request**:
```json
{
  "id": 3,
  "method": "mining.submit",
  "params": [
    "miner_id",
    "job_id",
    "extranonce2",
    "timestamp",
    "output_hash",
    75,
    {"prediction": "PLANET", "confidence": 0.87},
    "Qm1234567890"
  ]
}
```

**Response**:
```json
{
  "id": 3,
  "result": true,
  "error": null
}
```

**Fields**:
- `params[0]`: Miner ID
- `params[1]`: Job ID
- `params[2]`: Extranonce2 (hex)
- `params[3]`: Timestamp (string)
- `params[4]`: Output hash (hex, 64 chars)
- `params[5]`: Quality score (integer: 50-100)
- `params[6]`: Predictions (object)
- `params[7]`: IPFS CID (string)

---

### mining.set_difficulty

Pool sets difficulty target for miner.

**Notification**:
```json
{
  "method": "mining.set_difficulty",
  "params": [75]
}
```

**Fields**:
- `params[0]`: Difficulty (integer: 50-100)

---

### mining.set_extranonce

Pool sets new extranonce for miner.

**Notification**:
```json
{
  "method": "mining.set_extranonce",
  "params": ["new_extranonce", 4]
}
```

**Fields**:
- `params[0]`: New extranonce (hex)
- `params[1]`: Extranonce size (bytes)

---

### mining.ping

Keepalive message.

**Request**:
```json
{
  "id": 10,
  "method": "mining.ping",
  "params": []
}
```

**Response**:
```json
{
  "id": 10,
  "result": "pong",
  "error": null
}
```

---

## Error Codes

| Code | Message | Description |
|------|---------|-------------|
| 0 | Stale job | Job ID no longer valid |
| 1 | Duplicate share | Same nonce submitted twice |
| 2 | Low difficulty | Quality below threshold |
| 3 | Invalid hash | Output hash malformed |
| 4 | Unauthorized | Miner not authorized |
| 5 | No work | No work available |
| 6 | Invalid params | Missing required fields |

---

## Connection Flow

```
Miner                              Pool
  │                                 │
  │──── mining.subscribe ──────────▶│
  │◀─── subscribe response ────────│
  │                                 │
  │──── mining.authorize ──────────▶│
  │◀─── authorize response ────────│
  │                                 │
  │◀─── mining.set_difficulty ─────│
  │◀─── mining.notify ─────────────│
  │                                 │
  │──── mining.submit ─────────────▶│
  │◀─── submit response ───────────│
  │                                 │
  │◀─── mining.notify ─────────────│
  │     (new work)                  │
  │                                 │
```

---

## Example Client

```python
import websockets
import json

async def mine():
    async with websockets.connect("ws://pool.voidmap.org:3333") as ws:
        # Subscribe
        await ws.send(json.dumps({
            "id": 1,
            "method": "mining.subscribe",
            "params": ["my_miner"]
        }))
        resp = json.loads(await ws.recv())
        extranonce = resp["result"][1]

        # Authorize
        await ws.send(json.dumps({
            "id": 2,
            "method": "mining.authorize",
            "params": ["my_miner", "worker1"]
        }))
        resp = json.loads(await ws.recv())

        # Receive work
        work_msg = json.loads(await ws.recv())
        job_id = work_msg["params"][0]

        # Process and submit
        await ws.send(json.dumps({
            "id": 3,
            "method": "mining.submit",
            "params": ["my_miner", job_id, "0000", "1234567890", "abc...", 75, {}, ""]
        }))
        resp = json.loads(await ws.recv())
        print(f"Share accepted: {resp['result']}")
```

---

## Python Library

```python
from stratum import StratumProtocol, WorkUnit

# Create subscribe message
msg = StratumProtocol.subscribe("my_miner")
print(msg.to_json())

# Parse response
resp = StratumMessage.from_json('{"id":1,"result":[1,"abcd1234",4]}')
print(resp.result)
```
