#!/usr/bin/env bash
# lib/tui.sh - Interactive Terminal UI Wizard and Diagnostics for agyist

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=lib/installer.sh
source "$SCRIPT_DIR/installer.sh"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/backup.sh"
# shellcheck source=lib/fleet.sh
source "$SCRIPT_DIR/fleet.sh"
# shellcheck source=lib/cockpit.sh
source "$SCRIPT_DIR/cockpit.sh"
# shellcheck source=lib/doctor.sh
source "$SCRIPT_DIR/doctor.sh"

run_cockpit_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}=== Cockpit Tools & Multi-Account Hub ===${RESET}"
        echo -e "  ${CYAN}1)${RESET}  ${BOLD}Switch Active Account${RESET} (Instant CLI switcher)"
        echo -e "  ${CYAN}2)${RESET}  ${BOLD}Inspect Saved Accounts & Token Expiry Health${RESET}"
        echo -e "  ${CYAN}3)${RESET}  ${BOLD}Verify Active Accounts & Sync Status${RESET} (IDE vs 2.0 vs Cockpit)"
        echo -e "  ${CYAN}4)${RESET}  ${BOLD}Multi-Instance Isolated Profiles${RESET} (Launch / Manage)"
        echo -e "  ${CYAN}5)${RESET}  ${BOLD}Cockpit Health Doctor & Auto-Repair${RESET}"
        echo -e "  ${CYAN}6)${RESET}  ${BOLD}Configure Launch Path & Fix Integration${RESET} (IDE / 2.0 / Both)"
        echo -e "  ${CYAN}7)${RESET}  ${BOLD}Export Saved Accounts${RESET} (Password-encrypted .agyacc backup)"
        echo -e "  ${CYAN}8)${RESET}  ${BOLD}Import Saved Accounts${RESET} (Restore from .agyacc backup)"
        echo -e "  ${CYAN}9)${RESET}  Restart Cockpit Tools Daemon"
        echo -e "  ${CYAN}10)${RESET} Return to Main Menu"
        echo ""
        read -rp "Enter choice [1-10]: " cp_choice
        case "$cp_choice" in
            1)
                echo ""
                switch_cockpit_account ""
                ;;
            2)
                echo ""
                list_cockpit_accounts 0
                ;;
            3)
                echo ""
                show_account_status 0
                ;;
            4)
                echo ""
                echo "Multi-Instance Profiles:"
                echo "  1) List configured profiles"
                echo "  2) Launch / create an isolated profile"
                read -rp "Choice [1-2]: " inst_ch
                case "$inst_ch" in
                    1) list_cockpit_instances 0 ;;
                    2)
                        read -rp "Enter profile name (e.g. client-work, test-account): " p_name
                        [ -n "$p_name" ] && launch_cockpit_instance "$p_name"
                        ;;
                    *) log_warn "Invalid selection." ;;
                esac
                ;;
            5)
                echo ""
                repair_cockpit_tools
                ;;
            6)
                echo ""
                fix_cockpit_integration ""
                ;;
            7)
                echo ""
                read -rp "Enter export file path (press Enter for default in ~): " exp_f
                export_cockpit_accounts "$exp_f"
                ;;
            8)
                echo ""
                read -rp "Enter path to .agyacc backup archive: " imp_f
                [ -n "$imp_f" ] && import_cockpit_accounts "$imp_f"
                ;;
            9)
                echo ""
                restart_cockpit_tools
                ;;
            10|q|Q)
                break
                ;;
            *)
                log_warn "Invalid selection."
                ;;
        esac
    done
}

install_ide_interactive() {
    log_step "Starting Antigravity IDE installation..."
    local force_ide=0
    if [ -d "$HOME/.local/share/antigravity-ide" ] && [ -f "$HOME/.local/share/antigravity-ide/.antigravity-version" ]; then
        local cur_ver
        cur_ver="$(cat "$HOME/.local/share/antigravity-ide/.antigravity-version" 2>/dev/null || true)"
        echo -e "Antigravity IDE is already installed (${cur_ver:-installed} at ~/.local/share/antigravity-ide)."
        echo "  1) Refresh & repair launchers, desktop icons, and Cockpit integration [Fast]"
        echo "  2) Clean re-download and force reinstall from scratch"
        echo "  3) Cancel"
        read -rp "Enter choice [1-3, default 1]: " rein_choice
        case "$rein_choice" in
            2|reinstall|force) force_ide=1 ;;
            3|cancel|c) log_info "Installation cancelled."; return 0 ;;
            *) force_ide=0 ;;
        esac
    fi
    install_product "ide" "" "auto" "$force_ide" ""
}

