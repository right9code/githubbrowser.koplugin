# Github Browser — Git Client & Markdown Editor for KOReader

| Home Screen | Repository Browser |
|:-------------------------:|:-------------------------:|
| ![](screenshot_home.png) | ![](screenshot_repo.png) |

A comprehensive GitHub client for KOReader that lets you browse repositories, clone repos for offline editing, commit and push changes, and edit Markdown files with a rich formatting toolbar — all directly from your e-reader.

## Features

### Dual-Mode Repository Browsing

Every repo works in two modes:

| Mode | Network | Browsing | Editing | Git Operations |
|---|---|---|---|---|
| **Remote-Only** | Required | GitHub REST API | API commit (with token) | None |
| **Attached (Cloned)** | Optional | Local filesystem | Local editor | Full (commit, push, pull, sync) |

- **Remote-Only**: Browse any GitHub repo via API. View files, download, edit via API. No local storage used.
- **Attach to Device**: Clone a repo locally. Browse, edit, and commit fully offline. Sync when online.

### Git Operations

- **Clone**: Clone a remote repo to your device (optionally shallow with `--depth 1`)
- **Pull**: Fetch and fast-forward merge remote changes
- **Commit**: Stage all changes and commit with a message prompt
- **Push**: Send local commits to GitHub
- **Sync**: One-tap pull then push (bidirectional reconciliation)
- **Status**: View modified, untracked, and staged files
- **Log**: Browse recent commit history
- **Diff**: View uncommitted changes as a unified diff
- **Branch**: View current branch, list branches, switch branches
- **Detach**: Remove local clone while keeping the remote bookmark

### Smart Sync

When opening an attached repo while online, Github Browser automatically checks for remote changes:

- **Remote ahead**: Shows "N remote changes" banner with a Pull button
- **Local ahead**: Shows "N local commits ready to push" banner
- **Diverged**: Warns about conflict, offers manual resolution
- **Up to date**: No prompt needed

The **Recent Changes** view shows remote changes, uncommitted local changes, and unpushed commits in one screen.

### Enhanced Markdown Editor

A 2-row formatting toolbar pinned at the bottom of the editor, above the virtual keyboard:

```
Row 1 (Formatting): H# | B | I | S | - | 1. | [ ] | > | ` | ``` | Lnk | Tbl
Row 2 (Navigation): Tab | S+Tab | Undo | Redo | Home | End | up | down
```

