-- Test MOM native typechecker modules.
-- Tests compile all typecheck modules and exercises basic type inference.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local T = require("moonlift.mom.back.back_tags")
local Host = require("moonlift.mlua_run")

local function compile(path)
    local chunk = Host.loadfile(path)
    local mod = chunk()
    local compiled = mod:compile()
    return compiled
end

-- Compile all typecheck modules
local scalar_mod = compile("lua/moonlift/mom/typecheck/type_scalar.mlua")
local env_mod = compile("lua/moonlift/mom/typecheck/type_env.mlua")
local expr_mod = compile("lua/moonlift/mom/typecheck/type_expr.mlua")
local stmt_mod = compile("lua/moonlift/mom/typecheck/type_stmt.mlua")
local module_mod = compile("lua/moonlift/mom/typecheck/type_module.mlua")

-- Test 1: type_scalar predicates
do
    local is_float = scalar_mod:get("mt_is_float_scalar")
    local is_integer = scalar_mod:get("mt_is_integer_scalar")
    local is_bool = scalar_mod:get("mt_is_bool_scalar")
    local bit_width = scalar_mod:get("mt_scalar_bit_width")
    local adopt = scalar_mod:get("mt_adopt_literal_to_scalar")

    assert(is_float(T.ScalarF32) == true, "f32 is float")
    assert(is_float(T.ScalarI32) == false, "i32 is not float")
    assert(is_integer(T.ScalarI32) == true, "i32 is integer")
    assert(is_integer(T.ScalarU8) == true, "u8 is integer")
    assert(is_integer(T.ScalarF64) == false, "f64 is not integer")
    assert(is_bool(T.ScalarBool) == true, "bool is bool")
    assert(is_bool(T.ScalarI32) == false, "i32 is not bool")
    assert(bit_width(T.ScalarI32) == 32, "i32 bit width")
    assert(bit_width(T.ScalarI64) == 64, "i64 bit width")
    assert(bit_width(T.ScalarBool) == 0, "bool bit width")
    assert(adopt(T.ScalarI32, T.ScalarI64) == T.ScalarI64, "adopt i32->i64")
    assert(adopt(T.ScalarI32, T.ScalarBool) == T.ScalarBool, "adopt i32->bool")
    assert(adopt(T.ScalarBool, T.ScalarI32) == T.ScalarBool, "adopt bool->i32 no change")

    print("test 1: type_scalar predicates OK")
end

-- Test 2: type_env
do
    local push = env_mod:get("mt_env_push_scope")
    local pop = env_mod:get("mt_env_pop_scope")
    local bind = env_mod:get("mt_env_bind")
    local lookup = env_mod:get("mt_env_lookup")

    local cap = 64
    local env_names = ffi.new("int32_t[?]", cap)
    local env_types = ffi.new("int32_t[?]", cap)
    local scope_starts = ffi.new("int32_t[?]", cap)
    local env = ffi.new("struct { int32_t *names, *types, *scope_starts; int32_t count, scope_depth; size_t cap; }",
        env_names, env_types, scope_starts, 0, 0, cap)

    push(env)
    bind(env, 10, T.ScalarI32)
    bind(env, 20, T.ScalarBool)
    assert(lookup(env, 10) == T.ScalarI32, "lookup 10")
    assert(lookup(env, 20) == T.ScalarBool, "lookup 20")
    assert(lookup(env, 30) == -1, "lookup missing")

    push(env)
    bind(env, 10, T.ScalarF64)  -- shadow
    assert(lookup(env, 10) == T.ScalarF64, "shadowed lookup 10")

    pop(env)
    assert(lookup(env, 10) == T.ScalarI32, "restored lookup 10 after pop")

    print("test 2: type_env OK")
end

