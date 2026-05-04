local pvm = require("moonlift.pvm")
local Lex = require("moonlift.mlua_lex")

local M = {}

local scalar_names = {
    void = "ScalarVoid",
    bool = "ScalarBool",
    i8 = "ScalarI8", i16 = "ScalarI16", i32 = "ScalarI32", i64 = "ScalarI64",
    u8 = "ScalarU8", u16 = "ScalarU16", u32 = "ScalarU32", u64 = "ScalarU64",
    f32 = "ScalarF32", f64 = "ScalarF64",
    rawptr = "ScalarRawPtr", ptr = "ScalarRawPtr",
    index = "ScalarIndex",
}

local starts_ident_char = Lex.starts_ident_char
local is_boundary = Lex.is_boundary
local skip_space = Lex.skip_space
local skip_hspace = Lex.skip_hspace
local read_ident = Lex.read_ident
local skip_comment_or_string = Lex.skip_comment_or_string
local is_module_start = Lex.is_module_start
local split_top_commas = Lex.split_top_commas
local strip = Lex.strip
local strip_outer_parens = Lex.strip_outer_parens
local line_col = Lex.line_col
local form_extent = Lex.form_extent

local function mk_issue(P, src, msg, offset)
    local line, col = line_col(src, offset or 1)
    return P.ParseIssue(msg, offset or 1, line, col)
end

local function normalize_moonlift_body(src)
    return Lex.moonlift_body(src)
end

