#!/usr/bin/env python3
"""
lib/migrator.py - Antigravity Brain, Chat, Memory & State Migration/Sync Suite
Handles backup, restore, import, and cross-version bi-directional sync for:
- Agent Brains (~/.gemini/antigravity/brain/)
- Knowledge Base (~/.gemini/antigravity/knowledge/)
- Conversation logs & DBs (~/.gemini/antigravity/conversations/)
- SQLite state databases (state.vscdb) with protobuf concatenation
- User settings, keybindings, snippets, and workspaces
- Extensions & extensions.json path updates
"""

import os
import sys
import json
import shutil
import sqlite3
import base64
import tarfile
import argparse
import glob
import time
import subprocess
import contextlib
import tempfile
import re
import uuid
import getpass
import socket
from datetime import datetime
from pathlib import Path

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
    from cryptography.hazmat.primitives import hashes
    HAS_CRYPTOGRAPHY = True
except ImportError:
    HAS_CRYPTOGRAPHY = False

try:
    import websockets
    import asyncio
    HAS_WEBSOCKETS = True
except ImportError:
    HAS_WEBSOCKETS = False

HOME = os.path.expanduser("~")

# Default paths on Linux
PATH_CONFIG_LEGACY = os.path.join(HOME, ".config", "Antigravity")
PATH_CONFIG_IDE    = os.path.join(HOME, ".config", "Antigravity IDE")
PATH_GEMINI_MAIN   = os.path.join(HOME, ".gemini", "antigravity")
PATH_GEMINI_IDE    = os.path.join(HOME, ".gemini", "antigravity-ide")
PATH_DOT_LEGACY    = os.path.join(HOME, ".antigravity")
PATH_DOT_IDE       = os.path.join(HOME, ".antigravity-ide")

PROTOBUF_KEYS_TO_CONCAT = [
    "antigravityUnifiedStateSync.trajectorySummaries",
    "antigravityUnifiedStateSync.sidebarWorkspaces",
]

def log(msg, level="INFO"):
    colors = {
        "INFO": "\033[0;36mℹ\033[0m",
        "SUCCESS": "\033[0;32m✔\033[0m",
        "WARN": "\033[0;33m⚠\033[0m",
        "ERROR": "\033[0;31m✖\033[0m",
        "STEP": "\033[1;35m==>\033[0m"
    }
    prefix = colors.get(level, f"[{level}]")
    print(f"{prefix} {msg}")

def merge_json_files(src_path: str, dst_path: str, dry_run: bool = False) -> bool:
    """Merges two JSON dictionaries. Destination keys override source keys on conflict."""
    if not os.path.exists(src_path):
        return False
        
    src_data = {}
    try:
        with open(src_path, "r", encoding="utf-8") as f:
            src_data = json.load(f)
    except Exception as e:
        log(f"Failed to read source JSON {src_path}: {e}", "WARN")
        return False
        
    dst_data = {}
    if os.path.exists(dst_path):
        try:
            with open(dst_path, "r", encoding="utf-8") as f:
                dst_data = json.load(f)
        except Exception:
            pass
            
    merged = src_data.copy()
    merged.update(dst_data)
    
    if not dry_run:
        os.makedirs(os.path.dirname(dst_path), exist_ok=True)
        with open(dst_path, "w", encoding="utf-8") as f:
            json.dump(merged, f, indent=2)
    return True

def merge_sqlite_vscdb(src_db: str, dst_db: str, dry_run: bool = False, write_both: bool = False) -> int:
    """
    Merges two state.vscdb SQLite databases.
    Special protobuf keys (trajectory summaries & sidebar workspaces) are merged
    via binary concatenation of their base64-decoded protobuf payloads.
    Conversation notification threads and secrets are unified across both databases.
    If write_both is True, the merged database is saved to both src_db and dst_db.
    """
    if not os.path.exists(src_db) and not os.path.exists(dst_db):
        return 0
        
    src_data = {}
    if os.path.exists(src_db):
        try:
            conn = sqlite3.connect(src_db)
            cursor = conn.cursor()
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='ItemTable'")
            if cursor.fetchone():
                cursor.execute("SELECT key, value FROM ItemTable")
                for row in cursor.fetchall():
                    src_data[row[0]] = row[1]
            conn.close()
        except Exception as e:
            log(f"Error reading source database {src_db}: {e}", "ERROR")
            
    dst_data = {}
    if os.path.exists(dst_db):
        try:
            conn = sqlite3.connect(dst_db)
            cursor = conn.cursor()
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='ItemTable'")
            if cursor.fetchone():
                cursor.execute("SELECT key, value FROM ItemTable")
                for row in cursor.fetchall():
                    dst_data[row[0]] = row[1]
            conn.close()
        except Exception as e:
            log(f"Error reading destination database {dst_db}: {e}", "WARN")
            
    merged_data = src_data.copy()
    keys_updated = 0
    
    for key, dst_val in dst_data.items():
        if key in PROTOBUF_KEYS_TO_CONCAT and key in src_data:
            try:
                src_bytes = base64.b64decode(src_data[key])
                dst_bytes = base64.b64decode(dst_val)
                if src_bytes and dst_bytes and src_bytes != dst_bytes:
                    merged_bytes = src_bytes + dst_bytes
                    merged_data[key] = base64.b64encode(merged_bytes).decode("utf-8")
                    keys_updated += 1
                    log(f"Concatenated protobuf message for key '{key}' ({len(src_bytes)}B src + {len(dst_bytes)}B dst)")
                else:
                    merged_data[key] = dst_val if dst_val else src_data[key]
            except Exception as e:
                log(f"Failed to concat protobuf key '{key}': {e}. Preserving destination value.", "WARN")
                merged_data[key] = dst_val
        elif key not in merged_data:
            merged_data[key] = dst_val
        else:
            if key.startswith("secret://") or "notification" in key:
                if not merged_data[key] and dst_val:
                    merged_data[key] = dst_val
            else:
                merged_data[key] = dst_val

    def _write_db(target_path: str):
        if dry_run:
            return
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        if os.path.exists(target_path):
            try:
                shutil.copy2(target_path, target_path + ".backup")
            except Exception:
                pass
        conn = sqlite3.connect(target_path)
        cursor = conn.cursor()
        cursor.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)")
        for k, v in merged_data.items():
            cursor.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (k, v))
        conn.commit()
        conn.close()
        try:
            os.makedirs(os.path.dirname(target_path), exist_ok=True)
            if os.path.exists(target_path):
                try:
                    shutil.copy2(target_path, target_path + ".backup")
                except Exception:
                    pass
            conn = sqlite3.connect(target_path)
            cursor = conn.cursor()
            cursor.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value TEXT)")
            for k, v in merged_data.items():
                cursor.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (k, v))
            conn.commit()
            conn.close()
        except Exception as e:
            log(f"Warning: Could not write database {target_path}: {e}", "WARN")

    _write_db(dst_db)
    if write_both and src_db != dst_db:
        _write_db(src_db)
        
    return len(merged_data)

def copy_or_merge_directory(src: str, dst: str, dry_run: bool = False) -> int:
    """Recursively copies files from src to dst. Preserves existing dst files unless newer."""
    if not os.path.exists(src):
        return 0
    copied_count = 0
    for root, dirs, files in os.walk(src):
        rel_path = os.path.relpath(root, src)
        dest_root = os.path.join(dst, rel_path)
        if not dry_run:
            os.makedirs(dest_root, exist_ok=True)
            try:
                os.makedirs(dest_root, exist_ok=True)
            except Exception as e:
                log(f"Warning: Could not create directory {dest_root}: {e}", "WARN")
                continue
        for f in files:
            s_file = os.path.join(root, f)
            d_file = os.path.join(dest_root, f)
            if not os.path.exists(d_file) or os.path.getmtime(s_file) > os.path.getmtime(d_file):
                if not dry_run:
                    try:
                        shutil.copy2(s_file, d_file)
                    except Exception as e:
                        log(f"Failed copying {s_file} to {d_file}: {e}", "WARN")
                copied_count += 1
    return copied_count

