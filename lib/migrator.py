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
from datetime import datetime
from pathlib import Path

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
        conn.close()
    except Exception as e:
        return {"error": str(e)}
    return None

def get_cockpit_active_account():
    """Reads active account configured in Cockpit Tools."""
    cockpit_dir = os.environ.get("COCKPIT_TOOLS_DATA_DIR", os.path.expanduser("~/.antigravity_cockpit"))
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
    parser.add_argument("--json", action="store_true", help="Output status as JSON")
    
    args = parser.parse_args()
    
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
