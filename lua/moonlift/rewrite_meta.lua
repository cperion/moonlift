local pvm = require("pvm")

local M = {}

local function starts_with(s, prefix)
    return type(s) == "string" and string.sub(s, 1, #prefix) == prefix
end

function M.Define(T)
    local Meta = T.MoonliftMeta
    if Meta == nil then error("rewrite_meta: MoonliftMeta ASDL module is not defined", 2) end

    local rewrite_node
    local rewrite_stmt_one
    local rewrite_item_one

    local function ruleset(rules)
        if rules ~= nil and rules.rules ~= nil then return rules end
        return Meta.MetaRewriteSet(rules or {})
    end

    local function find_replacement(node, rules)
        for i = 1, #rules.rules do
            local r = rules.rules[i]
            if r.kind == "MetaRewriteStmt" or r.kind == "MetaRewriteItem" then
                -- Stmt/item list rewrites are only applied by the statement/item list phases.
            elseif r.from == node then
                return r.to
            end
        end
        return nil
    end

    local function find_stmt_replacement(node, rules)
        for i = 1, #rules.rules do
            local r = rules.rules[i]
            if r.kind == "MetaRewriteStmt" and r.from == node then return r.to end
        end
        return nil
    end

    local function find_item_replacement(node, rules)
        for i = 1, #rules.rules do
            local r = rules.rules[i]
            if r.kind == "MetaRewriteItem" and r.from == node then return r.to end
        end
        return nil
    end

    local function rewrite_value(v, rules)
        if pvm.classof(v) then return pvm.one(rewrite_node(v, rules)) end
        return v
    end

    local function rewrite_array(xs, field_type, rules)
        local out = {}
        if xs == nil then return out end
        if field_type == "MoonliftMeta.MetaStmt" then
            for i = 1, #xs do
                local g, p, c = rewrite_stmt_one(xs[i], rules)
                pvm.drain_into(g, p, c, out)
            end
            return out
        end
        if field_type == "MoonliftMeta.MetaItem" then
            for i = 1, #xs do
                local g, p, c = rewrite_item_one(xs[i], rules)
                pvm.drain_into(g, p, c, out)
            end
            return out
        end
        for i = 1, #xs do
            out[i] = rewrite_value(xs[i], rules)
        end
        return out
    end

    local function structural_rewrite(self, rules)
        local direct = find_replacement(self, rules)
        if direct ~= nil then return direct end

        local cls = pvm.classof(self)
        if not cls or not cls.__fields then return self end
        local overrides = nil
        for i = 1, #cls.__fields do
            local f = cls.__fields[i]
            if starts_with(f.type, "MoonliftMeta.") then
                local old = self[f.name]
                local new
                if f.list then
                    new = rewrite_array(old, f.type, rules)
                else
                    new = rewrite_value(old, rules)
                end
                if new ~= old then
                    overrides = overrides or {}
                    overrides[f.name] = new
                end
            end
        end
        if overrides == nil then return self end
        return pvm.with(self, overrides)
    end

    local node_handlers = {}
    for _, cls in pairs(Meta) do
        if type(cls) == "table" and (cls.__fields ~= nil or cls.kind ~= nil) then
            node_handlers[cls] = function(self, rules) return pvm.once(structural_rewrite(self, rules)) end
        end
    end

    rewrite_node = pvm.phase("rewrite_meta_node", node_handlers)

    local function expand_stmt_replacement(repl, rules)
        local trips = {}
        for i = 1, #repl do trips[i] = { rewrite_stmt_one(repl[i], rules) } end
        return pvm.concat_all(trips)
    end

    local function expand_item_replacement(repl, rules)
        local trips = {}
        for i = 1, #repl do trips[i] = { rewrite_item_one(repl[i], rules) } end
        return pvm.concat_all(trips)
    end

    local stmt_handlers = {}
    local stmt_classes = {
        Meta.MetaLet, Meta.MetaVar, Meta.MetaSet, Meta.MetaExprStmt, Meta.MetaAssert,
        Meta.MetaIf, Meta.MetaSwitch, Meta.MetaReturnVoid, Meta.MetaReturnValue,
        Meta.MetaBreak, Meta.MetaBreakValue, Meta.MetaContinue, Meta.MetaStmtLoop,
        Meta.MetaStmtUseRegionSlot, Meta.MetaStmtUseRegionFrag,
    }
    for i = 1, #stmt_classes do
        local cls = stmt_classes[i]
        stmt_handlers[cls] = function(self, rules)
            local repl = find_stmt_replacement(self, rules)
            if repl ~= nil then return expand_stmt_replacement(repl, rules) end
            return pvm.once(pvm.one(rewrite_node(self, rules)))
        end
    end
    rewrite_stmt_one = pvm.phase("rewrite_meta_stmt_one", stmt_handlers)

    local item_handlers = {}
    local item_classes = {
        Meta.MetaItemFunc, Meta.MetaItemExtern, Meta.MetaItemConst, Meta.MetaItemStatic,
        Meta.MetaItemImport, Meta.MetaItemType, Meta.MetaItemUseTypeDeclSlot,
        Meta.MetaItemUseItemsSlot, Meta.MetaItemUseModule, Meta.MetaItemUseModuleSlot,
    }
    for i = 1, #item_classes do
        local cls = item_classes[i]
        item_handlers[cls] = function(self, rules)
            local repl = find_item_replacement(self, rules)
            if repl ~= nil then return expand_item_replacement(repl, rules) end
            return pvm.once(pvm.one(rewrite_node(self, rules)))
        end
    end
    rewrite_item_one = pvm.phase("rewrite_meta_item_one", item_handlers)

    local api = {}
    api.phases = { node = rewrite_node, stmt_one = rewrite_stmt_one, item_one = rewrite_item_one }

    function api.node(node, rules) return pvm.one(rewrite_node(node, ruleset(rules))) end
    function api.type(node, rules) return api.node(node, rules) end
    function api.binding(node, rules) return api.node(node, rules) end
    function api.place(node, rules) return api.node(node, rules) end
    function api.domain(node, rules) return api.node(node, rules) end
    function api.expr(node, rules) return api.node(node, rules) end
    function api.loop(node, rules) return api.node(node, rules) end
    function api.func(node, rules) return api.node(node, rules) end
    function api.const(node, rules) return api.node(node, rules) end
    function api.static(node, rules) return api.node(node, rules) end
    function api.module(node, rules) return api.node(node, rules) end

    function api.stmt(node, rules)
        local out = pvm.drain(rewrite_stmt_one(node, ruleset(rules)))
        if #out ~= 1 then error("rewrite_meta: statement rewrite produced " .. tostring(#out) .. " statements for singular API", 2) end
        return out[1]
    end

    function api.stmts(nodes, rules)
        return rewrite_array(nodes, "MoonliftMeta.MetaStmt", ruleset(rules))
    end

    function api.item(node, rules)
        local out = pvm.drain(rewrite_item_one(node, ruleset(rules)))
        if #out ~= 1 then error("rewrite_meta: item rewrite produced " .. tostring(#out) .. " items for singular API", 2) end
        return out[1]
    end

    function api.items(nodes, rules)
        return rewrite_array(nodes, "MoonliftMeta.MetaItem", ruleset(rules))
    end

    return api
end

return M
