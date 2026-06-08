-- Transform expr_lower.mlua: replace recursive regions with func-based lowering
-- Usage: luajit scripts/transform_expr_lower.lua

local f = io.open("lua/moonlift/mom/back/expr_lower.mlua", "r")
local content = f:read("*all")
f:close()

-- 1. Add MomTreeOut import
content = content:gsub(
  "local MomBackLowerCtx = M.MomBackLowerCtx",
  "local MomTreeOut = M.MomTreeOut\nlocal MomBackLowerCtx = M.MomBackLowerCtx"
)

-- 2. Replace old address region imports with func imports; remove control_expr import
content = content:gsub(
  "%-%- Address/store helpers from back/address%.mlua %(registered by step 6%).\nlocal mb_place_addr_to_back = M%.mb_place_addr_to_back\nlocal mb_index_addr_to_back = M%.mb_index_addr_to_back\n\n%-%- Control expression lowerer %(from back/control_lower%.mlua%).\nlocal mb_lower_control_expr = M%.mb_lower_control_expr",
  "-- Address/store helpers from back/address.mlua (func-based).\nlocal mb_place_addr_to_back_fn = M.mb_place_addr_to_back_fn\nlocal mb_index_addr_to_back_fn = M.mb_index_addr_to_back_fn"
)

-- 3. Remove recursive regions + old Step 6 regions (unary through dot, excluding call/view/len)
-- We match from "Lower a unary expression." through the end of mb_expr_dot region.
-- This covers lines ~149-440 minus the kept call/view/len regions.

local kMB_EXPR_CALL = [[
-- Lower a call expression stub.
local mb_expr_call = region(ctx: ptr(@{MomBackLowerCtx}), idx: i32;
                            done: cont(value: i32, scalar: i32, ok: bool))
entry start()
    jump done(value = 0, scalar = 0, ok = false)
end
end

]]

local kMB_EXPR_VIEW = [[
-- Expr view lowering stub (view result protocol).
local mb_expr_view = region(ctx: ptr(@{MomBackLowerCtx}), idx: i32;
                            done: cont(data: i32, len: i32, stride: i32, elem_scalar: i32, ok: bool))
entry start()
    jump done(data = 0, len = 0, stride = 0, elem_scalar = 0, ok = false)
end
end

]]

local kMB_EXPR_LEN = [[
-- Expr length lowering.
local mb_expr_len = region(ctx: ptr(@{MomBackLowerCtx}), idx: i32;
                           done: cont(value: i32, scalar: i32, ok: bool))
entry start()
    let child_idx: i32 = ctx.tree.expr_lhs[idx]
    let child_tag: i32 = ctx.tree.expr_tag[child_idx]
    if child_tag == @{T.EX_REF} then
        let name_tok: i32 = ctx.tree.expr_tok[child_idx]
        let slot: i32 = mb_env_lookup(ctx.env, name_tok)
        let kind: i32 = select(slot >= 0, ctx.env.kind[as(index, slot)], 0)
        let scalar: i32 = select(slot >= 0, ctx.env.scalar[as(index, slot)], 0)
        let val: i32 = select(slot >= 0, ctx.env.val[as(index, slot)], 0)
        let aux0: i32 = select(slot >= 0, ctx.env.aux0[as(index, slot)], 0)
        if slot >= 0 and kind == @{MB_LOCAL_VIEW} then
            jump done(value = aux0, scalar = @{T.BackIndex}, ok = true)
        end
    end
    jump done(value = 0, scalar = 0, ok = false)
end
end

]]

