local GitNotesSettings = require("githubbrowser_settings")

local IgnoreEngine = {}

local DEFAULT_PATTERNS = {
    ".git",
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

    for _, p in ipairs(DEFAULT_PATTERNS) do
        if matchGlob(basename, p) then return true end
    end

    local customs = GitNotesSettings.getIgnorePatterns()
    for _, p in ipairs(customs) do
        if matchGlob(basename, p) then return true end
    end

    return false
end

function IgnoreEngine.filterEntries(entries)
    local result = {}
    for _, entry in ipairs(entries) do
        if not IgnoreEngine.shouldIgnore(entry.name or entry) then
            table.insert(result, entry)
        end
    end
    return result
end

function IgnoreEngine.getDefaultPatterns()
    local copy = {}
    for _, p in ipairs(DEFAULT_PATTERNS) do
        table.insert(copy, p)
    end
    return copy
end

return IgnoreEngine
