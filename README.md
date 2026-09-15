# Antigravity Linux Suite (`agyist`)

```
      ___       ___           ___           ___           ___           ___     
     /\  \     /\  \         /\  \         /\__\         /\  \         /\  \    
    /::\  \   /::\  \       /::\  \       /:/  /        _\:\  \        \:\  \   
   /:/\:\  \ /:/\:\  \     /:/\:\  \     /:/  /        /\ \:\  \        \:\  \  
  /::\~\:\  \\:\~\:\  \   /::\~\:\  \   /:/  /  ___   _\:\ \:\  \       /::\  \ 
 /:/\:\ \:\__\\:\ \:\__\ /:/\:\ \:\__\ /:/__/  /\__\ /\ \:\ \:\__\     /:/\:\__\
 \/__\:\/:/  / \:\/:/  / \/__\:\/:/  / \:\  \ /:/  / \:\ \:\ \/__/    /:/  \/__/
      \::/  /   \::/  /       \::/  /   \:\  /:/  /   \:\ \:\__\     /:/  /     
      /:/  /     /:/  /       /:/  /     \:\/:/  /     \:\/:/  /     \/__/      
     /:/  /     /:/  /       /:/  /       \::/  /       \::/  /                 
     \/__/      \/__/        \/__/         \/__/         \/__/                  
```

> **The definitive Linux installer, updater, desktop integrator, and brain/chat manager for Google Antigravity 2.0 and Antigravity IDE.**

---

## Highlights

- **Interactive TUI & Non-Interactive CLI**: Launch a terminal UI menu with `./agyist` or run headless one-liners in automated scripts.
- **Both Products Supported**: Installs and updates **Antigravity IDE** (VS Code-based AI environment) and **Antigravity 2.0** (standalone desktop Electron agent app).
- **Resilient Official Google Scraper**: Dynamically parses `https://antigravity.google/download` directly from Astro HTML and fallback channels, replacing obsolete JavaScript regex patterns that broke previous community tools.
- **Bi-Directional Chat & Brain Sync (`--sync`)**: Seamless two-way synchronization between Antigravity 2.0 Desktop and Antigravity IDE. Unifies SQLite `state.vscdb` (all conversation notification threads), workspace storage, agent brains (`~/.gemini/antigravity/brain/`), conversation protobufs, and `antigravity_state.pbtxt`.
- **Office Fleet & Unattended Deployments**:
  - **Offline Deployment Bundles (`--bundle`)**: Packages official tarballs, installer, and branding assets into a self-contained archive for air-gapped or bandwidth-limited office workstations.
  - **Automated Update Timers (`--setup-autoupdate`)**: Native systemd user timer (with fallback to cron) for automated background upgrades.
  - **Scriptable Update Checker (`--check-update`)**: Automated CI/CD and cron integration returning exit code `0` (up to date) or `10` (update available).
  - **Machine-Readable Diagnostics (`--status --json`)**: Full JSON output for fleet monitoring dashboards.
- **Genuine Official Branding Assets**: High-resolution 256x256, 512x512, scalable SVG, and Google press brand assets for both Antigravity 2.0 and Antigravity IDE.
- **Resilient Official Google Scraper**: Pure native Bash scraping of `https://antigravity.google/download` directly from Astro HTML and fallback CDN release channels.
- **Dual Installation Scope**:
  - **User Scope** (`~/.local/`, non-root, container & sandbox friendly)
  - **System Scope** (`/opt/` or `/usr/share/`, with `sudo` or root)
- **Smart Existing Installation Detection**: Automatically inspects if an existing Antigravity install is present (such as `/usr/share/antigravity` or `/opt/antigravity-ide`) and targets it directly for updates.
- **Full Desktop Integration**:
  - Automatically extracts high-resolution app icons (from `code.png` or `app.asar`).
  - Generates `.desktop` entries with standard MIME associations (`inode/directory`, `text/plain`, `.workspace`).
  - High-resolution authentic icons installed in `hicolor/` (256x256, 512x512, scalable) and `pixmaps/`.
  - Generates validated `.desktop` entries with standard MIME associations (`inode/directory`, `text/plain`, `.workspace`).
  - Registers URL handlers (`x-scheme-handler/antigravity` and `antigravity-ide`).
  - GNOME Files / Nautilus right-click context menu extension.
