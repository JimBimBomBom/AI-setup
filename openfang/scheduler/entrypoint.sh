#!/bin/sh
# OpenFang Scheduler - Failsafe version with simple loop-based scheduling

API="${OPENFANG_API_URL:-http://openfang:4200}"
TIMEZONE="${TIMEZONE:-Europe/Oslo}"
CHECK_INTERVAL=30

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1"
}

log "=========================================="
log "OpenFang Scheduler (Failsafe Mode)"
log "=========================================="

# Set timezone
if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
    cp "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    echo "${TIMEZONE}" > /etc/timezone
    log "Timezone set to $TIMEZONE"
fi

# Wait for OpenFang
log "Waiting for OpenFang at $API..."
RETRY=0
while ! curl -sf "${API}/api/health" >/dev/null 2>&1; do
    RETRY=$((RETRY + 1))
    if [ $RETRY -ge 30 ]; then
        log "ERROR: OpenFang not available after 90s"
        exit 1
    fi
    sleep 3
done
log "OpenFang is ready"

# Register all workflows
log ""
log "Registering workflows..."

register() {
    local file=$1
    local name
    name=$(jq -r '.name' "$file")
    
    # Check if exists
    local existing
    existing=$(curl -sf "${API}/api/workflows" | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)
    
    if [ -n "$existing" ]; then
        echo "$existing"
        log "  $name: ${existing:0:12} (existing)"
    else
        local id
        id=$(curl -sf -X POST "${API}/api/workflows" -H "Content-Type: application/json" -d @"$file" | jq -r '.id')
        if [ -n "$id" ]; then
            echo "$id"
            log "  $name: ${id:0:12} (registered)"
        else
            echo ""
            log "  $name: FAILED"
        fi
    fi
}

# Register workflows
WORLD_ID=$(register /workflows/world-news.json)
TECH_ID=$(register /workflows/tech-digest.json)
HN_ID=$(register /workflows/hacker-news-digest.json)
GEOPOL_ID=$(register /workflows/geopolitical-perspectives.json)
MARKET_ID=$(register /workflows/market-brief.json)

log ""
log "=========================================="
log "Starting Time-Based Scheduler"
log "=========================================="
log "Checking every ${CHECK_INTERVAL}s for scheduled times"
log ""
log "Scheduled jobs:"
log "  06:00 - World News"
log "  08:30 - Market Brief"  
log "  09:00 - Tech Digest"
log "  10:00 - Hacker News"
log "  16:52 - TEST JOB"
log ""

LAST_TIME=""

while true; do
    CURRENT_TIME=$(date '+%H:%M')
    
    # Only trigger once per minute
    if [ "$CURRENT_TIME" != "$LAST_TIME" ]; then
        LAST_TIME=$CURRENT_TIME
        
        case $CURRENT_TIME in
            "06:00")
                if [ -n "$WORLD_ID" ] && [ -n "$DISCORD_WEBHOOK_URL" ]; then
                    log "⏰ 06:00 - Triggering World News"
                    sh /scheduler/run-workflow.sh "$WORLD_ID" "$DISCORD_WEBHOOK_URL" "🌍 World News Bot" 3447003 > /tmp/world-news.log 2>&1 &
                fi
                ;;
            "08:30")
                if [ -n "$MARKET_ID" ] && [ -n "$DISCORD_WEBHOOK_URL" ]; then
                    log "⏰ 08:30 - Triggering Market Brief"
                    sh /scheduler/run-workflow.sh "$MARKET_ID" "$DISCORD_WEBHOOK_URL" "📈 Market Brief Bot" 5763719 > /tmp/market.log 2>&1 &
                fi
                ;;
            "09:00")
                if [ -n "$TECH_ID" ] && [ -n "$DISCORD_WEBHOOK_URL" ]; then
                    log "⏰ 09:00 - Triggering Tech Digest"
                    sh /scheduler/run-workflow.sh "$TECH_ID" "$DISCORD_WEBHOOK_URL" "💻 Tech Digest Bot" 5814783 > /tmp/tech.log 2>&1 &
                fi
                ;;
            "10:00")
                if [ -n "$HN_ID" ] && [ -n "$DISCORD_WEBHOOK_URL" ]; then
                    log "⏰ 10:00 - Triggering Hacker News"
                    sh /scheduler/run-workflow.sh "$HN_ID" "$DISCORD_WEBHOOK_URL" "🟠 HN Digest Bot" 16744192 > /tmp/hn.log 2>&1 &
                fi
                ;;
            "16:52")
                if [ -n "$HN_ID" ] && [ -n "$DISCORD_WEBHOOK_URL" ]; then
                    log "⏰ 16:52 - TEST JOB - Triggering Hacker News"
                    sh /scheduler/run-workflow.sh "$HN_ID" "$DISCORD_WEBHOOK_URL" "🧪 TEST: HN Digest" 16744192 > /tmp/test.log 2>&1 &
                fi
                ;;
        esac
    fi
    
    sleep $CHECK_INTERVAL
done
