#!/bin/bash

# ai-mode - Switch between Big (Dual GPU, 27B) and Small (Single GPU, 9B) modes.
# 
# This script manages GPU configuration for Docker-based Ollama deployment.
# It modifies the Ollama container's GPU access and restarts it with the new configuration.
#
# SMALL Mode (8GB VRAM - RTX 5060 Ti only):
#   - Uses GPU 1 only (RTX 5060 Ti, 8GB)
#   - Recommended models: Qwen 3.5 9B (7.5GB), Gemma 4 E4B (9.6GB)
#
# BIG Mode (24GB VRAM - Both GPUs):
#   - Uses GPU 0 + 1 (RTX 5060 16GB + 5060 Ti 8GB = 24GB total)
#   - Recommended models:
#     * Qwen 3.5 27B (17GB) - Best for coding/reasoning
#     * Gemma 4 26B A4B (15GB) - Fastest (~145 tok/s)
#     * Gemma 4 31B (18GB) - Best for math/competitive programming
#     * QwQ-32B (19GB) - Best for deep reasoning
#
# Usage: sudo ai-mode [big|small|toggle|status]

set -e

STATE_FILE="/var/lib/ai-mode/current_state"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_highlight() {
    echo -e "${CYAN}$1${NC}"
}

# Ensure the script has root for directory creation
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run with sudo to modify Docker containers and GPU configuration.${NC}"
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
            print_highlight "========================================"
            print_highlight "Switching to BIG Mode (24GB VRAM)"
            print_highlight "GPUs: RTX 5060 (16GB) + RTX 5060 Ti (8GB)"
            print_highlight "========================================"
            echo ""
            
            set_state "big"
            
            # Stop Ollama container if running
            print_status "Stopping Ollama container..."
            docker stop ollama 2>/dev/null || true
            docker rm ollama 2>/dev/null || true
            
            # Start Ollama with dual GPU access
            print_status "Starting Ollama with dual GPU configuration..."
            docker run -d \
                --name ollama \
                --gpus '"device=0,1"' \
                -p 127.0.0.1:11434:11434 \
                -v ollama_data:/root/.ollama \
                -e OLLAMA_KEEP_ALIVE=24h \
                -e OLLAMA_FLASH_ATTENTION=1 \
                --restart unless-stopped \
                ollama/ollama:latest
            
            # Wait for Ollama to be ready
            print_status "Waiting for Ollama to start..."
            sleep 10
            ATTEMPTS=0
            MAX_ATTEMPTS=30
            until curl -s http://localhost:11434/api/tags > /dev/null 2>&1; do
                ATTEMPTS=$((ATTEMPTS + 1))
                if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
                    print_error "Ollama failed to start after $MAX_ATTEMPTS attempts"
                    print_status "Check logs: docker logs ollama"
                    exit 1
                fi
                echo -n "."
                sleep 2
            done
            echo ""
            print_success "Ollama is ready!"
            
            # Show available models
            print_status "Available models in Ollama:"
            curl -s http://localhost:11434/api/tags | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sed 's/^/  - /' || echo "  No models found"
            
            echo ""
            print_highlight "========================================"
            print_success "BIG Mode activated successfully!"
            print_highlight "========================================"
            echo ""
            print_status "Recommended models for 24GB VRAM:"
            echo "  🏆 Qwen 3.5 27B      - Best for coding/reasoning (~17GB)"
            echo "  ⚡ Gemma 4 26B A4B   - Fastest inference (~15GB, ~145 tok/s)"
            echo "  🧮 Gemma 4 31B       - Best for math/competitive programming (~18GB)"
            echo "  💡 QwQ-32B           - Best for deep reasoning (~19GB)"
            echo ""
            echo "To download a model:"
            echo "  docker exec ollama ollama pull qwen3.5:27b"
            echo "  docker exec ollama ollama pull gemma4:26b-a4b-it-q4_k_m"
            echo "  docker exec ollama ollama pull gemma4:31b"
            echo ""
            ;;
            
        small)
            print_highlight "========================================"
            print_highlight "Switching to SMALL Mode (8GB VRAM)"
            print_highlight "GPU: RTX 5060 Ti (8GB only)"
            print_highlight "========================================"
            echo ""
            
            set_state "small"
            
            # Stop Ollama container if running
            print_status "Stopping Ollama container..."
            docker stop ollama 2>/dev/null || true
            docker rm ollama 2>/dev/null || true
            
            # Start Ollama with single GPU (5060 Ti = device 1)
            print_status "Starting Ollama with single GPU configuration (RTX 5060 Ti)..."
            docker run -d \
                --name ollama \
                --gpus '"device=1"' \
                -p 127.0.0.1:11434:11434 \
                -v ollama_data:/root/.ollama \
                -e OLLAMA_KEEP_ALIVE=24h \
                -e OLLAMA_FLASH_ATTENTION=1 \
                --restart unless-stopped \
                ollama/ollama:latest
            
            # Wait for Ollama to be ready
            print_status "Waiting for Ollama to start..."
            sleep 10
            ATTEMPTS=0
            MAX_ATTEMPTS=30
            until curl -s http://localhost:11434/api/tags > /dev/null 2>&1; do
                ATTEMPTS=$((ATTEMPTS + 1))
                if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
                    print_error "Ollama failed to start after $MAX_ATTEMPTS attempts"
                    print_status "Check logs: docker logs ollama"
                    exit 1
                fi
                echo -n "."
                sleep 2
            done
            echo ""
            print_success "Ollama is ready!"
            
            # Show available models
            print_status "Available models in Ollama:"
            curl -s http://localhost:11434/api/tags | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sed 's/^/  - /' || echo "  No models found"
            
            echo ""
            print_highlight "========================================"
            print_success "SMALL Mode activated successfully!"
            print_highlight "========================================"
            echo ""
            print_status "Recommended models for 8GB VRAM:"
            echo "  🏆 Qwen 3.5 9B  - Best overall (~7.5GB, 161 tok/s)"
            echo "  💎 Gemma 4 E4B  - Your current model (~9.6GB)"
            echo ""
            echo "To download a model:"
            echo "  docker exec ollama ollama pull qwen3.5:9b"
            echo "  docker exec ollama ollama pull gemma4:e4b"
            echo ""
            ;;
    esac
}

