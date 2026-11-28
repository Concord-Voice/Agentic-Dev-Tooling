# Preserve installed hook quoting

The installer rewrites whole-path-quoted adopter hooks. Path characters such as parentheses then reach Bash unquoted.

Normalize a whole-path-quoted command only when the relative suffix uses shell-safe path characters. Apply the same recognizer in drift detection. Preserve the established split anchor for standard managed hooks.

## Acceptance criteria

Extend the installer fixture with a quoted hook filename containing parentheses. Run scripts/test-install.sh and keep canonical deduplication and malformed path cases passing.
