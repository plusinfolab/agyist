#!/usr/bin/env python3
"""
lib/migrator.py - Antigravity Brain, Chat, Memory & State Migration/Import Suite
Handles backup, restore, import, and cross-version migration for:
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

def merge_sqlite_vscdb(src_db: str, dst_db: str, dry_run: bool = False) -> int:
    """
    Merges two state.vscdb SQLite databases.
    Special protobuf keys (trajectory summaries & sidebar workspaces) are merged
    via binary concatenation of their base64-decoded protobuf payloads.
    """
    if not os.path.exists(src_db):
        return 0
        
    # Read source keys
    src_data = {}
    try:
        conn = sqlite3.connect(src_db)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='ItemTable'")
        if not cursor.fetchone():
            conn.close()
            return 0
        cursor.execute("SELECT key, value FROM ItemTable")
        for row in cursor.fetchall():
            src_data[row[0]] = row[1]
        conn.close()
    except Exception as e:
        log(f"Error reading source database {src_db}: {e}", "ERROR")
        return 0
        
    # Read destination keys if exists
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
    keys_inserted = 0
    
    for key in dst_data:
        if key in PROTOBUF_KEYS_TO_CONCAT and key in src_data:
            # Concatenate protobuf payloads
            try:
                src_bytes = base64.b64decode(src_data[key])
                dst_bytes = base64.b64decode(dst_data[key])
                if src_bytes and dst_bytes:
                    merged_bytes = src_bytes + dst_bytes
                    merged_val = base64.b64encode(merged_bytes).decode("utf-8")
                    merged_data[key] = merged_val
                    keys_updated += 1
                    log(f"Concatenated protobuf message for key '{key}' ({len(src_bytes)}B src + {len(dst_bytes)}B dst)")
                else:
                    merged_data[key] = dst_data[key]
            except Exception as e:
                log(f"Failed to concat protobuf key '{key}': {e}. Using target value.", "WARN")
                merged_data[key] = dst_data[key]
        else:
            # Target takes precedence
            merged_data[key] = dst_data[key]
            
    if not dry_run:
        os.makedirs(os.path.dirname(dst_db), exist_ok=True)
        if os.path.exists(dst_db):
            shutil.copy2(dst_db, dst_db + ".backup")
            
        conn = sqlite3.connect(dst_db)
        cursor = conn.cursor()
        cursor.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
        cursor.execute("DELETE FROM ItemTable")
        for key, val in merged_data.items():
            cursor.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (key, val))
        conn.commit()
        conn.close()
        
    return len(merged_data)

def copy_or_merge_directory(src: str, dst: str, dry_run: bool = False) -> int:
    """Recursively copies files from src to dst without overwriting newer files."""
    if not os.path.exists(src):
        return 0
    count = 0
    for root, dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        dest_dir = os.path.join(dst, rel) if rel != "." else dst
        if not dry_run:
            os.makedirs(dest_dir, exist_ok=True)
        for f in files:
            src_file = os.path.join(root, f)
            dest_file = os.path.join(dest_dir, f)
            if not os.path.exists(dest_file):
                if not dry_run:
                    shutil.copy2(src_file, dest_file)
                count += 1
    return count

def migrate_extensions(src_dot: str, dst_dot: str, dry_run: bool = False) -> int:
    """Migrates extensions folder and rewrites paths inside extensions.json."""
    src_ext = os.path.join(src_dot, "extensions")
    dst_ext = os.path.join(dst_dot, "extensions")
    src_json = os.path.join(src_ext, "extensions.json")
    dst_json = os.path.join(dst_ext, "extensions.json")
    
    if not os.path.exists(src_json):
        return 0
        
    try:
        with open(src_json, "r", encoding="utf-8") as f:
            old_list = json.load(f)
    except Exception:
        return 0
        
    new_list = []
    if os.path.exists(dst_json):
        try:
            with open(dst_json, "r", encoding="utf-8") as f:
                new_list = json.load(f)
        except Exception:
            pass
            
    existing_ids = {ext.get("identifier", {}).get("id", "").lower() for ext in new_list if ext.get("identifier")}
    added = 0
    
    for ext in old_list:
        ext_id = ext.get("identifier", {}).get("id", "").lower()
        if not ext_id or ext_id in existing_ids:
            continue
            
        cloned = json.loads(json.dumps(ext))
        # Rewrite path occurrences
        for key in ["location", "extensionLocation"]:
            if key in cloned:
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
            
    return added

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
                # Exclude huge cache and video recording directories
                def tar_filter(tarinfo):
                    base = os.path.basename(tarinfo.name)
                    if base in ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "logs", "browser_recordings", "IndexedDB", "CachedData"]:
                        return None
                    return tarinfo
                tar.add(path, arcname=tag, filter=tar_filter)
                manifest["items"].append({"tag": tag, "source_path": path})
                
        # Write manifest
        manifest_bytes = json.dumps(manifest, indent=2).encode("utf-8")
        manifest_info = tarfile.TarInfo(name="manifest.json")
        manifest_info.size = len(manifest_bytes)
        manifest_info.mtime = int(time.time())
        import io
        tar.addfile(manifest_info, io.BytesIO(manifest_bytes))
        
    size_mb = os.path.getsize(output_tar) / (1024 * 1024)
    log(f"Backup created successfully! Size: {size_mb:.2f} MB", "SUCCESS")
    return output_tar

def restore_from_archive(input_tar: str, dry_run: bool = False):
    """Restores brains, conversations, and configurations from a backup archive."""
    if not os.path.exists(input_tar):
        log(f"Backup file not found: {input_tar}", "ERROR")
        sys.exit(1)
        
    log(f"Restoring from backup: {input_tar}", "STEP")
    
    import tempfile
    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(input_tar, "r:gz") as tar:
            tar.extractall(path=tmpdir)
            
        manifest_path = os.path.join(tmpdir, "manifest.json")
        manifest = {}
        if os.path.exists(manifest_path):
            with open(manifest_path, "r") as f:
                manifest = json.load(f)
            log(f"Backup archive created on: {manifest.get('created_at', 'unknown')}")
            
        # Target destinations
        restore_map = {
            "gemini_main": PATH_GEMINI_MAIN,
            "gemini_ide": PATH_GEMINI_IDE,
            "config_legacy": PATH_CONFIG_LEGACY,
            "config_ide": PATH_CONFIG_IDE,
            "dot_legacy": PATH_DOT_LEGACY,
            "dot_ide": PATH_DOT_IDE
        }
        
        for item in manifest.get("items", []):
            tag = item.get("tag")
            target_dst = restore_map.get(tag, item.get("source_path"))
            src_extracted = os.path.join(tmpdir, tag)
            
            if os.path.exists(src_extracted) and target_dst:
                log(f"Restoring {tag} -> {target_dst}")
                if tag in ["config_legacy", "config_ide"]:
                    # Merge state databases and json files carefully
                    old_db = os.path.join(src_extracted, "User", "globalStorage", "state.vscdb")
                    dst_db = os.path.join(target_dst, "User", "globalStorage", "state.vscdb")
                    if os.path.exists(old_db):
                        merge_sqlite_vscdb(old_db, dst_db, dry_run=dry_run)
                        
                    old_settings = os.path.join(src_extracted, "User", "settings.json")
                    dst_settings = os.path.join(target_dst, "User", "settings.json")
                    if os.path.exists(old_settings):
                        merge_json_files(old_settings, dst_settings, dry_run=dry_run)
                        
                    copy_or_merge_directory(src_extracted, target_dst, dry_run=dry_run)
                else:
                    copy_or_merge_directory(src_extracted, target_dst, dry_run=dry_run)
                    
    log("Restore completed successfully!", "SUCCESS")

def run_migration(dry_run: bool = False):
    """
    Performs seamless live migration between Antigravity (legacy/desktop)
    and Antigravity IDE.
    """
    log("Starting Antigravity Memory, Chat & State Migration...", "STEP")
    
    # 1. Brains & Conversations
    if os.path.exists(PATH_GEMINI_MAIN):
        brain_dir = os.path.join(PATH_GEMINI_MAIN, "brain")
        if os.path.exists(brain_dir):
            brains = os.listdir(brain_dir)
            log(f"Found {len(brains)} active brain directories in {brain_dir}")
            
            # Sync to IDE gemini path if separate
            target_brain = os.path.join(PATH_GEMINI_IDE, "brain")
            copied = copy_or_merge_directory(brain_dir, target_brain, dry_run=dry_run)
            log(f"Synced {copied} brain files to {target_brain}", "SUCCESS")
            
        # Conversations
        convo_dir = os.path.join(PATH_GEMINI_MAIN, "conversations")
        if os.path.exists(convo_dir):
            target_convo = os.path.join(PATH_GEMINI_IDE, "conversations")
            copied = copy_or_merge_directory(convo_dir, target_convo, dry_run=dry_run)
            log(f"Synced {copied} conversation logs to {target_convo}", "SUCCESS")
            
    # 2. Database & User Config (Antigravity -> Antigravity IDE)
    if os.path.exists(PATH_CONFIG_LEGACY):
        log("Migrating User configurations and state databases...")
        src_db = os.path.join(PATH_CONFIG_LEGACY, "User", "globalStorage", "state.vscdb")
        dst_db = os.path.join(PATH_CONFIG_IDE, "User", "globalStorage", "state.vscdb")
        
        merged_keys = merge_sqlite_vscdb(src_db, dst_db, dry_run=dry_run)
        log(f"Merged state.vscdb ({merged_keys} keys active)", "SUCCESS")
        
        # Merge settings.json
        src_settings = os.path.join(PATH_CONFIG_LEGACY, "User", "settings.json")
        dst_settings = os.path.join(PATH_CONFIG_IDE, "User", "settings.json")
        merge_json_files(src_settings, dst_settings, dry_run=dry_run)
        
        # Copy keybindings & snippets
        for item in ["keybindings.json", "snippets", "workspaceStorage"]:
            s = os.path.join(PATH_CONFIG_LEGACY, "User", item)
            d = os.path.join(PATH_CONFIG_IDE, "User", item)
            if os.path.exists(s):
                if os.path.isdir(s):
                    copy_or_merge_directory(s, d, dry_run=dry_run)
                else:
                    if not dry_run and not os.path.exists(d):
                        os.makedirs(os.path.dirname(d), exist_ok=True)
                        shutil.copy2(s, d)
                        
    # 3. Extensions
    if os.path.exists(PATH_DOT_LEGACY):
        migrated_exts = migrate_extensions(PATH_DOT_LEGACY, PATH_DOT_IDE, dry_run=dry_run)
        log(f"Migrated {migrated_exts} extensions to {PATH_DOT_IDE}", "SUCCESS")
        
    log("Migration completed successfully!", "SUCCESS")

def main():
    parser = argparse.ArgumentParser(description="Antigravity Chat, Memory & State Migration Tool")
    parser.add_argument("--backup", nargs="?", const="", help="Create a backup archive (optional output path)")
    parser.add_argument("--import", dest="import_file", help="Import / restore from a backup archive")
    parser.add_argument("--migrate", action="store_true", help="Migrate between Antigravity versions")
    parser.add_argument("--dry-run", action="store_true", help="Simulate actions without modifying files")
    parser.add_argument("--status", action="store_true", help="Inspect brains, chats, and config sizes")
    
    args = parser.parse_args()
    
    if args.status:
        print("\n=== Antigravity Data Status ===")
        for name, p in [
            ("Gemini Brains & Chats", PATH_GEMINI_MAIN),
            ("Gemini IDE Brains", PATH_GEMINI_IDE),
            ("Config Legacy", PATH_CONFIG_LEGACY),
            ("Config IDE", PATH_CONFIG_IDE),
            ("Extensions Legacy", PATH_DOT_LEGACY),
            ("Extensions IDE", PATH_DOT_IDE)
        ]:
            if os.path.exists(p):
                # Count files
                file_count = sum(len(files) for _, _, files in os.walk(p))
                size_mb = sum(os.path.getsize(os.path.join(r, f)) for r, _, files in os.walk(p) for f in files) / (1024 * 1024)
                print(f"  ✔ {name}: {p} ({file_count} files, {size_mb:.2f} MB)")
            else:
                print(f"  - {name}: not found")
        print("")
        sys.exit(0)
        
    if args.backup is not None:
        create_backup_archive(args.backup if args.backup != "" else None)
    elif args.import_file:
        restore_from_archive(args.import_file, dry_run=args.dry_run)
    elif args.migrate:
        run_migration(dry_run=args.dry_run)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
