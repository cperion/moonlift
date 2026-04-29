local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")
local MluaParse = require("moonlift.mlua_parse")

local M = {}

local scalar_words = {
    void = true, bool = true,
    i8 = true, i16 = true, i32 = true, i64 = true,
    u8 = true, u16 = true, u32 = true, u64 = true,
    f32 = true, f64 = true,
    rawptr = true, ptr = true, index = true,
    bool8 = true, bool32 = true,
}

local non_call_words = {
    ["if"] = true, ["then"] = true, ["else"] = true, ["elseif"] = true,
    ["end"] = true, ["return"] = true, ["yield"] = true, ["jump"] = true,
    ["func"] = true, ["struct"] = true, ["expose"] = true, ["module"] = true,
    ["region"] = true, ["expr"] = true, ["entry"] = true, ["block"] = true,
    ["for"] = true, ["while"] = true, ["do"] = true, ["let"] = true, ["var"] = true,
    state = true, next = true, set = true, emit = true,
    export = true, extern = true, import = true, const = true, static = true, type = true,
    lua = true, terra = true, c = true, moonlift = true,
    checked = true, unchecked = true, readonly = true, mutable = true,
    descriptor = true, pointer = true, proxy = true, data_len_stride = true, expanded_scalars = true,
    ["true"] = true, ["false"] = true, ["nil"] = true,
    view = true, ptr = true, len = true,
}
for k in pairs(scalar_words) do non_call_words[k] = true end

local function starts_ident_char(c)
    return c and c:match("[%w_]") ~= nil
end

local function word_at_boundary(src, s, e)
    local before = s > 1 and src:sub(s - 1, s - 1) or ""
    local after = src:sub(e + 1, e + 1)
    return not starts_ident_char(before) and not starts_ident_char(after)
end

local function kind_label(Mlua, kind)
    if kind == Mlua.IslandStruct then return "struct" end
    if kind == Mlua.IslandExpose then return "expose" end
    if kind == Mlua.IslandFunc then return "func" end
    if kind == Mlua.IslandModule then return "module" end
    if kind == Mlua.IslandRegion then return "region" end
    if kind == Mlua.IslandExpr then return "expr" end
    return "island"
end

local function safe(s)
    return tostring(s or "anonymous"):gsub("[^%w_%.%-:]", "_")
end

local function island_name_text(Mlua, island)
    if pvm.classof(island.name) == Mlua.IslandNamed then return island.name.name end
    if pvm.classof(island.name) == Mlua.IslandMalformedName then return island.name.text end
    return "anonymous"
end

local function add_range(P, index, start_offset, stop_offset)
    local range, reason = P.range_from_offsets(index, start_offset, stop_offset)
    if not range then error(reason, 2) end
    return range
end

