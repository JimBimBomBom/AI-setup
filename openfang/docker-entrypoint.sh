#!/bin/sh
# OpenFang container entrypoint.
#
# Generates /root/.openfang/config.toml from the mounted template by
# substituting ${OLLAMA_MODEL} and any other ${VAR} placeholders with
# values from the container's environment (set via docker-compose env_file).
#
# Auto-configures Discord channel adapter if DISCORD_BOT_TOKEN is set.
# Then starts OpenFang normally.
set -e

TEMPLATE="/config-template/config.toml.template"
CONFIG="/root/.openfang/config.toml"

mkdir -p /root/.openfang

if [ -f "$TEMPLATE" ]; then
    # Substitute env vars into the template and write the live config
    envsubst < "$TEMPLATE" > "$CONFIG"
    echo "[openfang] config.toml generated"
    echo "[openfang]   OLLAMA_MODEL = ${OLLAMA_MODEL:-<not set>}"
    echo "[openfang]   provider url = ${OLLAMA_BASE_URL:-http://host.docker.internal:11434/v1}"
else
    echo "[openfang] WARNING: config template not found at $TEMPLATE"
    echo "[openfang] Continuing with any existing config at $CONFIG"
fi

# Auto-configure Discord channel adapter if token is present
if [ -n "$DISCORD_BOT_TOKEN" ]; then
    echo "[openfang] DISCORD_BOT_TOKEN detected — will auto-configure Discord adapter"
    
    # Start OpenFang in background
    openfang start &
    OPENFANG_PID=$!
    
    # Wait for API to be ready
    echo "[openfang] Waiting for API to be ready..."
    for i in $(seq 1 60); do
        if curl -sf http://localhost:4200/api/health > /dev/null 2>&1; then
            echo "[openfang] API ready"
            break
        fi
        sleep 1
    done
    
    # Configure Discord via API
    echo "[openfang] Configuring Discord channel adapter..."
    AUTH_FLAGS=""
    if [ -n "$OPENFANG_API_KEY" ]; then
        AUTH_FLAGS="-H Authorization: Bearer $OPENFANG_API_KEY"
    fi

    # Create dedicated agents if they don't exist
    echo "[openfang] Creating agents..."
    
    # General Assistant (for Discord interactions)
    curl -sf -X POST $AUTH_FLAGS \
        -H "Content-Type: application/json" \
        -d '{"manifest_toml": "name = \"general-assistant\"\nprofile = \"Full\"\nmodel = \"ollama/qwen3.5:9b\"\ndescription = \"General purpose assistant for Discord bot interactions.\"\n"}' \
        http://localhost:4200/api/agents > /dev/null 2>&1 || true
    
    # Researcher (for workflow/cron execution)
    curl -sf -X POST $AUTH_FLAGS \
        -H "Content-Type: application/json" \
        -d '{"manifest_toml": "name = \"researcher\"\nprofile = \"Full\"\nmodel = \"ollama/qwen3.5:9b\"\ndescription = \"Dedicated researcher for workflow and cron job execution.\"\n"}' \
        http://localhost:4200/api/agents > /dev/null 2>&1 || true
    
    echo "[openfang] Agents created (or already exist)"
    
    # Configure Discord to use general-assistant
    RESP=$(curl -sf -X POST $AUTH_FLAGS \
        -H "Content-Type: application/json" \
        -d '{"bot_token_env": "DISCORD_BOT_TOKEN", "default_agent": "general-assistant", "guild_ids": []}' \
        http://localhost:4200/api/channels/discord/configure 2>&1 || echo "FAILED")
    echo "[openfang] Discord configure: $RESP"
    
    # Reload channels to activate
    RELOAD=$(curl -sf -X POST $AUTH_FLAGS http://localhost:4200/api/channels/reload 2>&1 || echo "FAILED")
    echo "[openfang] Channels reload: $RELOAD"
    
    # Bring OpenFang to foreground
    wait $OPENFANG_PID
else
    exec openfang start
fi
