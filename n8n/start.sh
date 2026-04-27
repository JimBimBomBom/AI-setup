#!/bin/sh
# N8N Startup Script - Import workflows after n8n starts

set -e

echo "=========================================="
echo "n8n with Auto-Import"
echo "=========================================="

# Start n8n in background
echo "Starting n8n server..."
n8n start &
N8N_PID=$!

# Wait for n8n to fully initialize by watching logs
echo ""
echo "Waiting for n8n to initialize..."
echo "(This may take 30-60 seconds on first run)"
echo ""

# Wait for the editor to be accessible message
LOG_WAIT=60
while [ $LOG_WAIT -gt 0 ]; do
    if docker logs n8n 2>/dev/null | grep -q "Editor is now accessible"; then
        echo "✓ n8n is ready!"
        break
    fi
    sleep 1
    LOG_WAIT=$((LOG_WAIT - 1))
    if [ $((LOG_WAIT % 10)) -eq 0 ]; then
        echo "  Still initializing... ($LOG_WAIT seconds remaining)"
    fi
done

# Give it a few more seconds to fully stabilize
sleep 5

# Import workflows
echo ""
echo "=========================================="
echo "Importing Workflows"
echo "=========================================="

workflow_count=0
if [ -d "/workflows" ]; then
    for workflow_file in /workflows/*.json; do
        if [ -f "$workflow_file" ]; then
            workflow_name=$(basename "$workflow_file" .json)
            echo "→ Importing: $workflow_name"
            
            if n8n import:workflow --input="$workflow_file" 2>&1; then
                echo "  ✓ Imported successfully"
                workflow_count=$((workflow_count + 1))
            else
                echo "  ✗ Import failed (check logs)"
            fi
        fi
    done
else
    echo "⚠ /workflows directory not found"
fi

echo ""
echo "=========================================="
echo "Imported: $workflow_count workflow(s)"
echo "=========================================="
echo ""
echo "n8n is ready at: http://localhost:5678"
echo ""
echo "To trigger test job manually:"
echo "  1. Open http://localhost:5678"
echo "  2. Click on 'test' workflow"
echo "  3. Click 'Execute Workflow' button"
echo ""

# Keep n8n running
wait $N8N_PID
