# Preserve installed hook quoting

The installer rewrites whole-path-quoted adopter hooks. Path characters such as parentheses then reach Bash unquoted.

Use managed-hook comparison for deduplication and matcher widening. The existing drift checks still validate managed-hook presence. Preserve whole-path quoting and literal arguments to custom commands in project settings. In user settings, shell-quote a complete literal hook path using the absolute install root. Preserve simple `sh` or `bash` flags (`-e`, `-u`, `-x`), literal `env` assignments, and following command text. Leave unsupported forms untouched, including `bash -c` shell programs.

## Acceptance criteria

Extend the installer fixture with a quoted filename containing parentheses and user hooks with literal command prefixes. Verify fresh installs and refreshes with the project variable unset, including a literal `./` segment. Preserve parent-relative commands as written. Keep canonical deduplication, legacy direct project anchoring, and malformed path cases passing.
