# Model Configuration Guide for 24GB VRAM Setup

This guide helps you choose the right models for your dual-GPU setup (RTX 5060 16GB + RTX 5060 Ti 8GB = 24GB total).

## 📊 Quick Reference Table

### Small Mode (8GB VRAM - 5060 Ti only)

| Model | Size | VRAM | Speed | Best For | Command |
|-------|------|------|-------|----------|---------|
| **Qwen 3.5 9B** 🏆 | 9B | ~7.5GB | 161 tok/s | General, coding, fast | `ollama pull qwen3.5:9b` |
| Gemma 4 E4B | 2.3B active | ~9.6GB | 13.8 tok/s | Current model, basic | `ollama pull gemma4:e4b` |

### Big Mode (24GB VRAM - Both GPUs)

| Model | Size | VRAM | Speed | Best For | Command |
|-------|------|------|-------|----------|---------|
| **Qwen 3.5 27B** 🏆 | 27B | ~17GB | 110 tok/s | Coding, reasoning, agents | `ollama pull qwen3.5:27b` |
| **Gemma 4 26B A4B** ⚡ | 26B (3.8B active) | ~15GB | 145 tok/s | Fastest, coding, multilingual | `ollama pull gemma4:26b-a4b-it-q4_k_m` |
| **Gemma 4 31B** 🧮 | 31B | ~18GB | 48 tok/s | Math, competitive programming | `ollama pull gemma4:31b` |
| **QwQ-32B** 💡 | 32B | ~19GB | ~30 tok/s | Deep reasoning (thinking model) | `ollama pull qwq:32b` |

## 🎯 Use Case Recommendations

### For Software Development / Coding

**Best Choice: Qwen 3.5 27B**
```bash
# Download
ollama pull qwen3.5:27b

# Test with coding prompt
curl http://localhost:11434/api/generate -d '{
  "model": "qwen3.5:27b",
  "prompt": "Write a Python function to implement binary search with error handling"
}'
```

**Why:**
- HumanEval+: 85.9% (excellent code generation)
- LiveCodeBench: 80.7% (excellent practical coding)
- SWE-bench: 73.4% (best for real-world software engineering)
- Apache 2.0 license (no restrictions)

### For Fast Inference / Real-time Applications

**Best Choice: Gemma 4 26B A4B**
```bash
# Download
ollama pull gemma4:26b-a4b-it-q4_k_m

# Test speed
curl http://localhost:11434/api/generate -d '{
  "model": "gemma4:26b-a4b-it-q4_k_m",
  "prompt": "Explain quantum computing in simple terms"
}'
```

**Why:**
- 145 tok/s (fastest in 24GB class!)
- Only 15GB VRAM (leaves 9GB for context)
- MoE architecture (3.8B active params) = very efficient
- LiveCodeBench: 77.1% (excellent coding)

### For Math / Competitive Programming

**Best Choice: Gemma 4 31B**
```bash
# Download
ollama pull gemma4:31b

# Test with math problem
curl http://localhost:11434/api/generate -d '{
  "model": "gemma4:31b",
  "prompt": "Solve this calculus problem: Find the derivative of f(x) = x^3 * sin(x)"
}'
```

**Why:**
- AIME 2026: 89.2% (best for math competitions!)
- Codeforces ELO: 2150 (best for competitive programming)
- MMLU-Pro: 85.2% (excellent general knowledge)
- GPQA Diamond: 84.3% (excellent science reasoning)

### For Deep Reasoning / Chain-of-Thought

**Best Choice: QwQ-32B**
```bash
# Download
ollama pull qwq:32b

# Test with reasoning problem
curl http://localhost:11434/api/generate -d '{
  "model": "qwq:32b",
  "prompt": "A farmer has 17 sheep and all but 9 die. How many are left? Think through this step by step."
}'
```

**Why:**
- AIME 2024: ~79.5% (excellent reasoning)
- Chain-of-thought architecture (shows reasoning steps)
- HumanEval+: 83.5% (excellent coding with reasoning)
- Best for complex problem-solving tasks

## 🔧 Model Configuration Tips

### Quantization Levels

Ollama uses different quantization levels. Here's what they mean:

| Quantization | Size | Quality | Speed | Use Case |
|--------------|------|---------|-------|----------|
| Q8_0 | Largest | Best | Slowest | Maximum quality |
| Q6_K | Large | Excellent | Slower | High quality |
| Q5_K_M | Medium | Very Good | Fast | Balanced |
| Q4_K_M | Smaller | Good | Faster | Efficiency |
| Q3_K_M | Small | OK | Fastest | Low VRAM |

**Recommendation**: Use `Q4_K_M` for most models - best balance of quality and speed.

### Context Length (num_ctx)

