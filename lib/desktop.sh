#!/usr/bin/env bash
# lib/desktop.sh - Desktop Integration, Icon Extraction, MIME registration for Antigravity

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

extract_asar_icon() {
    local asar_file="$1"
    local output_png="$2"
    
    python3 - "$asar_file" "$output_png" <<'PY'
import sys, json, struct
from pathlib import Path

asar_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])

if not asar_path.is_file():
    sys.exit(1)

try:
    with asar_path.open('rb') as f:
        f.read(4)
        header_size = struct.unpack('<I', f.read(4))[0]
        f.read(4)
        json_size = struct.unpack('<I', f.read(4))[0]
        header = json.loads(f.read(json_size).decode('utf-8', errors='ignore'))
        
    icon_info = header.get('files', {}).get('icon.png')
    if not icon_info:
        for name, meta in header.get('files', {}).items():
            if name.endswith('.png') and 'size' in meta:
                icon_info = meta
                break
                
    if not icon_info:
        sys.exit(1)
        
    with asar_path.open('rb') as f:
        f.seek(8 + header_size + int(icon_info['offset']))
        data = f.read(int(icon_info['size']))
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_bytes(data)
        sys.exit(0)
except Exception:
    sys.exit(1)
PY
}

install_desktop_integration() {
    local product="$1"       # "ide" or "desktop"
    local install_dir="$2"   # e.g. /opt/antigravity-ide or ~/.local/share/antigravity-ide
    local binary_path="$3"   # e.g. /usr/local/bin/antigravity-ide or ~/.local/bin/antigravity-ide
    local scope="${4:-auto}" # "system", "user", or "auto"

    local icon_dir hicolor_dir desktop_dir pixmap_dir
    if [ "$scope" = "system" ] || ([ "$scope" = "auto" ] && [ "$(id -u)" -eq 0 ]); then
        icon_dir="/usr/share/icons/hicolor/512x512/apps"
        hicolor_dir="/usr/share/icons/hicolor"
        desktop_dir="/usr/share/applications"
        pixmap_dir="/usr/share/pixmaps"
    else
        icon_dir="$HOME/.local/share/icons/hicolor/512x512/apps"
        hicolor_dir="$HOME/.local/share/icons/hicolor"
        desktop_dir="$HOME/.local/share/applications"
        pixmap_dir="$HOME/.local/share/pixmaps"
    fi

    mkdir -p "$icon_dir" "$desktop_dir"
    mkdir -p "$hicolor_dir/512x512/apps" "$hicolor_dir/256x256/apps" "$hicolor_dir/scalable/apps" "$desktop_dir"
    if [ -w "$pixmap_dir" ] || [ "$(id -u)" -eq 0 ]; then
        mkdir -p "$pixmap_dir" 2>/dev/null || true
    fi

    if [ "$product" = "ide" ]; then
        local icon_name="antigravity-ide"
        local icon_installed="$hicolor_dir/512x512/apps/$icon_name.png"

        # Search for icon in bundled assets or extracted IDE files
        local candidates=(
            "$SCRIPT_DIR/../assets/icons/antigravity-ide.png"
            "$install_dir/resources/app/resources/linux/code.png"
            "$install_dir/Antigravity-IDE/resources/app/resources/linux/code.png"
            "$install_dir/resources/app/resources/linux/antigravity.png"
            "$install_dir/antigravity.png"
            "/usr/share/pixmaps/antigravity.png"
        )
        local found_icon=0
        for cand in "${candidates[@]}"; do
            if [ -f "$cand" ]; then
                cp "$cand" "$icon_installed"
                chmod 644 "$icon_installed" 2>/dev/null || true
                cp "$cand" "$hicolor_dir/256x256/apps/$icon_name.png" 2>/dev/null || true
                if [ -w "$pixmap_dir" ]; then
                    cp "$cand" "$pixmap_dir/$icon_name.png" 2>/dev/null || true
                fi
                found_icon=1
                break
            fi
        done

        # Create Antigravity IDE .desktop entry
        local desktop_file="$desktop_dir/antigravity-ide.desktop"
        cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Name=Antigravity IDE
Comment=Google Antigravity IDE - Code with Gemini
GenericName=Text Editor
Exec="$binary_path" %F
Icon=$icon_name
Type=Application
StartupNotify=true
StartupWMClass=antigravity-ide
Categories=Development;IDE;TextEditor;
MimeType=inode/directory;text/plain;application/x-code-workspace;application/x-antigravity-workspace;x-scheme-handler/antigravity-ide;
Actions=new-empty-window;
Keywords=vscode;antigravity;ide;ai;

[Desktop Action new-empty-window]
Name=New Empty Window
Exec="$binary_path" --new-window %F
Icon=$icon_name
DESKTOP
        chmod 644 "$desktop_file" 2>/dev/null || true

        # Create URL Handler .desktop entry
        local url_desktop="$desktop_dir/antigravity-ide-url-handler.desktop"
        cat > "$url_desktop" <<DESKTOP
[Desktop Entry]
Name=Antigravity IDE - URL Handler
Comment=Open URLs with Antigravity IDE
GenericName=Text Editor
Exec="$binary_path" --open-url %U
Icon=$icon_name
Type=Application
NoDisplay=true
StartupNotify=true
Categories=Development;IDE;
MimeType=x-scheme-handler/antigravity-ide;
DESKTOP
        chmod 644 "$url_desktop" 2>/dev/null || true

    else
        # Desktop 2.0 app
        local icon_name="antigravity-2"
        local icon_installed="$icon_dir/$icon_name.png"

        # Install genuine Antigravity 2.0 icons into hicolor directories & pixmaps
        local icon_256="$SCRIPT_DIR/../assets/icons/antigravity-2.png"
        local icon_512="$SCRIPT_DIR/../assets/icons/antigravity-2-512.png"
        [ -f "$icon_512" ] || icon_512="$icon_256"
        local icon_svg="$SCRIPT_DIR/../assets/icons/antigravity-2.svg"

        if [ -f "$icon_256" ]; then
            cp "$icon_256" "$icon_installed"
            cp "$icon_256" "$icon_dir/antigravity.png" 2>/dev/null || true
            chmod 644 "$icon_installed" "$icon_dir/antigravity.png" 2>/dev/null || true

            cp "$icon_256" "$hicolor_dir/256x256/apps/$icon_name.png" 2>/dev/null || true
            cp "$icon_256" "$hicolor_dir/256x256/apps/antigravity.png" 2>/dev/null || true
            chmod 644 "$hicolor_dir/256x256/apps/$icon_name.png" "$hicolor_dir/256x256/apps/antigravity.png" 2>/dev/null || true
        fi

        if [ -f "$icon_512" ]; then
            cp "$icon_512" "$hicolor_dir/512x512/apps/$icon_name.png" 2>/dev/null || true
            cp "$icon_512" "$hicolor_dir/512x512/apps/antigravity.png" 2>/dev/null || true
            chmod 644 "$hicolor_dir/512x512/apps/$icon_name.png" "$hicolor_dir/512x512/apps/antigravity.png" 2>/dev/null || true
        fi

        if [ -f "$icon_svg" ]; then
            cp "$icon_svg" "$hicolor_dir/scalable/apps/$icon_name.svg" 2>/dev/null || true
            cp "$icon_svg" "$hicolor_dir/scalable/apps/antigravity.svg" 2>/dev/null || true
            chmod 644 "$hicolor_dir/scalable/apps/$icon_name.svg" "$hicolor_dir/scalable/apps/antigravity.svg" 2>/dev/null || true
        fi

        if [ -w "$pixmap_dir" ]; then
            if [ -f "$icon_512" ]; then
                cp "$icon_512" "$pixmap_dir/$icon_name.png" 2>/dev/null || true
                cp "$icon_512" "$pixmap_dir/antigravity.png" 2>/dev/null || true
            fi
        fi

        # Create Antigravity 2.0 .desktop entry
        local desktop_file="$desktop_dir/antigravity.desktop"
        cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Name=Antigravity 2.0
Comment=Google Antigravity 2.0 Agent Platform
GenericName=AI Agent Platform
Exec="$binary_path" %U
Icon=$icon_name
Type=Application
StartupNotify=true
StartupWMClass=Antigravity
Categories=Development;IDE;Utility;
MimeType=x-scheme-handler/antigravity;
Actions=new-window;

[Desktop Action new-window]
Name=New Window
Exec="$binary_path" --new-window
Icon=$icon_name
DESKTOP
        chmod 644 "$desktop_file" 2>/dev/null || true

        # Also create antigravity-2.desktop for explicit search
        cp "$desktop_file" "$desktop_dir/antigravity-2.desktop" 2>/dev/null || true

        # URL handler
        local url_desktop="$desktop_dir/antigravity-url-handler.desktop"
        cat > "$url_desktop" <<DESKTOP
[Desktop Entry]
Name=Antigravity 2.0 - URL Handler
Comment=Open URLs with Antigravity 2.0
GenericName=AI Agent Platform
Exec="$binary_path" --open-url %U
Icon=$icon_name
Type=Application
NoDisplay=true
StartupNotify=true
Categories=Development;Utility;
MimeType=x-scheme-handler/antigravity;
DESKTOP
        chmod 644 "$url_desktop" 2>/dev/null || true
    fi

    # Refresh desktop & icon databases
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$desktop_dir" >/dev/null 2>&1 || true
    fi
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        local base_icon_theme
        base_icon_theme="$(dirname "$(dirname "$(dirname "$icon_dir")")")"
        gtk-update-icon-cache -q -f "$base_icon_theme" >/dev/null 2>&1 || true
        gtk-update-icon-cache -q -f "$hicolor_dir" >/dev/null 2>&1 || true
    fi
}

install_nautilus_extension() {
    local nautilus_dir="$HOME/.local/share/nautilus-python/extensions"
    mkdir -p "$nautilus_dir"
    local ext_script="$SCRIPT_DIR/nautilus.py"
    if [ -f "$ext_script" ]; then
        cp "$ext_script" "$nautilus_dir/antigravity_nautilus.py"
        chmod 644 "$nautilus_dir/antigravity_nautilus.py"
    fi
}
