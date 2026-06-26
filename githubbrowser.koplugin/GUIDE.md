# GitNotes — User Guide

A combined Git client and Markdown editor for KOReader.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Home Screen](#2-home-screen)
3. [Browsing Remote Repos (Online)](#3-browsing-remote-repos-online)
4. [Cloning & Local Repos (Offline)](#4-cloning--local-repos-offline)
5. [Editing Files](#5-editing-files)
6. [Git Operations](#6-git-operations)
7. [Smart Sync](#7-smart-sync)
8. [Token Management](#8-token-management)
9. [Settings](#9-settings)
10. [Editor Toolbar Reference](#10-editor-toolbar-reference)
11. [Ignore System](#11-ignore-system)
12. [Common Workflows](#12-common-workflows)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Getting Started

### Opening GitNotes

**From the menu:** Top menu → **Search** → **GitNotes**

**From a gesture:** Settings → Gestures → assign "GitNotes" to any gesture

**From file manager:** Tap any `.md`, `.markdown`, or `.txt` file → opens in GitNotes editor

### First-time Setup

1. Open GitNotes → **Settings** → **Device Name** → set your device name (used in commit messages)
2. **Settings** → **Git Workspace** → choose where repos are cloned (default: `gitnotes/git_repos/`)
3. If you want to access private repos or push changes: **Settings** → **Manage GitHub Tokens** → add a token

---

## 2. Home Screen

```
GitNotes
├── 🔓 Browse public repo...        ← Browse any public GitHub repo
├── 🔐 Browse private repo...       ← Browse with token authentication
├── ⚡ owner/repo                    ← Quick access to last visited
├── ── Local Repos ──                ← Cloned repos with sync status
│   ├── 📁 my-notes
│   └── 📁 website
├── ── Pinned ──                     ← Pinned for quick access
│   └── 📌 owner/repo
├── 🔖 Bookmarks (N)                 ← Saved repos
├── 📜 History (N)                   ← Recently visited
├── ⚙️ Settings
└── ℹ️ About
```

---

## 3. Browsing Remote Repos (Online)

### Opening a Repo

1. Tap **Browse public repo** (or **Browse private repo** for authenticated access)
2. Enter `owner/repo` or a full GitHub URL like `https://github.com/owner/repo`
3. The repo opens showing its file tree

### Navigating

- **Tap a folder** → enter it
- **Tap ".."** → go up one level
- **Tap "◂ Back"** → return to home screen

### Viewing Files

- **Tap a text file** (`.md`, `.lua`, `.py`, `.js`, etc.) → fetches and displays content
- **Tap a binary file** (`.pdf`, `.epub`, `.zip`) → offers download

### Editing Remote Files

When viewing a text file, you'll see buttons at the bottom:

- **Edit** — Edit via GitHub API (requires explicit token assignment). Changes commit directly to GitHub.
- **Edit Locally** — Download the file to your device and open in the local editor. No token needed. Save locally, commit/push later.
- **Download** — Save the file to your download folder

### Repo Actions (at the top of the repo view)

- **☆ Bookmark** — Save this repo for quick access
- **📌 Pin to Home** — Add to the pinned section on the home screen
- **🔑 Change Token** — Assign a GitHub token for this repo
- **🔍 Search files** — Find files by name
- **🔎 Search code** — Search inside file contents
- **📥 Attach to device** — Clone the repo for offline use

### Long-press Actions

- **Long-press a file** → Download (if no token) or Delete (if token assigned)
- **Long-press a folder** → Delete (if token assigned)

---

## 4. Cloning & Local Repos (Offline)

### Attaching (Cloning) a Repo

From a remote repo view, tap **📥 Attach to device**:

1. The repo is cloned to your Git Workspace directory
2. The repo now appears in the **Local Repos** section on the home screen
3. You can now browse, edit, and commit **completely offline**

### Opening a Local Repo

From the home screen, tap a repo under **Local Repos**. The view shows:

```
local: my-repo [main]
├── ◂ Back
├── ☆ Bookmark
├── 📥 Pull                    ← Fetch + merge remote changes
├── 📤 Push                    ← Send local commits to GitHub
├── 🔄 Sync                    ← Pull then push (bidirectional)
├── 📝 Commit                  ← Commit staged changes
├── 📜 Recent Changes          ← See remote/local diffs
├── 🔍 Search files
├── 🔑 Change Token
├── 📴 Detach local copy       ← Remove local clone (keeps bookmark)
├── ────────────────────
├── 📁 src/
├── 📄 notes.md
└── 📄 config.json
```

### Browsing Local Files

- **Tap a text file** → opens in the enhanced editor with toolbar
- **Tap a binary file** → offers copy to download folder
- **Long-press a file** → Delete option

### Detaching

Tap **📴 Detach local copy** to remove the local clone. The repo stays in your bookmarks/history as a remote-only entry. You can re-attach anytime.

---

## 5. Editing Files

### Local Editor

When you open a text file from a local repo (or via "Edit Locally" from a remote view):

1. The file opens in a **fullscreen editor** with:
   - Built-in navigation bar (Home/End/Up/Down/Find/GoToLine)
   - **Formatting toolbar** at the bottom (2 rows)
   - Virtual keyboard
2. Edit freely using the toolbar buttons
3. **Save** → writes to disk (Save button in the InputDialog nav bar)
4. **Close** → if unsaved changes, asks Save/Discard/Cancel

### Remote Editor (API Edit)

When you tap **Edit** on a remote file (requires explicit token):

1. Same fullscreen editor with toolbar
2. **💾 Commit** → prompts for commit message → pushes to GitHub via API
3. No local file is created — changes go directly to GitHub

### "Edit Locally" Workflow

When you tap **Edit Locally** on a remote file:

1. File is downloaded to your device:
   - If repo is attached → saved into the local repo at the same path
   - If repo is not attached → saved to your download folder
2. Opens in the local editor
3. Edit → Save → the file is now on your device
4. If saved into an attached repo: go to the local repo → Commit → Push

---

## 6. Git Operations

All git operations are available from the local repo view menu.

### Commit

1. Edit files and save them
2. Go back to the repo view → tap **📝 Commit**
3. Enter a commit message
4. Tap **Commit** — all changes are staged and committed locally

### Push

- Tap **📤 Push** → sends all local commits to GitHub
- Requires a token assigned to the repo

### Pull

- Tap **📥 Pull** → fetches and merges remote changes (fast-forward only)
- Warns if there are conflicts (does not auto-merge)

### Sync

- Tap **🔄 Sync** → does Pull then Push in one operation
- Handles all three cases:
  - Remote ahead → pulls first, then pushes if local has commits
  - Local ahead → pushes
  - Up to date → reports "Already up to date"
  - Diverged → reports error, manual resolution needed

### Recent Changes

Tap **📜 Recent Changes** to see:

```
Recent Changes — owner/repo
├── Remote (new)         ← Commits on GitHub not yet pulled
│   ├── abc1234 Fix typo           (2h ago)
│   └── def5678 Add section        (1d ago)
├── Uncommitted          ← Modified files not yet committed
│   ├── M  notes.md
│   └── A  draft.md
├── Unpushed             ← Local commits not yet pushed
│   └── xyz7890 WIP chapter 3
├── [Pull] [Push] [View Diff] [Git Log]
```

### View Diff

From Recent Changes → tap **View Diff** → see unified diff of uncommitted changes

### Git Log

From Recent Changes → tap **Git Log** → see last 20 commits with hash, message, author, date

---

## 7. Smart Sync

### Auto-sync on Open

When enabled in Settings, GitNotes automatically checks for remote changes when you open a local repo. If changes are detected, a banner appears at the top:

- **"N remote changes (tap to pull)"** — tap to pull
- **"Local commits ready to push"** — tap to view Recent Changes

### Manual Sync

Use **🔄 Sync** from the repo menu for explicit bidirectional sync.

### Sync Status on Home Screen

The **Local Repos** section shows sync indicators:

- No indicator = up to date
- "N behind" = remote has new commits
- "N ahead" = local has unpushed commits

---

## 8. Token Management

### Adding a Token

1. Settings → **Manage GitHub Tokens** → **Add New Token**
2. Paste your GitHub Personal Access Token (starts with `ghp_` or `github_pat_`)
3. Give it a name (e.g., "Work", "Personal")

### Getting a GitHub Token

1. Go to [github.com/settings/tokens](https://github.com/settings/tokens)
2. Click **Generate new token (classic)**
3. Select **repo** scope (full control of private repositories)
4. Copy the token

### Setting a Default Token

Settings → Manage GitHub Tokens → **Set Default Token** → pick one

The default token is used for all repos that don't have a specific token assigned.

### Per-Repo Token Assignment

From a repo view → tap **🔑 Change Token** → select which token to use for this repo.

**Important:** Write operations (Edit, Delete, New file, Push) on remote repos only appear when a token is **explicitly assigned** to that repo (not just the default token).

### Importing Tokens from File

1. Create a `.txt` file with one token per line:
   ```
   ghp_abc123...
   ghp_def456...
   ```
2. Settings → Manage GitHub Tokens → **Import from file**
3. Browse to the file → name each token as prompted

---

## 9. Settings

| Setting | Description |
|---|---|
| **Manage GitHub Tokens** | Add, rename, delete, import tokens. Set default. |
| **Download Folder** | Where downloaded files are saved |
| **Git Workspace** | Root directory for cloned repos |
| **Device Name** | Tag in commit messages (e.g., "koreader", "libra2") |
| **Auto-sync on open** | Check for remote changes when opening a local repo |
| **Ignore Patterns** | Files/folders to hide from listings (`.sdr` is always ignored) |
| **Quick Repo** | A repo (`owner/repo`) opened by the "GitNotes: Quick Repo" gesture |

---

## 10. Editor Toolbar Reference

The toolbar has 2 rows, pinned at the bottom above the keyboard:

```
┌──────────────────────────────────────────────────┐
│ H# │ B │ I │ S │ - │1. │[ ]│ > │`  │```│Lnk│Tbl│  Row 1: Formatting
├──────────────────────────────────────────────────┤
│ Tab │S+Tab│ Undo │ Redo │ Home │ End │ ↑ │ ↓   │  Row 2: Navigation
├──────────────────────────────────────────────────┤
│                 Virtual Keyboard                 │
└──────────────────────────────────────────────────┘
```

### Row 1 — Formatting

| Button | Action | Details |
|---|---|---|
| **H#** | Heading | Tap once: `# `, twice: `## `, up to `##### `. 6th tap: removes all `#` |
| **B** | Bold | Wraps selection in `**` or inserts `**|**` |
| **I** | Italic | Wraps selection in `*` or inserts `*|*` |
| **S** | Strikethrough | Wraps selection in `~~` |
| **-** | Bullet list | Inserts `- ` at line start |
| **1.** | Numbered list | Auto-increments from previous number |
| **[ ]** | Checkbox | Inserts `- [ ] ` |
| **>** | Blockquote | Inserts `> ` at line start |
| **`** | Inline code | Wraps selection in backtick |
| **```** | Code block | Wraps selection in triple backticks |
| **Lnk** | Link | Inserts `[text](url)` |
| **Tbl** | Table | Prompts for columns × rows, inserts Markdown table |

### Row 2 — Navigation

| Button | Action |
|---|---|
| **Tab** | Insert 4 spaces (configurable in settings) |
| **S+Tab** | Remove up to 4 leading spaces from current line |
| **Undo** | Undo last change |
| **Redo** | Redo |
| **Home** | Jump to start of line |
| **End** | Jump to end of line |
| **↑** | Move cursor up one line |
| **↓** | Move cursor down one line |

### Built-in Navigation Bar (InputDialog)

Above the toolbar, InputDialog provides:
- **Keyboard toggle** — show/hide virtual keyboard
- **Find** — search in text (case-sensitive option)
- **Go to line** — jump to line number
- **Top/Bottom** — scroll to start/end
- **Up/Down** — scroll by page

---

## 11. Ignore System

### Default Ignored Patterns

These are always hidden from file listings:
- `.git` — Git internals
- `*.sdr` — KOReader sidecar directories
- `.koreader` — KOReader config
- `*.tmp` — Temporary files
- `.DS_Store` — macOS metadata
- `Thumbs.db` — Windows thumbnails

### Custom Patterns

Settings → **Ignore Patterns** → **Add Pattern**

Examples:
- `node_modules` — JavaScript dependencies
- `*.log` — Log files
- `build` — Build output directory
- `.env` — Environment files

---

## 12. Common Workflows

### Workflow 1: Browse & Download a File

```
Home → Browse public repo → owner/repo → navigate to file → tap file → Download
```

### Workflow 2: Clone, Edit Offline, Push Later

```
Home → Browse public repo → owner/repo
  → 📥 Attach to device
  → [later] Home → Local Repos → owner/repo
  → tap file → edit with toolbar → Save
  → 📝 Commit → enter message
  → [when online] 📤 Push
```

### Workflow 3: Quick Edit a Remote File

```
Home → Browse public repo → owner/repo
  → tap file → Edit Locally
  → edit → Save → Close
  → [file saved to download folder or local repo]
```

### Workflow 4: Edit Remote File with Token

```
Home → Browse private repo → owner/repo
  → 🔑 Change Token → select token
  → tap file → Edit
  → edit → 💾 Commit → enter message
  → [changes pushed to GitHub immediately]
```

### Workflow 5: Sync a Local Repo

```
Home → Local Repos → my-repo
  → 📜 Recent Changes → see what's new
  → 🔄 Sync → pulls remote + pushes local
```

### Workflow 6: Edit a .md File from File Manager

```
KOReader file manager → navigate to notes.md → tap
  → opens in GitNotes editor with full toolbar
  → edit → Save → Close
```

### Workflow 7: Manage Multiple Repos

```
Home → Browse public repo → repo1 → 📌 Pin to Home
Home → Browse public repo → repo2 → 📌 Pin to Home
Home → [both repos now in Pinned section for quick access]
```

### Workflow 8: Edit Locally then Push to GitHub (No Clone Needed)

```
Home → Browse public repo → owner/repo
  → tap file → "Edit Locally" button
  → file downloads and opens in editor with toolbar
  → edit → "Commit to GitHub" button
  → enter commit message → pushed directly via API
```

This workflow works without cloning the repo. The file is saved locally and pushed via API in one step.

### Workflow 9: Quick Repo Gesture

1. Settings → **Quick Repo** → enter `owner/repo`
2. KOReader Settings → Gestures → assign "GitNotes: Quick Repo" to a gesture
3. Perform the gesture → jumps directly to that repo (remote or local depending on attachment)

### Workflow 10: WiFi-Aware Operations

GitNotes automatically handles WiFi:
- **Opening a remote repo** → prompts WiFi if offline
- **Pull / Push / Sync** → prompts WiFi if offline
- **Cloning** → prompts WiFi if offline
- **Local browsing & editing** → works fully offline, no WiFi needed

---

## 13. Troubleshooting

### "API rate limit exceeded"

GitHub limits unauthenticated requests to 60/hour. Add a token to increase to 5000/hour.

### "Authentication error"

Your token may be expired or invalid. Generate a new one at github.com/settings/tokens.

### "Push failed: rejected"

Remote has changes you don't have locally. Tap **📥 Pull** first, then **📤 Push**.

### "Local and remote have diverged"

Both sides have commits the other doesn't have. Options:
1. Pull (accept remote changes, your local commits stay on top)
2. Force push (overwrite remote — use carefully)
3. View diff to understand what changed

### Save button is greyed out

Make a change to the text first (type something, use a toolbar button). The Save button activates only after the content is modified.

### "Cannot read directory"

The local repo directory may have been deleted outside KOReader. The plugin will auto-detect this and fall back to remote browsing. Re-attach if needed.

### "Git is not available"

Git CLI is not installed on your device. Local repo features (clone, commit, push, pull) won't work. Remote browsing via GitHub API still works.

### Token not showing Edit button

The Edit button on remote files requires a token **explicitly assigned** to that repo (via 🔑 Change Token), not just a default token. This is intentional to prevent accidental edits on repos you only want to browse.
