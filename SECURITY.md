# Security

> **Reporting a vulnerability?** Follow the [disclosure policy](https://github.com/Concord-Voice/.github/blob/main/SECURITY.md). Do not open a public issue.

## Threat model summary

This repository ships no network service. It ships instructions and guard scripts that AI coding agents follow, with real tool access, on developer machines and in the CI of consuming repositories.

- It is a supply chain: one merged change reaches every consumer.
- Its main assets are the integrity of agent instructions, the hooks that limit agents, and the developer authority that agents borrow.
- Its main adversaries are text that agents read (issues, comments, reviews, web pages), compromised install-time dependencies, and a misdirected agent.
- Hooks are one layer. They are pattern guards and they do not reach every platform.

The full model is in [docs/threat-model.md](docs/threat-model.md).

## Guidance for automated review

This section is guidance for reviewers and scanners. It is not the disclosure scope; the disclosure policy linked above sets that.

**Report**

- A blocking hook that allows a call when its tool is missing, its input is malformed, or it times out.
- A new or wider bypass channel, or a way for an agent to authorize itself.
- A skill or agent that acts on directives in fetched content, or that puts user-authored text on a command line.
- A path that merges without a human decision, or an unattended action beyond those the model lists (push a work branch, open a draft pull request, mark it ready, comment).
- An installer or sync path that writes outside its target, overwrites local edits, or runs upstream code beside a write token.
- An unpinned action, tool or package, and any secret value in the tree.
- A way for a pull request to reduce its own review.

**Do not report**

- That a pattern guard does not cover every shell construct, unless you name a construct an agent would plausibly use. The guards document this limit.
- Capability gaps already listed in `CAPABILITIES.md`.
- Behaviour of third-party plugins that this repository only references.
- Example values and placeholders in `config/`.

**Severity**

- Critical: remote code execution on developer machines or in consumer CI, or a change to agent instructions, that reaches consumers without review.
- High: an agent can pass a guard, authorize itself, or disclose a secret.
- Medium: a control that fails open under an unusual precondition, or review evidence that can be imitated.
- Low: missing pins in CI-only tooling, and documentation that overstates a control.
