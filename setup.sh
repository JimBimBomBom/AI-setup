#!/bin/bash

# setup.sh - Initial setup script for AI Setup repository
# Usage: ./setup.sh

set -e

echo "========================================"
echo "  AI Setup - Repository Setup"
echo "========================================"
echo ""

# Make scripts executable
echo "Making scripts executable..."
chmod +x ai-mode.sh deploy-ai.sh commit-and-push.sh 2>/dev/null || true
echo "✓ Scripts are now executable"

# Check if Docker is installed
if command -v docker &> /dev/null; then
    echo "✓ Docker is installed"
else
    echo "⚠ Docker not found. Install with: curl -fsSL https://get.docker.com | sh"
fi

# Check if NVIDIA Container Toolkit is installed
if command -v nvidia-ctk &> /dev/null; then
    echo "✓ NVIDIA Container Toolkit is installed"
else
    echo "⚠ NVIDIA Container Toolkit not found. Install with:"
    echo "   sudo apt install -y nvidia-container-toolkit"
    echo "   sudo nvidia-ctk runtime configure --runtime=docker"
    echo "   sudo systemctl restart docker"
fi

# Check if git remote is configured
if git remote -v > /dev/null 2>&1; then
    echo "✓ Git remote is configured"
    git remote -v
else
    echo "⚠ No git remote configured. To push to GitHub:"
    echo "   git remote add origin https://github.com/YOUR_USERNAME/ai-setup.git"
fi

echo ""
echo "========================================"
echo "  Setup Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Start in small mode (8GB):"
echo "   ./deploy-ai.sh switch-small"
echo ""
echo "2. Download recommended model:"
echo "   docker exec ollama ollama pull qwen3.5:9b"
echo ""
echo "3. Access Open WebUI:"
echo "   http://$(hostname -I | awk '{print $1}'):8081"
echo ""
echo "4. For 24GB mode with better models:"
echo "   ./deploy-ai.sh switch-big"
echo "   docker exec ollama ollama pull qwen3.5:27b"
echo ""
echo "Documentation:"
echo "  - README.md       - Complete guide"
echo "  - QUICKSTART.md   - 5-minute setup"
echo "  - MODELS.md       - Model comparisons"
echo "  - SUMMARY.md      - Quick reference"
echo ""
