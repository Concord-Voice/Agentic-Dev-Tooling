# Native sub-issue links

Use this procedure when the verified intake repository selects `native_rest`, including nested intake. Preserve the ordinary label, board, preview and approval steps.

## Intake and preview

Use the signed-in host's trusted GitHub CLI and the materialized edition's helper. For each user-approved existing parent or child, run this command with its full GitHub issue URL.

```bash
python3 -I -B "${FLEET_SKILLS:?}/_shared/native-issue-index.py" inspect "$ISSUE_URL"
```

Only the helper handles raw GitHub responses. Its successful inspection returns the verified issue URL, positive REST database ID and canonical current parent URL or null. Match the requested child repository and the approved same-owner parent. Use the helper's structured identities throughout. Keep titles, bodies, comments and API error text outside the write-capable agent's context. When inspecting or writing a relationship, omit debug tracing and raw API output. A failed inspection leaves the relationship pending.

Show existing children and their current parents by full URL. Show new issues by approved repository and proposed title until GitHub assigns a URL. For an absorbing parent, preview an empty `## Sub-Issues` section and the intended links separately. A retry uses the existing creation receipts. Never copy a remote child title into the agent's preview.

## Attach and verify

1. Inspect the child and parent immediately before attachment. If the child already has the approved parent, record the verified link. A missing visible parent permits only an ordinary, non-replacing attachment.
2. For a move, show the child, old parent and new parent by URL. Obtain confirmation for that exact move. Inspect again immediately before sending `replace_parent=true`. A change requires another decision. Coordinate competing moves because GitHub offers no atomic precondition on the previous parent.
3. Send the verified child's **database ID** as the numeric `sub_issue_id` to `POST /repos/{parent-owner}/{parent-repo}/issues/{parent-number}/sub_issues`. Use the fixed github.com host and `gh api --silent`. Discard stderr and use the exit status. Omit `replace_parent` for ordinary attachments.
4. On success, conflict or ambiguous failure, inspect the child again. Compare full parent URLs. Retry a still-missing ordinary link at most once. Stop on a different parent, unreadable readback or a second failure. Record verified and pending child identities before continuing.

## Absorption and the parent index

Before any Phase 7 write for a parent absorbing existing issues, show the proposed parent, children and current parents. Offer the choices to proceed, create only the parent, or cancel. Create each approved issue once and run its configured board step. Keep existing child bodies intact. For a verified existing absorbed child, use the isolated collector to check for the existing tracking comment. Return only a validated presence flag. If absent, post the fixed tracking comment with the verified parent URL using a silent request. If presence cannot be verified, leave the comment pending.

After every intended child verifies, preview the index against the exact approved parent and child URLs. Request an owner-only preview file from the helper. It chooses a fresh temporary filename for each pending preview. The helper checks one plain bullet per child against the current title, preserves other body text and identifies missing or titleless entries. Its private Markdown file contains the proposed titled rows for the maintainer. Keep that file out of the write-capable agent’s context. The structured receipt gives the preview file path, validated identities, status and a digest binding the complete parent body, proposed update and children.

```bash
python3 -I -B "${FLEET_SKILLS:?}/_shared/native-issue-index.py" index \
  --private-preview "$PARENT_URL" "${CHILD_URLS[@]}"
```

A `current` receipt verifies completion. Exit 2 with `pending` means the maintainer can review the titled rows at the path in `preview_file`. Give the maintainer that path. Show the exact parent URL, affected children and digest. For cross-repository links, include the destination repository so the maintainer can confirm that the previewed titles may be published there. Ask the maintainer to confirm they have coordinated **exclusive editing of that parent body** with its other human and automated editors for the duration of this one update and its readback. The separate absorption or attachment approval does not establish exclusivity. If exclusivity is unavailable or ends, retain the pending receipt for manual reconciliation. A nested or ambiguous section, an unreadable relationship, or a row with different title text or operator annotations stays pending for manual reconciliation.

While that confirmed window is active, apply the confirmed digest to the exact parent once:

```bash
python3 -I -B "${FLEET_SKILLS:?}/_shared/native-issue-index.py" apply-index \
  --exclusive-parent "$PARENT_URL" --confirmed-digest "$CONFIRMED_DIGEST" "${CHILD_URLS[@]}"
```

The helper reads the relationships, titles and body again immediately before writing, refuses a changed preview and sends the body as request data. It verifies the full body, titles and parent relationships after submission, including after an ambiguous result. Report an unverified write as pending. Any further write needs a fresh preview and confirmation. GitHub provides no atomic body-version precondition for the issue update. The exclusive editing window covers the interval between the last read and the write. [Issue updates](https://docs.github.com/en/rest/issues/issues#update-an-issue) · [Conditional requests](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests-if-appropriate)

[GitHub sub-issues REST reference](https://docs.github.com/en/rest/issues/sub-issues)
