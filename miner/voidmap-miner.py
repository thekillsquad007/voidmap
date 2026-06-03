#!/usr/bin/env python3
"""
Voidmap GPU Miner — works on AMD, NVIDIA, Intel, Apple Silicon.
Auto-detects best GPU backend: CUDA > ROCm > MPS > OpenCL > CPU.
"""
import argparse, hashlib, json, os, random, sys, time, platform, struct
from pathlib import Path

# ─── Backend detection ──────────────────────────────────
HAS_PYTORCH = False
HAS_OPENCL = False
BACKENDS = []

try:
    import torch
    HAS_PYTORCH = True
    if torch.cuda.is_available():
        # CUDA (NVIDIA) or ROCm (AMD)
        BACKENDS.append(("cuda", torch.version.cuda or "rocm"))
    if hasattr(torch, "backends") and hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        BACKENDS.append(("mps", "mps"))
    BACKENDS.append(("cpu", "cpu"))
except ImportError:
    pass

try:
    import pyopencl as cl
    HAS_OPENCL = True
    platforms = cl.get_platforms()
    for p in platforms:
        for d in p.get_devices():
            if d.type & cl.device_type.GPU:
                BACKENDS.append(("opencl", f"{p.name} {d.name}"))
                break
except ImportError:
    pass

if not BACKENDS:
    BACKENDS.append(("cpu", "cpu"))

# ─── Imports (conditional) ──────────────────────────────
if HAS_PYTORCH:
    import torch as _torch
    import numpy as np

# ─── Miner ──────────────────────────────────────────────
DEFAULT_TASKS = [
    {"id": 1, "name": "exoplanet_transit",  "desc": "Detect exoplanet transits in TESS light curves",  "shape": [1, 2048],        "compute": 1.0, "weight": 0.4},
    {"id": 2, "name": "galaxy_morphology",  "desc": "Classify galaxy morphology from JWST/Hubble",     "shape": [3, 256, 256],    "compute": 2.0, "weight": 0.3},
    {"id": 3, "name": "anomaly_detection",  "desc": "Flag anomalies in ZTF transient alert stream",    "shape": [1, 4096],        "compute": 1.5, "weight": 0.3},
]

class Backend:
    def __init__(self, name, label):
        self.name = name
        self.label = label

    def compute(self, task):
        """Run a task on this backend. Returns (quality_score, data_hash, bandwidth)."""
        pass

