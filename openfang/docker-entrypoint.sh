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

# ── Create dedicated agents ──────────────────────────────────────────────────
echo "[openfang] Creating dedicated agents..."

create_agent() {
    NAME="$1"
    MODEL="$2"
    DESC="$3"
    
    # Check if agent already exists
    if [ -n "$OPENFANG_API_KEY" ]; then
        EXISTING=$(curl -sf -H "Authorization: Bearer $OPENFANG_API_KEY" http://localhost:4200/api/agents 2>/dev/null | python3 -c "
import sys, json
try:
    for a in json.load(sys.stdin):
        if a.get('name') == '$NAME':
            print('exists')
            break
except: pass
" 2>/dev/null || true)
    else
        EXISTING=$(curl -sf http://localhost:4200/api/agents 2>/dev/null | python3 -c "
import sys, json
try:
    for a in json.load(sys.stdin):
        if a.get('name') == '$NAME':
            print('exists')
            break
except: pass
" 2>/dev/null || true)
    fi
    
    if [ "$EXISTING" = "exists" ]; then
        echo "[openfang] Agent '$NAME' already exists, skipping"
        return 0
    fi
    
    # Create agent using inline JSON with escaped newlines
    if [ -n "$OPENFANG_API_KEY" ]; then
        RESP=$(curl -s -X POST \
            -H "Authorization: Bearer $OPENFANG_API_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"manifest_toml\": \"name = \\\"$NAME\\\"\\nprofile = \\\"Full\\\"\\nmodel = \\\"$MODEL\\\"\\ndescription = \\\"$DESC\\\"\\n\"}" \
            http://localhost:4200/api/agents 2>&1)
    else
        RESP=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "{\"manifest_toml\": \"name = \\\"$NAME\\\"\\nprofile = \\\"Full\\\"\\nmodel = \\\"$MODEL\\\"\\ndescription = \\\"$DESC\\\"\\n\"}" \
            http://localhost:4200/api/agents 2>&1)
    fi
    
    if echo "$RESP" | grep -q "agent_id"; then
        AGENT_ID=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('agent_id',''))" 2>/dev/null || true)
        echo "[openfang] Created agent '$NAME' ($AGENT_ID)"
    else
        echo "[openfang] WARNING: Failed to create agent '$NAME': $RESP"
    fi
}

create_agent "general-assistant" "ollama/qwen3.5:9b" "General purpose assistant for Discord bot interactions"
create_agent "researcher" "ollama/qwen3.5:9b" "Dedicated researcher for workflow and cron job execution"

# Print all agent IDs
echo "[openfang] All agents:"
if [ -n "$OPENFANG_API_KEY" ]; then
    curl -sf -H "Authorization: Bearer $OPENFANG_API_KEY" http://localhost:4200/api/agents 2>/dev/null | python3 -c "
import sys, json
try:
    for a in json.load(sys.stdin):
        print(f\"  {a['name']}: {a['id']}\")
except:
    print('  (could not parse)')
" 2>/dev/null || true
else
    curl -sf http://localhost:4200/api/agents 2>/dev/null | python3 -c "
import sys, json
try:
    for a in json.load(sys.stdin):
        print(f\"  {a['name']}: {a['id']}\")
except:
    print('  (could not parse)')
" 2>/dev/null || true
fi

# ── Configure Discord channel adapter ────────────────────────────────────────
if [ -n "$DISCORD_BOT_TOKEN" ]; then
    echo "[openfang] Configuring Discord channel adapter..."
    
    if [ -n "$OPENFANG_API_KEY" ]; then
        RESP=$(curl -s -X POST \
            -H "Authorization: Bearer $OPENFANG_API_KEY" \
            -H "Content-Type: application/json" \
            -d '{"bot_token_env": "DISCORD_BOT_TOKEN", "default_agent": "general-assistant", "guild_ids": []}' \
            http://localhost:4200/api/channels/discord/configure 2>&1)
    else
        RESP=$(curl -s -X POST \
            -H "Content-Type: application/json" \
            -d '{"bot_token_env": "DISCORD_BOT_TOKEN", "default_agent": "general-assistant", "guild_ids": []}' \
            http://localhost:4200/api/channels/discord/configure 2>&1)
    fi
    echo "[openfang] Discord configure: $RESP"
    
    if [ -n "$OPENFANG_API_KEY" ]; then
        RELOAD=$(curl -s -X POST \
            -H "Authorization: Bearer $OPENFANG_API_KEY" \
            http://localhost:4200/api/channels/reload 2>&1)
    else
        RELOAD=$(curl -s -X POST http://localhost:4200/api/channels/reload 2>&1)
    fi
    echo "[openfang] Channels reload: $RELOAD"
fi

# Bring OpenFang to foreground
wait $OPENFANG_PID
