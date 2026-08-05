#!/usr/bin/env bash
# SessionStart: roster check, arrival announce, and completion-post contract.
#
# DESIGN: push at the edges, pull in the middle.
#   Arrival and completion are terminal, low-frequency, actionable -> worth an
#   interrupt. Everything between is state a supervisor can pull for free via
#   list_events. A session's transcript IS its status update; broadcasting
#   progress to N peers costs N interrupts to say what one read would reveal.
#
# ponytail: no session-store parsing, no message bus, no state file. The roster
# and the transcripts are the channel. This hook only emits an instruction.
#
# `set -eu`, deliberately NOT `set -euo pipefail`: there is no pipeline here, so
# pipefail observes nothing -- and it is a bashism that aborts at this line under
# dash, emitting zero bytes. Dropping it costs no safety and survives `sh <path>`.
set -eu

# SessionStart fires on startup, resume, clear AND compact. Only `startup` is a
# genuinely new session; the other three are the SAME session continuing, and on
# `compact` the model has just lost the memory of having already sent its login.
# Re-emitting the full block there produces a duplicate arrival post per
# compaction -- exactly the interrupt cost this design exists to prevent, scaling
# with session length.
#
# FAIL OPEN, unlike this repo's other hooks. destructive-commands.sh and
# protect-sensitive.sh fail CLOSED because their safe direction is to block. Here
# the safe direction is the opposite: a missing `jq`, a payload shape that does
# not match, or an unrecognized source must still emit the handshake. Failing
# closed would silently disable the coordination this hook exists to provide.
# So an unverified field name degrades to exactly the pre-gate behavior.
# `[ -t 0 ]` guards a manual run: with no stdin redirect `cat` would block on the
# terminal forever. Claude Code always pipes the payload, so this branch is only
# reached by a human testing the hook by hand -- who then gets the full block,
# which is the useful thing to see.
SOURCE=""
if [ ! -t 0 ] && command -v jq >/dev/null 2>&1; then
  INPUT=$(cat 2>/dev/null || true)
  SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // ""' 2>/dev/null || true)
fi

case "$SOURCE" in
  resume|clear|compact)
    cat <<'EOF'
=== SESSION HANDSHAKE (continuing session) ===
This session already ran its handshake. Do NOT re-send a login or arrival
message -- a duplicate post interrupts the supervisor with no new information.
The three-message budget (login / collision / completion) covers the whole
session lifetime, not the span since the last compaction.

If you have lost the roster, re-read it with
mcp__ccd_session_mgmt__list_sessions. Reading is free; posting is not.
Your completion post is still owed at the end.
EOF
    exit
    ;;
esac

cat <<'EOF'
=== SESSION HANDSHAKE ===
Once you know this session's goal (after the first user prompt, before
substantive work), call mcp__ccd_session_mgmt__list_sessions. Then:

1. SUPERVISOR. If a live session (isRunning:true) has a title beginning
   "Supervisor", note its sessionId and send_message it ONCE: your session
   title, branch/worktree, PR number if any, and the goal you were given.
   This is your login. Carry that sessionId for step 3.

2. COLLISION. If a live session shares this session's prNumber, branch, or
   cwd/worktree, it OWNS the code loop. send_message THAT PEER -- not the
   supervisor -- with your arrival and goal, then DIVIDE or DEFER. Never race
   commits (memory: two-sessions-one-pr-races).

3. COMPLETION. When this session's task finishes (merged, blocked, or handed
   back to the user), send_message the supervisor ONE final post: outcome,
   PR state, and anything unresolved.

DO NOT post progress updates. No phase transitions, no "starting X", no status
pings -- not to the supervisor, not to peers. A supervisor reads your transcript
with list_events whenever it wants. Messages arrive as user turns and interrupt
real work; you get at most 3 outbound messages per session lifetime (1, 2, 3
above). If you think you need a fourth, you are pushing something that should be
pulled.

Report the roster check to the user in one line, e.g.
"Roster: 2 live, no collision on PR #123, no supervisor."
EOF
