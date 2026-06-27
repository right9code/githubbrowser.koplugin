-- Pure Lua git operations via GitHub API (no git CLI required)
local logger = require("logger")
local lfs    = require("libs/libkoreader-lfs")
local json   = require("json")

local GithubBrowserSettings = require("githubbrowser_settings")
local GithubBrowserAPI      = require("githubbrowser_api")

local GitOps = {}

local META_FILE = ".ghbrowser.json"

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function ensureDir(path)
    if lfs.attributes(path, "mode") then return true end
    local parent = path:match("^(.+)/[^/]+$")
    if parent then ensureDir(parent) end
    return lfs.mkdir(path) == 0
end

local function removeDir(path)
    local ok_iter, iter, dir_obj = pcall(lfs.dir, path)
    if not ok_iter then return end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local full = path .. "/" .. entry
            local attr = lfs.attributes(full)
            if attr and attr.mode == "directory" then
                removeDir(full)
            else
                os.remove(full)
            end
        end
    end
    lfs.rmdir(path)
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function writeFile(path, content)
    local dir = path:match("^(.+)/[^/]+$")
    if dir then ensureDir(dir) end
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function hashContent(content)
    if not content or #content == 0 then return "e69de29" end
    local len = #content
    local sum = 0
    local step = math.max(1, math.floor(len / 1024))
    for i = 1, len, step do
        sum = (sum + content:byte(i)) % 0xFFFFFFFF
    end
    return string.format("%08x_%d", sum, len)
end

local function hashFile(path)
    local content = readFile(path)
    if not content then return nil end
    return hashContent(content)
end

local function readMeta(repo_path)
    local content = readFile(repo_path .. "/" .. META_FILE)
    if not content then return nil end
    local ok, data = pcall(json.decode, content)
    return ok and data or nil
end

local function writeMeta(repo_path, meta)
    return writeFile(repo_path .. "/" .. META_FILE, json.encode(meta))
end

-- Walk directory collecting all files (excluding meta/git files)
local function walkFiles(dir, prefix, result)
    local ok_iter, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok_iter then return end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." and entry ~= ".git"
           and entry ~= META_FILE and entry ~= ".gitignore" then
            local full = dir .. "/" .. entry
            local rel = prefix ~= "" and (prefix .. "/" .. entry) or entry
            local attr = lfs.attributes(full)
            if attr then
                if attr.mode == "directory" then
                    walkFiles(full, rel, result)
                else
                    result[rel] = full
                end
            end
        end
    end
end

-- Parse owner/repo from URL or remote_url
local function parseOwnerRepo(url)
    if not url then return nil, nil end
    local owner, repo = url:match("github%.com/([^/]+)/([^/]+)")
    if owner then
        repo = repo:gsub("%.git$", "")
        return owner, repo
    end
    return nil, nil
end

-- ── Detection ─────────────────────────────────────────────────────────────────

function GitOps.isAvailable()
    return true  -- No git binary needed
end

function GitOps.isGitRepo(path)
    if not path then return false end
    return lfs.attributes(path .. "/" .. META_FILE, "mode") ~= nil
end

function GitOps.getRemoteUrl(repo_path)
    local meta = readMeta(repo_path)
    if meta and meta.remote_url then return meta.remote_url end
    if meta and meta.owner and meta.repo then
        return "https://github.com/" .. meta.owner .. "/" .. meta.repo
    end
    return nil
end

function GitOps.getCurrentBranch(repo_path)
    local meta = readMeta(repo_path)
    return meta and meta.branch or nil
end

function GitOps.getLocalPath(owner, repo)
    local workspace = GithubBrowserSettings.getWorkspace()
    return workspace .. "/" .. repo
end

-- ── Clone (download entire repo as zipball - single HTTP request) ───────────

