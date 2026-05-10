#!/usr/bin/env bash
# =============================================================================
# OpenFang — Startup & Management Script
#
# Usage:
#   ./openfang/setup.sh start          # Validate, build, start (default)
#   ./openfang/setup.sh stop           # Stop all containers
#   ./openfang/setup.sh restart        # Stop + start
#   ./openfang/setup.sh rebuild        # Stop + rebuild + start
#   ./openfang/setup.sh logs           # Follow logs from both containers
#   ./openfang/setup.sh status         # Show container status + health
#   ./openfang/setup.sh diagnose       # Run scheduler diagnostics
#   ./openfang/setup.sh cron           # List registered cron jobs
#   ./openfang/setup.sh workflows      # List registered workflows
#   ./openfang/setup.sh trigger <name> # Manually trigger a cron job by name
#
# Run from repo root: ./openfang/setup.sh
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="${ROOT_DIR}/openfang/docker-compose.yaml"
ENV_FILE="${ROOT_DIR}/.env"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# ── Helpers ───────────────────────────────────────────────────────────────────
compose() {
  docker compose -f "${COMPOSE}" "$@"
}

check_docker() {
  if ! command -v docker &>/dev/null; then
    log_error "docker not found. Install Docker first."
    exit 1
  fi
  if ! docker info &>/dev/null; then
    log_error "Docker daemon not running. Start Docker and try again."
    exit 1
  fi
}

# ── Validation ────────────────────────────────────────────────────────────────
validate_env() {
  log_step "Validating .env"

  if [ ! -f "${ENV_FILE}" ]; then
    log_error ".env not found. Run: cp .env.example .env"
    exit 1
  fi

  set -a; source "${ENV_FILE}"; set +a

  errors=0
  warnings=0

  check_required() {
    local var="$1" hint="$2"
    if [ -z "${!var:-}" ]; then
      log_error "MISSING: ${var} — ${hint}"
      errors=$((errors + 1))
    else
      log_ok "${var}"
    fi
  }

  check_optional() {
    local var="$1" hint="$2"
    if [ -z "${!var:-}" ]; then
      log_warn "MISSING: ${var} — ${hint}"
      warnings=$((warnings + 1))
    else
      log_ok "${var}"
    fi
  }

  log_info "Required variables:"
  check_required OLLAMA_MODEL       "run ./list-models.sh to see available models"
  check_required DISCORD_BOT_TOKEN  "discord.com/developers -> New App -> Bot -> Copy Token"
  check_required DISCORD_WEBHOOK_URL "Discord Server Settings -> Integrations -> Webhooks"
  check_required SCHEDULER_WEBHOOK_TOKEN "openssl rand -hex 16"

  log_info "Optional variables:"
  check_optional SCHEDULER_AGENT_ID "auto-detected on first run (set via .env after)"
  check_optional TIMEZONE "defaults to UTC"
  check_optional SCHEDULER_HTTP_PORT "defaults to 8080"
  check_optional OPENFANG_API_KEY "recommended if exposing port 4200 externally"

  if [ "${errors}" -gt 0 ]; then
    echo ""
    log_error "${errors} required variable(s) missing. Fix them and re-run."
    exit 1
  fi

  if [ "${warnings}" -gt 0 ]; then
    log_warn "${warnings} optional variable(s) missing. Service will start with defaults."
  fi
}

# ── Commands ──────────────────────────────────────────────────────────────────
cmd_start() {
  check_docker
  validate_env

  log_step "Starting OpenFang"
  log_info "Model: ${OLLAMA_MODEL}"
  log_info "Timezone: ${TIMEZONE:-UTC}"

  compose up -d --build

  echo ""
  log_info "Waiting for OpenFang to become healthy..."
  local retries=0
  local max_retries=30
  while [ $retries -lt $max_retries ]; do
    if curl -sf http://localhost:4200/api/health &>/dev/null; then
      log_ok "OpenFang API is healthy"
      break
    fi
    retries=$((retries + 1))
    sleep 2
  done

  if [ $retries -eq $max_retries ]; then
    log_warn "OpenFang did not become healthy within $((max_retries * 2))s"
    log_info "Check logs: docker logs openfang"
  fi

  echo ""
  log_ok "OpenFang started successfully"
  echo ""
  log_info "Dashboard:  http://localhost:4200"
  log_info "Logs:       docker logs -f openfang"
  log_info "Scheduler:  docker logs -f openfang-scheduler"
  log_info "Diagnose:   $0 diagnose"
}

