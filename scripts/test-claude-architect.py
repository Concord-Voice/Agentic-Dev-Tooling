"""Offline tests for the architect launcher, native projections and MCP contract."""
import io
import json
import os
import random
from pathlib import Path
import runpy
import signal
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

HERE = Path(__file__).resolve().parent
LAUNCH = runpy.run_path(str(HERE / "claude-architect.py"))
BROKER = runpy.run_path(str(HERE / "architect_git_mcp.py"))
GLOBALS = LAUNCH["run"].__globals__
TOOLS = LAUNCH["TOOLS"]


class BrokerTest(unittest.TestCase):
    def setUp(self):
        self.evidence = Mock()
        self.evidence.read.side_effect = lambda name: name + " fixture"

    def call(self, method, params=None):
        request = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}}
        return BROKER["response"](request, self.evidence)

    def test_only_two_zero_argument_operations(self):
        for version in ("2024-11-05", "unknown"):
            actual = self.call("initialize", {"protocolVersion": version})["result"]
            self.assertIn(actual["protocolVersion"], BROKER["PROTOCOLS"])
            self.assertEqual(actual["capabilities"], {"tools": {}})
        tools = self.call("tools/list")["result"]["tools"]
        self.assertEqual({t["name"] for t in tools}, {"history", "diff"})
        for tool in tools:
            self.assertEqual(tool["inputSchema"], {"type": "object", "properties": {}, "additionalProperties": False})
            name = tool["name"]
            self.assertEqual(self.call("tools/call", {"name": name})["result"]["content"][0]["text"], name + " fixture")
        self.assertEqual(self.call("ping")["result"], {})
        self.assertIn("error", self.call("resources/list"))
        self.assertIsNone(BROKER["response"]({"jsonrpc": "2.0"}, self.evidence))
        for item in (None, [], {"id": 1}, {"jsonrpc": "2.0", "id": []}):
            self.assertIn("error", BROKER["response"](item, self.evidence))

    def test_rejects_parameters_and_reports_query_failure(self):
        for params in ({"name": "diff", "arguments": {"path": "docs"}}, {"name": []}, {"name": "status"}):
            self.assertEqual(self.call("tools/call", params)["error"]["code"], -32602)
        self.evidence.read.assert_not_called()
        self.evidence.read.side_effect = lambda _: "\x01" * 60000
        overflow = self.call("tools/call", {"name": "diff"})["result"]
        self.assertTrue(overflow["isError"])
        self.assertIn("inline limit", overflow["content"][0]["text"])
        self.evidence.read.side_effect = RuntimeError("inert private detail")
        reply = self.call("tools/call", {"name": "history"})["result"]
        self.assertTrue(reply["isError"])
        self.assertNotIn("private detail", str(reply))

    def test_framing(self):
        stream = io.BytesIO(b'bad json\n{"jsonrpc":"2.0"}\n{"jsonrpc":"2.0","id":3,"method":"ping"}\n')
        output = io.StringIO()
        BROKER["serve"](stream, output, self.evidence)
        replies = list(map(json.loads, output.getvalue().splitlines()))
        self.assertEqual([r["id"] for r in replies], [None, 3])
        with self.assertRaises(ValueError):
            BROKER["serve"](io.BytesIO(b"x" * 65537), output, self.evidence)


