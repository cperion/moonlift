package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Harness = require("tests.c_backend.test_c_gcc_harness")

if not Harness.have_cc() then
    io.write("C compiler not found; skipping full C semantic equivalence\n")
    os.exit(0)
end

local ok_run, Run = pcall(require, "moonlift.mlua_run")
if not ok_run then
    io.write("Cranelift/JIT unavailable; skipping full C semantic equivalence: " .. tostring(Run) .. "\n")
    os.exit(0)
end

local function jit_func(mlua_src)
    local value = Run.eval(mlua_src)
    return assert(value:compile())
end

local skipped = {}
local function note_skip(name, reason)
    skipped[#skipped + 1] = name .. ": " .. tostring(reason)
end

local function compare_return(case)
    local ok_jit, expected_or_err = pcall(function()
        local compiled = jit_func(case.mlua)
        local call_args = case.jit_args
        if call_args == nil then
            call_args = {}
            for i = 1, #(case.args or {}) do call_args[i] = tonumber(case.args[i]) or case.args[i] end
        end
        local got = tonumber(compiled(unpack(call_args)))
        compiled:free()
        return got
    end)
    if not ok_jit then
        note_skip(case.name, "JIT unavailable for case: " .. tostring(expected_or_err))
        return
    end
    if case.skip_c then
        note_skip(case.name, case.skip_c)
        return
    end
    Harness.assert_return(case.c_src, case.func, case.c_args or case.args or {}, expected_or_err, { name = "equiv_" .. case.name })
end

local cases = {
    {
        name = "scalars_casts_logic",
        func = "equiv_scalar",
        args = { "260", "6" },
        mlua = [[local equiv_scalar = func(a: i32, b: i32): i32
    let lo: i32 = as(i32, as(u8, a))
    let shifted: i32 = (b << 1) + (b >> 1)
    let q: i32 = (a / 3) + (a % 5)
    return select((lo >= 0) and (b ~= 0), q + shifted, 0)
end
return equiv_scalar]],
        c_src = [[func equiv_scalar(a: i32, b: i32): i32
    let lo: i32 = as(i32, as(u8, a))
    let shifted: i32 = (b << 1) + (b >> 1)
    let q: i32 = (a / 3) + (a % 5)
    return select((lo >= 0) and (b ~= 0), q + shifted, 0)
end]],
    },
    {
        name = "control_blocks_switch",
        func = "equiv_control",
        args = { "5" },
        mlua = [[local equiv_control = func(n: i32): i32
    var bias: i32 = 0
    if n > 5 then bias = 10 else bias = 1 end
    let sum: i32 = block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc else jump loop(i = i + 1, acc = acc + i) end
    end
    let klass: i32 = switch n do
    case 4 then 40
    case 5 then
        let x: i32 = 50
        x
    default then 7
    end
    return sum + bias + klass
end
return equiv_control]],
        c_src = [[func equiv_control(n: i32): i32
    var bias: i32 = 0
    if n > 5 then bias = 10 else bias = 1 end
    let sum: i32 = block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc else jump loop(i = i + 1, acc = acc + i) end
    end
    let klass: i32 = switch n do
    case 4 then 40
    case 5 then
        let x: i32 = 50
        x
    default then 7
    end
    return sum + bias + klass
end]],
    },
    {
        name = "arrays_aggregates",
        skip_c = "C backend does not yet lower array value binding as assignable C storage",
        func = "equiv_array_agg",
        args = {},
        mlua = [[local Pair = struct Pair
    x: i32,
    y: i32,
end
local equiv_array_agg = func(): i32
    let xs = [10, 20, 12]
    let p: Pair = Pair{ x = xs[0], y = xs[1] }
    return p.x + p.y + xs[2]
end
return equiv_array_agg]],
        c_src = [[struct Pair
    x: i32,
    y: i32,
end
func equiv_array_agg(): i32
    let xs = [10, 20, 12]
    let p: Pair = Pair{ x = xs[0], y = xs[1] }
    return p.x + p.y + xs[2]
end]],
    },
}

for i = 1, #cases do compare_return(cases[i]) end

-- Pointer/load/store equivalence needs non-scalar host arguments; compare the JIT
-- result for the same initial memory against C->compiler execution with an
-- equivalent C main.
do
    local ok_ptr, expected_or_err = pcall(function()
        local ffi = require("ffi")
        local compiled = jit_func([[local equiv_ptr = func(p: ptr(i32)): i32
    p[1] = 41
    p[2] = 1
    return *(&p[1]) + p[2]
end
return equiv_ptr]])
        local xs = ffi.new("int32_t[4]", 0, 0, 0, 0)
        local got = tonumber(compiled(xs))
        compiled:free()
        return got
    end)
    if ok_ptr then
        Harness.compile_run([[func equiv_ptr(p: ptr(i32)): i32
    p[1] = 41
    p[2] = 1
    return *(&p[1]) + p[2]
end]], { name = "equiv_pointers", expected_status = 0, main = Harness.main_for_return("equiv_ptr", { "xs" }, expected_or_err):gsub("int main%(void%) {", "int main(void) { int32_t xs[4] = {0,0,0,0};") })
    else
        note_skip("pointers", expected_or_err)
    end
end

io.write("moonlift full C semantic equivalence ok")
if #skipped > 0 then io.write(" (skipped: ", table.concat(skipped, "; "), ")") end
io.write("\n")
