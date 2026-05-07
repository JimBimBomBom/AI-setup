#!/bin/sh
# OpenFang Scheduler - Auto-registers workflows and creates cron schedule on startup

API="${OPENFANG_API_URL:-http://openfang:4200}"
TIMEZONE="${TIMEZONE:-Europe/Oslo}"

# Logging to stderr only (so it doesn't mix with function return values)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

log "=========================================="
log "OpenFang Scheduler Starting"
log "=========================================="

# Set timezone
log "Setting timezone to ${TIMEZONE}"
if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
    cp "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    echo "${TIMEZONE}" > /etc/timezone
    log "Timezone set to ${TIMEZONE}"
else
    log "WARNING: Unknown timezone '${TIMEZONE}', using UTC"
fi

# Wait for OpenFang
log "Waiting for OpenFang API at ${API}..."
RETRY=0
MAX_RETRY=30
while ! curl -sf "${API}/api/health" >/dev/null 2>&1; do
    RETRY=$((RETRY + 1))
    if [ $RETRY -ge $MAX_RETRY ]; then
        log "ERROR: OpenFang not available after ${MAX_RETRY} retries (90s)"
        log "Scheduler will start without workflows"
        break
    fi
    log "Attempt ${RETRY}/${MAX_RETRY} - waiting for OpenFang..."
    sleep 3
done

if [ $RETRY -lt $MAX_RETRY ]; then
    log "OpenFang is ready"
else
    log "WARNING: Proceeding without workflow registration"
fi

# Only register workflows if OpenFang is available
WORKFLOW_IDS=""
if [ $RETRY -lt $MAX_RETRY ]; then
    log ""
    log "=========================================="
    log "Registering Workflows"
    log "=========================================="

    # Register a single workflow - outputs ONLY the ID to stdout, logs to stderr
    register_workflow() {
        local file="$1"
        local name
        name=$(jq -r '.name' "$file" 2>/dev/null || echo "")
        
        if [ -z "$name" ] || [ "$name" = "null" ]; then
            log "ERROR: Invalid workflow JSON: $file"
            echo "FAILED"
            return 1
        fi
        
        log "Registering: $name"
        
        # Check if already exists
        local existing
        existing=$(curl -sf "${API}/api/workflows" 2>/dev/null | jq -r --arg n "$name" '.[] | select(.name == $n) | .id' | head -1)
        
        if [ -n "$existing" ]; then
            log "  -> Already registered (ID: ${existing:0:12}...)"
            echo "$existing"
            return 0
        fi
        
        # Register new
        local response
        response=$(curl -sf -X POST "${API}/api/workflows" -H "Content-Type: application/json" -d @"$file" 2>/dev/null || echo '{"error":"failed"}')
        local id
        id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null)
        
        if [ -n "$id" ]; then
            log "  -> Registered (ID: ${id:0:12}...)"
            echo "$id"
            return 0
        else
            log "  -> FAILED to register"
            log "     Response: $response"
            echo "FAILED"
            return 1
        fi
    }

    # Register all workflows
    WORLD_NEWS_ID=$(register_workflow /workflows/world-news.json)
    GLOBAL_NEWS_ID=$(register_workflow /workflows/global-news.json)
    AMERICAS_NEWS_ID=$(register_workflow /workflows/americas-news.json)
    EUROPE_NEWS_ID=$(register_workflow /workflows/europe-news.json)
    ASIA_PACIFIC_NEWS_ID=$(register_workflow /workflows/asia-pacific-news.json)
    TECH_DIGEST_ID=$(register_workflow /workflows/tech-digest.json)
    HACKER_NEWS_ID=$(register_workflow /workflows/hacker-news-digest.json)
    GITHUB_TRENDING_ID=$(register_workflow /workflows/github-trending.json)
    MARKET_BRIEF_ID=$(register_workflow /workflows/market-brief.json)
    INVESTING_INTEL_ID=$(register_workflow /workflows/investing-intelligence.json)
    GEOPOLITICAL_ID=$(register_workflow /workflows/geopolitical-perspectives.json)
    CODING_TECH_AI_ID=$(register_workflow /workflows/coding-tech-ai.json)
    DEEP_RESEARCH_ID=$(register_workflow /workflows/deep-research.json)
    MULTI_AGENT_ID=$(register_workflow /workflows/multi-agent-analysis.json)
    WEB_SCRAPING_ID=$(register_workflow /workflows/web-scraping-demo.json)

    log "Workflows registered"

    # Create cron schedule (only if DISCORD_WEBHOOK_URL is set)
    log ""
    log "=========================================="
    log "Creating Cron Schedule"
    log "=========================================="

    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        log "WARNING: DISCORD_WEBHOOK_URL not set"
        log "Add to .env: DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/..."
        log "Then restart: docker compose restart openfang-scheduler"
        log "Workflows are registered but no cron jobs created"
    else
        log "DISCORD_WEBHOOK_URL is set, creating cron jobs..."
        
        mkdir -p /var/spool/cron/crontabs
        
        # Create crontab header - only echo, no logging here
        cat > /var/spool/cron/crontabs/root << 'CRON_HEADER'
