#!/bin/sh
# =============================================================================
# OpenFang Scheduler Entrypoint
#
# 1. Sets the container timezone from $TIMEZONE
# 2. Waits for the OpenFang API to be ready
# 3. Registers workflows from /workflows/*.json (idempotent)
# 4. Writes cron entries and starts crond
# =============================================================================
set -e

API="${OPENFANG_API_URL:-http://openfang:4200}"
TIMEZONE="${TIMEZONE:-Europe/Oslo}"

# ── Set timezone ──────────────────────────────────────────────────────────────
if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
  cp "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  echo "${TIMEZONE}" > /etc/timezone
  echo "[tz] Set timezone to ${TIMEZONE}"
else
  echo "[tz] WARNING: Unknown timezone '${TIMEZONE}', falling back to UTC"
fi

# ── Wait for OpenFang API ─────────────────────────────────────────────────────
echo "[wait] Waiting for OpenFang API at ${API}..."
until curl -sf "${API}/api/health" > /dev/null 2>&1; do
  sleep 3
done
echo "[wait] OpenFang is ready."

# ── Register workflows (idempotent) ───────────────────────────────────────────
register_workflow() {
  local file="$1"
  local name
  name=$(jq -r '.name' "$file")

  # Check if workflow with this name already exists
  existing_id=$(curl -sf "${API}/api/workflows" \
    | jq -r --arg name "$name" '.[] | select(.name == $name) | .id' 2>/dev/null || true)

  if [ -n "$existing_id" ]; then
    echo "[workflow] '${name}' already registered (id: ${existing_id})"
    echo "$existing_id"
  else
    echo "[workflow] Registering '${name}'..."
    new_id=$(curl -sf -X POST "${API}/api/workflows" \
      -H "Content-Type: application/json" \
      -d @"$file" | jq -r '.id')
    echo "[workflow] Registered '${name}' (id: ${new_id})"
    echo "$new_id"
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
# Register all workflows
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "[workflow] ════════════════════════════════════════════════════════════════"
echo "[workflow] Registering OpenFang Workflows..."
echo "[workflow] ════════════════════════════════════════════════════════════════"
echo ""

# NEWS & CURRENT AFFAIRS WORKFLOWS
WORLD_NEWS_ID=$(register_workflow /workflows/world-news.json | tail -1)
GLOBAL_NEWS_ID=$(register_workflow /workflows/global-news.json | tail -1)
AMERICAS_NEWS_ID=$(register_workflow /workflows/americas-news.json | tail -1)
EUROPE_NEWS_ID=$(register_workflow /workflows/europe-news.json | tail -1)
ASIA_PACIFIC_NEWS_ID=$(register_workflow /workflows/asia-pacific-news.json | tail -1)

# TECHNOLOGY & DATA WORKFLOWS
TECH_DIGEST_ID=$(register_workflow /workflows/tech-digest.json | tail -1)
HACKER_NEWS_ID=$(register_workflow /workflows/hacker-news-digest.json | tail -1)
GITHUB_TRENDING_ID=$(register_workflow /workflows/github-trending.json | tail -1)

# FINANCE & MARKET WORKFLOWS
MARKET_BRIEF_ID=$(register_workflow /workflows/market-brief.json | tail -1)
INVESTING_INTEL_ID=$(register_workflow /workflows/investing-intelligence.json | tail -1)

# GEOPOLITICAL & ANALYSIS WORKFLOWS
GEOPOLITICAL_ID=$(register_workflow /workflows/geopolitical-perspectives.json | tail -1)

# DEVELOPER & TECH WORKFLOWS
CODING_TECH_AI_ID=$(register_workflow /workflows/coding-tech-ai.json | tail -1)

# CAPABILITY DEMO WORKFLOWS (Manual trigger only)
DEEP_RESEARCH_ID=$(register_workflow /workflows/deep-research.json | tail -1)
MULTI_AGENT_ID=$(register_workflow /workflows/multi-agent-analysis.json | tail -1)
WEB_SCRAPING_ID=$(register_workflow /workflows/web-scraping-demo.json | tail -1)

echo ""
echo "[workflow] ════════════════════════════════════════════════════════════════"
echo "[workflow] Workflow Registration Complete"
echo "[workflow] ════════════════════════════════════════════════════════════════"
echo ""

# ── Write cron jobs ───────────────────────────────────────────────────────────
mkdir -p /var/spool/cron/crontabs

cat > /var/spool/cron/crontabs/root << EOF
# =============================================================================
# OpenFang Automated Workflow Schedule
# =============================================================================

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ GLOBAL & REGIONAL NEWS                                                     │
# └─────────────────────────────────────────────────────────────────────────────┘

# 🌍 World News Digest — 6:00 AM daily (established workflow)
0 6 * * * sh /scheduler/run-workflow.sh "${WORLD_NEWS_ID}" "${DISCORD_WEBHOOK_URL}" "🌍 World News Bot" 3447003 >> /var/log/scheduler.log 2>&1

# 🌐 Global News (Multi-Region) — 6:30 AM daily
30 6 * * * sh /scheduler/run-workflow.sh "${GLOBAL_NEWS_ID}" "${DISCORD_WEBHOOK_URL}" "🌐 Global News Bot" 15158332 >> /var/log/scheduler.log 2>&1

# 🌎 Americas News — 7:00 AM daily
0 7 * * * sh /scheduler/run-workflow.sh "${AMERICAS_NEWS_ID}" "${DISCORD_WEBHOOK_URL}" "🌎 Americas News Bot" 3066993 >> /var/log/scheduler.log 2>&1

# 🇪🇺 Europe News — 7:30 AM daily
30 7 * * * sh /scheduler/run-workflow.sh "${EUROPE_NEWS_ID}" "${DISCORD_WEBHOOK_URL}" "🇪🇺 Europe News Bot" 3447003 >> /var/log/scheduler.log 2>&1

# 🌏 Asia-Pacific News — 8:00 AM daily
0 8 * * * sh /scheduler/run-workflow.sh "${ASIA_PACIFIC_NEWS_ID}" "${DISCORD_WEBHOOK_URL}" "🌏 Asia-Pacific News Bot" 15105570 >> /var/log/scheduler.log 2>&1

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ TECHNOLOGY & DEVELOPER NEWS                                                │
# └─────────────────────────────────────────────────────────────────────────────┘

# 💻 Tech Digest — 9:00 AM daily
0 9 * * * sh /scheduler/run-workflow.sh "${TECH_DIGEST_ID}" "${DISCORD_WEBHOOK_URL}" "💻 Tech Digest Bot" 5814783 >> /var/log/scheduler.log 2>&1

# 🟠 Hacker News Digest — 10:00 AM daily
0 10 * * * sh /scheduler/run-workflow.sh "${HACKER_NEWS_ID}" "${DISCORD_WEBHOOK_URL}" "🟠 HN Digest Bot" 16744192 >> /var/log/scheduler.log 2>&1

# 🚀 GitHub Trending — 11:00 AM daily
0 11 * * * sh /scheduler/run-workflow.sh "${GITHUB_TRENDING_ID}" "${DISCORD_WEBHOOK_URL}" "🚀 GitHub Trends Bot" 3066993 >> /var/log/scheduler.log 2>&1

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ FINANCE & MARKETS                                                            │
# └─────────────────────────────────────────────────────────────────────────────┘

# 📈 Market & Crypto Brief — 8:30 AM daily (before markets open)
30 8 * * * sh /scheduler/run-workflow.sh "${MARKET_BRIEF_ID}" "${DISCORD_WEBHOOK_URL}" "📈 Market Brief Bot" 5763719 >> /var/log/scheduler.log 2>&1

# 💹 Investing Intelligence — 4:00 PM daily (after market close, before AH trading)
0 16 * * 1-5 sh /scheduler/run-workflow.sh "${INVESTING_INTEL_ID}" "${DISCORD_WEBHOOK_URL}" "💹 Investing Intel Bot" 16776960 >> /var/log/scheduler.log 2>&1

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ GEOPOLITICAL INTELLIGENCE                                                    │
# └─────────────────────────────────────────────────────────────────────────────┘

# 🌐 Geopolitical Perspectives — 12:00 PM daily (midday global briefing)
0 12 * * * sh /scheduler/run-workflow.sh "${GEOPOLITICAL_ID}" "${DISCORD_WEBHOOK_URL}" "🌐 Geopol Intel Bot" 7419530 >> /var/log/scheduler.log 2>&1

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ DEVELOPER & CODING NEWS                                                      │
# └─────────────────────────────────────────────────────────────────────────────┘

# 👨‍💻 Coding, Tech & AI Digest — 9:30 AM daily (after tech digest)
30 9 * * * sh /scheduler/run-workflow.sh "${CODING_TECH_AI_ID}" "${DISCORD_WEBHOOK_URL}" "👨‍💻 Dev Digest Bot" 3447003 >> /var/log/scheduler.log 2>&1

# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ MANUAL WORKFLOWS (Not scheduled - triggered manually via API)                │
# └─────────────────────────────────────────────────────────────────────────────┘
# 🔬 Deep Research: Use /api/workflows/${DEEP_RESEARCH_ID}/execute with topic input
# 📊 Multi-Agent Analysis: Use /api/workflows/${MULTI_AGENT_ID}/execute with topic input
# 🌐 Web Scraping Demo: Use /api/workflows/${WEB_SCRAPING_ID}/execute
# 💹 Investing Intelligence: Use /api/workflows/${INVESTING_INTEL_ID}/execute (manual trigger)
# 🌐 Geopolitical Perspectives: Use /api/workflows/${GEOPOLITICAL_ID}/execute (manual trigger)
# 👨‍💻 Coding/Tech/AI: Use /api/workflows/${CODING_TECH_AI_ID}/execute (manual trigger)

EOF

echo "[cron] Cron jobs written:"
echo "═══════════════════════════════════════════════════════════════════════════════"
cat /var/spool/cron/crontabs/root
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "[cron] ═════════════════════════════════════════════════════════════════════"
echo "[cron] OpenFang Scheduler Active — Schedule Summary"
echo "[cron] ═════════════════════════════════════════════════════════════════════"
echo ""
echo "[cron] 📰 NEWS (6:00-8:00 AM):"
echo "[cron]    • 06:00 — World News Digest"
echo "[cron]    • 06:30 — Global Multi-Region News"
echo "[cron]    • 07:00 — Americas News"
echo "[cron]    • 07:30 — Europe News"
echo "[cron]    • 08:00 — Asia-Pacific News"
echo ""
echo "[cron] 💻 TECH (9:00-11:00 AM):"
echo "[cron]    • 09:00 — Tech Digest"
echo "[cron]    • 10:00 — Hacker News Digest"
echo "[cron]    • 11:00 — GitHub Trending"
echo ""
echo "[cron] 📈 MARKETS:"
echo "[cron]    • 08:30 — Market & Crypto Brief"
echo "[cron]    • 16:00 — Investing Intelligence (weekdays after close)"
echo ""
echo "[cron] 🌐 GEOPOLITICS:"
echo "[cron]    • 12:00 — Geopolitical Perspectives (multi-source analysis)"
echo ""
echo "[cron] 👨‍💻 DEVELOPER:"
echo "[cron]    • 09:30 — Coding, Tech & AI Digest"
echo ""
echo "[cron] 🔧 MANUAL WORKFLOWS (Trigger via API):"
echo "[cron]    • Deep Research (Loop Mode Demo) — ID: ${DEEP_RESEARCH_ID}"
echo "[cron]    • Multi-Agent Analysis — ID: ${MULTI_AGENT_ID}"
echo "[cron]    • Web Scraping Demo — ID: ${WEB_SCRAPING_ID}"
echo ""
echo "[cron] Timezone: ${TIMEZONE}"
echo "[cron] Logs: docker logs openfang-scheduler"
echo ""
echo "[cron] ═════════════════════════════════════════════════════════════════════"
echo ""

# ── Start crond in foreground ─────────────────────────────────────────────────
crond -f -l 6
