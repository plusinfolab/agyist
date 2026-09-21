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
from migrator import merge_sqlite_vscdb, merge_json_files, PROTOBUF_KEYS_TO_CONCAT, get_account_from_db, get_account_status

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

    def test_get_account_from_db_json(self):
        import json
        db_path = os.path.join(self.tmpdir.name, "test_account_json.vscdb")
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)")
        payload = json.dumps({
            "name": "Alex Dev",
            "email": "alex@company.com",
            "apiKey": "ya29.test123",
            "plan": "pro"
        })
        cur.execute("INSERT INTO ItemTable VALUES (?, ?)", ("antigravityAuthStatus", payload))
        conn.commit()
        conn.close()

        acc = get_account_from_db(db_path)
        self.assertIsNotNone(acc)
        self.assertEqual(acc["email"], "alex@company.com")
        self.assertEqual(acc["name"], "Alex Dev")
        self.assertEqual(acc["plan"], "Google AI Pro")
        self.assertTrue(acc["has_token"])

    def test_get_account_from_db_protobuf(self):
        db_path = os.path.join(self.tmpdir.name, "test_account_proto.vscdb")
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)")
        # OAuth token binary payload containing email
        proto_data = b"\x0a\x1auser@example.com\x12\x20ya29.mocked_token_string"
        b64 = base64.b64encode(proto_data).decode("utf-8")
        cur.execute("INSERT INTO ItemTable VALUES (?, ?)", ("antigravityUnifiedStateSync.oauthToken", b64))
        conn.commit()
        conn.close()

        acc = get_account_from_db(db_path)
        self.assertIsNotNone(acc)
        self.assertEqual(acc["email"], "user@example.com")
        self.assertTrue(acc["has_token"])

    def test_get_account_status_structure(self):
        status = get_account_status()
        self.assertIn("cockpit", status)
        self.assertIn("ide", status)
        self.assertIn("desktop", status)
        self.assertIn("in_sync", status)
        self.assertIn("unique_emails", status)
        self.assertIsInstance(status["unique_emails"], list)

if __name__ == "__main__":
    unittest.main()

