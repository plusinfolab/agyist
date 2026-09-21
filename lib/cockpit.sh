#!/usr/bin/env bash
# lib/cockpit.sh - Cockpit Tools integration & account switcher bridge for Antigravity
# Supports connecting Cockpit Tools to Antigravity IDE, Antigravity 2.0 Desktop, or Both.

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

is_ide_installation() {
    local exec_or_dir="$1"
    [ -n "$exec_or_dir" ] || return 1

    local dir
    if [ -f "$exec_or_dir" ]; then
        local real_file
        real_file="$(readlink -f "$exec_or_dir" 2>/dev/null || echo "$exec_or_dir")"
        dir="$(dirname "$real_file")"
        [ "$(basename "$dir")" = "bin" ] && dir="$(dirname "$dir")"
    else
        dir="$exec_or_dir"
    fi

    [ -f "$dir/resources/app/product.json" ] || [ -f "$dir/resources/app/out/cli.js" ]
}

resolve_ide_executable() {
    # 1. Check user-installed IDE first (latest build in ~/.local)
    local user_ide="$HOME/.local/share/antigravity-ide"
    if [ -x "$user_ide/antigravity-ide" ] && is_ide_installation "$user_ide"; then
        echo "$user_ide/antigravity-ide"
        return 0
    elif [ -x "$user_ide/bin/antigravity-ide" ] && is_ide_installation "$user_ide"; then
        echo "$user_ide/bin/antigravity-ide"
        return 0
    elif [ -x "$HOME/.local/bin/antigravity-ide" ]; then
        echo "$HOME/.local/bin/antigravity-ide"
        return 0
    fi

    # 2. Check explicit antigravity-ide in PATH
    if command -v antigravity-ide >/dev/null 2>&1; then
        command -v antigravity-ide
        return 0
    fi

    # 3. Check candidate executables and select the highest version build (avoiding obsolete < 2.0 builds)
    local best_exec=""
    local best_ver="0.0.0"

    for cand in \
        "$HOME/.local/share/antigravity-ide/bin/antigravity-ide" \
        "$HOME/.local/share/antigravity-ide/antigravity-ide" \
        "/opt/antigravity-ide/bin/antigravity-ide" \
        "/opt/antigravity-ide/antigravity-ide" \
        "/usr/share/antigravity-ide/bin/antigravity-ide" \
        "/usr/share/antigravity-ide/antigravity-ide" \
        "/usr/share/antigravity/bin/antigravity" \
        "/usr/share/antigravity/antigravity" \
        "/usr/bin/antigravity"; do
        if [ -x "$cand" ] && is_ide_installation "$cand"; then
            local cand_ver
            cand_ver="$(get_installed_version "$cand")"
            if [ -z "$best_exec" ] || version_ge "$cand_ver" "$best_ver"; then
                best_exec="$cand"
                best_ver="$cand_ver"
            fi
        fi
    done

    if [ -n "$best_exec" ]; then
        echo "$best_exec"
        return 0
    fi

    # Fallback to any antigravity launcher
    if command -v antigravity >/dev/null 2>&1; then
        command -v antigravity
        return 0
    fi

    echo ""
}

