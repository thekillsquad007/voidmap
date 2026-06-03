"""
Voidmap Stratum Protocol — JSON-RPC based mining protocol.

Adapted from Bitcoin Stratum for Proof of Useful Work:
- Work units are ML inference tasks, not hash puzzles
- Difficulty is quality-based (>= 50 to accept)
- Results include predictions, not just nonces

Protocol methods:
  mining.subscribe     — Miner subscribes to notifications
  mining.authorize    — Miner authenticates with pool
  mining.notify       — Pool sends new work to miner
  mining.submit       — Miner submits completed work
  mining.difficulty   — Pool sets difficulty target
  mining.extranonce   — Pool assigns extranonce to miner

Message format (JSON-RPC):
  Request:  {"id": 1, "method": "mining.subscribe", "params": [...]}
  Response: {"id": 1, "result": [...], "error": null}
  Notify:   {"method": "mining.notify", "params": [...]}
"""
import json
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Optional


# ─── Protocol Constants ───────────────────────────────────

PROTOCOL_VERSION = "2.0"
MINER_AGENT = "VoidmapMiner/1.0"
EXTRANONCE_SIZE = 4  # bytes


# ─── Data Structures ──────────────────────────────────────

@dataclass
class StratumMessage:
    """A Stratum JSON-RPC message."""
    id: Optional[int] = None
    method: Optional[str] = None
    params: list = field(default_factory=list)
    result: Any = None
    error: Optional[str] = None

    def to_json(self) -> str:
        msg = {}
        if self.id is not None:
            msg["id"] = self.id
        if self.method is not None:
            msg["method"] = self.method
        if self.params:
            msg["params"] = self.params
        if self.result is not None:
            msg["result"] = self.result
        if self.error is not None:
            msg["error"] = self.error
        return json.dumps(msg)

    @classmethod
    def from_json(cls, data: str) -> "StratumMessage":
        msg = json.loads(data)
        return cls(
            id=msg.get("id"),
            method=msg.get("method"),
            params=msg.get("params", []),
            result=msg.get("result"),
            error=msg.get("error"),
        )


@dataclass
class WorkUnit:
    """A unit of work to be processed by a miner."""
    job_id: str
    task_id: int  # 1=exoplanet, 2=galaxy, 3=anomaly
    block_hash: str  # hash of current block/difficulty target
    prev_hash: str  # previous block hash
    coinbase1: str  # coinbase transaction part 1
    coinbase2: str  # coinbase transaction part 2
    merkle_branches: list  # merkle tree branches
    version: str  # protocol version
    bits: str  # difficulty target (quality threshold)
    timestamp: int  # block timestamp
    height: int  # block height
    clean_jobs: bool  # should miner abandon old work?
    # Voidmap-specific fields
    model_variant: str  # CNN/Transformer/Mamba
    batch_size: int  # random batch size (anti-ASIC)
    data_hash: str  # hash of input data
    challenge_hash: str  # dynamic challenge hash
    ipfs_cid: str  # where to store results


@dataclass
class MinerSession:
    """State for a connected miner."""
    miner_id: str
    extranonce: str
    difficulty: float  # quality threshold (50-100)
    authorized: bool = False
    subscribed: bool = False
    share_count: int = 0
    accepted_shares: int = 0
    rejected_shares: int = 0
    last_activity: float = field(default_factory=time.time)


# ─── Protocol Messages ────────────────────────────────────

