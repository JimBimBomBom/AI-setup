#!/bin/sh
# Quick diagnostic for OpenFang Scheduler

echo "=========================================="
echo "OpenFang Scheduler Diagnostic"
echo "=========================================="
echo ""

# Check if we're in the scheduler container
if [ -f /etc/alpine-release ]; then
    echo "Running inside scheduler container ✅"
    IN_CONTAINER=1
else
    echo "Running on host system"
    IN_CONTAINER=0
fi

echo ""
echo "1. Checking environment variables:"
echo "----------------------------------------"
if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    echo "✅ DISCORD_WEBHOOK_URL is set"
    echo "   Value: ${DISCORD_WEBHOOK_URL:0:50}..."
else
    echo "❌ DISCORD_WEBHOOK_URL is NOT set"
    echo "   Cron jobs will NOT be created!"
    echo "   Fix: Add DISCORD_WEBHOOK_URL to .env file"
fi

if [ -n "$OPENFANG_API_URL" ]; then
    echo "✅ OPENFANG_API_URL is set: $OPENFORD_API_URL"
else
    echo "⚠️  OPENFANG_API_URL not set (using default: http://openfang:4200)"
fi

echo ""
echo "2. Checking required binaries:"
echo "----------------------------------------"
for cmd in curl jq crond; do
    if command -v $cmd >/dev/null 2>&1; then
        echo "✅ $cmd: $(which $cmd)"
    else
        echo "❌ $cmd: NOT FOUND"
    fi
done

echo ""
echo "3. Checking directory structure:"
echo "----------------------------------------"
if [ -d /workflows ]; then
    WF_COUNT=$(ls /workflows/*.json 2>/dev/null | wc -l)
    echo "✅ /workflows exists with $WF_COUNT workflow files"
    ls /workflows/*.json 2>/dev/null | head -5 | sed 's/^/   - /'
    [ $WF_COUNT -gt 5 ] && echo "   ... and $((WF_COUNT - 5)) more"
else
    echo "❌ /workflows directory NOT FOUND"
fi

if [ -d /scheduler ]; then
    echo "✅ /scheduler exists"
    for script in entrypoint.sh run-workflow.sh; do
        if [ -f "/scheduler/$script" ]; then
            if [ -x "/scheduler/$script" ]; then
                echo "   ✅ $script is executable"
            else
                echo "   ⚠️  $script exists but NOT executable"
                echo "      Fix: chmod +x /scheduler/$script"
            fi
        else
            echo "   ❌ $script NOT FOUND"
        fi
    done
else
    echo "❌ /scheduler directory NOT FOUND"
fi

echo ""
echo "4. Checking crontab:"
echo "----------------------------------------"
if [ -f /var/spool/cron/crontabs/root ]; then
    JOB_COUNT=$(grep -v '^#' /var/spool/cron/crontabs/root 2>/dev/null | grep -v '^$' | wc -l)
    if [ $JOB_COUNT -gt 0 ]; then
        echo "✅ Crontab exists with $JOB_COUNT active jobs"
        echo ""
        echo "Scheduled jobs:"
        grep -v '^#' /var/spool/cron/crontabs/root | grep -v '^$' | sed 's/^/   /'
    else
        echo "⚠️  Crontab exists but has NO active jobs"
        echo "    This means workflow registration failed or"
        echo "    DISCORD_WEBHOOK_URL was not set"
    fi
else
    echo "❌ Crontab file NOT FOUND"
    echo "   The scheduler entrypoint hasn't run yet"
fi

echo ""
echo "5. Checking OpenFang connectivity:"
echo "----------------------------------------"
API="${OPENFANG_API_URL:-http://openfang:4200}"
echo "API endpoint: $API"

if curl -sf "${API}/api/health" >/dev/null 2>&1; then
    echo "✅ OpenFang API is reachable"
    
    # Check workflows
    WF_API_COUNT=$(curl -sf "${API}/api/workflows" 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    echo "✅ Workflows registered: $WF_API_COUNT"
    
    if [ $WF_API_COUNT -gt 0 ]; then
        echo ""
        echo "Registered workflow names:"
        curl -sf "${API}/api/workflows" 2>/dev/null | jq -r '.[].name' 2>/dev/null | sed 's/^/   - /'
    fi
else
    echo "❌ OpenFang API is NOT reachable"
    echo "   Check if openfang container is running:"
    echo "   docker ps | grep openfang"
fi

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="

ERRORS=0
WARNINGS=0

[ -z "$DISCORD_WEBHOOK_URL" ] && ERRORS=$((ERRORS + 1))
[ ! -d /workflows ] && ERRORS=$((ERRORS + 1))
[ ! -f /var/spool/cron/crontabs/root ] && WARNINGS=$((WARNINGS + 1))

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✅ All checks passed - scheduler is ready"
elif [ $ERRORS -gt 0 ]; then
    echo "❌ Found $ERRORS error(s) - fix required"
    echo ""
    echo "To restart with fixes:"
    echo "   1. Update .env with DISCORD_WEBHOOK_URL"
    echo "   2. docker compose restart openfang-scheduler"
else
    echo "⚠️  Found $WARNINGS warning(s) - may affect functionality"
fi

echo ""
echo "Useful commands:"
echo "   View scheduler logs:     docker logs -f openfang-scheduler"
echo "   View cron job output:    docker exec openfang-scheduler tail -f /var/log/scheduler.log"
echo "   Check crontab:           docker exec openfang-scheduler crontab -l"
echo "   Restart scheduler:       docker compose restart openfang-scheduler"
echo ""
