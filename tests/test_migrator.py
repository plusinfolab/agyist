#!/usr/bin/env python3
"""
tests/test_migrator.py - Unit tests for database merging, protobuf concatenation, and JSON merging.
"""

import os
import sys
import tempfile
import sqlite3
import base64
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
from migrator import merge_sqlite_vscdb, merge_json_files, PROTOBUF_KEYS_TO_CONCAT

class TestMigrator(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.src_db = os.path.join(self.tmpdir.name, "src_state.vscdb")
        self.dst_db = os.path.join(self.tmpdir.name, "dst_state.vscdb")

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_protobuf_concatenation(self):
        # Create source DB with a base64 protobuf payload
        src_conn = sqlite3.connect(self.src_db)
        src_cur = src_conn.cursor()
        src_cur.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)")
        
        # Simulate protobuf bytes
        payload_src = b"\x08\x96\x01\x12\x07summary1"
        payload_dst = b"\x08\x97\x01\x12\x07summary2"
        
        b64_src = base64.b64encode(payload_src).decode("utf-8")
        b64_dst = base64.b64encode(payload_dst).decode("utf-8")
        
        proto_key = PROTOBUF_KEYS_TO_CONCAT[0]
        src_cur.execute("INSERT INTO ItemTable VALUES (?, ?)", (proto_key, b64_src))
        src_cur.execute("INSERT INTO ItemTable VALUES (?, ?)", ("other_key", "src_val"))
        src_conn.commit()
        src_conn.close()

        # Create destination DB
        dst_conn = sqlite3.connect(self.dst_db)
        dst_cur = dst_conn.cursor()
        dst_cur.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)")
        dst_cur.execute("INSERT INTO ItemTable VALUES (?, ?)", (proto_key, b64_dst))
        dst_cur.execute("INSERT INTO ItemTable VALUES (?, ?)", ("new_key", "dst_val"))
        dst_conn.commit()
        dst_conn.close()

        # Merge
        merged_count = merge_sqlite_vscdb(self.src_db, self.dst_db)
        self.assertEqual(merged_count, 3)

        # Verify merged result
        res_conn = sqlite3.connect(self.dst_db)
        res_cur = res_conn.cursor()
        res_cur.execute("SELECT key, value FROM ItemTable")
        results = dict(res_cur.fetchall())
        res_conn.close()

        # Check that protobuf payload was binary concatenated
        merged_bytes = base64.b64decode(results[proto_key])
        expected_bytes = payload_src + payload_dst
        self.assertEqual(merged_bytes, expected_bytes)
        self.assertEqual(results["other_key"], "src_val")
        self.assertEqual(results["new_key"], "dst_val")

    def test_json_merge(self):
        src_json = os.path.join(self.tmpdir.name, "src.json")
        dst_json = os.path.join(self.tmpdir.name, "dst.json")
        
        with open(src_json, "w") as f:
            f.write('{"font": "monospace", "theme": "dark", "tabSize": 2}')
        with open(dst_json, "w") as f:
            f.write('{"font": "JetBrains Mono", "zoom": 1}')
            
        merge_json_files(src_json, dst_json)
        
        import json
        with open(dst_json) as f:
            data = json.load(f)
            
        self.assertEqual(data["font"], "JetBrains Mono") # overridden by dst
        self.assertEqual(data["theme"], "dark")           # preserved from src
        self.assertEqual(data["tabSize"], 2)             # preserved from src
        self.assertEqual(data["zoom"], 1)                # dst preserved

if __name__ == "__main__":
    unittest.main()

