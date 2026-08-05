---
name: macos-screen-recording-workaround
description: macOS TCC Screen Recording stale cache — toggling off/on does not reset it; REMOVE the app from the panel entirely and re-add to force a fresh permission grant
metadata:
  type: project
---

When an application reports Screen Recording denied despite macOS System Settings → Privacy & Security → Screen & System Audio Recording showing the app is toggled on, the macOS TCC (Transparency, Consent, and Control) permission cache for Screen Recording has gone stale.

**Why:** Toggling the permission off and back on does NOT evict the TCC cache that the application reads at runtime. The Settings UI may show "granted" while the app's runtime API still sees stale denied state. This commonly occurs after rebuilding, reinstalling, or updating the application.

**How to apply:**

1. Open System Settings → Privacy & Security → Screen & System Audio Recording.
2. Click the `−` button to **remove the app from the list entirely** (not just toggle off).
3. Re-launch the application — it will re-prompt the OS for permission.
4. Click `+` to add back, or accept the permission prompt when it appears.
5. Restart the application.

Toggling off→on is insufficient. Removing entirely is the only reliable reset.

**Note:** This stale-cache behavior appears specific to Screen Recording in macOS TCC. Microphone and Camera permissions do not exhibit the same stale-cache problem — they typically respond to a simple toggle. Do not assume the same workaround is needed for other permission types.
