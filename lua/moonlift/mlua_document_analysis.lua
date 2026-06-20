local pvm = require("moonlift.pvm")
local Parse = require("moonlift.parse")
local PositionIndex = require("moonlift.source_position_index")
local HostValidate = require("moonlift.host_decl_validate")
local HostLayout = require("moonlift.host_layout_resolve")
local OpenFacts = require("moonlift.open_facts")
local OpenValidate = require("moonlift.open_validate")
local Pipeline_mod = require("moonlift.frontend_pipeline")
local BackValidate = require("moonlift.back_validate")
local Errors = require("moonlift.error")
local Session = require("moonlift.host_session")

local M = {}

local resolved_by_analysis = setmetatable({}, { __mode = "k" })

function M.resolved_issues(analysis)
    return resolved_by_analysis[analysis] or {}
end

local function append_all(dst, xs)
    for i = 1, #(xs or {}) do dst[#dst + 1] = xs[i] end
end

local scalar_names = {
    void = "ScalarVoid", bool = "ScalarBool", bool8 = "ScalarBool", bool32 = "ScalarBool",
    i8 = "ScalarI8", i16 = "ScalarI16", i32 = "ScalarI32", i64 = "ScalarI64",
    u8 = "ScalarU8", u16 = "ScalarU16", u32 = "ScalarU32", u64 = "ScalarU64",
    f32 = "ScalarF32", f64 = "ScalarF64", rawptr = "ScalarRawPtr", ptr = "ScalarRawPtr",
    index = "ScalarIndex",
}

local keyword_set = {
    ["func"] = true, ["region"] = true, ["expr"] = true, ["struct"] = true, ["union"] = true,
    ["handle"] = true,
    ["entry"] = true, ["block"] = true, ["if"] = true, ["then"] = true, ["elseif"] = true,
    ["else"] = true, ["switch"] = true, ["case"] = true, ["default"] = true, ["do"] = true,
    ["end"] = true, ["return"] = true, ["yield"] = true, ["jump"] = true, ["emit"] = true,
    ["let"] = true, ["var"] = true, ["requires"] = true, ["noalias"] = true, ["readonly"] = true,
    ["writeonly"] = true, ["noescape"] = true, ["invalidate"] = true, ["preserve"] = true,
    ["lease"] = true, ["invalid"] = true,
    ["as"] = true, ["select"] = true, ["true"] = true, ["false"] = true,
    ["nil"] = true, ["and"] = true, ["or"] = true, ["not"] = true,
    ["assert"] = true, ["len"] = true, ["view"] = true,
    ["bounds"] = true, ["window_bounds"] = true, ["disjoint"] = true, ["same_len"] = true,
}

local function island_kind(Mlua, kind)
    if kind == "struct" then return Mlua.IslandStruct end
    if kind == "handle" then return Mlua.IslandType end
    if kind == "func" then return Mlua.IslandFunc end
    if kind == "region" then return Mlua.IslandRegion end
    if kind == "expr" then return Mlua.IslandExpr end
    if kind == "union" then return Mlua.IslandType end
    if kind == "extern" then return Mlua.IslandExtern end
    return Mlua.IslandMalformedName(kind)
end

