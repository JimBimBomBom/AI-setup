# OpenFang Complete Guide

## Overview

OpenFang consists of **two containers**:

1. **openfang** (port 4200): Core API and workflow engine
2. **openfang-scheduler**: Cron-based workflow trigger system

## Quick Start

```bash
# Start everything (validates .env, builds, starts)
./openfang/setup.sh start

# Or directly:
cd openfang && docker compose up -d

# View scheduler initialization logs
docker logs -f openfang-scheduler

# Check if everything is working
docker exec openfang-scheduler sh /scheduler/diagnose.sh
```

## Management Commands

The setup script provides convenient commands:

```bash
./openfang/setup.sh start        # Validate, build, start
./openfang/setup.sh stop         # Stop all containers
./openfang/setup.sh restart      # Restart without rebuild
./openfang/setup.sh rebuild      # Stop, rebuild, start
./openfang/setup.sh status       # Full status report
./openfang/setup.sh logs         # Follow all logs
./openfang/setup.sh diagnose     # Run diagnostics
./openfang/setup.sh cron         # List cron jobs
./openfang/setup.sh workflows    # List workflows
./openfang/setup.sh trigger <n>  # Manually trigger a job
```

## Monitoring

```bash
# One-shot status report
./openfang/monitor.sh

# Live monitoring (refreshes every 30s)
./openfang/monitor.sh --watch 30

# JSON output (for scripting)
./openfang/monitor.sh --json

# Scheduler metrics (Prometheus format)
curl http://localhost:8080/metrics

# Health checks
curl http://localhost:4200/api/health        # OpenFang API
curl http://localhost:8080/healthz           # Scheduler relay
```

## Testing & Troubleshooting

### Problem 1: Discord Messages Not Working

**Test Discord webhook manually:**
```bash
# From inside the scheduler container
docker exec openfang-scheduler sh -c 'curl -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '"'"'{"content": "Test from OpenFang scheduler"}'"'"'

# Or test with a full embed
docker exec openfang-scheduler sh -c 'curl -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '"'"'{"username": "Test Bot", "embeds": [{"description": "Test message", "color": 3447003}]}'"'"'
```

**Run a workflow manually and see full debug output:**
```bash
# Get a workflow ID
WORKFLOW_ID=$(curl -s http://localhost:4200/api/workflows | jq -r '.[] | select(.name=="hacker-news-digest") | .id')

# Execute the workflow directly via the API
curl -X POST http://localhost:4200/api/workflows/$WORKFLOW_ID/run \
  -H "Content-Type: application/json" \
  -d '{"input": "Manual test run"}' | jq .
```

**Check if webhook URL is set correctly:**
```bash
docker exec openfang-scheduler env | grep DISCORD
docker exec openfang-scheduler sh -c 'echo "Webhook: ${DISCORD_WEBHOOK_URL:0:50}..."'
```

### Problem 2: Scheduler Not Loading Schedule

**Verify cron jobs exist:**
```bash
# List jobs (look for WF-* names)
curl http://localhost:4200/api/cron/jobs | jq '.jobs[] | {name, schedule, enabled}'

# Inspect a single job
curl http://localhost:4200/api/cron/jobs | jq '.jobs[] | select(.name=="WF-world-news-0600")'

# Trigger a job manually
curl -X POST http://localhost:4200/api/workflows/<WORKFLOW_ID>/run
```

**Restart and rebuild completely:**
```bash
cd openfang

# Stop and remove
docker compose down

# Rebuild scheduler (picks up changes to scheduler.py and schedule.json)
docker compose build openfang-scheduler

# Start fresh
docker compose up -d

# Watch logs (should show "Active cron jobs" with the list)
docker logs -f openfang-scheduler
```

**Force manual cron execution to test:**
```bash
# Trigger a job via the API (replace JOB_ID)
curl -X POST http://localhost:4200/api/workflows/<WORKFLOW_ID>/run
```

### Common Fix Commands

```bash
# Quick restart
docker compose restart openfang-scheduler

# Full rebuild (needed after changing scripts)
docker compose down && docker compose up -d --build

# Check scheduler status
docker exec openfang-scheduler sh /scheduler/diagnose.sh

# Watch scheduler logs
docker logs -f openfang-scheduler

# Watch webhook relay activity
docker logs -f openfang-scheduler | grep webhook

# Check OpenFang workflows
curl http://localhost:4200/api/workflows | jq '.[].name'
```

### Problem 3: Cron Jobs Exist But No Discord Messages

This is the most common issue. The delivery pipeline has three steps — any one can fail:

```
OpenFang cron fires → POSTs to scheduler /hook → Scheduler formats → POSTs to Discord
```

