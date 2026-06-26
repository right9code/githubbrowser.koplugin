local Menu         = require("ui/widget/menu")
local Font         = require("ui/font")
local InputDialog  = require("ui/widget/inputdialog")
local TextViewer   = require("ui/widget/textviewer")
local InfoMessage  = require("ui/widget/infomessage")
local ConfirmBox   = require("ui/widget/confirmbox")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager    = require("ui/uimanager")
local NetworkMgr   = require("ui/network/manager")
local Screen       = require("device").screen
local lfs          = require("libs/libkoreader-lfs")
local logger       = require("logger")
local _            = require("gettext")

local GitNotesAPI      = require("githubbrowser_api")
local GitNotesSettings = require("githubbrowser_settings")
local GitOps           = require("githubbrowser_git")
local SyncEngine       = require("githubbrowser_sync")
local IgnoreEngine     = require("githubbrowser_ignore")
local Editor           = require("githubbrowser_editor")

-- ── Helpers ───────────────────────────────────────────────────────────────────

local OPENABLE_EXT = {
    epub=true, pdf=true, djvu=true, cbz=true, cbr=true, fb2=true,
    mobi=true, azw=true, azw3=true, txt=true, html=true, htm=true,
    zip=true, doc=true, docx=true, rtf=true,
}

local TEXT_EXT = {
    lua=true, py=true, js=true, ts=true, c=true, cpp=true, h=true,
    java=true, go=true, rs=true, sh=true, bash=true, md=true,
    markdown=true, json=true, yaml=true, yml=true, toml=true,
    ini=true, cfg=true, conf=true, xml=true, csv=true, txt=true,
    html=true, htm=true, css=true, rb=true, php=true, pl=true,
    swift=true, kt=true, r=true, tex=true, sql=true, diff=true,
    patch=true, gitignore=true, dockerfile=true, makefile=true,
}

local function getExt(name)
    return (name:match("%.([^%.]+)$") or ""):lower()
end

local function isTextFile(name)
    local ext = getExt(name)
    return TEXT_EXT[ext] or ext == ""
end

local function ensureDir(p)
    if not lfs.attributes(p, "mode") then lfs.mkdir(p) end
end

local function loadOrShow(path)
    return lfs.attributes(path, "mode") ~= nil
end

-- ── Menu subclass ─────────────────────────────────────────────────────────────

local BrowserMenu = Menu:extend{
    covers_fullscreen = true,
    is_borderless     = true,
    is_popout         = false,
}

function BrowserMenu:onMenuSelect(item)
    if item.callback then item.callback(self); return true end
end

function BrowserMenu:onMenuHold(item)
    if item.hold_callback then item.hold_callback(self); return true end
end

function BrowserMenu:onReturn()
    UIManager:close(self)
    if self.on_close then self.on_close() end
    return true
end

-- ── BrowserUI ─────────────────────────────────────────────────────────────────

local BrowserUI = {}

-- ── Home Screen ───────────────────────────────────────────────────────────────

function BrowserUI.showHome()
    local function refresh_home()
        if BrowserUI._home_menu then UIManager:close(BrowserUI._home_menu) end
        BrowserUI.showHome()
    end

    local recent = GitNotesSettings.getRecentRepos()
    local items  = {}

    table.insert(items, {
        text = _("\u{E647} Browse public repo..."),
        callback = function() BrowserUI.showRepoInputDialog(refresh_home, false) end,
    })
    table.insert(items, {
        text = _("\u{E636} Browse private repo..."),
        callback = function() BrowserUI.showRepoInputDialog(refresh_home, true) end,
    })

    if #recent > 0 then
        local last = recent[1]
        table.insert(items, {
            text = "\u{EDAE} " .. last,
            mandatory = _("recent"),
            callback = function()
                local owner, repo = last:match("^([^/]+)/(.+)$")
                if owner then BrowserUI.openRepo(owner, repo, nil, nil, refresh_home) end
            end,
        })
    end

    -- Local repos
    local attached = GitNotesSettings.getAttachedRepos()
    if #attached > 0 then
        table.insert(items, {
            text = "── " .. _("Local Repos") .. " ──",
            callback = function() end,
        })
        for _, info in ipairs(attached) do
            table.insert(items, {
                text = "\u{E94A} " .. info.full_name,
                mandatory = info.branch or "",
                callback = function()
                    local owner, repo = info.full_name:match("^([^/]+)/(.+)$")
                    if owner then BrowserUI.openRepo(owner, repo, nil, nil, refresh_home) end
                end,
            })
        end
    end

    -- Pinned
    local pinned = GitNotesSettings.getPinnedRepos()
    if #pinned > 0 then
        table.insert(items, {
            text = "── " .. _("Pinned") .. " ──",
            callback = function() end,
        })
        for _, full_name in ipairs(pinned) do
            table.insert(items, {
                text = "\u{EB02} " .. full_name,
                callback = function()
                    local owner, repo = full_name:match("^([^/]+)/(.+)$")
                    if owner then BrowserUI.openRepo(owner, repo, nil, nil, refresh_home) end
                end,
                hold_callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = string.format(_("Unpin \"%s\"?"), full_name),
                        ok_text = _("Unpin"),
                        ok_callback = function()
                            GitNotesSettings.removePinnedRepo(full_name)
                            UIManager:show(InfoMessage:new{ text = _("Unpinned."), timeout = 2 })
                            BrowserUI.showHome()
                        end,
                    })
                end,
            })
        end
    end

    table.insert(items, {
        text = _("\u{EBCD} Bookmarks"),
        mandatory = tostring(#GitNotesSettings.getSavedRepos()),
        callback = function() BrowserUI.showBookmarks(refresh_home) end,
    })
    table.insert(items, {
        text = _("\u{F017} History"),
        mandatory = tostring(#recent),
        callback = function() BrowserUI.showHistory(refresh_home) end,
    })
    table.insert(items, {
        text = _("\u{E615} Settings"),
        callback = function() BrowserUI.showSettings(refresh_home) end,
    })
    table.insert(items, {
        text = _("\u{E9FB} About"),
        callback = function() BrowserUI.showAbout() end,
    })

    local menu = BrowserMenu:new{ title = _("GitNotes"), item_table = items }
    BrowserUI._home_menu = menu
    UIManager:show(menu)
end

-- ── About ─────────────────────────────────────────────────────────────────────

function BrowserUI.showAbout()
    UIManager:show(TextViewer:new{
        title = _("About GitNotes"),
        text = _("Version: 1.0\n") ..
            _("Author: right9code\n\n") ..
            _("A combined Git client and Markdown editor for KOReader.\n\n") ..
            _("Features:\n") ..
            _("• Browse & edit GitHub repos (remote API or local clone)\n") ..
            _("• Clone repos for offline editing\n") ..
            _("• Pull, commit, push from your e-reader\n") ..
            _("• Smart sync detects local vs remote changes\n") ..
            _("• Enhanced Markdown editor with toolbar\n\n") ..
            _("GitHub:\nhttps://github.com/right9code/githubbrowser"),
        height = math.floor(Screen:getHeight() * 0.6),
    })
end

-- ── Bookmarks ─────────────────────────────────────────────────────────────────

function BrowserUI.showBookmarks(on_close)
    local saved = GitNotesSettings.getSavedRepos()
    local items = {}
    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu) UIManager:close(menu); if on_close then on_close() end end,
    })
    if #saved == 0 then
        table.insert(items, { text = _("   No bookmarks yet."), callback = function() end })
    else
        for _, full_name in ipairs(saved) do
            table.insert(items, {
                text = "\u{EBCE} " .. full_name,
                callback = function()
                    local owner, repo = full_name:match("^([^/]+)/(.+)$")
                    if owner then BrowserUI.openRepo(owner, repo, nil, nil, on_close) end
                end,
                hold_callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = string.format(_("Remove \"%s\" from bookmarks?"), full_name),
                        ok_text = _("Remove"),
                        ok_callback = function()
                            GitNotesSettings.removeSavedRepo(full_name)
                            UIManager:show(InfoMessage:new{ text = _("Removed."), timeout = 2 })
                            BrowserUI.showBookmarks(on_close)
                        end,
                    })
                end,
            })
        end
        table.insert(items, {
            text = _("   Clear all bookmarks"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = string.format(_("Remove all %d bookmarks?"), #saved),
                    ok_text = _("Clear all"),
                    ok_callback = function()
                        GitNotesSettings.clearSavedRepos()
                        UIManager:show(InfoMessage:new{ text = _("All bookmarks cleared."), timeout = 2 })
                        BrowserUI.showBookmarks(on_close)
                    end,
                })
            end,
        })
    end
    UIManager:show(BrowserMenu:new{ title = _("Bookmarks"), item_table = items, on_close = on_close })
