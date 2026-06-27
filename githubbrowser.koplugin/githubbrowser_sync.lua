local logger = require("logger")
local GitOps = require("githubbrowser_git")

local SyncEngine = {}

function SyncEngine.checkStatus(repo_path, branch)
    -- Compare local snapshot hash vs remote HEAD hash
    local local_ok = GitOps.fetch(repo_path)
    if not local_ok then
        return "fetch_failed", "Could not reach remote."
    end

    local remote_sha = GitOps.fetchRemoteHead(repo_path)
    if not remote_sha then
        return "unknown", "Could not determine remote HEAD."
    end

    local meta = GitOps._readMeta and GitOps._readMeta(repo_path)
    -- Fall back: read meta directly
    if not meta then
        local lfs = require("libs/libkoreader-lfs")
        local f = io.open(repo_path .. "/.ghbrowser.json", "r")
        if not f then return "unknown", "Not a repo" end
        local content = f:read("*a"); f:close()
        local ok, data = pcall(require("json").decode, content)
        meta = ok and data or nil
    end
    if not meta then return "unknown", "Not a repo" end

    if remote_sha == meta.remote_head then
        return "up_to_date", nil, remote_sha
    end

    -- If we have unpushed commits, local is ahead
    if GitOps.hasLocalCommits(repo_path) then
        return "local_ahead", nil, meta.remote_head, remote_sha
    end

    -- Remote differs and we have no local commits to push
    return "remote_ahead", nil, meta.remote_head, remote_sha
end

function SyncEngine.getRemoteChanges(repo_path, branch, count)
    count = count or 10
    return GitOps.log(repo_path, count) or {}
end

function SyncEngine.getLocalUnpushed(repo_path, branch, count)
    -- Return unpushed commits from metadata
    local f = io.open(repo_path .. "/.ghbrowser.json", "r")
    if not f then return {} end
    local content = f:read("*a"); f:close()
    local ok, meta = pcall(require("json").decode, content)
    if not ok or not meta or not meta.unpushed then return {} end

    local entries = {}
    for i = #meta.unpushed, math.max(1, #meta.unpushed - count + 1), -1 do
        local e = meta.unpushed[i]
        if e then
            entries[#entries + 1] = {
                hash    = "local",
                message = e.message,
                author  = "you",
                date    = e.date,
            }
        end
    end
    return entries
end

function SyncEngine.getUncommitted(repo_path)
    return GitOps.status(repo_path) or {}
end

function SyncEngine.hasUnpushedCommits(repo_path)
    return GitOps.hasLocalCommits(repo_path)
end

function SyncEngine.sync(repo_path, token, branch)
    -- Auto-commit any local changes before syncing
    local has_changes = GitOps.hasChanges(repo_path)
    if has_changes then
        local ok, msg = GitOps.commit(repo_path, "Sync: auto-commit")
        if ok then
            logger.dbg("SyncEngine: auto-committed local changes: " .. (msg or ""))
        else
            logger.dbg("SyncEngine: auto-commit skipped: " .. (msg or ""))
        end
    end

    local status = SyncEngine.checkStatus(repo_path, branch)

    if status == "fetch_failed" then
        return false, "Could not reach remote. Check your network."
    end

    if status == "remote_ahead" then
        local ok, err = GitOps.pull(repo_path, token)
        if not ok then return false, "Pull failed: " .. err end
        if GitOps.hasLocalCommits(repo_path) then
            local ok2, err2 = GitOps.push(repo_path, token)
            if not ok2 then return false, "Pull OK, but push failed: " .. err2 end
        end
        return true, "Synced: pulled latest changes."

    elseif status == "local_ahead" then
        local ok, err = GitOps.push(repo_path, token)
        if not ok then return false, "Push failed: " .. err end
        return true, "Synced: pushed local commits."

    elseif status == "diverged" then
        return false, "Local and remote have diverged. Manual resolution needed."

    else
        return true, "Already up to date."
    end
end

return SyncEngine