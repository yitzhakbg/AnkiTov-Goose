---
name: style-rust
description: Enforces idiomatic Rust conventions, clippy lints, and project-specific code style
severity-default: low
tools: [Grep, Read, Bash]
globs:
  - '**/*.rs'
---

# Rust Style Check — AnkiTov

## What to Look For

### 1. Idiomatic Rust
- Use `?` operator instead of `unwrap()` or `expect()` in fallible contexts
- Prefer `map()` / `and_then()` over match blocks for Option/Result transforms
- Use `into()` / `from()` for type conversions rather than manual casts
- No `unsafe` blocks unless absolutely necessary and documented with SAFETY comments

### 2. AnkiTov-Specific Conventions
- All controller routes MUST have `#[utoipa::path]` annotations
- Use SeaORM typed query builders, not raw SQL strings
- Follow the existing module structure in `backend/src/`
- No gRPC — use stdio, HTTP, or MCP stdio servers for inter-service comms

### 3. Error Handling
- Define custom error types with `thiserror` or `anyhow`
- Propagate errors to the HTTP layer for proper status codes
- Log errors with context before returning

### 4. Testing
- Tests in `tests/` directory, not inline in source files
- Use `cargo nextest run` framework conventions
- Test names should describe the scenario: `test_<module>_<behavior>`
- Integration tests must verify database state, not just return codes