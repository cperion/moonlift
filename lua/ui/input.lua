local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Interact = T.Interact

local M = {}

-- Compatibility aliases used by existing host/text code. New code should prefer
-- the typed helpers below, but these strings remain the backend-independent host
-- vocabulary.
M.ButtonLeft = "left"
M.ButtonMiddle = "middle"
M.ButtonRight = "right"
M.ButtonX1 = "x1"
M.ButtonX2 = "x2"

M.KeyReturn = "return"
M.KeyEscape = "escape"
M.KeyBackspace = "backspace"
M.KeyTab = "tab"
M.KeySpace = "space"
M.KeyDelete = "delete"
M.KeyHome = "home"
M.KeyEnd = "end"
M.KeyPageUp = "pageup"
M.KeyPageDown = "pagedown"
M.KeyLeft = "left"
M.KeyRight = "right"
M.KeyUp = "up"
M.KeyDown = "down"
M.KeyA = "a"
M.KeyC = "c"
M.KeyV = "v"
M.KeyX = "x"

local key_by_name = {
    [M.KeyReturn] = Interact.KeyReturn,
    [M.KeyEscape] = Interact.KeyEscape,
    [M.KeyBackspace] = Interact.KeyBackspace,
    [M.KeyTab] = Interact.KeyTab,
    [M.KeySpace] = Interact.KeySpace,
    [M.KeyDelete] = Interact.KeyDelete,
    [M.KeyHome] = Interact.KeyHome,
    [M.KeyEnd] = Interact.KeyEnd,
    [M.KeyPageUp] = Interact.KeyPageUp,
    [M.KeyPageDown] = Interact.KeyPageDown,
    [M.KeyLeft] = Interact.KeyLeft,
    [M.KeyRight] = Interact.KeyRight,
    [M.KeyUp] = Interact.KeyUp,
    [M.KeyDown] = Interact.KeyDown,
}

local button_by_name = {
    [M.ButtonLeft] = Interact.BtnLeft,
    [M.ButtonMiddle] = Interact.BtnMiddle,
    [M.ButtonRight] = Interact.BtnRight,
    [M.ButtonX1] = Interact.BtnX1,
    [M.ButtonX2] = Interact.BtnX2,
}

local function is_asdl_value(v, ctor)
    return v == ctor
end

local function bool(v)
    return v == true
end

function M.modifiers(opts)
    opts = opts or {}
    return Interact.Modifiers(
        bool(opts.shift),
        bool(opts.ctrl),
        bool(opts.alt),
        bool(opts.meta or opts.gui or opts.super)
    )
end

function M.no_modifiers()
    return Interact.Modifiers(false, false, false, false)
end

function M.key_from_name(name)
    if name == nil then
        return Interact.KeyUnknown("")
    end
    if key_by_name[name] ~= nil then
        return key_by_name[name]
    end
    if type(name) == "string" and #name == 1 then
        return Interact.KeyChar(name)
    end
    return Interact.KeyUnknown(tostring(name))
end

function M.key_name(key)
    for name, value in pairs(key_by_name) do
        if key == value then
            return name
        end
    end
    local cls = require("pvm").classof(key)
    if cls == Interact.KeyChar then return key.value end
    if cls == Interact.KeyUnknown then return key.name end
    return tostring(key)
end

function M.button_from_name(name)
    if button_by_name[name] ~= nil then return button_by_name[name] end
    return nil
end

function M.key_return() return Interact.KeyReturn end
function M.key_escape() return Interact.KeyEscape end
function M.key_backspace() return Interact.KeyBackspace end
function M.key_tab() return Interact.KeyTab end
function M.key_space() return Interact.KeySpace end
function M.key_delete() return Interact.KeyDelete end
function M.key_home() return Interact.KeyHome end
function M.key_end() return Interact.KeyEnd end
function M.key_page_up() return Interact.KeyPageUp end
function M.key_page_down() return Interact.KeyPageDown end
function M.key_left() return Interact.KeyLeft end
function M.key_right() return Interact.KeyRight end
function M.key_up() return Interact.KeyUp end
function M.key_down() return Interact.KeyDown end
function M.key_char(ch) return Interact.KeyChar(ch) end
function M.key_unknown(name) return Interact.KeyUnknown(tostring(name or "")) end

