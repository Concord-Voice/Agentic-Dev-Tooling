# Preserve installed hook quoting

The installer rewrites whole-path-quoted adopter hooks. Path characters such as parentheses then reach Bash unquoted.

Use the safe matcher to recognize managed hooks for deduplication and drift checks. Keep a custom whole-path-quoted command intact in project settings. For user settings, replace the project anchor with the literal absolute install root inside the original quotes. Leave unsupported forms untouched.

## Acceptance criteria

Extend the installer fixture with a quoted hook filename containing parentheses. Run scripts/test-install.sh and keep canonical deduplication and malformed path cases passing.
