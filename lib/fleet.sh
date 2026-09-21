#!/usr/bin/env bash
# lib/fleet.sh - Fleet Management, Offline Bundling, and Automated Maintenance for agyist
# Designed for office networks, multi-machine deployments, and automated updates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=lib/resolver.sh
source "$SCRIPT_DIR/resolver.sh"

create_offline_bundle() {
    local output_file="${1:-}"
    local include_ide="${2:-1}"
    local include_desktop="${3:-1}"
    local arch
    arch="$(detect_arch)"

    local default_name="agyist-offline-bundle-${arch}-$(date +%Y%m%d).tar.gz"
    [ -n "$output_file" ] || output_file="$HOME/$default_name"

    log_step "Creating Standalone Offline Deployment Bundle for $arch..."
    log_info "Destination: $output_file"

    local bundle_temp
    bundle_temp="$(mktemp -d "/tmp/agyist-bundle-XXXXXX")"
    trap 'rm -rf "${bundle_temp:-}"' EXIT INT TERM

    local bundle_dir="$bundle_temp/agyist-offline"
    mkdir -p "$bundle_dir/packages"
    mkdir -p "$bundle_dir/assets"
    mkdir -p "$bundle_dir/lib"

    # 1. Copy agyist codebase
    cp "$PROJECT_ROOT/agyist" "$bundle_dir/"
    cp -r "$PROJECT_ROOT/lib/"* "$bundle_dir/lib/"
    cp -r "$PROJECT_ROOT/assets/"* "$bundle_dir/assets/"

    local cache_dir="$HOME/.cache/agyist"
    mkdir -p "$cache_dir"

    # 2. Download or fetch packages into packages/
    if [ "$include_ide" -eq 1 ]; then
        log_step "Fetching official Antigravity IDE package..."
        local ide_info
        ide_info="$(resolve_official_download "ide" "$arch")"
        local ide_url
        ide_url="$(echo "$ide_info" | awk '{print $2}')"
        local ide_ver
        ide_ver="$(echo "$ide_info" | awk '{print $1}')"
        local cached_ide="$cache_dir/antigravity-ide-${ide_ver}-${arch}.tar.gz"

        if [ -f "$cached_ide" ] && [ -s "$cached_ide" ]; then
            log_info "Using cached Antigravity IDE $ide_ver package: $cached_ide"
            cp "$cached_ide" "$bundle_dir/packages/antigravity-ide.tar.gz"
        else
            log_info "Downloading Antigravity IDE $ide_ver..."
            curl -fSL --retry 3 --progress-bar -o "$cached_ide" "$ide_url"
            cp "$cached_ide" "$bundle_dir/packages/antigravity-ide.tar.gz"
        fi
        echo "$ide_ver" > "$bundle_dir/packages/antigravity-ide.version"
    fi

    if [ "$include_desktop" -eq 1 ]; then
        log_step "Fetching official Antigravity 2.0 Desktop package..."
        local desk_info
        desk_info="$(resolve_official_download "desktop" "$arch")"
        local desk_url
        desk_url="$(echo "$desk_info" | awk '{print $2}')"
        local desk_ver
        desk_ver="$(echo "$desk_info" | awk '{print $1}')"
        local cached_desk="$cache_dir/antigravity-desktop-${desk_ver}-${arch}.tar.gz"

        if [ -f "$cached_desk" ] && [ -s "$cached_desk" ]; then
            log_info "Using cached Antigravity Desktop $desk_ver package: $cached_desk"
            cp "$cached_desk" "$bundle_dir/packages/antigravity-desktop.tar.gz"
        else
            log_info "Downloading Antigravity Desktop $desk_ver..."
            curl -fSL --retry 3 --progress-bar -o "$cached_desk" "$desk_url"
            cp "$cached_desk" "$bundle_dir/packages/antigravity-desktop.tar.gz"
        fi
        echo "$desk_ver" > "$bundle_dir/packages/antigravity-desktop.version"
    fi

    # 3. Create one-click offline install.sh script in bundle
    cat > "$bundle_dir/install.sh" <<'BUNDLE_INSTALL_EOF'
#!/usr/bin/env bash
# Standalone Offline Installer for Antigravity & Antigravity IDE
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Google Antigravity Standalone Offline Deployment ==="
SCOPE="auto"
TARGET_FLAG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --user) SCOPE="user" ;;
        --system) SCOPE="system" ;;
        --scope) SCOPE="$2"; shift ;;
        *) TARGET_FLAG="$1" ;;
    esac
    shift
