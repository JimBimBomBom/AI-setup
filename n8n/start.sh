#!/bin/sh
# n8n startup - imports workflows after server starts

set -e

echo "[n8n] Starting server..."
n8n start &
N8N_PID=$!

echo "[n8n] Waiting for initialization..."
for i in $(seq 1 60); do
    if curl -sf http://localhost:5678/healthz >/dev/null 2>&1; then
        echo "[n8n] Server ready"
        break
    fi
    sleep 1
done

sleep 3

# Import workflows
echo "[n8n] Importing workflows..."
count=0
for wf in /workflows/*.json; do
    if [ -f "$wf" ]; then
        name=$(basename "$wf" .json)
        if n8n import:workflow --input="$wf" 2>/dev/null; then
            echo "[n8n]  + $name"
            count=$((count + 1))
        else
            echo "[n8n]  x $name (import failed)"
        fi
    fi
done
echo "[n8n] Imported: $count workflows"

wait $N8N_PID
