#!/usr/bin/env bash
# lib/common.sh - Shared utilities, colors, detection logic for agyist

set -euo pipefail

# ANSI color codes
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

log_info()    { printf "${CYAN}ℹ %s${RESET}\n" "$*"; }
log_success() { printf "${GREEN}✔ %s${RESET}\n" "$*"; }
log_warn()    { printf "${YELLOW}⚠ %s${RESET}\n" "$*" >&2; }
log_error()   { printf "${RED}✖ %s${RESET}\n" "$*" >&2; }
log_step()    { printf "${BOLD}${MAGENTA}==> %s${RESET}\n" "$*"; }
log_dim()     { printf "${DIM}%s${RESET}\n" "$*"; }

print_banner() {
    cat <<'BANNER'
[36m      ___       ___           ___           ___           ___           ___     
     /\  \     /\  \         /\  \         /\__\         /\  \         /\  \    
    /::\  \   /::\  \       /::\  \       /:/  /        _\:\  \        \:\  \   
   /:/\:\  \ /:/\:\  \     /:/\:\  \     /:/  /        /\ \:\  \        \:\  \  
  /::\~\:\  \\:\~\:\  \   /::\~\:\  \   /:/  /  ___   _\:\ \:\  \       /::\  \ 
 /:/\:\ \:\__\\:\ \:\__\ /:/\:\ \:\__\ /:/__/  /\__\ /\ \:\ \:\__\     /:/\:\__\
 \/__\:\/:/  / \:\/:/  / \/__\:\/:/  / \:\  \ /:/  / \:\ \:\ \/__/    /:/  \/__/
      \::/  /   \::/  /       \::/  /   \:\  /:/  /   \:\ \:\__\     /:/  /     
      /:/  /     /:/  /       /:/  /     \:\/:/  /     \:\/:/  /     \/__/      
     /:/  /     /:/  /       /:/  /       \::/  /       \::/  /                 
     \/__/      \/__/        \/__/         \/__/         \/__/                  
[0m[1m[35m  Google Antigravity & Antigravity IDE • Linux Installer & Manager Suite[0m
BANNER
    echo ""
}

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) echo "linux-x64" ;;
        aarch64|arm64) echo "linux-arm" ;;
        *)
            log_error "Unsupported CPU architecture: $arch. Google builds support x64 and ARM64."
            exit 1
            ;;
    esac
}

# Detect existing installations
detect_existing_installations() {
    # Returns a list of detected locations: TYPE:PATH
    local detected=()

    # 1. Check /usr/share/antigravity (matches current system)
    if [ -d "/usr/share/antigravity" ] && [ -x "/usr/share/antigravity/antigravity" ]; then
        detected+=("ide:/usr/share/antigravity")
    fi

    # 2. Check /usr/share/antigravity-ide
    if [ -d "/usr/share/antigravity-ide" ] && ([ -x "/usr/share/antigravity-ide/antigravity-ide" ] || [ -x "/usr/share/antigravity-ide/antigravity" ]); then
        detected+=("ide:/usr/share/antigravity-ide")
    fi

    # 3. Check /opt/antigravity-ide
    if [ -d "/opt/antigravity-ide" ] && ([ -x "/opt/antigravity-ide/antigravity-ide" ] || [ -x "/opt/antigravity-ide/Antigravity-IDE/antigravity-ide" ]); then
        detected+=("ide:/opt/antigravity-ide")
    fi

    # 4. Check /opt/antigravity (Desktop 2.0 or IDE)
    if [ -d "/opt/antigravity" ] && [ -x "/opt/antigravity/antigravity" ]; then
        detected+=("desktop:/opt/antigravity")
    fi

    # 5. Check ~/.local/share/antigravity-ide
    if [ -d "$HOME/.local/share/antigravity-ide" ]; then
        detected+=("ide:$HOME/.local/share/antigravity-ide")
    fi

    # 6. Check ~/.local/share/antigravity
    if [ -d "$HOME/.local/share/antigravity" ]; then
        detected+=("desktop:$HOME/.local/share/antigravity")
    fi

    printf '%s\n' "${detected[@]:-}"
}

# Test if a directory or its parent is writable
is_dir_writable() {
    local target="$1"
    if [ -d "$target" ]; then
        [ -w "$target" ]
    else
        local parent
        parent="$(dirname "$target")"
        while [ ! -d "$parent" ] && [ "$parent" != "/" ] && [ "$parent" != "." ]; do
            parent="$(dirname "$parent")"
        done
        [ -w "$parent" ]
    fi
}

can_use_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        return 0
    fi
    return 1
}

# Resolve default install directory for a product
resolve_default_install_dir() {
    local product="$1" # "ide" or "desktop"
    local scope="${2:-auto}" # "system", "user", or "auto"

    # Check for existing installation first
    local existing
    existing="$(detect_existing_installations)"
    
    if [ -n "$existing" ]; then
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            local item_type="${item%%:*}"
            local item_path="${item#*:}"
            if [ "$item_type" = "$product" ]; then
                # Found matching existing path!
                if [ "$scope" = "system" ]; then
                    echo "$item_path"
                    return 0
                elif [ "$scope" = "user" ]; then
                    # Force user directory if requested
                    break
                else
                    # Auto: check if writable or sudo available
                    if is_dir_writable "$item_path" || can_use_sudo; then
                        echo "$item_path"
                        return 0
                    fi
                fi
            fi
        done <<< "$existing"
    fi

    # Fallback to standard defaults based on scope
    if [ "$scope" = "system" ]; then
        if [ "$product" = "ide" ]; then
            echo "/opt/antigravity-ide"
        else
            echo "/opt/antigravity"
        fi
    elif [ "$scope" = "user" ]; then
        if [ "$product" = "ide" ]; then
            echo "$HOME/.local/share/antigravity-ide"
        else
            echo "$HOME/.local/share/antigravity"
        fi
    else
        # Auto: choose system if running as root or sudo is usable, else user
        if [ "$(id -u)" -eq 0 ] || can_use_sudo; then
            if [ "$product" = "ide" ]; then
                # If /usr/share/antigravity is present and writable/root, use it
                if [ -d "/usr/share/antigravity" ]; then
                    echo "/usr/share/antigravity"
                else
                    echo "/opt/antigravity-ide"
                fi
            else
                echo "/opt/antigravity"
            fi
        else
            if [ "$product" = "ide" ]; then
                echo "$HOME/.local/share/antigravity-ide"
            else
                echo "$HOME/.local/share/antigravity"
            fi
        fi
    fi
}
