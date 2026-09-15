#!/usr/bin/env python3
"""
lib/nautilus.py - Nautilus / GNOME Files context menu extension for Antigravity IDE
"""

import subprocess
from urllib.parse import unquote, urlparse

try:
    from gi.repository import Nautilus, GObject
except ImportError:
    pass

class OpenInAntigravityIDE(GObject.GObject, Nautilus.MenuProvider):
    def _path(self, file_info):
        uri = file_info.get_uri()
        parsed = urlparse(uri)
        if parsed.scheme != 'file':
            return None
        return unquote(parsed.path)

    def get_file_items(self, files):
        if not files or len(files) != 1:
            return []
        path = self._path(files[0])
        if not path:
            return []
        item = Nautilus.MenuItem(
            name='OpenInAntigravityIDE::open',
            label='Open in Antigravity IDE',
            tip='Open this file or directory in Antigravity IDE'
        )
        item.connect('activate', lambda _item: subprocess.Popen(['antigravity-ide', path]))
        return [item]

    def get_background_items(self, folder):
        path = self._path(folder)
        if not path:
            return []
        item = Nautilus.MenuItem(
            name='OpenInAntigravityIDE::open_background',
            label='Open Folder in Antigravity IDE',
            tip='Open the current folder in Antigravity IDE'
        )
        item.connect('activate', lambda _item: subprocess.Popen(['antigravity-ide', path]))
        return [item]

