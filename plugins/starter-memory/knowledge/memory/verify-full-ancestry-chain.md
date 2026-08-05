---
name: verify-full-ancestry-chain
description: Multi-level issue hierarchies may have broken native parent links from retroactive body edits; verify all levels via GraphQL at session start and force-link via REST where broken
metadata:
  type: feedback
---

When working on a multi-level GitHub issue hierarchy (grandparent epic → parent epic → grandchildren), verify the full native-parent chain at session start. Do not assume upstream links work just because the new links being filed work.

**Why:** Retroactive body edits on parent issues (adding children to an existing body) trigger GitHub's tasklist auto-detect, which frequently fails on programmatic edits (see `tasklist-autolink-unreliable`). This means first-level children added retroactively are the most likely to have broken native parent links — even while second-level grandchildren filed cleanly via automation have correct links. The upstream chain can be silently orphaned from an earlier session, and the gap only surfaces via post-merge user questions or dashboard anomalies.

**How to apply:** At the start of any multi-level hierarchy work:

1. **Map the intended chain.** For example, for a parent epic `<P>` with grandparent `<G>` and children `<C1>...<Cn>`: identify all levels — `<G> → <P> → <C*>`.
2. **Verify each level via GraphQL** (the authoritative source — issue-body tasklist text can appear correct while the graph API returns empty):
   ```bash
   gh api graphql -f query='{ repository(owner: "<owner>", name: "<repo>") { issue(number: <N>) { parent { number } subIssues(first: 30) { nodes { number } } } } }'
   ```
   Check `parent.number` matches the intended grandparent AND `subIssues.nodes` includes the expected children. If either is empty or wrong, the chain is broken at that level.
3. **Force-link via REST** any broken levels:
   ```bash
   gh api --method POST repos/<owner>/<repo>/issues/<PARENT>/sub_issues -F sub_issue_id=<CHILD_NODE_ID>
   ```
   The child node id is the internal numeric id returned by `GET /repos/{owner}/{repo}/issues/{child}` as `.id` (not `.number`).
4. **Re-verify after fixes** with a fresh GraphQL `subIssues` query — the POST response may show a misleading `sub_issues_count: 0` due to UI caching.

**When this matters most:** Multi-level epics decomposed via brainstorms where first-level children were added to the grandparent body retroactively. The first level is where the chain is most likely already broken before the session starts.

**Cost:** ~5 seconds per level to verify, plus ~2 seconds per force-link if needed. Far cheaper than discovering the breakage via a post-merge question.

**Connects with:** `tasklist-autolink-unreliable` (the canonical failure mode), `branch-name-autolink-autoclose` (different auto-detection failure mode), `board-done-autoclose`.