- **One-Click Upgrades with Safe Rollback**: Replaces application directories atomically and preserves `.previous` rollback copies.
- **Comprehensive Brain, Chat & Memory Manager**:
  - **Backup (`--backup`)**: Snapshot all conversation brains (`~/.gemini/antigravity/brain/`), transcripts, knowledge, SQLite `state.vscdb`, and user configs into a lightweight `.tar.gz` bundle.
  - **Sync (`--sync`)**: Bi-directionally sync chats, brains, SQLite databases, and workspace storage across 2.0 and IDE.
  - **Backup (`--backup`)**: Snapshot all conversation brains, transcripts, knowledge, SQLite databases, and user configs into a lightweight `.tar.gz` bundle.
  - **Import (`--import`)**: Effortlessly transfer or restore memory and chats onto any Linux machine.
  - **Cross-Version Migration (`--migrate`)**: Migrates data from legacy Antigravity to Antigravity IDE, with automated protobuf concatenation for conversation trajectory summaries (`antigravityUnifiedStateSync.trajectorySummaries`).
  - **Migration (`--migrate`)**: Migrates data from legacy Antigravity to Antigravity IDE, with automated protobuf concatenation for conversation trajectory summaries.

---

## Quick Start

### 1. Interactive Mode
Run without arguments to open the interactive wizard:
```bash
./agyist
```

### 2. One-Line Installer
### 2. Fleet & Office Deployments
```bash
# Install Antigravity IDE for current user (no root required)
curl -fsSL https://raw.githubusercontent.com/username/agyist/main/install.sh | bash -s -- --ide --user
# Bi-directionally synchronize chats, brains, and state between 2.0 and IDE
./agyist --sync

# Install or upgrade both Antigravity IDE and Desktop App system-wide
curl -fsSL https://raw.githubusercontent.com/username/agyist/main/install.sh | sudo bash -s -- --all --system
# Check if updates are available (exit code 10 if update available)
./agyist --check-update

# Unattended upgrade of all installed components
./agyist --upgrade -y -q

# Generate a standalone offline bundle for air-gapped office PCs
./agyist --bundle ~/antigravity-office-bundle.tar.gz

# Schedule automated daily background updates via systemd
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
| `./agyist --upgrade` | One-click upgrade for currently installed components |
| `./agyist --status` | Display installed versions, paths, and brain/chat storage stats |
| `./agyist --upgrade` | One-click upgrade for all currently installed components |
| `./agyist --check-update` | Check for updates (exit 0: up to date, 10: update available) |
| `./agyist --sync` | Bi-directionally synchronize chats, brains & state (2.0 <-> IDE) |
| `./agyist --bundle [file]` | Generate standalone offline deployment bundle for office machines |
| `./agyist --setup-autoupdate` | Configure automated daily/weekly background updates (systemd/cron) |
| `./agyist --remove-autoupdate` | Disable automated background updates |
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
- **Agent Brains & Transcripts**: `~/.gemini/antigravity/brain/`
- **Conversation Logs & History**: `~/.gemini/antigravity/conversations/`
- **Knowledge Base**: `~/.gemini/antigravity/knowledge/`
- **IDE Global State**: `~/.config/Antigravity IDE/User/globalStorage/state.vscdb`
- **User Settings**: `~/.config/Antigravity IDE/User/settings.json`

### Creating a Snapshot Backup
```bash
agyist --backup ~/antigravity-backup.tar.gz
```

### Restoring on Another Machine
```bash
agyist --import ~/antigravity-backup.tar.gz
```

### Migrating Between Versions
When migrating from legacy Antigravity 2.0 to Antigravity IDE, SQLite `state.vscdb` stores conversation histories as Base64-encoded Protobuf payloads. `agyist` decodes the protobuf streams, concatenates repeated history fields cleanly, and re-encodes them so your conversation history stays intact without corruption.
```bash
agyist --migrate
```

---

## Architecture

```
agyist/
├── install.sh                  # Bootstrap script for curl-to-bash
├── agyist                      # Main unified CLI & TUI entry point
├── lib/
│   ├── common.sh              # Terminal styling, colors, arch & path detection
│   ├── resolver.py            # Google download URL & version scraper
│   ├── resolver.sh            # Pure native Bash scraper for official Google releases
│   ├── resolver.py            # Python scraper & URL validation fallback
│   ├── installer.sh           # Extraction, sandbox permissions, rollback logic
│   ├── desktop.sh             # Desktop entry, icon extraction, MIME registration
│   ├── migrator.py            # Brain, chat, state.vscdb & protobuf migrator
│   ├── backup.sh              # Backup & restore CLI integration
│   ├── desktop.sh             # Desktop entry, icon installation, MIME registration
│   ├── fleet.sh               # Fleet offline bundles, systemd autoupdate, unattended mode
│   ├── migrator.py            # Brain, chat, state.vscdb & protobuf sync engine
│   ├── backup.sh              # Backup, restore & sync CLI integration
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

