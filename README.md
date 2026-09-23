# Antigravity Linux Suite (`agyist`)

```
      ___           ___           ___                       ___           ___     
     /\  \         /\  \         |\__\          ___        /\  \         /\  \    
    /::\  \       /::\  \        |:|  |        /\  \      /::\  \        \:\  \   
   /:/\:\  \     /:/\:\  \       |:|  |        \:\  \    /:/\ \  \        \:\  \  
  /::\~\:\  \   /:/  \:\  \      |:|__|__      /::\__\  _\:\~\ \  \       /::\  \ 
 /:/\:\ \:\__\ /:/__/_\:\__\     /::::\__\  __/:/\/__/ /\ \:\ \ \__\     /:/\:\__\
 \/__\:\/:/  / \:\  /\ \/__/    /:/~~/~    /\/:/  /    \:\ \:\ \/__/    /:/  \/__/
      \::/  /   \:\ \:\__\     /:/  /      \::/__/      \:\ \:\__\     /:/  /     
      /:/  /     \:\/:/  /     \/__/        \:\__\       \:\/:/  /     \/__/      
     /:/  /       \::/  /                    \/__/        \::/  /                 
     \/__/         \/__/                                   \/__/                  
```

> **The definitive Linux installer, updater, fleet deployment suite, and bi-directional brain/chat sync manager for Google Antigravity 2.0 and Antigravity IDE.**

---

## Highlights

- **Interactive TUI & Non-Interactive CLI**: Launch an interactive terminal wizard with `./agyist` or run automated headless one-liners.
- **Both Applications Fully Supported**:
  - **Antigravity IDE**: AI-first coding environment based on VS Code with Gemini agent integration.
  - **Antigravity 2.0**: Standalone desktop AI assistant and agent workspace.
- **Bi-Directional Chat & Brain Synchronization (`--sync`)**:
  - Automatically unifies SQLite `state.vscdb` conversation threads and notifications between 2.0 and IDE.
  - Binary concatenation of repeated protobuf messages (`trajectorySummaries` and `sidebarWorkspaces`).
  - Synchronizes agent brains (`~/.gemini/antigravity/brain/`), conversation logs, knowledge bases, and workspace storage across both applications.
  - Automatically configures `antigravity_state.pbtxt` (`MIGRATION_STATUS_COMPLETED`) so Antigravity IDE discovers and displays project conversations.
  - Automatically triggered in the background after every install or upgrade.
- **Office Fleet & Air-Gapped Workstations**:
  - **Offline Deployment Bundles (`--bundle`)**: Creates a standalone `.tar.gz` archive containing official Google packages, `agyist`, `lib/`, and authentic branding assets with a 1-step offline `install.sh`.
  - **Automated Background Updates (`--setup-autoupdate`)**: Sets up a native `systemd` user timer and service (with automatic fallback to `crontab` on containers/headless servers).
  - **Scriptable Update Checker (`--check-update`)**: Automated exit codes (`0` for current, `10` for update available) for Ansible, Puppet, and CI/CD pipelines.
  - **Telemetry & Diagnostics (`--status --json`)**: Machine-readable JSON output for central monitoring dashboards.
  - **Unattended Execution**: Non-interactive flags (`-y` / `--yes`, `-q` / `--quiet`).
- **Resilient Official Google Scraper**: Pure native Bash scraping of `https://antigravity.google/download` directly from Astro HTML and fallback CDN release channels.
- **Dual Installation Scope**:
  - **User Scope** (`~/.local/`, non-root, container & sandbox friendly)
  - **System Scope** (`/opt/` or `/usr/share/`, with `sudo` or root)
- **Authentic Official Google Branding**: High-resolution 256×256, 512×512, scalable SVG, and Google press brand assets for both Antigravity 2.0 and Antigravity IDE.
- **Full Desktop Integration**:
  - Generates validated `.desktop` entries with standard MIME associations (`inode/directory`, `text/plain`, `.workspace`).
  - Registers URL handlers (`x-scheme-handler/antigravity` and `antigravity-ide`).
  - GNOME Files / Nautilus right-click context menu extension.
