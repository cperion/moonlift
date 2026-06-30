local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_graph ~= nil then return T._lalin_api_cache.code_graph end

    local Code = T.LalinCode
    local Graph = T.LalinGraph

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

    local function add_dest_edge(edges, func, block_by_id, from, dest, kind)
        if dest ~= nil and block_by_id[dest.text] ~= nil then
            edges[#edges + 1] = Graph.GraphEdge(from, Graph.GraphBlockId(func.id, dest), kind)
        end
    end

    function Code.CodePlace:code_graph_append_uses(uses, ref, role)
    end

    function Code.CodePlaceDeref:code_graph_append_uses(uses, ref, role)
        add_use(uses, self.addr, ref, nil, role .. ":deref.addr")
    end

    function Code.CodePlaceIndex:code_graph_append_uses(uses, ref, role)
        self.base:code_graph_append_uses(uses, ref, role .. ":index.base")
        add_use(uses, self.index, ref, nil, role .. ":index")
    end

    function Code.CodePlaceField:code_graph_append_uses(uses, ref, role)
        self.base:code_graph_append_uses(uses, ref, role .. ":field.base")
    end

    function Code.CodePlaceBytes:code_graph_append_uses(uses, ref, role)
        add_use(uses, self.base, ref, nil, role .. ":bytes.base")
    end

    function Code.CodeCallTarget:code_graph_append_uses(uses, ref, role)
    end

    function Code.CodeCallIndirect:code_graph_append_uses(uses, ref, role)
        add_use(uses, self.callee, ref, nil, role .. ".callee")
    end

    function Code.CodeCallClosure:code_graph_append_uses(uses, ref, role)
        add_use(uses, self.closure, ref, nil, role .. ".closure")
    end

    function Code.CodeInstOp:code_graph_dst()
        return rawget(self, "dst")
    end

    function Code.CodeInstOp:code_graph_append_uses(uses, ref)
    end

    function Code.CodeInstAlias:code_graph_append_uses(uses, ref)
        add_use(uses, self.src, ref, nil, "alias.src")
    end

    function Code.CodeInstUnary:code_graph_append_uses(uses, ref)
        add_use(uses, self.value, ref, nil, "unary.value")
    end

    function Code.CodeInstBinary:code_graph_append_uses(uses, ref)
        add_use(uses, self.lhs, ref, nil, "binary.lhs")
        add_use(uses, self.rhs, ref, nil, "binary.rhs")
    end

    function Code.CodeInstFloatBinary:code_graph_append_uses(uses, ref)
        add_use(uses, self.lhs, ref, nil, "binary.lhs")
        add_use(uses, self.rhs, ref, nil, "binary.rhs")
    end

    function Code.CodeInstCompare:code_graph_append_uses(uses, ref)
        add_use(uses, self.lhs, ref, nil, "binary.lhs")
        add_use(uses, self.rhs, ref, nil, "binary.rhs")
    end

    function Code.CodeInstCast:code_graph_append_uses(uses, ref)
        add_use(uses, self.value, ref, nil, "cast.value")
    end

    function Code.CodeInstSelect:code_graph_append_uses(uses, ref)
        add_use(uses, self.cond, ref, nil, "select.cond")
        add_use(uses, self.then_value, ref, nil, "select.then")
        add_use(uses, self.else_value, ref, nil, "select.else")
    end

    function Code.CodeInstIntrinsic:code_graph_append_uses(uses, ref)
        for i, arg in ipairs(self.args or {}) do add_use(uses, arg, ref, nil, "intrinsic.arg" .. tostring(i)) end
    end

    function Code.CodeInstAddrOf:code_graph_append_uses(uses, ref)
        self.place:code_graph_append_uses(uses, ref, "addr_of.place")
    end

    function Code.CodeInstPtrOffset:code_graph_append_uses(uses, ref)
        add_use(uses, self.base, ref, nil, "ptr_offset.base")
        add_use(uses, self.index, ref, nil, "ptr_offset.index")
    end

    function Code.CodeInstLoad:code_graph_append_uses(uses, ref)
        self.place:code_graph_append_uses(uses, ref, "load.place")
    end

    function Code.CodeInstStore:code_graph_append_uses(uses, ref)
        self.place:code_graph_append_uses(uses, ref, "store.place")
        add_use(uses, self.value, ref, nil, "store.value")
    end

    function Code.CodeInstAggregate:code_graph_append_uses(uses, ref)
        for i, field in ipairs(self.fields or {}) do add_use(uses, field.value, ref, nil, "aggregate.field" .. tostring(i)) end
    end

    function Code.CodeInstArray:code_graph_append_uses(uses, ref)
        for i, elem in ipairs(self.elems or {}) do add_use(uses, elem.value, ref, nil, "array.elem" .. tostring(i)) end
    end

    function Code.CodeInstViewMake:code_graph_append_uses(uses, ref)
        add_use(uses, self.data, ref, nil, "view.data")
        add_use(uses, self.len, ref, nil, "view.len")
        add_use(uses, self.stride, ref, nil, "view.stride")
    end

    function Code.CodeInstViewData:code_graph_append_uses(uses, ref)
        add_use(uses, self.view, ref, nil, "view")
    end

    function Code.CodeInstViewLen:code_graph_append_uses(uses, ref)
        add_use(uses, self.view, ref, nil, "view")
    end

    function Code.CodeInstViewStride:code_graph_append_uses(uses, ref)
        add_use(uses, self.view, ref, nil, "view")
    end

    function Code.CodeInstSliceMake:code_graph_append_uses(uses, ref)
        add_use(uses, self.data, ref, nil, "slice.data")
        add_use(uses, self.len, ref, nil, "slice.len")
    end

    function Code.CodeInstSliceData:code_graph_append_uses(uses, ref)
        add_use(uses, self.slice, ref, nil, "slice")
    end

    function Code.CodeInstSliceLen:code_graph_append_uses(uses, ref)
        add_use(uses, self.slice, ref, nil, "slice")
    end

    function Code.CodeInstByteSpanMake:code_graph_append_uses(uses, ref)
        add_use(uses, self.data, ref, nil, "bytespan.data")
        add_use(uses, self.len, ref, nil, "bytespan.len")
    end

    function Code.CodeInstByteSpanData:code_graph_append_uses(uses, ref)
        add_use(uses, self.span, ref, nil, "bytespan")
    end

    function Code.CodeInstByteSpanLen:code_graph_append_uses(uses, ref)
        add_use(uses, self.span, ref, nil, "bytespan")
    end

    function Code.CodeInstClosure:code_graph_append_uses(uses, ref)
        add_use(uses, self.fn, ref, nil, "closure.fn")
        add_use(uses, self.ctx, ref, nil, "closure.ctx")
    end

    function Code.CodeInstVariantCtor:code_graph_append_uses(uses, ref)
        add_use(uses, self.payload, ref, nil, "variant.payload")
    end

    function Code.CodeInstVariantTag:code_graph_append_uses(uses, ref)
        add_use(uses, self.value, ref, nil, "variant.value")
    end

    function Code.CodeInstVariantPayload:code_graph_append_uses(uses, ref)
        add_use(uses, self.value, ref, nil, "variant.value")
    end

    function Code.CodeInstCall:code_graph_append_uses(uses, ref)
        self.target:code_graph_append_uses(uses, ref, "call")
        for i, arg in ipairs(self.args or {}) do add_use(uses, arg, ref, nil, "call.arg" .. tostring(i)) end
    end

    function Code.CodeInstAtomicLoad:code_graph_append_uses(uses, ref)
        self.place:code_graph_append_uses(uses, ref, "atomic_load.place")
    end

    function Code.CodeInstAtomicStore:code_graph_append_uses(uses, ref)
        self.place:code_graph_append_uses(uses, ref, "atomic_store.place")
        add_use(uses, self.value, ref, nil, "atomic_store.value")
    end

    function Code.CodeInstAtomicRmw:code_graph_append_uses(uses, ref)
        self.place:code_graph_append_uses(uses, ref, "atomic_rmw.place")
        add_use(uses, self.value, ref, nil, "atomic_rmw.value")
    end

    function Code.CodeInstAtomicCas:code_graph_append_uses(uses, ref)
        self.place:code_graph_append_uses(uses, ref, "atomic_cas.place")
        add_use(uses, self.expected, ref, nil, "atomic_cas.expected")
        add_use(uses, self.replacement, ref, nil, "atomic_cas.replacement")
    end

    function Code.CodeInst:code_graph_append_def(func, block, defs)
        local dst = self.op:code_graph_dst()
        if dst ~= nil then defs[#defs + 1] = Graph.GraphDef(dst, inst_ref(func, block, self), nil) end
    end

    function Code.CodeInst:code_graph_append_uses(func, block, uses)
        self.op:code_graph_append_uses(uses, inst_ref(func, block, self))
    end

    function Code.CodeTermOp:code_graph_append_uses(uses, term_block)
    end

    function Code.CodeTermBranch:code_graph_append_uses(uses, term_block)
        add_use(uses, self.cond, nil, term_block, "branch.cond")
        for i, arg in ipairs(self.then_args or {}) do add_use(uses, arg, nil, term_block, "branch.then_arg" .. tostring(i)) end
        for i, arg in ipairs(self.else_args or {}) do add_use(uses, arg, nil, term_block, "branch.else_arg" .. tostring(i)) end
    end

    function Code.CodeTermJump:code_graph_append_uses(uses, term_block)
        for i, arg in ipairs(self.args or {}) do add_use(uses, arg, nil, term_block, "jump.arg" .. tostring(i)) end
    end

    function Code.CodeTermSwitch:code_graph_append_uses(uses, term_block)
        add_use(uses, self.value, nil, term_block, "switch.value")
        for i, case in ipairs(self.cases or {}) do
            for j, arg in ipairs(case.args or {}) do add_use(uses, arg, nil, term_block, "switch.case" .. tostring(i) .. ".arg" .. tostring(j)) end
        end
        for i, arg in ipairs(self.default_args or {}) do add_use(uses, arg, nil, term_block, "switch.default_arg" .. tostring(i)) end
    end

    function Code.CodeTermVariantSwitch:code_graph_append_uses(uses, term_block)
        add_use(uses, self.tag, nil, term_block, "variant_switch.tag")
        for i, case in ipairs(self.cases or {}) do
            for j, arg in ipairs(case.args or {}) do add_use(uses, arg, nil, term_block, "variant.case" .. tostring(i) .. ".arg" .. tostring(j)) end
        end
        for i, arg in ipairs(self.default_args or {}) do add_use(uses, arg, nil, term_block, "variant.default_arg" .. tostring(i)) end
    end

    function Code.CodeTermReturn:code_graph_append_uses(uses, term_block)
        for i, value in ipairs(self.values or {}) do add_use(uses, value, nil, term_block, "return.value" .. tostring(i)) end
    end

    function Code.CodeTermOp:code_graph_append_edges(func, block_by_id, from, edges)
    end

    function Code.CodeTermJump:code_graph_append_edges(func, block_by_id, from, edges)
        add_dest_edge(edges, func, block_by_id, from, self.dest, "jump")
    end

    function Code.CodeTermBranch:code_graph_append_edges(func, block_by_id, from, edges)
        add_dest_edge(edges, func, block_by_id, from, self.then_dest, "then")
        add_dest_edge(edges, func, block_by_id, from, self.else_dest, "else")
    end

    function Code.CodeTermSwitch:code_graph_append_edges(func, block_by_id, from, edges)
        for i, case in ipairs(self.cases or {}) do
            local lit = case.literal and (case.literal.raw or tostring(case.literal.value)) or tostring(i)
            add_dest_edge(edges, func, block_by_id, from, case.dest, "switch:" .. tostring(lit))
        end
        add_dest_edge(edges, func, block_by_id, from, self.default_dest, "switch:default")
    end

    function Code.CodeTermVariantSwitch:code_graph_append_edges(func, block_by_id, from, edges)
        for _, case in ipairs(self.cases or {}) do
            add_dest_edge(edges, func, block_by_id, from, case.dest, "variant:" .. tostring(case.variant.variant_name))
        end
        add_dest_edge(edges, func, block_by_id, from, self.default_dest, "variant:default")
    end

    function Code.CodeTerm:code_graph_append_uses(func, block, uses)
        self.op:code_graph_append_uses(uses, block_id(func, block))
    end

    function Code.CodeTerm:code_graph_append_edges(func, block_by_id, block, edges)
        self.op:code_graph_append_edges(func, block_by_id, block_id(func, block), edges)
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

    function Code.CodeFunc:code_graph_func()
        local block_by_id, order = {}, {}
        for i, block in ipairs(self.blocks or {}) do
            block_by_id[block.id.text] = block
            order[block.id.text] = i
        end

        local edges, defs, uses = {}, {}, {}
        for _, param in ipairs(self.params or {}) do defs[#defs + 1] = Graph.GraphDef(param.value, nil, param.value) end
        for _, block in ipairs(self.blocks or {}) do
            for _, param in ipairs(block.params or {}) do defs[#defs + 1] = Graph.GraphDef(param.value, nil, param.value) end
            if block.term ~= nil then block.term:code_graph_append_edges(self, block_by_id, block, edges) end
            for _, inst in ipairs(block.insts or {}) do
                inst:code_graph_append_def(self, block, defs)
                inst:code_graph_append_uses(self, block, uses)
            end
            if block.term ~= nil then block.term:code_graph_append_uses(self, block, uses) end
        end

        return Graph.CodeFuncGraph(self.id, edges, defs, uses, detect_natural_loops(self, self.blocks, order, edges))
    end

    function Code.CodeModule:code_graph_module()
        local funcs = {}
        for i, func in ipairs(self.funcs or {}) do funcs[i] = func:code_graph_func() end
        return Graph.CodeGraph(self.id, funcs)
    end

    local function graph(module)
        return module:code_graph_module()
    end

    api.block_id = block_id
    api.inst_ref = inst_ref
    api.graph = graph
    api.module = graph
    function api.phase(node)
        return { node:code_graph_module() }
    end

    T._lalin_api_cache.code_graph = api
    return api
end

return bind_context
