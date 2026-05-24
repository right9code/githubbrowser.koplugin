--[[--
Minimal settings for the Github Browser plugin.
Phase 1: Recent repos + download directory only.
--]]--

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

-- ── Recent Repos ──────────────────────────────────────────────────────────────

function GithubBrowserSettings.getRecentRepos()
    return settings():readSetting("recent_repos") or {}
end

function GithubBrowserSettings.addRecentRepo(full_name)
    local recent = GithubBrowserSettings.getRecentRepos()
    -- Remove if already exists (we'll re-add at front)
    for i, v in ipairs(recent) do
        if v == full_name then table.remove(recent, i); break end
    end
    table.insert(recent, 1, full_name)
    local max = GithubBrowserSettings.getMaxRecentRepos()
    while #recent > max do table.remove(recent) end
    settings():saveSetting("recent_repos", recent)
    settings():flush()
end

function GithubBrowserSettings.clearRecentRepos()
    settings():saveSetting("recent_repos", {})
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
        or (DataStorage:getDataDir() .. "/github_downloads")
end

function GithubBrowserSettings.setDownloadDir(dir)
    settings():saveSetting("download_dir", dir)
    settings():flush()
end

-- ── Saved / Bookmarked Repos ──────────────────────────────────────────────────

function GithubBrowserSettings.getSavedRepos()
    return settings():readSetting("saved_repos") or {}
end

function GithubBrowserSettings.addSavedRepo(full_name)
    local saved = GithubBrowserSettings.getSavedRepos()
    for i, v in ipairs(saved) do
        if v == full_name then return end  -- already saved
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

-- ── GitHub Tokens (Multi-Token) ───────────────────────────────────────────────

function GithubBrowserSettings.getTokens()
    local tokens = settings():readSetting("github_tokens")
    if not tokens then
        tokens = {}
        local old_token = settings():readSetting("github_token")
        if old_token and old_token ~= "" then
            tokens["Default Token"] = old_token
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
        
        -- Update any repos using this token
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
    
    -- Fallback: use the designated default token
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

function GithubBrowserSettings.isSavedRepo(full_name)
    for i, v in ipairs(GithubBrowserSettings.getSavedRepos()) do
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
    for _, v in ipairs(pinned) do
        if v == full_name then return end
    end
    table.insert(pinned, full_name)
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
    for _, v in ipairs(GithubBrowserSettings.getPinnedRepos()) do
        if v == full_name then return true end
    end
    return false
end

function GithubBrowserSettings.togglePinnedRepo(full_name)
    if GithubBrowserSettings.isPinnedRepo(full_name) then
        GithubBrowserSettings.removePinnedRepo(full_name)
        return false
    else
        GithubBrowserSettings.addPinnedRepo(full_name)
        return true
    end
end

return GithubBrowserSettings
