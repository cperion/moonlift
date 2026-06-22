local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local C = T.MoonCore
    local Ty = T.MoonType
    local Tr = T.MoonTree
    local O = T.MoonOpen
    local S = T.MoonSyntax

    local lower_type
    local lower_expr
    local lower_stmt
    local lower_stmt_items
    local lower_stmt_list
    local retarget_cont_jumps_stmts
    local region_frag
    local expr_frag

    local function path_text(path)
        local parts = {}
        for i = 1, #path.parts do parts[i] = path.parts[i].text end
        return table.concat(parts, ".")
    end

    local function lower_name(name)
        local cls = pvm.classof(name)
        if cls == S.SyntaxNameText then return name.text end
        if cls == S.SyntaxNamePath then return path_text(name.path) end
        if cls == S.SyntaxNameSplice then return name.splice.source end
        error("unsupported syntax name", 2)
    end

    local function splice_value(env, splice, role)
        local value = env and env[splice.key]
        if value == nil then value = env and env[splice.source] end
        if value == nil and env and env.fills and env.fills.bindings then
            for i = #env.fills.bindings, 1, -1 do
                local binding = env.fills.bindings[i]
                local slot = binding.slot and binding.slot.slot
                if slot and slot.key == splice.key then
                    value = binding.value
                    break
                end
            end
        end
        if value == nil then
            error("missing " .. role .. " splice value for " .. splice.source, 2)
        end
        return value
    end

    local function slot_value(value)
        local cls = pvm.classof(value)
        if cls == O.SlotValueType then return value.ty end
        if cls == O.SlotValueExpr then return value.expr end
        if cls == O.SlotValueTypes then return value.types end
        if cls == O.SlotValueExprs then return value.exprs end
        if cls == O.SlotValueParams then return value.params end
        if cls == O.SlotValueFields then return value.fields end
        if cls == O.SlotValueVariants then return value.variants end
        if cls == O.SlotValueBlockParams then return value.params end
        if cls == O.SlotValueEntryParams then return value.params end
        if cls == O.SlotValueOpenParams then return value.params end
        if cls == O.SlotValueContSlots then return value.conts end
        if cls == O.SlotValueControlBlocks then return value.blocks end
        if cls == O.SlotValueSwitchStmtArms then return value.arms end
        if cls == O.SlotValueSwitchExprArms then return value.arms end
        if cls == O.SlotValueRegion then return value.body end
        if cls == O.SlotValueRegionFrag then return value.frag end
        if cls == O.SlotValueExprFrag then return value.frag end
        if cls == O.SlotValueName then return value.text end
        return value
    end

    local function expect_list(value, role)
        value = slot_value(value)
        if type(value) ~= "table" then
            error("expected list for " .. role .. " spread, got " .. type(value), 3)
        end
        return value
    end

    local function expect_one(value, class, role)
        value = slot_value(value)
        local cls = pvm.classof(value)
        if cls ~= class and not (class.members and class.members[cls]) then
            error("expected " .. role .. " splice value", 3)
        end
        return value
    end

    local function lower_type_items(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxTypeItemOne then
                out[#out + 1] = lower_type(item.ty, env)
            elseif cls == S.SyntaxTypeItemSpread then
                local values = expect_list(splice_value(env, item.splice, "type list"), "type list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], Ty.Type, "type") end
            end
        end
        return out
    end

    lower_type = function(ty, env)
        local cls = pvm.classof(ty)
        if cls == S.SyntaxTypeTree then
            return ty.ty
        elseif cls == S.SyntaxTypeScalar then
            return Ty.TScalar(ty.scalar)
        elseif cls == S.SyntaxTypePath then
            return Ty.TNamed(Ty.TypeRefPath(ty.path))
        elseif cls == S.SyntaxTypePtr then
            return Ty.TPtr(lower_type(ty.elem, env))
        elseif cls == S.SyntaxTypeArray then
            return Ty.TArray(Ty.ArrayLenExpr(lower_expr(ty.len, env)), lower_type(ty.elem, env))
        elseif cls == S.SyntaxTypeSlice then
            return Ty.TSlice(lower_type(ty.elem, env))
        elseif cls == S.SyntaxTypeView then
            return Ty.TView(lower_type(ty.elem, env))
        elseif cls == S.SyntaxTypeLease then
            return Ty.TLease(lower_type(ty.base, env), Ty.LeaseOriginUnknown)
        elseif cls == S.SyntaxTypeHandle then
            return Ty.THandle(Ty.TypeRefPath(ty.path), Ty.HandleReprScalar(C.ScalarU32))
        elseif cls == S.SyntaxTypeFunc then
            return Ty.TFunc(lower_type_items(ty.params, env), lower_type(ty.result, env))
        elseif cls == S.SyntaxTypeClosure then
            return Ty.TClosure(lower_type_items(ty.params, env), lower_type(ty.result, env))
        elseif cls == S.SyntaxTypeSplice then
            return expect_one(splice_value(env, ty.splice, "type"), Ty.Type, "type")
        end
        error("unsupported syntax type " .. tostring(cls and cls.kind or cls), 2)
    end

    local function lower_params(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxParamItemOne then
                out[#out + 1] = Ty.Param(item.name, lower_type(item.ty, env))
            elseif cls == S.SyntaxParamItemSpread then
                local values = expect_list(splice_value(env, item.splice, "parameter list"), "parameter list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], Ty.Param, "parameter") end
            end
        end
        return out
    end

    local function lower_open_params(items, env, owner_name)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxOpenParamItemOne then
                out[#out + 1] = O.OpenParam("param:" .. owner_name .. ":" .. item.name .. ":" .. tostring(#out + 1), item.name, lower_type(item.ty, env))
            elseif cls == S.SyntaxOpenParamItemSpread then
                local values = expect_list(splice_value(env, item.splice, "open parameter list"), "open parameter list")
                for i = 1, #values do
                    local value = slot_value(values[i])
                    local vcls = pvm.classof(value)
                    if vcls == O.OpenParam then
                        out[#out + 1] = value
                    elseif vcls == Ty.Param then
                        out[#out + 1] = O.OpenParam("param:" .. owner_name .. ":" .. value.name .. ":splice:" .. tostring(i), value.name, value.ty)
                    else
                        error("expected open parameter spread element", 2)
                    end
                end
            end
        end
        return out
    end

    local function lower_fields(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxFieldItemOne then
                out[#out + 1] = Ty.FieldDecl(item.name, lower_type(item.ty, env))
            elseif cls == S.SyntaxFieldItemSpread then
                local values = expect_list(splice_value(env, item.splice, "field list"), "field list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], Ty.FieldDecl, "field") end
            end
        end
        return out
    end

    local function lower_variants(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxVariantItemOne then
                out[#out + 1] = Ty.VariantDecl(item.name, lower_type(item.payload, env), lower_fields(item.fields, env))
            elseif cls == S.SyntaxVariantItemSpread then
                local values = expect_list(splice_value(env, item.splice, "variant list"), "variant list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], Ty.VariantDecl, "variant") end
            end
        end
        return out
    end

    local function lower_expr_items(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxExprItemOne then
                out[#out + 1] = lower_expr(item.expr, env)
            elseif cls == S.SyntaxExprItemSpread then
                local values = expect_list(splice_value(env, item.splice, "expression list"), "expression list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], Tr.Expr, "expression") end
            end
        end
        return out
    end

    local function lower_block_params(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxBlockParamItemOne then
                out[#out + 1] = Tr.BlockParam(item.name, lower_type(item.ty, env))
            elseif cls == S.SyntaxBlockParamItemSpread then
                local values = expect_list(splice_value(env, item.splice, "block parameter list"), "block parameter list")
                for i = 1, #values do
                    local value = slot_value(values[i])
                    local vcls = pvm.classof(value)
                    if vcls == Tr.BlockParam then
                        out[#out + 1] = value
                    elseif vcls == Ty.Param then
                        out[#out + 1] = Tr.BlockParam(value.name, value.ty)
                    else
                        error("expected block parameter spread element", 2)
                    end
                end
            end
        end
        return out
    end

    local function lower_entry_params(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxEntryParamItemOne then
                out[#out + 1] = Tr.EntryBlockParam(item.name, lower_type(item.ty, env), lower_expr(item.init, env))
            elseif cls == S.SyntaxEntryParamItemSpread then
                local values = expect_list(splice_value(env, item.splice, "entry parameter list"), "entry parameter list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], Tr.EntryBlockParam, "entry parameter") end
            end
        end
        return out
    end

    local function lower_conts(items, env, owner_name)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxContItemOne then
                local name = lower_name(item.name)
                out[#out + 1] = O.ContSlot("cont:" .. owner_name .. ":" .. name .. ":" .. tostring(#out + 1), name, lower_block_params(item.params, env))
            elseif cls == S.SyntaxContItemSpread then
                local values = expect_list(splice_value(env, item.splice, "continuation list"), "continuation list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], O.ContSlot, "continuation") end
            end
        end
        return out
    end

    local function lower_control_blocks(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxControlBlockItemOne then
                local name = lower_name(item.label)
                out[#out + 1] = Tr.ControlBlock(Tr.BlockLabel(name), lower_block_params(item.params, env), lower_stmt_items(item.body, env))
            elseif cls == S.SyntaxControlBlockItemSpread then
                local values = expect_list(splice_value(env, item.splice, "control block list"), "control block list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], Tr.ControlBlock, "control block") end
            end
        end
        return out
    end

    local function switch_key_from_expr(expr)
        local cls = pvm.classof(expr)
        if cls == Tr.ExprLit then
            local lit = pvm.classof(expr.value)
            if lit == C.LitInt then return expr.value.raw end
            if lit == C.LitBool then return expr.value.value and "true" or "false" end
        elseif cls == Tr.ExprRef and pvm.classof(expr.ref) == T.MoonBind.ValueRefName then
            return expr.ref.name
        end
        error("switch spread lowering requires literal/name case keys", 2)
    end

    local function lower_switch_stmt_arms(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxSwitchStmtArmItemOne then
                out[#out + 1] = Tr.SwitchStmtArm(switch_key_from_expr(lower_expr(item.key, env)), lower_stmt_items(item.body, env))
            elseif cls == S.SyntaxSwitchStmtArmItemSpread then
                local values = expect_list(splice_value(env, item.splice, "switch statement arm list"), "switch statement arm list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], Tr.SwitchStmtArm, "switch statement arm") end
            end
        end
        return out
    end

    local function lower_switch_expr_arms(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxSwitchExprArmItemOne then
                out[#out + 1] = Tr.SwitchExprArm(switch_key_from_expr(lower_expr(item.key, env)), lower_stmt_items(item.body, env), lower_expr(item.result, env))
            elseif cls == S.SyntaxSwitchExprArmItemSpread then
                local values = expect_list(splice_value(env, item.splice, "switch expression arm list"), "switch expression arm list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], Tr.SwitchExprArm, "switch expression arm") end
            end
        end
        return out
    end

    local function retarget_cont_jumps_stmt(stmt, cont_by_name)
        local cls = pvm.classof(stmt)
        if cls == Tr.StmtJump then
            local target = stmt.target and stmt.target.name
            local slot = target and cont_by_name[target]
            if slot then return Tr.StmtJumpCont(stmt.h, slot, stmt.args) end
            return stmt
        elseif cls == Tr.StmtIf then
            return pvm.with(stmt, {
                then_body = retarget_cont_jumps_stmts(stmt.then_body, cont_by_name),
                else_body = retarget_cont_jumps_stmts(stmt.else_body, cont_by_name),
            })
        elseif cls == Tr.StmtSwitch then
            local arms, variant_arms = {}, {}
            for i = 1, #stmt.arms do
                arms[i] = pvm.with(stmt.arms[i], { body = retarget_cont_jumps_stmts(stmt.arms[i].body, cont_by_name) })
            end
            for i = 1, #stmt.variant_arms do
                variant_arms[i] = pvm.with(stmt.variant_arms[i], { body = retarget_cont_jumps_stmts(stmt.variant_arms[i].body, cont_by_name) })
            end
            return pvm.with(stmt, {
                arms = arms,
                variant_arms = variant_arms,
                default_body = retarget_cont_jumps_stmts(stmt.default_body, cont_by_name),
            })
        elseif cls == Tr.StmtControl then
            local region = stmt.region
            local entry = pvm.with(region.entry, {
                body = retarget_cont_jumps_stmts(region.entry.body, cont_by_name),
            })
            local blocks = {}
            for i = 1, #region.blocks do
                blocks[i] = pvm.with(region.blocks[i], {
                    body = retarget_cont_jumps_stmts(region.blocks[i].body, cont_by_name),
                })
            end
            return pvm.with(stmt, { region = pvm.with(region, { entry = entry, blocks = blocks }) })
        end
        return stmt
    end

    retarget_cont_jumps_stmts = function(stmts, cont_by_name)
        local out = {}
        for i = 1, #(stmts or {}) do out[i] = retarget_cont_jumps_stmt(stmts[i], cont_by_name) end
        return out
    end

    local function type_decl(decl, env)
        local cls = pvm.classof(decl)
        if cls == S.SyntaxTypeDeclStruct then
            return Tr.TypeDeclStruct(decl.name.text, lower_fields(decl.fields, env))
        elseif cls == S.SyntaxTypeDeclUnion then
            return Tr.TypeDeclTaggedUnionSugar(decl.name.text, lower_variants(decl.variants, env))
        end
        error("unsupported syntax type declaration " .. tostring(cls and cls.kind or cls), 2)
    end

    local function lower_frag_ref(ref, env, expr)
        local cls = pvm.classof(ref)
        if cls == S.SyntaxFragRefPath then
            local name = path_text(ref.path)
            return expr and O.ExprFragRefName(name) or O.RegionFragRefName(name), name
        elseif cls == S.SyntaxFragRefSplice then
            local value = slot_value(splice_value(env, ref.splice, expr and "expression fragment" or "region fragment"))
            if expr then
                if pvm.classof(value) == O.ExprFrag then
                    local slot = O.ExprFragSlot(ref.splice.key, ref.splice.source)
                    return O.ExprFragRefSlot(slot), ref.splice.source
                end
            elseif pvm.classof(value) == O.RegionFrag then
                local slot = O.RegionFragSlot(ref.splice.key, ref.splice.source)
                return O.RegionFragRefSlot(slot), ref.splice.source
            end
            error("expected fragment value for " .. ref.splice.source, 2)
        end
        error("unsupported fragment ref", 2)
    end

    lower_expr = function(expr, env)
        local cls = pvm.classof(expr)
        if cls == S.SyntaxExprTree then
            return expr.expr
        elseif cls == S.SyntaxExprSplice then
            return expect_one(splice_value(env, expr.splice, "expression"), Tr.Expr, "expression")
        elseif cls == S.SyntaxExprCall then
            return Tr.ExprCall(Tr.ExprSurface, lower_expr(expr.callee, env), lower_expr_items(expr.args, env))
        elseif cls == S.SyntaxExprEmit then
            local ref, name = lower_frag_ref(expr.frag, env, true)
            return Tr.ExprUseExprFrag(Tr.ExprSurface, "emit.expr." .. name, ref, lower_expr_items(expr.args, env), {})
        elseif cls == S.SyntaxExprSwitch then
            return Tr.ExprSwitch(Tr.ExprSurface, lower_expr(expr.value, env), lower_switch_expr_arms(expr.arms, env), expr.variant_arms, lower_stmt_items(expr.default_body, env), lower_expr(expr.default_expr, env))
        elseif cls == S.SyntaxExprControl then
            local entry = Tr.EntryControlBlock(Tr.BlockLabel(lower_name(expr.entry_label)), lower_entry_params(expr.entry_params, env), lower_stmt_items(expr.entry_body, env))
            return Tr.ExprControl(Tr.ExprSurface, Tr.ControlExprRegion(expr.region_id, lower_type(expr.result, env), entry, lower_control_blocks(expr.blocks, env)))
        end
        error("unsupported syntax expression " .. tostring(cls and cls.kind or cls), 2)
    end

    lower_stmt_list = function(stmts, env)
        local out = {}
        for _, stmt in ipairs(stmts or {}) do
            local cls = pvm.classof(stmt)
            if cls == S.Stmt or (S.Stmt.members and S.Stmt.members[cls]) then
                out[#out + 1] = lower_stmt(stmt, env)
            else
                out[#out + 1] = stmt
            end
        end
        return out
    end

    lower_stmt_items = function(items, env)
        local out = {}
        for _, item in ipairs(items or {}) do
            local cls = pvm.classof(item)
            if cls == S.SyntaxStmtItemOne then
                out[#out + 1] = lower_stmt(item.stmt, env)
            elseif cls == S.SyntaxStmtItemSpread then
                local values = expect_list(splice_value(env, item.splice, "statement list"), "statement list")
                for i = 1, #values do out[#out + 1] = expect_one(values[i], Tr.Stmt, "statement") end
            end
        end
        return out
    end

    lower_stmt = function(stmt, env)
        local cls = pvm.classof(stmt)
        if cls == S.SyntaxStmtTree then
            return stmt.stmt
        elseif cls == S.SyntaxStmtSplice then
            return expect_one(splice_value(env, stmt.splice, "statement"), Tr.Stmt, "statement")
        elseif cls == S.SyntaxStmtEmit then
            local ref, name = lower_frag_ref(stmt.frag, env, false)
            return Tr.StmtUseRegionFrag(Tr.StmtSurface, stmt.mode, "emit." .. name, ref, lower_expr_items(stmt.args, env), {}, stmt.conts)
        elseif cls == S.SyntaxStmtExpr then
            return Tr.StmtExpr(Tr.StmtSurface, lower_expr(stmt.expr, env))
        elseif cls == S.SyntaxStmtReturnValue then
            return Tr.StmtReturnValue(Tr.StmtSurface, lower_expr(stmt.value, env))
        elseif cls == S.SyntaxStmtYieldValue then
            return Tr.StmtYieldValue(Tr.StmtSurface, lower_expr(stmt.value, env))
        elseif cls == S.SyntaxStmtLet then
            return Tr.StmtLet(Tr.StmtSurface, stmt.binding, lower_expr(stmt.init, env))
        elseif cls == S.SyntaxStmtVar then
            return Tr.StmtVar(Tr.StmtSurface, stmt.binding, lower_expr(stmt.init, env))
        elseif cls == S.SyntaxStmtIf then
            return Tr.StmtIf(Tr.StmtSurface, lower_expr(stmt.cond, env), lower_stmt_items(stmt.then_body, env), lower_stmt_items(stmt.else_body, env))
        elseif cls == S.SyntaxStmtSwitch then
            return Tr.StmtSwitch(Tr.StmtSurface, lower_expr(stmt.value, env), lower_switch_stmt_arms(stmt.arms, env), stmt.variant_arms, lower_stmt_items(stmt.default_body, env))
        end
        error("unsupported syntax statement " .. tostring(cls and cls.kind or cls), 2)
    end

    local function lower_item(item, env)
        local cls = pvm.classof(item)
        if cls == S.SyntaxItemTree then
            return { item.item }
        elseif cls == S.SyntaxItemSpread then
            return expect_list(splice_value(env, item.splice, "item list"), "item list")
        elseif cls == S.SyntaxItemTypeDecl then
            return { Tr.ItemType(type_decl(item.decl, env)) }
        elseif cls == S.SyntaxItemFunc then
            local func = item.func
            local fcls = pvm.classof(func)
            if fcls == S.SyntaxFuncLocal then
                local params = lower_params(func.params, env)
                local result = lower_type(func.result, env)
                local body = lower_stmt_items(func.body, env)
                if #(func.contracts or {}) > 0 then
                    return { Tr.ItemFunc(Tr.FuncLocalContract(func.name, params, result, func.contracts, body)) }
                end
                return { Tr.ItemFunc(Tr.FuncLocal(func.name, params, result, body)) }
            elseif fcls == S.SyntaxFuncExport then
                local params = lower_params(func.params, env)
                local result = lower_type(func.result, env)
                local body = lower_stmt_items(func.body, env)
                if #(func.contracts or {}) > 0 then
                    return { Tr.ItemFunc(Tr.FuncExportContract(func.name, params, result, func.contracts, body)) }
                end
                return { Tr.ItemFunc(Tr.FuncExport(func.name, params, result, body)) }
            end
        elseif cls == S.SyntaxItemRegionFrag then
            return { Tr.ItemRegionFrag(region_frag(item.frag, env)) }
        elseif cls == S.SyntaxItemExprFrag then
            return { Tr.ItemExprFrag(expr_frag(item.frag, env)) }
        end
        error("unsupported syntax item " .. tostring(cls and cls.kind or cls), 2)
    end

    local function func(func, env)
        local cls = pvm.classof(func)
        if cls == S.SyntaxFuncLocal then
            local params = lower_params(func.params, env)
            local result = lower_type(func.result, env)
            local body = lower_stmt_items(func.body, env)
            if #(func.contracts or {}) > 0 then
                return Tr.FuncLocalContract(func.name, params, result, func.contracts, body)
            end
            return Tr.FuncLocal(func.name, params, result, body)
        elseif cls == S.SyntaxFuncExport then
            local params = lower_params(func.params, env)
            local result = lower_type(func.result, env)
            local body = lower_stmt_items(func.body, env)
            if #(func.contracts or {}) > 0 then
                return Tr.FuncExportContract(func.name, params, result, func.contracts, body)
            end
            return Tr.FuncExport(func.name, params, result, body)
        end
        error("unsupported syntax func " .. tostring(cls and cls.kind or cls), 2)
    end

    region_frag = function(frag, env)
        local owner = "region"
        if pvm.classof(frag.name) == O.NameRefText then owner = frag.name.text end
        local conts = lower_conts(frag.conts, env, owner)
        local cont_by_name = {}
        for i = 1, #conts do cont_by_name[conts[i].pretty_name] = conts[i] end
        local entry = Tr.EntryControlBlock(
            Tr.BlockLabel(lower_name(frag.entry_label)),
            lower_entry_params(frag.entry_params, env),
            retarget_cont_jumps_stmts(lower_stmt_items(frag.entry_body, env), cont_by_name))
        local blocks = lower_control_blocks(frag.blocks, env)
        for i = 1, #blocks do
            blocks[i] = pvm.with(blocks[i], { body = retarget_cont_jumps_stmts(blocks[i].body, cont_by_name) })
        end
        return O.RegionFrag(frag.name, lower_open_params(frag.params, env, owner), conts, O.OpenSet({}, {}, {}, {}), entry, blocks)
    end

    expr_frag = function(frag, env)
        local owner = "expr"
        if pvm.classof(frag.name) == O.NameRefText then owner = frag.name.text end
        return O.ExprFrag(frag.name, lower_open_params(frag.params, env, owner), O.OpenSet({}, {}, {}, {}), lower_expr(frag.body, env), lower_type(frag.result, env))
    end

    local function module(module, env)
        local items = {}
        for _, item in ipairs(module.items or {}) do
            local lowered = lower_item(item, env or {})
            for i = 1, #lowered do items[#items + 1] = lowered[i] end
        end
        return Tr.Module(Tr.ModuleSurface, items)
    end

    return {
        module = module,
        func = func,
        region_frag = region_frag,
        expr_frag = expr_frag,
        type = lower_type,
        type_decl = type_decl,
        expr = lower_expr,
        stmt = lower_stmt,
        stmt_list = lower_stmt_list,
        params = lower_params,
        fields = lower_fields,
        variants = lower_variants,
    }
end

return M
