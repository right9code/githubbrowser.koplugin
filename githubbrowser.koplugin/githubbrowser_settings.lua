local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local GithubBrowserSettings = {}

local _settings

local function settings()
    if not _settings then
        _settings = LuaSettings:open(
            DataStorage:getSettingsDir() .. "/githubbrowser.lua"
        )
    end
    return _settings
end

function GithubBrowserSettings.flush()
    settings():flush()
end

-- ── Repo Registry ─────────────────────────────────────────────────────────────

function GithubBrowserSettings.getRepoRegistry()
    return settings():readSetting("repo_registry") or {}
end

function GithubBrowserSettings.getRepoInfo(full_name)
    local reg = GithubBrowserSettings.getRepoRegistry()
    return reg[full_name]
end

function GithubBrowserSettings.setRepoInfo(full_name, info)
    local reg = GithubBrowserSettings.getRepoRegistry()
    reg[full_name] = info
    settings():saveSetting("repo_registry", reg)
    settings():flush()
end

function GithubBrowserSettings.removeRepoInfo(full_name)
    local reg = GithubBrowserSettings.getRepoRegistry()
    reg[full_name] = nil
    settings():saveSetting("repo_registry", reg)
    settings():flush()
end

function GithubBrowserSettings.isAttached(full_name)
    local info = GithubBrowserSettings.getRepoInfo(full_name)
    return info and info.mode == "attached" and info.local_path ~= nil
end

function GithubBrowserSettings.getLocalPath(full_name)
    local info = GithubBrowserSettings.getRepoInfo(full_name)
    return info and info.local_path
end

function GithubBrowserSettings.getAttachedRepos()
    local reg = GithubBrowserSettings.getRepoRegistry()
    local result = {}
    for name, info in pairs(reg) do
        if info.mode == "attached" then
            result[#result + 1] = {
                full_name = name,
                local_path = info.local_path,
                branch = info.branch,
                last_sync_hash = info.last_sync_hash,
                last_sync_time = info.last_sync_time,
            }
        end
    end
    table.sort(result, function(a, b) return a.full_name < b.full_name end)
    return result
end

function GithubBrowserSettings.updateSyncInfo(full_name, hash)
    local reg = GithubBrowserSettings.getRepoRegistry()
    if reg[full_name] then
        reg[full_name].last_sync_hash = hash
        reg[full_name].last_sync_time = os.time()
        settings():saveSetting("repo_registry", reg)
        settings():flush()
    end
end

-- ── Recent Repos ──────────────────────────────────────────────────────────────

function GithubBrowserSettings.getRecentRepos()
    return settings():readSetting("recent_repos") or {}
end

function GithubBrowserSettings.addRecentRepo(full_name)
    local recent = GithubBrowserSettings.getRecentRepos()
    for i, v in ipairs(recent) do
        if v == full_name then table.remove(recent, i); break end
    end
    table.insert(recent, 1, full_name)
    local max = GithubBrowserSettings.getMaxRecentRepos()
    while #recent > max do table.remove(recent) end
    settings():saveSetting("recent_repos", recent)
    settings():flush()
end

function GithubBrowserSettings.removeRecentRepo(full_name)
    local recent = GithubBrowserSettings.getRecentRepos()
    for i, v in ipairs(recent) do
        if v == full_name then table.remove(recent, i); break end
    end
    settings():saveSetting("recent_repos", recent)
    settings():flush()
end

function GithubBrowserSettings.clearRecentRepos()
    settings():saveSetting("recent_repos", {})
    settings():flush()
end

-- ── Max Recent Repos ──────────────────────────────────────────────────────────

function GithubBrowserSettings.getMaxRecentRepos()
    return settings():readSetting("max_recent_repos") or 20
end

function GithubBrowserSettings.setMaxRecentRepos(count)
    settings():saveSetting("max_recent_repos", count)
    settings():flush()
end

-- ── Download Directory ────────────────────────────────────────────────────────

function GithubBrowserSettings.getDownloadDir()
    return settings():readSetting("download_dir")
        or (DataStorage:getDataDir() .. "/githubbrowser_downloads")
end

function GithubBrowserSettings.setDownloadDir(dir)
    settings():saveSetting("download_dir", dir)
    settings():flush()
end

-- ── Git Workspace ─────────────────────────────────────────────────────────────

function GithubBrowserSettings.getWorkspace()
    return settings():readSetting("git_workspace")
        or (DataStorage:getDataDir() .. "/git_repos")
end

function GithubBrowserSettings.setWorkspace(dir)
    settings():saveSetting("git_workspace", dir)
    settings():flush()
end

