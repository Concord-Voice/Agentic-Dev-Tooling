---
name: supervise
description: Run this session as the supervisor for a fleet of live Claude Code sessions — poll the roster, diagnose stalls and PR-ownership races, act within a spawn-time oversight tier. Use when the user types /supervise, optionally with a tier (audit | partial | full).
---

# Supervise

**Model-invocation authorization.** Start a supervisor ONLY when the user types
`/supervise`, or when the `loop` skill re-invokes it on a tick. Never start one
unprompted — it is a long-running, token-expensive session.

## Setup — first invocation only

1. **Resolve the tier** from the argument: `audit` | `partial` | `full`.
   Default `partial`. State the resolved tier in your first line.

2. **Rename this session** so workers can find you: its title must begin with
   `Supervisor` — the session-handshake hook has every new session look for that
   prefix to log in. Use `mcp__ccd_session_mgmt__set_session_title`, e.g.
   `Supervisor (partial)`.

3. **Start the loop.** Invoke the `loop` skill with `/supervise <tier>` and no
   interval, so it self-paces. Workers run 20+ min per phase; a short fixed tick
   burns turns confirming nothing moved. If the loop skill is unavailable, run a
   single tick and tell the user to run `/loop /supervise <tier>` instead — do
   not fake a loop by polling in one turn.

On a loop-driven tick these instructions are already loaded: skip setup, go
straight to the tick.

## The tick

### 1. Sense — pull, never wait to be told

Workers post at most three times each and send NO progress updates. Two of those
reach you — login and completion; the third (collision) goes to the colliding
peer, not to you. You learn everything else by reading:

- `mcp__ccd_session_mgmt__list_sessions` — the roster. Cheap. Every tick.
- `mcp__ccd_session_mgmt__list_events` — another session's real transcript
  (turns + tool calls). This is how you know what a worker is *doing*.
- `mcp__ccd_session_mgmt__search_session_transcripts` — locate which session hit
  an error or touched a file.

A worker's transcript is its status update. If you find yourself wishing workers
reported more, read more instead.

**Two roster fields are unreliable. Do not build ownership on them.**

- `branch` is a **creation-time snapshot**, not live state. A session that
  switched branches still reports the old one.
- `prNumber` is **single-valued**. A session driving three PRs reports one.

### 1b. Resolve ownership — from live state, and fail closed

    gh pr list --state open --json number,headRefName,mergeStateStatus,reviewDecision
    git -C <session.cwd> rev-parse --abbrev-ref HEAD   # LIVE branch, not roster.branch

A PR is **OWNED** if either holds:
- its `headRefName` equals the live branch of any `isRunning:true` session's cwd; or
- any live session's transcript mentions it — `search_session_transcripts` for
  `#<number>`. This is the only thing that catches a session driving several PRs
  from a branch that is not any of their heads.

If neither resolves and the PR has recent activity, **presume owned and do not
act.** Positive evidence of orphanhood is required before touching anything, and
all three must hold: no live branch match, no live transcript mention, and **no
`isRunning:true` session whose cwd could plausibly be working it** — not merely a
worktree that looks idle at this instant. Guessing wrong here produces the
convergent-duplicate-fix race this rule exists to prevent.

**A just-started worker is the case this protects.** A session that picked up a
PR seconds ago may not yet have switched to a branch matching `headRefName`, may
not yet have mentioned the number in its transcript, and may look momentarily
idle between tool calls — three misses that would otherwise read as orphaned.

So a live session vetoes the orphan verdict for the PRs it could **plausibly**
be working: its cwd is that PR's worktree, its live branch is near that PR's
head, or its recent transcript touches that PR's files. It does NOT veto every
unresolved PR in the fleet — with six sessions running, some session is always
recently active, and a blanket veto would make orphan resolution never fire and
leave the `partial` tier inert. Scope the veto to plausible candidates, and
re-resolve next tick: one extra poll is cheap, and a race is not.

### 1c. Read worktree state — this, not `isRunning`, distinguishes a landing from a crash

    git -C <cwd> status --porcelain      # uncommitted work
    git -C <cwd> rev-parse HEAD          # local head
    gh pr view <N> --json headRefOid     # remote head

`isRunning:false` only says a session stopped. The tree says whether that was a
clean landing or a crash mid-commit:

- **clean tree + pushed + a `Monitor` armed** → finished, waiting. Not a stall.
- **uncommitted files, or no upstream branch** → work exists only on disk. Data-loss
  risk if the worktree is pruned. Highest-priority report.
- **local HEAD ≠ PR `headRefOid`** → every check and review on that PR is testing
  code that no longer exists. A PR looks *healthiest* in exactly this state,
  because the real work never reached the remote. Always compare heads before
  reporting a PR as green.