local function add_anchor(S, anchors, id_text, kind, label, range)
    anchors[#anchors + 1] = S.AnchorSpan(S.AnchorId(id_text), kind, label, range)
end

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

function M.Define(T)
    local S = (T.MoonSource or T.Moon2Source)
    local Mlua = (T.MoonMlua or T.Moon2Mlua)
    local H = (T.MoonHost or T.Moon2Host)
    local Tr = (T.MoonTree or T.Moon2Tree)
    local P = PositionIndex.Define(T)
    local Parser = MluaParse.Define(T)

    local function local_anchor_set(island)
        local source = island.source.text
        local label = kind_label(Mlua, island.kind)
        local name_text = island_name_text(Mlua, island)
        local uri = S.DocUri("island://" .. label .. "/" .. safe(name_text))
        local doc = S.DocumentSnapshot(uri, S.DocVersion(0), S.LangMlua, source)
        local index = P.build_index(doc)
        local anchors = {}
        add_anchor(S, anchors, "island", S.AnchorHostedIsland, label, add_range(P, index, 0, #source))
        local kw_s, kw_e = find_word(source, label, 1)
        if kw_s then
            add_anchor(S, anchors, "island.keyword", S.AnchorKeyword, label, add_range(P, index, kw_s - 1, kw_e))
        end
        if pvm.classof(island.name) == Mlua.IslandNamed then
            local ns, ne = source:find(island.name.name, 1, true)
            if ns then
                local name_kind = S.AnchorFunctionName
                if island.kind == Mlua.IslandStruct then name_kind = S.AnchorStructName
                elseif island.kind == Mlua.IslandExpose then name_kind = S.AnchorExposeName
                elseif island.kind == Mlua.IslandModule then name_kind = S.AnchorModuleName
                elseif island.kind == Mlua.IslandRegion then name_kind = S.AnchorRegionName
                elseif island.kind == Mlua.IslandExpr then name_kind = S.AnchorExprName end
                add_anchor(S, anchors, "island.name", name_kind, island.name.name, add_range(P, index, ns - 1, ne))
            end
        end
        local function add_type_anchor(word, start_offset)
            if scalar_words[word] then
                add_anchor(S, anchors, "scalar." .. word .. "." .. tostring(start_offset), S.AnchorScalarType, word, add_range(P, index, start_offset, start_offset + #word))
            else
                add_anchor(S, anchors, "typeuse." .. word .. "." .. tostring(start_offset), S.AnchorBindingUse, word, add_range(P, index, start_offset, start_offset + #word))
            end
        end
        if island.kind == Mlua.IslandStruct then
            for align_s, align in source:gmatch("packed%s*%(%s*()([0-9]+)") do
                add_anchor(S, anchors, "packed.align." .. tostring(align_s), S.AnchorPackedAlign, align, add_range(P, index, align_s - 1, align_s - 1 + #align))
            end
            local body_s = source:find("\n", 1, true)
            local body_e = source:match("()%f[%w_]end%f[^%w_]%s*$")
            if body_s and body_e then
                local body = source:sub(body_s + 1, body_e - 1)
                local body_base = body_s
                for field, name in body:gmatch("()([_%a][_%w]*)%s*:") do
                    local start_offset = body_base + field - 1
                    add_anchor(S, anchors, "field." .. name, S.AnchorFieldName, name, add_range(P, index, start_offset, start_offset + #name))
                end
                for type_pos, ty in body:gmatch(":%s*()([_%a][_%w]*)") do
                    add_type_anchor(ty, body_base + type_pos - 1)
                end
            end
        end
        local seen_type_anchor = {}
        for s, word in source:gmatch("()([_%a][_%w]*)") do
            if scalar_words[word] and not seen_type_anchor[s] then
                seen_type_anchor[s] = true
                add_type_anchor(word, s - 1)
            end
        end
        for s, word in source:gmatch("[%(:%-]%s*()([_%a][_%w]*)") do
            if not seen_type_anchor[s] and (scalar_words[word] or word:sub(1, 1):match("%u")) then
                seen_type_anchor[s] = true
                add_type_anchor(word, s - 1)
            end
        end

        local keyword_words = {
            "return", "yield", "if", "then", "else", "elseif", "jump", "let", "var", "state", "block", "entry", "module", "func", "export", "extern", "const", "static", "import", "type", "region", "expr", "expose",
        }
        for i = 1, #keyword_words do
            local kw = keyword_words[i]
            local pos = 1
            while true do
                local s, e = find_word(source, kw, pos)
                if not s then break end
                add_anchor(S, anchors, "keyword." .. kw .. "." .. tostring(s), S.AnchorKeyword, kw, add_range(P, index, s - 1, e))
                pos = e + 1
            end
        end

        local seen_operator = {}
        local function add_operator(op, s, e)
            local start_offset, stop_offset = s - 1, e
            for p = start_offset, stop_offset - 1 do if seen_operator[p] then return end end
            for p = start_offset, stop_offset - 1 do seen_operator[p] = true end
            add_anchor(S, anchors, "operator." .. op:gsub("%W", "_") .. "." .. tostring(s), S.AnchorOpaque("operator"), op, add_range(P, index, start_offset, stop_offset))
        end
        local multi_ops = { "==", "~=", "<=", ">=", "<<", ">>", "&&", "||" }
        for i = 1, #multi_ops do
            local op = multi_ops[i]
            local pos = 1
            while true do
                local s, e = source:find(op, pos, true)
                if not s then break end
                add_operator(op, s, e)
                pos = e + 1
            end
        end
        local single_ops = { "+", "-", "*", "/", "%", "<", ">", "&", "|", "~" }
        for i = 1, #single_ops do
            local op = single_ops[i]
            local pos = 1
            while true do
                local s, e = source:find(op, pos, true)
                if not s then break end
                if not seen_operator[s - 1] and not (op == "-" and source:sub(e + 1, e + 1) == ">") then add_operator(op, s, e) end
                pos = e + 1
            end
        end

        local function add_param_anchors(params, base_offset, id_prefix)
            for ps, pname in params:gmatch("()([_%a][_%w]*)%s*:") do
                local start_offset = base_offset + ps - 1
                add_anchor(S, anchors, id_prefix .. "." .. pname .. "." .. tostring(start_offset), S.AnchorParamName, pname, add_range(P, index, start_offset, start_offset + #pname))
            end
        end

        local function top_level_semicolon(text)
            local depth = 0
            for i = 1, #text do
                local c = text:sub(i, i)
                if c == "(" then depth = depth + 1
                elseif c == ")" and depth > 0 then depth = depth - 1
                elseif c == ";" and depth == 0 then return i end
            end
            return nil
        end

        local function add_region_header_param_anchors(params, base_offset)
            local sep = top_level_semicolon(params)
            add_param_anchors(sep and params:sub(1, sep - 1) or params, base_offset, "param")
            if not sep then return end
            local rest = params:sub(sep + 1)
            local rest_base = base_offset + sep
            local pos = 1
            while pos <= #rest do
                local ss, se, slot, body = rest:find("([_%a][_%w]*)%s*:%s*cont%s*(%b())", pos)
                if not ss then break end
                local _, cont_end = rest:find("cont%s*%(", ss)
                if cont_end then
                    add_param_anchors(body:sub(2, -2), rest_base + cont_end, "cont.param.slot." .. slot)
                end
                pos = se + 1
            end
        end

        local first_paren_s, first_paren_e = source:find("%b()")
        if first_paren_s and first_paren_e then
            local params = source:sub(first_paren_s + 1, first_paren_e - 1)
            if island.kind == Mlua.IslandRegion then
                add_region_header_param_anchors(params, first_paren_s)
            else
                add_param_anchors(params, first_paren_s, "param")
            end
        end
        for _, label_name, paren_s, parens in source:gmatch("()%f[%w_]entry%f[^%w_]%s+([_%a][_%w]*)%s*()(%b())") do
            add_param_anchors(parens:sub(2, -2), paren_s, "cont.param.entry." .. label_name)
        end
        for _, label_name, paren_s, parens in source:gmatch("()%f[%w_]block%f[^%w_]%s+([_%a][_%w]*)%s*()(%b())") do
            add_param_anchors(parens:sub(2, -2), paren_s, "cont.param.block." .. label_name)
        end

        local function add_local_decl_anchors(keyword)
            for s, lname in source:gmatch("%f[%w_]" .. keyword .. "%f[^%w_]%s+()([_%a][_%w]*)") do
                add_anchor(S, anchors, "local." .. keyword .. "." .. lname .. "." .. tostring(s), S.AnchorLocalName, lname, add_range(P, index, s - 1, s - 1 + #lname))
            end
        end
        add_local_decl_anchors("let")
        add_local_decl_anchors("var")
        add_local_decl_anchors("state")
        for s, label_name in source:gmatch("%f[%w_]entry%f[^%w_]%s+()([_%a][_%w]*)") do
            add_anchor(S, anchors, "cont.def.entry." .. label_name .. "." .. tostring(s), S.AnchorContinuationName, label_name, add_range(P, index, s - 1, s - 1 + #label_name))
        end
        for s, label_name in source:gmatch("%f[%w_]block%f[^%w_]%s+()([_%a][_%w]*)") do
            add_anchor(S, anchors, "cont.def.block." .. label_name .. "." .. tostring(s), S.AnchorContinuationName, label_name, add_range(P, index, s - 1, s - 1 + #label_name))
        end
        for s, label_name in source:gmatch("[;%s,]%s*()([_%a][_%w]*)%s*:%s*cont%s*%(") do
            add_anchor(S, anchors, "cont.def.slot." .. label_name .. "." .. tostring(s), S.AnchorContinuationName, label_name, add_range(P, index, s - 1, s - 1 + #label_name))
        end
        for s, label_name in source:gmatch("%f[%w_]jump%f[^%w_]%s+()([_%a][_%w]*)") do
            add_anchor(S, anchors, "cont.use." .. label_name .. "." .. tostring(s), S.AnchorContinuationUse, label_name, add_range(P, index, s - 1, s - 1 + #label_name))
        end
        for s, fname in source:gmatch("%.%s*()([_%a][_%w]*)") do
            add_anchor(S, anchors, "field.use." .. fname .. "." .. tostring(s), S.AnchorFieldUse, fname, add_range(P, index, s - 1, s - 1 + #fname))
        end
        for s, callee in source:gmatch("()([_%a][_%w_%.:]*)%s*%(") do
            local head = source:sub(1, s - 1)
            local preceding_decl = head:match("([_%a][_%w]*)%s+$")
            if callee:match("^moonlift%.") then
                add_anchor(S, anchors, "builtin.call." .. callee .. "." .. tostring(s), S.AnchorBuiltinName, callee, add_range(P, index, s - 1, s - 1 + #callee))
            elseif not non_call_words[callee] and preceding_decl ~= "func" and preceding_decl ~= "expr" and preceding_decl ~= "region" and preceding_decl ~= "entry" and preceding_decl ~= "block" then
                add_anchor(S, anchors, "func.use." .. callee .. "." .. tostring(s), S.AnchorFunctionUse, callee, add_range(P, index, s - 1, s - 1 + #callee))
            end
        end
        local function anchor_overlaps(start_offset, stop_offset)
            for i = 1, #anchors do
                local a = anchors[i]
                if a.kind ~= S.AnchorHostedIsland and a.kind ~= S.AnchorIslandBody and a.kind ~= S.AnchorDocument then
                    local r = a.range
                    if start_offset < r.stop_offset and r.start_offset < stop_offset then return true end
                end
            end
            return false
        end
        local declaration_prev_words = {
            func = true, struct = true, module = true, region = true, expr = true, expose = true,
            entry = true, block = true, let = true, var = true, state = true,
            const = true, static = true, type = true, import = true, extern = true, export = true,
        }
        local function follows_declaration_word(pos)
            local prev = source:sub(1, pos - 1):match("([_%a][_%w]*)%s*$")
            return declaration_prev_words[prev] == true
        end
        for s, word in source:gmatch("()([_%a][_%w]*)") do
            local start_offset, stop_offset = s - 1, s - 1 + #word
            if not non_call_words[word] and not follows_declaration_word(s) and not anchor_overlaps(start_offset, stop_offset) then
                add_anchor(S, anchors, "value.use." .. word .. "." .. tostring(s), S.AnchorBindingUse, word, add_range(P, index, start_offset, stop_offset))
            end
        end
        return S.AnchorSet(anchors)
    end

    local island_parse_phase = pvm.phase("moon2_mlua_island_parse", function(island)
        local parsed = Parser.parse(island.source.text, kind_label(Mlua, island.kind) .. ":" .. island_name_text(Mlua, island))
        return Mlua.IslandParse(
            island,
            parsed.decls,
            parsed.module,
            parsed.region_frags,
            parsed.expr_frags,
            parsed.issues,
            local_anchor_set(island)
        )
    end)

    local function parse(island)
        return pvm.one(island_parse_phase(island))
    end

    local function empty_parse(island)
        return Mlua.IslandParse(island, H.HostDeclSet({}), Tr.Module(Tr.ModuleSurface, {}), {}, {}, {}, local_anchor_set(island))
    end

    return {
        island_parse_phase = island_parse_phase,
        parse = parse,
        empty_parse = empty_parse,
    }
end

return M
