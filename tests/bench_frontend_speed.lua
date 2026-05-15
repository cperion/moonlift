package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")

local WARMUP = 50
local TRIALS = 500

-- Moonlift source for MOM
local MOM_SRC = [[
func ret7() -> i32 return 7 end
func add(x: i32, y: i32) -> i32 return x + y end
func mul_add(a: i32, b: i32, c: i32) -> i32 return a * b + c end
func neg(x: i32) -> i32 return -x end
func factorial(n: i32) -> i32
  block loop(i: i32 = 1, acc: i32 = 1)
    if i > n then return acc end
    jump loop(i = i + 1, acc = acc * i)
  end
end
]]

-- .mlua equivalent (Lua host with same Moonlift functions)
local MLUA_SRC = [[
local m = moon.module("bench")
m:export_func("ret7", {}, moon.i32, function(b) b:return_(moon.i32(7)) end)
m:export_func("add", {moon.param("x", moon.i32), moon.param("y", moon.i32)}, moon.i32, function(b)
  local x = b:param("x")
  local y = b:param("y")
  b:return_(b:iadd(x, y))
end)
m:export_func("mul_add", {moon.param("a", moon.i32), moon.param("b", moon.i32), moon.param("c", moon.i32)}, moon.i32, function(b)
  local a = b:param("a")
  local bv = b:param("b")
  local c = b:param("c")
  b:return_(b:iadd(b:imul(a, bv), c))
end)
m:export_func("neg", {moon.param("x", moon.i32)}, moon.i32, function(b)
  local x = b:param("x")
  b:return_(b:ineg(x))
end)
m:export_func("factorial", {moon.param("n", moon.i32)}, moon.i32, function(b)
  local n = b:param("n")
  local i = b:let("i", moon.i32, moon.i32(1))
  local acc = b:let("acc", moon.i32, moon.i32(1))
  b:block(moon.control_block("loop", {moon.param("i", moon.i32, i), moon.param("acc", moon.i32, acc)},
    moon.stmts(function(b2)
      b2:if_(b2:icmp_gt(b2:param("i"), n), function(b3)
        b3:return_(b3:param("acc"))
      end)
      b2:jump("loop", {b2:iadd(b2:param("i"), moon.i32(1)), b2:imul(b2:param("acc"), b2:param("i"))})
    end)))
end)
m:compile()
]]

-- ============================================================
-- MOM frontend
-- ============================================================

ffi.cdef[[
const char* moonlift_last_error_message(void);
typedef struct MomWireBuilder {
    uint8_t *data; size_t len; size_t cap;
    int32_t string_count; int32_t aux_count; int32_t error;
} MomWireBuilder;
typedef struct NativeParseOut {
    int32_t *state;
    int32_t *type_tag, *type_tok, *type_a, *type_b, *type_c;
    int32_t *expr_tag, *expr_tok, *expr_a, *expr_b, *expr_c, *expr_d;
    int32_t *stmt_tag, *stmt_tok, *stmt_a, *stmt_b, *stmt_c, *stmt_d, *stmt_e;
    int32_t *item_tag, *item_tok, *item_a, *item_b, *item_c, *item_d, *item_e;
    int32_t *param_name, *param_type;
    int32_t *field_name, *field_type;
    int32_t *jarg_name, *jarg_expr;
    int32_t *expr_list, *stmt_list, *type_list;
    int32_t *issue_tag, *issue_tok;
    size_t cap_nodes; size_t cap_lists;
} NativeParseOut;
]]

local Host = require("moonlift.mlua_run")

local function compile_mod(path)
    local mod = Host.dofile(path)
    local compiled, err = mod:compile()
    assert(compiled, "compile " .. path .. ": " .. tostring(err))
    return compiled
end

local function alloc_parse_out(cap)
    local out_c = ffi.new("NativeParseOut")
    local owner = { c = out_c }
    local function arr(name)
        local a = ffi.new("int32_t[?]", cap)
        owner[name] = a
        out_c[name] = a
    end
    arr("state")
    for _, name in ipairs({
        "type_tag", "type_tok", "type_a", "type_b", "type_c",
        "expr_tag", "expr_tok", "expr_a", "expr_b", "expr_c", "expr_d",
        "stmt_tag", "stmt_tok", "stmt_a", "stmt_b", "stmt_c", "stmt_d", "stmt_e",
        "item_tag", "item_tok", "item_a", "item_b", "item_c", "item_d", "item_e",
        "param_name", "param_type", "field_name", "field_type", "jarg_name", "jarg_expr",
        "expr_list", "stmt_list", "type_list", "issue_tag", "issue_tok",
    }) do arr(name) end
    out_c.cap_nodes = cap
    out_c.cap_lists = cap
    return owner
