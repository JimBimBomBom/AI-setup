# OpenFang Complete Guide

## Overview

OpenFang consists of **two containers**:

1. **openfang** (port 4200): Core API and workflow engine
2. **openfang-scheduler**: Cron-based workflow trigger system

## Quick Start

```bash
# Start both containers
cd openfang
docker compose up -d

# View scheduler initialization logs
docker logs -f openfang-scheduler

# Check if everything is working
docker exec openfang-scheduler sh /scheduler/diagnose.sh
```

## How the Scheduler Works

### Startup Sequence

```
1. Container starts
   └── Dockerfile ENTRYPOINT runs entrypoint.sh

2. entrypoint.sh executes:
   a. Set timezone
   b. Wait for OpenFang API (up to 90s)
   c. Register all workflow JSON files
   d. Create cron jobs (if DISCORD_WEBHOOK_URL set)
   e. Start crond daemon

3. crond runs continuously
   └── Triggers workflows at scheduled times
```

### What Gets Created

**Workflow Registration** (happens automatically):
- All `.json` files in `workflows/` are registered via API
- Each gets a unique ID stored in OpenFang
- IDs are used to trigger workflows

**Cron Schedule** (only if DISCORD_WEBHOOK_URL is set):
- Jobs created in `/var/spool/cron/crontabs/root`
- Each job runs `run-workflow.sh` at scheduled time
- Workflow output → Discord webhook

## Common Issues & Fixes

### Issue 1: "Scheduler is empty" (no cron jobs)

**Symptoms:**
- `docker exec openfang-scheduler crontab -l` shows nothing
- No automated workflow execution

**Causes:**
1. `DISCORD_WEBHOOK_URL` not set in `.env`
2. Workflow registration failed
3. OpenFang wasn't ready when scheduler started

**Fix:**

```bash
# Check the diagnostic
docker exec openfang-scheduler sh /scheduler/diagnose.sh

# If DISCORD_WEBHOOK_URL missing:
# 1. Edit ../.env and add:
#    DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR/TOKEN

# 2. Restart scheduler
docker compose restart openfang-scheduler

# 3. Watch logs
docker logs -f openfang-scheduler
```

### Issue 2: Workflows not registering

**Symptoms:**
- Logs show "0 workflows registered"
- API returns empty workflow list

**Fix:**

```bash
# Check if OpenFang is running
docker ps | grep openfang

# Check OpenFang health
curl http://localhost:4200/api/health

# Check workflow files exist
docker exec openfang-scheduler ls -la /workflows/

# If workflows missing from volume mount:
# Ensure docker-compose.yaml has: ./workflows:/workflows:ro

# Restart both
docker compose restart
```

### Issue 3: Cron jobs exist but don't run

**Symptoms:**
- `crontab -l` shows jobs
- No output in logs at scheduled times

**Fix:**

```bash
# Check if crond is running
docker exec openfang-scheduler pgrep crond

# Check run-workflow.sh is executable
docker exec openfang-scheduler ls -la /scheduler/run-workflow.sh

# If not executable:
docker exec openfang-scheduler chmod +x /scheduler/run-workflow.sh

# Test a workflow manually
docker exec openfang-scheduler sh /scheduler/run-workflow.sh \
  "WORKFLOW_ID" \
  "$DISCORD_WEBHOOK_URL" \
  "Test Bot" \
  3447003
```

## Architecture Deep Dive

### File Structure

```
openfang/
├── docker-compose.yaml          # Defines both containers
├── Dockerfile                   # OpenFang core image
├── docker-entrypoint.sh         # Core container startup
├── config.toml.template         # Config template (envsubst)
├── workflows/                   # Workflow definitions
│   ├── world-news.json         # Simple RSS fetch
│   ├── tech-digest.json        # Multi-source digest
│   └── ... (15 workflows)
└── scheduler/                   # Scheduler container files
    ├── Dockerfile              # Scheduler image
    ├── entrypoint.sh           # Scheduler startup (REGISTERS workflows)
    ├── run-workflow.sh         # Cron job execution script
    └── diagnose.sh             # Diagnostic tool
```

### Workflow Registration Flow

