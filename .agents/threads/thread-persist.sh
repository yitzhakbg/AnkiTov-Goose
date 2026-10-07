#!/usr/bin/env bash
set -euo pipefail

# thread-persist.sh — Cross-session thread persistence for AnkiTov
#
# Usage:
#   ./thread-persist.sh save   --label <name> [--summary <text>] [--context <json>] [--tags <tags>]
#   ./thread-persist.sh list   [--limit N] [--tag <tag>] [--change <hash>]
#   ./thread-persist.sh restore --id <uuid>
#   ./thread-persist.sh delete --id <uuid>
#
# Depends on: sqlite3, jj, date

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="${SCRIPT_DIR}/thread.db"

# ── Ensure database exists ──────────────────────────────────────────────
ensure_db() {
    if [ ! -f "$DB_PATH" ]; then
        sqlite3 "$DB_PATH" <<-SQL
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                label TEXT NOT NULL,
                jj_change_hash TEXT NOT NULL,
                jj_change_description TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                summary TEXT,
                context TEXT,
                tags TEXT
            );
            CREATE INDEX idx_threads_jj_hash ON threads(jj_change_hash);
            CREATE INDEX idx_threads_tags ON threads(tags);
            CREATE INDEX idx_threads_label ON threads(label);
SQL
        echo "Created thread database at $DB_PATH" >&2
    fi
}

# ── Get current jj context ──────────────────────────────────────────────
get_jj_context() {
    local hash desc
    if ! hash=$(jj log --limit 1 --no-graph -T 'change_id.shortest(12)' 2>/dev/null); then
        hash="no-jj-change"
        desc="(not in a jj repository)"
    else
        desc=$(jj log --limit 1 --no-graph -T 'description.first_line' 2>/dev/null || echo "(no description)")
    fi
    echo "${hash}|||${desc}"
}

# ── Subcommand: save ────────────────────────────────────────────────────
cmd_save() {
    local label="" summary="" context="" tags="" jj_hash="" jj_desc="" now
    local id

    while [ $# -gt 0 ]; do
        case "$1" in
            --label)    label="$2"; shift 2 ;;
            --summary)  summary="$2"; shift 2 ;;
            --context)  context="$2"; shift 2 ;;
            --tags)     tags="$2"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done

    if [ -z "$label" ]; then
        echo "Error: --label is required" >&2
        echo "Usage: $0 save --label <name> [--summary <text>] [--context <json>] [--tags <tags>]" >&2
        exit 1
    fi

    ensure_db

    id=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || date +%s)
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    IFS='|||' read -r jj_hash jj_desc < <(get_jj_context)

    sqlite3 "$DB_PATH" "INSERT INTO threads (id, label, jj_change_hash, jj_change_description, created_at, updated_at, summary, context, tags) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);" \
      "$id" "$label" "$jj_hash" "$jj_desc" "$now" "$now" "$summary" "$context" "$tags"

    echo "{\"status\":\"saved\",\"id\":\"${id}\",\"label\":\"${label}\",\"jj_change\":\"${jj_hash}\"}"
}

# ── Subcommand: list ────────────────────────────────────────────────────
cmd_list() {
    local limit=20 tag_filter="" change_filter="" where_clauses=() sql_where=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --limit)  limit="$2"; shift 2 ;;
            --tag)    tag_filter="$2"; shift 2 ;;
            --change) change_filter="$2"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done

    ensure_db

    if [ -n "$tag_filter" ]; then
        where_clauses+=("tags LIKE '%${tag_filter}%'")
    fi
    if [ -n "$change_filter" ]; then
        where_clauses+=("jj_change_hash = '${change_filter}'")
    fi

    if [ ${#where_clauses[@]} -gt 0 ]; then
        local IFS=" AND "
        sql_where="WHERE ${where_clauses[*]}"
    fi

    # Build query with parameterized filters
    local sql="SELECT id, label, jj_change_hash, created_at, summary, tags FROM threads ${sql_where} ORDER BY updated_at DESC LIMIT ${limit};"
    sqlite3 -header -json "$DB_PATH" "$sql"
}

# ── Subcommand: restore ─────────────────────────────────────────────────
cmd_restore() {
    local id=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --id) id="$2"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done

    if [ -z "$id" ]; then
        echo "Error: --id is required" >&2
        exit 1
    fi

    ensure_db

    sqlite3 -header -json "$DB_PATH" \
        "SELECT * FROM threads WHERE id = ?;" "$id" | head -1
}

# ── Subcommand: delete ─────────────────────────────────────────────────
cmd_delete() {
    local id=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --id) id="$2"; shift 2 ;;
            *) echo "Unknown option: $1" >&2; exit 1 ;;
        esac
    done

    if [ -z "$id" ]; then
        echo "Error: --id is required" >&2
        exit 1
    fi

    ensure_db

    sqlite3 "$DB_PATH" "DELETE FROM threads WHERE id = ?;" "$id"
    echo "{\"status\":\"deleted\",\"id\":\"${id}\"}"
}

# ── Main dispatch ──────────────────────────────────────────────────────
main() {
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <save|list|restore|delete> [options...]" >&2
        exit 1
    fi

    local cmd="$1"
    shift

    case "$cmd" in
        save)    cmd_save "$@" ;;
        list)    cmd_list "$@" ;;
        restore) cmd_restore "$@" ;;
        delete)  cmd_delete "$@" ;;
        *)
            echo "Unknown subcommand: $cmd" >&2
            echo "Usage: $0 <save|list|restore|delete> [options...]" >&2
            exit 1
            ;;
    esac
}

main "$@"