end

-- Pre-load MOM modules (one-time setup, excluded from benchmark time)
local lexer_mod = compile_mod("lua/moonlift/mom/parser/native_lexer.mlua")
local parser_mod = compile_mod("lua/moonlift/mom/parser/native_core.mlua")
local lower_mod = compile_mod("lua/moonlift/mom/driver/lower_wire.mlua")
local backend_mod = compile_mod("lua/moonlift/mom/driver/backend_ffi.mlua")

local mom_lex = lexer_mod:get("mom_lex_into")
local mom_parse = parser_mod:get("mom_parse_native_core")
local mom_lower = lower_mod:get("mom_lower_native_core_to_wire")
local mom_compile = backend_mod:get("mom_backend_compile_binary")
local mom_free = backend_mod:get("mom_backend_free_artifact")

local function mom_compile_fn(src)
    local cap = math.max(#src * 2, 256)
    local src_buf = ffi.new("uint8_t[?]", #src + 1, src)
    local kinds = ffi.new("int32_t[?]", cap)
    local starts = ffi.new("int32_t[?]", cap)
    local stops = ffi.new("int32_t[?]", cap)
    local lines = ffi.new("int32_t[?]", cap)
    local cols = ffi.new("int32_t[?]", cap)
    local ntok = tonumber(mom_lex(src_buf, #src, kinds, starts, stops, lines, cols, cap))
    assert(ntok and ntok > 0 and ntok < cap)
    local out = alloc_parse_out(cap)
    local nitems = tonumber(mom_parse(src_buf, #src, kinds, starts, stops, ntok, out.c))
    assert(nitems and nitems > 0)
    assert(out.c.state[5] == 0)
    local wire = ffi.new("uint8_t[?]", cap * 16)
    local wb = ffi.new("MomWireBuilder")
    local nwire = tonumber(mom_lower(src_buf, starts, stops, out.c, nitems, wb, wire, cap * 16))
    assert(wb.error == 0)
    local artifact = mom_compile(wire, nwire)
    assert(artifact and artifact ~= ffi.NULL)
    mom_free(artifact)
end

-- ============================================================
-- Lua frontend
-- ============================================================

local function lua_compile_fn()
    local chunk = Host.loadstring(MLUA_SRC, "bench.mlua")
    local compiled = chunk()
    compiled:free()
end

-- ============================================================
-- Verify
-- ============================================================

print("Verifying MOM path...")
mom_compile_fn(MOM_SRC)
print("Verifying Lua path...")
lua_compile_fn()
print()

-- ============================================================
-- Warmup
-- ============================================================

print("Warming up... (" .. WARMUP .. " iterations)")
for i = 1, WARMUP do
    mom_compile_fn(MOM_SRC)
    lua_compile_fn()
end
collectgarbage()

-- ============================================================
-- Benchmark
-- ============================================================

print(string.format("Benchmarking: %d iterations per frontend\n", TRIALS))

local t0 = os.clock()
for i = 1, TRIALS do
    mom_compile_fn(MOM_SRC)
end
local t_mom = os.clock() - t0
collectgarbage()

local t0 = os.clock()
for i = 1, TRIALS do
    lua_compile_fn()
end
local t_lua = os.clock() - t0
collectgarbage()

-- ============================================================
-- Report
-- ============================================================

local per_mom = t_mom / TRIALS * 1000
local per_lua = t_lua / TRIALS * 1000

print("                    Total (s)    Per trial (ms)   Iterations")
print(string.format("MOM:             %8.3f      %8.3f      %d", t_mom, per_mom, TRIALS))
print(string.format("Lua frontend:    %8.3f      %8.3f      %d", t_lua, per_lua, TRIALS))
print(string.format("\nMOM is %.2fx faster", t_lua / t_mom))
