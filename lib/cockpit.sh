#!/usr/bin/env bash
# lib/cockpit.sh - Cockpit Tools integration & account switcher bridge for Antigravity
# Ensures Cockpit Tools correctly detects and switches accounts for Antigravity IDE.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/backup.sh"

get_cockpit_data_dir() {
    if [ -n "${COCKPIT_TOOLS_DATA_DIR:-}" ]; then
        echo "$COCKPIT_TOOLS_DATA_DIR"
    else
        echo "$HOME/.antigravity_cockpit"
    fi
}

detect_cockpit_app() {
    if [ -x "/usr/bin/cockpit-tools" ]; then
        echo "/usr/bin/cockpit-tools"
    elif command -v cockpit-tools >/dev/null 2>&1; then
        command -v cockpit-tools
    else
        echo ""
    fi
}

resolve_ide_executable() {
    # Check PATH first
    if command -v antigravity-ide >/dev/null 2>&1; then
        command -v antigravity-ide
        return 0
    fi
    if command -v antigravity >/dev/null 2>&1; then
        command -v antigravity
        return 0
    fi

    # Check common install locations
    for cand in \
        "/usr/share/antigravity/bin/antigravity" \
        "/usr/share/antigravity/antigravity" \
        "/usr/local/bin/antigravity" \
        "/opt/antigravity/antigravity" \
        "$HOME/.local/bin/antigravity" \
        "$HOME/.local/share/antigravity/bin/antigravity" \
        "$HOME/.local/share/antigravity/antigravity"; do
        if [ -x "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done

    echo ""
}

resolve_ide_install_dir() {
    local exec_path="$1"
    if [ -z "$exec_path" ]; then
        echo ""
        return 0
    fi

    local real_path
    real_path="$(readlink -f "$exec_path" 2>/dev/null || echo "$exec_path")"
    local dir
    dir="$(dirname "$real_path")"

    if [ "$(basename "$dir")" = "bin" ]; then
        dirname "$dir"
    else
        echo "$dir"
    fi
}

diagnose_cockpit() {
    print_banner
    echo "=== Cockpit Tools & Antigravity IDE Integration Diagnostics ==="
    echo ""

    local cockpit_bin
    cockpit_bin="$(detect_cockpit_app)"
    if [ -n "$cockpit_bin" ]; then
        log_success "Cockpit Tools binary: $cockpit_bin"
    else
        log_warn "Cockpit Tools application binary not found in standard paths"
    fi

    local data_dir
    data_dir="$(get_cockpit_data_dir)"
    local config_file="$data_dir/config.json"
    echo "Data Directory:       $data_dir"

    local current_configured_path=""
    if [ -f "$config_file" ]; then
        log_success "Found Cockpit config: $config_file"
        current_configured_path="$(python3 -c '
import json, sys
try:
    with open("'"$config_file"'") as f:
        data = json.load(f)
        print(data.get("antigravity_app_path", "").strip())
except Exception:
    pass
' 2>/dev/null || true)"
        if [ -n "$current_configured_path" ]; then
            log_info "Configured IDE App Path: $current_configured_path"
        else
            log_warn "antigravity_app_path is currently empty (relies on auto-discovery)"
        fi
    else
        log_warn "Cockpit configuration file ($config_file) does not exist yet"
    fi

    echo ""
    echo "=== Executable & Discovery Checks ==="
    local ide_exec
    ide_exec="$(resolve_ide_executable)"
    if [ -n "$ide_exec" ]; then
        log_success "Resolved Antigravity IDE executable: $ide_exec"
    else
        log_error "No Antigravity IDE executable found on this system!"
    fi

    local ide_launcher
    ide_launcher="$(command -v antigravity-ide 2>/dev/null || true)"
    if [ -n "$ide_launcher" ]; then
        log_success "Found 'antigravity-ide' launcher in PATH: $ide_launcher"
    else
        log_warn "'antigravity-ide' launcher NOT found in PATH! (Cockpit Tools strictly searches for 'antigravity-ide')"
    fi

    local ide_dir
    ide_dir="$(resolve_ide_install_dir "$ide_exec")"
    if [ -n "$ide_dir" ] && [ -d "$ide_dir" ]; then
        log_info "Antigravity installation root: $ide_dir"
        if [ -e "$ide_dir/antigravity-ide" ] || [ -e "$ide_dir/bin/antigravity-ide" ]; then
            log_success "Cockpit Tools internal directory signature verified ($ide_dir)"
        else
            log_warn "Cockpit Tools directory signature missing in $ide_dir (needs bin/antigravity-ide symlink)"
        fi
    fi

    echo ""
    echo "=== Storage & Database Status ==="
    local ide_db="$HOME/.config/Antigravity IDE/User/globalStorage/state.vscdb"
    local desktop_db="$HOME/.config/Antigravity/User/globalStorage/state.vscdb"
    
    if [ -f "$ide_db" ]; then
        log_success "Antigravity IDE state.vscdb exists: $ide_db"
    else
        log_warn "Antigravity IDE state.vscdb not found: $ide_db"
    fi

    if [ -f "$desktop_db" ]; then
        log_success "Antigravity 2.0 state.vscdb exists: $desktop_db"
    else
        log_warn "Antigravity 2.0 state.vscdb not found: $desktop_db"
    fi

    echo ""
}

fix_cockpit_integration() {
    print_banner
    log_step "Fixing Cockpit Tools Integration for Antigravity IDE..."

    local ide_exec
    ide_exec="$(resolve_ide_executable)"
    if [ -z "$ide_exec" ]; then
        log_error "Cannot fix Cockpit Tools: No Antigravity executable found."
        log_info "Please install Antigravity IDE first using: ./agyist --ide"
        return 1
    fi

    log_info "Using Antigravity IDE executable: $ide_exec"

    # 1. Ensure 'antigravity-ide' launcher exists in PATH
    local launcher_installed=0
    # Prefer /usr/local/bin if writable or sudo available
    if [ "$(id -u)" -eq 0 ] || is_dir_writable "/usr/local/bin" || can_use_sudo; then
        log_step "Ensuring /usr/local/bin/antigravity-ide symlink exists..."
        if [ "$(id -u)" -eq 0 ] || is_dir_writable "/usr/local/bin"; then
            ln -sf "$ide_exec" "/usr/local/bin/antigravity-ide"
            launcher_installed=1
        elif can_use_sudo; then
            sudo ln -sf "$ide_exec" "/usr/local/bin/antigravity-ide"
            launcher_installed=1
        fi
        [ "$launcher_installed" -eq 1 ] && log_success "Created /usr/local/bin/antigravity-ide"
    fi

    # Also ensure user-scope ~/.local/bin/antigravity-ide if writable
    local user_bin="$HOME/.local/bin"
    if [ -d "$user_bin" ] && is_dir_writable "$user_bin"; then
        ln -sf "$ide_exec" "$user_bin/antigravity-ide"
        log_success "Created $user_bin/antigravity-ide"
        launcher_installed=1
    elif mkdir -p "$user_bin" 2>/dev/null; then
        ln -sf "$ide_exec" "$user_bin/antigravity-ide"
        log_success "Created $user_bin/antigravity-ide"
        launcher_installed=1
    fi

    # 2. Ensure internal install directory symlinks exist for Cockpit Tools directory verification
    local ide_dir
    ide_dir="$(resolve_ide_install_dir "$ide_exec")"
    if [ -n "$ide_dir" ] && [ -d "$ide_dir" ]; then
        if is_dir_writable "$ide_dir" || can_use_sudo; then
            log_step "Creating directory signatures in $ide_dir for Cockpit Tools..."
            local cmd_prefix=""
            if [ "$(id -u)" -ne 0 ] && ! is_dir_writable "$ide_dir" && can_use_sudo; then
                cmd_prefix="sudo "
            fi

            if [ ! -e "$ide_dir/antigravity-ide" ]; then
                $cmd_prefix ln -sf "$ide_exec" "$ide_dir/antigravity-ide" 2>/dev/null || true
            fi
            if [ -d "$ide_dir/bin" ] && [ ! -e "$ide_dir/bin/antigravity-ide" ]; then
                $cmd_prefix ln -sf "$ide_exec" "$ide_dir/bin/antigravity-ide" 2>/dev/null || true
            fi
            log_success "Directory signatures installed in $ide_dir"
        fi
    fi

    # 3. Configure ~/.antigravity_cockpit/config.json
    local data_dir
    data_dir="$(get_cockpit_data_dir)"
    mkdir -p "$data_dir" 2>/dev/null || true

    if [ -d "$data_dir" ] && is_dir_writable "$data_dir"; then
        log_step "Updating Cockpit Tools configuration ($data_dir/config.json)..."
        local update_res
        update_res="$(python3 -c '
import json, os, sys

data_dir = "'"$data_dir"'"
config_path = os.path.join(data_dir, "config.json")
ide_path = "'"$ide_exec"'"

data = {}
if os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        data = {}

data["antigravity_app_path"] = ide_path

try:
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print("OK")
except Exception as e:
    print(f"ERR: {e}")
' 2>/dev/null || echo "ERR: python update failed")"

        if [ "$update_res" = "OK" ]; then
            log_success "Configured 'antigravity_app_path' -> $ide_exec in Cockpit Tools"
        else
            log_warn "Could not update config.json automatically: $update_res"
        fi
    else
        log_info "Cockpit data directory ($data_dir) is not directly writable in this session."
    fi

    # 4. Synchronize databases
    log_step "Synchronizing account credentials across Antigravity 2.0 and Antigravity IDE..."
    sync_chat_storage || true

    echo ""
    log_success "Cockpit Tools integration configuration complete!"
    echo ""
    echo "=== Instructions for Cockpit Tools UI ==="
    echo "1. If Cockpit Tools is running, restart it to load new PATH / settings."
    echo "2. In Cockpit Tools UI, select 'Antigravity IDE' from the platform selector."
    echo "3. If prompted for application path, set:"
    echo "     Antigravity IDE Launch Path: $ide_exec"
    echo "     (Make sure to specify the file '$ide_exec', NOT the folder)"
    echo "4. The account switcher will now switch and inject tokens seamlessly."
    echo ""
}

