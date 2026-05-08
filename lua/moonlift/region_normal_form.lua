-- Region Normal Form (RNF)
--
-- This pass is the explicit CFG-composition boundary for Moonlift regions.
-- It imports emitted region fragments into the caller control region by:
--   * alpha-renaming imported labels,
--   * binding runtime params into imported block params,
--   * routing continuation slots to caller labels/continuations,
--   * replacing the emit site with a jump to the imported entry block,
--   * hoisting imported blocks into the caller region.
--
-- After RNF, executable control regions should contain no lowerable
-- StmtUseRegionFrag nodes. Unresolved open fragment uses are left in place for
-- open validation to report.

local pvm = require("moonlift.pvm")

local M = {}

local function append_all(dst, src)
    for i = 1, #(src or {}) do dst[#dst + 1] = src[i] end
    return dst
end

function M.Define(T, cb)
    cb = cb or {}
    local O = T.MoonOpen
    local B = T.MoonBind
    local Tr = T.MoonTree

    local function one_expand_type(ty, env) return cb.expand_type(ty, env) end
    local function one_expand_expr(expr, env) return cb.expand_expr(expr, env) end
    local function one_expand_stmt_header(h, env) return cb.expand_stmt_header(h, env) end
    local function expand_plain_stmt(stmt, env)
        local out = {}
        local g, p, c = cb.expand_stmt(stmt, env)
        pvm.drain_into(g, p, c, out)
        return out
    end

    local function expand_exprs(xs, env)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one_expand_expr(xs[i], env) end
        return out
    end

    local function expand_jump_args(xs, env)
        local out = {}
        for i = 1, #xs do out[#out + 1] = pvm.with(xs[i], { value = one_expand_expr(xs[i].value, env) }) end
        return out
    end

    local function name_ref_key(name)
        local cls = pvm.classof(name)
        if cls == O.NameRefText then return name.text end
        if cls == O.NameRefSlot then return "slot:" .. name.slot.key end
        return tostring(name)
    end

    local function push_stack(stack, key, site)
        stack = stack or { order = {}, seen = {} }
        if stack.seen[key] then
            local path = {}
            for i = 1, #stack.order do path[#path + 1] = stack.order[i] end
            path[#path + 1] = key
            error("recursive region emit detected at " .. tostring(site) .. ": " .. table.concat(path, " -> "), 3)
        end
        local next_stack = { order = {}, seen = {} }
        for i = 1, #stack.order do next_stack.order[i] = stack.order[i] end
        for k, v in pairs(stack.seen) do next_stack.seen[k] = v end
        next_stack.order[#next_stack.order + 1] = key
        next_stack.seen[key] = true
        return next_stack
    end

    local function label_map_for_frag(frag, use_id)
        local map = {}
        local prefix = use_id .. "."
        map[frag.entry.label.name] = Tr.BlockLabel(prefix .. frag.entry.label.name)
        for i = 1, #frag.blocks do
            map[frag.blocks[i].label.name] = Tr.BlockLabel(prefix .. frag.blocks[i].label.name)
        end
        return map
    end

    local function rebase_label(label, map)
        return map[label.name] or label
    end

    local function runtime_param_name(name)
        return "__rt_" .. name
    end

    local function runtime_param_expr(name)
        return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(runtime_param_name(name)))
    end

    local function runtime_block_params(frag, env)
        local out = {}
        for i = 1, #frag.params do
            out[#out + 1] = Tr.BlockParam(runtime_param_name(frag.params[i].name), one_expand_type(frag.params[i].ty, env))
        end
        return out
    end

    local function runtime_jump_args_from_names(frag, captures)
        local out = {}
        for i = 1, #frag.params do
            out[#out + 1] = Tr.JumpArg(runtime_param_name(frag.params[i].name), runtime_param_expr(frag.params[i].name))
        end
        for i = 1, #(captures or {}) do
            out[#out + 1] = Tr.JumpArg(captures[i].name, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(captures[i].name)))
        end
        return out
    end

    local function prepend_runtime_args(args, frag, captures)
        local out = runtime_jump_args_from_names(frag, captures)
        for i = 1, #args do out[#out + 1] = args[i] end
        return out
    end

    local function rebase_stmts(stmts, map, frag, captures)
        local out = {}
        for i = 1, #stmts do
            local stmt = stmts[i]
            local cls = pvm.classof(stmt)
            if cls == Tr.StmtJump then
                local target = rebase_label(stmt.target, map)
                local args = map[stmt.target.name] and prepend_runtime_args(stmt.args, frag, captures) or stmt.args
                out[#out + 1] = pvm.with(stmt, { target = target, args = args })
            elseif cls == Tr.StmtIf then
                out[#out + 1] = pvm.with(stmt, {
                    then_body = rebase_stmts(stmt.then_body, map, frag, captures),
                    else_body = rebase_stmts(stmt.else_body, map, frag, captures),
                })
            elseif cls == Tr.StmtSwitch then
                local arms = {}
                for j = 1, #stmt.arms do
                    arms[#arms + 1] = pvm.with(stmt.arms[j], { body = rebase_stmts(stmt.arms[j].body, map, frag, captures) })
                end
                local variant_arms = {}
                for j = 1, #(stmt.variant_arms or {}) do
                    variant_arms[#variant_arms + 1] = pvm.with(stmt.variant_arms[j], { body = rebase_stmts(stmt.variant_arms[j].body, map, frag, captures) })
                end
                out[#out + 1] = pvm.with(stmt, {
                    arms = arms,
                    variant_arms = variant_arms,
                    default_body = rebase_stmts(stmt.default_body, map, frag, captures),
                })
            else
                out[#out + 1] = stmt
            end
        end
        return out
    end

    local function rebase_control_block_body(block, map, frag, captures)
        return pvm.with(block, { body = rebase_stmts(block.body, map, frag, captures) })
    end

    local function expr_ref_name(expr)
        if pvm.classof(expr) == Tr.ExprRef and pvm.classof(expr.ref) == B.ValueRefName then return expr.ref.name end
        return nil
    end

    local function capture_runtime_params(frag, env)
        local seen, params, args = {}, {}, {}
        for i = 1, #frag.params do seen[runtime_param_name(frag.params[i].name)] = true end
        for i = 1, #env.params do
            local binding = env.params[i]
            local name = expr_ref_name(binding.value)
            if name ~= nil and name:match("^__rt_") and not seen[name] then
                seen[name] = true
                params[#params + 1] = Tr.BlockParam(name, one_expand_type(binding.param.ty, env))
                args[#args + 1] = Tr.JumpArg(name, binding.value)
            end
        end
        return params, args
    end

    local function cont_slot_by_name(frag, name)
        for i = 1, #frag.conts do
            if frag.conts[i].pretty_name == name then return frag.conts[i] end
        end
        return nil
    end

    local function instantiate_cont_fills(frag, cont_fills)
        local out = {}
        for i = 1, #(cont_fills or {}) do
            local fill = cont_fills[i]
            local slot = cont_slot_by_name(frag, fill.name)
            if slot ~= nil then out[#out + 1] = O.ContBinding(slot.key, fill.target) end
        end
        return out
    end

    local normalize_stmts

    local function normalize_region_frag_use(stmt, env, stack)
        local frag = cb.lookup_region_frag_ref(stmt.frag, env)
        if frag == pvm.NIL then
            return pvm.with(stmt, { h = one_expand_stmt_header(stmt.h, env), args = expand_exprs(stmt.args, env) }), {}
        end

        local frag_key = name_ref_key(frag.name)
        local child_path = (env.rebase_prefix ~= "" and (env.rebase_prefix .. ".") or "") .. stmt.use_id
        local child_stack = push_stack(stack, frag_key, child_path)

        local runtime_param_bindings = {}
        for i = 1, #frag.params do
            runtime_param_bindings[#runtime_param_bindings + 1] = O.ParamBinding(frag.params[i], runtime_param_expr(frag.params[i].name))
        end
        local cont_bindings = instantiate_cont_fills(frag, stmt.cont_fills)
        local local_env = cb.env_at_path(cb.env_with_fills_conts_and_params(env, stmt.fills, cont_bindings, runtime_param_bindings), child_path)
        local init_env = cb.env_at_path(cb.env_with_fills_conts_and_params(env, stmt.fills, cont_bindings, cb.frag_param_bindings(frag.params, stmt.args, env)), child_path)
        local map = label_map_for_frag(frag, child_path)
        local capture_params, capture_args = capture_runtime_params(frag, env)

        local entry_params, entry_args = append_all(runtime_block_params(frag, local_env), capture_params), {}
        for i = 1, #frag.params do
            entry_args[#entry_args + 1] = Tr.JumpArg(runtime_param_name(frag.params[i].name), one_expand_expr(stmt.args[i], env))
        end
        append_all(entry_args, capture_args)
        for i = 1, #frag.entry.params do
            local p = frag.entry.params[i]
            entry_params[#entry_params + 1] = Tr.BlockParam(p.name, one_expand_type(p.ty, local_env))
            entry_args[#entry_args + 1] = Tr.JumpArg(p.name, one_expand_expr(p.init, init_env))
        end

        local entry_body, entry_nested = normalize_stmts(frag.entry.body, local_env, child_stack)
        local entry_body2 = cb.expand_stmts(rebase_stmts(entry_body, map, frag, capture_params), local_env)
        local blocks = { Tr.ControlBlock(map[frag.entry.label.name], entry_params, entry_body2) }
        for i = 1, #entry_nested do blocks[#blocks + 1] = rebase_control_block_body(entry_nested[i], map, frag, capture_params) end

        for i = 1, #frag.blocks do
            local block = frag.blocks[i]
            local params = append_all(runtime_block_params(frag, local_env), capture_params)
            for j = 1, #block.params do
                params[#params + 1] = pvm.with(block.params[j], { ty = one_expand_type(block.params[j].ty, local_env) })
            end
            local block_body, block_nested = normalize_stmts(block.body, local_env, child_stack)
            local block_body2 = cb.expand_stmts(rebase_stmts(block_body, map, frag, capture_params), local_env)
            blocks[#blocks + 1] = Tr.ControlBlock(map[block.label.name], params, block_body2)
            for j = 1, #block_nested do blocks[#blocks + 1] = rebase_control_block_body(block_nested[j], map, frag, capture_params) end
        end

        return Tr.StmtJump(one_expand_stmt_header(stmt.h, env), map[frag.entry.label.name], entry_args), blocks
    end

    normalize_stmts = function(stmts, env, stack)
        local body, blocks = {}, {}
        for i = 1, #stmts do
            local stmt = stmts[i]
            local cls = pvm.classof(stmt)
            if cls == Tr.StmtUseRegionFrag then
                local jump, more_blocks = normalize_region_frag_use(stmt, env, stack)
                body[#body + 1] = jump
                append_all(blocks, more_blocks)
            elseif cls == Tr.StmtIf then
                local then_body, then_blocks = normalize_stmts(stmt.then_body, env, stack)
                local else_body, else_blocks = normalize_stmts(stmt.else_body, env, stack)
                body[#body + 1] = pvm.with(stmt, {
                    h = one_expand_stmt_header(stmt.h, env),
                    cond = one_expand_expr(stmt.cond, env),
                    then_body = then_body,
                    else_body = else_body,
                })
                append_all(blocks, then_blocks)
                append_all(blocks, else_blocks)
            elseif cls == Tr.StmtSwitch then
                local arms = {}
                for j = 1, #stmt.arms do
                    local arm_body, arm_blocks = normalize_stmts(stmt.arms[j].body, env, stack)
                    arms[#arms + 1] = pvm.with(stmt.arms[j], { body = arm_body })
                    append_all(blocks, arm_blocks)
                end
                local variant_arms = {}
                for j = 1, #(stmt.variant_arms or {}) do
                    local arm_body, arm_blocks = normalize_stmts(stmt.variant_arms[j].body, env, stack)
                    variant_arms[#variant_arms + 1] = pvm.with(stmt.variant_arms[j], { body = arm_body })
                    append_all(blocks, arm_blocks)
                end
                local default_body, default_blocks = normalize_stmts(stmt.default_body, env, stack)
                body[#body + 1] = pvm.with(stmt, {
                    h = one_expand_stmt_header(stmt.h, env),
                    value = one_expand_expr(stmt.value, env),
                    arms = arms,
                    variant_arms = variant_arms,
                    default_body = default_body,
                })
                append_all(blocks, default_blocks)
            else
                append_all(body, expand_plain_stmt(stmt, env))
            end
        end
        return body, blocks
    end

    local function normalize_entry_block(block, env)
        local params = {}
        for i = 1, #block.params do
            params[#params + 1] = pvm.with(block.params[i], {
                ty = one_expand_type(block.params[i].ty, env),
                init = one_expand_expr(block.params[i].init, env),
            })
        end
        local body, blocks = normalize_stmts(block.body, env, { order = {}, seen = {} })
        return pvm.with(block, { params = params, body = body }), blocks
    end

    local function normalize_control_block(block, env)
        local params = {}
        for i = 1, #block.params do
            params[#params + 1] = pvm.with(block.params[i], { ty = one_expand_type(block.params[i].ty, env) })
        end
        local body, blocks = normalize_stmts(block.body, env, { order = {}, seen = {} })
        return pvm.with(block, { params = params, body = body }), blocks
    end

    local function normalize_control_stmt_region(region, env)
        local entry, entry_blocks = normalize_entry_block(region.entry, env)
        local blocks = {}
        append_all(blocks, entry_blocks)
        for i = 1, #region.blocks do
            local block, more = normalize_control_block(region.blocks[i], env)
            blocks[#blocks + 1] = block
            append_all(blocks, more)
        end
        return pvm.with(region, { entry = entry, blocks = blocks })
    end

    local function normalize_control_expr_region(region, env)
        local entry, entry_blocks = normalize_entry_block(region.entry, env)
        local blocks = {}
        append_all(blocks, entry_blocks)
        for i = 1, #region.blocks do
            local block, more = normalize_control_block(region.blocks[i], env)
            blocks[#blocks + 1] = block
            append_all(blocks, more)
        end
        return pvm.with(region, { result_ty = one_expand_type(region.result_ty, env), entry = entry, blocks = blocks })
    end

    return {
        normalize_stmts = normalize_stmts,
        control_stmt_region = normalize_control_stmt_region,
        control_expr_region = normalize_control_expr_region,
    }
end

return M
