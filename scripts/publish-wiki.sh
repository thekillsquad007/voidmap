#!/usr/bin/env bash
# Publish wiki/ directory to the GitHub wiki repo
# https://github.com/thekillsquad007/voidmap/wiki
#
# First-time setup (one-time, requires browser):
#   1. Visit https://github.com/thekillsquad007/voidmap/wiki
#   2. Click "Create the first page" → title "Home" → Save
#      (body content doesn't matter; we'll overwrite it)
#   3. Then run this script.
#
# After the first run, re-run this script any time you want to sync
# wiki/ to GitHub Wiki.

set -e

WIKI_DIR="$(cd "$(dirname "$0")/.." && pwd)/wiki"
WIKI_REPO="https://github.com/thekillsquad007/voidmap.wiki.git"
WORKDIR="$(mktemp -d)"

echo "==> Publishing wiki/ to $WIKI_REPO"
echo "    Source: $WIKI_DIR"
echo "    Workdir: $WORKDIR"
echo

# 1. Sanity check: source dir exists
if [ ! -d "$WIKI_DIR" ]; then
  echo "ERROR: $WIKI_DIR does not exist" >&2
  exit 1
fi

# 2. Sanity check: at least one .md file
if ! find "$WIKI_DIR" -maxdepth 1 -name '*.md' -print -quit | grep -q .; then
  echo "ERROR: no .md files in $WIKI_DIR" >&2
  exit 1
fi

# 3. Clone wiki repo
cd "$WORKDIR"
if ! git clone "$WIKI_REPO" wiki 2>/dev/null; then
  echo "" >&2
  echo "ERROR: Could not clone $WIKI_REPO" >&2
  echo "" >&2
  echo "This usually means the wiki has not been initialized yet." >&2
  echo "To bootstrap:" >&2
  echo "  1. Open https://github.com/thekillsquad007/voidmap/wiki" >&2
  echo "  2. Click 'Create the first page'" >&2
  echo "  3. Title: Home, body: anything, click Save" >&2
  echo "  4. Re-run this script" >&2
  exit 1
fi

cd wiki

# 4. Wipe existing wiki pages (keep .git)
find . -maxdepth 1 -type f ! -name '.git*' -delete

# 5. Copy our wiki content
cp "$WIKI_DIR"/*.md .

# 6. Commit + push
git add -A
if git diff --cached --quiet; then
  echo "==> No changes — wiki is already up to date"
  exit 0
fi

git -c user.name='voidmap-bot' \
    -c user.email='voidmap-bot@users.noreply.github.com' \
    commit -m "Sync wiki from repo ($(date -u +%Y-%m-%dT%H:%M:%SZ))"

echo
echo "==> Pushing to $WIKI_REPO"
git push origin master

echo
echo "==> Done. View at: https://github.com/thekillsquad007/voidmap/wiki"
