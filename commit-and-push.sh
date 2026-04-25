#!/bin/bash

# commit-and-push.sh - Helper script to commit and push to GitHub
# Usage: ./commit-and-push.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  AI Setup - Git Commit & Push Helper  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if git is initialized
if [ ! -d .git ]; then
    echo -e "${YELLOW}Initializing Git repository...${NC}"
    git init
    echo -e "${GREEN}✓ Git repository initialized${NC}"
fi

# Check git status
echo -e "${BLUE}Checking repository status...${NC}"
git status

# Ask for confirmation
echo ""
read -p "Do you want to add all files and commit? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Add all files
    echo -e "${BLUE}Adding files to staging...${NC}"
    git add .
    echo -e "${GREEN}✓ Files added${NC}"
    
    # Create commit
    echo -e "${BLUE}Creating commit...${NC}"
    git commit -m "Initial commit: AI Setup with 2026 models

Complete local AI stack with:
- Ollama (Docker, localhost:11434) - Model server
- Open WebUI (Docker, port 8081) - Chat interface  
- ai-mode.sh - GPU switching (small ↔ big mode)
- deploy-ai.sh - One-command deployment

GPU Configuration:
- Small mode: RTX 5060 Ti (8GB) - Qwen 3.5 9B
- Big mode: RTX 5060 + 5060 Ti (24GB) - Qwen 3.5 27B, Gemma 4 26B/31B

Security:
- Ollama bound to localhost only
- Open WebUI with authentication
- Separate network isolation

Documentation:
- README.md - Complete setup guide
- QUICKSTART.md - 5-minute start
- MODELS.md - Comprehensive model comparison
- SUMMARY.md - Quick reference

Updated: April 2026
Models: Qwen 3.5, Gemma 4, DeepSeek, Llama 4"
    
    echo -e "${GREEN}✓ Commit created${NC}"
    
    # Check if remote exists
    if git remote -v > /dev/null 2>&1; then
        echo -e "${BLUE}Pushing to remote repository...${NC}"
        git push -u origin main
        echo -e "${GREEN}✓ Pushed to GitHub${NC}"
    else
        echo -e "${YELLOW}No remote repository configured.${NC}"
        echo ""
        echo "To push to GitHub:"
        echo "1. Create a new repository on GitHub named 'ai-setup'"
        echo "2. Run: git remote add origin https://github.com/YOUR_USERNAME/ai-setup.git"
        echo "3. Run: git push -u origin main"
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Commit & Push Complete!              ${NC}"
    echo -e "${GREEN}========================================${NC}"
    
else
    echo -e "${YELLOW}Commit cancelled.${NC}"
    echo "To commit manually, run:"
    echo "  git add ."
    echo "  git commit -m 'Your message'"
    echo "  git push origin main"
fi
