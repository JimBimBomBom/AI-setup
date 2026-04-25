# AI Setup

Local LLM stack with GPU switching for dual-GPU setup.

## Hardware

- **GPU 0**: RTX 5060 (8GB)
- **GPU 1**: RTX 5060 Ti (16GB)
- **Total**: 24GB VRAM

## Modes

### Small Mode (16GB - 5060 Ti only)
- GPU: RTX 5060 Ti (16GB)
- Target model: 12-14GB to leave room for context
- Current: gemma4:e4b (9.6GB, works but slow)
- Test: gemma4:12b, qwen3.5:14b (see models-to-test.txt)

### Big Mode (24GB - Both GPUs)
- GPUs: RTX 5060 (8GB) + RTX 5060 Ti (16GB)
- Target model: 18-22GB
- Recommended: qwen3.5:27b (17GB, excellent coding)
- Test: gemma4:31b, qwq:32b (see models-to-test.txt)

## Quick Start

```bash
# Start Ollama (small mode on 5060 Ti)
docker compose -f ollama-compose.yaml up -d

# Switch to big mode (both GPUs)
sudo ./ai-mode.sh big

# Start Open WebUI
docker compose -f webui-compose.yaml up -d

# Access: http://localhost:8081
```

## Commands

```bash
# Check status
docker ps
nvidia-smi

# View logs
docker logs -f ollama
docker logs -f open-webui

# Switch GPU modes
sudo ./ai-mode.sh small   # 5060 Ti only (16GB)
sudo ./ai-mode.sh big     # Both GPUs (24GB)
sudo ./ai-mode.sh status  # Check current mode

# Stop everything
docker compose -f ollama-compose.yaml down
docker compose -f webui-compose.yaml down
```

## Files

| File | Purpose |
|------|---------|
| `ollama-compose.yaml` | Ollama on localhost:11434 |
| `webui-compose.yaml` | Open WebUI on port 8081 |
| `ai-mode.sh` | GPU switching (requires sudo) |
| `models-to-test.txt` | Personal testing notes (gitignored) |
| `README.md` | This file |

## Security

- Ollama: bound to `127.0.0.1:11434` (localhost only, not exposed)
- Open WebUI: port `8081` with authentication enabled
- GPU access restricted via Docker device mapping

## Model Testing

See `models-to-test.txt` for personal testing notes. This file is gitignored so you can add your own notes.

## Recommended Models (2026)

### Small Mode (16GB)
- **gemma4:e4b** (9.6GB) - Current, works but slow
- Test: gemma4:12b, qwen3.5:14b (target 12-14GB)

### Big Mode (24GB)
- **qwen3.5:27b** (17GB) - Best for coding/reasoning
- **gemma4:26b-a4b-it-q4_k_m** (15GB) - Fastest
- Test: gemma4:31b, qwq:32b

## Troubleshooting

### Ollama not responding
```bash
docker ps | grep ollama
docker logs -f ollama
curl http://localhost:11434/api/tags
```

### GPU not being used
```bash
nvidia-smi
docker exec ollama nvidia-smi
sudo ./ai-mode.sh status
```

### Open WebUI can't connect
```bash
docker logs -f open-webui
docker exec open-webui curl http://localhost:11434/api/tags
```

## Git Commit

```bash
# Add all files
git add .

# Commit
git commit -m "AI Setup: Local LLMs with GPU switching

- Ollama (localhost:11434) + Open WebUI (port 8081)
- GPU modes: small (5060 Ti 16GB) ↔ big (both 24GB)
- Recommended: qwen3.5:27b (big), gemma4:e4b (small)
- Security: Ollama localhost-only, WebUI with auth

Hardware: RTX 5060 (8GB) + RTX 5060 Ti (16GB) = 24GB total"

# Push to GitHub
git push origin main
```

## License

MIT - Do whatever you want with this.