end

-- ── History ───────────────────────────────────────────────────────────────────

function BrowserUI.showHistory(on_close)
    local recent = GitNotesSettings.getRecentRepos()
    local items  = {}
    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu) UIManager:close(menu); if on_close then on_close() end end,
    })
    if #recent > 0 then
        table.insert(items, {
            text = _("   Clear history"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = string.format(_("Clear all %d history entries?"), #recent),
                    ok_text = _("Clear"),
                    ok_callback = function()
                        GitNotesSettings.clearRecentRepos()
                        UIManager:show(InfoMessage:new{ text = _("History cleared."), timeout = 2 })
                        BrowserUI.showHistory(on_close)
                    end,
                })
            end,
        })
    end
    if #recent == 0 then
        table.insert(items, { text = _("   No history yet."), callback = function() end })
    else
        for _, full_name in ipairs(recent) do
            local is_saved = GitNotesSettings.isSavedRepo(full_name)
            table.insert(items, {
                text = full_name,
                mandatory = is_saved and "\u{EBCE}" or "",
                callback = function()
                    local owner, repo = full_name:match("^([^/]+)/(.+)$")
                    if owner then BrowserUI.openRepo(owner, repo, nil, nil, on_close) end
                end,
                hold_callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = string.format(_("Remove \"%s\" from history?"), full_name),
                        ok_text = _("Remove"),
                        ok_callback = function()
                            GitNotesSettings.removeRecentRepo(full_name)
                            UIManager:show(InfoMessage:new{ text = _("Removed."), timeout = 2 })
                            BrowserUI.showHistory(on_close)
                        end,
                    })
                end,
            })
        end
    end
    UIManager:show(BrowserMenu:new{ title = _("History"), item_table = items, on_close = on_close })
end

-- ── Settings ──────────────────────────────────────────────────────────────────

function BrowserUI.showSettings(on_close)
    local items = {}
    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu) UIManager:close(menu); if on_close then on_close() end end,
    })

    table.insert(items, {
        text = _("   Manage GitHub Tokens"),
        callback = function() BrowserUI.showTokenManager(on_close) end,
    })

    local dl_dir = GitNotesSettings.getDownloadDir()
    table.insert(items, {
        text = _("   Download Folder"),
        mandatory = dl_dir,
        callback = function(menu)
            local PathChooser = require("ui/widget/pathchooser")
            local pc = PathChooser:new{
                path = G_reader_settings:readSetting("home_dir") or require("device").home_dir or "/",
                select_file = false,
                select_directory = true,
                onConfirm = function(path)
                    GitNotesSettings.setDownloadDir(path)
                    UIManager:show(InfoMessage:new{ text = _("Download folder updated."), timeout = 2 })
                    UIManager:close(menu)
                    BrowserUI.showSettings(on_close)
                end,
            }
            UIManager:show(pc)
        end,
    })

    local workspace = GitNotesSettings.getWorkspace()
    table.insert(items, {
        text = _("   Git Workspace"),
        mandatory = workspace,
        callback = function(menu)
            local PathChooser = require("ui/widget/pathchooser")
            local pc = PathChooser:new{
                path = workspace,
                select_file = false,
                select_directory = true,
                onConfirm = function(path)
                    GitNotesSettings.setWorkspace(path)
                    ensureDir(path)
                    UIManager:show(InfoMessage:new{ text = _("Workspace updated."), timeout = 2 })
                    UIManager:close(menu)
                    BrowserUI.showSettings(on_close)
                end,
            }
            UIManager:show(pc)
        end,
    })

    local device = GitNotesSettings.getDeviceName()
    table.insert(items, {
        text = _("   Device Name"),
        mandatory = device,
        callback = function(menu)
            local dlg
            dlg = InputDialog:new{
                title = _("Device Name"),
                input = device,
                buttons = {{
                    { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
                    { text = _("Save"), is_enter_default = true, callback = function()
                        local val = dlg:getInputText():match("^%s*(.-)%s*$")
                        if val == "" then val = "koreader" end
                        GitNotesSettings.setDeviceName(val)
                        UIManager:close(dlg)
                        UIManager:show(InfoMessage:new{ text = _("Saved."), timeout = 2 })
                        UIManager:close(menu)
                        BrowserUI.showSettings(on_close)
                    end },
                }},
            }
            UIManager:show(dlg)
            dlg:onShowKeyboard()
        end,
    })

    table.insert(items, {
        text = _("   Auto-sync on open"),
        mandatory = GitNotesSettings.getAutoSyncOnOpen() and _("ON") or _("OFF"),
        callback = function()
            GitNotesSettings.setAutoSyncOnOpen(not GitNotesSettings.getAutoSyncOnOpen())
            BrowserUI.showSettings(on_close)
        end,
    })

    table.insert(items, {
        text = _("   Ignore Patterns"),
        callback = function() BrowserUI.showIgnoreSettings(on_close) end,
    })

    local quick_repo = GitNotesSettings.getQuickRepo()
    table.insert(items, {
        text = _("   Quick Repo (gesture shortcut)"),
        mandatory = quick_repo ~= "" and quick_repo or _("Not set"),
        callback = function(menu)
            local dlg
            dlg = InputDialog:new{
                title = _("Quick Repo"),
                input = quick_repo,
                input_hint = _("owner/repo — opened by gesture shortcut"),
                buttons = {{
                    { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
                    { text = _("Clear"), callback = function()
                        GitNotesSettings.setQuickRepo("")
                        UIManager:close(dlg)
                        UIManager:show(InfoMessage:new{ text = _("Quick repo cleared."), timeout = 2 })
                        UIManager:close(menu)
                        BrowserUI.showSettings(on_close)
                    end },
                    { text = _("Save"), is_enter_default = true, callback = function()
                        local val = dlg:getInputText():match("^%s*(.-)%s*$")
                        GitNotesSettings.setQuickRepo(val)
                        UIManager:close(dlg)
                        UIManager:show(InfoMessage:new{ text = _("Quick repo saved."), timeout = 2 })
                        UIManager:close(menu)
                        BrowserUI.showSettings(on_close)
                    end },
                }},
            }
            UIManager:show(dlg)
            dlg:onShowKeyboard()
        end,
    })

    UIManager:show(BrowserMenu:new{ title = _("Settings"), item_table = items, on_close = on_close })
end

function BrowserUI.editRemoteFileLocally(owner, repo, path, text, branch, sha)
    local full_name = owner .. "/" .. repo
    local local_path

    -- If repo is attached, save into the local clone
    if GitNotesSettings.isAttached(full_name) then
        local repo_path = GitNotesSettings.getLocalPath(full_name)
        local_path = repo_path .. "/" .. path
        -- Ensure parent dirs exist
        local parts = {}
        for part in path:gmatch("[^/]+") do table.insert(parts, part) end
        local dir = repo_path
        for i = 1, #parts - 1 do
            dir = dir .. "/" .. parts[i]
            if not lfs.attributes(dir, "mode") then lfs.mkdir(dir) end
        end
    else
        -- Save to download folder
        local dl_dir = GitNotesSettings.getDownloadDir()
        if not lfs.attributes(dl_dir, "mode") then lfs.mkdir(dl_dir) end
        local filename = path:match("([^/]+)$") or path
        local_path = dl_dir .. "/" .. filename
    end

    local f = io.open(local_path, "wb")
    if not f then
        UIManager:show(InfoMessage:new{ text = _("Cannot write file: ") .. local_path, timeout = 4 })
        return
    end
    f:write(text)
    f:close()

    UIManager:show(InfoMessage:new{ text = _("Saved to: ") .. local_path, timeout = 2 })

    -- Open in local editor with remote origin for direct commit
    local remote_origin = {
        owner  = owner,
        repo   = repo,
        path   = path,
        branch = branch,
        sha    = sha,
    }
    Editor.openFile(local_path, nil, remote_origin)
end

function BrowserUI.showIgnoreSettings(on_close)
    local patterns = GitNotesSettings.getIgnorePatterns()
    local items = {}
    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu) UIManager:close(menu); BrowserUI.showSettings(on_close) end,
    })
    table.insert(items, {
        text = _("\u{EA08} Add Pattern"),
        callback = function()
            local dlg
            dlg = InputDialog:new{
                title = _("Add Ignore Pattern"),
                input = "",
                input_hint = _("e.g. *.log, build, node_modules"),
                buttons = {{
                    { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
                    { text = _("Add"), is_enter_default = true, callback = function()
                        local pat = dlg:getInputText():match("^%s*(.-)%s*$")
                        if pat ~= "" then
                            GitNotesSettings.addIgnorePattern(pat)
                        end
                        UIManager:close(dlg)
                        BrowserUI.showIgnoreSettings(on_close)
                    end },
                }},
            }
            UIManager:show(dlg)
            dlg:onShowKeyboard()
        end,
    })
    for _, pat in ipairs(patterns) do
        table.insert(items, {
            text = "  " .. pat,
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = string.format(_("Remove \"%s\" from ignore list?"), pat),
                    ok_text = _("Remove"),
                    ok_callback = function()
                        GitNotesSettings.removeIgnorePattern(pat)
                        BrowserUI.showIgnoreSettings(on_close)
                    end,
                })
            end,
        })
    end
    UIManager:show(BrowserMenu:new{ title = _("Ignore Patterns"), item_table = items })