local kNEW_STEP6 = [[
-- ── Step 6: func-based addr/index/dot lowering ──────────────────────

-- Expr addr‑of: delegate to mb_place_addr_to_back_fn.
local mb_expr_addr_of = region(ctx: ptr(@{MomBackLowerCtx}), idx: i32;
                               done: cont(value: i32, scalar: i32, ok: bool))
entry start()
    let child_idx: i32 = ctx.tree.expr_lhs[idx]
    let ok: bool = mb_place_addr_to_back_fn(ctx, child_idx)
    if not ok then jump done(value = 0, scalar = 0, ok = false) end
    let result_scalar: i32 = ctx.expr_scalar[idx]
    jump done(value = ctx.last_addr, scalar = result_scalar, ok = true)
end
end

-- Expr index: compute address via func, then load scalar.
local mb_expr_index = region(ctx: ptr(@{MomBackLowerCtx}), idx: i32;
                             done: cont(value: i32, scalar: i32, ok: bool))
entry start()
    let base_idx: i32 = ctx.tree.expr_op[idx]
    let index_expr: i32 = ctx.tree.expr_lhs[idx]
    let elem_type: i32 = ctx.expr_type[idx]
    let ok: bool = mb_index_addr_to_back_fn(ctx, base_idx, index_expr, elem_type)
    if not ok then jump done(value = 0, scalar = 0, ok = false) end
    let result_scalar: i32 = ctx.expr_scalar[idx]
    let dst: i32 = mb_ctx_fresh_value(ctx)
    mb_emit_load_info(ctx, dst, 0, result_scalar, 0, 0, ctx.last_addr, 0, 0, 1, 4, 0, 4, 0, 0, 1)
    jump done(value = dst, scalar = result_scalar, ok = true)
end
end

-- Expr dot (field access): result unsupported until layout resolution.
local mb_expr_dot = region(ctx: ptr(@{MomBackLowerCtx}), idx: i32;
                           done: cont(value: i32, scalar: i32, ok: bool))
entry start()
    jump done(value = 0, scalar = 0, ok = false)
end
end

]]

