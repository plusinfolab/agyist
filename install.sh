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

# Ensure ~/.local/bin is configured in user shell profiles
ensure_path_configured() {
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir" 2>/dev/null || true
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [ -f "$rc" ] && ! grep -qs "\.local/bin" "$rc"; then
            echo -e "\n# Antigravity CLI Suite (agyist)\nexport PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$rc"
        fi
    done
}

# 1. If running from within an existing checkout of agyist
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
    REPO_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
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
mkdir -p "$APP_DATA"

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
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$APP_DATA" --strip-components=1
else
    echo "Error: Neither git nor curl+tar is available to install agyist." >&2
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

    echo "✔ agyist command installed successfully to $HOME/.local/bin/agyist"

    # If explicit CLI arguments were passed, execute them directly
    if [ $# -gt 0 ]; then
        exec "$APP_DATA/agyist" "$@"
    fi

    # If no arguments were passed:
    # Check if we can attach to an interactive terminal (/dev/tty)
    if [ -t 0 ]; then
        exec "$APP_DATA/agyist"
    elif [ -c /dev/tty ] && [ -r /dev/tty ]; then
        echo "Launching interactive Antigravity installer..."
        exec "$APP_DATA/agyist" < /dev/tty
    else
        echo ""
        echo "=========================================================="
        echo "  agyist is now installed and ready on this device!"
        echo "=========================================================="
        echo "  Run agyist in any terminal to open the wizard."
        echo "  Or run: agyist --ide      (Install Antigravity IDE)"
        echo "          agyist --desktop  (Install Antigravity 2.0)"
        echo "          agyist --all      (Install both)"
        echo "=========================================================="
        exit 0
    fi
fi

# Fallback: if repository could not be reached
echo "Error: Could not bootstrap agyist files." >&2
echo "Please clone the repository directly:" >&2
echo "  git clone $REPO_URL && cd agyist && ./agyist" >&2
exit 1
