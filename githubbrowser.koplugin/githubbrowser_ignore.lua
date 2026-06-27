local GithubBrowserSettings = require("githubbrowser_settings")

local IgnoreEngine = {}

local DEFAULT_PATTERNS = {
    ".git",
    ".ghbrowser.json",
    "*.sdr",
    ".koreader",
    "*.tmp",
    ".DS_Store",
    "Thumbs.db",
}

local function matchGlob(name, pattern)
    if pattern:sub(1, 2) == "*." then
        local ext = pattern:sub(3)
        return name:sub(-#ext - 1) == "." .. ext
    end
    if pattern:sub(1, 1) == "*" then
        local suffix = pattern:sub(2)
        return name:sub(-#suffix) == suffix
    end
    return name == pattern
end

function IgnoreEngine.shouldIgnore(path)
    local basename = path:match("([^/]+)/?$") or path

    for __, p in ipairs(DEFAULT_PATTERNS) do
        if matchGlob(basename, p) then return true end
    end

    local customs = GithubBrowserSettings.getIgnorePatterns()
    for __, p in ipairs(customs) do
        if matchGlob(basename, p) then return true end
    end

    return false
end

function IgnoreEngine.filterEntries(entries)
    local result = {}
    for __, entry in ipairs(entries) do
        if not IgnoreEngine.shouldIgnore(entry.name or entry) then
            result[#result + 1] = entry
        end
    end
    return result
end

function IgnoreEngine.getDefaultPatterns()
    local copy = {}
    for __, p in ipairs(DEFAULT_PATTERNS) do
        copy[#copy + 1] = p
    end
    return copy
end

return IgnoreEngine
