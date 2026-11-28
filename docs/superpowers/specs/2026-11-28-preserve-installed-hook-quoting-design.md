# Preserve installed hook quoting

The installer rewrites whole-path-quoted adopter hooks. Path characters such as parentheses then reach Bash unquoted.

Recognize managed hooks for deduplication and drift checks. Preserve whole-path quoting for custom commands in project settings. In user settings, shell-quote the absolute path for a complete literal hook path and preserve any following command text. Leave unsupported forms untouched.

## Acceptance criteria

Extend the installer fixture with a quoted hook filename containing parentheses. Run scripts/test-install.sh and keep canonical deduplication and malformed path cases passing.
