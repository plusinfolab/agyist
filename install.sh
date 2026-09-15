#!/usr/bin/env bash
# install.sh - One-line Bootstrap and Installer for Google Antigravity & Antigravity IDE
#
# Quick install:
#   curl -fsSL https://raw.githubusercontent.com/username/agyist/main/install.sh | bash
#
# With options:
#   curl -fsSL https://raw.githubusercontent.com/username/agyist/main/install.sh | bash -s -- --ide
#   curl -fsSL https://raw.githubusercontent.com/username/agyist/main/install.sh | bash -s -- --all

set -euo pipefail

# If running from within an existing checkout of agyist
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
    REPO_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    if [ -f "$REPO_DIR/agyist" ] && [ -f "$REPO_DIR/lib/installer.sh" ]; then
        exec "$REPO_DIR/agyist" "$@"
    fi
fi

# If piped via curl | bash
echo "==> Bootstrapping Antigravity Installer Suite (agyist)..."

APP_DATA="${XDG_DATA_HOME:-$HOME/.local/share}/agyist"
mkdir -p "$APP_DATA"

REPO_URL="${AGYIST_GIT_URL:-https://github.com/opensnap/antigravity.git}" # Can be customized or defaulted

# Ensure git or curl is available
if command -v git >/dev/null 2>&1; then
    if [ -d "$APP_DATA/.git" ]; then
        echo "Updating existing agyist scripts..."
        git -C "$APP_DATA" pull --quiet || true
    else
        echo "Fetching agyist..."
        # In case git clone is used
        if [ -n "${AGYIST_REPO_URL:-}" ]; then
            git clone --depth 1 "$AGYIST_REPO_URL" "$APP_DATA"
        fi
    fi
fi

# Ensure agyist launcher is in PATH
mkdir -p "$HOME/.local/bin"
if [ -f "$APP_DATA/agyist" ]; then
    chmod +x "$APP_DATA/agyist"
    ln -sfn "$APP_DATA/agyist" "$HOME/.local/bin/agyist"
    exec "$APP_DATA/agyist" "$@"
fi

# Fallback: if running standalone
echo "Error: Could not bootstrap agyist files. Please clone the repository and run ./agyist" >&2
exit 1
