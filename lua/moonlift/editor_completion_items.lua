local pvm = require("moonlift.pvm")
local CompletionContext = require("moonlift.editor_completion_context")

local M = {}

local scalar_labels = {
    "void", "bool", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "index", "rawptr",
}

local function add(out, E, label, kind, detail, documentation, insert_text)
    out[#out + 1] = E.CompletionItem(label, kind, detail or "", documentation or "", insert_text or label)
end

function M.Define(T)
    local E = T.MoonEditor
    local H = T.MoonHost
    local Context = CompletionContext.Define(T)

    local items_phase = pvm.phase("moonlift_editor_completion_items", {
        [E.CompletionQuery] = function(query, analysis)
        local items = {}
        local context = query.context
        if context == E.CompletionTopLevel then
            add(items, E, "struct", E.CompletionSnippet, "Moonlift host struct", "Declare a host-visible struct", "struct ${1:Name}\n    ${2:field}: ${3:i32}\nend")
            add(items, E, "expose", E.CompletionSnippet, "Moonlift host exposure", "Expose a type/view/ptr with default host facets", "expose ${1:Name}: view(${2:Type})")
            add(items, E, "func", E.CompletionSnippet, "Moonlift function", "Declare a Moonlift function", "func ${1:name}(${2}) -> ${3:i32}\n    ${4:return 0}\nend")
            add(items, E, "module", E.CompletionSnippet, "Moonlift module island", "Declare a module island", "module\n    ${1}\nend")
            add(items, E, "region", E.CompletionSnippet, "Moonlift region fragment", "Declare a region fragment", "region ${1:Name}(${2})\nentry start()\nend\nend")
            add(items, E, "expr", E.CompletionSnippet, "Moonlift expr fragment", "Declare an expression fragment", "expr ${1:Name}(${2}) -> ${3:i32}\n    ${4:0}\nend")
        elseif context == E.CompletionTypePosition or context == E.CompletionStructField then
            for i = 1, #scalar_labels do
                add(items, E, scalar_labels[i], E.CompletionKeyword, "scalar type", "Moonlift scalar type")
            end
            add(items, E, "ptr", E.CompletionSnippet, "pointer type", "Pointer type", "ptr(${1:T})")
            add(items, E, "view", E.CompletionSnippet, "view type", "Moonlift zero-copy view type", "view(${1:T})")
            for i = 1, #analysis.parse.combined.decls.decls do
                local d = analysis.parse.combined.decls.decls[i]
                if pvm.classof(d) == H.HostDeclStruct then
                    add(items, E, d.decl.name, E.CompletionStruct, "host struct", "Known host struct")
                end
            end
        elseif context == E.CompletionExposeSubject then
            add(items, E, "view", E.CompletionSnippet, "view exposure", "Expose a zero-copy view", "view(${1:T})")
            add(items, E, "ptr", E.CompletionSnippet, "pointer exposure", "Expose a pointer", "ptr(${1:T})")
            for i = 1, #analysis.parse.combined.decls.decls do
                local d = analysis.parse.combined.decls.decls[i]
                if pvm.classof(d) == H.HostDeclStruct then
                    add(items, E, d.decl.name, E.CompletionStruct, "host struct", "Expose this host struct")
                end
            end
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
            add(items, E, "json", E.CompletionModule, "moonlift.json", "Indexed tape JSON library")
            add(items, E, "host", E.CompletionModule, "moonlift.host", "Moonlift host integration")
            add(items, E, "views", E.CompletionModule, "moonlift.views", "Moonlift zero-copy view helpers")
        elseif context == E.CompletionRegionStatement then
            add(items, E, "jump", E.CompletionKeyword, "control jump", "Jump to a block or continuation")
            add(items, E, "yield", E.CompletionKeyword, "yield", "Yield from a control expression")
            add(items, E, "return", E.CompletionKeyword, "return", "Return from a function")
        end
        return pvm.seq(items)
        end,
    }, { args_cache = "full" })

    local completion_phase = pvm.phase("moonlift_editor_completion", {
        [E.PositionQuery] = function(position_query, analysis)
        local context = Context.context(position_query, analysis)
        return pvm.seq(pvm.drain(items_phase(E.CompletionQuery(position_query, context), analysis)))
        end,
    }, { args_cache = "full" })

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
