package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Harness = require("tests.c_backend.test_c_gcc_harness")
local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")
local Pipeline = require("moonlift.frontend_pipeline")
local Coverage = require("moonlift.c_coverage")

if not Harness.have_cc() then
    io.write("C compiler not found; skipping C compiler/TCC feature corpus\n")
    os.exit(0)
end

local function c11_atomics_available()
    local src = [[#include <stdatomic.h>
int main(void) { _Atomic(int) x; atomic_init(&x, 0); return atomic_fetch_add_explicit(&x, 1, memory_order_seq_cst); }
]]
    local ok = pcall(function()
        local artifact = Harness.compile_c(src, { name = "probe_c11_atomics", cflags = "-std=c11 -Wall -Wextra" })
        if artifact.cleanup then os.remove(artifact.c_path); os.remove(artifact.exe_path) end
    end)
    return ok
end

local cases = {
    {
        name = "scalars_casts_div_rem_shift_bool_select_logic",
        src = [[
func feature_scalar(a: i32, b: i32): i32
    let lo: i32 = as(i32, as(u8, a))
    let shifted: i32 = (b << 1) + (b >> 1)
    let q: i32 = (a / 3) + (a % 5)
    return select((lo >= 0) and (b ~= 0), q + shifted, 0)
end
]],
        func = "feature_scalar", args = { "260", "6" }, expected = 101,
    },
    {
        name = "regions_nonterminal_if_switch_expression_block_assignment",
        src = [[
func feature_control(n: i32): i32
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
]],
        func = "feature_control", args = { "5" }, expected = 61,
    },
    {
        name = "pointers_deref_load_store",
        src = [[
func feature_ptr(p: ptr(i32)): i32
    p[1] = 41
    p[2] = 1
    return *(&p[1]) + p[2]
end
]],
        main = Harness.main_for_return("feature_ptr", { "xs" }, 42):gsub("int main%(void%) {", "int main(void) { int32_t xs[4] = {0,0,0,0};"),
    },
    {
        name = "struct_fields_and_mutation",
        src = [[
struct Pair
    x: i32,
    y: i32,
end
func feature_pair(p: ptr(Pair), v: i32): i32
    (*p).y = v
    return (*p).x + (*p).y
end
]],
        main = [[
int main(void) {
    struct _Pair p;
    p.x = 10;
    p.y = 0;
    long long got = (long long)feature_pair(&p, 32);
    if (got != 42) return 100;
    return 0;
}
]],
    },
    {
        name = "externs",
        src = [[
extern host_add7(x: i32): i32 end
func feature_extern(x: i32): i32
    return host_add7(x)
end
]],
        main = [[
int32_t host_add7(int32_t x) { return x + 7; }
int main(void) {
    long long got = (long long)feature_extern(35);
    if (got != 42) return 100;
    return 0;
}
]],
    },
    {
        name = "aggregate_literals",
        src = [[
struct Pair
    x: i32,
    y: i32,
end
func feature_array_agg(): i32
    let p: Pair = Pair{ x = 10, y = 20 }
    return p.x + p.y + 12
end
]],
        func = "feature_array_agg", args = {}, expected = 42,
    },
    {
        name = "string_data_global",
        src = [[
func feature_string_data(): i32
    let p: ptr(u8) = "ABC"
    return as(i32, p[0]) + as(i32, p[1]) - 89
end
]],
        func = "feature_string_data", args = {}, expected = 42,
    },
    {
        name = "views_strided_indexing",
        src = [[
func feature_view(v: view(i32)): i32
    return v[2]
end
]],
        main = [[
int main(void) {
    int32_t xs[8] = {1,2,3,4,5,6,7,8};
    ml_view_CBackendScalar_ScalarI32 v = { xs, 4, 2 };
    long long got = (long long)feature_view(v);
    if (got != 5) return 100;
    return 0;
}
]],
    },
    {
        name = "function_pointers",
        src = [[
func callee(x: i32): i32
    return x + 1
end
func feature_fp(fp: func(i32): i32, x: i32): i32
    return fp(x)
end
]],
        main = [[
int main(void) {
    long long got = (long long)feature_fp(callee, 41);
    if (got != 42) return 100;
    return 0;
}
]],
    },
    {
        name = "closure_descriptor_calls",
        src = [[
func feature_closure(f: closure(i32): i32, x: i32): i32
    return f(x)
end
]],
        main = [[
int32_t closure_add_ctx(void* ctx, int32_t x) { (void)ctx; return x + 1; }
int main(void) {
    ml_closure_closure_codesig_i32_to_i32 f = { closure_add_ctx, 0 };
    long long got = (long long)feature_closure(f, 41);
    if (got != 42) return 100;
    return 0;
}
]],
    },
    {
        name = "tagged_unions_source",
        src = [[
union Maybe
    some(i32)
  | none(void)
end
func feature_tagged(x: i32): i32
    let m = Maybe.some(x)
    return switch m do
    case .some(v) then v + 1
    default then 0
    end
end
]],
        func = "feature_tagged", args = { "41" }, expected = 42,
    },
    {
        name = "c11_atomics",
        requires = c11_atomics_available,
        skip_reason = "selected C compiler does not provide C11 <stdatomic.h>",
        src = [[
func feature_atomic(p: ptr(i32)): i32
    atomic_store(i32, p, 10)
    let old: i32 = atomic_fetch_add(i32, p, 5)
    let seen: i32 = atomic_cas(i32, p, 15, 21)
    atomic_fence()
    let after: i32 = atomic_load(i32, p)
    return old + seen + after
end
]],
        main = [[
int main(void) {
    int32_t x = 0;
    long long got = (long long)feature_atomic(&x);
    if (got != 46) return 100;
    if (x != 21) return 101;
    return 0;
}
]],
        opts = { emit_opts = { c_target = { dialect = "c11" } }, cflags = "-std=c11 -Wall -Wextra" },
    },
}

