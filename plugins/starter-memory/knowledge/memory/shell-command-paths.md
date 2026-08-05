---
name: shell-command-paths
description: When giving shell commands for the user to copy-paste, use plain-text paths only; chat-renderer auto-links survive copy-paste and break zsh
metadata:
  type: feedback
---

When providing shell commands for the user to copy-paste, every path inside the command must be plain text — even inside a fenced code block. Do NOT include markdown-link syntax like `[file.sh](http://file.sh)` in the command itself.

**Why:** Twice in one session, I provided `chmod +x .claude/hooks/protect-sensitive.sh` in a way that the chat renderer auto-converted to `chmod +x .claude/hooks/[protect-sensitive.sh](http://protect-sensitive.sh)`. When the user copy-pasted into zsh, zsh interpreted `(http:...)` as the `:h` filename modifier and threw `unknown file attribute: h`. The user had to retype each command manually. This is friction caused entirely by my output formatting decision.

**How to apply:**
- Inside a `bash` or `shell` fenced code block, write paths as bare strings: `chmod +x .claude/hooks/protect-sensitive.sh`
- If a path needs to be clickable elsewhere in the response (e.g., in prose explanations), keep that markdown-link reference OUTSIDE the code block
- The output-style instruction "format file references as markdown links so the user can click to open them" applies to PROSE, not to runnable commands
- Quick check before sending: would copy-pasting this command verbatim into a real shell work? If `[`, `]`, `(`, `)` appear anywhere on a path, no — fix before sending
- Same caution applies to `chmod`, `git`, `cd`, `rm`, `cp`, `mv`, `cat`, anywhere a literal path is consumed
