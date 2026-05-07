# AI Stack

Local AI automation: **Ollama** + **Open WebUI** + three workflow services that fetch news, summarize with a local LLM, and post to Discord.

All services are independent — start only what you need.

## Services

| Service | Port | What it does |
|---------|------|--------------|
| Open WebUI | 8081 | Chat interface for Ollama |
| n8n | 5678 | Visual workflow automation (node-based) |
| OpenFang | 4200 | Rust Agent OS — autonomous scheduled workflows. Builds locally from binary release. |
| OpenClaw | 18789 | TypeScript AI agent gateway — Discord bot. Builds locally from source. |

## Prerequisites

- Docker + Docker Compose
- Ollama running on the host (`sudo ./ai-mode.sh status`)
- A Discord webhook URL and bot token (see [Discord Setup](#discord-setup))

---

## OpenFang

OpenFang is the primary automation service. A Rust-based Agent OS that runs autonomous workflows on a schedule, using Ollama for inference and posting results to Discord.

### First-time setup

```bash
# 1. Configure .env
cp .env.example .env
# Fill in: OLLAMA_MODEL, DISCORD_WEBHOOK_URL, DISCORD_BOT_TOKEN

# 2. Check what models are available on your Ollama instance
./list-models.sh

# 3. Start
docker compose -f openfang/docker-compose.yaml up -d
```

On first run Docker builds a local image (`openfang-local`) that downloads the OpenFang binary from GitHub releases. The entrypoint automatically generates `config.toml` from `config.toml.template` by substituting `${OLLAMA_MODEL}` and other env vars at startup — no manual config step needed.

`./openfang/setup.sh` is an optional convenience wrapper that validates your `.env` before calling `docker compose up`. Useful for catching missing variables early.

### What starts

```
openfang            → Agent OS, REST API + dashboard on :4200
openfang-scheduler  → Alpine cron container that triggers workflows
```

The scheduler registers the workflows on startup and runs them on schedule:

| Workflow | Time | Sources |
|----------|------|---------|
| World News Digest | 07:00 daily | BBC, CNN, Reuters, The Guardian, Al Jazeera |
| Tech Digest | 08:00 daily | TechCrunch, Hacker News, The Verge, Ars Technica |

Each workflow: fetches RSS feeds → filters last 24h → Ollama summarizes → posts to Discord webhook.

### Dashboard

```
http://localhost:4200
```

From the dashboard you can: inspect agents, view workflow runs, see memory/sessions, change the default model, and explore the available Ollama models (auto-discovered).

### Common commands

```bash
# Start (builds image on first run)
docker compose -f openfang/docker-compose.yaml up -d

# Or use the setup wrapper (validates .env first, then starts)
./openfang/setup.sh

# Stop
docker compose -f openfang/docker-compose.yaml down

# Logs
docker logs -f openfang
docker logs -f openfang-scheduler

# List registered workflows and their IDs
curl -s http://localhost:4200/api/workflows | jq '.[].name, .[].id'

# Trigger a workflow manually
curl -X POST http://localhost:4200/api/workflows/<id>/run \
  -H "Content-Type: application/json" \
  -d '{"input": "2026-05-07"}'

# Change model: edit OLLAMA_MODEL in .env, then regenerate config
./openfang/setup.sh
```

### Changing the model

OpenFang auto-discovers all models available on your Ollama instance — they appear in the dashboard under Settings → Providers → Ollama. To change the default:

```bash
./list-models.sh          # see what's pulled

# Edit OLLAMA_MODEL in .env, then restart
docker compose -f openfang/docker-compose.yaml restart openfang
# The entrypoint regenerates config.toml from the template on every start
```

You can also override the model per-agent from the dashboard without changing `.env`.

---

## n8n

Visual workflow builder. Workflows auto-import on container start.

```bash
docker compose -f n8n-compose.yaml up -d
# Dashboard: http://localhost:5678
```

Same two news digest workflows as OpenFang, implemented as visual node graphs. Model is configured per-job in `jobs/*.json`.

---

## OpenClaw

TypeScript AI agent gateway. Requires a one-time build from source and a Discord bot token.

### First-time setup

```bash
# Clones openclaw/openclaw, builds Docker image, starts gateway, registers cron jobs
./openclaw/setup.sh
```

### Subsequent starts

```bash
docker compose -f openclaw/docker-compose.yaml up -d

# Re-register cron jobs after restart or if DISCORD_CHANNEL_ID changed
./openclaw/init-cron.sh
```

### Changing the model

OpenClaw reads `OLLAMA_MODEL` from `.env` at startup — no rebuild needed:

```bash
# Edit .env
OLLAMA_MODEL=gemma3:27b

# Restart gateway (picks up new env var)
docker compose -f openclaw/docker-compose.yaml restart

# Re-register cron jobs (they reference the model by name)
./openclaw/init-cron.sh
```

OpenClaw auto-discovers all available Ollama models via the `/v1/models` endpoint, so any pulled model is immediately usable.

### Common commands

```bash
docker logs -f openclaw-gateway
docker exec openclaw-gateway node dist/index.js cron list
docker exec openclaw-gateway node dist/index.js cron run <job-id>
```

---

## Open WebUI

```bash
docker compose -f webui-compose.yaml up -d
# Dashboard: http://localhost:8081
```

---

## Discord Setup

### Webhook URL — n8n + OpenFang

Server Settings → Integrations → Webhooks → New Webhook → copy URL → `DISCORD_WEBHOOK_URL` in `.env`.

### Bot Token — OpenClaw + OpenFang

1. [discord.com/developers](https://discord.com/developers/applications) → New Application → **Bot** → **Add Bot** → **Copy Token** → `DISCORD_BOT_TOKEN`
2. Enable **Message Content Intent** and **Server Members Intent** under Bot → Privileged Intents
3. OAuth2 URL Generator → scopes: `bot`, `applications.commands` → permissions: Send Messages, Read Message History, View Channels → invite bot to your server
4. Enable Developer Mode (User Settings → Advanced) → right-click the channel where news should post → **Copy Channel ID** → `DISCORD_CHANNEL_ID`

One bot token works for both OpenClaw and OpenFang.

---

## Model Selection

All three automation services use the same Ollama instance. Models are not bundled — you pull them first:

```bash
ollama pull qwen3:27b      # large, best quality (needs big GPU mode)
ollama pull qwen3:14b      # good balance
ollama pull gemma3:12b     # fast, decent quality
ollama pull llama3.1:8b    # smallest, fastest
```

```bash
# List what's pulled and which is currently selected
./list-models.sh
```

| Service | How model is set |
|---------|-----------------|
| OpenFang | `OLLAMA_MODEL` in `.env` → `./openfang/setup.sh` regenerates config |
| OpenClaw | `OLLAMA_MODEL` in `.env` → restart + `./openclaw/init-cron.sh` |
| n8n | `"model"` field in `jobs/*.json` (separate per job) |

---

## GPU Switching

```bash
sudo ./ai-mode.sh big      # both GPUs (24 GB) — run larger models
sudo ./ai-mode.sh small    # RTX 5060 Ti only (8 GB) — faster, smaller models
sudo ./ai-mode.sh status
sudo ./ai-mode.sh toggle
```

---

## Environment Variables

| Variable | Used by | Description |
|----------|---------|-------------|
| `TIMEZONE` | all | Cron timezone, e.g. `Europe/Oslo` |
| `OLLAMA_MODEL` | OpenFang, OpenClaw | Model for summarization (run `./list-models.sh`) |
| `DISCORD_WEBHOOK_URL` | n8n, OpenFang | Webhook for news posts |
| `TEST_DISCORD_WEBHOOK_URL` | n8n | Webhook for test/cron-test jobs |
| `DISCORD_BOT_TOKEN` | OpenClaw, OpenFang | Discord bot token |
| `DISCORD_CHANNEL_ID` | OpenClaw | Channel ID for news posts |
| `N8N_USER` | n8n | Login username |
| `N8N_PASSWORD` | n8n | Login password |
| `N8N_ENCRYPTION_KEY` | n8n | `openssl rand -hex 16` |
| `N8N_SECURE_COOKIE` | n8n | `false` for local/LAN |

---

## Project Structure

```
.
├── .env.example
├── ai-mode.sh                     # GPU switching
├── list-models.sh                 # Show available Ollama models
├── webui-compose.yaml
├── n8n-compose.yaml
├── jobs/                          # n8n job configs (RSS sources, model, prompts)
├── n8n/
│   ├── start.sh
│   └── workflows/
├── openfang/
│   ├── Dockerfile                 # Builds local image: debian + OpenFang binary + envsubst
│   ├── docker-entrypoint.sh       # Generates config from template at startup, then starts
│   ├── docker-compose.yaml
│   ├── setup.sh                   # Optional wrapper: validates .env then docker compose up
│   ├── config.toml.template       # Config template — ${OLLAMA_MODEL} substituted at startup
│   ├── workflows/
│   │   ├── world-news.json
│   │   └── tech-digest.json
│   └── scheduler/                 # Workflow registrar + webhook relay
│       ├── Dockerfile
│       ├── schedule.json
│       └── scheduler.py
└── openclaw/
    ├── setup.sh                   # First-time: clone source + build + init
    ├── init-cron.sh               # Register/update cron jobs
    ├── docker-compose.yaml
    ├── config.jsonc               # Config (uses ${OLLAMA_MODEL} — auto-substituted)
    ├── src/                       # Cloned by setup.sh — gitignored
    └── skills/news-digest/
        └── SKILL.md
```
