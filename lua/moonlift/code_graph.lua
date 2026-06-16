local pvm = require("moonlift.pvm")

local M = {}

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_graph ~= nil then return T._moonlift_api_cache.code_graph end

    local Code = T.MoonCode
    local Graph = T.MoonGraph

    local api = {}

    local function block_id(func, block)
        return Graph.GraphBlockId(func.id, block.id or block)
    end

    local function inst_ref(func, block, inst)
        return Graph.GraphInstRef(func.id, block.id, inst.id)
    end

    local function add_use(uses, value, ref, term_block, role)
        if value ~= nil then uses[#uses + 1] = Graph.GraphUse(value, ref, term_block, role) end
    end

    local function add_place_uses(uses, place, ref, role)
        if place == nil then return end
        local cls = pvm.classof(place)
        if cls == Code.CodePlaceDeref then
            add_use(uses, place.addr, ref, nil, role .. ":deref.addr")
        elseif cls == Code.CodePlaceIndex then
            add_place_uses(uses, place.base, ref, role .. ":index.base")
            add_use(uses, place.index, ref, nil, role .. ":index")
        elseif cls == Code.CodePlaceField then
            add_place_uses(uses, place.base, ref, role .. ":field.base")
        elseif cls == Code.CodePlaceBytes then
            add_use(uses, place.base, ref, nil, role .. ":bytes.base")
        end
    end

    local function inst_dst(k)
        return k and k.dst or nil
    end

    local function append_defs(func, block, inst, defs)
        local dst = inst_dst(inst.kind)
        if dst ~= nil then defs[#defs + 1] = Graph.GraphDef(dst, inst_ref(func, block, inst), nil) end
    end

    local function append_inst_uses(func, block, inst, uses)
        local k = inst.kind
        local cls = pvm.classof(k)
        local ref = inst_ref(func, block, inst)
        if cls == Code.CodeInstAlias then
            add_use(uses, k.src, ref, nil, "alias.src")
        elseif cls == Code.CodeInstUnary then
            add_use(uses, k.value, ref, nil, "unary.value")
        elseif cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstCompare then
            add_use(uses, k.lhs, ref, nil, "binary.lhs")
            add_use(uses, k.rhs, ref, nil, "binary.rhs")
        elseif cls == Code.CodeInstCast then
            add_use(uses, k.value, ref, nil, "cast.value")
        elseif cls == Code.CodeInstSelect then
            add_use(uses, k.cond, ref, nil, "select.cond")
            add_use(uses, k.then_value, ref, nil, "select.then")
            add_use(uses, k.else_value, ref, nil, "select.else")
        elseif cls == Code.CodeInstIntrinsic then
            for i, arg in ipairs(k.args or {}) do add_use(uses, arg, ref, nil, "intrinsic.arg" .. tostring(i)) end
        elseif cls == Code.CodeInstAddrOf then
            add_place_uses(uses, k.place, ref, "addr_of.place")
        elseif cls == Code.CodeInstPtrOffset then
            add_use(uses, k.base, ref, nil, "ptr_offset.base")
            add_use(uses, k.index, ref, nil, "ptr_offset.index")
        elseif cls == Code.CodeInstLoad then
            add_place_uses(uses, k.place, ref, "load.place")
        elseif cls == Code.CodeInstStore then
            add_place_uses(uses, k.place, ref, "store.place")
            add_use(uses, k.value, ref, nil, "store.value")
        elseif cls == Code.CodeInstAggregate then
            for i, field in ipairs(k.fields or {}) do add_use(uses, field.value, ref, nil, "aggregate.field" .. tostring(i)) end
        elseif cls == Code.CodeInstArray then
            for i, elem in ipairs(k.elems or {}) do add_use(uses, elem.value, ref, nil, "array.elem" .. tostring(i)) end
        elseif cls == Code.CodeInstViewMake then
            add_use(uses, k.data, ref, nil, "view.data")
            add_use(uses, k.len, ref, nil, "view.len")
            add_use(uses, k.stride, ref, nil, "view.stride")
        elseif cls == Code.CodeInstViewData or cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then
            add_use(uses, k.view, ref, nil, "view")
        elseif cls == Code.CodeInstClosure then
            add_use(uses, k.fn, ref, nil, "closure.fn")
            add_use(uses, k.ctx, ref, nil, "closure.ctx")
        elseif cls == Code.CodeInstVariantCtor then
            add_use(uses, k.payload, ref, nil, "variant.payload")
        elseif cls == Code.CodeInstVariantTag or cls == Code.CodeInstVariantPayload then
            add_use(uses, k.value, ref, nil, "variant.value")
        elseif cls == Code.CodeInstCall then
            local tcls = pvm.classof(k.target)
            if tcls == Code.CodeCallIndirect then add_use(uses, k.target.callee, ref, nil, "call.callee") end
            if tcls == Code.CodeCallClosure then add_use(uses, k.target.closure, ref, nil, "call.closure") end
            for i, arg in ipairs(k.args or {}) do add_use(uses, arg, ref, nil, "call.arg" .. tostring(i)) end
        elseif cls == Code.CodeInstAtomicLoad then
            add_place_uses(uses, k.place, ref, "atomic_load.place")
        elseif cls == Code.CodeInstAtomicStore then
            add_place_uses(uses, k.place, ref, "atomic_store.place")
            add_use(uses, k.value, ref, nil, "atomic_store.value")
        elseif cls == Code.CodeInstAtomicRmw then
            add_place_uses(uses, k.place, ref, "atomic_rmw.place")
            add_use(uses, k.value, ref, nil, "atomic_rmw.value")
        elseif cls == Code.CodeInstAtomicCas then
            add_place_uses(uses, k.place, ref, "atomic_cas.place")
            add_use(uses, k.expected, ref, nil, "atomic_cas.expected")
            add_use(uses, k.replacement, ref, nil, "atomic_cas.replacement")
        end
    end

    local function append_term_uses(func, block, uses)
        local term = block.term and block.term.kind or nil
        local term_block = block_id(func, block)
        local cls = pvm.classof(term)
        if cls == Code.CodeTermBranch then
            add_use(uses, term.cond, nil, term_block, "branch.cond")
            for i, arg in ipairs(term.then_args or {}) do add_use(uses, arg, nil, term_block, "branch.then_arg" .. tostring(i)) end
            for i, arg in ipairs(term.else_args or {}) do add_use(uses, arg, nil, term_block, "branch.else_arg" .. tostring(i)) end
        elseif cls == Code.CodeTermJump then
            for i, arg in ipairs(term.args or {}) do add_use(uses, arg, nil, term_block, "jump.arg" .. tostring(i)) end
        elseif cls == Code.CodeTermSwitch then
            add_use(uses, term.value, nil, term_block, "switch.value")
            for i, case in ipairs(term.cases or {}) do
                for j, arg in ipairs(case.args or {}) do add_use(uses, arg, nil, term_block, "switch.case" .. tostring(i) .. ".arg" .. tostring(j)) end
            end
            for i, arg in ipairs(term.default_args or {}) do add_use(uses, arg, nil, term_block, "switch.default_arg" .. tostring(i)) end
        elseif cls == Code.CodeTermVariantSwitch then
            add_use(uses, term.tag, nil, term_block, "variant_switch.tag")
            for i, case in ipairs(term.cases or {}) do
                for j, arg in ipairs(case.args or {}) do add_use(uses, arg, nil, term_block, "variant.case" .. tostring(i) .. ".arg" .. tostring(j)) end
            end
            for i, arg in ipairs(term.default_args or {}) do add_use(uses, arg, nil, term_block, "variant.default_arg" .. tostring(i)) end
        elseif cls == Code.CodeTermReturn then
            for i, value in ipairs(term.values or {}) do add_use(uses, value, nil, term_block, "return.value" .. tostring(i)) end
        end
    end

    local function append_edges(func, block_by_id, block, edges)
        local term = block.term and block.term.kind or nil
        local from = block_id(func, block)
        local cls = pvm.classof(term)
        local function add(dest, kind)
            if dest ~= nil and block_by_id[dest.text] ~= nil then
                edges[#edges + 1] = Graph.GraphEdge(from, Graph.GraphBlockId(func.id, dest), kind)
            end
        end
        if cls == Code.CodeTermJump then
            add(term.dest, "jump")
        elseif cls == Code.CodeTermBranch then
            add(term.then_dest, "then")
            add(term.else_dest, "else")
        elseif cls == Code.CodeTermSwitch then
            for i, case in ipairs(term.cases or {}) do
                local lit = case.literal and (case.literal.raw or tostring(case.literal.value)) or tostring(i)
                add(case.dest, "switch:" .. tostring(lit))
            end
            add(term.default_dest, "switch:default")
        elseif cls == Code.CodeTermVariantSwitch then
            for _, case in ipairs(term.cases or {}) do add(case.dest, "variant:" .. tostring(case.variant.variant_name)) end
            add(term.default_dest, "variant:default")
        end
    end

    local function natural_loop(header_key, latch_key, preds)
        local set = {}
        set[header_key] = true
        set[latch_key] = true
        local stack = { latch_key }
        while #stack > 0 do
            local node = table.remove(stack)
            for _, pred in ipairs(preds[node] or {}) do
                if not set[pred] then
                    set[pred] = true
                    if pred ~= header_key then stack[#stack + 1] = pred end
                end
            end
        end
        return set
    end

    local function detect_natural_loops(func, blocks, order, edges)
        local preds = {}
        for _, edge in ipairs(edges or {}) do
            local from_key = edge.from.block.text
            local to_key = edge.to.block.text
            preds[to_key] = preds[to_key] or {}
            preds[to_key][#preds[to_key] + 1] = from_key
        end

        local loops = {}
        for _, edge in ipairs(edges or {}) do
            local from_key = edge.from.block.text
            local to_key = edge.to.block.text
            if order[to_key] ~= nil and order[from_key] ~= nil and order[to_key] <= order[from_key] then
                local body_set = natural_loop(to_key, from_key, preds)
                local body = {}
                for _, block in ipairs(blocks or {}) do
                    if body_set[block.id.text] then body[#body + 1] = block_id(func, block) end
                end
                local exits = {}
                for _, candidate in ipairs(edges or {}) do
                    if body_set[candidate.from.block.text] and not body_set[candidate.to.block.text] then exits[#exits + 1] = candidate end
                end
                loops[#loops + 1] = Graph.GraphLoop(
                    Graph.GraphLoopId("loop:" .. sanitize(func.name) .. ":" .. sanitize(to_key) .. ":" .. sanitize(from_key)),
                    func.id,
                    Graph.GraphBlockId(func.id, edge.to.block),
                    body,
                    { edge },
                    exits
                )
            end
        end
        return loops
    end

    local function func_graph(func)
        local block_by_id, order = {}, {}
        for i, block in ipairs(func.blocks or {}) do
            block_by_id[block.id.text] = block
            order[block.id.text] = i
        end

        local edges, defs, uses = {}, {}, {}
        for _, param in ipairs(func.params or {}) do defs[#defs + 1] = Graph.GraphDef(param.value, nil, param.value) end
        for _, block in ipairs(func.blocks or {}) do
            for _, param in ipairs(block.params or {}) do defs[#defs + 1] = Graph.GraphDef(param.value, nil, param.value) end
            append_edges(func, block_by_id, block, edges)
            for _, inst in ipairs(block.insts or {}) do
                append_defs(func, block, inst, defs)
                append_inst_uses(func, block, inst, uses)
            end
            append_term_uses(func, block, uses)
        end

        return Graph.CodeFuncGraph(func.id, edges, defs, uses, detect_natural_loops(func, func.blocks, order, edges))
    end

    local function graph(module)
        local funcs = {}
        for i, func in ipairs(module.funcs or {}) do funcs[i] = func_graph(func) end
        return Graph.CodeGraph(module.id, funcs)
    end

    api.block_id = block_id
    api.inst_ref = inst_ref
    api.graph = graph
    api.module = graph
    api.phase = pvm.phase("code_graph", {
        [Code.CodeModule] = function(self) return pvm.once(graph(self)) end,
    })

    T._moonlift_api_cache.code_graph = api
    return api
end

return M
