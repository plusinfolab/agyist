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

## Quick Start

### 1. Interactive Terminal UI
Run without arguments to launch the wizard:
```bash
./agyist
```

### 2. Standalone & Fleet Commands
```bash
# Install Antigravity IDE in user scope (no root needed)
./agyist --ide --user

# Install Antigravity 2.0 Desktop app
./agyist --desktop --user

# Install or upgrade both applications system-wide
sudo ./agyist --all --system

# Bi-directionally synchronize chats, brains, and state between 2.0 and IDE
./agyist --sync

# Check if updates are available (exit code 10 if update available)
./agyist --check-update

# Unattended fleet upgrade of all installed components
./agyist --upgrade -y -q

# Generate a standalone offline bundle for air-gapped office PCs
./agyist --bundle ~/antigravity-office-bundle.tar.gz

# Schedule automated daily background updates via systemd user timer
./agyist --setup-autoupdate daily
```

---

## CLI Command Reference

| Command / Flag | Description |
|---|---|
| `./agyist` | Launch the interactive TUI menu |
| `./agyist --ide` | Install / update Antigravity IDE |
| `./agyist --desktop` | Install / update Antigravity 2.0 Desktop app |
| `./agyist --all` | Install / update both applications |
| `./agyist --upgrade` | One-click upgrade for all currently installed components |
| `./agyist --check-update` | Check for updates (exit `0`: up to date, `10`: update available) |
| `./agyist --sync` | Bi-directionally synchronize chats, brains & state (2.0 <-> IDE) |
| `./agyist --bundle [file]` | Generate standalone offline deployment bundle for office machines |
| `./agyist --setup-autoupdate` | Configure automated daily/weekly background updates (systemd/cron) |
| `./agyist --remove-autoupdate` | Disable automated background updates |
| `./agyist --cockpit` | Configure and fix Cockpit Tools account switcher for Antigravity IDE |
| `./agyist --diagnose-cockpit` | Diagnose Cockpit Tools path configuration and status |
| `./agyist --status [--json]` | Display installed versions, paths, and brain/chat sync status |
| `./agyist --backup [file]` | Create a complete backup of brains, chats, memory, and settings |
| `./agyist --import <file>` | Restore / import brains, chats, and settings from a backup archive |
| `./agyist --migrate` | Migrate data between legacy Antigravity and Antigravity IDE |
| `./agyist --target-dir <path>` | Specify custom installation directory |
| `./agyist --user` | Install into user space (`~/.local/share/` and `~/.local/bin/`) |
| `./agyist --system` | Install system-wide (`/opt/` and `/usr/local/bin/`) |
| `./agyist -q, --quiet` | Quiet mode (suppress banners and progress messages) |
| `./agyist -y, --yes` | Unattended mode (assume yes to all prompts) |
| `./agyist --uninstall` | Cleanly remove installed binaries, launchers, and desktop entries |

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
