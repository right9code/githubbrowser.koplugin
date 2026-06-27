local logger = require("logger")
local lfs    = require("libs/libkoreader-lfs")

local GithubBrowserSettings = require("githubbrowser_settings")

local GitOps = {}

-- ── Core execution helper ─────────────────────────────────────────────────────

local function gitExec(args, cwd)
    local cmd = "git " .. args
    if cwd then
        cmd = string.format("cd %q && %s", cwd, cmd)
    end
    logger.dbg("GitOps: " .. cmd)
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then return nil, false, -1 end
    local output = handle:read("*a")
    local ok, _, exitcode = handle:close()
    return (output or ""):gsub("%s+$", ""), ok, exitcode
end

local function shellEscape(str)
    return "'" .. str:gsub("'", "'\\''") .. "'"
end

-- ── Auth helper ───────────────────────────────────────────────────────────────

local function withAuth(repo_path, token, fn)
    if not token or token == "" then return fn() end
    local clean_url = GitOps.getRemoteUrl(repo_path)
    if not clean_url then return fn() end
    local auth_url = clean_url:gsub("https://", "https://" .. token .. "@")
    gitExec("remote set-url origin " .. auth_url, repo_path)
    local results = {fn()}
    gitExec("remote set-url origin " .. clean_url, repo_path)
    return unpack(results)
end

-- ── Detection ─────────────────────────────────────────────────────────────────

function GitOps.isAvailable()
    local handle = io.popen("git --version 2>&1")
    if not handle then return false end
    local output = handle:read("*a")
    handle:close()
    return output and output:match("git version") ~= nil
end

function GitOps.isGitRepo(path)
    if not path then return false end
    local output, ok = gitExec("rev-parse --is-inside-work-tree", path)
    return ok and output:find("true") ~= nil
end

-- ── Clone ─────────────────────────────────────────────────────────────────────

function GitOps.clone(url, dest, token, shallow)
    local clone_url = url
    if token and token ~= "" then
        clone_url = url:gsub("https://", "https://" .. token .. "@")
    end

    local depth_flag = shallow and " --depth 1" or ""
    local cmd = string.format("clone%s %q %q 2>&1", depth_flag, clone_url, dest)
    local output, ok = gitExec(cmd)

    if ok then
        gitExec("remote set-url origin " .. url, dest)
    end

    return ok, output, dest
end

-- ── Remote operations ─────────────────────────────────────────────────────────

function GitOps.fetch(repo_path, token)
    return withAuth(repo_path, token, function()
        local output, ok = gitExec("fetch origin 2>&1", repo_path)
        return ok, output
    end)
end

function GitOps.pull(repo_path, token)
    return withAuth(repo_path, token, function()
        local output, ok = gitExec("pull --ff-only 2>&1", repo_path)
        return ok, output
    end)
end

function GitOps.push(repo_path, token)
    return withAuth(repo_path, token, function()
        local branch = GitOps.getCurrentBranch(repo_path) or "main"
        local output, ok = gitExec("push origin " .. branch .. " 2>&1", repo_path)
        return ok, output
    end)
end

-- ── Local operations ──────────────────────────────────────────────────────────

function GitOps.commit(repo_path, message)
    local _, ok1 = gitExec("add -A", repo_path)
    if not ok1 then return false, "Failed to stage changes" end

    local device = GithubBrowserSettings.getDeviceName()
    local full_msg = message .. "\n\nFrom: " .. device
    local output, ok2 = gitExec("commit -m " .. shellEscape(full_msg), repo_path)
    if not ok2 then return false, "Nothing to commit or commit failed.\n" .. output end
    return true, output
end

function GitOps.status(repo_path)
    local output, ok = gitExec("status --porcelain", repo_path)
    if not ok then return nil, "Failed to get status" end
    local files = {}
    for line in output:gmatch("[^\r\n]+") do
        local status = line:sub(1, 2)
        local file = line:sub(4)
        files[#files + 1] = { status = status, file = file }
    end
    return files
end

function GitOps.hasChanges(repo_path)
    local files, err = GitOps.status(repo_path)
    if not files then return false end
    return #files > 0
end

function GitOps.log(repo_path, count)
    count = count or 20
    local output, ok = gitExec(
        "log --oneline --format='%h|%s|%an|%ar' -" .. count,
        repo_path
    )
    if not ok then return nil, "Failed to get log" end
    local entries = {}
    for line in output:gmatch("[^\r\n]+") do
        local hash, msg, author, date = line:match("^(%w+)|(.+)|(.+)|(.+)$")
        if hash then
            entries[#entries + 1] = {
                hash    = hash,
                message = msg,
                author  = author,
                date    = date,
            }
        end
    end
    return entries
end

function GitOps.diff(repo_path)
    local output, ok = gitExec("diff", repo_path)
    if not ok then return nil, "Failed to get diff" end
    return output
end

function GitOps.getCurrentBranch(repo_path)
    local output, ok = gitExec("branch --show-current", repo_path)
    if not ok then return nil end
    return output ~= "" and output or nil
end

function GitOps.listBranches(repo_path)
    local output, ok = gitExec("branch -a", repo_path)
    if not ok then return nil, "Failed to list branches" end
    local branches = {}
    for line in output:gmatch("[^\r\n]+") do
        local is_current = line:sub(1, 1) == "*"
        local name = line:gsub("^%*?%s+", ""):match("^%s*(.-)%s*$")
        if name and name ~= "" then
            branches[#branches + 1] = { name = name, is_current = is_current }
        end
    end
    return branches
end

function GitOps.checkout(repo_path, branch)
    local output, ok = gitExec("checkout " .. shellEscape(branch), repo_path)
    return ok, output
end

function GitOps.getRemoteUrl(repo_path)
    local output, ok = gitExec("remote get-url origin", repo_path)
    if not ok then return nil end
    return output ~= "" and output or nil
end

function GitOps.hasLocalCommits(repo_path)
    local branch = GitOps.getCurrentBranch(repo_path)
    if not branch then return false end
    local output, ok = gitExec("log --oneline origin/" .. branch .. "..HEAD", repo_path)
    if not ok then return false end
    return output:gsub("%s+", "") ~= ""
end

function GitOps.getLocalPath(owner, repo)
    local workspace = GithubBrowserSettings.getWorkspace()
    return workspace .. "/" .. repo
end

return GitOps
