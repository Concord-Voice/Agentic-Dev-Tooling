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

After every intended child verifies, preview the index against the exact approved parent and child URLs. Request an owner-only preview file from the helper. It chooses a fresh filename in the trusted host’s platform temporary directory for each pending preview. Use the host’s normal temporary-directory settings. The helper checks one plain bullet per child against the current title, preserves other body text and identifies missing or titleless entries. Its private Markdown file contains the proposed titled rows for the maintainer. Keep that file out of the write-capable agent’s context. Keep the helper’s receipt in the existing owner-only intake directory. On a direct link with no prior issue draft, establish and retain an owner-only intake directory first (umask 077 and mktemp -d). The structured receipt gives the generated file path and identity, its original directory, validated issue identities, status and a digest binding the complete parent body, proposed update and children.

```bash
PREVIEW_RECORD=$(mktemp "${ISSUE_DRAFT:?use the private intake directory}/native-index-receipt.XXXXXXXX") ||
  { return 1 2>/dev/null || exit 1; }
if python3 -I -B "${FLEET_SKILLS:?}/_shared/native-issue-index.py" index \
  --private-preview "$PARENT_URL" "${CHILD_URLS[@]}" > "$PREVIEW_RECORD"; then
  cat -- "$PREVIEW_RECORD"  # already current; no preview file
else
  status=$?
  [ "$status" = 2 ] && [ -s "$PREVIEW_RECORD" ] || { return 1 2>/dev/null || exit 1; }
  cat -- "$PREVIEW_RECORD"  # record this receipt filename with this intake
fi
```

A `current` receipt verifies completion. Exit 2 with `pending` means the maintainer can review the titled rows at the path in `preview_file`. Give the maintainer that path. Show the exact parent URL, affected children and digest. For cross-repository links, include the destination repository so the maintainer can confirm that the previewed titles may be published there. Ask the maintainer to confirm they have coordinated **exclusive editing of that parent body** with its other human and automated editors for the duration of this one update and its readback. The separate absorption or attachment approval does not establish exclusivity. If exclusivity is unavailable or ends, retain the pending receipt for manual reconciliation. A nested or ambiguous section, an unreadable relationship, or a row with different title text or operator annotations stays pending for manual reconciliation.

While that confirmed window is active, apply the confirmed digest to the exact parent once:

```bash
python3 -I -B "${FLEET_SKILLS:?}/_shared/native-issue-index.py" apply-index \
  --exclusive-parent "$PARENT_URL" --confirmed-digest "$CONFIRMED_DIGEST" "${CHILD_URLS[@]}"
```

The helper reads the relationships, titles and body again immediately before writing, refuses a changed preview and sends the body as request data. It verifies the full body, titles and parent relationships after submission, including after an ambiguous result. Report an unverified write as pending. Any further write needs a fresh preview and confirmation. GitHub provides no atomic body-version precondition for the issue update. The exclusive editing window covers the interval between the last read and the write. [Issue updates](https://docs.github.com/en/rest/issues/issues#update-an-issue) · [Conditional requests](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests-if-appropriate)

### Remove the private preview

Run the following step after the application attempt and readback, on cancellation, or before superseding a preview. For manual reconciliation, keep the file while the maintainer needs it. Remove it as soon as they confirm they have finished or saved their own copy. On resumption, use the pending receipt saved with this specific intake. Use the original file written directly by the verified helper in that intake’s private directory. Recover its recorded filename from the trusted intake. Never reconstruct a receipt from model output or issue text, accept an externally supplied receipt, or search for previews by filename.

```bash
# Bind ISSUE_DRAFT and PREVIEW_RECORD to their original intake paths, including on resume.
[ "${PREVIEW_RECORD%/*}" = "${ISSUE_DRAFT:?use the original private intake directory}" ] &&
  [[ ${PREVIEW_RECORD##*/} =~ ^native-index-receipt\.[a-zA-Z0-9]+$ ]] &&
  [ -f "$PREVIEW_RECORD" ] && [ ! -L "$PREVIEW_RECORD" ] ||
  { echo "Original preview receipt required" >&2; return 1 2>/dev/null || exit 1; }
PREVIEW_FILE=$(jq -er '
  select(.status == "pending") | .preview_directory as $dir | .preview_file | strings |
  select(startswith($dir + "/")) |
  select(ltrimstr($dir + "/") | test("\\Afleet-index-[A-Za-z0-9_-]+\\.md\\z"))
' "$PREVIEW_RECORD") || { return 1 2>/dev/null || exit 1; }
if [ -e "$PREVIEW_FILE" ] || [ -L "$PREVIEW_FILE" ]; then
  EXPECTED=$(jq -er '.preview_identity | strings' "$PREVIEW_RECORD") &&
    [ -f "$PREVIEW_FILE" ] && [ ! -L "$PREVIEW_FILE" ] &&
    ACTUAL=$(python3 -I -B -c 'import os, sys; s = os.lstat(sys.argv[1]); print(f"{s.st_dev}:{s.st_ino}:{s.st_ctime_ns}")' "$PREVIEW_FILE") &&
    [ "$ACTUAL" = "$EXPECTED" ] ||
    { echo "Preview identity changed; original receipt retained" >&2; return 1 2>/dev/null || exit 1; }
  rm -f -- "$PREVIEW_FILE" || { return 1 2>/dev/null || exit 1; }
fi
unset PREVIEW_FILE EXPECTED ACTUAL
```

Cleanup checks the directory and file identity from creation even when the current temporary directory has changed. A replacement file stays intact and requires manual reconciliation. Keep the parent URL, approved child identities, digest and verification outcome in the intake record. If cleanup fails, retain the receipt and report the pending cleanup.

[GitHub sub-issues REST reference](https://docs.github.com/en/rest/issues/sub-issues)