**Step 1: Verify the workflow actually produces output**
```bash
# Run the workflow directly
WORKFLOW_ID=$(curl -s http://localhost:4200/api/workflows | jq -r '.[] | select(.name=="world-news-digest") | .id')
curl -X POST http://localhost:4200/api/workflows/$WORKFLOW_ID/run \
  -H "Content-Type: application/json" \
  -d '{"input": "Test"}' | jq .
```
If this returns an error or empty output, the workflow itself is broken (likely the LLM can't fetch RSS feeds).

**Step 2: Verify cron job delivery_targets are correct**
```bash
curl http://localhost:4200/api/cron/jobs | jq '.jobs[0].delivery_targets'
```
Expected output:
```json
[
  {
    "kind": "webhook",
    "url": "http://openfang-scheduler:8080/hook",
    "auth_header": "Bearer <token>"
  }
]
```
If you see `"type"` instead of `"kind"`, or `"delivery": {"kind": "none"}`, the scheduler was built with an older version. Rebuild: `docker compose build openfang-scheduler && docker compose up -d`.

**Step 3: Verify the scheduler relay is receiving webhooks**
```bash
# Check scheduler logs for webhook activity
docker logs openfang-scheduler | grep -i "webhook received"

# Or check metrics
curl http://localhost:8080/metrics | grep deliveries
```
If `deliveries_total` is 0, OpenFang is not sending to the relay. Check container networking:
```bash
docker exec openfang curl -sf http://openfang-scheduler:8080/healthz
```

**Step 4: Verify Discord webhook is reachable**
```bash
docker exec openfang-scheduler sh -c 'curl -sf -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{"content": "test"}"'
```

**Quick fix — rebuild everything fresh:**
```bash
docker compose down
docker volume rm openfang_data  # WARNING: clears all agent data
docker compose up -d --build
docker logs -f openfang-scheduler  # Watch for successful cron job creation
```

## How the Scheduler Works

### Startup Sequence

```
1. Container starts (ENTRYPOINT runs `scheduler.py`)

2. scheduler.py actions:
   a. Wait for `openfang:4200/api/health`
   b. Register each JSON workflow via `/api/workflows`
   c. Pick the agent specified by `SCHEDULER_AGENT_ID`
   d. Convert `schedule.json` entries into cron specs (`MM HH * * *`, plus timezone)
   e. Upsert cron jobs via `/api/cron/jobs` with `action.kind = workflow_run`
   f. Start an HTTP webhook relay on `0.0.0.0:${SCHEDULER_HTTP_PORT}`

3. OpenFang's cron scheduler executes the workflows at the defined times and posts
   the output to `http://openfang-scheduler:8080/hook`. The relay formats the text
   and forwards it to `DISCORD_WEBHOOK_URL`.
```

### What Gets Created

**Workflow registration**
- All `.json` definitions in `/workflows` are registered via `/api/workflows`
- Existing workflows are reused; missing ones are created automatically

**Cron jobs (inside OpenFang)**
- One job per entry in `scheduler/schedule.json`
- Jobs live in OpenFang's cron scheduler (`/api/cron/jobs`, dashboard → Scheduler)
- Each job uses `action.kind = workflow_run` and owns a delivery fan-out target that
  posts back to the scheduler container

**Webhook relay**
- The scheduler container listens on `http://openfang-scheduler:${SCHEDULER_HTTP_PORT}/hook`
- OpenFang sends `{job, output, timestamp}` JSON payloads to that endpoint
- The relay formats the message (bot name, emoji, color) and posts to Discord

Inspect cron jobs / run history:

```bash
# List jobs owned by the scheduler agent
curl http://localhost:4200/api/cron/jobs | jq '.jobs[] | {name, id, schedule, action}'

# Trigger a job immediately (replace JOB_ID)
curl -X POST http://localhost:4200/api/workflows/WORKFLOW_ID/run
```

## Common Issues & Fixes

### Issue 1: "No agents found" when syncing cron jobs

**Symptoms:**
- Scheduler log shows `No agents found. Create one...`
- `/api/cron/jobs` stays empty

**Fix:**
1. Use the OpenFang dashboard (Agents tab) or CLI to create a simple agent.
2. Copy its ID via `curl http://localhost:4200/api/agents | jq '.[].id'`.
3. Set `SCHEDULER_AGENT_ID=<that-uuid>` in `.env` and restart the stack:
   `docker compose -f openfang/docker-compose.yaml up -d --build openfang-scheduler`

### Issue 2: Webhook requests rejected with 401

**Symptoms:**
- OpenFang log shows `cron fan-out: webhook delivery failed`
- Scheduler log shows `invalid token`

**Fix:**
1. Ensure `SCHEDULER_WEBHOOK_TOKEN` is set in `.env` **and** matches the value baked into existing cron jobs.
2. After changing the token, rebuild/restart `openfang-scheduler` so it recreates the cron jobs with the new header.
3. Verify by triggering a job manually: `curl -X POST http://localhost:4200/api/workflows/<WORKFLOW_ID>/run`

### Issue 3: Cron job created but never fires

**Symptoms:**
- `/api/cron/jobs` shows the job but `last_run` stays `null`
- Discord never receives the message

**Fix:**
1. Confirm the cron expression is correct and uses the intended timezone (`TIMEZONE` in `.env`).
2. Check job metadata:
   ```bash
   curl http://localhost:4200/api/cron/jobs | jq '.jobs[] | select(.name=="WF-world-news-0600")'
   ```
   Ensure `enabled: true` and `schedule.tz` matches your expectation.
3. Trigger the workflow directly via `/api/workflows/<id>/run` to verify it succeeds.
4. Inspect scheduler logs for `Delivered chunk` messages; if missing, verify the OpenFang container can reach `http://openfang-scheduler:8080/hook` (no firewall, container names resolve).

## Architecture Deep Dive

### File Structure

```
openfang/
├── docker-compose.yaml          # Defines both containers + healthchecks
├── Dockerfile                   # OpenFang core image (multi-arch)
├── docker-entrypoint.sh         # Core container startup (envsubst)
├── config.toml.template         # Config template (envsubst)
├── setup.sh                     # Management script (start/stop/status/etc)
├── monitor.sh                   # Monitoring script (--watch/--json)
├── .gitignore                   # OpenFang-specific ignores
├── workflows/                   # Workflow definitions (JSON)
└── scheduler/
    ├── Dockerfile              # Alpine + Python + requests
    ├── schedule.json           # Job metadata (time/cron + Discord display)
    ├── scheduler.py            # Registrar + cron sync + webhook relay + metrics
    └── diagnose.sh             # Curl-based troubleshooting helper
```

### Schedule Import Flow

```
scheduler.py starts
    ↓
Wait for openfang:4200/api/health
    ↓
Register/verify workflows via POST /api/workflows
    ↓
Pick agent (SCHEDULER_AGENT_ID) and read schedule.json
    ↓
Upsert cron jobs via POST /api/cron/jobs
      (kind = workflow_run, delivery_targets = webhook → scheduler)
    ↓
Serve webhook relay on http://openfang-scheduler:${SCHEDULER_HTTP_PORT}/hook
    ↓
OpenFang cron executes workflows and POSTs results → relay → Discord
```

### Configuring Daily Schedule

- Edit `scheduler/schedule.json` to control when each workflow runs. Each entry supports:
  - `time` (HH:MM 24h) **or** a raw `cron` expression
  - `workflow` (JSON filename inside `openfang/workflows`)
  - `bot_name` and `color` (Discord username + embed color)
  - Optional `tz` (defaults to `TIMEZONE`), `input` (static workflow input),
    and `timeout_secs` (default 420 seconds)
- Example entry:

  ```json
  {
    "time": "09:00",
    "workflow": "tech-digest.json",
    "bot_name": "💻 Tech Digest Bot",
    "color": 5814783,
    "input": "Summarize the latest developer tools and AI research",
    "timeout_secs": 420
  }
  ```

- The scheduler reads this file on startup; update it and run `docker compose up -d --build openfang-scheduler` to re-sync the jobs. To use a custom path, set `SCHEDULER_CONFIG=/scheduler/custom.json` in `.env`.

## Environment Variables

Create `.env` in the parent directory:

```env
# Discord relay
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR/TOKEN

# Workflow scheduler
SCHEDULER_AGENT_ID=uuid-from-/api/agents
SCHEDULER_WEBHOOK_TOKEN=generate_with_openssl_rand_hex_16
TIMEZONE=Europe/Oslo
OPENFANG_API_URL=http://openfang:4200
SCHEDULER_HTTP_PORT=8080
SCHEDULER_CONFIG=/scheduler/schedule.json

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
# List jobs (ensure the WF-* names exist)
curl http://localhost:4200/api/cron/jobs | jq '.jobs[] | {name, schedule, enabled, last_run}'

# Trigger one immediately (replace JOB_ID)
curl -X POST http://localhost:4200/api/workflows/WORKFLOW_ID/run

# View webhook relay activity
docker logs -f openfang-scheduler | grep webhook
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
1. `DISCORD_WEBHOOK_URL` in `.env`
2. `SCHEDULER_AGENT_ID` pointing at an existing agent
3. The scheduler container running (creates cron jobs via `/api/cron/jobs`)

Use `curl http://localhost:4200/api/cron/jobs | jq '.jobs[].name'` to verify the jobs exist after `docker compose up -d --build openfang-scheduler`.