- **One-Click Upgrades with Safe Rollback**: Replaces application directories atomically and preserves `.previous` rollback copies.
- **Comprehensive Memory & State Management**:
  - **Snapshot Backup (`--backup`)**: Archive all conversation brains, transcripts, knowledge, SQLite databases, and user configs.
  - **Snapshot Restore (`--import`)**: Effortlessly transfer or restore memory and chats onto any Linux workstation.
  - **Migration (`--migrate`)**: Upgrade and migrate legacy Antigravity state into Antigravity IDE.

---

## Installation & Deployment

### 1. One-Line Remote Install (Any Linux Machine)
Run this single command on any Linux workstation to download, install the `agyist` CLI suite into `~/.local/bin/agyist` (and `/usr/local/bin/agyist` if root/sudo is available), and launch the interactive setup:
```bash
curl -fsSL https://raw.githubusercontent.com/plusinfolab/agyist/main/install.sh | bash
```

> **Note on Shell PATH**: In Linux, child processes cannot mutate parent shell environments. To start using `agyist` immediately in the same terminal session right after running the installer, reload your shell profile:
> ```bash
> source ~/.bashrc   # or: source ~/.zshrc
> ```

To install both Antigravity IDE and Antigravity 2.0 Desktop unattended:
```bash
curl -fsSL https://raw.githubusercontent.com/plusinfolab/agyist/main/install.sh | bash -s -- --all -y
```

### 2. Interactive Terminal UI
When run locally without arguments, `agyist` presents an interactive terminal wizard:
```bash
agyist
```

### 3. Standalone & Fleet Commands
```bash
# Install Antigravity IDE in user scope (no root needed)
agyist --ide --user

# Install Antigravity 2.0 Desktop app
agyist --desktop --user

# Install or upgrade both applications system-wide
sudo agyist --all --system

# Bi-directionally synchronize chats, brains, and state between 2.0 and IDE
agyist --sync

# Check if updates are available (exit code 10 if update available)
agyist --check-update

# Unattended fleet upgrade of all installed components
agyist --upgrade -y -q

# Generate a standalone offline bundle for air-gapped office PCs
agyist --bundle ~/antigravity-office-bundle.tar.gz

# Schedule automated daily background updates via systemd user timer
agyist --setup-autoupdate daily
```

---

## Upgrades & Maintenance

### 1. Self-Updating `agyist` CLI Suite
Whenever new features, bugfixes, or Cockpit Tools adaptations are pushed to GitHub, update `agyist` itself with a single command without needing to reinstall:
```bash
agyist --self-update
```
- For **Git clones**: Runs a fast `git fetch && git merge --ff-only origin/main`.
- For **curl/standalone installs**: Downloads and unpacks the latest release tarball directly from GitHub and refreshes binary symlinks.

### 2. Upgrading Antigravity Applications
To upgrade all installed Antigravity components (IDE and 2.0 Desktop) to the latest official Google releases:
```bash
agyist --upgrade
```
> **ProTip**: `agyist --upgrade` automatically self-updates `agyist` first, ensuring your scrapers and migration tools are always up to date before updating the applications!

To check if updates are available without applying them (exit code `0` = up to date, `10` = update available):
```bash
agyist --check-update
```

---

## Cockpit Tools Multi-Account & Multi-Instance Suite

`agyist` provides a deep, production-grade integration with Cockpit Tools and Antigravity on Linux:

### 1. Instant CLI Account Switcher (`--switch`)
Switch active accounts across Cockpit Tools, Antigravity IDE, and Antigravity 2.0 Desktop from your terminal:
```bash
# Interactive selection menu (lists all saved accounts)
agyist --switch

# Switch by account index (from --accounts list)
agyist --switch 2

# Switch by email or partial name
agyist --switch meetsavani5657@gmail.com
agyist --switch hiru
```
- **Dual-Mode Switching**:
  - **Online IPC Mode**: If Cockpit Tools is running, communicates with its local WebSocket daemon (`ws://127.0.0.1:<port>`), triggering an instantaneous switch and live UI refresh.
  - **Offline Direct Mode**: If Cockpit Tools is closed, directly injects credentials into SQLite `state.vscdb` (`antigravityUnifiedStateSync.oauthToken` protobuf + `userStatus` + `antigravityAuthStatus`) and updates `current_account.json` and `accounts.json`.