# Main command handler
case $1 in
    start)
        start_stack
        ;;
    stop)
        stop_stack
        ;;
    restart)
        restart_stack
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs $2
        ;;
    switch-big|big)
        switch_big
        ;;
    switch-small|small)
        switch_small
        ;;
    *)
        echo ""
        echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║         AI Stack Management Script                     ║${NC}"
        echo -e "${CYAN}║   Local LLMs with GPU Switching (24GB Total)          ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo -e "${YELLOW}Core Commands:${NC}"
        echo "  start          Start the AI stack (Ollama + Open WebUI)"
        echo "  stop           Stop the AI stack"
        echo "  restart        Restart the AI stack"
        echo "  status         Show detailed status of all services"
        echo ""
        echo -e "${YELLOW}GPU Mode Switching:${NC}"
        echo "  switch-big     Switch to BIG mode (dual GPU, 24GB total)"
        echo "                  ├─ RTX 5060 (16GB) + RTX 5060 Ti (8GB)"
        echo "                  ├─ Recommended: Qwen 3.5 27B (coding)"
        echo "                  ├─ Recommended: Gemma 4 26B A4B (fastest)"
        echo "                  └─ Recommended: Gemma 4 31B (math)"
        echo ""
        echo "  switch-small   Switch to SMALL mode (single 5060 Ti, 8GB)"
        echo "                  ├─ RTX 5060 Ti (8GB only)"
        echo "                  ├─ Recommended: Qwen 3.5 9B (161 tok/s)"
        echo "                  └─ Recommended: Gemma 4 E4B (9.6GB)"
        echo ""
        echo -e "${YELLOW}Monitoring:${NC}"
        echo "  logs [service] Show logs (ollama|webui)"
        echo ""
        echo -e "${CYAN}Examples:${NC}"
        echo "  $0 start              # Start everything"
        echo "  $0 switch-small       # Use small model on 5060 Ti"
        echo "  $0 switch-big         # Use big model on both GPUs"
        echo "  $0 status             # Check what's running"
        echo "  $0 logs webui         # View Open WebUI logs"
        echo ""
        exit 1
        ;;
esac
