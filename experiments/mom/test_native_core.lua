package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

ffi.cdef[[
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

local lexer_mod = Host.dofile("experiments/mom/parser/native_lexer.mlua")
local parser_mod = Host.dofile("experiments/mom/parser/native_core.mlua")
local lexer_unit = lexer_mod:compile()
local parser_unit = parser_mod:compile()
local lex = lexer_unit:get("mom_lex_into")
local parse = parser_unit:get("mom_parse_native_core")

local function run(src)
    local n = #src
    local p = ffi.new("uint8_t[?]", n > 0 and n or 1)
    if n > 0 then ffi.copy(p, src, n) end
    local cap = 1024
    local kinds = ffi.new("int32_t[?]", cap)
    local starts = ffi.new("int32_t[?]", cap)
    local stops = ffi.new("int32_t[?]", cap)
    local lines = ffi.new("int32_t[?]", cap)
    local cols = ffi.new("int32_t[?]", cap)
    local ntok = tonumber(lex(p, n, kinds, starts, stops, lines, cols, cap))
    assert(ntok < cap)

    local out_c = ffi.new("NativeParseOut")
    local out = { c = out_c }
    local function arr(name, ctype, count)
        local a = ffi.new(ctype, count)
        out[name] = a
        out_c[name] = a
    end
    arr("state", "int32_t[?]", 12)
    for _, name in ipairs({
        "type_tag", "type_tok", "type_a", "type_b", "type_c",
        "expr_tag", "expr_tok", "expr_a", "expr_b", "expr_c", "expr_d",
        "stmt_tag", "stmt_tok", "stmt_a", "stmt_b", "stmt_c", "stmt_d", "stmt_e",
        "item_tag", "item_tok", "item_a", "item_b", "item_c", "item_d", "item_e",
        "param_name", "param_type", "field_name", "field_type", "jarg_name", "jarg_expr",
        "expr_list", "stmt_list", "type_list", "issue_tag", "issue_tok",
    }) do
        arr(name, "int32_t[?]", cap)
    end
    out_c.cap_nodes = cap
    out_c.cap_lists = cap
    local nitems = tonumber(parse(p, n, kinds, starts, stops, ntok, out_c))
    return out, nitems, kinds, starts, stops, src
end

local src = [[
struct Pair
  left: i32
  right: i32
end
func add(x: i32, y: i32) -> i32
  let z: i32 = x + y
  return z
end
func sum(n: i32) -> i32
  if n <= 0 then
    return 0
  else
    return n + 1
  end
end
]]

local out, nitems = run(src)
assert(nitems == 3, "items")
assert(out.state[5] == 0, "issues: " .. tonumber(out.state[5]))
assert(out.item_tag[0] == 3, "struct item")
assert(out.item_tag[1] == 1, "func item")
assert(out.item_tag[2] == 1, "func item 2")
assert(out.state[6] == 3, "params")
assert(out.state[7] == 2, "fields")
assert(out.state[3] >= 3, "stmts: " .. tonumber(out.state[3]))
assert(out.state[2] >= 4, "exprs: " .. tonumber(out.state[2]))
assert(out.state[1] >= 7, "types: " .. tonumber(out.state[1]))

parser_unit.artifact:free()
lexer_unit.artifact:free()
print("mom native parser core ok")
