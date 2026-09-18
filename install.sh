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

# 1. If running from within an existing checkout of agyist
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
    REPO_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    if [ -f "$REPO_DIR/agyist" ] && [ -f "$REPO_DIR/lib/installer.sh" ]; then
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
        echo "Git clone failed or repository not public yet, trying archive download..."
        curl -fsSL "$TARBALL_URL" | tar -xz -C "$APP_DATA" --strip-components=1 2>/dev/null || true
    }
elif command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    echo "Fetching agyist archive..."
    curl -fsSL "$TARBALL_URL" | tar -xz -C "$APP_DATA" --strip-components=1
else
    echo "Error: Neither git nor curl+tar is available to install agyist." >&2
    exit 1
fi

# Ensure agyist launcher is in PATH
mkdir -p "$HOME/.local/bin"
if [ -f "$APP_DATA/agyist" ]; then
    chmod +x "$APP_DATA/agyist"
    ln -sfn "$APP_DATA/agyist" "$HOME/.local/bin/agyist"

    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) echo "Notice: $HOME/.local/bin is not in your current PATH. Add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to ~/.bashrc" ;;
    esac

    exec "$APP_DATA/agyist" "$@"
fi

# Fallback: if repository could not be reached
echo "Error: Could not bootstrap agyist files." >&2
echo "Please clone the repository directly:" >&2
echo "  git clone $REPO_URL && cd agyist && ./agyist" >&2
exit 1
