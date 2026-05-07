#!/usr/bin/env python3
"""
Simple OpenFang Scheduler - Reliable time-based workflow triggering
"""

import json
import os
import sys
import time
import subprocess
from datetime import datetime
from pathlib import Path

# Configuration
API_URL = os.environ.get('OPENFANG_API_URL', 'http://openfang:4200')
WEBHOOK_URL = os.environ.get('DISCORD_WEBHOOK_URL', '')
CHECK_INTERVAL = 30  # seconds

# Schedule: hour:minute -> (workflow_file, bot_name, color)
SCHEDULE = {
    "06:00": ("world-news.json", "🌍 World News Bot", "3447003"),
    "06:30": ("global-news.json", "🌐 Global News Bot", "15158332"),
    "07:00": ("americas-news.json", "🌎 Americas News Bot", "3066993"),
    "07:30": ("europe-news.json", "🇪🇺 Europe News Bot", "3447003"),
    "08:00": ("asia-pacific-news.json", "🌏 Asia-Pacific News Bot", "15105570"),
    "08:30": ("market-brief.json", "📈 Market Brief Bot", "5763719"),
    "09:00": ("tech-digest.json", "💻 Tech Digest Bot", "5814783"),
    "09:30": ("coding-tech-ai.json", "👨‍💻 Dev Digest Bot", "3447003"),
    "10:00": ("hacker-news-digest.json", "🟠 HN Digest Bot", "16744192"),
    "11:00": ("github-trending.json", "🚀 GitHub Trends Bot", "3066993"),
    "12:00": ("geopolitical-perspectives.json", "🌐 Geopol Intel Bot", "7419530"),
    "16:00": ("investing-intelligence.json", "💹 Investing Intel Bot", "16776960"),
    "16:56": ("hacker-news-digest.json", "🧪 TEST Bot", "16744192"),  # TEST JOB - updated time
}

def log(msg):
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] {msg}", flush=True)