end

-- ── Token Manager ─────────────────────────────────────────────────────────────

function BrowserUI.showTokenManager(on_close)
    local tokens = GitNotesSettings.getTokens()
    local default_name = GitNotesSettings.getDefaultTokenName()
    local items = {}

    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu)
            UIManager:close(menu)
            BrowserUI.showSettings(on_close)
        end,
    })

    local token_count = 0
    for _ in pairs(tokens) do token_count = token_count + 1 end

    if token_count > 0 then
        table.insert(items, {
            text = _("\u{F43D} Set Default Token"),
            mandatory = default_name or _("Not set"),
            callback = function() BrowserUI.showDefaultTokenPicker(on_close) end,
        })
    end

    table.insert(items, {
        text = _("\u{EA08} Add New Token"),
        callback = function()
            BrowserUI.promptForTokenString(nil, function() BrowserUI.showTokenManager(on_close) end)
        end,
    })

    for tname, _v in pairs(tokens) do
        local is_default = (tname == default_name)
        table.insert(items, {
            text = (is_default and "\u{EA05} " or "\u{EA0A} ") .. tname,
            mandatory = is_default and _("default") or "",
            callback = function()
                UIManager:show(BrowserMenu:new{
                    title = _("Manage: ") .. tname,
                    item_table = {
                        {
                            text = "\u{ED0B} Back",
                            callback = function(cmenu)
                                UIManager:close(cmenu)
                                BrowserUI.showTokenManager(on_close)
                            end,
                        },
                        {
                            text = _("\u{EA07} Rename"),
                            callback = function(cmenu)
                                UIManager:close(cmenu)
                                BrowserUI.promptRenameToken(tname, on_close)
                            end,
                        },
                        {
                            text = _("\u{EA09} Delete"),
                            callback = function(cmenu)
                                UIManager:close(cmenu)
                                UIManager:show(ConfirmBox:new{
                                    text = _("Delete token '") .. tname .. _("'?"),
                                    ok_text = _("Delete"),
                                    ok_callback = function()
                                        GitNotesSettings.deleteToken(tname)
                                        if tname == default_name then
                                            GitNotesSettings.setDefaultTokenName(nil)
                                        end
                                        BrowserUI.showTokenManager(on_close)
                                    end,
                                })
                            end,
                        },
                    },
                })
            end,
        })
    end

    table.insert(items, {
        text = _("\u{EA06} Import from file"),
        callback = function() BrowserUI.promptImportTokens(on_close) end,
    })

    UIManager:show(BrowserMenu:new{
        title = _("GitHub Tokens"),
        item_table = items,
        on_close = on_close and function() BrowserUI.showSettings(on_close) end or nil,
    })
end

function BrowserUI.showDefaultTokenPicker(on_close)
    local tokens = GitNotesSettings.getTokens()
    local current = GitNotesSettings.getDefaultTokenName()
    local items = {}
    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu)
            UIManager:close(menu)
            BrowserUI.showTokenManager(on_close)
        end,
    })
    for tname, _v in pairs(tokens) do
        table.insert(items, {
            text = (tname == current and "● " or "○ ") .. tname,
            mandatory = tname == current and _("current") or "",
            callback = function()
                GitNotesSettings.setDefaultTokenName(tname)
                UIManager:show(InfoMessage:new{ text = _("Default set to: ") .. tname, timeout = 2 })
                BrowserUI.showTokenManager(on_close)
            end,
        })
    end
    table.insert(items, {
        text = _("✕ Clear Default"),
        callback = function()
            GitNotesSettings.setDefaultTokenName(nil)
            UIManager:show(InfoMessage:new{ text = _("Default cleared."), timeout = 2 })
            BrowserUI.showTokenManager(on_close)
        end,
    })
    UIManager:show(BrowserMenu:new{ title = _("Set Default Token"), item_table = items })
end