-- ── Saved / Bookmarked Repos ──────────────────────────────────────────────────

function GithubBrowserSettings.getSavedRepos()
    return settings():readSetting("saved_repos") or {}
end

function GithubBrowserSettings.addSavedRepo(full_name)
    local saved = GithubBrowserSettings.getSavedRepos()
    for __, v in ipairs(saved) do
        if v == full_name then return end
    end
    table.insert(saved, 1, full_name)
    settings():saveSetting("saved_repos", saved)
    settings():flush()
end

function GithubBrowserSettings.removeSavedRepo(full_name)
    local saved = GithubBrowserSettings.getSavedRepos()
    for i, v in ipairs(saved) do
        if v == full_name then table.remove(saved, i); break end
    end
    settings():saveSetting("saved_repos", saved)
    settings():flush()
end

function GithubBrowserSettings.clearSavedRepos()
    settings():saveSetting("saved_repos", {})
    settings():flush()
end

function GithubBrowserSettings.isSavedRepo(full_name)
    for __, v in ipairs(GithubBrowserSettings.getSavedRepos()) do
        if v == full_name then return true end
    end
    return false
end

-- ── Pinned Repos ──────────────────────────────────────────────────────────────

function GithubBrowserSettings.getPinnedRepos()
    return settings():readSetting("pinned_repos") or {}
end

