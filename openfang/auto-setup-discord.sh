#!/bin/sh
# Auto-configure and activate Discord channel adapter on startup.
# OpenFang requires explicit API configuration even when [discord] is in config.toml.
set -e

API_URL="${OPENFANG_API_URL:-http://localhost:4200}"
API_KEY="${OPENFANG_API_KEY:-}"

AUTH_FLAGS=""
if [ -n "$API_KEY" ]; then
    AUTH_FLAGS="-H Authorization: Bearer $API_KEY"
fi

# Wait for OpenFang to be ready
echo "[discord-auto-setup] Waiting for OpenFang API..."
for i in $(seq 1 60); do
    if curl -sf $AUTH_FLAGS "$API_URL/api/health" > /dev/null 2>&1; then
        echo "[discord-auto-setup] OpenFang is ready"
        break
    fi
    sleep 1
done

# Check if DISCORD_BOT_TOKEN is set
if [ -z "$DISCORD_BOT_TOKEN" ]; then
    echo "[discord-auto-setup] DISCORD_BOT_TOKEN not set, skipping Discord setup"
    exit 0
fi

echo "[discord-auto-setup] Configuring Discord channel adapter..."

# Configure Discord via API
RESP=$(curl -sf -X POST $AUTH_FLAGS \
    -H "Content-Type: application/json" \
    -d '{
        "bot_token_env": "DISCORD_BOT_TOKEN",
        "default_agent": "assistant",
        "guild_ids": []
    }' \
    "$API_URL/api/channels/discord/configure" 2>&1 || true)

echo "[discord-auto-setup] Configure response: $RESP"

# Reload channels to activate
RELOAD=$(curl -sf -X POST $AUTH_FLAGS \
    "$API_URL/api/channels/reload" 2>&1 || true)

echo "[discord-auto-setup] Reload response: $RELOAD"

# Verify Discord is active
STATUS=$(curl -sf $AUTH_FLAGS "$API_URL/api/channels" 2>&1 | grep -o '"name":"discord"[^}]*' || true)
echo "[discord-auto-setup] Discord status: $STATUS"

echo "[discord-auto-setup] Done"
