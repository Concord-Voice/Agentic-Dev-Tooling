---
agent: "ask"
description: "Explain the project's E2EE architecture, key management, and encryption flows"
---

Explain the End-to-End Encryption (E2EE) architecture in this project.

## Key Components

### Cryptographic Primitives
- **Message encryption:** AES-256-GCM (authenticated encryption)
- **Key wrapping:** RSA-OAEP with 4096-bit keys
- **Key agreement:** ECDH P-384 — account/device recovery only. Channel and DM keys are distributed by RSA-OAEP 4096 wrapping per member, not by key agreement.
- **Password hashing:** Argon2id (t=3, m=64MB, p=4)
- **RNG:** CSPRNG only (WebCrypto `getRandomValues()` or Go `crypto/rand`)

### Key Management
- Channel keys: epoch-based rotation with RSA-OAEP wrapping
- DM keys: per-conversation with key-epoch enforcement and a revocation record
- Key material stored via Electron `safeStorage` (OS keychain) — never plaintext
- Private keys never sent to server unencrypted, never logged

### Encryption Flow
1. Sender encrypts message with channel/DM AES-256-GCM key
2. Server relays ciphertext (cannot read content)
3. Recipient decrypts using their copy of the channel key
4. Key rotation: new epoch wraps new key with each member's RSA public key

### Implementation
- Client-side: one canonical encryption/decryption service
- Server-side: unconditional E2EE — there is no per-channel or per-conversation
  opt-out, and no per-row "is encrypted" flag. The real-time hub enforces the
  current channel key epoch instead
- DM: key-epoch validation against the revocation record

Reference: `docs/ai-workflows/prompt-templates/crypto-code.md`, plus your project's E2EE rule file if it has one
