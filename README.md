# Local LLM Stack: Ollama + Open WebUI

A Docker Compose deployment for running Ollama (AI model server) with Open WebUI (chat interface) on your local network with proper network isolation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           HOST MACHINE                          │
│  ┌──────────────────┐         ┌────────────────────────────┐   │
│  │   LAN Devices    │────────▶│  Open WebUI (Port 8081)    │   │
│  │   (Phones, PCs)  │         │  http://<host-ip>:8081     │   │
│  └──────────────────┘         └───────────┬────────────────┘   │
│                                           │                     │
│                                           │ Docker Network      │
│                                           │ llm_internal        │
│                                           │                     │
│                              ┌────────────▼────────────────┐    │
│                              │  Ollama (Port 11434)        │    │
│                              │  NOT exposed to LAN/Host      │    │
│                              │  Internal only                │    │
│                              └─────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Why This Setup?

### The Problem with `host.docker.internal`
The error `Cannot connect to host host.docker.internal:11434` happens because:
- `host.docker.internal` doesn't work on Linux by default (needs `--add-host`)
- Ollama binds to `127.0.0.1` by default, blocking external connections
- Cross-container networking is fragile when containers are deployed separately

### The Solution: Shared Docker Network
Both services share a private Docker bridge network (`llm_internal`):
- **Service discovery**: Open WebUI connects to `http://ollama:11434` using Docker's internal DNS
- **Network isolation**: Ollama has no exposed ports - completely inaccessible from LAN
- **Security**: Only Open WebUI is exposed (port 8081) to your local network

## Prerequisites

1. **Docker & Docker Compose** installed
2. **NVIDIA Container Toolkit** (for GPU support):
   ```bash
   # Ubuntu/Debian
   sudo apt install nvidia-container-toolkit
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```
3. **NVIDIA Docker runtime** configured as default

## Quick Start

1. **Start the stack**:
   ```bash
   docker compose up -d
   ```

2. **Download a model** (Qwen3 30B-A3B recommended for 24GB VRAM):
   ```bash
   docker exec -it ollama ollama pull qwen3:30b-a3b
   ```

   Other good options for your dual GPU setup (16GB + 8GB):
   - `qwen3:30b-a3b` - MoE model, fast, ~18GB at Q4
   - `gpt-oss:20b` - OpenAI's reasoning model, good for agents
   - `qwen3:32b` - Dense model, higher quality, slower

3. **Access the UI**:
   - Find your host IP: `ipconfig` (Windows) or `ip addr` (Linux)
   - Open: `http://<your-host-ip>:8081`
   - Create an account on first launch (auth is enabled for LAN security)

4. **Configure Open WebUI**:
   - Go to Settings → General
   - Ollama API URL should already be set to `http://ollama:11434`
   - Select your downloaded model from the dropdown

## Network Configuration

### Current Setup (LAN Access)
- Open WebUI: Available at `http://<host-ip>:8081` from any device on your network
- Ollama: Not exposed - only accessible within Docker

### To Restrict to Localhost Only
Edit `compose.yaml` and change the ports line:
```yaml
ports:
  - "127.0.0.1:8081:8080"  # Only localhost can access
```

### Firewall Rules (if needed)
If you want to block external access:
```bash
# Allow only local network (example: 192.168.1.x)
iptables -A INPUT -p tcp --dport 8081 -s 192.168.1.0/24 -j ACCEPT
iptables -A INPUT -p tcp --dport 8081 -j DROP
```

## GPU Verification

Check both GPUs are being used:
```bash
# Watch nvidia-smi inside the Ollama container
docker exec -it ollama nvidia-smi

# Or watch in real-time
docker exec -it ollama watch -n 1 nvidia-smi
```

When running a model, you should see VRAM allocated on both GPUs.

## Troubleshooting

### "Model not selected" error
1. Verify Ollama connection in Open WebUI settings (should show `http://ollama:11434`)
2. Check model is pulled: `docker exec ollama ollama list`
3. Restart Open WebUI: `docker restart open-webui`

### No GPUs detected
1. Verify NVIDIA Container Toolkit: `nvidia-ctk --version`
2. Check Docker runtime: `docker info | grep -i nvidia`
3. Restart Docker: `sudo systemctl restart docker`

### Cannot connect to Ollama
```bash
# Test connectivity from Open WebUI container
docker exec -it open-webui curl http://ollama:11434/api/tags

# Should return JSON with model list
```

### Model too large for VRAM
With 24GB total (16GB + 8GB), stick to models under ~14GB at Q4 quantization:
- Qwen3 30B-A3B (~18GB Q4) - might need flash attention or slight quantization tweak
- Gemma 3 27B (~16GB Q4) - fits well on the 16GB GPU
- DeepSeek-R1 14B (~9GB Q4) - plenty of room

## Managing the Stack

```bash
# Start
docker compose up -d

# Stop
docker compose down

# Stop and remove all data (WARNING: deletes models!)
docker compose down -v

# View logs
docker compose logs -f

# Update images
docker compose pull
docker compose up -d

# Exec into containers
docker exec -it ollama bash
docker exec -it open-webui bash
```

## Model Recommendations for Your Hardware

**RTX 5060 (16GB) + RTX 5060 Ti (8GB) = 24GB Total**

Best choices:
1. **Qwen3 30B-A3B** (MoE, 3B active) - Fast, good quality, ~18GB
2. **gpt-oss:20b** - OpenAI's model, strong reasoning, ~12GB
3. **Qwen3 32B** (dense) - Highest quality, slower, ~19GB
4. **Gemma 3 27B** - Good balance, ~16GB

Avoid models over 20GB dense or they won't fit well across your GPUs.

## Files

- `compose.yaml` - Docker Compose configuration
- `README.md` - This file

## Security Notes

- Auth is enabled by default (`WEBUI_AUTH=True`) - create an account on first launch
- Ollama is not exposed to the network - good for security
- Change the default port (8081) in compose.yaml if needed
- Consider setting `WEBUI_SECRET_KEY` for production-like deployments

## References

- [Ollama Docker Hub](https://hub.docker.com/r/ollama/ollama)
- [Open WebUI GitHub](https://github.com/open-webui/open-webui)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
