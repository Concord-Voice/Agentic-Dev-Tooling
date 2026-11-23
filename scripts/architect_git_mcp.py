"""Job-bound MCP stdio server. Only the trusted launcher supplies the snapshot."""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from architect_git_evidence import Evidence

TOOLS = {
    "history": "Read commit history for the bound comparison.",
    "diff": "Read the changes between the two bound commits.",
}
MAX_INLINE_BYTES = 256 * 1024
SCHEMA = {"type": "object", "properties": {}, "additionalProperties": False}
PROTOCOLS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")


def call_tool(ident, params, evidence):
    name = params.get("name")
    if not isinstance(name, str) or name not in TOOLS or params.get("arguments", {}) != {}:
        return {"id": ident, "error": {"code": -32602, "message": "Expected a fixed tool with no arguments"}}
    try:
        content = [{"type": "text", "text": evidence.read(name)}]
        # Bound worst-case JSON escaping and token-dense text as well as
        # Git's raw byte limit, so a successful result fits inline.
        if len(json.dumps(content, ensure_ascii=True)) > MAX_INLINE_BYTES:
            result = {"isError": True, "content": [{"type": "text", "text":
                      "Git evidence exceeds the 256 KiB inline limit. A narrower comparison is required."}]}
        else:
            result = {"content": content}
    except (ValueError, OSError, RuntimeError):
        result = {"isError": True, "content": [{"type": "text", "text": "Git evidence unavailable"}]}
    return {"id": ident, "result": result}


def response(request, evidence):
    if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
        return {"id": None, "error": {"code": -32600, "message": "Invalid request"}}
    if "id" not in request:
        return None
    ident = request["id"]
    method = request.get("method")
    params = request.get("params", {})
    if not isinstance(params, dict) or not isinstance(ident, (str, int)) or isinstance(ident, bool):
        return {"id": None, "error": {"code": -32600, "message": "Invalid request"}}
    if method == "initialize":
        version = params.get("protocolVersion")
        result = {"protocolVersion": version if version in PROTOCOLS else PROTOCOLS[0],
                  "capabilities": {"tools": {}}, "serverInfo": {"name": "architect_git", "version": "1"}}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": [{"name": name, "description": desc, "inputSchema": SCHEMA,
                             "_meta": {"anthropic/maxResultSizeChars": 400000},
                             "annotations": {"readOnlyHint": True, "openWorldHint": False}}
                            for name, desc in TOOLS.items()]}
    elif method == "tools/call":
        return call_tool(ident, params, evidence)
    else:
        return {"id": ident, "error": {"code": -32601, "message": "Method not found"}}
    return {"id": ident, "result": result}


def serve(stream, send, evidence):
    # A complete MCP stdio message occupies one line. Abort oversized frames.
    while line := stream.readline(65537):
        if len(line) > 65536:
            raise ValueError("MCP message too large")
        try:
            reply = response(json.loads(line), evidence)
        except (UnicodeError, json.JSONDecodeError, RecursionError):
            reply = {"id": None, "error": {"code": -32700, "message": "Parse error"}}
        if reply is not None:
            send.write(json.dumps({"jsonrpc": "2.0", **reply}) + "\n")
            send.flush()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Expected a job-bound snapshot")
    try:
        bound = Evidence(Path(sys.argv[1]))
        bound.check()
        serve(sys.stdin.buffer, sys.stdout, bound)
    except (OSError, ValueError, RuntimeError):
        sys.exit("Architect Git session unavailable")