local skipped = {}
for i = 1, #cases do
    local c = cases[i]
    if c.requires and not c.requires() then
        skipped[#skipped + 1] = c.name .. ": " .. (c.skip_reason or "unavailable")
    else
        local opts = c.opts or {}
        opts.name = "feature_" .. c.name
        if c.main then opts.main = c.main end
        if c.func then
            Harness.assert_return(c.src, c.func, c.args, c.expected, opts)
        else
            Harness.compile_run(c.src, opts)
        end
    end
end

do
    assert(Coverage.classification("MoonType.ArrayLen", "ArrayLenExpr").status == "language_rejected")
    assert(Coverage.classification("MoonTree.Item", "ItemImport").status == "phase_unreachable")

    local T = pvm.context(); Schema.Define(T)
    local Core = T.MoonCore
    local Tr = T.MoonTree
    local ok_bad_variant, err_bad_variant = pcall(function()
        Pipeline.Define(T).parse_and_lower_c([[
union Maybe
    some(i32)
  | none
end
func bad_variant(): i32
    let m = Maybe.none()
    return switch m do
    case .missing then 1
    default then 0
    end
end
]], { site = "feature_corpus_bad_variant" })
    end)
    assert(not ok_bad_variant and tostring(err_bad_variant):match("variant"), "unknown variant arm should be rejected before C emission")

    local ok_import, err_import = pcall(function()
        Pipeline.Define(T).lower_module_to_c(Tr.Module(Tr.ModuleSurface, { Tr.ItemImport(Tr.ImportItem(Core.Path({ Core.Name("missing") }))) }), { site = "feature_corpus_import_boundary" })
    end)
    assert(not ok_import and tostring(err_import):match("tree_to_code/code_to_c"), "unresolved import should fail at C phase boundary")
end

io.write("moonlift C compiler/TCC feature corpus ok")
if #skipped > 0 then io.write(" (skipped: ", table.concat(skipped, "; "), ")") end
io.write("\n")