class SessionTest(unittest.TestCase):
    def setUp(self):
        self.server = LAUNCH["broker_config"](Path("/fixture"))
        self.status = {"name": "architect_git", "config": self.server, "status": "connected",
                       "tools": [{"name": "history"}, {"name": "diff"}]}
        self.usage = {"categories": [{"name": "MCP tools", "kind": "used"}], "memoryFiles": [],
                      "agents": [{"agentType": "architect", "source": "flagSettings"}],
                      "mcpTools": [{"name": n} for n in TOOLS]}
        self.init = {"current_permission_mode": "dontAsk", "agents": [{"name": "architect", "model": "opus"}]}

    def check(self, states):
        with patch.dict(GLOBALS, control=Mock(side_effect=states)):
            LAUNCH["preflight"](None, "architect", self.server)

    def test_exact_same_session_inventory(self):
        self.check([self.init, {"mcpServers": [{**self.status, "status": "pending"}]},
                    {"mcpServers": [self.status]}, self.usage])
        for init in ({**self.init, "agents": []}, {**self.init, "current_permission_mode": "default"}):
            with self.assertRaises(RuntimeError):
                self.check([init])
        for servers in ([], [self.status] * 2, [{**self.status, "config": {}}],
                        [{**self.status, "status": "failed"}], [{**self.status, "tools": []}]):
            with self.assertRaises(RuntimeError):
                self.check([self.init, {"mcpServers": servers}])
        for usage in ({**self.usage, "agents": [{"agentType": "architect", "source": "projectSettings"}]},
                      {**self.usage, "mcpTools": []}, {**self.usage, "memoryFiles": ["test"]},
                      {**self.usage, "categories": self.usage["categories"] + [{"kind": "used", "name": "System tools"}]}):
            with self.assertRaises(RuntimeError):
                self.check([self.init, {"mcpServers": [self.status]}, usage])

    def test_environment_and_role_projections(self):
        with patch.dict(os.environ, {"GH_TOKEN": "fixture", "PYTHONPATH": "/fixture",
                                     "ANTHROPIC_API_KEY": "test-only", "CLAUDE_CONFIG_DIR": "/fixture",
                                     "ANTHROPIC_BASE_URL": "https://example.invalid"}):
            scratch = Path("/tmp/fixture")
            env = LAUNCH["client_environment"](scratch, False)
            self.assertNotIn("GH_TOKEN", env)
            self.assertNotIn("PYTHONPATH", env)
            self.assertNotIn("ANTHROPIC_BASE_URL", env)
            self.assertNotIn("CLAUDE_CONFIG_DIR", env)
            self.assertEqual(env["HOME"], str(scratch))
            self.assertEqual(env["ANTHROPIC_API_KEY"], "test-only")
            self.assertNotIn("ANTHROPIC_API_KEY", LAUNCH["client_environment"](scratch, True))
            self.assertEqual(self.server["command"], "/usr/bin/env")
            self.assertEqual(self.server["args"][0], "-i")
        for name in LAUNCH["NAMES"]:
            with tempfile.TemporaryDirectory() as temp, patch.dict(GLOBALS, client_binary=lambda: "/trusted/claude"):
                root = Path(temp)
                args = LAUNCH["command"](root, name, self.server)
                self.assertEqual(args[args.index("--agent") + 1], name)
                self.assertEqual(args[args.index("--tools") + 1], "")
                self.assertEqual(args[args.index("--max-turns") + 1], "40")
                self.assertEqual(args[args.index("--effort") + 1], "xhigh")
                if "--plugin-dir" in args:
                    role = (Path(args[args.index("--plugin-dir") + 1]) / "agents/architect.md").read_text()
                    header = role.split("---", 2)[1]
                    self.assertNotIn("skills:", header)
                    self.assertEqual(set(header.split("tools: ")[1].splitlines()[0].split(", ")), TOOLS)
                else:
                    role = json.loads(args[args.index("--agents") + 1])[name]
                    self.assertEqual(set(role["tools"]), TOOLS)
                    self.assertEqual((role["model"], role["effort"], role["maxTurns"]), ("opus", "xhigh", 40))
        with self.assertRaises(ValueError):
            LAUNCH["native_profile"](Path("/fixture"), "other")
        with self.assertRaisesRegex(ValueError, "Selected architect source"):
            LAUNCH["native_profile"](Path("/fixture"), "architect", "0" * 64)
        native = (HERE.parent / "plugins/core-lifecycle/agents/architect.md").read_text().split("---", 2)[1]
        self.assertIn("skills:", native)
        self.assertTrue({"Read", "Grep", "Glob", "Write(docs/**)", "Edit(docs/**)"} | TOOLS ==
                        set(native.split("tools: ")[1].splitlines()[0].split(", ")))

    def test_io_and_invalid_briefs(self):
        response = {"type": "control_response", "response": {"request_id": "initialize", "subtype": "success",
                                                            "response": {"fixture": True}}}
        process = SimpleNamespace(stdin=io.BytesIO(), stdout=io.BytesIO(json.dumps(response).encode() + b"\n"))
        self.assertEqual(LAUNCH["control"](process, "initialize"), {"fixture": True})
        for data in (b"", b"null\n", b'{"type":"control_request"}\n', b'x' * (4 * 1024 * 1024 + 1)):
            with self.assertRaises(RuntimeError):
                LAUNCH["receive"](SimpleNamespace(stdout=io.BytesIO(data)))
        for raw in (b"", b"x" * (LAUNCH["LIMIT"] + 1)):
            with self.assertRaises(ValueError):
                LAUNCH["design"](None, io.BytesIO(raw))
        for result in ("success", "error"):
            event = {"type": "result", "subtype": result, "is_error": False, "result": "design"}
            process.stdout = io.BytesIO(json.dumps(event).encode() + b"\n")
            if result == "success":
                self.assertEqual(LAUNCH["design"](process, io.BytesIO(b"brief facts")), "design")
                self.assertIn("brief facts", process.stdin.getvalue().decode())
            else:
                with self.assertRaises(RuntimeError):
                    LAUNCH["design"](process, io.BytesIO(b"brief facts"))
        with self.assertRaises(ValueError):
            LAUNCH["run"](SimpleNamespace(repo=Path("relative")))

    def test_unready_session_never_reads_brief(self):
        proc = Mock()
        with patch.dict(GLOBALS, prepare_snapshot=Mock(), command=Mock(return_value=["claude"]),
                        preflight=Mock(side_effect=RuntimeError("unready")), design=Mock()), \
             patch("subprocess.Popen", return_value=proc), patch("os.killpg"):
            with self.assertRaisesRegex(RuntimeError, "unready"):
                LAUNCH["run"](SimpleNamespace(repo=Path("/trusted"), base="a", head="b", role="architect", source_sha256=None, check=False))
            GLOBALS["design"].assert_not_called()
            proc.wait.assert_called_once_with(timeout=1)