function M.Define(T)
    local S = T.MoonSource
    local Mlua = T.MoonMlua
    local H = T.MoonHost
    local C = T.MoonCore
    local Ty = T.MoonType
    local Tr = T.MoonTree
    local Pm = T.MoonParse
    local O = T.MoonOpen
    local B = T.MoonBack

    local ParseApi = Parse.Define(T)
    local Pos = PositionIndex.Define(T)
    local HostV = HostValidate.Define(T)
    local HostL = HostLayout.Define(T)
    local OpenF = OpenFacts.Define(T)
    local OpenV = OpenValidate.Define(T)
    local Pipeline = require("moonlift.frontend_pipeline").Define(T)
    local BackV = BackValidate.Define(T)

    local function range(index, start_offset, stop_offset)
        if start_offset < 0 then start_offset = 0 end
        if stop_offset < start_offset then stop_offset = start_offset end
        local n = #index.document.text
        if start_offset > n then start_offset = n end
        if stop_offset > n then stop_offset = n end
        return assert(Pos.range_from_offsets(index, start_offset, stop_offset))
    end

    local function source_slice(text, start_offset, stop_offset)
        return S.SourceSlice(text:sub(start_offset + 1, stop_offset))
    end

    local function add_anchor(out, index, id, kind, label, start_offset, stop_offset)
        if stop_offset < start_offset then stop_offset = start_offset end
        out[#out + 1] = S.AnchorSpan(S.AnchorId(id), kind, label or "", range(index, start_offset, stop_offset))
    end

    local function ty_from_name(name)
        if scalar_names[name] then return Ty.TScalar(C[scalar_names[name]]) end
        return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) })))
    end

    local function parse_type_name(text)
        text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local ptr = text:match("^ptr%s*%((.-)%)$")
        if ptr then return Ty.TPtr(parse_type_name(ptr)) end
        local view = text:match("^view%s*%((.-)%)$")
        if view then return Ty.TView(parse_type_name(view)) end
        return ty_from_name(text)
    end

    local function layout_id(name) return H.HostLayoutId("mlua." .. name, name) end
    local function field_id(owner, name) return H.HostFieldId("mlua." .. owner .. "." .. name, name) end

    local function single_named_type(ty)
        if pvm.classof(ty) ~= Ty.TNamed or pvm.classof(ty.ref) ~= Ty.TypeRefPath then return nil end
        local parts = ty.ref.path.parts
        if #parts ~= 1 then return nil end
        return parts[1].text
    end

    local function host_field_type(ty)
        local name = single_named_type(ty)
        if name == "bool8" then return Ty.TScalar(C.ScalarBool), H.HostStorageBool(H.HostBoolU8, C.ScalarU8) end
        if name == "bool32" then return Ty.TScalar(C.ScalarBool), H.HostStorageBool(H.HostBoolI32, C.ScalarI32) end
        return ty, H.HostStorageSame
    end

    local function host_repr_from_parsed(repr)
        if type(repr) == "table" and repr.kind == "packed" then return H.HostReprPacked(repr.align or 0) end
        return H.HostReprC
    end

    local function host_struct_from_decl(decl, repr)
        local fields = {}
        for i = 1, #(decl.fields or {}) do
            local f = decl.fields[i]
            local expose_ty, storage = host_field_type(f.ty)
            fields[#fields + 1] = H.HostFieldDecl(field_id(decl.name, f.field_name), f.field_name, expose_ty, storage, {})
        end
        return H.HostStructDecl(layout_id(decl.name), decl.name, host_repr_from_parsed(repr), fields)
    end

    local function expose_subject(type_text)
        local view = type_text:match("^%s*view%s*%((.-)%)%s*$")
        if view then return H.HostExposeView(parse_type_name(view)) end
        local ptr = type_text:match("^%s*ptr%s*%((.-)%)%s*$")
        if ptr then return H.HostExposePtr(parse_type_name(ptr)) end
        return H.HostExposeType(parse_type_name(type_text))
    end

    local function collect_exposes(document, index, decls, anchors)
        local text = document.text
        local pos = 1
        while true do
            local s, e, name, ty_text = text:find("%f[%w_]expose%f[^%w_]%s+([_%a][_%w]*)%s*:%s*([^\n]+)", pos)
            if not s then break end
            if decls then decls[#decls + 1] = H.HostDeclExpose(H.HostExposeDecl(expose_subject(ty_text), name, {})) end
            if anchors then
                local chunk = text:sub(s, e)
                local local_start = chunk:find(name, 1, true) or 1
                add_anchor(anchors, index, "expose." .. name .. "." .. s, S.AnchorExposeName, name, s - 1 + local_start - 1, s - 1 + local_start - 1 + #name)
                local type_name = ty_text:match("%(([_%a][_%w]*)%)") or ty_text:match("^%s*([_%a][_%w]*)")
                if type_name then
                    local type_start = chunk:find(type_name, local_start + #name, true)
                    if type_start then
                        add_anchor(anchors, index, "expose.type." .. type_name .. "." .. s, S.AnchorBindingUse, type_name, s - 1 + type_start - 1, s - 1 + type_start - 1 + #type_name)
                    end
                end
            end
            pos = e + 1
        end
    end

    local function build_anchors(document, scan, index)
        local anchors = {}
        add_anchor(anchors, index, "document", S.AnchorDocument, "document", 0, #document.text)
        local toks = scan.toks
        local def_next = nil
        local after_struct = false
        local after_func = false
        local after_region = false
        local after_expr = false
        local after_block = false
        local skip_next_type_name = false
        local n = toks.n or 0
        local counter = 0
        local function tid(prefix, i) counter = counter + 1; return prefix .. "." .. tostring(i) .. "." .. tostring(counter) end
        local TK = Parse.TK
        local function add_emit_use_anchor(i, start)
            local j = i + 1
            while toks.kind[j] == TK.nl do j = j + 1 end
            if j > n then return end
            local frag = (toks.kind[j] == TK.hole) and "nil" or tostring(toks.text[j] or "")
            while j <= n and toks.kind[j] ~= TK.lparen do j = j + 1 end
            if j > n then return end
            local depth = 0
            while j <= n do
                if toks.kind[j] == TK.lparen then depth = depth + 1
                elseif toks.kind[j] == TK.rparen then
                    depth = depth - 1
                    if depth == 0 then
                        add_anchor(anchors, index, tid("emit-use", i), S.AnchorOpaque("emit-use"), "emit." .. frag .. "." .. tostring(j + 1), start, toks.stop[j] or start)
                        return
                    end
                end
                j = j + 1
            end
        end
        local function nearest_open_paren(tok_i, first_tok)
            local depth = 0
            for j = tok_i - 1, first_tok, -1 do
                local text = toks.text[j]
                if text == ")" then
                    depth = depth + 1
                elseif text == "(" then
                    if depth == 0 then return j end
                    depth = depth - 1
                end
            end
            return nil
        end
        local function param_anchor_id(tok_i, first_tok)
            local open = nearest_open_paren(tok_i, first_tok)
            if not open then return tid("param", tok_i) end
            local label = toks.text[open - 1]
            local before_label = toks.text[open - 2]
            if type(label) ~= "string" or not label:match("^[_%a][_%w]*$") then return tid("param", tok_i) end
            if before_label == "block" then return tid("cont.param.block." .. label, tok_i) end
            if before_label == "entry" then return tid("cont.param.entry." .. label, tok_i) end
            if before_label == ";" or before_label == "," then return tid("cont.param.slot." .. label, tok_i) end
            return tid("param", tok_i)
        end
        local function next_non_nl(tok_i)
            local j = tok_i + 1
            while j <= n and toks.kind[j] == TK.nl do j = j + 1 end
            return j <= n and j or nil
        end
        local function has_explicit_island_name(island)
            local j = next_non_nl(island.first_tok)
            if not j then return false end
            local text = toks.text[j]
            if type(text) ~= "string" or not text:match("^[_%a][_%w]*$") or keyword_set[text] then return false end
            local k = next_non_nl(j)
            return not (k and toks.text[k] == ":")
        end
        local assignment_anchor_kind = {
            struct = S.AnchorStructName,
            handle = S.AnchorStructName,
            union = S.AnchorStructName,
            func = S.AnchorFunctionName,
            region = S.AnchorRegionName,
            expr = S.AnchorExprName,
        }
        local function assignment_target_before(start_1based)
            local prefix = document.text:sub(1, start_1based - 1)
            local line_start = prefix:match(".*\n()") or 1
            local lhs = prefix:sub(line_start)
            local s, _, name = lhs:find("([_%a][_%w]*)%s*=%s*$")
            if not s then return nil end
            return name, line_start + s - 2, line_start + s - 2 + #name
        end
        for si, island in ipairs(scan.islands) do
            add_anchor(anchors, index, "island." .. si, S.AnchorHostedIsland, island.kind, island.start - 1, island.stop)
            local assigned_kind = assignment_anchor_kind[island.kind]
            if assigned_kind and island.name_hint and not has_explicit_island_name(island) then
                local name, start_offset, stop_offset = assignment_target_before(island.start)
                if name and name == island.name_hint then
                    add_anchor(anchors, index, "assigned." .. island.kind .. "." .. si, assigned_kind, name, start_offset, stop_offset)
                end
            end
            for i = island.first_tok, island.last_tok do
                local text = toks.text[i]
                local start = (toks.start[i] or 1) - 1
                local stop = toks.stop[i] or start
                if text and text ~= "" then
                    if keyword_set[text] then
                        add_anchor(anchors, index, tid("kw", i), S.AnchorKeyword, text, start, stop)
                        if text == "emit" then add_emit_use_anchor(i, start) end
                    end
                    if text == "struct" or text == "union" then
                        after_struct = has_explicit_island_name(island)
                    elseif text == "handle" then
                        local j = next_non_nl(i)
                        local candidate = j and toks.text[j]
                        after_struct = type(candidate) == "string" and candidate:match("^[_%a][_%w]*$") and not keyword_set[candidate] or false
                    elseif text == "func" then after_func = true
                    elseif text == "region" then after_region = true
                    elseif text == "expr" then after_expr = true
                    elseif text == "block" or text == "entry" then after_block = true
                    elseif text == "let" or text == "var" then def_next = S.AnchorLocalName
                    elseif scalar_names[text] then
                        add_anchor(anchors, index, tid("scalar", i), S.AnchorScalarType, text, start, stop)
                    elseif text:match("^[_%a][_%w]*$") and not keyword_set[text] then
                        local prev = toks.text[i - 1]
                        local nxt = toks.text[i + 1]
                        if prev == "emit" then
                            add_anchor(anchors, index, tid("funuse", i), S.AnchorFunctionUse, text, start, stop)
                            after_region = false; after_expr = false
                        elseif after_struct then
                            add_anchor(anchors, index, tid("struct", i), S.AnchorStructName, text, start, stop); after_struct = false
                        elseif after_func then
                            if nxt == ":" and toks.text[i + 2] and tostring(toks.text[i + 2]):match("^[_%a][_%w]*$") then
                                local label = text .. ":" .. toks.text[i + 2]
                                add_anchor(anchors, index, tid("method", i), S.AnchorMethodName, label, start, toks.stop[i + 2] or stop)
                            else
                                add_anchor(anchors, index, tid("func", i), S.AnchorFunctionName, text, start, stop)
                            end
                            after_func = false
                        elseif after_region then
                            add_anchor(anchors, index, tid("region", i), S.AnchorRegionName, text, start, stop); after_region = false
                        elseif after_expr then
                            add_anchor(anchors, index, tid("expr", i), S.AnchorExprName, text, start, stop); after_expr = false
                        elseif after_block then
                            add_anchor(anchors, index, tid("cont", i), S.AnchorContinuationName, text, start, stop); after_block = false
                        elseif def_next then
                            add_anchor(anchors, index, tid("def", i), def_next, text, start, stop); def_next = nil
                        elseif (prev == ";" or prev == ",") and nxt == "(" then
                            add_anchor(anchors, index, tid("cont", i), S.AnchorContinuationName, text, start, stop)
                        elseif nxt == ":" and (prev ~= ".") then
                            if island.kind == "struct" then
                                add_anchor(anchors, index, tid("field", i), S.AnchorFieldName, text, start, stop)
                            else
                                add_anchor(anchors, index, param_anchor_id(i, island.first_tok), S.AnchorParamName, text, start, stop)
                            end
                        elseif prev == "jump" then
                            add_anchor(anchors, index, tid("contuse", i), S.AnchorContinuationUse, text, start, stop)
                        elseif prev == "." then
                            add_anchor(anchors, index, tid("fielduse", i), S.AnchorFieldUse, text, start, stop)
                        elseif nxt == "(" then
                            add_anchor(anchors, index, tid("funuse", i), S.AnchorFunctionUse, text, start, stop)
                        else
                            add_anchor(anchors, index, tid("value.use", i), S.AnchorBindingUse, text, start, stop)
                        end
                    elseif text == "[" or text == "]" or text == "=" or text == "(" or text == ")" then
                        add_anchor(anchors, index, tid("punct", i), S.AnchorOpaque("operator"), text, start, stop)
                    elseif text == "+" or text == "-" or text == "*" or text == "/" or text == "%" or text == "==" or text == "~=" or text == "<" or text == ">" or text == "<=" or text == ">=" or text == "&" or text == "|" or text == "~" or text == "^" or text == "<<" or text == ">>>" or text == ">>" then
                        add_anchor(anchors, index, tid("op", i), S.AnchorOpaque("operator"), text, start, stop)
                    end
                end
            end
        end
        collect_exposes(document, index, {}, anchors)
        local ppos = 1
        while true do
            local s, e, align = document.text:find("packed%s*%(%s*(%d+)%s*%)", ppos)
            if not s then break end
            local rel = document.text:sub(s, e):find(align, 1, true) or 1
            add_anchor(anchors, index, "packed.align." .. tostring(s), S.AnchorPackedAlign, align, s - 1 + rel - 1, s - 1 + rel - 1 + #align)
            ppos = e + 1
        end
        return S.AnchorSet(anchors)
    end

    local function document_parts(document, scan, anchors)
        local segments = {}
        local cursor = 1
        for i, island in ipairs(scan.islands) do
            if island.start > cursor then
                local r = range(Pos.build_index(document), cursor - 1, island.start - 1)
                segments[#segments + 1] = Mlua.LuaOpaque(S.SourceOccurrence(source_slice(document.text, cursor - 1, island.start - 1), r))
            end
            local r = range(Pos.build_index(document), island.start - 1, island.stop)
            local src = document.text:sub(island.start, island.stop)
            local name = src:match("^%s*" .. island.kind .. "%s+([_%a][_%w]*)")
            if island.kind == "struct" and src:match("^%s*struct%s+[_%a][_%w]*%s*:") then name = nil end
            if island.kind == "union" and src:match("^%s*union%s+[_%a][_%w]*%s*[%(|]") then name = nil end
            name = name or island.name_hint
            segments[#segments + 1] = Mlua.HostedIsland(Mlua.IslandText(island_kind(Mlua, island.kind), name and Mlua.IslandNamed(name) or Mlua.IslandAnonymous, S.SourceSlice(src)), r)
            cursor = island.stop + 1
        end
        if cursor <= #document.text then
            local r = range(Pos.build_index(document), cursor - 1, #document.text)
            segments[#segments + 1] = Mlua.LuaOpaque(S.SourceOccurrence(source_slice(document.text, cursor - 1, #document.text), r))
        end
        return Mlua.DocumentParts(document, segments, anchors)
    end

    local function analyze_document(document)
        local index = Pos.build_index(document)
        local scan = Parse.scan_document(document.text)
        local anchors = build_anchors(document, scan, index)
        local parts = document_parts(document, scan, anchors)

        -- Create collector for this analysis cycle
        local analysis_ctx = {
            parse = nil,
            anchors = anchors,
            uri = document.uri and document.uri.text,
            source_text = document.text,
            back_provenance = nil,
        }
        local collector = Errors.CollectingCollector(Errors.SpanResolvers.RESOLVERS, analysis_ctx)

        -- Attach collector to the default session so host builders emit to it
        local session = require("moonlift.host").session()
        if session then session:set_issue_collector(collector) end
        require("moonlift.host_splice").set_collector(collector)

        local decls, items, region_frags, expr_frags, issues, island_parses = {}, {}, {}, {}, {}, {}
        local protocol_types = {}
        for i, island in ipairs(scan.islands) do
            local src = document.text:sub(island.start, island.stop)
            local parsed = ParseApi.parse_island(scan, i, { protocol_types = protocol_types })
            for pi = 1, #parsed.issues do
                local msg = parsed.issues[pi].message or ""
                if not (msg:match("^invalid character") and #parsed.issues > 1) then
                    if msg:match("^invalid token in expression") then
                        issues[#issues + 1] = Pm.ParseIssue("expected expression", parsed.issues[pi].offset, parsed.issues[pi].line, parsed.issues[pi].col)
                    else
                        issues[#issues + 1] = parsed.issues[pi]
                    end
                end
            end
            protocol_types = parsed.protocol_types or protocol_types
            local decl_set = H.HostDeclSet({})
            local module = Tr.Module(Tr.ModuleSurface, {})
            local rfrags, efrags = {}, {}
            if island.kind == "struct" then
                if parsed.value and parsed.value.decl and pvm.classof(parsed.value.decl) == Tr.TypeDeclStruct then
                    local sd = host_struct_from_decl(parsed.value.decl, parsed.value.repr)
                    decls[#decls + 1] = H.HostDeclStruct(sd)
                    decl_set = H.HostDeclSet({ H.HostDeclStruct(sd) })
                    local tree_fields = {}
                    for fi = 1, #sd.fields do tree_fields[fi] = Ty.FieldDecl(sd.fields[fi].name, sd.fields[fi].expose_ty) end
                    items[#items + 1] = Tr.ItemType(Tr.TypeDeclStruct(sd.name, tree_fields))
                elseif parsed.value and parsed.value.decl then
                    items[#items + 1] = Tr.ItemType(parsed.value.decl)
                end
            elseif island.kind == "union" or island.kind == "handle" then
                if parsed.value and parsed.value.decl then items[#items + 1] = Tr.ItemType(parsed.value.decl) end
            elseif island.kind == "func" then
                if parsed.value and parsed.value.kind ~= "func_impl" then items[#items + 1] = Tr.ItemFunc(parsed.value) end
            elseif island.kind == "extern" then
                if parsed.value then items[#items + 1] = Tr.ItemExtern(parsed.value) end
            elseif island.kind == "region" then
                if parsed.value and parsed.value.kind ~= "region_impl" then
                    local rcls = pvm.classof(parsed.value)
                    if rcls ~= O.RegionFragDecl then
                        items[#items + 1] = Tr.ItemRegionFrag(parsed.value)
                        region_frags[#region_frags + 1] = parsed.value
                        rfrags[1] = parsed.value
                    end
                end
            elseif island.kind == "expr" then
                if parsed.value then
                    items[#items + 1] = Tr.ItemExprFrag(parsed.value)
                    expr_frags[#expr_frags + 1] = parsed.value
                    efrags[1] = parsed.value
                end
            end
            module = Tr.Module(Tr.ModuleSurface, items)
            local island_text = Mlua.IslandText(island_kind(Mlua, island.kind), Mlua.IslandAnonymous, S.SourceSlice(src))
            island_parses[#island_parses + 1] = Mlua.IslandParse(island_text, decl_set, module, rfrags, efrags, parsed.issues, anchors)
        end
        collect_exposes(document, index, decls, nil)

        local combined = H.MluaParseResult(H.HostDeclSet(decls), Tr.Module(Tr.ModuleSurface, items), region_frags, expr_frags, issues)
        local parse = Mlua.DocumentParse(parts, combined, island_parses, anchors)
        analysis_ctx.parse = parse
        for i = 1, #issues do collector:emit(issues[i], "parse") end

        local host_report = HostV.validate(combined.decls)
        for i = 1, #host_report.issues do collector:emit(host_report.issues[i], "host") end
        local layouts = {}
        -- Invalid host declarations can make layout computation nonsensical
        -- (for example packed(3)); publish validation diagnostics first and
        -- skip layout-derived hover facts until the source is corrected.
        if #host_report.issues == 0 then
            for i = 1, #combined.decls.decls do
                local d = combined.decls.decls[i]
                if pvm.classof(d) == H.HostDeclStruct then
                    local ok, layout = pcall(function() return HostL.resolve_layout(d.decl) end)
                    if ok and layout then layouts[#layouts + 1] = layout
                    elseif not ok then
                        issues[#issues + 1] = Pm.ParseIssue("internal: layout resolution error: " .. tostring(layout), 0, 1, 1)
                    end
                end
            end
        end
        local host = H.MluaHostPipelineResult(combined, host_report, H.HostLayoutEnv(layouts))

        local open_report = O.ValidationReport({})
        local type_issues, control_facts = {}, {}
        local checked_module = combined.module
        local type_issues = {}
        local result_or_err = nil
        if #combined.module.items > 0 then
            local ok_tc, res = pcall(function()
                local r = Pipeline.lower_module(combined.module, {
                    site = "mlua_document_analysis",
                    collector = collector,
                    analysis_ctx = analysis_ctx,
                })
                return r
            end)
            result_or_err = res
            if ok_tc and res then
                checked_module = res.checked.module
                type_issues = res.checked.issues or {}
                open_report = res.open_report or O.ValidationReport({})
            else
                issues[#issues + 1] = Pm.ParseIssue("internal: pipeline error: " .. tostring(res), 0, 1, 1)
            end
        end

        local back_report = B.BackValidationReport({})
        if #type_issues == 0 and #checked_module.items > 0 then
            if result_or_err and result_or_err.back_report then
                back_report = result_or_err.back_report
                -- Provenance map is already attached to analysis_ctx.back_provenance
                -- by Pipeline.lower_module (frontend_pipeline.lua)
            end
        end

        -- Get resolved issues from the collector and run cascade filter
        local resolved = collector:resolved_issues()
        local filtered = Errors.CascadeFilter.filter(resolved)

        -- Clear collector from session to avoid leaking between analyses
        if session then session:set_issue_collector(nil) end
        require("moonlift.host_splice").set_collector(nil)

        local analysis = Mlua.DocumentAnalysis(parse, host, open_report, type_issues, control_facts, back_report, anchors)
        resolved_by_analysis[analysis] = filtered
        return analysis
    end

    return {
        analyze_document = analyze_document,
        resolved_issues = M.resolved_issues,
    }
end

return M
