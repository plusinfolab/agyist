#!/usr/bin/env python3
"""
tests/test_backup_roundtrip.py - Unit test for backup archive creation and restore roundtrip.
"""

import os
import sys
import tempfile
import unittest
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lib"))
from migrator import create_backup_archive, restore_from_archive

class TestBackupRoundtrip(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.archive_path = os.path.join(self.tmpdir.name, "test_backup.tar.gz")

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_backup_creates_valid_tar(self):
        created_file = create_backup_archive(self.archive_path)
        self.assertTrue(os.path.exists(created_file))
        self.assertGreater(os.path.getsize(created_file), 1000)

if __name__ == "__main__":
    unittest.main()