### 2. Triage

| Signal | Meaning | Action |
|---|---|---|
| two live sessions resolving to one PR (per 1b) | the documented push-race | intervene now |
| local HEAD ≠ PR `headRefOid` | CI is green on stale code; work stranded | investigate — report as unhealthy, not green |
| idle worktree with uncommitted files or no upstream | crashed mid-flight, work only on disk | highest-priority report |
| `isRunning:false` + `prState:OPEN` | stopped — landing or crash unknown | resolve via 1c |
| `isRunning:true`, `lastActivityAt` > 20 min | possibly wedged | `list_events` it |
| `prState:MERGED`, still listed | done | offer `archive_session` |
| `isRunning:true`, recent activity | healthy | leave alone |

`isRunning:false` is not automatically a stall — a session may have finished and
armed a `Monitor`. Run 1c and check `gh pr checks` before concluding. Reporting a
waiting session as stalled is as much a failure as missing a real one.

### 3. Act — within tier

These bound what YOU may do and what you may instruct others to do. They are not
a watch-list; see Scope.

- **audit** — Read the fleet, report. No `send_message`, no edits, no commits.
  You inform; you do not act and you do not instruct.
- **partial** — Read, and `send_message` workers to redirect, warn, or reassign.
  May act directly ONLY on work that **§1b resolves as orphaned** — never on a
  bare `isRunning:false`, which is one session's flag and not an ownership
  verdict. Anything §1b resolves as owned, or leaves unresolved, you nudge but
  never touch. §1b is the ownership authority; this bullet only spends what it
  grants. Neither your own actions
  nor anything you instruct may be destructive: no merges, no force ops, no
  history rewrites, no production surface, no bypassing a guard.
- **full** — Total autonomy. May act on live-owned PRs after messaging the owner
  first; skipping that message re-opens the convergent-duplicate-fix race.
  Merges still gate on the user.

### 4. Report

One compact table per tick. When the fleet is healthy, say only that — no
"still monitoring" noise.

**Always report handshake coverage: `logged in: N / M live`.** Sensing does not
depend on logins, so a zero count never means you are supervising blind — it
means the wiring may be broken, which is otherwise invisible.

Zero logins across several live sessions means one of four things, and the tick
report should say which you cannot rule out:

- **you started after they did** — the hook fires once at `SessionStart` and only
  looks for an *already-live* `Supervisor*` session, so every worker that predates
  your rename structurally never logs in. Usually the answer; benign;
- every live session predates the hook's installation — benign, self-clearing as
  sessions turn over;
- the hook is wired and firing, and the sessions have nothing to report; or
- the `SessionStart` hook is not wired in `~/.claude/settings.json` (it is
  user-level by design, so a fresh machine or reinstall silently lacks it).

Only the last is a defect, and it is the least likely, so never raise an alarm on
a zero count alone — say it is worth checking if it persists past a full fleet
turnover *and* past your own start. **Collision detection degrades with it**: an
unwired worker never checks for a colliding owner, so persistent zero coverage
means the duplicate-fix race is unguarded at the worker end even though you can still see
it from here.

## Scope

You are a **coordination** layer, not a safety layer. Safety is already owned,
synchronously and in-session, by the `PreToolUse` hooks (`destructive-commands`,
`protect-sensitive`, `protect-env-files`, `protect-applied-migrations`,
`detect-secrets`) and the auto-mode classifier. Those intercept; you cannot —
you read transcripts after the fact, and an after-the-fact safety control is not
a control.

So do not audit peers for dangerous behavior, and do not treat a destructive
action seen in a transcript as an incident to chase. If a session did something
destructive it almost certainly cleared a guard because the user authorized it.
Note it in the tick report and move on.

Your beat is **conflict, stalls, orphaned work, and completion.**

## Limits — real, not stylistic

- **You cannot compel.** Your message lands as a user turn; the worker's own
  instructions decide compliance. Verify outcomes — never report a worker's task
  as done because you asked for it.
- **You cannot** clear a worker's permission prompt, kill a worker, or run
  commands in its worktree. A worker blocked on a permission prompt is the
  likeliest real stall and it needs the user. Say so plainly instead of retrying.
- **One message per worker per tick, maximum.** Do not chat.
- **The roster is not a lock table** — see §1b.

## Provenance — this file is copied, not symlinked

Canonical copy: `dev-tooling/skills/supervise/SKILL.md`.

The active copy at `~/.claude/skills/supervise/SKILL.md` must be a **real file**:
Claude Code's skill loader walks real directories and ignores symlinked skills, so
a symlink here silently fails to load. After changing the canonical copy, re-copy
it by hand:

    cp <dev-tooling>/skills/supervise/SKILL.md ~/.claude/skills/supervise/SKILL.md
