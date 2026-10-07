---
name: deploy-docs
description: Deploy Mintlify documentation and Scalar API reference for AnkiTov
status: aspirational
---

> ⚠️ **MCP backends not wired.** This skill references `mintlify-deploy` and `scalar-validate`
> (both npm-based) but neither is enabled as a Goose extension. `#[utoipa::path]` annotations
> are also not yet implemented on management controllers, so OpenAPI generation is incomplete.
> To activate: enable the MCP servers in `goose_config.yaml` and complete utoipa annotations.
> Currently serves as documentation only.

# Deploy Documentation Skill

Deploys AnkiTov's public documentation (Mintlify) and interactive API reference (Scalar).

## Steps

1. **Verify OpenAPI spec** — Confirm all controller routes have `#[utoipa::path]` annotations
2. **Run `cargo check`** — Ensure the OpenAPI spec compiles
3. **Extract OpenAPI spec** — Generate `openapi.json` from the compiled binary
4. **Deploy Mintlify** — Push docs content to the mintlify.json-configured target
5. **Verify Scalar** — Check that Scalar picks up the updated `openapi.json`

## MCP Server Bundle

The `mcp.json` in this skill directory provides tools for:
- `mintlify_deploy` — pushes documentation to Mintlify
- `scalar_validate` — validates the OpenAPI spec for Scalar compatibility

## Resource Files

- `openapi-schema.json` — the generated OpenAPI schema (auto-updated)