local UndoStack = {}
UndoStack.__index = UndoStack

function UndoStack.new(max_size)
    return setmetatable({
        stack   = {},
        pointer = 0,
        max_size = max_size or 100,
    }, UndoStack)
end

function UndoStack:push(content, cursor_pos)
    if self.pointer < #self.stack then
        for i = #self.stack, self.pointer + 1, -1 do
            self.stack[i] = nil
        end
    end
    table.insert(self.stack, { content = content, cursor_pos = cursor_pos })
    self.pointer = #self.stack
    if #self.stack > self.max_size then
        table.remove(self.stack, 1)
        self.pointer = self.pointer - 1
    end
end

function UndoStack:undo()
    if self.pointer > 1 then
        self.pointer = self.pointer - 1
        return self.stack[self.pointer]
    end
    return nil
end

function UndoStack:redo()
    if self.pointer < #self.stack then
        self.pointer = self.pointer + 1
        return self.stack[self.pointer]
    end
    return nil
end

function UndoStack:canUndo()
    return self.pointer > 1
end

function UndoStack:canRedo()
    return self.pointer < #self.stack
end

function UndoStack:clear()
    self.stack = {}
    self.pointer = 0
end

function UndoStack:current()
    if self.pointer > 0 and self.stack[self.pointer] then
        return self.stack[self.pointer]
    end
    return nil
end

return UndoStack