local kMB_LOWER_EXPR_FN = [[
-- ── Function-based expression lowering (avoids region emit recursion) ──

local mb_lower_expr_fn = func(ctx: ptr(@{MomBackLowerCtx}), tree: ptr(@{MomTreeOut}), idx: i32): bool
    let tag: i32 = tree.expr_tag[idx]
    if tag == @{T.EX_LIT} then
        let tok_kind: i32 = tree.expr_op[idx]
        if tok_kind == @{T.TK_NIL} then ctx.last_expr_ok = false; return false end
        if tok_kind == @{T.TK_STRING} then ctx.last_expr_ok = false; return false end
        let dst: i32 = mb_ctx_fresh_value(ctx)
        let scalar: i32 = select(tok_kind == @{T.TK_TRUE} or tok_kind == @{T.TK_FALSE}, @{T.BackBool},
                           select(tok_kind == @{T.TK_FLOAT}, @{T.BackF64},
                                  @{T.BackI32}))
        let lit_tag: i32 = select(tok_kind == @{T.TK_TRUE}, 1,
                           select(tok_kind == @{T.TK_FALSE}, 1,
                           select(tok_kind == @{T.TK_INT}, 2,
                           select(tok_kind == @{T.TK_FLOAT}, 3, 0))))
        let lit_lo: i32 = select(tok_kind == @{T.TK_TRUE}, 1, 0)
        mb_emit_const(ctx, dst, scalar, lit_tag, lit_lo, 0)
        ctx.last_expr_value = dst; ctx.last_expr_scalar = scalar; ctx.last_expr_ok = true
        return true
    end
    if tag == @{T.EX_REF} then
        let tok: i32 = tree.expr_tok[idx]
        let slot: i32 = mb_env_lookup(ctx.env, tok)
        let kind: i32 = select(slot >= 0, ctx.env.kind[as(index, slot)], 0)
        let scalar: i32 = select(slot >= 0, ctx.env.scalar[as(index, slot)], 0)
        let val: i32 = select(slot >= 0, ctx.env.val[as(index, slot)], 0)
        if slot < 0 then ctx.last_expr_ok = false; return false end
        if kind == @{MB_LOCAL_SCALAR} then
            ctx.last_expr_value = val; ctx.last_expr_scalar = scalar; ctx.last_expr_ok = true
            return true
        end
        if kind == @{MB_LOCAL_STACK} then
            let aux0: i32 = select(slot >= 0, ctx.env.aux0[as(index, slot)], 0)
            let stack_dst: i32 = mb_ctx_fresh_value(ctx)
            mb_emit_stack_addr(ctx, stack_dst, val)
            mb_emit_load_info(ctx, stack_dst, 0, scalar, 0, 0, stack_dst, 0, 0, 0, 0, 0, 0, 0, 0, 1)
            ctx.last_expr_value = stack_dst; ctx.last_expr_scalar = scalar; ctx.last_expr_ok = true
            return true
        end
        ctx.last_expr_ok = false; return false
    end
    if tag == @{T.EX_UNARY} then
        let child_idx: i32 = tree.expr_lhs[idx]
        if not mb_lower_expr_fn(ctx, tree, child_idx) then return false end
        let child_value: i32 = ctx.last_expr_value
        let child_scalar: i32 = ctx.last_expr_scalar
        let tok: i32 = tree.expr_op[idx]
        let unary_op: i32 = mb_token_to_unary_op(tok)
        if unary_op == 0 then ctx.last_expr_ok = false; return false end
        let back_op: i32 = mb_lower_unary_op(unary_op, child_scalar)
        if back_op == 0 then ctx.last_expr_ok = false; return false end
        let dst: i32 = mb_ctx_fresh_value(ctx)
        mb_emit_unary(ctx, dst, back_op, 0, child_scalar, 0, child_value)
        ctx.last_expr_value = dst; ctx.last_expr_scalar = child_scalar; ctx.last_expr_ok = true
        return true
    end
    if tag == @{T.EX_BINARY} then
        let left_idx: i32 = tree.expr_lhs[idx]
        if not mb_lower_expr_fn(ctx, tree, left_idx) then return false end
        let left_val: i32 = ctx.last_expr_value
        let left_scalar: i32 = ctx.last_expr_scalar
        let right_idx: i32 = tree.expr_rhs[idx]
        if not mb_lower_expr_fn(ctx, tree, right_idx) then return false end
        let right_val: i32 = ctx.last_expr_value
        let right_scalar: i32 = ctx.last_expr_scalar
        if right_scalar ~= left_scalar then ctx.last_expr_ok = false; return false end
        let scalar: i32 = left_scalar
        let tok: i32 = tree.expr_op[idx]
        let op: i32 = mb_token_to_binary_op(tok)
        if op == 0 then ctx.last_expr_ok = false; return false end
        let is_float: bool = mb_is_float_scalar(scalar)
        let dst: i32 = mb_ctx_fresh_value(ctx)
        if op == @{T.BinBitAnd} or op == @{T.BinBitOr} or op == @{T.BinBitXor} then
            var bit_op: i32 = select(op == @{T.BinBitAnd}, @{T.BackBitAnd},
                                select(op == @{T.BinBitOr}, @{T.BackBitOr}, @{T.BackBitXor}))
            mb_emit_bit_binary(ctx, dst, bit_op, scalar, left_val, right_val)
            ctx.last_expr_value = dst; ctx.last_expr_scalar = scalar; ctx.last_expr_ok = true
            return true
        end
        if op == @{T.BinShl} or op == @{T.BinLShr} or op == @{T.BinAShr} then
            var shift_op: i32 = select(op == @{T.BinShl}, @{T.BackShiftLeft},
                                 select(op == @{T.BinLShr}, @{T.BackShiftLogicalRight},
                                        @{T.BackShiftArithmeticRight}))
            mb_emit_shift(ctx, dst, shift_op, scalar, left_val, right_val)
            ctx.last_expr_value = dst; ctx.last_expr_scalar = scalar; ctx.last_expr_ok = true
            return true
        end
        if is_float then
            let float_op: i32 = select(op == @{T.BinAdd}, @{T.BackFloatAdd},
                               select(op == @{T.BinSub}, @{T.BackFloatSub},
                               select(op == @{T.BinMul}, @{T.BackFloatMul},
                               select(op == @{T.BinDiv}, @{T.BackFloatDiv}, 0))))
            if float_op == 0 then ctx.last_expr_ok = false; return false end
            mb_emit_float_binary(ctx, dst, float_op, scalar, 1, left_val, right_val)
            ctx.last_expr_value = dst; ctx.last_expr_scalar = scalar; ctx.last_expr_ok = true
            return true
        end
        let int_op: i32 = select(op == @{T.BinAdd}, @{T.BackIntAdd},
                       select(op == @{T.BinSub}, @{T.BackIntSub},
                       select(op == @{T.BinMul}, @{T.BackIntMul},
                       select(op == @{T.BinDiv}, @{T.BackIntSDiv},
                       select(op == @{T.BinRem}, @{T.BackIntSRem}, 0)))))
        if int_op == 0 then ctx.last_expr_ok = false; return false end
        let overflow: i32 = 0
        let exact: i32 = 0
        mb_emit_int_binary(ctx, dst, int_op, scalar, overflow, exact, left_val, right_val)
        ctx.last_expr_value = dst; ctx.last_expr_scalar = scalar; ctx.last_expr_ok = true
        return true
    end
    if tag == @{T.EX_COMPARE} then
        let lhs_idx: i32 = tree.expr_lhs[idx]
        if not mb_lower_expr_fn(ctx, tree, lhs_idx) then return false end
        let lhs_val: i32 = ctx.last_expr_value
        let lhs_scalar: i32 = ctx.last_expr_scalar
        let rhs_idx: i32 = tree.expr_rhs[idx]
        if not mb_lower_expr_fn(ctx, tree, rhs_idx) then return false end
        let rhs_val: i32 = ctx.last_expr_value
        let rhs_scalar: i32 = ctx.last_expr_scalar
        if rhs_scalar ~= lhs_scalar then ctx.last_expr_ok = false; return false end
        let tok: i32 = tree.expr_op[idx]
        let sem_op: i32 = mb_token_to_compare_op(tok)
        if sem_op == 0 then ctx.last_expr_ok = false; return false end
        let cmp_op: i32 = mb_lower_compare_op(sem_op, lhs_scalar)
        if cmp_op == 0 then ctx.last_expr_ok = false; return false end
        let dst: i32 = mb_ctx_fresh_value(ctx)
        mb_emit_compare(ctx, dst, cmp_op, 0, lhs_scalar, 0, lhs_val, rhs_val)
        ctx.last_expr_value = dst; ctx.last_expr_scalar = @{T.BackBool}; ctx.last_expr_ok = true
        return true
    end
    if tag == @{T.EX_LOGIC} then
        let left_idx: i32 = tree.expr_lhs[idx]
        if not mb_lower_expr_fn(ctx, tree, left_idx) then return false end
        let left_val: i32 = ctx.last_expr_value
        let left_scalar: i32 = ctx.last_expr_scalar
        let right_idx: i32 = tree.expr_rhs[idx]
        if not mb_lower_expr_fn(ctx, tree, right_idx) then return false end
        let right_val: i32 = ctx.last_expr_value
        let right_scalar: i32 = ctx.last_expr_scalar
        let tok: i32 = tree.expr_op[idx]
        let dst: i32 = mb_ctx_fresh_value(ctx)
        if tok == @{T.TK_AND} then
            let false_val: i32 = mb_ctx_fresh_value(ctx)
            mb_emit_const(ctx, false_val, @{T.BackBool}, 0, 0, 0)
            mb_emit_select(ctx, dst, 0, @{T.BackBool}, 0, left_val, right_val, false_val)
            ctx.last_expr_value = dst; ctx.last_expr_scalar = @{T.BackBool}; ctx.last_expr_ok = true
            return true
        end
        if tok == @{T.TK_OR} then
            let true_val: i32 = mb_ctx_fresh_value(ctx)
            mb_emit_const(ctx, true_val, @{T.BackBool}, 1, 0, 0)
            mb_emit_select(ctx, dst, 0, @{T.BackBool}, 0, left_val, true_val, right_val)
            ctx.last_expr_value = dst; ctx.last_expr_scalar = @{T.BackBool}; ctx.last_expr_ok = true
            return true
        end
        ctx.last_expr_ok = false; return false
    end
    if tag == @{T.EX_CAST} then
        let child_idx: i32 = tree.expr_lhs[idx]
        if not mb_lower_expr_fn(ctx, tree, child_idx) then return false end
        let child_val: i32 = ctx.last_expr_value
        let child_scalar: i32 = ctx.last_expr_scalar
        let dst_scalar: i32 = ctx.expr_scalar[idx]
        if dst_scalar == child_scalar then
            ctx.last_expr_value = child_val; ctx.last_expr_scalar = dst_scalar; ctx.last_expr_ok = true
            return true
        end
        let cast_op: i32 = tree.expr_op[idx]
        let surface_op: i32 = select(cast_op == @{T.TK_AS}, @{T.SC_SURFACE_CAST}, cast_op)
        let machine_op: i32 = mb_lower_surface_cast_op(surface_op, child_scalar, dst_scalar)
        if machine_op == 0 then ctx.last_expr_ok = false; return false end
        let dst: i32 = mb_ctx_fresh_value(ctx)
        mb_emit_cast(ctx, dst, machine_op, dst_scalar, child_val)
        ctx.last_expr_value = dst; ctx.last_expr_scalar = dst_scalar; ctx.last_expr_ok = true
        return true
    end
    if tag == @{T.EX_SELECT} then
        let arg_start: i32 = tree.expr_lhs[idx]
        let arg_count: i32 = tree.expr_rhs[idx]
        if arg_count ~= 3 then ctx.last_expr_ok = false; return false end
        let cond_idx: i32 = tree.expr_list[as(index, arg_start)]
        if not mb_lower_expr_fn(ctx, tree, cond_idx) then return false end
        let cond_val: i32 = ctx.last_expr_value
        let then_idx: i32 = tree.expr_list[as(index, arg_start + 1)]
        if not mb_lower_expr_fn(ctx, tree, then_idx) then return false end
        let then_val: i32 = ctx.last_expr_value
        let else_idx: i32 = tree.expr_list[as(index, arg_start + 2)]
        if not mb_lower_expr_fn(ctx, tree, else_idx) then return false end
        let else_val: i32 = ctx.last_expr_value
        let result_scalar: i32 = ctx.expr_scalar[idx]
        let dst: i32 = mb_ctx_fresh_value(ctx)
        mb_emit_select(ctx, dst, 0, result_scalar, 0, cond_val, then_val, else_val)
        ctx.last_expr_value = dst; ctx.last_expr_scalar = result_scalar; ctx.last_expr_ok = true
        return true
    end
    if tag == @{T.EX_DEREF} then
        let child_idx: i32 = tree.expr_lhs[idx]
        if not mb_lower_expr_fn(ctx, tree, child_idx) then return false end
        let child_val: i32 = ctx.last_expr_value
        let result_scalar: i32 = ctx.expr_scalar[idx]
        let dst: i32 = mb_ctx_fresh_value(ctx)
        mb_emit_load_info(ctx, dst, 0, result_scalar, 0, 0, child_val, 0, 0, 1, 4, 0, 4, 0, 0, 1)
        ctx.last_expr_value = dst; ctx.last_expr_scalar = result_scalar; ctx.last_expr_ok = true
        return true
    end
    if tag == @{T.EX_LEN} then
        let child_idx: i32 = tree.expr_lhs[idx]
        let child_tag: i32 = tree.expr_tag[child_idx]
        if child_tag == @{T.EX_REF} then
            let name_tok: i32 = tree.expr_tok[child_idx]
            let slot: i32 = mb_env_lookup(ctx.env, name_tok)
            let kind: i32 = select(slot >= 0, ctx.env.kind[as(index, slot)], 0)
            let aux0: i32 = select(slot >= 0, ctx.env.aux0[as(index, slot)], 0)
            if slot >= 0 and kind == @{MB_LOCAL_VIEW} then
                ctx.last_expr_value = aux0; ctx.last_expr_scalar = @{T.BackIndex}; ctx.last_expr_ok = true
                return true
            end
        end
        ctx.last_expr_ok = false; return false
    end
    if tag == @{T.EX_ADDR} then
        ctx.last_expr_ok = false; return false
    end
    if tag == @{T.EX_INDEX} then
        ctx.last_expr_ok = false; return false
    end
    if tag == @{T.EX_CALL} then
        ctx.last_expr_ok = false; return false
    end
    if tag == @{T.EX_CONTROL} then
        ctx.last_expr_ok = false; return false
    end
    if tag == @{T.EX_DOT} then
        ctx.last_expr_ok = false; return false
    end
    if tag == @{T.EX_VIEW} then
        ctx.last_expr_ok = false; return false
    end
    ctx.last_expr_ok = false
    return false
end

]]

