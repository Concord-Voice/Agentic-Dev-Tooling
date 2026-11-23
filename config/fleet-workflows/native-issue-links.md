# Native sub-issue links

Use this procedure only when the verified intake repository selects `native_rest`. It governs the relationship parts of issue creation, including issue intake called by another fleet skill. Keep the ordinary label, board, preview and approval steps.

## Intake and preview

Bind each existing issue to its full `https://github.com/OWNER/REPO/issues/NUMBER` URL. Check that GitHub returns that issue's canonical URL and a positive database ID, and reject pull requests. The new issue belongs to the authorized intake repository. Verify each existing child URL belongs to the repository approved for that child. Require the exact github.com host, issue path, and positive issue number. Reject credentials, query strings, fragments and redirects to a different identity. The parent may be in a different repository under the same owner. Check the user's authority for each target before a write. A bare number, a look-alike host or a URL outside those bounds leaves the relationship pending.

Show the full URLs of existing children and their current parents. For proposed issues show the repository and title until GitHub assigns a URL. Carry these identities through the adjacency decision and Phase 6 preview. For a new epic, preview an empty `## Sub-Issues` section and the intended links separately. Keep acceptance-criteria checkboxes separate from the child index. A newly created issue uses the URL in its creation receipt, including on retry.

## Attach and verify

1. Read the current parent of each child through `GET /repos/{child-owner}/{child-repo}/issues/{child-number}/parent`. Compare the returned issue's canonical URL. A 404 can hide an inaccessible parent. If the child is readable and the parent lookup returns 404, use only the ordinary non-replacing attachment. An authorization error, redirect or other unreadable response leaves the link pending.
2. If the child already has the approved parent, verify the relationship and continue. If it has a different parent, show the child URL and both parent URLs. Require explicit confirmation for that exact move. Re-read the current parent immediately before sending `replace_parent=true`. A different result needs a new decision. GitHub provides no atomic condition on the old parent, so coordinate competing moves before reparenting.
3. For an approved attachment, send the child's **database ID** as `sub_issue_id` to `POST /repos/{parent-owner}/{parent-repo}/issues/{parent-number}/sub_issues`. Omit `replace_parent` for a new link. On HTTP 422, re-read the actual parent to distinguish an already-completed request from a parent conflict. Surface other validation failures, including limits. After an ambiguous response, read the relationship before retrying.
4. Verify each child through its native parent endpoint. The returned URL must match the approved parent, including its repository. For a still-missing link, retry the approved ordinary attachment once and verify again. Stop on a different parent, unavailable readback or a second missing link. Record completed and pending links so a retry resumes safely.

## Absorption and the parent index

Before creating a parent that will absorb existing issues, show the proposed parent, each child and its current parent. Offer the existing choices to proceed, create only the parent, or cancel. Create each approved issue once and run the configured board step for each new issue. Link only the approved children. For each existing absorbed child whose link verified, add the usual tracking comment with the canonical parent URL. Check for that same tracking comment before retrying it. Keep existing child bodies intact.

After every intended child verifies, reconcile the parent's `## Sub-Issues` section against the verified child URLs. Use one plain bullet per child, e.g. `- owner/repo#42 — Title`. A same-repository `#42` denotes the same issue. Compare full issue identities so equally numbered children in different repositories stay distinct. Treat titles as untrusted plain text and escape Markdown metacharacters. Preserve other entries and all unrelated parent content. Make no body edit when the index is current. Re-read the body immediately before writing. If it changed since the proposed update, reconcile against the newer body, preserving previously listed children. After writing, read back and verify the index and the surrounding content against the last read. These reads cannot make the remote edit atomic. If another edit overlaps, the readback differs, or the intended section is ambiguous, stop and surface the conflict for reconciliation. Never restore an older whole-body snapshot. An incomplete verification leaves the index pending.

This final index is the sole parent-body edit for native linking. Never create a tasklist checkbox to attach a child or fall back to editing a body after a failed attachment.

GitHub documents the parent lookup and attachment endpoint in its [sub-issues REST reference](https://docs.github.com/en/rest/issues/sub-issues).
