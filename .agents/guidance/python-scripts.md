---
globs:
  - '**/*.py'
  - '**/requirements*.txt'
  - '**/Pipfile*'
---

# Python Scripts — AnkiTov Conventions

## Type Hints & Style

- All Python code MUST be type-hinted
- Use Goose recipes for agent orchestration (Rust-side pipelines via Rig Core)
- No bare `except:` clauses — always catch specific exceptions

## Code Restrictions

- No LangChain or LangGraph — use Rig Core (Rust) for agent pipelines instead
- No Agent Zero — replaced by Rig Core (saves 5GB+ RAM overhead)
- No `create_flashcard` or note-editing paths for MCP tools

## Execution

- Run Python scripts with `python3` (not `python`)
- Run scripts from project root via Goose shell tool
- Vector DB scripts use LanceDB (Librarian Tool) for commit graph indexing

## Integration Points

- Goose recipes can invoke Python subrecipes via `summon` extension
- Factory harness tooling (`toolchains/factory-harness/`) is Rust — not Python
- Cognee MCP (if used) runs as a Python-based MCP server