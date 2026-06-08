package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

ffi.cdef[[
typedef struct NativeParseOut {
    int32_t *state;
    int32_t *type_tag; int32_t *type_tok; int32_t *type_a; int32_t *type_b; int32_t *type_c;
    int32_t *expr_tag; int32_t *expr_tok; int32_t *expr_a; int32_t *expr_b; int32_t *expr_c; int32_t *expr_d;
    int32_t *stmt_tag; int32_t *stmt_tok; int32_t *stmt_a; int32_t *stmt_b; int32_t *stmt_c; int32_t *stmt_d; int32_t *stmt_e;
    int32_t *item_tag; int32_t *item_tok; int32_t *item_a; int32_t *item_b; int32_t *item_c; int32_t *item_d; int32_t *item_e; int32_t *item_f;
    int32_t *param_name; int32_t *param_type;
    int32_t *field_name; int32_t *field_type;
    int32_t *jarg_name; int32_t *jarg_expr;
    int32_t *expr_list; int32_t *stmt_list; int32_t *type_list;
    int32_t *issue_tag; int32_t *issue_tok;
    int32_t *switch_arm_key; int32_t *switch_arm_body_start; int32_t *switch_arm_body_count;
    int32_t *ctrl_block_label; int32_t *ctrl_block_param_start; int32_t *ctrl_block_param_count; int32_t *ctrl_block_body_start; int32_t *ctrl_block_body_count;
    int32_t *entry_param_name; int32_t *entry_param_type; int32_t *entry_param_init;
    int32_t *cont_fill_name; int32_t *cont_fill_label;
    size_t cap_nodes; size_t cap_lists;
} NativeParseOut;
]]

local lexer_mod = Host.dofile("lua/moonlift/mom/parser/native_lexer.mlua")
local parser_mod = Host.dofile("lua/moonlift/mom/parser/native_core.mlua")
local lexer_unit = lexer_mod:compile()
local parser_unit = parser_mod:compile()
local lex = lexer_unit:get("mom_lex_into")
local parse = parser_unit:get("mom_parse_native_core")

local IT_FUNC = 1
local IT_EXTERN = 2
local IT_STRUCT = 3
local IT_UNION = 4
local IT_EXPR_FRAG = 6
local IT_REGION = 5

local ST_LET = 1
local ST_VAR = 2
local ST_SET = 3
local ST_EXPR = 4
local ST_IF = 5
local ST_RETURN_VOID = 6
local ST_RETURN_VALUE = 7
local ST_YIELD_VOID = 8
local ST_YIELD_VALUE = 9
local ST_JUMP = 10
local ST_CONTROL = 11
local ST_EMIT = 12
local ST_SWITCH = 13

local EX_LIT = 1
local EX_REF = 2
local EX_UNARY = 3
local EX_BINARY = 4
local EX_COMPARE = 5
local EX_CAST = 7
local EX_CALL = 8
local EX_SELECT = 9
local EX_DOT = 10
local EX_INDEX = 11
local EX_IF = 16
local EX_SWITCH = 18
local EX_CONTROL = 19

local function run(src)
    local n = #src
    local p = ffi.new("uint8_t[?]", n > 0 and n or 1)
    if n > 0 then ffi.copy(p, src, n) end
    local cap = 2048
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
    arr("state", "int32_t[?]", 16)
    for _, name in ipairs({
        "type_tag", "type_tok", "type_a", "type_b", "type_c",
        "expr_tag", "expr_tok", "expr_a", "expr_b", "expr_c", "expr_d",
        "stmt_tag", "stmt_tok", "stmt_a", "stmt_b", "stmt_c", "stmt_d", "stmt_e",
        "item_tag", "item_tok", "item_a", "item_b", "item_c", "item_d", "item_e", "item_f",
        "param_name", "param_type", "field_name", "field_type", "jarg_name", "jarg_expr",
        "expr_list", "stmt_list", "type_list", "issue_tag", "issue_tok",
        "switch_arm_key", "switch_arm_body_start", "switch_arm_body_count",
        "ctrl_block_label", "ctrl_block_param_start", "ctrl_block_param_count", "ctrl_block_body_start", "ctrl_block_body_count",
        "entry_param_name", "entry_param_type", "entry_param_init",
        "cont_fill_name", "cont_fill_label",
    }) do
        arr(name, "int32_t[?]", cap)
    end
    out_c.cap_nodes = cap
    out_c.cap_lists = cap
    local nitems = tonumber(parse(p, n, kinds, starts, stops, ntok, out_c))
    return out, nitems, kinds, starts, stops, src
end

-- Test 1: struct, func, if-then-else (existing)
local src1 = [[
struct Pair
  left: i32
  right: i32
end
func add(x: i32, y: i32): i32
  let z: i32 = x + y
  return z
end
func sum(n: i32): i32
  if n <= 0 then
    return 0
  else
    return n + 1
  end
end
]]

