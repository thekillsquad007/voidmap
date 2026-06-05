# Voidmap Daily Stats Bot — Setup

Automated daily Twitter post of Voidmap network statistics.

## Overview

The bot queries the on-chain state of the Voidmap contracts daily and posts a tweet summarizing:
- Submission count
- Average quality
- Block reward + halving progress
- Total burned

Tweet format:

```
🌌 Voidmap Daily Stats — Day N

📊 Network:
• Submissions: 1,234
• Avg Quality: 84/100

💎 Token:
• Block Reward: 50 VOID
• Halving: 0.1% (in 209,765 subs)
• Burned: 127K VOID

🌐 explorer.voidmap.org
```

## Setup

### 1. Install dependencies

```bash
pip install tweepy web3
```

### 2. Set up Twitter API

1. Apply for a Twitter developer account: https://developer.twitter.com
2. Create an app
3. Generate API keys and access tokens
4. Save them in `~/.voidmap/bot.env` or `/etc/voidmap/bot.env`:

```bash
TWITTER_API_KEY=...
TWITTER_API_SECRET=...
TWITTER_ACCESS_TOKEN=...
TWITTER_ACCESS_SECRET=...

VOIDMAP_RPC=https://mainnet.base.org
VOIDMAP_POOL=0x...
VOIDMAP_TOKEN=0x...
VOIDMAP_REGISTRY=0x...
```

### 3. Test

```bash
# Dry run (no posting)
python automation/daily_stats.py --dry-run

# JSON output (for inspection)
python automation/daily_stats.py --json

# Actually post
python automation/daily_stats.py
```

### 4. Schedule (cron)

```cron
# Post daily at 12:00 UTC
0 12 * * * cd /opt/voidmap && /usr/bin/python3 automation/daily_stats.py
```

### 5. Schedule (systemd)

```bash
# Install service + timer
sudo cp automation/voidmap-bot.service /etc/systemd/system/
sudo cp automation/voidmap-bot.timer /etc/systemd/system/
sudo cp automation/daily_stats.py /opt/voidmap/automation/

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable voidmap-bot.timer
sudo systemctl start voidmap-bot.timer

# Check status
sudo systemctl list-timers voidmap-bot
```

## State

The bot stores the last-posted date in `~/.voidmap/last_stats_date.txt`. It will refuse to post twice in the same day unless `--force` is passed.

## Customization

Edit `format_tweet()` in `daily_stats.py` to customize the tweet format.

## See Also

- [Twitter thread template](twitter-thread.md) — for the launch thread
- [Bitcointalk ANN](bitcointalk-ann.md) — for the forum post
