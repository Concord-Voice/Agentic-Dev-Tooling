# Preserve installed hook quoting implementation plan

1. Confirm the affected source contract on the current default branch.
2. Use the safe matcher to recognize managed hooks for deduplication and drift checks. Keep a custom whole-path-quoted command intact in project settings. For user settings, replace the project anchor with the literal absolute install root inside the original quotes. Leave unsupported forms untouched.
3. Extend the installer fixture with a quoted hook filename containing parentheses. Run scripts/test-install.sh and keep canonical deduplication and malformed path cases passing.
4. Run the applicable independent reviews and required CI. Request merge approval for the reviewed head.
