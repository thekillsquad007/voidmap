#!/usr/bin/env python3
"""
Voidmap Daily Stats Bot

Reads on-chain state from the Voidmap contracts and posts daily stats
to Twitter (via tweepy). Designed to run as a daily cron job.

Setup:
    pip install tweepy web3
    export TWITTER_API_KEY=...
    export TWITTER_API_SECRET=...
    export TWITTER_ACCESS_TOKEN=...
    export TWITTER_ACCESS_SECRET=...
    export VOIDMAP_RPC=https://mainnet.base.org
    export VOIDMAP_POOL=0x...
    export VOIDMAP_TOKEN=0x...
    export VOIDMAP_REGISTRY=0x...

Usage:
    python automation/daily_stats.py           # post today's stats
    python automation/daily_stats.py --dry-run  # print without posting
    python automation/daily_stats.py --json     # output JSON only
"""
import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


# ─── Config ───────────────────────────────────────────────

RPC = os.environ.get("VOIDMAP_RPC", "https://mainnet.base.org")
POOL = os.environ.get("VOIDMAP_POOL", "0x3768e25aFc129D4455e267819801f2b2914fA4A2")
TOKEN = os.environ.get("VOIDMAP_TOKEN", "0x8AF20228A724d7420434791EAEA5F7D037865d35")
REGISTRY = os.environ.get("VOIDMAP_REGISTRY", "")

DAY_NUMBER = (datetime.now(timezone.utc) - datetime(2026, 6, 1, tzinfo=timezone.utc)).days + 1


# ─── On-chain queries ─────────────────────────────────────

def _find_cast() -> str:
    """Find cast binary."""
    candidates = [
        os.environ.get("CAST_BIN"),
        os.path.expanduser("~/.foundry/bin/cast"),
        os.path.expanduser("~/.var/app/ai.opencode.opencode/config/.foundry/bin/cast"),
        "cast",
    ]
    for c in candidates:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return "cast"


def cast_call(signature: str, to: str, *args) -> str:
    """Call a contract function via cast."""
    cast = _find_cast()
    cmd = [cast, "call", to, signature] + list(args) + ["--rpc-url", RPC]
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=30, check=True
        )
        return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        return f"0"


def wei_to_void(wei_str: str) -> float:
    """Convert wei string to VOID float."""
    try:
        return int(wei_str) / 1e18
    except (ValueError, TypeError):
        return 0.0


def fetch_stats() -> dict:
    """Fetch all on-chain stats."""
    stats = {
        "day": DAY_NUMBER,
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    }

    # Mining pool stats
    stats["submission_count"] = int(cast_call("submissionCount()(uint256)", POOL) or "0")
    stats["block_reward_void"] = wei_to_void(
        cast_call("getCurrentBlockReward()(uint256)", POOL) or "0"
    )
    stats["halving_epoch"] = int(cast_call("getHalvingEpoch()(uint256)", POOL) or "0")

    # Subscriptions in current epoch
    halving_progress = cast_call(
        "getHalvingProgress()(uint256,uint256,uint256)", POOL
    ).strip("()").split()
    if len(halving_progress) >= 2:
        stats["subs_in_epoch"] = int(halving_progress[1])
    else:
        stats["subs_in_epoch"] = 0

    # Network quality
    avg_q = cast_call("getAvgNetworkQuality()(uint256)", POOL) or "0"
    try:
        stats["avg_quality"] = int(avg_q)
    except ValueError:
        stats["avg_quality"] = 0

    # Token stats
    stats["total_supply"] = wei_to_void(cast_call("totalSupply()(uint256)", TOKEN) or "0")
    stats["total_burned"] = wei_to_void(cast_call("totalBurned()(uint256)", TOKEN) or "0")

    # Registry stats
    if REGISTRY:
        try:
            registry_stats = cast_call(
                "getNetworkStats()(uint256,uint256,uint256,uint256)", REGISTRY
            ).strip("()").split()
            if len(registry_stats) >= 2:
                stats["registry_results"] = int(registry_stats[0])
                stats["registry_samples"] = int(registry_stats[1])
        except Exception:
            pass

    # Compute interesting derived stats
    stats["subs_to_halving"] = max(0, 210_000 - stats["subs_in_epoch"])
    stats["halving_pct"] = round(stats["subs_in_epoch"] / 210_000 * 100, 1)

    return stats


# ─── Tweet formatting ─────────────────────────────────────

def format_tweet(stats: dict) -> str:
    """Format stats as a tweet. Must be ≤ 280 chars."""
    lines = [
        f"🌌 Voidmap Daily Stats — Day {stats['day']}",
        "",
        "📊 Network:",
        f"• Submissions: {stats['submission_count']:,}",
        f"• Avg Quality: {stats['avg_quality']}/100",
        "",
        "💎 Token:",
        f"• Block Reward: {stats['block_reward_void']:.1f} VOID",
        f"• Halving: {stats['halving_pct']:.1f}% (in {stats['subs_to_halving']:,} subs)",
        f"• Burned: {stats['total_burned']:,.0f} VOID",
        "",
        "🌐 explorer.voidmap.org",
    ]
    return "\n".join(lines)


# ─── Twitter posting ─────────────────────────────────────

def post_to_twitter(text: str) -> bool:
    """Post a tweet via tweepy."""
    try:
        import tweepy
    except ImportError:
        print("tweepy not installed: pip install tweepy", file=sys.stderr)
        return False

    api_key = os.environ.get("TWITTER_API_KEY")
    api_secret = os.environ.get("TWITTER_API_SECRET")
    access_token = os.environ.get("TWITTER_ACCESS_TOKEN")
    access_secret = os.environ.get("TWITTER_ACCESS_SECRET")

    if not all([api_key, api_secret, access_token, access_secret]):
        print("Twitter API credentials not set in env", file=sys.stderr)
        return False

    try:
        client = tweepy.Client(
            consumer_key=api_key,
            consumer_secret=api_secret,
            access_token=access_token,
            access_token_secret=access_secret,
        )
        response = client.create_tweet(text=text)
        print(f"Posted tweet: {response.data['id']}")
        return True
    except Exception as e:
        print(f"Twitter post failed: {e}", file=sys.stderr)
        return False


# ─── State tracking ───────────────────────────────────────

STATE_FILE = Path.home() / ".voidmap" / "last_stats_date.txt"


def already_posted_today() -> bool:
    """Check if we already posted today's stats."""
    if not STATE_FILE.exists():
        return False
    try:
        last_date = STATE_FILE.read_text().strip()
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        return last_date == today
    except Exception:
        return False


def mark_posted():
    """Record that we posted today."""
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    STATE_FILE.write_text(today)


# ─── CLI ──────────────────────────────────────────────────

def main():
    p = argparse.ArgumentParser(description="Voidmap Daily Stats Bot")
    p.add_argument("--dry-run", action="store_true", help="Print without posting")
    p.add_argument("--json", action="store_true", help="Output JSON only")
    p.add_argument("--force", action="store_true", help="Post even if already posted today")
    args = p.parse_args()

    print(f"Fetching on-chain stats from {RPC}...")
    stats = fetch_stats()

    if args.json:
        print(json.dumps(stats, indent=2))
        return 0

    tweet = format_tweet(stats)
    print(tweet)
    print(f"\nLength: {len(tweet)} chars (limit: 280)")

    if args.dry_run:
        return 0

    if not args.force and already_posted_today():
        print("\nAlready posted today. Use --force to override.")
        return 0

    print("\nPosting to Twitter...")
    if post_to_twitter(tweet):
        mark_posted()
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
