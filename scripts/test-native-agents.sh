#!/usr/bin/env bash
# Exercise the same offline profile install used by standalone consumers.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
mkdir "$root/bin"
printf '#!/bin/sh\nexit 99\n' > "$root/bin/npx"
chmod +x "$root/bin/npx"
export PATH="$root/bin:$PATH"
for platform in claude codex antigravity copilot; do
  ./install.sh "$platform" --agents-only --project "$root/$platform" >/dev/null
  [[ ! -e "$root/$platform/.claude/settings.json" ]]
  [[ ! -e "$root/$platform/.claude/hooks" ]]
  [[ ! -e "$root/$platform/.codex/config.toml" ]]
  [[ ! -e "$root/$platform/.agents/mcp_config.json" ]]
done

python3 - "$root" <<'PY'
import json
from pathlib import Path
import sys
import tomllib

root = Path(sys.argv[1])
claude = root / "claude/.claude/agents"
codex = root / "codex/.codex/agents"
google = root / "antigravity/.agents/agents"
github = root / "copilot/.github/agents"
assert {p.stem for p in claude.glob("*.md")} == {p.stem for p in codex.glob("*.toml")}
assert len(list(codex.glob("*.toml"))) == 18
assert "tools: []" in (claude / "feedback-analyst.md").read_text().split("---", 2)[1]
for path in codex.glob("*.toml"):
    profile = tomllib.loads(path.read_text())
    assert path.stem == profile["name"] and profile["description"] and profile["developer_instructions"]
    assert "sandbox_mode" not in profile and "mcp_servers" not in profile
architect = tomllib.loads((codex / "architect.toml").read_text())["developer_instructions"]
assert "## Turn Budget" not in architect
assert "## Output Format" in architect
analyst = tomllib.loads((codex / "feedback-analyst.toml").read_text())
assert analyst["features"] == {key: False for key in (
    "apps", "shell_tool", "plugins", "memories", "request_permissions_tool"
)}
assert not analyst["skills"]["include_instructions"]
for name, model, effort in [
    ("architect", "gpt-6.2-sol", "xhigh"), ("test-writer", "gpt-6.1-terra", "medium"),
    ("feedback-analyst", "gpt-6-luna", "low"),
    ("security-reviewer", "gpt-6.2-sol", "high"), ("researcher", "gpt-6.1-terra", "high"),
]:
    profile = tomllib.loads((codex / (name + ".toml")).read_text())
    assert (profile["model"], profile["model_reasoning_effort"]) == (model, effort)

for name in ["code-reviewer", "docs-reviewer", "frontend-reviewer", "migration-reviewer",
             "scope-reviewer", "security-reviewer"]:
    reviewer = tomllib.loads((codex / (name + ".toml")).read_text())
    assert reviewer["features"] == analyst["features"]
    assert "independent Codex review worker" in reviewer["description"]
    assert "scripts/codex-isolated-review.py" in reviewer["developer_instructions"]
researcher = tomllib.loads((codex / "researcher.toml").read_text())
assert "npx ctx7" not in researcher["developer_instructions"]
assert "without a checkout" in researcher["developer_instructions"]
assert "root discovery instructions" not in researcher["developer_instructions"]
assert "reads and greps" not in (claude / "researcher.md").read_text()
profile = (root / "claude/.claude/agents/researcher.md").read_text().split("---\n", 2)[1]
assert profile.split("tools: ",1)[1].splitlines()[0].split(", ") == ["mcp__context7__resolve-library-id", "mcp__context7__query-docs"]
assert not researcher["features"]["shell_tool"] and "apps" not in researcher["features"]
assert not (codex / "red-team.toml").exists()
assert {(p.stem) for p in google.glob("*.md")} == {
    "code-reviewer", "docs-reviewer", "docs-writer", "feedback-analyst", "test-writer"
}
for path in google.glob("*.md"):
    fields = path.read_text().split("---\n", 2)[1].splitlines()
    tools = json.loads(next(x for x in fields if x.startswith("tools: "))[7:])
    assert "model: flash" in fields
    assert "run_command" not in tools
    if path.stem == "feedback-analyst":
        assert tools == []
    if path.stem == "test-writer":
        profile = path.read_text()
        assert "replace_file_content" in tools and "write_to_file" in tools
        assert "does not grant these source operations: Bash." in profile
        assert "exact validation command" in profile and "unexecuted" in profile
        assert "caller runs the tests" in profile
    if path.stem.endswith("-reviewer"):
        assert set(tools) == {"view_file", "grep_search", "find_by_name"}
assert [p.name for p in github.iterdir()] == ["code-reviewer.agent.md"]
copilot = (github / "code-reviewer.agent.md").read_text()
assert "tools: [read, search]" in copilot and "model: claude-opus-5.5" in copilot
PY

# Source updates flow to managed files. Keep local role changes and reserved
# destinations even when the installer and the consumer changed independently.
cp -R install.sh scripts plugins "$root/"
printf '\nA new review convention.\n' >> "$root/plugins/core-lifecycle/agents/code-reviewer.md"
"$root/install.sh" codex --agents-only --project "$root/codex" >/dev/null
role="$root/codex/.codex/agents/code-reviewer.toml"
grep -qF "A new review convention." "$role"
echo "# Local override" >> "$role"
printf '\nAnother review convention.\n' >> "$root/plugins/core-lifecycle/agents/code-reviewer.md"
"$root/install.sh" codex --agents-only --project "$root/codex" >/dev/null
grep -qxF "# Local override" "$role"
printf '{"paths":[".codex/agents/code-reviewer.toml"]}\n' > "$root/codex/.claude/agentic-protected-paths.json"
"$root/install.sh" codex --agents-only --project "$root/codex" --force >/dev/null
grep -qxF "# Local override" "$role"

# A consumer's linked output directory cannot redirect an install elsewhere.
mkdir -p "$root/linked/.codex" "$root/outside"
ln -s "$root/outside" "$root/linked/.codex/agents"
if ./install.sh codex --agents-only --project "$root/linked" >/dev/null 2>&1; then
  echo "installer followed consumer agent directory symlink" >&2; exit 1
fi
[[ -z "$(ls -A "$root/outside")" ]]

# A mismatched source pin cannot silently inherit the user's default model.
sed 's/^model: opus$/model: unregistered-tier/' "$root/plugins/core-lifecycle/agents/architect.md" > "$root/new-role"
mv "$root/new-role" "$root/plugins/core-lifecycle/agents/architect.md"
if "$root/install.sh" codex --agents-only --project "$root/unmapped" >"$root/error.log" 2>&1; then
  echo "installer accepted unregistered source model" >&2; exit 1
fi
grep -q "no approved Codex translation" "$root/error.log"
[[ ! -e "$root/unmapped/.codex/agents" ]]
python3 -I -B scripts/test-codex-isolated-review.py
echo ok
