local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local GitNotesSettings = {}

local _settings

local function settings()
    if not _settings then
        _settings = LuaSettings:open(
            DataStorage:getSettingsDir() .. "/githubbrowser.lua"
        )
    end
    return _settings
end

function GitNotesSettings.flush()
    settings():flush()
end

-- ── Repo Registry ─────────────────────────────────────────────────────────────

function GitNotesSettings.getRepoRegistry()
    return settings():readSetting("repo_registry") or {}
end

function GitNotesSettings.getRepoInfo(full_name)
    local reg = GitNotesSettings.getRepoRegistry()
    return reg[full_name]
end

function GitNotesSettings.setRepoInfo(full_name, info)
    local reg = GitNotesSettings.getRepoRegistry()
    reg[full_name] = info
    settings():saveSetting("repo_registry", reg)
    settings():flush()
end

function GitNotesSettings.removeRepoInfo(full_name)
    local reg = GitNotesSettings.getRepoRegistry()
    reg[full_name] = nil
    settings():saveSetting("repo_registry", reg)
    settings():flush()
end

function GitNotesSettings.isAttached(full_name)
    local info = GitNotesSettings.getRepoInfo(full_name)
    return info and info.mode == "attached" and info.local_path ~= nil
end

function GitNotesSettings.getLocalPath(full_name)
    local info = GitNotesSettings.getRepoInfo(full_name)
    return info and info.local_path
end

function GitNotesSettings.getAttachedRepos()
    local reg = GitNotesSettings.getRepoRegistry()
    local result = {}
    for name, info in pairs(reg) do
        if info.mode == "attached" then
            table.insert(result, {
                full_name = name,
                local_path = info.local_path,
                branch = info.branch,
                last_sync_hash = info.last_sync_hash,
                last_sync_time = info.last_sync_time,
            })
        end
    end
    table.sort(result, function(a, b) return a.full_name < b.full_name end)
    return result
end

function GitNotesSettings.updateSyncInfo(full_name, hash)
    local reg = GitNotesSettings.getRepoRegistry()
    if reg[full_name] then
        reg[full_name].last_sync_hash = hash
        reg[full_name].last_sync_time = os.time()
        settings():saveSetting("repo_registry", reg)
        settings():flush()
    end
end

-- ── Recent Repos ──────────────────────────────────────────────────────────────

function GitNotesSettings.getRecentRepos()
    return settings():readSetting("recent_repos") or {}
end

function GitNotesSettings.addRecentRepo(full_name)
    local recent = GitNotesSettings.getRecentRepos()
    for i, v in ipairs(recent) do
        if v == full_name then table.remove(recent, i); break end
    end
    table.insert(recent, 1, full_name)
    local max = GitNotesSettings.getMaxRecentRepos()
    while #recent > max do table.remove(recent) end
    settings():saveSetting("recent_repos", recent)
    settings():flush()
end

function GitNotesSettings.removeRecentRepo(full_name)
    local recent = GitNotesSettings.getRecentRepos()
    for i, v in ipairs(recent) do
        if v == full_name then table.remove(recent, i); break end
    end
    settings():saveSetting("recent_repos", recent)
    settings():flush()
end

function GitNotesSettings.clearRecentRepos()
    settings():saveSetting("recent_repos", {})
    settings():flush()
end

-- ── Max Recent Repos ──────────────────────────────────────────────────────────

function GitNotesSettings.getMaxRecentRepos()
    return settings():readSetting("max_recent_repos") or 20
end

function GitNotesSettings.setMaxRecentRepos(count)
    settings():saveSetting("max_recent_repos", count)
    settings():flush()
end

-- ── Download Directory ────────────────────────────────────────────────────────

function GitNotesSettings.getDownloadDir()
    return settings():readSetting("download_dir")
        or (DataStorage:getDataDir() .. "/githubbrowser_downloads")
end

function GitNotesSettings.setDownloadDir(dir)
    settings():saveSetting("download_dir", dir)
    settings():flush()
end

-- ── Git Workspace ─────────────────────────────────────────────────────────────

function GitNotesSettings.getWorkspace()
    return settings():readSetting("git_workspace")
        or (DataStorage:getDataDir() .. "/git_repos")
