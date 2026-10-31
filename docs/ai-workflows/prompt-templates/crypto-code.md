# Prompt Template: Cryptographic Code

Use this template when asking AI tools to generate or modify cryptographic code for Concord Voice.

## Pre-filled Constraints

Include these constraints in your prompt or verify them in the output:

- [ ] **WebCrypto API only** (frontend) or **Go `crypto/*` standard library only** (backend) — no third-party crypto libraries
- [ ] **Minimum key sizes**: AES-256, RSA-4096 (RSA-OAEP for key wrapping), ECDH P-384+
- [ ] **No deprecated algorithms**: MD5, SHA-1 (for integrity), DES, RC4, ECB mode
- [ ] **IV/nonce generation** from CSPRNG (`crypto.getRandomValues` in JS, `crypto/rand` in Go) — never reuse IVs
- [ ] **Authenticated encryption**: AES-GCM (provides both confidentiality and integrity)
- [ ] **Key derivation**: Argon2id for password-based (t=3, m=64MB, p=4), and HKDF for key expansion
- [ ] **Key material handling**: never log, never send unencrypted, zeroize after use when possible
- [ ] **No custom crypto**: never implement encryption/decryption/signing algorithms from scratch
- [ ] **Forward secrecy**: ephemeral keys for session establishment where applicable
- [ ] **Existing modules**: use `crypto.ts` / `e2eeService.ts` / `mediaEncryption.ts` — do not create new crypto modules

## Example Prompt

```
Generate [key rotation / message encryption / key derivation] code for Concord Voice E2EE.

Requirements:
- Use WebCrypto API (frontend) or Go crypto/* (backend)
- AES-256-GCM with unique IV per message (crypto.getRandomValues)
- RSA-OAEP 4096-bit for key wrapping
- Integrate with existing e2eeService.ts / crypto.ts
- Key material never logged or sent unencrypted
- Tests covering encryption roundtrip + key rotation + error cases

Follow the project's crypto standards in CLAUDE.md.
Apply the RCI self-review pattern before presenting the code.
```

## Related

- [RCI Workflow](../rci-workflow.md)
- CLAUDE.md — "AI Code Generation Security Constraints" > "Prohibited Patterns"
- React Frontend Instructions
