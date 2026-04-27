#!/bin/bash
# Quick test script - trigger n8n test workflow

echo "=========================================="
echo "Testing n8n Setup"
echo "=========================================="
echo ""

# Check if n8n is running
echo "1. Checking n8n container status..."
if docker ps | grep -q n8n; then
    echo "   ✓ n8n is running"
else
    echo "   ✗ n8n is not running. Start it with:"
    echo "     docker compose -f n8n-compose.yaml up -d"
    exit 1
fi

echo ""
echo "2. Checking workflow import status..."
docker logs n8n | grep -E "(Importing|Imported:|workflow\(s\))" | tail -10

echo ""
echo "=========================================="
echo "Manual Test Instructions"
echo "=========================================="
echo ""
echo "To trigger the test job:"
echo ""
echo "1. Open browser: http://$(hostname -I | awk '{print $1}'):5678"
echo ""
echo "2. Login with credentials from .env file"
echo ""
echo "3. In n8n interface:"
echo "   - Look for 'test' workflow in left sidebar"
echo "   - Click on 'test' to open it"
echo "   - Click 'Execute Workflow' button at bottom"
echo "   - Watch nodes turn green as they execute"
echo ""
echo "4. Check results:"
echo "   - Execution log shows output of each node"
echo "   - Check Discord for test message"
echo "   - If no webhook configured, check 'Log Skip' node output"
echo ""
echo "Alternative: Check if cron-test already ran:"
docker logs n8n | grep -i "cron-test" | tail -5

echo ""
echo "=========================================="
echo "View all executions:"
echo "   docker logs n8n | grep -i 'execution\|workflow'"
echo "=========================================="