function M.Define(T)
    local C, Ty, Tr, H, O, P = T.MoonCore, T.MoonType, T.MoonTree, T.MoonHost, T.MoonOpen, T.MoonParse
    local Parse = require("moonlift.parse").Define(T)

    local function scalar_ty(name)
        local cname = scalar_names[name]
        if not cname then return nil end
        return Ty.TScalar(C[cname])
    end

    local parse_type_expr
    parse_type_expr = function(text)
        text = strip(text):gsub("%s+", " ")
        if text == "bool8" then return Ty.TScalar(C.ScalarBool), H.HostStorageBool(H.HostBoolU8, C.ScalarU8) end
        if text == "bool32" then return Ty.TScalar(C.ScalarBool), H.HostStorageBool(H.HostBoolI32, C.ScalarI32) end
        local stored = text:match("^bool%s+stored%s+(.+)$")
        if stored then
            local storage_ty = scalar_ty(strip(stored))
            local scalar = storage_ty and storage_ty.scalar or C.ScalarI32
            local enc = (scalar == C.ScalarU8 or scalar == C.ScalarI8) and H.HostBoolU8 or H.HostBoolI32
            return Ty.TScalar(C.ScalarBool), H.HostStorageBool(enc, scalar)
        end
        local inner = text:match("^ptr%s*%((.*)%)$")
        if inner then local ty = parse_type_expr(inner); return Ty.TPtr(ty), H.HostStoragePtr(ty) end
        inner = text:match("^view%s*%((.*)%)$")
        if inner then local ty = parse_type_expr(inner); return Ty.TView(ty), H.HostStorageView(ty) end
        inner = text:match("^slice%s*%((.*)%)$")
        if inner then local ty = parse_type_expr(inner); return Ty.TSlice(ty), H.HostStorageSlice(ty) end
        local scalar = scalar_ty(text)
        if scalar then return scalar, H.HostStorageSame end
        return Ty.TNamed(Ty.TypeRefGlobal("", text)), H.HostStorageSame
    end

    local function parse_field_type_attrs(text)
        local attrs = {}
        while true do
            local base, attr = text:match("^(.-)%s+([_%a][_%w]*)%s*$")
            if attr == "readonly" then attrs[#attrs + 1] = H.HostFieldReadonly; text = base
            elseif attr == "mutable" then attrs[#attrs + 1] = H.HostFieldMutable; text = base
            elseif attr == "noalias" then attrs[#attrs + 1] = H.HostFieldNoalias; text = base
            else break end
        end
        local ty, storage = parse_type_expr(text)
        return ty, storage, attrs
    end

    local function layout_id(name) return H.HostLayoutId("mlua." .. name, name) end
    local function field_id(owner, name) return H.HostFieldId("mlua." .. owner .. "." .. name, name) end

    local function parse_struct(src, full_src, offset, issues)
        local name = src:match("^%s*struct%s+([_%a][_%w]*)")
        if not name then issues[#issues + 1] = mk_issue(P, full_src, "expected struct name", offset); return nil, nil end
        if src:find("{", 1, true) then issues[#issues + 1] = mk_issue(P, full_src, "struct uses keyword...end, not braces", offset); return nil, nil end
        if not src:match("%f[%w_]end%f[^%w_]%s*$") then issues[#issues + 1] = mk_issue(P, full_src, "expected end after struct", offset); return nil, nil end
        local repr = H.HostReprC
        local packed = src:match("repr%s*%(%s*packed%s*%(%s*(%d+)%s*%)%s*%)")
        if packed then repr = H.HostReprPacked(tonumber(packed)) end
        local body = src:gsub("^%s*struct%s+[_%a][_%w]*[^\n]*\n?", "", 1):gsub("%s*%f[%w_]end%f[^%w_]%s*$", "")
        local host_fields, tree_fields = {}, {}
        for raw in body:gmatch("[^\n;]+") do
            raw = strip(raw:gsub(",%s*$", ""))
            if raw ~= "" then
                local fname, fty_src = raw:match("^([_%a][_%w]*)%s*:%s*(.-)%s*$")
                if fname then
                    local expose_ty, storage, attrs = parse_field_type_attrs(fty_src)
                    host_fields[#host_fields + 1] = H.HostFieldDecl(field_id(name, fname), fname, expose_ty, storage or H.HostStorageSame, attrs)
                    tree_fields[#tree_fields + 1] = Ty.FieldDecl(fname, expose_ty)
                else
                    issues[#issues + 1] = mk_issue(P, full_src, "invalid struct field: " .. raw, offset)
                end
            end
        end
        return H.HostDeclStruct(H.HostStructDecl(layout_id(name), name, repr, host_fields)), Tr.ItemType(Tr.TypeDeclStruct(name, tree_fields))
    end

    local function parse_expose_subject(text)
        text = strip(text)
        local inner = text:match("^ptr%s*%((.*)%)$")
        if inner then local ty = parse_type_expr(inner); return H.HostExposePtr(ty) end
        inner = text:match("^view%s*%((.*)%)$")
        if inner then local ty = parse_type_expr(inner); return H.HostExposeView(ty) end
        local ty = parse_type_expr(text)
        return H.HostExposeType(ty)
    end

    local function proxy_kind_for_subject(subject)
        local cls = pvm.classof(subject)
        if cls == H.HostExposePtr then return H.HostProxyPtr end
        if cls == H.HostExposeView then return H.HostProxyView end
        return H.HostProxyTypedRecord
    end

    local function target_for_word(word)
        if word == "lua" then return H.HostExposeLua end
        if word == "terra" then return H.HostExposeTerra end
        if word == "c" then return H.HostExposeC end
        if word == "moonlift" then return H.HostExposeMoonlift end
        return nil
    end

    local function default_abi_for_target(subject, target)
        local cls = pvm.classof(subject)
        if cls == H.HostExposeView and (target == H.HostExposeC or target == H.HostExposeTerra) then return H.HostExposeAbiDescriptor end
        if cls == H.HostExposePtr and (target == H.HostExposeC or target == H.HostExposeTerra) then return H.HostExposeAbiPointer end
        return H.HostExposeAbiDefault
    end

    local function parse_expose_facet(subject, target, words)
        local abi = default_abi_for_target(subject, target)
        local mutability = H.HostReadonly
        local bounds = target == H.HostExposeLua and H.HostBoundsChecked or H.HostBoundsUnchecked
        local cache = H.HostProxyCacheNone
        local proxy_kind = proxy_kind_for_subject(subject)
        local materialize = nil
        local opaque = nil
        for i = 1, #words do
            local word = words[i]
            if word == "pointer" or word == "ptr" then abi = H.HostExposeAbiPointer
            elseif word == "descriptor" then abi = H.HostExposeAbiDescriptor
            elseif word == "data_len_stride" then abi = H.HostExposeAbiDataLenStride
            elseif word == "expanded" or word == "expanded_scalars" then abi = H.HostExposeAbiExpandedScalars
            elseif word == "proxy" then proxy_kind = proxy_kind_for_subject(subject)
            elseif word == "record" or word == "typed_record" then proxy_kind = H.HostProxyTypedRecord
            elseif word == "buffer_view" then proxy_kind = H.HostProxyBufferView
            elseif word == "opaque" then opaque = "opaque exposure requested"
            elseif word == "readonly" then mutability = H.HostReadonly
            elseif word == "mutable" then mutability = H.HostMutable
            elseif word == "interior_mutable" then mutability = H.HostInteriorMutable
            elseif word == "checked" then bounds = H.HostBoundsChecked
            elseif word == "unchecked" then bounds = H.HostBoundsUnchecked
            elseif word == "lazy" or word == "cache_lazy" then cache = H.HostProxyCacheLazy
            elseif word == "eager" or word == "cache_eager" then cache = H.HostProxyCacheEager
            elseif word == "none" or word == "cache_none" then cache = H.HostProxyCacheNone
            elseif word == "table" or word == "eager_table" then materialize = H.HostMaterializeProjectedFields
            elseif word == "full_copy" then materialize = H.HostMaterializeFullCopy
            elseif word == "borrowed_view" then materialize = H.HostMaterializeBorrowedView end
        end
        local mode
        if opaque then mode = H.HostExposeOpaque(opaque)
        elseif materialize then mode = H.HostExposeEagerTable(materialize)
        else mode = H.HostExposeProxy(proxy_kind, cache, mutability, bounds) end
        return H.HostExposeFacet(target, abi, mode)
    end

    local function words_in(text)
        local words = {}
        for word in tostring(text or ""):gmatch("[_%a][_%w]*") do words[#words + 1] = word end
        return words
    end

    local function default_expose_facets(subject)
        return {
            parse_expose_facet(subject, H.HostExposeLua, {}),
            parse_expose_facet(subject, H.HostExposeTerra, {}),
            parse_expose_facet(subject, H.HostExposeC, {}),
        }
    end

    local function parse_expose_facets(subject, body, full_src, offset, issues)
        body = strip(body or "")
        if body == "" then return default_expose_facets(subject) end
        if body:find("{", 1, true) or body:find("}", 1, true) then
            issues[#issues + 1] = mk_issue(P, full_src, "expose facets use keyword...end, not braces", offset)
            return nil
        end
        local facets = {}
        local seen = {}
        for _, line in ipairs(split_top_commas(body:gsub("\n", ","))) do
            line = strip(line)
            if line ~= "" then
                local words = words_in(line)
                local target = target_for_word(words[1])
                if target and not seen[words[1]] then
                    seen[words[1]] = true
                    local policy = {}
                    for i = 2, #words do policy[#policy + 1] = words[i] end
                    facets[#facets + 1] = parse_expose_facet(subject, target, policy)
                else
                    issues[#issues + 1] = mk_issue(P, full_src, "expected expose target line", offset)
                    return nil
                end
            end
        end
        if #facets == 0 then return default_expose_facets(subject) end
        return facets
    end

    local function parse_expose(src, full_src, offset, issues)
        if src:find("{", 1, true) then issues[#issues + 1] = mk_issue(P, full_src, "expose uses keyword...end, not braces", offset); return nil end
        local public_name, subject_src = src:match("^%s*expose%s+([_%a][_%w]*)%s*:%s*([^\n]+)")
        if not subject_src or not public_name then issues[#issues + 1] = mk_issue(P, full_src, "expected expose Name: subject", offset); return nil end
        subject_src = strip(subject_src)
        local body = ""
        if src:match("%f[%w_]end%f[^%w_]%s*$") then
            body = src:gsub("^%s*expose%s+[_%a][_%w]*%s*:%s*[^\n]+\n?", "", 1):gsub("%s*%f[%w_]end%f[^%w_]%s*$", "")
        end
        local subject = parse_expose_subject(subject_src)
        local facets = parse_expose_facets(subject, body, full_src, offset, issues)
        if not facets then return nil end
        return H.HostDeclExpose(H.HostExposeDecl(subject, public_name, facets))
    end

    local function append_parsed_module(source, items, region_frags_by_name, expr_frags_by_name, issues)
        local parsed = Parse.parse_module(normalize_moonlift_body(source), { region_frags = region_frags_by_name, expr_frags = expr_frags_by_name })
        for i = 1, #parsed.issues do issues[#issues + 1] = parsed.issues[i] end
        if #parsed.issues == 0 then
            for i = 1, #parsed.module.items do items[#items + 1] = parsed.module.items[i] end
        end
        return parsed
    end

    local function parse_module_items(source, items, region_frags_by_name, expr_frags_by_name, issues)
        append_parsed_module(source, items, region_frags_by_name, expr_frags_by_name, issues)
    end

    local function parse_func_form(source, decls, items, region_frags_by_name, expr_frags_by_name, issues)
        local prefix, owner, method_name, rest = source:match("^%s*(export%s+)func%s+([_%a][_%w]*)%s*:%s*([_%a][_%w]*)(.*)$")
        if not owner then prefix, owner, method_name, rest = "", source:match("^%s*func%s+([_%a][_%w]*)%s*:%s*([_%a][_%w]*)(.*)$") end
        if not owner then
            parse_module_items(source, items, region_frags_by_name, expr_frags_by_name, issues)
            return
        end
        local func_name = owner .. "_" .. method_name
        local normalized = (prefix or "") .. "func " .. func_name .. rest
        local before = #items
        local parsed = append_parsed_module(normalized, items, region_frags_by_name, expr_frags_by_name, issues)
        if #parsed.issues == 0 and #items > before then
            local item = items[before + 1]
            if pvm.classof(item) == Tr.ItemFunc then
                decls[#decls + 1] = H.HostDeclAccessor(H.HostAccessorMoonlift(owner, method_name, item.func))
            end
        end
    end

    local function parse_region(source, regions, region_frags_by_name, expr_frags_by_name, issues)
        local parsed = Parse.parse_region_frag(normalize_moonlift_body(source), { region_frags = region_frags_by_name, expr_frags = expr_frags_by_name })
        for i = 1, #parsed.issues do issues[#issues + 1] = parsed.issues[i] end
        if #parsed.issues == 0 and parsed.value then
            regions[#regions + 1] = parsed.value.frag
            local name = source:match("^%s*region%s+([_%a][_%w]*)")
            if name then region_frags_by_name[name] = parsed.value end
        end
    end

    local function parse_expr_frag(source, exprs, expr_frags_by_name, issues)
        local parsed = Parse.parse_expr_frag(normalize_moonlift_body(source))
        for i = 1, #parsed.issues do issues[#issues + 1] = parsed.issues[i] end
        if #parsed.issues == 0 and parsed.value then
            exprs[#exprs + 1] = parsed.value.frag
            local name = source:match("^%s*expr%s+([_%a][_%w]*)")
            if name then expr_frags_by_name[name] = parsed.value end
        end
    end

    local function parse_module_body(body, items, regions, exprs, region_frags_by_name, expr_frags_by_name, issues)
        local kept = {}
        local i = 1
        while i <= #body do
            local skipped = skip_comment_or_string(body, i)
            if skipped then
                kept[#kept + 1] = body:sub(i, skipped - 1)
                i = skipped
            elseif body:sub(i, i):match("[A-Za-z_]") then
                local word, j = read_ident(body, i)
                local effective_word = word
                if word == "export" then
                    local k = skip_space(body, j)
                    if body:sub(k, k + 3) == "func" and is_boundary(body, k, 4) then effective_word = "export func" end
                end
                if (effective_word == "func" or effective_word == "export func") and is_boundary(body, i, #word) then
                    local e = form_extent(body, i, effective_word)
                    if not e then
                        issues[#issues + 1] = mk_issue(P, body, "unterminated module-local form: " .. effective_word, i)
                        break
                    end
                    kept[#kept + 1] = body:sub(i, e)
                    i = e + 1
                elseif (word == "region" or word == "expr") and is_boundary(body, i, #word) then
                    local e = form_extent(body, i, word)
                    if not e then
                        issues[#issues + 1] = mk_issue(P, body, "unterminated module-local form: " .. word, i)
                        break
                    end
                    local form = body:sub(i, e)
                    if word == "region" then parse_region(form, regions, region_frags_by_name, expr_frags_by_name, issues)
                    else parse_expr_frag(form, exprs, expr_frags_by_name, issues) end
                    kept[#kept + 1] = "\n"
                    i = e + 1
                else
                    kept[#kept + 1] = body:sub(i, j - 1)
                    i = j
                end
            else
                kept[#kept + 1] = body:sub(i, i)
                i = i + 1
            end
        end
        parse_module_items(table.concat(kept), items, region_frags_by_name, expr_frags_by_name, issues)
    end

    local function parse_source(node)
        local src = node.source
        local issues, decls, items, regions, exprs = {}, {}, {}, {}, {}
        local region_frags_by_name, expr_frags_by_name = {}, {}
        local i = 1
        while i <= #src do
            local skipped = skip_comment_or_string(src, i)
            if skipped then
                i = skipped
            elseif src:sub(i, i):match("[A-Za-z_]") then
                local word, j = read_ident(src, i)
                if word == "export" then
                    local k = skip_space(src, j)
                    local w2 = src:sub(k, k + 3)
                    if w2 == "func" and is_boundary(src, k, 4) then word, i = "export func", i else i = j end
                end
                local is_form = word == "struct" or word == "expose" or word == "region" or word == "expr" or word == "module" or word == "func" or word == "export func"
                if word == "module" and not is_module_start(src, i) then is_form = false end
                if is_form then
                    local e = form_extent(src, i, word)
                    if not e then
                        issues[#issues + 1] = mk_issue(P, src, "unterminated .mlua form: " .. word, i)
                        break
                    end
                    local form = src:sub(i, e)
                    if word == "struct" then
                        local decl, item = parse_struct(form, src, i, issues)
                        if decl then decls[#decls + 1] = decl end
                        if item then items[#items + 1] = item end
                    elseif word == "expose" then
                        local decl = parse_expose(form, src, i, issues)
                        if decl then decls[#decls + 1] = decl end
                    elseif word == "region" then
                        parse_region(form, regions, region_frags_by_name, expr_frags_by_name, issues)
                    elseif word == "expr" then
                        parse_expr_frag(form, exprs, expr_frags_by_name, issues)
                    elseif word == "module" then
                        local body = form:match("^%s*module%s+[_%a][_%w]*%s*{%s*([%s%S]-)%s*}%s*$")
                        if not body then body = form:match("^%s*module%s*{%s*([%s%S]-)%s*}%s*$") end
                        if not body then
                            body = form:gsub("^%s*module%s*", ""):gsub("%s*end%s*$", "")
                            local maybe_name, rest = body:match("^%s*([_%a][_%w]*)(.*)$")
                            if maybe_name and not ({ export = true, extern = true, func = true, const = true, static = true, import = true, type = true, region = true, expr = true })[maybe_name] then
                                body = rest
                            end
                        end
                        parse_module_body(body, items, regions, exprs, region_frags_by_name, expr_frags_by_name, issues)
                    elseif word == "func" or word == "export func" then
                        parse_func_form(form, decls, items, region_frags_by_name, expr_frags_by_name, issues)
                    else
                        parse_module_items(form, items, region_frags_by_name, expr_frags_by_name, issues)
                    end
                    i = e + 1
                else
                    i = j
                end
            else
                i = i + 1
            end
        end
        return H.MluaParseResult(H.HostDeclSet(decls), Tr.Module(Tr.ModuleSurface, items), regions, exprs, issues)
    end

    local mlua_parse = pvm.phase("moonlift_mlua_parse", {
        [H.MluaSource] = function(self)
            return pvm.once(parse_source(self))
        end,
    })

    return {
        mlua_parse = mlua_parse,
        parse = function(source, name)
            return pvm.one(mlua_parse(H.MluaSource(name or "<mlua>", source)))
        end,
        parse_type_expr = parse_type_expr,
    }
end

return M
