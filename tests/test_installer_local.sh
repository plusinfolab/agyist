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
"$PROJECT_ROOT/agyist" --status | grep -q "Antigravity Data Status" || { echo "Status test failed"; exit 1; }
echo "✔ Status test passed"

echo "==> Testing Migrator Dry-run Migration..."
python3 "$PROJECT_ROOT/lib/migrator.py" --migrate --dry-run | grep -q "Migration completed successfully" || { echo "Migrate test failed"; exit 1; }
echo "✔ Migration dry-run test passed"

echo "==> All automated tests passed successfully!"
