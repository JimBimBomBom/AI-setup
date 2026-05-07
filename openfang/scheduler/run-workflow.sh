#!/bin/sh
# Run OpenFang workflow and send to Discord

WORKFLOW_ID="$1"
WEBHOOK_URL="$2"
BOT_NAME="$3"
COLOR="${4:-3447003}"
API="${OPENFANG_API_URL:-http://openfang:4200}"

LOG="/var/log/scheduler.log"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"
}

log "=========================================="
log "Starting: $BOT_NAME"
log "Workflow: ${WORKFLOW_ID:0:20}..."
log "=========================================="

# Validate
if [ -z "$WORKFLOW_ID" ]; then
    log "ERROR: No workflow ID"
    exit 1
fi

if [ -z "$WEBHOOK_URL" ]; then
    log "ERROR: No webhook URL"
    exit 1
fi

# Run workflow
log "Calling OpenFang API..."
TODAY=$(date '+%Y-%m-%d %H:%M %Z')

RESPONSE=$(curl -s -X POST "${API}/api/workflows/${WORKFLOW_ID}/run" \
    -H "Content-Type: application/json" \
    -d "{\"input\": \"${TODAY}\"}" 2>&1)

if [ $? -ne 0 ]; then
    log "ERROR: API call failed"
    log "$RESPONSE"
    exit 1
fi

# Check for error in response
if echo "$RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
    log "ERROR: Workflow returned error"
    log "$RESPONSE"
    exit 1
fi

# Extract output
OUTPUT=$(echo "$RESPONSE" | jq -r '.output // .result // empty')

if [ -z "$OUTPUT" ] || [ "$OUTPUT" = "null" ]; then
    log "ERROR: No output from workflow"
    log "Response: ${RESPONSE:0:500}"
    exit 1
fi

LEN=$(echo "$OUTPUT" | wc -c)
log "Output received: $LEN chars"

# Send to Discord
log "Sending to Discord..."

if [ $LEN -le 4000 ]; then
    # Single message
    PAYLOAD=$(jq -n \
        --arg name "$BOT_NAME" \
        --arg text "$OUTPUT" \
        --argjson color "$COLOR" \
        '{username: $name, embeds: [{description: $text, color: $color}]}')
    
    curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log "✓ Discord message sent"
    else
        log "✗ Discord send failed"
        exit 1
    fi
else
    # Split and send
    log "Message too long ($LEN), splitting..."
    CHUNKS=0
    echo "$OUTPUT" | fold -s -w 3900 | while read chunk; do
        PAYLOAD=$(jq -n \
            --arg name "$BOT_NAME" \
            --arg text "$chunk" \
            --argjson color "$COLOR" \
            '{username: $name, embeds: [{description: $text, color: $color}]}')
        
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$PAYLOAD" > /dev/null 2>&1
        CHUNKS=$((CHUNKS + 1))
        sleep 1
    done
    log "✓ Sent $CHUNKS chunks"
fi

log "Complete: $BOT_NAME"
log "=========================================="
