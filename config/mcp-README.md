# dev-tooling/mcp/ — Shared MCP server templates

- `*.mcp.json` — committed, **SECRET-FREE** templates. Secrets use `${ENV_VAR}` expansion only.
- `*.local.json` — gitignored (see `../.gitignore`). For machine-resolved variants ONLY; NEVER commit.

## sonarqube.mcp.json
Stdio MCP server running the `mcp/sonarqube` Docker image against SonarCloud.

**Required (secret):** `SONARQUBE_TOKEN` — a SonarCloud **USER token** (not a project token).
No default is set, so Claude Code refuses to start the server until it is exported.

**Required (non-secret):** `SONARQUBE_ORG` — your SonarCloud organization key. Must be set; no default is set, so Claude Code refuses to start the server until it is exported (same mechanism as `SONARQUBE_TOKEN` above — the template intentionally does not use the `${VAR:?msg}` fail-fast form, which isn't documented for MCP env blocks).

**Optional (non-secret, defaulted):** `SONARQUBE_URL` (default `https://sonarcloud.io`).

### Set the token locally (untracked)
- CLI: `export SONARQUBE_TOKEN='<user-token>'` in `~/.zshrc` or a gitignored `~/.secrets`.
- macOS app + IDE extension: `launchctl setenv SONARQUBE_TOKEN '<user-token>'`.

### Never commit the real token
The template contains NO secret. For a fully-resolved variant, name it `sonarqube.local.json` (gitignored).
Generate: SonarCloud → My Account → Security → Generate Token (type **User**).

### Auth note
"Not authorized" almost always means a *project* token was used instead of a **user** token.
