---
name: security
description: Checks for credential leaks, injection vulnerabilities, unsafe code patterns, and telemetry integrity
severity-default: critical
tools: [Grep, Read, Bash]
globs:
  - '**/*.rs'
  - '**/*.py'
  - '**/*.sh'
---

# Security Check — AnkiTov

## What to Look For

### 1. Credential & Secret Leaks
- API keys, tokens, passwords hardcoded in source files
- `.env` files or secrets committed to version control
- Debug logging of sensitive data (session tokens, decryption keys)

### 2. Injection Vulnerabilities
- Raw SQL string concatenation (use SeaORM query builders)
- Shell command injection via `bash -c` or `os.system` with unsanitized input
- Unsafe deserialization of untrusted data

### 3. DRM & Cryptographic Integrity
- In-memory decryption keys must never be written to disk
- AES-256 encrypted content must only be decrypted via `gui_hooks.card_will_render`
- No offline storage of decrypted premium content

### 4. Authentication & Authorization
- All Loco.rs routes must check authentication
- Multi-tenant data isolation must be enforced at the query level
- Admin endpoints must verify role-based access

### 5. Telemetry & Audit
- Telemetry pings must be append-only, never mutable
- Audit logs must be immutable (append-only transaction ledger)
- No modification of telemetry data after creation