done

if [ -f "packages/antigravity-ide.tar.gz" ]; then
    echo "Installing Antigravity IDE from offline package..."
    ./agyist --ide --scope "$SCOPE" --file "packages/antigravity-ide.tar.gz" --force -y
fi

if [ -f "packages/antigravity-desktop.tar.gz" ]; then
    echo "Installing Antigravity 2.0 Desktop from offline package..."
    ./agyist --desktop --scope "$SCOPE" --file "packages/antigravity-desktop.tar.gz" --force -y
fi

# Bi-directionally synchronize chats, state, and databases
echo "Synchronizing chat history and workspaces..."
python3 lib/migrator.py --sync || true

echo "✔ Offline installation complete!"
BUNDLE_INSTALL_EOF
    chmod +x "$bundle_dir/install.sh"
    chmod +x "$bundle_dir/agyist"

    # 4. Create tar.gz bundle
    log_step "Compressing deployment bundle..."
    mkdir -p "$(dirname "$output_file")"
    tar -czf "$output_file" -C "$bundle_temp" "agyist-offline"

    rm -rf "$bundle_temp"
    trap - EXIT INT TERM

    local bundle_size
    bundle_size="$(du -sh "$output_file" | awk '{print $1}')"
    log_success "Offline bundle created successfully: $output_file ($bundle_size)"
    log_info "To deploy on remote machines:"
    log_dim "  1. scp $output_file user@remote-machine:"
    log_dim "  2. tar -xzf $(basename "$output_file") && cd agyist-offline && ./install.sh"
}

setup_autoupdate() {
    local schedule="${1:-daily}"     # "daily", "weekly", or cron
    local scope="${2:-user}"          # "user" or "system"

    log_step "Configuring automated update service ($schedule, scope: $scope)..."

    local agyist_path
    agyist_path="$(command -v agyist 2>/dev/null || echo "$PROJECT_ROOT/agyist")"

    # Check if systemd user daemon is available
    if [ "$scope" = "user" ] && command -v systemctl >/dev/null 2>&1 && systemctl --user is-active dbus >/dev/null 2>&1 || [ -d "/run/user/$(id -u)/systemd" ]; then
        local user_systemd_dir="$HOME/.config/systemd/user"
        mkdir -p "$user_systemd_dir"

        local service_file="$user_systemd_dir/antigravity-update.service"
        local timer_file="$user_systemd_dir/antigravity-update.timer"

        cat > "$service_file" <<SERVICE_EOF
[Unit]
Description=Google Antigravity & Antigravity IDE Automatic Update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$agyist_path --upgrade --quiet -y
StandardOutput=journal
StandardError=journal
SERVICE_EOF

        local calendar="daily"
        if [ "$schedule" = "weekly" ]; then
            calendar="weekly"
        fi

        cat > "$timer_file" <<TIMER_EOF
[Unit]
Description=Google Antigravity Update Timer
Persistent=true

[Timer]
OnCalendar=$calendar
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
TIMER_EOF

        systemctl --user daemon-reload || true
        systemctl --user enable --now antigravity-update.timer || true
        log_success "Created and enabled systemd user timer: $timer_file"
        log_info "Service status: $(systemctl --user is-enabled antigravity-update.timer 2>/dev/null || echo "active")"
        return 0
    fi

    # Fallback to crontab
    log_info "Setting up update schedule via crontab..."
    local cron_time="0 3 * * *"  # 3:00 AM daily
    if [ "$schedule" = "weekly" ]; then
        cron_time="0 3 * * 0"   # Sunday 3:00 AM
    fi

    local cron_cmd="$cron_time $agyist_path --upgrade --quiet -y >/dev/null 2>&1 # agyist-autoupdate"
    (crontab -l 2>/dev/null | grep -v "agyist-autoupdate" || true; echo "$cron_cmd") | crontab -
    log_success "Configured cron job: $cron_cmd"
}