-- Test 3: type_expr — basic literal type inference
do
    local type_expr = expr_mod:get("mt_type_expr")

    local cap = 64
    local type_tag = ffi.new("int32_t[?]", cap)
    local type_scalar = ffi.new("int32_t[?]", cap)
    local type_elem = ffi.new("int32_t[?]", cap)
    local expr_tag = ffi.new("int32_t[?]", cap)
    local expr_tok = ffi.new("int32_t[?]", cap)
    local expr_op = ffi.new("int32_t[?]", cap)
    local expr_lhs = ffi.new("int32_t[?]", cap)
    local expr_rhs = ffi.new("int32_t[?]", cap)
    local expr_aux0 = ffi.new("int32_t[?]", cap)
    local stmt_name = ffi.new("int32_t[?]", cap)
    local stmt_type_arr = ffi.new("int32_t[?]", cap)
    local env_name = ffi.new("int32_t[?]", cap)
    local env_type = ffi.new("int32_t[?]", cap)
    local env_count = ffi.new("int32_t[1]", 0)
    local out_scalar = ffi.new("int32_t[?]", cap)
    local out_type_idx = ffi.new("int32_t[?]", cap)
    local issue_tag = ffi.new("int32_t[?]", cap)
    local issue_d0 = ffi.new("int32_t[?]", cap)
    local issue_d1 = ffi.new("int32_t[?]", cap)
    local issue_cnt = ffi.new("int32_t[1]", 0)

    -- LIT with TK_INT → ScalarI32
    expr_tag[0] = T.ME_LIT; expr_tok[0] = T.TK_INT
    local r = type_expr(0, type_tag, type_scalar, type_elem,
        expr_tag, expr_tok, expr_op, expr_lhs, expr_rhs, expr_aux0,
        stmt_name, stmt_type_arr,
        env_name, env_type, env_count,
        out_scalar, out_type_idx,
        issue_tag, issue_d0, issue_d1, issue_cnt, cap)
    assert(r == T.ScalarI32, "int lit scalar: " .. tostring(r))
    assert(out_scalar[0] == T.ScalarI32, "int lit out_scalar")

    -- LIT with TK_TRUE → ScalarBool
    expr_tag[1] = T.ME_LIT; expr_tok[1] = T.TK_TRUE
    r = type_expr(1, type_tag, type_scalar, type_elem,
        expr_tag, expr_tok, expr_op, expr_lhs, expr_rhs, expr_aux0,
        stmt_name, stmt_type_arr,
        env_name, env_type, env_count,
        out_scalar, out_type_idx,
        issue_tag, issue_d0, issue_d1, issue_cnt, cap)
    assert(r == T.ScalarBool, "true lit scalar: " .. tostring(r))
    assert(out_scalar[1] == T.ScalarBool, "true lit out_scalar")

    -- LIT with TK_FLOAT → ScalarF64
    expr_tag[2] = T.ME_LIT; expr_tok[2] = T.TK_FLOAT
    r = type_expr(2, type_tag, type_scalar, type_elem,
        expr_tag, expr_tok, expr_op, expr_lhs, expr_rhs, expr_aux0,
        stmt_name, stmt_type_arr,
        env_name, env_type, env_count,
        out_scalar, out_type_idx,
        issue_tag, issue_d0, issue_d1, issue_cnt, cap)
    assert(r == T.ScalarF64, "float lit scalar: " .. tostring(r))
    assert(out_scalar[2] == T.ScalarF64, "float lit out_scalar")

    -- REF lookup failure → unresolved issue + ScalarVoid
    expr_tag[3] = T.ME_REF; expr_tok[3] = 999
    r = type_expr(3, type_tag, type_scalar, type_elem,
        expr_tag, expr_tok, expr_op, expr_lhs, expr_rhs, expr_aux0,
        stmt_name, stmt_type_arr,
        env_name, env_type, env_count,
        out_scalar, out_type_idx,
        issue_tag, issue_d0, issue_d1, issue_cnt, cap)
    assert(r == T.ScalarVoid, "unresolved ref scalar: " .. tostring(r))
    assert(issue_cnt[0] > 0, "unresolved ref should produce issue")

    -- COMPARE → ScalarBool
    expr_tag[4] = T.ME_COMPARE
    r = type_expr(4, type_tag, type_scalar, type_elem,
        expr_tag, expr_tok, expr_op, expr_lhs, expr_rhs, expr_aux0,
        stmt_name, stmt_type_arr,
        env_name, env_type, env_count,
        out_scalar, out_type_idx,
        issue_tag, issue_d0, issue_d1, issue_cnt, cap)
    assert(r == T.ScalarBool, "compare scalar: " .. tostring(r))

    print("test 3: type_expr OK")
end

scalar_mod.artifact:free()
env_mod.artifact:free()
expr_mod.artifact:free()
stmt_mod.artifact:free()
module_mod.artifact:free()

print()
print("mom typecheck ok")