function BrowserUI.promptRenameToken(old_name, on_close)
    local dlg
    dlg = InputDialog:new{
        title = _("Rename Token"),
        input = old_name,
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local new_name = dlg:getInputText():match("^%s*(.-)%s*$")
                UIManager:close(dlg)
                if new_name == "" or new_name == old_name then return end
                GitNotesSettings.renameToken(old_name, new_name)
                BrowserUI.showTokenManager(on_close)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function BrowserUI.promptImportTokens(on_close)
    local FileChooser = require("ui/widget/filechooser")
    local fc
    fc = FileChooser:new{
        path = G_reader_settings:readSetting("home_dir") or "/",
        title = _("Select Token File (.txt)"),
        onFileSelect = function(self_fc, item)
            UIManager:close(self_fc)
            BrowserUI.processTokenFile(item.path, on_close)
            return true
        end,
        onClose = function(self_fc)
            UIManager:close(self_fc)
            if on_close then on_close() end
            return true
        end,
    }
    UIManager:show(fc)
end

function BrowserUI.processTokenFile(path, on_close)
    local f = io.open(path, "r")
    if not f then
        UIManager:show(InfoMessage:new{ text = _("Could not open file:\n") .. path, timeout = 3 })
        return
    end
    local tokens = {}
    for line in f:lines() do
        local t = line:match("^%s*(.-)%s*$")
        if t ~= "" then table.insert(tokens, t) end
    end
    f:close()
    if #tokens == 0 then
        UIManager:show(InfoMessage:new{ text = _("No tokens found."), timeout = 3 })
        return
    end
    BrowserUI._promptNextImportToken(tokens, 1, on_close)
end

function BrowserUI._promptNextImportToken(tokens, index, on_close)
    if index > #tokens then
        UIManager:show(InfoMessage:new{ text = _("Import complete!"), timeout = 2 })
        BrowserUI.showTokenManager(on_close)
        return
    end
    local tstr = tokens[index]
    local default_name = os.date("token_%Y%m%d%H%M") .. "_" .. index
    local dlg
    dlg = InputDialog:new{
        title = string.format(_("Name for token %d/%d"), index, #tokens),
        description = _("Token: ") .. tstr:sub(1, 15) .. "...",
        input = default_name,
        buttons = {{
            { text = _("Skip"), callback = function()
                UIManager:close(dlg)
                UIManager:scheduleIn(0.1, function()
                    BrowserUI._promptNextImportToken(tokens, index + 1, on_close)
                end)
            end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local name = dlg:getInputText():match("^%s*(.-)%s*$")
                if name == "" then name = default_name end
                GitNotesSettings.addToken(name, tstr)
                UIManager:close(dlg)
                UIManager:scheduleIn(0.1, function()
                    BrowserUI._promptNextImportToken(tokens, index + 1, on_close)
                end)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function BrowserUI.showTokenSelectMenu(owner, repo, on_close)
    local full_name = owner .. "/" .. repo
    local tokens = GitNotesSettings.getTokens()
    local items = {}
    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu) UIManager:close(menu); if on_close then on_close() end end,
    })
    table.insert(items, {
        text = _("➕ Add New Token"),
        callback = function() BrowserUI.promptForTokenString(full_name, on_close) end,
    })
    for tname, _v in pairs(tokens) do
        table.insert(items, {
            text = "🔑 " .. tname,
            callback = function()
                GitNotesSettings.setTokenForRepo(full_name, tname)
                BrowserUI.openRepo(owner, repo, nil, nil, on_close)
            end,
        })
    end
    UIManager:show(BrowserMenu:new{
        title = _("Token for: ") .. full_name,
        item_table = items,
        on_close = on_close,
    })
end

function BrowserUI.promptForTokenString(full_name, on_close)
    local dlg
    dlg = InputDialog:new{
        title = _("GitHub Token"),
        input = "",
        input_hint = _("ghp_..."),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Next"), is_enter_default = true, callback = function()
                local tstr = dlg:getInputText():match("^%s*(.-)%s*$")
                UIManager:close(dlg)
                if tstr == "" then
                    UIManager:show(InfoMessage:new{ text = _("Token cannot be empty."), timeout = 2 })
                    return
                end
                BrowserUI.promptForTokenName(full_name, tstr, on_close)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function BrowserUI.promptForTokenName(full_name, token_string, on_close)
    local dlg
    dlg = InputDialog:new{
        title = _("Token Name"),
        input = "",
        input_hint = _("e.g. Work Token"),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local tname = dlg:getInputText():match("^%s*(.-)%s*$")
                if tname == "" then tname = os.date("token_%Y%m%d%H%M") end
                GitNotesSettings.addToken(tname, token_string)
                UIManager:close(dlg)
                if full_name then
                    GitNotesSettings.setTokenForRepo(full_name, tname)
                    UIManager:show(InfoMessage:new{ text = _("Token saved and assigned!"), timeout = 2 })
                    local owner, repo = full_name:match("^([^/]+)/(.+)$")
                    BrowserUI.openRepo(owner, repo, nil, nil, on_close)
                else
                    UIManager:show(InfoMessage:new{ text = _("Token saved!"), timeout = 2 })
                    if on_close then on_close() end
                end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

-- ── Repo Input Dialog ─────────────────────────────────────────────────────────

function BrowserUI.showRepoInputDialog(on_close, is_private)
    local dlg
    dlg = InputDialog:new{
        title = is_private and _("Open Private Repo") or _("Open Repository"),
        input = "",
        input_hint = _("owner/repo  or  github.com/owner/repo"),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Browse"), is_enter_default = true, callback = function()
                local inp = dlg:getInputText()
                UIManager:close(dlg)
                local owner, repo = GitNotesAPI.parseRepoInput(inp)
                if not owner then
                    UIManager:show(InfoMessage:new{
                        text = _("Invalid format.\nUse: owner/repo"),
                        timeout = 4,
                    })
                    return
                end
                if is_private then
                    BrowserUI.showTokenSelectMenu(owner, repo, on_close)
                else
                    BrowserUI.openRepo(owner, repo, nil, nil, on_close)
                end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

-- ── Unified Repo Opener ───────────────────────────────────────────────────────

function BrowserUI.openRepo(owner, repo, path, branch, on_close)
    local full_name = owner .. "/" .. repo
    local repo_info = GitNotesSettings.getRepoInfo(full_name)

    if repo_info and repo_info.mode == "attached"
       and repo_info.local_path
       and lfs.attributes(repo_info.local_path, "mode") == "directory"
       and GitOps.isGitRepo(repo_info.local_path) then
        BrowserUI.openAttachedRepo(full_name, repo_info, path, branch, on_close)
    else
        -- If registry says attached but local dir is gone, clean up registry
        if repo_info and repo_info.mode == "attached" then
            GitNotesSettings.removeRepoInfo(full_name)
        end
        BrowserUI.openRemoteRepo(owner, repo, path, branch, on_close)
    end
end

-- ── Remote-Only Repo ──────────────────────────────────────────────────────────

function BrowserUI.openRemoteRepo(owner, repo, path, branch, on_close)
    if not NetworkMgr:isOnline() then
        NetworkMgr:promptWifiOn(function()
            BrowserUI.openRemoteRepo(owner, repo, path, branch, on_close)
        end)
        return
    end

    local full_name = owner .. "/" .. repo
    path = path or ""

    if not branch then
        local loading = InfoMessage:new{ text = _("Loading..."), timeout = 30 }
        UIManager:show(loading)
        UIManager:forceRePaint()
        local meta, err = GitNotesAPI.getRepo(owner, repo)
        UIManager:close(loading)
        if not meta then
            UIManager:show(InfoMessage:new{ text = _("Error: ") .. (err or "?"), timeout = 5 })
            return
        end
        branch = meta.default_branch or "main"
        GitNotesSettings.addRecentRepo(full_name)
    end

    local loading2 = InfoMessage:new{ text = _("Loading..."), timeout = 30 }
    UIManager:show(loading2)
    UIManager:forceRePaint()
    local contents, err2 = GitNotesAPI.getContents(owner, repo, path or "", branch)
    UIManager:close(loading2)

    if not contents then
        UIManager:show(InfoMessage:new{ text = _("Error: ") .. (err2 or "?"), timeout = 5 })
        return
    end

    if contents.type == "file" then
        BrowserUI.showRemoteFile(owner, repo, contents, branch)
        return
    end

    table.sort(contents, function(a, b)
        if a.type ~= b.type then return a.type == "dir" end
        return a.name:lower() < b.name:lower()
    end)

    local items = {}
    local is_root = not path or path == ""

    if is_root then
        table.insert(items, {
            text = "\u{ED0B} Back",
            callback = function(menu) UIManager:close(menu); if on_close then on_close() end end,
        })

        local is_saved = GitNotesSettings.isSavedRepo(full_name)
        table.insert(items, {
            text = is_saved and _("★  Remove bookmark") or _("☆  Bookmark"),
            callback = function(menu)
                if is_saved then GitNotesSettings.removeSavedRepo(full_name)
                else GitNotesSettings.addSavedRepo(full_name) end
                UIManager:close(menu)
                BrowserUI.openRemoteRepo(owner, repo, path, branch, on_close)
            end,
        })

        local is_pinned = GitNotesSettings.isPinnedRepo(full_name)
        table.insert(items, {
            text = is_pinned and _("\u{EB03} Unpin") or _("\u{EB02} Pin to Home"),
            callback = function(menu)
                if is_pinned then GitNotesSettings.removePinnedRepo(full_name)
                else GitNotesSettings.addPinnedRepo(full_name) end
                UIManager:close(menu)
                BrowserUI.openRemoteRepo(owner, repo, path, branch, on_close)
            end,
        })

        local cur_token = GitNotesSettings.getRepoTokens()[full_name] or _("Not set")
        table.insert(items, {
            text = _("\u{E60A} Change Token"),
            mandatory = cur_token,
            callback = function(menu)
                UIManager:close(menu)
                BrowserUI.showTokenSelectMenu(owner, repo, on_close)
            end,
        })

        table.insert(items, {
            text = _("\u{F414} Search files"),
            callback = function(menu) UIManager:close(menu); BrowserUI.promptSearchRepo(owner, repo, branch, "filename", on_close) end,
        })

        table.insert(items, {
            text = _("\u{E91D} Search code"),
            callback = function(menu) UIManager:close(menu); BrowserUI.promptSearchRepo(owner, repo, branch, "code", on_close) end,
        })

        table.insert(items, {
            text = _("\u{EA9B} Attach to device"),
            callback = function(menu)
                UIManager:close(menu)
                BrowserUI.attachRepo(owner, repo, branch, on_close)
            end,
        })
    else
        table.insert(items, {
            text = "\u{ED22} ..",
            callback = function(menu) UIManager:close(menu) end,
        })
    end

    local token = GitNotesSettings.getTokenForRepo(full_name)
    local repo_tokens = GitNotesSettings.getRepoTokens()
    local has_explicit_token = repo_tokens[full_name] and token ~= ""
    if has_explicit_token then
        table.insert(items, {
            text = _("\u{EA9B} New file"),
            callback = function() BrowserUI.createRemoteFile(owner, repo, path or "", branch, on_close) end,
        })
    end

    if #items > 0 then
        table.insert(items, { text = "────────────────────", callback = function() end })
    end

    for _, entry in ipairs(contents) do
        if entry.type == "dir" then
            table.insert(items, {
                text = "\u{E94A} " .. entry.name .. "/",
                callback = function() BrowserUI.openRemoteRepo(owner, repo, entry.path, branch, on_close) end,
                hold_callback = function()
                    BrowserUI.handleRemoteEntryHold(owner, repo, entry, branch, on_close)
                end,
            })
        else
            table.insert(items, {
                text = "\u{F016} " .. entry.name,
                mandatory = GitNotesAPI.formatSize(entry.size),
                callback = function() BrowserUI.showRemoteFile(owner, repo, entry, branch) end,
                hold_callback = function()
                    BrowserUI.handleRemoteEntryHold(owner, repo, entry, branch, on_close)
                end,
            })
        end
    end

    local title = is_root and (full_name .. " [" .. branch .. "]") or (full_name .. "/" .. path)
    UIManager:show(BrowserMenu:new{ title = title, item_table = items, on_close = is_root and on_close or nil })
end

function BrowserUI.handleRemoteEntryHold(owner, repo, entry, branch, on_close)
    local full_name = owner .. "/" .. repo
    local token = GitNotesSettings.getTokenForRepo(full_name)
    local repo_tokens = GitNotesSettings.getRepoTokens()
    local has_explicit_token = repo_tokens[full_name] and token ~= ""
    if has_explicit_token then
        UIManager:show(ConfirmBox:new{
            text = _("Delete ") .. entry.name .. "?",
            ok_text = _("Delete"),
            ok_callback = function()
                local loading = InfoMessage:new{ text = _("Deleting..."), timeout = 120 }
                UIManager:show(loading)
                UIManager:forceRePaint()
                local device = GitNotesSettings.getDeviceName()
                local msg = string.format("Delete %s from %s on %s", entry.name, device, os.date("%c"))
                local ok, err
                if entry.type == "dir" then
                    ok, err = GitNotesAPI.deleteDirectory(owner, repo, entry.path, branch, msg, token)
                else
                    ok, err = GitNotesAPI.deleteFile(owner, repo, entry.path, entry.sha, branch, msg, token)
                end
                UIManager:close(loading)
                if not ok then
                    UIManager:show(InfoMessage:new{ text = _("Delete failed: ") .. (err or "?"), timeout = 6 })
                else
                    UIManager:show(InfoMessage:new{ text = _("Deleted!"), timeout = 2 })
                    local parent = entry.path:match("^(.+)/[^/]+$") or ""
                    UIManager:scheduleIn(1, function()
                        BrowserUI.openRemoteRepo(owner, repo, parent, branch, on_close)
                    end)
                end
            end,
        })
    elseif entry.type == "file" and entry.download_url then
        UIManager:show(ConfirmBox:new{
            text = string.format(_("Download \"%s\"?"), entry.name),
            ok_text = _("Download"),
            ok_callback = function() BrowserUI.downloadFile(entry.name, entry.download_url) end,
        })
    else
        UIManager:show(InfoMessage:new{ text = _("Read-only. No actions available."), timeout = 2 })
    end
end

function BrowserUI.showRemoteFile(owner, repo, entry, branch)
    local name = entry.name or "file"
    local download_url = entry.download_url

    if isTextFile(name) and download_url then
        local loading = InfoMessage:new{ text = _("Fetching..."), timeout = 30 }
        UIManager:show(loading)
        UIManager:forceRePaint()
        local text, err = GitNotesAPI.getRawFile(download_url)
        UIManager:close(loading)
        if not text then
            UIManager:show(InfoMessage:new{ text = _("Error: ") .. (err or "?"), timeout = 4 })
            return
        end

        local truncated = false
        if #text > 50000 then
            text = text:sub(1, 50000)
            truncated = true
        end
        if truncated then text = text .. "\n\n── [ truncated ] ──" end

        local token = GitNotesSettings.getTokenForRepo(owner .. "/" .. repo)
        local repo_tokens = GitNotesSettings.getRepoTokens()
        local has_explicit_token = repo_tokens[owner .. "/" .. repo] and token ~= ""
        local full_name = owner .. "/" .. repo
        local buttons = {}
        if has_explicit_token and entry.path and entry.sha and not truncated then
            table.insert(buttons, {{
                text = _("\u{EAEB} Edit"),
                callback = function()
                    BrowserUI.editRemoteFile(owner, repo, entry.path, text, entry.sha, branch)
                end,
            }})
        end
        -- Edit Locally: download to disk and open in local editor (no token needed)
        if entry.path and not truncated then
            table.insert(buttons, {{
                text = _("\u{F016} Edit Locally"),
                callback = function()
                    BrowserUI.editRemoteFileLocally(owner, repo, entry.path, text, branch, entry.sha)
                end,
            }})
        end
        if download_url then
            table.insert(buttons, {{
                text = _("\u{F317} Download"),
                callback = function() BrowserUI.downloadFile(name, download_url) end,
            }})
        end

        UIManager:show(TextViewer:new{
            title = name,
            text = text,
            height = math.floor(Screen:getHeight() * 0.85),
            buttons_table = #buttons > 0 and buttons or nil,
        })
    elseif download_url then
        UIManager:show(ConfirmBox:new{
            text = string.format(_("Download \"%s\"?"), name),
            ok_text = _("Download"),
            ok_callback = function() BrowserUI.downloadFile(name, download_url) end,
        })
    else
        UIManager:show(InfoMessage:new{ text = _("Cannot display this file."), timeout = 3 })
    end
end

function BrowserUI.editRemoteFile(owner, repo, path, content, sha, branch)
    local EditorToolbar = require("githubbrowser_editor_toolbar")
    local UndoStack     = require("githubbrowser_undo")

    local undo_stack = UndoStack.new(GitNotesSettings.getUndoStackSize())
    undo_stack:push(content, 1)

    local dlg
    dlg = InputDialog:new{
        title = _("Edit: ") .. path,
        input = content,
        input_face = Font:getFace(GitNotesSettings.getFontFace(), GitNotesSettings.getFontSize()),
        allow_newline = true,
        fullscreen = true,
        condensed = true,
        add_nav_bar = true,
        scroll_by_pan = true,
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("💾 Commit"), is_enter_default = true, callback = function()
                local new_content = dlg:getInputText()
                UIManager:close(dlg)
                BrowserUI._askRemoteCommitMsg(owner, repo, path, new_content, sha, branch)
            end },
        }},
    }

    local toolbar = EditorToolbar:new{
        input_dialog = dlg,
        bar_width    = dlg:getAddedWidgetAvailableWidth(),
    }
    toolbar:setUndoStack(undo_stack)
    dlg:addWidget(toolbar.widget)

    local orig_edit_cb = dlg._input_widget.edit_callback
    dlg._input_widget.edit_callback = function()
        if toolbar.restoring then return end
        if orig_edit_cb then orig_edit_cb(true) end
        local iw = dlg._input_widget
        local text = iw:getText()
        undo_stack:push(text, iw.charpos)
    end

    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function BrowserUI._askRemoteCommitMsg(owner, repo, path, content, sha, branch)
    local dlg
    dlg = InputDialog:new{
        title = _("Commit message"),
        input = "Update " .. path,
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Commit"), is_enter_default = true, callback = function()
                local msg = dlg:getInputText()
                UIManager:close(dlg)
                local loading = InfoMessage:new{ text = _("Committing..."), timeout = 60 }
                UIManager:show(loading)
                UIManager:forceRePaint()
                local token = GitNotesSettings.getTokenForRepo(owner .. "/" .. repo)
                local device = GitNotesSettings.getDeviceName()
                local full_msg = msg .. "\n\nFrom: " .. device
                local ok, err = GitNotesAPI.updateFile(owner, repo, path, content, sha, branch, full_msg, token)
                UIManager:close(loading)
                if ok then
                    UIManager:show(InfoMessage:new{ text = _("Committed!"), timeout = 2 })
                else
                    UIManager:show(InfoMessage:new{ text = _("Error: ") .. (err or "?"), timeout = 6 })
                end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function BrowserUI.createRemoteFile(owner, repo, dir_path, branch, on_close)
    local dlg
    dlg = InputDialog:new{
        title = _("New File Name"),
        input = "",
        input_hint = _("e.g. notes.md"),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Next"), is_enter_default = true, callback = function()
                local fname = dlg:getInputText():match("^%s*(.-)%s*$")
                UIManager:close(dlg)
                if fname == "" then return end
                local fpath = (dir_path ~= "" and dir_path .. "/" or "") .. fname
                local editor
                editor = InputDialog:new{
                    title = _("New: ") .. fpath,
                    input = "",
                    allow_newline = true,
                    fullscreen = true,
                    buttons = {{
                        { text = _("Cancel"), callback = function() UIManager:close(editor) end },
                        { text = _("💾 Commit"), is_enter_default = true, callback = function()
                            local content = editor:getInputText()
                            UIManager:close(editor)
                            BrowserUI._askRemoteCommitMsg(owner, repo, fpath, content, nil, branch)
                        end },
                    }},
                }
                UIManager:show(editor)
                editor:onShowKeyboard()
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function BrowserUI.downloadFile(name, url)
    local dl_dir = GitNotesSettings.getDownloadDir()
    ensureDir(dl_dir)
    local dest = dl_dir .. "/" .. name
    local loading = InfoMessage:new{ text = _("Downloading..."), timeout = 120 }
    UIManager:show(loading)
    UIManager:forceRePaint()
    local ok, err = GitNotesAPI.downloadFile(url, dest)
    UIManager:close(loading)
    if ok then
        UIManager:show(InfoMessage:new{ text = _("Saved to: ") .. dest, timeout = 4 })
    else
        UIManager:show(InfoMessage:new{ text = _("Download failed: ") .. (err or "?"), timeout = 5 })
    end
end

function BrowserUI.promptSearchRepo(owner, repo, branch, search_type, on_close)
    local dlg
    dlg = InputDialog:new{
        title = search_type == "code" and _("Search code in ") .. repo or _("Search files in ") .. repo,
        input = "",
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local query = dlg:getInputText():match("^%s*(.-)%s*$")
                UIManager:close(dlg)
                if query == "" then return end
                if search_type == "code" then
                    BrowserUI.doCodeSearch(owner, repo, query, on_close)
                else
                    BrowserUI.doFileNameSearch(owner, repo, branch, query, on_close)
                end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function BrowserUI.doFileNameSearch(owner, repo, branch, query, on_close)
    local loading = InfoMessage:new{ text = _("Searching..."), timeout = 30 }
    UIManager:show(loading)
    UIManager:forceRePaint()
    local tree, err = GitNotesAPI.getTree(owner, repo, branch)
    UIManager:close(loading)
    if not tree then
        UIManager:show(InfoMessage:new{ text = _("Error: ") .. (err or "?"), timeout = 5 })
        return
    end
    local q_lower = query:lower()
    local items = {}
    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu) UIManager:close(menu); BrowserUI.openRemoteRepo(owner, repo, nil, branch, on_close) end,
    })
    for _, node in ipairs(tree.tree or {}) do
        if node.type == "blob" and node.path:lower():find(q_lower, 1, true) then
            table.insert(items, {
                text = node.path,
                callback = function()
                    local fetching = InfoMessage:new{ text = _("Fetching..."), timeout = 30 }
                    UIManager:show(fetching)
                    UIManager:forceRePaint()
                    local raw_url = string.format(
                        "https://raw.githubusercontent.com/%s/%s/%s/%s",
                        owner, repo, branch, node.path
                    )
                    local text, err2 = GitNotesAPI.getRawFile(raw_url)
                    UIManager:close(fetching)
                    if text then
                        UIManager:show(TextViewer:new{
                            title = node.path:match("([^/]+)$"),
                            text = #text > 50000 and text:sub(1, 50000) .. "\n\n── [ truncated ] ──" or text,
                            height = math.floor(Screen:getHeight() * 0.85),
                        })
                    else
                        UIManager:show(InfoMessage:new{ text = _("Error: ") .. (err2 or "?"), timeout = 4 })
                    end
                end,
            })
        end
    end
    if #items == 1 then
        table.insert(items, { text = _("   No results."), callback = function() end })
    end
    UIManager:show(BrowserMenu:new{
        title = _("Results: ") .. query,
        item_table = items,
    })
end

function BrowserUI.doCodeSearch(owner, repo, query, on_close)
    local loading = InfoMessage:new{ text = _("Searching..."), timeout = 30 }
    UIManager:show(loading)
    UIManager:forceRePaint()
    local results, err = GitNotesAPI.searchCode(owner, repo, query)
    UIManager:close(loading)
    if not results then
        UIManager:show(InfoMessage:new{ text = _("Error: ") .. (err or "?"), timeout = 5 })
        return
    end
    local items = {}
    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu) UIManager:close(menu); BrowserUI.openRemoteRepo(owner, repo, nil, nil, on_close) end,
    })
    for _, item in ipairs(results.items or {}) do
        table.insert(items, {
            text = item.path or item.name or "?",
            callback = function()
                if item.html_url then
                    UIManager:show(InfoMessage:new{
                        text = item.path .. "\n\nSee: " .. item.html_url,
                        timeout = 6,
                    })
                end
            end,
        })
    end
    if #items == 1 then
        table.insert(items, { text = _("   No results."), callback = function() end })
    end
    UIManager:show(BrowserMenu:new{
        title = _("Code: ") .. query,
        item_table = items,
    })