| Button | Action |
|---|---|
| **H#** | Heading cycle: tap adds `#` at line start (up to `#####`), 6th tap removes all |
| **B / I / S** | Bold, Italic, Strikethrough (wraps selection) |
| **- / 1. / [ ]** | Bullet list, numbered list (auto-increment), checkbox |
| **> / ` / ```** | Blockquote, inline code, code block |
| **Lnk / Tbl** | Link template, table insertion (prompt for dimensions) |
| **Tab / S+Tab** | Indent (insert spaces) / Outdent (remove leading spaces) |
| **Undo / Redo** | Full undo/redo stack (KOReader's built-in editor has none) |
| **Home / End** | Jump to start/end of line |
| **up / down** | Move cursor between lines |

### Token Management

- Store multiple GitHub Personal Access Tokens with named labels
- Set a global default token
- Assign specific tokens to individual repositories
- Import tokens from a `.txt` file (one per line)
- Write operations (edit, delete, push) only appear when a token is explicitly assigned to that repo

### File Operations

- **View**: Fetch and display text/code files inline (remote) or from disk (local)
- **File Preview**: Files open in a preview view first with Edit Remote, Edit Locally, and Download action buttons
- **Edit via API**: Edit remote files directly on GitHub (requires token)
- **Edit Locally**: Download a remote file to disk, edit with the full toolbar, push later
- **Commit to GitHub**: From the local editor, push changes directly via API
- **Download**: Save binary files to device storage
- **Create / Delete**: Add or remove files (requires token for remote, works directly on local)
- **New File**: Create new files in attached repos directly from the repo view
- **Search**: Search files by name or code content within a repository

### Navigation & Organization

- **Pinned Repos**: Quick-access repos on the home screen
- **Bookmarks**: Save favorite repos
- **History**: Track recently visited repos with configurable limit
- **Local Repos**: All attached repos with sync status indicators
- **Add Local Folder**: Attach any folder on your device (git repo or plain folder) — browse and edit files from the home screen
- **Multiple Quick Repos**: Assign multiple repos as gesture shortcuts, each with its own dedicated gesture
- **DocumentRegistry**: Opens `.md`, `.markdown`, `.txt` files from KOReader's file manager

### Ignore System

- `.sdr` folders are automatically excluded from all listings and git operations
- Configurable ignore patterns (`.koreader`, `*.tmp`, `.DS_Store` added by default)
- `.git` directory always hidden from browsing

### Network Awareness

All network operations automatically check connectivity:

- **Opening a remote repo**: Prompts WiFi if offline
- **Pull / Push / Sync / Clone**: Prompts WiFi if offline
- **Local browsing & editing**: Works fully offline, no WiFi needed
- **Edit Locally flow**: Downloads file (needs network), then edits fully offline

## Installation

1. Copy the `githubbrowser.koplugin` folder to your KOReader `plugins/` directory:
   - **Kobo**: `/mnt/onboard/.adds/koreader/plugins/`
   - **Kindle**: `/mnt/us/koreader/plugins/`
   - **Android**: Wherever your KOReader data directory is located.
   - **Desktop (AppImage)**: `~/.config/koreader/plugins/`
2. Restart KOReader.
3. The plugin will appear in the **Search** menu (4th column in the top menu).

## Quick Start

### Browse a Public Repo

1. Open GitNotes from **Search > Github Browser**
2. Tap **Browse public repo...**
3. Enter `owner/repo` or a full GitHub URL
4. Navigate directories, tap files to view or download

### Clone and Edit Offline

1. Browse a remote repo
2. Tap **Attach to device** at the top of the repo view
3. The repo is cloned locally and appears under **Local Repos** on the home screen
4. Open it anytime — works fully offline
5. Edit files with the toolbar, commit locally
6. When online: tap **Push** or **Sync** to send changes to GitHub

### Edit a Remote File Directly

1. Browse a remote repo
2. Tap a text file
3. Tap **Edit** (requires token assigned to the repo) — commits via API
4. Or tap **Edit Locally** (no token needed) — downloads and opens in local editor

### Set Up a Gesture Shortcut

1. Go to KOReader **Settings > Gestures**
2. Find **Github Browser** in the action list to open the home screen
3. Or find **Github Browser: Quick Repo** to jump directly to a specific repo
4. To configure Quick Repo: Settings > **Quick Repo (gesture shortcut)** > enter `owner/repo`

## Settings

| Setting | Description |
|---|---|
| **Manage GitHub Tokens** | Add, rename, delete, or import tokens. Set a default token. |
| **Download Folder** | Where downloaded files are saved |
| **Git Workspace** | Root directory for cloned repos |
| **Device Name** | Tag in commit messages (e.g., "koreader", "libra2") |
| **Auto-sync on open** | Check for remote changes when opening a local repo |
| **Max history entries** | Limit how many recent repos are tracked (default: 20) |
| **Ignore Patterns** | Files/folders to hide from listings |
| **Quick Repo** | A repo opened by the "Quick Repo" gesture shortcut |

## Getting a GitHub Token

1. Go to [github.com/settings/tokens](https://github.com/settings/tokens)
2. Click **Generate new token (classic)**
3. Select **repo** scope (full control of private repositories)
4. Copy the token
5. In Github Browser: Settings > Manage GitHub Tokens > Add New Token

## File Structure

```
githubbrowser.koplugin/
├── _meta.lua                      # Plugin metadata
├── main.lua                       # Entry point, menu & gesture registration
├── githubbrowser_api.lua          # GitHub REST API client (remote-only mode)
├── githubbrowser_git.lua          # Local Git CLI wrapper (clone/pull/push/commit)
├── githubbrowser_sync.lua         # Smart sync engine (reconcile local ↔ remote)
├── githubbrowser_browser.lua      # Unified browsing UI (remote + local + sync)
├── githubbrowser_editor.lua       # Enhanced editor (InputDialog + toolbar + undo)
├── githubbrowser_editor_toolbar.lua # 2-row formatting toolbar widget
├── githubbrowser_undo.lua         # Undo/redo stack implementation
├── githubbrowser_settings.lua     # Settings, tokens, repo registry
├── githubbrowser_ignore.lua       # Ignore pattern matching engine
└── GUIDE.md                       # Detailed user guide
```

## Requirements

- KOReader 2024.01 or later
- `git` CLI installed on the device (for local repo features; remote browsing works without it)
- Network connection for remote browsing, cloning, and pushing
- GitHub Personal Access Token for private repos and write operations

---

**Author**: right9code
**Version**: 2.0.0
**License**: [Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/)