local out1, nitems1 = run(src1)
assert(nitems1 == 3, "items: " .. nitems1)
assert(out1.state[5] == 0, "issues: " .. tonumber(out1.state[5]))
assert(out1.item_tag[0] == IT_STRUCT, "struct item")
assert(out1.item_tag[1] == IT_FUNC, "func item")
assert(out1.item_tag[2] == IT_FUNC, "func item 2")
assert(out1.state[6] == 3, "params")
assert(out1.state[7] == 2, "fields")
assert(out1.state[3] >= 3, "stmts: " .. tonumber(out1.state[3]))
assert(out1.state[2] >= 4, "exprs: " .. tonumber(out1.state[2]))
assert(out1.state[1] >= 7, "types: " .. tonumber(out1.state[1]))

-- Test 2: switch statement
local src2 = [[
func classify(x: i32): i32
  switch x do
  case 0 then
    return 1
  case 1 then
    return 2
  default then
    return 0
  end
end
]]

local out2, nitems2 = run(src2)
assert(nitems2 == 1, "switch items: " .. nitems2)
assert(out2.state[5] == 0, "switch issues: " .. tonumber(out2.state[5]))
local found_switch = false
for i = 0, out2.state[3] - 1 do
    if out2.stmt_tag[i] == ST_SWITCH then found_switch = true end
end
assert(found_switch, "expected ST_SWITCH in switch test")
assert(out2.state[12] == 2, "switch arms: " .. tonumber(out2.state[12]))

-- Test 3: block (control region) with init params
local src3 = [[
func countdown(n: i32): i32
  block loop(i: i32 = 0)
    if i >= n then yield i end
    jump loop(i = i + 1)
  end
end
]]

local out3, nitems3 = run(src3)
assert(nitems3 == 1, "block items: " .. nitems3)
assert(out3.state[5] == 0, "block issues: " .. tonumber(out3.state[5]))
local found_ctrl = false
for i = 0, out3.state[3] - 1 do
    if out3.stmt_tag[i] == ST_CONTROL then found_ctrl = true end
end
assert(found_ctrl, "expected ST_CONTROL in block test")
assert(out3.state[13] >= 1, "ctrl blocks: " .. tonumber(out3.state[13]))
assert(out3.state[14] >= 1, "entry params: " .. tonumber(out3.state[14]))

-- Test 4: emit statement (simpler: one arg, one cont ref)
local src4 = [[
func find(p: ptr(u8)): i32
  emit scan(p; hit = done)
end
]]

local out4, nitems4 = run(src4)
assert(nitems4 == 1, "emit items: " .. nitems4)
assert(out4.state[5] == 0, "emit issues: " .. tonumber(out4.state[5]))
local found_emit = false
for i = 0, out4.state[3] - 1 do
    if out4.stmt_tag[i] == ST_EMIT then found_emit = true end
end
assert(found_emit, "expected ST_EMIT in emit test")
local found_cont = out4.state[15] >= 1
assert(found_cont, "expected cont fills in emit test: " .. tonumber(out4.state[15]))

-- Test 5: if expression (ternary)
local src5 = [[
func max(a: i32, b: i32): i32
  let result: i32 = if a > b then a else b end
  return result
end
]]

local out5, nitems5 = run(src5)
assert(nitems5 == 1, "if-expr items: " .. nitems5)
assert(out5.state[5] == 0, "if-expr issues: " .. tonumber(out5.state[5]))
local found_if_expr = false
for i = 0, out5.state[2] - 1 do
    if out5.expr_tag[i] == EX_IF then found_if_expr = true end
end
assert(found_if_expr, "expected EX_IF in if-expr test")

-- Test 6: native parsing of top-level union, region fragment, expr fragment.
local src6 = [[
union Maybe
  none
  some(i32)
end
region scan(p: ptr(u8); hit: cont(pos: i32), miss: cont())
entry start()
  jump miss()
end
block done(pos: i32)
  jump hit(pos = pos)
end
end
expr inc(x: i32): i32
  x + 1
end
]]

local out6, nitems6 = run(src6)
assert(nitems6 == 3, "fragment items: " .. nitems6)
assert(out6.state[5] == 0, "fragment issues: " .. tonumber(out6.state[5]))
assert(out6.item_tag[0] == IT_UNION, "union item parsed")
assert(out6.item_tag[1] == IT_REGION, "region fragment parsed")
assert(out6.item_tag[2] == IT_EXPR_FRAG, "expr fragment parsed")
assert(out6.item_b[0] == 0 and out6.item_c[0] == 2, "union variant range/count")
assert(out6.item_b[1] >= 0 and out6.item_c[1] == 1, "region param range/count")
assert(out6.item_e[1] == 2, "region control block count: " .. tonumber(out6.item_e[1]))
assert(out6.item_c[2] == 1, "expr fragment param count")
assert(out6.expr_tag[out6.item_e[2]] == EX_BINARY, "expr fragment body")

parser_unit.artifact:free()
lexer_unit.artifact:free()
print("mom native parser core ok")