local kNEW_MB_LOWER_EXPR_REGION = [[
-- ── Required protocol entrypoints ───────────────────────────────────

-- Lower an expression returning ExprResult protocol.
-- Delegates to mb_lower_expr_fn (func-based, no region emits).
-- Safe to emit from other regions since this region emits no sub-regions.
local mb_lower_expr_region = region(ctx: ptr(@{MomBackLowerCtx}), idx: i32;
                                    done: cont(value: i32, scalar: i32, ok: bool))
entry start()
    let ok: bool = mb_lower_expr_fn(ctx, ctx.tree, idx)
    jump done(value = ctx.last_expr_value, scalar = ctx.last_expr_scalar, ok = ok)
end
end

]]

local kNEW_EXPORTS = [[
M.mb_lower_expr_region = mb_lower_expr_region
M.mb_lower_expr_ops_view = mb_lower_expr_ops_view
M.mb_lower_call_args = mb_lower_call_args
M.mb_expr_lit = mb_expr_lit
M.mb_expr_ref = mb_expr_ref
M.mb_expr_view = mb_expr_view
M.mb_expr_len = mb_expr_len
M.mb_expr_addr_of = mb_expr_addr_of
M.mb_expr_index = mb_expr_index
M.mb_expr_dot = mb_expr_dot
M.mb_lower_expr_fn = mb_lower_expr_fn
M.mb_token_to_compare_op = mb_token_to_compare_op

return M
end
]]

