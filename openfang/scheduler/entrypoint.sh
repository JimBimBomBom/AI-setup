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
until curl -sf "${API}/health" > /dev/null 2>&1; do
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

WORLD_NEWS_ID=$(register_workflow /workflows/world-news.json | tail -1)
TECH_DIGEST_ID=$(register_workflow /workflows/tech-digest.json | tail -1)

echo "[workflow] World News ID: ${WORLD_NEWS_ID}"
echo "[workflow] Tech Digest ID: ${TECH_DIGEST_ID}"

# ── Write cron jobs ───────────────────────────────────────────────────────────
mkdir -p /var/spool/cron/crontabs

cat > /var/spool/cron/crontabs/root << EOF
# World News Digest — 7:00 AM daily
0 7 * * * /scheduler/run-workflow.sh "${WORLD_NEWS_ID}" "${DISCORD_WEBHOOK_URL}" "News Bot (OpenFang)" 3447003 >> /var/log/scheduler.log 2>&1

# Tech Digest — 8:00 AM daily
0 8 * * * /scheduler/run-workflow.sh "${TECH_DIGEST_ID}" "${DISCORD_WEBHOOK_URL}" "Tech News Bot (OpenFang)" 5814783 >> /var/log/scheduler.log 2>&1
EOF

echo "[cron] Cron jobs written:"
cat /var/spool/cron/crontabs/root

echo "[cron] Scheduler running. World News at 07:00, Tech Digest at 08:00 (${TIMEZONE})."
echo "[cron] Logs: docker logs openfang-scheduler"
echo ""

# ── Start crond in foreground ─────────────────────────────────────────────────
crond -f -l 6