-- progress_cb(phase, current, total, current_file) where phase is "listing" or "downloading"
function GitOps.clone(url, dest, token, shallow, progress_cb)
    local owner, repo = parseOwnerRepo(url)
    if not owner or not repo then
        return false, "Invalid GitHub URL: " .. tostring(url)
    end

    -- Get repo info for default branch
    local repo_info, err = GithubBrowserAPI.getRepo(owner, repo)
    if not repo_info then
        return false, "Failed to get repo info: " .. (err or "?")
    end
    local branch = repo_info.default_branch or "main"

    -- Get remote HEAD sha
    local remote_sha = GithubBrowserAPI.getRemoteHead(owner, repo, branch)

    if progress_cb then
        progress_cb("downloading", 0, 100, "Downloading repository...")
    end

    -- Download repo as zipball (single HTTP request - much faster than file-by-file)
    local ok2, zip_err = GithubBrowserAPI.downloadZipball(owner, repo, branch, dest, token)
    if not ok2 then
        return false, "Failed to download repo: " .. (zip_err or "?")
    end

    if progress_cb then
        progress_cb("downloading", 50, 100, "Indexing files...")
    end

    -- Build snapshot by hashing all downloaded files
    local snapshot = {}
    local downloaded = 0
    local function walkForSnapshot(dir, prefix)
        local ok_iter, iter, dir_obj = pcall(lfs.dir, dir)
        if not ok_iter then return end
        for entry in iter, dir_obj do
            if entry ~= "." and entry ~= ".." and entry ~= ".git"
               and entry ~= META_FILE and entry ~= ".gitignore" then
                local full = dir .. "/" .. entry
                local rel = prefix ~= "" and (prefix .. "/" .. entry) or entry
                local attr = lfs.attributes(full)
                if attr then
                    if attr.mode == "directory" then
                        walkForSnapshot(full, rel)
                    else
                        snapshot[rel] = hashFile(full)
                        downloaded = downloaded + 1
                    end
                end
            end
        end
    end
    walkForSnapshot(dest, "")

    -- Save metadata
    local meta = {
        owner         = owner,
        repo          = repo,
        branch        = branch,
        remote_url    = "https://github.com/" .. owner .. "/" .. repo,
        remote_head   = remote_sha or "",
        snapshot      = snapshot,
        unpushed      = {},
    }
    writeMeta(dest, meta)

    if progress_cb then
        progress_cb("downloading", 100, 100, "Done")
    end

    logger.dbg("GitOps: " .. owner .. "/" .. repo .. " cloned (" .. downloaded .. " files)")
    return true, "Cloned " .. downloaded .. " files", dest
end

-- ── Fetch (check remote head) ────────────────────────────────────────────────

function GitOps.fetch(repo_path, token)
    local meta = readMeta(repo_path)
    if not meta then return false, "Not a repo" end

    local remote_sha = GithubBrowserAPI.getRemoteHead(
        meta.owner, meta.repo, meta.branch
    )
    if not remote_sha then return false, "Could not reach remote" end

    meta.remote_head = remote_sha
    writeMeta(repo_path, meta)
    return true, remote_sha
end

function GitOps.fetchRemoteHead(repo_path)
    local meta = readMeta(repo_path)
    if not meta then return nil end
    return GithubBrowserAPI.getRemoteHead(meta.owner, meta.repo, meta.branch)
end

-- ── Pull (download changes from remote) ──────────────────────────────────────

function GitOps.pull(repo_path, token)
    local meta = readMeta(repo_path)
    if not meta then return false, "Not a repo" end

    local remote_sha = GithubBrowserAPI.getRemoteHead(
        meta.owner, meta.repo, meta.branch
    )
    if not remote_sha then return false, "Could not reach remote" end

    if remote_sha == meta.remote_head then
        return true, "Already up to date"
    end

    -- Get the new tree
    local tree_data, tree_err = GithubBrowserAPI.getTree(meta.owner, meta.repo, meta.branch)
    if not tree_data or not tree_data.tree then
        return false, "Failed to get tree: " .. (tree_err or "?")
    end

    -- Build set of remote files
    local remote_files = {}
    for _, entry in ipairs(tree_data.tree) do
        if entry.type == "blob" then
            remote_files[entry.path] = entry.sha
        end
    end

    -- Download new/changed files
    local updated = 0
    for path, remote_file_sha in pairs(remote_files) do
        local local_hash = meta.snapshot[path]
        -- Download if file is new or we don't have it tracked
        if not local_hash then
            local raw_url = "https://raw.githubusercontent.com/" .. meta.owner .. "/" .. meta.repo
                           .. "/" .. meta.branch .. "/" .. path
            local data = GithubBrowserAPI.getRawFile(raw_url)
            if data then
                writeFile(repo_path .. "/" .. path, data)
                meta.snapshot[path] = hashContent(data)
                updated = updated + 1
            end
        end
    end

    -- For files that exist locally but might have changed remotely,
    -- re-download all tracked files (simple approach, reliable)
    for _, entry in ipairs(tree_data.tree) do
        if entry.type == "blob" then
            local raw_url = "https://raw.githubusercontent.com/" .. meta.owner .. "/" .. meta.repo
                           .. "/" .. meta.branch .. "/" .. entry.path
            local data = GithubBrowserAPI.getRawFile(raw_url)
            if data then
                writeFile(repo_path .. "/" .. entry.path, data)
                meta.snapshot[entry.path] = hashContent(data)
            end
        end
    end

    -- Remove files that no longer exist on remote
    local local_files = {}
    walkFiles(repo_path, "", local_files)
    for rel_path, _ in pairs(local_files) do
        if not remote_files[rel_path] then
            os.remove(repo_path .. "/" .. rel_path)
            meta.snapshot[rel_path] = nil
        end
    end

    meta.remote_head = remote_sha
    meta.unpushed = {}
    writeMeta(repo_path, meta)

    return true, "Pulled latest changes"
