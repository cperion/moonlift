package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("pvm")
local A = require("moonlift.asdl")
local Source = require("moonlift.source")
local J = require("moonlift.jit")

local T = pvm.context()
A.Define(T)
local S = Source.Define(T)
local Back = T.MoonliftBack
local Sem = T.MoonliftSem

-- Create one JIT for all tests
local jit = S.jit()

local function test_intrinsic(name, src, func_name, sig, args, expected)
    local ok, artifact_or_err = pcall(S.compile, src, nil, nil, nil, jit)
    if not ok then
        error(string.format("intrinsic %s compile failed: %s", name, tostring(artifact_or_err)))
    end
    local artifact = artifact_or_err
    local ptr = artifact:getpointer(Back.BackFuncId(func_name))
    local f = ffi.cast(sig, ptr)
    local result
    if type(args) == "table" then
        result = f(unpack(args))
    else
        result = f(args)
    end
    if type(expected) == "string" then
        assert(tostring(result) == expected,
               string.format("intrinsic %s: expected %s, got %s", name, tostring(expected), tostring(result)))
    elseif type(result) == "number" and type(expected) == "number" then
        assert(math.abs(result - expected) < 1e-5,
               string.format("intrinsic %s: expected %s, got %s", name, tostring(expected), tostring(result)))
    else
        assert(result == expected,
               string.format("intrinsic %s: expected %s, got %s", name, tostring(expected), tostring(result)))
    end
    artifact:free()
    print(string.format("  ✓ %s", name))
end

local function test_intrinsic_nocrash(name, src, func_name)
    local ok, artifact_or_err = pcall(S.compile, src, nil, nil, nil, jit)
    if not ok then
        error(string.format("intrinsic %s compile failed: %s", name, tostring(artifact_or_err)))
    end
    local artifact = artifact_or_err
    local ptr = artifact:getpointer(Back.BackFuncId(func_name))
    -- just call it; if it doesn't crash, test passes
    ffi.cast("void (*)()", ptr)()
    artifact:free()
    print(string.format("  ✓ %s (no crash)", name))
end

print("=== Intrinsic tests ===")

-- popcount
test_intrinsic(
    "popcount",
    [[export func popcnt(x: u32) -> u32
    return popcount(x)
end
]],
    "popcnt",
    "uint32_t (*)(uint32_t)",
    0xFF, 8
)
test_intrinsic(
    "popcount zero",
    [[export func popcnt0() -> u32
    return popcount(0)
end
]],
    "popcnt0",
    "uint32_t (*)()",
    {}, 0
)

-- clz
test_intrinsic(
    "clz",
    [[export func clz32(x: u32) -> u32
    return clz(x)
end
]],
    "clz32",
    "uint32_t (*)(uint32_t)",
    0x00000001, 31
)
test_intrinsic(
    "clz zero",
    [[export func clz0() -> u32
    return clz(0)
end
]],
    "clz0",
    "uint32_t (*)()",
    {}, 32
)

-- ctz
test_intrinsic(
    "ctz",
    [[export func ctz32(x: u32) -> u32
    return ctz(x)
end
]],
    "ctz32",
    "uint32_t (*)(uint32_t)",
    0x80000000, 31
)
test_intrinsic(
    "ctz zero",
    [[export func ctz0() -> u32
    return ctz(0)
end
]],
    "ctz0",
    "uint32_t (*)()",
    {}, 32
)

-- rotl
test_intrinsic(
    "rotl",
    [[export func rotl1(x: u32) -> u32
    return rotl(x, 1)
end
]],
    "rotl1",
    "uint32_t (*)(uint32_t)",
    0x80000001, 0x00000003
)
test_intrinsic(
    "rotl no shift",
    [[export func rotl0(x: u32) -> u32
    return rotl(x, 0)
end
]],
    "rotl0",
    "uint32_t (*)(uint32_t)",
    0x12345678, 0x12345678
)

-- rotr
test_intrinsic(
    "rotr",
    [[export func rotr1(x: u32) -> u32
    return rotr(x, 1)
end
]],
    "rotr1",
    "uint32_t (*)(uint32_t)",
    0x80000001, 0xC0000000
)

-- bswap
test_intrinsic(
    "bswap",
    [[export func bswap32(x: u32) -> u32
    return bswap(x)
end
]],
    "bswap32",
    "uint32_t (*)(uint32_t)",
    0x01020304, 0x04030201
)
test_intrinsic(
    "bswap i64",
    [[export func bswap64(x: u64) -> u64
    return bswap(x)
end
]],
    "bswap64",
    "uint64_t (*)(uint64_t)",
    1, "72057594037927936ULL"
)

