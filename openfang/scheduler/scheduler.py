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
ENABLE_NATIVE_SCHEDULES = os.environ.get('ENABLE_NATIVE_SCHEDULES', '1').lower() not in ('0', 'false', 'no')
ENABLE_LEGACY_LOOP = os.environ.get('ENABLE_LEGACY_LOOP', '0').lower() in ('1', 'true', 'yes')

def log(msg):
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] {msg}", flush=True)

def register_workflow(workflow_file):
    """Register a workflow and return metadata"""
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
                    return {'id': wf['id'], 'name': name}
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
                return {'id': wf_id, 'name': name}
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

def cron_from_time(time_str):
    hour, minute = time_str.split(':')
    return f"{int(minute)} {int(hour)} * * *"

def list_existing_schedules():
    try:
        result = subprocess.run(
            ['curl', '-sf', f'{API_URL}/api/schedules?limit=1000'],
            capture_output=True, text=True, timeout=15
        )
    except Exception as exc:
        log(f"  ERROR: Unable to query /api/schedules: {exc}")
        return None

    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip() or str(result.returncode)
        log(f"  ERROR: /api/schedules query failed: {stderr}")
        return None

    try:
        payload = json.loads(result.stdout or '[]')
        if isinstance(payload, dict) and 'schedules' in payload:
            return payload.get('schedules', [])
        if isinstance(payload, list):
            return payload
        return []
    except Exception as exc:
        log(f"  ERROR: Unable to parse /api/schedules response: {exc}")
        return None

def sync_native_schedules(schedule_entries, workflow_records):
    log("")
    log("Syncing schedules with OpenFang native cron...")

    schedule_list = list_existing_schedules()
    if schedule_list is None:
        log("  Skipping native sync (failed to fetch existing schedules)")
        return False

    existing_by_name = {}
    for item in schedule_list:
        name = item.get('name')
        if name:
            existing_by_name[name] = item

    created = updated = skipped = 0
    success = True

    for job in schedule_entries:
        if not job['time']:
            continue  # delay-only jobs rely on legacy loop

        wf_file = job['workflow']
        info = workflow_records.get(wf_file)
        if not info:
            log(f"  WARN: Workflow not registered for {wf_file}, skipping schedule import")
            skipped += 1
            success = False
            continue

        schedule_name = job.get('schedule_name') or f"{info['name']}-{job['time'].replace(':', '')}"
        cron_expr = cron_from_time(job['time'])
        input_text = job.get('input') or f"Automated run for {info['name']} at {job['time']} UTC"
        timeout_secs = int(job.get('timeout_secs', 300))

        delivery_targets = job.get('delivery_targets')
        if delivery_targets is None and WEBHOOK_URL:
            delivery_targets = [{"type": "webhook", "url": WEBHOOK_URL}]

        payload = {
            "name": schedule_name,
            "cron": cron_expr,
            "enabled": job.get('enabled', True),
            "action": {
                "kind": "workflow_run",
                "workflow_id": info['id'],
                "workflow_name": info['name'],
                "input": input_text,
                "timeout_secs": timeout_secs
            },
            "delivery_targets": delivery_targets or []
        }

        if schedule_name in existing_by_name:
            sched_id = existing_by_name[schedule_name].get('id')
            if not sched_id:
                log(f"  WARN: Existing schedule '{schedule_name}' missing ID, skipping update")
                skipped += 1
                success = False
                continue
            method = 'PUT'
            path = f"/api/schedules/{sched_id}"
        else:
            method = 'POST'
            path = '/api/schedules'

        try:
            result = subprocess.run(
                ['curl', '-sf', '-X', method, f'{API_URL}{path}',
                 '-H', 'Content-Type: application/json',
                 '-d', json.dumps(payload)],
                capture_output=True, text=True, timeout=20
            )
        except Exception as exc:
            log(f"  ERROR: Failed to sync {schedule_name}: {exc}")
            success = False
            continue

        if result.returncode != 0:
            stderr = result.stderr.strip() or result.stdout.strip() or str(result.returncode)
            log(f"  ERROR: {method} {path} failed for {schedule_name}: {stderr}")
            success = False
            continue

        if method == 'POST':
            created += 1
            log(f"  Created cron job: {schedule_name} ({cron_expr})")
        else:
            updated += 1
            log(f"  Updated cron job: {schedule_name} ({cron_expr})")

    total_time_jobs = sum(1 for job in schedule_entries if job['time'])
    if total_time_jobs == 0:
        log("  No time-based jobs defined; nothing to import")
    else:
        log(f"Native schedule sync summary: {created} created, {updated} updated, {skipped} skipped")

    return success

def idle_forever():
    log("Scheduler idle loop active (native schedules managed by OpenFang)")
    while True:
        time.sleep(3600)

def run_workflow(workflow_id, bot_name, color, job_input=None):
    """Execute a workflow and send to Discord"""
    if not WEBHOOK_URL:
        log(f"  ERROR: No DISCORD_WEBHOOK_URL set")
        return False
    
    log(f"  Executing workflow...")
    
    # Call OpenFang API to run workflow
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M %Z')
    if job_input:
        rendered_input = str(job_input).replace('{{timestamp}}', timestamp)
    else:
        rendered_input = timestamp
    payload = json.dumps({"input": rendered_input})
    
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
    workflow_records = {}
    
    unique_workflows = {job['workflow'] for job in schedule_entries}
    
    for wf_file in unique_workflows:
        info = register_workflow(wf_file)
        if info:
            workflow_records[wf_file] = info
    
    log("")
    log(f"Registered {len(workflow_records)} workflows")
    log("")
    log("Schedule:")
    for time_str in sorted(schedule_by_time.keys()):
        for job in schedule_by_time[time_str]:
            wf_file = job['workflow']
            bot_name = job['bot_name']
            status = "✓" if wf_file in workflow_records else "✗"
            log(f"  {time_str} - {bot_name} ({wf_file}) {status}")
    for delayed in delayed_jobs:
        job = delayed['job']
        wf_file = job['workflow']
        bot_name = job['bot_name']
        status = "✓" if wf_file in workflow_records else "✗"
        log(f"  +{job['delay_seconds']}s - {bot_name} ({wf_file}) {status}")

    native_synced = False
    if ENABLE_NATIVE_SCHEDULES:
        native_synced = sync_native_schedules(schedule_entries, workflow_records)
    else:
        log("Skipping native cron sync (ENABLE_NATIVE_SCHEDULES=0)")

    if native_synced:
        log("Native OpenFang cron schedules are active.")
        if not ENABLE_LEGACY_LOOP:
            log("Legacy loop disabled (ENABLE_LEGACY_LOOP=0). Handing control to OpenFang and idling...")
            idle_forever()
        else:
            log("ENABLE_LEGACY_LOOP=1 - will also run local loop as a fallback")
    else:
        log("Native cron sync unavailable; continuing with internal loop")
    
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

                if wf_file in workflow_records:
                    run_workflow(workflow_records[wf_file]['id'], bot_name, color, job.get('input'))
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

                if wf_file in workflow_records:
                    run_workflow(workflow_records[wf_file]['id'], bot_name, color, job.get('input'))
                else:
                    log(f"  ERROR: Workflow not registered: {wf_file}")
                log("")
                delayed['triggered'] = True

        time.sleep(CHECK_INTERVAL)

if __name__ == '__main__':
    main()