class FixtureEndpoint(BaseHTTPRequestHandler):
    """Replay one tool-use turn and one Markdown response over loopback."""
    def log_message(self, *args):
        pass

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path.startswith("/v1/messages/count_tokens"):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"input_tokens":100}')
            return
        self.server.requests.append(payload)
        if len(self.server.requests) == 1:
            blocks = [{"type": "tool_use", "id": "toolu_" + t, "name": "mcp__architect_git__" + t, "input": {}}
                      for t in ("history", "diff")]
        else:
            blocks = [{"type": "text", "text": "Design fixture"}]
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()

        def emit(kind, **fields):
            event = json.dumps({"type": kind, **fields})
            self.wfile.write(f"event: {kind}\ndata: {event}\n\n".encode())

        emit("message_start", message={"id": "msg_fixture", "type": "message", "role": "assistant",
             "model": payload["model"], "content": [], "stop_reason": None, "stop_sequence": None,
             "usage": {"input_tokens": 100, "output_tokens": 1}})
        for i, block in enumerate(blocks):
            text = block["type"] == "text"
            emit("content_block_start", index=i, content_block={**block, "text": ""} if text else block)
            delta = {"type": "text_delta", "text": block["text"]} if text else {"type": "input_json_delta", "partial_json": "{}"}
            emit("content_block_delta", index=i, delta=delta)
            emit("content_block_stop", index=i)
        emit("message_delta", delta={"stop_reason": "end_turn" if text else "tool_use", "stop_sequence": None},
             usage={"output_tokens": 3})
        emit("message_stop")


NATIVE = "--native" in sys.argv
if NATIVE:
    sys.argv.remove("--native")


