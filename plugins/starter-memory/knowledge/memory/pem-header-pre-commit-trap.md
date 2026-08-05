---
name: pem-header-pre-commit-trap
description: A literal -----BEGIN PRIVATE KEY----- in any file trips both detect-secrets and detect-private-key pre-commit hooks; use a placeholder like <inline PEM with BEGIN/END markers> instead
metadata:
  type: project
---

When writing a spec, plan, or any markdown that documents an environment-variable format containing PEM key bytes (e.g., TLS certs, signing keys, API private keys), the literal string `-----BEGIN PRIVATE KEY-----` (or matching variants like `-----END PRIVATE KEY-----`, `-----BEGIN RSA PRIVATE KEY-----`) trips two separate pre-commit hooks:

- **`detect-secrets`** — flags it as `Secret Type: Private Key`.
- **`detect-private-key`** (pre-commit's built-in hook) — flags it with a regex match.

**Why both matter:** The two hooks have different override mechanisms. `detect-secrets` honors `# pragma: allowlist secret` inline comments; `detect-private-key` is regex-only and does NOT honor pragmas. Adding a pragma silences only `detect-secrets`. Adding an entry to `.secrets.baseline` silences only `detect-secrets`. There is no inline escape that silences `detect-private-key` — only removing the triggering string works.

**How to apply:** When documenting a PEM env-var format in any spec, plan, or markdown file, never include the literal `-----BEGIN PRIVATE KEY-----` string. Use a placeholder pattern instead:

```
SOME_PRIVATE_KEY="<inline PEM with BEGIN/END PRIVATE KEY markers, newlines escaped as \n>"
```

This preserves documentation clarity (the reader knows the format includes BEGIN/END markers) without placing a triggerable string in the file. The text `BEGIN PRIVATE KEY` without the surrounding `-----` dashes does NOT trip either hook.

**How to apply to other PEM variants:** The same rule applies to `-----BEGIN RSA PRIVATE KEY-----`, `-----BEGIN EC PRIVATE KEY-----`, and similar PEM headers — replace the literal header with a descriptive placeholder in documentation.
