# Preserve installed hook quoting implementation plan

1. Confirm the affected source contract on the current default branch.
2. Recognize managed hooks for deduplication and drift checks. Preserve whole-path quoting and literal arguments to custom commands in project settings. In user settings, shell-quote the absolute path for a complete literal hook path while preserving literal prefixes and following command text.
3. Verify quoted filenames, legacy project anchoring, and user hooks with literal command prefixes in scripts/test-install.sh. Keep canonical deduplication and malformed path cases passing.
4. Run the applicable independent reviews and required CI. Request merge approval for the reviewed head.
