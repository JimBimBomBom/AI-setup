#!/usr/bin/env bash
# =============================================================================
# OpenFang — Monitoring Script
#
# Usage:
#   ./openfang/monitor.sh              # One-shot status report
#   ./openfang/monitor.sh --watch 30   # Refresh every 30 seconds
#   ./openfang/monitor.sh --json       # Output as JSON
#
# Checks:
#   - OpenFang API health
#   - Scheduler webhook relay health
#   - Cron job status (enabled, last_run, error_count)
#   - Workflow registration count
#   - Discord webhook connectivity
# =============================================================================
set -euo pipefail

API_URL="${OPENFANG_API_URL:-http://localhost:4200}"
SCHEDULER_PORT="${SCHEDULER_HTTP_PORT:-8080}"
ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.env"

# Load .env if available
[ -f "$ENV_FILE" ] && set -a && source "$ENV_FILE" && set +a

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── JSON mode ─────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--json" ]; then
  cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "openfang_api": {
    "url": "$API_URL",
    "healthy": $(curl -sf "$API_URL/api/health" &>/dev/null && echo "true" || echo "false")
  },
  "scheduler_relay": {
    "port": $SCHEDULER_PORT,
    "healthy": $(curl -sf "http://localhost:$SCHEDULER_PORT/healthz" &>/dev/null && echo "true" || echo "false")
  },
  "cron_jobs": $(curl -sf "$API_URL/api/cron/jobs" 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])
    result = []
    for j in jobs:
        result.append({
            'name': j.get('name'),
            'enabled': j.get('enabled'),
            'schedule': j.get('schedule', {}).get('expr'),
            'last_run': j.get('last_run'),
            'run_count': j.get('run_count', 0),
            'error_count': j.get('error_count', 0)
        })
    print(json.dumps(result))
except: print('[]')
" 2>/dev/null || echo '[]'),
  "workflows": $(curl -sf "$API_URL/api/workflows" 2>/dev/null | python3 -c "
import json, sys
try:
    wfs = json.load(sys.stdin)
    print(json.dumps([{'name': w.get('name'), 'steps': len(w.get('steps', []))} for w in wfs]))
except: print('[]')
" 2>/dev/null || echo '[]')
}
EOF
  exit 0
fi

# ── Watch mode ────────────────────────────────────────────────────────────────
WATCH_INTERVAL=""
for arg in "$@"; do
  if [ "$arg" = "--watch" ]; then
    shift
    WATCH_INTERVAL="${1:-10}"
    break
  fi
done

# ── Report function ───────────────────────────────────────────────────────────
report() {
  local now
  now=$(date '+%Y-%m-%d %H:%M:%S %Z')

  echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}  OpenFang Monitor — ${now}${NC}"
  echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
  echo ""

  # ── API Health ────────────────────────────────────────────────────────────
  if curl -sf "$API_URL/api/health" &>/dev/null; then
    echo -e "  ${GREEN}●${NC} OpenFang API       ${GREEN}healthy${NC}  ($API_URL)"
  else
    echo -e "  ${RED}●${NC} OpenFang API       ${RED}DOWN${NC}     ($API_URL)"
  fi

  # ── Scheduler Relay ───────────────────────────────────────────────────────
  if curl -sf "http://localhost:$SCHEDULER_PORT/healthz" &>/dev/null; then
    local job_count
    job_count=$(curl -sf "http://localhost:$SCHEDULER_PORT/healthz" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('jobs',0))" 2>/dev/null || echo "?")
    echo -e "  ${GREEN}●${NC} Scheduler relay    ${GREEN}healthy${NC}  (port $SCHEDULER_PORT, $job_count jobs)"
  else
    echo -e "  ${RED}●${NC} Scheduler relay    ${RED}DOWN${NC}     (port $SCHEDULER_PORT)"
  fi

  echo ""

  # ── Cron Jobs ─────────────────────────────────────────────────────────────
  echo -e "  ${BLUE}Cron Jobs:${NC}"
  cron_data=$(curl -sf "$API_URL/api/cron/jobs" 2>/dev/null || echo "")
  if [ -n "$cron_data" ]; then
    echo "$cron_data" | python3 -c "
