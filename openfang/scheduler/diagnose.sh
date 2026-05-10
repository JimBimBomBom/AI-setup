#!/bin/sh
# Quick diagnostic for OpenFang Scheduler

echo "=========================================="
echo "OpenFang Scheduler Diagnostic"
echo "=========================================="
echo ""

# Check if we're in the scheduler container
if [ -f /etc/alpine-release ]; then
    echo "Running inside scheduler container"
    IN_CONTAINER=1
else
    echo "Running on host system"
    IN_CONTAINER=0
fi

echo ""
echo "1. Checking environment variables:"
echo "----------------------------------------"
if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    echo "  DISCORD_WEBHOOK_URL is set"
    echo "   Value: ${DISCORD_WEBHOOK_URL:0:50}..."
else
    echo "  DISCORD_WEBHOOK_URL is NOT set"
    echo "   Discord messages will be dropped"
fi

if [ -n "$SCHEDULER_AGENT_ID" ]; then
    echo "  SCHEDULER_AGENT_ID is set: $SCHEDULER_AGENT_ID"
else
    echo "  SCHEDULER_AGENT_ID is NOT set"
    echo "   Jobs cannot be created without an owning agent"
fi

if [ -n "$SCHEDULER_WEBHOOK_TOKEN" ]; then
    echo "  SCHEDULER_WEBHOOK_TOKEN is set"
else
    echo "  SCHEDULER_WEBHOOK_TOKEN not set (webhook relay accepts any request)"
fi

if [ -n "$OPENFANG_API_URL" ]; then
    echo "  OPENFANG_API_URL is set: $OPENFANG_API_URL"
else
    echo "  OPENFANG_API_URL not set (using default: http://openfang:4200)"
fi

echo ""
echo "2. Checking required binaries:"
echo "----------------------------------------"
for cmd in curl jq python3; do
    if command -v $cmd >/dev/null 2>&1; then
        echo "  $cmd: $(which $cmd)"
    else
        echo "  $cmd: NOT FOUND"
    fi
done

echo ""
echo "3. Checking directory structure:"
echo "----------------------------------------"
if [ -d /workflows ]; then
    WF_COUNT=$(ls /workflows/*.json 2>/dev/null | wc -l)
    echo "  /workflows exists with $WF_COUNT workflow files"
    ls /workflows/*.json 2>/dev/null | head -5 | sed 's/^/   - /'
    [ $WF_COUNT -gt 5 ] && echo "   ... and $((WF_COUNT - 5)) more"
else
    echo "  /workflows directory NOT FOUND"
fi

if [ -d /scheduler ]; then
    echo "  /scheduler exists"
    for file in scheduler.py schedule.json diagnose.sh; do
        if [ -f "/scheduler/$file" ]; then
            echo "   $file present"
        else
            echo "   $file missing"
        fi
    done
else
    echo "  /scheduler directory NOT FOUND"
fi

echo ""
echo "4. Checking cron jobs via OpenFang API:"
echo "----------------------------------------"
API="${OPENFANG_API_URL:-http://openfang:4200}"
CRON_JSON=$(curl -sf "${API}/api/cron/jobs" 2>/dev/null)
if [ $? -eq 0 ]; then
    JOB_TOTAL=$(echo "$CRON_JSON" | jq '.total' 2>/dev/null)
    echo "  /api/cron/jobs reachable (total jobs: ${JOB_TOTAL:-0})"
    echo "   Managed jobs (prefix WF-):"
    echo "$CRON_JSON" | jq -r '.jobs[] | select(.name | startswith("WF-")) | "     - \(.name) -> \(.schedule.expr)"'
else
    echo "  Failed to call /api/cron/jobs"
fi

echo ""
echo "5. Checking OpenFang connectivity:"
echo "----------------------------------------"
API="${OPENFANG_API_URL:-http://openfang:4200}"
echo "API endpoint: $API"

if curl -sf "${API}/api/health" >/dev/null 2>&1; then
    echo "  OpenFang API is reachable"
    
    # Check workflows
    WF_API_COUNT=$(curl -sf "${API}/api/workflows" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    echo "  Workflows registered: $WF_API_COUNT"
    
    if [ $WF_API_COUNT -gt 0 ]; then
        echo ""
        echo "Registered workflow names:"
        curl -sf "${API}/api/workflows" 2>/dev/null | jq -r '.[].name' 2>/dev/null | sed 's/^/   - /'
    fi
else
    echo "  OpenFang API is NOT reachable"
    echo "   Check if openfang container is running:"
    echo "   docker ps | grep openfang"
fi

PORT="${SCHEDULER_HTTP_PORT:-8080}"
echo ""
echo "6. Checking scheduler endpoints:"
echo "----------------------------------------"
if curl -sf "http://localhost:${PORT}/healthz" >/dev/null 2>&1; then
    echo "  Webhook relay responding on port ${PORT} (/healthz)"
else
    echo "  Webhook relay not responding on port ${PORT}"
fi

if curl -sf "http://localhost:${PORT}/metrics" >/dev/null 2>&1; then
    echo "  Metrics endpoint responding (/metrics)"
    echo ""
    echo "  Metrics preview:"
    curl -sf "http://localhost:${PORT}/metrics" 2>/dev/null | head -6 | sed 's/^/   /'
else
    echo "  Metrics endpoint not responding"
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="

ERRORS=0
WARNINGS=0

[ -z "$DISCORD_WEBHOOK_URL" ] && ERRORS=$((ERRORS + 1))
[ -z "$SCHEDULER_AGENT_ID" ] && ERRORS=$((ERRORS + 1))
[ ! -d /workflows ] && ERRORS=$((ERRORS + 1))

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "  All checks passed - scheduler is ready"
elif [ $ERRORS -gt 0 ]; then
    echo "  Found $ERRORS error(s) - fix required"
    echo ""
    echo "To restart with fixes:"
    echo "   1. Update .env with DISCORD_WEBHOOK_URL"
    echo "   2. docker compose restart openfang-scheduler"
else
    echo "  Found $WARNINGS warning(s) - may affect functionality"
fi

echo ""
echo "Useful commands:"
echo "   View scheduler logs:     docker logs -f openfang-scheduler"
echo "   List cron jobs:          curl http://localhost:4200/api/cron/jobs | jq '.jobs[] | {name, schedule}'"
echo "   Trigger a job:           curl -X POST http://localhost:4200/api/workflows/<WORKFLOW_ID>/run"
echo "   Check webhook relay:     curl http://localhost:${SCHEDULER_HTTP_PORT:-8080}/healthz"
echo "   View metrics:            curl http://localhost:${SCHEDULER_HTTP_PORT:-8080}/metrics"
echo "   Restart scheduler:       docker compose restart openfang-scheduler"
echo ""
