local pvm = require("pvm")
local ui_asdl = require("ui.asdl")

local T = ui_asdl.T
local Core = T.Core
local Auth = T.Auth
local Layout = T.Layout
local Compose = T.Compose

local M = {}

local function classof(v)
    if v == nil then return nil end
    return pvm.classof(v)
end

function M.is_no_id(id)
    return id == nil or id == Core.NoId
end

function M.key(id)
    if M.is_no_id(id) then return nil end
    if type(id) == "string" then return id end
    return id.value
end

function M.id(value)
    if value == nil or value == "" then return Core.NoId end
    if type(value) ~= "string" then value = tostring(value) end
    return Core.IdValue(value)
end

function M.child(parent, suffix)
    local base = M.key(parent)
    if base == nil or base == "" then
        error("ui.id.child requires a non-empty parent id", 2)
    end
    if suffix == nil or suffix == "" then
        error("ui.id.child requires a non-empty suffix", 2)
    end
    return Core.IdValue(base .. ":" .. tostring(suffix))
end

local function path_child(path, field, index)
    if index ~= nil then
        return path .. "." .. field .. "[" .. tostring(index) .. "]"
    end
    return path .. "." .. field
end

local function add_entry(out, id, kind, path, role)
    local key = M.key(id)
    if key == nil then return end
    out[#out + 1] = {
        id = id,
        key = key,
        kind = kind,
        role = role or "define",
        path = path,
    }
end

local function collect_auth_node(node, out, path, opts)
    local cls = classof(node)
    if cls == nil then return end

    if cls == Auth.Box then
        add_entry(out, node.id, "Auth.Box", path)
        for i = 1, #node.children do
            collect_auth_node(node.children[i], out, path_child(path, "children", i), opts)
        end
    elseif cls == Auth.Text then
        add_entry(out, node.id, "Auth.Text", path)
    elseif cls == Auth.TextRef then
        add_entry(out, node.id, "Auth.TextRef", path)
        if opts == nil or opts.content_refs ~= false then
            add_entry(out, node.content_id, "Auth.TextRef.content_id", path .. ".content_id", "content_ref")
        end
    elseif cls == Auth.Paint then
        add_entry(out, node.id, "Auth.Paint", path)
    elseif cls == Auth.Scroll then
        add_entry(out, node.id, "Auth.Scroll", path)
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Auth.WithState then
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Auth.WithInput then
        add_entry(out, node.id, "Auth.WithInput", path, "input")
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Auth.WithDragSource then
        add_entry(out, node.id, "Auth.WithDragSource", path, "drag_source")
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Auth.WithDropTarget then
        add_entry(out, node.id, "Auth.WithDropTarget", path, "drop_target")
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Auth.WithDropSlot then
        add_entry(out, node.id, "Auth.WithDropSlot", path, "drop_slot")
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Auth.FocusScope then
        add_entry(out, node.id, "Auth.FocusScope", path, "focus_scope")
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Auth.Layer then
        add_entry(out, node.id, "Auth.Layer", path, "layer")
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Auth.Overlay then
        add_entry(out, node.id, "Auth.Overlay", path, "overlay")
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Auth.Modal then
        add_entry(out, node.id, "Auth.Modal", path, "modal")
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Auth.Fragment then
        for i = 1, #node.children do
            collect_auth_node(node.children[i], out, path_child(path, "children", i), opts)
        end
    elseif cls == Auth.Empty or node == Auth.Empty or cls == classof(Auth.Empty) then
        return
    else
        error("ui.id.collect_auth: unknown Auth node at " .. path, 2)
    end
end

function M.collect_auth(node, opts)
    local out = {}
    collect_auth_node(node, out, opts and opts.path or "root", opts)
    return out
end

local function collect_layout_node(node, out, path, opts)
    local cls = classof(node)
    if cls == nil then return end

    if cls == Layout.Flow or cls == Layout.Flex then
        add_entry(out, node.id, cls == Layout.Flow and "Layout.Flow" or "Layout.Flex", path)
        for i = 1, #node.children do
            collect_layout_node(node.children[i], out, path_child(path, "children", i), opts)
        end
    elseif cls == Layout.Grid then
        add_entry(out, node.id, "Layout.Grid", path)
        for i = 1, #node.items do
            collect_layout_node(node.items[i].node, out, path_child(path, "items", i) .. ".node", opts)
        end
    elseif cls == Layout.Leaf then
        add_entry(out, node.id, "Layout.Leaf", path)
        if node.text ~= nil and (opts == nil or opts.content_refs ~= false) then
            local text_cls = classof(node.text)
            if text_cls == Layout.TextBinding then
                add_entry(out, node.text.content_id, "Layout.TextBinding.content_id", path .. ".text.content_id", "content_ref")
            end
        end
    elseif cls == Layout.Paint then
        add_entry(out, node.id, "Layout.Paint", path)
    elseif cls == Layout.Scroll then
        add_entry(out, node.id, "Layout.Scroll", path)
        collect_layout_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Layout.WithInput then
        add_entry(out, node.id, "Layout.WithInput", path, "input")
        collect_layout_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Layout.WithDragSource then
        add_entry(out, node.id, "Layout.WithDragSource", path, "drag_source")
        collect_layout_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Layout.WithDropTarget then
        add_entry(out, node.id, "Layout.WithDropTarget", path, "drop_target")
        collect_layout_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Layout.WithDropSlot then
        add_entry(out, node.id, "Layout.WithDropSlot", path, "drop_slot")
        collect_layout_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Layout.FocusScope then
        add_entry(out, node.id, "Layout.FocusScope", path, "focus_scope")
        collect_layout_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Layout.Layer then
        add_entry(out, node.id, "Layout.Layer", path, "layer")
        collect_layout_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Layout.Overlay then
        add_entry(out, node.id, "Layout.Overlay", path, "overlay")
        collect_layout_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Layout.Modal then
        add_entry(out, node.id, "Layout.Modal", path, "modal")
        collect_layout_node(node.child, out, path_child(path, "child"), opts)
    else
        error("ui.id.collect_layout: unknown Layout node at " .. path, 2)
    end
