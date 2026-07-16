"""Voidmap TUI Miner — Rich-powered live dashboard.

A one-command, full-screen mining experience with:
  - Live GPU + backend status
  - Current task + target + prediction
  - VOID balance + earnings
  - Recent discoveries with chime
  - Keyboard shortcuts: q=quit, p=pause, t=switch task, s=submit, d=discoveries

Run: voidmap [options]
"""
from __future__ import annotations

import argparse
import os
import sys
import time
import threading
from datetime import datetime, timedelta
from pathlib import Path

try:
    from rich.console import Console
    from rich.live import Live
    from rich.layout import Layout
    from rich.panel import Panel
    from rich.table import Table
    from rich.text import Text
    from rich.align import Align
    from rich import box
    HAS_RICH = True
except ImportError:
    HAS_RICH = False

from .engine import MineEngine, MineResult, KNOWN_TARGETS, RESULTS_DIR
from .hardware import detect_hardware, HardwareInfo


# ─── Discovery chime (optional, with sounddevice) ─────────

def play_discovery_chime():
    """Play a short pleasant chime on high-confidence discovery."""
    try:
        import numpy as np
        # Generate a simple sine wave chord
        sample_rate = 22050
        duration = 0.8
        t = np.linspace(0, duration, int(sample_rate * duration), False)
        # C5, E5, G5 chord
        chord = (
            np.sin(2 * np.pi * 523.25 * t) * 0.3 +
            np.sin(2 * np.pi * 659.25 * t) * 0.3 +
            np.sin(2 * np.pi * 783.99 * t) * 0.3
        )
        # Fade out
        chord *= np.exp(-t * 2)

        # Try sounddevice first
        try:
            import sounddevice as sd
            sd.play(chord, sample_rate, blocking=False)
            return
        except ImportError:
            pass

        # Try winsound on Windows
        try:
            import winsound
            winsound.MessageBeep(winsound.MB_ICONASTERISK)
            return
        except ImportError:
            pass

        # Try macOS afplay
        if sys.platform == "darwin":
            os.system("afplay /System/Library/Sounds/Glass.aiff &")
            return

        # Try Linux aplay
        if sys.platform.startswith("linux"):
            os.system("aplay -q /usr/share/sounds/sound-icons/glass-water.wav 2>/dev/null &")
    except Exception:
        pass  # No audio, silent


# ─── TUI Dashboard ─────────────────────────────────────────

