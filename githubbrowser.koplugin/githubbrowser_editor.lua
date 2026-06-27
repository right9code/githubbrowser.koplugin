local DataStorage  = require("datastorage")
local Device       = require("device")
local Font         = require("ui/font")
local Geom         = require("ui/geometry")
local InfoMessage  = require("ui/widget/infomessage")
local InputDialog  = require("ui/widget/inputdialog")
local Size         = require("ui/size")
local UIManager    = require("ui/uimanager")
local Screen       = require("device").screen
local ffiUtil      = require("ffi/util")
local lfs          = require("libs/libkoreader-lfs")
local logger       = require("logger")
local util         = require("util")
local _            = require("gettext")
local T            = ffiUtil.template

local GithubBrowserSettings  = require("githubbrowser_settings")
local EditorToolbar          = require("githubbrowser_editor_toolbar")
local UndoStack              = require("githubbrowser_undo")

local Editor = {}

local TEXT_EXT = {
    lua=true, py=true, js=true, ts=true, c=true, cpp=true, h=true,
    java=true, go=true, rs=true, sh=true, bash=true, md=true,
    markdown=true, json=true, yaml=true, yml=true, toml=true,
    ini=true, cfg=true, conf=true, xml=true, csv=true, txt=true,
    html=true, htm=true, css=true, rb=true, php=true, pl=true,
    swift=true, kt=true, r=true, tex=true, sql=true, diff=true,
    patch=true, gitignore=true, dockerfile=true, makefile=true,
}

local function getExt(name)
    return (name:match("%.([^%.]+)$") or ""):lower()
end

local function isTextFile(name)
    local ext = getExt(name)
    return TEXT_EXT[ext] or ext == ""
end

