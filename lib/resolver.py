#!/usr/bin/env python3
"""
lib/resolver.py - Official Google Antigravity Download URL & Version Resolver
Resolves official Linux tarball URLs and versions for Antigravity IDE & Antigravity 2.0.
"""

import sys
import os
import re
import json
import gzip
import argparse
import urllib.request
from urllib.parse import unquote

DOWNLOAD_PAGE = "https://antigravity.google/download"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"

# Fallback known release versions and URLs if the live download portal is unreachable
FALLBACK_RELEASES = {
    "ide": {
        "linux-x64": {
            "version": "2.5.5",
            "full_version": "2.5.5-4923483625488384",
            "url": "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-x64/Antigravity%20IDE.tar.gz"
        },
        "linux-arm": {
            "version": "2.5.5",
            "full_version": "2.5.5-4923483625488384",
            "url": "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/2.5.5-4923483625488384/linux-arm/Antigravity%20IDE.tar.gz"
        }
    },
    "desktop": {
        "linux-x64": {
            "version": "2.13.0",
            "full_version": "2.13.0-6362815968182272",
            "url": "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.13.0-6362815968182272/linux-x64/Antigravity.tar.gz"
        },
        "linux-arm": {
            "version": "2.13.0",
            "full_version": "2.13.0-6362815968182272",
            "url": "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.13.0-6362815968182272/linux-arm/Antigravity.tar.gz"
        }
    }
}

def extract_version_from_url(url: str) -> str:
    decoded = unquote(url)
    # Typical patterns: /stable/<version>/ or /antigravity-hub/<version>/
    patterns = [
        r'/antigravity-hub/([^/]+)/',
        r'/stable/([^/]+)/',
        r'/(\d+\.\d+\.\d+(?:-[^/]+)?)/'
    ]
    for pattern in patterns:
        m = re.search(pattern, decoded)
        if m:
            raw_version = m.group(1)
            # Return semantic version (strip hash/build suffix if needed for display)
            return raw_version.split('-')[0]
    return "unknown"

def fetch_page_content(url: str) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept-Encoding": "gzip, deflate",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        }
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        raw = resp.read()
        if resp.info().get("Content-Encoding") == "gzip":
            try:
                raw = gzip.decompress(raw)
            except Exception:
                pass
        return raw.decode("utf-8", errors="replace")

def resolve_online(product: str, platform: str):
    """
    Scrapes https://antigravity.google/download to find the official download URL.
    Returns: (version, full_url)
    """
    html = fetch_page_content(DOWNLOAD_PAGE)
    
    # Target file patterns
    if product == "ide":
        filename_pattern = r'Antigravity(?:%20|\+| )IDE\.tar\.gz'
    else:
        filename_pattern = r'Antigravity\.tar\.gz'
        
    regex_str = rf'https?://[^\s"\'<>)]+/{re.escape(platform)}/{filename_pattern}'
    matches = re.findall(regex_str, html)
    
    if matches:
        # Take the most recent/authoritative match
        url = matches[-1].replace(" ", "%20")
        version = extract_version_from_url(url)
        return version, url
        
    # Check if download page references any JavaScript or JSON bundles
    scripts = re.findall(r'src=["\']([^"\']+\.js)["\']', html)
    for script_rel in scripts:
        script_url = urllib.parse.urljoin(DOWNLOAD_PAGE, script_rel)
        try:
            js_content = fetch_page_content(script_url)
            js_matches = re.findall(regex_str, js_content)
            if js_matches:
                url = js_matches[-1].replace(" ", "%20")
                version = extract_version_from_url(url)
                return version, url
        except Exception:
            continue
            
    raise RuntimeError(f"Could not find download URL for {product} on {platform} in live page.")

def get_release_info(product: str, platform: str):
    try:
        version, url = resolve_online(product, platform)
        return {
            "product": product,
            "platform": platform,
            "version": version,
            "url": url,
            "source": "live"
        }
    except Exception as e:
        fallback = FALLBACK_RELEASES.get(product, {}).get(platform)
        if fallback:
            return {
                "product": product,
                "platform": platform,
                "version": fallback["version"],
                "url": fallback["url"],
                "source": "fallback",
                "error": str(e)
            }
        raise

def parse_installed_version(install_path: str) -> str:
    """Detects version from package.json or version stamp file"""
    if not os.path.exists(install_path):
        return "none"
        
    # Check version stamp file
    vfile = os.path.join(install_path, ".antigravity-version")
    if os.path.isfile(vfile):
        try:
            with open(vfile, "r") as f:
                return f.read().strip()
        except Exception:
            pass
            
    # Check package.json (for IDE)
    pkg_json = os.path.join(install_path, "resources", "app", "package.json")
    if not os.path.isfile(pkg_json):
        # Could be inside Antigravity-IDE subfolder
        pkg_json = os.path.join(install_path, "Antigravity-IDE", "resources", "app", "package.json")
        
    if os.path.isfile(pkg_json):
        try:
            with open(pkg_json, "r") as f:
                data = json.load(f)
                return data.get("version", "unknown")
        except Exception:
            pass
            
    return "installed (unknown version)"

def main():
    parser = argparse.ArgumentParser(description="Official Google Antigravity Download Resolver")
    parser.add_argument("--product", choices=["ide", "desktop"], default="ide", help="Product to resolve")
    parser.add_argument("--platform", choices=["linux-x64", "linux-arm"], default="linux-x64", help="Platform architecture")
    parser.add_argument("--check-path", help="Check installed path and compare with latest")
    parser.add_argument("--json", action="store_true", help="Output result as JSON")
    parser.add_argument("--url-only", action="store_true", help="Print download URL only")
    parser.add_argument("--version-only", action="store_true", help="Print latest version only")
    
    args = parser.parse_args()
    
    try:
        info = get_release_info(args.product, args.platform)
        
        if args.check_path:
            installed_ver = parse_installed_version(args.check_path)
            info["installed_version"] = installed_ver
            info["update_available"] = (installed_ver != info["version"] and installed_ver != "none")
            
        if args.json:
            print(json.dumps(info, indent=2))
        elif args.url_only:
            print(info["url"])
        elif args.version_only:
            print(info["version"])
        else:
            print(f"{info['version']} {info['url']}")
            
    except Exception as err:
        sys.stderr.write(f"Error resolving download: {err}\n")
        sys.exit(1)

if __name__ == "__main__":
    main()