install_desktop_interactive() {
    log_step "Starting Antigravity 2.0 Desktop installation..."
    local force_desk=0
    if [ -d "$HOME/.local/share/antigravity" ] && [ -f "$HOME/.local/share/antigravity/.antigravity-version" ]; then
        local cur_ver
        cur_ver="$(cat "$HOME/.local/share/antigravity/.antigravity-version" 2>/dev/null || true)"
        echo -e "Antigravity 2.0 Desktop is already installed (${cur_ver:-installed} at ~/.local/share/antigravity)."
        echo "  1) Refresh & repair launchers, desktop icons, and registrations [Fast]"
        echo "  2) Clean re-download and force reinstall from scratch"
        echo "  3) Cancel"
        read -rp "Enter choice [1-3, default 1]: " rein_choice
        case "$rein_choice" in
            2|reinstall|force) force_desk=1 ;;
            3|cancel|c) log_info "Installation cancelled."; return 0 ;;
            *) force_desk=0 ;;
        esac
    fi
    install_product "desktop" "" "auto" "$force_desk" ""
}

install_both_interactive() {
    log_step "Starting Full Suite installation..."
    local force_all=0
    if ([ -d "$HOME/.local/share/antigravity-ide" ] && [ -f "$HOME/.local/share/antigravity-ide/.antigravity-version" ]) || \
       ([ -d "$HOME/.local/share/antigravity" ] && [ -f "$HOME/.local/share/antigravity/.antigravity-version" ]); then
        echo "Antigravity components are already installed."
        echo "  1) Refresh & repair launchers, desktop icons, and registrations [Fast]"
        echo "  2) Clean re-download and force reinstall both applications"
        echo "  3) Cancel"
        read -rp "Enter choice [1-3, default 1]: " rein_choice
        case "$rein_choice" in
            2|reinstall|force) force_all=1 ;;
            3|cancel|c) log_info "Installation cancelled."; return 0 ;;
            *) force_all=0 ;;
        esac
    fi
    install_product "ide" "" "auto" "$force_all" ""
    install_product "desktop" "" "auto" "$force_all" ""
}

run_install_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}=== Installation & Upgrade Hub ===${RESET}"
        echo -e "  ${CYAN}1)${RESET}  Install / Upgrade ${BOLD}Antigravity IDE${RESET} (AI Coding Environment)"
        echo -e "  ${CYAN}2)${RESET}  Install / Upgrade ${BOLD}Antigravity 2.0 Desktop${RESET} (Desktop Agent App)"
        echo -e "  ${CYAN}3)${RESET}  Install / Upgrade ${BOLD}Both${RESET} (Full Suite)"
        echo -e "  ${CYAN}4)${RESET}  Refresh & Repair Launchers, Icons & Protocol Handlers"
        echo -e "  ${CYAN}5)${RESET}  Return to Main Menu"
        echo ""
        read -rp "Enter choice [1-5]: " in_choice
        case "$in_choice" in
            1) echo ""; install_ide_interactive ;;
            2) echo ""; install_desktop_interactive ;;
            3) echo ""; install_both_interactive ;;
            4)
                echo ""
                # shellcheck source=lib/desktop.sh
                source "$SCRIPT_DIR/desktop.sh"
                setup_desktop_integrations
                ;;
            5|q|Q) break ;;
            *) log_warn "Invalid selection." ;;
        esac
    done
}

