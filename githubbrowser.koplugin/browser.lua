--[[--
Main browsing UI for the Github Browser plugin.
Features: enter repo, browse directories, view text files, download files.
No README auto-popup. No token/auth features.
--]]--

local Menu         = require("ui/widget/menu")
local InputDialog  = require("ui/widget/inputdialog")
local TextViewer   = require("ui/widget/textviewer")
local InfoMessage  = require("ui/widget/infomessage")
local ConfirmBox   = require("ui/widget/confirmbox")
local ButtonDialog = require("ui/widget/buttondialog")
local UIManager    = require("ui/uimanager")
local Screen       = require("device").screen
local lfs          = require("libs/libkoreader-lfs")
local logger       = require("logger")
local _            = require("gettext")

local GithubBrowserAPI      = require("api")
local GithubBrowserSettings = require("settings")

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function ensureDir(p)
    if not lfs.attributes(p, "mode") then lfs.mkdir(p) end
end

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

local function isOpenable(name) return OPENABLE_EXT[getExt(name)] end

local function isTextFile(name)
    local ext = getExt(name)
    -- Files with known text extensions, or files with no extension at all
    return TEXT_EXT[ext] or ext == ""
end

-- ── Menu subclass ─────────────────────────────────────────────────────────────

local BrowserMenu = Menu:extend {
    covers_fullscreen = true,
    is_borderless     = true,
    is_popout         = false,
}

function BrowserMenu:onMenuSelect(item)
    if item.callback then 
        item.callback(self) 
        return true
    end
end

function BrowserMenu:onMenuHold(item)
    if item.hold_callback then 
        item.hold_callback(self) 
        return true
    end
end

function BrowserMenu:onReturn()
    UIManager:close(self)
    if self.on_close then self.on_close() end
    return true
end

-- ── GithubBrowserUI ────────────────────────────────────────────────────────────

local GithubBrowserUI = {}

-- ── Home Screen ───────────────────────────────────────────────────────────────

