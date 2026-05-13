-- Tape × Memory product-space experiment
--
-- Goal:
--   Treat optimization facts + GC facts as one runtime fact stream.
--   Every executed op has two projections:
--     (1) tape projection (recorded op, maybe folded)
--     (2) memory projection (slot/heap mutation)
--   Maintain invariants in Tape × Mem.

local function ptr(id)
    return { kind = "ptr", id = id }
end

local function is_ptr(v)
    return type(v) == "table" and v.kind == "ptr" and type(v.id) == "number"
end

local function clone_value(v)
    if is_ptr(v) then
        return ptr(v.id)
    end
    return v
end

local function value_eq(a, b)
    if is_ptr(a) and is_ptr(b) then
        return a.id == b.id
    end
    return a == b
end

local function value_str(v)
    if is_ptr(v) then
        return "ptr(" .. tostring(v.id) .. ")"
    end
    return tostring(v)
end

local function record_event(state, ev)
    state.facts.events[#state.facts.events + 1] = ev
end

local function emit_tape(state, ins)
    state.tape[#state.tape + 1] = ins
    return #state.tape
end

local function compute_reachable(slots, heap)
    local reachable = {}
    local work = {}

    local function mark_ptr(p)
        if not is_ptr(p) then return end
        local id = p.id
        if reachable[id] then return end
        local obj = heap[id]
        if not obj or not obj.alive then return end
        reachable[id] = true
        work[#work + 1] = id
    end

    for _, v in pairs(slots) do
        mark_ptr(v)
    end

    while #work > 0 do
        local id = work[#work]
        work[#work] = nil
        local obj = heap[id]
        if obj and obj.alive then
            for _, fv in pairs(obj.fields) do
                mark_ptr(fv)
            end
        end
    end

    return reachable
end

local function gc_cycle(slots, heap)
    for _, obj in pairs(heap) do
        if obj.alive then
            obj.marked = false
        end
    end

    local reachable = compute_reachable(slots, heap)
    for id, _ in pairs(reachable) do
        local obj = heap[id]
        if obj and obj.alive then
            obj.marked = true
        end
    end

    local swept = 0
    for _, obj in pairs(heap) do
        if obj.alive and not obj.marked then
            obj.alive = false
            swept = swept + 1
        end
    end

    return swept
end

local function replay_tape(tape)
    local slots = {}
    local heap = {}
    local next_obj = 1

    for _, ins in ipairs(tape) do
        if ins.op == "KINT" or ins.op == "FOLD_KINT" then
            slots[ins.dst] = ins.k

        elseif ins.op == "ADD" then
            slots[ins.dst] = slots[ins.a] + slots[ins.b]

        elseif ins.op == "NEWOBJ" then
            local id = next_obj
            next_obj = next_obj + 1
            heap[id] = { alive = true, marked = false, fields = {} }
            slots[ins.dst] = ptr(id)

        elseif ins.op == "SETFIELD" then
            local p = slots[ins.obj]
            if is_ptr(p) then
                local obj = heap[p.id]
                if obj and obj.alive then
                    obj.fields[ins.field] = clone_value(slots[ins.src])
                end
            end

        elseif ins.op == "GETFIELD" then
            local p = slots[ins.obj]
            local out = nil
            if is_ptr(p) then
                local obj = heap[p.id]
                if obj and obj.alive then
                    out = clone_value(obj.fields[ins.field])
                end
            end
            slots[ins.dst] = out

        elseif ins.op == "GC_CYCLE" then
            gc_cycle(slots, heap)
        end
    end

    return slots, heap
end

local function check_slot_coherence(state)
    local rs, rh = replay_tape(state.tape)

    for k, v in pairs(state.slots) do
        if not value_eq(v, rs[k]) then
            return false, "slot mismatch r" .. tostring(k) .. " mem=" .. value_str(v) .. " tape=" .. value_str(rs[k])
        end
    end
    for k, v in pairs(rs) do
        if not value_eq(v, state.slots[k]) then
            return false, "slot mismatch r" .. tostring(k) .. " mem=" .. value_str(state.slots[k]) .. " tape=" .. value_str(v)
        end
    end

    for id, obj in pairs(state.heap) do
        local robj = rh[id]
        if (robj ~= nil) ~= (obj ~= nil) then
            return false, "heap object set mismatch at id " .. tostring(id)
        end
        if robj then
            if obj.alive ~= robj.alive then
                return false, "heap alive mismatch at id " .. tostring(id)
            end
            for f, v in pairs(obj.fields) do
                if not value_eq(v, robj.fields[f]) then
                    return false, "field mismatch obj=" .. tostring(id) .. "." .. tostring(f)
                end
            end
            for f, v in pairs(robj.fields) do
                if not value_eq(v, obj.fields[f]) then
                    return false, "field mismatch obj=" .. tostring(id) .. "." .. tostring(f)
                end
            end
        end
    end

    return true
end

local function check_gc_soundness(state)
    local reachable = compute_reachable(state.slots, state.heap)
    for id, _ in pairs(reachable) do
        local obj = state.heap[id]
        if not obj or not obj.alive then
            return false, "reachable object swept: " .. tostring(id)
        end
    end
    return true
end

local function check_fold_safety(state)
    if state.facts.fold_failures > 0 then
        return false, "fold failures=" .. tostring(state.facts.fold_failures)
    end
    return true
end

local function check_all_invariants(state)
    local ok, msg = check_slot_coherence(state)
    if not ok then return false, "coherence: " .. msg end

    ok, msg = check_gc_soundness(state)
    if not ok then return false, "gc: " .. msg end

    ok, msg = check_fold_safety(state)
    if not ok then return false, "fold: " .. msg end

    return true
end

local function run(program)
    local state = {
        pc = 1,
        slots = {},
        heap = {},
        next_obj = 1,
        tape = {},
        facts = {
            slot_type = {},
            const_slot = {},
            events = {},
            fold_checks = 0,
            fold_failures = 0,
        },
    }

    while true do
        local ins = program[state.pc]
        if not ins then
            break
        end

        if ins.op == "HALT" then
            print(string.format("step %02d  HALT", state.pc))
            break
        end

        if ins.op == "KINT" then
            state.slots[ins.dst] = ins.k
            state.facts.slot_type[ins.dst] = "i64"
            state.facts.const_slot[ins.dst] = ins.k
            emit_tape(state, { op = "KINT", dst = ins.dst, k = ins.k })
            record_event(state, { kind = "const", slot = ins.dst, value = ins.k })

        elseif ins.op == "ADD" then
            local a = state.slots[ins.a]
            local b = state.slots[ins.b]
            local sum = a + b
            state.slots[ins.dst] = sum
            state.facts.slot_type[ins.dst] = "i64"

            local ca = state.facts.const_slot[ins.a]
            local cb = state.facts.const_slot[ins.b]
            if ca ~= nil and cb ~= nil then
                local folded = ca + cb
                state.facts.fold_checks = state.facts.fold_checks + 1
                if folded ~= sum then
                    state.facts.fold_failures = state.facts.fold_failures + 1
                end
                state.facts.const_slot[ins.dst] = folded
                emit_tape(state, { op = "FOLD_KINT", dst = ins.dst, k = folded, from_a = ins.a, from_b = ins.b })
                record_event(state, { kind = "fold", dst = ins.dst, value = folded })
            else
                state.facts.const_slot[ins.dst] = nil
                emit_tape(state, { op = "ADD", dst = ins.dst, a = ins.a, b = ins.b })
                record_event(state, { kind = "arith", dst = ins.dst, op = "ADD" })
            end

        elseif ins.op == "NEWOBJ" then
            local id = state.next_obj
            state.next_obj = state.next_obj + 1
            state.heap[id] = { alive = true, marked = false, fields = {} }
            state.slots[ins.dst] = ptr(id)
            state.facts.slot_type[ins.dst] = "ptr"
            state.facts.const_slot[ins.dst] = nil
            emit_tape(state, { op = "NEWOBJ", dst = ins.dst })
            record_event(state, { kind = "alloc", slot = ins.dst, obj = id })

        elseif ins.op == "SETFIELD" then
            local p = state.slots[ins.obj]
            local v = clone_value(state.slots[ins.src])
            if is_ptr(p) then
                local obj = state.heap[p.id]
                if obj and obj.alive then
                    obj.fields[ins.field] = v
                end
            end
            emit_tape(state, { op = "SETFIELD", obj = ins.obj, field = ins.field, src = ins.src })
            record_event(state, {
                kind = "heap_write",
                obj_slot = ins.obj,
                field = ins.field,
                src = ins.src,
                value = value_str(v),
            })

        elseif ins.op == "GETFIELD" then
            local p = state.slots[ins.obj]
            local out = nil
            if is_ptr(p) then
                local obj = state.heap[p.id]
                if obj and obj.alive then
                    out = clone_value(obj.fields[ins.field])
                end
            end
            state.slots[ins.dst] = out
            state.facts.const_slot[ins.dst] = nil
            state.facts.slot_type[ins.dst] = is_ptr(out) and "ptr" or "unknown"
            emit_tape(state, { op = "GETFIELD", dst = ins.dst, obj = ins.obj, field = ins.field })
            record_event(state, { kind = "heap_read", dst = ins.dst, field = ins.field })

        elseif ins.op == "GC_CYCLE" then
            local swept = gc_cycle(state.slots, state.heap)
            emit_tape(state, { op = "GC_CYCLE" })
            record_event(state, { kind = "gc", swept = swept })

        else
            error("unknown op: " .. tostring(ins.op))
        end

        local ok, msg = check_all_invariants(state)
        local status = ok and "OK" or ("FAIL: " .. msg)
        print(string.format("step %02d  %-10s  %s", state.pc, ins.op, status))
        if not ok then
            error("invariant violation at step " .. tostring(state.pc) .. ": " .. msg)
        end

        state.pc = state.pc + 1
    end

    return state
end

local program = {
    { op = "KINT",   dst = 0, k = 2 },
    { op = "KINT",   dst = 1, k = 40 },
    { op = "ADD",    dst = 2, a = 0, b = 1 },
    { op = "NEWOBJ", dst = 3 },
    { op = "SETFIELD", obj = 3, field = "x", src = 2 },
    { op = "KINT",   dst = 4, k = 1 },
    { op = "ADD",    dst = 2, a = 2, b = 4 },
    { op = "SETFIELD", obj = 3, field = "x", src = 2 },
    { op = "NEWOBJ", dst = 5 },
    { op = "KINT",   dst = 6, k = 99 },
    { op = "SETFIELD", obj = 5, field = "y", src = 6 },
    { op = "KINT",   dst = 5, k = 0 }, -- drop last root to object #2
    { op = "GC_CYCLE" },
    { op = "HALT" },
}

local state = run(program)

print("\n=== Summary ===")
print("tape_len            ", #state.tape)
print("fact_events         ", #state.facts.events)
print("fold_checks         ", state.facts.fold_checks)
print("fold_failures       ", state.facts.fold_failures)

for id, obj in pairs(state.heap) do
    local status = obj.alive and "alive" or "swept"
    print(string.format("heap[%d] %-5s", id, status))
end

print("\nTape projection:")
for i, t in ipairs(state.tape) do
    if t.op == "KINT" or t.op == "FOLD_KINT" then
        print(string.format("  %02d: %-10s r%d <- %s", i, t.op, t.dst, tostring(t.k)))
    elseif t.op == "ADD" then
        print(string.format("  %02d: ADD        r%d <- r%d + r%d", i, t.dst, t.a, t.b))
    elseif t.op == "NEWOBJ" then
        print(string.format("  %02d: NEWOBJ     r%d <- newobj", i, t.dst))
    elseif t.op == "SETFIELD" then
        print(string.format("  %02d: SETFIELD   r%d.%s <- r%d", i, t.obj, t.field, t.src))
    elseif t.op == "GETFIELD" then
        print(string.format("  %02d: GETFIELD   r%d <- r%d.%s", i, t.dst, t.obj, t.field))
    else
        print(string.format("  %02d: %s", i, t.op))
    end
end