run_sync_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}=== Chat, Brain & State Synchronization Hub ===${RESET}"
        echo -e "  ${CYAN}1)${RESET}  ${BOLD}Bi-directional Sync${RESET} (Sync chats & brains between IDE and 2.0)"
        echo -e "  ${CYAN}2)${RESET}  ${BOLD}Background Auto-Sync Watcher${RESET} (Real-time daemon / service)"
        echo -e "  ${CYAN}3)${RESET}  ${BOLD}Backup Archive${RESET} (Full snapshot of brains, chats, memory & settings)"
        echo -e "  ${CYAN}4)${RESET}  ${BOLD}Import / Restore Archive${RESET} (Restore brains & chats from backup)"
        echo -e "  ${CYAN}5)${RESET}  ${BOLD}Migrate Legacy Data${RESET} (Migrate legacy Antigravity v1 to IDE)"
        echo -e "  ${CYAN}6)${RESET}  Return to Main Menu"
        echo ""
        read -rp "Enter choice [1-6]: " sy_choice
        case "$sy_choice" in
            1) echo ""; run_sync 0 ;;
            2)
                echo ""
                # shellcheck source=lib/watcher.sh
                source "$SCRIPT_DIR/watcher.sh"
                echo "Real-Time State & Account Sync Watcher:"
                echo "  1) Run Watcher in foreground (Ctrl+C to stop)"
                echo "  2) Install systemd user service (starts on boot)"
                echo "  3) Remove systemd user service"
                read -rp "Choice [1-3]: " watch_choice
                case "$watch_choice" in
                    1) run_state_watcher 0 ;;
                    2) setup_watch_service ;;
                    3) remove_watch_service ;;
                    *) log_warn "Invalid selection." ;;
                esac
                ;;
            3)
                echo ""
                read -rp "Enter custom backup file path (press Enter for default in ~): " bpath
                run_backup "$bpath"
                ;;
            4)
                echo ""
                read -rp "Enter path to backup archive (.tar.gz): " ipath
                if [ -n "$ipath" ]; then
                    run_import "$ipath"
                else
                    log_warn "No archive path provided."
                fi
                ;;
            5)
                echo ""
                log_step "Running legacy migration..."
                run_migration_wrapper 0
                ;;
            6|q|Q) break ;;
            *) log_warn "Invalid selection." ;;
        esac
    done
}

run_doctor_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}=== System Doctor & Anti-Freeze Diagnostics ===${RESET}"
        echo -e "  ${CYAN}1)${RESET}  ${BOLD}Run Complete Health Doctor & Auto-Repair${RESET} (Comprehensive fix)"
        echo -e "  ${CYAN}2)${RESET}  Clear Stale Singleton Locks & Lingering Processes"
        echo -e "  ${CYAN}3)${RESET}  Purge Corrupted GPU & Shader Caches"
        echo -e "  ${CYAN}4)${RESET}  Enable Software Rendering in argv.json (Disable GPU acceleration)"
        echo -e "  ${CYAN}5)${RESET}  Check Linux Inotify Watcher Limits (Prevent high CPU freeze)"
        echo -e "  ${CYAN}6)${RESET}  Return to Main Menu"
        echo ""
        read -rp "Enter choice [1-6]: " doc_choice
        case "$doc_choice" in
            1) echo ""; fix_freeze_issues 0 ;;
            2) echo ""; clean_stale_locks_and_zombies ;;
            3) echo ""; purge_gpu_and_shader_caches ;;
            4) echo ""; configure_hardware_acceleration 1 ;;
            5) echo ""; check_inotify_limits ;;
            6|q|Q) break ;;
            *) log_warn "Invalid selection." ;;
        esac
    done
}

run_utilities_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}=== Fleet & Advanced Utilities ===${RESET}"
        echo -e "  ${CYAN}1)${RESET}  ${BOLD}Create Standalone Offline Deployment Bundle${RESET} (Air-gapped / Fleet)"
        echo -e "  ${CYAN}2)${RESET}  ${BOLD}Configure Automated Updates${RESET} (systemd user timer / cron)"
        echo -e "  ${CYAN}3)${RESET}  ${BOLD}Register Desktop Entry & URL Protocols${RESET} (antigravity://)"
        echo -e "  ${CYAN}4)${RESET}  Uninstall Antigravity Components"
        echo -e "  ${CYAN}5)${RESET}  Return to Main Menu"
        echo ""
        read -rp "Enter choice [1-5]: " ut_choice
        case "$ut_choice" in
            1)
                echo ""
                read -rp "Enter output file path (press Enter for default in ~): " bpath
                create_offline_bundle "$bpath" 1 1
                ;;
            2)
                echo ""
                echo "Select update schedule:"
                echo "  1) Daily (recommended)"
                echo "  2) Weekly"
                echo "  3) Disable / remove autoupdate"
                read -rp "Choice [1-3]: " sched_choice
                case "$sched_choice" in
                    1) setup_autoupdate "daily" "user" ;;
                    2) setup_autoupdate "weekly" "user" ;;
                    3) remove_autoupdate ;;
                    *) log_warn "Invalid selection." ;;
                esac
                ;;
            3)
                echo ""
                # shellcheck source=lib/desktop.sh
                source "$SCRIPT_DIR/desktop.sh"
                setup_desktop_integrations
                ;;
            4)
                echo ""
                read -rp "Are you sure you want to uninstall Antigravity? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    run_uninstall
                else
                    log_info "Uninstall cancelled."
                fi
                ;;
            5|q|Q) break ;;
            *) log_warn "Invalid selection." ;;
        esac
    done
}