@unittest.skipUnless(NATIVE, "pass --native to test the installed CLI and OS Git confinement against a local model fixture")
class NativeReplayTest(unittest.TestCase):
    def test_native_seats_request_bound_evidence(self):
        with tempfile.TemporaryDirectory() as temp, ThreadingHTTPServer(("127.0.0.1", 0), FixtureEndpoint) as endpoint:
            root = Path(temp).resolve()
            home = root / "home"
            home.mkdir()
            repo = root / "project"
            repo.mkdir()
            env = {"HOME": str(home), "PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1"}
            def git(*args):
                return subprocess.check_output(["/usr/bin/git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                                               "-c", "commit.gpgSign=false", *args], cwd=repo, env=env, text=True).strip()
            git("init", "-q")
            git("commit", "--allow-empty", "-qm", "base")
            base = git("rev-parse", "HEAD")
            # Exceeds Claude's ordinary 50,000-character offload threshold.
            # End markers prove the model received the entire high-entropy result.
            noise = random.Random(7).randbytes(100000).hex()
            (repo / "fixture.txt").write_text("proposed design\n" + noise + "\nend of architecture fixture\n")
            git("add", "fixture.txt")
            git("commit", "-qm", "architecture fixture")
            head = git("rev-parse", "HEAD")
            renderer = runpy.run_path(str(HERE / "render-agent-profiles.py"))
            fleet = runpy.run_path(str(HERE / "resolve-fleet-workflow.py"))
            agents = repo / ".claude/agents"
            agents.mkdir(parents=True)
            (agents / "architect.md").write_bytes(renderer["profile_bytes"]("claude", "architect"))
            (agents / "fleet-architect.md").write_bytes(renderer["alias_bytes"]("claude", "architect"))
            thread = threading.Thread(target=endpoint.serve_forever, daemon=True)
            thread.start()
            original_env = LAUNCH["client_environment"]
            def fixture_env(_home, _check):
                return {**original_env(home, True), "ANTHROPIC_API_KEY": "offline-fixture",
                        "ANTHROPIC_BASE_URL": f"http://127.0.0.1:{endpoint.server_port}"}

            previous = signal.signal(signal.SIGALRM, LAUNCH["timeout"])
            try:
                for name in LAUNCH["NAMES"]:
                    with self.subTest(name=name):
                        selected_digest = None
                        if name != "core-lifecycle:architect":
                            if name == "fleet-architect":
                                (agents / "architect.md").write_text("locally authored architect")
                            selected = fleet["select_role"]("claude", "architect", repo)
                            self.assertEqual(selected["native_name"], name)
                            selected_digest = fleet["verified_role"]("claude", "architect", Path(selected["profile"]))
                            self.assertEqual(selected_digest, selected["sha256"])
                        endpoint.requests = []
                        brief = SimpleNamespace(buffer=io.BytesIO(b"Mode 1. Project rule fixture."))
                        with patch.dict(GLOBALS, client_environment=fixture_env), patch.object(sys, "stdin", brief):
                            result = LAUNCH["run"](SimpleNamespace(repo=repo, base=base, head=head, role=name, source_sha256=selected_digest, check=False))
                        self.assertEqual(result, "Design fixture")
                        self.assertEqual(len(endpoint.requests), 2)
                        for req in endpoint.requests:
                            self.assertEqual({t["name"] for t in req["tools"]}, TOOLS)
                            self.assertEqual(req["output_config"]["effort"], "xhigh")
                            self.assertTrue(req["model"].startswith("claude-opus-"))
                        self.assertIn("Project rule fixture", json.dumps(endpoint.requests[0]["messages"]))
                        self.assertIn("Blast-Radius Scout", json.dumps(endpoint.requests[0]))
                        results = [block for msg in endpoint.requests[1]["messages"] if isinstance(msg["content"], list)
                                   for block in msg["content"] if block.get("type") == "tool_result"]
                        self.assertEqual(len(results), 2)
                        self.assertTrue(all(not r.get("is_error") for r in results))
                        self.assertIn(head + " architecture fixture", json.dumps(results))
                        self.assertIn("+" + noise, json.dumps(results))
                        self.assertIn("+end of architecture fixture", json.dumps(results))
                        self.assertEqual(list(home.rglob("tool-results/*")), [])
            finally:
                signal.signal(signal.SIGALRM, previous)
                endpoint.shutdown()
                thread.join()


if __name__ == "__main__":
    unittest.main()