function GithubBrowserUI.showHome()
    local function refresh_home()
        if GithubBrowserUI._home_menu then UIManager:close(GithubBrowserUI._home_menu) end
        GithubBrowserUI.showHome()
    end

    local recent = GithubBrowserSettings.getRecentRepos()
    local items  = {}

    -- Browse public repo
    table.insert(items, {
        text = _("\u{E647} Browse public repo..."),
        callback = function()
            GithubBrowserUI.showRepoInputDialog(refresh_home)
        end,
    })

    -- Browse private repo
    table.insert(items, {
        text = _("\u{E636} Browse private repo..."),
        callback = function()
            GithubBrowserUI.showRepoInputDialog(refresh_home, true)
        end,
    })

    -- Most recent repo (quick access)
    if #recent > 0 then
        local last = recent[1]
        table.insert(items, {
            text = "\u{EDAE} " .. last,
            mandatory = _("recent"),
            callback = function()
                local owner, repo = last:match("^([^/]+)/(.+)$")
                if owner then
                    GithubBrowserUI.openRepo(owner, repo, nil, nil, refresh_home)
                end
            end,
        })
    end

    -- Pinned Repos
    local pinned = GithubBrowserSettings.getPinnedRepos()
    if #pinned > 0 then
        table.insert(items, {
            text = "── " .. _("Pinned") .. " ──",
            callback = function() end,
        })
        for i, full_name in ipairs(pinned) do
            table.insert(items, {
                text = "  \u{EB02} " .. full_name,
                callback = function()
                    local owner, repo = full_name:match("^([^/]+)/(.+)$")
                    if owner then
                        GithubBrowserUI.openRepo(owner, repo, nil, nil, refresh_home)
                    end
                end,
                hold_callback = function(menu)
                    UIManager:show(ConfirmBox:new {
                        text = string.format(_("Unpin \"%s\"?"), full_name),
                        ok_text = _("Unpin"),
                        cancel_text = _("Cancel"),
                        ok_callback = function()
                            GithubBrowserSettings.removePinnedRepo(full_name)
                            UIManager:show(InfoMessage:new {
                                text = _("Unpinned."), timeout = 2,
                            })
                            UIManager:close(menu)
                            GithubBrowserUI.showHome()
                        end,
                    })
                end,
            })
        end
    end

    -- Bookmarks
    table.insert(items, {
        text = _("\u{EBCD} Bookmarks"),
        mandatory = tostring(#GithubBrowserSettings.getSavedRepos()),
        callback = function()
            GithubBrowserUI.showBookmarks(refresh_home)
        end,
    })

    -- History
    table.insert(items, {
        text = _("\u{F017} History"),
        mandatory = tostring(#recent),
        callback = function()
            GithubBrowserUI.showHistory(refresh_home)
        end,
    })

    -- Settings
    table.insert(items, {
        text = _("\u{E615} Settings"),
        callback = function()
            GithubBrowserUI.showSettings(refresh_home)
        end,
    })

    -- About
    table.insert(items, {
        text = _("\u{E9FB} About"),
        callback = function()
            GithubBrowserUI.showAbout(refresh_home)
        end,
    })

    local menu = BrowserMenu:new {
        title      = _("Github Browser"),
        item_table = items,
    }
    GithubBrowserUI._home_menu = menu
    UIManager:show(menu)
end

-- ── About Section ─────────────────────────────────────────────────────────────

function GithubBrowserUI.showAbout(on_close)
    local about_text =
        _("Version: 0.1\n") ..
        _("Author: right9code\n\n") ..
        _("A comprehensive GitHub client tailored for KOReader.\n\n") ..
        _("Key Features:\n") ..
        _("• Browse public and private repositories seamlessly.\n") ..
        _("• View, edit, and download files directly to your device.\n") ..
        _("• Securely manage multiple GitHub personal access tokens.\n") ..
        _("• Bookmark and pin your favorite repos for quick access.\n\n") ..
        _("GitHub:\nhttps://github.com/right9code/githubbrowser.koplugin")

    UIManager:show(TextViewer:new {
        title = _("About Github Browser"),
        text = about_text,
        height = math.floor(Screen:getHeight() * 0.6),
    })
end

-- ── Bookmarks View ────────────────────────────────────────────────────────────

function GithubBrowserUI.showBookmarks(on_close)
    local saved = GithubBrowserSettings.getSavedRepos()
    local items = {}

    -- Back
    table.insert(items, {
        text = "\u{ED0B} Back",
        callback = function(menu)
            UIManager:close(menu)
            if on_close then on_close() end
        end,
    })

    -- Clear all bookmarks will be at the bottom

    if #saved == 0 then
        table.insert(items, {
            text = _("   No bookmarked repos yet."),
            callback = function() end,
        })
    else
        for i, full_name in ipairs(saved) do
            table.insert(items, {
                text = "  \u{EBCE} " .. full_name,
                callback = function()
                    local owner, repo = full_name:match("^([^/]+)/(.+)$")
                    if owner then
                        GithubBrowserUI.openRepo(owner, repo, nil, nil, on_close)
                    end
                end,
                hold_callback = function(menu)
                    UIManager:show(ConfirmBox:new {
                        text = string.format(_("Remove \"%s\" from bookmarks?"), full_name),
                        ok_text = _("Remove"),
                        cancel_text = _("Cancel"),
                        ok_callback = function()
                            GithubBrowserSettings.removeSavedRepo(full_name)
                            UIManager:show(InfoMessage:new {
                                text = _("Removed."), timeout = 2,
                            })
                            UIManager:close(menu)
                            GithubBrowserUI.showBookmarks(on_close)
                        end,
                    })
                end,
            })
        end
    end

    -- Clear all bookmarks at the bottom
    if #saved > 0 then
        table.insert(items, {
            text = _("   Clear all bookmarks"),
            callback = function(menu)
                UIManager:show(ConfirmBox:new {
                    text = string.format(_("Remove all %d bookmarks?"), #saved),
                    ok_text = _("Clear all"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        GithubBrowserSettings.clearSavedRepos()
                        UIManager:show(InfoMessage:new {
                            text = _("All bookmarks cleared."), timeout = 2,
                        })
                        UIManager:close(menu)
                        GithubBrowserUI.showBookmarks(on_close)
                    end,
                })
            end,
        })
    end

    UIManager:show(BrowserMenu:new {
        title      = _("Bookmarks"),
        item_table = items,
        on_close   = on_close,
    })
end

-- ── History View ──────────────────────────────────────────────────────────────

function GithubBrowserUI.showHistory(on_close)
    local recent = GithubBrowserSettings.getRecentRepos()
    local items  = {}

    -- Back
    table.insert(items, {
        text = "◂ Back",
        callback = function(menu)
            UIManager:close(menu)
            if on_close then on_close() end
        end,
    })

    -- Clear history
    if #recent > 0 then
        table.insert(items, {
            text = _("   Clear history"),
            callback = function(menu)
                UIManager:show(ConfirmBox:new {
                    text = string.format(_("Clear all %d history entries?"), #recent),
                    ok_text = _("Clear"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        GithubBrowserSettings.clearRecentRepos()
                        UIManager:show(InfoMessage:new {
                            text = _("History cleared."), timeout = 2,
                        })
                        UIManager:close(menu)
                        GithubBrowserUI.showHistory(on_close)
                    end,
                })
            end,
        })
    end

    if #recent == 0 then
        table.insert(items, {
            text = _("   No history yet."),
            callback = function() end,
        })
    else
        for i, full_name in ipairs(recent) do
            local is_saved = GithubBrowserSettings.isSavedRepo(full_name)
            table.insert(items, {
                text = "  " .. full_name,
                mandatory = is_saved and "\u{EBCE}" or "",
                callback = function()
                    local owner, repo = full_name:match("^([^/]+)/(.+)$")
                    if owner then
                        GithubBrowserUI.openRepo(owner, repo, nil, nil, on_close)
                    end
                end,
                hold_callback = function(menu)
                    UIManager:show(ConfirmBox:new {
                        text = string.format(_("Remove \"%s\" from history?"), full_name),
                        ok_text = _("Remove"),
                        cancel_text = _("Cancel"),
                        ok_callback = function()
                            GithubBrowserSettings.removeRecentRepo(full_name)
                            UIManager:show(InfoMessage:new {
                                text = _("Removed."), timeout = 2,
                            })
                            UIManager:close(menu)
                            GithubBrowserUI.showHistory(on_close)
                        end,
                    })
                end,
            })
        end
    end


    UIManager:show(BrowserMenu:new {
        title      = _("History"),
        item_table = items,
        on_close   = on_close,
    })
end

-- ── Settings View ─────────────────────────────────────────────────────────────

function GithubBrowserUI.showSettings(on_close)
    local items = {}

    -- Back
    table.insert(items, {
        text = "◂ Back",
        callback = function(menu)
            UIManager:close(menu)
            if on_close then on_close() end
        end,
    })

    -- Clear history
    local recent = GithubBrowserSettings.getRecentRepos()
    if #recent > 0 then
        table.insert(items, {
            text = _("   Clear history"),
            mandatory = tostring(#recent),
            callback = function(menu)
                UIManager:show(ConfirmBox:new {
                    text = string.format(_("Clear all %d history entries?"), #recent),
                    ok_text = _("Clear"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        GithubBrowserSettings.clearRecentRepos()
                        UIManager:show(InfoMessage:new {
                            text = _("History cleared."), timeout = 2,
                        })
                        UIManager:close(menu)
                        GithubBrowserUI.showSettings(on_close)
                    end,
                })
            end,
        })
    end

    -- Clear all bookmarks
    local saved = GithubBrowserSettings.getSavedRepos()
    if #saved > 0 then
        table.insert(items, {
            text = _("   Clear all bookmarks"),
            mandatory = tostring(#saved),
            callback = function(menu)
                UIManager:show(ConfirmBox:new {
                    text = string.format(_("Remove all %d bookmarks?"), #saved),
                    ok_text = _("Clear all"),
                    cancel_text = _("Cancel"),
                    ok_callback = function()
                        GithubBrowserSettings.clearSavedRepos()
                        UIManager:show(InfoMessage:new {
                            text = _("All bookmarks cleared."), timeout = 2,
                        })
                        UIManager:close(menu)
                        GithubBrowserUI.showSettings(on_close)
                    end,
                })
            end,
        })
    end

    -- Manage GitHub Tokens
    table.insert(items, {
        text = _("   Manage GitHub Tokens"),
        callback = function(menu)
            GithubBrowserUI.showTokenManager(on_close)
        end,
    })

    -- Download Folder
    local current_dl_dir = GithubBrowserSettings.getDownloadDir()
    table.insert(items, {
        text = _("   Download Folder"),
        mandatory = current_dl_dir,
        callback = function(menu)
            local PathChooser = require("ui/widget/pathchooser")
            local path_chooser
            path_chooser = PathChooser:new {
                path = G_reader_settings:readSetting("home_dir") or require("device").home_dir or require("datastorage"):getDataDir(),
                select_file = false,
                select_directory = true,
                onConfirm = function(path)
                    GithubBrowserSettings.setDownloadDir(path)
                    UIManager:show(InfoMessage:new {
                        text = _("Download folder updated."),
                        timeout = 2,
                    })
                    UIManager:close(menu)
                    GithubBrowserUI.showSettings(on_close)
                end,
            }
            UIManager:show(path_chooser)
        end,
    })


    -- Device Name
    local current_device = GithubBrowserSettings.getDeviceName()
    table.insert(items, {
        text = _("   Device Name"),
        mandatory = current_device,
        callback = function(menu)
            local dlg
            dlg = InputDialog:new {
                title = _("Device Name"),
                input = current_device,
                input_hint = _("e.g. koreader, libra2"),
                buttons = {{
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function() UIManager:close(dlg) end,
                    },
                    {
                        text = _("Save"),
                        is_enter_default = true,
                        callback = function()
                            local val = dlg:getInputText()
                            UIManager:close(dlg)
                            val = val:match("^%s*(.-)%s*$")
                            if val == "" then val = "koreader" end
                            GithubBrowserSettings.setDeviceName(val)
                            UIManager:show(InfoMessage:new {
                                text = _("Device name saved."),
                                timeout = 2,
                            })
                            UIManager:close(menu)
                            GithubBrowserUI.showSettings(on_close)
                        end,
                    },
                }},
            }
            UIManager:show(dlg)
            dlg:onShowKeyboard()
        end,
    })

    -- Max history entries
    local current_max = GithubBrowserSettings.getMaxRecentRepos()
    table.insert(items, {
        text = _("   Max history entries"),
        mandatory = tostring(current_max),
        callback = function(menu)
            local dlg
            dlg = InputDialog:new {
                title = _("Max History Entries"),
                input = tostring(current_max),
                input_hint = _("Number (default: 20)"),
                input_type = "number",
                buttons = {{
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function() UIManager:close(dlg) end,
                    },
                    {
                        text = _("Save"),
                        is_enter_default = true,
                        callback = function()
                            local val = tonumber(dlg:getInputText())
                            UIManager:close(dlg)
                            if not val or val < 1 then
                                UIManager:show(InfoMessage:new {
                                    text = _("Enter a number greater than 0."),
                                    timeout = 3,
                                })
                                return
                            end
                            GithubBrowserSettings.setMaxRecentRepos(val)
                            UIManager:show(InfoMessage:new {
                                text = string.format(_("Max history set to %d."), val),
                                timeout = 2,
                            })
                            UIManager:close(menu)
                            GithubBrowserUI.showSettings(on_close)
                        end,
                    },
                }},
            }
            UIManager:show(dlg)
            dlg:onShowKeyboard()
        end,
    })

    UIManager:show(BrowserMenu:new {
        title      = _("Settings"),
        item_table = items,
        on_close   = on_close,
    })
end

-- ── Token Management Dialogs ──────────────────────────────────────────────────

function GithubBrowserUI.showTokenManager(on_close)
    local tokens = GithubBrowserSettings.getTokens()
    local default_name = GithubBrowserSettings.getDefaultTokenName()
    local items = {}

    -- Count tokens to decide whether to show "Set Default"
    local token_count = 0
    for _ in pairs(tokens) do token_count = token_count + 1 end

    if token_count > 0 then
        table.insert(items, {
            text = _("\u{F43D} Set Default Token"),
            mandatory = default_name or _("Not set"),
            callback = function()
                GithubBrowserUI.showDefaultTokenPicker(on_close)
            end,
        })
    end

    table.insert(items, {
        text = _("\u{EA08} Add New Token"),
        callback = function()
            GithubBrowserUI.promptForTokenString(nil, function()
                GithubBrowserUI.showTokenManager(on_close)
            end)
        end,
    })

    for tname, _v in pairs(tokens) do
        local is_default = (tname == default_name)
        table.insert(items, {
            text = (is_default and "\u{EA05} " or "\u{EA0A} ") .. tname,
            mandatory = is_default and _("default") or "",
            callback = function()
                UIManager:show(BrowserMenu:new {
                    title = _("Manage: ") .. tname,
                    item_table = {
                        {
                            text = _("\u{EA07} Rename Token"),
                            callback = function(cmenu)
                                UIManager:close(cmenu)
                                GithubBrowserUI.promptRenameToken(tname, on_close)
                            end,
                        },
                        {
                            text = _("\u{EA09} Delete Token"),
                            callback = function(cmenu)
                                UIManager:close(cmenu)
                                UIManager:show(ConfirmBox:new {
                                    text = _("Delete token '") .. tname .. _("'?"),
                                    ok_text = _("Delete"), cancel_text = _("Cancel"),
                                    ok_callback = function()
                                        GithubBrowserSettings.deleteToken(tname)
                                        if tname == default_name then
                                            GithubBrowserSettings.setDefaultTokenName(nil)
                                        end
                                        GithubBrowserUI.showTokenManager(on_close)
                                    end,
                                })
                            end,
                        }
                    }
                })
            end,
        })
    end
    table.insert(items, {
        text = _("\u{EA06} Import Tokens (File Picker)"),
        callback = function()
            GithubBrowserUI.promptImportTokens(on_close)
        end,
    })
    table.insert(items, {
        text = _("\u{EA06} Import Tokens (Type Path) - Use if picker fails"),
        callback = function()
            GithubBrowserUI.promptImportTokensPath(on_close)
        end,
    })
    UIManager:show(BrowserMenu:new {
        title = _("GitHub Tokens"),
        item_table = items,
        on_close = on_close and function() GithubBrowserUI.showSettings(on_close) end or nil,
    })
end

function GithubBrowserUI.showDefaultTokenPicker(on_close)
    local tokens = GithubBrowserSettings.getTokens()
    local current_default = GithubBrowserSettings.getDefaultTokenName()
    local items = {}
    
    for tname, _v in pairs(tokens) do
        local is_current = (tname == current_default)
        table.insert(items, {
            text = (is_current and "● " or "○ ") .. tname,
            mandatory = is_current and _("current") or "",
            callback = function()
                GithubBrowserSettings.setDefaultTokenName(tname)
                UIManager:show(InfoMessage:new {
                    text = _("Default token set to: ") .. tname,
                    timeout = 2,
                })
                GithubBrowserUI.showTokenManager(on_close)
            end,
        })
    end
    
    table.insert(items, {
        text = _("✕ Clear Default"),
        callback = function()
            GithubBrowserSettings.setDefaultTokenName(nil)
            UIManager:show(InfoMessage:new {
                text = _("Default token cleared."),
                timeout = 2,
            })
            GithubBrowserUI.showTokenManager(on_close)
        end,
    })
    
    UIManager:show(BrowserMenu:new {
        title = _("Set Default Token"),
        item_table = items,
    })
end

function GithubBrowserUI.promptRenameToken(old_name, on_close)
    local dlg
    dlg = InputDialog:new {
        title = _("Rename Token"),
        input = old_name,
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local new_name = dlg:getInputText()
                UIManager:close(dlg)
                new_name = new_name:match("^%s*(.-)%s*$")
                if new_name == "" or new_name == old_name then return end
                GithubBrowserSettings.renameToken(old_name, new_name)
                GithubBrowserUI.showTokenManager(on_close)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function GithubBrowserUI.promptImportTokens(on_close)
    local FileChooser = require("ui/widget/filechooser")
    local file_chooser
    file_chooser = FileChooser:new {
        path = G_reader_settings:readSetting("home_dir") or require("device").home_dir or require("datastorage"):getDataDir(),
        title = _("Select Token File (.txt)"),
        onFileSelect = function(self_fc, item)
            UIManager:close(self_fc)
            GithubBrowserUI.processTokenFile(item.path, on_close)
            return true
        end,
        onClose = function(self_fc)
            UIManager:close(self_fc)
            if on_close then on_close() end
            return true
        end,
    }
    UIManager:show(file_chooser)
end

function GithubBrowserUI.promptImportTokensPath(on_close)
    local InputDialog = require("ui/widget/inputdialog")
    local default_path = G_reader_settings:readSetting("home_dir") or require("device").home_dir or "/mnt/onboard"
    default_path = default_path .. "/token.txt"
    
    local dlg
    dlg = InputDialog:new {
        title = _("Enter path to tokens file"),
        input = default_path,
        input_type = "string",
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function()
                UIManager:close(dlg)
                if on_close then on_close() end
            end },
            { text = _("Import"), is_enter = true, callback = function()
                local text = dlg:getInputValue()
                UIManager:close(dlg)
                if text and text ~= "" then
                    GithubBrowserUI.processTokenFile(text, on_close)
                else
                    if on_close then on_close() end
                end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function GithubBrowserUI.processTokenFile(path, on_close)
    local f = io.open(path, "r")
    if not f then
        UIManager:show(InfoMessage:new { text = _("Could not open file:\n") .. path, timeout = 3 })
        return
    end

    local tokens = {}
    for line in f:lines() do
        local tstr = line:match("^%s*(.-)%s*$")
        if tstr ~= "" then
            table.insert(tokens, tstr)
        end
    end
    f:close()

    if #tokens == 0 then
        UIManager:show(InfoMessage:new { text = _("No tokens found in file."), timeout = 3 })
        return
    end

    GithubBrowserUI._promptNextImportToken(tokens, 1, on_close)
end

function GithubBrowserUI._promptNextImportToken(tokens, index, on_close)
    if index > #tokens then
        UIManager:show(InfoMessage:new { text = _("Import complete!"), timeout = 2 })
        GithubBrowserUI.showTokenManager(on_close)
        return
    end

    local tstr = tokens[index]
    local short_tstr = tstr:sub(1, 15) .. "..."
    local default_name = os.date("token_%Y%m%d%H%M") .. "_" .. index

    local dlg
    dlg = InputDialog:new {
        title = string.format(_("Name for token %d/%d"), index, #tokens),
        description = _("Token: ") .. short_tstr,
        input = default_name,
        buttons = {{
            { text = _("Skip"), callback = function() 
                UIManager:close(dlg)
                UIManager:scheduleIn(0.1, function()
                    GithubBrowserUI._promptNextImportToken(tokens, index + 1, on_close)
                end)
            end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local name = dlg:getInputText()
                UIManager:close(dlg)
                name = name:match("^%s*(.-)%s*$")
                if name == "" then name = default_name end
                
                GithubBrowserSettings.addToken(name, tstr)
                UIManager:scheduleIn(0.1, function()
                    GithubBrowserUI._promptNextImportToken(tokens, index + 1, on_close)
                end)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function GithubBrowserUI.showTokenSelectMenu(owner, repo, on_close)
    local full_name = owner .. "/" .. repo
    local tokens = GithubBrowserSettings.getTokens()
    
    local items = {}
    table.insert(items, {
        text = _("➕ Add New Token"),
        callback = function()
            GithubBrowserUI.promptForTokenString(full_name, on_close)
        end,
    })
    
    for tname, _v in pairs(tokens) do
        table.insert(items, {
            text = "🔑 " .. tname,
            callback = function()
                GithubBrowserSettings.setTokenForRepo(full_name, tname)
                GithubBrowserUI.openRepo(owner, repo, nil, nil, on_close)
            end,
        })
    end
    
    UIManager:show(BrowserMenu:new {
        title = _("Select Token for: ") .. full_name,
        item_table = items,
        on_close = on_close,
    })
end

function GithubBrowserUI.promptForTokenString(full_name, on_close)
    local dlg
    dlg = InputDialog:new {
        title = _("GitHub Token String"),
        input = "",
        input_hint = _("ghp_..."),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Next"), is_enter_default = true, callback = function()
                local tstr = dlg:getInputText()
                UIManager:close(dlg)
                tstr = tstr:match("^%s*(.-)%s*$")
                if tstr == "" then
                    UIManager:show(InfoMessage:new { text = _("Token cannot be empty."), timeout = 2 })
                    return
                end
                GithubBrowserUI.promptForTokenName(full_name, tstr, on_close)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function GithubBrowserUI.promptForTokenName(full_name, token_string, on_close)
    local dlg
    dlg = InputDialog:new {
        title = _("Token Name"),
        input = "",
        input_hint = _("e.g. Work Token (Leave blank for timestamp)"),
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local tname = dlg:getInputText()
                UIManager:close(dlg)
                tname = tname:match("^%s*(.-)%s*$")
                if tname == "" then
                    tname = os.date("token_%Y%m%d%H%M")
                end
                GithubBrowserSettings.addToken(tname, token_string)
                
                if full_name then
                    GithubBrowserSettings.setTokenForRepo(full_name, tname)
                    UIManager:show(InfoMessage:new { text = _("Token saved and assigned!"), timeout = 2 })
                    local owner, repo = full_name:match("^([^/]+)/(.+)$")
                    GithubBrowserUI.openRepo(owner, repo, nil, nil, on_close)
                else
                    UIManager:show(InfoMessage:new { text = _("Token saved!"), timeout = 2 })
                    if on_close then on_close() end
                end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

-- ── Repo Input Dialog ─────────────────────────────────────────────────────────

function GithubBrowserUI.showRepoInputDialog(on_close, is_private)
    local dlg
    dlg = InputDialog:new {
        title = is_private and _("Open Private Repo") or _("Open Repository"),
        input = "",
        input_hint = _("owner/repo  or  github.com/owner/repo"),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function() UIManager:close(dlg) end,
            },
            {
                text = _("Browse"),
                is_enter_default = true,
                callback = function()
                    local inp = dlg:getInputText()
                    UIManager:close(dlg)
                    local owner, repo = GithubBrowserAPI.parseRepoInput(inp)
                    if not owner then
                        UIManager:show(InfoMessage:new {
                            text = _("Invalid format.\nUse: owner/repo\n  or: https://github.com/owner/repo"),
                            timeout = 4,
                        })
                        return
                    end
                    if is_private then
                        GithubBrowserUI.showTokenSelectMenu(owner, repo, on_close)
                    else
                        GithubBrowserUI.openRepo(owner, repo, nil, nil, on_close)
                    end
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

-- ── Open Repo / Browse Directory ──────────────────────────────────────────────

function GithubBrowserUI.openRepo(owner, repo, path, branch, on_close)
    local full_name = owner .. "/" .. repo

    -- If no branch yet, fetch repo metadata to get default branch
    if not branch then
        local loading = InfoMessage:new { text = _("Loading ..."), timeout = 30 }
        UIManager:show(loading)
        UIManager:forceRePaint()

        local meta, err = GithubBrowserAPI.getRepo(owner, repo)
        UIManager:close(loading)

        if not meta then
            UIManager:show(InfoMessage:new {
                text = _("Error: ") .. (err or "?"), timeout = 5,
            })
            return
        end

        branch = meta.default_branch or "main"
        GithubBrowserSettings.addRecentRepo(full_name)
    end

    -- Fetch directory contents
    local loading2 = InfoMessage:new { text = _("Loading ..."), timeout = 30 }
    UIManager:show(loading2)
    UIManager:forceRePaint()

    local contents, err2 = GithubBrowserAPI.getContents(owner, repo, path or "", branch)
    UIManager:close(loading2)

    if not contents then
        UIManager:show(InfoMessage:new {
            text = _("Error: ") .. (err2 or "?"), timeout = 5,
        })
        return
    end

    -- If API returned a single file object (not a directory listing)
    if contents.type == "file" then
        GithubBrowserUI.showFile(owner, repo, contents, branch)
        return
    end

    -- Sort: directories first, then alphabetical
    table.sort(contents, function(a, b)
        if a.type ~= b.type then return a.type == "dir" end
        return a.name:lower() < b.name:lower()
    end)

    local items = {}
    local is_root = not path or path == ""

    -- Back / Go up button (always at top)
    if is_root then
        table.insert(items, {
            text = "\u{ED0B} Back",
            callback = function(menu)
                UIManager:close(menu)
                if on_close then on_close() end
            end,
        })

        -- Bookmark / unbookmark toggle
        local is_saved = GithubBrowserSettings.isSavedRepo(full_name)
        table.insert(items, {
            text = is_saved and _("★  Remove bookmark") or _("☆  Bookmark this repo"),
            callback = function(menu)
                if is_saved then
                    GithubBrowserSettings.removeSavedRepo(full_name)
                    UIManager:show(InfoMessage:new {
                        text = _("Bookmark removed."), timeout = 2,
                    })
                else
                    GithubBrowserSettings.addSavedRepo(full_name)
                    UIManager:show(InfoMessage:new {
                        text = _("Bookmarked!"), timeout = 2,
                    })
                end
                UIManager:close(menu)
                -- Need to pass same path/branch so it doesn't lose state
                GithubBrowserUI.openRepo(owner, repo, path, branch, on_close)
            end,
        })

        -- Pin / unpin toggle
        local is_pinned = GithubBrowserSettings.isPinnedRepo(full_name)
        table.insert(items, {
            text = is_pinned and _("\u{EB03} Unpin from Home") or _("\u{EB02} Pin to Home"),
            callback = function(menu)
                if is_pinned then
                    GithubBrowserSettings.removePinnedRepo(full_name)
                    UIManager:show(InfoMessage:new {
                        text = _("Unpinned."), timeout = 2,
                    })
                else
                    GithubBrowserSettings.addPinnedRepo(full_name)
                    UIManager:show(InfoMessage:new {
                        text = _("Pinned!"), timeout = 2,
                    })
                end
                UIManager:close(menu)
                GithubBrowserUI.openRepo(owner, repo, path, branch, on_close)
            end,
        })

        -- Change Token for this repo
        local current_token_name = GithubBrowserSettings.getRepoTokens()[full_name] or _("Not set")
        table.insert(items, {
            text = _("\u{E60A} Change Token for this repo"),
            mandatory = current_token_name,
            callback = function(menu)
                UIManager:close(menu)
                GithubBrowserUI.showTokenSelectMenu(owner, repo, on_close)
            end,
        })

        table.insert(items, {
            text = _("\u{F414} Search files/folder"),
            callback = function(menu)
                UIManager:close(menu)
                GithubBrowserUI.promptSearchRepo(owner, repo, branch, "filename", on_close)
            end,
        })
        
        table.insert(items, {
            text = _("\u{E91D} Search code"),
            callback = function(menu)
                UIManager:close(menu)
                GithubBrowserUI.promptSearchRepo(owner, repo, branch, "code", on_close)
            end,
        })
    else
        local parent_path = path:match("^(.+)/[^/]+$") or ""
        table.insert(items, {
            text = "\u{ED22} ..",
            callback = function(menu)
                UIManager:close(menu)
            end,
        })
    end

    -- New file / folder buttons (only if token is available)
    local repo_token = GithubBrowserSettings.getTokenForRepo(full_name)
    if repo_token and repo_token ~= "" then
        table.insert(items, {
            text = _("\u{EA9B} New file here"),
            callback = function()
                GithubBrowserUI.createNewFile(owner, repo, path or "", branch, on_close)
            end,
        })
        table.insert(items, {
            text = _("\u{E956} New folder here"),
            callback = function()
                GithubBrowserUI.createNewFolder(owner, repo, path or "", branch, on_close)
            end,
        })
    end

    -- Separator
    if #items > 0 then
        table.insert(items, {
            text = "────────────────────",
            callback = function() end,
        })
    end

    -- Directory entries
    for i, entry in ipairs(contents) do
        if entry.type == "dir" then
            table.insert(items, {
                text = "\u{E94A} " .. entry.name .. "/",
                callback = function()
                    GithubBrowserUI.openRepo(owner, repo, entry.path, branch)
                end,
                hold_callback = function()
                    GithubBrowserUI.handleEntryHold(owner, repo, entry, branch, on_close)
                end,
            })
        else
            table.insert(items, {
                text = "\u{F016} " .. entry.name,
                mandatory = GithubBrowserAPI.formatSize(entry.size),
                callback = function()
                    GithubBrowserUI.showFile(owner, repo, entry, branch)
                end,
                hold_callback = function()
                    GithubBrowserUI.handleEntryHold(owner, repo, entry, branch, on_close)
                end,
            })
        end
    end

    -- Build title
    local title
    if is_root then
        title = full_name .. " [" .. branch .. "]"
    else
        title = full_name .. "/" .. path
    end

    UIManager:show(BrowserMenu:new {
        title      = title,
        item_table = items,
        on_close   = is_root and on_close or nil,
    })
end

-- ── Create New File ───────────────────────────────────────────────────────────

function GithubBrowserUI.createNewFile(owner, repo, dir_path, branch, on_close)
    local dlg
    dlg = InputDialog:new {
        title = _("New File Name"),
        input = "",
        input_hint = _("e.g. notes.md or subdir/file.txt"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function() UIManager:close(dlg) end,
            },
            {
                text = _("Next"),
                is_enter_default = true,
                callback = function()
                    local fname = dlg:getInputText()
                    UIManager:close(dlg)
                    fname = fname:match("^%s*(.-)%s*$")
                    if fname == "" then return end
                    local fpath = (dir_path ~= "" and dir_path .. "/" or "") .. fname
                    GithubBrowserUI._editNewFile(owner, repo, fpath, branch, on_close)
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function GithubBrowserUI._editNewFile(owner, repo, file_path, branch, on_close)
    local editor
    editor = InputDialog:new {
        title = _("New: ") .. file_path,
        input = "",
        allow_newline = true,
        fullscreen = true,
        buttons = {{
            {
                text = _("Cancel"),
                callback = function() UIManager:close(editor) end,
            },
            {
                text = _("💾 Commit"),
                is_enter_default = true,
                callback = function()
                    local content = editor:getInputText()
                    UIManager:close(editor)
                    -- For new files, sha is nil
                    GithubBrowserUI._askCommitMsg(owner, repo, file_path, content, nil, branch)
                end,
            },
        }},
    }
    UIManager:show(editor)
    editor:onShowKeyboard()
end

function GithubBrowserUI.createNewFolder(owner, repo, dir_path, branch, on_close)
    local dlg
    dlg = InputDialog:new {
        title = _("New Folder Name"),
        input = "",
        input_hint = _("e.g. my-notes"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function() UIManager:close(dlg) end,
            },
            {
                text = _("Create"),
                is_enter_default = true,
                callback = function()
                    local folder = dlg:getInputText()
                    UIManager:close(dlg)
                    folder = folder:match("^%s*(.-)%s*$")
                    if folder == "" then return end
                    -- GitHub needs a file to create a directory; use .gitkeep
                    local fpath = (dir_path ~= "" and dir_path .. "/" or "") .. folder .. "/.gitkeep"
                    GithubBrowserUI._askCommitMsg(owner, repo, fpath, "", nil, branch)
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function GithubBrowserUI.handleEntryHold(owner, repo, entry, branch, on_close)
    local token = GithubBrowserSettings.getTokenForRepo(owner .. "/" .. repo)
    
    if token and token ~= "" then
        -- Has write access -> Show Delete ConfirmBox
        UIManager:show(ConfirmBox:new {
            text = _("Are you sure you want to delete ") .. entry.name .. "?\n" .. (entry.type == "dir" and _("(This will recursively delete all files inside it)") or ""),
            ok_text = _("Delete"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                GithubBrowserUI._doDelete(owner, repo, entry, branch, token, on_close)
            end,
        })
    else
        -- No write access -> If file, show Download ConfirmBox
        if entry.type == "file" and entry.download_url then
            UIManager:show(ConfirmBox:new {
                text = string.format(_("Download \"%s\"?"), entry.name),
                ok_text = _("Download"),
                cancel_text = _("Cancel"),
                ok_callback = function()
                    GithubBrowserUI.downloadFile(entry.name, entry.download_url)
                end,
            })
        else
            UIManager:show(InfoMessage:new { text = _("Read-only. No actions available."), timeout = 2 })
        end
    end
end

function GithubBrowserUI._doDelete(owner, repo, entry, branch, token, on_close)
    local loading = InfoMessage:new { text = _("Deleting ..."), timeout = 120 }
    UIManager:show(loading)
    UIManager:forceRePaint()

    local device = GithubBrowserSettings.getDeviceName()
    local date_str = os.date("%m/%d/%Y, %I:%M:%S %p")
    local msg = string.format("Delete %s from %s on %s", entry.name, device, date_str)

    local ok, err
    if entry.type == "dir" then
        ok, err = GithubBrowserAPI.deleteDirectory(owner, repo, entry.path, branch, msg, token)
    else
        ok, err = GithubBrowserAPI.deleteFile(owner, repo, entry.path, entry.sha, branch, msg, token)
    end

    UIManager:close(loading)

    if not ok then
        UIManager:show(InfoMessage:new {
            text = _("Delete failed: ") .. (err or "?"),
            timeout = 6,
        })
        return
    end

    UIManager:show(InfoMessage:new {
        text = _("✅ Deleted!"),
        timeout = 2,
    })

    -- Auto-refresh: re-open the parent directory
    local parent_path = entry.path:match("^(.+)/[^/]+$") or ""
    UIManager:scheduleIn(1, function()
        GithubBrowserUI.openRepo(owner, repo, parent_path, branch, on_close)
    end)
end

-- ── Show File ─────────────────────────────────────────────────────────────────

function GithubBrowserUI.showFile(owner, repo, entry, branch)
    local name = entry.name or "file"
    local download_url = entry.download_url

    if isTextFile(name) and download_url then
        -- Fetch and display text content
        local loading = InfoMessage:new { text = _("Fetching ..."), timeout = 30 }
        UIManager:show(loading)
        UIManager:forceRePaint()

        local text, err = GithubBrowserAPI.getRawFile(download_url)
        UIManager:close(loading)

        if not text then
            UIManager:show(InfoMessage:new {
                text = _("Error: ") .. (err or "?"), timeout = 4,
            })
            return
        end

        -- Truncate very large files
        local truncated = false
        if #text > 50000 then
            text = text:sub(1, 50000)
            truncated = true
        end
        if truncated then
            text = text .. "\n\n── [ truncated at 50k chars ] ──"
        end

        local full_text = text
        local token = GithubBrowserSettings.getTokenForRepo(owner .. "/" .. repo)

        -- Build buttons
        local buttons = {}
        if token ~= "" and entry.path and entry.sha and not truncated then
            table.insert(buttons, {{
                text = _("\u{EAEB} Edit"),
                callback = function()
                    GithubBrowserUI.editFile(owner, repo, entry.path, full_text, entry.sha, branch)
                end,
            }})
        end
        if download_url then
            table.insert(buttons, {{
                text = _("\u{F317} Download"),
                callback = function()
                    GithubBrowserUI.downloadFile(name, download_url)
                end,
            }})
        end

        UIManager:show(TextViewer:new {
            title = name,
            text  = text,
            height = math.floor(Screen:getHeight() * 0.85),
            buttons_table = #buttons > 0 and buttons or nil,
        })

    elseif download_url then
        -- Binary / openable file — offer download
        UIManager:show(ConfirmBox:new {
            text = string.format(_("Download \"%s\"?"), name),
            ok_text = _("Download"),
            cancel_text = _("Cancel"),
            ok_callback = function()
                GithubBrowserUI.downloadFile(name, download_url)
            end,
        })
    else
        UIManager:show(InfoMessage:new {
            text = _("No download URL available."), timeout = 3,
        })
    end
end

-- ── Download File ─────────────────────────────────────────────────────────────

function GithubBrowserUI.downloadFile(name, url)
    local dir = GithubBrowserSettings.getDownloadDir()
    ensureDir(dir)
    local dest = dir .. "/" .. name

    local loading = InfoMessage:new { text = _("Downloading ..."), timeout = 60 }
    UIManager:show(loading)
    UIManager:forceRePaint()

    local ok, err = GithubBrowserAPI.downloadFile(url, dest)
    UIManager:close(loading)

    if not ok then
        UIManager:show(InfoMessage:new {
            text = _("Failed: ") .. (err or "?"), timeout = 4,
        })
        return
    end

    if isOpenable(name) then
        UIManager:show(ConfirmBox:new {
            text = string.format(_("Saved to:\n%s\n\nOpen now?"), dest),
            ok_text = _("Open"),
            cancel_text = _("Close"),
            ok_callback = function()
                local Event = require("ui/event")
                UIManager:broadcastEvent(Event:new("OpenDocument", dest))
            end,
        })
    else
        UIManager:show(InfoMessage:new {
            text = _("Saved to:\n") .. dest, timeout = 4,
        })
    end
end

-- ── Edit File ─────────────────────────────────────────────────────────────────

function GithubBrowserUI.editFile(owner, repo, file_path, original_text, sha, branch)
    local editor
    editor = InputDialog:new {
        title = _("Edit: ") .. (file_path:match("[^/]+$") or file_path),
        input = original_text,
        allow_newline = true,
        cursor_at_end = false,
        fullscreen = true,
        buttons = {{
            {
                text = _("Cancel"),
                callback = function() UIManager:close(editor) end,
            },
            {
                text = _("💾 Commit"),
                is_enter_default = true,
                callback = function()
                    local new_text = editor:getInputText()
                    UIManager:close(editor)
                    if new_text == original_text then
                        UIManager:show(InfoMessage:new { text = _("No changes."), timeout = 2 })
                        return
                    end
                    GithubBrowserUI._askCommitMsg(owner, repo, file_path, new_text, sha, branch)
                end,
            },
        }},
    }
    UIManager:show(editor)
    editor:onShowKeyboard()
end

function GithubBrowserUI._askCommitMsg(owner, repo, file_path, content, sha, branch)
    local name = file_path:match("[^/]+$") or file_path
    local dlg
    dlg = InputDialog:new {
        title = _("Commit Message"),
        input = "",
        input_hint = _("Leave blank for auto-generated msg"),
        description = string.format("%s/%s [%s]", owner, repo, branch),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function() UIManager:close(dlg) end,
            },
            {
                text = _("Commit"),
                is_enter_default = true,
                callback = function()
                    local msg = dlg:getInputText()
                    UIManager:close(dlg)
                    
                    local device = GithubBrowserSettings.getDeviceName()
                    
                    if not msg or msg:match("^%s*$") then
                        local date_str = os.date("%m/%d/%Y, %I:%M:%S %p")
                        -- Format: Update Untitled from RIGHT9xOS on 5/11/2026, 8:08:47 PM
                        msg = string.format("Update %s from %s on %s", name, device, date_str)
                    else
                        -- Append device name for custom messages
                        msg = msg .. "\n\nby " .. device
                    end
                    
                    GithubBrowserUI._doCommit(owner, repo, file_path, content, sha, branch, msg)
                end,
            },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function GithubBrowserUI._doCommit(owner, repo, file_path, content, sha, branch, msg)
    local loading = InfoMessage:new { text = _("Committing ..."), timeout = 60 }
    UIManager:show(loading)
    UIManager:forceRePaint()

    local token = GithubBrowserSettings.getTokenForRepo(owner .. "/" .. repo)
    local result, err = GithubBrowserAPI.updateFile(owner, repo, file_path, content, sha, branch, msg, token)
    UIManager:close(loading)

    if not result then
        UIManager:show(InfoMessage:new {
            text = _("Commit failed: ") .. (err or "?"),
            timeout = 6,
        })
        return
    end

    local csha = (result.commit and result.commit.sha) and result.commit.sha:sub(1, 7) or ""
    UIManager:show(InfoMessage:new {
        text = _("✅ Committed! ") .. csha,
        timeout = 2,
    })

    -- Auto-refresh: re-open the parent directory
    local parent_path = file_path:match("^(.+)/[^/]+$") or ""
    UIManager:scheduleIn(1, function()
        GithubBrowserUI.openRepo(owner, repo, parent_path, branch)
    end)
end

function GithubBrowserUI.promptSearchRepo(owner, repo, branch, search_type, on_close)
    local InputDialog = require("ui/widget/inputdialog")
    local title = search_type == "filename" and _("Search files/folder in repo") or _("Search code in repo")
    
    local dlg
    dlg = InputDialog:new {
        title = title,
        input = "",
        input_type = "string",
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function()
                UIManager:close(dlg)
                GithubBrowserUI.openRepo(owner, repo, "", branch, on_close)
            end },
            { text = _("Search"), is_enter = true, callback = function()
                local query = dlg:getInputValue()
                UIManager:close(dlg)
                if query and query ~= "" then
                    if search_type == "filename" then
                        GithubBrowserUI.searchRepoFilenames(owner, repo, branch, query, on_close)
                    else
                        GithubBrowserUI.searchRepoCode(owner, repo, branch, query, on_close)
                    end
                else
                    GithubBrowserUI.openRepo(owner, repo, "", branch, on_close)
                end
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function GithubBrowserUI.searchRepoFilenames(owner, repo, branch, query, on_close)
    local loading = InfoMessage:new { text = _("Fetching repository tree..."), timeout = 0 }
    UIManager:show(loading)
    UIManager:forceRePaint()

    local tree_data, err = GithubBrowserAPI.getTree(owner, repo, branch)
    UIManager:close(loading)

    if not tree_data or not tree_data.tree then
        UIManager:show(InfoMessage:new { text = _("Search failed: ") .. (err or "?"), timeout = 4 })
        GithubBrowserUI.openRepo(owner, repo, "", branch, on_close)
        return
    end

    local query_lower = query:lower()
    local results = {}
    for _, item in ipairs(tree_data.tree) do
        if item.type == "blob" and item.path:lower():find(query_lower, 1, true) then
            table.insert(results, item)
            if #results >= 100 then break end
        end
    end

    GithubBrowserUI.showSearchResults(owner, repo, branch, query, results, on_close, "filename")
end

function GithubBrowserUI.searchRepoCode(owner, repo, branch, query, on_close)
    local loading = InfoMessage:new { text = _("Searching code..."), timeout = 0 }
    UIManager:show(loading)
    UIManager:forceRePaint()

    local data, err = GithubBrowserAPI.searchCode(owner, repo, query)
    UIManager:close(loading)

    if not data then
        local msg = err or "?"
        if msg:find("HTTP 401") or msg:find("HTTP 403") or msg:find("Requires authentication") then
            msg = _("Rate limit exceeded or token required.\nPlease add a GitHub Token in settings.")
        end
        UIManager:show(InfoMessage:new { text = _("Search failed: ") .. msg, timeout = 5 })
        GithubBrowserUI.openRepo(owner, repo, "", branch, on_close)
        return
    end

    local results = {}
    if data.items then
        for _, item in ipairs(data.items) do
            local snippet = ""
            if item.text_matches and #item.text_matches > 0 then
                snippet = item.text_matches[1].fragment or ""
                snippet = snippet:gsub("[\r\n\t]+", " ")
                if #snippet > 80 then snippet = snippet:sub(1, 80) .. "..." end
            end
            table.insert(results, {
                path = item.path,
                type = "blob",
                snippet = snippet,
                url = item.html_url
            })
        end
    end

    GithubBrowserUI.showSearchResults(owner, repo, branch, query, results, on_close, "code")
end

function GithubBrowserUI.showSearchResults(owner, repo, branch, query, results, on_close, search_type)
    local items = {}
    
    table.insert(items, {
        text = "\u{ED0B} Back to repo root",
        callback = function(menu)
            UIManager:close(menu)
            GithubBrowserUI.openRepo(owner, repo, "", branch, on_close)
        end,
    })

    if #results == 0 then
        table.insert(items, { text = _("No matching files found."), unselectable = true })
    else
        table.sort(results, function(a, b) return a.path:lower() < b.path:lower() end)
        for _, item in ipairs(results) do
            local file_name = item.path:match("([^/]+)$") or item.path
            local dir_path = item.path:match("^(.*)/[^/]+$") or ""
            local size_str = item.size and GithubBrowserAPI.formatSize(item.size) or ""
            
            local mandatory_str = size_str ~= "" and size_str or dir_path
            if item.snippet and item.snippet ~= "" then
                mandatory_str = item.snippet
            end
            
            local icon = search_type == "code" and "\u{E91D} " or "\u{F414} "
            
            table.insert(items, {
                text = icon .. file_name,
                mandatory = mandatory_str,
                callback = function(menu)
                    UIManager:close(menu)
                    GithubBrowserUI.openRepo(owner, repo, item.path, branch, function()
                        GithubBrowserUI.showSearchResults(owner, repo, branch, query, results, on_close, search_type)
                    end)
                end,
            })
        end
    end

    UIManager:show(BrowserMenu:new {
        title = string.format(_("Search Results: '%s' (%d)"), query, #results),
        item_table = items,
        on_close = on_close,
    })
end

return GithubBrowserUI
