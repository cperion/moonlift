local pvm = require("pvm")

local M = {}

local function copy_array(src)
    local out = {}
    if src == nil then return out end
    for i = 1, #src do
        out[i] = src[i]
    end
    return out
end

function M.Define(T)
    local Meta = T.MoonliftMeta
    if Meta == nil then
        error("moonlift.meta: MoonliftMeta ASDL module is not defined", 2)
    end

    local api = {}
    api.Meta = Meta

    local function list(xs)
        return copy_array(xs)
    end

    local wrap_slot_phase = pvm.phase("meta_wrap_slot", {
        [Meta.MetaTypeSlot] = function(self) return pvm.once(Meta.MetaSlotType(self)) end,
        [Meta.MetaExprSlot] = function(self) return pvm.once(Meta.MetaSlotExpr(self)) end,
        [Meta.MetaPlaceSlot] = function(self) return pvm.once(Meta.MetaSlotPlace(self)) end,
        [Meta.MetaDomainSlot] = function(self) return pvm.once(Meta.MetaSlotDomain(self)) end,
        [Meta.MetaRegionSlot] = function(self) return pvm.once(Meta.MetaSlotRegion(self)) end,
        [Meta.MetaFuncSlot] = function(self) return pvm.once(Meta.MetaSlotFunc(self)) end,
        [Meta.MetaConstSlot] = function(self) return pvm.once(Meta.MetaSlotConst(self)) end,
        [Meta.MetaStaticSlot] = function(self) return pvm.once(Meta.MetaSlotStatic(self)) end,
        [Meta.MetaTypeDeclSlot] = function(self) return pvm.once(Meta.MetaSlotTypeDecl(self)) end,
        [Meta.MetaItemsSlot] = function(self) return pvm.once(Meta.MetaSlotItems(self)) end,
        [Meta.MetaModuleSlot] = function(self) return pvm.once(Meta.MetaSlotModule(self)) end,
        [Meta.MetaSlotType] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotExpr] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotPlace] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotDomain] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotRegion] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotFunc] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotConst] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotStatic] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotTypeDecl] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotItems] = function(self) return pvm.once(self) end,
        [Meta.MetaSlotModule] = function(self) return pvm.once(self) end,
    })

    local slot_binding_phase = pvm.phase("meta_slot_binding", {
        [Meta.MetaTypeSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotType(self), Meta.MetaSlotValueType(value))) end,
        [Meta.MetaExprSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotExpr(self), Meta.MetaSlotValueExpr(value))) end,
        [Meta.MetaPlaceSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotPlace(self), Meta.MetaSlotValuePlace(value))) end,
        [Meta.MetaDomainSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotDomain(self), Meta.MetaSlotValueDomain(value))) end,
        [Meta.MetaRegionSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotRegion(self), Meta.MetaSlotValueRegion(value))) end,
        [Meta.MetaFuncSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotFunc(self), Meta.MetaSlotValueFunc(value))) end,
        [Meta.MetaConstSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotConst(self), Meta.MetaSlotValueConst(value))) end,
        [Meta.MetaStaticSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotStatic(self), Meta.MetaSlotValueStatic(value))) end,
        [Meta.MetaTypeDeclSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotTypeDecl(self), Meta.MetaSlotValueTypeDecl(value))) end,
        [Meta.MetaItemsSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotItems(self), Meta.MetaSlotValueItems(value))) end,
        [Meta.MetaModuleSlot] = function(self, value) return pvm.once(Meta.MetaSlotBinding(Meta.MetaSlotModule(self), Meta.MetaSlotValueModule(value))) end,
        [Meta.MetaSlotType] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValueType(value))) end,
        [Meta.MetaSlotExpr] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValueExpr(value))) end,
        [Meta.MetaSlotPlace] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValuePlace(value))) end,
        [Meta.MetaSlotDomain] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValueDomain(value))) end,
        [Meta.MetaSlotRegion] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValueRegion(value))) end,
        [Meta.MetaSlotFunc] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValueFunc(value))) end,
        [Meta.MetaSlotConst] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValueConst(value))) end,
        [Meta.MetaSlotStatic] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValueStatic(value))) end,
        [Meta.MetaSlotTypeDecl] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValueTypeDecl(value))) end,
        [Meta.MetaSlotItems] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValueItems(value))) end,
        [Meta.MetaSlotModule] = function(self, value) return pvm.once(Meta.MetaSlotBinding(self, Meta.MetaSlotValueModule(value))) end,
    })

    api.wrap_slot = function(slot)
        return pvm.one(wrap_slot_phase(slot))
    end

    api.slot_binding = function(slot, value)
        return pvm.one(slot_binding_phase(slot, value))
    end

    api.fill_set = function(bindings)
        return Meta.MetaFillSet(list(bindings))
    end

    api.param_binding = function(param, value)
        return Meta.MetaParamBinding(param, value)
    end

    api.expand_env = function(fills, params, rebase_prefix)
        return Meta.MetaExpandEnv(fills or Meta.MetaFillSet({}), list(params), rebase_prefix or "")
    end

    api.rewrite = {
        set = function(rules) return Meta.MetaRewriteSet(list(rules)) end,
        type = function(from, to) return Meta.MetaRewriteType(from, to) end,
        binding = function(from, to) return Meta.MetaRewriteBinding(from, to) end,
        place = function(from, to) return Meta.MetaRewritePlace(from, to) end,
        domain = function(from, to) return Meta.MetaRewriteDomain(from, to) end,
        expr = function(from, to) return Meta.MetaRewriteExpr(from, to) end,
        stmt = function(from, to) return Meta.MetaRewriteStmt(from, list(to)) end,
        item = function(from, to) return Meta.MetaRewriteItem(from, list(to)) end,
    }

    api.sym = {
        type = function(key, name) return Meta.MetaTypeSym(key, name or key) end,
        func = function(key, name) return Meta.MetaFuncSym(key, name or key) end,
        extern = function(key, name, symbol) return Meta.MetaExternSym(key, name or key, symbol or name or key) end,
        const = function(key, name) return Meta.MetaConstSym(key, name or key) end,
        static = function(key, name) return Meta.MetaStaticSym(key, name or key) end,
    }

    api.type = {
        void = Meta.MetaTVoid,
        bool = Meta.MetaTBool,
        i8 = Meta.MetaTI8,
        i16 = Meta.MetaTI16,
        i32 = Meta.MetaTI32,
        i64 = Meta.MetaTI64,
        u8 = Meta.MetaTU8,
        u16 = Meta.MetaTU16,
        u32 = Meta.MetaTU32,
        u64 = Meta.MetaTU64,
        f32 = Meta.MetaTF32,
        f64 = Meta.MetaTF64,
        index = Meta.MetaTIndex,
        ptr = function(elem) return Meta.MetaTPtr(elem) end,
        array = function(count, elem) return Meta.MetaTArray(count, elem) end,
        slice = function(elem) return Meta.MetaTSlice(elem) end,
        view = function(elem) return Meta.MetaTView(elem) end,
        func = function(params, result) return Meta.MetaTFunc(list(params), result) end,
        named = function(module_name, type_name) return Meta.MetaTNamed(module_name, type_name) end,
        local_named = function(sym) return Meta.MetaTLocalNamed(sym) end,
        slot = function(slot) return Meta.MetaTSlot(slot) end,
    }

    api.slot = {
        type = function(key, pretty_name) return Meta.MetaTypeSlot(key, pretty_name or key) end,
        expr = function(key, ty, pretty_name) return Meta.MetaExprSlot(key, pretty_name or key, ty) end,
        place = function(key, ty, pretty_name) return Meta.MetaPlaceSlot(key, pretty_name or key, ty) end,
        domain = function(key, pretty_name) return Meta.MetaDomainSlot(key, pretty_name or key) end,
        region = function(key, pretty_name) return Meta.MetaRegionSlot(key, pretty_name or key) end,
        func = function(key, fn_ty, pretty_name) return Meta.MetaFuncSlot(key, pretty_name or key, fn_ty) end,
        const = function(key, ty, pretty_name) return Meta.MetaConstSlot(key, pretty_name or key, ty) end,
        static = function(key, ty, pretty_name) return Meta.MetaStaticSlot(key, pretty_name or key, ty) end,
        type_decl = function(key, pretty_name) return Meta.MetaTypeDeclSlot(key, pretty_name or key) end,
        items = function(key, pretty_name) return Meta.MetaItemsSlot(key, pretty_name or key) end,
        module = function(key, pretty_name) return Meta.MetaModuleSlot(key, pretty_name or key) end,
    }

    api.param = function(key, name, ty)
        if ty == nil then
            ty = name
            name = key
        end
        return Meta.MetaParam(key, name, ty)
    end

    api.import = {
        value = function(key, name, ty)
            if ty == nil then
                ty = name
                name = key
            end
            return Meta.MetaImportValue(key, name, ty)
        end,
        global_func = function(key, module_name, item_name, ty)
            return Meta.MetaImportGlobalFunc(key, module_name, item_name, ty)
        end,
        global_const = function(key, module_name, item_name, ty)
            return Meta.MetaImportGlobalConst(key, module_name, item_name, ty)
        end,
        global_static = function(key, module_name, item_name, ty)
            return Meta.MetaImportGlobalStatic(key, module_name, item_name, ty)
        end,
        extern = function(key, symbol, ty)
            return Meta.MetaImportExtern(key, symbol, ty)
        end,
        type = function(key, local_name, ty)
            return Meta.MetaTypeImport(key, local_name, ty)
        end,
        layout_named = function(module_name, type_name, fields)
            return Meta.MetaLayoutNamed(module_name, type_name, list(fields))
        end,
        layout_local = function(sym, fields)
            return Meta.MetaLayoutLocal(sym, list(fields))
        end,
    }

    api.field_type = function(name, ty) return Meta.MetaFieldType(name, ty) end
    api.field_init = function(name, value) return Meta.MetaFieldInit(name, value) end

    api.open_set = function(opts)
        opts = opts or {}
        return Meta.MetaOpenSet(
            list(opts.value_imports),
            list(opts.type_imports),
            list(opts.layouts),
            list(opts.slots)
        )
    end
    api.empty_open_set = function()
        return Meta.MetaOpenSet({}, {}, {}, {})
    end

    api.bind = {
        param = function(param) return Meta.MetaBindParam(param) end,
        local_value = function(id, name, ty) return Meta.MetaBindLocalValue(id, name, ty) end,
        local_cell = function(id, name, ty) return Meta.MetaBindLocalCell(id, name, ty) end,
        loop_carry = function(loop_id, port_id, name, ty) return Meta.MetaBindLoopCarry(loop_id, port_id, name, ty) end,
        loop_index = function(loop_id, name, ty) return Meta.MetaBindLoopIndex(loop_id, name, ty) end,
        global_func = function(module_name, item_name, ty) return Meta.MetaBindGlobalFunc(module_name, item_name, ty) end,
        global_const = function(module_name, item_name, ty) return Meta.MetaBindGlobalConst(module_name, item_name, ty) end,
        global_static = function(module_name, item_name, ty) return Meta.MetaBindGlobalStatic(module_name, item_name, ty) end,
        extern = function(symbol, ty) return Meta.MetaBindExtern(symbol, ty) end,
        import = function(import) return Meta.MetaBindImport(import) end,
        func_sym = function(sym, ty) return Meta.MetaBindFuncSym(sym, ty) end,
        extern_sym = function(sym, ty) return Meta.MetaBindExternSym(sym, ty) end,
        const_sym = function(sym, ty) return Meta.MetaBindConstSym(sym, ty) end,
        static_sym = function(sym, ty) return Meta.MetaBindStaticSym(sym, ty) end,
        func_slot = function(slot) return Meta.MetaBindFuncSlot(slot) end,
        const_slot = function(slot) return Meta.MetaBindConstSlot(slot) end,
        static_slot = function(slot) return Meta.MetaBindStaticSlot(slot) end,
    }

    api.place = {
        binding = function(binding) return Meta.MetaPlaceBinding(binding) end,
        deref = function(base, elem) return Meta.MetaPlaceDeref(base, elem) end,
        field = function(base, name, ty) return Meta.MetaPlaceField(base, name, ty) end,
        index = function(base, index, ty) return Meta.MetaPlaceIndex(base, index, ty) end,
        slot = function(slot) return Meta.MetaPlaceSlotValue(slot) end,
    }

    api.index_base = {
        place = function(base, elem) return Meta.MetaIndexBasePlace(base, elem) end,
        view = function(base, elem) return Meta.MetaIndexBaseView(base, elem) end,
    }

    api.domain = {
        range = function(stop) return Meta.MetaDomainRange(stop) end,
        range2 = function(start, stop) return Meta.MetaDomainRange2(start, stop) end,
        zip_eq = function(values) return Meta.MetaDomainZipEq(list(values)) end,
        value = function(value) return Meta.MetaDomainValue(value) end,
        slot = function(slot) return Meta.MetaDomainSlotValue(slot) end,
    }

    api.loop = {
        carry = function(port_id, name, ty, init) return Meta.MetaCarryPort(port_id, name, ty, init) end,
        index = function(name, ty) return Meta.MetaIndexPort(name, ty) end,
        update = function(port_id, value) return Meta.MetaCarryUpdate(port_id, value) end,
        while_stmt = function(loop_id, carries, cond, body, next_updates)
            return Meta.MetaWhileStmt(loop_id, list(carries), cond, list(body), list(next_updates))
        end,
        over_stmt = function(loop_id, index_port, domain, carries, body, next_updates)
            return Meta.MetaOverStmt(loop_id, index_port, domain, list(carries), list(body), list(next_updates))
        end,
        while_expr = function(loop_id, carries, cond, body, next_updates, exit, result)
            return Meta.MetaWhileExpr(loop_id, list(carries), cond, list(body), list(next_updates), exit, result)
        end,
        over_expr = function(loop_id, index_port, domain, carries, body, next_updates, exit, result)
            return Meta.MetaOverExpr(loop_id, index_port, domain, list(carries), list(body), list(next_updates), exit, result)
        end,
        exit_end_only = Meta.MetaExprEndOnly,
        exit_end_or_break_value = Meta.MetaExprEndOrBreakValue,
    }

    api.intrinsic = {
        popcount = Meta.MetaPopcount,
        clz = Meta.MetaClz,
        ctz = Meta.MetaCtz,
        rotl = Meta.MetaRotl,
        rotr = Meta.MetaRotr,
        bswap = Meta.MetaBswap,
        fma = Meta.MetaFma,
        sqrt = Meta.MetaSqrt,
        abs = Meta.MetaAbs,
        floor = Meta.MetaFloor,
        ceil = Meta.MetaCeil,
        trunc_float = Meta.MetaTruncFloat,
        round = Meta.MetaRound,
        trap = Meta.MetaTrap,
        assume = Meta.MetaAssume,
    }

    api.expr = {
        int = function(raw, ty) return Meta.MetaInt(tostring(raw), ty) end,
        float = function(raw, ty) return Meta.MetaFloat(tostring(raw), ty) end,
        bool = function(value, ty) return Meta.MetaBool(value, ty) end,
        nil_ = function(ty) return Meta.MetaNil(ty) end,
        binding = function(binding) return Meta.MetaBindingExpr(binding) end,
        neg = function(ty, value) return Meta.MetaExprNeg(ty, value) end,
        not_ = function(ty, value) return Meta.MetaExprNot(ty, value) end,
        bnot = function(ty, value) return Meta.MetaExprBNot(ty, value) end,
        addr_of = function(place, ty) return Meta.MetaExprAddrOf(place, ty) end,
        deref = function(ty, value) return Meta.MetaExprDeref(ty, value) end,
        add = function(ty, lhs, rhs) return Meta.MetaExprAdd(ty, lhs, rhs) end,
        sub = function(ty, lhs, rhs) return Meta.MetaExprSub(ty, lhs, rhs) end,
        mul = function(ty, lhs, rhs) return Meta.MetaExprMul(ty, lhs, rhs) end,
        div = function(ty, lhs, rhs) return Meta.MetaExprDiv(ty, lhs, rhs) end,
        rem = function(ty, lhs, rhs) return Meta.MetaExprRem(ty, lhs, rhs) end,
        eq = function(ty, lhs, rhs) return Meta.MetaExprEq(ty, lhs, rhs) end,
        ne = function(ty, lhs, rhs) return Meta.MetaExprNe(ty, lhs, rhs) end,
        lt = function(ty, lhs, rhs) return Meta.MetaExprLt(ty, lhs, rhs) end,
        le = function(ty, lhs, rhs) return Meta.MetaExprLe(ty, lhs, rhs) end,
        gt = function(ty, lhs, rhs) return Meta.MetaExprGt(ty, lhs, rhs) end,
        ge = function(ty, lhs, rhs) return Meta.MetaExprGe(ty, lhs, rhs) end,
        and_ = function(ty, lhs, rhs) return Meta.MetaExprAnd(ty, lhs, rhs) end,
        or_ = function(ty, lhs, rhs) return Meta.MetaExprOr(ty, lhs, rhs) end,
        bit_and = function(ty, lhs, rhs) return Meta.MetaExprBitAnd(ty, lhs, rhs) end,
        bit_or = function(ty, lhs, rhs) return Meta.MetaExprBitOr(ty, lhs, rhs) end,
        bit_xor = function(ty, lhs, rhs) return Meta.MetaExprBitXor(ty, lhs, rhs) end,
        shl = function(ty, lhs, rhs) return Meta.MetaExprShl(ty, lhs, rhs) end,
        lshr = function(ty, lhs, rhs) return Meta.MetaExprLShr(ty, lhs, rhs) end,
        ashr = function(ty, lhs, rhs) return Meta.MetaExprAShr(ty, lhs, rhs) end,
        cast_to = function(ty, value) return Meta.MetaExprCastTo(ty, value) end,
        trunc_to = function(ty, value) return Meta.MetaExprTruncTo(ty, value) end,
        zext_to = function(ty, value) return Meta.MetaExprZExtTo(ty, value) end,
        sext_to = function(ty, value) return Meta.MetaExprSExtTo(ty, value) end,
        bitcast_to = function(ty, value) return Meta.MetaExprBitcastTo(ty, value) end,
        satcast_to = function(ty, value) return Meta.MetaExprSatCastTo(ty, value) end,
        intrinsic = function(op, ty, args) return Meta.MetaExprIntrinsicCall(op, ty, list(args)) end,
        call = function(callee, ty, args) return Meta.MetaCall(callee, ty, list(args)) end,
        field = function(base, name, ty) return Meta.MetaField(base, name, ty) end,
        index = function(base, index, ty) return Meta.MetaIndex(base, index, ty) end,
        agg = function(ty, fields) return Meta.MetaAgg(ty, list(fields)) end,
        array_lit = function(ty, elems) return Meta.MetaArrayLit(ty, list(elems)) end,
        if_ = function(cond, then_expr, else_expr, ty) return Meta.MetaIfExpr(cond, then_expr, else_expr, ty) end,
        select = function(cond, then_expr, else_expr, ty) return Meta.MetaSelectExpr(cond, then_expr, else_expr, ty) end,
        switch = function(value, arms, default_expr, ty) return Meta.MetaSwitchExpr(value, list(arms), default_expr, ty) end,
        loop = function(loop, ty) return Meta.MetaExprLoop(loop, ty) end,
        block = function(stmts, result, ty) return Meta.MetaBlockExpr(list(stmts), result, ty) end,
        view = function(base, ty) return Meta.MetaExprView(base, ty) end,
        view_window = function(base, start, len, ty) return Meta.MetaExprViewWindow(base, start, len, ty) end,
        view_from_ptr = function(ptr, len, ty) return Meta.MetaExprViewFromPtr(ptr, len, ty) end,
        view_from_ptr_strided = function(ptr, len, stride, ty) return Meta.MetaExprViewFromPtrStrided(ptr, len, stride, ty) end,
        view_strided = function(base, stride, ty) return Meta.MetaExprViewStrided(base, stride, ty) end,
        view_interleaved = function(base, stride, lane, ty) return Meta.MetaExprViewInterleaved(base, stride, lane, ty) end,
        slot = function(slot, ty) return Meta.MetaExprSlotValue(slot, ty or slot.ty) end,
        use = function(use_id, frag, args, fills, ty) return Meta.MetaExprUseExprFrag(use_id, frag, list(args), list(fills), ty or frag.result) end,
    }

    api.switch_stmt_arm = function(key, body) return Meta.MetaSwitchStmtArm(key, list(body)) end
    api.switch_expr_arm = function(key, body, result) return Meta.MetaSwitchExprArm(key, list(body), result) end

    api.stmt = {
        let = function(id, name, ty, init) return Meta.MetaLet(id, name, ty, init) end,
        var = function(id, name, ty, init) return Meta.MetaVar(id, name, ty, init) end,
        set = function(place, value) return Meta.MetaSet(place, value) end,
        expr = function(expr) return Meta.MetaExprStmt(expr) end,
        assert_ = function(cond) return Meta.MetaAssert(cond) end,
        if_ = function(cond, then_body, else_body) return Meta.MetaIf(cond, list(then_body), list(else_body)) end,
        switch = function(value, arms, default_body) return Meta.MetaSwitch(value, list(arms), list(default_body)) end,
        return_void = Meta.MetaReturnVoid,
        return_value = function(value) return Meta.MetaReturnValue(value) end,
        break_ = Meta.MetaBreak,
        break_value = function(value) return Meta.MetaBreakValue(value) end,
        continue_ = Meta.MetaContinue,
        loop = function(loop) return Meta.MetaStmtLoop(loop) end,
        use_region_slot = function(slot) return Meta.MetaStmtUseRegionSlot(slot) end,
        use_region_frag = function(use_id, frag, args, fills) return Meta.MetaStmtUseRegionFrag(use_id, frag, list(args), list(fills)) end,
    }

    api.expr_frag = function(params, open, body, result)
        return Meta.MetaExprFrag(list(params), open or api.empty_open_set(), body, result)
    end

    api.region_frag = function(params, open, body)
        return Meta.MetaRegionFrag(list(params), open or api.empty_open_set(), list(body))
    end

    api.func = {
        local_ = function(sym, params, open, result, body)
            return Meta.MetaFuncLocal(sym, list(params), open or api.empty_open_set(), result, list(body))
        end,
        export = function(sym, params, open, result, body)
            return Meta.MetaFuncExport(sym, list(params), open or api.empty_open_set(), result, list(body))
        end,
    }

    api.extern_func = function(sym, params, result)
        return Meta.MetaExternFunc(sym, list(params), result)
    end

    api.const = function(sym, open, ty, value)
        return Meta.MetaConst(sym, open or api.empty_open_set(), ty, value)
    end

    api.static = function(sym, open, ty, value)
        return Meta.MetaStatic(sym, open or api.empty_open_set(), ty, value)
    end

    api.import_item = function(module_name)
        return Meta.MetaImport(module_name)
    end

    api.type_decl = {
        struct = function(sym, fields) return Meta.MetaStruct(sym, list(fields)) end,
        union = function(sym, fields) return Meta.MetaUnion(sym, list(fields)) end,
    }

    api.item = {
        func = function(func) return Meta.MetaItemFunc(func) end,
        extern = function(func) return Meta.MetaItemExtern(func) end,
        const = function(c) return Meta.MetaItemConst(c) end,
        static = function(s) return Meta.MetaItemStatic(s) end,
        import = function(imp) return Meta.MetaItemImport(imp) end,
        type = function(t) return Meta.MetaItemType(t) end,
        type_decl_slot = function(slot) return Meta.MetaItemUseTypeDeclSlot(slot) end,
        items_slot = function(slot) return Meta.MetaItemUseItemsSlot(slot) end,
        module = function(use_id, module, fills) return Meta.MetaItemUseModule(use_id, module, list(fills)) end,
        module_slot = function(use_id, slot, fills) return Meta.MetaItemUseModuleSlot(use_id, slot, list(fills)) end,
    }

    api.module_name = {
        open = Meta.MetaModuleNameOpen,
        fixed = function(name) return Meta.MetaModuleNameFixed(name) end,
    }

    api.module = function(name, open, items)
        return Meta.MetaModule(name or Meta.MetaModuleNameOpen, open or api.empty_open_set(), list(items))
    end

    local function install_slot_methods(cls, wrap_ctor, value_ctor)
        rawset(cls, "as_slot", function(self) return wrap_ctor(self) end)
        rawset(cls, "slot_binding", function(self, value) return Meta.MetaSlotBinding(wrap_ctor(self), value_ctor(value)) end)
    end

    install_slot_methods(Meta.MetaTypeSlot, Meta.MetaSlotType, Meta.MetaSlotValueType)
    install_slot_methods(Meta.MetaExprSlot, Meta.MetaSlotExpr, Meta.MetaSlotValueExpr)
    install_slot_methods(Meta.MetaPlaceSlot, Meta.MetaSlotPlace, Meta.MetaSlotValuePlace)
    install_slot_methods(Meta.MetaDomainSlot, Meta.MetaSlotDomain, Meta.MetaSlotValueDomain)
    install_slot_methods(Meta.MetaRegionSlot, Meta.MetaSlotRegion, Meta.MetaSlotValueRegion)
    install_slot_methods(Meta.MetaFuncSlot, Meta.MetaSlotFunc, Meta.MetaSlotValueFunc)
    install_slot_methods(Meta.MetaConstSlot, Meta.MetaSlotConst, Meta.MetaSlotValueConst)
    install_slot_methods(Meta.MetaStaticSlot, Meta.MetaSlotStatic, Meta.MetaSlotValueStatic)
    install_slot_methods(Meta.MetaTypeDeclSlot, Meta.MetaSlotTypeDecl, Meta.MetaSlotValueTypeDecl)
    install_slot_methods(Meta.MetaItemsSlot, Meta.MetaSlotItems, Meta.MetaSlotValueItems)
    install_slot_methods(Meta.MetaModuleSlot, Meta.MetaSlotModule, Meta.MetaSlotValueModule)

    rawset(Meta.MetaTypeSlot, "as_type", function(self) return Meta.MetaTSlot(self) end)
    rawset(Meta.MetaExprSlot, "as_expr", function(self, ty) return Meta.MetaExprSlotValue(self, ty or self.ty) end)
    rawset(Meta.MetaPlaceSlot, "as_place", function(self) return Meta.MetaPlaceSlotValue(self) end)
    rawset(Meta.MetaDomainSlot, "as_domain", function(self) return Meta.MetaDomainSlotValue(self) end)
    rawset(Meta.MetaRegionSlot, "as_stmt", function(self) return Meta.MetaStmtUseRegionSlot(self) end)
    rawset(Meta.MetaFuncSlot, "as_binding", function(self) return Meta.MetaBindFuncSlot(self) end)
    rawset(Meta.MetaConstSlot, "as_binding", function(self) return Meta.MetaBindConstSlot(self) end)
    rawset(Meta.MetaStaticSlot, "as_binding", function(self) return Meta.MetaBindStaticSlot(self) end)

    rawset(Meta.MetaExprFrag, "use", function(self, use_id, args, fills, ty)
        return Meta.MetaExprUseExprFrag(use_id, self, list(args), list(fills), ty or self.result)
    end)
    rawset(Meta.MetaRegionFrag, "use", function(self, use_id, args, fills)
        return Meta.MetaStmtUseRegionFrag(use_id, self, list(args), list(fills))
    end)

    rawset(Meta.MetaTypeSym, "as_type", function(self) return Meta.MetaTLocalNamed(self) end)
    rawset(Meta.MetaFuncSym, "as_binding", function(self, ty) return Meta.MetaBindFuncSym(self, ty) end)
    rawset(Meta.MetaExternSym, "as_binding", function(self, ty) return Meta.MetaBindExternSym(self, ty) end)
    rawset(Meta.MetaConstSym, "as_binding", function(self, ty) return Meta.MetaBindConstSym(self, ty) end)
    rawset(Meta.MetaStaticSym, "as_binding", function(self, ty) return Meta.MetaBindStaticSym(self, ty) end)

    return api
end

return M
