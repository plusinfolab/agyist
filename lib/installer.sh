#!/usr/bin/env bash
# lib/installer.sh - Core Download, Extraction, Sandbox setup, and Rollback engine for agyist

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source dependencies
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=lib/desktop.sh
source "$SCRIPT_DIR/desktop.sh"

fix_chrome_sandbox() {
    local sandbox="$1"
    if [ -f "$sandbox" ]; then
        if [ "$(id -u)" -eq 0 ]; then
            chown root:root "$sandbox" 2>/dev/null || true
            chmod 4755 "$sandbox" 2>/dev/null || true
        elif can_use_sudo; then
            sudo chown root:root "$sandbox" 2>/dev/null || true
            sudo chmod 4755 "$sandbox" 2>/dev/null || true
        else
            log_dim "Running without root; chrome-sandbox will use unprivileged user namespace mode."
        fi
    fi
}

safe_replace_directory() {
    local new_dir="$1"
    local target_dir="$2"

    local backup_dir="${target_dir}.previous"
    rm -rf "$backup_dir"

    if [ -d "$target_dir" ]; then
        mv "$target_dir" "$backup_dir"
        log_dim "Backed up previous installation to: $backup_dir"
    fi

    mv "$new_dir" "$target_dir"
}

create_cli_launcher() {
    local binary_name="$1"     # e.g. "antigravity-ide" or "antigravity"
    local target_exec="$2"     # e.g. /opt/antigravity-ide/antigravity-ide
    local bin_dir="$3"         # e.g. /usr/local/bin or ~/.local/bin
    local install_dir="$4"

    mkdir -p "$bin_dir"
    local launcher_path="$bin_dir/$binary_name"

    # Create robust wrapper script that handles CLI arguments and remote tunnels
    cat > "$launcher_path" <<LAUNCHER
#!/usr/bin/env sh
# agyist generated launcher for $binary_name

APP_DIR="$install_dir"
EXEC="$target_exec"

if [ ! -x "\$EXEC" ]; then
    echo "Error: Executable not found at \$EXEC" >&2
    exit 1
fi

# Check for VS Code style CLI javascript entry
CLI="\$APP_DIR/resources/app/out/cli.js"
if [ -f "\$CLI" ]; then
    ELECTRON_RUN_AS_NODE=1 "\$EXEC" "\$CLI" "\$@"
    exit \$?
else
    "\$EXEC" "\$@"
    exit \$?
fi
LAUNCHER

    chmod 755 "$launcher_path"
    log_success "Created CLI launcher: $launcher_path"

    # Ensure ~/.local/bin is noted if not in PATH
    if [ "$bin_dir" = "$HOME/.local/bin" ]; then
        case ":$PATH:" in
            *":$HOME/.local/bin:"*) ;;
            *)
                log_warn "~/.local/bin is not in your PATH. Consider adding: export PATH=\"\$HOME/.local/bin:\$PATH\" to ~/.bashrc"
                ;;
        esac
    fi
}

