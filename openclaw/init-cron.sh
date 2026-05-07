#!/usr/bin/env bash
# =============================================================================
# OpenClaw — Register Cron Jobs
#
# Registers the news digest cron jobs in the running OpenClaw gateway.
# Safe to re-run: skips jobs that already exist.
#
# Run from repo root: ./openclaw/init-cron.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
CONTAINER="${OPENCLAW_CONTAINER:-openclaw-gateway}"

# Load .env from repo root
if [ -f "${ROOT_DIR}/.env" ]; then
  set -a; source "${ROOT_DIR}/.env"; set +a
fi

: "${DISCORD_CHANNEL_ID:?DISCORD_CHANNEL_ID not set in .env}"
: "${OLLAMA_MODEL:?OLLAMA_MODEL not set in .env}"
TIMEZONE="${TIMEZONE:-Europe/Oslo}"
MODEL="ollama-local/${OLLAMA_MODEL}"
CHANNEL_TARGET="channel:${DISCORD_CHANNEL_ID}"

oclaw() { docker exec "${CONTAINER}" node dist/index.js "$@"; }

job_exists() {
  oclaw cron list 2>/dev/null | grep -qi "${1}" || return 1
}

echo "Registering OpenClaw cron jobs → ${CHANNEL_TARGET} (${TIMEZONE})"

# ── World News Digest — 7:00 AM ───────────────────────────────────────────────
if job_exists "World News Digest"; then
  echo "  [skip] World News Digest already registered"
else
  echo "  [add]  World News Digest (0 7 * * *)"
  oclaw cron add \
    --name "World News Digest" \
    --cron "0 7 * * *" \
    --tz "${TIMEZONE}" \
    --session isolated \
    --model "${MODEL}" \
    --message "Use the news-digest skill to fetch world news.
Fetch RSS feeds from:
- BBC News: https://feeds.bbci.co.uk/news/rss.xml
- CNN: https://rss.cnn.com/rss/edition.rss
- Reuters: https://feeds.reuters.com/reuters/topNews
- The Guardian: https://feeds.theguardian.com/theguardian/rss
- Al Jazeera: https://www.aljazeera.com/xml/rss/all.xml

Filter to articles from the last 24 hours. Create a concise digest under 500 words covering the most important stories across politics, business, and world events. Use Discord markdown. Sign off as News Bot." \
    --announce \
    --channel discord \
    --to "${CHANNEL_TARGET}"
fi

# ── Tech Digest — 8:00 AM ────────────────────────────────────────────────────
if job_exists "Tech Digest"; then
  echo "  [skip] Tech Digest already registered"
else
  echo "  [add]  Tech Digest (0 8 * * *)"
  oclaw cron add \
    --name "Tech Digest" \
    --cron "0 8 * * *" \
    --tz "${TIMEZONE}" \
    --session isolated \
    --model "${MODEL}" \
    --message "Use the news-digest skill to fetch tech news.
Fetch RSS feeds from:
- TechCrunch: https://techcrunch.com/feed/
- Hacker News: https://news.ycombinator.com/rss
- The Verge: https://www.theverge.com/rss/index.xml
- Ars Technica: http://feeds.arstechnica.com/arstechnica/index

Filter to articles from the last 24 hours. Create a concise digest under 400 words covering AI, product launches, startup news, and industry trends. Use Discord markdown. Sign off as Tech News Bot." \
    --announce \
    --channel discord \
    --to "${CHANNEL_TARGET}"
fi

echo ""
oclaw cron list
echo ""
echo "Done. Trigger manually: docker exec ${CONTAINER} node dist/index.js cron run <id>"