run_interactive_menu() {
    while true; do
        clear 2>/dev/null || true
        print_banner

        echo -e "${BOLD}=== Quick Actions ===${RESET}"
        echo -e "  ${CYAN}1)${RESET}  ⚡ ${BOLD}Quick Install / Update Antigravity IDE${RESET}"
        echo -e "  ${CYAN}2)${RESET}  👤 ${BOLD}Switch Active Account${RESET} (Instant CLI switcher)"
        echo -e "  ${CYAN}3)${RESET}  🩺 ${BOLD}Fix PC Freezes & System Doctor${RESET}"
        echo ""
        echo -e "${BOLD}=== Management Hubs ===${RESET}"
        echo -e "  ${CYAN}4)${RESET}  🚀 ${BOLD}Installation & Upgrade Hub${RESET}     (IDE, 2.0 Desktop, Both)"
        echo -e "  ${CYAN}5)${RESET}  👥 ${BOLD}Multi-Account & Cockpit Hub${RESET}    (Accounts, Token Health, Profiles)"
        echo -e "  ${CYAN}6)${RESET}  🔄 ${BOLD}Data & State Sync Hub${RESET}          (Chats, Brains, Auto-Watcher, Backup)"
        echo -e "  ${CYAN}7)${RESET}  🛠  ${BOLD}Fleet & System Utilities Hub${RESET}   (Offline Bundles, Autoupdate, Launchers)"
        echo ""
        echo -e "${BOLD}=== System ===${RESET}"
        echo -e "  ${CYAN}8)${RESET}  📊 View System Diagnostics & Installation Status"
        echo -e "  ${CYAN}9)${RESET}  ⬇  Self-Update agyist CLI Suite (GitHub)"
        echo -e "  ${CYAN}0)${RESET}  🚪 Exit"
        echo ""

        read -rp "Enter choice [0-9]: " choice
        case "$choice" in
            1)
                echo ""
                install_ide_interactive
                echo ""
                read -rp "Press Enter to return to main menu..." _
                ;;
            2)
                echo ""
                switch_cockpit_account ""
                echo ""
                read -rp "Press Enter to return to main menu..." _
                ;;
            3)
                run_doctor_menu
                ;;
            4)
                run_install_menu
                ;;
            5)
                run_cockpit_menu
                ;;
            6)
                run_sync_menu
                ;;
            7)
                run_utilities_menu
                ;;
            8)
                echo ""
                show_system_status 0
                echo ""
                read -rp "Press Enter to return to main menu..." _
                ;;
            9)
                echo ""
                self_update_agyist 0
                echo ""
                read -rp "Press Enter to return to main menu..." _
                ;;
            0|q|Q)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                log_warn "Invalid selection."
                sleep 1
                ;;
        esac
    done
}

