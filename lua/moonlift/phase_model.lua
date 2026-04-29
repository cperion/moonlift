-- Canonical compiler phase/wiring model.
--
-- This records dependency and phase-boundary architecture as ASDL values.  The
-- first consumer is a Lua registry; later consumers can generate docs, reports,
-- or native Moonlift/LL-PVM phase machines from the same data.

local M = {}

M.SCHEMA = [[
module MoonPhase {
    Package = Package(string name, MoonPhase.PhaseUnit* units) unique

    PhaseUnit = PhaseUnit(string name, string file, MoonPhase.UnitUse* uses, MoonPhase.PhaseSpec* phases, MoonPhase.UnitExport* exports) unique

    UnitUse = UnitUse(string name) unique
    UnitExport = UnitExport(string name) unique

    TypeRef = TypeRef(string module_name, string type_name) unique
            | TypeRefAny
            | TypeRefValue(string name) unique

    CachePolicy = CacheNode
                | CacheNodeArgsFull
                | CacheNodeArgsLast
                | CacheNone

    ResultShape = ResultOne
                | ResultOptional
                | ResultMany
                | ResultReport(MoonPhase.TypeRef report_ty) unique

    PhaseSpec = PhaseSpec(string name, MoonPhase.TypeRef input, MoonPhase.TypeRef output, MoonPhase.CachePolicy cache, MoonPhase.ResultShape result) unique

    UnitPart = UnitFile(string module_name) unique
             | UnitUses(MoonPhase.UnitUse* uses) unique
             | UnitExports(MoonPhase.UnitExport* exports) unique
             | UnitPhase(MoonPhase.PhaseSpec phase) unique

    PhasePart = PhaseInput(MoonPhase.TypeRef input) unique
              | PhaseOutput(MoonPhase.TypeRef output) unique
              | PhaseCache(MoonPhase.CachePolicy cache) unique
              | PhaseResult(MoonPhase.ResultShape result) unique
}
]]

function M.Define(T)
    if T.MoonPhase ~= nil then return T end
    T:Define(M.SCHEMA)
    return T
end

return M
