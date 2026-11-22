# Working on Agentic Dev Tooling

The reusable source is in `plugins/`. For issue authoring and the development lifecycle through native checkout discovery, resolve `issue-creation` or `dev-lifecycle` from the pinned fleet edition described in `CAPABILITIES.md`. Run `python3 -I -B "$ADT/scripts/resolve-fleet-workflow.py" --cache "$PRIVATE_CACHE" --skill dev-lifecycle` from a trusted public revision, and follow that returned file and its adjacent references. Use a private owner-controlled cache outside the checkout. An unavailable edition or required native role leaves that step pending.

Use `install.sh codex --agents-only --project <checkout>` to provision supported Codex roles for a trusted project before opening a new session. For untrusted PRs, use the independent Codex review worker from the verified tooling revision. Check isolation before obtaining the diff. See `CAPABILITIES.md`. Inspect custom project instructions and existing profiles before updating them. Use a privately supplied defensive specialist only when its owner, pinned profile, imports and effective tools can be independently verified.

Changes to public packs belong here. Run the relevant scripts under `scripts/test-*.sh` and the public-content guard before proposing changes. Keep organization-specific values in consumer configuration.