Adjust context length based on your VRAM:

```bash
# For Qwen 3.5 27B (17GB VRAM)
# 24GB total - 17GB model = 7GB for context
# ~7GB / 0.5MB per 1K tokens = ~14K tokens context
# Safe default: 8192 tokens

# For Gemma 4 26B A4B (15GB VRAM)
# 24GB - 15GB = 9GB for context
# ~18K tokens possible
# Safe default: 16384 tokens
```

### Temperature Settings

Different tasks need different temperature (randomness) settings:

```bash
# Coding: Low temperature for deterministic output
PARAMETER temperature 0.2
PARAMETER top_p 0.9

# Creative writing: Higher temperature
PARAMETER temperature 0.8
PARAMETER top_p 0.95

# Reasoning/math: Low temperature
PARAMETER temperature 0.1
PARAMETER top_p 0.9

# General chat: Medium temperature
PARAMETER temperature 0.7
PARAMETER top_p 0.9
```

## 📈 Performance Benchmarks

Based on testing on RTX 4090 (similar to your dual 5060 setup):

### Small Mode (8GB)

| Model | Speed | Quality | Best For |
|-------|-------|---------|----------|
| Qwen 3.5 9B | 161 tok/s | ⭐⭐⭐⭐ | General, coding, fast responses |
| Gemma 4 E4B | 13.8 tok/s | ⭐⭐⭐ | Basic tasks, lower resource use |

### Big Mode (24GB)

| Model | Speed | Quality | Best For |
|-------|-------|---------|----------|
| Qwen 3.5 27B | 110 tok/s | ⭐⭐⭐⭐⭐ | Coding, agents, reasoning |
| Gemma 4 26B A4B | 145 tok/s | ⭐⭐⭐⭐ | Fastest, coding, multilingual |
| Gemma 4 31B | 48 tok/s | ⭐⭐⭐⭐⭐ | Math, competitive programming |
| QwQ-32B | 30 tok/s | ⭐⭐⭐⭐⭐ | Deep reasoning, thinking |

## 🎓 Use Case Examples

### Example 1: Software Development

```bash
# Start in big mode for best coding performance
./deploy-ai.sh switch-big

# Download Qwen 3.5 27B (best for coding)
docker exec ollama ollama pull qwen3.5:27b

# Use it for code review, generation, debugging
# In Open WebUI, select "qwen3.5:27b" from dropdown
```

### Example 2: Fast Prototyping

```bash
# Start in small mode for quick responses
./deploy-ai.sh switch-small

# Download Qwen 3.5 9B (fastest)
docker exec ollama ollama pull qwen3.5:9b

# Use for brainstorming, quick questions, summaries
```

### Example 3: Math and Science

```bash
# Start in big mode
./deploy-ai.sh switch-big

# Download Gemma 4 31B (best for math)
docker exec ollama ollama pull gemma4:31b

# Use for calculus, physics problems, competitive programming
```

### Example 4: Multilingual Support

```bash
# Start in big mode
./deploy-ai.sh switch-big

# Download Gemma 4 26B A4B (excellent multilingual)
docker exec ollama ollama pull gemma4:26b-a4b-it-q4_k_m

# Supports 100+ languages
```

## 🔍 Model Comparison Matrix

| Feature | Qwen 3.5 27B | Gemma 4 26B A4B | Gemma 4 31B | QwQ-32B |
|---------|--------------|-----------------|-------------|---------|
| **Parameters** | 27B dense | 26B (3.8B active) | 31B dense | 32B dense |
| **VRAM Usage** | ~17GB | ~15GB | ~18GB | ~19GB |
| **Speed** | 110 tok/s | 145 tok/s | 48 tok/s | 30 tok/s |
| **Coding** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Reasoning** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Math** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Multilingual** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **License** | Apache 2.0 | Gemma | Gemma | Qwen |

## 🎬 Next Steps

1. **Choose your mode:**
   ```bash
   ./deploy-ai.sh switch-small   # For 8GB VRAM
   ./deploy-ai.sh switch-big     # For 24GB VRAM
   ```

2. **Download recommended models:**
   ```bash
   # For small mode
   docker exec ollama ollama pull qwen3.5:9b
   
   # For big mode
   docker exec ollama ollama pull qwen3.5:27b
   ```

3. **Access Open WebUI:**
   - Open browser: `http://your-server-ip:8081`
   - Create account
   - Select model from dropdown
   - Start chatting!

4. **Monitor performance:**
   ```bash
   # Watch GPU usage
   watch -n 1 nvidia-smi
   
   # Check Ollama status
   curl http://localhost:11434/api/ps
   ```

---

**Questions or Issues?** Check the main README.md or run `./deploy-ai.sh status` for diagnostics.
