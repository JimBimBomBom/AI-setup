#!/usr/bin/env python3
"""
Simple OpenFang Scheduler - Reliable time-based workflow triggering
"""

import json
import os
import sys
import time
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

# Configuration
API_URL = os.environ.get('OPENFANG_API_URL', 'http://openfang:4200')
WEBHOOK_URL = os.environ.get('DISCORD_WEBHOOK_URL', '')
CHECK_INTERVAL = 30  # seconds
SCHEDULE_PATH = Path(os.environ.get('SCHEDULER_CONFIG', '/scheduler/schedule.json'))

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

def load_schedule():
    """Load schedule definitions from JSON config"""
    if not SCHEDULE_PATH.exists():
        log(f"ERROR: Schedule file not found: {SCHEDULE_PATH}")
        sys.exit(1)

    try:
        raw = json.loads(SCHEDULE_PATH.read_text())
    except Exception as exc:
        log(f"ERROR: Failed to read schedule config: {exc}")
        sys.exit(1)

    if not isinstance(raw, list):
        log("ERROR: Schedule config must be a list of jobs")
        sys.exit(1)

    schedule_entries = []
    for idx, entry in enumerate(raw, start=1):
        if not isinstance(entry, dict):
            log(f"ERROR: Schedule entry #{idx} is not an object")
            sys.exit(1)

        time_raw = entry.get('time')
        time_str = str(time_raw).strip() if time_raw is not None else ''
        workflow_file = entry.get('workflow') or entry.get('workflow_file')
        bot_name = entry.get('bot_name') or Path(str(workflow_file or 'workflow.json')).stem
        color_value = entry.get('color', 3447003)
        delay_raw = entry.get('delay_seconds')
        delay_seconds = None

        if time_str:
            try:
                datetime.strptime(time_str, '%H:%M')
            except Exception:
                log(f"ERROR: Invalid time format in schedule entry #{idx}: '{time_str}' (expected HH:MM)")
                sys.exit(1)
        elif delay_raw is not None:
            try:
                delay_seconds = int(delay_raw)
                if delay_seconds < 0:
                    raise ValueError
            except Exception:
                log(f"ERROR: Schedule entry #{idx} has invalid delay_seconds '{delay_raw}'")
                sys.exit(1)
        else:
            log(f"ERROR: Schedule entry #{idx} must include either 'time' or 'delay_seconds'")
            sys.exit(1)

        if not workflow_file:
            log(f"ERROR: Schedule entry #{idx} missing 'workflow' field")
            sys.exit(1)

        try:
            color_int = int(color_value)
        except Exception:
            log(f"ERROR: Schedule entry #{idx} has invalid color '{color_value}'")
            sys.exit(1)

        schedule_entries.append({
            'time': time_str if time_str else None,
            'delay_seconds': delay_seconds,
            'workflow': str(workflow_file),
            'bot_name': str(bot_name),
            'color': color_int
        })
        if time_str:
            log(f"  Loaded job #{idx}: {time_str} -> {bot_name} ({workflow_file})")
        else:
            log(f"  Loaded job #{idx}: +{delay_seconds}s -> {bot_name} ({workflow_file})")

    return schedule_entries

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
    log(f"Schedule config: {SCHEDULE_PATH}")
    log("")

    schedule_entries = load_schedule()
    if not schedule_entries:
        log("ERROR: Schedule config is empty")
        sys.exit(1)

    if not schedule_entries:
        log("ERROR: Schedule config is empty")
        sys.exit(1)

    schedule_by_time = {}
    delayed_jobs = []
    for job in schedule_entries:
        if job['time']:
            schedule_by_time.setdefault(job['time'], []).append(job)
        elif job['delay_seconds'] is not None:
            delayed_jobs.append({'job': job, 'triggered': False})
    
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
    
    unique_workflows = {job['workflow'] for job in schedule_entries}
    
    for wf_file in unique_workflows:
        wf_id = register_workflow(wf_file)
        if wf_id:
            workflow_ids[wf_file] = wf_id
    
    log("")
    log(f"Registered {len(workflow_ids)} workflows")
    log("")
    log("Schedule:")
    for time_str in sorted(schedule_by_time.keys()):
        for job in schedule_by_time[time_str]:
            wf_file = job['workflow']
            bot_name = job['bot_name']
            status = "✓" if wf_file in workflow_ids else "✗"
            log(f"  {time_str} - {bot_name} ({wf_file}) {status}")
    for delayed in delayed_jobs:
        job = delayed['job']
        wf_file = job['workflow']
        bot_name = job['bot_name']
        status = "✓" if wf_file in workflow_ids else "✗"
        log(f"  +{job['delay_seconds']}s - {bot_name} ({wf_file}) {status}")
    
    # Main loop
    log("Starting scheduler loop...")
    log("=" * 50)
    
    last_minute = None
    start_time = datetime.now()
    
    while True:
        now = datetime.now()
        current_time = now.strftime('%H:%M')
        
        # Only trigger once per minute
        if current_time != last_minute:
            last_minute = current_time
            jobs = schedule_by_time.get(current_time, [])

            for job in jobs:
                wf_file = job['workflow']
                bot_name = job['bot_name']
                color = job['color']

                log("")
                log(f"⏰ {current_time} - TRIGGERING: {bot_name}")

                if wf_file in workflow_ids:
                    run_workflow(workflow_ids[wf_file], bot_name, color)
                else:
                    log(f"  ERROR: Workflow not registered: {wf_file}")
                log("")

        for delayed in delayed_jobs:
            if delayed['triggered']:
                continue
            job = delayed['job']
            target_time = start_time + timedelta(seconds=job['delay_seconds'])
            if datetime.now() >= target_time:
                wf_file = job['workflow']
                bot_name = job['bot_name']
                color = job['color']

                log("")
                log(f"⏰ +{job['delay_seconds']}s - TRIGGERING: {bot_name}")

                if wf_file in workflow_ids:
                    run_workflow(workflow_ids[wf_file], bot_name, color)
                else:
                    log(f"  ERROR: Workflow not registered: {wf_file}")
                log("")
                delayed['triggered'] = True

        time.sleep(CHECK_INTERVAL)

if __name__ == '__main__':
    main()
