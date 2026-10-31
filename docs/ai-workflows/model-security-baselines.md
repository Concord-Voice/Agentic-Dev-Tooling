# Model Security Baselines

| Field          | Value      |
|----------------|------------|
| Effective Date | 2026-04-03 |
| Version        | 1.0        |
| Review Cadence | Quarterly  |

## Purpose

Security-focused system prompts are not optional. The difference between a default prompt and a security-hardened prompt can change the share of secure code output dramatically (see the estimates below). This document tracks known baselines to inform tool configuration and review practices.

## Industry Data

Source: [Veracode GenAI Code Security Report (2025)](https://www.veracode.com/resources/analyst-reports/2025-genai-code-security-report/)

- 100+ LLMs tested across Java, JavaScript, Python, and C#
- **45%** of AI-generated code samples contained OWASP Top 10 vulnerabilities
- AI-generated code has **2.74x more vulnerabilities** than human-written code
- XSS (CWE-80): **86% failure rate**
- Log injection (CWE-117): **88% failure rate**
- All major LLMs generate code vulnerable to at least 4 of CWE Top 10 categories

Secret leak data from [GitGuardian State of Secrets Sprawl 2025](https://blog.gitguardian.com/yes-github-copilot-can-leak-secrets/):

- Repositories using Copilot leak secrets at a **40% higher rate** than baseline (6.4% vs 4.6% of ~20,000 sampled repos)

## Model-Specific Observations

| Model Family | Default Secure Rate | With Security Prompts | Notes |
|---|---|---|---|
| Claude (Anthropic) | ~60% | ~95-100% | Best baseline; responds strongly to security-focused instructions |
| GPT-4o (OpenAI) | ~10% | ~70-85% | Significant improvement with prompting but still requires review |
| Codex (OpenAI) | ~10% | ~50-70% | Legacy model; lower ceiling even with hardened prompts |
| Copilot (GitHub) | ~15-25% | ~60-80% | Depends on underlying model; benefits from copilot-instructions.md |

These figures are rough internal estimates, not sourced or measured benchmarks; the Veracode report above does not break results down by model. Treat them as directional only and replace them with your own measurements. Rates vary by language, vulnerability type, and prompt complexity.

## Implications for This Project

1. **Security-focused system prompts** (`CLAUDE.md`, `copilot-instructions.md`) are the primary control determining whether AI output is secure. Without them, AI tools generate vulnerable code the majority of the time.

2. **Human review remains essential** — no model achieves 100% across all vulnerability types, even with hardened prompts.

3. **The RCI workflow** (see `rci-workflow.md`) provides an additional safety layer by having the model self-review before presenting code.

4. **Model selection matters.** Measure candidate models on your own security-sensitive tasks before choosing a primary tool; the estimates above are a starting hypothesis, not evidence.

## Model Version Pinning

- When practical, pin AI tool model versions in project configuration to avoid security regressions from model updates.
- Claude Code: model specified in project settings or CLI flags.
- GitHub Copilot: model selection in IDE settings.
- Monitor model changelogs for security-relevant changes.
- Re-evaluate baselines after major model updates.

## Quarterly Review

Update this document during the quarterly AI security review (a recurring issue or calendar reminder in the consuming project):

- Re-assess model baselines if new research is published or models are updated
- Track whether the RCI workflow and hardened prompts are maintaining expected secure output rates
- Update the model-specific observations table with any new data

## Related Documents

- [RCI Workflow](rci-workflow.md)
- Your project's AI-generated code policy
- CLAUDE.md — "AI Code Generation Security Constraints" section