class TUIMiner:
    """Live dashboard for Voidmap mining."""

    def __init__(self, task: str = "exoplanet", submit: bool = False,
                 rpc: str = None, pk: str = None, rounds: int = 0,
                 idle: bool = False):
        if not HAS_RICH:
            print("Error: 'rich' required for TUI. Install: pip install rich")
            sys.exit(1)
        self.console = Console()
        self.task_name = task
        self.submit = submit
        self.rpc = rpc
        self.pk = pk
        self.rounds_total = rounds  # 0 = infinite
        self.idle_mode = idle

        self.engine = MineEngine()
        self.running = True
        self.paused = False
        self.target_idx = 0
        self.discoveries: list[MineResult] = []
        self.recent: list[MineResult] = []
        self.start_time = time.time()
        self.last_round_time = 0
        self.round_count = 0
        self.errors = 0
        self._sub_lock = threading.Lock()

        # Discoveries board
        self.discoveries_log: list[dict] = []
        self._load_discoveries()

    def _load_discoveries(self):
        """Load past high-confidence results from disk."""
        try:
            for f in sorted(RESULTS_DIR.glob("exoplanet_*.json"), reverse=True)[:5]:
                import json
                with open(f) as fp:
                    r = json.load(fp)
                if r.get("prediction") == "PLANET" and r.get("confidence", 0) >= 0.85:
                    self.discoveries_log.append({
                        "target": r.get("target", "?"),
                        "confidence": r.get("confidence", 0),
                        "timestamp": r.get("timestamp", 0),
                        "tx": r.get("tx_hash", ""),
                    })
        except Exception:
            pass

    def _build_layout(self) -> Layout:
        layout = Layout()
        layout.split_column(
            Layout(name="header", size=3),
            Layout(name="body"),
            Layout(name="footer", size=3),
        )
        layout["body"].split_row(
            Layout(name="left"),
            Layout(name="right"),
        )
        layout["left"].split_column(
            Layout(name="status", size=12),
            Layout(name="current"),
        )
        layout["right"].split_column(
            Layout(name="stats", size=10),
            Layout(name="discoveries"),
        )
        return layout

    def _render_header(self) -> Panel:
        runtime = int(time.time() - self.start_time)
        h, m, s = runtime // 3600, (runtime // 60) % 60, runtime % 60
        runtime_str = f"{h:02d}:{m:02d}:{s:02d}"

        title = Text()
        title.append("◆ VOIDMAP ", style="bold magenta")
        title.append("Proof of Useful Work ", style="white")
        title.append(f"  ⏱  {runtime_str}  ", style="cyan")
        if self.paused:
            title.append("  ⏸ PAUSED  ", style="yellow bold")
        else:
            title.append("  ▶ MINING  ", style="green bold")
        if self.submit:
            title.append("  [ON-CHAIN]  ", style="bright_green")

        return Panel(Align.center(title), box=box.DOUBLE, style="magenta")

    def _render_status(self) -> Panel:
        hw = self.engine.hw
        table = Table.grid(padding=(0, 2))
        table.add_column(style="bold", justify="right")
        table.add_column()

        table.add_row("GPU:", f"[cyan]{hw.gpu_name}[/]")
        table.add_row("Backend:", f"[green]{hw.backend.value}[/]")
        table.add_row("PyTorch:", hw.pytorch_version or "[dim]—[/]")
        table.add_row("ONNX:", hw.onnx_version or "[dim]—[/]")
        if hw.onnx_providers:
            table.add_row("Providers:", f"[dim]{', '.join(hw.onnx_providers[:2])}[/]")
        table.add_row("Platform:", hw.platform.split("-")[0])
        if hw.is_hiveos:
            table.add_row("Env:", "[yellow bold]HiveOS[/]")
        table.add_row("Task:", f"[magenta]{self.task_name}[/]")

        if self.target_idx < len(KNOWN_TARGETS) and self.task_name == "exoplanet":
            t = KNOWN_TARGETS[self.target_idx]
            table.add_row("Target:", f"[white]{t['name']}[/]")
            table.add_row("TIC:", f"[dim]{t['tic']}[/]")
        elif self.task_name == "galaxy":
            table.add_row("Target:", "[white]random SDSS galaxy[/]")

        if self.idle_mode:
            table.add_row("Mode:", "[yellow]⏸ idle mining[/]")

        return Panel(table, title="[bold]⚙ System[/]", border_style="cyan")

    def _render_current(self) -> Panel:
        if not self.recent:
            content = Text("Waiting for first round...", style="dim italic")
        else:
            r = self.recent[-1]
            content = Text()
            content.append(f"Target: ", style="bold")
            content.append(f"{r.target}\n", style="cyan")
            content.append(f"Prediction: ", style="bold")
            color = "green" if r.prediction == "PLANET" else "yellow" if r.prediction == "FALSE_POSITIVE" else "red"
            content.append(f"{r.prediction}", style=f"{color} bold")
            content.append(f" ({r.confidence:.1%})\n")
            content.append(f"Quality: ", style="bold")
            qcolor = "green" if r.quality_score >= 70 else "yellow" if r.quality_score >= 50 else "red"
            content.append(f"{r.quality_score}/100\n", style=f"{qcolor} bold")
            content.append(f"Samples: ", style="bold")
            content.append(f"{r.samples}\n")
            content.append(f"Duration: ", style="bold")
            content.append(f"{r.duration_ms}ms\n")
            content.append(f"Backend: ", style="bold")
            content.append(f"{r.backend}\n")
            content.append(f"Est. VOID: ", style="bold")
            content.append(f"{r.extra.get('est_void', 0):.2f}\n", style="magenta")
            if r.ipfs_cid:
                content.append(f"IPFS: ", style="bold")
                content.append(f"{r.ipfs_cid[:20]}...\n", style="dim")
            if r.extra.get("tx_hash"):
                content.append(f"TX: ", style="bold")
                content.append(f"{r.extra['tx_hash'][:16]}...\n", style="dim green")
        return Panel(content, title="[bold]🔭 Current Round[/]", border_style="magenta")

    def _render_stats(self) -> Panel:
        stats = self.engine.stats()
        rate = stats["rate_per_hour"]

        table = Table.grid(padding=(0, 2))
        table.add_column(style="bold", justify="right")
        table.add_column()

        table.add_row("Rounds:", f"[cyan]{stats['rounds']}[/]")
        table.add_row("Rate:", f"[cyan]{rate:.1f}/hr[/]")
        table.add_row("Avg quality:", f"[cyan]{stats['avg_quality']:.0f}/100[/]")
        table.add_row("VOID est.:", f"[magenta bold]⌬ {stats['total_void']:.2f}[/]")
        table.add_row("Discoveries:", f"[green bold]★ {stats['discoveries']}[/]")
        table.add_row("Errors:", f"[{'red' if self.errors else 'dim'}] {self.errors}[/]")

        if self.rounds_total > 0:
            pct = self.round_count / self.rounds_total * 100
            table.add_row("Progress:", f"[cyan]{self.round_count}/{self.rounds_total} ({pct:.0f}%)[/]")

        return Panel(table, title="[bold]📊 Stats[/]", border_style="green")

    def _render_discoveries(self) -> Panel:
        if not self.discoveries_log and not self.discoveries:
            content = Text("No discoveries yet. Keep mining!", style="dim italic")
        else:
            content = Text()
            for d in self.discoveries_log[:5]:
                ts = datetime.fromtimestamp(d["timestamp"]).strftime("%m-%d %H:%M")
                content.append(f"  ★ ", style="yellow")
                content.append(f"{d['target']}", style="cyan bold")
                content.append(f" ({d['confidence']:.0%}) ", style="dim")
                content.append(f" {ts}", style="dim")
                if d.get("tx"):
                    content.append(f"  [TX ✓]", style="green")
                content.append("\n")
        return Panel(content, title="[bold]🌟 Recent Discoveries[/]", border_style="yellow")

    def _render_footer(self) -> Panel:
        help_text = Text()
        help_text.append("[q]", style="bold red")
        help_text.append("uit  ")
        help_text.append("[p]", style="bold yellow")
        help_text.append("ause  ")
        help_text.append("[t]", style="bold cyan")
        help_text.append("ask  ")
        help_text.append("[d]", style="bold green")
        help_text.append("iscoveries  ")
        help_text.append("[r]", style="bold blue")
        help_text.append("esults  ")
        help_text.append("[Enter]", style="bold magenta")
        help_text.append(" = mine 1 round")
        return Panel(Align.center(help_text), box=box.ROUNDED)

    def _render(self) -> Layout:
        layout = self._build_layout()
        layout["header"].update(self._render_header())
        layout["footer"].update(self._render_footer())
        layout["status"].update(self._render_status())
        layout["current"].update(self._render_current())
        layout["stats"].update(self._render_stats())
        layout["discoveries"].update(self._render_discoveries())
        return layout

    def _mine_one(self):
        """Mine one round (called in background thread)."""
        try:
            with self._sub_lock:
                result = self.engine.mine_one(self.task_name, target_idx=self.target_idx)
                self.round_count += 1

                # Save result
                result.save()

                # Submit if requested
                if self.submit and self.pk and self.rpc:
                    try:
                        from .submit import submit_result
                        tx_hash = submit_result(result, self.rpc, self.pk)
                        result.extra["tx_hash"] = tx_hash
                    except Exception as e:
                        self.errors += 1
                        result.extra["submit_error"] = str(e)

                # Track
                self.recent.append(result)
                if len(self.recent) > 10:
                    self.recent.pop(0)

                if result.is_discovery:
                    self.discoveries.append(result)
                    self.discoveries_log.insert(0, {
                        "target": result.target,
                        "confidence": result.confidence,
                        "timestamp": result.timestamp,
                        "tx": result.extra.get("tx_hash", ""),
                    })
                    if len(self.discoveries_log) > 10:
                        self.discoveries_log.pop()
                    # Play chime
                    if not self.paused:
                        threading.Thread(target=play_discovery_chime, daemon=True).start()

                # Rotate target
                if self.task_name == "exoplanet":
                    self.target_idx = (self.target_idx + 1) % len(KNOWN_TARGETS)
        except Exception as e:
            self.errors += 1
            if HAS_RICH:
                self.console.print(f"[red]Mining error:[/] {e}")
        finally:
            self.last_round_time = time.time()

    def _input_thread(self, live: Live):
        """Watch for keyboard input."""
        try:
            import select
            import tty
            import termios
            old_settings = termios.tcgetattr(sys.stdin)
            tty.setcbreak(sys.stdin.fileno())
        except Exception:
            old_settings = None

        try:
            while self.running:
                if old_settings is not None:
                    if select.select([sys.stdin], [], [], 0.1)[0]:
                        ch = sys.stdin.read(1).lower()
                        if ch == 'q':
                            self.running = False
                            break
                        elif ch == 'p':
                            self.paused = not self.paused
                        elif ch == 't':
                            self._switch_task()
                        elif ch == 'd':
                            self._show_discoveries()
                        elif ch == 'r':
                            self._show_recent()
                        elif ch == '\r' or ch == '\n':
                            if not self.paused:
                                self._mine_one()
                else:
                    # No tty — sleep
                    time.sleep(0.1)
        finally:
            if old_settings is not None:
                try:
                    termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
                except Exception:
                    pass

    def _switch_task(self):
        tasks = ["exoplanet", "galaxy", "anomaly"]
        idx = tasks.index(self.task_name) if self.task_name in tasks else 0
        self.task_name = tasks[(idx + 1) % len(tasks)]

    def _show_discoveries(self):
        with self.console.screen():
            self.console.clear()
            self.console.print("[bold yellow]🌟 Discoveries[/]\n", justify="center")
            if not self.discoveries_log:
                self.console.print("No discoveries yet.", style="dim")
            else:
                for d in self.discoveries_log:
                    ts = datetime.fromtimestamp(d["timestamp"]).strftime("%Y-%m-%d %H:%M")
                    self.console.print(f"  ★ [cyan]{d['target']}[/] ({d['confidence']:.1%}) — {ts}")
                    if d.get("tx"):
                        self.console.print(f"    [dim green]TX: {d['tx']}[/]")
            self.console.print("\n[dim]Press Enter to return...[/]")
            input()

    def _show_recent(self):
        with self.console.screen():
            self.console.clear()
            self.console.print("[bold green]📋 Recent Rounds[/]\n", justify="center")
            for r in reversed(self.recent):
                color = "green" if r.prediction == "PLANET" else "yellow" if r.prediction == "FALSE_POSITIVE" else "red"
                self.console.print(
                    f"  [cyan]{r.target}[/] → [{color}]{r.prediction}[/] "
                    f"({r.confidence:.1%}) Q={r.quality_score} {r.duration_ms}ms"
                )
            self.console.print("\n[dim]Press Enter to return...[/]")
            input()

    def run(self):
        """Run the TUI dashboard."""
        if not HAS_RICH:
            print("Error: rich library required for TUI. Install: pip install rich")
            return 1

        self.console.print("[bold magenta]◆ VOIDMAP TUI Miner[/]")
        self.console.print(f"GPU: [cyan]{self.engine.hw.gpu_name}[/]")
        self.console.print(f"Backend: [green]{self.engine.hw.backend.value}[/]")
        self.console.print(f"Task: [magenta]{self.task_name}[/]")
        if self.submit:
            self.console.print(f"[green]Mode: ON-CHAIN submission enabled[/]")
        self.console.print()
        self.console.print("[dim]Press 'q' to quit, 'Enter' to mine a round, 'p' to pause[/]")
        self.console.print()

        try:
            with Live(self._render(), refresh_per_second=4, screen=True) as live:
                # Start input thread
                input_t = threading.Thread(target=self._input_thread, args=(live,), daemon=True)
                input_t.start()

                # Main loop: mine on cooldown
                while self.running:
                    if self.rounds_total > 0 and self.round_count >= self.rounds_total:
                        break
                    
                    # Idle Mode: Check if system is idle before mining
                    if self.idle_mode:
                        if not self.engine.hw.is_system_idle():
                            self.paused = True
                            live.update(self._render())
                            time.sleep(5)
                            continue
                        else:
                            self.paused = False

                    if not self.paused:
                        # Mine one round
                        self._mine_one()
                        # Cooldown
                        if self.rounds_total == 0 or self.round_count < self.rounds_total:
                            for _ in range(12):  # 12s cooldown, updated 1Hz
                                if not self.running or self.paused:
                                    break
                                live.update(self._render())
                                time.sleep(1)
                        else:
                            live.update(self._render())
                            time.sleep(0.25)
                    else:
                        live.update(self._render())
                        time.sleep(0.5)
        except KeyboardInterrupt:
            pass

        # Final stats
        stats = self.engine.stats()
        self.console.print()
        self.console.print("[bold green]◆ Mining stopped[/]")
        self.console.print(f"  Rounds: {stats['rounds']}")
        self.console.print(f"  Runtime: {stats['elapsed_s']}s")
        self.console.print(f"  VOID est.: {stats['total_void']:.2f}")
        self.console.print(f"  Discoveries: {stats['discoveries']}")
        return 0


