-- Named opcode continuation protocols.
-- This is the only place opcode-handler continuation signatures are assembled.

local P = {}

P.conts = {
    next = "next: cont(frame: ptr(Frame), pc: index, base: index, top: index)",
    do_jump = "do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index)",
    enter_lua = "enter_lua: cont(child: ptr(Frame))",
    enter_native = "enter_native: cont(cl: ptr(CClosure), ctx: NativeCallContext)",
    yielded = "yielded: cont(nres: i32)",
    error = "error: cont(code: i32)",
    oom = "oom: cont()",
    resume_parent = "resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index)",
    finished = "finished: cont(nres: i32)",
}

P.protocols = {
    next_only = { "next" },
    table = { "next", "enter_lua", "enter_native", "yielded", "error", "oom" },
    compare = { "next", "do_jump", "enter_lua", "enter_native", "yielded", "error", "oom" },
    call = { "next", "enter_lua", "enter_native", "yielded", "error", "oom" },
    ret = { "resume_parent", "finished", "error", "oom" },
    mmbin = { "enter_lua", "enter_native", "yielded", "error", "oom" },
    tforcall = { "enter_lua", "enter_native", "yielded", "error", "oom" },
    arith = { "next", "error" },
}

function P.signature(name)
    local p = assert(P.protocols[name], "unknown opcode protocol " .. tostring(name))
    local out = {}
    for i, cont_name in ipairs(p) do
        out[i] = assert(P.conts[cont_name], "unknown opcode continuation " .. tostring(cont_name))
    end
    return table.concat(out, ",\n               ")
end

function P.handler_params()
    return "L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index, a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32, ax: u32, sj: i32, sc: i32, vb: u16, vc: u16"
end

return P