resolve_desktop_executable() {
    # 1. Check user-installed Antigravity 2.0 Desktop first
    local user_desktop="$HOME/.local/share/antigravity"
    if [ -x "$user_desktop/antigravity" ] && ! is_ide_installation "$user_desktop"; then
        echo "$user_desktop/antigravity"
        return 0
    elif [ -x "$user_desktop/bin/antigravity" ] && ! is_ide_installation "$user_desktop"; then
        echo "$user_desktop/bin/antigravity"
        return 0
    fi

    # 2. Check explicit desktop launcher
    if [ -x "$HOME/.local/bin/antigravity-desktop" ]; then
        echo "$HOME/.local/bin/antigravity-desktop"
        return 0
    elif command -v antigravity-desktop >/dev/null 2>&1; then
        command -v antigravity-desktop
        return 0
    fi

    # 3. Check ~/.local/bin/antigravity IF it is not an IDE wrapper
    if [ -x "$HOME/.local/bin/antigravity" ] && ! is_ide_installation "$HOME/.local/bin/antigravity"; then
        echo "$HOME/.local/bin/antigravity"
        return 0
    fi

    # 4. Check system non-IDE locations
    for cand in \
        "/opt/antigravity/antigravity" \
        "/opt/antigravity/bin/antigravity" \
        "/usr/share/antigravity-desktop/antigravity"; do
        if [ -x "$cand" ] && ! is_ide_installation "$cand"; then
            echo "$cand"
            return 0
        fi
    done

    # 5. Check /usr/bin/antigravity ONLY IF it is not an IDE installation
    if [ -x "/usr/bin/antigravity" ] && ! is_ide_installation "/usr/bin/antigravity"; then
        echo "/usr/bin/antigravity"
        return 0
    fi

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
    echo "=== Cockpit Tools & Antigravity Integration Diagnostics ==="
    echo ""

    local cockpit_bin
    cockpit_bin="$(detect_cockpit_app)"
    if [ -n "$cockpit_bin" ]; then
        log_success "Cockpit Tools binary: $cockpit_bin"
    else
        log_warn "Cockpit Tools application binary not found in standard paths (/usr/bin/cockpit-tools)"
    fi

    local data_dir
    data_dir="$(get_cockpit_data_dir)"
    local config_file="$data_dir/config.json"
    echo "Cockpit Data Directory: $data_dir"

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
            local path_ver
            path_ver="$(get_installed_version "$current_configured_path")"
            log_info "Configured App Path (antigravity_app_path): $current_configured_path (version: $path_ver)"
            if [[ "$current_configured_path" =~ /usr/share/antigravity ]] || ! version_ge "$path_ver" "2.0.0"; then
                log_warn "WARNING: Cockpit is currently configured to launch an outdated Antigravity build ($path_ver)!"
                log_info "Fix this by running: ./agyist --cockpit ide (or ./agyist --cockpit desktop)"
            else
                log_success "Cockpit launch path is modern ($path_ver)"
            fi
        else
            log_warn "antigravity_app_path is currently empty (relies on auto-discovery)"
        fi
    else
        log_warn "Cockpit configuration file ($config_file) does not exist yet"
    fi

    echo ""
    echo "=== Applications & Executable Checks ==="
    local ide_exec desktop_exec
    ide_exec="$(resolve_ide_executable)"
    desktop_exec="$(resolve_desktop_executable)"

    if [ -n "$ide_exec" ]; then
        local ide_ver
        ide_ver="$(get_installed_version "$ide_exec")"
        log_success "Antigravity IDE executable:     $ide_exec (version: $ide_ver)"
    else
        log_warn "Antigravity IDE executable not detected"
    fi

    if [ -n "$desktop_exec" ]; then
        local desk_ver
        desk_ver="$(get_installed_version "$desktop_exec")"
        log_success "Antigravity 2.0 Desktop executable: $desktop_exec (version: $desk_ver)"
    else
        log_warn "Antigravity 2.0 Desktop executable not detected"
    fi

    echo ""
    echo "=== Cockpit Tools Launcher & Discovery Verification ==="
    local ide_launcher desktop_launcher
    ide_launcher="$(command -v antigravity-ide 2>/dev/null || true)"
    desktop_launcher="$(command -v antigravity 2>/dev/null || true)"

    if [ -n "$ide_launcher" ]; then
        log_success "Launcher 'antigravity-ide' (required for IDE): $ide_launcher"
    else
        log_warn "Launcher 'antigravity-ide' NOT found in PATH! (Cockpit Tools strictly searches for 'antigravity-ide' when switching IDE accounts)"
    fi

    if [ -n "$desktop_launcher" ]; then
        log_success "Launcher 'antigravity' (used for 2.0 Desktop):  $desktop_launcher"
    else
        log_warn "Launcher 'antigravity' NOT found in PATH!"
    fi

    local ide_dir
    ide_dir="$(resolve_ide_install_dir "$ide_exec")"
    if [ -n "$ide_dir" ] && [ -d "$ide_dir" ]; then
        echo ""
        log_info "Antigravity IDE installation root: $ide_dir"
        if [ -e "$ide_dir/antigravity-ide" ] || [ -e "$ide_dir/bin/antigravity-ide" ]; then
            log_success "Cockpit Tools internal directory signature verified ($ide_dir)"
        else
            log_warn "Cockpit Tools directory signature missing in $ide_dir (needs bin/antigravity-ide symlink)"
        fi
    fi

    echo ""
    echo "=== Linux Secret Service & Keyring Status ==="
    if command -v secret-tool >/dev/null 2>&1; then
        local st_err
        st_err="$(secret-tool search service antigravity 2>&1 || true)"
        if [ -z "$st_err" ] || [[ "$st_err" =~ ^\[ ]]; then
            log_success "Linux Secret Service (secret-tool & D-Bus keyring): Connected and active"
        elif [[ "$st_err" =~ "No such file or directory" ]] || [[ "$st_err" =~ "Cannot autolaunch" ]]; then
            log_warn "Linux Secret Service daemon (gnome-keyring / D-Bus) is not connected in this session!"
            log_dim "  Cockpit Tools calls secret-tool for secure credential switching."
            log_dim "  Fix: Run eval \$(gnome-keyring-daemon --start) or ensure your desktop session keyring is unlocked."
        else
            log_info "Linux Secret Service (secret-tool): Available"
        fi
    else
        log_warn "secret-tool not found in PATH. Install with: sudo apt install libsecret-tools"
    fi

    local user_share_ide="$HOME/.local/share/antigravity-ide"
    if [ -f "$user_share_ide/bin/antigravity-ide" ] && [ -f "$user_share_ide/resources/app/product.json" ]; then
        log_success "Zero-root Cockpit discovery root: $user_share_ide"
    elif [ -d "$user_share_ide" ]; then
        log_info "Zero-root discovery directory present ($user_share_ide)"
    else
        log_dim "  Zero-root discovery root ($user_share_ide) not configured yet (run: agyist --cockpit)"
    fi

    echo ""
    echo "=== Active Accounts & Switch State ==="
    show_account_status
}

show_account_status() {
    local json_flag="${1:-0}"
    if [ "$json_flag" -eq 1 ] || [ "${JSON_OUTPUT:-0}" -eq 1 ]; then
        python3 "$PROJECT_ROOT/lib/migrator.py" --account --json
    else
        python3 "$PROJECT_ROOT/lib/migrator.py" --account
    fi
}

restart_cockpit_tools() {
    if pgrep -f cockpit-tools >/dev/null 2>&1; then
        log_step "Restarting Cockpit Tools daemon to reload configuration..."
        pkill -f cockpit-tools 2>/dev/null || true
        sleep 1
        if command -v cockpit-tools >/dev/null 2>&1; then
            nohup "$(command -v cockpit-tools)" >/dev/null 2>&1 &
            log_success "Cockpit Tools restarted with updated launcher path!"
        elif [ -x "/usr/bin/cockpit-tools" ]; then
            nohup /usr/bin/cockpit-tools >/dev/null 2>&1 &
            log_success "Cockpit Tools restarted with updated launcher path!"
        fi
    else
        log_info "Cockpit Tools is not currently running. Next launch will use updated configuration."
    fi
}

fix_cockpit_integration() {
    local target="${1:-}"

    # If no target provided and running interactively, ask user
    if [ -z "$target" ] && [ -t 0 ] && [ "${YES:-0}" -eq 0 ]; then
        echo ""
        echo -e "${BOLD}Select which application to connect with Cockpit Tools:${RESET}"
        echo -e "  ${CYAN}1)${RESET} ${BOLD}Both (Unified Integration)${RESET} [Recommended] - Support switching in both IDE & 2.0"
        echo -e "  ${CYAN}2)${RESET} ${BOLD}Antigravity IDE${RESET} (VS Code based AI coding environment)"
        echo -e "  ${CYAN}3)${RESET} ${BOLD}Antigravity 2.0${RESET} (Desktop AI assistant app)"
        echo ""
        read -rp "Enter choice [1-3, default 1]: " user_target_choice
        case "$user_target_choice" in
            2|ide|IDE) target="ide" ;;
            3|desktop|2.0|Desktop) target="desktop" ;;
            *) target="both" ;;
        esac
    fi

    [ -n "$target" ] || target="both"
    # Normalize aliases
    case "$target" in
        all|both|unified) target="both" ;;
        ide|vscode) target="ide" ;;
        desktop|2.0|hub) target="desktop" ;;
    esac

    print_banner
    log_step "Configuring Cockpit Tools Integration (Mode: $target)..."

    local ide_exec desktop_exec
    ide_exec="$(resolve_ide_executable)"
    desktop_exec="$(resolve_desktop_executable)"

    if [ -z "$ide_exec" ] && [ -z "$desktop_exec" ]; then
        log_error "Cannot configure Cockpit Tools: No Antigravity installation found."
        log_info "Please install Antigravity IDE or 2.0 first using ./agyist"
        return 1
    fi

    local primary_path=""
    if [ "$target" = "desktop" ]; then
        primary_path="${desktop_exec:-$ide_exec}"
    else
        primary_path="${ide_exec:-$desktop_exec}"
    fi

    log_info "Resolved target executable: $primary_path"

    # 1. Setup launchers & compatibility symlinks
    local launcher_installed=0

    # Ensure antigravity-ide launcher exists for IDE mode
    if [ "$target" = "ide" ] || [ "$target" = "both" ]; then
        local target_ide="${ide_exec:-$primary_path}"
        if [ -n "$target_ide" ]; then
            if [ "$(id -u)" -eq 0 ] || is_dir_writable "/usr/local/bin" || can_use_sudo; then
                log_step "Ensuring /usr/local/bin/antigravity-ide launcher exists..."
                if [ "$(id -u)" -eq 0 ] || is_dir_writable "/usr/local/bin"; then
                    ln -sf "$target_ide" "/usr/local/bin/antigravity-ide"
                    launcher_installed=1
                elif can_use_sudo; then
                    sudo ln -sf "$target_ide" "/usr/local/bin/antigravity-ide"
                    launcher_installed=1
                fi
                [ "$launcher_installed" -eq 1 ] && log_success "Created /usr/local/bin/antigravity-ide"
            fi

            local user_bin="$HOME/.local/bin"
            if [ -d "$user_bin" ] && is_dir_writable "$user_bin"; then
                ln -sf "$target_ide" "$user_bin/antigravity-ide"
                log_success "Created $user_bin/antigravity-ide"
            elif mkdir -p "$user_bin" 2>/dev/null; then
                ln -sf "$target_ide" "$user_bin/antigravity-ide"
                log_success "Created $user_bin/antigravity-ide"
            fi
        fi
    fi

    # Ensure 'antigravity' launcher exists for Desktop / general mode
    if [ "$target" = "desktop" ] || [ "$target" = "both" ]; then
        local target_desktop="${desktop_exec:-$primary_path}"
        if [ -n "$target_desktop" ]; then
            if [ ! -e "/usr/bin/antigravity" ] && [ ! -e "/usr/local/bin/antigravity" ]; then
                if [ "$(id -u)" -eq 0 ] || is_dir_writable "/usr/local/bin"; then
                    ln -sf "$target_desktop" "/usr/local/bin/antigravity"
                    log_success "Created /usr/local/bin/antigravity"
                elif can_use_sudo; then
                    sudo ln -sf "$target_desktop" "/usr/local/bin/antigravity"
                    log_success "Created /usr/local/bin/antigravity"
                fi
            fi

            local user_bin="$HOME/.local/bin"
            if [ ! -e "$user_bin/antigravity" ]; then
                mkdir -p "$user_bin" 2>/dev/null || true
                if [ -d "$user_bin" ] && is_dir_writable "$user_bin"; then
                    ln -sf "$target_desktop" "$user_bin/antigravity"
                    log_success "Created $user_bin/antigravity"
                fi
            fi
        fi
    fi

    # 2. Setup internal directory signatures inside installation root
    if [ -n "$ide_exec" ]; then
        local ide_dir
        ide_dir="$(resolve_ide_install_dir "$ide_exec")"
        if [ -n "$ide_dir" ] && [ -d "$ide_dir" ]; then
            if is_dir_writable "$ide_dir" || can_use_sudo; then
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
                log_success "Installed Cockpit Tools directory signatures in $ide_dir"
            fi

            # User-scope zero-root discovery root (~/.local/share/antigravity-ide)
            local user_share_ide="$HOME/.local/share/antigravity-ide"
            if [ "$ide_dir" != "$user_share_ide" ]; then
                mkdir -p "$HOME/.local/share" 2>/dev/null || true
                if [ -L "$user_share_ide" ]; then
                    rm -f "$user_share_ide" 2>/dev/null || true
                fi
                mkdir -p "$user_share_ide/bin" 2>/dev/null || true
                if [ -d "$user_share_ide" ]; then
                    for entry in "$ide_dir"/*; do
                        local base
                        base="$(basename "$entry")"
                        [ "$base" = "bin" ] && continue
                        [ "$base" = "antigravity-ide" ] && continue
                        [ -e "$entry" ] && ln -sfn "$entry" "$user_share_ide/$base" 2>/dev/null || true
                    done
                    ln -sf "$ide_exec" "$user_share_ide/antigravity-ide" 2>/dev/null || true
                    ln -sf "$ide_exec" "$user_share_ide/bin/antigravity-ide" 2>/dev/null || true
                    if [ -f "$ide_dir/bin/antigravity" ]; then
                        ln -sf "$ide_dir/bin/antigravity" "$user_share_ide/bin/antigravity" 2>/dev/null || true
                    fi
                    log_success "Created zero-root Cockpit discovery root: $user_share_ide"
                fi
            else
                # When ~/.local/share/antigravity-ide is the genuine install directory, ensure bin/antigravity-ide signature exists
                mkdir -p "$user_share_ide/bin" 2>/dev/null || true
                if [ ! -e "$user_share_ide/bin/antigravity-ide" ] && [ -x "$user_share_ide/antigravity-ide" ]; then
                    ln -sf "$user_share_ide/antigravity-ide" "$user_share_ide/bin/antigravity-ide" 2>/dev/null || true
                fi
                log_success "Verified user installation discovery root: $user_share_ide"
            fi
        fi
    fi

    # 3. Update ~/.antigravity_cockpit/config.json
    local data_dir
    data_dir="$(get_cockpit_data_dir)"
    mkdir -p "$data_dir" 2>/dev/null || true

    # Compatibility link for legacy Cockpit Tools versions (~/.antigravity_tools)
    local legacy_tools_dir="$HOME/.antigravity_tools"
    if [ ! -e "$legacy_tools_dir" ] && [ -d "$data_dir" ]; then
        ln -sfn "$data_dir" "$legacy_tools_dir" 2>/dev/null || true
    fi

    # Attempt to initialize Secret Service daemon if present
    if command -v gnome-keyring-daemon >/dev/null 2>&1; then
        eval "$(gnome-keyring-daemon --start 2>/dev/null)" || true
    fi

    if [ -d "$data_dir" ] && is_dir_writable "$data_dir"; then
        log_step "Updating Cockpit Tools configuration ($data_dir/config.json)..."
        local update_res
        update_res="$(python3 -c '
import json, os, sys

data_dir = "'"$data_dir"'"
config_path = os.path.join(data_dir, "config.json")
chosen_path = "'"$primary_path"'"

data = {}
if os.path.exists(config_path):
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        data = {}

data["antigravity_app_path"] = chosen_path
if "antigravity_launch_on_switch" not in data:
    data["antigravity_launch_on_switch"] = True
if "antigravity_dual_switch_no_restart_enabled" not in data:
    data["antigravity_dual_switch_no_restart_enabled"] = False

try:
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print("OK")
except Exception as e:
    print(f"ERR: {e}")
' 2>/dev/null || echo "ERR: python update failed")"

        if [ "$update_res" = "OK" ]; then
            log_success "Updated 'antigravity_app_path' -> $primary_path in Cockpit Tools config"
        else
            log_warn "Could not write to config.json automatically: $update_res"
        fi
    else
        log_info "Cockpit data directory ($data_dir) is not directly writable in this session."
    fi

    # 4. Synchronize databases across 2.0 and IDE
    log_step "Synchronizing account credentials across Antigravity 2.0 and Antigravity IDE..."
    run_sync 0 || true

    # 5. Offer/trigger Cockpit Tools restart if running
    if pgrep -f cockpit-tools >/dev/null 2>&1; then
        echo ""
        log_info "Cockpit Tools is currently running (PID: $(pgrep -f cockpit-tools | head -n 1))."
        if [ "${YES:-0}" -eq 1 ] || [ ! -t 0 ]; then
            restart_cockpit_tools
        else
            read -rp "Restart Cockpit Tools now to reload the new configuration? [Y/n]: " restart_choice
            if [[ ! "$restart_choice" =~ ^[Nn]$ ]]; then
                restart_cockpit_tools
            else
                log_info "Please remember to restart Cockpit Tools manually to apply the new launcher path."
            fi
        fi
    fi

    echo ""
    log_success "Cockpit Tools configuration complete!"
    echo ""
    echo "=== How Cockpit Tools Works With Both Versions ==="
    echo "Cockpit Tools has native support for BOTH applications:"
    echo "  • 'Antigravity IDE': Controls the VS Code AI environment (~/.config/Antigravity IDE)"
    echo "  • 'Antigravity':     Controls the 2.0 Desktop agent app   (~/.config/Antigravity)"
    echo ""
    echo "=== In the Cockpit Tools UI ==="
    echo "1. Cockpit Tools is now aligned to launch: $primary_path"
    if [ "$target" = "ide" ]; then
        echo "2. Switch to 'Antigravity IDE' in Cockpit's platform selector (top-left or sidebar)."
        echo "3. If prompted for Launch Path, enter: $ide_exec"
    elif [ "$target" = "desktop" ]; then
        echo "2. Switch to 'Antigravity' in Cockpit's platform selector."
        echo "3. If prompted for Launch Path, enter: $desktop_exec"
    else
        echo "2. You can switch between 'Antigravity IDE' and 'Antigravity' at any time using"
        echo "   the platform dropdown in Cockpit Tools."
        echo "3. If prompted for Launch Path in IDE mode, enter: $primary_path"
        echo "4. Accounts switched in either application will stay synchronized across both!"
    fi
    echo ""
}
