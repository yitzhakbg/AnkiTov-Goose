---
globs:
  - '**/*.rs'
  - '**/Cargo.toml'
  - '**/rust-toolchain.toml'
---

# Rust Backend — AnkiTov Conventions

## Build & Test

- Use `cargo check` (not `cargo build`) for compilation verification
- Use `cargo nextest run` (not `cargo test`) for running tests
- Run `cargo check` after every Rust file change — self-correct up to 3 iterations
- Budget gate: `cd ankitov-budget-gate && cargo check`

## Code Style

- Follow idiomatic Rust conventions (rustfmt, clippy)
- All controller routes MUST be annotated with `#[utoipa::path]` for auto-generated OpenAPI
- No external migration files — use `NoOpMigrator` pattern. Schema changes must be reversible
- No gRPC — all inter-service comms are native (stdio, HTTP, MCP stdio servers)

## Architecture

- Backend source: `backend/src/` (controllers, models, server, app.rs, lib.rs, main.rs)
- Framework: Loco.rs (Axum + SeaORM + libSQL)
- ORM: SeaORM for all database queries
- Database: libSQL in WAL mode

## Model Routing Context

- AnkiTov uses Goose in `smart_approve` mode — auto-approves safe ops, blocks destructive ones
- The HITL Gate intercept blocks writes until human types `APPROVE`
- Budget Gate sidecar (`ankitov-budget-gate/`) routes model spend and applies rate limits
- Prefer "Step 3.7 Flash" for heavy code-gen volume to minimize cost

## Version Control

- Use `jj` (Jujutsu) for all commits — NOT `git`
- Atomic commits only with descriptive messages
- No native git commands unless explicitly stated

## Path Conventions

| What | Path |
|------|------|
| Backend source | `backend/src/` |
| Budget gate | `ankitov-budget-gate/src/` |
| Factory harness | `toolchains/factory-harness/` |
| Internal runbooks | `docs-repository/internal-runbooks/` |
| Workspace docs | `workspace/` |
| Specs | `specs/` |
| Recipes | `recipes/` |