function GithubBrowserSettings.addPinnedRepo(full_name)
    local pinned = GithubBrowserSettings.getPinnedRepos()
    for __, v in ipairs(pinned) do
        if v == full_name then return end
    end
    pinned[#pinned + 1] = full_name
    settings():saveSetting("pinned_repos", pinned)
    settings():flush()
end

function GithubBrowserSettings.removePinnedRepo(full_name)
    local pinned = GithubBrowserSettings.getPinnedRepos()
    for i, v in ipairs(pinned) do
        if v == full_name then table.remove(pinned, i); break end
    end
    settings():saveSetting("pinned_repos", pinned)
    settings():flush()
end

function GithubBrowserSettings.isPinnedRepo(full_name)
    for __, v in ipairs(GithubBrowserSettings.getPinnedRepos()) do
        if v == full_name then return true end
    end
    return false
end

-- ── GitHub Tokens ─────────────────────────────────────────────────────────────

function GithubBrowserSettings.getTokens()
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

function GithubBrowserSettings.addToken(name, token)
    local tokens = GithubBrowserSettings.getTokens()
    tokens[name] = token
    settings():saveSetting("github_tokens", tokens)
    settings():flush()
end

function GithubBrowserSettings.deleteToken(name)
    local tokens = GithubBrowserSettings.getTokens()
    tokens[name] = nil
    settings():saveSetting("github_tokens", tokens)
    settings():flush()
end

function GithubBrowserSettings.renameToken(old_name, new_name)
    local tokens = GithubBrowserSettings.getTokens()
    if tokens[old_name] then
        tokens[new_name] = tokens[old_name]
        tokens[old_name] = nil
        settings():saveSetting("github_tokens", tokens)
        local rtokens = GithubBrowserSettings.getRepoTokens()
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

function GithubBrowserSettings.getRepoTokens()
    return settings():readSetting("repo_tokens") or {}
end

function GithubBrowserSettings.setTokenForRepo(full_name, token_name)
    if not full_name then return end
    local rtokens = GithubBrowserSettings.getRepoTokens()
    rtokens[full_name] = token_name
    settings():saveSetting("repo_tokens", rtokens)
    settings():flush()
end

function GithubBrowserSettings.getTokenForRepo(full_name)
    local tokens = GithubBrowserSettings.getTokens()
    local rtokens = GithubBrowserSettings.getRepoTokens()

    if full_name and rtokens[full_name] then
        local t = tokens[rtokens[full_name]]
        if t and t ~= "" then return t end
    end

    local default_name = GithubBrowserSettings.getDefaultTokenName()
    if default_name and tokens[default_name] then
        return tokens[default_name]
    end

    return ""
end

function GithubBrowserSettings.getDefaultTokenName()
    return settings():readSetting("default_token_name") or nil
end

function GithubBrowserSettings.setDefaultTokenName(name)
    settings():saveSetting("default_token_name", name)
    settings():flush()
end

-- ── Device Name ───────────────────────────────────────────────────────────────

function GithubBrowserSettings.getDeviceName()
    return settings():readSetting("device_name") or "koreader"
end

function GithubBrowserSettings.setDeviceName(name)
    settings():saveSetting("device_name", name)
    settings():flush()
end

-- ── Sync Settings ─────────────────────────────────────────────────────────────

function GithubBrowserSettings.getAutoSyncOnOpen()
    return settings():nilOrTrue("auto_sync_on_open")
end

function GithubBrowserSettings.setAutoSyncOnOpen(val)
    settings():saveSetting("auto_sync_on_open", val)
    settings():flush()
end

function GithubBrowserSettings.getShallowCloneDefault()
    return settings():hasNot("shallow_clone_default") and false
        or settings():isTrue("shallow_clone_default")
end

function GithubBrowserSettings.setShallowCloneDefault(val)
    settings():saveSetting("shallow_clone_default", val)
    settings():flush()
end

-- ── Editor Settings ───────────────────────────────────────────────────────────

function GithubBrowserSettings.getFontFace()
    return settings():readSetting("font_face") or "infont"
end

function GithubBrowserSettings.setFontFace(face)
    settings():saveSetting("font_face", face)
    settings():flush()
end

function GithubBrowserSettings.getFontSize()
    return settings():readSetting("font_size") or 20
end

function GithubBrowserSettings.setFontSize(size)
    settings():saveSetting("font_size", size)
    settings():flush()
end

function GithubBrowserSettings.getShowKeyboardOnStart()
    return settings():nilOrTrue("show_keyboard_on_start")
end

function GithubBrowserSettings.setShowKeyboardOnStart(val)
    settings():saveSetting("show_keyboard_on_start", val)
    settings():flush()
end

function GithubBrowserSettings.getUndoStackSize()
    return settings():readSetting("undo_stack_size") or 100
end

function GithubBrowserSettings.setUndoStackSize(size)
    settings():saveSetting("undo_stack_size", size)
    settings():flush()
end

function GithubBrowserSettings.getTabSize()
    return settings():readSetting("tab_size") or 4
end

function GithubBrowserSettings.setTabSize(size)
    settings():saveSetting("tab_size", size)
    settings():flush()
end

-- ── Ignore Patterns ───────────────────────────────────────────────────────────

function GithubBrowserSettings.getIgnorePatterns()
    return settings():readSetting("ignore_patterns") or {".sdr", ".koreader", "*.tmp", ".DS_Store"}
end

function GithubBrowserSettings.setIgnorePatterns(patterns)
    settings():saveSetting("ignore_patterns", patterns)
    settings():flush()
end

function GithubBrowserSettings.addIgnorePattern(pattern)
    local patterns = GithubBrowserSettings.getIgnorePatterns()
    for __, p in ipairs(patterns) do
        if p == pattern then return end
    end
    patterns[#patterns + 1] = pattern
    settings():saveSetting("ignore_patterns", patterns)
    settings():flush()
end

function GithubBrowserSettings.removeIgnorePattern(pattern)
    local patterns = GithubBrowserSettings.getIgnorePatterns()
    for i, p in ipairs(patterns) do
        if p == pattern then table.remove(patterns, i); break end
    end
    settings():saveSetting("ignore_patterns", patterns)
    settings():flush()
end

-- ── Quick Repos (for gesture shortcuts) ──────────────────────────────────────

function GithubBrowserSettings.getQuickRepo()
    local repos = GithubBrowserSettings.getQuickRepos()
    return repos[1] or ""
end

function GithubBrowserSettings.getQuickRepos()
    -- Migrate from old single quick_repo if present
    local old = settings():readSetting("quick_repo")
    if old and old ~= "" then
        settings():saveSetting("quick_repos", { old })
        settings():saveSetting("quick_repo", nil)
        settings():flush()
    end
    return settings():readSetting("quick_repos") or {}
end

function GithubBrowserSettings.setQuickRepos(repos)
    settings():saveSetting("quick_repos", repos)
    settings():flush()
end

function GithubBrowserSettings.addQuickRepo(repo)
    local repos = GithubBrowserSettings.getQuickRepos()
    for __, r in ipairs(repos) do
        if r == repo then return end
    end
    repos[#repos + 1] = repo
    settings():saveSetting("quick_repos", repos)
    settings():flush()
end

function GithubBrowserSettings.removeQuickRepo(repo)
    local repos = GithubBrowserSettings.getQuickRepos()
    for i, r in ipairs(repos) do
        if r == repo then table.remove(repos, i); break end
    end
    settings():saveSetting("quick_repos", repos)
    settings():flush()
end

function GithubBrowserSettings.setQuickRepo(repo)
    -- Keep backward compat: set first entry
    local repos = GithubBrowserSettings.getQuickRepos()
    if repo == "" then
        if #repos > 0 then table.remove(repos, 1) end
    else
        repos[1] = repo
    end
    settings():saveSetting("quick_repos", repos)
    settings():flush()
end

return GithubBrowserSettings
