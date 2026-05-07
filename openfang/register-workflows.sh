#!/bin/sh
# =============================================================================
# Manual Workflow Registration Script for OpenFang
# 
# Run this script to register all workflow JSON files with OpenFang.
# This can be run manually when the scheduler hasn't registered them,
# or when you add new workflows.
#
# Usage: ./register-workflows.sh [openfang-api-url]
#   Default API URL: http://localhost:4200
# =============================================================================

set -e

API_URL="${1:-http://localhost:4200}"
WORKFLOWS_DIR="./workflows"

echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  OpenFang Workflow Registration Tool"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "API Endpoint: ${API_URL}"
echo "Workflows directory: ${WORKFLOWS_DIR}"
echo ""

# Check if OpenFang is accessible
echo "[check] Testing connection to OpenFang..."
if ! curl -sf "${API_URL}/api/health" > /dev/null 2>&1; then
    echo "[error] ❌ Cannot connect to OpenFang at ${API_URL}"
    echo ""
    echo "Make sure OpenFang is running:"
    echo "  docker compose -f openfang/docker-compose.yaml up -d openfang"
    echo ""
    exit 1
fi
echo "[check] ✅ OpenFang is running and accessible"
echo ""

# Function to register a single workflow
register_workflow() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    
    # Extract workflow name from JSON
    local name
    name=$(jq -r '.name' "$file" 2>/dev/null || echo "unknown")
    
    if [ "$name" = "null" ] || [ -z "$name" ] || [ "$name" = "unknown" ]; then
        echo "[skip] ⚠️  ${filename}: No valid 'name' field found in JSON"
        return 1
    fi
    
    echo "[register] 📝 ${name} (${filename})..."
    
    # Check if workflow already exists
    local existing_id
    existing_id=$(curl -sf "${API_URL}/api/workflows" 2>/dev/null | \
        jq -r --arg name "$name" '.[] | select(.name == $name) | .id' 2>/dev/null || echo "")
    
    if [ -n "$existing_id" ]; then
        echo "[exists] ✓ Already registered (ID: ${existing_id})"
        echo "         To re-register, delete it first via API or use a different name"
        return 0
    fi
    
    # Register the workflow
    local response
    response=$(curl -sf -X POST "${API_URL}/api/workflows" \
        -H "Content-Type: application/json" \
        -d @"$file" 2>/dev/null || echo '{"error":"registration failed"}')
    
    # Check if registration succeeded
    local new_id
    new_id=$(echo "$response" | jq -r '.id // .error // "unknown"' 2>/dev/null || echo "parse_error")
    
    if [ "$new_id" = "registration failed" ] || [ "$new_id" = "unknown" ] || [ "$new_id" = "parse_error" ]; then
        echo "[error] ❌ Failed to register ${name}"
        echo "        Response: ${response}"
        return 1
    else
        echo "[success] ✅ Registered (ID: ${new_id})"
        return 0
    fi
}

# Count total workflows
total=0
for file in "${WORKFLOWS_DIR}"/*.json; do
    [ -f "$file" ] && ((total++))
done

echo "[scan] Found ${total} workflow files"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Registering Workflows..."
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

# Register all workflow files
success_count=0
error_count=0

for file in "${WORKFLOWS_DIR}"/*.json; do
    if [ -f "$file" ]; then
        if register_workflow "$file"; then
            ((success_count++))
        else
            ((error_count++))
        fi
        echo ""
    fi
done

# Summary
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Registration Summary"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Total workflows: ${total}"
echo "Successfully registered: ${success_count}"
echo "Errors: ${error_count}"
echo ""

# List all registered workflows
echo "Currently registered workflows:"
echo "─────────────────────────────────────────────────────────────────────────────────"
curl -sf "${API_URL}/api/workflows" 2>/dev/null | \
    jq -r '.[] | "  • \(.name) (ID: \(.id))"' 2>/dev/null || \
    echo "  (Could not retrieve workflow list)"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Start the scheduler to enable automated execution:"
echo "     docker compose -f openfang/docker-compose.yaml up -d openfang-scheduler"
echo ""
echo "  2. Or manually trigger a workflow:"
echo "     curl -X POST ${API_URL}/api/workflows/<workflow-id>/run \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d '{\"input\": \"test\"}'"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
