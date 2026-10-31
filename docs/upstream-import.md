# Upstream import

`scripts/upstream-import.sh` keeps a private repo current with the public repo it was split from, for example Self-Hosted into Hosted, or this repo into Internal-Dev-Tooling. It never overwrites what the private repo owns.

It replays upstream's diff since the last import, limited to the paths upstream owns, with `git apply --3way`. A file the private repo edited keeps its edits, and only the lines upstream changed move. When both sides changed the same lines, the result is a conflict for a person to resolve, never a silent overwrite. The script stages the change and never pushes; the caller opens a pull request.

## Downstream config

`.github/upstream-sync.json` holds path prefixes, not globs:

```json
{
  "upstream": "Concord-Voice/Self-Hosted",
  "import": ["services/", "client/admin/", "packages/"],
  "private": [".github/workflows/deploy-", "CLAUDE.md", ".claude/"]
}
```

`.github/upstream-sync.lock` holds the full SHA of the last upstream commit imported. Set it once, by hand, to the upstream commit the private repo is level with.

## Refusals

The script stops with exit 1, before staging anything, when:

- an `import` prefix overlaps a `private` one;
- the upstream commit does not descend from the lock;
- the diff adds an `[internal]` token. That's damage from the public-repo scrub; fix it upstream first.

Exit 2 means it hit conflicts. The lock is staged and the conflicted files are left unmerged. Upstream changes outside `import` are listed as skipped and not applied.

## Caller workflow (in the private repo)

```yaml
on:
  schedule: [{cron: '0 6 * * 1'}]
  workflow_dispatch:
permissions:
  contents: write
  pull-requests: write
jobs:
  import:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha> # v7
      - uses: actions/checkout@<sha> # v7, the public upstream: no token needed
        with: {repository: Concord-Voice/Self-Hosted, path: .upstream, fetch-depth: 0, persist-credentials: false}
      - uses: actions/checkout@<sha> # v7, this tool at a pinned commit
        with: {repository: Concord-Voice/Agentic-Dev-Tooling, ref: <sha>, path: .tool, persist-credentials: false}
      - run: |
          git switch -c "upstream-import/$(git -C .upstream rev-parse --short HEAD)"
          bash .tool/scripts/upstream-import.sh .upstream || [ $? -eq 2 ]
          # commit and open the PR with gh; it merges only after review
```

Add `.upstream/` and `.tool/` to the private repo's `.gitignore`. That keeps the two checkouts out of the import commit.