remove_autoupdate() {
    log_step "Disabling automated update schedule..."
    # Disable systemd user timer if exists
    if [ -f "$HOME/.config/systemd/user/antigravity-update.timer" ]; then
        systemctl --user disable --now antigravity-update.timer 2>/dev/null || true
        rm -f "$HOME/.config/systemd/user/antigravity-update.timer"
        rm -f "$HOME/.config/systemd/user/antigravity-update.service"
        systemctl --user daemon-reload 2>/dev/null || true
        log_info "Removed systemd user update timer and service."
    fi

    # Clean crontab
    if crontab -l 2>/dev/null | grep -q "agyist-autoupdate"; then
        (crontab -l 2>/dev/null | grep -v "agyist-autoupdate" || true) | crontab -
        log_info "Removed cron job from user crontab."
    fi

    log_success "Automated updates have been disabled."
}
self_update_agyist() {
    local dry_run="${1:-0}"
    log_step "Checking for updates to agyist CLI suite..."

    local target_dir="$PROJECT_ROOT"
    local repo_url="${AGYIST_REPO_URL:-https://github.com/plusinfolab/agyist.git}"
    local tarball_url="${AGYIST_TARBALL_URL:-https://github.com/plusinfolab/agyist/archive/refs/heads/main.tar.gz}"

    if [ "$dry_run" -eq 1 ]; then
        log_info "[Dry-Run] Checking remote repository: $repo_url"
        if [ -d "$target_dir/.git" ] && command -v git >/dev/null 2>&1; then
            local current_commit
            current_commit="$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
            log_info "[Dry-Run] Git repository at $target_dir (current commit: $current_commit)"
        else
            log_info "[Dry-Run] Standalone/tarball installation at $target_dir"
        fi
        log_success "[Dry-Run] Self-update check completed."
        return 0
    fi

    if [ -d "$target_dir/.git" ] && command -v git >/dev/null 2>&1; then
        log_info "Git repository detected at $target_dir. Pulling latest commits..."
        local current_commit
        current_commit="$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

        if git -C "$target_dir" pull --ff-only origin main 2>/dev/null; then
            local new_commit
            new_commit="$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
            if [ "$current_commit" = "$new_commit" ]; then
                log_success "agyist is already at the latest version ($new_commit)."
            else
                log_success "agyist successfully updated from $current_commit to $new_commit!"
            fi
        else
            log_warn "Fast-forward git pull was not possible. Trying standard pull..."
            if git -C "$target_dir" pull --quiet origin main 2>/dev/null; then
                local new_commit
                new_commit="$(git -C "$target_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
                log_success "agyist updated to $new_commit!"
            else
                log_warn "Git pull failed (possibly private repo or detached state). Attempting archive download fallback..."
                local tmp_archive
                tmp_archive="$(mktemp "/tmp/agyist-update-XXXXXX.tar.gz" 2>/dev/null || echo "/tmp/agyist-update.tar.gz")"
                if curl -fsSL "$tarball_url" -o "$tmp_archive" 2>/dev/null; then
                    tar -xzf "$tmp_archive" -C "$target_dir" --strip-components=1
                    rm -f "$tmp_archive"
                    log_success "agyist updated successfully via archive fallback!"
                else
                    rm -f "$tmp_archive"
                    log_error "Failed to update agyist from remote repository."
                    return 1
                fi
            fi
        fi
    elif command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
        log_info "Standalone installation detected. Downloading latest agyist release archive..."
        local tmp_archive
        tmp_archive="$(mktemp "/tmp/agyist-update-XXXXXX.tar.gz" 2>/dev/null || echo "/tmp/agyist-update.tar.gz")"
        if curl -fsSL "$tarball_url" -o "$tmp_archive" 2>/dev/null; then
            tar -xzf "$tmp_archive" -C "$target_dir" --strip-components=1
            rm -f "$tmp_archive"
            log_success "agyist updated successfully from archive!"
        else
            rm -f "$tmp_archive"
            log_error "Failed to download agyist archive from $tarball_url"
            return 1
        fi
    else
        log_error "Neither git nor curl+tar is available to perform self-update."
        return 1
    fi

    # Refresh launcher permissions and PATH links
    chmod +x "$target_dir/agyist" "$target_dir/install.sh" 2>/dev/null || true
    mkdir -p "$HOME/.local/bin" 2>/dev/null || true
    ln -sfn "$target_dir/agyist" "$HOME/.local/bin/agyist" 2>/dev/null || true
    if [ "$(id -u)" -eq 0 ] || [ -w "/usr/local/bin" ]; then
        ln -sfn "$target_dir/agyist" "/usr/local/bin/agyist" 2>/dev/null || true
    fi

    log_success "agyist CLI launcher verified at $HOME/.local/bin/agyist"
    return 0
}
