package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Run = require("moonlift.mlua_run")

local src = [[
local pvmll = require("moonlift.pvm_ll")
assert(pvmll._VERSION == "pvm-ll-2")

-- ── Scalar phase ──

local classify_uncached = region classify_uncached(ctx: ptr(u8), subject: i32;
    value: cont(v: i32))
entry start()
    switch subject do
    case 0 then jump value(v = 11)
    case 1 then jump value(v = 22)
    default then jump value(v = 99)
    end
end
end

local classify = pvmll.one {
    name       = "classify",
    uncached   = classify_uncached,
    ctx_ty     = pvmll.ptr(pvmll.u8),
    subject_ty = pvmll.i32,
    value_ty   = pvmll.i32,
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

-- ── Stream phase ──

local sink = pvmll.append_sink {
    name     = "drop_value",
    ctx_ty   = pvmll.ptr(pvmll.u8),
    value_ty = pvmll.i32,
    append   = "append_drop",
}

local facts = region facts(ctx: ptr(u8), subject: i32;
    done: cont())
entry start()
    switch subject do
    case 0 then emit @{sink}(ctx, 10; resume = done)
    case 1 then emit @{sink}(ctx, subject + 20; resume = done)
    default then jump done()
    end
end
end

local stream_mod = module PvmLlStreamTest
func append_drop(ctx: ptr(u8), value: i32) -> i32
    return 0
end

export func run(ctx: ptr(u8), subject: i32) -> i32
    return region -> i32
    entry start()
        emit facts(ctx, subject; done = done)
    end
    block done()  yield 7  end
    end
end
end
local stream_compiled = stream_mod:compile()
local run_fn = stream_compiled:get("run")
assert(run_fn(nil, 0) == 7)
assert(run_fn(nil, 1) == 7)
assert(run_fn(nil, 2) == 7)
stream_compiled:free()

-- ── One with fail ──

local uncached_failable = region uncached_failable(ctx: ptr(u8), subject: i32;
    value: cont(v: i32),
    fail: cont(issue: i32))
entry start()
    if subject < 0 then jump fail(issue = subject) end
    jump value(v = subject + 1)
end
end

local wrapper = pvmll.one {
    name        = "failable",
    uncached    = uncached_failable,
    ctx_ty      = pvmll.ptr(pvmll.u8),
    subject_ty  = pvmll.i32,
    value_ty    = pvmll.i32,
    fail_ty     = pvmll.i32,
}

local test_fail = region test_fail(r: ptr(u8), s: i32; ok: cont(), err: cont(code: i32))
entry start()
    emit @{wrapper}(r, s;
        value = got, fail = got_fail)
end
block got(v: i32)         jump ok() end
block got_fail(issue: i32) jump err(code = issue) end
end

local fail_mod = module PvmLlFailTest
export func run_fail(ctx: ptr(u8), subject: i32) -> i32
    return region -> i32
    entry start()
        emit test_fail(ctx, subject; ok = done, err = err)
    end
    block done()  yield 0  end
    block err(code: i32)  yield code  end
    end
end
end
local fail_compiled = fail_mod:compile()
local run_fail_fn = fail_compiled:get("run_fail")
assert(run_fail_fn(nil, 5) == 0)
assert(run_fail_fn(nil, -3) == -3)
fail_compiled:free()

return "moonlift pvm_ll ok"
]]

local ok, result = pcall(Run.eval, src, "=test_pvm_ll")
if not ok then
    io.stderr:write(tostring(result) .. "\n")
    os.exit(1)
end
assert(result == "moonlift pvm_ll ok")
print(result)
