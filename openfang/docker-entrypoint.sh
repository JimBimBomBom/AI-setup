#!/bin/sh
# OpenFang container entrypoint.
#
# Generates /root/.openfang/config.toml from the mounted template by
# substituting ${OLLAMA_MODEL} and any other ${VAR} placeholders with
# values from the container's environment (set via docker-compose env_file).
#
# Auto-creates dedicated agents and configures Discord channel adapter.
# Then starts OpenFang normally.
set -e

TEMPLATE="/config-template/config.toml.template"
CONFIG="/root/.openfang/config.toml"

mkdir -p /root/.openfang

if [ -f "$TEMPLATE" ]; then
    envsubst < "$TEMPLATE" > "$CONFIG"
    echo "[openfang] config.toml generated"
    echo "[openfang]   OLLAMA_MODEL = ${OLLAMA_MODEL:-<not set>}"
    echo "[openfang]   provider url = ${OLLAMA_BASE_URL:-http://host.docker.internal:11434/v1}"
else
    echo "[openfang] WARNING: config template not found at $TEMPLATE"
    echo "[openfang] Continuing with any existing config at $CONFIG"
fi

# Start OpenFang in background
openfang start &
OPENFANG_PID=$!

# Wait for API to be ready
echo "[openfang] Waiting for API to be ready..."
for i in $(seq 1 90); do
    if curl -sf http://localhost:4200/api/health > /dev/null 2>&1; then
        echo "[openfang] API ready after ${i}s"
        break
    fi
    sleep 1
done

# Auth flags
AUTH_FLAGS=""
if [ -n "$OPENFANG_API_KEY" ]; then
    AUTH_FLAGS="-H Authorization: Bearer $OPENFANG_API_KEY"
fi

# ── Create dedicated agents ──────────────────────────────────────────────────
echo "[openfang] Creating dedicated agents..."

create_agent() {
    NAME="$1"
    MODEL="$2"
    DESC="$3"
    
    # Check if agent already exists
    EXISTING=$(curl -sf $AUTH_FLAGS http://localhost:4200/api/agents 2>/dev/null | grep -o "\"name\":\"$NAME\"" || true)
    if [ -n "$EXISTING" ]; then
        echo "[openfang] Agent '$NAME' already exists, skipping"
        return 0
    fi
    
    # Create agent
    RESP=$(curl -s -X POST $AUTH_FLAGS \
        -H "Content-Type: application/json" \
        -d "{\"manifest_toml\": \"name = \\\"$NAME\\\"\\nprofile = \\\"Full\\\"\\nmodel = \\\"$MODEL\\\"\\ndescription = \\\"$DESC\\\"\\n\"}" \
        http://localhost:4200/api/agents 2>&1)
    
    if echo "$RESP" | grep -q "agent_id"; then
        AGENT_ID=$(echo "$RESP" | grep -o '"agent_id":"[^"]*"' | cut -d'"' -f4)
        echo "[openfang] Created agent '$NAME' ($AGENT_ID)"
    else
        echo "[openfang] WARNING: Failed to create agent '$NAME': $RESP"
    fi
}

create_agent "general-assistant" "ollama/qwen3.5:9b" "General purpose assistant for Discord bot interactions"
create_agent "researcher" "ollama/qwen3.5:9b" "Dedicated researcher for workflow and cron job execution"

# Print all agent IDs for SCHEDULER_AGENT_ID setup
echo "[openfang] All agents:"
curl -sf $AUTH_FLAGS http://localhost:4200/api/agents 2>/dev/null | python3 -c "
import sys, json
try:
    agents = json.load(sys.stdin)
    for a in agents:
        print(f\"  {a['name']}: {a['id']}\")
except:
    print('  (could not parse agents)')
" 2>/dev/null || true

# ── Configure Discord channel adapter ────────────────────────────────────────
if [ -n "$DISCORD_BOT_TOKEN" ]; then
    echo "[openfang] Configuring Discord channel adapter..."
    
    RESP=$(curl -s -X POST $AUTH_FLAGS \
        -H "Content-Type: application/json" \
        -d '{"bot_token_env": "DISCORD_BOT_TOKEN", "default_agent": "general-assistant", "guild_ids": []}' \
        http://localhost:4200/api/channels/discord/configure 2>&1)
    echo "[openfang] Discord configure: $RESP"
    
    RELOAD=$(curl -s -X POST $AUTH_FLAGS http://localhost:4200/api/channels/reload 2>&1)
    echo "[openfang] Channels reload: $RELOAD"
fi

# Bring OpenFang to foreground
wait $OPENFANG_PID