def migrate_extensions(src_dot: str, dst_dot: str, dry_run: bool = False) -> int:
    """Migrates extensions folder and rewrites extensions.json metadata."""
    src_ext = os.path.join(src_dot, "extensions")
    dst_ext = os.path.join(dst_dot, "extensions")
    
    if not os.path.exists(src_ext):
        return 0
        
    src_json = os.path.join(src_ext, "extensions.json")
    dst_json = os.path.join(dst_ext, "extensions.json")
    
    src_exts = []
    if os.path.exists(src_json):
        try:
            with open(src_json, "r", encoding="utf-8") as f:
                src_exts = json.load(f)
        except Exception:
            pass
            
    dst_exts = []
    dst_ids = set()
    if os.path.exists(dst_json):
        try:
            with open(dst_json, "r", encoding="utf-8") as f:
                dst_exts = json.load(f)
                for item in dst_exts:
                    if "identifier" in item and "id" in item["identifier"]:
                        dst_ids.add(item["identifier"]["id"].lower())
        except Exception:
            pass
            
    new_list = list(dst_exts)
    added = 0
    
    for ext in src_exts:
        ext_id = ext.get("identifier", {}).get("id", "").lower()
        if not ext_id or ext_id in dst_ids:
            continue
            
        cloned = json.loads(json.dumps(ext))
        for key in ["location", "source"]:
            if key in cloned and isinstance(cloned[key], dict):
                for sub in ["path", "fsPath", "external"]:
                    if sub in cloned[key] and isinstance(cloned[key][sub], str):
                        cloned[key][sub] = cloned[key][sub].replace(src_dot, dst_dot)
                        
        rel_loc = ext.get("relativeLocation")
        if rel_loc:
            src_dir = os.path.join(src_ext, rel_loc)
            dst_dir = os.path.join(dst_ext, rel_loc)
            if os.path.exists(src_dir) and not os.path.exists(dst_dir) and not dry_run:
                try:
                    shutil.copytree(src_dir, dst_dir, symlinks=True)
                except Exception as e:
                    log(f"Failed to copy extension folder {rel_loc}: {e}", "WARN")
                    
        new_list.append(cloned)
        added += 1
        
    if not dry_run and added > 0:
        os.makedirs(dst_ext, exist_ok=True)
        with open(dst_json, "w", encoding="utf-8") as f:
            json.dump(new_list, f)
        try:
            os.makedirs(dst_ext, exist_ok=True)
            with open(dst_json, "w", encoding="utf-8") as f:
                json.dump(new_list, f)
        except Exception as e:
            log(f"Warning: Could not write extensions json {dst_json}: {e}", "WARN")
            
    return added

def merge_workspace_storage(dir_a: str, dir_b: str, dry_run: bool = False) -> int:
    """Bi-directionally synchronizes workspaceStorage folders and merges inner databases."""
    if not os.path.exists(dir_a) and not os.path.exists(dir_b):
        return 0
    if not dry_run:
        os.makedirs(dir_a, exist_ok=True)
        os.makedirs(dir_b, exist_ok=True)
        try:
            os.makedirs(dir_a, exist_ok=True)
            os.makedirs(dir_b, exist_ok=True)
        except Exception:
            pass
    
    set_a = set(os.listdir(dir_a)) if os.path.exists(dir_a) else set()
    set_b = set(os.listdir(dir_b)) if os.path.exists(dir_b) else set()
    all_ws = set_a | set_b
    merged_count = 0

    for ws in all_ws:
        path_a = os.path.join(dir_a, ws)
        path_b = os.path.join(dir_b, ws)
        
        if os.path.exists(path_a) and not os.path.exists(path_b):
            if not dry_run:
                shutil.copytree(path_a, path_b, symlinks=True)
                try:
                    shutil.copytree(path_a, path_b, symlinks=True)
                except Exception as e:
                    log(f"Warning: Could not copy workspace {path_a} to {path_b}: {e}", "WARN")
            merged_count += 1
        elif os.path.exists(path_b) and not os.path.exists(path_a):
            if not dry_run:
                shutil.copytree(path_b, path_a, symlinks=True)
                try:
                    shutil.copytree(path_b, path_a, symlinks=True)
                except Exception as e:
                    log(f"Warning: Could not copy workspace {path_b} to {path_a}: {e}", "WARN")
            merged_count += 1
        elif os.path.exists(path_a) and os.path.exists(path_b):
            db_a = os.path.join(path_a, "state.vscdb")
            db_b = os.path.join(path_b, "state.vscdb")
            if os.path.exists(db_a) or os.path.exists(db_b):
                merge_sqlite_vscdb(db_a, db_b, dry_run=dry_run, write_both=True)
                merged_count += 1
            
    return merged_count

