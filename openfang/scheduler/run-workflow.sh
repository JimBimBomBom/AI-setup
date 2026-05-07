#!/bin/sh
# Run an OpenFang workflow and POST the result to a Discord webhook
#
# Usage: run-workflow.sh <workflow-id> <discord-webhook-url> <bot-name> <color>

# Remove set -e to handle errors gracefully
# set -e

WORKFLOW_ID="$1"
WEBHOOK_URL="$2"
BOT_NAME="${3:-OpenFang Bot}"
EMBED_COLOR="${4:-3447003}"
API="${OPENFANG_API_URL:-http://openfang:4200}"
TODAY=$(date '+%Y-%m-%d %H:%M %Z')

LOG_PREFIX="[$(date '+%H:%M:%S')]"

# Log to both stdout and log file
log() {
    echo "$LOG_PREFIX $1"
    echo "$LOG_PREFIX $1" >> /var/log/scheduler.log
}

log "=========================================="
log "Starting workflow execution"
log "Workflow ID: ${WORKFLOW_ID:0:20}..."
log "Bot Name: $BOT_NAME"
log "Webhook configured: $([ -n "$WEBHOOK_URL" ] && echo 'YES' || echo 'NO')"
log "API Endpoint: $API"
log "=========================================="

# Validate inputs
if [ -z "$WORKFLOW_ID" ]; then
    log "ERROR: No workflow ID provided"
    exit 1
fi

if [ -z "$WEBHOOK_URL" ]; then
    log "ERROR: No Discord webhook URL provided"
    exit 1
fi

# Execute the workflow
log "Calling OpenFang API..."
log "Request: POST ${API}/api/workflows/${WORKFLOW_ID:0:20}.../run"

RESPONSE=$(curl -s -X POST "${API}/api/workflows/${WORKFLOW_ID}/run" \
  -H "Content-Type: application/json" \
  -d "{\"input\": \"${TODAY}\"}" 2>&1)

CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ]; then
    log "ERROR: curl failed with exit code $CURL_EXIT"
    log "Response: $RESPONSE"
    exit 1
fi

log "API Response received"
log "Response length: $(echo "$RESPONSE" | wc -c) chars"

# Check for API errors
if echo "$RESPONSE" | jq -e '.error' >/dev/null 2>&1; then
    log "ERROR: API returned error:"
    log "$RESPONSE"
    exit 1
fi

# Extract the output text
OUTPUT=$(echo "$RESPONSE" | jq -r '.output // .result // empty' 2>/dev/null)

if [ -z "$OUTPUT" ] || [ "$OUTPUT" = "null" ]; then
    log "ERROR: Empty output from workflow"
    log "Full response: ${RESPONSE:0:500}"
    exit 1
fi

OUTPUT_LEN=$(echo "$OUTPUT" | wc -c)
log "Workflow output extracted: $OUTPUT_LEN chars"

# Prepare Discord payload
log "Preparing Discord message..."

# Discord embed description limit is 4096 chars; we use 3900 to be safe.
CHUNK_SIZE=3900

if [ "$OUTPUT_LEN" -le "$CHUNK_SIZE" ]; then
    # Single message
    log "Sending single Discord message..."
    
    PAYLOAD=$(jq -n \
        --arg username "$BOT_NAME" \
        --arg desc "$OUTPUT" \
        --argjson color "$EMBED_COLOR" \
        '{username: $username, embeds: [{description: $desc, color: $color}]}')
    
    log "Payload prepared ($(echo "$PAYLOAD" | wc -c) chars)"
    
    DISCORD_RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>&1)
    
    DISCORD_EXIT=$?
    
    if [ $DISCORD_EXIT -eq 0 ]; then
        log "✓ Posted to Discord successfully (single message)"
    else
        log "✗ Discord POST failed (exit code: $DISCORD_EXIT)"
        log "Response: ${DISCORD_RESPONSE:0:200}"
        exit 1
    fi
else
    # Split into chunks
    log "Output too long ($OUTPUT_LEN chars), splitting into chunks..."
    
    CHUNK_NUM=0
    echo "$OUTPUT" | fold -s -w "$CHUNK_SIZE" | while IFS= read -r chunk; do
        CHUNK_NUM=$((CHUNK_NUM + 1))
        log "Sending chunk $CHUNK_NUM..."
        
        CHUNK_PAYLOAD=$(jq -n \
            --arg username "$BOT_NAME" \
            --arg desc "$chunk" \
            --argjson color "$EMBED_COLOR" \
            '{username: $username, embeds: [{description: $desc, color: $color}]}')
        
        DISCORD_RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$CHUNK_PAYLOAD" 2>&1)
        
        if [ $? -eq 0 ]; then
            log "  ✓ Chunk $CHUNK_NUM sent"
        else
            log "  ✗ Chunk $CHUNK_NUM failed: ${DISCORD_RESPONSE:0:100}"
        fi
        
        sleep 1
    done
    
    log "✓ Posted to Discord ($CHUNK_NUM chunks)"
fi

log "=========================================="
log "Workflow execution complete"
log "=========================================="
