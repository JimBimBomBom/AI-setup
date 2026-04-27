# AI Setup

Local LLM stack: **Ollama** (systemd) + **Open WebUI** (Docker) + **n8n Workflow Automation** with GPU switching.

## Overview

This setup provides:
- **Ollama**: Local LLM server running as systemd service with GPU switching
- **Open WebUI**: Web chat interface (Docker, port 8081)
- **n8n**: Visual workflow automation with auto-imported workflows (Docker, port 5678)

## Hardware

- **GPU 0**: RTX 5060 (16GB)
- **GPU 1**: RTX 5060 Ti (8GB)
- **Total**: 24GB VRAM

## Quick Start

### 1. Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env with your settings (REQUIRED):
# - N8N_USER / N8N_PASSWORD (login credentials)
# - N8N_ENCRYPTION_KEY (generate: openssl rand -hex 16)
# - DISCORD_WEBHOOK_URL (for production digests)
# - TEST_DISCORD_WEBHOOK_URL (for test/cron-test)
# - TIMEZONE (your timezone for cron jobs)

# Generate encryption key
openssl rand -hex 16
# Copy output to N8N_ENCRYPTION_KEY in .env
```

### 2. Start Ollama with GPU switching

```bash
# Small mode (8GB - 5060 Ti only) - faster, good for testing
sudo ./ai-mode.sh small

# Or big mode (24GB - both GPUs) - for larger models
sudo ./ai-mode.sh big

# Check status
sudo ./ai-mode.sh status
```

### 3. Start Services

```bash
# Start Open WebUI
docker compose -f webui-compose.yaml up -d

