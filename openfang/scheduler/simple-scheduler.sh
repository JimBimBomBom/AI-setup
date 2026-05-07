#!/bin/sh
# Simple OpenFang Scheduler - Just runs a loop checking for scheduled times
# No crond dependency, no complex shell scripting

API="${OPENFANG_API_URL:-http://openfang:4200}"
TIMEZONE="${TIMEZONE:-Europe/Oslo}"
CHECK_INTERVAL=30  # Check every 30 seconds

# Set timezone
if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
    cp "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    echo "${TIMEZONE}" > /etc/timezone
fi

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1"
}

log "=========================================="
log "Simple OpenFang Scheduler Starting"
log "API: $API"
log "Timezone: $TIMEZONE"
log "Check interval: ${CHECK_INTERVAL}s"
log "=========================================="

# Wait for OpenFang
log "Waiting for OpenFang API..."
RETRY=0
while ! curl -sf "${API}/api/health" >/dev/null 2>&1; do
    RETRY=$((RETRY + 1))
    if [ $RETRY -ge 30 ]; then
        log "ERROR: OpenFang not available, exiting"
        exit 1
    fi
    sleep 3
done
log "OpenFang is ready"

# Register workflows and build schedule
log ""
log "Registering workflows..."

# Simple registration - just gets IDs
WORLD_NEWS_ID=$(curl -sf "${API}/api/workflows" | jq -r '.[] | select(.name=="world-news-digest") | .id' 2>/dev/null)
TECH_DIGEST_ID=$(curl -sf "${API}/api/workflows" | jq -r '.[] | select(.name=="tech-digest") | .id' 2>/dev/null)

# If not found, register them
if [ -z "$WORLD_NEWS_ID" ]; then
    WORLD_NEWS_ID=$(curl -sf -X POST "${API}/api/workflows" -H "Content-Type: application/json" -d @/workflows/world-news.json | jq -r '.id' 2>/dev/null)
    log "Registered world-news: ${WORLD_NEWS_ID:0:12}"
fi

if [ -z "$TECH_DIGEST_ID" ]; then
    TECH_DIGEST_ID=$(curl -sf -X POST "${API}/api/workflows" -H "Content-Type: application/json" -d @/workflows/tech-digest.json | jq -r '.id' 2>/dev/null)
    log "Registered tech-digest: ${TECH_DIGEST_ID:0:12}"
fi

log "Workflow IDs:"
log "  World News: ${WORLD_NEWS_ID:0:12}"
log "  Tech Digest: ${TECH_DIGEST_ID:0:12}"

# Main loop - check time and run workflows
log ""
log "Starting schedule loop..."
log "=========================================="

LAST_HOUR=-1
LAST_MIN=-1

while true; do
    # Get current time
    CURRENT_HOUR=$(date '+%H')
    CURRENT_MIN=$(date '+%M')
    
    # Only check once per minute
    if [ "$CURRENT_HOUR" != "$LAST_HOUR" ] || [ "$CURRENT_MIN" != "$LAST_MIN" ]; then
        LAST_HOUR=$CURRENT_HOUR
        LAST_MIN=$CURRENT_MIN
        
        # Check schedules (24h format)
        case "$CURRENT_HOUR:$CURRENT_MIN" in
            "06:00")
                if [ -n "$WORLD_NEWS_ID" ]; then
                    log "Triggering: World News at 06:00"
                    /scheduler/run-workflow.sh "$WORLD_NEWS_ID" "$DISCORD_WEBHOOK_URL" "🌍 World News Bot" 3447003 &
                fi
                ;;
            "08:00")
                if [ -n "$TECH_DIGEST_ID" ]; then
                    log "Triggering: Tech Digest at 08:00"
                    /scheduler/run-workflow.sh "$TECH_DIGEST_ID" "$DISCORD_WEBHOOK_URL" "💻 Tech Digest Bot" 5814783 &
                fi
                ;;
            "16:52")
                if [ -n "$TECH_DIGEST_ID" ]; then
                    log "Triggering: TEST at 16:52"
                    /scheduler/run-workflow.sh "$TECH_DIGEST_ID" "$DISCORD_WEBHOOK_URL" "🧪 TEST Bot" 5814783 &
                fi
                ;;
        esac
    fi
    
    sleep $CHECK_INTERVAL
done