# ─── Public API (for non-TUI use) ─────────────────────────

def detect_only():
    """CLI: print hardware + backend info, exit."""
    hw = detect_hardware(force=True)
    print()
    print(f"  GPU: {hw.gpu_name} ({hw.gpu.value})")
    print(f"  Backend: {hw.backend.value}")
    if hw.pytorch_version:
        print(f"  PyTorch: {hw.pytorch_version}")
    if hw.onnx_version:
        print(f"  ONNX Runtime: {hw.onnx_version}")
    if hw.onnx_providers:
        print(f"  ONNX Providers: {', '.join(hw.onnx_providers)}")
    print(f"  Platform: {hw.platform}")
    if hw.is_hiveos:
        print(f"  Environment: HiveOS")
    if hw.notes:
        print(f"\n  Notes:")
        for n in hw.notes:
            print(f"    - {n}")
    print()


def mine_cli():
    """CLI: mine N rounds non-interactively."""
    p = argparse.ArgumentParser(description="Voidmap non-TUI miner")
    p.add_argument("--task", choices=["exoplanet", "galaxy", "anomaly"], default="exoplanet")
    p.add_argument("--rounds", type=int, default=1)
    p.add_argument("--target-idx", type=int)
    p.add_argument("--submit", action="store_true")
    p.add_argument("--rpc", help="Base RPC URL")
    p.add_argument("--pk", help="Wallet private key")
    args = p.parse_args()

    engine = MineEngine()
    print(f"\n  ◆ VOIDMAP MINER — Non-TUI Mode")
    print(f"  GPU: {engine.hw.gpu_name}")
    print(f"  Backend: {engine.hw.backend.value}")
    print(f"  Task: {args.task}")
    print(f"  Rounds: {args.rounds}\n")

    for i in range(args.rounds):
        try:
            r = engine.mine_one(args.task, target_idx=args.target_idx)
            r.save()
            print(f"  [{i+1}/{args.rounds}] {r.target}: {r.prediction} "
                  f"({r.confidence:.1%}) Q={r.quality_score} {r.duration_ms}ms")
            if r.is_discovery:
                print(f"    ★ DISCOVERY!")
            if args.submit and args.rpc and args.pk:
                try:
                    from .submit import submit_result
                    tx = submit_result(r, args.rpc, args.pk)
                    r.extra["tx_hash"] = tx
                    print(f"    TX: {tx[:16]}...")
                except Exception as e:
                    print(f"    Submit failed: {e}")
        except Exception as e:
            print(f"  [{i+1}/{args.rounds}] Error: {e}")

    stats = engine.stats()
    print(f"\n  Done. {stats['rounds']} rounds, {stats['total_void']:.2f} VOID est., {stats['discoveries']} discoveries.")


