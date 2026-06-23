-- Source-to-source erasure for simple PVM phase boundaries.
--
-- The first supported shape is intentionally conservative:
--
--   local name = pvm.phase("phase_name", function(args...)
--       return value
--   end, { node_cache = "none", args_cache = "none" })
--
-- It rewrites that boundary into a direct local Lua function and rewrites
-- pvm.one(name(...)) call sites into name(...). Opaque dispatch phases and
-- triplet-producing handlers are reported but left intact.

local M = {}

local PHASE_OUTPUT_HELPERS = [[
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end
]]

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a") or ""
    f:close()
    return s
end

local function write_file(path, text)
    local dir = tostring(path):match("^(.*)/[^/]+$")
    if dir and dir ~= "" then
        local quoted = "'" .. dir:gsub("'", "'\\''") .. "'"
        os.execute("mkdir -p " .. quoted)
    end
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function is_ident_char(ch)
    return ch and ch:match("[_%w]") ~= nil
end

local function long_bracket_eq(src, i)
    local eq = src:match("^%[(=*)%[", i)
    return eq
end

local function skip_long_bracket(src, i)
    local eq = long_bracket_eq(src, i)
    if not eq then return nil end
    local close = "%]" .. eq .. "%]"
    local s, e = src:find(close, i + 2 + #eq)
    return (e and e + 1) or (#src + 1)
end

local function skip_short_string(src, i)
    local quote = src:sub(i, i)
    i = i + 1
    while i <= #src do
        local ch = src:sub(i, i)
        if ch == "\\" then
            i = i + 2
        elseif ch == quote then
            return i + 1
        else
            i = i + 1
        end
    end
    return #src + 1
end

local function skip_comment(src, i)
    if src:sub(i, i + 1) ~= "--" then return nil end
    local long_start = i + 2
    if src:sub(long_start, long_start) == "[" then
        local e = skip_long_bracket(src, long_start)
        if e then return e end
    end
    local nl = src:find("\n", i + 2, true)
    return (nl and nl + 1) or (#src + 1)
end

local function find_code(src, needle, start_i)
    local i = start_i or 1
    while i <= #src do
        local comment_end = skip_comment(src, i)
        if comment_end then
            i = comment_end
        else
            local ch = src:sub(i, i)
            if ch == "'" or ch == '"' then
                i = skip_short_string(src, i)
            elseif ch == "[" and long_bracket_eq(src, i) then
                i = skip_long_bracket(src, i)
            elseif src:sub(i, i + #needle - 1) == needle then
                local before = src:sub(i - 1, i - 1)
                local after = src:sub(i + #needle, i + #needle)
                if not is_ident_char(before) and not is_ident_char(after) then
                    return i
                end
                i = i + 1
            else
                i = i + 1
            end
        end
    end
    return nil
end

local function find_matching(src, open_i, open_ch, close_ch)
    local depth = 1
    local i = open_i + 1
    while i <= #src do
        local comment_end = skip_comment(src, i)
        if comment_end then
            i = comment_end
        else
            local ch = src:sub(i, i)
            if ch == "'" or ch == '"' then
                i = skip_short_string(src, i)
            elseif ch == "[" and long_bracket_eq(src, i) then
                i = skip_long_bracket(src, i)
            elseif ch == open_ch then
                depth = depth + 1
                i = i + 1
            elseif ch == close_ch then
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

local function split_top_level_commas(src)
    local parts = {}
    local start_i = 1
    local paren, brace, bracket = 0, 0, 0
    local i = 1
    while i <= #src do
        local comment_end = skip_comment(src, i)
        if comment_end then
            i = comment_end
        else
            local ch = src:sub(i, i)
            if ch == "'" or ch == '"' then
                i = skip_short_string(src, i)
            elseif ch == "[" and long_bracket_eq(src, i) then
                i = skip_long_bracket(src, i)
            else
                if ch == "(" then paren = paren + 1
                elseif ch == ")" then paren = paren - 1
                elseif ch == "{" then brace = brace + 1
                elseif ch == "}" then brace = brace - 1
                elseif ch == "[" then bracket = bracket + 1
                elseif ch == "]" then bracket = bracket - 1
                elseif ch == "," and paren == 0 and brace == 0 and bracket == 0 then
                    parts[#parts + 1] = src:sub(start_i, i - 1)
                    start_i = i + 1
                end
                i = i + 1
            end
        end
    end
    parts[#parts + 1] = src:sub(start_i)
    return parts
end

local function find_top_level_comma(src, start_i)
    local paren, brace, bracket = 0, 0, 0
    local i = start_i or 1
    while i <= #src do
        local comment_end = skip_comment(src, i)
        if comment_end then
            i = comment_end
        else
            local ch = src:sub(i, i)
            if ch == "'" or ch == '"' then
                i = skip_short_string(src, i)
            elseif ch == "[" and long_bracket_eq(src, i) then
                i = skip_long_bracket(src, i)
            else
                if ch == "(" then paren = paren + 1
                elseif ch == ")" then paren = paren - 1
                elseif ch == "{" then brace = brace + 1
                elseif ch == "}" then brace = brace - 1
                elseif ch == "[" then bracket = bracket + 1
                elseif ch == "]" then bracket = bracket - 1
                elseif ch == "," and paren == 0 and brace == 0 and bracket == 0 then
                    return i
                end
                i = i + 1
            end
        end
    end
    return nil
end

local function next_code_word(src, start_i)
    local i = start_i or 1
    while i <= #src do
        local comment_end = skip_comment(src, i)
        if comment_end then
            i = comment_end
        else
            local ch = src:sub(i, i)
            if ch == "'" or ch == '"' then
                i = skip_short_string(src, i)
            elseif ch == "[" and long_bracket_eq(src, i) then
                i = skip_long_bracket(src, i)
            elseif ch:match("[_%a]") then
                local j = i + 1
                while j <= #src and src:sub(j, j):match("[_%w]") do j = j + 1 end
                return src:sub(i, j - 1), i, j - 1
            else
                i = i + 1
            end
        end
    end
    return nil
end

local function find_function_end(src, function_start)
    local depth = 0
    local i = function_start
    local skip_then = false
    while true do
        local word, s, e = next_code_word(src, i)
        if not word then return nil end
        if word == "elseif" then
            skip_then = true
        elseif word == "then" then
            if skip_then then skip_then = false else depth = depth + 1 end
        elseif word == "function" or word == "do" or word == "repeat" then
            depth = depth + 1
        elseif word == "end" or word == "until" then
            depth = depth - 1
            if depth == 0 then return e end
        end
        i = e + 1
    end
end

local function parse_phase_args(src)
    local first_comma = find_top_level_comma(src, 1)
    if not first_comma then return split_top_level_commas(src) end
    local args = { src:sub(1, first_comma - 1) }
    local second_start = first_comma + 1
    while src:sub(second_start, second_start):match("%s") do second_start = second_start + 1 end
    if src:sub(second_start, second_start + #"function" - 1) == "function"
        and not is_ident_char(src:sub(second_start + #"function", second_start + #"function")) then
        local second_end = find_function_end(src, second_start)
        if not second_end then return split_top_level_commas(src) end
        args[2] = src:sub(second_start, second_end)
        local rest_start = second_end + 1
        while src:sub(rest_start, rest_start):match("%s") do rest_start = rest_start + 1 end
        if src:sub(rest_start, rest_start) == "," then
            args[3] = src:sub(rest_start + 1)
        end
        return args
    end
    if src:sub(second_start, second_start) == "{" then
        local second_end = find_matching(src, second_start, "{", "}")
        if second_end then
            args[2] = src:sub(second_start, second_end)
            local rest_start = second_end + 1
            while src:sub(rest_start, rest_start):match("%s") do rest_start = rest_start + 1 end
            if src:sub(rest_start, rest_start) == "," then
                args[3] = src:sub(rest_start + 1)
            end
            return args
        end
    end
    return split_top_level_commas(src)
end

local function parse_function_expr(src)
    local fn_start, params_open = src:find("^%s*function%s*%(")
    if not fn_start then return nil end
    params_open = src:find("%(", fn_start)
    local params_close = find_matching(src, params_open, "(", ")")
    if not params_close then return nil end
    local params = src:sub(params_open + 1, params_close - 1)
    local body = src:sub(params_close + 1)
    local body_trimmed = body:gsub("%s*end%s*$", "")
    if body_trimmed == body then return nil end
    return params, body_trimmed
end

local function rewrite_direct_body(body)
    body = body:gsub("pvm%.empty%(%s*%)", "{}")
    body = body:gsub("pvm%.once", "single")
    body = body:gsub("pvm%.seq", "as_list")
    body = body:gsub("pvm%.children", "flat_map")
    body = body:gsub("pvm%.concat_all", "concat_all")
    body = body:gsub("pvm%.concat3", "concat3")
    body = body:gsub("pvm%.concat2", "concat2")
    return body
end

local function parse_dispatch_table(src)
    local table_start = src:find("^%s*{")
    if not table_start then return nil end
    local table_end = find_matching(src, table_start, "{", "}")
    if not table_end then return nil end
    local entries = {}
    local i = table_start + 1
    while i < table_end do
        local comment_end = skip_comment(src, i)
        if comment_end then
            i = comment_end
        else
            local ch = src:sub(i, i)
            if ch == "'" or ch == '"' then
                i = skip_short_string(src, i)
            elseif ch == "[" and long_bracket_eq(src, i) then
                i = skip_long_bracket(src, i)
            elseif ch == "[" then
                local key_close = find_matching(src, i, "[", "]")
                if not key_close then return nil end
                local key = trim(src:sub(i + 1, key_close - 1))
                local j = key_close + 1
                while src:sub(j, j):match("%s") do j = j + 1 end
                if src:sub(j, j) ~= "=" then return nil end
                j = j + 1
                while src:sub(j, j):match("%s") do j = j + 1 end
                if src:sub(j, j + #"function" - 1) ~= "function" then return nil end
                local fn_end = find_function_end(src, j)
                if not fn_end then return nil end
                local fn_src = src:sub(j, fn_end)
                local params, body = parse_function_expr(fn_src)
                if not params then return nil end
                entries[#entries + 1] = { key = key, params = params, body = body }
                i = fn_end + 1
            else
                i = i + 1
            end
        end
    end
    return entries
end

local function parse_phase_name(src)
    local q, name = src:match("^%s*([\"'])(.-)%1%s*$")
    if q then return name end
    return nil
end

local function is_uncached_opts(src)
    if not src or trim(src) == "" then return false end
    return src:match("node_cache%s*=%s*([\"'])none%1") ~= nil
        and src:match("args_cache%s*=%s*([\"'])none%1") ~= nil
end

local function assignment_at(src, call_start)
    local line_start = src:sub(1, call_start):match(".*()\n")
    line_start = line_start and (line_start + 1) or 1
    local prefix = src:sub(line_start, call_start - 1)
    local indent, local_name = prefix:match("^(%s*)local%s+([_%a][_%w]*)%s*=%s*$")
    if indent then
        return { start_pos = line_start, indent = indent, name = local_name, local_decl = true }
    end
    indent, local_name = prefix:match("^(%s*)([_%a][_%w%.]*)%s*=%s*$")
    if indent then
        return { start_pos = line_start, indent = indent, name = local_name, local_decl = false }
    end
    return nil
end

function M.find_phases(src)
    local phases = {}
    local i = 1
    while true do
        local call_start = find_code(src, "pvm.phase", i)
        if not call_start then break end
        local open_i = src:find("%(", call_start + #"pvm.phase")
        if not open_i then break end
        local close_i = find_matching(src, open_i, "(", ")")
        if not close_i then break end
        local args = parse_phase_args(src:sub(open_i + 1, close_i - 1))
        local assignment = assignment_at(src, call_start)
        local phase = {
            call_start = call_start,
            call_end = close_i,
            replace_start = assignment and assignment.start_pos or call_start,
            assignment = assignment,
            args = args,
            phase_name = parse_phase_name(args[1]),
            kind = "unsupported",
            reason = "unsupported phase shape",
        }
        if assignment and args[2] then
            local params, body = parse_function_expr(args[2])
            if params and is_uncached_opts(args[3]) then
                phase.kind = "scalar_uncached"
                phase.reason = nil
                phase.params = params
                phase.body = body
            elseif params then
                phase.kind = "scalar_cached"
                phase.reason = "scalar phase still has cache semantics"
                phase.params = params
                phase.body = body
            elseif trim(args[2]):sub(1, 1) == "{" then
                local entries = parse_dispatch_table(args[2])
                if entries and #entries > 0 then
                    phase.kind = "dispatch"
                    phase.reason = "dispatch phase still has PVM stream semantics"
                    phase.entries = entries
                else
                    phase.kind = "dispatch"
                    phase.reason = "dispatch table shape is not supported"
                end
            end
        end
        phases[#phases + 1] = phase
        i = close_i + 1
    end
    return phases
end

local function direct_function_text(phase)
    local decl = phase.assignment.local_decl and "local function " or "function "
    local body = phase.body or ""
    body = body:gsub("%s*$", "")
    return phase.assignment.indent .. decl .. phase.assignment.name .. "(" .. trim(phase.params) .. ")"
        .. body .. "\n" .. phase.assignment.indent .. "end"
end

local function direct_dispatch_text(phase)
    local indent = phase.assignment.indent
    local decl = phase.assignment.local_decl and "local function " or "function "
    local out = {}
    out[#out + 1] = indent .. decl .. phase.assignment.name .. "(node, ...)"
    out[#out + 1] = indent .. "    local cls = schema.classof(node)"
    for i, entry in ipairs(phase.entries or {}) do
        local kw = i == 1 and "if" or "elseif"
        out[#out + 1] = indent .. "    " .. kw .. " schema.isa(node, " .. entry.key .. ") then"
        out[#out + 1] = indent .. "        return (function(" .. trim(entry.params) .. ")"
        local body = rewrite_direct_body(entry.body or ""):gsub("%s*$", "")
        out[#out + 1] = body
        out[#out + 1] = indent .. "        end)(node, ...)"
    end
    out[#out + 1] = indent .. "    else"
    out[#out + 1] = indent .. "        error(\"phase " .. tostring(phase.phase_name or phase.assignment.name) .. ": no handler for \" .. tostring(cls and cls.kind or type(node)), 2)"
    out[#out + 1] = indent .. "    end"
    out[#out + 1] = indent .. "end"
    return table.concat(out, "\n")
end

local function replace_ranges(src, ranges)
    table.sort(ranges, function(a, b) return a.start_pos > b.start_pos end)
    for _, r in ipairs(ranges) do
        src = src:sub(1, r.start_pos - 1) .. r.text .. src:sub(r.end_pos + 1)
    end
    return src
end

local function rewrite_pvm_terminal_calls(src, phase_names, report)
    local ranges = {}
    local i = 1
    while true do
        local call_start = find_code(src, "pvm.one", i)
        if not call_start then break end
        local open_i = src:find("%(", call_start + #"pvm.one")
        local close_i = open_i and find_matching(src, open_i, "(", ")")
        if not close_i then break end
        local inner = trim(src:sub(open_i + 1, close_i - 1))
        local name = inner:match("^([_%a][_%w]*)%s*%(")
        if name and phase_names[name] then
            local output = phase_names[name]
            local text = output == "many" and ("only(" .. inner .. ")") or inner
            ranges[#ranges + 1] = { start_pos = call_start, end_pos = close_i, text = text }
            report.rewritten_one_calls = report.rewritten_one_calls + 1
        else
            local method_name, args = inner:match("^([_%a][_%w]*):triplet_uncached%s*%((.*)%)$")
            if method_name and phase_names[method_name] then
                local output = phase_names[method_name]
                local inner_text = method_name .. "(" .. args .. ")"
                local text = output == "many" and ("only(" .. inner_text .. ")") or inner_text
                ranges[#ranges + 1] = { start_pos = call_start, end_pos = close_i, text = text }
                report.rewritten_one_calls = report.rewritten_one_calls + 1
            end
        end
        i = close_i + 1
    end
    src = replace_ranges(src, ranges)

    ranges = {}
    i = 1
    while true do
        local call_start = find_code(src, "pvm.drain", i)
        if not call_start then break end
        local open_i = src:find("%(", call_start + #"pvm.drain")
        local close_i = open_i and find_matching(src, open_i, "(", ")")
        if not close_i then break end
        local inner = trim(src:sub(open_i + 1, close_i - 1))
        local name = inner:match("^([_%a][_%w]*)%s*%(")
        if name and phase_names[name] == "many" then
            ranges[#ranges + 1] = { start_pos = call_start, end_pos = close_i, text = inner }
            report.rewritten_drain_calls = report.rewritten_drain_calls + 1
        end
        i = close_i + 1
    end
    return replace_ranges(src, ranges)
end

local function receiver_before_method(src, method_start)
    local i = method_start - 1
    while i >= 1 and src:sub(i, i):match("%s") do i = i - 1 end
    local stop_i = i
    while i >= 1 and src:sub(i, i):match("[_%w%.]") do i = i - 1 end
    local name = src:sub(i + 1, stop_i)
    if name == "" then return nil end
    return name, i + 1, stop_i
end

local function rewrite_phase_method_calls(src, phase_names, report)
    for _, method in ipairs({ "drain_uncached", "one_uncached", "triplet_uncached" }) do
        local ranges = {}
        local i = 1
        while true do
            local method_start = find_code(src, method, i)
            if not method_start then break end
            local colon = method_start - 1
            if src:sub(colon, colon) == ":" then
                local receiver, receiver_start = receiver_before_method(src, colon)
                local open_i = src:find("%(", method_start + #method)
                local close_i = open_i and find_matching(src, open_i, "(", ")")
                local output = receiver and phase_names[receiver]
                if output and close_i then
                    local args = src:sub(open_i + 1, close_i - 1)
                    local call = receiver .. "(" .. args .. ")"
                    local text = call
                    if method == "one_uncached" and output == "many" then
                        text = "only(" .. call .. ")"
                    elseif method == "drain_uncached" and output == "scalar" then
                        text = "single(" .. call .. ")"
                    elseif method == "triplet_uncached" and output == "scalar" then
                        text = "single(" .. call .. ")"
                    end
                    ranges[#ranges + 1] = { start_pos = receiver_start, end_pos = close_i, text = text }
                    report.rewritten_method_calls = (report.rewritten_method_calls or 0) + 1
                    i = close_i + 1
                else
                    i = method_start + #method
                end
            else
                i = method_start + #method
            end
        end
        src = replace_ranges(src, ranges)
    end
    return src
end

function M.transform_source(src, opts)
    opts = opts or {}
    local phases = M.find_phases(src)
    local report = {
        path = opts.path,
        phases = phases,
        erased_count = 0,
        rewritten_one_calls = 0,
        rewritten_drain_calls = 0,
        rewritten_method_calls = 0,
        erased = {},
        unsupported = {},
    }
    local ranges = {}
    local direct_names = {}
    for _, phase in ipairs(phases) do
        if phase.kind == "scalar_uncached" or (phase.kind == "scalar_cached" and opts.erase_cached_scalar ~= false) then
            ranges[#ranges + 1] = {
                start_pos = phase.replace_start,
                end_pos = phase.call_end,
                text = direct_function_text(phase),
            }
            direct_names[phase.assignment.name] = "scalar"
            report.erased_count = report.erased_count + 1
            report.erased[#report.erased + 1] = {
                variable = phase.assignment.name,
                phase_name = phase.phase_name,
                kind = phase.kind,
                cache_erased = phase.kind == "scalar_cached",
            }
        elseif phase.kind == "dispatch" and phase.entries and opts.erase_dispatch ~= false then
            ranges[#ranges + 1] = {
                start_pos = phase.replace_start,
                end_pos = phase.call_end,
                text = direct_dispatch_text(phase),
            }
            direct_names[phase.assignment.name] = "many"
            report.erased_count = report.erased_count + 1
            report.erased[#report.erased + 1] = {
                variable = phase.assignment.name,
                phase_name = phase.phase_name,
                kind = phase.kind,
                stream_erased = true,
            }
        else
            report.unsupported[#report.unsupported + 1] = {
                variable = phase.assignment and phase.assignment.name or nil,
                phase_name = phase.phase_name,
                kind = phase.kind,
                reason = phase.reason,
            }
        end
    end

    local out = replace_ranges(src, ranges)
    out = rewrite_pvm_terminal_calls(out, direct_names, report)
    out = rewrite_phase_method_calls(out, direct_names, report)
    out = out:gsub("pvm%.classof", "schema.classof")
    out = out:gsub("pvm%.with", "schema.with")
    out = out:gsub("pvm%.NIL", "schema.NIL")
    out = out:gsub("pvm%.context", "schema.context")

    local need_schema = out:match("schema%.") ~= nil
    local need_phase_output = out:match("%f[%w_]single%f[^%w_]%s*%(")
        or out:match("%f[%w_]only%f[^%w_]%s*%(")
        or out:match("%f[%w_]as_list%f[^%w_]%s*%(")
        or out:match("%f[%w_]append_all%f[^%w_]%s*%(")
        or out:match("%f[%w_]concat_all%f[^%w_]%s*%(")
        or out:match("%f[%w_]concat2%f[^%w_]%s*%(")
        or out:match("%f[%w_]concat3%f[^%w_]%s*%(")
        or out:match("%f[%w_]flat_map%f[^%w_]%s*%(")
    if need_schema or need_phase_output then
        local lines = {}
        if out:match("pvm%.") then lines[#lines + 1] = "local pvm = require(\"moonlift.pvm\")" end
        if need_schema then lines[#lines + 1] = "local schema = require(\"moonlift.schema_runtime\")" end
        if need_phase_output then lines[#lines + 1] = PHASE_OUTPUT_HELPERS:gsub("%s+$", "") end
        local replacement = table.concat(lines, "\n")
        local count = out:match("pvm%.") and 1 or nil
        out = out:gsub("local%s+pvm%s*=%s*require%(([\"'])moonlift%.pvm%1%)", replacement, count)
        if not out:match("moonlift%.schema_runtime") and need_schema then
            out = "local schema = require(\"moonlift.schema_runtime\")\n" .. out
        end
        if not out:match("local function single%(value%)") and need_phase_output then
            out = PHASE_OUTPUT_HELPERS .. out
        end
    end

    return out, report
end

function M.transform_file(path, out_path, opts)
    opts = opts or {}
    opts.path = opts.path or path
    local out, report = M.transform_source(read_file(path), opts)
    if out_path then write_file(out_path, out) end
    return out, report
end

function M.report_string(report)
    local lines = {}
    lines[#lines + 1] = tostring(report.path or "<source>") .. ": erased " .. tostring(report.erased_count or 0) .. " phase(s), rewrote " .. tostring(report.rewritten_one_calls or 0) .. " pvm.one call(s), rewrote " .. tostring(report.rewritten_drain_calls or 0) .. " pvm.drain call(s)"
    for _, item in ipairs(report.erased or {}) do
        lines[#lines + 1] = "  erased " .. tostring(item.variable) .. " (" .. tostring(item.phase_name or "?") .. ")"
    end
    for _, item in ipairs(report.unsupported or {}) do
        lines[#lines + 1] = "  kept " .. tostring(item.variable or "?") .. " (" .. tostring(item.phase_name or "?") .. "): " .. tostring(item.reason or item.kind)
    end
    return table.concat(lines, "\n")
end

return M
