"""Run a text-only Codex review after the independent parent attests its policy."""

from functools import partial
import json
import os
import queue
import subprocess
import threading
import time
from pathlib import Path


PROFILE = "adt-review"
DISABLED_FEATURES = (
    "apps", "plugins", "hooks", "shell_tool", "memories", "request_permissions_tool",
    "computer_use", "image_generation", "code_mode",
)
MAX_LINE = 8 * 1024 * 1024


REPORT_STATUSES = ("complete", "insufficient-evidence")
SEVERITIES = ("P0", "P1", "P2", "P3")
CATEGORIES = ("correctness", "security", "permissions", "data-integrity", "compatibility",
              "performance", "reliability", "maintainability", "tests", "documentation",
              "scope", "migration", "accessibility")
MAX_FINDINGS = 40


def report_schema(line_count):
    position = {"type": "integer", "minimum": 1, "maximum": line_count}
    fields = {
        "line": position, "end_line": position,
        "severity": {"type": "string", "enum": list(SEVERITIES)},
        "category": {"type": "string", "enum": list(CATEGORIES)},
    }
    item = {"type": "object", "properties": fields, "required": list(fields),
            "additionalProperties": False}
    return {
        "type": "object", "additionalProperties": False, "required": ["status", "findings"],
        "properties": {"status": {"type": "string", "enum": list(REPORT_STATUSES)},
                       "findings": {"type": "array", "maxItems": MAX_FINDINGS, "items": item}},
    }


