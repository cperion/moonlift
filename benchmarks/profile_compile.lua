-- Profile Moonlift compile-time boundaries for the current jump-first i32 kernels.
-- Measures explicit phase boundaries rather than sampling Lua internals.

package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local boot_start = os.clock()
local spans = {}
local order = {}

local unpack_ = table.unpack or unpack

local function timed(name, fn)
    local t0 = os.clock()
    local values = { fn() }
    local dt = os.clock() - t0
    spans[name] = (spans[name] or 0) + dt
    order[#order + 1] = name
    return unpack_(values)
end

local function timed_require(name)
    return timed("require " .. name, function() return require(name) end)
end

local ffi = timed_require("ffi")
local pvm = timed_require("moonlift.pvm")
local A2 = timed_require("moonlift.asdl")
local Parse = timed_require("moonlift.parse")
local Typecheck = timed_require("moonlift.tree_typecheck")
local TreeToBack = timed_require("moonlift.tree_to_back")
local Validate = timed_require("moonlift.back_validate")
local J = timed_require("moonlift.back_jit")

local SRC = [[
export func sum_i32(xs: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end

export func dot_i32(a: ptr(i32), b: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + a[i] * b[i])
    end
end

export func add_i32(dst: ptr(i32), a: ptr(i32), b: ptr(i32), n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = a[i] + b[i]
        jump loop(i = i + 1)
    end
end

export func scale_i32(dst: ptr(i32), xs: ptr(i32), k: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i] = xs[i] * k
        jump loop(i = i + 1)
    end
end
]]

local T = timed("pvm.context", function() return pvm.context() end)
timed("Define moonlift.asdl", function() A2.Define(T) end)
local P = timed("Define parse API", function() return Parse.Define(T) end)
local TC = timed("Define typecheck phases", function() return Typecheck.Define(T) end)
local Lower = timed("Define tree_to_back phases", function() return TreeToBack.Define(T) end)
local V = timed("Define back_validate phases", function() return Validate.Define(T) end)
local jit_api = timed("Define back_jit API", function() return J.Define(T) end)

local parsed = timed("parse", function() return P.parse_module(SRC) end)
assert(#parsed.issues == 0, "parse issues: " .. #parsed.issues)
local checked = timed("typecheck", function() return TC.check_module(parsed.module) end)
assert(#checked.issues == 0, "type issues: " .. #checked.issues)
local program = timed("tree_to_back", function() return Lower.module(checked.module) end)
local report = timed("back_validate", function() return V.validate(program) end)
assert(#report.issues == 0, "back validation issues: " .. #report.issues)
local jit = timed("jit_create", function() return jit_api.jit() end)
local artifact = timed("back_jit_cranelift_compile", function() return jit:compile(program) end)

local B2 = T.Moon2Back
local sum_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t)", artifact:getpointer(B2.BackFuncId("sum_i32")))
local xs = ffi.new("int32_t[8]", { 3, 20, 37, 54, 71, 88, 105, 122 })
assert(sum_i32(xs, 8) == 500)

local compile_core = (spans.parse or 0) + (spans.typecheck or 0) + (spans.tree_to_back or 0) + (spans.back_validate or 0) + (spans.back_jit_cranelift_compile or 0)
local phase_total = compile_core + (spans.jit_create or 0)
local boot_total = os.clock() - boot_start

local function ms(x) return x * 1000 end
local function pct(x, total) if total == 0 then return 0 end return x * 100 / total end

io.write("Moonlift compile-time profile: jump-first i32 kernels\n\n")
io.write(string.format("source_bytes %d\n", #SRC))
io.write(string.format("items %d\n", #checked.module.items))
io.write(string.format("moon2_back_cmds %d\n\n", #program.cmds))

io.write("Core compile path\n")
io.write(string.format("  %-24s %9.3f ms %6.1f%%\n", "parse", ms(spans.parse or 0), pct(spans.parse or 0, compile_core)))
io.write(string.format("  %-24s %9.3f ms %6.1f%%\n", "typecheck", ms(spans.typecheck or 0), pct(spans.typecheck or 0, compile_core)))
io.write(string.format("  %-24s %9.3f ms %6.1f%%\n", "tree_to_back", ms(spans.tree_to_back or 0), pct(spans.tree_to_back or 0, compile_core)))
io.write(string.format("  %-24s %9.3f ms %6.1f%%\n", "back_validate", ms(spans.back_validate or 0), pct(spans.back_validate or 0, compile_core)))
io.write(string.format("  %-24s %9.3f ms %6.1f%%\n", "back_jit+cranelift", ms(spans.back_jit_cranelift_compile or 0), pct(spans.back_jit_cranelift_compile or 0, compile_core)))
io.write(string.format("  %-24s %9.3f ms %6.1f%%\n\n", "TOTAL", ms(compile_core), 100.0))

io.write("Setup / load costs in this process\n")
io.write(string.format("  %-24s %9.3f ms\n", "jit_create", ms(spans.jit_create or 0)))
io.write(string.format("  %-24s %9.3f ms\n", "core+jit_create", ms(phase_total)))
io.write(string.format("  %-24s %9.3f ms\n\n", "script_total", ms(boot_total)))

local function report_phases(phases)
    local filtered = {}
    for i = 1, #phases do
        if type(phases[i]) == "table" and type(phases[i].stats) == "function" then
            filtered[#filtered + 1] = phases[i]
        end
    end
    if #filtered == 0 then return "  <no exported pvm phases>" end
    return pvm.report_string(filtered)
end

io.write("PVM cache diagnostics\n")
io.write("typecheck phases:\n")
io.write(report_phases({ TC.expr, TC.place, TC.stmt, TC.stmt_body, TC.control_stmt_region, TC.control_expr_region, TC.func, TC.item, TC.module }) .. "\n")
io.write("tree_to_back phases:\n")
io.write(report_phases({ Lower.expr_to_back, Lower.stmt_to_back, Lower.func_to_back, Lower.item_to_back, Lower.module_to_back }) .. "\n")
io.write("back_validate phases:\n")
io.write(report_phases({ V.cmd_facts, V.validate_program }) .. "\n")
if os.getenv("MOONLIFT2_PROFILE_DISASM") == "1" then
    io.stderr:write(artifact:disasm("sum_i32", { bytes = 260 }) .. "\n")
end

artifact:free()
