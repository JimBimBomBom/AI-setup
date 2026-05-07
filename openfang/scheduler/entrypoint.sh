#!/bin/sh
# OpenFang Scheduler - Auto-registers workflows and creates cron schedule on startup

set -e

API="${OPENFANG_API_URL:-http://openfang:4200}"
TIMEZONE="${TIMEZONE:-Europe/Oslo}"

# Set timezone
echo "[scheduler] Setting timezone to ${TIMEZONE}"
if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
  cp "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  echo "${TIMEZONE}" > /etc/timezone
else
  echo "[scheduler] Warning: Unknown timezone, using UTC"
fi

# Wait for OpenFang
echo "[scheduler] Waiting for OpenFang at ${API}..."
RETRY=0
while ! curl -sf "${API}/api/health" >/dev/null 2>&1; do
  RETRY=$((RETRY + 1))
  if [ $RETRY -ge 30 ]; then
    echo "[scheduler] ERROR: OpenFang not available after 90s"
    exit 1
  fi
  sleep 3
done
echo "[scheduler] OpenFang is ready"

# Register a single workflow
register_workflow() {
  local file="$1"
  local name=$(jq -r '.name' "$file" 2>/dev/null || echo "")
  
  if [ -z "$name" ] || [ "$name" = "null" ]; then
    echo "[scheduler] ERROR: Invalid workflow JSON: $file"
    return 1
  fi
  
  # Check if exists
  local existing=$(curl -sf "${API}/api/workflows" 2>/dev/null | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)
  
  if [ -n "$existing" ]; then
    echo "$existing"
    return 0
  fi
  
  # Register new
  local response=$(curl -sf -X POST "${API}/api/workflows" -H "Content-Type: application/json" -d @"$file" 2>/dev/null || echo '{"error":"failed"}')
  local id=$(echo "$response" | jq -r '.id // empty')
  
  if [ -n "$id" ]; then
    echo "$id"
    return 0
  else
    echo ""
    return 1
  fi
}

# Register all workflows
echo "[scheduler] Registering workflows..."

WORLD_NEWS_ID=$(register_workflow /workflows/world-news.json)
GLOBAL_NEWS_ID=$(register_workflow /workflows/global-news.json)
AMERICAS_NEWS_ID=$(register_workflow /workflows/americas-news.json)
EUROPE_NEWS_ID=$(register_workflow /workflows/europe-news.json)
ASIA_PACIFIC_NEWS_ID=$(register_workflow /workflows/asia-pacific-news.json)
TECH_DIGEST_ID=$(register_workflow /workflows/tech-digest.json)
HACKER_NEWS_ID=$(register_workflow /workflows/hacker-news-digest.json)
GITHUB_TRENDING_ID=$(register_workflow /workflows/github-trending.json)
MARKET_BRIEF_ID=$(register_workflow /workflows/market-brief.json)
INVESTING_INTEL_ID=$(register_workflow /workflows/investing-intelligence.json)
GEOPOLITICAL_ID=$(register_workflow /workflows/geopolitical-perspectives.json)
CODING_TECH_AI_ID=$(register_workflow /workflows/coding-tech-ai.json)
DEEP_RESEARCH_ID=$(register_workflow /workflows/deep-research.json)
MULTI_AGENT_ID=$(register_workflow /workflows/multi-agent-analysis.json)
WEB_SCRAPING_ID=$(register_workflow /workflows/web-scraping-demo.json)

echo "[scheduler] Workflows registered"

# Create cron schedule (only if DISCORD_WEBHOOK_URL is set)
if [ -z "$DISCORD_WEBHOOK_URL" ]; then
  echo "[scheduler] WARNING: DISCORD_WEBHOOK_URL not set - schedules not created"
  echo "[scheduler] Set DISCORD_WEBHOOK_URL in .env and restart"
else
  echo "[scheduler] Creating cron schedule..."
  
  mkdir -p /var/spool/cron/crontabs
  
  cat > /var/spool/cron/crontabs/root << EOF
SHELL=/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin

# OpenFang Scheduled Workflows - $(date)

EOF

  # Helper to add cron job if workflow registered
  add_job() {
    local id="$1"
    local schedule="$2"
    local name="$3"
    local color="$4"
    if [ -n "$id" ]; then
      echo "$schedule sh /scheduler/run-workflow.sh \"$id\" \"\${DISCORD_WEBHOOK_URL}\" \"$name\" $color >> /var/log/scheduler.log 2>&1" >> /var/spool/cron/crontabs/root
      echo "[scheduler] Scheduled: $name"
    fi
  }

  # News workflows
  add_job "$WORLD_NEWS_ID" "0 6 * * *" "🌍 World News Bot" 3447003
  add_job "$GLOBAL_NEWS_ID" "30 6 * * *" "🌐 Global News Bot" 15158332
  add_job "$AMERICAS_NEWS_ID" "0 7 * * *" "🌎 Americas News Bot" 3066993
  add_job "$EUROPE_NEWS_ID" "30 7 * * *" "🇪🇺 Europe News Bot" 3447003
  add_job "$ASIA_PACIFIC_NEWS_ID" "0 8 * * *" "🌏 Asia-Pacific News Bot" 15105570

  # Finance workflows  
  add_job "$MARKET_BRIEF_ID" "30 8 * * *" "📈 Market Brief Bot" 5763719
  add_job "$INVESTING_INTEL_ID" "0 16 * * 1-5" "💹 Investing Intel Bot" 16776960

  # Tech workflows
  add_job "$TECH_DIGEST_ID" "0 9 * * *" "💻 Tech Digest Bot" 5814783
  add_job "$CODING_TECH_AI_ID" "30 9 * * *" "👨‍💻 Dev Digest Bot" 3447003
  add_job "$HACKER_NEWS_ID" "0 10 * * *" "🟠 HN Digest Bot" 16744192
  add_job "$GITHUB_TRENDING_ID" "0 11 * * *" "🚀 GitHub Trends Bot" 3066993

  # Analysis workflows
  add_job "$GEOPOLITICAL_ID" "0 12 * * *" "🌐 Geopol Intel Bot" 7419530

  chmod 600 /var/spool/cron/crontabs/root
  echo "[scheduler] Cron schedule created"
fi

# Log registered workflow IDs for manual use
echo "[scheduler] Manual workflow IDs:"
[ -n "$DEEP_RESEARCH_ID" ] && echo "  Deep Research: $DEEP_RESEARCH_ID"
[ -n "$MULTI_AGENT_ID" ] && echo "  Multi-Agent: $MULTI_AGENT_ID"
[ -n "$WEB_SCRAPING_ID" ] && echo "  Web Scraping: $WEB_SCRAPING_ID"

echo "[scheduler] Starting cron daemon..."
exec crond -f -l 6
