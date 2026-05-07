#!/usr/bin/env bash
# =============================================================================
# OpenClaw Setup Script
# Clones the openclaw/openclaw repo, builds the Docker image, starts the
# gateway, and registers the news-digest cron jobs.
#
# Run once: ./openclaw/setup.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="${SCRIPT_DIR}/src"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"

# Load .env from repo root if it exists
if [ -f "${ROOT_DIR}/.env" ]; then
  # shellcheck disable=SC1091
  set -a; source "${ROOT_DIR}/.env"; set +a
fi

# ── 1. Clone OpenClaw source ──────────────────────────────────────────────────
if [ ! -d "${SRC_DIR}/.git" ]; then
  echo ">>> Cloning openclaw/openclaw..."
  git clone --depth 1 https://github.com/openclaw/openclaw.git "${SRC_DIR}"
else
  echo ">>> OpenClaw source already present — pulling latest..."
  git -C "${SRC_DIR}" pull --ff-only
fi

# ── 2. Build the Docker image ─────────────────────────────────────────────────
echo ">>> Building openclaw:local image..."
docker build -t openclaw:local "${SRC_DIR}"

# ── 3. Start the gateway ──────────────────────────────────────────────────────
echo ">>> Starting OpenClaw gateway..."
docker compose -f "${SCRIPT_DIR}/docker-compose.yaml" up -d

# ── 4. Wait for gateway to be ready ──────────────────────────────────────────
echo ">>> Waiting for gateway to be ready (this may take ~30s)..."
for i in $(seq 1 30); do
  if docker compose -f "${SCRIPT_DIR}/docker-compose.yaml" exec openclaw-gateway \
      node dist/index.js health 2>/dev/null | grep -q "ok"; then
    echo ">>> Gateway is ready."
    break
  fi
  sleep 2
  if [ "$i" -eq 30 ]; then
    echo ">>> Gateway did not respond — check logs with:"
    echo "    docker compose -f openclaw/docker-compose.yaml logs"
    exit 1
  fi
done

# ── 5. Register cron jobs ─────────────────────────────────────────────────────
echo ">>> Registering cron jobs..."
bash "${SCRIPT_DIR}/init-cron.sh"

echo ""
echo "✓ OpenClaw setup complete."
echo ""
echo "  Dashboard:  http://localhost:18789"
echo "  Logs:       docker compose -f openclaw/docker-compose.yaml logs -f"
echo "  Cron jobs:  docker exec openclaw-gateway node dist/index.js cron list"
echo ""
  echo "  Next steps:"
  echo "  1. Set DISCORD_BOT_TOKEN in your .env"
  echo "  2. Set DISCORD_CHANNEL_ID in your .env"
  echo "  3. Re-run ./openclaw/init-cron.sh if you change channels"
