local pvm = require("pvm")

local M = {}

local function map_array(src, fn)
    local out = {}
    if src == nil then return out end
    for i = 1, #src do out[i] = fn(src[i], i) end
    return out
end

function M.Define(T)
    local Elab = T.MoonliftElab
    local Meta = T.MoonliftMeta
    if Elab == nil or Meta == nil then error("lower_elab_to_meta: Elab and Meta modules must be defined", 2) end

    local lower_type
    local lower_source_binding
    local lower_binding
    local lower_place
    local lower_index_base
    local lower_domain
    local lower_loop
    local lower_intrinsic
    local lower_expr
    local lower_stmt
    local lower_func
    local lower_extern_func
    local lower_const
    local lower_static
    local lower_import
    local lower_type_decl
    local lower_item
    local lower_module

    local function one(boundary, node, env)
        if env ~= nil then return pvm.one(boundary(node, env)) end
        return pvm.one(boundary(node))
    end
    local function one_type(node, env) return one(lower_type, node, env) end
    local function one_source_binding(node, env) return one(lower_source_binding, node, env) end
    local function one_binding(node, env) return one(lower_binding, node, env) end
    local function one_place(node, env) return one(lower_place, node, env) end
    local function one_index_base(node, env) return one(lower_index_base, node, env) end
    local function one_domain(node, env) return one(lower_domain, node, env) end
    local function one_loop(node, env) return one(lower_loop, node, env) end
    local function one_intrinsic(node) return one(lower_intrinsic, node) end
    local function one_expr(node, env) return one(lower_expr, node, env) end
    local function one_stmt(node, env) return one(lower_stmt, node, env) end
    local function one_func(node, env) return one(lower_func, node, env) end
    local function one_extern_func(node, env) return one(lower_extern_func, node, env) end
    local function one_const(node, env) return one(lower_const, node, env) end
    local function one_static(node, env) return one(lower_static, node, env) end
    local function one_import(node, env) return one(lower_import, node, env) end
    local function one_type_decl(node, env) return one(lower_type_decl, node, env) end
    local function one_item(node, env) return one(lower_item, node, env) end
    local function one_module(node, env) return one(lower_module, node, env) end

    local function types(xs, env) return map_array(xs, function(x) return one_type(x, env) end) end
    local function exprs(xs, env) return map_array(xs, function(x) return one_expr(x, env) end) end
    local function stmts(xs, env) return map_array(xs, function(x) return one_stmt(x, env) end) end

    local function find_source_binding(env, binding)
        for i = 1, #(env.bindings or {}) do
            local entry = env.bindings[i]
            if entry.binding == binding then return entry.source end
        end
        return nil
    end

    local function find_source_type(env, ty)
        for i = 1, #(env.types or {}) do
            local entry = env.types[i]
            if entry.ty == ty then return entry.meta_ty end
        end
        return nil
    end

    lower_source_binding = pvm.phase("elab_to_meta_source_binding", {
        [Meta.MetaSourceParamBinding] = function(self) return pvm.once(Meta.MetaBindParam(self.param)) end,
        [Meta.MetaSourceValueImportBinding] = function(self) return pvm.once(Meta.MetaBindImport(self.import)) end,
        [Meta.MetaSourceExprSlotBinding] = function() error("lower_elab_to_meta: expr slot binding should be handled at expression position", 2) end,
        [Meta.MetaSourceFuncSlotBinding] = function(self) return pvm.once(Meta.MetaBindFuncSlot(self.slot)) end,
        [Meta.MetaSourceConstSlotBinding] = function(self) return pvm.once(Meta.MetaBindConstSlot(self.slot)) end,
        [Meta.MetaSourceStaticSlotBinding] = function(self) return pvm.once(Meta.MetaBindStaticSlot(self.slot)) end,
    })

    lower_type = pvm.phase("elab_to_meta_type", {
        [Elab.ElabTVoid] = function() return pvm.once(Meta.MetaTVoid) end,
        [Elab.ElabTBool] = function() return pvm.once(Meta.MetaTBool) end,
        [Elab.ElabTI8] = function() return pvm.once(Meta.MetaTI8) end,
        [Elab.ElabTI16] = function() return pvm.once(Meta.MetaTI16) end,
        [Elab.ElabTI32] = function() return pvm.once(Meta.MetaTI32) end,
        [Elab.ElabTI64] = function() return pvm.once(Meta.MetaTI64) end,
        [Elab.ElabTU8] = function() return pvm.once(Meta.MetaTU8) end,
        [Elab.ElabTU16] = function() return pvm.once(Meta.MetaTU16) end,
        [Elab.ElabTU32] = function() return pvm.once(Meta.MetaTU32) end,
        [Elab.ElabTU64] = function() return pvm.once(Meta.MetaTU64) end,
        [Elab.ElabTF32] = function() return pvm.once(Meta.MetaTF32) end,
        [Elab.ElabTF64] = function() return pvm.once(Meta.MetaTF64) end,
        [Elab.ElabTIndex] = function() return pvm.once(Meta.MetaTIndex) end,
        [Elab.ElabTPtr] = function(self, env) return pvm.once(Meta.MetaTPtr(one_type(self.elem, env))) end,
        [Elab.ElabTArray] = function(self, env) return pvm.once(Meta.MetaTArray(one_expr(self.count, env), one_type(self.elem, env))) end,
        [Elab.ElabTSlice] = function(self, env) return pvm.once(Meta.MetaTSlice(one_type(self.elem, env))) end,
        [Elab.ElabTView] = function(self, env) return pvm.once(Meta.MetaTView(one_type(self.elem, env))) end,
        [Elab.ElabTFunc] = function(self, env) return pvm.once(Meta.MetaTFunc(types(self.params, env), one_type(self.result, env))) end,
        [Elab.ElabTNamed] = function(self, env)
            local mapped = find_source_type(env, self)
            if mapped ~= nil then return pvm.once(mapped) end
            return pvm.once(Meta.MetaTNamed(self.module_name, self.type_name))
        end,
    })

    lower_binding = pvm.phase("elab_to_meta_binding", {
        [Elab.ElabLocalValue] = function(self, env)
            local mapped = find_source_binding(env, self)
            if mapped ~= nil then return pvm.once(one_source_binding(mapped, env)) end
            return pvm.once(Meta.MetaBindLocalValue(self.id, self.name, one_type(self.ty, env)))
        end,
        [Elab.ElabLocalCell] = function(self, env) return pvm.once(Meta.MetaBindLocalCell(self.id, self.name, one_type(self.ty, env))) end,
        [Elab.ElabArg] = function(self, env)
            local mapped = find_source_binding(env, self)
            if mapped ~= nil then return pvm.once(one_source_binding(mapped, env)) end
            return pvm.once(Meta.MetaBindLocalValue("arg." .. tostring(self.index), self.name, one_type(self.ty, env)))
        end,
        [Elab.ElabLoopCarry] = function(self, env) return pvm.once(Meta.MetaBindLoopCarry(self.loop_id, self.port_id, self.name, one_type(self.ty, env))) end,
        [Elab.ElabLoopIndex] = function(self, env) return pvm.once(Meta.MetaBindLoopIndex(self.loop_id, self.name, one_type(self.ty, env))) end,
        [Elab.ElabGlobalFunc] = function(self, env) return pvm.once(Meta.MetaBindGlobalFunc(self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Elab.ElabGlobalConst] = function(self, env) return pvm.once(Meta.MetaBindGlobalConst(self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Elab.ElabGlobalStatic] = function(self, env) return pvm.once(Meta.MetaBindGlobalStatic(self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Elab.ElabExtern] = function(self, env) return pvm.once(Meta.MetaBindExtern(self.symbol, one_type(self.ty, env))) end,
    })

    lower_place = pvm.phase("elab_to_meta_place", {
        [Elab.ElabPlaceBinding] = function(self, env) return pvm.once(Meta.MetaPlaceBinding(one_binding(self.binding, env))) end,
        [Elab.ElabPlaceDeref] = function(self, env) return pvm.once(Meta.MetaPlaceDeref(one_expr(self.base, env), one_type(self.elem, env))) end,
        [Elab.ElabPlaceField] = function(self, env) return pvm.once(Meta.MetaPlaceField(one_place(self.base, env), self.name, one_type(self.ty, env))) end,
        [Elab.ElabPlaceIndex] = function(self, env) return pvm.once(Meta.MetaPlaceIndex(one_index_base(self.base, env), one_expr(self.index, env), one_type(self.ty, env))) end,
    })

    lower_index_base = pvm.phase("elab_to_meta_index_base", {
        [Elab.ElabIndexBasePlace] = function(self, env) return pvm.once(Meta.MetaIndexBasePlace(one_place(self.base, env), one_type(self.elem, env))) end,
        [Elab.ElabIndexBaseView] = function(self, env) return pvm.once(Meta.MetaIndexBaseView(one_expr(self.base, env), one_type(self.elem, env))) end,
    })

    lower_domain = pvm.phase("elab_to_meta_domain", {
        [Elab.ElabDomainRange] = function(self, env) return pvm.once(Meta.MetaDomainRange(one_expr(self.stop, env))) end,
        [Elab.ElabDomainRange2] = function(self, env) return pvm.once(Meta.MetaDomainRange2(one_expr(self.start, env), one_expr(self.stop, env))) end,
        [Elab.ElabDomainZipEq] = function(self, env) return pvm.once(Meta.MetaDomainZipEq(exprs(self.values, env))) end,
        [Elab.ElabDomainValue] = function(self, env) return pvm.once(Meta.MetaDomainValue(one_expr(self.value, env))) end,
    })

    lower_intrinsic = pvm.phase("elab_to_meta_intrinsic", {
        [Elab.ElabPopcount] = function() return pvm.once(Meta.MetaPopcount) end,
        [Elab.ElabClz] = function() return pvm.once(Meta.MetaClz) end,
        [Elab.ElabCtz] = function() return pvm.once(Meta.MetaCtz) end,
        [Elab.ElabRotl] = function() return pvm.once(Meta.MetaRotl) end,
        [Elab.ElabRotr] = function() return pvm.once(Meta.MetaRotr) end,
        [Elab.ElabBswap] = function() return pvm.once(Meta.MetaBswap) end,
        [Elab.ElabFma] = function() return pvm.once(Meta.MetaFma) end,
        [Elab.ElabSqrt] = function() return pvm.once(Meta.MetaSqrt) end,
        [Elab.ElabAbs] = function() return pvm.once(Meta.MetaAbs) end,
        [Elab.ElabFloor] = function() return pvm.once(Meta.MetaFloor) end,
        [Elab.ElabCeil] = function() return pvm.once(Meta.MetaCeil) end,
        [Elab.ElabTruncFloat] = function() return pvm.once(Meta.MetaTruncFloat) end,
        [Elab.ElabRound] = function() return pvm.once(Meta.MetaRound) end,
        [Elab.ElabTrap] = function() return pvm.once(Meta.MetaTrap) end,
        [Elab.ElabAssume] = function() return pvm.once(Meta.MetaAssume) end,
    })

    local function carry_ports(xs, env) return map_array(xs, function(x) return Meta.MetaCarryPort(x.port_id, x.name, one_type(x.ty, env), one_expr(x.init, env)) end) end
    local function carry_updates(xs, env) return map_array(xs, function(x) return Meta.MetaCarryUpdate(x.port_id, one_expr(x.value, env)) end) end
    local function switch_stmt_arms(xs, env) return map_array(xs, function(x) return Meta.MetaSwitchStmtArm(one_expr(x.key, env), stmts(x.body, env)) end) end
    local function switch_expr_arms(xs, env) return map_array(xs, function(x) return Meta.MetaSwitchExprArm(one_expr(x.key, env), stmts(x.body, env), one_expr(x.result, env)) end) end
    local function field_inits(xs, env) return map_array(xs, function(x) return Meta.MetaFieldInit(x.name, one_expr(x.value, env)) end) end
    local function field_types(xs, env) return map_array(xs, function(x) return Meta.MetaFieldType(x.field_name, one_type(x.ty, env)) end) end

    local function lower_params_with_env(elab_params, env)
        local params = {}
        local bindings = {}
        for i = 1, #(elab_params or {}) do
            local p = elab_params[i]
            local meta_param = Meta.MetaParam("arg." .. tostring(i - 1), p.name, one_type(p.ty, env))
            params[i] = meta_param
            bindings[#bindings + 1] = Meta.MetaSourceBindingEntry(
                Elab.ElabArg(i - 1, p.name, p.ty),
                Meta.MetaSourceParamBinding(meta_param)
            )
        end
        local merged = {}
        for i = 1, #(env.bindings or {}) do merged[#merged + 1] = env.bindings[i] end
        for i = 1, #bindings do merged[#merged + 1] = bindings[i] end
        return params, Meta.MetaSourceEnv(env.module_name, merged, env.types or {})
    end

    lower_loop = pvm.phase("elab_to_meta_loop", {
        [Elab.ElabWhileStmt] = function(self, env) return pvm.once(Meta.MetaWhileStmt(self.loop_id, carry_ports(self.carries, env), one_expr(self.cond, env), stmts(self.body, env), carry_updates(self.next, env))) end,
        [Elab.ElabOverStmt] = function(self, env) return pvm.once(Meta.MetaOverStmt(self.loop_id, Meta.MetaIndexPort(self.index_port.name, one_type(self.index_port.ty, env)), one_domain(self.domain, env), carry_ports(self.carries, env), stmts(self.body, env), carry_updates(self.next, env))) end,
        [Elab.ElabWhileExpr] = function(self, env) return pvm.once(Meta.MetaWhileExpr(self.loop_id, carry_ports(self.carries, env), one_expr(self.cond, env), stmts(self.body, env), carry_updates(self.next, env), self.exit == Elab.ElabExprEndOnly and Meta.MetaExprEndOnly or Meta.MetaExprEndOrBreakValue, one_expr(self.result, env))) end,
        [Elab.ElabOverExpr] = function(self, env) return pvm.once(Meta.MetaOverExpr(self.loop_id, Meta.MetaIndexPort(self.index_port.name, one_type(self.index_port.ty, env)), one_domain(self.domain, env), carry_ports(self.carries, env), stmts(self.body, env), carry_updates(self.next, env), self.exit == Elab.ElabExprEndOnly and Meta.MetaExprEndOnly or Meta.MetaExprEndOrBreakValue, one_expr(self.result, env))) end,
    })

    lower_expr = pvm.phase("elab_to_meta_expr", {
        [Elab.ElabInt] = function(self, env) return pvm.once(Meta.MetaInt(self.raw, one_type(self.ty, env))) end,
        [Elab.ElabFloat] = function(self, env) return pvm.once(Meta.MetaFloat(self.raw, one_type(self.ty, env))) end,
        [Elab.ElabBool] = function(self, env) return pvm.once(Meta.MetaBool(self.value, one_type(self.ty, env))) end,
        [Elab.ElabNil] = function(self, env) return pvm.once(Meta.MetaNil(one_type(self.ty, env))) end,
        [Elab.ElabBindingExpr] = function(self, env)
            local mapped = find_source_binding(env, self.binding)
            if mapped ~= nil and mapped.slot ~= nil then return pvm.once(Meta.MetaExprSlotValue(mapped.slot, mapped.slot.ty)) end
            return pvm.once(Meta.MetaBindingExpr(one_binding(self.binding, env)))
        end,
        [Elab.ElabExprNeg] = function(self, env) return pvm.once(Meta.MetaExprNeg(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Elab.ElabExprNot] = function(self, env) return pvm.once(Meta.MetaExprNot(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Elab.ElabExprBNot] = function(self, env) return pvm.once(Meta.MetaExprBNot(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Elab.ElabExprAddrOf] = function(self, env) return pvm.once(Meta.MetaExprAddrOf(one_place(self.place, env), one_type(self.ty, env))) end,
        [Elab.ElabExprDeref] = function(self, env) return pvm.once(Meta.MetaExprDeref(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Elab.ElabExprAdd] = function(self, env) return pvm.once(Meta.MetaExprAdd(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprSub] = function(self, env) return pvm.once(Meta.MetaExprSub(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprMul] = function(self, env) return pvm.once(Meta.MetaExprMul(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprDiv] = function(self, env) return pvm.once(Meta.MetaExprDiv(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprRem] = function(self, env) return pvm.once(Meta.MetaExprRem(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprEq] = function(self, env) return pvm.once(Meta.MetaExprEq(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprNe] = function(self, env) return pvm.once(Meta.MetaExprNe(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprLt] = function(self, env) return pvm.once(Meta.MetaExprLt(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprLe] = function(self, env) return pvm.once(Meta.MetaExprLe(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprGt] = function(self, env) return pvm.once(Meta.MetaExprGt(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprGe] = function(self, env) return pvm.once(Meta.MetaExprGe(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprAnd] = function(self, env) return pvm.once(Meta.MetaExprAnd(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprOr] = function(self, env) return pvm.once(Meta.MetaExprOr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprBitAnd] = function(self, env) return pvm.once(Meta.MetaExprBitAnd(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprBitOr] = function(self, env) return pvm.once(Meta.MetaExprBitOr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprBitXor] = function(self, env) return pvm.once(Meta.MetaExprBitXor(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprShl] = function(self, env) return pvm.once(Meta.MetaExprShl(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprLShr] = function(self, env) return pvm.once(Meta.MetaExprLShr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprAShr] = function(self, env) return pvm.once(Meta.MetaExprAShr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Elab.ElabExprCastTo] = function(self, env) return pvm.once(Meta.MetaExprCastTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Elab.ElabExprTruncTo] = function(self, env) return pvm.once(Meta.MetaExprTruncTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Elab.ElabExprZExtTo] = function(self, env) return pvm.once(Meta.MetaExprZExtTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Elab.ElabExprSExtTo] = function(self, env) return pvm.once(Meta.MetaExprSExtTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Elab.ElabExprBitcastTo] = function(self, env) return pvm.once(Meta.MetaExprBitcastTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Elab.ElabExprSatCastTo] = function(self, env) return pvm.once(Meta.MetaExprSatCastTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Elab.ElabExprIntrinsicCall] = function(self, env) return pvm.once(Meta.MetaExprIntrinsicCall(one_intrinsic(self.op), one_type(self.ty, env), exprs(self.args, env))) end,
        [Elab.ElabCall] = function(self, env) return pvm.once(Meta.MetaCall(one_expr(self.callee, env), one_type(self.ty, env), exprs(self.args, env))) end,
        [Elab.ElabField] = function(self, env) return pvm.once(Meta.MetaField(one_expr(self.base, env), self.name, one_type(self.ty, env))) end,
        [Elab.ElabIndex] = function(self, env) return pvm.once(Meta.MetaIndex(one_index_base(self.base, env), one_expr(self.index, env), one_type(self.ty, env))) end,
        [Elab.ElabAgg] = function(self, env) return pvm.once(Meta.MetaAgg(one_type(self.ty, env), field_inits(self.fields, env))) end,
        [Elab.ElabArrayLit] = function(self, env) return pvm.once(Meta.MetaArrayLit(one_type(self.ty, env), exprs(self.elems, env))) end,
        [Elab.ElabIfExpr] = function(self, env) return pvm.once(Meta.MetaIfExpr(one_expr(self.cond, env), one_expr(self.then_expr, env), one_expr(self.else_expr, env), one_type(self.ty, env))) end,
        [Elab.ElabSelectExpr] = function(self, env) return pvm.once(Meta.MetaSelectExpr(one_expr(self.cond, env), one_expr(self.then_expr, env), one_expr(self.else_expr, env), one_type(self.ty, env))) end,
        [Elab.ElabSwitchExpr] = function(self, env) return pvm.once(Meta.MetaSwitchExpr(one_expr(self.value, env), switch_expr_arms(self.arms, env), one_expr(self.default_expr, env), one_type(self.ty, env))) end,
        [Elab.ElabExprLoop] = function(self, env) return pvm.once(Meta.MetaExprLoop(one_loop(self.loop, env), one_type(self.ty, env))) end,
        [Elab.ElabBlockExpr] = function(self, env) return pvm.once(Meta.MetaBlockExpr(stmts(self.stmts, env), one_expr(self.result, env), one_type(self.ty, env))) end,
        [Elab.ElabExprView] = function(self, env) return pvm.once(Meta.MetaExprView(one_expr(self.base, env), one_type(self.ty, env))) end,
        [Elab.ElabExprViewWindow] = function(self, env) return pvm.once(Meta.MetaExprViewWindow(one_expr(self.base, env), one_expr(self.start, env), one_expr(self.len, env), one_type(self.ty, env))) end,
        [Elab.ElabExprViewFromPtr] = function(self, env) return pvm.once(Meta.MetaExprViewFromPtr(one_expr(self.ptr, env), one_expr(self.len, env), one_type(self.ty, env))) end,
        [Elab.ElabExprViewFromPtrStrided] = function(self, env) return pvm.once(Meta.MetaExprViewFromPtrStrided(one_expr(self.ptr, env), one_expr(self.len, env), one_expr(self.stride, env), one_type(self.ty, env))) end,
        [Elab.ElabExprViewStrided] = function(self, env) return pvm.once(Meta.MetaExprViewStrided(one_expr(self.base, env), one_expr(self.stride, env), one_type(self.ty, env))) end,
        [Elab.ElabExprViewInterleaved] = function(self, env) return pvm.once(Meta.MetaExprViewInterleaved(one_expr(self.base, env), one_expr(self.stride, env), one_expr(self.lane, env), one_type(self.ty, env))) end,
    })

    lower_stmt = pvm.phase("elab_to_meta_stmt", {
        [Elab.ElabLet] = function(self, env) return pvm.once(Meta.MetaLet(self.id, self.name, one_type(self.ty, env), one_expr(self.init, env))) end,
        [Elab.ElabVar] = function(self, env) return pvm.once(Meta.MetaVar(self.id, self.name, one_type(self.ty, env), one_expr(self.init, env))) end,
        [Elab.ElabSet] = function(self, env) return pvm.once(Meta.MetaSet(one_place(self.place, env), one_expr(self.value, env))) end,
        [Elab.ElabExprStmt] = function(self, env) return pvm.once(Meta.MetaExprStmt(one_expr(self.expr, env))) end,
        [Elab.ElabAssert] = function(self, env) return pvm.once(Meta.MetaAssert(one_expr(self.cond, env))) end,
        [Elab.ElabIf] = function(self, env) return pvm.once(Meta.MetaIf(one_expr(self.cond, env), stmts(self.then_body, env), stmts(self.else_body, env))) end,
        [Elab.ElabSwitch] = function(self, env) return pvm.once(Meta.MetaSwitch(one_expr(self.value, env), switch_stmt_arms(self.arms, env), stmts(self.default_body, env))) end,
        [Elab.ElabReturnVoid] = function() return pvm.once(Meta.MetaReturnVoid) end,
        [Elab.ElabReturnValue] = function(self, env) return pvm.once(Meta.MetaReturnValue(one_expr(self.value, env))) end,
        [Elab.ElabBreak] = function() return pvm.once(Meta.MetaBreak) end,
        [Elab.ElabBreakValue] = function(self, env) return pvm.once(Meta.MetaBreakValue(one_expr(self.value, env))) end,
        [Elab.ElabContinue] = function() return pvm.once(Meta.MetaContinue) end,
        [Elab.ElabStmtLoop] = function(self, env) return pvm.once(Meta.MetaStmtLoop(one_loop(self.loop, env))) end,
    })

    lower_func = pvm.phase("elab_to_meta_func", {
        [Elab.ElabFuncLocal] = function(self, env)
            local params, body_env = lower_params_with_env(self.params, env)
            return pvm.once(Meta.MetaFuncLocal(Meta.MetaFuncSym(self.name, self.name), params, Meta.MetaOpenSet({}, {}, {}, {}), one_type(self.result, env), stmts(self.body, body_env)))
        end,
        [Elab.ElabFuncExport] = function(self, env)
            local params, body_env = lower_params_with_env(self.params, env)
            return pvm.once(Meta.MetaFuncExport(Meta.MetaFuncSym(self.name, self.name), params, Meta.MetaOpenSet({}, {}, {}, {}), one_type(self.result, env), stmts(self.body, body_env)))
        end,
    })
    lower_extern_func = pvm.phase("elab_to_meta_extern_func", { [Elab.ElabExternFunc] = function(self, env)
        local params = lower_params_with_env(self.params, env)
        return pvm.once(Meta.MetaExternFunc(Meta.MetaExternSym(self.name, self.name, self.symbol), params, one_type(self.result, env)))
    end })
    lower_const = pvm.phase("elab_to_meta_const", { [Elab.ElabConst] = function(self, env) return pvm.once(Meta.MetaConst(Meta.MetaConstSym(self.name, self.name), Meta.MetaOpenSet({}, {}, {}, {}), one_type(self.ty, env), one_expr(self.value, env))) end })
    lower_static = pvm.phase("elab_to_meta_static", { [Elab.ElabStatic] = function(self, env) return pvm.once(Meta.MetaStatic(Meta.MetaStaticSym(self.name, self.name), Meta.MetaOpenSet({}, {}, {}, {}), one_type(self.ty, env), one_expr(self.value, env))) end })
    lower_import = pvm.phase("elab_to_meta_import", { [Elab.ElabImport] = function(self) return pvm.once(Meta.MetaImport(self.module_name)) end })
    lower_type_decl = pvm.phase("elab_to_meta_type_decl", {
        [Elab.ElabStruct] = function(self, env) return pvm.once(Meta.MetaStruct(Meta.MetaTypeSym(self.name, self.name), field_types(self.fields, env))) end,
        [Elab.ElabUnion] = function(self, env) return pvm.once(Meta.MetaUnion(Meta.MetaTypeSym(self.name, self.name), field_types(self.fields, env))) end,
    })
    lower_item = pvm.phase("elab_to_meta_item", {
        [Elab.ElabItemFunc] = function(self, env) return pvm.once(Meta.MetaItemFunc(one_func(self.func, env))) end,
        [Elab.ElabItemExtern] = function(self, env) return pvm.once(Meta.MetaItemExtern(one_extern_func(self.func, env))) end,
        [Elab.ElabItemConst] = function(self, env) return pvm.once(Meta.MetaItemConst(one_const(self.c, env))) end,
        [Elab.ElabItemStatic] = function(self, env) return pvm.once(Meta.MetaItemStatic(one_static(self.s, env))) end,
        [Elab.ElabItemImport] = function(self, env) return pvm.once(Meta.MetaItemImport(one_import(self.imp, env))) end,
        [Elab.ElabItemType] = function(self, env) return pvm.once(Meta.MetaItemType(one_type_decl(self.t, env))) end,
    })
    lower_module = pvm.phase("elab_to_meta_module", {
        [Elab.ElabModule] = function(self, env)
            return pvm.once(Meta.MetaModule(Meta.MetaModuleNameFixed(self.module_name), Meta.MetaOpenSet({}, {}, {}, {}), map_array(self.items, function(item) return one_item(item, env) end)))
        end,
    })

    local api = {}
    api.phases = { type = lower_type, binding = lower_binding, place = lower_place, expr = lower_expr, stmt = lower_stmt, func = lower_func, item = lower_item, module = lower_module }
    function api.empty_env(module_name) return Meta.MetaSourceEnv(module_name or "", {}, {}) end
    function api.type(node, env) return one_type(node, env or api.empty_env()) end
    function api.expr(node, env) return one_expr(node, env or api.empty_env()) end
    function api.stmt(node, env) return one_stmt(node, env or api.empty_env()) end
    function api.func(node, env) return one_func(node, env or api.empty_env()) end
    function api.module(node, env) return one_module(node, env or api.empty_env(node.module_name)) end
    return api
end

return M
