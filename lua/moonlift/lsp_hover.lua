local pvm = require("moonlift.pvm")

local M = {}

local scalar_docs = {
    void = "Moonlift `void` result type.",
    bool = "Moonlift semantic boolean. In hosted boundary structs use explicit storage such as `bool8`, `bool32`, or `bool stored T`.",
    bool8 = "Hosted boundary boolean exposed as `bool` and stored as `u8`.",
    bool32 = "Hosted boundary boolean exposed as `bool` and stored as `i32`.",
    i8 = "Signed 8-bit integer.", i16 = "Signed 16-bit integer.", i32 = "Signed 32-bit integer.", i64 = "Signed 64-bit integer.",
    u8 = "Unsigned 8-bit integer.", u16 = "Unsigned 16-bit integer.", u32 = "Unsigned 32-bit integer.", u64 = "Unsigned 64-bit integer.",
    f32 = "32-bit float.", f64 = "64-bit float.", index = "Pointer-sized Moonlift index integer.",
    view = "`view(T)` is Moonlift's semantic view type. Public host ABI uses descriptor pointers; internal ABI expands to data/len/stride.",
    ptr = "`ptr(T)` is a raw pointer to `T`.",
    json = "Moonlift JSON builtin: bytes -> decoded tape -> indexed tape -> typed reads/projections.",
}

local function line_bounds(text, line0)
    local pos, cur = 1, 0
    while cur < line0 do
        local nl = text:find("\n", pos, true)
        if not nl then return #text + 1, #text + 1 end
        pos = nl + 1; cur = cur + 1
    end
    local e = text:find("\n", pos, true) or (#text + 1)
    return pos, e
end

local function word_at(text, line0, char0)
    local s, e = line_bounds(text, line0)
    local line = text:sub(s, e - 1)
    local i = math.max(1, math.min(#line, (char0 or 0) + 1))
    local function ok(c) return c and c:match("[%w_]") ~= nil end
    if not ok(line:sub(i, i)) and i > 1 and ok(line:sub(i - 1, i - 1)) then i = i - 1 end
    if not ok(line:sub(i, i)) then return nil end
    local l, r = i, i
    while l > 1 and ok(line:sub(l - 1, l - 1)) do l = l - 1 end
    while r < #line and ok(line:sub(r + 1, r + 1)) do r = r + 1 end
    return line:sub(l, r), l - 1, r
end

function M.Define(T)
    require("moonlift.lsp_asdl").Define(T)
    local L = T.MoonliftLsp
    local Scan = require("moonlift.lsp_scan").Define(T)

    local phase = pvm.phase("moonlift_lsp_hover", {
        [L.HoverQuery] = function(self)
            local word, c0, c1 = word_at(self.document.text, self.position.line, self.position.character)
            if not word then return pvm.empty() end
            local doc = scalar_docs[word]
            if not doc then
                local islands = Scan.scan(self.document)
                for i = 1, #islands do
                    if islands[i].name == word then
                        doc = "Moonlift " .. tostring(islands[i].kind):gsub("^MoonliftLsp%.", "") .. " `" .. word .. "`."
                        break
                    end
                end
            end
            if not doc then return pvm.empty() end
            local range = L.Range(L.Position(self.position.line, c0), L.Position(self.position.line, c1))
            return pvm.once(L.Hover(range, doc))
        end,
    })

    return { phase = phase, hover = function(doc, pos) return pvm.drain(phase(L.HoverQuery(doc, pos)))[1] end }
end

return M
