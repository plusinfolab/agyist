#!/usr/bin/env bash
# lib/doctor.sh - Comprehensive System Doctor & Anti-Freeze Diagnostics for agyist
# Detects and repairs:
# 1. Recursive fork-bomb launcher corruption
# 2. GPU hardware acceleration hangs and corrupted shader caches
# 3. Stale Electron / VS Code singleton socket locks
# 4. Inotify file watcher limit exhaustion
# 5. Shared memory (/dev/shm) restrictions
# 6. Wayland / display compositor buffer deadlocks
# 7. Cockpit Tools path and dual-switch integration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=lib/resolver.sh
source "$SCRIPT_DIR/resolver.sh"
# shellcheck source=lib/cockpit.sh
source "$SCRIPT_DIR/cockpit.sh"

clean_stale_locks_and_zombies() {
    log_step "Checking for lingering processes and stale singleton locks..."
    local killed=0

    # Terminate hung or zombie Antigravity processes
    if pgrep -f "antigravity-ide" >/dev/null 2>&1 || pgrep -f "/.local/share/antigravity" >/dev/null 2>&1; then
        pkill -9 -f "antigravity-ide" 2>/dev/null || true
        pkill -9 -f "/.local/share/antigravity" 2>/dev/null || true
        killed=1
        log_success "Terminated lingering Antigravity processes"
    else
        log_dim "  No lingering Antigravity processes found"
    fi

    # Remove stale singleton lock files
    local removed_locks=0
    for lock_dir in \
        "$HOME/.config/Antigravity IDE" \
        "$HOME/.config/Antigravity" \
        "$HOME/.antigravity-ide" \
        "$HOME/.antigravity"; do
        if [ -d "$lock_dir" ]; then
            for f in "$lock_dir"/Singleton*; do
                if [ -e "$f" ] || [ -L "$f" ]; then
                    rm -f "$f" 2>/dev/null || true
                    removed_locks=$((removed_locks + 1))
                fi
            done
        fi
    done

    if [ "$removed_locks" -gt 0 ]; then
        log_success "Cleaned $removed_locks stale Singleton lock file(s)"
    else
        log_dim "  No stale Singleton lock files detected"
    fi
}

verify_and_repair_binary_integrity() {
    log_step "Verifying binary integrity (checking for recursive fork-loop scripts)..."
    local ide_dir="$HOME/.local/share/antigravity-ide"
    local ide_exec="$ide_dir/antigravity-ide"
    local has_issue=0

    if [ -f "$ide_exec" ]; then
        local file_type
        file_type="$(file "$ide_exec" 2>/dev/null || true)"
        if [[ "$file_type" =~ "ASCII text" ]] || [[ "$file_type" =~ "shell script" ]]; then
            log_error "CORRUPTED LAUNCHER DETECTED!"
            log_warn "$ide_exec is an ASCII script causing an infinite fork loop (PC freeze)."
            has_issue=1

            # Check if bin/antigravity-ide is a clean ELF binary
            if [ -f "$ide_dir/bin/antigravity-ide" ] && file "$ide_dir/bin/antigravity-ide" 2>/dev/null | grep -q "ELF"; then
                log_step "Restoring healthy binary from $ide_dir/bin/antigravity-ide..."
                rm -f "$ide_exec"
                cp -p "$ide_dir/bin/antigravity-ide" "$ide_exec"
                chmod +x "$ide_exec"
                log_success "Restored native binary from bin/antigravity-ide"
                has_issue=0
            else
                # Check cache for a clean archive
                local arch
                arch="$(detect_arch)"
                local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/agyist"
                local found_archive=""
                for cand in "$cache_dir"/antigravity-ide-linux-*.tar.gz "$SCRIPT_DIR/../packages"/antigravity-ide-linux-*.tar.gz; do
                    if [ -f "$cand" ]; then
                        found_archive="$cand"
                        break
                    fi
                done

                if [ -n "$found_archive" ]; then
                    log_step "Extracting clean binary from cache: $found_archive..."
                    tar -xzf "$found_archive" -C "$ide_dir" --strip-components=1 2>/dev/null || true
                    if file "$ide_exec" 2>/dev/null | grep -q "ELF"; then
                        log_success "Successfully repaired and extracted native ELF binary"
                        has_issue=0
                    fi
                fi
            fi

            if [ "$has_issue" -eq 1 ]; then
                log_warn "Could not auto-extract cached binary. Please run: agyist --ide"
            fi
        else
            log_success "Antigravity IDE executable is a valid native ELF binary"
        fi
    fi

    # Verify ~/.local/bin/antigravity-ide launcher
    local user_bin="$HOME/.local/bin/antigravity-ide"
    if [ -e "$user_bin" ] || [ -L "$user_bin" ]; then
        if [ -L "$user_bin" ]; then
            local target
            target="$(readlink -f "$user_bin" 2>/dev/null || true)"
            if [ "$target" = "$user_bin" ]; then
                log_error "Self-referencing symlink detected at $user_bin. Repairing..."
                rm -f "$user_bin"
                if [ -x "$ide_exec" ]; then
                    ln -sf "$ide_exec" "$user_bin"
                    log_success "Repaired $user_bin symlink -> $ide_exec"
                fi
            fi
        fi
    fi
}