install_product() {
    local product="$1"               # "ide" or "desktop"
    local requested_target="${2:-}"  # optional target path
    local scope="${3:-auto}"         # "system", "user", or "auto"
    local force="${4:-0}"
    local local_archive="${5:-}"

    local platform
    platform="$(detect_arch)"

    log_step "Resolving official Google package for $product ($platform)..."
    
    ensure_dependencies

    local version url
    if [ -n "$local_archive" ] && [ -f "$local_archive" ]; then
        version="local-package"
        url="file://$local_archive"
        log_info "Using local archive: $local_archive"
    else
        # Resolve official Google package using pure native Bash scraper
        # shellcheck source=lib/resolver.sh
        source "$SCRIPT_DIR/resolver.sh"
        local resolve_output
        resolve_output="$(python3 "$SCRIPT_DIR/resolver.py" --product "$product" --platform "$platform")"
        resolve_output="$(resolve_official_download "$product" "$platform")"
        version="$(echo "$resolve_output" | awk '{print $1}')"
        url="$(echo "$resolve_output" | awk '{print $2}')"
        log_info "Latest version: $version"
        local source_type
        source_type="$(echo "$resolve_output" | awk '{print $3}')"
        log_info "Latest version: $version (source: $source_type)"
        log_dim "URL: $url"
    fi

    # Determine installation directory
    local install_dir
    if [ -n "$requested_target" ]; then
        install_dir="$requested_target"
    else
        install_dir="$(resolve_default_install_dir "$product" "$scope")"
    fi

    # Determine binary directory
    local bin_dir
    if [[ "$install_dir" =~ ^/usr|^/opt ]] && ([ "$(id -u)" -eq 0 ] || can_use_sudo); then
        bin_dir="/usr/local/bin"
    else
        bin_dir="$HOME/.local/bin"
        # If install_dir was system path but not writable and no root, fallback to ~/.local/share
        if ! is_dir_writable "$install_dir" && [ "$(id -u)" -ne 0 ] && ! can_use_sudo; then
            log_warn "Target directory $install_dir is not writable and sudo is unavailable."
            if [ "$product" = "ide" ]; then
                install_dir="$HOME/.local/share/antigravity-ide"
            else
                install_dir="$HOME/.local/share/antigravity"
            fi
            log_info "Falling back to user installation at: $install_dir"
        fi
    fi

    # Version check
    local version_file="$install_dir/.antigravity-version"
    if [ "$force" -eq 0 ] && [ -f "$version_file" ]; then
        local current_ver
        current_ver="$(cat "$version_file" 2>/dev/null || true)"
        if [ "$current_ver" = "$version" ]; then
            log_success "$product is already up to date ($version at $install_dir)."
            return 0
        fi
    fi

    local tmpdir
    tmpdir="$(mktemp -d "/tmp/agyist-$product-XXXXXX")"
    trap 'rm -rf "${tmpdir:-}"' EXIT INT TERM

    local archive="$tmpdir/archive.tar.gz"
    if [ -n "$local_archive" ] && [ -f "$local_archive" ]; then
        cp "$local_archive" "$archive"
    else
        log_step "Downloading $product $version..."
        if command -v curl >/dev/null 2>&1; then
            curl -fSL --retry 3 --progress-bar -o "$archive" "$url"
        elif command -v wget >/dev/null 2>&1; then
            wget -q --show-progress -O "$archive" "$url"
        else
            log_error "Neither curl nor wget found."
            exit 1
        fi
    fi

    log_step "Extracting package archive..."
    local extract_dir="$tmpdir/extracted"
    mkdir -p "$extract_dir"
    tar -xzf "$archive" -C "$extract_dir"

    # Identify extracted root folder
    local top_folder
    top_folder="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [ -z "$top_folder" ]; then
        top_folder="$extract_dir"
    fi

    # Locate main executable inside extracted directory
    local exec_name
    if [ "$product" = "ide" ]; then
        if [ -f "$top_folder/antigravity-ide" ]; then
            exec_name="antigravity-ide"
        elif [ -f "$top_folder/antigravity" ]; then
            exec_name="antigravity"
        else
            exec_name="$(find "$top_folder" -maxdepth 2 -name "antigravity*" -type f -perm -111 | head -n 1 | xargs -r basename)"
        fi
    else
        exec_name="antigravity"
    fi

    [ -n "$exec_name" ] || exec_name="antigravity"

    log_info "Detected executable: $exec_name"

    # Stage installation into .new directory
    local staged_dir="${install_dir}.new"
    rm -rf "$staged_dir"
    mkdir -p "$(dirname "$install_dir")"

    cp -a "$top_folder" "$staged_dir"

    # Stamp metadata
    echo "$version" > "$staged_dir/.antigravity-version"
    echo "$url" > "$staged_dir/.antigravity-source-url"
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$staged_dir/.antigravity-installed-at"

    # Setup chrome-sandbox
    fix_chrome_sandbox "$staged_dir/chrome-sandbox"

    log_step "Activating installation at $install_dir..."
    safe_replace_directory "$staged_dir" "$install_dir"

    local installed_exec="$install_dir/$exec_name"
    if [ ! -f "$installed_exec" ]; then
        # Search inside if nested
        installed_exec="$(find "$install_dir" -maxdepth 2 -name "$exec_name" -type f | head -n 1)"
    fi
    chmod 755 "$installed_exec" 2>/dev/null || true

    # Create CLI Launchers
    if [ "$product" = "ide" ]; then
        create_cli_launcher "antigravity-ide" "$installed_exec" "$bin_dir" "$install_dir"
        create_cli_launcher "antigravity" "$installed_exec" "$bin_dir" "$install_dir"
    else
        create_cli_launcher "antigravity" "$installed_exec" "$bin_dir" "$install_dir"
    fi

    # Install Desktop & Icon Integration
    log_step "Configuring desktop integration and application icons..."
    install_desktop_integration "$product" "$install_dir" "$bin_dir/$exec_name" "$scope"

    log_success "=========================================================="
    log_success "  $product $version successfully installed!"
    log_success "  Location:   $install_dir"
    log_success "  Launcher:   $bin_dir/$exec_name"
    log_success "=========================================================="

    rm -rf "$tmpdir"
    trap - EXIT INT TERM
}

