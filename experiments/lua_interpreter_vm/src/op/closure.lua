-- Moonlift VM — Closure/Vararg opcode handlers

local B = require("experiments.lua_interpreter_vm.src.op._init")
local R, H = B.R, B.H

local op_closure = R([[
region op_closure(]] .. H .. [[;
                  next(frame: ptr(Frame), pc: index, base: index, top: index) |
                  error(code: i32) |
                  oom)
entry start()
    let parent: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    if parent == nil then jump error(code = @{ERR_RUNTIME}) end
    if parent.proto == nil then jump error(code = @{ERR_RUNTIME}) end
    let child: ptr(Proto) = parent.proto.children[as(index, bx)]
    emit make_lclosure(L, parent, child, parent.env, base;
        ok = made,
        oom = out_of_mem)
end
block made(cl: ptr(LClosure))
    L.stack[base + as(index, a)] = { tag = @{TAG_LCLOSURE}, aux = 0, bits = as(u64, cl) }
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block out_of_mem()
    jump oom()
end
end
]])

local op_vararg = R([[
region op_vararg(]] .. H .. [[;
                 next(frame: ptr(Frame), pc: index, base: index, top: index) |
                 error(code: i32) |
                 oom)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let fixed: index = as(index, cl.proto.numparams)
    let var_base: index = base + fixed
    var actual: i32 = 0
    if top > var_base then actual = as(i32, top - var_base) end
    if c == 0 then
        jump copy_loop(i = 0, n = actual, wanted = actual, set_open_top = as(u8, 1), var_base = var_base)
    end
    jump copy_loop(i = 0, n = actual, wanted = as(i32, c - 1), set_open_top = as(u8, 0), var_base = var_base)
end
block copy_loop(i: i32, n: i32, wanted: i32, set_open_top: u8, var_base: index)
    if i >= wanted then jump done(wanted = wanted, set_open_top = set_open_top) end
    if i < n then
        L.stack[base + as(index, a) + as(index, i)] = L.stack[var_base + as(index, i)]
    else
        L.stack[base + as(index, a) + as(index, i)] = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    end
    jump copy_loop(i = i + 1, n = n, wanted = wanted, set_open_top = set_open_top, var_base = var_base)
end
block done(wanted: i32, set_open_top: u8)
    let new_top: index = base + as(index, a) + as(index, wanted)
    if set_open_top ~= 0 then
        frame.top = new_top
        L.top = new_top
        jump next(frame = frame, pc = pc + 1, base = base, top = new_top)
    end
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
block stack_err()
    jump error(code = @{ERR_STACK_OVERFLOW})
end
block out_of_mem()
    jump oom()
end
end
]])

local op_getvarg = R([[
region op_getvarg(]] .. H .. [[;
                  next(frame: ptr(Frame), pc: index, base: index, top: index) |
                  error(code: i32) |
                  oom)
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]])

local op_varargprep = R([[
region op_varargprep(]] .. H .. [[;
                     next(frame: ptr(Frame), pc: index, base: index, top: index) |
                     oom)
entry start()
    -- Incoming varargs are already explicit in the frame argument window;
    -- OP_VARARGPREP records no hidden side state.
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

return {
    op_closure = op_closure,
    op_vararg = op_vararg, op_getvarg = op_getvarg, op_varargprep = op_varargprep,
}
