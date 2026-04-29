local pvm = require("moonlift.pvm")
local PositionIndex = require("moonlift.source_position_index")

local M = {}

local scalar_type_names = nil

local function starts_ident_char(c)
    return c and c:match("[%w_]") ~= nil
end

local function is_boundary(src, i, n)
    local before = i > 1 and src:sub(i - 1, i - 1) or ""
    local after = src:sub(i + n, i + n)
    return not starts_ident_char(before) and not starts_ident_char(after)
end

local function read_ident(src, i)
    if not src:sub(i, i):match("[A-Za-z_]") then return nil, i end
    local s = i
    i = i + 1
    while i <= #src and src:sub(i, i):match("[%w_]") do i = i + 1 end
    return src:sub(s, i - 1), i
end

local function skip_space(src, i)
    while i <= #src do
        local c = src:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" and c ~= "\n" then break end
        i = i + 1
    end
    return i
end

local function skip_hspace(src, i)
    while i <= #src do
        local c = src:sub(i, i)
        if c ~= " " and c ~= "\t" and c ~= "\r" then break end
        i = i + 1
    end
    return i
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

local function line_prefix_has_word(src, i, word)
    local line_start = src:sub(1, i - 1):match(".*\n()") or 1
    local prefix = src:sub(line_start, i - 1)
    return prefix:match("%f[%w_]" .. word .. "%f[^%w_]") ~= nil
end

local function range_contains(range, offset)
    return offset >= range.start_offset and offset <= range.stop_offset
end

local function strict_range_contains(range, offset)
    return offset >= range.start_offset and offset < range.stop_offset
end

local function range_size(range)
    return range.stop_offset - range.start_offset
end

local function same_uri(a, b)
    return a == b or (a and b and a.text == b.text)
end

local function sort_anchors(a, b)
    if a.range.start_offset ~= b.range.start_offset then return a.range.start_offset < b.range.start_offset end
    return a.range.stop_offset < b.range.stop_offset
end

local function line_next_offset(text, offset)
    local nl = text:find("\n", offset + 1, true)
    return nl or #text
end

local function find_matching_paren(text, paren_offset)
    local depth = 0
    local i = paren_offset + 1
    while i <= #text do
        local skipped = skip_comment_or_string(text, i)
        if skipped then
            i = skipped
        else
            local c = text:sub(i, i)
            if c == "(" then depth = depth + 1
            elseif c == ")" then
                depth = depth - 1
                if depth == 0 then return i - 1 end
            end
            i = i + 1
        end
    end
    return nil
end

local function left_of_assignment(text, anchor)
    local i = skip_hspace(text, anchor.range.stop_offset + 1)
    if text:sub(i, i) ~= "=" then return false end
    if text:sub(i + 1, i + 1) == "=" then return false end
    return true
end

local function jump_arg_target_label(text, anchor)
    if not left_of_assignment(text, anchor) then return nil end
    local prefix = text:sub(1, anchor.range.start_offset)
    local best_label, best_paren = nil, nil
    for _, label, paren_pos in prefix:gmatch("()%f[%w_]jump%f[^%w_]%s+([_%a][_%w]*)%s*()") do
        local p = skip_hspace(prefix, paren_pos)
        if prefix:sub(p, p) == "(" then
            best_label, best_paren = label, p - 1
        end
    end
    if not best_label then return nil end
    local close = find_matching_paren(text, best_paren)
    if close and anchor.range.start_offset < close then return best_label end
    return nil
end

local function scope_kind_for_word(E, word)
    if word == "func" then return E.BindingScopeFunction end
    if word == "region" then return E.BindingScopeRegion end
    if word == "expr" then return E.BindingScopeExpr end
    if word == "block" or word == "entry" or word == "loop" then return E.BindingScopeControlBlock end
    if word == "if" or word == "then" or word == "else" or word == "elseif" or word == "switch" or word == "do" then return E.BindingScopeBranch end
    if word == "module" then return E.BindingScopeModule end
    return E.BindingScopeOpaque(word)
end

local scope_open_words = {
    func = true, region = true, expr = true, block = true, entry = true,
    ["if"] = true, switch = true, module = true,
}

