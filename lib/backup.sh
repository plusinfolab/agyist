#!/usr/bin/env bash
# lib/backup.sh - Chat, Memory, Brain & State Manager wrapper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"

run_backup() {
    local target_file="${1:-}"
    log_step "Creating comprehensive snapshot of Antigravity Brains & Memory..."
    if [ -n "$target_file" ]; then
        python3 "$SCRIPT_DIR/migrator.py" --backup "$target_file"
    else
        python3 "$SCRIPT_DIR/migrator.py" --backup
    fi
}

run_import() {
    local source_file="$1"
    if [ ! -f "$source_file" ]; then
        log_error "Backup file not found: $source_file"
        exit 1
    fi
    log_step "Restoring Antigravity Brains, Chats & Memory from: $source_file"
    python3 "$SCRIPT_DIR/migrator.py" --import "$source_file"
}

run_migration_wrapper() {
    local dry_run="${1:-0}"
    log_step "Migrating Antigravity Memory, Chats & State..."
    if [ "$dry_run" -eq 1 ]; then
        python3 "$SCRIPT_DIR/migrator.py" --migrate --dry-run
    else
        python3 "$SCRIPT_DIR/migrator.py" --migrate
    fi
}

