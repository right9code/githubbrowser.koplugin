9tlocal json        = require("json")
local socket_http = require("socket.http")
local socketutil  = require("socketutil")
local ltn12       = require("ltn12")
local logger      = require("logger")
local bit         = require("bit")
local table_new   = require("table.new")
local lfs         = require("libs/libkoreader-lfs")

-- Cache frequently-used functions as locals (LuaJIT: avoids repeated global lookups)
local table_concat = table.concat
local pcall        = pcall
local json_decode  = json.decode
local json_encode  = json.encode

local GithubBrowserSettings = require("githubbrowser_settings")

local GithubBrowserAPI = {}

local BASE_URL = "https://api.github.com"
local DEFAULT_TIMEOUT = 30
local DEFAULT_MAXTIME = 60

-- ── Base64 encoder ────────────────────────────────────────────────────────────

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64encode(data)
    local out = {}
    local len = #data
    for i = 1, len, 3 do
        local b1 = string.byte(data, i)
        local b2 = i + 1 <= len and string.byte(data, i + 1) or 0
        local b3 = i + 2 <= len and string.byte(data, i + 2) or 0
        local n = bit.bor(bit.lshift(b1, 16), bit.lshift(b2, 8), b3)
        local c1 = bit.band(bit.rshift(n, 18), 0x3F) + 1
        local c2 = bit.band(bit.rshift(n, 12), 0x3F) + 1
        local c3 = bit.band(bit.rshift(n,  6), 0x3F) + 1
        local c4 = bit.band(n,                 0x3F) + 1
        out[#out + 1] = string.sub(B64_CHARS, c1, c1)
        out[#out + 1] = string.sub(B64_CHARS, c2, c2)
        out[#out + 1] = (i + 1 <= len) and string.sub(B64_CHARS, c3, c3) or "="
        out[#out + 1] = (i + 2 <= len) and string.sub(B64_CHARS, c4, c4) or "="
    end
    return table.concat(out)
end

-- ── HTTP helpers ──────────────────────────────────────────────────────────────

local function extractRepoFromURL(url)
    local owner, repo = url:match("/repos/([^/]+)/([^/]+)")
    if owner and repo then return owner .. "/" .. repo end
    owner, repo = url:match("raw%.githubusercontent%.com/([^/]+)/([^/]+)")
    if owner and repo then return owner .. "/" .. repo end
    return nil
end

local function curlRequest(url, method, payload, token)
    logger.dbg("GithubBrowserAPI: " .. method .. " " .. url)
    local headers = {
        ["User-Agent"]   = "KOReader-GithubBrowser/1.0",
        ["Accept"]       = "application/vnd.github.v3+json",
        ["Content-Type"] = "application/json",
    }
    if token and token ~= "" then
        headers["Authorization"] = "token " .. token
    end
    local source = nil
    if payload then
        headers["Content-Length"] = tostring(#payload)
        source = ltn12.source.string(payload)
    else
        headers["Content-Length"] = "0"
    end
    local response_body = {}
    socketutil:set_timeout(DEFAULT_TIMEOUT, DEFAULT_MAXTIME)
    local ok, code = socket_http.request {
        url      = url,
        method   = method,
        headers  = headers,
        source   = source,
        sink     = ltn12.sink.table(response_body),
        redirect = true,
    }
    socketutil:reset_timeout()
    if not ok then
        return nil, "Network error: " .. tostring(code)
    end
    local response = table.concat(response_body)
    if response == "" and (code == 200 or code == 201 or code == 204) then
        return { success = true }, nil
    elseif response == "" then
        return nil, "Empty response (HTTP " .. tostring(code) .. ")"
    end
    local ok2, data = pcall(json_decode, response)
    if not ok2 then
        return nil, "Failed to parse response (HTTP " .. tostring(code) .. "): " .. response:sub(1, 200)
    end
    if type(code) == "number" and code >= 400 then
        return nil, "API Error (HTTP " .. tostring(code) .. "): " .. (data.message or "?")
    end
    return data, nil
end

local function makeRequest(url, custom_accept)
    logger.dbg("GithubBrowserAPI: GET " .. url)
    local headers = {
        ["User-Agent"] = "KOReader-GithubBrowser/1.0",
        ["Accept"]     = custom_accept or "application/vnd.github.v3+json",
    }
    local repo_full = extractRepoFromURL(url)
    local token = GithubBrowserSettings.getTokenForRepo(repo_full)
    if token and token ~= "" then
        headers["Authorization"] = "token " .. token
    end
    local response_body = {}
    socketutil:set_timeout(DEFAULT_TIMEOUT, DEFAULT_MAXTIME)
    local ok, code = socket_http.request {
        url      = url,
        method   = "GET",
        headers  = headers,
        sink     = ltn12.sink.table(response_body),
        redirect = true,
    }
    socketutil:reset_timeout()
    if not ok then
        return nil, "Network error: " .. tostring(code)
    end
    if type(code) ~= "number" then
        return nil, "Network error: " .. tostring(code)
    end
    local body = table.concat(response_body)
    if code == 404 then
        return nil, "Not found. Check owner/repo name."
    elseif code == 403 then
        return nil, "API rate limit exceeded (60 req/hr without token)."
    elseif code == 401 then
        return nil, "Authentication error."
    elseif code ~= 200 then
        return nil, "API error (HTTP " .. tostring(code) .. ")"
    end
    local ok2, data = pcall(json_decode, body)
    if not ok2 then
        return nil, "Failed to parse API response."
    end
    return data, nil
end

local function fetchRaw(raw_url)
    local response_body = {}
    local headers = { ["User-Agent"] = "KOReader-GithubBrowser/1.0" }
    local repo_full = extractRepoFromURL(raw_url)
    local token = GithubBrowserSettings.getTokenForRepo(repo_full)
    if token and token ~= "" then
        headers["Authorization"] = "token " .. token
    end
    socketutil:set_timeout(DEFAULT_TIMEOUT, DEFAULT_MAXTIME)
    local ok, code = socket_http.request {
        url      = raw_url,
        method   = "GET",
        headers  = headers,
        sink     = ltn12.sink.table(response_body),
        redirect = true,
    }
    socketutil:reset_timeout()
    if not ok then
        return nil, "Network error: " .. tostring(code)
    end
    if type(code) == "number" and code ~= 200 then
        return nil, "Failed to fetch file (HTTP " .. tostring(code) .. ")"
    elseif type(code) ~= "number" then
        return nil, "Network error: " .. tostring(code)
    end
    return table.concat(response_body), nil
end

-- ── URL Encoding ──────────────────────────────────────────────────────────────

local function urlEncodePath(str)
    if not str then return str end
    str = string.gsub(str, "([^%w _%%%-%.~%/])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "%%20")
    return str
end

local function urlEncodeQuery(str)
    if not str then return str end
    str = string.gsub(str, "([^%w _%%%-%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "%%20")
    return str
end

-- ── Public API ────────────────────────────────────────────────────────────────

function GithubBrowserAPI.getRepo(owner, repo)
    return makeRequest(BASE_URL .. "/repos/" .. owner .. "/" .. repo)
end

function GithubBrowserAPI.getContents(owner, repo, path, ref)
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo .. "/contents"
    if path and path ~= "" then
        url = url .. "/" .. urlEncodePath(path)
    end
    if ref and ref ~= "" then
        url = url .. "?ref=" .. urlEncodeQuery(ref)
    end
    return makeRequest(url)
end

function GithubBrowserAPI._getTreeViaContents(owner, repo, ref, progress_cb)
    logger.dbg("GithubBrowserAPI: tree truncated, falling back to Contents API")
    local tree = {}
    local file_count = 0
    local function fetchDir(path)
        local page = 1
        while true do
            local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo .. "/contents"
            if path and path ~= "" then
                url = url .. "/" .. urlEncodePath(path)
            end
            url = url .. "?ref=" .. urlEncodeQuery(ref) .. "&per_page=100&page=" .. tostring(page)
            local data, err = makeRequest(url)
            if not data then break end
            -- data is an array of entries
            if type(data) ~= "table" or #data == 0 then break end
            for _, entry in ipairs(data) do
                if entry.type == "file" then
                    file_count = file_count + 1
                    tree[#tree + 1] = { path = entry.path, type = "blob", sha = entry.sha }
                    if progress_cb then
                        progress_cb(file_count, 0, entry.path)
                    end
                elseif entry.type == "dir" then
                    fetchDir(entry.path)
                end
            end
            if #data < 100 then break end
            page = page + 1
        end
    end
    fetchDir("")
    return { tree = tree, truncated = false }, nil
end

function GithubBrowserAPI.getTree(owner, repo, ref, progress_cb)
    ref = ref or "main"
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo
              .. "/git/trees/" .. urlEncodePath(ref) .. "?recursive=1"
    local data, err = makeRequest(url)
    if not data then return nil, err end
    if data.truncated then
        return GithubBrowserAPI._getTreeViaContents(owner, repo, ref, progress_cb)
    end
    return data, nil
end

function GithubBrowserAPI.searchCode(owner, repo, query)
    local full_query = query .. " repo:" .. owner .. "/" .. repo
    local url = BASE_URL .. "/search/code?q=" .. urlEncodeQuery(full_query) .. "&per_page=50"
    return makeRequest(url, "application/vnd.github.v3.text-match+json")
end

function GithubBrowserAPI.getRawFile(raw_url)
    return fetchRaw(raw_url)
end

function GithubBrowserAPI.downloadFile(raw_url, dest_path)
    local data, err = fetchRaw(raw_url)
    if not data then return nil, err end
    local fh, ferr = io.open(dest_path, "wb")
    if not fh then
        return nil, "Cannot write file: " .. tostring(ferr)
    end
    fh:write(data)
    fh:close()
    return true, nil
end

function GithubBrowserAPI.formatSize(bytes)
    if not bytes or bytes == 0 then return "" end
    if bytes < 1024 then
        return bytes .. " B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
end

function GithubBrowserAPI.parseRepoInput(input)
    if not input then return nil, nil end
    input = input:match("^%s*(.-)%s*$")
    input = input:gsub("^https?://github%.com/", "")
    input = input:gsub("%.git$", "")
    input = input:gsub("/+$", "")
    local owner, repo = input:match("^([^/]+)/([^/]+)$")
    return owner, repo
end

function GithubBrowserAPI.updateFile(owner, repo, path, content, sha, branch, message, token)
    if not token or token == "" then
        return nil, "A GitHub token is required to edit files."
    end
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo
              .. "/contents/" .. urlEncodePath(path)
    local body = {
        message = message or ("Update " .. path),
        content = b64encode(content),
        branch  = branch,
    }
    if sha and sha ~= "" then
        body.sha = sha
    end
    return curlRequest(url, "PUT", json_encode(body), token)
end

function GithubBrowserAPI.deleteFile(owner, repo, path, sha, branch, message, token)
    if not token or token == "" then
        return nil, "A GitHub token is required to delete files."
    end
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo
              .. "/contents/" .. urlEncodePath(path)
    local body = {
        message = message or ("Delete " .. path),
        sha     = sha,
        branch  = branch,
    }
    return curlRequest(url, "DELETE", json_encode(body), token)
end

function GithubBrowserAPI.deleteDirectory(owner, repo, path, branch, message, token)
    local contents, err = GithubBrowserAPI.getContents(owner, repo, path, branch)
    if not contents then return false, "Failed to read directory: " .. (err or "?") end
    if contents.type == "file" then return false, "Path is a file, not a directory" end
    for __, entry in ipairs(contents) do
        if entry.type == "dir" then
            local ok, err2 = GithubBrowserAPI.deleteDirectory(owner, repo, entry.path, branch, message, token)
            if not ok then return false, err2 end
        elseif entry.type == "file" then
            local ok, err2 = GithubBrowserAPI.deleteFile(owner, repo, entry.path, entry.sha, branch, message, token)
            if not ok then return false, err2 end
        end
    end
    return true, nil
end

-- ── Git API methods (pure Lua, no git CLI needed) ───────────────────────────

function GithubBrowserAPI.getBranches(owner, repo, token)
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo .. "/branches?per_page=100"
    return makeRequest(url)
end

function GithubBrowserAPI.getCommits(owner, repo, ref, count, token)
    ref = ref or "main"
    count = count or 20
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo
              .. "/commits?sha=" .. urlEncodeQuery(ref) .. "&per_page=" .. tostring(count)
    return makeRequest(url)
end

function GithubBrowserAPI.getRemoteHead(owner, repo, ref, token)
    ref = ref or "main"
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo
              .. "/git/ref/heads/" .. urlEncodePath(ref)
    local data, err = makeRequest(url)
    if not data then return nil, err end
    if data.object and data.object.sha then
        return data.object.sha
    end
    return nil, "Unexpected response"
end

function GithubBrowserAPI.createBlob(owner, repo, content, token)
    if not token or token == "" then return nil, "Token required" end
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo .. "/git/blobs"
    local body = {
        encoding = "base64",
        content  = b64encode(content),
    }
    return curlRequest(url, "POST", json_encode(body), token)
end

function GithubBrowserAPI.createTree(owner, repo, base_tree_sha, tree_entries, token)
    if not token or token == "" then return nil, "Token required" end
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo .. "/git/trees"
    local body = {
        base_tree = base_tree_sha,
        tree      = tree_entries,
    }
    return curlRequest(url, "POST", json_encode(body), token)
end

function GithubBrowserAPI.createCommit(owner, repo, message, tree_sha, parent_sha, token)
    if not token or token == "" then return nil, "Token required" end
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo .. "/git/commits"
    local body = {
        message = message,
        tree    = tree_sha,
    }
    if parent_sha then
        body.parents = { parent_sha }
    end
    return curlRequest(url, "POST", json_encode(body), token)
end

function GithubBrowserAPI.updateRef(owner, repo, ref, sha, token)
    if not token or token == "" then return nil, "Token required" end
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo
              .. "/git/refs/heads/" .. urlEncodePath(ref)
    local body = {
        sha   = sha,
        force = false,
    }
    return curlRequest(url, "PATCH", json_encode(body), token)
end

local function ensureDir(path)
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(path, "mode") then return true end
    local parent = path:match("^(.+)/[^/]+$")
    if parent then ensureDir(parent) end
    return lfs.mkdir(path) == 0
end

function GithubBrowserAPI.downloadTree(owner, repo, ref, token, dest_path)
    local data, err = GithubBrowserAPI.getTree(owner, repo, ref)
    if not data then return nil, err end
    if not data.tree then return nil, "No tree in response" end

    ensureDir(dest_path)
    local downloaded = 0
    local total = #data.tree
    for _, entry in ipairs(data.tree) do
        if entry.type == "blob" and entry.sha then
            local file_url = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo
                           .. "/" .. (ref or "main") .. "/" .. entry.path
            local file_data, ferr = fetchRaw(file_url)
            if file_data then
                local full_path = dest_path .. "/" .. entry.path
                local dir = full_path:match("^(.+)/[^/]+$")
                if dir then ensureDir(dir) end
                local fh = io.open(full_path, "wb")
                if fh then
                    fh:write(file_data)
                    fh:close()
                end
            end
            downloaded = downloaded + 1
        end
    end
    return downloaded, nil
end

-- Download repo as tarball (single request) - much faster than file-by-file
-- Uses tarball instead of zipball because `tar` is universally available on
-- all KOReader devices (Kobo/Kindle/Android) via BusyBox, while `unzip` often is not.
function GithubBrowserAPI.downloadZipball(owner, repo, ref, dest_path, token)
    ref = ref or "main"
    local tar_url = BASE_URL .. "/repos/" .. owner .. "/" .. repo .. "/tarball/" .. urlEncodeQuery(ref)

    -- Download tarball to temp file
    local tmp_tar = dest_path .. ".tar.gz"
    local response_body = {}
    local headers = {
        ["User-Agent"] = "KOReader-GithubBrowser/1.0",
        ["Accept"]     = "application/vnd.github.v3+json",
    }
    if token and token ~= "" then
        headers["Authorization"] = "token " .. token
    end
    socketutil:set_timeout(30, 300)  -- longer timeout for large downloads
    local ok, code = socket_http.request {
        url      = tar_url,
        method   = "GET",
        headers  = headers,
        sink     = ltn12.sink.table(response_body),
        redirect = true,
    }
    socketutil:reset_timeout()
    if not ok then
        return nil, "Network error downloading tarball: " .. tostring(code)
    end
    if type(code) == "number" and code ~= 200 then
        return nil, "Failed to download tarball (HTTP " .. tostring(code) .. ")"
    end

    local tar_data = table_concat(response_body)
    if #tar_data == 0 then
        return nil, "Empty tarball response"
    end

    -- Write tarball to temp file
    local fh = io.open(tmp_tar, "wb")
    if not fh then
        return nil, "Cannot write temp tarball file"
    end
    fh:write(tar_data)
    fh:close()

    -- Extract using tar (available on all KOReader devices via BusyBox)
    local extract_dir = dest_path .. "_tar_extract"
    os.execute(string.format("rm -rf %q", extract_dir))
    ensureDir(extract_dir)
    local tar_cmd = string.format("tar xzf %q -C %q 2>&1", tmp_tar, extract_dir)
    local ret = os.execute(tar_cmd)
    if ret ~= 0 and ret ~= true then
        -- tar with gzip might not be supported; try with separate gunzip
        local gunzip_cmd = string.format("gunzip -f %q 2>&1", tmp_tar)
        local ret2 = os.execute(gunzip_cmd)
        if ret2 == 0 or ret2 == true then
            local plain_tar = dest_path .. ".tar"
            local tar_cmd2 = string.format("tar xf %q -C %q 2>&1", plain_tar, extract_dir)
            ret = os.execute(tar_cmd2)
            os.remove(plain_tar)
        end
        if ret ~= 0 and ret ~= true then
            os.execute(string.format("rm -rf %q %q", tmp_tar, extract_dir))
            return nil, "tar extraction failed. Is tar installed?"
        end
    end

    -- GitHub tarballs contain a single directory like owner-repo-sha/
    -- Find that directory and move its contents to dest_path
    local ok_iter, iter, dir_obj = pcall(lfs.dir, extract_dir)
    if not ok_iter then
        os.execute(string.format("rm -rf %q %q", tmp_tar, extract_dir))
        return nil, "Cannot read extracted directory"
    end
    local inner_dir = nil
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local full = extract_dir .. "/" .. entry
            if lfs.attributes(full, "mode") == "directory" then
                inner_dir = full
                break
            end
        end
    end

    if inner_dir then
        -- Move contents from inner dir to dest_path
        ensureDir(dest_path)
        os.execute(string.format("cp -a %q/. %q/ 2>/dev/null || cp -r %q/. %q/", inner_dir, dest_path, inner_dir, dest_path))
    else
        -- No inner directory, just move everything
        ensureDir(dest_path)
        os.execute(string.format("cp -a %q/. %q/ 2>/dev/null || cp -r %q/. %q/", extract_dir, dest_path, extract_dir, dest_path))
    end

    -- Cleanup temp files
    os.execute(string.format("rm -rf %q %q", tmp_tar, extract_dir))

    return true, nil
end

return GithubBrowserAPI