### 2. Saved Accounts & Token Health Inspector (`--accounts`)
Inspect all Cockpit accounts with real-time token validity countdowns:
```bash
agyist --accounts          # Formatted terminal table
agyist --accounts --json   # Safe structured JSON (tokens masked)
```

### 3. Multi-Instance Isolated Profiles (`--instance` & `--instances`)
Run separate Antigravity IDE instances simultaneously with dedicated `--user-data-dir` profiles and separate logged-in accounts:
```bash
# Launch or create an isolated instance named 'client-project'
agyist --instance client-project ~/Projects/client-repo

# Create and bind an instance profile to a specific account
python3 lib/migrator.py --create-instance client-work --bind-account 2

# List configured multi-instance profiles
agyist --instances
```

### 4. Cockpit Health Doctor & Auto-Repair (`--doctor` / `--repair-cockpit`)
Diagnose and repair common Cockpit Tools lockups, stale files, and broken paths:
```bash
agyist --doctor
```
- Safely removes stale `config.json.lock` and `.cockpit-token-locks/*`.
- Detects and cleans up orphaned `server.json` pointing to dead process IDs.
- Verifies and auto-repairs `antigravity_app_path` in `config.json` to the latest valid executable.
- Ensures required directory signatures (`bin/antigravity-ide`) exist.

### 5. Encrypted Account Export & Import (`--export-accounts` / `--import-accounts`)
Transfer or backup all saved Cockpit accounts using industry-standard **PBKDF2-HMAC-SHA256 (100,000 iterations) + AES-256-GCM**:
```bash
# Export all saved accounts to a password-encrypted archive (0600 permissions)
agyist --export-accounts ~/antigravity-accounts-backup.agyacc

# Import and re-encrypt accounts into a new workstation's Cockpit Tools
agyist --import-accounts ~/antigravity-accounts-backup.agyacc
```

### 6. Zero-Root Discovery & Integration Setup
```bash
agyist --cockpit ide       # Launch Antigravity IDE (v2.5.5) on account switch
agyist --cockpit desktop   # Launch Antigravity 2.0 Desktop on account switch
agyist --cockpit both      # Unified mode (keeps both applications synchronized)
agyist --restart-cockpit   # Restart running Cockpit Tools daemon to reload configurations
agyist --account           # Verify active credentials in IDE, Desktop 2.0 & Cockpit
```

### 7. Real-Time Auto-Sync Watcher
```bash
agyist --watch             # Run real-time state & account watcher in foreground
agyist --setup-watch       # Install background systemd user daemon (starts on boot)
agyist --remove-watch      # Disable and remove background service
```

---

## CLI Command Reference

| Command / Flag | Description |
|---|---|
| `agyist` | Launch the interactive TUI menu |
| `agyist --ide` | Install / update Antigravity IDE |
| `agyist --desktop` | Install / update Antigravity 2.0 Desktop app |
| `agyist --all` | Install / update both applications |
| `agyist --upgrade` | One-click upgrade for all installed components (auto self-updates agyist first) |
| `agyist --self-update` | Update agyist CLI suite itself from remote GitHub repository |
| `agyist --check-update` | Check for updates (exit `0`: up to date, `10`: update available) |
| `agyist --sync` | Bi-directionally synchronize chats, brains & state (2.0 <-> IDE) |
| `agyist --switch [target]` | Instant account switcher (index, email, or interactive selection) |
| `agyist --accounts` | List saved Cockpit accounts with real-time token health countdown |
| `agyist --instance <name> [path]` | Launch isolated Antigravity profile (separate user-data-dir & account) |
| `agyist --instances` | List configured multi-instance isolated profiles |
| `agyist --doctor`, `--repair-cockpit` | Health doctor to clean stale locks, dead PIDs, and align paths |
| `agyist --export-accounts [file]` | Password-encrypted archive export (PBKDF2 + AES-256-GCM) |
| `agyist --import-accounts <file>` | Import and re-encrypt saved accounts from .agyacc archive |
| `agyist --bundle [file]` | Generate standalone offline deployment bundle for office machines |
| `agyist --setup-autoupdate` | Configure automated daily/weekly background updates (systemd/cron) |
| `agyist --remove-autoupdate` | Disable automated background updates |
| `agyist --account` | Inspect active account in IDE, Desktop 2.0 & Cockpit Tools |
| `agyist --watch` | Run real-time state & account switch watcher daemon |
| `agyist --setup-watch` | Configure background systemd user service for auto-sync on boot |
| `agyist --remove-watch` | Disable and remove background auto-sync service |
| `agyist --desktop-entry` | Install Linux desktop launchers & URL protocol handlers (`antigravity://`) |
| `agyist --cockpit [target]` | Configure Cockpit Tools launch path (`ide`, `desktop`, or `both`) |
| `agyist --restart-cockpit` | Restart running Cockpit Tools daemon to reload configurations |
| `agyist --diagnose-cockpit` | Diagnose Cockpit Tools path configuration and status |
| `agyist --status [--json]` | Display installed versions, paths, and brain/chat sync status |
| `agyist --backup [file]` | Create a complete backup of brains, chats, memory, and settings |
| `agyist --import <file>` | Restore / import brains, chats, and settings from a backup archive |
| `agyist --migrate` | Migrate data between legacy Antigravity and Antigravity IDE |
| `agyist --target-dir <path>` | Specify custom installation directory |
| `agyist --user` | Install into user space (`~/.local/share/` and `~/.local/bin/`) |
| `agyist --system` | Install system-wide (`/opt/` and `/usr/local/bin/`) |
| `agyist -q, --quiet` | Quiet mode (suppress banners and progress messages) |
| `agyist -y, --yes` | Unattended mode (assume yes to all prompts) |
| `agyist --uninstall` | Cleanly remove installed binaries, launchers, and desktop entries |

