# AI Stack

Local AI automation: **Ollama** + **Open WebUI** + three workflow services that fetch news, summarize with a local LLM, and post to Discord.

## Services

| Service | Port | Description | Command |
|---------|------|-------------|---------|
| Open WebUI | 8081 | Chat interface for Ollama | `docker compose -f webui-compose.yaml up -d` |
| n8n | 5678 | Visual workflow automation | `docker compose -f n8n-compose.yaml up -d` |
| OpenClaw | 18789 | TypeScript AI agent gateway | `./openclaw/setup.sh` (first time), then `docker compose -f openclaw/docker-compose.yaml up -d` |
| OpenFang | 4200 | Rust Agent OS | `docker compose -f openfang/docker-compose.yaml up -d` |

All `docker compose` commands run from the **repo root**.

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env — fill in Discord webhook, bot token, n8n credentials

# 2. Start Ollama with GPU
sudo ./ai-mode.sh big     # both GPUs (24 GB)
# or: sudo ./ai-mode.sh small  # one GPU (8 GB)

# 3. Start whichever services you want — they're independent
docker compose -f webui-compose.yaml up -d
docker compose -f n8n-compose.yaml up -d
docker compose -f openfang/docker-compose.yaml up -d

# OpenClaw needs a one-time build step:
./openclaw/setup.sh
```

## Workflows

All three automation services run the same two schedules:

| Workflow | Schedule | Sources |
|----------|----------|---------|
| World News Digest | 07:00 daily | BBC, CNN, Reuters, The Guardian, Al Jazeera |
| Tech Digest | 08:00 daily | TechCrunch, Hacker News, The Verge, Ars Technica |

How each service handles it:

| | n8n | OpenClaw | OpenFang |
|---|---|---|---|
| Scheduling | Cron trigger nodes | `openclaw cron add` CLI | Alpine cron sidecar |
| Discord output | Webhook URL | Bot (posts to channel by ID) | Webhook URL |
| Config | `jobs/*.json` | `openclaw/config.jsonc` + CLI | `openfang/config.toml` + `workflows/*.json` |

## Discord Setup

### Webhook URL (n8n + OpenFang)

Server Settings → Integrations → Webhooks → New Webhook → copy URL → `DISCORD_WEBHOOK_URL` in `.env`.

### Bot Token (OpenClaw + OpenFang)

1. [discord.com/developers](https://discord.com/developers/applications) → New Application → **Bot** → **Add Bot** → **Copy Token**
2. Enable **Message Content Intent** and **Server Members Intent**
3. OAuth2 URL Generator → scopes: `bot`, `applications.commands` → permissions: Send Messages, Read Message History, View Channels → copy invite URL → invite bot to your server
4. Enable Developer Mode (User Settings → Advanced) → right-click the target channel → **Copy Channel ID** → `DISCORD_CHANNEL_ID` in `.env`

Both OpenClaw and OpenFang use the same `DISCORD_BOT_TOKEN`. You only need one bot.

## Environment Variables

| Variable | Used by | Description |
|----------|---------|-------------|
| `TIMEZONE` | all | Cron timezone, e.g. `Europe/Oslo` |
| `DISCORD_WEBHOOK_URL` | n8n, OpenFang | Webhook for news posts |
| `TEST_DISCORD_WEBHOOK_URL` | n8n | Webhook for test/cron-test jobs |
| `DISCORD_BOT_TOKEN` | OpenClaw, OpenFang | Discord bot token |
| `DISCORD_CHANNEL_ID` | OpenClaw | Channel ID where news is posted |
| `N8N_USER` | n8n | Login username |
| `N8N_PASSWORD` | n8n | Login password |
| `N8N_ENCRYPTION_KEY` | n8n | Credential key (`openssl rand -hex 16`) |
| `N8N_SECURE_COOKIE` | n8n | `false` for local/LAN |

## GPU Switching

```bash
sudo ./ai-mode.sh big      # both GPUs (24 GB) — for qwen3:27b and larger
sudo ./ai-mode.sh small    # RTX 5060 Ti only (8 GB) — faster, smaller models
sudo ./ai-mode.sh status   # show current mode
sudo ./ai-mode.sh toggle   # switch between modes
```

## Logs & Debugging

```bash
# n8n
docker logs n8n
docker compose -f n8n-compose.yaml logs -f

# OpenClaw
docker logs openclaw-gateway
docker exec openclaw-gateway node dist/index.js cron list

# OpenFang
docker logs openfang
docker logs openfang-scheduler

# Trigger a workflow manually (OpenFang)
curl -X POST http://localhost:4200/api/workflows/<id>/run \
  -H "Content-Type: application/json" -d '{"input": "2026-05-07"}'

# Trigger a cron job manually (OpenClaw)
docker exec openclaw-gateway node dist/index.js cron run <job-id>
```

## Project Structure

```
.
├── .env.example                   # Environment template
├── ai-mode.sh                     # GPU switching (requires sudo)
├── webui-compose.yaml             # Open WebUI (port 8081)
├── n8n-compose.yaml               # n8n (port 5678)
├── jobs/                          # n8n job configs (RSS sources, prompts)
│   ├── world-news.json
│   └── tech-digest.json
├── n8n/
│   ├── start.sh                   # Auto-imports workflows on container start
│   └── workflows/                 # n8n workflow JSON files
├── openclaw/                      # OpenClaw (port 18789)
│   ├── setup.sh                   # First-time: clone + build + init
│   ├── init-cron.sh               # Register cron jobs (re-run after restarts)
│   ├── docker-compose.yaml
│   ├── config.jsonc               # Ollama provider + Discord bot config
│   ├── src/                       # Cloned by setup.sh (gitignored)
│   └── skills/news-digest/
│       └── SKILL.md               # Teaches the agent to fetch/summarize RSS
└── openfang/                      # OpenFang (port 4200)
    ├── docker-compose.yaml        # OpenFang + scheduler sidecar
    ├── config.toml                # Ollama provider + Discord bot config
    ├── workflows/                 # Workflow definitions (registered on start)
    │   ├── world-news.json
    │   └── tech-digest.json
    └── scheduler/                 # Alpine cron sidecar
        ├── Dockerfile
        ├── entrypoint.sh          # Registers workflows + starts crond
        └── run-workflow.sh        # Runs workflow → posts to Discord webhook
```