end

-- ── Push (upload local changes via GitHub API) ───────────────────────────────

function GitOps.push(repo_path, token)
    if not token or token == "" then
        return false, "GitHub token required to push"
    end

    local meta = readMeta(repo_path)
    if not meta then return false, "Not a repo" end

    -- Collect local changes vs snapshot
    local local_files = {}
    walkFiles(repo_path, "", local_files)

    local tree_entries = {}
    local has_changes = false

    -- Check all local files
    for rel_path, full_path in pairs(local_files) do
        local local_hash = hashFile(full_path)
        local snap_hash = meta.snapshot[rel_path]
        if local_hash ~= snap_hash then
            -- New or modified file - create blob
            local content = readFile(full_path)
            if content then
                local blob, err = GithubBrowserAPI.createBlob(meta.owner, meta.repo, content, token)
                if blob and blob.sha then
                    tree_entries[#tree_entries + 1] = {
                        path = rel_path,
                        mode = "100644",
                        type = "blob",
                        sha  = blob.sha,
                    }
                    has_changes = true
                else
                    return false, "Failed to create blob for " .. rel_path .. ": " .. (err or "?")
                end
            end
        end
    end

    -- Check for deleted files
    for snap_path, _ in pairs(meta.snapshot) do
        if not local_files[snap_path] then
            tree_entries[#tree_entries + 1] = {
                path = snap_path,
                mode = "100644",
                type = "blob",
                sha  = nil,  -- nil sha = delete
            }
            has_changes = true
        end
    end

    if not has_changes then
        return true, "Nothing to push"
    end

    -- Get current remote head as parent
    local remote_sha = GithubBrowserAPI.getRemoteHead(meta.owner, meta.repo, meta.branch)
    if not remote_sha then
        return false, "Could not get remote HEAD"
    end

    -- Create tree
    local tree, tree_err = GithubBrowserAPI.createTree(meta.owner, meta.repo, remote_sha, tree_entries, token)
    if not tree or not tree.sha then
        return false, "Failed to create tree: " .. (tree_err or "?")
    end

    -- Create commit
    local device = GithubBrowserSettings.getDeviceName()
    local commit_msg = "Push from KOReader (" .. device .. ")"
    local commit, commit_err = GithubBrowserAPI.createCommit(
        meta.owner, meta.repo, commit_msg, tree.sha, remote_sha, token
    )
    if not commit or not commit.sha then
        return false, "Failed to create commit: " .. (commit_err or "?")
    end

    -- Update ref
    local ref_result, ref_err = GithubBrowserAPI.updateRef(
        meta.owner, meta.repo, meta.branch, commit.sha, token
    )
    if not ref_result then
        return false, "Failed to update ref: " .. (ref_err or "?")
    end

    -- Update local snapshot
    for rel_path, full_path in pairs(local_files) do
        meta.snapshot[rel_path] = hashFile(full_path)
    end
    for snap_path, _ in pairs(meta.snapshot) do
        if not local_files[snap_path] then
            meta.snapshot[snap_path] = nil
        end
    end
    meta.remote_head = commit.sha
    meta.unpushed = {}
    writeMeta(repo_path, meta)

    return true, "Pushed " .. #tree_entries .. " changes"
end

-- ── Commit (local staging for later push) ────────────────────────────────────

function GitOps.commit(repo_path, message)
    local meta = readMeta(repo_path)
    if not meta then return false, "Not a repo" end

    -- Check if there are actual changes
    if not GitOps.hasChanges(repo_path) then
        return false, "Nothing to commit"
    end

    local device = GithubBrowserSettings.getDeviceName()
    local full_msg = message .. "\n\nFrom: " .. device

    -- Record unpushed commit
    meta.unpushed = meta.unpushed or {}
    meta.unpushed[#meta.unpushed + 1] = {
        message = full_msg,
        date    = os.date("%Y-%m-%d %H:%M"),
    }
    writeMeta(repo_path, meta)

    return true, "Committed locally (will push on next sync)"
