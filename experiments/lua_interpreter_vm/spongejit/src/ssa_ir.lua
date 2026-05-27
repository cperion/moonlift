-- ssa_ir.lua -- typed SSA graph with explicit memory/effect/exit objects.

local Facts = require("src.facts")

local M = {}

local function copy_array(xs)
    local out = {}
    for i, x in ipairs(xs or {}) do out[i] = x end
    return out
end

local function sorted_keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local VALUE_TYPES = {
    TValue = true, I64 = true, F64 = true, Bool = true,
    PtrTable = true, PtrClosure = true, Shape = true,
    FieldAddr = true, Void = true, Unknown = true,
}

local EFFECTS = {
    none = true, guard = true, frame_read = true, frame_write = true,
    heap_read = true, heap_write = true, gc_barrier = true, call = true,
    residual = true, branch = true, return_ = true,
}

local CODEGEN_OP = {
    FrameLoad = "load_slot",
    FrameStore = "store_slot",
    LoadConst = "load_const",
    ConstI64 = "const_i64",
    ConstNil = "const_nil",
    ConstBool = "const_bool",
    Move = "move_value",
    GuardTypeI64 = "guard_i64",
    GuardTable = "guard_table",
    GuardShape = "guard_shape",
    GuardMetatableAbsent = "guard_metatable_absent",
    GuardCallTarget = "guard_call_target",
    GuardArrayHit = "guard_array_hit",
    GuardBounds = "guard_bounds",
    UnboxI64 = "unbox_i64",
    BoxI64 = "box_i64",
    AddI64 = "add_i64",
    SubI64 = "sub_i64",
    MulI64 = "mul_i64",
    CmpI64 = "cmp_i64",
    FieldLoad = "table_field_load",
    FieldStore = "table_field_store",
    ArrayLoad = "table_array_load",
    ArrayStore = "table_array_store",
    BarrierCheck = "barrier_check",
    Call = "call_boundary",
    KnownCall = "call_boundary_known",
    TailCall = "tailcall_boundary",
    Return0 = "return0",
    Return1 = "return1",
    Residual = "residual_boundary",
    Jump = "jump",
    Branch = "branch",
}

M.CODEGEN_OP = CODEGEN_OP

local PURE_OP = {
    FrameLoad = true, LoadConst = true, ConstI64 = true, ConstNil = true,
    ConstBool = true, Move = true, UnboxI64 = true, BoxI64 = true,
    AddI64 = true, SubI64 = true, MulI64 = true, CmpI64 = true,
    FieldLoad = true, ArrayLoad = true,
}

M.PURE_OP = PURE_OP

local HARD_BARRIER = {
    Call = true, KnownCall = true, TailCall = true, Residual = true,
}
M.HARD_BARRIER = HARD_BARRIER

local Graph = {}
Graph.__index = Graph
M.Graph = Graph

function M.new(facts, config)
    return Graph.new(facts, config)
end

function Graph.new(facts, config)
    local factset = facts
    if getmetatable(facts) ~= Facts.FactSet then factset = Facts.new(facts or {}) end
    local g = setmetatable({
        values = {},
        nodes = {},
        memories = {},
        factset = factset,
        config = config or {},
        next_node = 1,
        next_value = 1,
        next_memory = 1,
        current = nil,
        stats = { guards = 0, removed = 0, barriers = 0, values = 0, memory_tokens = 0 },
    }, Graph)
    g.mem = {
        frame = g:new_memory("frame", "entry"),
        table = g:new_memory("table", "entry"),
        gc = g:new_memory("gc", "entry"),
        call = g:new_memory("call", "entry"),
    }
    return g
end

function Graph:new_memory(domain, reason)
    local id = "m" .. tostring(self.next_memory)
    self.next_memory = self.next_memory + 1
    local m = { id = id, domain = domain or "unknown", reason = reason or "" }
    self.memories[id] = m
    self.stats.memory_tokens = self.stats.memory_tokens + 1
    return id
end

function Graph:new_value(ty, name, facts, residency)
    ty = ty or "Unknown"
    if not VALUE_TYPES[ty] then ty = "Unknown" end
    local id = name or ("v" .. tostring(self.next_value))
    if not name then self.next_value = self.next_value + 1 end
    local v = { id = id, ty = ty, facts = copy_array(facts), residency = residency }
    self.values[id] = v
    self.stats.values = self.stats.values + 1
    return id
end

function Graph:value(v) return self.values[v] end

