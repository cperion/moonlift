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

typedef struct MomTreeOut {
    int32_t *counts;
    int32_t *type_tag; int32_t *type_tok; int32_t *type_scalar; int32_t *type_name_tok; int32_t *type_elem; int32_t *type_list_start; int32_t *type_list_count; int32_t *type_result;
    int32_t *param_name; int32_t *param_type;
    int32_t *field_name; int32_t *field_type;
    int32_t *expr_tag; int32_t *expr_tok; int32_t *expr_op; int32_t *expr_lhs; int32_t *expr_rhs; int32_t *expr_aux0; int32_t *expr_aux1; int32_t *expr_aux2;
    int32_t *stmt_tag; int32_t *stmt_tok; int32_t *stmt_name; int32_t *stmt_type; int32_t *stmt_value; int32_t *stmt_body_start; int32_t *stmt_body_count; int32_t *stmt_aux;
    int32_t *item_tag; int32_t *item_tok; int32_t *item_name; int32_t *item_member_start; int32_t *item_member_count; int32_t *item_result; int32_t *item_body_start; int32_t *item_body_count;
    int32_t *expr_list; int32_t *stmt_list; int32_t *type_list;
    int32_t *jump_arg_name; int32_t *jump_arg_expr;
    int32_t *switch_arm_key; int32_t *switch_arm_body_start; int32_t *switch_arm_body_count;
    int32_t *ctrl_block_label; int32_t *ctrl_block_param_start; int32_t *ctrl_block_param_count; int32_t *ctrl_block_body_start; int32_t *ctrl_block_body_count;
    int32_t *entry_param_name; int32_t *entry_param_type; int32_t *entry_param_init;
    size_t cap_nodes; size_t cap_lists;
} MomTreeOut;
]]

local lexer_unit = Host.dofile("lua/moonlift/mom/parser/native_lexer.mlua"):compile()
local parser_unit = Host.dofile("lua/moonlift/mom/parser/native_core.mlua"):compile()
local tree_unit = Host.dofile("lua/moonlift/mom/parser/native_tree.mlua"):compile()
local lex = lexer_unit:get("mom_lex_into")
local parse = parser_unit:get("mom_parse_native_core")
local materialize = tree_unit:get("mom_materialize_tree")

local function alloc_parse(cap)
    local c = ffi.new("NativeParseOut")
    local keep = {}
    local function arr(name)
        local a = ffi.new("int32_t[?]", cap)
        keep[#keep + 1] = a
        c[name] = a
    end
    arr("state")
    for _, name in ipairs({
        "type_tag", "type_tok", "type_a", "type_b", "type_c",
        "expr_tag", "expr_tok", "expr_a", "expr_b", "expr_c", "expr_d",
        "stmt_tag", "stmt_tok", "stmt_a", "stmt_b", "stmt_c", "stmt_d", "stmt_e",
        "item_tag", "item_tok", "item_a", "item_b", "item_c", "item_d", "item_e", "item_f",
        "param_name", "param_type", "field_name", "field_type", "jarg_name", "jarg_expr",
        "expr_list", "stmt_list", "type_list", "issue_tag", "issue_tok",
        "switch_arm_key", "switch_arm_body_start", "switch_arm_body_count",
        "ctrl_block_label", "ctrl_block_param_start", "ctrl_block_param_count", "ctrl_block_body_start", "ctrl_block_body_count",
        "entry_param_name", "entry_param_type", "entry_param_init", "cont_fill_name", "cont_fill_label",
    }) do arr(name) end
    c.cap_nodes = cap; c.cap_lists = cap
    return c, keep
end

local function alloc_tree(cap)
    local c = ffi.new("MomTreeOut")
    local keep = {}
    local function arr(name, n)
        local a = ffi.new("int32_t[?]", n or cap)
        keep[#keep + 1] = a
        c[name] = a
    end
    arr("counts", 16)
    for _, name in ipairs({
        "type_tag", "type_tok", "type_scalar", "type_name_tok", "type_elem", "type_list_start", "type_list_count", "type_result",
        "param_name", "param_type", "field_name", "field_type",
        "expr_tag", "expr_tok", "expr_op", "expr_lhs", "expr_rhs", "expr_aux0", "expr_aux1", "expr_aux2",
        "stmt_tag", "stmt_tok", "stmt_name", "stmt_type", "stmt_value", "stmt_body_start", "stmt_body_count", "stmt_aux",
        "item_tag", "item_tok", "item_name", "item_member_start", "item_member_count", "item_result", "item_body_start", "item_body_count",
        "expr_list", "stmt_list", "type_list", "jump_arg_name", "jump_arg_expr",
        "switch_arm_key", "switch_arm_body_start", "switch_arm_body_count",
        "ctrl_block_label", "ctrl_block_param_start", "ctrl_block_param_count", "ctrl_block_body_start", "ctrl_block_body_count",
        "entry_param_name", "entry_param_type", "entry_param_init",
    }) do arr(name) end
    c.cap_nodes = cap; c.cap_lists = cap
    return c, keep
end

local src = [[
struct Pair
  left: i32
  right: i32
end
union Maybe
  none
  some(i32)
end
func add(x: i32, y: i32) -> i32
  let z: i32 = x + y
  return z
end
region scan(p: ptr(u8); hit: cont(pos: i32), miss: cont())
entry start()
  jump miss()
end
end
expr inc(x: i32) -> i32
  x + 1
end
]]

local n = #src
local p = ffi.new("uint8_t[?]", n)
ffi.copy(p, src, n)
local cap = 4096
local kinds = ffi.new("int32_t[?]", cap)
local starts = ffi.new("int32_t[?]", cap)
local stops = ffi.new("int32_t[?]", cap)
local lines = ffi.new("int32_t[?]", cap)
local cols = ffi.new("int32_t[?]", cap)
local ntok = tonumber(lex(p, n, kinds, starts, stops, lines, cols, cap))
local parsed = alloc_parse(cap)
local nitems = tonumber(parse(p, n, kinds, starts, stops, ntok, parsed))
assert(nitems == 5, "parse items " .. nitems)
assert(parsed.state[5] == 0, "parse issues " .. tonumber(parsed.state[5]))
local tree = alloc_tree(cap)
local tree_items = tonumber(materialize(parsed, tree))
assert(tree_items == 5, "tree items " .. tree_items)
assert(tree.counts[0] == parsed.state[1], "type count copied")
assert(tree.counts[1] == parsed.state[2], "expr count copied")
assert(tree.counts[2] == parsed.state[3], "stmt count copied")
assert(tree.item_tag[0] == 3, "struct item")
assert(tree.item_tag[1] == 4, "union item")
assert(tree.item_tag[2] == 1, "func item")
assert(tree.item_body_count[2] == 2, "func body count")
assert(tree.item_tag[3] == 5, "region item")
assert(tree.item_body_count[3] == 1, "region block count")
assert(tree.item_tag[4] == 6, "expr item")
assert(tree.expr_tag[tree.item_body_start[4]] == 4, "expr body is binary")
assert(tree.field_type[tree.item_member_start[1] + 1] >= 0, "union payload type retained")

lexer_unit.artifact:free()
parser_unit.artifact:free()
tree_unit.artifact:free()
print("mom native typed tree ok")
