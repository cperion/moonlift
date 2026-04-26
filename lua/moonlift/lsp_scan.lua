local pvm = require("moonlift.pvm")

local M = {}

local function starts_ident_char(c) return c and c:match("[%w_]") ~= nil end
local function is_boundary(src, i, n)
    local before = i > 1 and src:sub(i - 1, i - 1) or ""
    local after = src:sub(i + n, i + n)
    return not starts_ident_char(before) and not starts_ident_char(after)
end
local function has_word(src, i, word) return src:sub(i, i + #word - 1) == word and is_boundary(src, i, #word) end
local function skip_space(src, i)
    while i <= #src do
        local c = src:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" and c ~= "\n" then break end
        i = i + 1
    end
    return i
end
local function read_ident(src, i)
    if not src:sub(i, i):match("[A-Za-z_]") then return nil, i end
    local s = i; i = i + 1
    while i <= #src and src:sub(i, i):match("[%w_]") do i = i + 1 end
    return src:sub(s, i - 1), i
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
local function find_matching_brace(src, open_i)
    if not open_i then return nil end
    local depth, i = 0, open_i
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then i = skipped else
            local c = src:sub(i, i)
            if c == "{" then depth = depth + 1; i = i + 1
            elseif c == "}" then depth = depth - 1; if depth == 0 then return i end; i = i + 1
            else i = i + 1 end
        end
    end
    return nil
end
local function find_first_brace(src, start_i)
    local i = start_i
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then i = skipped
        elseif src:sub(i, i) == "{" and src:sub(i - 1, i - 1) ~= "@" then return i
        else i = i + 1 end
    end
    return nil
end
local open_words = { func = true, module = true, region = true, expr = true, ["if"] = true, switch = true, block = true, entry = true, control = true, ["do"] = true, ["function"] = true, ["repeat"] = true }
local function find_matching_end(src, start_i)
    local depth, i = 0, start_i
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then i = skipped
        elseif src:sub(i, i):match("[A-Za-z_]") then
            local word, j = read_ident(src, i)
            if is_boundary(src, i, #word) then
                if word == "end" then depth = depth - 1; if depth == 0 then return j - 1 end
                elseif open_words[word] then depth = depth + 1 end
            end
            i = j
        else i = i + 1 end
    end
    return nil
end
local function same_line_before(src, a, b)
    local nl = src:find("\n", a, true)
    return not nl or b < nl
end

local function is_island_start(src, i, kind)
    if not has_word(src, i, kind) then return false end
    local j = skip_space(src, i + #kind)
    if kind == "struct" or kind == "func" or kind == "region" or kind == "expr" then return read_ident(src, j) ~= nil end
    if kind == "expose" then return src:find("%f[%w_]as%f[^%w_]", j) ~= nil end
    if kind == "module" then
        local word, after_word = read_ident(src, j)
        local ch = src:sub(j, j)
        if ch == "{" then return true end
        if word and src:sub(skip_space(src, after_word), skip_space(src, after_word)) == "{" then return true end
        return word == "export" or word == "extern" or word == "func" or word == "const" or word == "static" or word == "import" or word == "type" or word == "region" or word == "expr" or word == "end"
    end
    return false
end
local island_order = { "struct", "expose", "func", "module", "region", "expr" }
local function find_next_island(src, i)
    while i <= #src do
        local skipped = skip_comment_or_string(src, i)
        if skipped then i = skipped else
            for k = 1, #island_order do if is_island_start(src, i, island_order[k]) then return i, island_order[k] end end
            i = i + 1
        end
    end
    return nil, nil
end
local function island_end(src, start_i, kind)
    local brace = find_first_brace(src, start_i)
    if kind == "struct" or kind == "expose" then return find_matching_brace(src, brace) end
    if (kind == "func" or kind == "module") and brace and same_line_before(src, start_i, brace) then return find_matching_brace(src, brace) end
    return find_matching_end(src, start_i)
end

local function line_starts(text)
    local starts = { 1 }
    local i = 1
    while true do
        local nl = text:find("\n", i, true)
        if not nl then break end
        starts[#starts + 1] = nl + 1
        i = nl + 1
    end
    return starts
end
local function pos_for_offset(TL, starts, offset)
    if offset < 1 then offset = 1 end
    local line = 1
    for i = 1, #starts do if starts[i] <= offset then line = i else break end end
    return TL.Position(line - 1, offset - starts[line])
end
local function range_for_offsets(TL, starts, s, e)
    return TL.Range(pos_for_offset(TL, starts, s), pos_for_offset(TL, starts, e))
end

local function island_name(kind, source)
    if kind == "struct" then return source:match("^%s*struct%s+([_%a][_%w]*)") or "<struct>" end
    if kind == "expose" then return source:match("%f[%w_]as%f[^%w_]%s+([_%a][_%w]*)") or "<expose>" end
    if kind == "func" then
        local owner, method = source:match("^%s*func%s+([_%a][_%w]*)%s*:%s*([_%a][_%w]*)")
        if owner then return owner .. ":" .. method end
        return source:match("^%s*export%s+func%s+([_%a][_%w]*)") or source:match("^%s*func%s+([_%a][_%w]*)") or "<func>"
    end
    if kind == "module" then return source:match("^%s*module%s+([_%a][_%w]*)%s*{") or "<module>" end
    if kind == "region" then return source:match("^%s*region%s+([_%a][_%w]*)") or "<region>" end
    if kind == "expr" then return source:match("^%s*expr%s+([_%a][_%w]*)") or "<expr>" end
    return "<island>"
end

function M.Define(T)
    require("moonlift.lsp_asdl").Define(T)
    local L = T.MoonliftLsp
    local kind_asdl = { struct = L.IslandStruct, expose = L.IslandExpose, func = L.IslandFunc, module = L.IslandModule, region = L.IslandRegion, expr = L.IslandExpr }

    local function scan(doc)
        local src, starts, out = doc.text, line_starts(doc.text), {}
        local i = 1
        while i <= #src do
            local s, kind = find_next_island(src, i)
            if not s then break end
            local e = island_end(src, s, kind)
            if not e then break end
            local source = src:sub(s, e)
            local name = island_name(kind, source)
            local ns = source:find(name, 1, true) or 1
            local range = range_for_offsets(L, starts, s, e + 1)
            local sel = range_for_offsets(L, starts, s + ns - 1, s + ns - 1 + #name)
            out[#out + 1] = L.Island(kind_asdl[kind], name, range, sel, s, e, source)
            i = e + 1
        end
        return out
    end

    local phase = pvm.phase("moonlift_lsp_scan_islands", {
        [L.Document] = function(self) return pvm.T.seq(scan(self)) end,
    })

    return { phase = phase, scan = function(doc) return pvm.drain(phase(doc)) end, _helpers = { line_starts = line_starts, range_for_offsets = range_for_offsets, pos_for_offset = pos_for_offset } }
end

return M