end

function GitNotesSettings.setWorkspace(dir)
    settings():saveSetting("git_workspace", dir)
    settings():flush()
end

-- ── Saved / Bookmarked Repos ──────────────────────────────────────────────────

function GitNotesSettings.getSavedRepos()
    return settings():readSetting("saved_repos") or {}
end

function GitNotesSettings.addSavedRepo(full_name)
    local saved = GitNotesSettings.getSavedRepos()
    for _, v in ipairs(saved) do
        if v == full_name then return end
    end
    table.insert(saved, 1, full_name)
    settings():saveSetting("saved_repos", saved)
    settings():flush()
end

function GitNotesSettings.removeSavedRepo(full_name)
    local saved = GitNotesSettings.getSavedRepos()
    for i, v in ipairs(saved) do
        if v == full_name then table.remove(saved, i); break end
    end
    settings():saveSetting("saved_repos", saved)
    settings():flush()
end

function GitNotesSettings.clearSavedRepos()
    settings():saveSetting("saved_repos", {})
    settings():flush()
end

function GitNotesSettings.isSavedRepo(full_name)
    for _, v in ipairs(GitNotesSettings.getSavedRepos()) do
        if v == full_name then return true end
    end
    return false
end

-- ── Pinned Repos ──────────────────────────────────────────────────────────────

function GitNotesSettings.getPinnedRepos()
    return settings():readSetting("pinned_repos") or {}
end

function GitNotesSettings.addPinnedRepo(full_name)
    local pinned = GitNotesSettings.getPinnedRepos()
    for _, v in ipairs(pinned) do
        if v == full_name then return end
    end
    table.insert(pinned, full_name)
    settings():saveSetting("pinned_repos", pinned)
    settings():flush()
end

function GitNotesSettings.removePinnedRepo(full_name)
    local pinned = GitNotesSettings.getPinnedRepos()
    for i, v in ipairs(pinned) do
        if v == full_name then table.remove(pinned, i); break end
    end
    settings():saveSetting("pinned_repos", pinned)
    settings():flush()
end

function GitNotesSettings.isPinnedRepo(full_name)
    for _, v in ipairs(GitNotesSettings.getPinnedRepos()) do
        if v == full_name then return true end
    end
    return false
end

-- ── GitHub Tokens ─────────────────────────────────────────────────────────────

function GitNotesSettings.getTokens()
    local tokens = settings():readSetting("github_tokens")
    if not tokens then
        tokens = {}
        local old = settings():readSetting("github_token")
        if old and old ~= "" then
            tokens["Default Token"] = old
            settings():saveSetting("github_token", nil)
        end
        settings():saveSetting("github_tokens", tokens)
        settings():flush()
    end
    return tokens
end

function GitNotesSettings.addToken(name, token)
    local tokens = GitNotesSettings.getTokens()
    tokens[name] = token
    settings():saveSetting("github_tokens", tokens)
    settings():flush()
end

function GitNotesSettings.deleteToken(name)
    local tokens = GitNotesSettings.getTokens()
    tokens[name] = nil
    settings():saveSetting("github_tokens", tokens)
    settings():flush()
end

function GitNotesSettings.renameToken(old_name, new_name)
    local tokens = GitNotesSettings.getTokens()
    if tokens[old_name] then
        tokens[new_name] = tokens[old_name]
        tokens[old_name] = nil
        settings():saveSetting("github_tokens", tokens)
        local rtokens = GitNotesSettings.getRepoTokens()
        local changed = false
        for repo, tname in pairs(rtokens) do
            if tname == old_name then
                rtokens[repo] = new_name
                changed = true
            end
        end
        if changed then
            settings():saveSetting("repo_tokens", rtokens)
        end
        settings():flush()
    end
end

function GitNotesSettings.getRepoTokens()
    return settings():readSetting("repo_tokens") or {}
end

function GitNotesSettings.setTokenForRepo(full_name, token_name)
    if not full_name then return end
    local rtokens = GitNotesSettings.getRepoTokens()
    rtokens[full_name] = token_name
    settings():saveSetting("repo_tokens", rtokens)
    settings():flush()
end