end

-- ── Attach (Clone) ────────────────────────────────────────────────────────────

function BrowserUI.attachRepo(owner, repo, branch, on_close)
    if not NetworkMgr:isOnline() then
        NetworkMgr:promptWifiOn(function()
            BrowserUI.attachRepo(owner, repo, branch, on_close)
        end)
        return
    end

    local full_name = owner .. "/" .. repo
    local workspace = GitNotesSettings.getWorkspace()
    ensureDir(workspace)
    local dest = workspace .. "/" .. repo

    if lfs.attributes(dest, "mode") then
        UIManager:show(ConfirmBox:new{
            text = string.format(_("Directory \"%s\" already exists.\nOverwrite?"), dest),
            ok_text = _("Overwrite"),
            ok_callback = function() BrowserUI._doClone(owner, repo, branch, dest, on_close) end,
        })
    else
        BrowserUI._doClone(owner, repo, branch, dest, on_close)
    end
end

function BrowserUI._doClone(owner, repo, branch, dest, on_close)
    local full_name = owner .. "/" .. repo
    local token = GitNotesSettings.getTokenForRepo(full_name)

    local loading = InfoMessage:new{ text = _("Cloning..."), timeout = 300 }
    UIManager:show(loading)
    UIManager:forceRePaint()

    local url = "https://github.com/" .. owner .. "/" .. repo .. ".git"
    local shallow = GitNotesSettings.getShallowCloneDefault()
    local ok, output = GitOps.clone(url, dest, token, shallow)

    UIManager:close(loading)

    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Clone failed:\n") .. (output or "?"), timeout = 8 })
        return
    end

    -- Get current HEAD hash for sync tracking
    local handle = io.popen(string.format("cd %q && git rev-parse HEAD 2>&1", dest))
    local hash = handle and handle:read("*a"):gsub("%s+$", "") or ""
    if handle then handle:close() end

    GitNotesSettings.setRepoInfo(full_name, {
        mode           = "attached",
        local_path     = dest,
        branch         = branch or GitOps.getCurrentBranch(dest) or "main",
        last_sync_hash = hash,
        last_sync_time = os.time(),
    })

    UIManager:show(InfoMessage:new{ text = _("Cloned to: ") .. dest, timeout = 4 })
    if on_close then on_close() end
