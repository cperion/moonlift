-- Lowerable PVM-on-Moonlift body for MoonType.TypeRef classification.
--
-- This is the same semantic question as the Lua PVM `classify_type_ref` phase,
-- authored as MoonPvmSurface data so it can emit a Moonlift region-fragment
-- producer.

local M = {}

function M.Define(T)
    local P = require("moonlift.pvm_surface_builder").Define(T)
    return P.phase "type_ref_classify" {
        P.input "MoonType.TypeRef",
        P.output "MoonType.TypeClass",
        P.cache "node",
        P.result "one",

        P.on "TypeRefGlobal" {
            P.bind "module_name",
            P.bind "type_name",
            P.once(P.ctor("MoonType_TypeClass", "TypeClassAggregate") {
                module_name = P.local_("module_name"),
                type_name = P.local_("type_name"),
            }),
        },

        P.on "TypeRefPath" {
            P.once(P.ctor("MoonType_TypeClass", "TypeClassUnknown") {}),
        },

        P.on "TypeRefLocal" {
            P.once(P.ctor("MoonType_TypeClass", "TypeClassUnknown") {}),
        },

        P.on "TypeRefSlot" {
            P.once(P.ctor("MoonType_TypeClass", "TypeClassUnknown") {}),
        },
    }
end

return M
