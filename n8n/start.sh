#!/bin/sh
# N8N Startup Script - Auto-import workflows and start n8n

set -e

echo "=========================================="
echo "n8n Startup Script"
echo "=========================================="
echo ""

# Function to check if n8n is ready
wait_for_n8n() {
    echo "Waiting for n8n to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:5678/healthz > /dev/null 2>&1 || \
           curl -s http://localhost:5678/ > /dev/null 2>&1; then
            echo "✓ n8n is ready!"
            return 0
        fi
        attempt=$((attempt + 1))
        echo "  Attempt $attempt/$max_attempts - waiting..."
        sleep 2
    done
    
    echo "⚠ Warning: n8n health check timeout, proceeding anyway..."
    return 1
}

# Start n8n in background
echo "Starting n8n in background..."
n8n start &
N8N_PID=$!

# Wait for n8n to initialize
sleep 5
wait_for_n8n

# Import all workflows from /workflows directory
echo ""
echo "=========================================="
echo "Importing Workflows"
echo "=========================================="

if [ -d "/workflows" ]; then
    workflow_count=0
    for workflow_file in /workflows/*.json; do
        if [ -f "$workflow_file" ]; then
            workflow_name=$(basename "$workflow_file" .json)
            echo ""
            echo "→ Importing: $workflow_name"
            
            if n8n import:workflow --input="$workflow_file" 2>&1; then
                echo "✓ Successfully imported: $workflow_name"
                workflow_count=$((workflow_count + 1))
            else
                echo "✗ Failed to import: $workflow_name"
            fi
        fi
    done
    
    echo ""
    echo "=========================================="
    echo "Import Summary: $workflow_count workflow(s) imported"
    echo "=========================================="
else
    echo "⚠ Warning: /workflows directory not found"
fi

echo ""
echo "=========================================="
echo "n8n is running and ready!"
echo "Access at: http://localhost:5678"
echo "=========================================="

# Wait for n8n process to complete
wait $N8N_PID