# ─── Entry point ───────────────────────────────────────────

def main():
    """Main TUI entry point."""
    p = argparse.ArgumentParser(description="Voidmap TUI Miner")
    p.add_argument("--task", choices=["exoplanet", "galaxy", "anomaly", "all"],
                   default="exoplanet")
    p.add_argument("--rounds", type=int, default=0, help="0 = infinite")
    p.add_argument("--submit", action="store_true", help="Submit results on-chain")
    p.add_argument("--rpc", help="Base RPC URL (for --submit)")
    p.add_argument("--pk", help="Wallet private key (for --submit)")
    p.add_argument("--idle", action="store_true", help="Idle mining (auto-mine when CPU/GPU is free)")
    p.add_argument("--no-tui", action="store_true", help="Run non-TUI mode")
    p.add_argument("--detect", action="store_true", help="Show hardware info and exit")
    args = p.parse_args()

    if args.detect:
        detect_only()
        return 0

    if args.no_tui or not sys.stdout.isatty():
        # Non-TUI
        sys.argv = [sys.argv[0]]
        for opt in ["--task", "--rounds", "--submit", "--rpc", "--pk", "--target-idx"]:
            pass
        mine_cli()
        return 0

    tui = TUIMiner(
        task=args.task if args.task != "all" else "exoplanet",
        submit=args.submit,
        rpc=args.rpc,
        pk=args.pk,
        rounds=args.rounds,
        idle=args.idle,
    )
    return tui.run()


if __name__ == "__main__":
    sys.exit(main())
