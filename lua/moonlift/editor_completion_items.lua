local pvm = require("moonlift.pvm")
local CompletionContext = require("moonlift.editor_completion_context")
local PositionIndex = require("moonlift.source_position_index")

local M = {}

local scalar_labels = {
    "void", "bool", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "index", "rawptr",
}

local function add(out, E, label, kind, detail, documentation, insert_text, insert_format)
    if not insert_format then
        insert_format = (kind == E.CompletionSnippet or tostring(insert_text or ""):find("${", 1, true)) and E.CompletionInsertSnippet or E.CompletionInsertPlainText
    end
    out[#out + 1] = E.CompletionItem(label, kind, detail or "", documentation or "", insert_text or label, insert_format)
end

function M.Define(T)
    local S = T.MoonSource
    local E = T.MoonEditor
    local H = T.MoonHost
    local Tr = T.MoonTree
    local Context = CompletionContext.Define(T)
    local P = PositionIndex.Define(T)

    local function line_prefix_at(text, offset)
        local start = text:sub(1, offset):match(".*\n()") or 1
        return text:sub(start, offset)
    end

    local function add_tree_types(items, analysis)
        for i = 1, #(analysis.parse.combined.module.items or {}) do
            local item = analysis.parse.combined.module.items[i]
            if pvm.classof(item) == Tr.ItemType and item.t and item.t.name then
                add(items, E, item.t.name, E.CompletionClass, "Moonlift type", "Known Moonlift type")
            end
        end
    end

    local function region_frag_names(analysis)
        local out = {}
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorRegionName then out[#out + 1] = a.label end
        end
        return out
    end

    local function region_frag_by_name(analysis, name)
        local names = region_frag_names(analysis)
        for i = 1, #names do
            if names[i] == name then return analysis.parse.combined.region_frags[i] end
        end
        return nil
    end

    local function completion_prefix(query, analysis)
        local doc = analysis.parse.parts.document
        local hit = P.source_pos_to_offset(P.build_index(doc), query.position.pos)
        if pvm.classof(hit) ~= S.SourceOffsetHit then return "" end
        return line_prefix_at(doc.text, hit.offset)
    end

    local function add_jump_targets(items, analysis)
        local seen = {}
        for i = 1, #analysis.anchors.anchors do
            local a = analysis.anchors.anchors[i]
            if a.kind == S.AnchorContinuationName and not seen[a.label] then
                seen[a.label] = true
                add(items, E, a.label, E.CompletionEvent, "control label", "Jump target")
            end
        end
    end

    local function add_emit_routes(items, analysis, prefix)
        local name = prefix:match("%f[%w_]emit%f[^%w_]%s+([_%a][_%w]*)%s*%(")
        local frag = name and region_frag_by_name(analysis, name)
        if not frag then return false end
        for i = 1, #(frag.conts or {}) do
            local cont = frag.conts[i]
            add(items, E, cont.pretty_name, E.CompletionEvent, "region exit", "Route continuation exit", cont.pretty_name .. " = ${1:block}")
        end
        return true
    end

    local items_phase = pvm.phase("moonlift_editor_completion_items", {
        [E.CompletionQuery] = function(query, analysis)
        local items = {}
        local context = query.context
        if context == E.CompletionTopLevel then
            add(items, E, "struct", E.CompletionSnippet, "Moonlift host struct", "Declare a host-visible struct", "struct ${1:Name}\n    ${2:field}: ${3:i32}\nend")
            add(items, E, "handle", E.CompletionSnippet, "Moonlift handle", "Declare an opaque durable identity handle", "handle ${1:Name} : ${2:u32} invalid ${3:0} end")
            add(items, E, "expose", E.CompletionSnippet, "Moonlift host exposure", "Expose a type/view/ptr with default host facets", "expose ${1:Name}: view(${2:Type})")
            add(items, E, "func", E.CompletionSnippet, "Moonlift function", "Declare a Moonlift function", "func ${1:name}(${2}): ${3:i32}\n    ${4:return 0}\nend")
            add(items, E, "region", E.CompletionSnippet, "Moonlift region fragment", "Declare a region fragment", "region ${1:Name}(${2})\nentry start()\nend\nend")
            add(items, E, "expr", E.CompletionSnippet, "Moonlift expr fragment", "Declare an expression fragment", "expr ${1:Name}(${2}): ${3:i32}\n    ${4:0}\nend")
        elseif context == E.CompletionTypePosition or context == E.CompletionStructField then
            for i = 1, #scalar_labels do
                add(items, E, scalar_labels[i], E.CompletionKeyword, "scalar type", "Moonlift scalar type")
            end
            add(items, E, "ptr", E.CompletionSnippet, "pointer type", "Pointer type", "ptr(${1:T})")
            add(items, E, "view", E.CompletionSnippet, "view type", "Moonlift zero-copy view type", "view(${1:T})")
            add(items, E, "lease", E.CompletionSnippet, "lease access type", "Temporary no-escape access", "lease ptr(${1:T})")
            add(items, E, "owned", E.CompletionSnippet, "owned resource authority", "CFG-tracked resource discharge authority", "owned ${1:HandleRef}")
            add(items, E, "noescape", E.CompletionKeyword, "noescape parameter", "Parameter modifier for non-retained pointer/view access")
            add(items, E, "readonly", E.CompletionKeyword, "readonly store parameter", "Reads and preserves live leases")
            add(items, E, "preserve", E.CompletionKeyword, "preserve store parameter", "May write but keeps live leases valid")
            add(items, E, "invalidate", E.CompletionKeyword, "invalidating store parameter", "May move/free/reuse storage and conflicts with live leases")
            for i = 1, #analysis.parse.combined.decls.decls do
                local d = analysis.parse.combined.decls.decls[i]
                if pvm.classof(d) == H.HostDeclStruct then
                    add(items, E, d.decl.name, E.CompletionStruct, "host struct", "Known host struct")
                end
            end
            add_tree_types(items, analysis)
        elseif context == E.CompletionExposeSubject then
            add(items, E, "view", E.CompletionSnippet, "view exposure", "Expose a zero-copy view", "view(${1:T})")
            add(items, E, "ptr", E.CompletionSnippet, "pointer exposure", "Expose a pointer", "ptr(${1:T})")
            for i = 1, #analysis.parse.combined.decls.decls do
                local d = analysis.parse.combined.decls.decls[i]
                if pvm.classof(d) == H.HostDeclStruct then
                    add(items, E, d.decl.name, E.CompletionStruct, "host struct", "Expose this host struct")
                end
            end
            add_tree_types(items, analysis)
        elseif context == E.CompletionExposeTarget then
            add(items, E, "lua", E.CompletionKeyword, "Lua exposure target", "Generate Lua FFI access")
            add(items, E, "terra", E.CompletionKeyword, "Terra exposure target", "Generate Terra access")
            add(items, E, "c", E.CompletionKeyword, "C exposure target", "Generate C header access")
        elseif context == E.CompletionExposeMode then
            add(items, E, "proxy", E.CompletionKeyword, "proxy exposure", "Generate proxy access")
            add(items, E, "descriptor", E.CompletionKeyword, "descriptor ABI", "Use descriptor-pointer host ABI")
            add(items, E, "pointer", E.CompletionKeyword, "pointer ABI", "Use pointer host ABI")
            add(items, E, "readonly", E.CompletionKeyword, "readonly exposure", "Read-only host access")
            add(items, E, "mutable", E.CompletionKeyword, "mutable exposure", "Mutable host access")
            add(items, E, "checked", E.CompletionKeyword, "checked bounds", "Checked view bounds")
            add(items, E, "unchecked", E.CompletionKeyword, "unchecked bounds", "Unchecked view bounds")
        elseif context == E.CompletionBuiltinPath then
            add(items, E, "host", E.CompletionModule, "moonlift.host", "Moonlift host integration")
            add(items, E, "views", E.CompletionModule, "moonlift.views", "Moonlift zero-copy view helpers")
        elseif context == E.CompletionRegionStatement then
            add(items, E, "jump", E.CompletionKeyword, "control jump", "Jump to a block or continuation")
            add(items, E, "yield", E.CompletionKeyword, "yield", "Yield from a control expression")
            add(items, E, "return", E.CompletionKeyword, "return", "Return from a function")
            add(items, E, "call", E.CompletionKeyword, "region call", "Call a region through a generated function/result boundary")
        elseif context == E.CompletionContinuationArgs then
            local prefix = completion_prefix(query, analysis)
            if not add_emit_routes(items, analysis, prefix) then
                add_jump_targets(items, analysis)
            end
        end
        return pvm.seq(items)
        end,
    }, { node_cache = "none", args_cache = "none" })

    local completion_phase = pvm.phase("moonlift_editor_completion", {
        [E.PositionQuery] = function(position_query, analysis)
        local context = Context.context(position_query, analysis)
        return pvm.seq(pvm.drain(items_phase(E.CompletionQuery(position_query, context), analysis)))
        end,
    }, { node_cache = "none", args_cache = "none" })

    local function items(completion_query, analysis)
        return pvm.drain(items_phase(completion_query, analysis))
    end

    local function complete(position_query, analysis)
        return pvm.drain(completion_phase(position_query, analysis))
    end

    return {
        items_phase = items_phase,
        completion_phase = completion_phase,
        items = items,
        complete = complete,
    }
end

return M
