---
name: release-checklist
description: Run release verification checks for a new version
argument-hint: [version]
disable-model-invocation: true
allowed-tools:
  - Bash(git *)
  - Bash(gh *)
  - Bash(npm *)
  - Bash(go *)
  - Read
  - Grep
  - Glob
---

Release checklist for version **$0**.

> Paths below use `frontend/` and `backend/` as literal stand-ins for this
> repo's actual frontend and backend directories (e.g. `apps/desktop/` and
> `services/api/`) — adjust every occurrence to your actual layout
> before running these commands.

## 1. Version Consistency

- [ ] Check current version: `cat frontend/package.json | jq .version`
- [ ] Verify tag doesn't exist: `git tag -l "<tag-prefix>$0"` — use the repo's
      actual release-tag scheme (e.g. `v$0`, or a prefixed `app-v$0`). Check it
      with `git tag -l | head` first: a pattern that matches no tag in the repo
      returns empty for every version and can never fire.
- [ ] Verify no release is published for it: `gh release view "<tag-prefix>$0"`
      (expect `release not found`). Do NOT check with `gh release list` or
      `GET /releases/latest` — if every release is a prerelease, that endpoint
      404s and the check proves nothing.
- [ ] Desktop version matches: `frontend/package.json`

## 2. CI Status

- [ ] All GitHub Actions passing on main: `gh run list --branch main -L 5`
- [ ] SonarQube Quality Gate passing
- [ ] No open release-gating issues: `gh issue list --label "risk: release-gate" --state open --json number,title,milestone`

      Do **not** add `--milestone "v$0"` when `$0` is a PATCH version
      (`0.2.42`) and milestones exist only at MINOR granularity (`v1.0.0`,
      `v1.1.0`, …). A patch-version milestone filter matches nothing and exits 0,
      so the check passes vacuously while release-gate issues are open. List them
      all and confirm by eye that none belongs to the milestone this tag ships
      toward.

## 3. Test Suite

- [ ] Go tests pass: `cd backend/ && go test ./... -race`
- [ ] Frontend tests pass: `cd frontend/ && npx vitest run`
- [ ] Coverage >= 80% on new code (SonarQube enforced)

## 4. Security Checks

- [ ] No critical Dependabot alerts: `gh api repos/{owner}/{repo}/dependabot/alerts --jq '[.[] | select(.state=="open" and .security_advisory.severity=="critical")] | length'`
- [ ] Pre-commit hooks pass on HEAD: `pre-commit run --all-files`
- [ ] No secrets in codebase: `gitleaks detect --source .`

## 5. Documentation

- [ ] CHANGELOG.md updated for v$0
- [ ] CLAUDE.md counts current (migrations, stores, routes)
- [ ] API docs reflect any new endpoints

## 6. Build Verification

- [ ] Desktop build succeeds locally: `cd frontend/ && npm run build`
- [ ] Go build succeeds: `cd backend/ && go build ./...`

## 7. Release Steps

Once all checks pass:
1. Bump version in `frontend/package.json` to `$0`
2. Commit: `git commit -m "chore: bump version to $0"`
3. Push to main and let the repo's release workflow run. If the main-branch CI
   workflow **dispatches** the release build through the REST API (rather than via
   `workflow_call`, e.g. because a called workflow cannot reach the release
   environment's secrets), the build is a separate run.
4. Monitor build: `gh run list --branch main -L 1 --workflow <release-workflow>.yml`.
   **A dispatched release run is `event_name == 'workflow_dispatch'` and appears
   under the release workflow, not the dispatcher.** The dispatcher shows only its
   dispatch step, not the build/signing matrix — watching it is the common mistake.
5. Verify release artifacts on GitHub Releases page

## 8. Post-Release

- [ ] Close milestone — **only when this tag completes a MINOR milestone.** A
      patch release does not close a milestone. Milestones are `v1.0.0`,
      `v1.1.0`, … and a patch tag usually ships *toward* one rather
      than completing it. When it does complete one:
      `gh api repos/{owner}/{repo}/milestones/{id} -X PATCH -f state=closed`
- [ ] Verify auto-updater delivers to existing clients
- [ ] Smoke test: login and core user flows on a fresh install
