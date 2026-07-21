# Goose Apps

Goose apps are HTML/CSS/JavaScript applications that run in sandboxed windows.

## Contents

| File | Size | Description |
|------|------|-------------|
| `ankitov-management-console.html` | 64 KB | Original management console (v1) |
| `clock.html` | 7 KB | Simple clock app |

## Notes

- **`ankitov-management-console-v2.html`** (189 KB) — The full IMP Management Console GUI.
  This is the canonical version served by the Goose app system.
  The backend-compiled version lives at `backend/resources/dashboard/imp-console.html` in the AnkiTov repo.

- **`ankitov-management-console.html`** (64 KB) — Original v1 management console.
  Still functional but superseded by v2.

## Adding New Apps

```bash
# Create a new app via Goose
goose apps create "My App" path/to/my-app.html

# Or by dropping HTML into ~/.local/share/goose/apps/
```

## Development

To rebuild the management console app after making changes to the AnkiTov backend:

```bash
cd /path/to/ankitov/backend
cargo build -p backend
```

The backend HTML is compiled into the binary via `include_str!`.