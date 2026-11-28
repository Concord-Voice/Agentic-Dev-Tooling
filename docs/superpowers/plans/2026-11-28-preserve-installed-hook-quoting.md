# Preserve installed hook quoting implementation plan

1. Confirm the affected source contract on the current default branch.
2. Recognize managed hooks for deduplication and drift checks. Preserve whole-path quoting for custom commands in project settings. In user settings, shell-quote the absolute path for a complete literal hook path and preserve any following command text. Leave unsupported forms untouched.
3. Extend the installer fixture with a quoted hook filename containing parentheses. Run scripts/test-install.sh and keep canonical deduplication and malformed path cases passing.
4. Run the applicable independent reviews and required CI. Request merge approval for the reviewed head.
