local pvm = require("pvm")

local M = {}

local function starts_with(s, prefix)
    return type(s) == "string" and string.sub(s, 1, #prefix) == prefix
end

function M.Define(T)
    local Meta = T.MoonliftMeta
    if Meta == nil then error("meta_query: MoonliftMeta ASDL module is not defined", 2) end

    local facts_here
    local walk

    local function slot_fact(slot) return pvm.once(Meta.MetaFactSlot(slot)) end

    local here_handlers = {}
    for _, cls in pairs(Meta) do
        if type(cls) == "table" and (cls.__fields ~= nil or cls.kind ~= nil) then
            here_handlers[cls] = function() return pvm.empty() end
        end
    end

    here_handlers[Meta.MetaSlotType] = function(self) return slot_fact(self) end
    here_handlers[Meta.MetaSlotExpr] = function(self) return slot_fact(self) end
    here_handlers[Meta.MetaSlotPlace] = function(self) return slot_fact(self) end
    here_handlers[Meta.MetaSlotDomain] = function(self) return slot_fact(self) end
    here_handlers[Meta.MetaSlotRegion] = function(self) return slot_fact(self) end
    here_handlers[Meta.MetaSlotFunc] = function(self) return slot_fact(self) end
    here_handlers[Meta.MetaSlotConst] = function(self) return slot_fact(self) end
    here_handlers[Meta.MetaSlotStatic] = function(self) return slot_fact(self) end
    here_handlers[Meta.MetaSlotTypeDecl] = function(self) return slot_fact(self) end
    here_handlers[Meta.MetaSlotItems] = function(self) return slot_fact(self) end
    here_handlers[Meta.MetaSlotModule] = function(self) return slot_fact(self) end

    here_handlers[Meta.MetaTSlot] = function(self) return slot_fact(Meta.MetaSlotType(self.slot)) end
    here_handlers[Meta.MetaExprSlotValue] = function(self) return slot_fact(Meta.MetaSlotExpr(self.slot)) end
    here_handlers[Meta.MetaPlaceSlotValue] = function(self) return slot_fact(Meta.MetaSlotPlace(self.slot)) end
    here_handlers[Meta.MetaDomainSlotValue] = function(self) return slot_fact(Meta.MetaSlotDomain(self.slot)) end
    here_handlers[Meta.MetaStmtUseRegionSlot] = function(self) return slot_fact(Meta.MetaSlotRegion(self.slot)) end
    here_handlers[Meta.MetaBindFuncSlot] = function(self) return slot_fact(Meta.MetaSlotFunc(self.slot)) end
    here_handlers[Meta.MetaBindConstSlot] = function(self) return slot_fact(Meta.MetaSlotConst(self.slot)) end
    here_handlers[Meta.MetaBindStaticSlot] = function(self) return slot_fact(Meta.MetaSlotStatic(self.slot)) end
    here_handlers[Meta.MetaItemUseTypeDeclSlot] = function(self) return slot_fact(Meta.MetaSlotTypeDecl(self.slot)) end
    here_handlers[Meta.MetaItemUseItemsSlot] = function(self) return slot_fact(Meta.MetaSlotItems(self.slot)) end
    here_handlers[Meta.MetaItemUseModuleSlot] = function(self)
        local g1, p1, c1 = slot_fact(Meta.MetaSlotModule(self.slot))
        local g2, p2, c2 = pvm.once(Meta.MetaFactModuleSlotUse(self.use_id, self.slot))
        return pvm.concat2(g1, p1, c1, g2, p2, c2)
    end

    here_handlers[Meta.MetaImportValue] = function(self) return pvm.once(Meta.MetaFactValueImportUse(self)) end
    here_handlers[Meta.MetaImportGlobalFunc] = function(self) return pvm.once(Meta.MetaFactValueImportUse(self)) end
    here_handlers[Meta.MetaImportGlobalConst] = function(self) return pvm.once(Meta.MetaFactValueImportUse(self)) end
    here_handlers[Meta.MetaImportGlobalStatic] = function(self) return pvm.once(Meta.MetaFactValueImportUse(self)) end
    here_handlers[Meta.MetaImportExtern] = function(self) return pvm.once(Meta.MetaFactValueImportUse(self)) end
    here_handlers[Meta.MetaBindParam] = function(self) return pvm.once(Meta.MetaFactParamUse(self.param)) end
    here_handlers[Meta.MetaBindImport] = function(self) return pvm.once(Meta.MetaFactValueImportUse(self.import)) end
    here_handlers[Meta.MetaBindLocalValue] = function(self) return pvm.once(Meta.MetaFactLocalValue(self.id, self.name)) end
    here_handlers[Meta.MetaBindLocalCell] = function(self) return pvm.once(Meta.MetaFactLocalCell(self.id, self.name)) end
    here_handlers[Meta.MetaBindLoopCarry] = function(self) return pvm.once(Meta.MetaFactLoopCarry(self.loop_id, self.port_id, self.name)) end
    here_handlers[Meta.MetaBindLoopIndex] = function(self) return pvm.once(Meta.MetaFactLoopIndex(self.loop_id, self.name)) end
    here_handlers[Meta.MetaBindGlobalFunc] = function(self) return pvm.once(Meta.MetaFactGlobalFunc(self.module_name, self.item_name)) end
    here_handlers[Meta.MetaBindGlobalConst] = function(self) return pvm.once(Meta.MetaFactGlobalConst(self.module_name, self.item_name)) end
    here_handlers[Meta.MetaBindGlobalStatic] = function(self) return pvm.once(Meta.MetaFactGlobalStatic(self.module_name, self.item_name)) end
    here_handlers[Meta.MetaBindExtern] = function(self) return pvm.once(Meta.MetaFactExtern(self.symbol)) end
    here_handlers[Meta.MetaTLocalNamed] = function(self) return pvm.once(Meta.MetaFactLocalType(self.sym)) end
    here_handlers[Meta.MetaExprUseExprFrag] = function(self) return pvm.once(Meta.MetaFactExprFragUse(self.use_id)) end
    here_handlers[Meta.MetaStmtUseRegionFrag] = function(self) return pvm.once(Meta.MetaFactRegionFragUse(self.use_id)) end
    here_handlers[Meta.MetaItemUseModule] = function(self) return pvm.once(Meta.MetaFactModuleUse(self.use_id)) end
    here_handlers[Meta.MetaModuleNameOpen] = function() return pvm.once(Meta.MetaFactOpenModuleName) end

    facts_here = pvm.phase("meta_query_facts_here", here_handlers)

    local function child_trips(node)
        local cls = pvm.classof(node)
        local trips = {}
        if not cls or not cls.__fields then return trips end
        for i = 1, #cls.__fields do
            local f = cls.__fields[i]
            if starts_with(f.type, "MoonliftMeta.") then
                local v = node[f.name]
                if f.list then
                    for j = 1, #(v or {}) do
                        local child = v[j]
                        if pvm.classof(child) then
                            local g, p, c = walk(child)
                            trips[#trips + 1] = { g, p, c }
                        end
                    end
                elseif pvm.classof(v) then
                    local g, p, c = walk(v)
                    trips[#trips + 1] = { g, p, c }
                end
            end
        end
        return trips
    end

    local walk_handlers = {}
    for _, cls in pairs(Meta) do
        if type(cls) == "table" and (cls.__fields ~= nil or cls.kind ~= nil) then
            walk_handlers[cls] = function(self)
                local trips = {}
                local g, p, c = facts_here(self)
                trips[#trips + 1] = { g, p, c }
                local children = child_trips(self)
                for i = 1, #children do trips[#trips + 1] = children[i] end
                return pvm.concat_all(trips)
            end
        end
    end

    walk = pvm.phase("meta_query_walk", walk_handlers)

    local api = {}
    api.phases = { facts_here = facts_here, walk = walk }

    function api.facts(node)
        return Meta.MetaFactSet(pvm.drain(walk(node)))
    end

    function api.fact_list(node)
        return pvm.drain(walk(node))
    end

    function api.slots(node)
        local out = {}
        local facts = api.fact_list(node)
        for i = 1, #facts do
            if facts[i].slot ~= nil then out[#out + 1] = facts[i].slot end
        end
        return out
    end

    function api.params(node)
        local out = {}
        local facts = api.fact_list(node)
        for i = 1, #facts do
            if facts[i].param ~= nil then out[#out + 1] = facts[i].param end
        end
        return out
    end

    function api.fragment_uses(node)
        local out = {}
        local facts = api.fact_list(node)
        for i = 1, #facts do
            local k = facts[i].kind
            if k == "MetaFactExprFragUse" or k == "MetaFactRegionFragUse" or k == "MetaFactModuleUse" or k == "MetaFactModuleSlotUse" then
                out[#out + 1] = facts[i]
            end
        end
        return out
    end

    return api
end

return M
