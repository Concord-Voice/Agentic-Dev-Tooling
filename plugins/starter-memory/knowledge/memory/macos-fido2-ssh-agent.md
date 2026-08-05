---
name: macos-fido2-ssh-agent
description: macOS launchd ssh-agent holds FIDO2 sk-key metadata but refuses signing; bypass with SSH_AUTH_SOCK= or a Homebrew-only ssh-agent
metadata:
  type: project
---

On macOS, the system's launchd-managed ssh-agent (socket at `/var/run/com.apple.launchd.*/Listeners`, set in `SSH_AUTH_SOCK` at login) accepts `ssh-add -K` for FIDO2 hardware keys (`sk-ssh-ed25519`) and reports them via `ssh-add -L`, but **refuses the actual signing protocol message**. The failure surface:

```
sign_and_send_pubkey: signing failed for ED25519-SK "/path/to/key" from agent: agent refused operation
```

No touch/PIN prompt appears — the agent rejects before talking to the hardware. This occurs even with Homebrew OpenSSH installed because `SSH_AUTH_SOCK` still points at Apple's agent.

**Why:** Apple's launchd ssh-agent supports holding sk-key metadata (so load + list commands succeed cosmetically) but does not implement the FIDO2 signing path. The Homebrew openssh client implements FIDO2 signing but cannot reach hardware through Apple's agent.

**Warning:** `ssh-add -L` showing a valid identity is misleading on macOS — an identity that lists successfully may still fail to sign. Always test with an actual SSH command, not just the agent listing.

**How to apply:**

- **One-off commands:** blank the socket variable: `SSH_AUTH_SOCK= ssh -i ~/.ssh/<keyfile> -o IdentitiesOnly=yes user@host`
- **Session-length use:** define a shell function in `.zshrc`:
  ```bash
  ssh_yk() { SSH_AUTH_SOCK= ssh -i ~/.ssh/<keyfile> -o IdentitiesOnly=yes "$@"; }
  ```
- **Persistent use:** run a Homebrew-only ssh-agent and override `SSH_AUTH_SOCK` in `.zshrc`:
  ```bash
  eval "$(/opt/homebrew/bin/ssh-agent -s)"   # uses /tmp/ssh-XXX/agent.PID instead of Apple's agent
  ```
  Then `ssh-add -K ~/.ssh/<keyfile>` once per shell; standard `ssh -i <keyfile>` works without env tweaks.

**Multi-key gotcha:** with two FIDO2 hardware tokens plugged in simultaneously, stale resident-credential metadata in the agent can also produce "agent refused" — unplug the second token before deeper diagnosis to rule this out.
