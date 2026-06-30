local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.c_validate ~= nil then return T._lalin_api_cache.c_validate end

    local C = T.LalinC
    local Helpers = require("lalin.c_helpers")(T)
    local Coverage = require("lalin.c_coverage")

    local function is_c_name(s)
        return type(s) == "string" and s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
    end

    local function align_ok(n)
        return type(n) == "number" and n >= 1 and n % 1 == 0 and (n == 1 or n % 2 == 0) and (function(x) while x > 1 do if x % 2 ~= 0 then return false end; x = x / 2 end; return true end)(n)
    end

    local function add_issue(issues, collector, issue)
        issues[#issues + 1] = issue
        if collector and collector.emit then pcall(function() collector:emit(issue, "c") end) end
    end

    local function type_eq(a, b, seen)
        if a == b then return true end
        local ac, bc = asdl.classof(a), asdl.classof(b)
        if ac ~= bc then
            if ac == C.CBackendArray and bc == C.CBackendDataPtr then return b.pointee == nil or type_eq(a.elem, b.pointee, seen) end
            if ac == C.CBackendDataPtr and bc == C.CBackendArray then return a.pointee == nil or type_eq(a.pointee, b.elem, seen) end
            return false
        end
        if ac == C.CBackendDataPtr then
            -- CBackendDataPtr(nil) represents an untyped C void* at ABI/helper
            -- boundaries and is compatible with any typed data pointer.
            if a.pointee == nil or b.pointee == nil then return true end
        end
        if ac == nil then return a == b end
        seen = seen or {}
        local key = tostring(a) .. "|" .. tostring(b)
        if seen[key] then return true end
        seen[key] = true
        local fields = asdl.fields(ac) or {}
        for i = 1, #fields do
            local name = fields[i].name
            local av, bv = a[name], b[name]
            if type(av) == "table" and asdl.classof(av) == nil then
                if type(bv) ~= "table" or #av ~= #bv then return false end
                for j = 1, #av do if not type_eq(av[j], bv[j], seen) then return false end end
            elseif type(av) == "table" and asdl.classof(av) ~= nil then
                if not type_eq(av, bv, seen) then return false end
            else
                if av ~= bv then return false end
            end
        end
        return true
    end

    local function index_by(items, key_fn, dup_issue, issues, collector)
        local by = {}
        for i = 1, #(items or {}) do
            local item = items[i]
            local key, ref = key_fn(item)
            if by[key] ~= nil then add_issue(issues, collector, dup_issue(ref), "c") else by[key] = item end
        end
        return by
    end

    local function scalar_size(s)
        if s == T.LalinCore.ScalarBool or s == T.LalinCore.ScalarI8 or s == T.LalinCore.ScalarU8 then return 1 end
        if s == T.LalinCore.ScalarI16 or s == T.LalinCore.ScalarU16 then return 2 end
        if s == T.LalinCore.ScalarI32 or s == T.LalinCore.ScalarU32 or s == T.LalinCore.ScalarF32 then return 4 end
        if s == T.LalinCore.ScalarI64 or s == T.LalinCore.ScalarU64 or s == T.LalinCore.ScalarF64 then return 8 end
        if s == T.LalinCore.ScalarIndex or s == T.LalinCore.ScalarRawPtr then return 8 end
        return 0
    end

    local function type_size(ty)
        local cls = asdl.classof(ty)
        if ty == C.CBackendBool8 or cls == C.CBackendBool8 then return 1 end
        if ty == C.CBackendIndex or cls == C.CBackendIndex then return 8 end
        if cls == C.CBackendScalar then return scalar_size(ty.scalar) end
        if cls == C.CBackendDataPtr or cls == C.CBackendCodePtr or cls == C.CBackendImportedCodePtr then return 8 end
        return 0
    end

    local function data_init_size(init)
        local cls = asdl.classof(init)
        if cls == C.CBackendDataZero then return init.size end
        if cls == C.CBackendDataBytes then return #init.bytes end
        if cls == C.CBackendDataScalar then return type_size(init.ty) end
        if cls == C.CBackendDataReloc then return 8 end
        return 0
    end

    local function validate_input(input, collector)
        local unit = input.unit or input
        local issues = {}
        for i = 1, #(input.abi_issues or {}) do add_issue(issues, collector, input.abi_issues[i]) end
        local storage_by_func = {}
        for i = 1, #(input.storage or {}) do
            local rec = input.storage[i]
            local by_local = storage_by_func[rec.func.text] or {}
            storage_by_func[rec.func.text] = by_local
            for j = 1, #rec.storage do by_local[rec.storage[j].id.text] = rec.storage[j] end
        end
        local valid_coverage_status = Coverage.statuses()
        for sum_name, table_ in pairs(Coverage.all_tables()) do
            for variant, c in pairs(table_) do
                if not valid_coverage_status[c.status] then
                    add_issue(issues, collector, C.CBackendIssueCoverageMissing(sum_name, variant))
                end
            end
        end
        local sigs = index_by(unit.sigs, function(s) return s.id.text, s.id end, function(id) return C.CBackendIssueDuplicateSig(id) end, issues, collector)
        local globals = index_by(unit.globals, function(g) return g.id.text, g.id end, function(id) return C.CBackendIssueDuplicateGlobal(id) end, issues, collector)
        local externs = index_by(unit.externs, function(e) return e.name.text, e.name end, function(n) return C.CBackendIssueDuplicateExtern(n) end, issues, collector)
        local helpers = index_by(unit.helpers, function(h) return h.id.text, h.id end, function(id) return C.CBackendIssueDuplicateHelper(id) end, issues, collector)
        local funcs = index_by(unit.funcs, function(f) return f.name.text, f.name end, function(n) return C.CBackendIssueDuplicateFunc(n) end, issues, collector)

        local c_names = {}
        local function check_c_name(site, name)
            if not is_c_name(name.text) then add_issue(issues, collector, C.CBackendIssueInvalidCName(site, name)) end
            local key = site .. ":" .. name.text
            if c_names[key] then add_issue(issues, collector, C.CBackendIssueDuplicateCName(site, name)) end
            c_names[key] = true
        end
        for i = 1, #unit.funcs do check_c_name("func", unit.funcs[i].name) end
        for i = 1, #unit.externs do check_c_name("extern", unit.externs[i].name) end
        for i = 1, #unit.globals do check_c_name("global", unit.globals[i].name) end

        for i = 1, #unit.globals do
            local g = unit.globals[i]
            if not align_ok(g.align) then add_issue(issues, collector, C.CBackendIssueInvalidAlignment("global:" .. g.id.text, g.align)) end
            for j = 1, #g.inits do
                local init = g.inits[j]
                local off = init.offset or 0
                local sz = data_init_size(init)
                if off < 0 or off + sz > g.size then add_issue(issues, collector, C.CBackendIssueDataInitOutOfBounds(g.id, off, sz, g.size)) end
                if asdl.classof(init) == C.CBackendDataReloc then
                    local tcls = asdl.classof(init.target)
                    if tcls == C.CBackendRelocGlobal and globals[init.target.global.text] == nil then
                        add_issue(issues, collector, C.CBackendIssueMissingGlobal(init.target.global))
                    elseif tcls == C.CBackendRelocFunc and funcs[init.target.func.text] == nil then
                        add_issue(issues, collector, C.CBackendIssueMissingFunc(init.target.func))
                    elseif tcls == C.CBackendRelocExtern and externs[init.target["extern"].text] == nil then
                        add_issue(issues, collector, C.CBackendIssueMissingExtern(init.target["extern"]))
                    end
                end
            end
        end

        for i = 1, #unit.externs do if sigs[unit.externs[i].sig.text] == nil then add_issue(issues, collector, C.CBackendIssueMissingSig(unit.externs[i].sig)) end end
        for i = 1, #unit.helpers do
            local ok, sig_or_err = pcall(Helpers.helper_signature, unit.helpers[i])
            if not ok or not sig_or_err then add_issue(issues, collector, C.CBackendIssueHelperMismatch(unit.helpers[i].id, tostring(sig_or_err))) end
        end

        local function func_sig(func)
            return sigs[func.sig.text]
        end

        local function func_blocks(func)
            local body = assert(func.body, "CBackendFunc requires body")
            local cls = asdl.classof(body)
            if cls == C.CBackendBodyBlocks or cls == C.CBackendBodyMixed then return body.blocks end
            if cls == C.CBackendBodyExec then return {} end
            error("c_validate: unknown CBackendFunc body", 2)
        end

        local function atom_type(atom, locals)
            local cls = asdl.classof(atom)
            if cls == C.CBackendAtomLocal then return locals[atom.local_id.text] end
            if cls == C.CBackendAtomGlobal then local g = globals[atom.global.text]; return g and g.ty or nil end
            if cls == C.CBackendAtomLiteral or cls == C.CBackendAtomNull then return atom.ty end
            return nil
        end

        local place_type

        local function check_atom(atom, func, locals, initialized)
            local cls = asdl.classof(atom)
            if cls == C.CBackendAtomLocal then
                if locals[atom.local_id.text] == nil then add_issue(issues, collector, C.CBackendIssueMissingLocal(func.name, atom.local_id))
                elseif initialized ~= nil and initialized[atom.local_id.text] == false then add_issue(issues, collector, C.CBackendIssueUninitializedLocal(func.name, atom.local_id)) end
            elseif cls == C.CBackendAtomGlobal and globals[atom.global.text] == nil then add_issue(issues, collector, C.CBackendIssueMissingGlobal(atom.global)) end
        end

        local function rvalue_type(rv, func, locals, initialized)
            local cls = asdl.classof(rv)
            if cls == C.CBackendRAtom then check_atom(rv.atom, func, locals, initialized); return atom_type(rv.atom, locals)
            elseif cls == C.CBackendRCompare then check_atom(rv.lhs, func, locals, initialized); check_atom(rv.rhs, func, locals, initialized); return C.CBackendBool8
            elseif cls == C.CBackendRCast then check_atom(rv.value, func, locals, initialized); return rv.to
            elseif cls == C.CBackendRSelect then check_atom(rv.cond, func, locals, initialized); check_atom(rv.then_value, func, locals, initialized); check_atom(rv.else_value, func, locals, initialized); return rv.ty
            elseif cls == C.CBackendRFuncAddr then if funcs[rv.func.text] == nil then add_issue(issues, collector, C.CBackendIssueMissingFunc(rv.func)) end; return C.CBackendCodePtr(rv.sig)
            elseif cls == C.CBackendRExternAddr then if externs[rv["extern"].text] == nil then add_issue(issues, collector, C.CBackendIssueMissingExtern(rv["extern"])) end; return C.CBackendCodePtr(rv.sig)
            elseif cls == C.CBackendRPtrOffset then check_atom(rv.base, func, locals, initialized); check_atom(rv.index, func, locals, initialized); return C.CBackendDataPtr(nil)
            elseif cls == C.CBackendRAddrOfPlace then return C.CBackendDataPtr(place_type(rv.place, func, locals)) end
            return nil
        end

        local function check_call_sig(site, sig, args, dst, target_name, locals)
            if sig == nil then return end
            if #args ~= #sig.params then add_issue(issues, collector, C.CBackendIssueCallArgCount(site, sig.id, #sig.params, #args)) end
            local n = math.min(#args, #sig.params)
            for i = 1, n do
                local aty = atom_type(args[i], locals)
                if aty and not type_eq(aty, sig.params[i]) then add_issue(issues, collector, C.CBackendIssueCallArgType(site, sig.id, i, sig.params[i], aty)) end
            end
            if dst ~= nil then
                local dty = locals[dst.text]
                if dty and not type_eq(dty, sig.result) then add_issue(issues, collector, C.CBackendIssueCallResultType(site, sig.id, sig.result, dty)) end
            elseif sig.result ~= C.CBackendVoid and asdl.classof(sig.result) ~= C.CBackendVoid then
                add_issue(issues, collector, C.CBackendIssueCallResultType(site, sig.id, sig.result, C.CBackendVoid))
            end
        end

        local function check_transfer(func, labels, locals, dest, args)
            local block = labels[dest.text]
            if not block then add_issue(issues, collector, C.CBackendIssueMissingLabel(func.name, dest)); return end
            if #args ~= #block.params then add_issue(issues, collector, C.CBackendIssueBlockArgCount(func.name, dest, #block.params, #args)) end
            local n = math.min(#args, #block.params)
            for i = 1, n do
                local aty = atom_type(args[i], locals)
                check_atom(args[i], func, locals)
                if aty and not type_eq(aty, block.params[i].ty) then add_issue(issues, collector, C.CBackendIssueBlockArgType(func.name, dest, i, block.params[i].ty, aty)) end
            end
        end

        local function check_exec_site(func, sig, locals, initialized, site)
            for a = 1, #(site.args or {}) do
                local arg = site.args[a]
                check_atom(arg.atom, func, locals, initialized)
                local aty = atom_type(arg.atom, locals)
                if aty ~= nil and not type_eq(aty, arg.ty) then
                    add_issue(issues, collector, C.CBackendIssueCallArgType("exec:" .. tostring(arg.name), sig and sig.id or C.CBackendFuncSigId("<exec>"), a, arg.ty, aty))
                end
            end
            local rcls = asdl.classof(site.result)
            if rcls == C.CBackendExecResultLocal then
                local dty = locals[site.result.dst.text]
                if dty == nil then
                    add_issue(issues, collector, C.CBackendIssueMissingLocal(func.name, site.result.dst))
                else
                    if not type_eq(dty, site.result.ty) then
                        add_issue(issues, collector, C.CBackendIssueCallResultType("exec:" .. func.name.text, sig and sig.id or C.CBackendFuncSigId("<exec>"), site.result.ty, dty))
                    end
                    if sig ~= nil and not type_eq(sig.result, dty) then
                        add_issue(issues, collector, C.CBackendIssueCallResultType("exec-return:" .. func.name.text, sig.id, sig.result, dty))
                    end
                end
                initialized[site.result.dst.text] = true
            elseif sig ~= nil and not type_eq(sig.result, C.CBackendVoid) then
                add_issue(issues, collector, C.CBackendIssueCallResultType("exec-return:" .. func.name.text, sig.id, sig.result, C.CBackendVoid))
            end
        end

        local function check_access(site, access)
            if access and not align_ok(access.align) then add_issue(issues, collector, C.CBackendIssueInvalidAlignment(site, access.align)) end
        end

        place_type = function(p, func, locals)
            local cls = asdl.classof(p)
            if cls == C.CBackendPlaceLocal then
                if locals[p.local_id.text] == nil then add_issue(issues, collector, C.CBackendIssueMissingLocal(func.name, p.local_id)) end
                return p.ty
            elseif cls == C.CBackendPlaceGlobal then
                if globals[p.global.text] == nil then add_issue(issues, collector, C.CBackendIssueMissingGlobal(p.global)) end
                return p.ty
            elseif cls == C.CBackendPlaceDeref then
                check_atom(p.addr, func, locals)
                return p.ty
            elseif cls == C.CBackendPlaceField then
                place_type(p.base, func, locals)
                if p.align ~= nil and not align_ok(p.align) then add_issue(issues, collector, C.CBackendIssueInvalidAlignment("place-field", p.align)) end
                return p.ty
            elseif cls == C.CBackendPlaceIndex then
                place_type(p.base, func, locals); check_atom(p.index, func, locals)
                return p.ty
            elseif cls == C.CBackendPlaceBytes then
                check_atom(p.base, func, locals)
                if not align_ok(p.align) then add_issue(issues, collector, C.CBackendIssueInvalidAlignment("place-bytes", p.align)) end
                return p.ty
            end
            return nil
        end

        local function helper_requires_c11_atomic(kind)
            local cls = asdl.classof(kind)
            return cls == C.CBackendHelperAtomicLoad or cls == C.CBackendHelperAtomicStore or cls == C.CBackendHelperAtomicRmw or cls == C.CBackendHelperAtomicCas or cls == C.CBackendHelperAtomicFence
        end

        local function target_has_c11_atomics(target)
            if target == nil then return false end
            local dcls = asdl.classof(target.dialect)
            return target.dialect == C.CBackendC11 or target.dialect == C.CBackendGnuC or target.dialect == C.CBackendClangC
                or dcls == C.CBackendC11 or dcls == C.CBackendGnuC or dcls == C.CBackendClangC
        end

        for i = 1, #unit.types do
            local td = unit.types[i]
            local cls = asdl.classof(td)
            if (cls == C.CBackendStructDecl or cls == C.CBackendUnionDecl) and (td.size == nil or td.align == nil) then
                add_issue(issues, collector, C.CBackendIssueLayoutAssertionMissing(td.id))
            end
            if (cls == C.CBackendStructDecl or cls == C.CBackendUnionDecl) and td.align ~= nil and not align_ok(td.align) then
                add_issue(issues, collector, C.CBackendIssueInvalidAlignment("type:" .. td.id.spelling, td.align))
            end
        end

        for i = 1, #unit.helpers do
            local spec = unit.helpers[i].spec
            local kcls = asdl.classof(spec)
            if helper_requires_c11_atomic(spec) and not target_has_c11_atomics(unit.target) then
                add_issue(issues, collector, C.CBackendIssueInvalidTargetFeature(C.CBackendFeatureC11Atomics, "atomic helper requires C11 atomics or runtime provider"))
            elseif kcls == C.CBackendHelperRequireFeature then
                add_issue(issues, collector, C.CBackendIssueInvalidTargetFeature(kind.feature, kind.reason))
            end
        end

        for i = 1, #unit.funcs do
            local func = unit.funcs[i]
            local sig = func_sig(func)
            if sig == nil then add_issue(issues, collector, C.CBackendIssueMissingSig(func.sig)) end
            local locals = {}
            local labels = {}
            for j = 1, #func.params do
                local p = func.params[j]
                if locals[p.id.text] then add_issue(issues, collector, C.CBackendIssueDuplicateLocal(func.name, p.id)) end
                locals[p.id.text] = p.ty
                if sig and sig.params[j] and not type_eq(sig.params[j], p.ty) then add_issue(issues, collector, C.CBackendIssueFuncSigMismatch(func.name, sig.params[j], p.ty)) end
            end
            if sig and #func.params ~= #sig.params then add_issue(issues, collector, C.CBackendIssueCallArgCount("func:" .. func.name.text, sig.id, #sig.params, #func.params)) end
            for j = 1, #func.locals do
                local l = func.locals[j]
                if locals[l.id.text] then add_issue(issues, collector, C.CBackendIssueDuplicateLocal(func.name, l.id)) end
                locals[l.id.text] = l.ty
            end
            local body_cls = asdl.classof(func.body)
            if body_cls == C.CBackendBodyExec then
                local initialized = {}
                for _, p in ipairs(func.params) do initialized[p.id.text] = true end
                for id, rec in pairs(storage_by_func[func.name.text] or {}) do
                    local icls = asdl.classof(rec.init_state)
                    initialized[id] = not (rec.init_state == C.CBackendLocalUninitialized or icls == C.CBackendLocalUninitialized)
                end
                check_exec_site(func, sig, locals, initialized, func.body.fragment)
            elseif body_cls == C.CBackendBodyMixed then
                local initialized = {}
                for _, p in ipairs(func.params) do initialized[p.id.text] = true end
                for id, rec in pairs(storage_by_func[func.name.text] or {}) do
                    local icls = asdl.classof(rec.init_state)
                    initialized[id] = not (rec.init_state == C.CBackendLocalUninitialized or icls == C.CBackendLocalUninitialized)
                end
                for _, site in ipairs(func.body.fragments or {}) do
                    check_exec_site(func, nil, locals, initialized, site)
                end
            end
            local blocks = func_blocks(func)
            for j = 1, #blocks do
                local b = blocks[j]
                if labels[b.label.text] then add_issue(issues, collector, C.CBackendIssueDuplicateLabel(func.name, b.label)) end
                labels[b.label.text] = b
                for k = 1, #b.params do locals[b.params[k].local_id.text] = b.params[k].ty end
            end
            local storage = storage_by_func[func.name.text] or {}
            for _, rec in pairs(storage) do
                local rcls = asdl.classof(rec.residence)
                if rec.address_taken and (rec.residence == C.CBackendResidenceValue or rcls == C.CBackendResidenceValue) then
                    add_issue(issues, collector, C.CBackendIssueUnmaterializedAddressTakenValue(func.name, rec.id))
                end
            end
            for j = 1, #blocks do
                local b = blocks[j]
                local initialized = {}
                for _, p in ipairs(func.params) do initialized[p.id.text] = true end
                for _, bp in ipairs(b.params) do initialized[bp.local_id.text] = true end
                for id, rec in pairs(storage) do
                    local icls = asdl.classof(rec.init_state)
                    initialized[id] = not (rec.init_state == C.CBackendLocalUninitialized or icls == C.CBackendLocalUninitialized)
                end
                local function mark_init(id) if id ~= nil then initialized[id.text] = true end end
                for k = 1, #b.stmts do
                    local s = b.stmts[k]
                    local cls = asdl.classof(s)
                    if cls == C.CBackendAssign then
                        if locals[s.dst.text] == nil then add_issue(issues, collector, C.CBackendIssueMissingLocal(func.name, s.dst)) end
                        local rty = rvalue_type(s.rhs, func, locals, initialized)
                        if rty and locals[s.dst.text] and not type_eq(rty, locals[s.dst.text]) then add_issue(issues, collector, C.CBackendIssueCallResultType("assign:" .. s.dst.text, C.CBackendFuncSigId("<assign>"), locals[s.dst.text], rty)) end
                        mark_init(s.dst)
                    elseif cls == C.CBackendHelperCall then
                        local helper = helpers[s.helper.text]
                        if helper == nil then add_issue(issues, collector, C.CBackendIssueMissingHelper(s.helper)) end
                        local actual = {}
                        for a = 1, #s.args do check_atom(s.args[a], func, locals, initialized); actual[a] = atom_type(s.args[a], locals) or C.CBackendVoid end
                        if helper ~= nil then
                            local ok, hsig = pcall(Helpers.helper_signature, helper)
                            if not ok or hsig == nil then
                                add_issue(issues, collector, C.CBackendIssueHelperMismatch(s.helper, tostring(hsig)))
                            else
                                local mismatch = (#actual ~= #hsig.params)
                                local n = math.min(#actual, #hsig.params)
                                for a = 1, n do if not type_eq(actual[a], hsig.params[a]) then mismatch = true end end
                                if s.dst ~= nil then
                                    local dty = locals[s.dst.text]
                                    if dty == nil then add_issue(issues, collector, C.CBackendIssueMissingLocal(func.name, s.dst))
                                    elseif not type_eq(dty, hsig.result) then mismatch = true end
                                elseif not type_eq(hsig.result, C.CBackendVoid) then mismatch = true end
                                if mismatch then add_issue(issues, collector, C.CBackendIssueHelperSignatureMismatch(s.helper, hsig.params, actual)) end
                            end
                        end
                        mark_init(s.dst)
                    elseif cls == C.CBackendLoad then
                        check_atom(s.addr, func, locals, initialized); check_access("load", s.access); if locals[s.dst.text] == nil then add_issue(issues, collector, C.CBackendIssueMissingLocal(func.name, s.dst)) end; mark_init(s.dst)
                    elseif cls == C.CBackendStore then
                        check_atom(s.addr, func, locals, initialized); check_atom(s.value, func, locals, initialized); check_access("store", s.access)
                    elseif cls == C.CBackendPlaceLoad then
                        local pty = place_type(s.place, func, locals)
                        local dty = locals[s.dst.text]
                        if dty == nil then add_issue(issues, collector, C.CBackendIssueMissingLocal(func.name, s.dst))
                        elseif pty ~= nil and not type_eq(pty, dty) then add_issue(issues, collector, C.CBackendIssuePlaceTypeMismatch("place-load", s.place, dty, pty)) end
                        mark_init(s.dst)
                    elseif cls == C.CBackendPlaceStore then
                        local pty = place_type(s.place, func, locals)
                        check_atom(s.value, func, locals, initialized)
                        local vty = atom_type(s.value, locals)
                        if pty ~= nil and vty ~= nil and not type_eq(pty, vty) then add_issue(issues, collector, C.CBackendIssuePlaceTypeMismatch("place-store", s.place, pty, vty)) end
                        if asdl.classof(s.place) == C.CBackendPlaceLocal then mark_init(s.place.local_id) end
                    elseif cls == C.CBackendZeroInit then
                        local pty = place_type(s.place, func, locals)
                        if pty ~= nil and not type_eq(pty, s.ty) then add_issue(issues, collector, C.CBackendIssuePlaceTypeMismatch("zero-init", s.place, s.ty, pty)) end
                        if asdl.classof(s.place) == C.CBackendPlaceLocal then mark_init(s.place.local_id) end
                    elseif cls == C.CBackendAggregateInit then
                        local pty = place_type(s.place, func, locals)
                        if pty ~= nil and not type_eq(pty, s.ty) then add_issue(issues, collector, C.CBackendIssuePlaceTypeMismatch("aggregate-init", s.place, s.ty, pty)) end
                        for a = 1, #s.fields do check_atom(s.fields[a].value, func, locals, initialized) end
                        if asdl.classof(s.place) == C.CBackendPlaceLocal then mark_init(s.place.local_id) end
                    elseif cls == C.CBackendArrayInit then
                        local pty = place_type(s.place, func, locals)
                        if pty ~= nil and not type_eq(pty, s.ty) then add_issue(issues, collector, C.CBackendIssuePlaceTypeMismatch("array-init", s.place, s.ty, pty)) end
                        for a = 1, #s.elems do if s.elems[a].index < 0 then add_issue(issues, collector, C.CBackendIssueLoadStoreTypeMismatch("array-init-index", C.CBackendIndex, C.CBackendVoid)) end; check_atom(s.elems[a].value, func, locals, initialized) end
                        if asdl.classof(s.place) == C.CBackendPlaceLocal then mark_init(s.place.local_id) end
                    elseif cls == C.CBackendCall then
                        for a = 1, #s.args do check_atom(s.args[a], func, locals, initialized) end
                        local tcls = asdl.classof(s.target)
                        if tcls == C.CBackendCallDirect then
                            local tf = funcs[s.target.func.text]
                            if not tf then add_issue(issues, collector, C.CBackendIssueMissingFunc(s.target.func)) else check_call_sig("call:" .. s.target.func.text, sigs[tf.sig.text], s.args, s.dst, s.target.func, locals) end
                        elseif tcls == C.CBackendCallExtern then
                            local te = externs[s.target["extern"].text]
                            if not te then add_issue(issues, collector, C.CBackendIssueMissingExtern(s.target["extern"])) else check_call_sig("extern:" .. s.target["extern"].text, sigs[te.sig.text], s.args, s.dst, s.target["extern"], locals) end
                        elseif tcls == C.CBackendCallIndirect then
                            check_atom(s.target.callee, func, locals)
                            local cty = atom_type(s.target.callee, locals)
                            if not cty or asdl.classof(cty) ~= C.CBackendCodePtr then add_issue(issues, collector, C.CBackendIssueIndirectCallNonCodePtr("indirect", cty or C.CBackendVoid))
                            elseif cty.sig.text ~= s.target.sig.text then add_issue(issues, collector, C.CBackendIssueDataCodePtrConfusion("indirect", cty)) end
                            check_call_sig("indirect", sigs[s.target.sig.text], s.args, s.dst, nil, locals)
                        elseif tcls == C.CBackendCallClosure then
                            check_atom(s.target.closure, func, locals)
                            local cty = atom_type(s.target.closure, locals)
                            if not cty or asdl.classof(cty) ~= C.CBackendClosureDescriptor then
                                add_issue(issues, collector, C.CBackendIssueIndirectCallNonCodePtr("closure", cty or C.CBackendVoid))
                            end
                            check_call_sig("closure", sigs[s.target.sig.text], s.args, s.dst, nil, locals)
                        end
                        mark_init(s.dst)
                    end
                end
                local t = b.term
                local tcls = asdl.classof(t)
                if tcls == C.CBackendGoto then check_transfer(func, labels, locals, t.dest, t.args)
                elseif tcls == C.CBackendIfGoto then check_atom(t.cond, func, locals, initialized); check_transfer(func, labels, locals, t.then_dest, t.then_args); check_transfer(func, labels, locals, t.else_dest, t.else_args)
                elseif tcls == C.CBackendSwitchGoto then
                    check_atom(t.value, func, locals, initialized)
                    for k = 1, #t.cases do check_transfer(func, labels, locals, t.cases[k].dest, t.cases[k].args) end
                    check_transfer(func, labels, locals, t.default_dest, t.default_args)
                elseif tcls == C.CBackendReturn then check_atom(t.value, func, locals, initialized) end
            end
        end

        return C.CBackendValidationReport(issues)
    end

    local function validate(unit, collector)
        return validate_input(C.CBackendValidationInput(unit, {}, {}), collector)
    end

    local api = { validate = validate, validate_input = validate_input }
    T._lalin_api_cache.c_validate = api
    return api
end

return bind_context
