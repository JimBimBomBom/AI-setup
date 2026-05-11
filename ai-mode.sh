#!/bin/bash

# ai-mode - Switch between Big (Dual GPU, 3090+5060Ti) and Small (Single GPU, 5060Ti) modes.
# Usage: sudo ai-mode [big|small|toggle|status]

STATE_FILE="/var/lib/ai-mode/current_state"
OLLAMA_CONF="/etc/systemd/system/ollama.service.d/override.conf"

# Ensure the script has root for directory creation
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with sudo to modify system configurations."
   exit 1
fi

mkdir -p /var/lib/ai-mode

get_current_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "small"
    fi
}

set_state() {
    echo "$1" > "$STATE_FILE"
}

apply_mode() {
    case $1 in
        big)
            mkdir -p /etc/systemd/system/ollama.service.d
            tee "$OLLAMA_CONF" > /dev/null <<'EOF'
[Service]
Environment="CUDA_VISIBLE_DEVICES=0,1"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_KEEP_ALIVE=1h"
Environment="OLLAMA_FLASH_ATTENTION=1"
EOF
            set_state "big"
            systemctl daemon-reload
            systemctl restart ollama
            
            # Wait for Ollama to be ready
            echo "Waiting for Ollama to restart..."
            sleep 5
            until curl -s http://localhost:11434/api/tags > /dev/null 2>&1; do
                echo -n "."
                sleep 2
            done
            echo " Ollama is ready!"
            
            # Pre-load the recommended big model
            echo "Pre-loading recommended models for 40GB VRAM (3090 + 5060Ti)..."
            echo "  - Qwen 3.5 27B (coding, reasoning)"
            ollama pull qwen3.5:27b &
            ;;
            
        small)
            mkdir -p /etc/systemd/system/ollama.service.d
            tee "$OLLAMA_CONF" > /dev/null <<'EOF'
[Service]
Environment="CUDA_VISIBLE_DEVICES=1"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_KEEP_ALIVE=1h"
Environment="OLLAMA_FLASH_ATTENTION=1"
EOF
            set_state "small"
            systemctl daemon-reload
            systemctl restart ollama
            
            # Wait for Ollama to be ready
            echo "Waiting for Ollama to restart..."
            sleep 5
            until curl -s http://localhost:11434/api/tags > /dev/null 2>&1; do
                echo -n "."
                sleep 2
            done
            echo " Ollama is ready!"
            
            # Unload any other models to free VRAM on the 3090
            echo "Stopping other models to free VRAM..."
            ollama stop qwen3.5:27b 2>/dev/null || true
            ollama stop qwen3.5:14b 2>/dev/null || true
            
            # Pre-load the fast small model
            echo "Pre-loading Qwen 3.5 9B for fast inference on RTX 3090..."
            ollama pull qwen3.5:9b &
            ;;
    esac
    echo "Ollama service restarted in $1 mode."
    echo ""
    echo "Recommended models for $1 mode:"
    if [ "$1" = "big" ]; then
        echo "  - Qwen 3.5 27B Q4_K_M: Best overall (~17GB, fits on 3090 alone)"
        echo "  - Qwen 3.5 32B Q4_K_M: Larger reasoning (~20GB, fits on 3090)"
        echo "  - Gemma 3 27B Q4_K_M: Fast alternative (~17GB)"
        echo "  - Llama 3.3 70B Q2_K: Max size (~35GB, spans both GPUs)"
    else
        echo "  - Qwen 3.5 14B Q4_K_M: Best overall (~9GB, fast)"
        echo "  - Qwen 3.5 9B Q4_K_M: Fastest (~6GB)"
        echo "  - Gemma 3 12B Q4_K_M: Good alternative (~8GB)"
    fi
}

case $1 in
    big)
        apply_mode big
        ;;
    small)
        apply_mode small
        ;;
    toggle)
        CURRENT=$(get_current_state)
        if [ "$CURRENT" = "big" ]; then
            apply_mode small
        else
            apply_mode big
        fi
        ;;
    status)
        CURRENT=$(get_current_state)
        echo "Current AI Mode: $CURRENT"
        echo "-----------------------"
        echo "GPU Configuration:"
        nvidia-smi --query-gpu=index,name,memory.total,memory.used --format=csv,noheader | sed 's/^/  /'
        echo ""
        echo "Ollama Config:"
        if [ -f "$OLLAMA_CONF" ]; then
            grep "Environment" "$OLLAMA_CONF" | sed 's/^/  /'
        else
            echo "  No override found."
        fi
        echo ""
        echo "Available Models:"
        ollama list 2>/dev/null | sed 's/^/  /' || echo "  Ollama not responding"
        ;;
    *)
        echo "AI Mode - GPU Switching for Local LLMs"
        echo ""
        echo "Usage: ai-mode {big|small|toggle|status}"
        echo ""
        echo "Modes:"
        echo "  big     - Dual GPU mode (RTX 3090 24GB + RTX 5060Ti 16GB = 40GB)"
        echo "            Recommended: Qwen 3.5 27B, Qwen 3.5 32B, Gemma 3 27B"
        echo ""
        echo "  small   - Single GPU mode (RTX 5060Ti 16GB)"
        echo "            Recommended: Qwen 3.5 14B, Qwen 3.5 9B, Gemma 3 12B"
        echo ""
        echo "Examples:"
        echo "  sudo ai-mode big       # Switch to dual GPU mode"
        echo "  sudo ai-mode small     # Switch to single GPU mode"
        echo "  sudo ai-mode toggle    # Toggle between modes"
        echo "  sudo ai-mode status    # Show current status"
        exit 1
        ;;
esac
