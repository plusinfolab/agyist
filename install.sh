#!/usr/bin/env bash
# install.sh - One-line Bootstrap and Installer for Google Antigravity & Antigravity IDE
#
# Quick install:
#   curl -fsSL https://raw.githubusercontent.com/plusinfolab/agyist/main/install.sh | bash
#
# With options:
#   curl -fsSL https://raw.githubusercontent.com/plusinfolab/agyist/main/install.sh | bash -s -- --ide
#   curl -fsSL https://raw.githubusercontent.com/plusinfolab/agyist/main/install.sh | bash -s -- --all
#   curl -fsSL https://raw.githubusercontent.com/plusinfolab/agyist/main/install.sh | bash -s -- --cockpit both

set -euo pipefail

detect_shell_rc() {
    if [ -n "${ZSH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
        echo "~/.zshrc"
    else
        echo "~/.bashrc"
    fi
}

# Ensure ~/.local/bin is configured in user shell profiles
ensure_path_configured() {
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir" 2>/dev/null || true
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [ -f "$rc" ] && [ -w "$rc" ] && ! grep -qs "\.local/bin" "$rc"; then
            echo -e "\n# Antigravity CLI Suite (agyist)\nexport PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$rc" 2>/dev/null || true
        fi
    done
}

show_post_install_box() {
    local rc_file
    rc_file="$(detect_shell_rc)"
    echo ""
    echo "=================================================================="
    echo "  ✔ agyist CLI suite installed successfully!"
    echo "  Binary location: $HOME/.local/bin/agyist"
    echo ""
    echo "  To start using agyist in this terminal session right now, run:"
    echo "     source $rc_file"
    echo ""
    echo "  Then run agyist from any terminal:"
    echo "     agyist               # Launch interactive setup wizard"
    echo "     agyist --ide         # Install / update Antigravity IDE"
    echo "     agyist --all         # Install both IDE and 2.0 Desktop"
    echo "     agyist --sync        # Sync chats, brains and state"
    echo "     agyist --cockpit     # Configure Cockpit Tools integration"
    echo "     agyist --self-update # Update agyist itself to latest version"
    echo "=================================================================="
    echo ""
}

# 1. If running from within an existing checkout of agyist
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -e "$SCRIPT_SOURCE" ]; then
    REAL_SOURCE="$SCRIPT_SOURCE"
    while [ -h "$REAL_SOURCE" ]; do
        DIR="$(cd -P "$(dirname "$REAL_SOURCE")" >/dev/null 2>&1 && pwd)"
        REAL_SOURCE="$(readlink "$REAL_SOURCE")"
        [[ "$REAL_SOURCE" != /* ]] && REAL_SOURCE="$DIR/$REAL_SOURCE"
    done
    REPO_DIR="$(cd -P "$(dirname "$REAL_SOURCE")" && pwd)"
    if [ -f "$REPO_DIR/agyist" ] && [ -f "$REPO_DIR/lib/installer.sh" ]; then
        ensure_path_configured
        chmod +x "$REPO_DIR/agyist"
        ln -sfn "$REPO_DIR/agyist" "$HOME/.local/bin/agyist" 2>/dev/null || true
        if [ "$(id -u)" -eq 0 ] || [ -w "/usr/local/bin" ]; then
            ln -sfn "$REPO_DIR/agyist" "/usr/local/bin/agyist" 2>/dev/null || true
        fi
        exec "$REPO_DIR/agyist" "$@"
    fi
fi

# 2. If piped via curl | bash
echo "==> Bootstrapping Antigravity Installer Suite (agyist)..."

APP_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/agyist"
mkdir -p "$APP_DATA" 2>/dev/null || true

REPO_URL="${AGYIST_REPO_URL:-${AGYIST_GIT_URL:-https://github.com/plusinfolab/agyist.git}}"
TARBALL_URL="${AGYIST_TARBALL_URL:-https://github.com/plusinfolab/agyist/archive/refs/heads/main.tar.gz}"

if [ -d "$APP_DATA/.git" ] && command -v git >/dev/null 2>&1; then
    echo "Updating existing agyist scripts..."
    git -C "$APP_DATA" pull --quiet || true
elif command -v git >/dev/null 2>&1; then
    echo "Fetching agyist repository..."
    git clone --depth 1 "$REPO_URL" "$APP_DATA" 2>/dev/null || {
        echo "Git clone failed (or private repository). Attempting archive download..."
        curl -fsSL "$TARBALL_URL" | tar -xz -C "$APP_DATA" --strip-components=1 2>/dev/null || true
    }
elif command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    echo "Fetching agyist archive..."
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$APP_DATA" --strip-components=1 2>/dev/null || true
else
    echo "Error: Neither git nor curl+tar is available to install agyist." >&2
    exit 1
fi

# If remote download was blocked (e.g. private repo), check for local copy
if [ ! -f "$APP_DATA/agyist" ] || [ ! -f "$APP_DATA/lib/common.sh" ]; then
    for local_cand in "$HOME/Projects/agyist" "$PWD"; do
        if [ -f "$local_cand/agyist" ] && [ -f "$local_cand/lib/common.sh" ]; then
            echo "Copying local agyist suite from $local_cand to $APP_DATA..."
            cp -r "$local_cand"/* "$APP_DATA/" 2>/dev/null || true
            break
        fi
    done
fi

if [ ! -f "$APP_DATA/agyist" ] || [ ! -f "$APP_DATA/lib/common.sh" ]; then
    echo "Error: Failed to obtain agyist suite files." >&2
    echo "If https://github.com/plusinfolab/agyist.git is private, please clone with your credentials first:" >&2
    echo "  git clone https://github.com/plusinfolab/agyist.git ~/Projects/agyist" >&2
    echo "  cd ~/Projects/agyist && ./install.sh" >&2
    exit 1
fi

# Ensure agyist launcher is installed in PATH
ensure_path_configured
if [ -f "$APP_DATA/agyist" ]; then
    chmod +x "$APP_DATA/agyist"
    ln -sfn "$APP_DATA/agyist" "$HOME/.local/bin/agyist" 2>/dev/null || true
    if [ "$(id -u)" -eq 0 ] || [ -w "/usr/local/bin" ]; then
        ln -sfn "$APP_DATA/agyist" "/usr/local/bin/agyist" 2>/dev/null || true
    fi

    # If explicit CLI arguments were passed, execute them directly
    if [ $# -gt 0 ]; then
        exec "$APP_DATA/agyist" "$@"
    fi

    show_post_install_box

    # If interactive terminal is attached (/dev/tty), launch wizard
    if [ -t 0 ]; then
        exec "$APP_DATA/agyist"
    elif [ -c /dev/tty ] && [ -r /dev/tty ]; then
        echo "Launching interactive Antigravity installer..."
        exec "$APP_DATA/agyist" < /dev/tty
    else
        exit 0
    fi
fi

# Fallback: if repository could not be reached
echo "Error: Could not bootstrap agyist files." >&2
echo "Please clone the repository directly:" >&2
echo "  git clone $REPO_URL && cd agyist && ./agyist" >&2
exit 1
