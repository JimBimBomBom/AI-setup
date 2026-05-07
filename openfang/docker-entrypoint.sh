#!/bin/sh
# OpenFang container entrypoint.
#
# Generates /root/.openfang/config.toml from the mounted template by
# substituting ${OLLAMA_MODEL} and any other ${VAR} placeholders with
# values from the container's environment (set via docker-compose env_file).
#
# After that it just starts OpenFang normally.
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

exec openfang start
