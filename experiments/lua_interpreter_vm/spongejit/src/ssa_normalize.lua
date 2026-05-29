-- ssa_normalize.lua -- graph-derived semantic normal forms and hashes.

local Util = require("src.util")
local Facts = require("src.facts")

local M = {}

local function sorted_keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function val(v, map)
    if not v then return "" end
    if not map[v] then map[v] = "v" .. tostring(#map + 1) end
    return map[v]
end

local function args_key(args)
    local out = {}
    for _, k in ipairs(sorted_keys(args or {})) do
        local v = args[k]
        if type(v) ~= "table" then out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
    end
    return table.concat(out, ",")
end

local IMPORTANT = {
    GuardTypeI64 = "I64",
    GuardTable = "TABLE",
    GuardShape = "SHAPE",
    GuardMetatableAbsent = "NO_META",
    GuardCallTarget = "CALL_TARGET",
    GuardArrayHit = "ARRAY_HIT",
    GuardBounds = "BOUNDS",
    FieldLoad = "FIELD_LOAD",
    FieldStore = "FIELD_STORE",
    ArrayLoad = "ARRAY_LOAD",
    ArrayStore = "ARRAY_STORE",
    AddI64 = "ADD_I64",
    SubI64 = "SUB_I64",
    MulI64 = "MUL_I64",
    I64BinOp = "I64_BINOP",
    I64UnaryOp = "I64_UNOP",
    CmpI64 = "CMP_I64",
    UnboxI64 = "UNBOX_I64",
    BoxI64 = "BOX_I64",
    ConstI64 = "CONST_I64",
    LoadConst = "LOAD_CONST",
    ConstBool = "CONST_BOOL",
    ConstNil = "CONST_NIL",
    Call = "CALL",
    KnownCall = "KNOWN_CALL",
    Return1 = "RETURN1",
    Return0 = "RETURN0",
    Residual = "RESIDUAL",
    GenericExit = "GENERIC_EXIT",
    BarrierCheck = "BARRIER",
    FrameLoad = "FRAME_LOAD",
    FrameStore = "FRAME_STORE",
}

local COMPOSITE_PATTERNS = {
    -- These patterns are over typed SSA semantic ops (raw IR node names).
    -- They match sequences produced by the real typed SSA lifter + optimizer.
    -- FrameStore/FrameLoad nodes appear because the typed IR models slot/stack
    -- writes explicitly for correct memory SSA.
    {
        name = "FIELD_ADDI_UPDATE",
        seq = { "FrameLoad", "GuardTable", "GuardShape", "GuardMetatableAbsent", "FieldLoad", "FrameStore", "GuardTypeI64", "UnboxI64", "ConstI64", "AddI64", "BoxI64", "FrameStore", "FrameLoad", "FieldStore" },
    },
    {
        name = "FIELD_LOAD_RETURN",
        seq = { "FrameLoad", "GuardTable", "GuardShape", "GuardMetatableAbsent", "FieldLoad", "FrameStore", "Return1" },
    },
    {
        name = "ARRAY_ADD_UPDATE",
        seq = { "FrameLoad", "GuardTable", "GuardMetatableAbsent", "GuardArrayHit", "GuardBounds", "ArrayLoad", "FrameStore", "GuardTypeI64", "UnboxI64", "AddI64", "BoxI64", "FrameLoad", "GuardTable", "GuardMetatableAbsent", "GuardArrayHit", "GuardBounds", "ArrayStore" },
    },
    {
        name = "SELF_CALL",
        seq = { "FrameLoad", "GuardTable", "GuardShape", "GuardMetatableAbsent", "FieldLoad", "FrameStore", "FrameLoad", "GuardCallTarget", "KnownCall" },
    },
    {
        name = "SELF_CALL_GENERIC",
        seq = { "FrameLoad", "GuardTable", "GuardShape", "GuardMetatableAbsent", "FieldLoad", "FrameStore", "FrameLoad", "Call" },
    },
    {
        name = "SELF_TAILCALL",
        seq = { "FrameLoad", "GuardTable", "GuardShape", "GuardMetatableAbsent", "FieldLoad", "FrameStore", "FrameLoad", "TailCall" },
    },
}

local function active_semantic_ops(g)
    local out = {}
    for _, n in ipairs(g.nodes or {}) do if not n.removed then out[#out + 1] = n.op end end
    return out
end

local function compress_patterns(ops)
    local out, i = {}, 1
    while i <= #ops do
        local matched = false
        for _, p in ipairs(COMPOSITE_PATTERNS) do
            local ok = true
            if i + #p.seq - 1 > #ops then ok = false end
            if ok then
                for j, op in ipairs(p.seq) do if ops[i + j - 1] ~= op then ok = false; break end end
            end
            if ok then
                out[#out + 1] = p.name
                i = i + #p.seq
                matched = true
                break
            end
        end
        if not matched then out[#out + 1] = IMPORTANT[ops[i]] or ops[i]; i = i + 1 end
    end
    return out
end

function M.active_codegen_ops(g)
    local out = {}
    for _, n in ipairs(g.nodes or {}) do if not n.removed and n.codegen_op then out[#out + 1] = n.codegen_op end end
    return out
end

function M.checked_facts(g)
    local seen, out = {}, {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed and n.guard and n.guard.fact then
            local f = n.guard.fact
            local k = Facts.guard_key(f)
            if not seen[k] then seen[k] = true; out[#out + 1] = f end
        end
    end
    table.sort(out, function(a, b) return Facts.guard_key(a) < Facts.guard_key(b) end)
    return out
end

function M.checked_fact_names(g)
    local out = {}
    for _, f in ipairs(M.checked_facts(g)) do out[#out + 1] = f.predicate end
    table.sort(out)
    return out
end

function M.deps(g)
    local seen, out = {}, {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed then
            for _, d in ipairs(n.deps or {}) do if not seen[d] then seen[d] = true; out[#out + 1] = d end end
            if n.guard and n.guard.fact then
                for _, d in ipairs(n.guard.fact.deps or {}) do if not seen[d] then seen[d] = true; out[#out + 1] = d end end
            end
        end
    end
    table.sort(out)
    return out
end

function M.projection(g)
    local exits, virtuals = 0, 0
    local reasons = {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed and n.exit then
            exits = exits + 1
            reasons[#reasons + 1] = n.exit.reason or "exit"
            if n.exit.virtual_values then virtuals = virtuals + #n.exit.virtual_values end
        end
    end
    table.sort(reasons)
    return { ok = true, exit_obligations = exits, virtual_values = virtuals, reasons = reasons }
end

function M.semantic_normal_form(g)
    return compress_patterns(active_semantic_ops(g))
end

function M.canonical_graph_key(g)
    local vmap, lines = {}, {}
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed then
            local ins, outs = {}, {}
            for _, x in ipairs(n.inputs or {}) do ins[#ins + 1] = val(x, vmap) end
            for _, x in ipairs(n.outputs or {}) do outs[#outs + 1] = val(x, vmap) end
            local guard = n.guard and n.guard.key or ""
            lines[#lines + 1] = table.concat({ n.op, table.concat(ins, ","), table.concat(outs, ","), n.effect or "none", guard, args_key(n.args) }, ";")
        end
    end
    return table.concat(lines, "|")
end

function M.hash(g)
    local facts = {}
    for _, f in ipairs(M.checked_facts(g)) do facts[#facts + 1] = Facts.guard_key(f) end
    return Util.stable_hash(M.canonical_graph_key(g) .. " :: " .. table.concat(facts, ",") .. " :: " .. table.concat(M.deps(g), ","))
end

return M
