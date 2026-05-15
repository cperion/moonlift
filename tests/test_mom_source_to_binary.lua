package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

ffi.cdef[[
const char* moonlift_last_error_message(void);

typedef struct MomWireBuilder {
    uint8_t *data;
    size_t len;
    size_t cap;
    int32_t string_count;
    int32_t aux_count;
    int32_t error;
} MomWireBuilder;

typedef struct NativeParseOut {
    int32_t *state;
    int32_t *type_tag; int32_t *type_tok; int32_t *type_a; int32_t *type_b; int32_t *type_c;
    int32_t *expr_tag; int32_t *expr_tok; int32_t *expr_a; int32_t *expr_b; int32_t *expr_c; int32_t *expr_d;
    int32_t *stmt_tag; int32_t *stmt_tok; int32_t *stmt_a; int32_t *stmt_b; int32_t *stmt_c; int32_t *stmt_d; int32_t *stmt_e;
    int32_t *item_tag; int32_t *item_tok; int32_t *item_a; int32_t *item_b; int32_t *item_c; int32_t *item_d; int32_t *item_e;
    int32_t *param_name; int32_t *param_type;
    int32_t *field_name; int32_t *field_type;
    int32_t *jarg_name; int32_t *jarg_expr;
    int32_t *expr_list; int32_t *stmt_list; int32_t *type_list;
    int32_t *issue_tag; int32_t *issue_tok;
    size_t cap_nodes; size_t cap_lists;
} NativeParseOut;
]]

local function compile(path)
    local mod = Host.dofile(path)
    return mod:compile()
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

local lexer = compile("lua/moonlift/mom/parser/native_lexer.mlua")
local parser = compile("lua/moonlift/mom/parser/native_core.mlua")
local lower = compile("lua/moonlift/mom/driver/lower_wire.mlua")
local backend = compile("lua/moonlift/mom/driver/backend_ffi.mlua")

local lex = lexer:get("mom_lex_into")
local parse = parser:get("mom_parse_native_core")
local lower_wire = lower:get("mom_lower_native_core_to_wire")
local compile_binary = backend:get("mom_backend_compile_binary")
local getpointer = backend:get("mom_backend_getpointer")
local free_artifact = backend:get("mom_backend_free_artifact")

local src = [[
func ret7() -> i32
  return 7
end
func add(x: i32, y: i32) -> i32
  return x + y
end
]]

local cap = 1024
local src_buf = ffi.new("uint8_t[?]", #src + 1, src)
local kinds = ffi.new("int32_t[?]", cap)
local starts = ffi.new("int32_t[?]", cap)
local stops = ffi.new("int32_t[?]", cap)
local lines = ffi.new("int32_t[?]", cap)
local cols = ffi.new("int32_t[?]", cap)
local ntok = tonumber(lex(src_buf, #src, kinds, starts, stops, lines, cols, cap))
assert(ntok > 0 and ntok < cap)

local out = alloc_parse_out(cap)
local nitems = tonumber(parse(src_buf, #src, kinds, starts, stops, ntok, out.c))
assert(nitems == 2, "nitems=" .. tostring(nitems))
assert(out.c.state[5] == 0, "parse issues=" .. tonumber(out.c.state[5]))

local wire = ffi.new("uint8_t[?]", 8192)
local wb = ffi.new("MomWireBuilder")
local nwire = tonumber(lower_wire(src_buf, starts, stops, out.c, nitems, wb, wire, 8192))
assert(wb.error == 0, "wire error=" .. tonumber(wb.error))
assert(nwire > 16, "wire length")

local artifact = compile_binary(wire, nwire)
if artifact == nil or artifact == ffi.NULL then
  local lib = ffi.load("./target/release/libmoonlift.so")
  error(ffi.string(lib.moonlift_last_error_message()))
end

local ret7_ptr = getpointer(artifact, ffi.new("char[?]", 5, "ret7"))
assert(ret7_ptr ~= nil and ret7_ptr ~= ffi.NULL)
local ret7 = ffi.cast("int32_t (*)()", ret7_ptr)
assert(ret7() == 7)

local add_ptr = getpointer(artifact, ffi.new("char[?]", 4, "add"))
assert(add_ptr ~= nil and add_ptr ~= ffi.NULL)
local add = ffi.cast("int32_t (*)(int32_t, int32_t)", add_ptr)
assert(add(20, 22) == 42)

free_artifact(artifact)
print("mom source to binary ok")
