-- lalin/dap_variables.lua
-- Format Lalin variables for DAP display.
-- Maps register values to typed, named variables using binding facts.

local M = {}

--- Format variables from the interpreter for DAP.
-- @param vars  table {name → raw_value} from debugger get_variables()
-- @param bindings  table (optional) — not yet used; future: BindingFact[]
-- @return DAP variables array: [{name, value, type, variablesReference}]
function M.format_variables(vars, bindings)
    local result = {}
    for name, raw_value in pairs(vars) do
        -- Skip internal/synthetic register names
        if not name:match("^v%d+$") and not name:match("^addr") then
            local ty = M._infer_type(name, raw_value, bindings)
            result[#result + 1] = {
                name = name,
                value = M._format_value(raw_value, ty),
                type = ty,
                variablesReference = 0,
            }
        end
    end
    -- Sort by name for consistent display
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

--- Infer type of a variable from binding facts or value.
-- @param name  string — variable name
-- @param value  raw value
-- @param bindings  table or nil
-- @return type string like "i32", "bool", "f64", "i64"
function M._infer_type(name, value, bindings)
    -- Try to resolve from binding facts (future enhancement)
    -- Currently just infers from Lua type

    if type(value) == "boolean" then
        return "bool"
    end
    if type(value) == "number" then
        -- Check if it looks like a float (has fractional part)
        if value ~= math.floor(value) then
            return "f64"
        end
        -- Check if it fits in i32
        if value >= -2147483648 and value <= 2147483647 then
            return "i32"
        end
        return "i64"
    end
    if type(value) == "string" then
        -- Could be a pointer address
        if value:match("^%d+$") then
            return "ptr"
        end
        return "string"
    end
    return "unknown"
end

--- Format a raw value for display.
-- @param raw  raw Lua value
-- @param ty  type string
-- @return formatted string
function M._format_value(raw, ty)
    if type(raw) == "boolean" then
        return raw and "true" or "false"
    end
    if type(raw) == "number" then
        if ty == "f32" or ty == "f64" then
            return string.format("%.6g", raw)
        end
        if raw == math.floor(raw) then
            return tostring(math.floor(raw))
        end
        return string.format("%g", raw)
    end
    if type(raw) == "string" then
        -- Check if it's a numeric address
        local num = tonumber(raw)
        if num then
            return "0x" .. string.format("%x", num)
        end
        return '"' .. raw .. '"'
    end
    return tostring(raw)
end

return M
