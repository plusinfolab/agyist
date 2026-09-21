#!/usr/bin/env bash
# lib/watcher.sh - Real-Time Antigravity & Cockpit State Sync Watcher Daemon
# Automatically detects account switches and state changes, keeping
# Antigravity IDE, 2.0 Desktop, and Cockpit Tools synchronized in real-time.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"

get_watch_targets() {
    local targets=()
    local ide_db="$HOME/.config/Antigravity IDE/User/globalStorage/state.vscdb"
    local desktop_db="$HOME/.config/Antigravity/User/globalStorage/state.vscdb"
    local cockpit_dir="${COCKPIT_TOOLS_DATA_DIR:-$HOME/.antigravity_cockpit}"
    local cockpit_curr="$cockpit_dir/current_account.json"
    local cockpit_idx="$cockpit_dir/accounts.json"

    [ -f "$ide_db" ] && targets+=("$ide_db")
    [ -f "$desktop_db" ] && targets+=("$desktop_db")
    [ -f "$cockpit_curr" ] && targets+=("$cockpit_curr")
    [ -f "$cockpit_idx" ] && targets+=("$cockpit_idx")

    printf "%s\n" "${targets[@]}"
}

get_file_mtime() {
    local file="$1"
    if [ -f "$file" ]; then
        stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

run_state_watcher() {
    local dry_run="${1:-0}"
    print_banner
    log_step "Starting Antigravity Real-Time State & Account Sync Watcher..."

    local ide_db="$HOME/.config/Antigravity IDE/User/globalStorage/state.vscdb"
    local desktop_db="$HOME/.config/Antigravity/User/globalStorage/state.vscdb"
    local cockpit_dir="${COCKPIT_TOOLS_DATA_DIR:-$HOME/.antigravity_cockpit}"
    local cockpit_curr="$cockpit_dir/current_account.json"

    log_info "Monitoring state and credentials:"
    log_dim "  • Antigravity IDE:   $ide_db"
    log_dim "  • Antigravity 2.0:   $desktop_db"
    log_dim "  • Cockpit Tools:     $cockpit_curr"
    echo ""

    if [ "$dry_run" -eq 1 ]; then
        log_success "Watcher dry-run check passed. Watch targets verified."
        return 0
    fi

    # Trap clean termination
    trap 'echo ""; log_info "Stopping state watcher daemon..."; exit 0' SIGINT SIGTERM

    local last_sync_time=0
    local debounce_secs=2

    perform_sync_trigger() {
        local reason="$1"
        local now
        now="$(date +%s)"
        if [ $(( now - last_sync_time )) -lt "$debounce_secs" ]; then
            return 0
        fi
        last_sync_time="$now"
        log_step "Change detected ($reason). Synchronizing state and credentials..."
        if python3 "$PROJECT_ROOT/lib/migrator.py" --sync; then
            log_success "Sync completed successfully at $(date '+%H:%M:%S')"
        else
            log_warn "Sync reported warnings or partial copy at $(date '+%H:%M:%S')"
        fi
        echo ""
    }

    # Strategy 1: inotifywait if available
    if command -v inotifywait >/dev/null 2>&1; then
        log_info "Using Linux kernel inotify events (inotifywait)"
        local watch_dirs=()
        [ -d "$HOME/.config/Antigravity IDE/User/globalStorage" ] && watch_dirs+=("$HOME/.config/Antigravity IDE/User/globalStorage")
        [ -d "$HOME/.config/Antigravity/User/globalStorage" ] && watch_dirs+=("$HOME/.config/Antigravity/User/globalStorage")
        [ -d "$cockpit_dir" ] && watch_dirs+=("$cockpit_dir")

        if [ "${#watch_dirs[@]}" -gt 0 ]; then
            log_success "Watcher active. Waiting for account switch or database write events..."
            inotifywait -m -q -e close_write -e moved_to --format '%w%f' "${watch_dirs[@]}" 2>/dev/null | while read -r changed_file; do
                case "$changed_file" in
                    *state.vscdb*|*current_account.json*|*accounts.json*)
                        perform_sync_trigger "$(basename "$changed_file")"
                        ;;
                esac
            done
            return 0
        fi
    fi

    # Strategy 2: Resilient polling fallback
    log_info "Using high-efficiency polling watcher (interval: 3s)"
    local last_ide_mtime=0
    local last_desk_mtime=0
    local last_cockpit_mtime=0

    last_ide_mtime="$(get_file_mtime "$ide_db")"
    last_desk_mtime="$(get_file_mtime "$desktop_db")"
    last_cockpit_mtime="$(get_file_mtime "$cockpit_curr")"

    log_success "Watcher active. Press Ctrl+C to stop."
    while true; do
        sleep 3
        local cur_ide cur_desk cur_cockpit
        cur_ide="$(get_file_mtime "$ide_db")"
        cur_desk="$(get_file_mtime "$desktop_db")"
        cur_cockpit="$(get_file_mtime "$cockpit_curr")"

        if [ "$cur_ide" != "$last_ide_mtime" ] && [ "$cur_ide" -gt 0 ]; then
            last_ide_mtime="$cur_ide"
            last_desk_mtime="$cur_ide" # Avoid immediate rebound
            perform_sync_trigger "Antigravity IDE state.vscdb"
        elif [ "$cur_desk" != "$last_desk_mtime" ] && [ "$cur_desk" -gt 0 ]; then
            last_desk_mtime="$cur_desk"
            last_ide_mtime="$cur_desk"
            perform_sync_trigger "Antigravity 2.0 state.vscdb"
        elif [ "$cur_cockpit" != "$last_cockpit_mtime" ] && [ "$cur_cockpit" -gt 0 ]; then
            last_cockpit_mtime="$cur_cockpit"
            perform_sync_trigger "Cockpit Tools active account switch"
        fi
    done
}

setup_watch_service() {
    print_banner
    log_step "Setting up background systemd user service for auto-sync..."

    local service_dir="$HOME/.config/systemd/user"
    local service_file="$service_dir/agyist-sync.service"
    local agyist_bin

    if [ -x "$HOME/.local/bin/agyist" ]; then
        agyist_bin="$HOME/.local/bin/agyist"
    elif [ -x "/usr/local/bin/agyist" ]; then
        agyist_bin="/usr/local/bin/agyist"
    else
        agyist_bin="$PROJECT_ROOT/agyist"
    fi

    mkdir -p "$service_dir" 2>/dev/null || true

    cat <<EOF > "$service_file"
[Unit]
Description=Antigravity State & Cockpit Tools Auto-Sync Daemon
After=default.target

[Service]
Type=simple
ExecStart=$agyist_bin --watch
Restart=always
RestartSec=5s
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
EOF

    log_success "Created service unit: $service_file"

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl --user daemon-reload 2>/dev/null; then
            if systemctl --user enable --now agyist-sync.service 2>/dev/null; then
                log_success "Enabled and started agyist-sync.service in systemd user session!"
                log_info "Status check: systemctl --user status agyist-sync.service"
                return 0
            fi
        fi
    fi

    log_warn "systemd --user session not active or not supported in this environment."
    log_info "You can run the watcher in the background anytime using:"
    echo "  nohup $agyist_bin --watch > ~/.antigravity_sync.log 2>&1 &"
    echo ""
}

remove_watch_service() {
    log_step "Removing background auto-sync service..."
    local service_file="$HOME/.config/systemd/user/agyist-sync.service"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable --now agyist-sync.service 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
    fi

    if [ -f "$service_file" ]; then
        rm -f "$service_file"
        log_success "Removed $service_file"
    else
        log_info "Service file was not present."
    fi
}

