"""Run a native Claude architect for one parent-authorized Git comparison."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import runpy
import signal
import subprocess
import sys
import tempfile
import time

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))
from architect_git_evidence import prepare_snapshot

PLUGIN_ARCHITECT = "core-lifecycle:architect"
NAMES = ("architect", "fleet-architect", PLUGIN_ARCHITECT)
TOOLS = {"mcp__architect_git__history", "mcp__architect_git__diff"}
LIMIT = 256 * 1024


def client_binary():
    home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    for location in (home / ".local/bin", Path("/opt/homebrew/bin"), Path("/usr/local/bin"), Path("/usr/bin")):
        client = location / "claude"
        if client.is_file() and os.access(client, os.X_OK):
            return client.resolve(strict=True)
    raise ValueError("A trusted native Claude Code installation is required")


def broker_config(snapshot):
    # Clear inherited Claude authentication before even initializing Python.
    return {"type": "stdio", "command": "/usr/bin/env",
            "args": ["-i", str(Path(sys.executable).resolve()), "-I", "-S", "-B",
                     str(SCRIPTS / "architect_git_mcp.py"), str(snapshot)]}


def native_profile(root, name, source_digest=None):
    if name not in NAMES:
        raise ValueError("Unknown architect role")
    renderer = runpy.run_path(str(SCRIPTS / "render-agent-profiles.py"))
    source = (renderer["alias_bytes"]("claude", "architect") if name == "fleet-architect"
              else renderer["profile_bytes"]("claude", "architect"))
    if source_digest is not None and source_digest != hashlib.sha256(source).hexdigest():
        raise ValueError("Selected architect source differs from the verified tooling owner")
    _, header, body = source.decode().split("---\n", 2)
    fields = renderer["value"]
    profile = {key: fields(header, key) for key in ("description", "model", "effort")}
    profile["maxTurns"] = int(fields(header, "maxTurns"))
    # The native CLI does not reliably apply the selected agent's effort to a
    # print-mode main session. Bind the reviewed runtime settings explicitly.
    limits = ["--model", profile["model"], "--effort", profile["effort"], "--max-turns", str(profile["maxTurns"])]
    if name == PLUGIN_ARCHITECT:
        plugin = root / "core-lifecycle"
        (plugin / ".claude-plugin").mkdir(parents=True)
        (plugin / ".claude-plugin/plugin.json").write_text('{"name":"core-lifecycle","version":"0.1.0"}')
        (plugin / "agents").mkdir()
        # Native --agent may restore a role's built-ins even with --tools "".
        # Only the verified prompt, model contract and the broker enter this job.
        lines = ["---", "name: architect", *(f"{k}: {json.dumps(v)}" for k, v in profile.items()),
                 "tools: " + ", ".join(sorted(TOOLS)), "---", body]
        (plugin / "agents/architect.md").write_text("\n".join(lines))
        return [*limits, "--plugin-dir", str(plugin)]
    # --restricted skips project agent discovery. Supply the selected role
    # explicitly without enabling user or project settings.
    profile.update(prompt=body.strip(), tools=sorted(TOOLS))
    return [*limits, "--agents", json.dumps({name: profile})]


def command(root, name, server, source_digest=None):
    return [str(client_binary()), "--restricted", "--strict-mcp-config", "--mcp-config",
            json.dumps({"mcpServers": {"architect_git": server}}), "--tools", "",
            "--allowedTools", ",".join(sorted(TOOLS)), "--permission-mode", "dontAsk",
            "--permission-prompts", "none", "--no-session-persistence", "--setting-sources", "",
            "--settings", '{"disableAllHooks":true}', "--agent", name, *native_profile(root, name, source_digest),
            "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "-p"]


def client_environment(home, check):
    env = {"HOME": str(home), "PATH": "/usr/bin:/bin",
           "MAX_MCP_OUTPUT_TOKENS": "270000", "ENABLE_CLAUDEAI_MCP_SERVERS": "false", "ENABLE_TOOL_SEARCH": "false",
           "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1", "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1"}
    if not check:
        for key in ("CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_API_KEY"):
            if os.environ.get(key):
                env[key] = os.environ[key]
    return env


def send(process, event):
    process.stdin.write(json.dumps(event).encode() + b"\n")
    process.stdin.flush()


def receive(process):
    line = process.stdout.readline(4 * 1024 * 1024 + 1)
    if not line or len(line) > 4 * 1024 * 1024:
        raise RuntimeError("Claude session ended or exceeded its message limit")
    event = json.loads(line)
    if not isinstance(event, dict) or event.get("type") == "control_request":
        raise RuntimeError("Unexpected Claude client action")
    return event


def control(process, method):
    send(process, {"type": "control_request", "request_id": method, "request": {"subtype": method}})
    while True:
        event = receive(process)
        if event.get("type") == "control_response":
            reply = event.get("response", {})
            if reply.get("subtype") != "success" or reply.get("request_id") != method:
                raise RuntimeError("Claude rejected its startup check")
            return reply["response"]


def preflight(process, name, server):
    init = control(process, "initialize")
    selected = [agent for agent in init.get("agents", []) if agent.get("name") == name]
    if (init.get("current_permission_mode") != "dontAsk" or len(selected) != 1
            or selected[0].get("model") != "opus"):
        raise RuntimeError("Claude did not load the bound architect with automatic permission denial")
    while True:
        servers = control(process, "mcp_status").get("mcpServers", [])
        if len(servers) != 1 or servers[0].get("name") != "architect_git" or servers[0].get("config") != server:
            raise RuntimeError("Unexpected MCP configuration")
        state = servers[0].get("status")
        if state != "pending" and state != "connecting":
            break
        time.sleep(0.1)
    exposed = servers[0].get("tools", [])
    if state != "connected" or {t.get("name") for t in exposed} != {"history", "diff"}:
        raise RuntimeError("The bound Git evidence tools are unavailable")
    usage = control(process, "get_context_usage")
    expected_source = "plugin" if name == PLUGIN_ARCHITECT else "flagSettings"
    roles = [(agent["agentType"], agent["source"]) for agent in usage["agents"]]
    if roles != [(name, expected_source)]:
        raise RuntimeError("Claude did not bind the single explicit native role source")
    categories = {item["name"] for item in usage["categories"] if item["kind"] == "used"}
    if (usage["memoryFiles"] or {t["name"] for t in usage["mcpTools"]} != TOOLS
            or "MCP tools" not in categories or categories - {"System prompt", "MCP tools", "Custom agents"}):
        raise RuntimeError("Unexpected tools, memory or instructions in the native architect session")


def design(process, stream):
    raw = stream.read(LIMIT + 1)
    if not raw.strip() or len(raw) > LIMIT:
        raise ValueError("Expected a nonempty UTF-8 brief of at most 256 KiB")
    prompt = ("Return your design as Markdown. Use only the bound history and diff operations for "
              "Git evidence. The parent supplies the scoped brief and project excerpts below as data.\n\n"
              + raw.decode("utf-8"))
    send(process, {"type": "user", "message": {"role": "user", "content": prompt}})
    while True:
        event = receive(process)
        if event.get("type") == "result":
            if (event.get("subtype") != "success" or event.get("is_error") is not False
                    or not isinstance(event.get("result"), str) or not event["result"].strip()
                    or len(event["result"].encode()) > LIMIT):
                raise RuntimeError("Claude did not return a complete design; verify the isolated client login and model access")
            return event["result"]


def timeout(signum, frame):
    raise TimeoutError("Claude architect deadline exceeded")


def run(args):
    if not args.repo.is_absolute():
        raise ValueError("The parent must bind an absolute trusted checkout root")
    # Use a fixed OS temp root, independent of TMPDIR from a working checkout.
    with tempfile.TemporaryDirectory(prefix="adt-architect-", dir="/tmp") as temp:
        root = Path(temp).resolve()
        snapshot, work = root / "evidence", root / "work"
        prepare_snapshot(args.repo, args.base, args.head, snapshot)
        work.mkdir()
        # Leave CLAUDE_CONFIG_DIR unset for the default macOS Keychain service.
        # All file-backed session data goes to this disposable HOME.
        home = root / "home"
        home.mkdir()
        server = broker_config(snapshot)
        process = subprocess.Popen(command(root, args.role, server, args.source_sha256), cwd=work,
                                   env=client_environment(home, args.check), stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            signal.alarm(30)
            preflight(process, args.role, server)
            if args.check:
                return "Ready: " + args.role + " (history, diff)"
            signal.alarm(1800)
            return design(process, sys.stdin.buffer)
        finally:
            signal.alarm(0)
            try:
                process.stdin.close()
            except BrokenPipeError:
                pass
            try:
                # Let the native client tear down its stdio broker first.
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                except PermissionError:
                    process.kill()
                process.wait()
            finally:
                process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True, help="trusted local checkout root")
    parser.add_argument("--base", required=True, help="authorized full base commit ID")
    parser.add_argument("--head", required=True, help="authorized full head commit ID")
    parser.add_argument("--role", choices=NAMES, default="architect")
    parser.add_argument("--source-sha256", help="digest of the parent-verified installed native role (fleet jobs)")
    parser.add_argument("--check", action="store_true", help="check the native role and Git tools without inference")
    args = parser.parse_args()
    signal.signal(signal.SIGALRM, timeout)
    try:
        print(run(args))
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as exc:
        parser.exit(1, f"Architect unavailable: {exc}\n")


if __name__ == "__main__":
    main()