end

-- ── Attached (Local) Repo ─────────────────────────────────────────────────────

function BrowserUI.openAttachedRepo(full_name, repo_info, path, branch, on_close)
    local repo_path = repo_info.local_path
    if not repo_path or lfs.attributes(repo_path, "mode") ~= "directory" then
        UIManager:show(InfoMessage:new{ text = _("Local repo not found. Falling back to remote."), timeout = 3 })
        GitNotesSettings.removeRepoInfo(full_name)
        local owner, repo = full_name:match("^([^/]+)/(.+)$")
        if owner then BrowserUI.openRemoteRepo(owner, repo, path, branch, on_close) end
        return
    end
    branch = branch or repo_info.branch or GitOps.getCurrentBranch(repo_path) or "main"
    path = path or ""

    local items = {}
    local is_root = path == ""
    local owner, repo = full_name:match("^([^/]+)/(.+)$")

    if is_root then
        -- Auto-sync check
        if GitNotesSettings.getAutoSyncOnOpen() and not BrowserUI._sync_checked[full_name] then
            BrowserUI._sync_checked[full_name] = true
            local status = SyncEngine.checkStatus(repo_path, branch)
            if status == "remote_ahead" then
                local changes = SyncEngine.getRemoteChanges(repo_path, branch, 5)
                table.insert(items, {
                    text = "\u{EA2E} " .. string.format(_("%d remote changes (tap to pull)"), #changes),
                    callback = function()
                        local ok, err = GitOps.pull(repo_path, GitNotesSettings.getTokenForRepo(full_name))
                        if ok then
                            UIManager:show(InfoMessage:new{ text = _("Pulled!"), timeout = 2 })
                        else
                            UIManager:show(InfoMessage:new{ text = _("Pull failed: ") .. (err or "?"), timeout = 5 })
                        end
                        BrowserUI.openRepo(owner, repo, nil, branch, on_close)
                    end,
                })
            elseif status == "local_ahead" then
                table.insert(items, {
                    text = "\u{EA2D} Local commits ready to push",
                    callback = function() BrowserUI.showRecentChanges(full_name, repo_info, on_close) end,
                })
            end
        end

        table.insert(items, {
            text = "\u{ED0B} Back",
            callback = function(menu) UIManager:close(menu); if on_close then on_close() end end,
        })

        local is_saved = GitNotesSettings.isSavedRepo(full_name)
        table.insert(items, {
            text = is_saved and _("★  Remove bookmark") or _("☆  Bookmark"),
            callback = function(menu)
                if is_saved then GitNotesSettings.removeSavedRepo(full_name)
                else GitNotesSettings.addSavedRepo(full_name) end
                UIManager:close(menu)
                BrowserUI.openRepo(owner, repo, nil, branch, on_close)
            end,
        })

        table.insert(items, {
            text = _("\u{EA2E} Pull"),
            callback = function()
                if not NetworkMgr:isOnline() then
                    NetworkMgr:promptWifiOn(function()
                        local ok, err = GitOps.pull(repo_path, GitNotesSettings.getTokenForRepo(full_name))
                        UIManager:show(InfoMessage:new{
                            text = ok and _("Pulled!") or ("Pull failed: " .. (err or "?")),
                            timeout = ok and 3 or 5,
                        })
                    end)
                    return
                end
                local ok, err = GitOps.pull(repo_path, GitNotesSettings.getTokenForRepo(full_name))
                UIManager:show(InfoMessage:new{
                    text = ok and _("Pulled!") or ("Pull failed: " .. (err or "?")),
                    timeout = ok and 3 or 5,
                })
            end,
        })

        table.insert(items, {
            text = _("\u{EA2D} Push"),
            callback = function()
                if not NetworkMgr:isOnline() then
                    NetworkMgr:promptWifiOn(function()
                        local ok, err = GitOps.push(repo_path, GitNotesSettings.getTokenForRepo(full_name))
                        UIManager:show(InfoMessage:new{
                            text = ok and _("Pushed!") or ("Push failed: " .. (err or "?")),
                            timeout = ok and 3 or 5,
                        })
                    end)
                    return
                end
                local ok, err = GitOps.push(repo_path, GitNotesSettings.getTokenForRepo(full_name))
                UIManager:show(InfoMessage:new{
                    text = ok and _("Pushed!") or ("Push failed: " .. (err or "?")),
                    timeout = ok and 3 or 5,
                })
            end,
        })

        table.insert(items, {
            text = _("\u{EA2C} Sync"),
            callback = function()
                local function doSync()
                    local token = GitNotesSettings.getTokenForRepo(full_name)
                    local loading = InfoMessage:new{ text = _("Syncing..."), timeout = 120 }
                    UIManager:show(loading)
                    UIManager:forceRePaint()
                    local ok, msg = SyncEngine.sync(repo_path, token, branch)
                    UIManager:close(loading)
                    UIManager:show(InfoMessage:new{ text = msg, timeout = ok and 3 or 5 })
                    GitNotesSettings.updateSyncInfo(full_name, "")
                end
                if not NetworkMgr:isOnline() then
                    NetworkMgr:promptWifiOn(doSync)
                    return
                end
                doSync()
            end,
        })

        table.insert(items, {
            text = _("\u{EBCD} Commit"),
            callback = function() BrowserUI.promptCommit(full_name, repo_info, on_close) end,
        })

        table.insert(items, {
            text = _("\u{F017} Recent Changes"),
            callback = function() BrowserUI.showRecentChanges(full_name, repo_info, on_close) end,
        })

        table.insert(items, {
            text = _("\u{F414} Search files"),
            callback = function()
                BrowserUI.promptLocalSearch(repo_path, full_name, repo_info, on_close)
            end,
        })

        local cur_token = GitNotesSettings.getRepoTokens()[full_name] or _("Not set")
        table.insert(items, {
            text = _("\u{E60A} Change Token"),
            mandatory = cur_token,
            callback = function(menu)
                UIManager:close(menu)
                BrowserUI.showTokenSelectMenu(owner, repo, on_close)
            end,
        })

        table.insert(items, {
            text = _("\u{ECE7} Detach local copy"),
            callback = function()
                UIManager:show(ConfirmBox:new{
                    text = string.format(_("Detach local copy of \"%s\"?\n\nDirectory: %s\n\nThe remote bookmark will be preserved."), full_name, repo_path),
                    ok_text = _("Detach"),
                    ok_callback = function()
                        os.execute(string.format("rm -rf %q", repo_path))
                        GitNotesSettings.removeRepoInfo(full_name)
                        UIManager:show(InfoMessage:new{ text = _("Detached."), timeout = 2 })
                        if on_close then on_close() end
                    end,
                })
            end,
        })
    else
        local parent = path:match("^(.+)/[^/]+$") or ""
        table.insert(items, {
            text = "\u{ED22} ..",
            callback = function(menu) UIManager:close(menu) end,
        })
    end

    -- List directory contents
    local full_path = repo_path
    if path and path ~= "" then full_path = repo_path .. "/" .. path end

    local dir_attr = lfs.attributes(full_path)
    if not dir_attr or dir_attr.mode ~= "directory" then
        UIManager:show(InfoMessage:new{ text = _("Cannot read directory: ") .. (full_path or "?"), timeout = 3 })
        return
    end

    local ok_iter, iter, dir_obj = pcall(lfs.dir, full_path)
    if not ok_iter or not iter then
        UIManager:show(InfoMessage:new{ text = _("Cannot list directory: ") .. full_path, timeout = 3 })
        return
    end

    local dirs, files = {}, {}
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local entry_path = full_path .. "/" .. entry
            local attr = lfs.attributes(entry_path)
            if attr and not IgnoreEngine.shouldIgnore(entry) then
                if attr.mode == "directory" then
                    table.insert(dirs, { name = entry, path = (path ~= "" and path .. "/" or "") .. entry, attr = attr })
                else
                    table.insert(files, { name = entry, path = (path ~= "" and path .. "/" or "") .. entry, attr = attr })
                end
            end
        end
    end
    table.sort(dirs, function(a, b) return a.name:lower() < b.name:lower() end)
    table.sort(files, function(a, b) return a.name:lower() < b.name:lower() end)

    if #items > 0 then
        table.insert(items, { text = "────────────────────", callback = function() end })
    end

    for _, d in ipairs(dirs) do
        table.insert(items, {
            text = "\u{E94A} " .. d.name .. "/",
            callback = function()
                BrowserUI.openAttachedRepo(full_name, repo_info, d.path, branch, on_close)
            end,
        })
    end

    for _, f in ipairs(files) do
        table.insert(items, {
            text = "\u{F016} " .. f.name,
            mandatory = GitNotesAPI.formatSize(f.attr.size),
            callback = function()
                BrowserUI.openLocalFile(full_name, repo_info, f.path, f.name, branch, on_close)
            end,
            hold_callback = function()
                UIManager:show(ConfirmBox:new{
                    text = string.format(_("Delete \"%s\"?"), f.name),
                    ok_text = _("Delete"),
                    ok_callback = function()
                        local fpath = repo_path .. "/" .. f.path
                        os.remove(fpath)
                        UIManager:show(InfoMessage:new{ text = _("Deleted."), timeout = 2 })
                        BrowserUI.openAttachedRepo(full_name, repo_info, path, branch, on_close)
                    end,
                })
            end,
        })
    end

    local title = is_root and ("local: " .. repo .. " [" .. branch .. "]") or (repo .. "/" .. path)
    UIManager:show(BrowserMenu:new{ title = title, item_table = items, on_close = is_root and on_close or nil })
end

function BrowserUI.openLocalFile(full_name, repo_info, rel_path, name, branch, on_close)
    local full_path = repo_info.local_path .. "/" .. rel_path

    if isTextFile(name) then
        Editor.openFile(full_path)
    else
        UIManager:show(ConfirmBox:new{
            text = string.format(_("File: %s\n\nThis file type cannot be edited inline.\nCopy to download folder?"), name),
            ok_text = _("Copy"),
            ok_callback = function()
                local dl_dir = GitNotesSettings.getDownloadDir()
                ensureDir(dl_dir)
                local dest = dl_dir .. "/" .. name
                local src_f = io.open(full_path, "rb")
                if not src_f then
                    UIManager:show(InfoMessage:new{ text = _("Cannot read file."), timeout = 3 })
                    return
                end
                local data = src_f:read("*a")
                src_f:close()
                local dst_f = io.open(dest, "wb")
                if dst_f then
                    dst_f:write(data)
                    dst_f:close()
                    UIManager:show(InfoMessage:new{ text = _("Copied to: ") .. dest, timeout = 4 })
                end
            end,
        })
    end
end

function BrowserUI.promptCommit(full_name, repo_info, on_close)
    if not GitOps.hasChanges(repo_info.local_path) then
        UIManager:show(InfoMessage:new{ text = _("Nothing to commit."), timeout = 3 })
        return
    end
    local dlg
    dlg = InputDialog:new{
        title = _("Commit message"),
        input = "",
        input_hint = _("What changed?"),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Commit"), is_enter_default = true, callback = function()
                local msg = dlg:getInputText():match("^%s*(.-)%s*$")
                UIManager:close(dlg)
                if msg == "" then msg = "Update" end
                local ok, err = GitOps.commit(repo_info.local_path, msg)
                UIManager:show(InfoMessage:new{
                    text = ok and _("Committed!") or ("Commit failed: " .. (err or "?")),
                    timeout = ok and 3 or 5,
                })
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function BrowserUI.showRecentChanges(full_name, repo_info, on_close)
    local repo_path = repo_info.local_path
    local branch = repo_info.branch or GitOps.getCurrentBranch(repo_path) or "main"
    local items = {}

    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu)
            UIManager:close(menu)
            local o, r = full_name:match("^([^/]+)/(.+)$")
            if o then BrowserUI.openRepo(o, r, nil, branch, on_close) end
        end,
    })

    -- Remote changes
    local remote_changes = SyncEngine.getRemoteChanges(repo_path, branch, 10)
    table.insert(items, { text = "── " .. _("Remote (new)") .. " ──", callback = function() end })
    if #remote_changes == 0 then
        table.insert(items, { text = _("   None"), callback = function() end })
    else
        for _, entry in ipairs(remote_changes) do
            table.insert(items, {
                text = entry.hash .. " " .. entry.message,
                mandatory = entry.date,
                callback = function() end,
            })
        end
    end

    -- Uncommitted
    local uncommitted = SyncEngine.getUncommitted(repo_path)
    table.insert(items, { text = "── " .. _("Uncommitted") .. " ──", callback = function() end })
    if #uncommitted == 0 then
        table.insert(items, { text = _("   None"), callback = function() end })
    else
        for _, entry in ipairs(uncommitted) do
            table.insert(items, {
                text = entry.status .. " " .. entry.file,
                callback = function() end,
            })
        end
    end

    -- Unpushed
    local unpushed = SyncEngine.getLocalUnpushed(repo_path, branch, 10)
    table.insert(items, { text = "── " .. _("Unpushed") .. " ──", callback = function() end })
    if #unpushed == 0 then
        table.insert(items, { text = _("   None"), callback = function() end })
    else
        for _, entry in ipairs(unpushed) do
            table.insert(items, {
                text = entry.hash .. " " .. entry.message,
                mandatory = entry.date,
                callback = function() end,
            })
        end
    end

    -- Actions
    table.insert(items, { text = "────────────────────", callback = function() end })
    table.insert(items, {
        text = _("\u{EA2E} Pull"),
        callback = function()
            if not NetworkMgr:isOnline() then
                NetworkMgr:promptWifiOn(function()
                    local ok, err = GitOps.pull(repo_path, GitNotesSettings.getTokenForRepo(full_name))
                    UIManager:show(InfoMessage:new{
                        text = ok and _("Pulled!") or ("Pull failed: " .. (err or "?")),
                        timeout = ok and 3 or 5,
                    })
                    BrowserUI.showRecentChanges(full_name, repo_info, on_close)
                end)
                return
            end
            local ok, err = GitOps.pull(repo_path, GitNotesSettings.getTokenForRepo(full_name))
            UIManager:show(InfoMessage:new{
                text = ok and _("Pulled!") or ("Pull failed: " .. (err or "?")),
                timeout = ok and 3 or 5,
            })
            BrowserUI.showRecentChanges(full_name, repo_info, on_close)
        end,
    })
    table.insert(items, {
        text = _("\u{EA2D} Push"),
        callback = function()
            if not NetworkMgr:isOnline() then
                NetworkMgr:promptWifiOn(function()
                    local ok, err = GitOps.push(repo_path, GitNotesSettings.getTokenForRepo(full_name))
                    UIManager:show(InfoMessage:new{
                        text = ok and _("Pushed!") or ("Push failed: " .. (err or "?")),
                        timeout = ok and 3 or 5,
                    })
                    BrowserUI.showRecentChanges(full_name, repo_info, on_close)
                end)
                return
            end
            local ok, err = GitOps.push(repo_path, GitNotesSettings.getTokenForRepo(full_name))
            UIManager:show(InfoMessage:new{
                text = ok and _("Pushed!") or ("Push failed: " .. (err or "?")),
                timeout = ok and 3 or 5,
            })
            BrowserUI.showRecentChanges(full_name, repo_info, on_close)
        end,
    })
    table.insert(items, {
        text = _("\u{F314} View Diff"),
        callback = function()
            local diff = GitOps.diff(repo_path)
            if diff and diff ~= "" then
                UIManager:show(TextViewer:new{
                    title = _("Diff"),
                    text = #diff > 30000 and diff:sub(1, 30000) .. "\n\n── [ truncated ] ──" or diff,
                    height = math.floor(Screen:getHeight() * 0.85),
                })
            else
                UIManager:show(InfoMessage:new{ text = _("No uncommitted changes."), timeout = 3 })
            end
        end,
    })
    table.insert(items, {
        text = _("\u{F017} Git Log"),
        callback = function()
            local log_entries = GitOps.log(repo_path, 20)
            if not log_entries or #log_entries == 0 then
                UIManager:show(InfoMessage:new{ text = _("No commits yet."), timeout = 3 })
                return
            end
            local log_items = {}
            table.insert(log_items, {
                text = "\u{ED0B} Back",
                callback = function(m) UIManager:close(m); BrowserUI.showRecentChanges(full_name, repo_info, on_close) end,
            })
            for _, e in ipairs(log_entries) do
                table.insert(log_items, {
                    text = e.hash .. " " .. e.message,
                    mandatory = e.date,
                    callback = function() end,
                })
            end
            UIManager:show(BrowserMenu:new{ title = _("Git Log"), item_table = log_items })
        end,
    })

    UIManager:show(BrowserMenu:new{
        title = _("Changes: ") .. full_name,
        item_table = items,
    })
