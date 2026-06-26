local WidgetContainer  = require("ui/widget/container/widgetcontainer")
local Dispatcher       = require("dispatcher")
local UIManager        = require("ui/uimanager")
local InfoMessage      = require("ui/widget/infomessage")
local DocumentRegistry = require("document/documentregistry")
local _                = require("gettext")

local GitNotes = WidgetContainer:extend{
    name        = "githubbrowser",
    is_doc_only = false,
}

function GitNotes:onDispatcherRegisterActions()
    Dispatcher:registerAction("githubbrowser_open", {
        category = "none",
        event    = "OpenGitNotes",
        title    = _("GitNotes"),
        general  = true,
    })
    Dispatcher:registerAction("githubbrowser_quick_repo", {
        category = "none",
        event    = "OpenGitNotesQuickRepo",
        title    = _("GitNotes: Quick Repo"),
        general  = true,
    })
end

function GitNotes:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self:registerDocumentRegistryAuxProvider()
end

function GitNotes:registerDocumentRegistryAuxProvider()
    DocumentRegistry:addAuxProvider({
        provider_name = self.name,
        provider      = self.name,
        order         = 25,
        disable_file  = true,
        disable_type  = false,
    })
end

function GitNotes:isFileTypeSupported(file)
    local suffix = file:lower():match("%.([^%.]+)$")
    return suffix == "md" or suffix == "markdown" or suffix == "txt"
end

function GitNotes:openFile(file, caller_callback)
    local Editor = require("githubbrowser_editor")
    Editor.openFile(file, caller_callback)
end

function GitNotes:addToMainMenu(menu_items)
    menu_items.githubbrowser = {
        text         = _("GitNotes"),
        sorting_hint = "search",
        callback     = function() self:onOpenGitNotes() end,
    }
end

function GitNotes:onOpenGitNotes()
    self:_launch()
end

function GitNotes:onOpenGitNotesQuickRepo()
    local GitNotesSettings = require("githubbrowser_settings")
    local quick_repo = GitNotesSettings.getQuickRepo()
    if not quick_repo or quick_repo == "" then
        self:_launch()
        return
    end
    local GitNotesAPI = require("githubbrowser_api")
    local owner, repo = GitNotesAPI.parseRepoInput(quick_repo)
    if not owner then
        self:_launch()
        return
    end
    local ok, browser = pcall(require, "githubbrowser_browser")
    if not ok then
        UIManager:show(InfoMessage:new{
            text    = _("GitNotes failed to load:\n") .. tostring(browser),
            timeout = 6,
        })
        return
    end
    browser.openRepo(owner, repo)
end

function GitNotes:_launch()
    local ok, browser_or_err = pcall(require, "githubbrowser_browser")
    if not ok then
        UIManager:show(InfoMessage:new{
            text    = _("GitNotes failed to load:\n") .. tostring(browser_or_err),
            timeout = 6,
        })
        return
    end
    browser_or_err.showHome()
end

return GitNotes