def register_workflow(workflow_file):
    """Register a workflow and return its ID"""
    workflow_path = f"/workflows/{workflow_file}"
    
    if not os.path.exists(workflow_path):
        log(f"ERROR: Workflow file not found: {workflow_path}")
        return None
    
    # Get workflow name from file
    try:
        with open(workflow_path) as f:
            data = json.load(f)
            name = data.get('name', 'unknown')
    except Exception as e:
        log(f"ERROR: Failed to parse {workflow_file}: {e}")
        return None
    
    # Check if already registered
    try:
        result = subprocess.run(
            ['curl', '-sf', f'{API_URL}/api/workflows'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            workflows = json.loads(result.stdout)
            for wf in workflows:
                if wf.get('name') == name:
                    log(f"  {name}: {wf['id'][:12]}... (existing)")
                    return wf['id']
    except Exception as e:
        log(f"  Warning: Could not check existing workflows: {e}")
    
    # Register new workflow
    try:
        result = subprocess.run(
            ['curl', '-sf', '-X', 'POST', f'{API_URL}/api/workflows',
             '-H', 'Content-Type: application/json',
             '-d', f'@{workflow_path}'],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            response = json.loads(result.stdout)
            wf_id = response.get('id')
            if wf_id:
                log(f"  {name}: {wf_id[:12]}... (registered)")
                return wf_id
        log(f"  {name}: FAILED to register")
        return None
    except Exception as e:
        log(f"  {name}: ERROR - {e}")
        return None

def run_workflow(workflow_id, bot_name, color):
    """Execute a workflow and send to Discord"""
    if not WEBHOOK_URL:
        log(f"  ERROR: No DISCORD_WEBHOOK_URL set")
        return False
    
    log(f"  Executing workflow...")
    
    # Call OpenFang API to run workflow
    today = datetime.now().strftime('%Y-%m-%d %H:%M %Z')
    payload = json.dumps({"input": today})
    
    try:
        result = subprocess.run(
            ['curl', '-s', '-X', 'POST', 
             f'{API_URL}/api/workflows/{workflow_id}/run',
             '-H', 'Content-Type: application/json',
             '-d', payload],
            capture_output=True, text=True, timeout=300
        )
        
        if result.returncode != 0:
            log(f"  ERROR: API call failed: {result.stderr[:200]}")
            return False
        
        response = json.loads(result.stdout)
        output = response.get('output') or response.get('result')
        
        if not output:
            log(f"  ERROR: No output from workflow")
            return False
        
        log(f"  Output: {len(output)} chars")
        
        # Send to Discord
        discord_payload = {
            "username": bot_name,
            "embeds": [{"description": output, "color": int(color)}]
        }
        
        discord_result = subprocess.run(
            ['curl', '-s', '-X', 'POST', WEBHOOK_URL,
             '-H', 'Content-Type: application/json',
             '-d', json.dumps(discord_payload)],
            capture_output=True, text=True, timeout=30
        )
        
        if discord_result.returncode == 0:
            log(f"  ✓ Discord message sent")
            return True
        else:
            log(f"  ✗ Discord failed: {discord_result.stderr[:200]}")
            return False
            
    except Exception as e:
        log(f"  ERROR: {e}")
        return False

def main():
    log("=" * 50)
    log("OpenFang Simple Scheduler Starting")
    log("=" * 50)
    log(f"API: {API_URL}")
    log(f"Webhook: {'YES' if WEBHOOK_URL else 'NO - set DISCORD_WEBHOOK_URL!'}")
    log(f"Check interval: {CHECK_INTERVAL}s")
    log("")
    
    # Wait for OpenFang
    log("Waiting for OpenFang API...")
    for i in range(30):
        try:
            result = subprocess.run(
                ['curl', '-sf', f'{API_URL}/api/health'],
                capture_output=True, timeout=5
            )
            if result.returncode == 0:
                log("OpenFang is ready!")
                break
        except:
            pass
        time.sleep(3)
    else:
        log("ERROR: OpenFang not available after 90s")
        sys.exit(1)
    
    # Register all workflows in schedule
    log("")
    log("Registering workflows...")
    workflow_ids = {}
    
    unique_workflows = set()
    for time_str, (wf_file, _, _) in SCHEDULE.items():
        unique_workflows.add(wf_file)
    
    for wf_file in unique_workflows:
        wf_id = register_workflow(wf_file)
        if wf_id:
            workflow_ids[wf_file] = wf_id
    
    log("")
    log(f"Registered {len(workflow_ids)} workflows")
    log("")
    log("Schedule:")
    for time_str in sorted(SCHEDULE.keys()):
        wf_file, bot_name, _ = SCHEDULE[time_str]
        status = "✓" if wf_file in workflow_ids else "✗"
        test_mark = " [TEST]" if "TEST" in bot_name else ""
        log(f"  {time_str} - {bot_name}{test_mark} {status}")
    log("")
    log(f"Next: TEST JOB at 16:56 (in ~{max(0, (16*60+56) - (datetime.now().hour*60 + datetime.now().minute))} minutes)")
    
    # Main loop
    log("Starting scheduler loop...")
    log("=" * 50)
    
    last_triggered = None
    
    while True:
        now = datetime.now()
        current_time = now.strftime('%H:%M')
        
        # Only trigger once per minute
        if current_time != last_triggered:
            last_triggered = current_time
            
            if current_time in SCHEDULE:
                wf_file, bot_name, color = SCHEDULE[current_time]
                
                log("")
                log(f"⏰ {current_time} - TRIGGERING: {bot_name}")
                
                if wf_file in workflow_ids:
                    run_workflow(workflow_ids[wf_file], bot_name, color)
                else:
                    log(f"  ERROR: Workflow not registered: {wf_file}")
                log("")
        
        time.sleep(CHECK_INTERVAL)

if __name__ == '__main__':
    main()