cmd_stop() {
  check_docker
  log_step "Stopping OpenFang"
  compose down
  log_ok "Stopped"
}

cmd_restart() {
  check_docker
  log_step "Restarting OpenFang"
  compose restart
  log_ok "Restarted"
}

cmd_rebuild() {
  check_docker
  validate_env
  log_step "Rebuilding OpenFang"
  compose down
  compose up -d --build
  log_ok "Rebuilt and started"
}

cmd_logs() {
  check_docker
  log_step "Following logs (Ctrl+C to exit)"
  compose logs -f --tail=100
}

cmd_status() {
  check_docker
  log_step "OpenFang Status"

  echo ""
  log_info "Containers:"
  compose ps

  echo ""
  log_info "OpenFang API health:"
  if curl -sf http://localhost:4200/api/health &>/dev/null; then
    log_ok "Healthy (http://localhost:4200)"
  else
    log_error "Not responding"
  fi

  echo ""
  log_info "Scheduler webhook relay:"
  if curl -sf http://localhost:${SCHEDULER_HTTP_PORT:-8080}/healthz &>/dev/null; then
    log_ok "Healthy (port ${SCHEDULER_HTTP_PORT:-8080})"
  else
    log_warn "Not responding (may still be starting)"
  fi

  echo ""
  log_info "Registered workflows:"
  curl -sf http://localhost:4200/api/workflows 2>/dev/null | python3 -c "
import json, sys
try:
    wfs = json.load(sys.stdin)
    print(f'  {len(wfs)} workflows registered')
    for wf in wfs[:5]:
        print(f'  - {wf.get(\"name\", \"?\")}')
    if len(wfs) > 5:
        print(f'  ... and {len(wfs) - 5} more')
except:
    print('  (could not fetch)')
" 2>/dev/null || log_warn "  (could not fetch)"

  echo ""
  log_info "Cron jobs:"
  curl -sf http://localhost:4200/api/cron/jobs 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])
    wf_jobs = [j for j in jobs if j.get('name', '').startswith('WF-')]
    print(f'  {len(jobs)} total jobs, {len(wf_jobs)} scheduler-managed')
    for job in wf_jobs[:5]:
        status = 'enabled' if job.get('enabled') else 'disabled'
        print(f'  - {job[\"name\"]} ({job.get(\"schedule\", {}).get(\"expr\", \"?\")}) [{status}]')
    if len(wf_jobs) > 5:
        print(f'  ... and {len(wf_jobs) - 5} more')
except:
    print('  (could not fetch)')
" 2>/dev/null || log_warn "  (could not fetch)"
}

cmd_diagnose() {
  check_docker
  log_step "Running diagnostics"
  docker exec openfang-scheduler sh /scheduler/diagnose.sh 2>/dev/null || {
    log_error "Could not run diagnostics in scheduler container"
    log_info "Is the scheduler running? Check: docker ps"
  }
}

cmd_cron() {
  check_docker
  log_step "Cron Jobs"
  curl -sf http://localhost:4200/api/cron/jobs 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])
    if not jobs:
        print('  No cron jobs registered')
        sys.exit(0)
    for job in jobs:
        status = 'ON' if job.get('enabled') else 'OFF'
        last = job.get('last_run', 'never')
        runs = job.get('run_count', 0)
        name = job.get('name', '?')
        expr = job.get('schedule', {}).get('expr', '?')
        action = job.get('action', {}).get('kind', '?')
        print(f'  [{status}] {name}')
        print(f'         schedule: {expr}')
        print(f'         action:   {action}')
        print(f'         last_run: {last} (total: {runs})')
        print()
except Exception as e:
    print(f'  Error: {e}')
" 2>/dev/null || log_error "Could not fetch cron jobs"
}

