#!/bin/bash

# ai-mode - Switch between Big (Dual GPU, 26B) and Small (Single GPU, E4B) modes.
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
        cat "$0" 2>/dev/null || cat "$STATE_FILE"
    else
        echo "small"
    fi
}

# Re-writing get_current_state correctly
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
EOF
            set_state "big"
            # Pre-load the large model to ensure it's ready
            ollama run gemma4:26b-a4b-it-q4_K_M ""
            ;;
        small)
            mkdir -p /etc/systemd/open/ollama.service.d
            tee "$OLLAMA_CONF" > /dev/null <<'EOF'
[Service]
Environment="CUDA_VISIBLE_DEVICES=0"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_KEEP_ALIVE=1h"
EOF
            set_state "small"
            # Pre-load the small model to ensure it's ready
            ollama run gemma4:e4b ""
            ;;
    esac
    systemctl daemon-reload
    systemctl restart ollama
    echo "Ollama service restarted with $1 configuration."
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
        nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader | sed 's/^/  /'
        echo "Ollama Config:"
        if [ -f "$OLLAMA_CONF" ]; then
            grep "Environment" "$OLLAMA_CONF" | sed 's/^/  /'
        else
            echo "  No override found."
        fi
        ;;
    *)
        echo "Usage: ai-mode {big|small|toggle|status}"
        exit 1
        ;;
esac
