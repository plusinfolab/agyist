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

QUIET="${QUIET:-0}"

log_info()    { [ "$QUIET" -eq 1 ] || printf "${CYAN}ℹ %s${RESET}\n" "$*"; }
log_success() { [ "$QUIET" -eq 1 ] || printf "${GREEN}✔ %s${RESET}\n" "$*"; }
log_warn()    { [ "$QUIET" -eq 1 ] || printf "${YELLOW}⚠ %s${RESET}\n" "$*" >&2; }
log_error()   { printf "${RED}✖ %s${RESET}\n" "$*" >&2; }
log_step()    { [ "$QUIET" -eq 1 ] || printf "${BOLD}${MAGENTA}==> %s${RESET}\n" "$*"; }
log_dim()     { [ "$QUIET" -eq 1 ] || printf "${DIM}%s${RESET}\n" "$*"; }

print_banner() {
    [ "$QUIET" -eq 1 ] && return 0
    cat <<'BANNER'
 [36m      ___           ___           ___                       ___           ___     
     /\  \         /\  \         |\__\          ___        /\  \         /\  \    
    /::\  \       /::\  \        |:|  |        /\  \      /::\  \        \:\  \   
   /:/\:\  \     /:/\:\  \       |:|  |        \:\  \    /:/\ \  \        \:\  \  
  /::\~\:\  \   /:/  \:\  \      |:|__|__      /::\__\  _\:\~\ \  \       /::\  \ 
 /:/\:\ \:\__\ /:/__/_\:\__\     /::::\__\  __/:/\/__/ /\ \:\ \ \__\     /:/\:\__\
 \/__\:\/:/  / \:\  /\ \/__/    /:/~~/~    /\/:/  /    \:\ \:\ \/__/    /:/  \/__/
      \::/  /   \:\ \:\__\     /:/  /      \::/__/      \:\ \:\__\     /:/  /     
      /:/  /     \:\/:/  /     \/__/        \:\__\       \:\/:/  /     \/__/      
     /:/  /       \::/  /                    \/__/        \::/  /                 
     \/__/         \/__/                                   \/__/                  
 [0m [1m [35m  Google Antigravity & Antigravity IDE • Linux Installer & Manager Suite [0m
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
                if [ "$scope" = "system" ]; then
                    echo "$item_path"
                    return 0
                elif [ "$scope" = "user" ]; then
                    break
                else
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
        if [ "$(id -u)" -eq 0 ] || can_use_sudo; then
            if [ "$product" = "ide" ]; then
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

# Auto-install missing system dependencies
ensure_dependencies() {
    local missing=()
    for cmd in curl tar gzip sed grep; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi

    log_step "Missing required tools: ${missing[*]}. Attempting automatic installation..."

    if [ "$(id -u)" -ne 0 ] && ! can_use_sudo; then
        log_error "Missing tools (${missing[*]}) and root/sudo privileges are not available."
        log_error "Please install them via your system package manager."
        exit 1
    fi

    local SUDO=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO="sudo"
    fi

    if command -v apt-get >/dev/null 2>&1; then
        log_info "Detected apt package manager (Debian/Ubuntu/Mint)..."
        $SUDO apt-get update -qq
        $SUDO apt-get install -y -qq curl tar gzip desktop-file-utils xdg-utils ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
        log_info "Detected dnf package manager (Fedora/RHEL)..."
        $SUDO dnf install -y -q curl tar gzip desktop-file-utils xdg-utils ca-certificates
    elif command -v pacman >/dev/null 2>&1; then
        log_info "Detected pacman package manager (Arch/Manjaro)..."
        $SUDO pacman -Sy --noconfirm --needed curl tar gzip desktop-file-utils xdg-utils ca-certificates
    elif command -v zypper >/dev/null 2>&1; then
        log_info "Detected zypper package manager (openSUSE)..."
        $SUDO zypper --quiet install -y curl tar gzip desktop-file-utils xdg-utils ca-certificates
    elif command -v apk >/dev/null 2>&1; then
        log_info "Detected apk package manager (Alpine)..."
        $SUDO apk add --no-cache curl tar gzip xdg-utils ca-certificates
    else
        log_warn "Unknown package manager. Please ensure ${missing[*]} are installed."
    fi
}