-- Now build the final content.
-- Strategy: anchor replacements on unique comment headers.

-- 3a. Remove the old recursive regions + Step 6 section.
-- Pattern: from "Lower a unary expression." up to (but not including) "Required protocol entrypoints"
-- But we need to KEEP: mb_expr_call, mb_expr_view, mb_expr_len

-- First, replace the entire block from "-- Lower a unary expression." through the Step 6 end
-- with a placeholder that just keeps call/view/len + new content.

local remove_start = "-- Lower a unary expression."
local remove_end_marker = "-- ── Required protocol entrypoints ───────────────────────────────────"

local s_start, s_end = content:find(remove_start, 1, true)
local e_start, e_end = content:find(remove_end_marker, 1, true)

local head = content:sub(1, s_start - 1)
local tail = content:sub(e_start)

local middle = kMB_EXPR_CALL .. kMB_EXPR_VIEW .. kMB_EXPR_LEN .. kNEW_STEP6 .. kMB_LOWER_EXPR_FN

content = head .. middle .. tail

-- 4. Replace the old mb_lower_expr_region with the new func-based version
local old_region_start = "-- Lower an expression returning ExprResult protocol."
local old_region_end = "end\n\n-- Lower an expression returning ViewResult protocol."

local rs, re = content:find(old_region_start, 1, true)
local es2, ee2 = content:find(old_region_end, 1, true)

