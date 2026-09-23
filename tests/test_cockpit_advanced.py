#!/usr/bin/env python3
"""
tests/test_cockpit_advanced.py - Unit tests for Cockpit Tools integration,
AES-256-GCM storage, protobuf codec, account switching, instances, doctor, and export/import.
"""

import os
import sys
import json
import base64
import time
import tempfile
import sqlite3
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
import migrator

class TestCockpitAdvanced(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.cockpit_dir = os.path.join(self.tmpdir.name, ".antigravity_cockpit")
        os.makedirs(self.cockpit_dir, exist_ok=True)
        self.orig_cockpit_env = os.environ.get("COCKPIT_TOOLS_DATA_DIR")
        os.environ["COCKPIT_TOOLS_DATA_DIR"] = self.cockpit_dir

    def tearDown(self):
        if self.orig_cockpit_env is not None:
            os.environ["COCKPIT_TOOLS_DATA_DIR"] = self.orig_cockpit_env
        else:
            os.environ.pop("COCKPIT_TOOLS_DATA_DIR", None)
        self.tmpdir.cleanup()

    def test_cockpit_key_generation_and_account_encryption(self):
        key = migrator.get_cockpit_key(create_if_missing=True)
        self.assertEqual(len(key), 32)

        sample_account = {
            "id": "acc-uuid-1",
            "email": "tester@example.com",
            "name": "Test User",
            "token": {
                "access_token": "ya29.sample_access",
                "refresh_token": "1//sample_refresh",
                "expiry_timestamp": int(time.time()) + 7200
            }
        }

        acc_path = os.path.join(self.cockpit_dir, "accounts", "acc-uuid-1.json")
        migrator.encrypt_account_file(acc_path, sample_account, key)

        self.assertTrue(os.path.exists(acc_path))
        with open(acc_path, "r", encoding="utf-8") as f:
            raw_data = json.load(f)
        self.assertEqual(raw_data.get("algorithm"), "AES-256-GCM")
        self.assertIn("ciphertext", raw_data)
        self.assertIn("nonce", raw_data)

        # Decrypt
        decrypted = migrator.decrypt_account_file(acc_path, key)
        self.assertEqual(decrypted["email"], "tester@example.com")
        self.assertEqual(decrypted["name"], "Test User")
        self.assertEqual(decrypted["token"]["access_token"], "ya29.sample_access")

    def test_protobuf_codec_and_sentinel_removal(self):
        # 1. Varint encoding / decoding
        for num in [0, 1, 127, 128, 300, 16384, 1790000000]:
            encoded = migrator.encode_varint(num)
            val, off = migrator.read_varint(encoded, 0)
            self.assertEqual(val, num)
            self.assertEqual(off, len(encoded))

        # 2. OAuth protobuf message
        proto = migrator.create_oauth_info_protobuf(
            access_token="test_access",
            refresh_token="test_refresh",
            expiry=1790000000,
            id_token="test_id_token",
            is_gcp_tos=True,
            email="tester@example.com"
        )
        self.assertTrue(len(proto) > 20)

        # 3. Unified topic entry and removal
        entry1 = migrator.create_unified_topic_entry("keyA", b"payloadA")
        entry2 = migrator.create_unified_topic_entry("keyB", b"payloadB")
        combined = entry1 + entry2
        removed = migrator.remove_unified_topic_entry(combined, "keyA")
        self.assertEqual(removed, entry2)

    def test_direct_sqlite_token_injection(self):
        db_path = os.path.join(self.tmpdir.name, "state.vscdb")
        account = {
            "id": "acc-777",
            "email": "injected@example.com",
            "name": "Injected User",
            "token": {
                "access_token": "ya29.inject_token",
                "refresh_token": "1//inject_refresh",
                "expiry_timestamp": int(time.time()) + 3600
            }
        }

        success = migrator.inject_account_to_vscdb(db_path, account)
        self.assertTrue(success)
        self.assertTrue(os.path.exists(db_path))

        # Check tables and keys
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("SELECT key FROM ItemTable")
        keys = {r[0] for r in cur.fetchall()}
        conn.close()

        self.assertIn("antigravityUnifiedStateSync.oauthToken", keys)
        self.assertIn("antigravityUnifiedStateSync.userStatus", keys)
        self.assertIn("antigravityAuthStatus", keys)
        self.assertIn("antigravityOnboarding", keys)

        # Check get_account_from_db
        extracted = migrator.get_account_from_db(db_path)
        self.assertIsNotNone(extracted)
        self.assertEqual(extracted["email"], "injected@example.com")
        self.assertEqual(extracted["name"], "Injected User")

    def test_multi_instance_profile_creation(self):
        key = migrator.get_cockpit_key(create_if_missing=True)
        acc_path = os.path.join(self.cockpit_dir, "accounts", "acc-inst.json")
        migrator.encrypt_account_file(acc_path, {
            "id": "acc-inst",
            "email": "profile@example.com",
            "token": {"access_token": "ya29.prof", "refresh_token": "1//prof"}
        }, key)

        profile = migrator.setup_instance_profile("work-client", bind_account="acc-inst")
        self.assertEqual(profile["name"], "work-client")
        self.assertTrue(os.path.exists(profile["user_data_dir"]))
        self.assertTrue(os.path.exists(profile["state_db"]))

        instances = migrator.list_cockpit_instances()
        self.assertEqual(len(instances), 1)
        self.assertEqual(instances[0]["name"], "work-client")
        self.assertEqual(instances[0]["bindAccountId"], "acc-inst")

    def test_cockpit_doctor_repairs(self):
        # Create stale lock and dead PID server.json
        lock_file = os.path.join(self.cockpit_dir, "config.json.lock")
        with open(lock_file, "w") as f:
            f.write("")

        server_file = os.path.join(self.cockpit_dir, "server.json")
        with open(server_file, "w") as f:
            json.dump({"ws_port": 12345, "pid": 99999999}, f)

        res = migrator.repair_cockpit_tools()
        self.assertTrue(res["success"])
        self.assertFalse(os.path.exists(lock_file))
        self.assertFalse(os.path.exists(server_file))
        self.assertGreater(res["repairs_count"], 0)

    def test_encrypted_account_export_and_import(self):
        key = migrator.get_cockpit_key(create_if_missing=True)
        acc1 = {
            "id": "acc-exp-1",
            "email": "user1@example.com",
            "token": {"access_token": "ya29.tok1", "refresh_token": "1//ref1"}
        }
        acc2 = {
            "id": "acc-exp-2",
            "email": "user2@example.com",
            "token": {"access_token": "ya29.tok2", "refresh_token": "1//ref2"}
        }
        migrator.encrypt_account_file(os.path.join(self.cockpit_dir, "accounts", "acc-exp-1.json"), acc1, key)
        migrator.encrypt_account_file(os.path.join(self.cockpit_dir, "accounts", "acc-exp-2.json"), acc2, key)

        with open(os.path.join(self.cockpit_dir, "accounts.json"), "w") as f:
            json.dump({"current_account_id": "acc-exp-1", "accounts": [acc1, acc2]}, f)

        export_archive = os.path.join(self.tmpdir.name, "backup.agyacc")
        password = "SecurePassword123!"

        # 1. Export
        migrator.export_cockpit_accounts(export_archive, password=password)
        self.assertTrue(os.path.exists(export_archive))
        stat = os.stat(export_archive)
        self.assertEqual(stat.st_mode & 0o777, 0o600)

        # 2. Reject wrong password
        with self.assertRaises(ValueError):
            migrator.import_cockpit_accounts(export_archive, password="WrongPassword")

        # 3. Import into clean directory
        clean_cockpit_dir = os.path.join(self.tmpdir.name, "clean_cockpit")
        os.environ["COCKPIT_TOOLS_DATA_DIR"] = clean_cockpit_dir
        imported_count = migrator.import_cockpit_accounts(export_archive, password=password)
        self.assertEqual(imported_count, 2)

        clean_accounts = migrator.get_all_cockpit_accounts()
        self.assertEqual(len(clean_accounts), 2)
        emails = {a["email"] for a in clean_accounts}
        self.assertIn("user1@example.com", emails)
        self.assertIn("user2@example.com", emails)

if __name__ == "__main__":
    unittest.main()