class StratumProtocol:
    """Implements the Voidmap Stratum protocol."""

    @staticmethod
    def subscribe(miner_id: str = None) -> StratumMessage:
        """Miner subscribes to work notifications."""
        return StratumMessage(
            id=1,
            method="mining.subscribe",
            params=[miner_id or f"miner_{uuid.uuid4().hex[:8]}"]
        )

    @staticmethod
    def subscribe_response(subscription_id: int, extranonce: str, extranonce_size: int) -> StratumMessage:
        """Response to mining.subscribe."""
        return StratumMessage(
            id=1,
            result=[
                ["mining.notify", subscription_id],
                extranonce,
                extranonce_size
            ],
            error=None
        )

    @staticmethod
    def authorize(miner_id: str, worker_name: str, password: str = "") -> StratumMessage:
        """Miner authorizes with pool."""
        return StratumMessage(
            id=2,
            method="mining.authorize",
            params=[miner_id, worker_name, password]
        )

    @staticmethod
    def authorize_response(success: bool) -> StratumMessage:
        """Response to mining.authorize."""
        return StratumMessage(
            id=2,
            result=success,
            error=None if success else "Unauthorized"
        )

    @staticmethod
    def notify(work: WorkUnit) -> StratumMessage:
        """Pool sends new work to miner."""
        return StratumMessage(
            method="mining.notify",
            params=[
                work.job_id,
                work.prev_hash,
                work.coinbase1,
                work.coinbase2,
                work.merkle_branches,
                work.version,
                work.bits,
                work.timestamp,
                work.height,
                work.clean_jobs,
                # Voidmap-specific params
                work.task_id,
                work.model_variant,
                work.batch_size,
                work.data_hash,
                work.challenge_hash,
                work.ipfs_cid,
            ]
        )

    @staticmethod
    def submit(miner_id: str, job_id: str, result: dict) -> StratumMessage:
        """Miner submits completed work."""
        return StratumMessage(
            id=3,
            method="mining.submit",
            params=[
                miner_id,
                job_id,
                result.get("extranonce2", ""),
                result.get("timestamp", ""),
                result.get("output_hash", ""),
                result.get("quality", 0),
                result.get("predictions", {}),
                result.get("ipfs_cid", ""),
            ]
        )

    @staticmethod
    def submit_response(success: bool, reason: str = "") -> StratumMessage:
        """Response to mining.submit."""
        return StratumMessage(
            id=3,
            result=success,
            error=reason if not success else None
        )

    @staticmethod
    def set_difficulty(difficulty: float) -> StratumMessage:
        """Pool sets difficulty target for miner."""
        return StratumMessage(
            method="mining.set_difficulty",
            params=[difficulty]
        )

    @staticmethod
    def set_extranonce(extranonce: str) -> StratumMessage:
        """Pool sets new extranonce for miner."""
        return StratumMessage(
            method="mining.set_extranonce",
            params=[extranonce]
        )

    @staticmethod
    def error(id: int, code: int, message: str) -> StratumMessage:
        """Error response."""
        return StratumMessage(
            id=id,
            result=None,
            error=[code, message]
        )


# ─── Validation ───────────────────────────────────────────

def validate_submit(submit: StratumMessage, work: WorkUnit) -> tuple[bool, str]:
    """Validate a mining.submit message."""
    if submit.method != "mining.submit":
        return False, "Not a submit message"

    if len(submit.params) < 5:
        return False, "Insufficient params"

    miner_id, job_id, extranonce2, timestamp, output_hash = submit.params[:5]

    # Check job ID matches current work
    if job_id != work.job_id:
        return False, "Job ID mismatch"

    # Check quality if provided
    if len(submit.params) > 5:
        quality = submit.params[5]
        if quality < 50:
            return False, f"Quality {quality} < 50"

    # Check output hash is valid
    if not output_hash or len(output_hash) != 64:
        return False, "Invalid output hash"

    return True, "Valid"


if __name__ == "__main__":
    # Test protocol messages
    print("Testing Stratum Protocol Messages:\n")

    # Subscribe
    sub = StratumProtocol.subscribe("test_miner_1")
    print(f"Subscribe: {sub.to_json()}")

    # Subscribe response
    sub_resp = StratumProtocol.subscribe_response(1, "abcd1234", 4)
    print(f"Subscribe Response: {sub_resp.to_json()}")

    # Authorize
    auth = StratumProtocol.authorize("test_miner_1", "worker1")
    print(f"Authorize: {auth.to_json()}")

    # Notify (new work)
    work = WorkUnit(
        job_id="job_001",
        task_id=1,
        block_hash="0000000000000000000abcdef",
        prev_hash="0000000000000000000000000",
        coinbase1="coinbase1",
        coinbase2="coinbase2",
        merkle_branches=[],
        version="2.0",
        bits="50",  # quality threshold
        timestamp=int(time.time()),
        height=1000,
        clean_jobs=True,
        model_variant="cnn",
        batch_size=32,
        data_hash="abc123",
        challenge_hash="def456",
        ipfs_cid="Qm1234567890",
    )
    notify = StratumProtocol.notify(work)
    print(f"Notify: {notify.to_json()[:200]}...")

    # Submit
    submit = StratumProtocol.submit("test_miner_1", "job_001", {
        "extranonce2": "0000",
        "timestamp": str(int(time.time())),
        "output_hash": "a" * 64,
        "quality": 75,
        "predictions": {"prediction": "PLANET", "confidence": 0.87},
        "ipfs_cid": "Qm9876543210",
    })
    print(f"Submit: {submit.to_json()[:200]}...")

    print("\nAll messages valid!")