end

function M.collect_layout(node, opts)
    local out = {}
    collect_layout_node(node, out, opts and opts.path or "root", opts)
    return out
end

local function collect_compose_node(node, out, path, opts)
    local cls = classof(node)
    if cls == nil then return end

    if cls == Compose.Raw then
        collect_auth_node(node.child, out, path_child(path, "child"), opts)
    elseif cls == Compose.Fragment then
        for i = 1, #node.children do
            collect_compose_node(node.children[i], out, path_child(path, "children", i), opts)
        end
    elseif cls == Compose.Panel then
        add_entry(out, node.id, "Compose.Panel", path)
        if node.header ~= nil then collect_compose_node(node.header, out, path_child(path, "header"), opts) end
        if node.body ~= nil then collect_compose_node(node.body, out, path_child(path, "body"), opts) end
        if node.footer ~= nil then collect_compose_node(node.footer, out, path_child(path, "footer"), opts) end
    elseif cls == Compose.ScrollPanel then
        add_entry(out, node.id, "Compose.ScrollPanel", path)
        add_entry(out, node.scroll_id, "Compose.ScrollPanel.scroll_id", path .. ".scroll_id", "scroll")
        if node.header ~= nil then collect_compose_node(node.header, out, path_child(path, "header"), opts) end
        if node.body ~= nil then collect_compose_node(node.body, out, path_child(path, "body"), opts) end
        if node.footer ~= nil then collect_compose_node(node.footer, out, path_child(path, "footer"), opts) end
    elseif cls == Compose.HSplit or cls == Compose.VSplit then
        add_entry(out, node.id, cls == Compose.HSplit and "Compose.HSplit" or "Compose.VSplit", path)
        for i = 1, #node.children do
            collect_compose_node(node.children[i], out, path_child(path, "children", i), opts)
        end
    elseif cls == Compose.Workbench then
        add_entry(out, node.id, "Compose.Workbench", path)
        if node.top ~= nil then collect_compose_node(node.top, out, path_child(path, "top"), opts) end
        if node.left ~= nil then collect_compose_node(node.left, out, path_child(path, "left"), opts) end
        if node.center ~= nil then collect_compose_node(node.center, out, path_child(path, "center"), opts) end
        if node.right ~= nil then collect_compose_node(node.right, out, path_child(path, "right"), opts) end
        if node.bottom ~= nil then collect_compose_node(node.bottom, out, path_child(path, "bottom"), opts) end
    else
        error("ui.id.collect_compose: unknown Compose node at " .. path, 2)
    end
end

function M.collect_compose(node, opts)
    local out = {}
    collect_compose_node(node, out, opts and opts.path or "root", opts)
    return out
end

function M.collect_surfaces(surfaces, opts)
    local out = {}
    local path = opts and opts.path or "surfaces"
    if surfaces == nil then return out end
    for name, id in pairs(surfaces) do
        add_entry(out, id, "surface." .. tostring(name), path .. "." .. tostring(name), "surface")
    end
    return out
end

local function duplicate_errors(entries)
    local first = {}
    local errors = {}
    for i = 1, #entries do
        local e = entries[i]
        local prev = first[e.key]
        if prev == nil then
            first[e.key] = e
        else
            errors[#errors + 1] = string.format(
                "%s(id=%q) duplicates %s(id=%q): %s duplicates %s",
                e.kind,
                e.key,
                prev.kind,
                prev.key,
                e.path,
                prev.path
            )
        end
    end
    return errors
end

function M.validate_entries(entries)
    local errors = duplicate_errors(entries or {})
    return #errors == 0, errors, entries or {}
end

function M.validate_auth(node, opts)
    local entries = M.collect_auth(node, opts)
    return M.validate_entries(entries)
end

function M.validate_layout(node, opts)
    local entries = M.collect_layout(node, opts)
    return M.validate_entries(entries)
end

function M.validate_compose(node, opts)
    local entries = M.collect_compose(node, opts)
    return M.validate_entries(entries)
end

function M.validate_surfaces(surfaces, opts)
    local entries = M.collect_surfaces(surfaces, opts)
    return M.validate_entries(entries)
end

local function assert_ok(ok, errors, level)
    if ok then return true end
    error("ui.id validation failed:\n- " .. table.concat(errors, "\n- "), (level or 1) + 1)
end

function M.assert_entries(entries)
    local ok, errors = M.validate_entries(entries)
    return assert_ok(ok, errors, 2)
end

function M.assert_auth(node, opts)
    local ok, errors = M.validate_auth(node, opts)
    return assert_ok(ok, errors, 2)
end

function M.assert_layout(node, opts)
    local ok, errors = M.validate_layout(node, opts)
    return assert_ok(ok, errors, 2)
end

function M.assert_compose(node, opts)
    local ok, errors = M.validate_compose(node, opts)
    return assert_ok(ok, errors, 2)
end

function M.assert_surfaces(surfaces, opts)
    local ok, errors = M.validate_surfaces(surfaces, opts)
    return assert_ok(ok, errors, 2)
end

return M
