local Blitbuffer     = require("ffi/blitbuffer")
local Button         = require("ui/widget/button")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputDialog    = require("ui/widget/inputdialog")
local LineWidget     = require("ui/widget/linewidget")
local Size           = require("ui/size")
local UIManager      = require("ui/uimanager")
local VerticalGroup  = require("ui/widget/verticalgroup")
local Screen         = require("device").screen
local _              = require("gettext")

local EditorToolbar = {}

function EditorToolbar:new(config)
    local o = setmetatable({}, { __index = self })
    o.input_dialog = config.input_dialog
    o.bar_width    = config.bar_width or Screen:getWidth()
    o.restoring    = false
    o:getWidget()
    return o
end

function EditorToolbar:getInputWidget()
    return self.input_dialog._input_widget
end

function EditorToolbar:notifyModified()
    local dlg = self.input_dialog
    if dlg._buttons_edit_callback then
        dlg._buttons_edit_callback(true)
    end
end

function EditorToolbar:getWidget()
    local bar_width = self.bar_width
    local btn_h = Screen:scaleBySize(32)
    local borders = Size.border.thin

    local function makeBtn(text, callback, width_override)
        return Button:new{
            text       = text,
            callback   = callback,
            width      = width_override or nil,
            height     = btn_h,
            bordersize = borders,
            margin     = 0,
            padding    = 0,
            text_font_size = 16,
        }
    end

    -- ── Row 1: Formatting ─────────────────────────────────────────────────────

    local fmt_keys = {
        { text = "H#", callback = function() self:cycleHeading() end },
        { text = "B",  callback = function() self:wrapText("**", "**") end },
        { text = "I",  callback = function() self:wrapText("*", "*") end },
        { text = "S",  callback = function() self:wrapText("~~", "~~") end },
        { text = "-",  callback = function() self:getInputWidget():addChars("- ") end },
        { text = "1.", callback = function() self:autoNumber() end },
        { text = "[ ]",callback = function() self:getInputWidget():addChars("- [ ] ") end },
        { text = ">",  callback = function() self:getInputWidget():addChars("> ") end },
        { text = "`",  callback = function() self:wrapText("`", "`") end },
        { text = "```",callback = function() self:wrapText("```\n", "\n```") end },
        { text = "Lnk",callback = function() self:wrapText("[", "](url)") end },
        { text = "Tbl",callback = function() self:insertTable() end },
    }

    local fmt_btn_w = math.floor(bar_width / #fmt_keys)
    local fmt_row = HorizontalGroup:new{ allow_mirroring = false }
    for _, kd in ipairs(fmt_keys) do
        fmt_row[#fmt_row + 1] = makeBtn(kd.text, kd.callback, fmt_btn_w)
    end

    -- ── Row 2: Navigation ─────────────────────────────────────────────────────

    local nav_keys = {
        { text = "Tab",   callback = function() self:getInputWidget():addChars(string.rep(" ", self:getTabSize())) end },
        { text = "S+Tab", callback = function() self:outdent() end },
        { text = "Undo",  callback = function() self:performUndo() end },
        { text = "Redo",  callback = function() self:performRedo() end },
        { text = "Home",  callback = function() self:getInputWidget():goToStartOfLine() end },
        { text = "End",   callback = function() self:getInputWidget():goToEndOfLine() end },
        { text = "\u{2191}", callback = function() self:getInputWidget():upLine() end },
        { text = "\u{2193}", callback = function() self:getInputWidget():downLine() end },
    }

    local nav_btn_w = math.floor(bar_width / #nav_keys)
    local nav_row = HorizontalGroup:new{ allow_mirroring = false }
    for _, kd in ipairs(nav_keys) do
        nav_row[#nav_row + 1] = makeBtn(kd.text, kd.callback, nav_btn_w)
    end

    -- ── Separators ────────────────────────────────────────────────────────────

    local sep = LineWidget:new{
        dimen = Geom:new{ w = bar_width, h = Size.line.thin },
        background = Blitbuffer.COLOR_DARK_GRAY,
    }

    self.widget = VerticalGroup:new{
        fmt_row,
        sep,
        nav_row,
    }
    return self.widget
end

function EditorToolbar:getTabSize()
    local ok, s = pcall(require, "githubbrowser_settings")
    if ok then return s.getTabSize() end
    return 4
end

-- ── Formatting helpers ────────────────────────────────────────────────────────

function EditorToolbar:wrapText(prefix, suffix)
    local iw = self:getInputWidget()
    local start_pos = iw.selection_start_pos
    local end_pos = iw.charpos - 1

    if start_pos and end_pos and start_pos <= end_pos then
        local selected_chars = {}
        for i = start_pos, end_pos do
            selected_chars[#selected_chars + 1] = iw.charlist[i]
        end
        local selected_text = table.concat(selected_chars)
        for i = end_pos, start_pos, -1 do
            table.remove(iw.charlist, i)
        end
        iw.charpos = start_pos
        iw:addChars(prefix .. selected_text .. suffix)
        iw.selection_start_pos = nil
    else
        iw:addChars(prefix .. suffix)
        local suffix_chars = require("util").splitToChars(suffix)
        iw:moveCursorToCharPos(iw.charpos - #suffix_chars)
    end
end

function EditorToolbar:cycleHeading()
    local iw = self:getInputWidget()
    local charpos = iw.charpos
    local text = iw:getText()

    -- Find line start (byte offset)
    local line_start = 1
    local byte_pos = 1
    local char_idx = 1
    while char_idx < charpos and byte_pos <= #text do
        local next_byte = byte_pos
        if text:byte(byte_pos) == 10 then -- \n
            line_start = byte_pos + 1
        end
        byte_pos = next_byte + select(2, utf8.codes(text:sub(byte_pos, byte_pos + 3))) or 1
        if byte_pos <= next_byte then byte_pos = next_byte + 1 end
        char_idx = char_idx + 1
    end

    -- Extract current line
    local line_end = text:find("\n", line_start, true)
    line_end = line_end and (line_end - 1) or #text
    local line = text:sub(line_start, line_end)

    -- Count leading '#'
    local hashes, rest = line:match("^(#+)(.*)")
    local hash_count = hashes and #hashes or 0

    local new_line
    if hash_count >= 5 then
        -- Strip all leading '# ' or '##' etc
        new_line = rest:gsub("^%s*", "")
    elseif hash_count > 0 then
        new_line = "#" .. line
    else
        new_line = "# " .. line
    end

    local new_text = text:sub(1, line_start - 1) .. new_line .. text:sub(line_end + 1)
    local offset_diff = #new_line - #line
    iw:setText(new_text, true)
    iw:moveCursorToCharPos(charpos + (offset_diff > 0 and 1 or 0))
    self:notifyModified()
end

function EditorToolbar:autoNumber()
    local iw = self:getInputWidget()
    local charpos = iw.charpos
    local line_start = 1
    for i = charpos - 1, 1, -1 do
        if iw.charlist[i] == "\n" then
            line_start = i + 1
            break
        end
    end

    local curr_text = table.concat(iw.charlist, "", line_start, charpos - 1)
    local prev_num = curr_text:match("^(%d+)%. ")

    if not prev_num and line_start > 1 then
        local prev_end = line_start - 2
        local prev_start = 1
        for i = prev_end - 1, 1, -1 do
            if iw.charlist[i] == "\n" then
                prev_start = i + 1
                break
            end
        end
        local prev_text = table.concat(iw.charlist, "", prev_start, prev_end)
        prev_num = prev_text:match("^(%d+)%. ")
    end

    local next_num = prev_num and (tonumber(prev_num) + 1) or 1
    iw:addChars(next_num .. ". ")
end

function EditorToolbar:outdent()
    local iw = self:getInputWidget()
    local charpos = iw.charpos
    local tab_size = self:getTabSize()

    -- Find line start using charlist (no utf8 module needed)
    local line_start = 1
    for i = charpos - 1, 1, -1 do
        if iw.charlist[i] == "\n" then
            line_start = i + 1
            break
        end
    end

    -- Count removable leading spaces/tabs
    local removed = 0
    for i = line_start, math.min(line_start + tab_size - 1, #iw.charlist) do
        local ch = iw.charlist[i]
        if ch == " " or ch == "\t" then
            removed = removed + 1
        else
            break
        end
    end

    if removed == 0 then return end

    -- Remove from charlist
    for _ = 1, removed do
        table.remove(iw.charlist, line_start)
    end

    iw.charpos = math.max(1, charpos - removed)
    iw.is_text_edited = true
    iw:initTextBox(nil, true)
    self:notifyModified()
end

function EditorToolbar:insertTable()
    local dlg
    dlg = InputDialog:new{
        title = _("Table size (e.g. 3x3)"),
        input = "3x3",
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dlg) end },
            { text = _("Insert"), is_enter_default = true, callback = function()
                local input = dlg:getInputText()
                UIManager:close(dlg)
                local cols, rows = input:match("(%d+)%s*x%s*(%d+)")
                cols = tonumber(cols) or 3
                rows = tonumber(rows) or 3
                self:_doInsertTable(cols, rows)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function EditorToolbar:_doInsertTable(cols, rows)
    local lines = {}
    local header = "|"
    for c = 1, cols do header = header .. " Header " .. c .. " |" end
    lines[#lines + 1] = header
    local sep = "|"
    for c = 1, cols do sep = sep .. " --- |" end
    lines[#lines + 1] = sep
    for _ = 1, rows - 1 do
        local row = "|"
        for _ = 1, cols do row = row .. "  |" end
        lines[#lines + 1] = row
    end
    self:getInputWidget():addChars("\n" .. table.concat(lines, "\n") .. "\n")
end

-- ── Undo/Redo integration ─────────────────────────────────────────────────────

function EditorToolbar:setUndoStack(undo_stack)
    self.undo_stack = undo_stack
end

function EditorToolbar:performUndo()
    if not self.undo_stack then return end
    local state = self.undo_stack:undo()
    if state then
        self.restoring = true
        local iw = self:getInputWidget()
        iw:setText(state.content, true)
        if state.cursor_pos then
            iw:moveCursorToCharPos(state.cursor_pos)
        end
        self.restoring = false
    end
end

function EditorToolbar:performRedo()
    if not self.undo_stack then return end
    local state = self.undo_stack:redo()
    if state then
        self.restoring = true
        local iw = self:getInputWidget()
        iw:setText(state.content, true)
        if state.cursor_pos then
            iw:moveCursorToCharPos(state.cursor_pos)
        end
        self.restoring = false
    end
end

return EditorToolbar
