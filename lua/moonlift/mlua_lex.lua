-- Shared lexer/scanner primitives for the .mlua meta layer.
-- Every other mlua_* module imports from here.

local M = {}

-- Character/token utilities

local function starts_ident_char(c)
    return c and c:match("[%w_]") ~= nil
end
M.starts_ident_char = starts_ident_char

local function is_boundary(src, i, n)
    local before = i > 1 and src:sub(i - 1, i - 1) or ""
    local after = src:sub(i + n, i + n)
    return not starts_ident_char(before) and not starts_ident_char(after)
end
M.is_boundary = is_boundary

local function has_word(src, i, word)
    return src:sub(i, i + #word - 1) == word and is_boundary(src, i, #word)
end
M.has_word = has_word

local function skip_space(src, i)
    while i <= #src do
        local c = src:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" and c ~= "\n" then break end
        i = i + 1
    end
    return i
end
M.skip_space = skip_space

local function skip_hspace(src, i)
    while i <= #src do
        local c = src:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" then break end
        i = i + 1
    end
    return i
end
M.skip_hspace = skip_hspace

local function read_ident(src, i)
    if not src:sub(i, i):match("[A-Za-z_]") then return nil, i end
    local s = i
    i = i + 1
    while i <= #src and src:sub(i, i):match("[%w_]") do i = i + 1 end
    return src:sub(s, i - 1), i
end
M.read_ident = read_ident

local function word_at_boundary(src, s, e)
    local before = s > 1 and src:sub(s - 1, s - 1) or ""
    local after = src:sub(e + 1, e + 1)
    return not starts_ident_char(before) and not starts_ident_char(after)
end
M.word_at_boundary = word_at_boundary

local function find_word(src, word, init)
    init = init or 1
    local i = init
    while true do
        local s, e = src:find(word, i, true)
        if not s then return nil end
        if word_at_boundary(src, s, e) then return s, e end
        i = e + 1
    end
end
M.find_word = find_word

-- String/comment skipping

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
M.skip_string = skip_string

local function skip_long_bracket(src, i)
    local eq = src:match("^%[(=*)%[", i)
    if not eq then return nil end
    local close = "]" .. eq .. "]"
    local j = src:find(close, i + 2 + #eq, true)
    return j and (j + #close) or (#src + 1)
end
M.skip_long_bracket = skip_long_bracket

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
M.skip_comment_or_string = skip_comment_or_string

-- Matching/depth tracking

local function line_prefix_has_word(src, i, word)
    local line_start = src:sub(1, i - 1):match(".*\n()") or 1
    local prefix = src:sub(line_start, i - 1)
    return prefix:match("%f[%w_]" .. word .. "%f[^%w_]") ~= nil
end
M.line_prefix_has_word = line_prefix_has_word

-- Pre-built open_words sets

-- For finding island boundaries in .mlua text
local open_words_island = {
    struct = true, expose = true, func = true, module = true, region = true, expr = true,
    ["if"] = true, switch = true, block = true, entry = true, control = true, ["type"] = true,
}
M.open_words_island = open_words_island

-- For scanning inside Moonlift bodies (source normalize)
local open_words_body = { ["if"] = true, switch = true, block = true, control = true }
M.open_words_body = open_words_body

-- For finding form extent within parsed islands (no switch)
local open_words_form = {
    struct = true, expose = true, func = true, region = true, expr = true, module = true,
    block = true, entry = true, control = true, ["if"] = true, ["type"] = true, ["switch"] = true,
}
M.open_words_form = open_words_form

local function find_matching_end(src, start_i, open_words)
    local depth, i = 0, start_i
    local keyword_stack = {}  -- stack of opener keywords (not case/default)
    local pending_case_ends = 0  -- case/default bodies inside switch not yet closed
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        elseif src:sub(i, i):match("[A-Za-z_]") then
            local word, j = read_ident(src, i)
            if is_boundary(src, i, #word) then
                if word == "end" then
                    if pending_case_ends > 0 then
                        -- An end that shares a line with case/default is an explicit
                        -- case-body terminator; otherwise it is the switch's own end
                        -- (which also closes the last pending case body).
                        if line_prefix_has_word(src, i, "case") or line_prefix_has_word(src, i, "default") then
                            pending_case_ends = pending_case_ends - 1
                        else
                            pending_case_ends = 0
                            if keyword_stack[#keyword_stack] == "switch" then
                                table.remove(keyword_stack)
                                depth = depth - 1
                            end
                        end
                    else
                        table.remove(keyword_stack)
                        depth = depth - 1
                        if depth == 0 then return j - 1 end
                    end
                elseif word == "case" or word == "default" then
                    if pending_case_ends > 0 then
                        -- previous case/default body implicitly closed
                        pending_case_ends = pending_case_ends - 1
                    end
                    pending_case_ends = pending_case_ends + 1
                elseif open_words[word] then
                    if word == "block" and keyword_stack[#keyword_stack] == "entry" then
                        table.remove(keyword_stack)
                        depth = depth - 1
                    end
                    table.insert(keyword_stack, word)
                    depth = depth + 1
                elseif word == "do" then
                    if not line_prefix_has_word(src, i, "switch") then
                        depth = depth + 1
                    end
                elseif word == "loop" then
                    local next_word = read_ident(src, skip_space(src, j))
                    if next_word == "counted" then
                        depth = depth + 1
                    end
                end
            end
            i = j
        else
            i = i + 1
        end
    end
    return nil, "unterminated hosted Moonlift island"
end
M.find_matching_end = find_matching_end

local function find_matching_brace(src, open_i)
    local depth = 1
    local i = open_i + 1
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        else
            local c = src:sub(i, i)
            if c == "{" then depth = depth + 1; i = i + 1
            elseif c == "}" then
                depth = depth - 1
                if depth == 0 then return i end
                i = i + 1
            else
                i = i + 1
            end
        end
    end
    return nil, "unterminated Moonlift brace island"
end
M.find_matching_brace = find_matching_brace

-- find_matching for balanced character pairs (parens, etc.)
local function find_matching(src, open_i, open_ch, close_ch)
    local depth = 0
    local i = open_i
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        else
            local c = src:sub(i, i)
            if c == open_ch then depth = depth + 1; i = i + 1
            elseif c == close_ch then
                depth = depth - 1
                if depth == 0 then return i end
                i = i + 1
            else
                i = i + 1
            end
        end
    end
    return nil
end
M.find_matching = find_matching

-- Island detection

local function is_module_start(src, i)
    local item_words = { export = true, extern = true, func = true, const = true, static = true, import = true, type = true, region = true, expr = true, ["end"] = true }
    local p = i - 1
    while p >= 1 do
        local c = src:sub(p, p)
        if c ~= " " and c ~= "\t" and c ~= "\r" then break end
        p = p - 1
    end
    local prev = p >= 1 and src:sub(p, p) or "\n"
    local word_end = p
    while p >= 1 and src:sub(p, p):match("[%w_]") do p = p - 1 end
    local prev_word = word_end >= p + 1 and src:sub(p + 1, word_end) or ""
    local from_return = prev_word == "return"
    local prefix_ok = prev == "\n" or prev == "="
    if not prefix_ok and not from_return then return false end
    local k = skip_hspace(src, i + #"module")
    local ch = src:sub(k, k)
    if ch == "" then return prefix_ok end
    if ch == "\n" then
        if not from_return then return true end
        local next_word = read_ident(src, skip_space(src, k + 1))
        return item_words[next_word] == true
    end
    local word, after_word = read_ident(src, k)
    if not word then return false end
    if item_words[word] then return true end
    local next_i = skip_hspace(src, after_word)
    local next_ch = src:sub(next_i, next_i)
    if from_return then return next_ch == "\n" or next_ch == "{" end
    return next_ch == "" or next_ch == "\n" or next_ch == "{"
end
M.is_module_start = is_module_start

local island_order = { "struct", "expose", "func", "module", "region", "expr" }

local function is_island_start(src, i, kind)
    if not has_word(src, i, kind) then return false end
    local j = skip_space(src, i + #kind)
    if kind == "struct" or kind == "func" or kind == "region" or kind == "expr" then
        return read_ident(src, j) ~= nil
    end
    if kind == "expose" then
        return read_ident(src, j) ~= nil
    end
    if kind == "module" then
        return is_module_start(src, i)
    end
    return false
end
M.is_island_start = is_island_start

local function island_end(src, start_i, kind)
    if kind == "expose" then
        local nl = src:find("\n", start_i, true)
        if not nl then return #src end
        local next_word = read_ident(src, skip_space(src, nl + 1))
        if next_word == "end" or next_word == "lua" or next_word == "terra" or next_word == "c" or next_word == "moonlift" then
            return find_matching_end(src, start_i, open_words_island)
        end
        return nl - 1
    end
    if kind == "module" then
        local _, after_module = read_ident(src, start_i)
        local k = skip_hspace(src, after_module)
        local word, after_word = read_ident(src, k)
        if word ~= nil then k = skip_hspace(src, after_word) end
        if src:sub(k, k) == "{" then return find_matching_brace(src, k) end
    end
    return find_matching_end(src, start_i, open_words_island)
end
M.island_end = island_end

local function find_next_island(src, i)
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then
            i = skipped
        else
            if has_word(src, i, "export") then
                local func_i = skip_space(src, i + #"export")
                if is_island_start(src, func_i, "func") then return i, "func", func_i end
            end
            for k = 1, #island_order do
                local kind = island_order[k]
                if is_island_start(src, i, kind) then return i, kind, i end
            end
            i = i + 1
        end
    end
    return nil, nil, nil
end
M.find_next_island = find_next_island

local function target_for_word(word)
    if word == "lua" then return true end
    if word == "terra" then return true end
    if word == "c" then return true end
    if word == "moonlift" then return true end
    return false
end

local function form_extent(src, i, word)
    if word == "struct" then return find_matching_end(src, i, open_words_form) end
    if word == "expose" then
        local nl = src:find("\n", i, true)
        if not nl then return #src end
        local next_word = read_ident(src, skip_space(src, nl + 1))
        if next_word == "end" or target_for_word(next_word) then return find_matching_end(src, i, open_words_form) end
        return nl - 1
    end
    if word == "module" then
        local _, after_module = read_ident(src, i)
        local k = skip_hspace(src, after_module)
        local maybe_name, after_name = read_ident(src, k)
        if maybe_name then k = skip_hspace(src, after_name) end
        if src:sub(k, k) == "{" then return find_matching_brace(src, k) end
    end
    return find_matching_end(src, i, open_words_form)
end
M.form_extent = form_extent

-- Source normalization (absorbed from mlua_source_normalize)

local function strip(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
M.strip = strip

local function split_lines(s)
    local out = {}
    s = s:gsub("\r\n", "\n")
    for line in (s .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
    return out
end

local function find_matching_end_body(src, start_i)
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
                elseif open_words_body[word] then
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
            local end_start, end_stop = find_matching_end_body(src, after)
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
M.expand_counted_loops = expand_counted_loops

local function moonlift_body(src)
    return expand_counted_loops(src)
end
M.moonlift_body = moonlift_body

-- Text utilities

local function split_top_commas(s)
    local out = {}
    local start, i, depth = 1, 1, 0
    while i <= #s do
        local skipped = skip_comment_or_string(s, i)
        if skipped then
            i = skipped
        else
            local c = s:sub(i, i)
            if c == "(" or c == "[" or c == "{" then depth = depth + 1
            elseif c == ")" or c == "]" or c == "}" then depth = depth - 1
            elseif c == "," and depth == 0 then
                out[#out + 1] = s:sub(start, i - 1)
                start = i + 1
            end
            i = i + 1
        end
    end
    if start <= #s then out[#out + 1] = s:sub(start) end
    return out
end
M.split_top_commas = split_top_commas

local function strip_outer_parens(s)
    s = strip(s)
    if s:sub(1, 1) == "(" then
        local e = find_matching(s, 1, "(", ")")
        if e == #s then return strip(s:sub(2, -2)) end
    end
    return s
end
M.strip_outer_parens = strip_outer_parens

local function line_col(src, offset)
    local line, col = 1, 1
    for i = 1, math.max(1, offset) - 1 do
        if src:sub(i, i) == "\n" then line, col = line + 1, 1 else col = col + 1 end
    end
    return line, col
end
M.line_col = line_col

local function lua_string_literal(s)
    return string.format("%q", s)
end
M.lua_string_literal = lua_string_literal

return M