end

-- ── Status ────────────────────────────────────────────────────────────────────

function GitOps.status(repo_path)
    local meta = readMeta(repo_path)
    if not meta then return nil, "Not a repo" end

    local local_files = {}
    walkFiles(repo_path, "", local_files)

    local files = {}
    for rel_path, full_path in pairs(local_files) do
        local local_hash = hashFile(full_path)
        local snap_hash = meta.snapshot[rel_path]
        if not snap_hash then
            files[#files + 1] = { status = "A ", file = rel_path }
        elseif local_hash ~= snap_hash then
            files[#files + 1] = { status = "M ", file = rel_path }
        end
    end
    for snap_path, _ in pairs(meta.snapshot) do
        if not local_files[snap_path] then
            files[#files + 1] = { status = "D ", file = snap_path }
        end
    end
    return files
end

function GitOps.hasChanges(repo_path)
    local files = GitOps.status(repo_path)
    if not files then return false end
    return #files > 0
end

-- ── Log (via GitHub API) ─────────────────────────────────────────────────────

function GitOps.log(repo_path, count)
    count = count or 20
    local meta = readMeta(repo_path)
    if not meta then return nil, "Not a repo" end

    local commits, err = GithubBrowserAPI.getCommits(
        meta.owner, meta.repo, meta.branch, count
    )
    if not commits then return nil, err end

    local entries = {}
    for _, c in ipairs(commits) do
        local hash = c.sha and c.sha:sub(1, 7) or "?"
        local msg = c.commit and c.commit.message or "?"
        local author = c.commit and c.commit.author and c.commit.author.name or "?"
        local date = c.commit and c.commit.author and c.commit.author.date or ""
        -- Format date as relative
        entries[#entries + 1] = {
            hash    = hash,
            message = msg:gsub("\n.*", ""),  -- first line only
            author  = author,
            date    = date:sub(1, 10),
        }
    end
    return entries
end

-- ── Diff (local changes vs snapshot) ─────────────────────────────────────────

function GitOps.diff(repo_path)
    local meta = readMeta(repo_path)
    if not meta then return nil, "Not a repo" end

    local local_files = {}
    walkFiles(repo_path, "", local_files)

    local parts = {}
    for rel_path, full_path in pairs(local_files) do
        local local_hash = hashFile(full_path)
        local snap_hash = meta.snapshot[rel_path]
        if not snap_hash then
            parts[#parts + 1] = "--- /dev/null"
            parts[#parts + 1] = "+++ b/" .. rel_path
            local content = readFile(full_path) or ""
            for line in content:gmatch("[^\r\n]*") do
                parts[#parts + 1] = "+" .. line
            end
        elseif local_hash ~= snap_hash then
            parts[#parts + 1] = "--- a/" .. rel_path
            parts[#parts + 1] = "+++ b/" .. rel_path
            parts[#parts + 1] = "(file modified)"
        end
    end
    for snap_path, _ in pairs(meta.snapshot) do
        if not local_files[snap_path] then
            parts[#parts + 1] = "--- a/" .. snap_path
            parts[#parts + 1] = "+++ /dev/null"
            parts[#parts + 1] = "(deleted)"
        end
    end

    if #parts == 0 then return "" end
    return table.concat(parts, "\n")
end

-- ── Branches (via GitHub API) ────────────────────────────────────────────────

function GitOps.listBranches(repo_path)
    local meta = readMeta(repo_path)
    if not meta then return nil, "Not a repo" end

    local branches_data, err = GithubBrowserAPI.getBranches(meta.owner, meta.repo)
    if not branches_data then return nil, err end

    local branches = {}
    for _, b in ipairs(branches_data) do
        branches[#branches + 1] = {
            name        = b.name,
            is_current  = (b.name == meta.branch),
        }
    end
    return branches
end

function GitOps.checkout(repo_path, branch)
    local meta = readMeta(repo_path)
    if not meta then return false, "Not a repo" end

    -- Update branch in metadata and re-download
    meta.branch = branch
    writeMeta(repo_path, meta)

    -- Pull the new branch
    local ok, msg = GitOps.pull(repo_path)
    return ok, msg
end

-- ── Unpushed commits ─────────────────────────────────────────────────────────

function GitOps.hasLocalCommits(repo_path)
    local meta = readMeta(repo_path)
    if not meta then return false end
    return meta.unpushed and #meta.unpushed > 0
end

return GitOps