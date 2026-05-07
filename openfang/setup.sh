#!/usr/bin/env bash
# =============================================================================
# OpenFang — optional convenience wrapper
#
# Validates .env before starting so you get clear error messages instead of
# a silently misconfigured container.
#
# You can also start directly without this script:
#   docker compose -f openfang/docker-compose.yaml up -d
#
# Run from repo root: ./openfang/setup.sh
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="${ROOT_DIR}/openfang/docker-compose.yaml"
ENV_FILE="${ROOT_DIR}/.env"

# ── Load and validate .env ────────────────────────────────────────────────────
if [ ! -f "${ENV_FILE}" ]; then
  echo "ERROR: .env not found. Run: cp .env.example .env"
  exit 1
fi
set -a; source "${ENV_FILE}"; set +a

errors=0

check() {
  local var="$1" hint="$2"
  if [ -z "${!var:-}" ]; then
    echo "  MISSING: ${var} — ${hint}"
    errors=$((errors + 1))
  else
    echo "  OK:      ${var}"
  fi
}

echo "Checking .env..."
check OLLAMA_MODEL       "run ./list-models.sh to see available models"
check DISCORD_BOT_TOKEN  "discord.com/developers → New App → Bot → Copy Token"
check DISCORD_WEBHOOK_URL "Discord Server Settings → Integrations → Webhooks"

if [ "${errors}" -gt 0 ]; then
  echo ""
  echo "${errors} required variable(s) missing in .env. Fix them and re-run."
  exit 1
fi

echo ""
echo "Starting OpenFang (model: ${OLLAMA_MODEL})..."
docker compose -f "${COMPOSE}" up -d

echo ""
echo "  Dashboard:  http://localhost:4200"
echo "  Logs:       docker logs -f openfang"
echo "              docker logs -f openfang-scheduler"