show_system_status() {
    local json_output="${1:-0}"

    if [ "$json_output" -eq 1 ]; then
        python3 -c "
import sys, json, os, subprocess, shutil
lib_dir = os.environ.get('LIB_DIR', '${LIB_DIR:-$SCRIPT_DIR}')
if lib_dir not in sys.path:
    sys.path.insert(0, lib_dir)
import migrator

status = migrator.get_status_dict()
status['system'] = {
    'arch': subprocess.check_output(['uname', '-m']).decode().strip(),
    'user': os.environ.get('USER', ''),
    'uid': os.getuid()
}

# Installations
installs = []
paths = [os.path.expanduser('~/.local/share/antigravity-ide'), os.path.expanduser('~/.local/share/antigravity'), '/opt/antigravity-ide', '/opt/antigravity', '/usr/share/antigravity-ide', '/usr/share/antigravity']
for p in paths:
    if os.path.exists(p):
        v = 'unknown'
        vf = os.path.join(p, '.antigravity-version')
        if os.path.exists(vf):
            v = open(vf).read().strip()
        elif os.path.exists(os.path.join(p, 'resources', 'app', 'product.json')):
            try:
                pj = json.load(open(os.path.join(p, 'resources', 'app', 'product.json')))
                v = pj.get('ideVersion', pj.get('version', 'unknown'))
            except Exception: pass
        elif os.path.exists(os.path.join(p, 'resources', 'app', 'package.json')):
            try:
                pj = json.load(open(os.path.join(p, 'resources', 'app', 'package.json')))
                v = pj.get('version', 'unknown')
            except Exception: pass
        installs.append({'path': p, 'version': v})
status['installations'] = installs

# Launchers
launchers = {}
for cmd in ['antigravity', 'antigravity-ide', 'agy']:
    which = shutil.which(cmd)
    launchers[cmd] = which if which else None
status['launchers'] = launchers

print(json.dumps(status, indent=2))
"
        return 0
    fi

    print_banner
    echo -e "${BOLD}=== System & Application Diagnostics ===${RESET}"
    echo "Architecture: $(detect_arch)"
    echo "User:         $(whoami) (UID: $(id -u))"
    echo "Sudo access:  $(if can_use_sudo; then echo -e "${GREEN}available${RESET}"; else echo -e "${YELLOW}not available / container mode${RESET}"; fi)"
    echo ""

    echo -e "${BOLD}=== Detected Installations ===${RESET}"
    local existing
    existing="$(detect_existing_installations)"
    if [ -z "$existing" ]; then
        echo "  (No Antigravity installations detected)"
    else
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            local type="${line%%:*}"
            local path="${line#*:}"
            local ver
            ver="$(get_installed_version "$path")"
            local tag=""
            if [[ "$path" =~ /usr/share/antigravity$ ]] && ! version_ge "$ver" "2.0.0"; then
                tag=" ${YELLOW}(legacy / obsolete)${RESET}"
            fi
            echo -e "  ✔ [${CYAN}$type${RESET}] $path (version: ${BOLD}$ver${RESET})$tag"
        done <<< "$existing"
    fi
    echo ""

    echo -e "${BOLD}=== CLI Launchers in PATH ===${RESET}"
    for cmd in antigravity antigravity-ide agy; do
        local which_path
        which_path="$(command -v "$cmd" 2>/dev/null || true)"
        if [ -n "$which_path" ]; then
            echo -e "  ✔ $cmd: $which_path"
        else
            echo -e "  - $cmd: not found"
        fi
    done
    echo ""

    local migrator_py="${LIB_DIR:-$SCRIPT_DIR}/migrator.py"
    if [ -f "$migrator_py" ]; then
        python3 "$migrator_py" --status
    elif [ -f "$SCRIPT_DIR/migrator.py" ]; then
        python3 "$SCRIPT_DIR/migrator.py" --status
    fi
}

run_uninstall() {
    log_step "Uninstalling Antigravity helper-managed binaries & desktop integrations..."
    
    # Remove desktop files and workspace shortcuts
    for df in \
        "/usr/share/applications/antigravity.desktop" \
        "/usr/share/applications/antigravity-ide.desktop" \
        "/usr/share/applications/antigravity-url-handler.desktop" \
        "/usr/share/applications/antigravity-ide-url-handler.desktop" \
        "$HOME/.local/share/applications/antigravity.desktop" \
        "$HOME/.local/share/applications/antigravity-ide.desktop" \
        "$HOME/.local/share/applications/antigravity-url-handler.desktop" \
        "$HOME/.local/share/applications/antigravity-ide-url-handler.desktop" \
        "$HOME/Desktop/Antigravity IDE.desktop" \
        "$HOME/Desktop/Antigravity 2.0.desktop" \
        "$HOME/Desktop/antigravity.desktop" \
        "$HOME/Desktop/antigravity-ide.desktop"; do
        if [ -f "$df" ]; then
            rm -f "$df" 2>/dev/null || sudo rm -f "$df" 2>/dev/null || true
            log_dim "Removed $df"
        fi
    done

    # Remove launchers
    for bin in \
        "/usr/local/bin/antigravity" \
        "/usr/local/bin/antigravity-ide" \
        "/usr/local/bin/agyist" \
        "$HOME/.local/bin/antigravity" \
        "$HOME/.local/bin/antigravity-ide" \
        "$HOME/.local/bin/agyist"; do
        if [ -f "$bin" ] || [ -L "$bin" ]; then
            rm -f "$bin" 2>/dev/null || sudo rm -f "$bin" 2>/dev/null || true
            log_dim "Removed $bin"
        fi
    done

    # Remove application install packages
    for app_dir in \
        "$HOME/.local/share/antigravity-ide" \
        "$HOME/.local/share/antigravity" \
        "$HOME/.local/share/antigravity-ide.previous" \
        "$HOME/.local/share/antigravity.previous"; do
        if [ -d "$app_dir" ]; then
            rm -rf "$app_dir" 2>/dev/null || true
            log_dim "Removed application directory: $app_dir"
        fi
    done

    # Remove installed icon assets
    rm -f "$HOME/.local/share/icons/hicolor/"*"/apps/antigravity"* 2>/dev/null || true
    rm -f "$HOME/.local/share/pixmaps/antigravity"* 2>/dev/null || true

    # Refresh desktop and icon database
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -q -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    fi

    log_success "Uninstall completed. User chats, brains and settings in ~/.gemini and ~/.config were preserved."
}
