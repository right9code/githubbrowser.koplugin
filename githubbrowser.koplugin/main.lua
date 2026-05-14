--[[--
@module koplugin.GithubBrowser
Github Browser — browse GitHub repositories from KOReader.
--]]--

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Dispatcher      = require("dispatcher")
local UIManager       = require("ui/uimanager")
local InfoMessage     = require("ui/widget/infomessage")
local NetworkMgr      = require("ui/network/manager")
local _               = require("gettext")

local GithubBrowser = WidgetContainer:extend {
    name        = "githubbrowser",
    is_doc_only = false,
}

function GithubBrowser:onDispatcherRegisterActions()
    Dispatcher:registerAction("github_browser_open", {
        category = "none",
        event = "OpenGithubBrowser",
        title = _("Github Browser"),
        general = true,
    })
end

function GithubBrowser:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function GithubBrowser:addToMainMenu(menu_items)
    menu_items.githubbrowser = {
        text         = _("Github Browser"),
        sorting_hint = "search",
        callback     = function()
            self:onOpenGithubBrowser()
        end,
    }
end

function GithubBrowser:onOpenGithubBrowser()
    -- Ensure network is available before doing anything
    if not NetworkMgr:isOnline() then
        NetworkMgr:promptWifiOn(function()
            self:_launch()
        end)
        return
    end
    self:_launch()
end

function GithubBrowser:_launch()
    -- Lazy-load the browser module to keep KOReader startup fast
    local ok, browser_or_err = pcall(require, "browser")
    if not ok then
        UIManager:show(InfoMessage:new {
            text    = _("Github Browser failed to load:\n") .. tostring(browser_or_err),
            timeout = 6,
        })
        return
    end
    browser_or_err.showHome()
end

return GithubBrowser