# Start n8n (workflows auto-import on startup)
docker compose -f n8n-compose.yaml up -d
```

### 4. Access Services

- **Open WebUI**: http://localhost:8081
- **n8n**: http://localhost:5678
  - Login with credentials from `.env`
  - All workflows are pre-imported and ready

### 5. Check Workflow Import

View startup logs to see workflow import status:
```bash
docker logs n8n | head -100
```

You should see:
```
→ Importing: test
✓ Successfully imported: test
→ Importing: cron-test
✓ Successfully imported: cron-test
→ Importing: world-news
✓ Successfully imported: world-news
→ Importing: tech-digest
✓ Successfully imported: tech-digest
```

## Project Structure

```
.
├── ai-mode.sh                  # GPU switching script (requires sudo)
├── webui-compose.yaml          # Open WebUI Docker (port 8081)
├── n8n-compose.yaml            # n8n Docker (port 5678)
├── .env.example                # Environment template (copy to .env)
├── .env                        # Your configuration (gitignored)
├── jobs/                       # Job configurations (URLs, models, prompts)
│   ├── test.json               # Single-source manual test
│   ├── cron-test.json          # 15-min cron system test
│   ├── world-news.json         # Daily world news digest
│   └── tech-digest.json        # Daily tech news digest
├── n8n/
│   ├── start.sh                # Startup script (auto-imports workflows)
│   └── workflows/              # Workflow definitions (auto-imported)
│       ├── test.json           # Manual trigger workflow
│       ├── cron-test.json      # 15-min cron workflow
│       ├── world-news.json     # Daily 7am cron workflow
│       └── tech-digest.json    # Daily 8am cron workflow
└── README.md                   # This file
```

## How It Works

### Auto-Import on Startup

n8n automatically imports all workflows on startup:

1. Container starts with custom `start.sh` script
2. Waits for n8n to initialize
3. Imports all `.json` files from `/workflows` directory
4. Workflows are ready to use immediately

**To update workflows**: Restart n8n container
```bash
docker compose -f n8n-compose.yaml restart
```

### Job Configuration System

Workflows are generic - they load job configs from `jobs/*.json`:

- **Workflow** = execution logic (nodes, triggers, processing)
- **Job Config** = data (URLs, model, prompts, Discord webhook)

Each workflow has `JOB_NAME` hardcoded to match a job config file.

## Pre-Configured Workflows

| Workflow | Trigger | Job Config | Schedule | Purpose |
|----------|---------|------------|----------|---------|
| **test** | Manual | `test.json` | Click "Execute" | Quick manual test |
| **cron-test** | Cron | `cron-test.json` | Every 15 min | Verify cron works |
| **world-news** | Cron | `world-news.json` | Daily 7:00 AM | World news digest |
| **tech-digest** | Cron | `tech-digest.json` | Daily 8:00 AM | Tech news digest |

## Testing Your Setup

### 1. Check Workflow Import

View startup logs to confirm workflows were imported:
```bash
docker logs n8n | grep -A 5 "Importing Workflows"
```

You should see:
```
→ Importing: test
  ✓ Imported successfully
→ Importing: cron-test
  ✓ Imported successfully
→ Importing: world-news
  ✓ Imported successfully
→ Importing: tech-digest
  ✓ Imported successfully
```

### 2. Trigger Test Job Manually

The **test** workflow is configured for manual execution (no schedule).

**Steps to run it:**

1. **Open n8n**: http://localhost:5678
2. **Login** with credentials from `.env` file
3. **Click on "test"** workflow (left sidebar or main view)
4. **Click "Execute Workflow"** button (bottom of screen)
5. **Wait** for execution to complete (watch node status)
6. **Check results**:
   - Execution log shows each node's output
   - Check Discord for test message (if webhook configured)
   - Green nodes = success, red = error

**What the test job does:**
- Loads `jobs/test.json` config (single BBC news source)
- Fetches latest articles
- Summarizes with lightweight model (`qwen3.5:9b`)
- Sends to Discord (or logs "skipped" if no webhook)

### 3. Verify Cron is Working

The **cron-test** workflow runs automatically every 15 minutes:

```bash
# Watch for cron executions
docker logs n8n | grep "cron-test\|Schedule Trigger"
```

Wait 15 minutes and check:
- n8n execution history (left sidebar → Executions)
- Discord test channel for system status message

### 4. Check Workflow Status in n8n

In the n8n interface:
- **Active workflows** have a green dot and "Active" toggle on
- **Inactive workflows** (test) show as gray
- **Executions** tab shows run history

### Quick Test Helper Script

Run the included test script for quick diagnostics:

```bash
./test-n8n.sh
```

This will:
- Check if n8n is running
- Show which workflows were imported
- Display instructions for manual testing
- Show recent cron-test execution status

## GPU Mode Switching

The `ai-mode.sh` script manages Ollama's GPU configuration:

### Small Mode (8GB VRAM)
```bash
sudo ./ai-mode.sh small
```
- Uses GPU 1 only (RTX 5060 Ti)
- Recommended models: `qwen3.5:9b`, `gemma4:9b`
- Best for: Fast inference, testing, basic tasks

### Big Mode (24GB VRAM)
```bash
sudo ./ai-mode.sh big
```
- Uses both GPUs (5060 + 5060 Ti)
- Recommended models: `qwen3.5:27b`, `gemma4:26b-a4b`, `gemma4:31b`
- Best for: Complex reasoning, coding, larger context

### Mode Commands
```bash
sudo ./ai-mode.sh small      # Switch to single GPU
sudo ./ai-mode.sh big        # Switch to dual GPU
sudo ./ai-mode.sh toggle     # Toggle between modes
sudo ./ai-mode.sh status     # Show current status
```

## Model Recommendations

### Small Mode (8GB - RTX 5060 Ti)
| Model | VRAM | Speed | Best For |
|-------|------|-------|----------|
| **qwen3.5:9b** | ~7.5GB | 161 tok/s | General, coding, fast |
| gemma4:9b | ~8GB | ~70 tok/s | Balanced, multilingual |

### Big Mode (24GB - Both GPUs)
| Model | VRAM | Speed | Best For |
|-------|------|-------|----------|
| **qwen3.5:27b** | ~17GB | 110 tok/s | Coding, agents, reasoning 🏆 |
| **gemma4:26b-a4b** | ~15GB | 145 tok/s | Fastest, efficient ⚡ |
| **gemma4:31b** | ~18GB | 48 tok/s | Math, competitive programming 🧮 |
| **qwq:32b** | ~19GB | 30 tok/s | Deep reasoning 💡 |

## Customizing Jobs

### Edit Job Configurations

Job configs are in `jobs/*.json`. Each contains:

```json
{
  "name": "Job Display Name",
  "schedule": "cron expression",
  "model": "ollama-model:tag",
  "sources": [
    {"name": "Source Name", "url": "RSS URL", "category": "category"}
  ],
  "discord": {
    "webhook_url": "Discord webhook URL",
    "username": "Bot Name",
    "embed_color": 3447003
  }
}
```

**To change sources**: Edit the `sources` array in any job file
**To change model**: Update the `model` field
**To change schedule**: Update the `schedule` field (cron expression)

### Add New Jobs

1. Create `jobs/my-job.json` with your configuration
2. Create `n8n/workflows/my-job.json` by copying an existing workflow
3. Change `JOB_NAME = 'my-job'` in the Load Config node
4. Set appropriate trigger (Manual or Cron)
5. Restart n8n: `docker compose -f n8n-compose.yaml restart`

## Discord Webhook Setup

### Production Webhook (world-news, tech-digest)

1. In Discord: Server Settings → Integrations → Webhooks → New Webhook
2. Copy webhook URL
3. Add to `.env`: `DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...`

### Test Webhook (test, cron-test)

1. Create a test channel in Discord
2. Create webhook for that channel
3. Add to `.env`: `TEST_DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...`

**Can use same webhook for both**, but separate channels keep test messages organized.

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `N8N_USER` | ✓ | n8n login username |
| `N8N_PASSWORD` | ✓ | n8n login password |
| `N8N_ENCRYPTION_KEY` | ✓ | Credential encryption (16 hex chars) |
| `N8N_SECURE_COOKIE` | ✓ | Set to `false` for local/LAN access |
| `TIMEZONE` | ✓ | Cron scheduling timezone |
| `DISCORD_WEBHOOK_URL` | ✓ | Production Discord webhook |
| `TEST_DISCORD_WEBHOOK_URL` | ✓ | Test Discord webhook |
| `OLLAMA_HOST` | Auto | Ollama connection (host.docker.internal) |
| `SMTP_*` | ✗ | Email configuration (optional) |

## Common Commands

### Start/Stop Everything

```bash
# Start all services
sudo ./ai-mode.sh small
docker compose -f webui-compose.yaml up -d
docker compose -f n8n-compose.yaml up -d

# Stop everything
docker compose -f webui-compose.yaml down
docker compose -f n8n-compose.yaml down
sudo systemctl stop ollama
```

### Check Status

```bash
# Ollama status
systemctl status ollama
curl http://localhost:11434/api/tags

# Docker containers
docker ps

# n8n logs
docker logs n8n

# GPU status
watch -n 1 nvidia-smi
```

### Restart Services

```bash
# Restart n8n (re-imports workflows)
docker compose -f n8n-compose.yaml restart

# Restart Open WebUI
docker compose -f webui-compose.yaml restart

# Restart Ollama with different mode
sudo ./ai-mode.sh big
```

## Troubleshooting

### Workflows Not Auto-Importing

```bash
# Check startup logs
docker logs n8n | grep -A 20 "n8n Startup Script"

# Verify workflow files exist
docker compose -f n8n-compose.yaml exec n8n ls /workflows/

# Check for import errors
docker logs n8n | grep -i "error\|failed"
```

### Ollama Connection Failed

```bash
# Check if Ollama is running
systemctl status ollama
curl http://localhost:11434/api/tags

# Verify Ollama is accessible from container
docker compose -f n8n-compose.yaml exec n8n \
  curl http://host.docker.internal:11434/api/tags
```

### Cron Jobs Not Running

```bash
# Check cron-test is firing every 15 min
docker logs n8n | grep "cron-test\|Cron"

# Check n8n timezone setting
docker compose -f n8n-compose.yaml exec n8n env | grep TZ
```

### Discord Messages Not Sending

```bash
# Check webhook URL is set
docker compose -f n8n-compose.yaml exec n8n env | grep DISCORD

# Test webhook manually
curl -X POST -H "Content-Type: application/json" \
  -d '{"content":"Test message"}' \
  YOUR_WEBHOOK_URL
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                          Host                                │
│  ┌──────────────┐  ┌────────────────────────────────────┐  │
│  │   Ollama     │  │           Docker Containers          │  │
│  │  (systemd)   │  │  ┌────────────┐    ┌────────────┐   │  │
│  │  localhost   │──│  │ Open WebUI │    │    n8n     │   │  │
│  │  :11434      │  │  │   :8081    │    │   :5678    │   │  │
│  └──────────────┘  │  │            │    │            │   │  │
│         │          │  │  Connects  │    │  Auto-import│   │  │
│         │          │  │  via host  │    │  workflows  │   │  │
│    GPU 0,1         │  │  network   │    │  + Cron jobs│   │  │
│  (RTX 5060/5060Ti) │  └────────────┘    └────────────┘   │  │
│                    │                                      │  │
│                    │  Mounts:                             │  │
│                    │  - ./jobs:/data/jobs (configs)      │  │
│                    │  - ./n8n/workflows:/workflows       │  │
└─────────────────────────────────────────────────────────────┘
```

## Security Notes

- **Ollama**: Bound to `0.0.0.0:11434` for container access, firewall recommended
- **Open WebUI**: Exposed on port 8081, authentication enabled
- **n8n**: 
  - `N8N_SECURE_COOKIE=false` required for local/LAN (no HTTPS)
  - Change default password in `.env`
  - Encryption key protects stored credentials
- **Discord**: Webhooks in `.env` (gitignored), use separate test/production channels

## Updating Workflows

Since workflows are auto-imported on startup:

1. Edit workflow file in `n8n/workflows/`
2. Restart n8n: `docker compose -f n8n-compose.yaml restart`
3. View startup logs to confirm import

**No manual GUI interaction needed!**

## Complete Setup Checklist

Before starting:
- [ ] Copy `.env.example` to `.env`
- [ ] Set `N8N_USER` and `N8N_PASSWORD`
- [ ] Generate and set `N8N_ENCRYPTION_KEY`
- [ ] Set `TIMEZONE`
- [ ] Set `DISCORD_WEBHOOK_URL`
- [ ] Set `TEST_DISCORD_WEBHOOK_URL`
- [ ] (Optional) Edit job configs in `jobs/` to customize sources

Start services:
- [ ] `sudo ./ai-mode.sh small` (or `big`)
- [ ] `docker compose -f webui-compose.yaml up -d`
- [ ] `docker compose -f n8n-compose.yaml up -d`
- [ ] Check `docker logs n8n` for successful imports
- [ ] Access http://localhost:5678 and login
- [ ] Verify workflows appear in n8n UI

Test:
- [ ] Manually trigger "test" workflow in n8n
- [ ] Check Discord for test message
- [ ] Wait 15 minutes for first "cron-test" run
- [ ] Check Discord for system test message

---

**Questions?** Check logs: `docker logs n8n`
