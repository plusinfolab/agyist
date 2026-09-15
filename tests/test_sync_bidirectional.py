#!/usr/bin/env python3
"""
tests/test_sync_bidirectional.py - Tests for bidirectional chat & brain sync engine
"""

import os
import sys
import tempfile
import sqlite3
import base64
import unittest
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
from migrator import (
    merge_sqlite_vscdb,
    merge_workspace_storage,
    configure_pbtxt_states,
    PROTOBUF_KEYS_TO_CONCAT,
)

class TestSyncBidirectional(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.db_a = os.path.join(self.tmpdir.name, "db_a", "state.vscdb")
        self.db_b = os.path.join(self.tmpdir.name, "db_b", "state.vscdb")
        os.makedirs(os.path.dirname(self.db_a), exist_ok=True)
        os.makedirs(os.path.dirname(self.db_b), exist_ok=True)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_bidirectional_sqlite_merge(self):
        # Database A has 3 conversation notifications and a protobuf summary
        conn_a = sqlite3.connect(self.db_a)
        cur_a = conn_a.cursor()
        cur_a.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)")
        cur_a.execute("INSERT INTO ItemTable VALUES ('antigravity.notification.thread_1', 'chat 1 payload')")
        cur_a.execute("INSERT INTO ItemTable VALUES ('antigravity.notification.thread_2', 'chat 2 payload')")
        cur_a.execute("INSERT INTO ItemTable VALUES ('secret://token1', 'encrypted_token_1')")

        proto_key = PROTOBUF_KEYS_TO_CONCAT[0]
        payload_a = b"\x08\x01\x12\x04msgA"
        cur_a.execute("INSERT INTO ItemTable VALUES (?, ?)", (proto_key, base64.b64encode(payload_a).decode()))
        conn_a.commit()
        conn_a.close()

        # Database B has a different thread and protobuf summary
        conn_b = sqlite3.connect(self.db_b)
        cur_b = conn_b.cursor()
        cur_b.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)")
        cur_b.execute("INSERT INTO ItemTable VALUES ('antigravity.notification.thread_3', 'chat 3 payload')")
        cur_b.execute("INSERT INTO ItemTable VALUES ('ide_specific_key', 'ide_val')")

        payload_b = b"\x08\x02\x12\x04msgB"
        cur_b.execute("INSERT INTO ItemTable VALUES (?, ?)", (proto_key, base64.b64encode(payload_b).decode()))
        conn_b.commit()
        conn_b.close()

        # Perform bidirectional merge (write_both=True)
        total_merged = merge_sqlite_vscdb(self.db_a, self.db_b, dry_run=False, write_both=True)
        self.assertGreater(total_merged, 0)

        # Inspect DB A
        conn_a = sqlite3.connect(self.db_a)
        cur_a = conn_a.cursor()
        keys_a = dict(cur_a.execute("SELECT key, value FROM ItemTable").fetchall())
        conn_a.close()

        # Inspect DB B
        conn_b = sqlite3.connect(self.db_b)
        cur_b = conn_b.cursor()
        keys_b = dict(cur_b.execute("SELECT key, value FROM ItemTable").fetchall())
        conn_b.close()

        # Both databases must now contain all 5 distinct keys
        expected_keys = {
            'antigravity.notification.thread_1',
            'antigravity.notification.thread_2',
            'antigravity.notification.thread_3',
            'secret://token1',
            'ide_specific_key',
            proto_key
        }
        self.assertEqual(set(keys_a.keys()), expected_keys)
        self.assertEqual(set(keys_b.keys()), expected_keys)

        # Verify protobuf concatenation on both databases
        expected_proto = payload_a + payload_b
        self.assertEqual(base64.b64decode(keys_a[proto_key]), expected_proto)
        self.assertEqual(base64.b64decode(keys_b[proto_key]), expected_proto)

    def test_merge_workspace_storage(self):
        storage_a = os.path.join(self.tmpdir.name, "storage_a")
        storage_b = os.path.join(self.tmpdir.name, "storage_b")

        ws1_a = os.path.join(storage_a, "ws1")
        ws2_b = os.path.join(storage_b, "ws2")
        os.makedirs(ws1_a, exist_ok=True)
        os.makedirs(ws2_b, exist_ok=True)

        with open(os.path.join(ws1_a, "workspace.json"), "w") as f:
            f.write('{"folder": "file:///path/to/project1"}')

        with open(os.path.join(ws2_b, "workspace.json"), "w") as f:
            f.write('{"folder": "file:///path/to/project2"}')

        merge_workspace_storage(storage_a, storage_b)

        # Both storage directories must now have both ws1 and ws2
        self.assertTrue(os.path.exists(os.path.join(storage_a, "ws1", "workspace.json")))
        self.assertTrue(os.path.exists(os.path.join(storage_a, "ws2", "workspace.json")))
        self.assertTrue(os.path.exists(os.path.join(storage_b, "ws1", "workspace.json")))
        self.assertTrue(os.path.exists(os.path.join(storage_b, "ws2", "workspace.json")))

    def test_configure_pbtxt_states(self):
        pbtxt_path = os.path.join(self.tmpdir.name, "antigravity_state.pbtxt")
        with open(pbtxt_path, "w") as f:
            f.write("user_id: 12345\nmigrate_convos_into_projects: MIGRATION_STATUS_UNSPECIFIED\n")

        # Update in-place
        configure_pbtxt_states("MIGRATION_STATUS_COMPLETED", pbtxt_path=pbtxt_path)

        with open(pbtxt_path, "r") as f:
            content = f.read()

        self.assertIn("migrate_convos_into_projects: MIGRATION_STATUS_COMPLETED", content)
        self.assertIn("user_id: 12345", content)

if __name__ == "__main__":
    unittest.main()

