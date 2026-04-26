local pvm = require("moonlift.pvm")

local M = {}

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
local function pos_for_offset(L, starts, offset)
    if offset < 1 then offset = 1 end
    local line = 1
    for i = 1, #starts do if starts[i] <= offset then line = i else break end end
    return L.Position(line - 1, offset - starts[line])
end
local function range_for_offsets(L, starts, s, e) return L.Range(pos_for_offset(L, starts, s), pos_for_offset(L, starts, e)) end

local function struct_fields(T, doc, island)
    local L = T.MoonliftLsp
    local starts = line_starts(doc.text)
    local body_s = island.source:find("{", 1, true)
    local body_e = island.source:match(".*()}")
    local out = {}
    if not body_s or not body_e then return out end
    local body = island.source:sub(body_s + 1, body_e - 1)
    local search_from = 1
    for name in body:gmatch("([_%a][_%w]*)%s*:") do
        local local_pos = island.source:find(name, body_s + search_from, true) or island.source:find(name, body_s, true) or 1
        search_from = local_pos + #name - body_s
        local abs = island.start_offset + local_pos - 1
        local r = range_for_offsets(L, starts, abs, abs + #name)
        out[#out + 1] = L.Symbol(name, L.SymField, r, r, {})
    end
    return out
end

function M.Define(T)
    require("moonlift.lsp_asdl").Define(T)
    local L = T.MoonliftLsp
    local Scan = require("moonlift.lsp_scan").Define(T)
    local kind_symbol = {
        [L.IslandStruct] = L.SymStruct,
        [L.IslandExpose] = L.SymProperty,
        [L.IslandFunc] = L.SymFunction,
        [L.IslandModule] = L.SymModule,
        [L.IslandRegion] = L.SymFunction,
        [L.IslandExpr] = L.SymFunction,
    }

    local phase = pvm.phase("moonlift_lsp_symbols", {
        [L.Document] = function(self)
            local out = {}
            local islands = Scan.scan(self)
            for i = 1, #islands do
                local island = islands[i]
                local children = {}
                if island.kind == L.IslandStruct then children = struct_fields(T, self, island) end
                out[#out + 1] = L.Symbol(island.name, kind_symbol[island.kind] or L.SymVariable, island.range, island.selection_range, children)
            end
            return pvm.T.seq(out)
        end,
    })

    return { phase = phase, symbols = function(doc) return pvm.drain(phase(doc)) end }
end

return M
