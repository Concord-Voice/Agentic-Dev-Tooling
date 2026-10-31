# Prompt Template: Electron IPC

Use this template when asking AI tools to generate Electron IPC handlers or preload bridge code for this project.

## Pre-filled Constraints

Include these constraints in your prompt or verify them in the output:

- [ ] **Sender validation** — all `ipcMain.handle` / `ipcMain.on` handlers must validate `event.senderFrame.url` so a request can only come from the expected renderer
- [ ] **Input sanitization** — validate and sanitize all data received from the renderer before processing in the main process
- [ ] **Minimal contextBridge exposure** — expose only the specific methods the renderer needs, not broad APIs
- [ ] **No nodeIntegration** — never enable `nodeIntegration` in any BrowserWindow
- [ ] **contextIsolation ON** — never disable `contextIsolation`
- [ ] **sandbox ON** — never disable `sandbox`
- [ ] **No @electron/remote** — use structured IPC through the preload bridge exclusively
- [ ] **No arbitrary remote URLs** — the main window loads bundled content by default. Remote loading is allowed only for a validated HTTPS `spaUrl` from client configuration
- [ ] **No shell access** — renderer code must never trigger a shell command. Every shell operation goes through a validated, specific IPC channel
- [ ] **Type-safe IPC contract** — use the `ipcContract.ts` versioned contract pattern, and increment `IPC_CONTRACT_VERSION` on breaking changes
- [ ] **Credential handling** — use the Electron `safeStorage` API for sensitive data. Never store secrets in localStorage or plain files

## Example Prompt

```
Generate an IPC handler for [feature] in the desktop client.

Requirements:
- Main process handler in src/main/ with sender validation
- Preload bridge exposure in src/preload/ via contextBridge
- Renderer-side usage through the typed window.api interface
- Validate and sanitize all input from renderer
- Follow the ipcContract.ts versioning pattern
- No @electron/remote, no nodeIntegration, contextIsolation ON
- Tests for the handler (mock IPC events)

Follow Electron security constraints in CLAUDE.md and react-frontend.instructions.md.
Apply the RCI self-review pattern before presenting the code.
```

## Related

- [RCI Workflow](../rci-workflow.md)
- CLAUDE.md — "AI Code Generation Security Constraints" > "Electron Constraints"
- React Frontend Instructions