---

## Chat & Brain Memory Management

Antigravity stores its AI agent context, conversation trajectories, and knowledge in specific local directories:
- **Agent Brains & Transcripts**: `~/.gemini/antigravity/brain/` and `~/.gemini/antigravity-ide/brain/`
- **Conversation Logs & History**: `~/.gemini/antigravity/conversations/`
- **Knowledge Base**: `~/.gemini/antigravity/knowledge/`
- **IDE Global State**: `~/.config/Antigravity IDE/User/globalStorage/state.vscdb`
- **Desktop 2.0 Global State**: `~/.config/Antigravity/User/globalStorage/state.vscdb`
- **User Settings & Keybindings**: `~/.config/Antigravity IDE/User/settings.json`

### Bi-Directional Synchronization
Synchronizes conversation notification threads and agent brains so discussions started in Antigravity 2.0 can be continued seamlessly inside Antigravity IDE and vice-versa:
```bash
./agyist --sync
```

### Creating a Snapshot Backup
```bash
./agyist --backup ~/antigravity-backup.tar.gz
```

### Restoring on Another Machine
```bash
./agyist --import ~/antigravity-backup.tar.gz
```

---

## Architecture

```
agyist/
├── install.sh                  # Bootstrap script for curl-to-bash
├── agyist                      # Main unified CLI & TUI entry point
├── lib/
│   ├── common.sh              # Terminal styling, colors, arch & path detection
│   ├── resolver.sh            # Pure native Bash scraper for official Google releases
│   ├── resolver.py            # Python scraper & URL validation fallback
│   ├── installer.sh           # Extraction, sandbox permissions, rollback logic
│   ├── desktop.sh             # Desktop entry, icon installation, MIME registration
│   ├── fleet.sh               # Fleet offline bundles, systemd autoupdate, unattended mode
│   ├── migrator.py            # Brain, chat, state.vscdb & protobuf sync engine
│   ├── backup.sh              # Backup, restore & sync CLI integration
│   ├── cockpit.sh             # Cockpit Tools account switcher & path bridge
│   ├── watcher.sh             # Real-time state watcher & systemd sync daemon
│   ├── tui.sh                 # Interactive terminal UI wizard
│   └── nautilus.py            # GNOME Files / Nautilus right-click integration
├── assets/
│   └── icons/                 # Authentic 256px, 512px, vector SVG, and brand icons
├── tests/
│   ├── test_installer_local.sh# End-to-end component verification script
│   ├── test_migrator.py       # Unit tests for protobuf & database merging
│   ├── test_sync_bidirectional.py # Tests for bidirectional chat & storage sync
│   └── test_backup_roundtrip.py # Backup archive round-trip verification
├── README.md                   # Documentation
└── LICENSE                     # MIT License
```

---

## License

Released under the [MIT License](LICENSE).