function Editor.openFile(file_path, caller_callback, remote_origin)
    local attr = lfs.attributes(file_path)
    if not attr then
        local f, err = io.open(file_path, "wb")
        if f then f:close(); os.remove(file_path)
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Cannot create file:\n%1\n%2"), file_path, err),
            })
            return
        end
    elseif attr.mode ~= "file" then
        UIManager:show(InfoMessage:new{ text = T(_("Not a file: %1"), file_path) })
        return
    end

    local content = util.readFromFile(file_path, "rb") or ""
    local filename = file_path:match("([^/]+)$") or file_path
    local readonly = false
    local test = io.open(file_path, "r+b")
    if test then test:close() else readonly = true end

    local undo_stack = UndoStack.new(GithubBrowserSettings.getUndoStackSize())
    undo_stack:push(content, 1)

    local show_kb = GithubBrowserSettings.getShowKeyboardOnStart()

    local saved_since_open = false
    local commit_btn_ref = nil  -- will hold reference to the commit button

    -- Check if this file is inside a git repo for the Commit button
    local git_repo_root = nil
    if remote_origin and not readonly then
        local GitOps = require("githubbrowser_git")
        local dir = file_path:match("^(.+)/[^/]+$")
        git_repo_root = dir
        while git_repo_root and git_repo_root ~= "/" do
            if GitOps.isGitRepo(git_repo_root) then break end
            git_repo_root = git_repo_root:match("^(.+)/[^/]+$")
        end
        if git_repo_root and not GitOps.isGitRepo(git_repo_root) then
            git_repo_root = nil
        end
    end

    -- Build the bottom button row
    local bottom_buttons = {{
        text = _("Close"),
        id = "close",
        callback = function()
            input:onClose()
        end,
    }}
    if git_repo_root then
        bottom_buttons[#bottom_buttons + 1] = {
            text = _("Commit"),
            id = "commit",
            enabled = false,  -- greyed out until Save is pressed
            callback = function()
                if not saved_since_open then
                    UIManager:show(InfoMessage:new{ text = _("Save first, then commit."), timeout = 3 })
                    return
                end
                local GitOps = require("githubbrowser_git")
                local rel = file_path:sub(#git_repo_root + 2)

                local loading = InfoMessage:new{ text = _("Committing..."), timeout = 60 }
                UIManager:show(loading)
                UIManager:forceRePaint()

                local device = GithubBrowserSettings.getDeviceName() or "koreader"
                local msg = "Edit " .. rel .. " from " .. device
                local c_ok, c_err = GitOps.syncSingleFile(git_repo_root, rel, msg)
                UIManager:close(loading)
                if c_ok then
                    UIManager:show(InfoMessage:new{ text = _("Committed & pushed!"), timeout = 2 })
                else
                    UIManager:show(InfoMessage:new{ text = _("Commit failed: ") .. (c_err or "?"), timeout = 4 })
                end
            end,
        }
    end

    local input
    input = InputDialog:new{
        title             = filename,
        input             = content,
        input_face        = Font:getFace(GithubBrowserSettings.getFontFace(), GithubBrowserSettings.getFontSize()),
        fullscreen        = true,
        condensed         = true,
        allow_newline     = true,
        cursor_at_end     = false,
        readonly          = readonly,
        add_nav_bar       = true,
        rotation_enabled  = true,
        keyboard_visible  = show_kb,
        scroll_by_pan     = true,
        buttons = { bottom_buttons },
        save_callback = function(text, closing)
            if readonly then return false, _("File is read only") end
            local ok = util.writeToFile(text, file_path)
            if ok then
                saved_since_open = true
                -- Enable commit button if it exists
                if input._button_table then
                    for __, row in ipairs(input._button_table) do
                        for __, btn in ipairs(row) do
                            if btn.id == "commit" and btn.enabled == false then
                                btn:enable()
                            end
                        end
                    end
                end
                return true, _("File saved")
            else
                return false, _("Failed to save")
            end
        end,
    }

    if not readonly then
        local toolbar = EditorToolbar:new{
            input_dialog = input,
            bar_width    = input:getAddedWidgetAvailableWidth(),
        }
        toolbar:setUndoStack(undo_stack)
        input:addWidget(toolbar.widget)

        local orig_edit_cb = input._input_widget.edit_callback
        input._input_widget.edit_callback = function()
            if toolbar.restoring then return end
            if orig_edit_cb then orig_edit_cb(true) end
            local iw = input._input_widget
            local text = iw:getText()
            undo_stack:push(text, iw.charpos)
        end
    end

    UIManager:show(input)
    if show_kb and not readonly then
        input:onShowKeyboard()
    end
end

function Editor.openRemoteFile(name, text_content, download_url, buttons_extra)
    if not isTextFile(name) then
        return false
    end

    if #text_content > 50000 then
        text_content = text_content:sub(1, 50000) .. "\n\n── [ truncated at 50k chars ] ──"
    end

    local buttons = {}
    if buttons_extra then
        for __, row in ipairs(buttons_extra) do
            buttons[#buttons + 1] = row
        end
    end

    local TextViewer = require("ui/widget/textviewer")
    UIManager:show(TextViewer:new{
        title          = name,
        text           = text_content,
        height         = math.floor(Screen:getHeight() * 0.85),
        buttons_table  = #buttons > 0 and buttons or nil,
    })
    return true
end

-- ── Markdown Preview ──────────────────────────────────────────────────────────

function Editor.togglePreview(input_dialog)
    local content = input_dialog:getInputText()
    local preview_widget

    input_dialog:onCloseKeyboard()

    local parse_markdown = require("apps/filemanager/lib/md")
    local processed = Editor.preprocessContent(content)
    local html_content = parse_markdown(processed)
    html_content = html_content:gsub('<a href=""> </a>', '[ ]')
    html_content = html_content:gsub('<a href="">x</a>', '[x]')

    local preview_css = [[
body { padding: 15px; font-family: sans-serif; line-height: 1.5; }
h1, h2, h3, h4 { font-weight: bold; margin-top: 1.2em; margin-bottom: 0.4em; }
h1 { font-size: 1.5em; border-bottom: 1px solid #ccc; }
h2 { font-size: 1.3em; border-bottom: 1px solid #eee; }
h3 { font-size: 1.1em; }
p { margin-bottom: 0.8em; }
code { background-color: #f0f0f0; padding: 2px 4px; border-radius: 3px; font-family: monospace; }
pre { background-color: #f0f0f0; padding: 8px; border-radius: 4px; margin-bottom: 0.8em; }
pre code { background-color: transparent; padding: 0; }
ul { margin-bottom: 0.8em; padding-left: 20px; list-style-type: disc; }
ol { margin-bottom: 0.8em; padding-left: 20px; list-style-type: decimal; }
li { margin-bottom: 0.2em; }
blockquote { border-left: 3px solid #ccc; padding-left: 8px; color: #555; margin: 0 0 0.8em 0; }
table { border-collapse: collapse; margin-bottom: 0.8em; }
th, td { border: 1px solid #ccc; padding: 4px 8px; }
th { background-color: #f0f0f0; }
del { text-decoration: line-through; }
mark { background-color: #bbb; }
]]

    local full_html = string.format(
        "<!DOCTYPE html><html><head><style>%s</style></head><body>%s</body></html>",
        preview_css, html_content
    )
    local tmp_path = DataStorage:getDataDir() .. "/tmp_githubbrowser_preview.html"
    util.writeToFile(full_html, tmp_path)

    local CreDocument = require("document/credocument")
    local ok, doc = pcall(CreDocument.new, CreDocument, { file = tmp_path })
    if not ok then
        UIManager:show(InfoMessage:new{ text = "Preview engine failed." })
        os.remove(tmp_path)
        return
    end
    doc:render()

    local Blitbuffer   = require("ffi/blitbuffer")
    local ButtonTable  = require("ui/widget/buttontable")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local LineWidget   = require("ui/widget/linewidget")

    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    local button_table = ButtonTable:new{
        width = screen_w - 2 * Size.padding.default,
        buttons = {{{
            text = _("Edit"),
            callback = function() Editor.endPreview(input_dialog, doc, tmp_path, preview_widget) end,
        }}},
        zero_sep = true,
    }
    local sep_line = LineWidget:new{
        dimen = Geom:new{ w = screen_w, h = Size.line.thick },
        background = Blitbuffer.COLOR_DARK_GRAY,
    }
    local btn_bar_height = button_table:getSize().h + sep_line:getSize().h
    local view_h = screen_h - btn_bar_height
    local view_rect = Geom:new{ x = 0, y = 0, w = screen_w, h = view_h }

    local current_pos = 0
    local doc_height = doc.info.doc_height or view_h
    local max_pos = math.max(0, doc_height - view_h)
    local scroll_step = math.floor(view_h * 0.75)

    local ContentArea = WidgetContainer:new{ dimen = view_rect }
    function ContentArea:paintTo(bb, x, y)
        doc:gotoPos(current_pos)
        doc:drawCurrentView(bb, x, y, view_rect)
    end

    preview_widget = InputContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h },
        covers_fullscreen = true,
        is_always_active = true,
        [1] = FrameContainer:new{
            width = screen_w, height = screen_h,
            bordersize = 0, padding = 0, margin = 0,
            background = Blitbuffer.COLOR_WHITE,
            VerticalGroup:new{
                ContentArea,
                sep_line,
                button_table,
            },
        },
    }

    local function scrollDown()
        if current_pos < max_pos then
            current_pos = math.min(current_pos + scroll_step, max_pos)
            UIManager:setDirty(preview_widget, "partial")
        end
    end
    local function scrollUp()
        if current_pos > 0 then
            current_pos = math.max(current_pos - scroll_step, 0)
            UIManager:setDirty(preview_widget, "partial")
        end
    end

    preview_widget:registerTouchZones({
        {
            id = "preview_swipe",
            ges = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges)
                if ges.direction == "north" or ges.direction == "west" then
                    scrollDown()
                elseif ges.direction == "south" or ges.direction == "east" then
                    scrollUp()
                end
                return true
            end,
        },
        {
            id = "preview_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = view_h / screen_h },
            handler = function(ges)
                if ges.pos.y > view_h * 0.5 then
                    scrollDown()
                else
                    scrollUp()
                end
                return true
            end,
        },
    })

    if Device:hasDPad() then
        preview_widget.key_events = {
            PreviewScrollUp   = { { "Up" } },
            PreviewScrollDown = { { "Down" } },
        }
    end
    if Device:hasKeys() then
        preview_widget.key_events = preview_widget.key_events or {}
        preview_widget.key_events.PreviewScrollUp   = { { "LPgBack" } }
        preview_widget.key_events.PreviewScrollDown  = { { "LPgFwd" } }
    end
    function preview_widget:onPreviewScrollUp() scrollUp() return true end
    function preview_widget:onPreviewScrollDown() scrollDown() return true end

    function preview_widget:onCloseWidget()
        pcall(function() doc:close() end)
        pcall(function() os.remove(tmp_path) end)
    end

    UIManager:show(preview_widget)
    UIManager:setDirty("all", "full")
end

function Editor.endPreview(input_dialog, doc, tmp_path, preview_widget)
    UIManager:close(preview_widget)
    UIManager:setDirty("all", "full")
end

function Editor.preprocessContent(content)
    content = content:gsub("~~([^~]+)~~", "<del>%1</del>")
    content = content:gsub("==([^=]+)==", "<mark>%1</mark>")
    content = content:gsub("%[%[([^%]]+)%]%]", function(inner)
        local label, target = inner:match("^(.-)|(.+)$")
        if target then
            return string.format('<a href="%s">%s</a>', target, label)
        end
        return string.format('<a href="%s">%s</a>', inner, inner)
    end)
    return content
end

return Editor
