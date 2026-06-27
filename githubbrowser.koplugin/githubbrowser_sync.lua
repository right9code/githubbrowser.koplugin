local logger = require("logger")
local GitOps = require("githubbrowser_git")

local SyncEngine = {}

function SyncEngine.checkStatus(repo_path, branch)
    branch = branch or GitOps.getCurrentBranch(repo_path) or "main"

    local local_hash = select(1, GitOps.getCurrentBranch(repo_path))
    local _, fetch_ok = GitOps.fetch(repo_path)
    if not fetch_ok then
        return "fetch_failed", "Could not reach remote."
    end

    local local_h  = select(1,
        (function() local o, ok = GitOps._rawExec and nil or nil; return select(1, (function()
            local handle = io.popen(string.format("cd %q && git rev-parse HEAD 2>&1", repo_path))
            local out = handle:read("*a"):gsub("%s+$", "")
            handle:close()
            return out
        end)()) end)()
    )

    -- Use gitExec directly for hash comparison
    local cmd_base = function(args)
        local handle = io.popen(string.format("cd %q && git %s 2>&1", repo_path, args))
        if not handle then return nil end
        local out = handle:read("*a"):gsub("%s+$", "")
        handle:close()
        return out
    end

    local_h = cmd_base("rev-parse HEAD")
    local remote_h = cmd_base("rev-parse origin/" .. branch)

    if not local_h or not remote_h then
        return "unknown", "Could not determine HEAD."
    end

    if local_h == remote_h then
        return "up_to_date", nil, local_h
    end

    -- Check if local is ancestor of remote (remote is ahead)
    local _, exit1 = cmd_base("merge-base --is-ancestor " .. local_h .. " " .. remote_h)
    if exit1 == 0 then
        return "remote_ahead", nil, local_h, remote_h
    end

    -- Check if remote is ancestor of local (local is ahead)
    local _, exit2 = cmd_base("merge-base --is-ancestor " .. remote_h .. " " .. local_h)
    if exit2 == 0 then
        return "local_ahead", nil, local_h, remote_h
    end

    return "diverged", "Local and remote have diverged.", local_h, remote_h
end

function SyncEngine.getRemoteChanges(repo_path, branch, count)
    count = count or 10
    branch = branch or GitOps.getCurrentBranch(repo_path) or "main"
    local cmd = string.format(
        "cd %q && git log --oneline --format='%%h|%%s|%%an|%%ar' HEAD..origin/%s -%d 2>&1",
        repo_path, branch, count
    )
    local handle = io.popen(cmd)
    if not handle then return {} end
    local output = handle:read("*a")
    handle:close()
    local entries = {}
    for line in output:gmatch("[^\r\n]+") do
        local hash, msg, author, date = line:match("^(%w+)|(.+)|(.+)|(.+)$")
        if hash then
            entries[#entries + 1] = { hash = hash, message = msg, author = author, date = date }
        end
    end
    return entries
end

function SyncEngine.getLocalUnpushed(repo_path, branch, count)
    count = count or 10
    branch = branch or GitOps.getCurrentBranch(repo_path) or "main"
    local cmd = string.format(
        "cd %q && git log --oneline --format='%%h|%%s|%%an|%%ar' origin/%s..HEAD -%d 2>&1",
        repo_path, branch, count
    )
    local handle = io.popen(cmd)
    if not handle then return {} end
    local output = handle:read("*a")
    handle:close()
    local entries = {}
    for line in output:gmatch("[^\r\n]+") do
        local hash, msg, author, date = line:match("^(%w+)|(.+)|(.+)|(.+)$")
        if hash then
            entries[#entries + 1] = { hash = hash, message = msg, author = author, date = date }
        end
    end
    return entries
end

function SyncEngine.getUncommitted(repo_path)
    return GitOps.status(repo_path) or {}
end

function SyncEngine.sync(repo_path, token, branch)
    -- Auto-commit any local changes (including deletions) before syncing
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