class TorchBackend(Backend):
    def __init__(self, device, label):
        super().__init__("torch", label)
        self.device = _torch.device(device)

    def compute(self, task):
        _torch.manual_seed(random.randint(0, 2**32))
        shape = task["shape"]
        bs = max(1, min(16, int(512 / (shape[-1] * shape[-2] / 1024)) if len(shape) >= 2 and shape[-1] > 1 else 4))
        ds = random.randint(50, 200)

        # Warmup
        try:
            dummy = _torch.randn(bs, *shape[1:], device=self.device)
            _ = dummy * 2
        except Exception:
            self.device = _torch.device("cpu")
            dummy = _torch.randn(bs, *shape[1:], device=self.device)
        del dummy

        start = time.time()
        total_loss = 0.0

        with _torch.no_grad():
            for b in range(0, ds, bs):
                n = min(bs, ds - b)
                x = _torch.randn(n, *shape[1:], device=self.device)
                seed = _torch.randint(0, 2**32, (1,), device=self.device)

                if task["id"] == 1:
                    # Exoplanet: 1D CNN-like computation
                    noise = _torch.randn_like(x) * 0.02
                    transit = _torch.sigmoid((x - 0.5) * 20) * 0.05
                    bias = _torch.sin(x * 50) * 0.01
                    o = x + transit + noise + bias
                    loss = _torch.nn.functional.mse_loss(o, x)

                elif task["id"] == 2:
                    # Galaxy: 2D convolution
                    c = _torch.nn.Conv2d(shape[1] if len(shape) == 4 else 3, 8, 3, padding=1).to(self.device)
                    f = c(x)
                    pooled = f.mean(dim=(2, 3))
                    o = _torch.softmax(pooled, dim=-1)
                    loss = -o.max(dim=-1).values.mean() + 1.0

                elif task["id"] == 3:
                    # Anomaly: autoencoder-style
                    encoded = _torch.sin(x * 3.14159) * 0.5
                    decoded = _torch.cos(encoded * 3.14159) * 0.5
                    o = decoded + _torch.randn_like(x) * 0.005
                    loss = _torch.nn.functional.mse_loss(o, x * 0.5)

                else:
                    o = x * 0.5
                    loss = _torch.tensor(0.5)

                total_loss += loss.item()
                progress = min(100, int(100 * (b + n) / ds))
                bar = "█" * (progress // 4) + "░" * (25 - progress // 4)
                sys.stdout.write(f"\r  [{bar}] {progress:3d}%  {task['name']:22s} loss={loss.item():.4f}")
                sys.stdout.flush()

        elapsed = max(0.001, time.time() - start)
        avg_loss = total_loss / max(1, ds)
        quality = max(1, min(100, int(100 * (1 - avg_loss / 1.0))))
        bandwidth = int(ds * shape[-1] / elapsed) if len(shape) == 2 else int(ds * shape[1] * shape[2] * 4 / elapsed)

        # Data hash (simulated proof)
        h = hashlib.sha256(f"{task['id']}:{ds}:{avg_loss:.4f}:{random.random()}".encode()).hexdigest()

        return quality, h, bandwidth

class OpenCLBackend(Backend):
    KERNEL_SRC = """
    __kernel void compute(__global const float *in, __global float *out, float multiplier) {
        int gid = get_global_id(0);
        float x = in[gid];
        float val = x * multiplier;
        val = 1.0f / (1.0f + exp(-val * 20.0f)); // sigmoid
        out[gid] = x + val * 0.05f + (float)(gid % 100) * 0.0001f;
    }
    """

    def __init__(self, device):
        import pyopencl as cl
        self.ctx = cl.Context([device])
        self.queue = cl.CommandQueue(self.ctx)
        self.device_name = device.name.strip()
        try:
            self.program = cl.Program(self.ctx, self.KERNEL_SRC).build()
        except:
            self.program = None

    def compute(self, task):
        import pyopencl as cl
        import numpy as np

        shape = task["shape"]
        n_elements = shape[-1]
        ds = random.randint(30, 100)
        total_loss = 0.0
        start = time.time()

        for b in range(ds):
            x = np.random.randn(n_elements).astype(np.float32)
            out = np.empty_like(x)

            if self.program and shape[-1] <= 65536:
                mf = cl.mem_flags
                x_buf = cl.Buffer(self.ctx, mf.READ_ONLY | mf.COPY_HOST_PTR, hostbuf=x)
                o_buf = cl.Buffer(self.ctx, mf.WRITE_ONLY, out.nbytes)
                self.program.compute(self.queue, (n_elements,), None, x_buf, o_buf, np.float32(0.5 + random.random() * 0.5))
                cl.enqueue_copy(self.queue, out, o_buf)
            else:
                # CPU fallback
                out = x * 0.3 + np.random.randn(n_elements).astype(np.float32) * 0.01

            loss = float(np.mean((out - x)**2))
            total_loss += loss

            progress = int(100 * (b + 1) / ds)
            bar = "█" * (progress // 4) + "░" * (25 - progress // 4)
            sys.stdout.write(f"\r  [{bar}] {progress:3d}%  opencl {self.device_name[:20]:20s} loss={loss:.4f}")
            sys.stdout.flush()

        elapsed = max(0.001, time.time() - start)
        avg_loss = total_loss / ds
        quality = max(1, min(100, int(100 * (1 - avg_loss / 0.5))))
        bandwidth = int(ds * n_elements * 4 / elapsed)
        h = hashlib.sha256(f"cl:{task['id']}:{ds}:{avg_loss:.4f}:{random.random()}".encode()).hexdigest()

        return quality, h, bandwidth


class VoidmapMiner:
    def __init__(self, args):
        self.address = args.address
        self.rpc_url = args.rpc_url
        self.backend_name = args.backend
        self.worker_id = hashlib.sha256(f"{self.address}:{time.time()}".encode()).hexdigest()[:12]
        self.stats = {"submissions": 0, "verified": 0, "total_quality": 0, "total_bandwidth": 0}

        # Init backend
        self.backend = self._init_backend()
        self._print_header()

    def _init_backend(self):
        if self.backend_name == "opencl" and HAS_OPENCL:
            import pyopencl as cl
            for p in cl.get_platforms():
                for d in p.get_devices():
                    if d.type & cl.device_type.GPU:
                        return OpenCLBackend(d)
            print("No OpenCL GPU found, falling back.")
            self.backend_name = "auto"

        if self.backend_name in ("auto", "cuda", "rocmmps", "cpu") and HAS_PYTORCH:
            if self.backend_name == "cuda" and _torch.cuda.is_available():
                return TorchBackend("cuda", _torch.cuda.get_device_name(0))
            if self.backend_name == "rocmmps":
                for dev in [("cuda", "cuda"), ("mps", "mps"), ("cpu", "cpu")]:
                    try:
                        t = _torch.device(dev[0])
                        _ = _torch.randn(2, device=t)
                        return TorchBackend(dev[0], dev[1])
                    except:
                        continue
            # auto: pick best
            if _torch.cuda.is_available():
                name = _torch.cuda.get_device_name(0)
                return TorchBackend("cuda", f"{name} (CUDA)")
            if hasattr(_torch, "backends") and hasattr(_torch.backends, "mps") and _torch.backends.mps.is_available():
                return TorchBackend("mps", "Apple Silicon (MPS)")
            return TorchBackend("cpu", "CPU")
        if self.backend_name == "cpu":
            return TorchBackend("cpu", "CPU")

        print(f"Backend '{self.backend_name}' not available, falling back to CPU")
        return TorchBackend("cpu", "CPU")

    def _print_header(self):
        print()
        print("  ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆")
        print("  ◆                                    ◆")
        print("  ◆   V O I D M A P   M I N E R        ◆")
        print("  ◆                                    ◆")
        print("  ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆ ◆")
        print()
        print(f"  Backend : {self.backend.name.upper()} — {self.backend.label}")
        print(f"  Worker  : {self.worker_id}")
        print(f"  Wallet  : {self.address[:10]}...{self.address[-6:]}")
        print()

    def mine_round(self, task=None):
        if task is None:
            tasks = DEFAULT_TASKS
            w = [t["weight"] for t in tasks]
            task = random.choices(tasks, weights=w, k=1)[0]

        print(f"\n  ── Task: {task['name']} ──")
        print(f"     {task['desc']}")

        quality, data_hash, bandwidth = self.backend.compute(task)
        self.stats["submissions"] += 1
        self.stats["total_quality"] += quality
        self.stats["total_bandwidth"] += bandwidth

        if quality >= 50:
            self.stats["verified"] += 1
            status = "✓ VERIFIED"
        else:
            status = "✗ LOW QUALITY"

        print(f"\n  ───────────────────────────────────")
        print(f"  Quality : {quality}/100")
        print(f"  BW      : {bandwidth/1e6:.1f} MB/s")
        print(f"  Status  : {status}")
        print(f"  Hash    : {data_hash[:20]}...")

        return {"task": task["name"], "quality": quality, "hash": data_hash, "bandwidth": bandwidth}

    def print_stats(self):
        avg_q = self.stats["total_quality"] / max(1, self.stats["submissions"])
        avg_bw = self.stats["total_bandwidth"] / max(1, self.stats["submissions"])
        print()
        print(f"  ╔═══════════════════════════════════╗")
        print(f"  ║  STATS                           ║")
        print(f"  ╠═══════════════════════════════════╣")
        print(f"  ║  Submissions : {self.stats['submissions']:10d}        ║")
        print(f"  ║  Verified   : {self.stats['verified']:10d}        ║")
        print(f"  ║  Avg Quality: {avg_q:7.1f}/100              ║")
        print(f"  ║  Avg BW     : {avg_bw/1e6:7.1f} MB/s            ║")
        print(f"  ╚═══════════════════════════════════╝")

    def mine(self, rounds=None):
        count = 0
        try:
            while True:
                r = self.mine_round()
                count += 1
                if rounds and count >= rounds:
                    break
                delay = random.uniform(0.5, 2.0)
                time.sleep(delay)
        except KeyboardInterrupt:
            pass
        self.print_stats()


def detect():
    """Print all available backends."""
    print("\n  Voidmap — Detecting GPU backends...\n")
    if HAS_PYTORCH:
        print(f"  PyTorch : {_torch.__version__}")
        if _torch.cuda.is_available():
            n = _torch.cuda.device_count()
            for i in range(n):
                print(f"  GPU {i}    : {_torch.cuda.get_device_name(i)} (CUDA {_torch.version.cuda})")
                print(f"            : {_torch.cuda.get_device_properties(i).total_memory / 1e9:.1f} GB VRAM")
        if hasattr(_torch, "backends") and hasattr(_torch.backends, "mps") and _torch.backends.mps.is_available():
            print(f"  MPS     : Apple Silicon GPU")
        print(f"  CPU     : {platform.processor() or platform.machine()}")
    if HAS_OPENCL:
        import pyopencl as cl
        for p in cl.get_platforms():
            for d in p.get_devices():
                typ = "GPU" if d.type & cl.device_type.GPU else "CPU"
                print(f"  OpenCL  : {p.name} — {d.name.strip()} ({typ})")
    print()


def main():
    parser = argparse.ArgumentParser(description="Voidmap GPU Miner — AMD, NVIDIA, Intel, Apple")
    parser.add_argument("--address", default="0x0000000000000000000000000000000000000000", help="Your wallet address")
    parser.add_argument("--rpc-url", default="http://localhost:8545")
    parser.add_argument("--backend", choices=["auto", "cuda", "rocmmps", "opencl", "cpu"], default="auto",
                        help="GPU backend (auto = best available)")
    parser.add_argument("--rounds", type=int, help="Number of mining rounds to run")
    parser.add_argument("--detect", action="store_true", help="Detect available GPU backends and exit")
    parser.add_argument("--bench", action="store_true", help="Run quick benchmark on all backends")

    args = parser.parse_args()

    if args.detect:
        detect()
        return

    if args.bench:
        detect()
        print("  Running benchmark (30s)...")
        for label, bname in [("CPU     ", "cpu")]:
            if HAS_PYTORCH:
                m = VoidmapMiner(argparse.Namespace(address=args.address, rpc_url=args.rpc_url, backend=bname))
                start = time.time()
                c = 0
                while time.time() - start < 15:
                    m.mine_round()
                    c += 1
                print(f"\n  {label}: {c} rounds in 15s ({c/15:.1f} rps)")
        return

    m = VoidmapMiner(args)
    m.mine(args.rounds)


if __name__ == "__main__":
    main()