local head2 = content:sub(1, rs - 1)
local tail2 = content:sub(ee2)

content = head2 .. "-- Lower an expression returning ExprResult protocol.\n-- Delegates to mb_lower_expr_fn (func-based, no region emits).\n-- Safe to emit from other regions since this region emits no sub-regions.\nlocal mb_lower_expr_region = region(ctx: ptr(@{MomBackLowerCtx}), idx: i32;\n                                    done: cont(value: i32, scalar: i32, ok: bool))\nentry start()\n    let ok: bool = mb_lower_expr_fn(ctx, ctx.tree, idx)\n    jump done(value = ctx.last_expr_value, scalar = ctx.last_expr_scalar, ok = ok)\nend\nend\n\n" .. tail2

-- 5. Replace old exports with new exports
local old_exports_start = "M.mb_lower_expr_region = mb_lower_expr_region\nM.mb_lower_expr_ops_view = mb_lower_expr_ops_view\nM.mb_lower_call_args = mb_lower_call_args"
local es3, ee3 = content:find(old_exports_start, 1, true)
if not es3 then
    -- Try alternate pattern (with different spacing)
    old_exports_start = "M%.mb_lower_expr_region = mb_lower_expr_region"
    es3, ee3 = content:find(old_exports_start, 1, true)
end

if es3 then
    local head3 = content:sub(1, es3 - 1)
    content = head3 .. kNEW_EXPORTS
else
    error("Could not find exports section")
end

f = io.open("lua/moonlift/mom/back/expr_lower.mlua", "w")
f:write(content)
f:close()

print("Transformation complete")