function M.Define(T)
    local S = T.Moon2Source
    local C = T.Moon2Core
    local Ty = T.Moon2Type
    local B = T.Moon2Bind
    local E = T.Moon2Editor
    local Mlua = T.Moon2Mlua
    local P = PositionIndex.Define(T)

    scalar_type_names = scalar_type_names or {
        void = C.ScalarVoid, bool = C.ScalarBool,
        i8 = C.ScalarI8, i16 = C.ScalarI16, i32 = C.ScalarI32, i64 = C.ScalarI64,
        u8 = C.ScalarU8, u16 = C.ScalarU16, u32 = C.ScalarU32, u64 = C.ScalarU64,
        f32 = C.ScalarF32, f64 = C.ScalarF64,
        rawptr = C.ScalarRawPtr, index = C.ScalarIndex,
        bool8 = C.ScalarBool, bool32 = C.ScalarBool,
    }

    local function make_range(index, start_offset, stop_offset)
        if start_offset < 0 then start_offset = 0 end
        if stop_offset < start_offset then stop_offset = start_offset end
        return assert(P.range_from_offsets(index, start_offset, stop_offset))
    end

    local function type_after_anchor(analysis, anchor)
        local text = analysis.parse.parts.document.text
        local tail = text:sub(anchor.range.stop_offset + 1, math.min(#text, anchor.range.stop_offset + 120))
        local name = tail:match("^%s*:%s*([_%a][_%w]*)")
        if name and scalar_type_names[name] then return Ty.TScalar(scalar_type_names[name]) end
        if name then return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) }))) end
        return Ty.TScalar(C.ScalarVoid)
    end

    local function add_scope(scopes, index, id_text, parent_text, kind, start_offset, stop_offset)
        local fact = E.BindingScopeFact(E.BindingScopeId(id_text), E.BindingScopeId(parent_text), kind, make_range(index, start_offset, stop_offset))
        scopes[#scopes + 1] = fact
        return { id = fact.id, parent = fact.parent, kind = kind, range = fact.range }
    end

    local function build_scopes(analysis, index)
        local text = analysis.parse.parts.document.text
        local scopes, records = {}, {}
        local doc_record = add_scope(scopes, index, "document", "document", E.BindingScopeDocument, 0, #text)
        records[#records + 1] = doc_record
        local island_anchors = {}
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorHostedIsland then island_anchors[#island_anchors + 1] = a end
        end
        table.sort(island_anchors, sort_anchors)
        for i = 1, #island_anchors do
            local island = island_anchors[i]
            local island_id = "scope." .. island.id.text
            local island_record = add_scope(scopes, index, island_id, "document", E.BindingScopeIsland, island.range.start_offset, island.range.stop_offset)
            records[#records + 1] = island_record
            local stack = { island_record }
            local pending = {}
            local limit = island.range.stop_offset
            local function close_pending(stop_offset)
                local rec = table.remove(pending)
                if not rec then return nil end
                rec.range = make_range(index, rec.range.start_offset, math.max(rec.range.start_offset, stop_offset))
                records[#records + 1] = rec
                scopes[#scopes + 1] = E.BindingScopeFact(rec.id, rec.parent, rec.kind, rec.range)
                table.remove(stack)
                return rec
            end
            local function open_pending(word, start_offset, parent)
                parent = parent or stack[#stack] or island_record
                local rec = {
                    id = E.BindingScopeId("scope.local." .. tostring(start_offset) .. "." .. word),
                    parent = parent.id,
                    kind = scope_kind_for_word(E, word),
                    range = make_range(index, start_offset, limit),
                    word = word,
                    branch = word == "then" or word == "else" or word == "elseif",
                }
                pending[#pending + 1] = rec
                stack[#stack + 1] = rec
                return rec
            end
            local pos = island.range.start_offset + 1
            while pos <= limit do
                local skipped = skip_comment_or_string(text, pos)
                if skipped then
                    pos = skipped
                elseif text:sub(pos, pos):match("[A-Za-z_]") then
                    local word, after = read_ident(text, pos)
                    if is_boundary(text, pos, #word) then
                        if word == "end" then
                            if pending[#pending] and pending[#pending].branch then close_pending(pos - 1) end
                            close_pending(after - 1)
                        elseif word == "then" then
                            if pending[#pending] and pending[#pending].word == "if" then open_pending("then", after - 1, pending[#pending]) end
                        elseif word == "else" or word == "elseif" then
                            if pending[#pending] and pending[#pending].branch then close_pending(pos - 1) end
                            local parent = stack[#stack]
                            if parent and parent.word == "if" then open_pending(word, after - 1, parent) end
                        elseif scope_open_words[word] or word == "do" or word == "loop" then
                            local opens = scope_open_words[word]
                            if word == "do" then opens = not line_prefix_has_word(text, pos, "switch") end
                            if word == "loop" then
                                local next_word = read_ident(text, skip_space(text, after))
                                opens = next_word == "counted"
                            end
                            if opens then open_pending(word, pos - 1) end
                        end
                    end
                    pos = after
                else
                    pos = pos + 1
                end
            end
            while #pending > 0 do
                close_pending(island.range.stop_offset)
            end
        end
        return scopes, records
    end

    local function innermost_scope(records, uri, offset)
        local best = nil
        for i = 1, #records do
            local r = records[i].range
            if same_uri(r.uri, uri) and range_contains(r, offset) then
                if not best or range_size(r) <= range_size(best.range) then best = records[i] end
            end
        end
        return best or records[1]
    end

    local function visible_stop_for_scope(scope)
        return scope and scope.range.stop_offset or 0
    end

    local function binding_class_for_anchor(scope, anchor, ordinal)
        local entry_label = anchor.id.text:match("cont%.param%.entry%.([_%a][_%w]*)%.")
        local block_label = anchor.id.text:match("cont%.param%.block%.([_%a][_%w]*)%.")
        local slot_label = anchor.id.text:match("cont%.param%.slot%.([_%a][_%w]*)%.")
        local region_id = scope and scope.id.text or "document"
        if entry_label then return B.BindingClassEntryBlockParam(region_id, entry_label, ordinal or 0) end
        if block_label then return B.BindingClassBlockParam(region_id, block_label, ordinal or 0) end
        if slot_label then return B.BindingClassContParam(region_id, slot_label, ordinal or 0) end
        if anchor.kind == S.AnchorParamName then return B.BindingClassArg(ordinal or 0) end
        if anchor.id.text:match("local%.var%.") then return B.BindingClassLocalCell end
        return B.BindingClassLocalValue
    end

    local function class_key_for_anchor(anchor)
        return anchor.id.text:match("cont%.param%.entry%.([_%a][_%w]*)%.") and ("entry:" .. anchor.id.text:match("cont%.param%.entry%.([_%a][_%w]*)%."))
            or anchor.id.text:match("cont%.param%.block%.([_%a][_%w]*)%.") and ("block:" .. anchor.id.text:match("cont%.param%.block%.([_%a][_%w]*)%."))
            or anchor.id.text:match("cont%.param%.slot%.([_%a][_%w]*)%.") and ("cont:" .. anchor.id.text:match("cont%.param%.slot%.([_%a][_%w]*)%."))
            or (anchor.kind.kind or tostring(anchor.kind))
    end

    local function binding_visible_start(text, anchor, cls)
        if cls == B.BindingClassContParam then return anchor.range.stop_offset end
        return line_next_offset(text, anchor.range.stop_offset)
    end

    local function build_bindings(analysis, index, scope_records)
        local text = analysis.parse.parts.document.text
        local anchors = {}
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorParamName or a.kind == S.AnchorLocalName then anchors[#anchors + 1] = a end
        end
        table.sort(anchors, sort_anchors)
        local out, ordinal_by_key = {}, {}
        for i = 1, #anchors do
            local a = anchors[i]
            local scope = innermost_scope(scope_records, a.range.uri, a.range.start_offset)
            local key = scope.id.text .. ":" .. class_key_for_anchor(a)
            ordinal_by_key[key] = (ordinal_by_key[key] or 0) + 1
            local class = binding_class_for_anchor(scope, a, ordinal_by_key[key])
            local start = binding_visible_start(text, a, pvm.classof(class))
            local stop = visible_stop_for_scope(scope)
            if pvm.classof(class) == B.BindingClassContParam then stop = start end
            local binding = B.Binding(C.Id("editor.binding." .. a.id.text), a.label, type_after_anchor(analysis, a), class)
            out[#out + 1] = E.ScopedBinding(binding, scope.id, make_range(index, start, stop), a)
        end
        return out
    end

    local function binding_class_label(binding)
        local cls = pvm.classof(binding.class)
        if cls == B.BindingClassBlockParam then return binding.class.block_name end
        if cls == B.BindingClassEntryBlockParam then return binding.class.block_name end
        if cls == B.BindingClassContParam then return binding.class.cont_name end
        return nil
    end

    local function containing_scope_score(scopes_by_id, scope_id, offset)
        local scope = scopes_by_id[scope_id]
        local best = nil
        local guard = 0
        while scope and guard < 64 do
            guard = guard + 1
            if strict_range_contains(scope.range, offset) then
                local size = range_size(scope.range)
                if not best or size < best then best = size end
            end
            if scope.parent.text == scope.id.text then break end
            scope = scopes_by_id[scope.parent.text]
        end
        return best
    end

    local function target_param_binding(scopes_by_id, scoped_bindings, anchor, target_label)
        local best, best_score = nil, nil
        for i = 1, #scoped_bindings do
            local sb = scoped_bindings[i]
            local b = sb.binding
            local cls = pvm.classof(b.class)
            if b.name == anchor.label and (cls == B.BindingClassBlockParam or cls == B.BindingClassEntryBlockParam or cls == B.BindingClassContParam) and binding_class_label(b) == target_label then
                local score = containing_scope_score(scopes_by_id, sb.scope.text, anchor.range.start_offset)
                if score and (not best_score or score < best_score or (score == best_score and sb.anchor.range.start_offset > best.anchor.range.start_offset)) then
                    best, best_score = sb, score
                elseif not best and sb.anchor.range.start_offset <= anchor.range.start_offset then
                    best = sb
                end
            end
        end
        return best
    end

    local function normal_binding_for_use(scoped_bindings, anchor)
        local best = nil
        for i = 1, #scoped_bindings do
            local sb = scoped_bindings[i]
            if sb.binding.name == anchor.label and pvm.classof(sb.binding.class) ~= B.BindingClassContParam and strict_range_contains(sb.visible_range, anchor.range.start_offset) then
                if not best or sb.anchor.range.start_offset > best.anchor.range.start_offset then best = sb end
            end
        end
        return best
    end

    local function build_resolutions(analysis, scope_records, scoped_bindings)
        local text = analysis.parse.parts.document.text
        local scopes_by_id = {}
        for i = 1, #scope_records do scopes_by_id[scope_records[i].id.text] = scope_records[i] end
        local out = {}
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorBindingUse then
                local scope = innermost_scope(scope_records, a.range.uri, a.range.start_offset)
                local target = jump_arg_target_label(text, a)
                local role = target and E.BindingWrite or (left_of_assignment(text, a) and E.BindingWrite or E.BindingRead)
                local use = E.BindingUseSite(a, role, scope.id)
                local binding = target and target_param_binding(scopes_by_id, scoped_bindings, a, target) or normal_binding_for_use(scoped_bindings, a)
                if binding then out[#out + 1] = E.BindingResolved(use, binding)
                else out[#out + 1] = E.BindingUnresolved(use, "unresolved binding: " .. a.label) end
            end
        end
        return out
    end

    local scope_report_phase = pvm.phase("moon2_editor_binding_scope_report", {
        [Mlua.DocumentAnalysis] = function(analysis)
            local index = P.build_index(analysis.parse.parts.document)
            local scopes, scope_records = build_scopes(analysis, index)
            local bindings = build_bindings(analysis, index, scope_records)
            local resolutions = build_resolutions(analysis, scope_records, bindings)
            return pvm.once(E.BindingScopeReport(scopes, bindings, resolutions))
        end,
    })

    local function report(analysis)
        return pvm.one(scope_report_phase(analysis))
    end

    return {
        scope_report_phase = scope_report_phase,
        report = report,
    }
end

return M
