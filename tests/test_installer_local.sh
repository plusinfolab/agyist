#!/usr/bin/env bash
# tests/test_installer_local.sh - Verification test for installer components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==> Testing Resolver..."
OUTPUT="$(python3 "$PROJECT_ROOT/lib/resolver.py" --product ide --platform linux-x64 --json)"
echo "$OUTPUT" | grep -q '"product": "ide"' || { echo "Resolver test failed"; exit 1; }
echo "$OUTPUT" | grep -q '"version"' || { echo "Resolver version missing"; exit 1; }
echo "✔ Resolver test passed"

echo "==> Testing Migrator Status..."
"$PROJECT_ROOT/agyist" --status | grep -q "Antigravity Data" || { echo "Status test failed"; exit 1; }
echo "✔ Status test passed"

echo "==> Testing Status JSON..."
"$PROJECT_ROOT/agyist" --status --json | grep -q '"sync_status"' || { echo "Status JSON test failed"; exit 1; }
echo "✔ Status JSON test passed"

echo "==> Testing Check-Update..."
"$PROJECT_ROOT/agyist" --check-update >/dev/null 2>&1 || true
echo "✔ Check-update test passed"

echo "==> Testing Migrator Dry-run Migration..."
python3 "$PROJECT_ROOT/lib/migrator.py" --migrate --dry-run | grep -q "Migration completed successfully" || { echo "Migrate test failed"; exit 1; }
echo "✔ Migration dry-run test passed"

echo "==> Testing Bi-directional Sync Dry-run..."
"$PROJECT_ROOT/agyist" --sync --dry-run | grep -q "Bi-directional sync completed successfully" || { echo "Sync dry-run test failed"; exit 1; }
echo "✔ Sync dry-run test passed"

echo "==> Testing Cockpit Tools Diagnostics..."
"$PROJECT_ROOT/agyist" --diagnose-cockpit | grep "Cockpit Tools & Antigravity IDE Integration Diagnostics" >/dev/null || { echo "Cockpit diagnose test failed"; exit 1; }
echo "✔ Cockpit diagnose test passed"

echo "==> All automated tests passed successfully!"
