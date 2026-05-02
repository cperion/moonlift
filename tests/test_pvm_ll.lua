package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.host_quote")

local src = [[
local pvmll = require("moonlift.pvm_ll")
assert(pvmll._VERSION == "pvm-ll-mlua-patterns-1")

-- Users write ordinary MLUA passes.  This is the compiler phase.
local classify_uncached = region classify_uncached(ctx: ptr(u8), subject: i32;
    value: cont(v: i32))
entry start()
    switch subject do
    case 0 then
        jump value(v = 11)
    case 1 then
        jump value(v = 22)
    default then
        jump value(v = 99)
    end
end
end

-- pvm-ll only wraps common phase-boundary patterns.
local classify = pvmll.one {
    name = "classify",
    uncached = classify_uncached,
    ctx_ty = pvmll.ptr(pvmll.u8),
    subject_ty = pvmll.i32,
    value_ty = pvmll.i32,
}

local scalar_mod = module PvmLlScalarTest
export func classify_export(ctx: ptr(u8), subject: i32) -> i32
    return region -> i32
    entry start()
        emit @{classify}(ctx, subject; value = done)
    end
    block done(v: i32)
        yield v
    end
    end
end
end
local scalar_compiled = scalar_mod:compile()
local classify_export = scalar_compiled:get("classify_export")
assert(classify_export(nil, 0) == 11)
assert(classify_export(nil, 1) == 22)
assert(classify_export(nil, 7) == 99)
scalar_compiled:free()

local sink = pvmll.append_sink {
    name = "drop_value",
    ctx_ty = pvmll.ptr(pvmll.u8),
    value_ty = pvmll.i32,
    append = "append_drop",
}

local stream_mod = module PvmLlStreamTest
func append_drop(ctx: ptr(u8), value: i32) -> i32
    return 0
end

region facts(ctx: ptr(u8), subject: i32;
    done: cont())
entry start()
    switch subject do
    case 0 then
        emit @{sink}(ctx, 10; resume = done)
    case 1 then
        emit @{sink}(ctx, subject + 20; resume = done)
    default then
        jump done()
    end
end
end

export func run(ctx: ptr(u8), subject: i32) -> i32
    return region -> i32
    entry start()
        emit facts(ctx, subject; done = done)
    end
    block done()
        yield 7
    end
    end
end
end
local stream_compiled = stream_mod:compile()
local run = stream_compiled:get("run")
assert(run(nil, 0) == 7)
assert(run(nil, 1) == 7)
assert(run(nil, 2) == 7)
stream_compiled:free()

return "moonlift pvm_ll ok"
]]

local result = Host.eval(src, "=test_pvm_ll")
assert(result == "moonlift pvm_ll ok")
io.write(result .. "\n")
