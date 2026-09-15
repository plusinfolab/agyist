#!/usr/bin/env bash
# lib/resolver.sh - Pure Native Bash Google Antigravity Download URL & Version Resolver
# Zero Python dependency. Scrapes official Google download links directly using curl & sed/grep.

set -euo pipefail

DOWNLOAD_PAGE="https://antigravity.google/download"
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
CACHE_FILE="/tmp/agyist-download-cache.html"

# Verified fallback URLs in case machine is completely offline or download portal is down
FALLBACK_IDE_X64_VER="2.5.5"
FALLBACK_IDE_X64_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-x64/Antigravity%20IDE.tar.gz"

FALLBACK_IDE_ARM_VER="2.5.5"
FALLBACK_IDE_ARM_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-arm/Antigravity%20IDE.tar.gz"

FALLBACK_DESKTOP_X64_VER="2.13.0"
FALLBACK_DESKTOP_X64_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/2.13.0-6362815968182272/linux-x64/Antigravity.tar.gz"

FALLBACK_DESKTOP_ARM_VER="2.13.0"
FALLBACK_DESKTOP_ARM_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/2.13.0-6362815968182272/linux-arm/Antigravity.tar.gz"

extract_version_from_url() {
    local url="$1"
    local ver
    ver="$(echo "$url" | sed -nE 's|.*/([0-9]+\.[0-9]+\.[0-9]+)[^/]*/.*|\1|p' | head -n 1)"
    if [ -z "$ver" ]; then
        ver="$(echo "$url" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || echo "unknown")"
    fi
    echo "$ver"
}

fetch_download_page() {
    if command -v curl >/dev/null 2>&1; then
        local cache_age=999999
        if [ -f "$CACHE_FILE" ]; then
            local now file_mtime
            now="$(date +%s)"
            file_mtime="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)"
            cache_age=$(( now - file_mtime ))
        fi

        # Refresh cache if older than 300 seconds
        if [ "$cache_age" -gt 300 ] || [ ! -s "$CACHE_FILE" ]; then
            curl -fsSL --compressed -A "$USER_AGENT" --connect-timeout 8 --max-time 20 "$DOWNLOAD_PAGE" -o "$CACHE_FILE" 2>/dev/null || true
        fi
    fi
}

resolve_official_download() {
    local product="${1:-ide}"       # "ide" or "desktop"
    local platform="${2:-linux-x64}" # "linux-x64" or "linux-arm"

    fetch_download_page

    local resolved_url=""
    local resolved_version=""

    # 1. Attempt live scraping via curl & cache
    if command -v curl >/dev/null 2>&1; then
        local pattern
        if [ "$product" = "ide" ]; then
            pattern='https://[^"'\''<>\ ]+/'"$platform"'/Antigravity(%20|\+| )?IDE\.tar\.gz'
        else
            pattern='https://[^"'\''<>\ ]+/'"$platform"'/Antigravity\.tar\.gz'
        fi

        if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
            resolved_url="$(grep -oE "$pattern" "$CACHE_FILE" | head -n 1 || true)"
        fi

        if [ -z "$resolved_url" ]; then
            local html
            if html="$(curl -fsSL --compressed -A "$USER_AGENT" --connect-timeout 5 --max-time 15 "$DOWNLOAD_PAGE" 2>/dev/null)"; then
                resolved_url="$(echo "$html" | grep -oE "$pattern" | head -n 1 || true)"
            fi
        fi
    fi

    # 2. Check if live scrape succeeded
    if [ -n "$resolved_url" ]; then
        # Normalize spaces to %20
        resolved_url="${resolved_url// /%20}"
        resolved_version="$(extract_version_from_url "$resolved_url")"
        echo "$resolved_version $resolved_url live"
        return 0
    fi

    # 3. Fallback to official Google CDN release builds
    if [ "$product" = "ide" ]; then
        if [ "$platform" = "linux-arm" ]; then
            echo "$FALLBACK_IDE_ARM_VER $FALLBACK_IDE_ARM_URL fallback"
        else
            echo "$FALLBACK_IDE_X64_VER $FALLBACK_IDE_X64_URL fallback"
        fi
    else
        if [ "$platform" = "linux-arm" ]; then
            echo "$FALLBACK_DESKTOP_ARM_VER $FALLBACK_DESKTOP_ARM_URL fallback"
        else
            echo "$FALLBACK_DESKTOP_X64_VER $FALLBACK_DESKTOP_X64_URL fallback"
        fi
    fi
}

check_for_updates() {
    local product="${1:-ide}"
    local install_path="${2:-}"
    local platform
    platform="$(uname -m)"
    case "$platform" in
        x86_64|amd64) platform="linux-x64" ;;
        aarch64|arm64) platform="linux-arm" ;;
        *) platform="linux-x64" ;;
    esac

    local installed_version="unknown"
    if [ -n "$install_path" ] && [ -d "$install_path" ]; then
        if [ -f "$install_path/.antigravity-version" ]; then
            installed_version="$(cat "$install_path/.antigravity-version" | tr -d '[:space:]')"
        elif [ -f "$install_path/resources/app/package.json" ]; then
            installed_version="$(grep -oE '"version": *"[^"]+"' "$install_path/resources/app/package.json" | head -n 1 | awk -F'"' '{print $4}' || echo "unknown")"
        fi
    fi

    local resolve_output
    resolve_output="$(resolve_official_download "$product" "$platform")"
    local latest_version
    latest_version="$(echo "$resolve_output" | awk '{print $1}')"
    local download_url
    download_url="$(echo "$resolve_output" | awk '{print $2}')"

    echo "Product:           $product"
    echo "Installed version: $installed_version"
    echo "Latest version:    $latest_version"
    echo "Download URL:      $download_url"

    if [ "$installed_version" = "unknown" ]; then
        echo "Status:            not installed or version unknown"
        return 10
    fi

    if [ "$installed_version" = "$latest_version" ]; then
        echo "Status:            up to date"
        return 0
    else
        echo "Status:            update available ($installed_version -> $latest_version)"
        return 10
    fi
}

# Direct CLI invocation
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ "${1:-}" = "--check-update" ]; then
        prod="${2:-ide}"
        path="${3:-}"
        check_for_updates "$prod" "$path"
        exit $?
    fi
    prod="${1:-ide}"
    plat="${2:-linux-x64}"
    resolve_official_download "$prod" "$plat"
fi