def configure_pbtxt_states(status: str = "MIGRATION_STATUS_COMPLETED", dry_run: bool = False, pbtxt_path: str = None):
    """Configures antigravity_state.pbtxt in all gemini directories to mark conversations migrated."""
    if pbtxt_path:
        pbtxt_paths = [pbtxt_path]
    else:
        pbtxt_paths = [
            os.path.join(PATH_GEMINI_MAIN, "antigravity_state.pbtxt"),
            os.path.join(PATH_GEMINI_IDE, "antigravity_state.pbtxt")
        ]
    for p in pbtxt_paths:
        if dry_run:
            continue
        try:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            content = ""
            if os.path.exists(p):
                with open(p, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
            if "migrate_convos_into_projects:" in content:
                content = content.replace("migrate_convos_into_projects: MIGRATION_STATUS_UNSPECIFIED",
                                          f"migrate_convos_into_projects: {status}")
            else:
                content += f"\nmigrate_convos_into_projects: {status}\n"
            with open(p, "w", encoding="utf-8") as f:
                f.write(content.strip() + "\n")
            log(f"Configured conversation state in {p}", "SUCCESS")
        except Exception as e:
            log(f"Failed configuring pbtxt state {p}: {e}", "WARN")

def create_backup_archive(output_tar: str = None) -> str:
    """Creates a comprehensive backup archive of all Antigravity brains, chats, and configurations."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    if not output_tar:
        backup_dir = os.path.join(HOME, ".antigravity_backups")
        os.makedirs(backup_dir, exist_ok=True)
        output_tar = os.path.join(backup_dir, f"antigravity-backup-{timestamp}.tar.gz")
    else:
        output_tar = os.path.abspath(output_tar)
        os.makedirs(os.path.dirname(output_tar), exist_ok=True)
        
    log(f"Creating full backup archive at: {output_tar}", "STEP")
    
    manifest = {
        "created_at": datetime.now().isoformat(),
        "hostname": os.uname().nodename,
        "items": []
    }
    
    items_to_backup = [
        ("gemini_main", PATH_GEMINI_MAIN),
        ("gemini_ide", PATH_GEMINI_IDE),
        ("config_legacy", PATH_CONFIG_LEGACY),
        ("config_ide", PATH_CONFIG_IDE),
        ("dot_legacy", PATH_DOT_LEGACY),
        ("dot_ide", PATH_DOT_IDE)
    ]
    
    with tarfile.open(output_tar, "w:gz") as tar:
        for tag, path in items_to_backup:
            if os.path.exists(path):
                log(f"Archiving [{tag}]: {path}")
                def tar_filter(tarinfo):
                    # Skip massive cache/socket directories
                    skip_patterns = ["/cache/", "/cacheddata/", "/gpucache/", "/logs/", "lockfile", ".sock", "browser_recordings"]
                    for pat in skip_patterns:
                        if pat in tarinfo.name.lower():
                            return None
                    return tarinfo
                tar.add(path, arcname=f"data/{tag}", filter=tar_filter)
                manifest["items"].append({"tag": tag, "source": path})
                
        manifest_data = json.dumps(manifest, indent=2).encode("utf-8")
        ti = tarfile.TarInfo(name="manifest.json")
        ti.size = len(manifest_data)
        ti.mtime = int(time.time())
        from io import BytesIO
        tar.addfile(ti, BytesIO(manifest_data))
        
    size_mb = os.path.getsize(output_tar) / (1024 * 1024)
    log(f"Backup created successfully! Size: {size_mb:.2f} MB", "SUCCESS")
    return output_tar

@contextlib.contextmanager
def tempfile_extract(tar_path):
    tmpdir = tempfile.mkdtemp(prefix="agyist_restore_")
    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            tar.extractall(path=tmpdir)
        yield tmpdir
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

def restore_from_archive(input_tar: str, dry_run: bool = False):
    """Restores brains, chats, and configurations from a backup archive."""
    if not os.path.exists(input_tar):
        log(f"Archive file not found: {input_tar}", "ERROR")
        sys.exit(1)
        
    log(f"Inspecting backup archive: {input_tar}", "STEP")
    
    tag_map = {
        "gemini_main": PATH_GEMINI_MAIN,
        "gemini_ide": PATH_GEMINI_IDE,
        "config_legacy": PATH_CONFIG_LEGACY,
        "config_ide": PATH_CONFIG_IDE,
        "dot_legacy": PATH_DOT_LEGACY,
        "dot_ide": PATH_DOT_IDE
    }
    
    with tempfile_extract(input_tar) as extract_dir:
        manifest_file = os.path.join(extract_dir, "manifest.json")
        if os.path.exists(manifest_file):
            with open(manifest_file, "r") as f:
                manifest = json.load(f)
            log(f"Archive created on: {manifest.get('created_at')} from host: {manifest.get('hostname')}")
            
        data_dir = os.path.join(extract_dir, "data")
        if not os.path.exists(data_dir):
            log("Invalid archive layout: 'data/' not found", "ERROR")
            sys.exit(1)
            
        for tag in os.listdir(data_dir):
            if tag in tag_map:
                src_extracted = os.path.join(data_dir, tag)
                target_dst = tag_map[tag]
                log(f"Restoring [{tag}] to: {target_dst}")
                if "config" in tag:
                    db_extracted = os.path.join(src_extracted, "User", "globalStorage", "state.vscdb")
                    db_target = os.path.join(target_dst, "User", "globalStorage", "state.vscdb")
                    if os.path.exists(db_extracted):
                        merge_sqlite_vscdb(db_extracted, db_target, dry_run=dry_run)
                    copy_or_merge_directory(src_extracted, target_dst, dry_run=dry_run)
                else:
                    copy_or_merge_directory(src_extracted, target_dst, dry_run=dry_run)
                    
    log("Restore completed successfully!", "SUCCESS")

def sync_bidirectional(dry_run: bool = False):
    """
    Performs full two-way synchronization between Antigravity 2.0 (Desktop)
    and Antigravity IDE so that chats, brains, settings, and workspaces are
    available in both applications.
    """
    log("Starting Bi-Directional Antigravity Chat, Brain & State Synchronization...", "STEP")
    
    # 1. Gemini Brains, Conversations & Assistant States
    if not dry_run:
        os.makedirs(PATH_GEMINI_MAIN, exist_ok=True)
        os.makedirs(PATH_GEMINI_IDE, exist_ok=True)
        try:
            os.makedirs(PATH_GEMINI_MAIN, exist_ok=True)
            os.makedirs(PATH_GEMINI_IDE, exist_ok=True)
        except OSError as e:
            log(f"Warning: Could not create Gemini directories ({e}). Continuing with existing paths.", "WARN")
    
    for sub in ["brain", "conversations", "knowledge", "html_artifacts"]:
        dir_main = os.path.join(PATH_GEMINI_MAIN, sub)
        dir_ide = os.path.join(PATH_GEMINI_IDE, sub)
        c1 = copy_or_merge_directory(dir_main, dir_ide, dry_run=dry_run)
        c2 = copy_or_merge_directory(dir_ide, dir_main, dry_run=dry_run)
        if c1 > 0 or c2 > 0:
            log(f"Synchronized {sub}: {c1} files -> IDE, {c2} files -> Desktop", "SUCCESS")
            
    # Sync state.pbtxt & summaries
    for state_file in ["antigravity_state.pbtxt", "agyhub_summaries_proto.pb"]:
        f_main = os.path.join(PATH_GEMINI_MAIN, state_file)
        f_ide = os.path.join(PATH_GEMINI_IDE, state_file)
        if os.path.exists(f_main) and not os.path.exists(f_ide) and not dry_run:
            shutil.copy2(f_main, f_ide)
        elif os.path.exists(f_ide) and not os.path.exists(f_main) and not dry_run:
            shutil.copy2(f_ide, f_main)
            
    # Mark conversation migrations complete so IDE loads conversation projects
    configure_pbtxt_states("MIGRATION_STATUS_COMPLETED", dry_run=dry_run)
    
    # Sync MCP config
    shared_mcp = os.path.join(HOME, ".gemini", "config", "mcp_config.json")
    for d in [PATH_GEMINI_MAIN, PATH_GEMINI_IDE]:
        mcp_target = os.path.join(d, "mcp_config.json")
        if os.path.exists(shared_mcp) and not os.path.exists(mcp_target) and not dry_run:
            try:
                os.symlink(shared_mcp, mcp_target)
            except Exception:
                shutil.copy2(shared_mcp, mcp_target)
                
    # 2. SQLite Global Storage Databases (two-way merge with protobuf concatenation)
    db_2 = os.path.join(PATH_CONFIG_LEGACY, "User", "globalStorage", "state.vscdb")
    db_ide = os.path.join(PATH_CONFIG_IDE, "User", "globalStorage", "state.vscdb")
    
    if os.path.exists(db_2) or os.path.exists(db_ide):
        log("Synchronizing SQLite state databases (state.vscdb)...", "STEP")
        total_keys = merge_sqlite_vscdb(db_2, db_ide, dry_run=dry_run, write_both=True)
        log(f"Both Antigravity 2.0 and IDE state.vscdb now contain {total_keys} active keys", "SUCCESS")
        
    # 3. Workspace Storage
    ws_2 = os.path.join(PATH_CONFIG_LEGACY, "User", "workspaceStorage")
    ws_ide = os.path.join(PATH_CONFIG_IDE, "User", "workspaceStorage")
    if os.path.exists(ws_2) or os.path.exists(ws_ide):
        synced_ws = merge_workspace_storage(ws_2, ws_ide, dry_run=dry_run)
        if synced_ws > 0:
            log(f"Synchronized {synced_ws} workspace storage entries across both applications", "SUCCESS")
            
    # 4. Settings & Keybindings
    settings_2 = os.path.join(PATH_CONFIG_LEGACY, "User", "settings.json")
    settings_ide = os.path.join(PATH_CONFIG_IDE, "User", "settings.json")
    if os.path.exists(settings_2) and not os.path.exists(settings_ide):
        merge_json_files(settings_2, settings_ide, dry_run=dry_run)
    elif os.path.exists(settings_ide) and not os.path.exists(settings_2):
        merge_json_files(settings_ide, settings_2, dry_run=dry_run)
        
    for item in ["keybindings.json", "snippets"]:
        src_i = os.path.join(PATH_CONFIG_LEGACY, "User", item)
        dst_i = os.path.join(PATH_CONFIG_IDE, "User", item)
        if os.path.exists(src_i) and not os.path.exists(dst_i) and not dry_run:
            try:
                if os.path.isdir(src_i):
                    copy_or_merge_directory(src_i, dst_i)
                else:
                    shutil.copy2(src_i, dst_i)
            except Exception as e:
                log(f"Warning: Could not copy {src_i} to {dst_i}: {e}", "WARN")
        elif os.path.exists(dst_i) and not os.path.exists(src_i) and not dry_run:
            try:
                if os.path.isdir(dst_i):
                    copy_or_merge_directory(dst_i, src_i)
                else:
                    shutil.copy2(dst_i, src_i)
            except Exception as e:
                log(f"Warning: Could not copy {dst_i} to {src_i}: {e}", "WARN")
                
    # 5. Extensions
    if os.path.exists(PATH_DOT_LEGACY) and os.path.exists(PATH_DOT_IDE):
        migrate_extensions(PATH_DOT_LEGACY, PATH_DOT_IDE, dry_run=dry_run)
        migrate_extensions(PATH_DOT_IDE, PATH_DOT_LEGACY, dry_run=dry_run)
        
    log("Bi-directional sync completed successfully!", "SUCCESS")

def run_migration(dry_run: bool = False):
    """Legacy one-way / two-way migration wrapper."""
    sync_bidirectional(dry_run=dry_run)
    log("Migration completed successfully!", "SUCCESS")

def get_account_from_db(db_path: str):
    """Extracts active account credentials, display name, and plan from a state.vscdb SQLite file."""
    if not os.path.exists(db_path):
        return None
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='ItemTable'")
        if not cur.fetchone():
            conn.close()
            return None

        # 1. Check antigravityAuthStatus (JSON format written by Language Server)
        cur.execute("SELECT value FROM ItemTable WHERE key = 'antigravityAuthStatus'")
        row = cur.fetchone()
        if row and row[0]:
            try:
                data = json.loads(row[0])
                plan = "Free"
                raw_str = str(data).lower()
                if "ultra" in raw_str:
                    plan = "Google AI Ultra"
                elif "pro" in raw_str:
                    plan = "Google AI Pro"
                elif "standard" in raw_str:
                    plan = "Standard"
                email = data.get("email", "").strip()
                name = data.get("name", "").strip()
                has_token = bool(data.get("apiKey"))
                conn.close()
                return {
                    "email": email,
                    "name": name,
                    "plan": plan,
                    "has_token": has_token,
                    "source": "antigravityAuthStatus"
                }
            except Exception:
                pass

        # 2. Check antigravityUnifiedStateSync.oauthToken (Protobuf binary format injected by Cockpit / Language Server)
        cur.execute("SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.oauthToken'")
        row = cur.fetchone()
        if row and row[0]:
            try:
                raw_bytes = base64.b64decode(row[0])
                emails = re.findall(rb"[\w\.-]+@[\w\.-]+\.[a-zA-Z]{2,}", raw_bytes)
                if emails:
                    email = emails[0].decode(errors="ignore").strip()
                    conn.close()
                    return {
                        "email": email,
                        "name": "",
                        "plan": "Authorized",
                        "has_token": True,
                        "source": "oauthToken"
                    }
            except Exception:
                pass

        # 3. Check antigravityUnifiedStateSync.userStatus (injected by Cockpit / Language Server)
        cur.execute("SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.userStatus'")
        row = cur.fetchone()
        if row and row[0]:
            try:
                raw_bytes = base64.b64decode(row[0])
                emails = re.findall(rb"[\w\.-]+@[\w\.-]+\.[a-zA-Z]{2,}", raw_bytes)
                if emails:
                    email = emails[0].decode(errors="ignore").strip()
                    conn.close()
                    return {
                        "email": email,
                        "name": "",
                        "plan": "Authorized",
                        "has_token": True,
                        "source": "userStatus"
                    }
            except Exception:
                pass
        conn.close()
    except Exception as e:
        return {"error": str(e)}
    return None

def get_cockpit_dir() -> str:
    """Returns the base data directory for Cockpit Tools."""
    return os.environ.get("COCKPIT_TOOLS_DATA_DIR", os.path.join(HOME, ".antigravity_cockpit"))

def get_cockpit_key(create_if_missing: bool = False) -> bytes:
    """Reads or generates the 32-byte AES-256 key for Cockpit account storage."""
    cockpit_dir = get_cockpit_dir()
    key_path = os.path.join(cockpit_dir, "secure-account-storage.key")
    if os.path.exists(key_path):
        try:
            with open(key_path, "r", encoding="utf-8") as f:
                raw = f.read().strip()
            key_bytes = base64.b64decode(raw)
            if len(key_bytes) == 32:
                return key_bytes
        except Exception as e:
            log(f"Failed to read Cockpit encryption key from {key_path}: {e}", "WARN")
            
    if create_if_missing:
        os.makedirs(cockpit_dir, exist_ok=True)
        key_bytes = os.urandom(32)
        try:
            with open(key_path, "w", encoding="utf-8") as f:
                f.write(base64.b64encode(key_bytes).decode("ascii") + "\n")
            try:
                os.chmod(key_path, 0o600)
            except Exception:
                pass
            return key_bytes
        except Exception as e:
            log(f"Failed to create Cockpit encryption key: {e}", "ERROR")
    return None

def decrypt_account_file(file_path: str, key: bytes = None) -> dict:
    """Decrypts a Cockpit account JSON file (AES-256-GCM envelope or legacy plaintext)."""
    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip()
    try:
        data = json.loads(content)
    except Exception as e:
        raise ValueError(f"Invalid JSON in {file_path}: {e}")
        
    if isinstance(data, dict) and "ciphertext" in data and "nonce" in data:
        if not HAS_CRYPTOGRAPHY:
            raise RuntimeError("cryptography package is required to decrypt Cockpit accounts")
        if not key:
            key = get_cockpit_key()
            if not key:
                raise ValueError("Cockpit secure-account-storage.key not found")
        aesgcm = AESGCM(key)
        nonce = base64.b64decode(data["nonce"])
        ciphertext = base64.b64decode(data["ciphertext"])
        plaintext = aesgcm.decrypt(nonce, ciphertext, None)
        return json.loads(plaintext.decode("utf-8"))
    else:
        return data

def encrypt_account_file(file_path: str, account_data: dict, key: bytes = None, kind: str = "antigravity"):
    """Encrypts an account dictionary into an AES-256-GCM envelope matching Cockpit Tools format."""
    if not HAS_CRYPTOGRAPHY:
        raise RuntimeError("cryptography package is required to encrypt Cockpit accounts")
    if not key:
        key = get_cockpit_key(create_if_missing=True)
        if not key:
            raise ValueError("Could not obtain Cockpit encryption key")
            
    aesgcm = AESGCM(key)
    nonce = os.urandom(12)
    plaintext = json.dumps(account_data).encode("utf-8")
    ciphertext = aesgcm.encrypt(nonce, plaintext, None)
    envelope = {
        "version": 1,
        "kind": kind,
        "algorithm": "AES-256-GCM",
        "key_id": "local-secure-account-storage-v1",
        "nonce": base64.b64encode(nonce).decode("ascii"),
        "ciphertext": base64.b64encode(ciphertext).decode("ascii"),
        "encrypted_at": int(time.time())
    }
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(envelope, f, indent=2)

# Protobuf Varint & Message Encoding Utilities
def encode_varint(value: int) -> bytes:
    buf = bytearray()
    while value >= 0x80:
        buf.append((value & 0x7F) | 0x80)
        value >>= 7
    buf.append(value)
    return bytes(buf)

def encode_len_delim_field(field_num: int, data: bytes) -> bytes:
    tag = (field_num << 3) | 2
    return encode_varint(tag) + encode_varint(len(data)) + data

def encode_string_field(field_num: int, value: str) -> bytes:
    return encode_len_delim_field(field_num, value.encode("utf-8"))

def encode_varint_field(field_num: int, value: int) -> bytes:
    tag = (field_num << 3) | 0
    return encode_varint(tag) + encode_varint(value)

def read_varint(data: bytes, offset: int = 0):
    result = 0
    shift = 0
    pos = offset
    while pos < len(data):
        byte = data[pos]
        result |= (byte & 0x7F) << shift
        pos += 1
        if (byte & 0x80) == 0:
            break
        shift += 7
    return result, pos

def skip_field(data: bytes, offset: int, wire_type: int) -> int:
    if wire_type == 0:
        _, new_offset = read_varint(data, offset)
        return new_offset
    elif wire_type == 1:
        return offset + 8
    elif wire_type == 2:
        length, content_offset = read_varint(data, offset)
        return content_offset + length
    elif wire_type == 5:
        return offset + 4
    else:
        raise ValueError(f"Unknown wire type: {wire_type}")

def unified_topic_entry_key(data: bytes) -> str:
    offset = 0
    while offset < len(data):
        try:
            tag, new_offset = read_varint(data, offset)
            wire_type = tag & 7
            field_num = tag >> 3
            if field_num == 1 and wire_type == 2:
                length, content_offset = read_varint(data, new_offset)
                if content_offset + length > len(data):
                    return None
                return data[content_offset:content_offset + length].decode("utf-8", errors="ignore")
            offset = skip_field(data, new_offset, wire_type)
        except Exception:
            break
    return None

def remove_unified_topic_entry(data: bytes, target_key: str) -> bytes:
    if not data:
        return b""
    result = bytearray()
    offset = 0
    while offset < len(data):
        start_offset = offset
        try:
            tag, new_offset = read_varint(data, offset)
            wire_type = tag & 7
            field_num = tag >> 3
            next_offset = skip_field(data, new_offset, wire_type)
        except Exception:
            break

        should_remove = False
        if field_num == 1 and wire_type == 2:
            try:
                length, content_offset = read_varint(data, new_offset)
                if content_offset + length <= len(data):
                    entry = data[content_offset:content_offset + length]
                    if unified_topic_entry_key(entry) == target_key:
                        should_remove = True
            except Exception:
                pass

        if not should_remove:
            result.extend(data[start_offset:next_offset])
        offset = next_offset

    return bytes(result)

def create_oauth_info_protobuf(access_token: str, refresh_token: str, expiry: int,
                               id_token: str = None, is_gcp_tos: bool = False, email: str = None) -> bytes:
    field1 = encode_string_field(1, access_token)
    field2 = encode_string_field(2, "Bearer")
    field3 = encode_string_field(3, refresh_token)
    ts_tag = (1 << 3) | 0
    ts_msg = encode_varint(ts_tag) + encode_varint(int(expiry)) + encode_varint_field(2, 0)
    field4 = encode_len_delim_field(4, ts_msg)
    
    oauth_info = bytearray(field1 + field2 + field3 + field4)
    if id_token and id_token.strip():
        oauth_info.extend(encode_string_field(5, id_token.strip()))
    if is_gcp_tos:
        oauth_info.extend(encode_varint_field(6, 1))
    return bytes(oauth_info)

def create_unified_topic_entry(sentinel_key: str, payload: bytes) -> bytes:
    row = encode_string_field(1, base64.b64encode(payload).decode("ascii"))
    entry = encode_string_field(1, sentinel_key) + encode_len_delim_field(2, row)
    return encode_len_delim_field(1, entry)

def create_minimal_user_status_payload(email: str) -> bytes:
    return encode_string_field(3, email) + encode_string_field(7, email)

def inject_account_to_vscdb(db_path: str, account: dict) -> bool:
    """Directly injects protobuf credentials into state.vscdb ItemTable."""
    token = account.get("token") or {}
    access_token = token.get("access_token") or account.get("access_token") or ""
    refresh_token = token.get("refresh_token") or account.get("refresh_token") or ""
    expiry = token.get("expiry_timestamp") or token.get("expiry") or account.get("expiry") or int(time.time() + 3600 * 24 * 30)
    if expiry > 1e11:
        expiry = int(expiry / 1000)
    id_token = token.get("id_token") or account.get("id_token")
    is_gcp_tos = bool(token.get("is_gcp_tos", False))
    email = account.get("email", "")

    if not access_token and not refresh_token:
        log(f"Cannot inject account {email}: No tokens available in account object", "WARN")
        return False

    os.makedirs(os.path.dirname(db_path), exist_ok=True)
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT PRIMARY KEY, value BLOB)")
        
        # Read current oauthToken if present
        cur.execute("SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.oauthToken'")
        row = cur.fetchone()
        current_topic = b""
        if row and row[0]:
            try:
                current_topic = base64.b64decode(row[0])
            except Exception:
                current_topic = b""

        # Strip existing OAuth sentinel entries
        topic = remove_unified_topic_entry(current_topic, "oauthTokenInfoSentinelKey")
        topic = remove_unified_topic_entry(topic, "authStateWithContextSentinelKey")

        oauth_info = create_oauth_info_protobuf(
            access_token=access_token,
            refresh_token=refresh_token,
            expiry=expiry,
            id_token=id_token,
            is_gcp_tos=is_gcp_tos,
            email=email
        )

        topic = topic + create_unified_topic_entry("oauthTokenInfoSentinelKey", oauth_info)
        topic_b64 = base64.b64encode(topic).decode("ascii")

        cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('antigravityUnifiedStateSync.oauthToken', ?)", (topic_b64,))

        # Update antigravityAuthStatus and userStatus for UI/Language Server sync
        if email:
            tier = "Authorized"
            if isinstance(account.get("quota"), dict):
                tier = account.get("quota", {}).get("subscription_tier") or "Authorized"
            auth_status = {
                "email": email,
                "name": account.get("name", ""),
                "apiKey": access_token,
                "userTier": tier,
                "signedIn": True
            }
            cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('antigravityAuthStatus', ?)", (json.dumps(auth_status),))

            us_payload = create_minimal_user_status_payload(email)
            us_topic = create_unified_topic_entry("userStatusSentinelKey", us_payload)
            us_b64 = base64.b64encode(us_topic).decode("ascii")
            cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('antigravityUnifiedStateSync.userStatus', ?)", (us_b64,))

        cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('antigravityOnboarding', 'true')")
        conn.commit()
        conn.close()
        return True
    except Exception as e:
        log(f"Failed to inject account credentials into {db_path}: {e}", "ERROR")
        return False

def get_all_cockpit_accounts() -> list:
    """Decrypts and returns all accounts stored in Cockpit Tools with token health information."""
    cockpit_dir = get_cockpit_dir()
    accounts_dir = os.path.join(cockpit_dir, "accounts")
    index_file = os.path.join(cockpit_dir, "accounts.json")
    current_file = os.path.join(cockpit_dir, "current_account.json")
    
    current_account_id = None
    if os.path.exists(index_file):
        try:
            with open(index_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                current_account_id = data.get("current_account_id")
        except Exception:
            pass
    if not current_account_id and os.path.exists(current_file):
        try:
            with open(current_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                current_account_id = data.get("id")
        except Exception:
            pass
            
    key = get_cockpit_key()
    accounts = []
    
    if os.path.exists(accounts_dir):
        for fname in sorted(os.listdir(accounts_dir)):
            if not fname.endswith(".json") or fname.endswith(".bak"):
                continue
            fpath = os.path.join(accounts_dir, fname)
            try:
                acc = decrypt_account_file(fpath, key)
                acc_id = acc.get("id") or fname[:-5]
                acc["id"] = acc_id
                acc["is_active"] = (acc_id == current_account_id)
                
                # Token expiry health calculation
                token = acc.get("token", {})
                expiry = token.get("expiry_timestamp") or token.get("expiry") or acc.get("expiry_timestamp") or 0
                now = int(time.time())
                
                if expiry > 1e11:
                    expiry = int(expiry / 1000)
                
                acc["expiry_epoch"] = expiry
                if expiry == 0:
                    acc["health_status"] = "No Expiry Info"
                    acc["is_expired"] = False
                elif expiry < now:
                    acc["health_status"] = "EXPIRED"
                    acc["is_expired"] = True
                else:
                    diff = expiry - now
                    acc["is_expired"] = False
                    if diff < 3600:
                        acc["health_status"] = f"Expiring in {diff // 60}m"
                    elif diff < 86400:
                        acc["health_status"] = f"Valid ({diff // 3600}h left)"
                    else:
                        acc["health_status"] = f"Valid ({diff // 86400}d left)"
                
                accounts.append(acc)
            except Exception as e:
                log(f"Could not load account file {fname}: {e}", "WARN")
                
    return accounts

def is_port_open(port: int, host: str = "127.0.0.1", timeout: float = 0.2) -> bool:
    """Fast TCP check to determine if local port is active and accepting connections."""
    try:
        with socket.create_connection((host, int(port)), timeout=timeout):
            return True
    except (OSError, ConnectionRefusedError):
        return False

def send_cockpit_ws_request(port: int, req_type: str, payload: dict, timeout: float = 1.5) -> dict:
    """Sends a tagged WebSocket request to Cockpit Tools local IPC daemon."""
    if not HAS_WEBSOCKETS or not is_port_open(port):
        return None

    async def _async_req():
        uri = f"ws://127.0.0.1:{port}"
        async with websockets.connect(uri, open_timeout=0.6, close_timeout=0.4) as ws:
            # Receive initial greeting event (event.ready)
            try:
                await asyncio.wait_for(ws.recv(), timeout=0.4)
            except Exception:
                pass
            msg = {
                "type": req_type,
                "payload": payload
            }
            await ws.send(json.dumps(msg))
            resp_raw = await asyncio.wait_for(ws.recv(), timeout=timeout)
            return json.loads(resp_raw)

    try:
        return asyncio.run(_async_req())
    except Exception:
        return None

def switch_cockpit_account(target: str = None, target_app: str = "both") -> tuple:
    """
    Switches active account in Cockpit Tools, Antigravity IDE, and/or Antigravity 2.0.
    target: 1-based index, email address, or account ID. If None, user is prompted interactively.
    Returns: (success: bool, message: str, account_info: dict)
    """
    accounts = get_all_cockpit_accounts()
    if not accounts:
        return False, "No accounts found in Cockpit Tools storage (~/.antigravity_cockpit/accounts/)", None

    chosen = None
    if target is None:
        print("\n=== Available Accounts in Cockpit Tools ===")
        for i, acc in enumerate(accounts, 1):
            act_mark = " ✔ (ACTIVE)" if acc.get("is_active") else "  "
            name_str = f" - {acc.get('name')}" if acc.get("name") else ""
            status_str = f"[{acc.get('health_status', 'Unknown')}]"
            print(f"  [{i}]{act_mark} {acc.get('email')}{name_str} {status_str}")
        print("")
        try:
            choice = input(f"Select account to activate [1-{len(accounts)}] (or 'q' to cancel): ").strip()
            if not choice or choice.lower() in ("q", "quit", "cancel"):
                return False, "Account switch cancelled by user.", None
            target = choice
        except (KeyboardInterrupt, EOFError):
            return False, "\nOperation cancelled.", None

    target_str = str(target).strip()

    # Match by index
    if target_str.isdigit():
        idx = int(target_str) - 1
        if 0 <= idx < len(accounts):
            chosen = accounts[idx]

    # Match by ID
    if not chosen:
        for acc in accounts:
            if acc.get("id") == target_str:
                chosen = acc
                break

    # Match by exact email
    if not chosen:
        for acc in accounts:
            if acc.get("email", "").lower() == target_str.lower():
                chosen = acc
                break

    # Match by substring in email or name
    if not chosen:
        candidates = []
        for acc in accounts:
            if (target_str.lower() in acc.get("email", "").lower()) or \
               (acc.get("name") and target_str.lower() in acc.get("name", "").lower()):
                candidates.append(acc)
        if len(candidates) == 1:
            chosen = candidates[0]
        elif len(candidates) > 1:
            opts = ", ".join([f"{a.get('email')} [{i+1}]" for i, a in enumerate(candidates)])
            return False, f"Multiple accounts match '{target}': {opts}. Please specify index or full email.", None

    if not chosen:
        avail = "\n".join([f"  [{i+1}] {a.get('email')} ({a.get('name', 'N/A')})" for i, a in enumerate(accounts)])
        return False, f"Account '{target}' not found. Available accounts:\n{avail}", None

    cockpit_dir = get_cockpit_dir()
    server_json = os.path.join(cockpit_dir, "server.json")
    online_ipc = False
    ws_log = ""

    # Attempt online switch via WebSocket if Cockpit is running
    if os.path.exists(server_json):
        try:
            with open(server_json, "r", encoding="utf-8") as f:
                srv = json.load(f)
            pid = srv.get("pid")
            ws_port = srv.get("ws_port")
            is_alive = False
            if pid:
                try:
                    os.kill(pid, 0)
                    is_alive = True
                except OSError:
                    is_alive = False
            if is_alive and ws_port:
                req_id = f"agyist-switch-{int(time.time()*1000)}"
                resp = send_cockpit_ws_request(ws_port, "request.switch_account", {
                    "account_id": chosen["id"],
                    "request_id": req_id
                })
                if resp:
                    online_ipc = True
                    ws_log = f"Cockpit IPC WebSocket broadcast successful (PID {pid}, port {ws_port})"
        except Exception as e:
            ws_log = f"Cockpit IPC attempted but not used: {e}"

    # Perform direct SQLite injection into state.vscdb
    ide_db = os.path.join(PATH_CONFIG_IDE, "User", "globalStorage", "state.vscdb")
    desktop_db = os.path.join(PATH_CONFIG_LEGACY, "User", "globalStorage", "state.vscdb")

    injected = []
    if target_app in ("ide", "both"):
        if os.path.exists(ide_db) or not online_ipc:
            if inject_account_to_vscdb(ide_db, chosen):
                injected.append("Antigravity IDE")

    if target_app in ("desktop", "both"):
        if os.path.exists(desktop_db) or not online_ipc:
            if inject_account_to_vscdb(desktop_db, chosen):
                injected.append("Antigravity 2.0")

    # Update Cockpit's current_account.json and accounts.json
    curr_file = os.path.join(cockpit_dir, "current_account.json")
    try:
        with open(curr_file, "w", encoding="utf-8") as f:
            json.dump({
                "email": chosen.get("email"),
                "id": chosen.get("id"),
                "updated_at": int(time.time())
            }, f, indent=2)
    except Exception:
        pass

    idx_file = os.path.join(cockpit_dir, "accounts.json")
    try:
        if os.path.exists(idx_file):
            with open(idx_file, "r", encoding="utf-8") as f:
                idx_data = json.load(f)
            idx_data["current_account_id"] = chosen.get("id")
            for acc in idx_data.get("accounts", []):
                if acc.get("id") == chosen.get("id"):
                    acc["last_used"] = int(time.time())
            with open(idx_file, "w", encoding="utf-8") as f:
                json.dump(idx_data, f, indent=2)
    except Exception:
        pass

    mode_str = "Online Cockpit IPC + SQLite Sync" if online_ipc else "Direct SQLite Credential Injection"
    apps_str = ", ".join(injected) if injected else "Cockpit state files"
    msg = f"Successfully activated {chosen.get('email')} ({mode_str} into {apps_str})"
    return True, msg, chosen

def get_cockpit_instances_dir() -> str:
    """Returns directory path for multi-instance isolated profiles."""
    return os.path.join(get_cockpit_dir(), "instances", "antigravity")

def list_cockpit_instances() -> list:
    """Lists configured Cockpit multi-instance profiles."""
    instances_file = os.path.join(get_cockpit_dir(), "instances.json")
    instances = []
    if os.path.exists(instances_file):
        try:
            with open(instances_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            instances = data.get("instances", [])
        except Exception:
            pass

    # Build account ID -> email map from accounts list
    acc_map = {}
    for a in get_all_cockpit_accounts():
        if a.get("id"):
            acc_map[a["id"]] = a.get("email")

    # Enrich with disk existence check
    for inst in instances:
        udd = inst.get("userDataDir", "")
        inst["exists_on_disk"] = os.path.exists(udd) if udd else False
        db = os.path.join(udd, "User", "globalStorage", "state.vscdb")
        inst["has_state_db"] = os.path.exists(db)
        bound_id = inst.get("bindAccountId")
        if inst["has_state_db"]:
            acc_info = get_account_from_db(db)
            inst["active_email"] = (acc_info.get("email") if acc_info else None) or acc_map.get(bound_id)
        else:
            inst["active_email"] = acc_map.get(bound_id)

    return instances

def setup_instance_profile(name: str, bind_account: str = None, working_dir: str = None) -> dict:
    """
    Creates or configures an isolated multi-instance Antigravity profile.
    bind_account can be an index, email, or account ID.
    """
    name = re.sub(r"[^\w\-.]", "_", name.strip())
    if not name:
        raise ValueError("Instance profile name cannot be empty")

    inst_dir = os.path.join(get_cockpit_instances_dir(), name)
    storage_dir = os.path.join(inst_dir, "User", "globalStorage")
    os.makedirs(storage_dir, exist_ok=True)
    db_path = os.path.join(storage_dir, "state.vscdb")

    bound_acc_info = None
    bind_id = None
    if bind_account:
        accounts = get_all_cockpit_accounts()
        for i, acc in enumerate(accounts, 1):
            if str(i) == str(bind_account) or acc.get("id") == bind_account or acc.get("email", "").lower() == bind_account.lower():
                bound_acc_info = acc
                bind_id = acc.get("id")
                break
        if bound_acc_info:
            inject_account_to_vscdb(db_path, bound_acc_info)
            log(f"Bound account {bound_acc_info.get('email')} to instance profile '{name}'", "SUCCESS")
        else:
            log(f"Warning: Account '{bind_account}' not found; created blank instance profile.", "WARN")

    # Update instances.json
    inst_file = os.path.join(get_cockpit_dir(), "instances.json")
    store = {"instances": [], "defaultSettings": {"bindAccountId": None}}
    if os.path.exists(inst_file):
        try:
            with open(inst_file, "r", encoding="utf-8") as f:
                store = json.load(f)
        except Exception:
            pass

    instances = store.get("instances", [])
    found = False
    for inst in instances:
        if inst.get("name") == name or inst.get("userDataDir") == inst_dir:
            inst["userDataDir"] = inst_dir
            if bind_id:
                inst["bindAccountId"] = bind_id
            if working_dir:
                inst["workingDir"] = working_dir
            inst["lastLaunchedAt"] = int(time.time() * 1000)
            found = True
            break

    if not found:
        new_inst = {
            "id": str(uuid.uuid4()),
            "name": name,
            "userDataDir": inst_dir,
            "workingDir": working_dir,
            "extraArgs": "",
            "bindAccountId": bind_id,
            "launchMode": "app",
            "createdAt": int(time.time() * 1000),
            "lastLaunchedAt": int(time.time() * 1000)
        }
        instances.append(new_inst)

    store["instances"] = instances
    with open(inst_file, "w", encoding="utf-8") as f:
        json.dump(store, f, indent=2)

    return {
        "name": name,
        "user_data_dir": inst_dir,
        "state_db": db_path,
        "bind_account": bound_acc_info.get("email") if bound_acc_info else None
    }

def repair_cockpit_tools() -> dict:
    """Scans and auto-repairs common Cockpit Tools lockups, stale states, and launch paths."""
    cockpit_dir = get_cockpit_dir()
    repairs = []
    warnings = []

    # 1. Clean stale config.json.lock
    lock_file = os.path.join(cockpit_dir, "config.json.lock")
    if os.path.exists(lock_file):
        try:
            os.remove(lock_file)
            repairs.append("Removed stale config.json.lock file")
        except Exception as e:
            warnings.append(f"Failed to remove config.json.lock: {e}")

    # 2. Clean stale token locks
    token_locks_dir = os.path.join(cockpit_dir, ".cockpit-token-locks")
    if os.path.exists(token_locks_dir):
        now = time.time()
        for f in os.listdir(token_locks_dir):
            fp = os.path.join(token_locks_dir, f)
            try:
                if now - os.path.getmtime(fp) > 10:
                    os.remove(fp)
                    repairs.append(f"Cleaned stale token lock: {f}")
            except Exception:
                pass

    # 3. Check dead PID in server.json
    server_file = os.path.join(cockpit_dir, "server.json")
    if os.path.exists(server_file):
        try:
            with open(server_file, "r", encoding="utf-8") as f:
                srv = json.load(f)
            pid = srv.get("pid")
            is_alive = False
            if pid:
                try:
                    os.kill(pid, 0)
                    is_alive = True
                except OSError:
                    is_alive = False
            if not is_alive:
                os.remove(server_file)
                repairs.append(f"Removed orphaned server.json referencing dead PID {pid}")
        except Exception as e:
            warnings.append(f"Could not inspect server.json: {e}")

    # 4. Verify antigravity_app_path in config.json
    config_file = os.path.join(cockpit_dir, "config.json")
    if os.path.exists(config_file):
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            app_path = cfg.get("antigravity_app_path", "").strip()
            
            # Check if current configured path is obsolete
            repaired_path = None
            if not app_path or not os.path.exists(app_path) or "/usr/share/antigravity" in app_path:
                for cand in [
                    os.path.join(HOME, ".local/share/antigravity-ide/antigravity-ide"),
                    os.path.join(HOME, ".local/share/antigravity-ide/bin/antigravity-ide"),
                    os.path.join(HOME, ".local/bin/antigravity-ide"),
                    os.path.join(HOME, ".local/share/antigravity/antigravity"),
                    os.path.join(HOME, ".local/bin/antigravity"),
                ]:
                    if os.path.isfile(cand) and os.access(cand, os.X_OK):
                        repaired_path = cand
                        break
                        
            if repaired_path and repaired_path != app_path:
                cfg["antigravity_app_path"] = repaired_path
                with open(config_file, "w", encoding="utf-8") as f:
                    json.dump(cfg, f, indent=2)
                repairs.append(f"Updated antigravity_app_path in config.json to modern build: {repaired_path}")
        except Exception as e:
            warnings.append(f"Could not inspect config.json: {e}")

    # 5. Check directory signatures
    ide_root = os.path.join(HOME, ".local/share/antigravity-ide")
    if os.path.exists(ide_root):
        bin_dir = os.path.join(ide_root, "bin")
        os.makedirs(bin_dir, exist_ok=True)
        sig = os.path.join(bin_dir, "antigravity-ide")
        exec_file = os.path.join(ide_root, "antigravity-ide")
        if not os.path.exists(sig) and os.path.isfile(exec_file):
            try:
                os.symlink(exec_file, sig)
                repairs.append(f"Restored directory signature {sig}")
            except Exception:
                pass

    return {
        "success": True,
        "repairs_count": len(repairs),
        "repairs": repairs,
        "warnings": warnings
    }

def export_cockpit_accounts(output_path: str = None, password: str = None) -> str:
    """Exports all Cockpit accounts into a password-encrypted PBKDF2 + AES-256-GCM archive."""
    if not HAS_CRYPTOGRAPHY:
        raise RuntimeError("cryptography package is required to export accounts")

    accounts = get_all_cockpit_accounts()
    if not accounts:
        raise ValueError("No accounts available in Cockpit Tools to export")

    if not password:
        password = os.environ.get("AGY_EXPORT_PASSWORD")
    if not password:
        try:
            p1 = getpass.getpass("Enter passphrase to encrypt account export: ")
            p2 = getpass.getpass("Confirm passphrase: ")
            if p1 != p2:
                raise ValueError("Passphrases do not match")
            password = p1
        except (KeyboardInterrupt, EOFError):
            raise ValueError("Operation cancelled")

    if not password:
        raise ValueError("Passphrase cannot be empty")

    salt = os.urandom(16)
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=100000
    )
    derived_key = kdf.derive(password.encode("utf-8"))
    nonce = os.urandom(12)
    aesgcm = AESGCM(derived_key)

    bundle = {
        "format": "agyist-encrypted-accounts-v1",
        "exported_at": int(time.time()),
        "host": socket.gethostname(),
        "account_count": len(accounts),
        "accounts": accounts
    }

    ciphertext = aesgcm.encrypt(nonce, json.dumps(bundle).encode("utf-8"), None)
    archive = {
        "header": "AGYIST_ENCRYPTED_ACCOUNTS",
        "version": 1,
        "kdf": "PBKDF2-HMAC-SHA256",
        "iterations": 100000,
        "salt": base64.b64encode(salt).decode("ascii"),
        "nonce": base64.b64encode(nonce).decode("ascii"),
        "ciphertext": base64.b64encode(ciphertext).decode("ascii")
    }

    if not output_path:
        date_str = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_path = os.path.join(HOME, f"antigravity_accounts_export_{date_str}.agyacc")

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(archive, f, indent=2)

    try:
        os.chmod(output_path, 0o600)
    except Exception:
        pass

    return output_path

def import_cockpit_accounts(input_path: str, password: str = None) -> int:
    """Decrypts and imports accounts from an encrypted .agyacc archive into local Cockpit storage."""
    if not HAS_CRYPTOGRAPHY:
        raise RuntimeError("cryptography package is required to import accounts")

    if not os.path.exists(input_path):
        raise FileNotFoundError(f"Export file not found: {input_path}")

    with open(input_path, "r", encoding="utf-8") as f:
        archive = json.load(f)

    if archive.get("header") != "AGYIST_ENCRYPTED_ACCOUNTS":
        raise ValueError("Invalid archive format: missing AGYIST_ENCRYPTED_ACCOUNTS header")

    salt = base64.b64decode(archive["salt"])
    nonce = base64.b64decode(archive["nonce"])
    ciphertext = base64.b64decode(archive["ciphertext"])
    iterations = int(archive.get("iterations", 100000))

    if not password:
        password = os.environ.get("AGY_EXPORT_PASSWORD")
    if not password:
        try:
            password = getpass.getpass("Enter passphrase to decrypt account archive: ")
        except (KeyboardInterrupt, EOFError):
            raise ValueError("Operation cancelled")

    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=iterations
    )
    derived_key = kdf.derive(password.encode("utf-8"))
    aesgcm = AESGCM(derived_key)

    try:
        plaintext = aesgcm.decrypt(nonce, ciphertext, None)
    except Exception:
        raise ValueError("Decryption failed: Incorrect passphrase or corrupted archive")

    bundle = json.loads(plaintext.decode("utf-8"))
    accounts_to_import = bundle.get("accounts", [])

    cockpit_dir = get_cockpit_dir()
    accounts_dir = os.path.join(cockpit_dir, "accounts")
    os.makedirs(accounts_dir, exist_ok=True)
    local_key = get_cockpit_key(create_if_missing=True)

    idx_file = os.path.join(cockpit_dir, "accounts.json")
    idx_data = {"version": "2.0", "accounts": [], "current_account_id": None}
    if os.path.exists(idx_file):
        try:
            with open(idx_file, "r", encoding="utf-8") as f:
                idx_data = json.load(f)
        except Exception:
            pass

    existing_ids = {a.get("id") for a in idx_data.get("accounts", [])}
    imported_count = 0

    for acc in accounts_to_import:
        acc_id = acc.get("id") or str(uuid.uuid4())
        acc["id"] = acc_id
        target_file = os.path.join(accounts_dir, f"{acc_id}.json")
        encrypt_account_file(target_file, acc, local_key)
        
        if acc_id not in existing_ids:
            idx_data.setdefault("accounts", []).append({
                "id": acc_id,
                "email": acc.get("email", ""),
                "name": acc.get("name", ""),
                "created_at": int(time.time()),
                "last_used": int(time.time())
            })
            existing_ids.add(acc_id)
        imported_count += 1

    if not idx_data.get("current_account_id") and idx_data.get("accounts"):
        idx_data["current_account_id"] = idx_data["accounts"][0]["id"]

    with open(idx_file, "w", encoding="utf-8") as f:
        json.dump(idx_data, f, indent=2)

    return imported_count

def get_cockpit_active_account():
    """Reads active account configured in Cockpit Tools."""
    cockpit_dir = get_cockpit_dir()
    curr_file = os.path.join(cockpit_dir, "current_account.json")
    if os.path.exists(curr_file):
        try:
            with open(curr_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                email = data.get("email", "").strip()
                if email:
                    return {
                        "email": email,
                        "updated_at": data.get("updated_at"),
                        "source": "current_account.json"
                    }
        except Exception:
            pass

    idx_file = os.path.join(cockpit_dir, "accounts.json")
    if os.path.exists(idx_file):
        try:
            with open(idx_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                curr_id = data.get("current_account_id")
                accounts = data.get("accounts", [])
                for acc in accounts:
                    if acc.get("id") == curr_id:
                        return {
                            "email": acc.get("email", "").strip(),
                            "id": curr_id,
                            "source": "accounts.json"
                        }
        except Exception:
            pass
    return None

def get_account_status():
    """Returns active account info for Cockpit Tools, Antigravity IDE, and Antigravity 2.0 Desktop."""
    ide_db = os.path.join(PATH_CONFIG_IDE, "User", "globalStorage", "state.vscdb")
    desktop_db = os.path.join(PATH_CONFIG_LEGACY, "User", "globalStorage", "state.vscdb")

    ide_acc = get_account_from_db(ide_db)
    desktop_acc = get_account_from_db(desktop_db)
    cockpit_acc = get_cockpit_active_account()

    unique_emails = set()
    for acc in [ide_acc, desktop_acc, cockpit_acc]:
        if acc and acc.get("email"):
            unique_emails.add(acc["email"].lower())

    in_sync = True
    if len(unique_emails) > 1:
        in_sync = False

    return {
        "cockpit": cockpit_acc,
        "ide": ide_acc,
        "desktop": desktop_acc,
        "in_sync": in_sync,
        "unique_emails": list(unique_emails)
    }

def get_status_dict():
    """Returns a structured dictionary of Antigravity data status and synchronization state."""
    status = {
        "timestamp": datetime.now().isoformat(),
        "components": {},
        "databases": {},
        "sync_status": "unknown"
    }
    
    paths = [
        ("gemini_main", PATH_GEMINI_MAIN),
        ("gemini_ide", PATH_GEMINI_IDE),
        ("config_2", PATH_CONFIG_LEGACY),
        ("config_ide", PATH_CONFIG_IDE),
        ("extensions_2", PATH_DOT_LEGACY),
        ("extensions_ide", PATH_DOT_IDE),
    ]
    
    for tag, p in paths:
        if os.path.exists(p):
            total_size = 0
            file_count = 0
            for root, dirs, files in os.walk(p):
                for f in files:
                    fp = os.path.join(root, f)
                    if not os.path.islink(fp):
                        total_size += os.path.getsize(fp)
                        file_count += 1
            status["components"][tag] = {
                "path": p,
                "exists": True,
                "files": file_count,
                "size_mb": round(total_size / (1024 * 1024), 2)
            }
        else:
            status["components"][tag] = {
                "path": p,
                "exists": False,
                "files": 0,
                "size_mb": 0.0
            }
            
    # Check databases
    db_paths = [
        ("desktop_2", os.path.join(PATH_CONFIG_LEGACY, "User", "globalStorage", "state.vscdb")),
        ("ide", os.path.join(PATH_CONFIG_IDE, "User", "globalStorage", "state.vscdb"))
    ]
    
    db_keys = {}
    for name, p in db_paths:
        if os.path.exists(p):
            try:
                conn = sqlite3.connect(p)
                cur = conn.cursor()
                cur.execute("SELECT count(*) FROM ItemTable")
                count = cur.fetchone()[0]
                cur.execute("SELECT count(*) FROM ItemTable WHERE key LIKE 'antigravity.notification.%'")
                chats = cur.fetchone()[0]
                conn.close()
                status["databases"][name] = {
                    "exists": True,
                    "total_keys": count,
                    "chat_notifications": chats
                }
                db_keys[name] = count
            except Exception:
                status["databases"][name] = {"exists": False, "total_keys": 0, "chat_notifications": 0}
        else:
            status["databases"][name] = {"exists": False, "total_keys": 0, "chat_notifications": 0}
            
    if len(db_keys) == 2 and db_keys["desktop_2"] == db_keys["ide"] and db_keys["desktop_2"] > 0:
        status["sync_status"] = "synced"
    elif len(db_keys) == 2:
        status["sync_status"] = "asymmetric"
    else:
        status["sync_status"] = "standalone"
        
    status["accounts"] = get_account_status()
    return status

def main():
    parser = argparse.ArgumentParser(description="Antigravity Chat, Memory & State Migration Tool")
    parser.add_argument("--backup", nargs="?", const="", help="Create a backup archive (optional output path)")
    parser.add_argument("--import", dest="import_file", help="Import / restore from a backup archive")
    parser.add_argument("--migrate", action="store_true", help="Migrate legacy Antigravity to Antigravity IDE")
    parser.add_argument("--sync", action="store_true", help="Bi-directionally synchronize chats, brains and state between 2.0 and IDE")
    parser.add_argument("--dry-run", action="store_true", help="Simulate actions without modifying files")
    parser.add_argument("--status", action="store_true", help="Inspect brains, chats, and config sizes")
    parser.add_argument("--account", "--verify-account", dest="account", action="store_true", help="Inspect active accounts across Cockpit Tools, IDE, and 2.0")
    parser.add_argument("--accounts", "--list-accounts", dest="list_accounts", action="store_true", help="List all saved accounts in Cockpit Tools with token health status")
    parser.add_argument("--switch", nargs="?", const="", help="Switch active account by index, email, or ID (prompts if omitted)")
    parser.add_argument("--switch-app", choices=["ide", "desktop", "both"], default="both", help="Target application for account switch (default: both)")
    parser.add_argument("--instances", "--list-instances", dest="list_instances", action="store_true", help="List configured Cockpit multi-instance profiles")
    parser.add_argument("--create-instance", dest="create_instance", help="Create or configure a multi-instance profile by name")
    parser.add_argument("--bind-account", dest="bind_account", help="Account index, email, or ID to bind to instance profile")
    parser.add_argument("--working-dir", dest="working_dir", help="Working directory path for instance profile")
    parser.add_argument("--repair-cockpit", action="store_true", help="Scan and auto-repair Cockpit Tools stale lockups, dead PIDs, and paths")
    parser.add_argument("--export-accounts", nargs="?", const="", help="Export Cockpit accounts to encrypted .agyacc file")
    parser.add_argument("--import-accounts", dest="import_accounts", help="Import Cockpit accounts from encrypted .agyacc file")
    parser.add_argument("--password", dest="password", help="Passphrase for encrypted account archive export/import")
    parser.add_argument("--json", action="store_true", help="Output status as JSON")
    
    args = parser.parse_args()

    if args.list_accounts:
        accounts = get_all_cockpit_accounts()
        if args.json:
            # Mask sensitive tokens before outputting JSON
            safe_accounts = []
            for acc in accounts:
                safe_acc = acc.copy()
                if "token" in safe_acc and isinstance(safe_acc["token"], dict):
                    tok = safe_acc["token"].copy()
                    if tok.get("access_token"):
                        tok["access_token"] = tok["access_token"][:12] + "..."
                    if tok.get("refresh_token"):
                        tok["refresh_token"] = tok["refresh_token"][:8] + "..."
                    safe_acc["token"] = tok
                safe_accounts.append(safe_acc)
            print(json.dumps(safe_accounts, indent=2))
            sys.exit(0)

        print("\n=== Saved Cockpit Tools Accounts & Token Health ===")
        if not accounts:
            print("  No accounts found in ~/.antigravity_cockpit/accounts/ (add accounts via Cockpit Tools GUI)")
            print("")
            sys.exit(0)

        for i, acc in enumerate(accounts, 1):
            act_badge = " ✔ ACTIVE " if acc.get("is_active") else "          "
            health_color = "\033[0;32m" if not acc.get("is_expired") and "Valid" in acc.get("health_status", "") else "\033[0;33m"
            if acc.get("is_expired"):
                health_color = "\033[0;31m"
            reset_c = "\033[0m"

            name_part = f" - {acc.get('name')}" if acc.get('name') else ""
            email_part = f"{acc.get('email')}{name_part}"
            status_part = f"{health_color}[{acc.get('health_status')}]{reset_c}"
            print(f"  [{i}]{act_badge} {email_part:<42} {status_part}")
        print("\nUse './agyist --switch <number|email>' to switch active account.\n")
        sys.exit(0)

    if args.switch is not None:
        target = args.switch if args.switch != "" else None
        success, msg, acc = switch_cockpit_account(target, target_app=args.switch_app)
        if success:
            log(msg, "SUCCESS")
            sys.exit(0)
        else:
            log(msg, "ERROR")
            sys.exit(1)

    if args.list_instances:
        instances = list_cockpit_instances()
        if args.json:
            print(json.dumps(instances, indent=2))
            sys.exit(0)

        print("\n=== Cockpit Isolated Multi-Instance Profiles ===")
        if not instances:
            print("  No multi-instance profiles configured yet.")
            print("  Create a new isolated profile with: ./agyist --instance <profile_name> [path]\n")
            sys.exit(0)

        for i, inst in enumerate(instances, 1):
            name = inst.get("name")
            udd = inst.get("userDataDir")
            acc_id = inst.get("bindAccountId")
            email = inst.get("active_email") or "(Default/Unbound)"
            print(f"  [{i}] Profile: \033[1;36m{name}\033[0m")
            print(f"      Data Dir:      {udd}")
            print(f"      Bound Account: {email} (ID: {acc_id or 'none'})")
            print("")
        sys.exit(0)

    if args.create_instance:
        try:
            res = setup_instance_profile(args.create_instance, bind_account=args.bind_account, working_dir=args.working_dir)
            if args.json:
                print(json.dumps(res, indent=2))
            else:
                log(f"Successfully configured instance profile '{res['name']}'!", "SUCCESS")
                log(f"User Data Directory: {res['user_data_dir']}", "INFO")
                if res.get("bind_account"):
                    log(f"Bound Account:       {res['bind_account']}", "INFO")
                print(f"\nLaunch this profile at any time with:")
                print(f"  antigravity-ide --user-data-dir \"{res['user_data_dir']}\"\n")
            sys.exit(0)
        except Exception as e:
            log(f"Failed to create instance profile: {e}", "ERROR")
            sys.exit(1)

    if args.repair_cockpit:
        res = repair_cockpit_tools()
        if args.json:
            print(json.dumps(res, indent=2))
            sys.exit(0)

        print("\n=== Cockpit Tools Health Doctor & Auto-Repair ===")
        if res.get("repairs"):
            for rep in res["repairs"]:
                log(rep, "SUCCESS")
        else:
            log("No locks or misconfigurations detected. Cockpit configuration is healthy!", "SUCCESS")

        if res.get("warnings"):
            for warn in res["warnings"]:
                log(warn, "WARN")
        print("")
        sys.exit(0)

    if args.export_accounts is not None:
        try:
            target_path = args.export_accounts if args.export_accounts != "" else None
            out_file = export_cockpit_accounts(target_path, password=args.password)
            log(f"Accounts securely exported to: {out_file}", "SUCCESS")
            log(f"Permissions set to 0600 (owner read/write only). Keep your passphrase safe!", "INFO")
            sys.exit(0)
        except Exception as e:
            log(f"Export failed: {e}", "ERROR")
            sys.exit(1)

    if args.import_accounts:
        try:
            count = import_cockpit_accounts(args.import_accounts, password=args.password)
            log(f"Successfully imported and re-encrypted {count} account(s) into Cockpit Tools!", "SUCCESS")
            sys.exit(0)
        except Exception as e:
            log(f"Import failed: {e}", "ERROR")
            sys.exit(1)
    
    if args.account:
        acc_data = get_account_status()
        if args.json:
            print(json.dumps(acc_data, indent=2))
            sys.exit(0)
            
        print("\n=== Antigravity & Cockpit Tools Active Accounts ===")
        cockpit = acc_data.get("cockpit")
        if cockpit:
            print(f"  ✔ Cockpit Tools:     {cockpit.get('email')} (Active in {cockpit.get('source')})")
        else:
            print("  - Cockpit Tools:     No active account configured (add accounts in Cockpit Tools GUI)")
            
        ide = acc_data.get("ide")
        if ide:
            user_str = f"{ide.get('name')} <{ide.get('email')}>" if ide.get("name") else ide.get("email")
            plan_str = f" [{ide.get('plan')}]" if ide.get("plan") else ""
            print(f"  ✔ Antigravity IDE:   {user_str}{plan_str}")
        else:
            print("  - Antigravity IDE:   No active account or state.vscdb not found")
            
        desktop = acc_data.get("desktop")
        if desktop:
            user_str = f"{desktop.get('name')} <{desktop.get('email')}>" if desktop.get("name") else desktop.get("email")
            plan_str = f" [{desktop.get('plan')}]" if desktop.get("plan") else ""
            print(f"  ✔ Antigravity 2.0:   {user_str}{plan_str}")
        else:
            print("  - Antigravity 2.0:   No active account or state.vscdb not found")
            
        print("")
        if acc_data["in_sync"]:
            if acc_data["unique_emails"]:
                print(f"Status: IN SYNC (Active: {', '.join(acc_data['unique_emails'])})\n")
            else:
                print("Status: IN SYNC (No active accounts detected)\n")
        else:
            print("⚠ Status: DESYNCHRONIZED! Different accounts detected across applications.")
            print("  Run './agyist --sync' to propagate current IDE/Cockpit credentials to both apps.\n")
        sys.exit(0)

    if args.status:
        status_data = get_status_dict()
        if args.json:
            print(json.dumps(status_data, indent=2))
            sys.exit(0)
            
        print("\n=== Antigravity Data & Chat Sync Status ===")
        for name, info in status_data["components"].items():
            if info["exists"]:
                print(f"  ✔ {name}: {info['path']} ({info['files']} files, {info['size_mb']} MB)")
            else:
                print(f"  - {name}: not found")
        print("\n=== Database Keys & Chats ===")
        for name, db in status_data["databases"].items():
            if db["exists"]:
                print(f"  ✔ {name}: {db['total_keys']} total keys, {db['chat_notifications']} conversation threads")
            else:
                print(f"  - {name}: no database")
        print(f"Sync Status: {status_data['sync_status'].upper()}")

        acc_data = status_data.get("accounts", {})
        if acc_data.get("unique_emails"):
            print(f"Active Account: {', '.join(acc_data['unique_emails'])} ({'IN SYNC' if acc_data.get('in_sync') else 'OUT OF SYNC'})\n")
        else:
            print("")
        sys.exit(0)
        
    if args.backup is not None:
        create_backup_archive(args.backup if args.backup != "" else None)
    elif args.import_file:
        restore_from_archive(args.import_file, dry_run=args.dry_run)
    elif args.sync:
        sync_bidirectional(dry_run=args.dry_run)
    elif args.migrate:
        run_migration(dry_run=args.dry_run)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
