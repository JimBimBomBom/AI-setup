#!/usr/bin/env python3
"""OpenFang workflow scheduler — native cron importer + Discord relay."""

import argparse
import copy
import json
import logging
import os
import signal
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Dict, List, Optional

import requests


API_URL = os.environ.get("OPENFANG_API_URL", "http://openfang:4200").rstrip("/")
SCHEDULE_PATH = Path(os.environ.get("SCHEDULER_CONFIG", "/scheduler/schedule.json"))
WORKFLOW_DIR = Path("/workflows")
TIMEZONE = os.environ.get("TIMEZONE", "UTC")
DISCORD_WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL", "")
HTTP_PORT = int(os.environ.get("SCHEDULER_HTTP_PORT", "9090"))
WEBHOOK_BASE_URL = os.environ.get(
    "SCHEDULER_WEBHOOK_URL", f"http://openfang-scheduler:{HTTP_PORT}/hook"
)
WEBHOOK_TOKEN = os.environ.get("SCHEDULER_WEBHOOK_TOKEN", "").strip()
AGENT_ID_OVERRIDE = os.environ.get("SCHEDULER_AGENT_ID", "").strip()
AGENT_NAME_HINT = os.environ.get("SCHEDULER_AGENT_NAME", "").strip()
JOB_PREFIX = os.environ.get("SCHEDULER_JOB_PREFIX", "WF-").strip() or "WF-"
HTTP_TIMEOUT = float(os.environ.get("SCHEDULER_HTTP_TIMEOUT", "15"))
DEFAULT_TIMEOUT = int(os.environ.get("SCHEDULER_WORKFLOW_TIMEOUT", "420"))


logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
LOG = logging.getLogger("openfang-scheduler")


