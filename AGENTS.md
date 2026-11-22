# Working on Agentic Dev Tooling

The reusable source is in `plugins/`. Start an issue with `plugins/core-lifecycle/skills/issue-creation/SKILL.md` and intake approved work through `plugins/core-lifecycle/skills/dev-lifecycle/SKILL.md`. Resolve relative references from the skill directory. Consult `CAPABILITIES.md` for the client's discovery paths, tools and trust requirements.

Use `install.sh codex --agents-only --project <checkout>` to provision supported Codex roles for a trusted project before opening a new session. Inspect custom project instructions and existing profiles before updating them. When a private organization profile is supplied by the host, use that profile for tasks it owns.

Changes to public packs belong here. Run the relevant scripts under `scripts/test-*.sh` and the public-content guard before proposing changes. Keep organization-specific values in consumer configuration.