cmd_workflows() {
  check_docker
  log_step "Registered Workflows"
  curl -sf http://localhost:4200/api/workflows 2>/dev/null | python3 -c "
import json, sys
try:
    wfs = json.load(sys.stdin)
    if not wfs:
        print('  No workflows registered')
        sys.exit(0)
    for wf in wfs:
        steps = len(wf.get('steps', []))
        desc = wf.get('description', '')[:60]
        print(f'  {wf[\"name\"]}')
        print(f'    steps: {steps}  |  {desc}')
        print()
except Exception as e:
    print(f'  Error: {e}')
" 2>/dev/null || log_error "Could not fetch workflows"
}

cmd_trigger() {
  check_docker
  if [ $# -lt 1 ]; then
    log_error "Usage: $0 trigger <job-name>"
    echo ""
    log_info "Available jobs:"
    cmd_cron
    exit 1
  fi

  local job_name="$1"
  log_step "Triggering workflow for: ${job_name}"

  # Look up the cron job, extract the workflow_id from its action
  local workflow_id
  workflow_id=$(curl -sf http://localhost:4200/api/cron/jobs 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for job in data.get('jobs', []):
    if job.get('name') == '${job_name}':
        wf_id = job.get('action', {}).get('workflow_id', '')
        if wf_id:
            print(wf_id)
            sys.exit(0)
        print('NO_WORKFLOW_ID')
        sys.exit(0)
print('NOT_FOUND')
" 2>/dev/null)

  if [ "$workflow_id" = "NOT_FOUND" ] || [ -z "$workflow_id" ]; then
    log_error "Job '${job_name}' not found"
    cmd_cron
    exit 1
  fi

  if [ "$workflow_id" = "NO_WORKFLOW_ID" ]; then
    log_error "Job '${job_name}' has no workflow_id attached"
    exit 1
  fi

  log_info "Workflow ID: ${workflow_id}"
  log_info "Triggering..."

  local response
  response=$(curl -s -X POST "http://localhost:4200/api/workflows/${workflow_id}/run" \
    -H "Content-Type: application/json" \
    -d '{"input": "Manual trigger"}' 2>/dev/null)

  if [ $? -eq 0 ]; then
    log_ok "Workflow triggered successfully"
    echo "$response" | python3 -m json.tool 2>/dev/null || echo "$response"
  else
    log_error "Failed to trigger workflow"
    echo "$response"
  fi
}

cmd_help() {
  echo "OpenFang Management Script"
  echo ""
  echo "Usage: $0 <command>"
  echo ""
  echo "Commands:"
  echo "  start        Validate config, build, and start (default)"
  echo "  stop         Stop all containers"
  echo "  restart      Restart containers without rebuild"
  echo "  rebuild      Stop, rebuild, and start"
  echo "  logs         Follow logs from both containers"
  echo "  status       Show container status + health + summary"
  echo "  diagnose     Run scheduler diagnostics"
  echo "  cron         List all registered cron jobs"
  echo "  workflows    List all registered workflows"
  echo "  trigger <n>  Manually trigger a cron job by name"
  echo "  help         Show this help"
}

# ── Main ──────────────────────────────────────────────────────────────────────
COMMAND="${1:-start}"
shift || true

case "$COMMAND" in
  start)     cmd_start ;;
  stop)      cmd_stop ;;
  restart)   cmd_restart ;;
  rebuild)   cmd_rebuild ;;
  logs)      cmd_logs ;;
  status)    cmd_status ;;
  diagnose)  cmd_diagnose ;;
  cron)      cmd_cron ;;
  workflows) cmd_workflows ;;
  trigger)   cmd_trigger "$@" ;;
  help|--help|-h) cmd_help ;;
  *)
    log_error "Unknown command: $COMMAND"
    cmd_help
    exit 1
    ;;
esac
