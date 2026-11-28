# Preserve installed hook quoting

The installer rewrites whole-path-quoted adopter hooks. Path characters such as parentheses then reach Bash unquoted.

Recognize managed hooks for deduplication and drift checks. Preserve whole-path quoting and literal arguments to custom commands in project settings. In user settings, shell-quote a complete literal hook path using the absolute install root. Preserve literal interpreter flags, environment assignments, and following command text. Leave unsupported forms untouched.

## Acceptance criteria

Extend the installer fixture with a quoted filename containing parentheses and user hooks with literal command prefixes. Verify fresh installs and refreshes with the project variable unset. Keep canonical deduplication, legacy direct project anchoring, and malformed path cases passing.