end

function BrowserUI.promptLocalSearch(repo_path, full_name, repo_info, on_close)
    local dlg
    dlg = InputDialog:new{
        title = _("Search files"),
        input = "",
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local query = dlg:getInputText():match("^%s*(.-)%s*$")
                UIManager:close(dlg)
                if query == "" then return end
                BrowserUI.doLocalSearch(repo_path, full_name, repo_info, query, on_close)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function BrowserUI.doLocalSearch(repo_path, full_name, repo_info, query, on_close)
    local results = {}
    local q_lower = query:lower()

    local function walk(dir, prefix)
        local ok_iter, iter, dir_obj = pcall(lfs.dir, dir)
        if not ok_iter or not iter then return end
        for entry in iter, dir_obj do
            if entry ~= "." and entry ~= ".." and not IgnoreEngine.shouldIgnore(entry) then
                local full = dir .. "/" .. entry
                local rel = prefix ~= "" and (prefix .. "/" .. entry) or entry
                local attr = lfs.attributes(full)
                if attr then
                    if attr.mode == "directory" then
                        walk(full, rel)
                    elseif entry:lower():find(q_lower, 1, true) then
                        table.insert(results, { name = entry, path = rel })
                    end
                end
            end
        end
    end

    walk(repo_path, "")

    local items = {}
    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu)
            UIManager:close(menu)
            local owner, repo = full_name:match("^([^/]+)/(.+)$")
            BrowserUI.openAttachedRepo(full_name, repo_info, nil, nil, on_close)
        end,
    })

    for _, r in ipairs(results) do
        table.insert(items, {
            text = r.path,
            callback = function()
                local owner, repo = full_name:match("^([^/]+)/(.+)$")
                BrowserUI.openLocalFile(full_name, repo_info, r.path, r.name, nil, on_close)
            end,
        })
    end

    if #items == 1 then
        table.insert(items, { text = _("   No results."), callback = function() end })
    end

    UIManager:show(BrowserMenu:new{ title = _("Results: ") .. query, item_table = items })
end

BrowserUI._sync_checked = {}

return BrowserUI