```
scheduler starts
    ↓
entrypoint.sh runs
    ↓
Wait for openfang:4200/api/health
    ↓
For each /workflows/*.json:
    POST /api/workflows
    Get back workflow ID
    ↓
Create cron job with ID
    ↓
exec crond -f
```

### Cron Job Flow

```
Cron triggers at scheduled time
    ↓
run-workflow.sh WORKFLOW_ID WEBHOOK_URL BOT_NAME COLOR
    ↓
POST /api/workflows/{ID}/run
    ↓
OpenFang executes workflow
    ↓
Return output text
    ↓
POST to Discord webhook
```

## Environment Variables

Create `.env` in the parent directory:

```env
# Required for scheduler
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR/TOKEN

# Optional
TIMEZONE=Europe/Oslo
OPENFANG_API_URL=http://openfang:4200

# For OpenFang core
OLLAMA_MODEL=qwen3.5:27b
```

## Manual Operations

### Register Workflows Manually

If auto-registration fails:

```bash
# Get into scheduler container
docker exec -it openfang-scheduler sh

# Register one workflow
curl -X POST http://openfang:4200/api/workflows \
  -H "Content-Type: application/json" \
  -d @/workflows/world-news.json

# Or from host
curl -X POST http://localhost:4200/api/workflows \
  -H "Content-Type: application/json" \
  -d @workflows/world-news.json
```

### Run Workflow Manually

```bash
# Get workflow ID
curl http://localhost:4200/api/workflows | jq '.[] | {name, id}'

# Run with input
curl -X POST http://localhost:4200/api/workflows/{ID}/run \
  -d '{"input": "test data"}'
```

### View All Registered Workflows

```bash
# Via API
curl http://localhost:4200/api/workflows | jq '.[].name'

# Via UI
open http://localhost:4200/workflows
```

## Debugging

### Check Scheduler Initialization

```bash
# View full startup log
docker logs openfang-scheduler

# Look for:
# - "OpenFang is ready"
# - "Registered:" lines
# - "Creating Cron Schedule"
# - "Created X cron jobs"
```

### Check Cron Jobs

```bash
# Inside container
docker exec openfang-scheduler crontab -l

# Or from diagnose script
docker exec openfang-scheduler sh /scheduler/diagnose.sh
```

### Test Discord Webhook

```bash
# From inside scheduler container
curl -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"content": "Test message from scheduler"}'
```

### Reset Everything

```bash
# Stop and remove everything
docker compose down

# Clear volumes (WARNING: loses all data)
docker volume rm openfang_data

# Rebuild from scratch
docker compose up -d --build

# Watch initialization
docker logs -f openfang-scheduler
```

## Workflow JSON Structure

```json
{
  "name": "unique-workflow-name",
  "description": "What this does",
  "steps": [
    {
      "name": "step-name",
      "agent_name": "assistant|researcher|analyst|writer",
      "prompt": "Instructions with {{variables}}",
      "mode": "sequential",
      "timeout_secs": 120,
      "error_mode": "retry|continue",
      "output_var": "result_var"
    }
  ]
}
```

## Available Agents

- **assistant**: General purpose (most workflows)
- **researcher**: Information gathering
- **analyst**: Data synthesis
- **writer**: Content formatting

## Schedule Reference

| Time | Workflow | Runs If |
|------|----------|---------|
| 06:00 | world-news | DISCORD_WEBHOOK_URL set |
| 06:30 | global-news | Workflow registered |
| 07:00 | americas-news | Workflow registered |
| 07:30 | europe-news | Workflow registered |
| 08:00 | asia-pacific-news | Workflow registered |
| 08:30 | market-brief | Workflow registered |
| 09:00 | tech-digest | Workflow registered |
| 09:30 | coding-tech-ai | Workflow registered |
| 10:00 | hacker-news-digest | Workflow registered |
| 11:00 | github-trending | Workflow registered |
| 12:00 | geopolitical-perspectives | Workflow registered |
| 16:00 | investing-intelligence | Workflow registered (weekdays) |

**Note:** All scheduled workflows require:
1. DISCORD_WEBHOOK_URL environment variable
2. Successful workflow registration (got an ID from API)
3. Both containers running and healthy
