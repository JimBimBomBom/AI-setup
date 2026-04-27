# AI Setup

Local LLM stack: **Ollama** (systemd) + **Open WebUI** (Docker) + **n8n Workflow Automation** with GPU switching.

## Overview

This setup provides:
- **Ollama**: Local LLM server running as systemd service with GPU switching
- **Open WebUI**: Web chat interface (Docker, port 8081)
- **n8n**: Visual workflow automation for scheduled tasks like news digests (Docker, port 5678)

## Hardware

- **GPU 0**: RTX 5060 (16GB)
- **GPU 1**: RTX 5060 Ti (8GB)
- **Total**: 24GB VRAM

## Quick Start

### 1. Start Ollama with GPU switching

```bash
# Small mode (8GB - 5060 Ti only)
sudo ./ai-mode.sh small

# Or big mode (24GB - both GPUs)
sudo ./ai-mode.sh big

# Check status
sudo ./ai-mode.sh status
```

### 2. Start Open WebUI

```bash
docker compose -f webui-compose.yaml up -d
```

Access at http://localhost:8081

### 3. Start n8n (for news digest automation)

```bash
# Copy and configure environment variables
cp .env.example .env
# Edit .env with your Discord webhook, timezone, etc.

# Start n8n
docker compose -f n8n-compose.yaml up -d
```

Access at http://localhost:5678

## Project Structure

```
.
├── ai-mode.sh                  # GPU switching script (requires sudo)
├── webui-compose.yaml          # Open WebUI Docker (port 8081)
├── n8n-compose.yaml            # n8n Workflow Automation (port 5678)
├── .env.example                # Environment template (copy to .env)
├── jobs/                       # Job configurations for n8n workflows
│   ├── test.json               # Test job (single source, manual trigger)
│   ├── world-news.json         # World news digest config
│   └── tech-digest.json        # Tech news digest config
├── n8n/
│   └── workflows/
│       └── news-digest.json    # Generic workflow (import into n8n)
└── README.md                   # This file
```

## GPU Mode Switching

The `ai-mode.sh` script manages Ollama's GPU configuration:

### Small Mode (8GB VRAM)
```bash
sudo ./ai-mode.sh small
```
- Uses GPU 1 only (RTX 5060 Ti)
- Recommended models: `qwen3.5:9b`, `gemma4:9b`
- Best for: Fast inference, basic tasks

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

## n8n Workflow Automation

n8n provides visual workflow automation with:
- **Cron triggers** for scheduled tasks
- **RSS feed** reading and web scraping
- **Ollama integration** for local AI processing
- **Discord/Email** notifications

### News Digest Workflow

The included workflow (`n8n/workflows/news-digest.json`) creates automated news digests with **dual trigger support**:

- **Schedule Trigger** → Runs automatically on cron schedule (disabled by default for testing)
- **Manual Trigger** → Click "Execute Workflow" for instant testing

**Workflow steps:**
1. **Load Config** → Reads job configuration from `jobs/*.json` (change `JOB_NAME` to switch jobs)
2. **Fetch RSS** → Scrapes multiple news sources listed in config
3. **Filter & Aggregate** → Filters by time window, groups by category
4. **Ollama Summarize** → Local LLM creates summary
5. **Send Discord** → Posts formatted digest to Discord (gracefully skips if no webhook)

### Job Configuration

Jobs are configured via JSON files in the `jobs/` directory:

```json
{
  "name": "World News Digest",
  "schedule": "0 7 * * *",
  "lookback_hours": 24,
  "max_articles": 60,
  "model": "qwen3.5:14b",
  "system_prompt": "You are a professional news editor...",
  "user_prompt_format": "Create a daily news summary...",
  "discord": {
    "webhook_url": "https://discord.com/api/webhooks/...",
    "username": "News Bot",
    "embed_color": 3447003
  },
  "sources": [
    {"name": "BBC", "url": "https://feeds.bbci.co.uk/news/rss.xml", "category": "world"},
    {"name": "Reuters", "url": "https://feeds.reuters.com/reuters/topNews", "category": "world"}
  ]
}
```

### Setting Up News Digest

1. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

2. **Configure job**:
   ```bash
   # Edit jobs/world-news.json
   # Add your Discord webhook URL
   # Customize sources, model, prompts
   ```

3. **Start n8n**:
   ```bash
   docker compose -f n8n-compose.yaml up -d
   ```

4. **Import workflow**:
   - Open http://localhost:5678
   - Workflows → Import from File → `n8n/workflows/news-digest.json`
   - Open the "Load Config" node and set `JOB_NAME = 'world-news'`
   - Configure Ollama credentials (Settings → Credentials → Ollama API)

5. **Test**:
   - Click "Execute Workflow" to test
   - Check Discord for the digest

6. **Activate**:
   - Toggle workflow to "Active"
   - It will run automatically on schedule

### Adding More Jobs

Create multiple news digests by copying job configs:

1. Copy `jobs/world-news.json` to `jobs/my-digest.json`
2. Edit sources, prompts, schedule, Discord webhook
3. In n8n, duplicate the workflow
4. Change `JOB_NAME` in the Load Config node to `'my-digest'`
5. Activate

### Testing Your Setup

Use the built-in test job to quickly test your setup without waiting for schedules:

1. **Configure test webhook** (optional):
   ```bash
   # Edit .env and set TEST_DISCORD_WEBHOOK_URL
   # Or leave empty to skip Discord sending
   TEST_DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR_TEST_WEBHOOK
   # Restart n8n to load new env vars
   docker compose -f n8n-compose.yaml restart
   ```

2. **Run a test**:
   - Open http://localhost:5678
   - Open the "Load Config" node
   - Change `JOB_NAME = 'test'` (loads `jobs/test.json`)
   - Click "Execute Workflow" (Manual Trigger is used automatically)
   - Check the execution logs for results

3. **Test job features**:
   - Uses only 1 news source (BBC) for quick testing
   - Lighter model (`qwen3.5:9b`) for faster processing
   - Falls back to `TEST_DISCORD_WEBHOOK_URL` env var if webhook not in config
   - Gracefully skips Discord if no webhook configured
   - Articles from last 48 hours (more likely to find content)

4. **Restore for production**:
   - After testing, change `JOB_NAME` back to `'world-news'` or `'tech-digest'`
   - Enable the "Schedule Trigger" node (toggle on)
   - Activate the workflow

## Environment Configuration

Copy `.env.example` to `.env` and configure:

| Variable | Purpose | Example |
|----------|---------|---------|
| `N8N_USER` | n8n admin username | `admin` |
| `N8N_PASSWORD` | n8n admin password | `changeme` |
| `N8N_ENCRYPTION_KEY` | Credential encryption | `openssl rand -hex 16` |
| `TIMEZONE` | Cron scheduling timezone | `Europe/Oslo` |
| `OLLAMA_HOST` | Ollama connection | `host.docker.internal` |
| `DISCORD_WEBHOOK_URL` | Default Discord webhook | `https://discord.com/api/webhooks/...` |
| `SMTP_*` | Email configuration (optional) | See `.env.example` |

## Common Commands

### Ollama
```bash
# Check status
systemctl status ollama
curl http://localhost:11434/api/tags

# Download models
ollama pull qwen3.5:14b
ollama pull qwen3.5:27b

# List running models
curl http://localhost:11434/api/ps
```

### Open WebUI
```bash
# Start
docker compose -f webui-compose.yaml up -d

# Stop
docker compose -f webui-compose.yaml down

# Logs
docker logs -f open-webui
```

### n8n
```bash
# Start
docker compose -f n8n-compose.yaml up -d

# Stop
docker compose -f n8n-compose.yaml down

# Logs
docker logs -f n8n

# View jobs directory
docker compose -f n8n-compose.yaml exec n8n ls /data/jobs/
```

### GPU Mode
```bash
# Switch modes
sudo ./ai-mode.sh small
sudo ./ai-mode.sh big
sudo ./ai-mode.sh toggle

# Monitor GPU
watch -n 1 nvidia-smi
```

## Troubleshooting

### Ollama Connection Failed
```
Error: connect ECONNREFUSED host.docker.internal:11434
```

**Solution**:
1. Ensure Ollama is running: `systemctl status ollama`
2. Check Ollama is accessible: `curl http://localhost:11434/api/tags`
3. Verify Ollama listens on all interfaces in ai-mode.sh: `OLLAMA_HOST=0.0.0.0`

### Workflow Can't Read Job Config
```
Could not read job config at /data/jobs/world-news.json
```

**Solution**:
1. Check file exists: `docker compose -f n8n-compose.yaml exec n8n ls /data/jobs/`
2. Verify JOB_NAME in Load Config node matches filename (without .json)
3. Ensure jobs directory is mounted in compose file

### RSS Feed Returns Nothing
Some feeds rate-limit or block. Test with:
```bash
curl -I https://feeds.bbci.co.uk/news/rss.xml
```

### Discord 400 Bad Request
- Verify webhook URL is correct and not revoked
- Check embed description is under 4096 chars (workflow handles chunking)

### Model Not Found
```bash
# List available models
ollama list

# Download missing model
ollama pull qwen3.5:14b
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                        Host                              │
│  ┌──────────────┐  ┌──────────────────────────────────┐ │
│  │   Ollama     │  │         Docker Containers          │ │
│  │  (systemd)   │  │  ┌──────────────┐ ┌──────────────┐  │ │
│  │  localhost   │──│  │ Open WebUI   │ │     n8n      │  │ │
│  │  :11434      │  │  │   :8081      │ │   :5678      │  │ │
│  └──────────────┘  │  │              │ │              │  │ │
│         │          │  │  Connects    │ │  Reads jobs/ │  │ │
│         │          │  │  via host    │ │  Summarizes  │  │ │
│    GPU 0,1         │  │  network     │ │  Sends to    │  │ │
│  (RTX 5060/5060Ti)│  └──────────────┘ │  Discord     │  │ │
│                    │                  └──────────────┘  │ │
└─────────────────────────────────────────────────────────┘
```

## Security Notes

- **Ollama**: Bound to `0.0.0.0:11434` for container access, firewall recommended
- **Open WebUI**: Exposed on port 8081, authentication enabled by default
- **n8n**: Change default password in `.env`
- **Credentials**: Use encryption key, don't commit `.env` to git
- **Webhooks**: Use Discord app-specific webhooks, don't share URLs

## License

Configuration files in this repository are provided as-is for personal use.
Model licenses (Qwen, Gemma, etc.) apply to their respective downloads.
