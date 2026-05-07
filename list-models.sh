#!/usr/bin/env bash
# =============================================================================
# List available Ollama models
#
# Shows all models pulled on this machine, their sizes, and which one is
# currently selected as OLLAMA_MODEL in .env.
#
# Usage: ./list-models.sh [ollama-url]
#   ollama-url defaults to http://localhost:11434
# =============================================================================
set -euo pipefail

OLLAMA_URL="${1:-http://localhost:11434}"
ENV_FILE="$(dirname "$0")/.env"

# Read current OLLAMA_MODEL from .env if it exists
CURRENT_MODEL=""
if [ -f "${ENV_FILE}" ]; then
  CURRENT_MODEL=$(grep -E "^OLLAMA_MODEL=" "${ENV_FILE}" | cut -d'=' -f2- | tr -d '"' || true)
fi

echo "Ollama models at ${OLLAMA_URL}:"
echo ""

# Query Ollama's tags API
RESPONSE=$(curl -sf "${OLLAMA_URL}/api/tags" 2>/dev/null || true)

if [ -z "${RESPONSE}" ]; then
  echo "  ERROR: Could not reach Ollama at ${OLLAMA_URL}"
  echo "         Make sure Ollama is running: sudo ./ai-mode.sh status"
  exit 1
fi

# Check if jq is available
if command -v jq &>/dev/null; then
  echo "${RESPONSE}" | jq -r '
    .models[]
    | [
        .name,
        ((.size / 1073741824) | floor | tostring) + " GB",
        (if .details.parameter_size then .details.parameter_size else "" end)
      ]
    | @tsv
  ' | while IFS=$'\t' read -r name size params; do
    marker=""
    if [ "${name}" = "${CURRENT_MODEL}" ]; then
      marker=" ← current (OLLAMA_MODEL)"
    fi
    printf "  %-40s %8s  %s%s\n" "${name}" "${size}" "${params}" "${marker}"
  done
else
  # Fallback without jq
  echo "${RESPONSE}" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | while read -r name; do
    marker=""
    if [ "${name}" = "${CURRENT_MODEL}" ]; then
      marker=" ← current"
    fi
    echo "  ${name}${marker}"
  done
fi

echo ""
if [ -n "${CURRENT_MODEL}" ]; then
  echo "Current OLLAMA_MODEL in .env: ${CURRENT_MODEL}"
  echo ""
  echo "To switch model: edit OLLAMA_MODEL in .env, then restart:"
  echo "  docker compose -f openfang/docker-compose.yaml restart openfang"
  echo "  ./openclaw/init-cron.sh   (if OpenClaw is running)"
else
  echo "OLLAMA_MODEL not set in .env"
  echo ""
  echo "Add one of the models above to your .env:"
  echo "  OLLAMA_MODEL=qwen3.5:27b"
  echo ""
  echo "Then start OpenFang:"
  echo "  docker compose -f openfang/docker-compose.yaml up -d"
fi
