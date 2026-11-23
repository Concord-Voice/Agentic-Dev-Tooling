# PR review dispatch

## Codex review of untrusted PRs

Before fetching a diff or passing PR-authored input to a reviewer, run the independent worker from the verified public tooling checkout. For each required public role, run `python3 -I -B "$ADT/scripts/codex-isolated-review.py" --role code-reviewer --check`, substituting its exact role. After a successful preflight a trusted collector may stage the diff in a private regular file without exposing it to the parent. Supply that file using `--input "$review_input"`. Each run rechecks the effective read-only sandbox, approvals, tool inventory and connector isolation before opening input. Accept only validated codes and numeric line references. Retain the original lines privately for human inspection. A missing or incomplete worker receipt leaves review pending. A native child of a privileged parent cannot substitute for this worker.

On another host, verify effective read-only access and provenance before supplying review data. For a private reviewer, require independent confinement and a deterministic reports-only return boundary as well as the verified identity described in [the nested skill contract](nested-skills.md). Give the Context7 researcher a fresh session with only the two documentation tools and a public package question. Gather repository evidence separately. Keep caller credentials, writes and raw model responses outside the reviewer handoff.

## Agent dispatch

| Required coverage | Eligible role |
| --- | --- |
| Security for every change, including Phase 4 for a security label or sensitive changed surface, then again on the PR head | security-reviewer |
| Correctness, regressions and tests | code-reviewer |
| Documentation consistency | docs-reviewer |
| Scope of the PR | scope-reviewer |
| Frontend changes | frontend-reviewer |
| Database migrations | migration-reviewer |

Use the applicable rows on the current head. Deduplicate a shared role. Record the head SHA, availability, exact role and result for each required row. Project labels, paths and trusted configuration can add a separate **requested coverage area**, never a dispatch identity. When the known private catalog supplies an independently verified read-only specialist for that area, use its explicit identity under the nested skill contract. Otherwise record the unmet requirement and leave final approval pending. A service receipt covers only the service, role and exact head it identifies.

Inspect source, security invariants, existing evidence and benign tests. Rank concrete results by severity, affected location and required mitigation. Separate verified findings from unknowns. Report informational items separately. Keep authorization and merge disposition with the parent. Write reviewer names bare in GitHub messages.
