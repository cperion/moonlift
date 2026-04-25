local pvm = require("pvm")

local M = {}

local function map_array(src, fn)
    local out = {}
    if src == nil then return out end
    for i = 1, #src do
        out[i] = fn(src[i], i)
    end
    return out
end

local function ensure_no_open_slots(open, where)
    if open ~= nil and open.slots ~= nil and #open.slots > 0 then
        error("seal_meta_to_elab: " .. where .. " still has open slots", 3)
    end
end

function M.Define(T)
    local Meta = T.MoonliftMeta
    local Elab = T.MoonliftElab
    if Meta == nil or Elab == nil then
        error("seal_meta_to_elab: MoonliftMeta and MoonliftElab must be defined", 2)
    end

    local seal_type
    local seal_intrinsic
    local seal_import_binding
    local seal_binding
    local seal_place
    local seal_index_base
    local seal_domain
    local seal_loop
    local seal_expr
    local seal_stmt
    local seal_func
    local seal_extern_func
    local seal_const
    local seal_static
    local seal_import
    local seal_type_decl
    local seal_item
    local seal_module_name

    local function one(boundary, node, env)
        if env ~= nil then
            return pvm.one(boundary(node, env))
        end
        return pvm.one(boundary(node))
    end

    local function one_type(node, env) return one(seal_type, node, env) end
    local function one_intrinsic(node) return one(seal_intrinsic, node) end
    local function one_import_binding(node, env) return one(seal_import_binding, node, env) end
    local function one_binding(node, env) return one(seal_binding, node, env) end
    local function one_place(node, env) return one(seal_place, node, env) end
    local function one_index_base(node, env) return one(seal_index_base, node, env) end
    local function one_domain(node, env) return one(seal_domain, node, env) end
    local function one_loop(node, env) return one(seal_loop, node, env) end
    local function one_expr(node, env) return one(seal_expr, node, env) end
    local function one_stmt(node, env) return one(seal_stmt, node, env) end
    local function one_func(node, env) return one(seal_func, node, env) end
    local function one_extern_func(node, env) return one(seal_extern_func, node, env) end
    local function one_const(node, env) return one(seal_const, node, env) end
    local function one_static(node, env) return one(seal_static, node, env) end
    local function one_import(node, env) return one(seal_import, node, env) end
    local function one_type_decl(node, env) return one(seal_type_decl, node, env) end
    local function one_item(node, env) return one(seal_item, node, env) end
    local function one_module_name(node, explicit_name) return pvm.one(seal_module_name(node, explicit_name)) end

    local function seal_types(xs, env) return map_array(xs, function(x) return one_type(x, env) end) end
    local function seal_params(xs, env)
        return map_array(xs, function(x)
            return Elab.ElabParam(x.name, one_type(x.ty, env))
        end)
    end
    local function seal_fields(xs, env)
        return map_array(xs, function(x)
            return Elab.ElabFieldType(x.field_name, one_type(x.ty, env))
        end)
    end
    local function seal_exprs(xs, env) return map_array(xs, function(x) return one_expr(x, env) end) end
    local function seal_stmts(xs, env) return map_array(xs, function(x) return one_stmt(x, env) end) end

    local function param_entries(params)
        return map_array(params, function(param, i)
            return Meta.MetaSealParamEntry(param, i - 1)
        end)
    end

    local function env_for_params(parent_env, params)
        return Meta.MetaSealEnv(parent_env.module_name, param_entries(params))
    end

    local function find_param(env, param)
        for i = 1, #env.params do
            local entry = env.params[i]
            if entry.param == param then
                return entry.index
            end
        end
        error("seal_meta_to_elab: parameter '" .. param.name .. "' is not in the seal environment", 3)
    end

    local function require_module_name(env, what)
        if env.module_name == nil or env.module_name == "" then
            error("seal_meta_to_elab: " .. what .. " requires a sealed module name", 3)
        end
        return env.module_name
    end

    seal_module_name = pvm.phase("seal_meta_module_name_to_elab", {
        [Meta.MetaModuleNameOpen] = function(_, explicit_name)
            if explicit_name == nil or explicit_name == "" then
                error("seal_meta_to_elab: open MetaModule requires an explicit module name", 2)
            end
            return pvm.once(explicit_name)
        end,
        [Meta.MetaModuleNameFixed] = function(self, explicit_name)
            if explicit_name ~= nil and explicit_name ~= "" and explicit_name ~= self.module_name then
                error("seal_meta_to_elab: explicit module name '" .. explicit_name .. "' does not match fixed MetaModule name '" .. self.module_name .. "'", 2)
            end
            return pvm.once(self.module_name)
        end,
    })

    seal_intrinsic = pvm.phase("seal_meta_intrinsic_to_elab", {
        [Meta.MetaPopcount] = function() return pvm.once(Elab.ElabPopcount) end,
        [Meta.MetaClz] = function() return pvm.once(Elab.ElabClz) end,
        [Meta.MetaCtz] = function() return pvm.once(Elab.ElabCtz) end,
        [Meta.MetaRotl] = function() return pvm.once(Elab.ElabRotl) end,
        [Meta.MetaRotr] = function() return pvm.once(Elab.ElabRotr) end,
        [Meta.MetaBswap] = function() return pvm.once(Elab.ElabBswap) end,
        [Meta.MetaFma] = function() return pvm.once(Elab.ElabFma) end,
        [Meta.MetaSqrt] = function() return pvm.once(Elab.ElabSqrt) end,
        [Meta.MetaAbs] = function() return pvm.once(Elab.ElabAbs) end,
        [Meta.MetaFloor] = function() return pvm.once(Elab.ElabFloor) end,
        [Meta.MetaCeil] = function() return pvm.once(Elab.ElabCeil) end,
        [Meta.MetaTruncFloat] = function() return pvm.once(Elab.ElabTruncFloat) end,
        [Meta.MetaRound] = function() return pvm.once(Elab.ElabRound) end,
        [Meta.MetaTrap] = function() return pvm.once(Elab.ElabTrap) end,
        [Meta.MetaAssume] = function() return pvm.once(Elab.ElabAssume) end,
    })

    seal_type = pvm.phase("seal_meta_type_to_elab", {
        [Meta.MetaTVoid] = function() return pvm.once(Elab.ElabTVoid) end,
        [Meta.MetaTBool] = function() return pvm.once(Elab.ElabTBool) end,
        [Meta.MetaTI8] = function() return pvm.once(Elab.ElabTI8) end,
        [Meta.MetaTI16] = function() return pvm.once(Elab.ElabTI16) end,
        [Meta.MetaTI32] = function() return pvm.once(Elab.ElabTI32) end,
        [Meta.MetaTI64] = function() return pvm.once(Elab.ElabTI64) end,
        [Meta.MetaTU8] = function() return pvm.once(Elab.ElabTU8) end,
        [Meta.MetaTU16] = function() return pvm.once(Elab.ElabTU16) end,
        [Meta.MetaTU32] = function() return pvm.once(Elab.ElabTU32) end,
        [Meta.MetaTU64] = function() return pvm.once(Elab.ElabTU64) end,
        [Meta.MetaTF32] = function() return pvm.once(Elab.ElabTF32) end,
        [Meta.MetaTF64] = function() return pvm.once(Elab.ElabTF64) end,
        [Meta.MetaTIndex] = function() return pvm.once(Elab.ElabTIndex) end,
        [Meta.MetaTPtr] = function(self, env) return pvm.once(Elab.ElabTPtr(one_type(self.elem, env))) end,
        [Meta.MetaTArray] = function(self, env) return pvm.once(Elab.ElabTArray(one_expr(self.count, env), one_type(self.elem, env))) end,
        [Meta.MetaTSlice] = function(self, env) return pvm.once(Elab.ElabTSlice(one_type(self.elem, env))) end,
        [Meta.MetaTView] = function(self, env) return pvm.once(Elab.ElabTView(one_type(self.elem, env))) end,
        [Meta.MetaTFunc] = function(self, env) return pvm.once(Elab.ElabTFunc(seal_types(self.params, env), one_type(self.result, env))) end,
        [Meta.MetaTNamed] = function(self) return pvm.once(Elab.ElabTNamed(self.module_name, self.type_name)) end,
        [Meta.MetaTLocalNamed] = function(self, env) return pvm.once(Elab.ElabTNamed(require_module_name(env, "local named type"), self.sym.name)) end,
        [Meta.MetaTSlot] = function() error("seal_meta_to_elab: type slot survived sealing", 2) end,
    })

    seal_import_binding = pvm.phase("seal_meta_import_binding_to_elab", {
        [Meta.MetaImportValue] = function()
            error("seal_meta_to_elab: generic value imports must be resolved before sealing", 2)
        end,
        [Meta.MetaImportGlobalFunc] = function(self, env)
            return pvm.once(Elab.ElabGlobalFunc(self.module_name, self.item_name, one_type(self.ty, env)))
        end,
        [Meta.MetaImportGlobalConst] = function(self, env)
            return pvm.once(Elab.ElabGlobalConst(self.module_name, self.item_name, one_type(self.ty, env)))
        end,
        [Meta.MetaImportGlobalStatic] = function(self, env)
            return pvm.once(Elab.ElabGlobalStatic(self.module_name, self.item_name, one_type(self.ty, env)))
        end,
        [Meta.MetaImportExtern] = function(self, env)
            return pvm.once(Elab.ElabExtern(self.symbol, one_type(self.ty, env)))
        end,
    })

    seal_binding = pvm.phase("seal_meta_binding_to_elab", {
        [Meta.MetaBindParam] = function(self, env)
            return pvm.once(Elab.ElabArg(find_param(env, self.param), self.param.name, one_type(self.param.ty, env)))
        end,
        [Meta.MetaBindLocalValue] = function(self, env) return pvm.once(Elab.ElabLocalValue(self.id, self.name, one_type(self.ty, env))) end,
        [Meta.MetaBindLocalCell] = function(self, env) return pvm.once(Elab.ElabLocalCell(self.id, self.name, one_type(self.ty, env))) end,
        [Meta.MetaBindLoopCarry] = function(self, env) return pvm.once(Elab.ElabLoopCarry(self.loop_id, self.port_id, self.name, one_type(self.ty, env))) end,
        [Meta.MetaBindLoopIndex] = function(self, env) return pvm.once(Elab.ElabLoopIndex(self.loop_id, self.name, one_type(self.ty, env))) end,
        [Meta.MetaBindGlobalFunc] = function(self, env) return pvm.once(Elab.ElabGlobalFunc(self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Meta.MetaBindGlobalConst] = function(self, env) return pvm.once(Elab.ElabGlobalConst(self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Meta.MetaBindGlobalStatic] = function(self, env) return pvm.once(Elab.ElabGlobalStatic(self.module_name, self.item_name, one_type(self.ty, env))) end,
        [Meta.MetaBindExtern] = function(self, env) return pvm.once(Elab.ElabExtern(self.symbol, one_type(self.ty, env))) end,
        [Meta.MetaBindImport] = function(self, env) return pvm.once(one_import_binding(self.import, env)) end,
        [Meta.MetaBindFuncSym] = function(self, env) return pvm.once(Elab.ElabGlobalFunc(require_module_name(env, "function symbol binding"), self.sym.name, one_type(self.ty, env))) end,
        [Meta.MetaBindExternSym] = function(self, env) return pvm.once(Elab.ElabExtern(self.sym.symbol, one_type(self.ty, env))) end,
        [Meta.MetaBindConstSym] = function(self, env) return pvm.once(Elab.ElabGlobalConst(require_module_name(env, "const symbol binding"), self.sym.name, one_type(self.ty, env))) end,
        [Meta.MetaBindStaticSym] = function(self, env) return pvm.once(Elab.ElabGlobalStatic(require_module_name(env, "static symbol binding"), self.sym.name, one_type(self.ty, env))) end,
        [Meta.MetaBindFuncSlot] = function() error("seal_meta_to_elab: function slot binding survived sealing", 2) end,
        [Meta.MetaBindConstSlot] = function() error("seal_meta_to_elab: const slot binding survived sealing", 2) end,
        [Meta.MetaBindStaticSlot] = function() error("seal_meta_to_elab: static slot binding survived sealing", 2) end,
    })

    seal_place = pvm.phase("seal_meta_place_to_elab", {
        [Meta.MetaPlaceBinding] = function(self, env) return pvm.once(Elab.ElabPlaceBinding(one_binding(self.binding, env))) end,
        [Meta.MetaPlaceDeref] = function(self, env) return pvm.once(Elab.ElabPlaceDeref(one_expr(self.base, env), one_type(self.elem, env))) end,
        [Meta.MetaPlaceField] = function(self, env) return pvm.once(Elab.ElabPlaceField(one_place(self.base, env), self.name, one_type(self.ty, env))) end,
        [Meta.MetaPlaceIndex] = function(self, env) return pvm.once(Elab.ElabPlaceIndex(one_index_base(self.base, env), one_expr(self.index, env), one_type(self.ty, env))) end,
        [Meta.MetaPlaceSlotValue] = function() error("seal_meta_to_elab: place slot survived sealing", 2) end,
    })

    seal_index_base = pvm.phase("seal_meta_index_base_to_elab", {
        [Meta.MetaIndexBasePlace] = function(self, env) return pvm.once(Elab.ElabIndexBasePlace(one_place(self.base, env), one_type(self.elem, env))) end,
        [Meta.MetaIndexBaseView] = function(self, env) return pvm.once(Elab.ElabIndexBaseView(one_expr(self.base, env), one_type(self.elem, env))) end,
    })

    seal_domain = pvm.phase("seal_meta_domain_to_elab", {
        [Meta.MetaDomainRange] = function(self, env) return pvm.once(Elab.ElabDomainRange(one_expr(self.stop, env))) end,
        [Meta.MetaDomainRange2] = function(self, env) return pvm.once(Elab.ElabDomainRange2(one_expr(self.start, env), one_expr(self.stop, env))) end,
        [Meta.MetaDomainZipEq] = function(self, env) return pvm.once(Elab.ElabDomainZipEq(seal_exprs(self.values, env))) end,
        [Meta.MetaDomainValue] = function(self, env) return pvm.once(Elab.ElabDomainValue(one_expr(self.value, env))) end,
        [Meta.MetaDomainSlotValue] = function() error("seal_meta_to_elab: domain slot survived sealing", 2) end,
    })

    local function seal_carry_ports(xs, env)
        return map_array(xs, function(x)
            return Elab.ElabCarryPort(x.port_id, x.name, one_type(x.ty, env), one_expr(x.init, env))
        end)
    end
    local function seal_carry_updates(xs, env)
        return map_array(xs, function(x) return Elab.ElabCarryUpdate(x.port_id, one_expr(x.value, env)) end)
    end
    local function seal_index_port(x, env)
        return Elab.ElabIndexPort(x.name, one_type(x.ty, env))
    end
    local function seal_exit(x)
        if x == Meta.MetaExprEndOnly then return Elab.ElabExprEndOnly end
        if x == Meta.MetaExprEndOrBreakValue then return Elab.ElabExprEndOrBreakValue end
        error("seal_meta_to_elab: unknown MetaExprExit", 3)
    end

    seal_loop = pvm.phase("seal_meta_loop_to_elab", {
        [Meta.MetaWhileStmt] = function(self, env)
            return pvm.once(Elab.ElabWhileStmt(self.loop_id, seal_carry_ports(self.carries, env), one_expr(self.cond, env), seal_stmts(self.body, env), seal_carry_updates(self.next, env)))
        end,
        [Meta.MetaOverStmt] = function(self, env)
            return pvm.once(Elab.ElabOverStmt(self.loop_id, seal_index_port(self.index_port, env), one_domain(self.domain, env), seal_carry_ports(self.carries, env), seal_stmts(self.body, env), seal_carry_updates(self.next, env)))
        end,
        [Meta.MetaWhileExpr] = function(self, env)
            return pvm.once(Elab.ElabWhileExpr(self.loop_id, seal_carry_ports(self.carries, env), one_expr(self.cond, env), seal_stmts(self.body, env), seal_carry_updates(self.next, env), seal_exit(self.exit), one_expr(self.result, env)))
        end,
        [Meta.MetaOverExpr] = function(self, env)
            return pvm.once(Elab.ElabOverExpr(self.loop_id, seal_index_port(self.index_port, env), one_domain(self.domain, env), seal_carry_ports(self.carries, env), seal_stmts(self.body, env), seal_carry_updates(self.next, env), seal_exit(self.exit), one_expr(self.result, env)))
        end,
    })

    local function seal_field_inits(xs, env)
        return map_array(xs, function(x) return Elab.ElabFieldInit(x.name, one_expr(x.value, env)) end)
    end
    local function seal_switch_stmt_arms(xs, env)
        return map_array(xs, function(x) return Elab.ElabSwitchStmtArm(one_expr(x.key, env), seal_stmts(x.body, env)) end)
    end
    local function seal_switch_expr_arms(xs, env)
        return map_array(xs, function(x) return Elab.ElabSwitchExprArm(one_expr(x.key, env), seal_stmts(x.body, env), one_expr(x.result, env)) end)
    end

    seal_expr = pvm.phase("seal_meta_expr_to_elab", {
        [Meta.MetaInt] = function(self, env) return pvm.once(Elab.ElabInt(self.raw, one_type(self.ty, env))) end,
        [Meta.MetaFloat] = function(self, env) return pvm.once(Elab.ElabFloat(self.raw, one_type(self.ty, env))) end,
        [Meta.MetaBool] = function(self, env) return pvm.once(Elab.ElabBool(self.value, one_type(self.ty, env))) end,
        [Meta.MetaNil] = function(self, env) return pvm.once(Elab.ElabNil(one_type(self.ty, env))) end,
        [Meta.MetaBindingExpr] = function(self, env) return pvm.once(Elab.ElabBindingExpr(one_binding(self.binding, env))) end,
        [Meta.MetaExprNeg] = function(self, env) return pvm.once(Elab.ElabExprNeg(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprNot] = function(self, env) return pvm.once(Elab.ElabExprNot(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprBNot] = function(self, env) return pvm.once(Elab.ElabExprBNot(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprAddrOf] = function(self, env) return pvm.once(Elab.ElabExprAddrOf(one_place(self.place, env), one_type(self.ty, env))) end,
        [Meta.MetaExprDeref] = function(self, env) return pvm.once(Elab.ElabExprDeref(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprAdd] = function(self, env) return pvm.once(Elab.ElabExprAdd(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprSub] = function(self, env) return pvm.once(Elab.ElabExprSub(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprMul] = function(self, env) return pvm.once(Elab.ElabExprMul(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprDiv] = function(self, env) return pvm.once(Elab.ElabExprDiv(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprRem] = function(self, env) return pvm.once(Elab.ElabExprRem(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprEq] = function(self, env) return pvm.once(Elab.ElabExprEq(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprNe] = function(self, env) return pvm.once(Elab.ElabExprNe(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprLt] = function(self, env) return pvm.once(Elab.ElabExprLt(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprLe] = function(self, env) return pvm.once(Elab.ElabExprLe(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprGt] = function(self, env) return pvm.once(Elab.ElabExprGt(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprGe] = function(self, env) return pvm.once(Elab.ElabExprGe(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprAnd] = function(self, env) return pvm.once(Elab.ElabExprAnd(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprOr] = function(self, env) return pvm.once(Elab.ElabExprOr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprBitAnd] = function(self, env) return pvm.once(Elab.ElabExprBitAnd(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprBitOr] = function(self, env) return pvm.once(Elab.ElabExprBitOr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprBitXor] = function(self, env) return pvm.once(Elab.ElabExprBitXor(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprShl] = function(self, env) return pvm.once(Elab.ElabExprShl(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprLShr] = function(self, env) return pvm.once(Elab.ElabExprLShr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprAShr] = function(self, env) return pvm.once(Elab.ElabExprAShr(one_type(self.ty, env), one_expr(self.lhs, env), one_expr(self.rhs, env))) end,
        [Meta.MetaExprCastTo] = function(self, env) return pvm.once(Elab.ElabExprCastTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprTruncTo] = function(self, env) return pvm.once(Elab.ElabExprTruncTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprZExtTo] = function(self, env) return pvm.once(Elab.ElabExprZExtTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprSExtTo] = function(self, env) return pvm.once(Elab.ElabExprSExtTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprBitcastTo] = function(self, env) return pvm.once(Elab.ElabExprBitcastTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprSatCastTo] = function(self, env) return pvm.once(Elab.ElabExprSatCastTo(one_type(self.ty, env), one_expr(self.value, env))) end,
        [Meta.MetaExprIntrinsicCall] = function(self, env) return pvm.once(Elab.ElabExprIntrinsicCall(one_intrinsic(self.op), one_type(self.ty, env), seal_exprs(self.args, env))) end,
        [Meta.MetaCall] = function(self, env) return pvm.once(Elab.ElabCall(one_expr(self.callee, env), one_type(self.ty, env), seal_exprs(self.args, env))) end,
        [Meta.MetaField] = function(self, env) return pvm.once(Elab.ElabField(one_expr(self.base, env), self.name, one_type(self.ty, env))) end,
        [Meta.MetaIndex] = function(self, env) return pvm.once(Elab.ElabIndex(one_index_base(self.base, env), one_expr(self.index, env), one_type(self.ty, env))) end,
        [Meta.MetaAgg] = function(self, env) return pvm.once(Elab.ElabAgg(one_type(self.ty, env), seal_field_inits(self.fields, env))) end,
        [Meta.MetaArrayLit] = function(self, env) return pvm.once(Elab.ElabArrayLit(one_type(self.ty, env), seal_exprs(self.elems, env))) end,
        [Meta.MetaIfExpr] = function(self, env) return pvm.once(Elab.ElabIfExpr(one_expr(self.cond, env), one_expr(self.then_expr, env), one_expr(self.else_expr, env), one_type(self.ty, env))) end,
        [Meta.MetaSelectExpr] = function(self, env) return pvm.once(Elab.ElabSelectExpr(one_expr(self.cond, env), one_expr(self.then_expr, env), one_expr(self.else_expr, env), one_type(self.ty, env))) end,
        [Meta.MetaSwitchExpr] = function(self, env) return pvm.once(Elab.ElabSwitchExpr(one_expr(self.value, env), seal_switch_expr_arms(self.arms, env), one_expr(self.default_expr, env), one_type(self.ty, env))) end,
        [Meta.MetaExprLoop] = function(self, env) return pvm.once(Elab.ElabExprLoop(one_loop(self.loop, env), one_type(self.ty, env))) end,
        [Meta.MetaBlockExpr] = function(self, env) return pvm.once(Elab.ElabBlockExpr(seal_stmts(self.stmts, env), one_expr(self.result, env), one_type(self.ty, env))) end,
        [Meta.MetaExprView] = function(self, env) return pvm.once(Elab.ElabExprView(one_expr(self.base, env), one_type(self.ty, env))) end,
        [Meta.MetaExprViewWindow] = function(self, env) return pvm.once(Elab.ElabExprViewWindow(one_expr(self.base, env), one_expr(self.start, env), one_expr(self.len, env), one_type(self.ty, env))) end,
        [Meta.MetaExprViewFromPtr] = function(self, env) return pvm.once(Elab.ElabExprViewFromPtr(one_expr(self.ptr, env), one_expr(self.len, env), one_type(self.ty, env))) end,
        [Meta.MetaExprViewFromPtrStrided] = function(self, env) return pvm.once(Elab.ElabExprViewFromPtrStrided(one_expr(self.ptr, env), one_expr(self.len, env), one_expr(self.stride, env), one_type(self.ty, env))) end,
        [Meta.MetaExprViewStrided] = function(self, env) return pvm.once(Elab.ElabExprViewStrided(one_expr(self.base, env), one_expr(self.stride, env), one_type(self.ty, env))) end,
        [Meta.MetaExprViewInterleaved] = function(self, env) return pvm.once(Elab.ElabExprViewInterleaved(one_expr(self.base, env), one_expr(self.stride, env), one_expr(self.lane, env), one_type(self.ty, env))) end,
        [Meta.MetaExprSlotValue] = function() error("seal_meta_to_elab: expr slot survived sealing", 2) end,
        [Meta.MetaExprUseExprFrag] = function() error("seal_meta_to_elab: expr fragment use must be expanded before sealing", 2) end,
    })

    seal_stmt = pvm.phase("seal_meta_stmt_to_elab", {
        [Meta.MetaLet] = function(self, env) return pvm.once(Elab.ElabLet(self.id, self.name, one_type(self.ty, env), one_expr(self.init, env))) end,
        [Meta.MetaVar] = function(self, env) return pvm.once(Elab.ElabVar(self.id, self.name, one_type(self.ty, env), one_expr(self.init, env))) end,
        [Meta.MetaSet] = function(self, env) return pvm.once(Elab.ElabSet(one_place(self.place, env), one_expr(self.value, env))) end,
        [Meta.MetaExprStmt] = function(self, env) return pvm.once(Elab.ElabExprStmt(one_expr(self.expr, env))) end,
        [Meta.MetaAssert] = function(self, env) return pvm.once(Elab.ElabAssert(one_expr(self.cond, env))) end,
        [Meta.MetaIf] = function(self, env) return pvm.once(Elab.ElabIf(one_expr(self.cond, env), seal_stmts(self.then_body, env), seal_stmts(self.else_body, env))) end,
        [Meta.MetaSwitch] = function(self, env) return pvm.once(Elab.ElabSwitch(one_expr(self.value, env), seal_switch_stmt_arms(self.arms, env), seal_stmts(self.default_body, env))) end,
        [Meta.MetaReturnVoid] = function() return pvm.once(Elab.ElabReturnVoid) end,
        [Meta.MetaReturnValue] = function(self, env) return pvm.once(Elab.ElabReturnValue(one_expr(self.value, env))) end,
        [Meta.MetaBreak] = function() return pvm.once(Elab.ElabBreak) end,
        [Meta.MetaBreakValue] = function(self, env) return pvm.once(Elab.ElabBreakValue(one_expr(self.value, env))) end,
        [Meta.MetaContinue] = function() return pvm.once(Elab.ElabContinue) end,
        [Meta.MetaStmtLoop] = function(self, env) return pvm.once(Elab.ElabStmtLoop(one_loop(self.loop, env))) end,
        [Meta.MetaStmtUseRegionSlot] = function() error("seal_meta_to_elab: region slot survived sealing", 2) end,
        [Meta.MetaStmtUseRegionFrag] = function() error("seal_meta_to_elab: region fragment use must be expanded before sealing", 2) end,
    })

    seal_func = pvm.phase("seal_meta_func_to_elab", {
        [Meta.MetaFuncLocal] = function(self, env)
            ensure_no_open_slots(self.open, "function '" .. self.sym.name .. "'")
            local fn_env = env_for_params(env, self.params)
            return pvm.once(Elab.ElabFuncLocal(self.sym.name, seal_params(self.params, env), one_type(self.result, env), seal_stmts(self.body, fn_env)))
        end,
        [Meta.MetaFuncExport] = function(self, env)
            ensure_no_open_slots(self.open, "function '" .. self.sym.name .. "'")
            local fn_env = env_for_params(env, self.params)
            return pvm.once(Elab.ElabFuncExport(self.sym.name, seal_params(self.params, env), one_type(self.result, env), seal_stmts(self.body, fn_env)))
        end,
    })

    seal_extern_func = pvm.phase("seal_meta_extern_func_to_elab", {
        [Meta.MetaExternFunc] = function(self, env)
            return pvm.once(Elab.ElabExternFunc(self.sym.name, self.sym.symbol, seal_params(self.params, env), one_type(self.result, env)))
        end,
    })

    seal_const = pvm.phase("seal_meta_const_to_elab", {
        [Meta.MetaConst] = function(self, env)
            ensure_no_open_slots(self.open, "const '" .. self.sym.name .. "'")
            return pvm.once(Elab.ElabConst(self.sym.name, one_type(self.ty, env), one_expr(self.value, env)))
        end,
    })

    seal_static = pvm.phase("seal_meta_static_to_elab", {
        [Meta.MetaStatic] = function(self, env)
            ensure_no_open_slots(self.open, "static '" .. self.sym.name .. "'")
            return pvm.once(Elab.ElabStatic(self.sym.name, one_type(self.ty, env), one_expr(self.value, env)))
        end,
    })

    seal_import = pvm.phase("seal_meta_import_to_elab", {
        [Meta.MetaImport] = function(self) return pvm.once(Elab.ElabImport(self.module_name)) end,
    })

    seal_type_decl = pvm.phase("seal_meta_type_decl_to_elab", {
        [Meta.MetaStruct] = function(self, env) return pvm.once(Elab.ElabStruct(self.sym.name, seal_fields(self.fields, env))) end,
        [Meta.MetaUnion] = function(self, env) return pvm.once(Elab.ElabUnion(self.sym.name, seal_fields(self.fields, env))) end,
    })

    seal_item = pvm.phase("seal_meta_item_to_elab", {
        [Meta.MetaItemFunc] = function(self, env) return pvm.once(Elab.ElabItemFunc(one_func(self.func, env))) end,
        [Meta.MetaItemExtern] = function(self, env) return pvm.once(Elab.ElabItemExtern(one_extern_func(self.func, env))) end,
        [Meta.MetaItemConst] = function(self, env) return pvm.once(Elab.ElabItemConst(one_const(self.c, env))) end,
        [Meta.MetaItemStatic] = function(self, env) return pvm.once(Elab.ElabItemStatic(one_static(self.s, env))) end,
        [Meta.MetaItemImport] = function(self, env) return pvm.once(Elab.ElabItemImport(one_import(self.imp, env))) end,
        [Meta.MetaItemType] = function(self, env) return pvm.once(Elab.ElabItemType(one_type_decl(self.t, env))) end,
        [Meta.MetaItemUseTypeDeclSlot] = function() error("seal_meta_to_elab: type-decl slot item survived sealing", 2) end,
        [Meta.MetaItemUseItemsSlot] = function() error("seal_meta_to_elab: items slot survived sealing", 2) end,
        [Meta.MetaItemUseModule] = function() error("seal_meta_to_elab: module splice must be expanded before sealing", 2) end,
        [Meta.MetaItemUseModuleSlot] = function() error("seal_meta_to_elab: module slot item survived sealing", 2) end,
    })

    local api = {}
    api.phases = {
        type = seal_type,
        intrinsic = seal_intrinsic,
        import_binding = seal_import_binding,
        binding = seal_binding,
        place = seal_place,
        index_base = seal_index_base,
        domain = seal_domain,
        loop = seal_loop,
        expr = seal_expr,
        stmt = seal_stmt,
        func = seal_func,
        extern_func = seal_extern_func,
        const = seal_const,
        static = seal_static,
        import = seal_import,
        type_decl = seal_type_decl,
        item = seal_item,
        module_name = seal_module_name,
    }

    function api.env(module_name, params)
        return Meta.MetaSealEnv(module_name or "", param_entries(params or {}))
    end

    function api.type(node, env) return one_type(node, env or api.env("")) end
    function api.expr(node, env) return one_expr(node, env or api.env("")) end
    function api.stmt(node, env) return one_stmt(node, env or api.env("")) end
    function api.place(node, env) return one_place(node, env or api.env("")) end
    function api.domain(node, env) return one_domain(node, env or api.env("")) end
    function api.loop(node, env) return one_loop(node, env or api.env("")) end
    function api.func(node, module_name)
        return one_func(node, api.env(module_name or "", {}))
    end
    function api.extern_func(node, module_name)
        return one_extern_func(node, api.env(module_name or "", {}))
    end
    function api.const(node, module_name)
        return one_const(node, api.env(module_name or "", {}))
    end
    function api.static(node, module_name)
        return one_static(node, api.env(module_name or "", {}))
    end
    function api.type_decl(node, module_name)
        return one_type_decl(node, api.env(module_name or "", {}))
    end
    function api.item(node, module_name)
        return one_item(node, api.env(module_name or "", {}))
    end
    function api.expr_frag(node, module_name)
        ensure_no_open_slots(node.open, "expr fragment")
        return one_expr(node.body, api.env(module_name or "", node.params))
    end
    function api.region_frag(node, module_name)
        ensure_no_open_slots(node.open, "region fragment")
        return seal_stmts(node.body, api.env(module_name or "", node.params))
    end
    function api.module(node, module_name)
        ensure_no_open_slots(node.open, "module")
        local sealed_name = one_module_name(node.name, module_name)
        local env = api.env(sealed_name, {})
        return Elab.ElabModule(sealed_name, map_array(node.items, function(item) return one_item(item, env) end))
    end

    return api
end

return M
