#!/bin/sh
# =============================================================================
# Run an OpenFang workflow and POST the result to a Discord webhook
#
# Usage: run-workflow.sh <workflow-id> <discord-webhook-url> <bot-name> <color>
#   workflow-id:         OpenFang workflow UUID
#   discord-webhook-url: Discord webhook URL (from DISCORD_WEBHOOK_URL in .env)
#   bot-name:            Display name in Discord (e.g. "News Bot (OpenFang)")
#   color:               Embed color as decimal integer (e.g. 3447003 = blue)
# =============================================================================
set -e

WORKFLOW_ID="$1"
WEBHOOK_URL="$2"
BOT_NAME="${3:-OpenFang Bot}"
EMBED_COLOR="${4:-3447003}"
API="${OPENFANG_API_URL:-http://openfang:4200}"
TODAY=$(date '+%Y-%m-%d %H:%M %Z')

echo "[$(date '+%H:%M:%S')] Starting workflow ${WORKFLOW_ID} (${BOT_NAME})..."

# ── Execute the workflow ──────────────────────────────────────────────────────
RESPONSE=$(curl -sf -X POST "${API}/api/workflows/${WORKFLOW_ID}/run" \
  -H "Content-Type: application/json" \
  -d "{\"input\": \"${TODAY}\"}" || echo '{"error":"workflow request failed"}')

# Extract the output text from the response
OUTPUT=$(echo "$RESPONSE" | jq -r '.output // .result // .error // "No output returned"' 2>/dev/null \
  || echo "Failed to parse workflow response")

if [ -z "$OUTPUT" ] || [ "$OUTPUT" = "null" ]; then
  echo "[$(date '+%H:%M:%S')] ERROR: Empty output from workflow ${WORKFLOW_ID}"
  echo "Response: ${RESPONSE}"
  exit 1
fi

echo "[$(date '+%H:%M:%S')] Workflow complete. Output length: $(echo "$OUTPUT" | wc -c) chars"

# ── Split into Discord chunks (max 4000 chars per embed) ─────────────────────
# Discord embed description limit is 4096 chars; we use 3900 to be safe.
CHUNK_SIZE=3900
OUTPUT_LEN=$(echo "$OUTPUT" | wc -c)

if [ "$OUTPUT_LEN" -le "$CHUNK_SIZE" ]; then
  # Single message
  PAYLOAD=$(jq -n \
    --arg username "$BOT_NAME" \
    --arg desc "$OUTPUT" \
    --argjson color "$EMBED_COLOR" \
    '{username: $username, embeds: [{description: $desc, color: $color}]}')

  curl -sf -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" > /dev/null

  echo "[$(date '+%H:%M:%S')] Posted to Discord (single message)."
else
  # Split into chunks — post each as a separate embed
  echo "$OUTPUT" | fold -s -w "$CHUNK_SIZE" | while IFS= read -r chunk; do
    PAYLOAD=$(jq -n \
      --arg username "$BOT_NAME" \
      --arg desc "$chunk" \
      --argjson color "$EMBED_COLOR" \
      '{username: $username, embeds: [{description: $desc, color: $color}]}')

    curl -sf -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD" > /dev/null

    # Small delay between chunks to avoid rate limiting
    sleep 1
  done
  echo "[$(date '+%H:%M:%S')] Posted to Discord (chunked)."
fi