function GitNotesSettings.getTokenForRepo(full_name)
    local tokens = GitNotesSettings.getTokens()
    local rtokens = GitNotesSettings.getRepoTokens()

    if full_name and rtokens[full_name] then
        local t = tokens[rtokens[full_name]]
        if t and t ~= "" then return t end
    end

    local default_name = GitNotesSettings.getDefaultTokenName()
    if default_name and tokens[default_name] then
        return tokens[default_name]
    end

    return ""
end

function GitNotesSettings.getDefaultTokenName()
    return settings():readSetting("default_token_name") or nil
end

function GitNotesSettings.setDefaultTokenName(name)
    settings():saveSetting("default_token_name", name)
    settings():flush()
end

-- ── Device Name ───────────────────────────────────────────────────────────────

function GitNotesSettings.getDeviceName()
    return settings():readSetting("device_name") or "koreader"
end

function GitNotesSettings.setDeviceName(name)
    settings():saveSetting("device_name", name)
    settings():flush()
end

-- ── Sync Settings ─────────────────────────────────────────────────────────────

function GitNotesSettings.getAutoSyncOnOpen()
    return settings():nilOrTrue("auto_sync_on_open")
end

function GitNotesSettings.setAutoSyncOnOpen(val)
    settings():saveSetting("auto_sync_on_open", val)
    settings():flush()
end

function GitNotesSettings.getShallowCloneDefault()
    return settings():hasNot("shallow_clone_default") and false
        or settings():isTrue("shallow_clone_default")
end

function GitNotesSettings.setShallowCloneDefault(val)
    settings():saveSetting("shallow_clone_default", val)
    settings():flush()
end

-- ── Editor Settings ───────────────────────────────────────────────────────────

function GitNotesSettings.getFontFace()
    return settings():readSetting("font_face") or "infont"
end

function GitNotesSettings.setFontFace(face)
    settings():saveSetting("font_face", face)
    settings():flush()
end

function GitNotesSettings.getFontSize()
    return settings():readSetting("font_size") or 20
end

function GitNotesSettings.setFontSize(size)
    settings():saveSetting("font_size", size)
    settings():flush()
end

function GitNotesSettings.getShowKeyboardOnStart()
    return settings():nilOrTrue("show_keyboard_on_start")
end

function GitNotesSettings.setShowKeyboardOnStart(val)
    settings():saveSetting("show_keyboard_on_start", val)
    settings():flush()
end

function GitNotesSettings.getUndoStackSize()
    return settings():readSetting("undo_stack_size") or 100
end

function GitNotesSettings.setUndoStackSize(size)
    settings():saveSetting("undo_stack_size", size)
    settings():flush()
end

function GitNotesSettings.getTabSize()
    return settings():readSetting("tab_size") or 4
end

function GitNotesSettings.setTabSize(size)
    settings():saveSetting("tab_size", size)
    settings():flush()
end

-- ── Ignore Patterns ───────────────────────────────────────────────────────────

function GitNotesSettings.getIgnorePatterns()
    return settings():readSetting("ignore_patterns") or {".sdr", ".koreader", "*.tmp", ".DS_Store"}
end

function GitNotesSettings.setIgnorePatterns(patterns)
    settings():saveSetting("ignore_patterns", patterns)
    settings():flush()
end

function GitNotesSettings.addIgnorePattern(pattern)
    local patterns = GitNotesSettings.getIgnorePatterns()
    for _, p in ipairs(patterns) do
        if p == pattern then return end
    end
    table.insert(patterns, pattern)
    settings():saveSetting("ignore_patterns", patterns)
    settings():flush()
end

function GitNotesSettings.removeIgnorePattern(pattern)
    local patterns = GitNotesSettings.getIgnorePatterns()
    for i, p in ipairs(patterns) do
        if p == pattern then table.remove(patterns, i); break end
    end
    settings():saveSetting("ignore_patterns", patterns)
    settings():flush()
end

-- ── Quick Repo (for gesture shortcut) ────────────────────────────────────────

function GitNotesSettings.getQuickRepo()
    return settings():readSetting("quick_repo") or ""
end

function GitNotesSettings.setQuickRepo(repo)
    settings():saveSetting("quick_repo", repo)
    settings():flush()
end

return GitNotesSettings
