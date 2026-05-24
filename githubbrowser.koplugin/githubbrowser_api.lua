--[[--
GitHub REST API wrapper for the Github Browser plugin.
Uses KOReader's socket.http + socketutil for GET requests.
Phase 1: Read-only, no authentication.
--]]--

local json        = require("json")
local socket_http = require("socket.http")
local socketutil  = require("socketutil")
local ltn12       = require("ltn12")
local logger      = require("logger")
local DataStorage = require("datastorage")
local bit         = require("bit")

local GithubBrowserSettings = require("githubbrowser_settings")

local GithubBrowserAPI = {}

local BASE_URL = "https://api.github.com"

local DEFAULT_TIMEOUT = 30
local DEFAULT_MAXTIME = 60

-- ── Pure-Lua Base64 encoder ───────────────────────────────────────────────────

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

-- ── curl-based write helper ───────────────────────────────────────────────────

local function curlRequest(url, method, payload, token)
    logger.dbg("GithubBrowserAPI: " .. method .. " " .. url)

    local headers = {
        ["User-Agent"] = "KOReader-GithubBrowser/1.0",
        ["Accept"]     = "application/vnd.github.v3+json",
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
    local ok, code, _resp_headers, _status = socket_http.request {
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

    local ok2, data = pcall(json.decode, response)
    if not ok2 then
        return nil, "Failed to parse response (HTTP " .. tostring(code) .. "): " .. response:sub(1, 200)
    end

    if type(code) == "number" and code >= 400 then
        return nil, "API Error (HTTP " .. tostring(code) .. "): " .. (data.message or "?")
    end

    return data, nil
end

-- ── HTTP GET helper ───────────────────────────────────────────────────────────

local function extractRepoFromURL(url)
    local owner, repo = url:match("/repos/([^/]+)/([^/]+)")
    if owner and repo then return owner .. "/" .. repo end
    owner, repo = url:match("raw%.githubusercontent%.com/([^/]+)/([^/]+)")
    if owner and repo then return owner .. "/" .. repo end
    return nil
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
    local ok, code, _resp_headers, _status = socket_http.request {
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

    local ok2, data = pcall(json.decode, body)
    if not ok2 then
        return nil, "Failed to parse API response."
    end

    return data, nil
end

-- ── Fetch raw file content ────────────────────────────────────────────────────

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

-- ── URL Encoding Helpers ──────────────────────────────────────────────────────

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

--- Fetch repository metadata (default branch, description, etc.).
function GithubBrowserAPI.getRepo(owner, repo)
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo
    return makeRequest(url)
end

--- List contents of a repo path (root if path is nil/empty).
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

--- Fetch repository Git Tree recursively.
function GithubBrowserAPI.getTree(owner, repo, ref)
    ref = ref or "main"
    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo .. "/git/trees/" .. urlEncodePath(ref) .. "?recursive=1"
    return makeRequest(url)
end

--- Search code within a repository.
function GithubBrowserAPI.searchCode(owner, repo, query)
    local full_query = query .. " repo:" .. owner .. "/" .. repo
    local url = BASE_URL .. "/search/code?q=" .. urlEncodeQuery(full_query) .. "&per_page=50"
    return makeRequest(url, "application/vnd.github.v3.text-match+json")
end

--- Download a raw file URL and return its text content.
function GithubBrowserAPI.getRawFile(raw_url)
    return fetchRaw(raw_url)
end

--- Download a raw file URL and save it to disk.
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

--- Human-readable byte size string.
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

--- Split "owner/repo" string into two parts.
--- Accepts: "owner/repo", "https://github.com/owner/repo", "owner/repo.git"
function GithubBrowserAPI.parseRepoInput(input)
    if not input then return nil, nil end
    input = input:match("^%s*(.-)%s*$")           -- trim
    input = input:gsub("^https?://github%.com/", "") -- strip URL prefix
    input = input:gsub("%.git$", "")                 -- strip .git suffix
    input = input:gsub("/+$", "")                    -- strip trailing slashes
    local owner, repo = input:match("^([^/]+)/([^/]+)$")
    return owner, repo
end

--- Update a file in a GitHub repository via curl
function GithubBrowserAPI.updateFile(owner, repo, path, content, sha, branch, message, token)
    if not token or token == "" then
        return nil, "A GitHub token is required to edit files."
    end

    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo .. "/contents/" .. urlEncodePath(path)

    local body = {
        message = message or "Update " .. path,
        content = b64encode(content),
        branch  = branch,
    }
    if sha and sha ~= "" then
        body.sha = sha
    end

    return curlRequest(url, "PUT", json.encode(body), token)
end

--- Delete a file in a GitHub repository via curl
function GithubBrowserAPI.deleteFile(owner, repo, path, sha, branch, message, token)
    if not token or token == "" then
        return nil, "A GitHub token is required to delete files."
    end

    local url = BASE_URL .. "/repos/" .. owner .. "/" .. repo .. "/contents/" .. urlEncodePath(path)

    local body = {
        message = message or "Delete " .. path,
        sha = sha,
        branch  = branch,
    }

    return curlRequest(url, "DELETE", json.encode(body), token)
end

--- Recursively delete a directory (by deleting all its files)
function GithubBrowserAPI.deleteDirectory(owner, repo, path, branch, message, token)
    -- First get all contents of the directory
    local contents, err = GithubBrowserAPI.getContents(owner, repo, path, branch)
    if not contents then return false, "Failed to read directory: " .. (err or "?") end
    if contents.type == "file" then return false, "Path is a file, not a directory" end

    for _, entry in ipairs(contents) do
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

return GithubBrowserAPI