# ── Metrics ──────────────────────────────────────────────────────────────────
class Metrics:
    """Thread-safe delivery metrics."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.deliveries_total = 0
        self.deliveries_failed = 0
        self.discord_posts_total = 0
        self.discord_posts_failed = 0
        self.last_delivery_time: Optional[str] = None
        self.last_delivery_job: Optional[str] = None
        self.start_time = time.time()

    def record_delivery(self, job_name: str, success: bool) -> None:
        with self._lock:
            self.deliveries_total += 1
            if not success:
                self.deliveries_failed += 1
            self.last_delivery_time = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            self.last_delivery_job = job_name

    def record_discord(self, success: bool) -> None:
        with self._lock:
            self.discord_posts_total += 1
            if not success:
                self.discord_posts_failed += 1

    def render_prometheus(self, jobs: Dict[str, dict]) -> str:
        with self._lock:
            uptime = time.time() - self.start_time
            lines = [
                "# HELP openfang_scheduler_uptime_seconds Scheduler uptime",
                "# TYPE openfang_scheduler_uptime_seconds counter",
                f"openfang_scheduler_uptime_seconds {uptime:.0f}",
                "# HELP openfang_scheduler_deliveries_total Total webhook deliveries received",
                "# TYPE openfang_scheduler_deliveries_total counter",
                f"openfang_scheduler_deliveries_total {self.deliveries_total}",
                "# HELP openfang_scheduler_deliveries_failed Failed webhook deliveries",
                "# TYPE openfang_scheduler_deliveries_failed counter",
                f"openfang_scheduler_deliveries_failed {self.deliveries_failed}",
                "# HELP openfang_scheduler_discord_posts_total Total Discord posts attempted",
                "# TYPE openfang_scheduler_discord_posts_total counter",
                f"openfang_scheduler_discord_posts_total {self.discord_posts_total}",
                "# HELP openfang_scheduler_discord_posts_failed Failed Discord posts",
                "# TYPE openfang_scheduler_discord_posts_failed counter",
                f"openfang_scheduler_discord_posts_failed {self.discord_posts_failed}",
                "# HELP openfang_scheduler_jobs_total Number of managed cron jobs",
                "# TYPE openfang_scheduler_jobs_total gauge",
                f"openfang_scheduler_jobs_total {len(jobs)}",
                "# HELP openfang_scheduler_jobs_enabled Number of enabled cron jobs",
                "# TYPE openfang_scheduler_jobs_enabled gauge",
                f"openfang_scheduler_jobs_enabled {sum(1 for j in jobs.values() if j.get('enabled', True))}",
            ]
            if self.last_delivery_time:
                lines.append("# HELP openfang_scheduler_last_delivery_timestamp Last delivery time")
                lines.append("# TYPE openfang_scheduler_last_delivery_timestamp gauge")
                # Approximate: just for visibility, not a real timestamp metric
                lines.append(f"# Last delivery: {self.last_delivery_job} at {self.last_delivery_time}")
            return "\n".join(lines) + "\n"


metrics = Metrics()


class ApiClient:
    """Thin wrapper around requests with consistent timeouts and logging."""

    def __init__(self) -> None:
        self.session = requests.Session()

    def request(self, method: str, path: str, **kwargs) -> requests.Response:
        url = f"{API_URL}{path}"
        timeout = kwargs.pop("timeout", HTTP_TIMEOUT)
        try:
            resp = self.session.request(method, url, timeout=timeout, **kwargs)
            return resp
        except requests.RequestException as exc:
            raise RuntimeError(f"HTTP {method} {url} failed: {exc}") from exc


class SchedulerConfigError(Exception):
    pass


def wait_for_openfang(api: ApiClient, retries: int = 30) -> None:
    LOG.info("Waiting for OpenFang at %s", API_URL)
    for attempt in range(1, retries + 1):
        try:
            resp = api.request("GET", "/api/health", timeout=5)
            if resp.ok:
                LOG.info("OpenFang is ready")
                return
        except RuntimeError:
            pass
        time.sleep(3)
        LOG.debug("  attempt %s/%s", attempt, retries)
    raise RuntimeError("OpenFang API did not become ready in time")


def load_schedule_entries() -> List[dict]:
    if not SCHEDULE_PATH.exists():
        raise SchedulerConfigError(f"Schedule file not found: {SCHEDULE_PATH}")
    try:
        raw = json.loads(SCHEDULE_PATH.read_text())
    except Exception as exc:  # pragma: no cover - config errors
        raise SchedulerConfigError(f"Failed to parse {SCHEDULE_PATH}: {exc}") from exc
    if not isinstance(raw, list) or not raw:
        raise SchedulerConfigError("Schedule config must be a non-empty list")
    return raw


def parse_time_to_cron(time_str: str) -> str:
    parts = time_str.split(":")
    if len(parts) != 2:
        raise SchedulerConfigError(f"Invalid HH:MM time: {time_str}")
    hour, minute = parts
    if not hour.isdigit() or not minute.isdigit():
        raise SchedulerConfigError(f"Invalid HH:MM time: {time_str}")
    h = int(hour)
    m = int(minute)
    if not (0 <= h <= 23 and 0 <= m <= 59):
        raise SchedulerConfigError(f"Invalid HH:MM time: {time_str}")
    return f"{m} {h} * * *"


def sanitize_job_name(raw: str) -> str:
    filtered = [c if (c.isalnum() or c in " -_") else "-" for c in raw]
    result = "".join(filtered).strip().replace(" ", "-")
    result = result or "schedule"
    return (JOB_PREFIX + result)[:120]


def chunk_output(text: str, limit: int = 3900) -> List[str]:
    if len(text) <= limit:
        return [text]
    chunks: List[str] = []
    current = []
    length = 0
    for line in text.splitlines():
        line_with_newline = line + "\n"
        if length + len(line_with_newline) > limit and current:
            chunks.append("".join(current).rstrip())
            current = []
            length = 0
        current.append(line_with_newline)
        length += len(line_with_newline)
    if current:
        chunks.append("".join(current).rstrip())
    return chunks or [text[:limit]]


def ensure_workflow_dir(file_name: str) -> Path:
    path = WORKFLOW_DIR / file_name
    if not path.exists():
        raise SchedulerConfigError(f"Workflow file not found: {path}")
    return path


class WorkflowRegistry:
    def __init__(self, api: ApiClient):
        self.api = api

    def list_workflows(self) -> Dict[str, dict]:
        resp = self.api.request("GET", "/api/workflows")
        if not resp.ok:
            raise RuntimeError(f"GET /api/workflows failed: {resp.text}")
        try:
            workflows = resp.json()
        except ValueError as exc:
            raise RuntimeError("Invalid /api/workflows response") from exc
        return {wf.get("name"): wf for wf in workflows}

    def ensure(self, workflow_file: str) -> dict:
        workflows = self.list_workflows()
        path = ensure_workflow_dir(workflow_file)
        data = json.loads(path.read_text())
        name = data.get("name")
        if not name:
            raise SchedulerConfigError(f"Workflow missing name: {workflow_file}")
        if name in workflows:
            LOG.info("  %s: %s (existing)", name, workflows[name]["id"][:12])
            return {"id": workflows[name]["id"], "name": name}
        resp = self.api.request("POST", "/api/workflows", json=data)
        if not resp.ok:
            raise RuntimeError(f"Register workflow failed: {resp.text}")
        wf_id = resp.json().get("workflow_id")
        LOG.info("  %s: %s (registered)", name, wf_id[:12])
        return {"id": wf_id, "name": name}


def list_agents(api: ApiClient) -> List[dict]:
    resp = api.request("GET", "/api/agents")
    if not resp.ok:
        raise RuntimeError(f"GET /api/agents failed: {resp.text}")
    try:
        agents = resp.json()
    except ValueError as exc:
        raise RuntimeError("Invalid /api/agents response") from exc
    return agents


def select_agent_id(api: ApiClient) -> str:
    agents = list_agents(api)
    if AGENT_ID_OVERRIDE:
        try:
            uuid.UUID(AGENT_ID_OVERRIDE)
        except ValueError as exc:  # pragma: no cover - config errors
            raise SchedulerConfigError(
                f"SCHEDULER_AGENT_ID is not a valid UUID: {AGENT_ID_OVERRIDE}"
            ) from exc
        LOG.info("Using agent %s from env SCHEDULER_AGENT_ID", AGENT_ID_OVERRIDE)
        return AGENT_ID_OVERRIDE
    if not agents:
        raise SchedulerConfigError(
            "No agents found. Create one via the OpenFang dashboard or CLI, "
            "then set SCHEDULER_AGENT_ID in .env."
        )
    if AGENT_NAME_HINT:
        for agent in agents:
            if agent.get("name") == AGENT_NAME_HINT:
                LOG.info(
                    "Using agent '%s' (%s) from SCHEDULER_AGENT_NAME",
                    AGENT_NAME_HINT,
                    agent.get("id"),
                )
                return agent.get("id")
    chosen = agents[0]
    LOG.info(
        "Using first available agent '%s' (%s). Set SCHEDULER_AGENT_ID to override.",
        chosen.get("name"),
        chosen.get("id"),
    )
    return chosen.get("id")


def fetch_cron_jobs(api: ApiClient) -> Dict[str, dict]:
    resp = api.request("GET", "/api/cron/jobs")
    if not resp.ok:
        raise RuntimeError(f"GET /api/cron/jobs failed: {resp.text}")
    payload = resp.json()
    jobs = payload.get("jobs", [])
    return {job.get("name"): job for job in jobs}


def delete_cron_job(api: ApiClient, job_id: str) -> None:
    resp = api.request("DELETE", f"/api/cron/jobs/{job_id}")
    if resp.status_code == 404:
        return
    if not resp.ok:
        raise RuntimeError(f"DELETE cron job failed: {resp.text}")


def jobs_equal(existing: dict, desired: dict) -> bool:
    if existing.get("agent_id") != desired.get("agent_id"):
        return False
    if existing.get("enabled", True) != desired.get("enabled", True):
        return False
    if existing.get("schedule") != desired.get("schedule"):
        return False
    existing_action = existing.get("action", {})
    desired_action = desired.get("action", {})
    if existing_action.get("kind") != desired_action.get("kind"):
        return False
    if existing_action.get("workflow_id") != desired_action.get("workflow_id"):
        return False
    if existing_action.get("input", "") != desired_action.get("input", ""):
        return False
    if existing_action.get("timeout_secs") != desired_action.get("timeout_secs"):
        return False
    if existing.get("delivery") != desired.get("delivery"):
        return False
    if existing.get("delivery_targets", []) != desired.get("delivery_targets", []):
        return False
    return True


def build_job_payload(entry: dict, workflow: dict, agent_id: str, webhook_url: str) -> dict:
    cron_expr = entry.get("cron") or parse_time_to_cron(entry.get("time", ""))
    tz = entry.get("tz") or TIMEZONE or None
    job_name = sanitize_job_name(entry.get("name") or f"{workflow['name']}-{entry.get('time','00:00')}")
    timeout = int(entry.get("timeout_secs") or DEFAULT_TIMEOUT)
    timeout = max(10, min(timeout, 3600))
    delivery_target = {
        "type": "webhook",
        "url": webhook_url,
    }
    if WEBHOOK_TOKEN:
        delivery_target["auth_header"] = f"Bearer {WEBHOOK_TOKEN}"

    payload = {
        "agent_id": agent_id,
        "name": job_name,
        "enabled": entry.get("enabled", True),
        "schedule": {"kind": "cron", "expr": cron_expr, "tz": tz},
        "action": {
            "kind": "workflow_run",
            "workflow_id": workflow["id"],
            "input": entry.get("input"),
            "timeout_secs": timeout,
        },
        "delivery_targets": [delivery_target],
    }
    return payload


def create_cron_job(api: ApiClient, payload: dict) -> str:
    resp = api.request("POST", "/api/cron/jobs", json=payload)
    if not resp.ok:
        raise RuntimeError(f"POST /api/cron/jobs failed: {resp.text}")
    result = resp.json().get("result")
    try:
        parsed = json.loads(result)
    except Exception:
        raise RuntimeError(f"Unexpected cron create response: {resp.text}")
    return parsed.get("job_id")


def build_job_configs(entries: List[dict], workflows: Dict[str, dict]) -> List[dict]:
    configs: List[dict] = []
    for raw in entries:
        workflow_file = raw.get("workflow")
        if not workflow_file:
            raise SchedulerConfigError("Each schedule entry must include 'workflow'")
        if workflow_file not in workflows:
            raise SchedulerConfigError(f"Workflow not registered: {workflow_file}")
        workflow_meta = workflows[workflow_file]
        payload = build_job_payload(raw, workflow_meta, agent_id="", webhook_url=WEBHOOK_BASE_URL)
        configs.append(
            {
                "raw": raw,
                "workflow_file": workflow_file,
                "workflow": workflow_meta,
                "job_name": payload["name"],
                "cron_expr": payload["schedule"],
                "payload_template": copy.deepcopy(payload),
                "bot_name": raw.get("bot_name", workflow_meta["name"]),
                "color": int(raw.get("color", 3447003)),
            }
        )
    return configs


def sync_cron_jobs(api: ApiClient, job_configs: List[dict], agent_id: str) -> Dict[str, dict]:
    existing = fetch_cron_jobs(api)
    desired_names = {cfg["job_name"] for cfg in job_configs}

    # Remove stale jobs owned by us (same prefix)
    for name, job in existing.items():
        if not name.startswith(JOB_PREFIX):
            continue
        if name not in desired_names:
            LOG.info("Deleting stale cron job %s (%s)", name, job.get("id"))
            delete_cron_job(api, job.get("id"))

    job_meta: Dict[str, dict] = {}

    for cfg in job_configs:
        payload = copy.deepcopy(cfg["payload_template"])
        payload["agent_id"] = agent_id
        new_delivery = payload["delivery_targets"][0].copy()
        if WEBHOOK_TOKEN:
            new_delivery["auth_header"] = f"Bearer {WEBHOOK_TOKEN}"
        else:
            new_delivery.pop("auth_header", None)
        payload["delivery_targets"] = [new_delivery]

        name = payload["name"]
        desired = payload
        existing_job = existing.get(name)
        if existing_job:
            comparable = desired.copy()
            comparable["action"] = comparable["action"].copy()
            comparable["action"].pop("workflow_name", None)
            if jobs_equal(existing_job, comparable):
                LOG.info("Cron job %s already up to date", name)
                job_meta[name] = {"bot_name": cfg["bot_name"], "color": cfg["color"]}
                continue
            LOG.info("Updating cron job %s", name)
            delete_cron_job(api, existing_job.get("id"))

        job_id = create_cron_job(api, desired)
        LOG.info("  Created cron job %s (%s)", name, job_id)
        job_meta[name] = {"bot_name": cfg["bot_name"], "color": cfg["color"]}

    return job_meta


class CronWebhookHandler(BaseHTTPRequestHandler):
    job_meta: Dict[str, dict] = {}
    discord_webhook: str = ""
    auth_token: str = ""
    session = requests.Session()

    def _json_response(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        path = self.path.rstrip("/")
        if path == "/healthz":
            self._json_response(200, {"status": "ok", "jobs": len(self.job_meta)})
        elif path == "/metrics":
            body = metrics.render_prometheus(self.job_meta).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self._json_response(404, {"error": "not found"})

    def do_POST(self) -> None:
        if not self.path.startswith("/hook"):
            self._json_response(404, {"error": "unknown path"})
            return
        if self.auth_token:
            header = self.headers.get("Authorization", "")
            if header != f"Bearer {self.auth_token}":
                self._json_response(401, {"error": "invalid token"})
                return
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            self._json_response(400, {"error": "invalid json"})
            return
        job_name = payload.get("job")
        output = payload.get("output", "")
        LOG.info("Webhook received: job=%s output_len=%s known_jobs=%s", job_name, len(output), list(self.job_meta.keys()))
        if not job_name:
            LOG.warning("Webhook received empty job name")
            self._json_response(400, {"error": "missing job name"})
            return
        if job_name not in self.job_meta:
            # Try prefix match — OpenFang may send the cron job name which differs from our meta key
            matched = [k for k in self.job_meta if k == job_name or job_name.endswith(k)]
            if matched:
                job_name = matched[0]
                LOG.info("Matched job name %s to meta key %s", job_name, matched[0])
            else:
                LOG.warning("Unknown job name '%s' — available: %s", job_name, list(self.job_meta.keys()))
                self._json_response(404, {"error": "unknown job", "received": job_name, "known": list(self.job_meta.keys())})
                return
        if not output:
            self._json_response(200, {"status": "ok", "note": "empty output"})
            return
        if not self.discord_webhook:
            LOG.warning("Discord webhook missing; dropping output for %s", job_name)
            metrics.record_delivery(job_name, False)
            self._json_response(503, {"error": "discord webhook not configured"})
            return
        meta = self.job_meta[job_name]
        success = send_to_discord(
            webhook=self.discord_webhook,
            bot_name=meta.get("bot_name", job_name),
            color=meta.get("color", 3447003),
            content=output,
        )
        metrics.record_delivery(job_name, success)
        if success:
            self._json_response(200, {"status": "ok"})
        else:
            self._json_response(502, {"error": "discord delivery failed"})

    def log_message(self, format: str, *args) -> None:  # pragma: no cover - quiet server
        LOG.debug("Webhook: " + format, *args)


def send_to_discord(webhook: str, bot_name: str, color: int, content: str) -> bool:
    chunks = chunk_output(content)
    for idx, chunk in enumerate(chunks, start=1):
        payload = {
            "username": bot_name,
            "embeds": [
                {
                    "description": chunk,
                    "color": color,
                }
            ],
        }
        preview = chunk[:200].replace("\n", " ")
        LOG.info(
            "Dispatching Discord chunk %s/%s len=%s preview=%r",
            idx,
            len(chunks),
            len(chunk),
            preview,
        )
        try:
            resp = requests.post(webhook, json=payload, timeout=HTTP_TIMEOUT)
        except requests.RequestException as exc:
            LOG.error("Discord webhook error: %s", exc)
            metrics.record_discord(False)
            return False
        if not resp.ok:
            body_preview = resp.text[:400].replace("\n", " ")
            LOG.error(
                "Discord webhook HTTP %s (chunk %s/%s) body=%r",
                resp.status_code,
                idx,
                len(chunks),
                body_preview,
            )
            LOG.debug("Discord payload rejected: %s", json.dumps(payload)[:6000])
            metrics.record_discord(False)
            return False
        LOG.info("Sent Discord message chunk %s/%s for %s", idx, len(chunks), bot_name)
        metrics.record_discord(True)
        time.sleep(0.2)
    return True


def start_webhook_server(job_meta: Dict[str, dict]) -> None:
    CronWebhookHandler.job_meta = job_meta
    CronWebhookHandler.discord_webhook = DISCORD_WEBHOOK_URL
    CronWebhookHandler.auth_token = WEBHOOK_TOKEN
    server = ThreadingHTTPServer(("0.0.0.0", HTTP_PORT), CronWebhookHandler)

    def shutdown(signum, _frame):  # pragma: no cover - signal path
        LOG.info("Received signal %s, shutting down webhook server", signum)
        server.shutdown()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    LOG.info("Webhook relay listening on 0.0.0.0:%s", HTTP_PORT)
    LOG.info("Endpoints: /healthz  /metrics  /hook")
    server.serve_forever()


def main() -> None:
    parser = argparse.ArgumentParser(description="OpenFang workflow scheduler")
    parser.add_argument(
        "--print-config",
        action="store_true",
        help="Print parsed schedule and exit (debug)",
    )
    args = parser.parse_args()

    api = ApiClient()
    wait_for_openfang(api)

    entries = load_schedule_entries()
    if args.print_config:
        print(json.dumps(entries, indent=2))
        return

    LOG.info("Registering workflows...")
    registry = WorkflowRegistry(api)
    workflows: Dict[str, dict] = {}
    for entry in entries:
        wf_file = entry.get("workflow")
        if not wf_file:
            raise SchedulerConfigError("Missing 'workflow' key in schedule entry")
        workflows[wf_file] = registry.ensure(wf_file)

    agent_id = select_agent_id(api)
    LOG.info("Using agent_id=%s", agent_id)

    job_configs = build_job_configs(entries, workflows)
    LOG.info("Syncing %s cron jobs via /api/cron/jobs", len(job_configs))
    job_meta = sync_cron_jobs(api, job_configs, agent_id)
    if not job_meta:
        LOG.warning("No cron jobs were created. Check schedule configuration.")

    if not DISCORD_WEBHOOK_URL:
        LOG.warning("DISCORD_WEBHOOK_URL not set — outputs will be dropped")

    LOG.info("Jobs ready: %s", ", ".join(sorted(job_meta.keys())))
    start_webhook_server(job_meta)


if __name__ == "__main__":
    try:
        main()
    except SchedulerConfigError as exc:
        LOG.error("Configuration error: %s", exc)
        sys.exit(1)
    except Exception as exc:  # pragma: no cover - top-level guard
        LOG.exception("Fatal error: %s", exc)
        sys.exit(1)

