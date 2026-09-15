#!/usr/bin/env bash
# lib/resolver.sh - Pure Native Bash Google Antigravity Download URL & Version Resolver
# Zero Python dependency. Scrapes official Google download links directly using curl & sed/grep.

set -euo pipefail

DOWNLOAD_PAGE="https://antigravity.google/download"
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
CACHE_FILE="/tmp/agyist-download-cache.html"

# Verified fallback URLs in case machine is completely offline or download portal changes
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

    # 1. Attempt live scraping via curl
    if command -v curl >/dev/null 2>&1; then
    if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
        local pattern
        if [ "$product" = "ide" ]; then
            pattern='https://[^"'\''<>\ ]+/'"$platform"'/Antigravity(%20|\+| )?IDE\.tar\.gz'
        else
            pattern='https://[^"'\''<>\ ]+/'"$platform"'/Antigravity\.tar\.gz'
        fi

        local html
        if html="$(curl -fsSL --compressed -A "$USER_AGENT" --connect-timeout 5 --max-time 15 "$DOWNLOAD_PAGE" 2>/dev/null)"; then
            resolved_url="$(echo "$html" | grep -oE "$pattern" | head -n 1 || true)"
        fi
        resolved_url="$(grep -oE "$pattern" "$CACHE_FILE" | head -n 1 || true)"
    fi

    # 2. Check if live scrape succeeded
    if [ -n "$resolved_url" ]; then
        # Normalize spaces to %20
        resolved_url="${resolved_url// /%20}"
        resolved_version="$(extract_version_from_url "$resolved_url")"
        echo "$resolved_version $resolved_url live"
        return 0
    fi

    # 3. Fallback to official Google edge cache / cloud storage releases
    # Fallback to official Google CDN release builds
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

# If executed directly as CLI
# Direct CLI invocation
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    prod="${1:-ide}"
    plat="${2:-linux-x64}"
    resolve_official_download "$prod" "$plat"
fi
