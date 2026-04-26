local pvm = require("moonlift.pvm")

local M = {}

local function stable_name(text)
    text = tostring(text or "anon")
    text = text:gsub("[^%w_]", "_")
    if not text:match("^[A-Za-z_]") then text = "_" .. text end
    return text
end

function M.Define(T)
    local H = T.Moon2Host
    local C = T.Moon2Core

    local scalar_terra = {
        [C.ScalarBool] = "bool",
        [C.ScalarI8] = "int8", [C.ScalarU8] = "uint8",
        [C.ScalarI16] = "int16", [C.ScalarU16] = "uint16",
        [C.ScalarI32] = "int32", [C.ScalarU32] = "uint32",
        [C.ScalarI64] = "int64", [C.ScalarU64] = "uint64",
        [C.ScalarF32] = "float", [C.ScalarF64] = "double",
        [C.ScalarIndex] = "intptr",
        [C.ScalarRawPtr] = "&uint8",
    }

    local function rep_terra_type(rep)
        local cls = pvm.classof(rep)
        if cls == H.HostRepScalar then return scalar_terra[rep.scalar] or "uint8" end
        if cls == H.HostRepBool then return scalar_terra[rep.storage] or "int32" end
        if cls == H.HostRepPtr or cls == H.HostRepRef then return "&uint8" end
        if cls == H.HostRepSlice or cls == H.HostRepView then return "&uint8" end
        return "uint8"
    end

    local function layout_source(layout)
        local lines = { "struct " .. stable_name(layout.ctype) .. " {" }
        for i = 1, #layout.fields do
            local f = layout.fields[i]
            lines[#lines + 1] = "  " .. stable_name(f.cfield) .. ": " .. rep_terra_type(f.rep)
        end
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local phase = pvm.phase("moon2_host_terra_emit_plan", {
        [H.HostFactSet] = function(self, module_name)
            local layouts, views, sources = {}, {}, {}
            for i = 1, #self.facts do
                local fact = self.facts[i]
                local cls = pvm.classof(fact)
                if cls == H.HostFactTypeLayout then
                    layouts[#layouts + 1] = fact.layout
                    sources[#sources + 1] = layout_source(fact.layout)
                elseif cls == H.HostFactViewDescriptor then
                    views[#views + 1] = fact.descriptor
                end
            end
            return pvm.once(H.HostTerraPlan(module_name or "moon2_host", table.concat(sources, "\n\n"), layouts, views))
        end,
    }, { args_cache = "full" })

    local function plan(facts, module_name)
        return pvm.one(phase(facts, module_name or "moon2_host"))
    end

    return {
        phase = phase,
        plan = plan,
    }
end

return M
