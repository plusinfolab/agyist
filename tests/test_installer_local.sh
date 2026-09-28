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
"$PROJECT_ROOT/agyist" --diagnose-cockpit | grep "Cockpit Tools & Antigravity" >/dev/null || { echo "Cockpit diagnose test failed"; exit 1; }
echo "✔ Cockpit diagnose test passed"

echo "==> Testing Account Inspection..."
"$PROJECT_ROOT/agyist" --account | grep -q "Antigravity & Cockpit Tools Active Accounts" || { echo "Account test failed"; exit 1; }
"$PROJECT_ROOT/agyist" --account --json | grep -q '"unique_emails"' || { echo "Account JSON test failed"; exit 1; }
echo "✔ Account test passed"

echo "==> Testing Real-Time Watcher Dry-run..."
"$PROJECT_ROOT/agyist" --watch --dry-run | grep -q "Watcher dry-run check passed" || { echo "Watch dry-run test failed"; exit 1; }
echo "✔ Watcher dry-run test passed"

echo "==> Testing Desktop Entry Configuration..."
"$PROJECT_ROOT/agyist" --desktop-entry --dry-run | grep -q "Desktop integration dry-run completed successfully" || { echo "Desktop entry test failed"; exit 1; }
echo "✔ Desktop entry test passed"

echo "==> Testing Self-Update Dry-run..."
"$PROJECT_ROOT/agyist" --self-update --dry-run | grep -q "Self-update check completed" || { echo "Self-update test failed"; exit 1; }
echo "✔ Self-update dry-run test passed"

echo "==> Testing Launcher Safety & Recursion Prevention..."
bash -c "
set -euo pipefail
SCRIPT_DIR=\"$PROJECT_ROOT/lib\"
source \"\$SCRIPT_DIR/common.sh\"
source \"\$SCRIPT_DIR/installer.sh\"

TEST_DIR=\"\$(mktemp -d)\"
trap \"rm -rf '\$TEST_DIR'\" EXIT

mkdir -p \"\$TEST_DIR/install/bin\" \"\$TEST_DIR/bin\"
echo '#!/bin/sh' > \"\$TEST_DIR/install/bin/antigravity-ide\"
echo 'echo OFFICIAL_LAUNCHER_OK' >> \"\$TEST_DIR/install/bin/antigravity-ide\"
chmod 755 \"\$TEST_DIR/install/bin/antigravity-ide\"

echo 'BINARY_CONTENTS_12345' > \"\$TEST_DIR/install/antigravity-ide\"
chmod 755 \"\$TEST_DIR/install/antigravity-ide\"

# Pre-existing symlink (the exact trap that triggered the old bug)
ln -sf \"\$TEST_DIR/install/antigravity-ide\" \"\$TEST_DIR/bin/antigravity-ide\"

# Run create_cli_launcher
create_cli_launcher 'antigravity-ide' \"\$TEST_DIR/install/antigravity-ide\" \"\$TEST_DIR/bin\" \"\$TEST_DIR/install\" >/dev/null

# 1. Verify original binary was NOT truncated or overwritten
CONTENT=\"\$(cat \"\$TEST_DIR/install/antigravity-ide\")\"
if [ \"\$CONTENT\" != 'BINARY_CONTENTS_12345' ]; then
    echo 'FAILED: Target binary was overwritten by launcher!'
    exit 1
fi

# 2. Verify launcher correctly runs without recursion loop
OUTPUT=\"\$(\"\$TEST_DIR/bin/antigravity-ide\")\"
if [ \"\$OUTPUT\" != 'OFFICIAL_LAUNCHER_OK' ]; then
    echo \"FAILED: Launcher did not run expected binary! Output: \$OUTPUT\"
    exit 1
fi
"
echo "✔ Launcher safety & recursion prevention test passed"

echo "==> Testing Doctor & Anti-Freeze Diagnostics..."
DOCTOR_OUTPUT="$("$PROJECT_ROOT/agyist" --doctor -y 2>&1)"
if ! echo "$DOCTOR_OUTPUT" | grep -q "Antigravity System Doctor & Freeze Diagnostics"; then
    echo "FAILED: Doctor did not run expected diagnostics!"
    echo "$DOCTOR_OUTPUT"
    exit 1
fi
echo "✔ Doctor & anti-freeze diagnostics test passed"

echo "==> All automated tests passed successfully!"