-- fma (float)
test_intrinsic(
    "fma f32",
    [[export func fma_f32(a: f32, b: f32, c: f32) -> f32
    return fma(a, b, c)
end
]],
    "fma_f32",
    "float (*)(float, float, float)",
    {2.0, 3.0, 4.0}, 10.0
)

-- fma (double)
test_intrinsic(
    "fma f64",
    [[export func fma_f64(a: f64, b: f64, c: f64) -> f64
    return fma(a, b, c)
end
]],
    "fma_f64",
    "double (*)(double, double, double)",
    {2.0, 3.0, 4.0}, 10.0
)

-- sqrt (float)
test_intrinsic(
    "sqrt f32",
    [[export func sqrt_f32(x: f32) -> f32
    return sqrt(x)
end
]],
    "sqrt_f32",
    "float (*)(float)",
    4.0, 2.0
)

-- sqrt (double)
test_intrinsic(
    "sqrt f64",
    [[export func sqrt_f64(x: f64) -> f64
    return sqrt(x)
end
]],
    "sqrt_f64",
    "double (*)(double)",
    9.0, 3.0
)

-- abs (integer)
test_intrinsic(
    "abs i32",
    [[export func abs_i32(x: i32) -> i32
    return abs(x)
end
]],
    "abs_i32",
    "int32_t (*)(int32_t)",
    -5, 5
)
test_intrinsic(
    "abs i32 positive",
    [[export func abs_i32_pos(x: i32) -> i32
    return abs(x)
end
]],
    "abs_i32_pos",
    "int32_t (*)(int32_t)",
    7, 7
)

-- abs (float)
test_intrinsic(
    "abs f32",
    [[export func abs_f32(x: f32) -> f32
    return abs(x)
end
]],
    "abs_f32",
    "float (*)(float)",
    -3.14, 3.14
)

-- floor
test_intrinsic(
    "floor f64",
    [[export func floor_f64(x: f64) -> f64
    return floor(x)
end
]],
    "floor_f64",
    "double (*)(double)",
    2.7, 2.0
)
test_intrinsic(
    "floor negative",
    [[export func floor_neg(x: f64) -> f64
    return floor(x)
end
]],
    "floor_neg",
    "double (*)(double)",
    -2.7, -3.0
)

-- ceil
test_intrinsic(
    "ceil f64",
    [[export func ceil_f64(x: f64) -> f64
    return ceil(x)
end
]],
    "ceil_f64",
    "double (*)(double)",
    2.1, 3.0
)
test_intrinsic(
    "ceil negative",
    [[export func ceil_neg(x: f64) -> f64
    return ceil(x)
end
]],
    "ceil_neg",
    "double (*)(double)",
    -2.1, -2.0
)

-- trunc_float
test_intrinsic(
    "trunc_float f64",
    [[export func trunc_f64(x: f64) -> f64
    return trunc_float(x)
end
]],
    "trunc_f64",
    "double (*)(double)",
    2.7, 2.0
)
test_intrinsic(
    "trunc_float negative",
    [[export func trunc_neg(x: f64) -> f64
    return trunc_float(x)
end
]],
    "trunc_neg",
    "double (*)(double)",
    -2.7, -2.0
)

-- round (nearest, ties to even per Cranelift default)
test_intrinsic(
    "round f64",
    [[export func round_f64(x: f64) -> f64
    return round(x)
end
]],
    "round_f64",
    "double (*)(double)",
    2.5, 2.0
)
test_intrinsic(
    "round f64 up",
    [[export func round_up(x: f64) -> f64
    return round(x)
end
]],
    "round_up",
    "double (*)(double)",
    2.6, 3.0
)

-- trap (stmt form, must not be called)
-- We test that a function that *never* hits the trap compiles and runs normally.
test_intrinsic_nocrash(
    "trap (unreachable)",
    [[export func trap_unreachable() -> void
    if false then
        trap()
    end
    return
end
]],
    "trap_unreachable"
)

-- assume (stmt form, condition true should be no-op)
test_intrinsic_nocrash(
    "assume (true)",
    [[export func assume_passes() -> void
    let x: i32 = 1
    assume(x == 1)
    return
end
]],
    "assume_passes"
)

-- assume (stmt form, condition false triggers trap but we won't call it)
test_intrinsic_nocrash(
    "assume (unreachable false)",
    [[export func assume_unreachable() -> void
    if false then
        assume(false)
    end
    return
end
]],
    "assume_unreachable"
)

print()
print("All intrinsic tests passed.")

jit:free()