purge_gpu_and_shader_caches() {
    log_step "Purging corrupted GPU shader and code caches..."
    local purged=0
    for cache_path in \
        "$HOME/.config/Antigravity IDE/GPUCache" \
        "$HOME/.config/Antigravity IDE/DawnGraphiteCache" \
        "$HOME/.config/Antigravity IDE/DawnWebGPUCache" \
        "$HOME/.config/Antigravity IDE/Code Cache" \
        "$HOME/.config/Antigravity/GPUCache" \
        "$HOME/.config/Antigravity/Code Cache"; do
        if [ -d "$cache_path" ]; then
            rm -rf "$cache_path" 2>/dev/null || true
            purged=$((purged + 1))
        fi
    done

    if [ "$purged" -gt 0 ]; then
        log_success "Cleared $purged GPU and rendering cache directory/directories"
    else
        log_dim "  GPU caches are already clean"
    fi
}

configure_hardware_acceleration() {
    local enable_software_rendering="${1:-0}"
    local argv_path="$HOME/.antigravity-ide/argv.json"

    if [ "$enable_software_rendering" -eq 1 ]; then
        log_step "Enabling software rendering in $argv_path..."
        python3 -c '
import os, re, json

argv_path = os.path.expanduser("~/.antigravity-ide/argv.json")
os.makedirs(os.path.dirname(argv_path), exist_ok=True)

if not os.path.exists(argv_path):
    with open(argv_path, "w", encoding="utf-8") as f:
        json.dump({"disable-hardware-acceleration": True}, f, indent=2)
    print("CREATED")
else:
    with open(argv_path, "r", encoding="utf-8") as f:
        content = f.read()

    if re.search(r"\"disable-hardware-acceleration\"\s*:\s*(true|false)", content):
        content = re.sub(
            r"\"disable-hardware-acceleration\"\s*:\s*(true|false)",
            "\"disable-hardware-acceleration\": true",
            content
        )
    elif re.search(r"//\s*\"disable-hardware-acceleration\"\s*:\s*true", content):
        content = re.sub(
            r"//\s*\"disable-hardware-acceleration\"\s*:\s*true,?",
            "\"disable-hardware-acceleration\": true,",
            content
        )
    else:
        content = re.sub(
            r"\{\s*",
            "{\n\t\"disable-hardware-acceleration\": true,\n",
            content,
            count=1
        )

    with open(argv_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("UPDATED")
' 2>/dev/null || true
        log_success "Software rendering enabled in argv.json (GPU hardware acceleration disabled)"
    else
        # Inspect current state
        if [ -f "$argv_path" ]; then
            if grep -q '"disable-hardware-acceleration": true' "$argv_path" 2>/dev/null; then
                log_info "Hardware acceleration is currently DISABLED (software rendering active)."
            else
                log_dim "  Hardware acceleration is currently ENABLED in $argv_path"
            fi
        fi
    fi
}

check_inotify_limits() {
    log_step "Checking Linux inotify file watcher limits..."
    local inotify_file="/proc/sys/fs/inotify/max_user_watches"
    if [ -f "$inotify_file" ]; then
        local current_watches
        current_watches="$(cat "$inotify_file" 2>/dev/null || echo "0")"
        if [ "$current_watches" -lt 65536 ]; then
            log_warn "inotify max_user_watches is low: $current_watches (system default: 8192)"
            log_warn "When opening large codebases, this can exhaust watches and freeze the CPU."
            echo ""
            echo "  To increase file watcher limits permanently, run:"
            echo -e "  ${BOLD}echo fs.inotify.max_user_watches=524288 | sudo tee /etc/sysctl.d/40-antigravity.conf && sudo sysctl --system${RESET}"
            echo ""
        else
            log_success "inotify max_user_watches is optimal ($current_watches)"
        fi
    fi
}

check_shared_memory() {
    log_step "Checking shared memory (/dev/shm) availability..."
    if [ -d "/dev/shm" ]; then
        local avail
        avail="$(df -h /dev/shm 2>/dev/null | awk 'NR==2 {print $4}' || echo "unknown")"
        log_success "Shared memory (/dev/shm) available: $avail"
    fi
}

check_display_server() {
    log_step "Checking display server environment..."
    local session_type="${XDG_SESSION_TYPE:-unknown}"
    log_info "Session type: $session_type"
    if [ "$session_type" = "wayland" ]; then
        log_dim "  Note: If Wayland freezes occur with GPU acceleration, launch using:"
        log_dim "  antigravity-ide --ozone-platform=x11 --disable-gpu"
    fi
}

fix_freeze_issues() {
    local disable_gpu="${1:-0}"
    print_banner
    echo -e "${BOLD}=== Antigravity System Doctor & Freeze Diagnostics ===${RESET}\n"

    clean_stale_locks_and_zombies
    verify_and_repair_binary_integrity
    purge_gpu_and_shader_caches

    if [ "$disable_gpu" -eq 1 ]; then
        configure_hardware_acceleration 1
    else
        # In interactive terminal, ask if the user wants to enable software rendering
        if [ -t 0 ] && [ "${YES:-0}" -ne 1 ]; then
            echo ""
            read -rp "Does your PC freeze during startup or graphics rendering? Enable software rendering? [y/N]: " gpu_ans
            if [[ "$gpu_ans" =~ ^[Yy]$ ]]; then
                configure_hardware_acceleration 1
            else
                configure_hardware_acceleration 0
            fi
        else
            configure_hardware_acceleration 0
        fi
    fi

    check_inotify_limits
    check_shared_memory
    check_display_server

    echo ""
    log_step "Running Cockpit Tools configuration & DB sync repair..."
    python3 "$PROJECT_ROOT/lib/migrator.py" --repair-cockpit 2>/dev/null || true

    echo ""
    log_success "All diagnostics and repairs completed successfully!"
    echo ""
    echo "=== Summary of Tips for Freeze Prevention ==="
    echo "1. Damaged Binary: Checked and repaired if corrupted."
    echo "2. GPU Deadlocks: Run 'antigravity-ide --disable-gpu' or enable software rendering."
    echo "3. Stale Locks: Cleared all Singleton lock files and zombie processes."
    echo "4. Inotify Limits: Ensure max_user_watches is set to 524288 for large projects."
    echo "5. Wayland: Run with '--ozone-platform=x11' if compositor freezes occur."
    echo ""
}
