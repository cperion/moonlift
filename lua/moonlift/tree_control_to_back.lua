local pvm = require("moonlift.pvm")

local M = {}

local function append_all(out, xs)
    for i = 1, #xs do out[#out + 1] = xs[i] end
end

local function label_key(label)
    return label.name
end

local function find_jump_arg(args, name)
    local found = nil
    for i = 1, #args do
        if args[i].name == name then
            if found ~= nil then return nil, "duplicate jump arg " .. name end
            found = args[i]
        end
    end
    if found == nil then return nil, "missing jump arg " .. name end
    return found, nil
end

function M.Define(T, base)
    local C = T.MoonCore
    local Bn = T.MoonBind
    local Sem = T.MoonSem
    local Ty = T.MoonType
    local Tr = T.MoonTree
    local Back = T.MoonBack

    local facts_api = require("moonlift.tree_control_facts").Define(T)

    local switch_key_raw
    local control_stmt_to_back
    local control_stmt_region_to_back
    local control_expr_region_to_back

    local function unsupported_stmt(_, _, reason)
        error("moonlift tree_control_to_back unsupported lowering: " .. tostring(reason or "control statement could not be lowered"), 2)
    end

    local function expr_value(result)
        if pvm.classof(result) == Tr.TreeBackExprValue then return result end
        return nil
    end

    local function shape_scalar(scalar)
        return Back.BackShapeScalar(scalar)
    end

    local function binding_id(region_id, label, name)
        return C.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. name)
    end

    local function value_id(nonce, region_id, label, name)
        return Back.BackValId("ctl:" .. tostring(nonce) .. ":" .. region_id .. ":" .. label.name .. ":" .. name)
    end

    local function block_id(nonce, region_id, label)
        return Back.BackBlockId("ctl:" .. tostring(nonce) .. ":" .. region_id .. ":" .. label.name)
    end

    local function synthetic_block_id(nonce, region_id, suffix)
        return Back.BackBlockId("ctl:" .. tostring(nonce) .. ":" .. region_id .. ":" .. suffix)
    end

    local function synthetic_value_id(nonce, region_id, suffix)
        return Back.BackValId("ctl:" .. tostring(nonce) .. ":" .. region_id .. ":" .. suffix)
    end

    local function param_specs(nonce, region_id, label, params, is_entry)
        local specs = {}
        for i = 1, #params do
            local scalar = base.back_scalar(params[i].ty)
            if scalar == nil then
                local ty_cls = pvm.classof(params[i].ty)
                if ty_cls == Ty.TNamed or ty_cls == Ty.TArray or (base.elem_size ~= nil and base.elem_size(params[i].ty) ~= nil) then scalar = Back.BackPtr end
            end
            if scalar == nil then return nil, "control block param has non-scalar type: " .. tostring(label.name) .. "." .. tostring(params[i].name) end
            local class
            if is_entry then
                class = Bn.BindingClassEntryBlockParam(region_id, label.name, i)
            else
                class = Bn.BindingClassBlockParam(region_id, label.name, i)
            end
            specs[#specs + 1] = {
                name = params[i].name,
                ty = params[i].ty,
                scalar = scalar,
                value = value_id(nonce, region_id, label, params[i].name),
                binding = Bn.Binding(binding_id(region_id, label, params[i].name), params[i].name, params[i].ty, class),
                init = params[i].init,
            }
        end
        return specs, nil
    end

    local function add_param_locals(env, outside_locals, specs)
        local locals = {}
        for i = 1, #outside_locals do locals[#locals + 1] = outside_locals[i] end
        local out = base.env_with_locals(env, locals)
        for i = 1, #specs do
            out = base.env_add(out, specs[i].binding, specs[i].value, specs[i].scalar)
        end
        return out
    end

    local function block_records(nonce, region_id, entry, blocks)
        local records = {}
        local labels = {}
        local entry_params, entry_err = param_specs(nonce, region_id, entry.label, entry.params, true)
        if entry_params == nil then return nil, nil, entry_err end
        records[#records + 1] = { label = entry.label, block = block_id(nonce, region_id, entry.label), params = entry_params, body = entry.body, is_entry = true }
        labels[label_key(entry.label)] = records[#records]
        for i = 1, #blocks do
            local params, err = param_specs(nonce, region_id, blocks[i].label, blocks[i].params, false)
            if params == nil then return nil, nil, err end
            records[#records + 1] = { label = blocks[i].label, block = block_id(nonce, region_id, blocks[i].label), params = params, body = blocks[i].body, is_entry = false }
            labels[label_key(blocks[i].label)] = records[#records]
        end
        return records, labels, nil
    end

    local function declare_blocks(cmds, records, exit_block, exit_value, exit_scalar)
        for i = 1, #records do
            cmds[#cmds + 1] = Back.CmdCreateBlock(records[i].block)
            local provenance = base.get_provenance()
            if provenance then
                provenance:record(#cmds, #cmds, nil, nil,
                    "block:" .. tostring(records[i].label.name))
            end
            for j = 1, #records[i].params do
                cmds[#cmds + 1] = Back.CmdAppendBlockParam(records[i].block, records[i].params[j].value, shape_scalar(records[i].params[j].scalar))
            end
        end
        cmds[#cmds + 1] = Back.CmdCreateBlock(exit_block)
        local provenance = base.get_provenance()
        if provenance then
            provenance:record(#cmds, #cmds, nil, nil,
                "block:" .. tostring(exit_block.text))
        end
        if exit_value ~= nil then
            cmds[#cmds + 1] = Back.CmdAppendBlockParam(exit_block, exit_value, shape_scalar(exit_scalar))
        end
    end

    local function lower_entry_jump(entry_record, env, cmds)
        local current = env
        local args = {}
        for i = 1, #entry_record.params do
            local init = expr_value(base.expr_to_back:one_uncached(entry_record.params[i].init, current))
            if init == nil then return unsupported_stmt(current, cmds) end
            append_all(cmds, init.cmds)
            args[#args + 1] = init.value
            current = init.env
        end
        cmds[#cmds + 1] = Back.CmdJump(entry_record.block, args)
        return Tr.TreeBackStmtResult(current, cmds, Back.BackTerminates)
    end

    local function jump_args_to_back(stmt, target, env)
        local cmds = {}
        local args = {}
        local current = env
        for i = 1, #target.params do
            local arg, err = find_jump_arg(stmt.args, target.params[i].name)
            if arg == nil then return nil, current, cmds, err end
            local lowered = base.expr_to_back:one_uncached(arg.value, current)
            local value = expr_value(lowered)
            if value == nil then
                local why = pvm.classof(lowered) == Tr.TreeBackExprUnsupported and lowered.reason or "unsupported expression"
                return nil, current, cmds, "unsupported jump arg " .. target.params[i].name .. ": " .. tostring(why) .. " at " .. tostring(arg.value)
            end
            append_all(cmds, value.cmds)
            args[#args + 1] = value.value
            current = value.env
        end
        return args, current, cmds, nil
    end

    switch_key_raw = function(key)
        if key.kind == "raw" then return key.raw end
        if key.kind == "const" then
            local cls = pvm.classof(key.value)
            if cls == Sem.ConstInt then return key.value.raw end
            if cls == Sem.ConstBool then return key.value.value and "1" or "0" end
            return nil
        end
        if key.kind == "expr" then
            -- A SwitchKeyExpr arises when a named const is used as a case label.
            -- Evaluate the expression as a compile-time constant to get its integer.
            local const_eval = base.const_eval
            local get_const_env = base.get_const_env
            if const_eval == nil or get_const_env == nil then return nil end
            local const_env = get_const_env()
            local value = const_eval.value(key.expr, const_env, const_eval.empty_local_env())
            if value == nil then return nil end
            local cls = pvm.classof(value)
            if cls == Sem.ConstInt  then return value.raw end
            if cls == Sem.ConstBool then return value.value and "1" or "0" end
            return nil
        end
        return nil
    end

    local function lower_body(stmts, env, ctx)
        local current = env
        local cmds = {}
        local flow = Back.BackFallsThrough
        for i = 1, #stmts do
            if flow == Back.BackTerminates then break end
            local result = control_stmt_to_back:one_uncached(stmts[i], current, ctx)
            append_all(cmds, result.cmds)
            current = result.env
            flow = result.flow
        end
        return current, cmds, flow
    end

    local function lower_joining_arms(arms, default_body, env, ctx, emit_term)
        local env_current = env
        local arm_blocks = {}
        for i = 1, #arms do
            env_current, arm_blocks[i] = base.env_next_block(env_current, "ctl.switch.arm")
        end
        local default_block; env_current, default_block = base.env_next_block(env_current, "ctl.switch.default")
        local join_block; env_current, join_block = base.env_next_block(env_current, "ctl.switch.join")

        local cmds = {}
        for i = 1, #arm_blocks do cmds[#cmds + 1] = Back.CmdCreateBlock(arm_blocks[i]) end
        cmds[#cmds + 1] = Back.CmdCreateBlock(default_block)
        cmds[#cmds + 1] = Back.CmdCreateBlock(join_block)
        local term = emit_term(arm_blocks, default_block)
        if term == nil then return unsupported_stmt(env_current, cmds) end
        cmds[#cmds + 1] = term
        for i = 1, #arm_blocks do cmds[#cmds + 1] = Back.CmdSealBlock(arm_blocks[i]) end
        cmds[#cmds + 1] = Back.CmdSealBlock(default_block)

        local fallers = {}
        for i = 1, #arms do
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(arm_blocks[i])
            local start = base.env_with_locals(base.env_with_counters(env, env_current), env.locals)
            local arm_env, arm_cmds, arm_flow = lower_body(arms[i].body, start, ctx)
            append_all(cmds, arm_cmds)
            if arm_flow ~= Back.BackTerminates then
                local jump_pos = #cmds + 1
                cmds[jump_pos] = Back.CmdJump(join_block, {})
                fallers[#fallers + 1] = { env = arm_env, jump_pos = jump_pos, args = {} }
            end
            env_current = base.env_with_counters(env_current, arm_env)
        end

        cmds[#cmds + 1] = Back.CmdSwitchToBlock(default_block)
        local default_start = base.env_with_locals(base.env_with_counters(env, env_current), env.locals)
        local default_env, default_cmds, default_flow = lower_body(default_body, default_start, ctx)
        append_all(cmds, default_cmds)
        if default_flow ~= Back.BackTerminates then
            local jump_pos = #cmds + 1
            cmds[jump_pos] = Back.CmdJump(join_block, {})
            fallers[#fallers + 1] = { env = default_env, jump_pos = jump_pos, args = {} }
        end
        env_current = base.env_with_counters(env_current, default_env)

        local out_locals = {}
        for i = 1, #env.locals do out_locals[#out_locals + 1] = env.locals[i] end
        local pre_counters = env_current
        if #fallers > 0 then
            for i = 1, #env.locals do
                local local_entry = env.locals[i]
                if pvm.classof(local_entry) == Tr.TreeBackScalarLocal
                    and local_entry.binding.class == Bn.BindingClassLocalCell then
                    local changed = false
                    local vals = {}
                    for j = 1, #fallers do
                        local found = base.env_lookup(fallers[j].env, local_entry.binding)
                        local v = found and found.value or local_entry.value
                        vals[j] = v
                        if v ~= local_entry.value then changed = true end
                    end
                    if changed then
                        local phi_env, phi_val = base.env_next_value(pre_counters, "ctl.phi")
                        pre_counters = phi_env
                        cmds[#cmds + 1] = Back.CmdAppendBlockParam(join_block, phi_val, shape_scalar(local_entry.ty))
                        for j = 1, #fallers do fallers[j].args[#fallers[j].args + 1] = vals[j] end
                        out_locals[#out_locals + 1] = Tr.TreeBackScalarLocal(local_entry.binding, phi_val, local_entry.ty)
                    end
                end
            end
            for i = 1, #fallers do cmds[fallers[i].jump_pos] = Back.CmdJump(join_block, fallers[i].args) end
        end

        local out_env = Tr.TreeBackEnv(out_locals, pre_counters.next_value, pre_counters.next_block, env.ret)
        cmds[#cmds + 1] = Back.CmdSealBlock(join_block)
        if #fallers > 0 then
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(join_block)
            return Tr.TreeBackStmtResult(out_env, cmds, Back.BackFallsThrough)
        end
        return Tr.TreeBackStmtResult(out_env, cmds, Back.BackTerminates)
    end

    local function lower_if(stmt, env, ctx)
        local cond = expr_value(base.expr_to_back:one_uncached(stmt.cond, env))
        if cond == nil then return pvm.once(unsupported_stmt(env, {})) end

        local env1, then_block = base.env_next_block(cond.env, "ctl.if.then")
        local env2, else_block = base.env_next_block(env1, "ctl.if.else")
        local env3, join_block = base.env_next_block(env2, "ctl.if.join")
        local cmds = {}
        append_all(cmds, cond.cmds)
        cmds[#cmds + 1] = Back.CmdCreateBlock(then_block)
        cmds[#cmds + 1] = Back.CmdCreateBlock(else_block)
        cmds[#cmds + 1] = Back.CmdCreateBlock(join_block)
        cmds[#cmds + 1] = Back.CmdBrIf(cond.value, then_block, {}, else_block, {})
        cmds[#cmds + 1] = Back.CmdSealBlock(then_block)
        cmds[#cmds + 1] = Back.CmdSealBlock(else_block)

        cmds[#cmds + 1] = Back.CmdSwitchToBlock(then_block)
        local then_start = base.env_with_locals(env3, env.locals)
        local then_env, then_cmds, then_flow = lower_body(stmt.then_body, then_start, ctx)
        if then_flow ~= Back.BackTerminates then then_cmds[#then_cmds + 1] = Back.CmdJump(join_block, {}) end
        local then_cmds_start = #cmds + 1
        append_all(cmds, then_cmds)
        local then_jump_pos = then_flow ~= Back.BackTerminates and (then_cmds_start + #then_cmds - 1) or nil

        cmds[#cmds + 1] = Back.CmdSwitchToBlock(else_block)
        local else_start = base.env_with_locals(base.env_with_counters(env, then_env), env.locals)
        local else_env, else_cmds, else_flow = lower_body(stmt.else_body, else_start, ctx)
        if else_flow ~= Back.BackTerminates then else_cmds[#else_cmds + 1] = Back.CmdJump(join_block, {}) end
        local else_cmds_start = #cmds + 1
        append_all(cmds, else_cmds)
        local else_jump_pos = else_flow ~= Back.BackTerminates and (else_cmds_start + #else_cmds - 1) or nil

        local out_locals = {}
        for i = 1, #env.locals do out_locals[#out_locals + 1] = env.locals[i] end
        local phi_then_args = {}
        local phi_else_args = {}
        local pre_counters = base.env_with_counters(env, else_env)
        for i = 1, #env.locals do
            local local_entry = env.locals[i]
            if pvm.classof(local_entry) == Tr.TreeBackScalarLocal
                and local_entry.binding.class == Bn.BindingClassLocalCell then
                local then_val = base.env_lookup(then_env, local_entry.binding)
                local else_val = base.env_lookup(else_env, local_entry.binding)
                local then_v = then_val and then_val.value or local_entry.value
                local else_v = else_val and else_val.value or local_entry.value
                local changed = (then_v ~= local_entry.value) or (else_v ~= local_entry.value)
                if changed then
                    local phi_env, phi_val = base.env_next_value(pre_counters, "ctl.phi")
                    pre_counters = phi_env
                    cmds[#cmds + 1] = Back.CmdAppendBlockParam(join_block, phi_val, shape_scalar(local_entry.ty))
                    phi_then_args[#phi_then_args + 1] = then_v
                    phi_else_args[#phi_else_args + 1] = else_v
                    out_locals[#out_locals + 1] = Tr.TreeBackScalarLocal(local_entry.binding, phi_val, local_entry.ty)
                end
            end
        end
        if #phi_then_args > 0 then
            if then_jump_pos ~= nil then cmds[then_jump_pos] = Back.CmdJump(join_block, phi_then_args) end
            if else_jump_pos ~= nil then cmds[else_jump_pos] = Back.CmdJump(join_block, phi_else_args) end
        end

        local out_env = Tr.TreeBackEnv(out_locals, pre_counters.next_value, pre_counters.next_block, env.ret)
        cmds[#cmds + 1] = Back.CmdSealBlock(join_block)
        if then_flow ~= Back.BackTerminates or else_flow ~= Back.BackTerminates then
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(join_block)
            return pvm.once(Tr.TreeBackStmtResult(out_env, cmds, Back.BackFallsThrough))
        end
        return pvm.once(Tr.TreeBackStmtResult(out_env, cmds, Back.BackTerminates))
    end

    local function lower_switch(stmt, env, ctx)
        local lowered_value = base.expr_to_back:one_uncached(stmt.value, env)
        local value = expr_value(lowered_value)
        if value == nil then
            local why = pvm.classof(lowered_value) == Tr.TreeBackExprUnsupported and lowered_value.reason or "unsupported switch value"
            return pvm.once(unsupported_stmt(env, {}, "switch value unsupported: " .. tostring(why) .. " at " .. tostring(stmt.value)))
        end
        local case_raws = {}
        for i = 1, #stmt.arms do
            local raw = stmt.arms[i].raw_key
            if raw == nil or raw == "" then return pvm.once(unsupported_stmt(value.env, value.cmds, "switch arm has non-raw case key in " .. tostring(stmt))) end
            case_raws[#case_raws + 1] = raw
        end
        local result = lower_joining_arms(stmt.arms, stmt.default_body, value.env, ctx, function(arm_blocks, default_block)
            local cases = {}
            for i = 1, #case_raws do cases[i] = Back.BackSwitchCase(case_raws[i], arm_blocks[i]) end
            return Back.CmdSwitchInt(value.value, value.ty, cases, default_block)
        end)
        local cmds = {}; append_all(cmds, value.cmds); append_all(cmds, result.cmds)
        return pvm.once(Tr.TreeBackStmtResult(result.env, cmds, result.flow))
    end

    control_stmt_to_back = pvm.phase("moonlift_tree_control_stmt_to_back", {
        [Tr.StmtJump] = function(self, env, ctx)
            local target = ctx.labels[label_key(self.target)]
            if target == nil then return pvm.once(unsupported_stmt(env, {})) end
            local args, env2, cmds, err = jump_args_to_back(self, target, env)
            if args == nil then return pvm.once(unsupported_stmt(env2, cmds, err)) end
            cmds[#cmds + 1] = Back.CmdJump(target.block, args)
            return pvm.once(Tr.TreeBackStmtResult(env2, cmds, Back.BackTerminates))
        end,
        [Tr.StmtYieldVoid] = function(_, env, ctx)
            if ctx.exit_value ~= nil then return pvm.once(unsupported_stmt(env, {}, "void yield in value-producing control region")) end
            ctx.has_exit_jump = true
            return pvm.once(Tr.TreeBackStmtResult(env, { Back.CmdJump(ctx.exit_block, {}) }, Back.BackTerminates))
        end,
        [Tr.StmtYieldValue] = function(self, env, ctx)
            if ctx.exit_value == nil then return pvm.once(unsupported_stmt(env, {}, "value yield in statement control region")) end
            local value = expr_value(base.expr_to_back:one_uncached(self.value, env))
            if value == nil then return pvm.once(unsupported_stmt(env, {}, "yield value could not be lowered")) end
            ctx.has_exit_jump = true
            local cmds = {}; append_all(cmds, value.cmds); cmds[#cmds + 1] = Back.CmdJump(ctx.exit_block, { value.value })
            return pvm.once(Tr.TreeBackStmtResult(value.env, cmds, Back.BackTerminates))
        end,
        [Tr.StmtIf] = lower_if,
        [Tr.StmtSwitch] = lower_switch,
        [Tr.StmtLet] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtVar] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtSet] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtAtomicStore] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtAtomicFence] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtExpr] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtAssert] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtReturnVoid] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtReturnValue] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtControl] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtUseRegionSlot] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
        [Tr.StmtUseRegionFrag] = function(self, env) return pvm.once(base.stmt_to_back:one_uncached(self, env)) end,
    }, { args_cache = "last" })

    local function validate_region(region)
        local decision = facts_api.decide(region)
        if pvm.classof(decision) == Tr.ControlDecisionIrreducible then
            return false, decision.reject
        end
        return true, nil
    end

    local function lower_region(region, region_id, entry, blocks, result_scalar, env)
        local ok = validate_region(region)
        if not ok then return nil, "invalid control region" end

        local nonce_env, nonce_id = base.env_next_block(env, "ctl.region")
        local nonce = nonce_id.text
        local records, labels, err = block_records(nonce, region_id, entry, blocks)
        if records == nil then return nil, err end
        local exit_block = synthetic_block_id(nonce, region_id, "exit")
        local exit_value = nil
        if result_scalar ~= nil then exit_value = synthetic_value_id(nonce, region_id, "result") end
        local ctx = { region_id = region_id, labels = labels, exit_block = exit_block, exit_value = exit_value, has_exit_jump = false }

        local cmds = {}
        declare_blocks(cmds, records, exit_block, exit_value, result_scalar)
        local entry_jump = lower_entry_jump(records[1], nonce_env, cmds)
        local current = entry_jump.env
        cmds = entry_jump.cmds

        local outside_locals = env.locals
        for i = 1, #records do
            cmds[#cmds + 1] = Back.CmdSwitchToBlock(records[i].block)
            local provenance = base.get_provenance()
            if provenance then
                provenance:record(#cmds, #cmds, nil, nil,
                    "switch:" .. tostring(records[i].label.name))
            end
            local start = add_param_locals(current, outside_locals, records[i].params)
            local body_env, body_cmds, flow = lower_body(records[i].body, start, ctx)
            append_all(cmds, body_cmds)
            if flow ~= Back.BackTerminates then unsupported_stmt(body_env, body_cmds, "control block can fall through without jump/yield/return") end
            current = base.env_with_counters(current, body_env)
        end
        for i = 1, #records do cmds[#cmds + 1] = Back.CmdSealBlock(records[i].block) end
        cmds[#cmds + 1] = Back.CmdSealBlock(exit_block)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(exit_block)

        local out_env = base.env_with_locals(current, outside_locals)
        local flow = ctx.has_exit_jump and Back.BackFallsThrough or Back.BackTerminates
        return { env = out_env, cmds = cmds, flow = flow, value = exit_value, scalar = result_scalar }, nil
    end

    control_stmt_region_to_back = pvm.phase("moonlift_tree_control_stmt_region_to_back", {
        [Tr.ControlStmtRegion] = function(self, env)
            local lowered, err = lower_region(self, self.region_id, self.entry, self.blocks, nil, env)
            if lowered == nil then return pvm.once(unsupported_stmt(env, {})) end
            return pvm.once(Tr.TreeBackStmtResult(lowered.env, lowered.cmds, lowered.flow))
        end,
    }, { args_cache = "last" })

    control_expr_region_to_back = pvm.phase("moonlift_tree_control_expr_region_to_back", {
        [Tr.ControlExprRegion] = function(self, env)
            local scalar = base.back_scalar(self.result_ty)
            if scalar == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, "control expression result has non-scalar type")) end
            local lowered, err = lower_region(self, self.region_id, self.entry, self.blocks, scalar, env)
            if lowered == nil then return pvm.once(Tr.TreeBackExprUnsupported(env, {}, err or "invalid control expression")) end
            return pvm.once(Tr.TreeBackExprValue(lowered.env, lowered.cmds, lowered.value, scalar))
        end,
    }, { args_cache = "last" })

    return {
        stmt_to_back = control_stmt_to_back,
        stmt_region_to_back = control_stmt_region_to_back,
        expr_region_to_back = control_expr_region_to_back,
    }
end

return M
