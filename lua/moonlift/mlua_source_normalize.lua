local M = {}

local function starts_ident_char(c)
    return c and c:match("[%w_]") ~= nil
end

local function is_boundary(src, i, n)
    local before = i > 1 and src:sub(i - 1, i - 1) or ""
    local after = src:sub(i + n, i + n)
    return not starts_ident_char(before) and not starts_ident_char(after)
end

local function skip_string(src, i, quote)
    i = i + 1
    while i <= #src do
        local c = src:sub(i, i)
        if c == "\\" then i = i + 2
        elseif c == quote then return i + 1
        else i = i + 1 end
    end
    return i
end

local function skip_long_bracket(src, i)
    local eq = src:match("^%[(=*)%[", i)
    if not eq then return nil end
    local close = "]" .. eq .. "]"
    local j = src:find(close, i + 2 + #eq, true)
    return j and (j + #close) or (#src + 1)
end

local function skip_comment_or_string(src, i)
    local c = src:sub(i, i)
    local n = src:sub(i, i + 1)
    if n == "--" then
        local lb = skip_long_bracket(src, i + 2)
        if lb then return lb end
        local j = src:find("\n", i + 2, true)
        return j or (#src + 1)
    end
    if c == '"' or c == "'" then return skip_string(src, i, c) end
    if c == "[" then return skip_long_bracket(src, i) end
    return nil
end

local function read_ident(src, i)
    if not src:sub(i, i):match("[A-Za-z_]") then return nil, i end
    local s = i
    i = i + 1
    while i <= #src and src:sub(i, i):match("[%w_]") do i = i + 1 end
    return src:sub(s, i - 1), i
end

local function find_matching_end(src, start_i)
    local open = { ["if"] = true, switch = true, block = true, control = true }
    local depth, i = 1, start_i
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        elseif src:sub(i, i):match("[A-Za-z_]") then
            local word, j = read_ident(src, i)
            if is_boundary(src, i, #word) then
                if word == "end" then
                    depth = depth - 1
                    if depth == 0 then return i, j - 1 end
                elseif open[word] then
                    depth = depth + 1
                elseif word == "loop" then
                    local next_word = read_ident(src, skip_space(src, j))
                    if next_word == "counted" then depth = depth + 1 end
                end
            end
            i = j
        else
            i = i + 1
        end
    end
    return nil
end

local function strip(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_lines(s)
    local out = {}
    s = s:gsub("\r\n", "\n")
    for line in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
    return out
end

local function parse_counted_header(header)
    local lines = split_lines(header)
    local first = strip(lines[1] or "")
    local var, var_ty, init, cond = first:match("^([_%a][_%w]*)%s*:%s*([^=]+)%s*=%s*(.-)%s+until%s+(.+)$")
    if not var then return nil end
    local states = {}
    local yield_expr
    for i = 2, #lines do
        local line = strip(lines[i])
        if line ~= "" then
            local name, ty, value = line:match("^state%s+([_%a][_%w]*)%s*:%s*([^=]+)%s*=%s*(.+)$")
            if name then
                states[#states + 1] = { name = name, ty = strip(ty), init = strip(value) }
            else
                local y = line:match("^yield%s+(.+)$")
                if y then yield_expr = strip(y) end
            end
        end
    end
    local result_ty = states[1] and states[1].ty or "void"
    return {
        var = var,
        var_ty = strip(var_ty),
        init = strip(init),
        cond = strip(cond),
        states = states,
        yield_expr = yield_expr or (states[1] and states[1].name) or "",
        result_ty = result_ty,
    }
end

local function parse_counted_body(body)
    local kept = {}
    local next_values = {}
    for _, line in ipairs(split_lines(body)) do
        local name, value = line:match("^%s*next%s+([_%a][_%w]*)%s*=%s*(.-)%s*$")
        if name then
            next_values[name] = value
        elseif line:match("^%s*state%s+[_%a][_%w]*%s*:") or line:match("^%s*yield%s+") then
            -- Header lines of the counted-loop sugar, not body statements.
        elseif strip(line) ~= "" then
            kept[#kept + 1] = line
        end
    end
    return kept, next_values
end

local function counted_rewrite(info, form)
    local lines = split_lines(form)
    local body_lines = {}
    for i = 2, #lines do body_lines[#body_lines + 1] = lines[i] end
    local kept, next_values = parse_counted_body(table.concat(body_lines, "\n"))
    local params = { info.var .. ": " .. info.var_ty .. " = " .. info.init }
    for i = 1, #info.states do
        local s = info.states[i]
        params[#params + 1] = s.name .. ": " .. s.ty .. " = " .. s.init
    end
    local jump_args = { info.var .. " = " .. info.var .. " + 1" }
    for i = 1, #info.states do
        local s = info.states[i]
        jump_args[#jump_args + 1] = s.name .. " = " .. (next_values[s.name] or s.name)
    end
    local out = {
        "block counted_loop(" .. table.concat(params, ", ") .. ") -> " .. info.result_ty,
        "    if " .. info.cond .. " then yield " .. info.yield_expr .. " end",
    }
    for i = 1, #kept do out[#out + 1] = kept[i] end
    out[#out + 1] = "    jump counted_loop(" .. table.concat(jump_args, ", ") .. ")"
    out[#out + 1] = "end"
    return table.concat(out, "\n")
end

local function expand_counted_loops(src)
    local out = {}
    local i = 1
    local literal_start = 1
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        elseif src:sub(i, i + #"loop counted" - 1) == "loop counted" and is_boundary(src, i, #"loop") then
            local after = i + #"loop counted"
            local end_start, end_stop = find_matching_end(src, after)
            if not end_start then
                i = i + 1
            else
                local form = src:sub(after, end_start - 1)
                local info = parse_counted_header(form)
                if not info then
                    i = i + 1
                else
                    out[#out + 1] = src:sub(literal_start, i - 1)
                    out[#out + 1] = counted_rewrite(info, form)
                    i = end_stop + 1
                    literal_start = i
                end
            end
        else
            i = i + 1
        end
    end
    if literal_start <= #src then out[#out + 1] = src:sub(literal_start) end
    return table.concat(out)
end

function M.expand_counted_loops(src)
    return expand_counted_loops(src)
end

function M.moonlift_body(src)
    return expand_counted_loops(src)
end

return M