function Graph:add(op, t)
    t = t or {}
    local effect = t.effect or "none"
    if effect == "return" then effect = "return_" end
    if not EFFECTS[effect] then effect = "none" end
    local n = {
        id = self.next_node,
        op = op,
        codegen_op = t.codegen_op or CODEGEN_OP[op] or op,
        inputs = copy_array(t.inputs),
        outputs = copy_array(t.outputs),
        args = t.args or {},
        effect = effect,
        mem_in = t.mem_in or {},
        mem_out = t.mem_out or {},
        guard = t.guard,
        exit = t.exit,
        deps = copy_array(t.deps),
        source = t.source,
        removed = false,
        remove_reason = nil,
    }
    self.next_node = self.next_node + 1
    self.nodes[#self.nodes + 1] = n
    if effect == "guard" then self.stats.guards = self.stats.guards + 1 end
    if HARD_BARRIER[op] then self.stats.barriers = self.stats.barriers + 1 end
    return n
end

function Graph:exit_projection(reason, pc, live_slots, virtual_values)
    return {
        reason = reason or "guard_exit",
        pc = pc or 0,
        live_slots = copy_array(live_slots or { "cur" }),
        virtual_values = copy_array(virtual_values or {}),
        ok = true,
    }
end

function Graph:guard(subject, fact, op, pc)
    local guard_op = op
    if not guard_op then
        if fact.predicate == "is_i64" then guard_op = "GuardTypeI64"
        elseif fact.predicate == "is_table" then guard_op = "GuardTable"
        elseif fact.predicate == "shape_known" or fact.predicate == "shape_eq" then guard_op = "GuardShape"
        elseif fact.predicate == "metatable_absent" then guard_op = "GuardMetatableAbsent"
        elseif fact.predicate == "known_call_target" or fact.predicate == "target_eq" then guard_op = "GuardCallTarget"
        elseif fact.predicate == "array_hit" then guard_op = "GuardArrayHit"
        elseif fact.predicate == "bounds_ok" then guard_op = "GuardBounds"
        else guard_op = "Guard" end
    end
    return self:add(guard_op, {
        inputs = { subject },
        effect = "guard",
        guard = { fact = fact, key = Facts.guard_key(fact) },
        exit = self:exit_projection("guard:" .. tostring(fact.predicate), pc),
        deps = copy_array(fact.deps),
    })
end

function Graph:frame_load(slot, ty, pc)
    local out = self:new_value(ty or "TValue")
    self:add("FrameLoad", {
        outputs = { out }, source = pc, effect = "frame_read",
        mem_in = { frame = self.mem.frame }, args = { slot = slot or "cur" },
    })
    self.current = out
    return out
end

function Graph:frame_store(slot, value, pc)
    local newm = self:new_memory("frame", "store:" .. tostring(slot or "cur"))
    self:add("FrameStore", {
        inputs = { value }, source = pc, effect = "frame_write",
        mem_in = { frame = self.mem.frame }, mem_out = { frame = newm }, args = { slot = slot or "cur" },
    })
    self.mem.frame = newm
    self.current = value
end

function Graph:slot_value(slot)
    if self.current then return self.current end
    return self:frame_load(slot or "cur", "TValue")
end

function Graph:store_current(value, slot, pc)
    self:frame_store(slot or "cur", value, pc)
end

function Graph:const_i64(value, pc)
    local out = self:new_value("I64")
    self:add("ConstI64", { outputs = { out }, source = pc, args = { value = value } })
    self.current = out
    return out
end

function Graph:load_const(k, pc)
    local out = self:new_value("TValue")
    self:add("LoadConst", { outputs = { out }, source = pc, args = { const = k } })
    self.current = out
    return out
end

function Graph:const_bool(value, pc)
    local out = self:new_value("TValue")
    self:add("ConstBool", { outputs = { out }, source = pc, args = { value = value and true or false } })
    self.current = out
    return out
end

function Graph:const_nil(pc)
    local out = self:new_value("TValue")
    self:add("ConstNil", { outputs = { out }, source = pc })
    self.current = out
    return out
end

function Graph:unbox_i64(v, pc)
    local out = self:new_value("I64", nil, nil, "gpr0")
    self:add("UnboxI64", { inputs = { v }, outputs = { out }, source = pc })
    self.current = out
    return out
end

function Graph:box_i64(v, pc)
    local out = self:new_value("TValue")
    self:add("BoxI64", { inputs = { v }, outputs = { out }, source = pc })
    self.current = out
    return out
end

function Graph:i64_arith(op, lhs, rhs, pc)
    local map = { ADD = "AddI64", ADDI = "AddI64", SUB = "SubI64", MUL = "MulI64" }
    local out = self:new_value("I64", nil, nil, "gpr0")
    self:add(map[op] or op, { inputs = { lhs, rhs }, outputs = { out }, source = pc })
    self.current = out
    return out
end

function Graph:field_load(tab, key, pc)
    local out = self:new_value("TValue")
    self:add("FieldLoad", {
        inputs = { tab }, outputs = { out }, source = pc, effect = "heap_read",
        mem_in = { table = self.mem.table }, args = { key = key or "const_key" },
    })
    self.current = out
    return out
end

function Graph:field_store(tab, key, val, pc)
    local newm = self:new_memory("table", "field_store")
    self:add("FieldStore", {
        inputs = { tab, val }, source = pc, effect = "heap_write",
        mem_in = { table = self.mem.table }, mem_out = { table = newm }, args = { key = key or "const_key" },
    })
    self.mem.table = newm
end

function Graph:array_load(tab, pc)
    local out = self:new_value("TValue")
    self:add("ArrayLoad", { inputs = { tab }, outputs = { out }, source = pc, effect = "heap_read", mem_in = { table = self.mem.table } })
    self.current = out
    return out
end

function Graph:array_store(tab, val, pc)
    local newm = self:new_memory("table", "array_store")
    self:add("ArrayStore", { inputs = { tab, val }, source = pc, effect = "heap_write", mem_in = { table = self.mem.table }, mem_out = { table = newm } })
    self.mem.table = newm
end

function Graph:barrier(tab, val, pc)
    local newm = self:new_memory("gc", "barrier")
    self:add("BarrierCheck", {
        inputs = { tab, val }, source = pc, effect = "gc_barrier",
        mem_in = { gc = self.mem.gc }, mem_out = { gc = newm },
        exit = self:exit_projection("barrier_slow_path", pc),
    })
    self.mem.gc = newm
end

function Graph:call(kind, fn, pc)
    local op = kind == "known" and "KnownCall" or "Call"
    local out = self:new_value("TValue")
    local new_call = self:new_memory("call", "call")
    self:add(op, {
        inputs = { fn }, outputs = { out }, source = pc, effect = "call",
        mem_in = { call = self.mem.call, frame = self.mem.frame, table = self.mem.table, gc = self.mem.gc },
        mem_out = { call = new_call },
        exit = self:exit_projection("call_exit", pc),
    })
    self.mem.call = new_call
    self.current = out
    return out
end

function Graph:residual(opcode, inputs, pc)
    local out = self:new_value("TValue")
    self:add("Residual", {
        inputs = copy_array(inputs or {}), outputs = { out }, source = pc,
        effect = "residual", args = { opcode = opcode },
        exit = self:exit_projection("residual:" .. tostring(opcode), pc),
    })
    self.current = out
    return out
end

function Graph:return1(v, pc)
    self:add("Return1", { inputs = { v }, source = pc, effect = "return", exit = self:exit_projection("return", pc) })
end

function Graph:return0(pc)
    self:add("Return0", { source = pc, effect = "return", exit = self:exit_projection("return", pc) })
end

function Graph:active_nodes()
    local out = {}
    for _, n in ipairs(self.nodes) do if not n.removed then out[#out + 1] = n end end
    return out
end

function Graph:active_codegen_ops()
    local out = {}
    for _, n in ipairs(self.nodes) do if not n.removed and n.codegen_op then out[#out + 1] = n.codegen_op end end
    return out
end

function Graph:validate()
    local errors = {}
    for _, n in ipairs(self.nodes) do
        if not n.removed then
            if n.effect == "guard" and not n.exit then errors[#errors + 1] = "guard without exit at node " .. n.id end
            if (n.effect == "residual" or n.effect == "call") and not n.exit then errors[#errors + 1] = n.effect .. " without exit at node " .. n.id end
            for _, v in ipairs(n.inputs or {}) do if not self.values[v] then errors[#errors + 1] = "unknown input " .. tostring(v) .. " at node " .. n.id end end
            for _, v in ipairs(n.outputs or {}) do if not self.values[v] then errors[#errors + 1] = "unknown output " .. tostring(v) .. " at node " .. n.id end end
        end
    end
    return #errors == 0, errors
end

function Graph:canonical_lines()
    local lines = {}
    for _, n in ipairs(self.nodes) do
        if not n.removed then
            local args = {}
            for _, k in ipairs(sorted_keys(n.args or {})) do args[#args + 1] = tostring(k) .. "=" .. tostring(n.args[k]) end
            local guard = n.guard and n.guard.key or ""
            lines[#lines + 1] = table.concat({ n.op, table.concat(n.inputs or {}, ","), table.concat(n.outputs or {}, ","), n.effect, guard, table.concat(args, ",") }, ";")
        end
    end
    return lines
end

return M