def _unique_keys(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("duplicate keys")
    return result


def _finding(raw, line_count):
    if type(raw) is not dict or raw.keys() != {"line", "end_line", "severity", "category"}:
        raise ValueError
    start, end, severity, category = (raw[k] for k in ("line", "end_line", "severity", "category"))
    if type(start) is not int or type(end) is not int or not 1 <= start <= end <= line_count:
        raise ValueError
    if severity not in SEVERITIES or category not in CATEGORIES:
        raise ValueError
    return start, end, severity, category


def validated_report(text, line_count):
    """Rebuild the only worker output allowed back into the privileged parent."""
    try:
        if len(text) > 32 * 1024:
            raise ValueError
        raw = json.loads(text, object_pairs_hook=_unique_keys)
        if type(raw) is not dict or raw.keys() != {"status", "findings"}:
            raise ValueError
        status, items = raw["status"], raw["findings"]
        if status not in REPORT_STATUSES or type(items) is not list or len(items) > MAX_FINDINGS:
            raise ValueError
        findings = [_finding(item, line_count) for item in items]
        if len(set(findings)) != len(findings):
            raise ValueError
    except (ValueError, TypeError, RecursionError):
        raise RuntimeError("Reviewer returned an invalid findings report") from None
    return json.dumps({"status": status, "findings": [
        {"line": start, "end_line": end, "severity": severity, "category": category}
        for start, end, severity, category in sorted(findings)
    ]}, separators=(",", ":"))


class Rpc:
    """Line-delimited JSON-RPC with a deadline and no client-executed tools."""

    def __init__(self, binary, cwd, environment):
        self.process = subprocess.Popen(
            [str(binary), "app-server"], cwd=cwd, env=environment,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        self.events = queue.Queue(maxsize=64)
        self.outgoing = queue.Queue(maxsize=4)
        self.closed = threading.Event()
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.writer = threading.Thread(target=self._write, daemon=True)
        self.reader.start()
        self.writer.start()
        self.next_id = 0

    def _read(self):
        while not self.closed.is_set():
            line = self.process.stdout.readline(MAX_LINE + 1)
            while not self.closed.is_set():
                try:
                    self.events.put(line, timeout=0.2)
                    break
                except queue.Full:
                    continue
            if not line or len(line) > MAX_LINE:
                return

    def _write(self):
        # A server that stops reading stdin must not stall the RPC deadline.
        while not self.closed.is_set():
            try:
                data = self.outgoing.get(timeout=0.2)
            except queue.Empty:
                continue
            try:
                self.process.stdin.write(data)
                self.process.stdin.flush()
            except (OSError, ValueError):
                return

    def close(self):
        self.closed.set()
        if self.process.poll() is None:
            self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        self.reader.join(timeout=1)
        self.writer.join(timeout=1)
        if not self.reader.is_alive():
            self.process.stdout.close()
        if not self.writer.is_alive():
            self.process.stdin.close()

    def send(self, message):
        encoded = json.dumps({"jsonrpc": "2.0", **message}).encode() + b"\n"
        if len(encoded) > MAX_LINE:
            raise RuntimeError("Codex RPC request exceeds the review size limit")
        try:
            self.outgoing.put_nowait(encoded)
        except queue.Full:
            raise RuntimeError("Codex app-server stopped reading requests") from None

    def receive(self, deadline):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError("Codex review session timed out")
        try:
            line = self.events.get(timeout=remaining)
        except queue.Empty:
            raise RuntimeError("Codex review session timed out") from None
        if not line or len(line) > MAX_LINE:
            raise RuntimeError("Codex app-server closed or exceeded its message size limit")
        try:
            message = json.loads(line)
        except (UnicodeError, ValueError):
            raise RuntimeError("Codex app-server returned invalid JSON") from None
        if not isinstance(message, dict) or message.get("jsonrpc", "2.0") != "2.0":
            raise RuntimeError("Unexpected Codex app-server protocol message")
        if "method" in message and "id" in message:
            raise RuntimeError("Codex requested a client action during a text-only review")
        return message

    def request(self, method, params, deadline, on_notification=None):
        self.next_id += 1
        request_id = self.next_id
        self.send({"id": request_id, "method": method, "params": params})
        while True:
            message = self.receive(deadline)
            if "method" in message:
                if on_notification is not None:
                    on_notification(message)
                continue
            if message.get("id") != request_id or not isinstance(message.get("result"), dict):
                raise RuntimeError(f"Codex app-server rejected {method} or returned an unexpected response")
            return message["result"]


def _configured(mapping):
    return {key: value for key, value in mapping.items() if value is not None}


def _check_config(config, binary):
    expected = (
        config.get("default_permissions") == PROFILE,
        config.get("approval_policy") == "never",
        config.get("web_search") == "disabled",
        config.get("agents", {}).get("enabled") is False,
        config.get("skills", {}).get("include_instructions") is False,
        config.get("skills", {}).get("bundled", {}).get("enabled") is False,
        all(config.get("features", {}).get(key) is False for key in DISABLED_FEATURES),
        config.get("mcp_servers") == {},
        config.get("model_provider") in (None, "openai"),
        config.get("chatgpt_base_url") in (None, "https://chatgpt.com/backend-api/"),
        all(not config.get(key) for key in (
            "apps", "plugins", "hooks", "notify", "model_providers", "openai_base_url",
            "sandbox_mode",
        )),
        _configured(config.get("shell_environment_policy", {})) == {"inherit": "none"},
    )
    if not all(expected):
        raise RuntimeError("Effective Codex configuration does not match the isolated reviewer policy")
    profiles = config.get("permissions") or {}
    profile = _configured(profiles.get(PROFILE, {}))
    filesystem = {":minimal": "read", ":workspace_roots": "read", str(Path(binary).resolve()): "read"}
    if (
        set(profile) != {"filesystem", "network"}
        or _configured(profile["filesystem"]) != filesystem
        or _configured(profile["network"]) != {"enabled": False}
    ):
        raise RuntimeError("Effective reviewer filesystem or network grants differ from the requested profile")


def _start(rpc, binary, cwd, role, deadline):
    rpc.request("initialize", {
        "clientInfo": {"name": "adt-review", "version": "1"},
        "capabilities": {"experimentalApi": True},
    }, deadline)
    rpc.send({"method": "initialized"})
    result = rpc.request("config/read", {"cwd": cwd, "includeLayers": False}, deadline)
    _check_config(result["config"], binary)
    result = rpc.request("thread/start", {
        "cwd": cwd, "model": role["model"], "developerInstructions": role["developer_instructions"],
        "config": {"model_reasoning_effort": role["model_reasoning_effort"]},
        "approvalPolicy": "never", "permissions": PROFILE, "ephemeral": True,
        "environments": [], "selectedCapabilityRoots": [], "dynamicTools": [],
        "allowProviderModelFallback": False,
    }, deadline)
    thread = result.get("thread", {})
    if not all((
        result.get("activePermissionProfile") == {"id": PROFILE, "extends": None},
        result.get("sandbox") == {"type": "readOnly", "networkAccess": False},
        result.get("approvalPolicy") == "never", result.get("instructionSources") == [],
        result.get("runtimeWorkspaceRoots") == [], thread.get("environments") == [],
        thread.get("ephemeral") is True, result.get("cwd") == cwd,
        result.get("model") == role["model"], result.get("modelProvider") == "openai",
        result.get("reasoningEffort") == role["model_reasoning_effort"],
        isinstance(thread.get("id"), str) and bool(thread["id"]),
    )):
        raise RuntimeError("Codex did not attest an isolated ephemeral review thread")
    inventory = rpc.request("mcpServerStatus/list", {"threadId": thread["id"]}, deadline)
    if inventory.get("data") != [] or "nextCursor" not in inventory or inventory["nextCursor"] is not None:
        raise RuntimeError("The review thread has an MCP server or an incomplete MCP inventory")
    return thread["id"]


def _record_notification(message, *, thread_id, completed, finals):
    params = message.get("params", {})
    if params.get("threadId") != thread_id:
        return
    method = message["method"]
    if method == "turn/completed":
        turn = params["turn"]
        completed[turn["id"]] = turn["status"]
        return
    if method not in ("item/started", "item/completed"):
        return
    item = params.get("item", {})
    if item.get("type") not in ("userMessage", "reasoning", "agentMessage"):
        raise RuntimeError("Codex attempted a non-text item during the review")
    if method == "item/completed" and item.get("type") == "agentMessage":
        if item.get("phase") in (None, "final_answer") and isinstance(item.get("text"), str):
            finals[params["turnId"]] = item["text"]


def _review(rpc, thread_id, role, payload):
    deadline = time.monotonic() + 600
    completed = {}
    finals = {}
    observe = partial(_record_notification, thread_id=thread_id, completed=completed, finals=finals)
    # Match physical lines in the staged Git diff, including blank lines.
    # Unicode line separators inside a filename or hunk do not shift references.
    lines = payload.removesuffix("\n").split("\n") if payload else []
    if not lines:
        raise RuntimeError("No review input lines were provided")
    numbered = "\n".join(f"{number}\t{line}" for number, line in enumerate(lines, 1))
    turn = rpc.request("turn/start", {
        "threadId": thread_id, "environments": [], "model": role["model"],
        "effort": role["model_reasoning_effort"],
        "outputSchema": report_schema(len(lines)),
        "input": [{"type": "text", "text": numbered, "text_elements": []}],
    }, deadline, observe)["turn"]["id"]
    while turn not in completed:
        message = rpc.receive(deadline)
        if "method" not in message:
            raise RuntimeError("Unexpected response during a Codex review turn")
        observe(message)
    if completed[turn] != "completed" or not finals.get(turn, "").strip():
        raise RuntimeError("Codex review finished without a final text answer")
    return validated_report(finals[turn], len(lines))


def run_session(binary, cwd, environment, role, read_payload=None):
    """Return final review text, or None for a successful payload-free preflight."""
    rpc = Rpc(binary, cwd, environment)
    try:
        thread = _start(rpc, binary, os.fspath(Path(cwd).resolve()), role, time.monotonic() + 30)
        if read_payload is None:
            return None
        return _review(rpc, thread, role, read_payload())
    finally:
        rpc.close()
