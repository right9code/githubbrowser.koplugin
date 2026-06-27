local WidgetContainer  = require("ui/widget/container/widgetcontainer")
local Dispatcher       = require("dispatcher")
local UIManager        = require("ui/uimanager")
local InfoMessage      = require("ui/widget/infomessage")
local DocumentRegistry = require("document/documentregistry")
local _                = require("gettext")

local GithubBrowser = WidgetContainer:extend{
    name        = "githubbrowser",
    is_doc_only = false,
}

function GithubBrowser:onDispatcherRegisterActions()
    Dispatcher:registerAction("githubbrowser_open", {
        category = "none",
        event    = "OpenGithubBrowser",
        title    = _("GitHub Browser"),
        general  = true,
    })
    -- Register one action per quick repo for gesture shortcuts
    local GithubBrowserSettings = require("githubbrowser_settings")
    local quick_repos = GithubBrowserSettings.getQuickRepos()
    for i, repo in ipairs(quick_repos) do
        Dispatcher:registerAction("githubbrowser_quick_repo_" .. i, {
            category = "none",
            event    = "OpenGithubBrowserQuickRepo" .. i,
            title    = _("GH: ") .. repo,
            general  = true,
        })
    end
    -- Keep legacy single quick repo action
    Dispatcher:registerAction("githubbrowser_quick_repo", {
        category = "none",
        event    = "OpenGithubBrowserQuickRepo",
        title    = _("GitHub Browser: Quick Repo"),
        general  = true,
    })
end

function GithubBrowser:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self:registerDocumentRegistryAuxProvider()
end

function GithubBrowser:registerDocumentRegistryAuxProvider()
    DocumentRegistry:addAuxProvider({
        provider_name = self.name,
        provider      = self.name,
        order         = 25,
        disable_file  = true,
        disable_type  = false,
    })
end

function GithubBrowser:isFileTypeSupported(file)
    local suffix = file:lower():match("%.([^%.]+)$")
    return suffix == "md" or suffix == "markdown" or suffix == "txt"
end

function GithubBrowser:openFile(file, caller_callback)
    local Editor = require("githubbrowser_editor")
    Editor.openFile(file, caller_callback)
end

function GithubBrowser:addToMainMenu(menu_items)
    menu_items.githubbrowser = {
        text         = _("GitHub Browser"),
        sorting_hint = "search",
        callback     = function() self:onOpenGithubBrowser() end,
    }
end

function GithubBrowser:onOpenGithubBrowser()
    self:_launch()
end

function GithubBrowser:onOpenGithubBrowserQuickRepo()
    local GithubBrowserSettings = require("githubbrowser_settings")
    local quick_repo = GithubBrowserSettings.getQuickRepo()
    if not quick_repo or quick_repo == "" then
        self:_launch()
        return
    end
    self:_openQuickRepo(quick_repo)
end

-- Generate dynamic handlers for numbered quick repos
for _i = 1, 20 do
    GithubBrowser["onOpenGithubBrowserQuickRepo" .. _i] = function(self)
        local GithubBrowserSettings = require("githubbrowser_settings")
        local repos = GithubBrowserSettings.getQuickRepos()
        local repo = repos[_i]
        if not repo then
            self:_launch()
            return
        end
        self:_openQuickRepo(repo)
    end
end

function GithubBrowser:_openQuickRepo(repo_str)
    local GithubBrowserAPI = require("githubbrowser_api")
    local owner, repo = GithubBrowserAPI.parseRepoInput(repo_str)
    if not owner then
        self:_launch()
        return
    end
    local ok, browser = pcall(require, "githubbrowser_browser")
    if not ok then
        UIManager:show(InfoMessage:new{
            text    = _("GitHub Browser failed to load:\n") .. tostring(browser),
            timeout = 6,
        })
        return
    end
    browser.openRepo(owner, repo)
end

function GithubBrowser:_launch()
    local ok, browser_or_err = pcall(require, "githubbrowser_browser")
    if not ok then
        UIManager:show(InfoMessage:new{
            text    = _("GitHub Browser failed to load:\n") .. tostring(browser_or_err),
            timeout = 6,
        })
        return
    end
    browser_or_err.showHome()
end

return GithubBrowser
