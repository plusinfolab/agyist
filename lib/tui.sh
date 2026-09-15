#!/usr/bin/env bash
# lib/tui.sh - Interactive Terminal UI Wizard for agyist

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=lib/installer.sh
source "$SCRIPT_DIR/installer.sh"
# shellcheck source=lib/backup.sh
source "$SCRIPT_DIR/backup.sh"

run_interactive_menu() {
    clear 2>/dev/null || true
    print_banner

    echo -e "${BOLD}Please select an action:${RESET}"
    echo -e "  ${CYAN}1)${RESET} Install / Upgrade ${BOLD}Antigravity IDE${RESET} (AI Coding Environment)"
    echo -e "  ${CYAN}2)${RESET} Install / Upgrade ${BOLD}Antigravity 2.0${RESET} (Desktop Agent App)"
    echo -e "  ${CYAN}3)${RESET} Install / Upgrade ${BOLD}Both${RESET} (Full Suite)"
    echo -e "  ${CYAN}4)${RESET} ${BOLD}Backup${RESET} Brains, Chats & Memory to an Archive"
    echo -e "  ${CYAN}5)${RESET} ${BOLD}Import / Restore${RESET} Brains & Chats from an Archive"
    echo -e "  ${CYAN}6)${RESET} ${BOLD}Migrate${RESET} Legacy Antigravity Data -> Antigravity IDE"
    echo -e "  ${CYAN}7)${RESET} View System Diagnostics & Installation Status"
    echo -e "  ${CYAN}8)${RESET} Uninstall Antigravity"
    echo -e "  ${CYAN}9)${RESET} Exit"
    echo ""

    read -rp "Enter choice [1-9]: " choice
    case "$choice" in
        1)
            echo ""
            log_step "Starting Antigravity IDE installation..."
            install_product "ide" "" "auto" 0 ""
            ;;
        2)
            echo ""
            log_step "Starting Antigravity 2.0 Desktop installation..."
            install_product "desktop" "" "auto" 0 ""
            ;;
        3)
            echo ""
            log_step "Starting Full Suite installation..."
            install_product "ide" "" "auto" 0 ""
            install_product "desktop" "" "auto" 0 ""
            ;;
        4)
            echo ""
            read -rp "Enter custom backup file path (press Enter for default): " bpath
            run_backup "$bpath"
            ;;
        5)
            echo ""
            read -rp "Enter path to backup archive (.tar.gz): " ipath
            if [ -n "$ipath" ]; then
                run_import "$ipath"
            else
                log_warn "No archive path provided."
            fi
            ;;
        6)
            echo ""
            log_step "Running migration..."
            run_migration_wrapper 0
            ;;
        7)
            echo ""
            show_system_status
            ;;
        8)
            echo ""
            read -rp "Are you sure you want to uninstall Antigravity? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                run_uninstall
            else
                log_info "Uninstall cancelled."
            fi
            ;;
        9|q|Q)
            echo "Exiting."
            exit 0
            ;;
        *)
            log_warn "Invalid selection."
            ;;
    esac
}

show_system_status() {
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
            ver="$(python3 "$SCRIPT_DIR/resolver.py" --check-path "$path" --json 2>/dev/null | grep '"installed_version"' | awk -F'"' '{print $4}' || echo "unknown")"
            echo -e "  ✔ [${CYAN}$type${RESET}] $path (version: ${BOLD}$ver${RESET})"
        done <<< "$existing"
    fi
    echo ""

    echo -e "${BOLD}=== CLI Launchers in PATH ===${RESET}"
    for cmd in antigravity antigravity-ide agy; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo -e "  ✔ $cmd: $(which "$cmd")"
        else
            echo -e "  - $cmd: not found"
        fi
    done
    echo ""

    python3 "$SCRIPT_DIR/migrator.py" --status
}

run_uninstall() {
    log_step "Uninstalling Antigravity helper-managed binaries & desktop integrations..."
    
    # Remove desktop files
    for df in \
        "/usr/share/applications/antigravity.desktop" \
        "/usr/share/applications/antigravity-ide.desktop" \
        "/usr/share/applications/antigravity-url-handler.desktop" \
        "/usr/share/applications/antigravity-ide-url-handler.desktop" \
        "$HOME/.local/share/applications/antigravity.desktop" \
        "$HOME/.local/share/applications/antigravity-ide.desktop" \
        "$HOME/.local/share/applications/antigravity-url-handler.desktop" \
        "$HOME/.local/share/applications/antigravity-ide-url-handler.desktop"; do
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

    log_success "Uninstall completed. User chats, brains and settings in ~/.gemini and ~/.config were preserved."
}

