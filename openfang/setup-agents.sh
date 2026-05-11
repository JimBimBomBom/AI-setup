#!/bin/sh
# OpenFang Agent Setup — Creates dedicated agents for Discord and workflows.
# Run this after OpenFang starts.
set -e

API_URL="${OPENFANG_API_URL:-http://localhost:4200}"
API_KEY="${OPENFANG_API_KEY:-}"

AUTH_FLAGS=""
if [ -n "$API_KEY" ]; then
    AUTH_FLAGS="-H Authorization: Bearer $API_KEY"
fi

# Wait for OpenFang to be ready
echo "[agent-setup] Waiting for OpenFang API..."
for i in $(seq 1 60); do
    if curl -sf $AUTH_FLAGS "$API_URL/api/health" > /dev/null 2>&1; then
        echo "[agent-setup] OpenFang is ready"
        break
    fi
    sleep 1
done

# ── 1. General Assistant (for Discord bot interactions) ──────────────────────
echo "[agent-setup] Creating General Assistant agent..."
ASSISTANT_RESP=$(curl -sf -X POST $AUTH_FLAGS \
    -H "Content-Type: application/json" \
    -d '{
        "manifest_toml": "name = \"general-assistant\"\nprofile = \"Full\"\nmodel = \"ollama/qwen3.5:9b\"\ndescription = \"General purpose assistant for Discord bot interactions and user queries.\"\n"
    }' \
    "$API_URL/api/agents" 2>&1 || echo "FAILED")

echo "[agent-setup] General Assistant: $ASSISTANT_RESP"

# Extract agent ID
ASSISTANT_ID=$(echo "$ASSISTANT_RESP" | grep -o '"agent_id":"[^"]*"' | cut -d'"' -f4 || true)
if [ -z "$ASSISTANT_ID" ]; then
    # Try to get existing agent
    ASSISTANT_ID=$(curl -sf $AUTH_FLAGS "$API_URL/api/agents" 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
fi

# ── 2. Researcher (for workflow/cron execution) ─────────────────────────────
echo "[agent-setup] Creating Researcher agent..."
RESEARCHER_RESP=$(curl -sf -X POST $AUTH_FLAGS \
    -H "Content-Type: application/json" \
    -d '{
        "manifest_toml": "name = \"researcher\"\nprofile = \"Full\"\nmodel = \"ollama/qwen3.5:9b\"\ndescription = \"Dedicated researcher for workflow and cron job execution. Handles data fetching, summarization, and report generation.\"\n"
    }' \
    "$API_URL/api/agents" 2>&1 || echo "FAILED")

echo "[agent-setup] Researcher: $RESEARCHER_RESP"

# Extract researcher ID
RESEARCHER_ID=$(echo "$RESEARCHER_RESP" | grep -o '"agent_id":"[^"]*"' | cut -d'"' -f4 || true)

# ── 3. Configure Discord to use General Assistant ────────────────────────────
if [ -n "$ASSISTANT_ID" ]; then
    echo "[agent-setup] Configuring Discord channel to use General Assistant..."
    DISCORD_RESP=$(curl -sf -X POST $AUTH_FLAGS \
        -H "Content-Type: application/json" \
        -d "{
            \"bot_token_env\": \"DISCORD_BOT_TOKEN\",
            \"default_agent\": \"general-assistant\",
            \"guild_ids\": []
        }" \
        "$API_URL/api/channels/discord/configure" 2>&1 || echo "FAILED")
    echo "[agent-setup] Discord configure: $DISCORD_RESP"
fi

# ── 4. Reload channels ──────────────────────────────────────────────────────
RELOAD=$(curl -sf -X POST $AUTH_FLAGS "$API_URL/api/channels/reload" 2>&1 || echo "FAILED")
echo "[agent-setup] Channels reload: $RELOAD"

# ── 5. List all agents ──────────────────────────────────────────────────────
echo "[agent-setup] All agents:"
curl -sf $AUTH_FLAGS "$API_URL/api/agents" 2>/dev/null | python3 -c "
import sys, json
agents = json.load(sys.stdin)
for a in agents:
    print(f\"  {a['id'][:12]}...  {a['name']}  ({a.get('model_provider','?')}/{a.get('model_name','?')})\")
" 2>/dev/null || echo "  (could not list agents)"

# ── 6. Print instructions ───────────────────────────────────────────────────
echo ""
echo "[agent-setup] Done. Add to your .env:"
if [ -n "$RESEARCHER_ID" ]; then
    echo "  SCHEDULER_AGENT_ID=$RESEARCHER_ID"
else
    echo "  # Find researcher ID via: curl .../api/agents | jq '.[] | select(.name==\"researcher\") | .id'"
    echo "  SCHEDULER_AGENT_ID=<researcher-agent-id>"
fi
echo ""
echo "[agent-setup] Then restart the scheduler:"
echo "  docker compose up -d --build openfang-scheduler"
