local pvm = require("moonlift.pvm")

local M = {}

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

function M.Define(T, base)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    -- This module is parameterized by the tree-to-C base callbacks, so do not
    -- use a global cache entry when a caller passes a fresh base table.
    if base == nil and T._moonlift_api_cache.tree_control_to_c ~= nil then return T._moonlift_api_cache.tree_control_to_c end

    base = base or {}
    local Core = T.MoonCore
    local Ty = T.MoonType
    local Bn = T.MoonBind
    local Tr = T.MoonTree
    local C = T.MoonC
    local TypeToC = require("moonlift.type_to_c").Define(T)
    local Facts = require("moonlift.tree_control_facts").Define(T)
    local CFG = require("moonlift.c_cfg").Define(T)

    local function append_all(out, xs)
        for i = 1, #(xs or {}) do out[#out + 1] = xs[i] end
    end

    local function label_id(region_id, label)
        return C.CBackendLabel("ml_" .. sanitize(region_id) .. "_" .. sanitize(label.name))
    end

    local function synthetic_label(ctx, prefix)
        ctx.next_label = (ctx.next_label or 0) + 1
        return C.CBackendLabel("ml_" .. sanitize(prefix or "bb") .. "_" .. tostring(ctx.next_label))
    end

    local function block_param_local(region_id, label, param)
        return C.CBackendLocalId("ml_" .. sanitize(region_id) .. "_" .. sanitize(label.name) .. "_" .. sanitize(param.name))
    end

    local function lower_expr(expr, ctx)
        if not base.expr_to_c then error("tree_control_to_c: missing base.expr_to_c", 3) end
        local atom, stmts = base.expr_to_c(expr, ctx)
        return atom, stmts or {}
    end

    local function lower_stmt(stmt, ctx)
        if not base.stmt_to_c then error("tree_control_to_c: missing base.stmt_to_c for " .. tostring(stmt.kind), 3) end
        local before = ctx.current_stmts and #ctx.current_stmts or nil
        local stmts = base.stmt_to_c(stmt, ctx)
        if stmts ~= nil then return stmts end
        if before ~= nil then
            local out = {}
            for i = before + 1, #ctx.current_stmts do out[#out + 1] = ctx.current_stmts[i] end
            return out
        end
        return {}
    end

    local function build_param_maps(region)
        local by_label = {}
        local ordered = {}
        local function add(label, params, is_entry)
            local c_label = label_id(region.region_id, label)
            local list = {}
            for i = 1, #params do
                local p = params[i]
                list[i] = {
                    name = p.name,
                    local_id = block_param_local(region.region_id, label, p),
                    ty = TypeToC.type_to_c(p.ty),
                    source = p,
                    is_entry = is_entry,
                }
            end
            by_label[label.name] = list
            ordered[c_label.text] = list
        end
        add(region.entry.label, region.entry.params, true)
        for i = 1, #region.blocks do add(region.blocks[i].label, region.blocks[i].params, false) end
        return by_label, ordered
    end

    local function switch_arm_literal(arm)
        if arm.literal ~= nil then return arm.literal end
        local raw = tostring(arm.raw_key or "0")
        if raw == "true" then return Core.LitBool(true) end
        if raw == "false" then return Core.LitBool(false) end
        return Core.LitInt(raw)
    end

    local function args_for_jump(region, param_map, target_label, args, ctx, out_stmts)
        local by_name = {}
        for i = 1, #args do by_name[args[i].name] = args[i].value end
        local params = param_map[target_label.name] or {}
        local atoms = {}
        for i = 1, #params do
            local expr = by_name[params[i].name]
            if expr == nil then error("tree_control_to_c: missing jump arg " .. params[i].name .. " for " .. target_label.name, 3) end
            local atom, stmts = lower_expr(expr, ctx)
            append_all(out_stmts, stmts)
            atoms[i] = atom
        end
        return atoms
    end

    local lower_body

    local function yield_term(stmt, region, ctx, stmts)
        local cls = pvm.classof(stmt)
        if cls == Tr.StmtYieldVoid then
            if ctx.yield_label then return C.CBackendGoto(ctx.yield_label, {}) end
            return C.CBackendReturnVoid
        elseif cls == Tr.StmtYieldValue then
            local atom, expr_stmts = lower_expr(stmt.value, ctx)
            append_all(stmts, expr_stmts)
            if ctx.yield_value_local then
                stmts[#stmts + 1] = C.CBackendAssign(ctx.yield_value_local, C.CBackendRAtom(atom))
                return C.CBackendGoto(ctx.yield_label, {})
            end
            return C.CBackendReturn(atom)
        end
    end

    local function terminal_for(stmt, region, ctx, block_label, param_map, stmts, blocks)
        local cls = pvm.classof(stmt)
        if cls == Tr.StmtJump then
            local args = args_for_jump(region, param_map, stmt.target, stmt.args, ctx, stmts)
            return C.CBackendGoto(label_id(region.region_id, stmt.target), args)
        elseif cls == Tr.StmtYieldVoid or cls == Tr.StmtYieldValue then
            return yield_term(stmt, region, ctx, stmts)
        elseif cls == Tr.StmtReturnVoid then
            return C.CBackendReturnVoid
        elseif cls == Tr.StmtReturnValue then
            local atom, expr_stmts = lower_expr(stmt.value, ctx)
            append_all(stmts, expr_stmts)
            return C.CBackendReturn(atom)
        elseif cls == Tr.StmtTrap then
            return C.CBackendTrap
        elseif cls == Tr.StmtIf then
            local cond, expr_stmts = lower_expr(stmt.cond, ctx)
            append_all(stmts, expr_stmts)
            local then_label = synthetic_label(ctx, region.region_id .. "_then")
            local else_label = synthetic_label(ctx, region.region_id .. "_else")
            local child_ctx = {}
            for k, v in pairs(ctx) do child_ctx[k] = v end
            lower_body(stmt.then_body, region, child_ctx, then_label, {}, param_map, blocks)
            lower_body(stmt.else_body, region, child_ctx, else_label, {}, param_map, blocks)
            return C.CBackendIfGoto(cond, then_label, {}, else_label, {})
        elseif cls == Tr.StmtSwitch then
            if #(stmt.variant_arms or {}) > 0 then
                if #stmt.arms > 0 then error("tree_control_to_c: mixed scalar and variant switch arms are not supported", 3) end
                if not (base.named_type_name and base.tag_place and base.payload_place and base.addr_of_atom_place and base.payload_offset_for_type and base.bind_local and base.add_local and base.local_id_for) then
                    error("tree_control_to_c: variant switch helpers are not wired", 3)
                end
                local value, expr_stmts = lower_expr(stmt.value, ctx)
                append_all(stmts, expr_stmts)
                local type_name = base.named_type_name((stmt.value.h and stmt.value.h.ty) or nil)
                local def = type_name and ctx.variant_defs and ctx.variant_defs[type_name] or nil
                if def == nil then error("tree_control_to_c: variant switch requires tagged-union facts", 3) end
                local value_ty = TypeToC.type_to_c(stmt.value.h.ty, ctx)
                local tag_ty = TypeToC.type_to_c(Ty.TScalar(Core.ScalarU32), ctx)
                local tag_id = base.local_id_for(ctx, "variant_tag")
                base.add_local(ctx, tag_id, "variant_tag", tag_ty, { init_state = C.CBackendLocalInitialized })
                stmts[#stmts + 1] = C.CBackendPlaceLoad(tag_id, base.tag_place(value, value_ty, ctx, type_name))
                local cases = {}
                local payload_offset = base.payload_offset_for_type(ctx, type_name)
                for i = 1, #stmt.variant_arms do
                    local arm = stmt.variant_arms[i]
                    local variant = def.variants[arm.variant_name]
                    if variant == nil then error("tree_control_to_c: unknown variant arm " .. tostring(arm.variant_name), 3) end
                    local arm_label = synthetic_label(ctx, region.region_id .. "_variant_case")
                    local child_ctx = {}
                    for k, v in pairs(ctx) do child_ctx[k] = v end
                    if payload_offset ~= nil and #(arm.binds or {}) > 0 then
                        local pre = {}
                        local addr = base.addr_of_atom_place(value, value_ty, child_ctx, "variant_addr", pre)
                        for j = 1, #arm.binds do
                            local bind = arm.binds[j]
                            local bty = TypeToC.type_to_c(bind.ty, child_ctx)
                            local id = base.local_id_for(child_ctx, bind.name)
                            base.add_local(child_ctx, id, bind.name, bty, { init_state = C.CBackendLocalInitialized })
                            local off = payload_offset
                            local rec = variant.field_offsets and variant.field_offsets[bind.name]
                            if rec then off = off + rec.offset end
                            pre[#pre + 1] = C.CBackendPlaceLoad(id, base.payload_place(addr, off, bind.ty, child_ctx))
                            local b = Bn.Binding(Core.Id("variant:stmt_switch:" .. variant.name .. ":" .. bind.name), bind.name, bind.ty, Bn.BindingClassLocalValue)
                            base.bind_local(child_ctx, b, id, bty)
                        end
                        child_ctx.pre_stmts = pre
                        lower_body(arm.body, region, child_ctx, arm_label, {}, param_map, blocks)
                    else
                        lower_body(arm.body, region, child_ctx, arm_label, {}, param_map, blocks)
                    end
                    cases[i] = C.CBackendSwitchCase(Core.LitInt(tostring(variant.tag)), arm_label, {})
                end
                local default_label = synthetic_label(ctx, region.region_id .. "_default")
                local child_ctx = {}
                for k, v in pairs(ctx) do child_ctx[k] = v end
                lower_body(stmt.default_body, region, child_ctx, default_label, {}, param_map, blocks)
                return C.CBackendSwitchGoto(C.CBackendAtomLocal(tag_id), cases, default_label, {})
            end
            local value, expr_stmts = lower_expr(stmt.value, ctx)
            append_all(stmts, expr_stmts)
            local cases = {}
            for i = 1, #stmt.arms do
                local arm_label = synthetic_label(ctx, region.region_id .. "_case")
                local child_ctx = {}
                for k, v in pairs(ctx) do child_ctx[k] = v end
                lower_body(stmt.arms[i].body, region, child_ctx, arm_label, {}, param_map, blocks)
                cases[i] = C.CBackendSwitchCase(switch_arm_literal(stmt.arms[i]), arm_label, {})
            end
            local default_label = synthetic_label(ctx, region.region_id .. "_default")
            local child_ctx = {}
            for k, v in pairs(ctx) do child_ctx[k] = v end
            lower_body(stmt.default_body, region, child_ctx, default_label, {}, param_map, blocks)
            return C.CBackendSwitchGoto(value, cases, default_label, {})
        end
        error("tree_control_to_c: statement does not terminate block: " .. tostring(stmt.kind), 3)
    end

    lower_body = function(body, region, ctx, c_label, params, param_map, blocks)
        local builder = CFG.new(ctx, { entry = false })
        builder:start_block(c_label, params)
        local stmts = builder.current.stmts
        if ctx.pre_stmts then
            for i = 1, #ctx.pre_stmts do stmts[#stmts + 1] = ctx.pre_stmts[i] end
            ctx.pre_stmts = nil
        end
        local old_cfg = ctx.cfg
        ctx.cfg = builder
        -- Make explicit block parameters visible to expression lowering for this
        -- block body.  CBackendBlockParam intentionally stores only the lowered
        -- local id/type, so recover the source names from the region param map.
        -- The ctx.env binding shape matches tree_to_c's function/local entries.
        for _, mapped_params in pairs(param_map or {}) do
            if type(mapped_params) == "table" and #mapped_params == #(params or {}) then
                local same = true
                for j = 1, #(params or {}) do
                    if mapped_params[j].local_id.text ~= params[j]["local"].text then same = false; break end
                end
                if same then
                    ctx.env = ctx.env or {}
                    ctx.local_types = ctx.local_types or {}
                    for j = 1, #(params or {}) do
                        local p = mapped_params[j]
                        ctx.env[p.name] = { id = p.local_id, ty = p.ty, binding = p.source }
                        ctx.local_types[p.local_id.text] = p.ty
                    end
                    break
                end
            end
        end
        for i = 1, #body do
            local stmt = body[i]
            local cls = pvm.classof(stmt)
            if cls == Tr.StmtJump or cls == Tr.StmtYieldVoid or cls == Tr.StmtYieldValue
                or cls == Tr.StmtReturnVoid or cls == Tr.StmtReturnValue or cls == Tr.StmtTrap
                or cls == Tr.StmtIf or cls == Tr.StmtSwitch then
                local term = terminal_for(stmt, region, ctx, c_label, param_map, stmts, blocks)
                builder:terminate(term)
                append_all(blocks, builder:sealed_blocks(false))
                ctx.cfg = old_cfg
                return
            elseif cls == Tr.StmtJumpCont then
                error("tree_control_to_c: unresolved StmtJumpCont cannot reach C backend lowering", 3)
            else
                local lowered = lower_stmt(stmt, ctx)
                for j = 1, #lowered do builder:emit(lowered[j]) end
            end
        end
        ctx.cfg = old_cfg
        error("tree_control_to_c: unterminated control block " .. c_label.text, 2)
    end

    local function validate_region(region)
        -- The C backend represents control directly with labels/gotos, so an
        -- irreducible decision from the structured-control facts is diagnostic
        -- information, not a lowering blocker.  Block-local validation still
        -- catches malformed jumps/params before this phase.
        return Facts.decide(region)
    end

    local function region_blocks(region, ctx)
        ctx = ctx or {}
        validate_region(region)
        local param_map = build_param_maps(region)
        local blocks = {}

        local function c_params(label, params)
            local out = {}
            for i = 1, #params do
                out[i] = C.CBackendBlockParam(block_param_local(region.region_id, label, params[i]), TypeToC.type_to_c(params[i].ty, ctx))
            end
            return out
        end

        lower_body(region.entry.body, region, ctx, label_id(region.region_id, region.entry.label), c_params(region.entry.label, region.entry.params), param_map, blocks)
        for i = 1, #region.blocks do
            local b = region.blocks[i]
            lower_body(b.body, region, ctx, label_id(region.region_id, b.label), c_params(b.label, b.params), param_map, blocks)
        end
        return blocks
    end

    local function entry_goto(region, ctx)
        local atoms = {}
        local stmts = {}
        for i = 1, #region.entry.params do
            local atom, expr_stmts = lower_expr(region.entry.params[i].init, ctx)
            append_all(stmts, expr_stmts)
            atoms[i] = atom
        end
        return stmts, C.CBackendGoto(label_id(region.region_id, region.entry.label), atoms)
    end

    local function stmt_region_to_c(region, ctx)
        local blocks = region_blocks(region, ctx)
        local init_stmts, term = entry_goto(region, ctx or {})
        return { blocks = blocks, init_stmts = init_stmts, entry_term = term }
    end

    local function expr_region_to_c(region, ctx)
        local blocks = region_blocks(region, ctx)
        local init_stmts, term = entry_goto(region, ctx or {})
        return { blocks = blocks, init_stmts = init_stmts, entry_term = term, result_ty = TypeToC.type_to_c(region.result_ty, ctx) }
    end

    local api = {
        label_id = label_id,
        block_param_local = block_param_local,
        stmt_region_to_c = stmt_region_to_c,
        expr_region_to_c = expr_region_to_c,
        region_blocks = region_blocks,
        entry_goto = entry_goto,
        validate_region = validate_region,
    }
    if base == nil then T._moonlift_api_cache.tree_control_to_c = api end
    return api
end

return M
