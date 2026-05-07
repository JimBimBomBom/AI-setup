# OpenFang Workflows - Registration Guide

## Overview

15 workflows have been created and validated. However, they need to be **registered** with OpenFang via its REST API before they appear in the UI or can be executed.

## How Workflow Registration Works

OpenFang uses a **scheduler sidecar** that automatically registers workflows on startup, but this requires:

1. The OpenFang main container to be running
2. The scheduler container to be running (and restart to pick up new workflows)
3. The scheduler must successfully connect to OpenFang's API

## Quick Start - Register Workflows

### Option 1: Restart the Scheduler (Automatic)

If OpenFang and the scheduler are already running, restart the scheduler to trigger registration:

```bash
docker compose -f openfang/docker-compose.yaml restart openfang-scheduler
```

Watch the logs to see registration:
```bash
docker logs -f openfang-scheduler
```

### Option 2: Manual Registration (Node.js)

If the scheduler isn't working or you want immediate registration:

**Prerequisites:**
- OpenFang must be running: `docker compose -f openfang/docker-compose.yaml up -d openfang`
- Node.js installed (or use the browser method below)

**Register all workflows:**
```bash
cd openfang
node register-workflows.js
```

Or with custom API URL:
```bash
node register-workflows.js http://localhost:4200
```

### Option 3: Manual Registration (Browser)

You can also use browser DevTools to register workflows:

1. Open OpenFang in browser: http://localhost:4200
2. Open DevTools (F12) → Console
3. Copy and paste the following for each workflow:

```javascript
// Example: Register a workflow
fetch('http://localhost:4200/api/workflows', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(/* paste workflow JSON here */)
})
.then(r => r.json())
.then(data => console.log('Registered:', data.id))
.catch(err => console.error('Failed:', err));
```

### Option 4: cURL (Linux/Mac/WSL)

```bash
cd openfang

# Register one workflow
curl -X POST http://localhost:4200/api/workflows \
  -H "Content-Type: application/json" \
  -d @workflows/global-news.json

# Or use the bash script
bash register-workflows.sh
```

## Troubleshooting

### "Cannot connect to OpenFang"

**Cause:** OpenFang isn't running or API is on a different port

**Fix:**
```bash
# Start OpenFang
docker compose -f openfang/docker-compose.yaml up -d openfang

# Check it's running
curl http://localhost:4200/api/health
```

### "Workflow already registered"

**Cause:** Workflow with same name exists

**Fix:** Either:
1. Use a different `name` field in the JSON
2. Delete the existing workflow via API first
3. Or just use the existing one (it has the same content)

### Workflows don't appear in UI

**Cause:** Registration might have failed silently

**Fix:**
1. Check scheduler logs: `docker logs openfang-scheduler | grep -i error`
2. Try manual registration with Node.js script for detailed errors
3. Check browser console for CORS errors (if accessing from different origin)

## Available Workflows

| Workflow | Schedule | Description |
|----------|----------|-------------|
| `world-news.json` | 6:00 AM | Classic world news digest |
| `global-news.json` | 6:30 AM | Multi-region global news (6 regions, 20+ countries) |
| `americas-news.json` | 7:00 AM | North & South America focus |
| `europe-news.json` | 7:30 AM | European regional news |
| `asia-pacific-news.json` | 8:00 AM | Asia-Pacific regional news |
| `market-brief.json` | 8:30 AM | Crypto + market indices |
| `tech-digest.json` | 9:00 AM | Classic tech news digest |
| `coding-tech-ai.json` | 9:30 AM | Developer frameworks, AI models, languages |
| `hacker-news-digest.json` | 10:00 AM | HN top stories with categorization |
| `github-trending.json` | 11:00 AM | Trending repos + HN combined |
| `geopolitical-perspectives.json` | 12:00 PM | Multi-perspective geopolitical analysis |
| `investing-intelligence.json` | 4:00 PM (weekdays) | Market movers, earnings, M&A, IPOs |
| `deep-research.json` | Manual | Loop-mode deep research |
| `multi-agent-analysis.json` | Manual | Researcher → Analyst → Writer pipeline |
| `web-scraping-demo.json` | Manual | Live web scraping demonstration |

## API Endpoints

- **List workflows:** `GET http://localhost:4200/api/workflows`
- **Register workflow:** `POST http://localhost:4200/api/workflows` (body: workflow JSON)
- **Run workflow:** `POST http://localhost:4200/api/workflows/{id}/run` (body: `{"input": "..."}`)
- **Health check:** `GET http://localhost:4200/api/health`

## Files Generated

- `workflows/*.json` - 15 workflow definitions
- `register-workflows.js` - Node.js registration script
- `register-workflows.sh` - Bash registration script (Linux/Mac/WSL)
- `register-workflows.ps1` - PowerShell registration script (Windows)
- `scheduler/entrypoint.sh` - Scheduler's auto-registration script

## Next Steps After Registration

1. **Verify workflows loaded:** Visit http://localhost:4200 and check workflows appear
2. **Test a workflow:** Pick an ID from the list and run it manually
3. **Start scheduler:** For automated daily execution, ensure scheduler is running
4. **Check Discord:** Workflows will post to your configured webhook