SHELL=/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin

# OpenFang Scheduled Workflows

CRON_HEADER

        JOB_COUNT=0

        # Helper to add cron job if workflow registered
        add_job() {
            local id="$1"
            local schedule="$2"
            local name="$3"
            local color="$4"
            
            if [ -n "$id" ] && [ "$id" != "FAILED" ]; then
                echo "$schedule sh /scheduler/run-workflow.sh \"$id\" \"\${DISCORD_WEBHOOK_URL}\" \"$name\" $color >> /var/log/scheduler.log 2>&1" >> /var/spool/cron/crontabs/root
                log "  + $name"
                JOB_COUNT=$((JOB_COUNT + 1))
            else
                log "  x $name (not registered, skipping)"
            fi
        }

        log ""
        log "News Workflows:"
        add_job "$WORLD_NEWS_ID" "0 6 * * *" "🌍 World News Bot" 3447003
        add_job "$GLOBAL_NEWS_ID" "30 6 * * *" "🌐 Global News Bot" 15158332
        add_job "$AMERICAS_NEWS_ID" "0 7 * * *" "🌎 Americas News Bot" 3066993
        add_job "$EUROPE_NEWS_ID" "30 7 * * *" "🇪🇺 Europe News Bot" 3447003
        add_job "$ASIA_PACIFIC_NEWS_ID" "0 8 * * *" "🌏 Asia-Pacific News Bot" 15105570

        log ""
        log "Finance Workflows:"
        add_job "$MARKET_BRIEF_ID" "30 8 * * *" "📈 Market Brief Bot" 5763719
        add_job "$INVESTING_INTEL_ID" "0 16 * * 1-5" "💹 Investing Intel Bot" 16776960

        log ""
        log "Tech Workflows:"
        add_job "$TECH_DIGEST_ID" "0 9 * * *" "💻 Tech Digest Bot" 5814783
        add_job "$CODING_TECH_AI_ID" "30 9 * * *" "👨‍💻 Dev Digest Bot" 3447003
        add_job "$HACKER_NEWS_ID" "0 10 * * *" "🟠 HN Digest Bot" 16744192
        add_job "$GITHUB_TRENDING_ID" "0 11 * * *" "🚀 GitHub Trends Bot" 3066993

        log ""
        log "Analysis Workflows:"
        add_job "$GEOPOLITICAL_ID" "0 12 * * *" "🌐 Geopol Intel Bot" 7419530

        # Set permissions
        chmod 600 /var/spool/cron/crontabs/root
        
        log ""
        log "Created $JOB_COUNT cron jobs"
        
        # Display crontab content
        log ""
        log "Crontab content:"
        log "----------------------------------------"
        while IFS= read -r line; do
            log "$line"
        done < /var/spool/cron/crontabs/root
        log "----------------------------------------"
    fi

    # Log manual workflow IDs
    log ""
    log "=========================================="
    log "Manual Workflow IDs (for API triggering)"
    log "=========================================="
    [ -n "$DEEP_RESEARCH_ID" ] && [ "$DEEP_RESEARCH_ID" != "FAILED" ] && log "  Deep Research: $DEEP_RESEARCH_ID"
    [ -n "$MULTI_AGENT_ID" ] && [ "$MULTI_AGENT_ID" != "FAILED" ] && log "  Multi-Agent: $MULTI_AGENT_ID"
    [ -n "$WEB_SCRAPING_ID" ] && [ "$WEB_SCRAPING_ID" != "FAILED" ] && log "  Web Scraping: $WEB_SCRAPING_ID"
else
    log ""
    log "Skipping workflow registration (OpenFang unavailable)"
fi

# Create test cron job for 16:34 (current time + few minutes for testing)
# Only add if we have the test ID
if [ -n "$HACKER_NEWS_ID" ] && [ "$HACKER_NEWS_ID" != "FAILED" ] && [ -n "$DISCORD_WEBHOOK_URL" ]; then
    log ""
    log "=========================================="
    log "Adding Test Cron Job"
    log "=========================================="
    
    # Add a test job at 16:34 (you can adjust this time)
    echo "34 16 * * * sh /scheduler/run-workflow.sh \"$HACKER_NEWS_ID\" \"\${DISCORD_WEBHOOK_URL}\" \"🧪 TEST: HN Digest\" 16744192 >> /var/log/scheduler.log 2>&1" >> /var/spool/cron/crontabs/root
    log "Added test job: 34 16 * * * (4:34 PM) - Hacker News Digest for testing"
fi

log ""
log "=========================================="
log "Starting Cron Daemon"
log "=========================================="
log "crond starting..."
log ""
log "To view scheduler activity:"
log "  docker logs -f openfang-scheduler"
log ""
log "To view cron job output:"
log "  docker exec openfang-scheduler tail -f /var/log/scheduler.log"
log ""

exec crond -f -l 6