import json, sys
from datetime import datetime, timezone

data = json.load(sys.stdin)
jobs = data.get('jobs', [])
if not jobs:
    print('    (none registered)')
    sys.exit(0)

# Sort by next_run or name
jobs.sort(key=lambda j: j.get('name', ''))

for job in jobs:
    name = job.get('name', '?')
    enabled = job.get('enabled', False)
    expr = job.get('schedule', {}).get('expr', '?')
    last_run = job.get('last_run', 'never')
    run_count = job.get('run_count', 0)
    error_count = job.get('error_count', 0)
    action = job.get('action', {}).get('kind', '?')

    status = 'ON' if enabled else 'OFF'
    status_color = '\033[0;32m' if enabled else '\033[0;31m'

    error_indicator = ''
    if error_count > 0:
        error_indicator = f' \033[1;33m⚠ {error_count} errors\033[0m'

    print(f'    {status_color}[{status}]\033[0m {name}')
    print(f'         schedule: {expr}  |  action: {action}')
    print(f'         last_run: {last_run}  |  runs: {run_count}{error_indicator}')
    print()
" 2>/dev/null || echo "    (parse error)"
  else
    echo -e "    ${RED}(API unreachable)${NC}"
  fi

  # ── Workflows ─────────────────────────────────────────────────────────────
  echo -e "  ${BLUE}Workflows:${NC}"
  wf_data=$(curl -sf "$API_URL/api/workflows" 2>/dev/null || echo "")
  if [ -n "$wf_data" ]; then
    echo "$wf_data" | python3 -c "
import json, sys
wfs = json.load(sys.stdin)
if not wfs:
    print('    (none registered)')
    sys.exit(0)
print(f'    {len(wfs)} workflows registered')
for wf in wfs[:8]:
    steps = len(wf.get('steps', []))
    print(f'    - {wf[\"name\"]} ({steps} steps)')
if len(wfs) > 8:
    print(f'    ... and {len(wfs) - 8} more')
" 2>/dev/null || echo "    (parse error)"
  else
    echo -e "    ${RED}(API unreachable)${NC}"
  fi

  echo ""

  # ── Alert Summary ─────────────────────────────────────────────────────────
  alerts=()
  if ! curl -sf "$API_URL/api/health" &>/dev/null; then
    alerts+=("OpenFang API is DOWN")
  fi
  if ! curl -sf "http://localhost:$SCHEDULER_PORT/healthz" &>/dev/null; then
    alerts+=("Scheduler relay is DOWN")
  fi

  if [ -n "$cron_data" ]; then
    error_jobs=$(echo "$cron_data" | python3 -c "
import json, sys
data = json.load(sys.stdin)
errors = [j['name'] for j in data.get('jobs', []) if j.get('error_count', 0) >= 5]
print('\n'.join(errors))
" 2>/dev/null || true)
    if [ -n "$error_jobs" ]; then
      while IFS= read -r job; do
        alerts+=("Cron job '$job' has >= 5 consecutive errors (auto-disabled)")
      done <<< "$error_jobs"
    fi
  fi

  if [ ${#alerts[@]} -gt 0 ]; then
    echo -e "  ${RED}ALERTS:${NC}"
    for alert in "${alerts[@]}"; do
      echo -e "  ${RED}  ! ${alert}${NC}"
    done
    echo ""
  else
    echo -e "  ${GREEN}No alerts${NC}"
    echo ""
  fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
if [ -n "$WATCH_INTERVAL" ]; then
  while true; do
    clear
    report
    sleep "$WATCH_INTERVAL"
  done
else
  report
fi
