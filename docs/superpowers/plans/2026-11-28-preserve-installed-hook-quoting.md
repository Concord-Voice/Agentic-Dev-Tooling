# Preserve installed hook quoting implementation plan

1. Confirm the affected source contract on the current default branch.
2. Normalize a whole-path-quoted command only when the relative suffix uses shell-safe path characters. Apply the same recognizer in drift detection. Preserve the established split anchor for standard managed hooks.
3. Extend the installer fixture with a quoted hook filename containing parentheses. Run scripts/test-install.sh and keep canonical deduplication and malformed path cases passing.
4. Run the applicable independent reviews and required CI. Request merge approval for the reviewed head.
