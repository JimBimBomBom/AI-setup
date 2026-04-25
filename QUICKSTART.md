# AI Setup - Quick Start Guide

🚀 **Get your local AI running in 5 minutes**

## 📦 What You Have

This repository contains a complete local AI stack:

- **Ollama**: AI model server (runs in Docker, localhost only)
- **Open WebUI**: Chat interface (runs in Docker, public port 8081)
- **ai-mode.sh**: GPU switching script (small ↔ big mode)
- **deploy-ai.sh**: One-command management script

## 🎯 Your Hardware

- **GPU 0**: RTX 5060 (16GB VRAM)
- **GPU 1**: RTX 5060 Ti (8GB VRAM)
- **Total**: 24GB VRAM
- **Modes**: Small (8GB) or Big (24GB)

## ⚡ 5-Minute Quick Start

### Step 1: Install Prerequisites

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh

# Install NVIDIA Container Toolkit
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Step 2: Clone and Setup

```bash
git clone https://github.com/YOUR_USERNAME/ai-setup.git
cd ai-setup
chmod +x *.sh
```

### Step 3: Start in Small Mode (Fastest)

```bash
# Switch to small mode (8GB VRAM, 5060 Ti only)
./deploy-ai.sh switch-small
```

This will:
- ✅ Start Ollama on GPU 1 (5060 Ti)
- ✅ Start Open WebUI
- ✅ Download Qwen 3.5 9B (recommended)

Wait ~30 seconds for models to download.

### Step 4: Access the Interface

Open your browser and go to:
```
http://YOUR-SERVER-IP:8081
```

**First time:**
1. Create an account (authentication is enabled)
2. Click the model dropdown (top of chat)
3. Select `qwen3.5:9b`
4. Start chatting!

### Step 5: Try Big Mode (24GB)

```bash
# Switch to big mode (both GPUs, 24GB total)
./deploy-ai.sh switch-big

# Download recommended big model (Qwen 3.5 27B)
docker exec ollama ollama pull qwen3.5:27b
```

Available big models:
- **Qwen 3.5 27B** (17GB) - Best for coding/reasoning 🏆
- **Gemma 4 26B A4B** (15GB) - Fastest (145 tok/s) ⚡
- **Gemma 4 31B** (18GB) - Best for math/competitive programming 🧮
- **QwQ-32B** (19GB) - Best for deep reasoning 💡

## 🎮 Common Commands

```bash
# Check status
./deploy-ai.sh status

# View logs
./deploy-ai.sh logs ollama    # Ollama logs
./deploy-ai.sh logs webui     # Open WebUI logs

# Switch modes
./deploy-ai.sh switch-small   # 8GB mode (5060 Ti)
./deploy-ai.sh switch-big     # 24GB mode (both GPUs)

# Stop everything
./deploy-ai.sh stop

# Restart everything
./deploy-ai.sh restart
```

## 📊 Model Comparison

### Small Mode (8GB)

| Model | Speed | Quality | Best For |
|-------|-------|---------|----------|
| Qwen 3.5 9B | 161 tok/s | ⭐⭐⭐⭐ | General, coding, fast |
| Gemma 4 E4B | 13.8 tok/s | ⭐⭐⭐ | Basic tasks |

### Big Mode (24GB)

| Model | Speed | Quality | Best For |
|-------|-------|---------|----------|
| Qwen 3.5 27B | 110 tok/s | ⭐⭐⭐⭐⭐ | Coding, reasoning, agents |
| Gemma 4 26B A4B | 145 tok/s | ⭐⭐⭐⭐ | Fastest, coding, multilingual |
| Gemma 4 31B | 48 tok/s | ⭐⭐⭐⭐⭐ | Math, competitive programming |
| QwQ-32B | 30 tok/s | ⭐⭐⭐⭐⭐ | Deep reasoning |

## 🚀 Performance Tips

1. **Use Q4_K_M quantization** - Best balance of quality and speed
2. **Enable flash attention** - Already enabled in our config (20-30% speed boost)
3. **Keep models loaded** - OLLAMA_KEEP_ALIVE=24h prevents reloading
4. **Use MoE models** - Gemma 4 26B A4B runs at 145 tok/s with only 3.8B active params

## 🐛 Troubleshooting

### "Cannot connect to Ollama"

```bash
# Check if Ollama is running
docker ps | grep ollama

# Check Ollama logs
docker logs -f ollama

# Test Ollama API
curl http://localhost:11434/api/tags
```

### "Model not found"

```bash
# List available models
docker exec ollama ollama list

# Download a model
docker exec ollama ollama pull qwen3.5:27b

# Check model loaded
curl http://localhost:11434/api/ps
```

### GPU not being used

```bash
# Check GPU status
nvidia-smi

# Check which GPUs Ollama sees
docker exec ollama nvidia-smi

# Verify current mode
./deploy-ai.sh status

# Switch mode if needed
./deploy-ai.sh switch-big   # or switch-small
```

## 📚 Additional Resources

- **Detailed Model Guide**: See `MODELS.md` for comprehensive model comparisons
- **Security Guide**: Check README.md Security section
- **Performance Tuning**: See README.md Performance Tuning section
- **Benchmarks**: All benchmarks from 2026 evaluations (Qwen 3.5, Gemma 4, Llama 4)

## 🎓 Learning Path

1. **Start Small**: Try Qwen 3.5 9B in small mode
2. **Go Big**: Switch to big mode and try Qwen 3.5 27B
3. **Experiment**: Try different models for different tasks
4. **Optimize**: Fine-tune quantization and context length for your needs

---

**Ready to start?** Run: `./deploy-ai.sh switch-small` 🚀
