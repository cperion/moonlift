local pvm = require("moonlift.pvm")

local M = {}

local function line_prefix(text, line0, char0)
    local pos, cur = 1, 0
    while cur < line0 do
        local nl = text:find("\n", pos, true)
        if not nl then return "" end
        pos = nl + 1; cur = cur + 1
    end
    local e = text:find("\n", pos, true) or (#text + 1)
    local line = text:sub(pos, e - 1)
    return line:sub(1, math.max(0, math.min(#line, char0 or 0)))
end

local function item(L, label, detail, insert_text, kind)
    return L.CompletionItem(label, detail or "", insert_text or label, kind or 14)
end

function M.Define(T)
    require("moonlift.lsp_asdl").Define(T)
    local L = T.MoonliftLsp
    local Scan = require("moonlift.lsp_scan").Define(T)

    local phase = pvm.phase("moonlift_lsp_completion", {
        [L.CompletionQuery] = function(self)
            local out = {}
            local prefix = line_prefix(self.document.text, self.position.line, self.position.character)
            local type_context = prefix:match(":%s*[%w_]*$") or prefix:match("%-%>%s*[%w_]*$") or prefix:match("%f[%w_]view%s*%(%s*[%w_]*$") or prefix:match("%f[%w_]ptr%s*%(%s*[%w_]*$")
            if type_context then
                for _, label in ipairs({ "i32", "i64", "u8", "u32", "bool", "bool8", "bool32", "index", "ptr(...)", "view(...)" }) do
                    out[#out + 1] = item(L, label, "Moonlift type", label, 7)
                end
                for _, island in ipairs(Scan.scan(self.document)) do
                    if island.kind == L.IslandStruct then out[#out + 1] = item(L, island.name, "struct", island.name, 7) end
                end
            elseif prefix:match("expose.-{%s*[%w_]*$") then
                for _, label in ipairs({ "lua", "terra", "c", "readonly", "mutable", "checked", "unchecked" }) do out[#out + 1] = item(L, label, "expose clause", label, 14) end
            else
                out[#out + 1] = item(L, "struct", "Moonlift host struct", "struct Name {\n    field: i32\n}", 14)
                out[#out + 1] = item(L, "expose", "Moonlift host exposure", "expose view(Name) as Names {\n    lua readonly checked\n}", 14)
                out[#out + 1] = item(L, "func", "Moonlift function", "func name(x: i32) -> i32 {\n    return x\n}", 14)
                out[#out + 1] = item(L, "module", "Moonlift module", "module Name {\n    export func f() -> i32 {\n        return 0\n    }\n}", 14)
                out[#out + 1] = item(L, "region", "Moonlift region fragment", "region Name(x: i32; done: cont(y: i32))\nentry start()\n    jump done(y = x)\nend\nend", 14)
                out[#out + 1] = item(L, "expr", "Moonlift expression fragment", "expr Name(x: i32) -> i32\n    x\nend", 14)
            end
            return pvm.T.seq(out)
        end,
    })

    return { phase = phase, complete = function(doc, pos) return pvm.drain(phase(L.CompletionQuery(doc, pos))) end }
end

return M