function M.raw_pointer_moved(x, y)
    return Interact.PointerMoved(x or 0, y or 0)
end

function M.raw_pointer_pressed(button, x, y)
    if type(button) == "string" then button = M.button_from_name(button) end
    button = button or Interact.BtnLeft
    return Interact.PointerPressed(button, x or 0, y or 0)
end

function M.raw_pointer_released(button, x, y)
    if type(button) == "string" then button = M.button_from_name(button) end
    button = button or Interact.BtnLeft
    return Interact.PointerReleased(button, x or 0, y or 0)
end

function M.raw_pointer_cancelled()
    return Interact.PointerCancelled
end

function M.raw_wheel_moved(dx, dy, x, y)
    return Interact.WheelMoved(dx or 0, dy or 0, x or 0, y or 0)
end

function M.raw_key_down(key, mods, repeat_)
    if type(key) == "string" or key == nil then key = M.key_from_name(key) end
    if mods == nil then mods = M.no_modifiers() end
    return Interact.KeyPressed(key, mods, repeat_ == true or repeat_ == 1)
end

function M.raw_key_up(key, mods)
    if type(key) == "string" or key == nil then key = M.key_from_name(key) end
    if mods == nil then mods = M.no_modifiers() end
    return Interact.KeyReleased(key, mods)
end

function M.raw_text_input(text)
    return Interact.TextInput(text or "")
end

function M.raw_text_editing(text, start, length)
    return Interact.TextEditing(text or "", start or 0, length or 0)
end

function M.raw_focus_lost()
    return Interact.FocusLost
end

function M.focus_intent_for_key(key, mods)
    if type(key) == "string" or key == nil then key = M.key_from_name(key) end
    mods = mods or M.no_modifiers()

    if key == Interact.KeyTab then
        if mods.shift then return Interact.FocusPrev end
        return Interact.FocusNext
    end
    if key == Interact.KeyReturn or key == Interact.KeySpace then
        return Interact.ActivateFocus
    end
    if key == Interact.KeyEscape then
        return Interact.CancelPointer
    end
    return nil
end

function M.raw_from_host_event(ev)
    if ev == nil then return nil end
    local t = ev.type

    if t == "mouse_moved" or t == "pointer_moved" then
        return M.raw_pointer_moved(ev.x, ev.y)
    end
    if t == "mouse_pressed" or t == "pointer_pressed" then
        return M.raw_pointer_pressed(ev.button, ev.x, ev.y)
    end
    if t == "mouse_released" or t == "pointer_released" then
        return M.raw_pointer_released(ev.button, ev.x, ev.y)
    end
    if t == "pointer_cancelled" or t == "mouse_cancelled" then
        return M.raw_pointer_cancelled()
    end
    if t == "mouse_wheel" or t == "wheel" or t == "wheel_moved" then
        return M.raw_wheel_moved(ev.dx, ev.dy, ev.x, ev.y)
    end
    if t == "key_down" or t == "key_pressed" then
        return M.raw_key_down(ev.key, M.modifiers(ev), ev.repeat_)
    end
    if t == "key_up" or t == "key_released" then
        return M.raw_key_up(ev.key, M.modifiers(ev))
    end
    if t == "text_input" then
        return M.raw_text_input(ev.text)
    end
    if t == "text_editing" then
        return M.raw_text_editing(ev.text, ev.start, ev.length)
    end
    if t == "focus_lost" then
        return M.raw_focus_lost()
    end

    return nil
end

function M.raw_many_from_host_event(ev, opts)
    opts = opts or {}
    local raw = M.raw_from_host_event(ev)
    if raw == nil then return {} end

    local out = { raw }
    if (ev.type == "key_down" or ev.type == "key_pressed") and opts.include_focus_intents ~= false then
        local intent = M.focus_intent_for_key(ev.key, M.modifiers(ev))
        if intent ~= nil then out[#out + 1] = intent end
    end
    return out
end

return M
