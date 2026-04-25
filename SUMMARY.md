# AI Setup - Summary of Changes

## 🎯 What You Asked For

You wanted:
1. ✅ **Separate deployments** for Ollama (local network only) and Open WebUI (public)
2. ✅ **Clear separation** between small mode (5060 Ti only, 8GB) and big mode (both GPUs, 24GB)
3. ✅ **Best 2026 models** for your 24GB VRAM setup
4. ✅ **Easy deployment** to your server

## 📦 What You Get

### Repository Structure
```
ai-setup/
├── ollama-compose.yaml      # Ollama - localhost only (port 11434)
├── webui-compose.yaml       # Open WebUI - public (port 8081)
├── ai-mode.sh               # GPU switching script
├── deploy-ai.sh             # One-command deployment manager
├── README.md                # Complete documentation
├── QUICKSTART.md            # 5-minute setup guide
├── MODELS.md                # Comprehensive model guide
└── .gitignore               # Security exclusions
```

### Small Mode (8GB - RTX 5060 Ti)

**Recommended Model: Qwen 3.5 9B**
- VRAM: ~7.5GB
- Speed: 161 tok/s (20x faster than your current E4B!)
- Best for: General tasks, coding, fast responses
- Command: `ollama pull qwen3.5:9b`

### Big Mode (24GB - Both GPUs)

**Recommended Model: Qwen 3.5 27B** (Best Overall)
- VRAM: ~17GB
- Speed: 110 tok/s
- Best for: Coding, reasoning, agents, software engineering
- MMLU-Pro: 86.1% (excellent knowledge)
- HumanEval+: 85.9% (best coding)
- SWE-bench: 73.4% (best for real-world software)
- Command: `ollama pull qwen3.5:27b`

**Alternative: Gemma 4 26B A4B** (Fastest)
- VRAM: ~15GB
- Speed: 145 tok/s (fastest!)
- Best for: Coding, multilingual, speed-critical tasks
- Architecture: MoE (3.8B active params, very efficient)
- Command: `ollama pull gemma4:26b-a4b-it-q4_k_m`

**Alternative: Gemma 4 31B** (Math Champion)
- VRAM: ~18GB
- Speed: 48 tok/s (slower but powerful)
- Best for: Math competitions, competitive programming
- AIME 2026: 89.2% (best for math!)
- Codeforces ELO: 2150 (best for competitive programming)
- Command: `ollama pull gemma4:31b`

## 🚀 Deployment Commands

### Start Everything (Small Mode)

```bash
# Clone repository
git clone https://github.com/YOUR_USERNAME/ai-setup.git
cd ai-setup

# Make scripts executable
chmod +x *.sh

# Start in small mode (8GB, 5060 Ti only)
./deploy-ai.sh switch-small

# Download recommended small model
docker exec ollama ollama pull qwen3.5:9b

# Access at http://your-server-ip:8081
```

### Switch to Big Mode (24GB)

```bash
# Switch to big mode (both GPUs)
./deploy-ai.sh switch-big

# Download recommended big model
docker exec ollama ollama pull qwen3.5:27b

# Model is now ready to use!
```

### Common Operations

```bash
# Check status
./deploy-ai.sh status

# View logs
./deploy-ai.sh logs ollama
./deploy-ai.sh logs webui

# Stop everything
./deploy-ai.sh stop

# Restart
./deploy-ai.sh restart
```

## 🔒 Security Summary

- ✅ **Ollama**: Bound to `127.0.0.1:11434` - NOT accessible from internet
- ✅ **Open WebUI**: Port `8081` public on your LAN
- ✅ **Authentication**: Enabled by default (`WEBUI_AUTH=True`)
- ✅ **GPU Isolation**: Models run in Docker with restricted GPU access

## 📊 Model Performance Summary

| Mode | Model | VRAM | Speed | Best For |
|------|-------|------|-------|----------|
| Small | Qwen 3.5 9B | 7.5GB | 161 tok/s | General, fast |
| Small | Gemma 4 E4B | 9.6GB | 13.8 tok/s | Basic tasks |
| Big | Qwen 3.5 27B | 17GB | 110 tok/s | Coding, agents 🏆 |
| Big | Gemma 4 26B A4B | 15GB | 145 tok/s | Fastest ⚡ |
| Big | Gemma 4 31B | 18GB | 48 tok/s | Math champion 🧮 |
| Big | QwQ-32B | 19GB | 30 tok/s | Deep reasoning 💡 |

## 🎓 Learning Path

1. **Start Small**: Try Qwen 3.5 9B in small mode
2. **Go Big**: Switch to big mode and try Qwen 3.5 27B
3. **Experiment**: Try different models for different tasks
4. **Optimize**: Adjust quantization and context for your needs

## 📚 Documentation

- **README.md**: Complete setup and configuration guide
- **QUICKSTART.md**: 5-minute quick start guide
- **MODELS.md**: Comprehensive model comparison and benchmarks
- **This file**: Summary of changes and quick reference

## 🆘 Troubleshooting

**Problem**: Ollama not responding
```bash
# Check if Ollama is running
docker ps | grep ollama

# Check logs
docker logs -f ollama

# Test connection
curl http://localhost:11434/api/tags
```

**Problem**: GPU not being used
```bash
# Check GPU status
nvidia-smi

# Check Ollama GPU access
docker exec ollama nvidia-smi

# Verify mode
./deploy-ai.sh status
```

**Problem**: Open WebUI can't connect
```bash
# Check Open WebUI logs
docker logs -f open-webui

# Test Ollama from Open WebUI
docker exec open-webui curl http://localhost:11434/api/tags

# Restart Open WebUI
docker restart open-webui
```

## ✅ Checklist

Before you start:
- [ ] Docker installed
- [ ] NVIDIA Container Toolkit installed
- [ ] Git repository cloned
- [ ] Scripts made executable (`chmod +x *.sh`)

Small Mode (8GB):
- [ ] Run `./deploy-ai.sh switch-small`
- [ ] Download Qwen 3.5 9B: `docker exec ollama ollama pull qwen3.5:9b`
- [ ] Access http://your-server-ip:8081

Big Mode (24GB):
- [ ] Run `./deploy-ai.sh switch-big`
- [ ] Download Qwen 3.5 27B: `docker exec ollama ollama pull qwen3.5:27b`
- [ ] Access http://your-server-ip:8081

## 🎉 You're Ready!

Your local AI setup is now ready. Enjoy your private, fast, and powerful AI assistant!

**Questions?** Check the detailed documentation in README.md and MODELS.md

**Issues?** Run `./deploy-ai.sh status` for diagnostics

---

**Last Updated:** April 2026  
**Version:** 2.0 - 2026 Model Update  
**Models:** Qwen 3.5, Gemma 4, DeepSeek, Llama 4
