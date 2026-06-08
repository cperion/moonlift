local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.c_emit ~= nil then return T._moonlift_api_cache.c_emit end

    local Core = T.MoonCore
    local C = T.MoonC
    local Helpers = require("moonlift.c_helpers").Define(T)

    local function append_all(out, xs) for i = 1, #(xs or {}) do out[#out + 1] = xs[i] end end

    local function sanitize(s)
        s = tostring(s or "x"):gsub("[^%w_]", "_")
        if s:match("^%d") then s = "_" .. s end
        if s == "" then s = "x" end
        return s
    end

    local function closure_type_name(ty)
        return "ml_closure_" .. sanitize(ty.sig.text)
    end

    local function scalar_name(s)
        if s == Core.ScalarBool then return "uint8_t" end
        if s == Core.ScalarI8 then return "int8_t" end
        if s == Core.ScalarI16 then return "int16_t" end
        if s == Core.ScalarI32 then return "int32_t" end
        if s == Core.ScalarI64 then return "int64_t" end
        if s == Core.ScalarU8 then return "uint8_t" end
        if s == Core.ScalarU16 then return "uint16_t" end
        if s == Core.ScalarU32 then return "uint32_t" end
        if s == Core.ScalarU64 then return "uint64_t" end
        if s == Core.ScalarF32 then return "float" end
        if s == Core.ScalarF64 then return "double" end
        if s == Core.ScalarRawPtr then return "void*" end
        if s == Core.ScalarIndex then return "intptr_t" end
        if s == Core.ScalarVoid then return "void" end
        return "intptr_t"
    end

    local emit_type
    emit_type = function(ty)
        local cls = pvm.classof(ty)
        if ty == C.CBackendVoid or cls == C.CBackendVoid then return "void" end
        if ty == C.CBackendBool8 or cls == C.CBackendBool8 then return "uint8_t" end
        if cls == C.CBackendScalar then return scalar_name(ty.scalar) end
        if ty == C.CBackendIndex or cls == C.CBackendIndex then return "ml_index" end
        if cls == C.CBackendDataPtr then return "void*" end
        if cls == C.CBackendCodePtr then return ty.sig.text end
        if cls == C.CBackendImportedCodePtr then return "void (*)(void)" end
        if cls == C.CBackendNamed then return (ty.id.module_name .. "_" .. ty.id.spelling):gsub("[^%w_]", "_") end
        if cls == C.CBackendArray then return emit_type(ty.elem) end
        if cls == C.CBackendSliceDescriptor then return "struct { " .. emit_type(C.CBackendDataPtr(ty.elem)) .. " data; ml_index len; }" end
        if cls == C.CBackendViewDescriptor then return "struct { " .. emit_type(C.CBackendDataPtr(ty.elem)) .. " data; ml_index len; ml_index stride; }" end
        if cls == C.CBackendClosureDescriptor then return closure_type_name(ty) end
        if cls == C.CBackendAbiHiddenOutPtr then return emit_type(C.CBackendDataPtr(ty.result)) end
        if cls == C.CBackendVector then return emit_type(ty.elem) end
        return "intptr_t"
    end

    local function literal(lit)
        local cls = pvm.classof(lit)
        if cls == Core.LitInt or cls == Core.LitFloat then return lit.raw end
        if cls == Core.LitBool then return lit.value and "1" or "0" end
        if cls == Core.LitNil then return "0" end
        if cls == Core.LitString then return "0" end
        return "0"
    end

    local function atom(a)
        local cls = pvm.classof(a)
        if cls == C.CBackendAtomLocal then return a["local"].text end
        if cls == C.CBackendAtomGlobal then return a.global.text end
        if cls == C.CBackendAtomLiteral then return "(" .. emit_type(a.ty) .. ")" .. literal(a.literal) end
        if cls == C.CBackendAtomNull then return "NULL" end
        return "0"
    end

    local place
    place = function(p)
        local cls = pvm.classof(p)
        if cls == C.CBackendPlaceLocal then return p["local"].text end
        if cls == C.CBackendPlaceGlobal then return p.global.text end
        if cls == C.CBackendPlaceDeref then return "(*(" .. emit_type(p.ty) .. "*)" .. atom(p.addr) .. ")" end
        if cls == C.CBackendPlaceField then return place(p.base) .. "." .. p.field.text end
        if cls == C.CBackendPlaceIndex then
            if pvm.classof(p.base) == C.CBackendPlaceDeref then return "((" .. emit_type(p.ty) .. "*)" .. atom(p.base.addr) .. ")[" .. atom(p.index) .. "]" end
            return place(p.base) .. "[" .. atom(p.index) .. "]"
        end
        if cls == C.CBackendPlaceBytes then return "(*(" .. emit_type(p.ty) .. "*)((unsigned char*)" .. atom(p.base) .. " + " .. tostring(p.offset) .. "))" end
        return "/*bad_place*/"
    end

    local function cmp_op(op)
        if op == Core.CmpEq then return "==" end
        if op == Core.CmpNe then return "!=" end
        if op == Core.CmpLt then return "<" end
        if op == Core.CmpLe then return "<=" end
        if op == Core.CmpGt then return ">" end
        if op == Core.CmpGe then return ">=" end
        return "=="
    end

    local function cast_expr(op, to, value)
        return "(" .. emit_type(to) .. ")(" .. atom(value) .. ")"
    end

    local function rvalue(rv)
        local cls = pvm.classof(rv)
        if cls == C.CBackendRAtom then return atom(rv.atom) end
        if cls == C.CBackendRCompare then return "(" .. atom(rv.lhs) .. " " .. cmp_op(rv.op) .. " " .. atom(rv.rhs) .. ")" end
        if cls == C.CBackendRCast then return cast_expr(rv.op, rv.to, rv.value) end
        if cls == C.CBackendRSelect then return "(" .. atom(rv.cond) .. " ? " .. atom(rv.then_value) .. " : " .. atom(rv.else_value) .. ")" end
        if cls == C.CBackendRFuncAddr then return rv.func.text end
        if cls == C.CBackendRExternAddr then return rv["extern"].text end
        if cls == C.CBackendRPtrOffset then return "((char*)" .. atom(rv.base) .. " + (" .. atom(rv.index) .. ") * " .. tostring(rv.elem_size) .. " + " .. tostring(rv.const_offset) .. ")" end
        if cls == C.CBackendRAddrOfPlace then return "&" .. place(rv.place) end
        return "0"
    end

    local function decl(ty, name)
        local cls = pvm.classof(ty)
        if cls == C.CBackendArray then return emit_type(ty.elem) .. " " .. name .. "[" .. tostring(ty.count) .. "]" end
        return emit_type(ty) .. " " .. name
    end

    local function sig_params(params)
        if #params == 0 then return "void" end
        local out = {}
        for i = 1, #params do out[i] = emit_type(params[i]) end
        return table.concat(out, ", ")
    end

    local function func_params(params)
        if #params == 0 then return "void" end
        local out = {}
        for i = 1, #params do out[i] = decl(params[i].ty, params[i].id.text) end
        return table.concat(out, ", ")
    end

    local function sig_by_id(unit)
        local out = {}
        for i = 1, #unit.sigs do out[unit.sigs[i].id.text] = unit.sigs[i] end
        return out
    end

    local function collect_closure_types(unit)
        local out, order = {}, {}
        local function visit_ty(ty)
            local cls = pvm.classof(ty)
            if cls == C.CBackendClosureDescriptor then
                local name = closure_type_name(ty)
                if out[name] == nil then out[name] = ty; order[#order + 1] = name end
            elseif cls == C.CBackendArray then visit_ty(ty.elem)
            elseif cls == C.CBackendDataPtr and ty.pointee ~= nil then visit_ty(ty.pointee)
            elseif cls == C.CBackendAbiHiddenOutPtr then visit_ty(ty.result)
            elseif cls == C.CBackendSliceDescriptor or cls == C.CBackendViewDescriptor then visit_ty(ty.elem) end
        end
        for i = 1, #(unit.sigs or {}) do
            for j = 1, #unit.sigs[i].params do visit_ty(unit.sigs[i].params[j]) end
            visit_ty(unit.sigs[i].result)
        end
        for i = 1, #(unit.funcs or {}) do
            for j = 1, #unit.funcs[i].params do visit_ty(unit.funcs[i].params[j].ty) end
            for j = 1, #unit.funcs[i].locals do visit_ty(unit.funcs[i].locals[j].ty) end
            for j = 1, #unit.funcs[i].blocks do
                for k = 1, #unit.funcs[i].blocks[j].params do visit_ty(unit.funcs[i].blocks[j].params[k].ty) end
            end
        end
        for i = 1, #(unit.globals or {}) do visit_ty(unit.globals[i].ty) end
        return out, order
    end

    local function emit_closure_type_decls(closure_types, closure_order, out)
        for i = 1, #closure_order do
            local name = closure_order[i]
            local ty = closure_types[name]
            out[#out + 1] = "struct " .. name .. " { " .. ty.sig.text .. " fn; void* ctx; };"
        end
    end

    local function emit_type_decls(unit, out)
        for i = 1, #unit.types do
            local td = unit.types[i]
            local cls = pvm.classof(td)
            local name = (td.id.module_name .. "_" .. td.id.spelling):gsub("[^%w_]", "_")
            if cls == C.CBackendTypedef then out[#out + 1] = "typedef " .. decl(td.ty, name) .. ";"
            elseif cls == C.CBackendStructDecl then
                out[#out + 1] = "typedef struct " .. name .. " {"
                for j = 1, #td.fields do out[#out + 1] = "    " .. decl(td.fields[j].ty, td.fields[j].name.text) .. ";" end
                out[#out + 1] = "} " .. name .. ";"
                if td.size ~= nil then out[#out + 1] = "typedef char ml_assert_size_" .. name .. "[(sizeof(" .. name .. ") == " .. tostring(td.size) .. ") ? 1 : -1];" end
                if td.align ~= nil then out[#out + 1] = "typedef char ml_assert_align_" .. name .. "[(offsetof(struct { char c; " .. name .. " x; }, x) == " .. tostring(td.align) .. ") ? 1 : -1];" end
            elseif cls == C.CBackendUnionDecl then
                out[#out + 1] = "typedef union " .. name .. " {"
                for j = 1, #td.fields do out[#out + 1] = "    " .. decl(td.fields[j].ty, td.fields[j].name.text) .. ";" end
                out[#out + 1] = "} " .. name .. ";"
                if td.size ~= nil then out[#out + 1] = "typedef char ml_assert_size_" .. name .. "[(sizeof(" .. name .. ") == " .. tostring(td.size) .. ") ? 1 : -1];" end
                if td.align ~= nil then out[#out + 1] = "typedef char ml_assert_align_" .. name .. "[(offsetof(struct { char c; " .. name .. " x; }, x) == " .. tostring(td.align) .. ") ? 1 : -1];" end
            elseif cls == C.CBackendOpaqueDecl then out[#out + 1] = "typedef struct " .. name .. " " .. name .. ";" end
        end
    end

    local function byte_init_list(g)
        local entries = {}
        for j = 1, #g.inits do
            local init = g.inits[j]
            local icls = pvm.classof(init)
            if icls == C.CBackendDataBytes then
                for k = 1, #init.bytes do
                    entries[#entries + 1] = "[" .. tostring(init.offset + k - 1) .. "] = " .. tostring(init.bytes:byte(k))
                end
            elseif icls == C.CBackendDataZero then
                -- Missing C initializers are zero-filled, so explicit zeros are unnecessary.
            end
        end
        if #entries == 0 then return "{0}" end
        return "{ " .. table.concat(entries, ", ") .. " }"
    end

    local function emit_globals(unit, out)
        for i = 1, #unit.globals do
            local g = unit.globals[i]
            local gcls = pvm.classof(g.ty)
            local byte_global = (gcls == C.CBackendDataPtr) or (#g.inits > 0 and pvm.classof(g.inits[1]) == C.CBackendDataBytes)
            if byte_global then
                out[#out + 1] = "static unsigned char " .. g.name.text .. "[" .. tostring(g.size) .. "] = " .. byte_init_list(g) .. ";"
            else
                out[#out + 1] = "static " .. decl(g.ty, g.name.text) .. ";"
            end
            for j = 1, #g.inits do
                local init = g.inits[j]
                local icls = pvm.classof(init)
                if icls == C.CBackendDataBytes then
                    out[#out + 1] = "/* bytes init at " .. tostring(init.offset) .. " size " .. tostring(#init.bytes) .. " */"
                elseif icls == C.CBackendDataZero then
                    out[#out + 1] = "/* zero init at " .. tostring(init.offset) .. " size " .. tostring(init.size) .. " */"
                elseif icls == C.CBackendDataScalar then
                    out[#out + 1] = "/* scalar init at " .. tostring(init.offset) .. ": " .. literal(init.literal) .. " */"
                elseif icls == C.CBackendDataReloc then
                    out[#out + 1] = "/* reloc init at " .. tostring(init.offset) .. " */"
                end
            end
        end
    end

    local function emit_transfer(out, block, args)
        for i = 1, #block.params do out[#out + 1] = "    __xfer_" .. block.label.text .. "_" .. tostring(i) .. " = " .. atom(args[i]) .. ";" end
        out[#out + 1] = "    goto " .. block.label.text .. ";"
    end

    local function emit_stmt(s, out, blocks)
        local cls = pvm.classof(s)
        if cls == C.CBackendAssign then out[#out + 1] = "    " .. s.dst.text .. " = " .. rvalue(s.rhs) .. ";"
        elseif cls == C.CBackendHelperCall then
            local args = {}; for i = 1, #s.args do args[i] = atom(s.args[i]) end
            local call = s.helper.text .. "(" .. table.concat(args, ", ") .. ")"
            if s.dst then out[#out + 1] = "    " .. s.dst.text .. " = " .. call .. ";" else out[#out + 1] = "    " .. call .. ";" end
        elseif cls == C.CBackendLoad then out[#out + 1] = "    memcpy(&" .. s.dst.text .. ", " .. atom(s.addr) .. ", sizeof(" .. s.dst.text .. "));"
        elseif cls == C.CBackendStore then out[#out + 1] = "    memcpy(" .. atom(s.addr) .. ", &" .. atom(s.value) .. ", sizeof(" .. atom(s.value) .. "));"
        elseif cls == C.CBackendPlaceLoad then out[#out + 1] = "    " .. s.dst.text .. " = " .. place(s.place) .. ";"
        elseif cls == C.CBackendPlaceStore then out[#out + 1] = "    " .. place(s.place) .. " = " .. atom(s.value) .. ";"
        elseif cls == C.CBackendZeroInit then out[#out + 1] = "    memset(&" .. place(s.place) .. ", 0, (size_t)" .. tostring(s.size) .. ");"
        elseif cls == C.CBackendAggregateInit then
            for i = 1, #s.fields do out[#out + 1] = "    " .. place(s.place) .. "." .. s.fields[i].field.text .. " = " .. atom(s.fields[i].value) .. ";" end
        elseif cls == C.CBackendArrayInit then
            for i = 1, #s.elems do out[#out + 1] = "    " .. place(s.place) .. "[" .. tostring(s.elems[i].index) .. "] = " .. atom(s.elems[i].value) .. ";" end
        elseif cls == C.CBackendCall then
            local args = {}; for i = 1, #s.args do args[i] = atom(s.args[i]) end
            local tcls = pvm.classof(s.target)
            local callee
            if tcls == C.CBackendCallDirect then callee = s.target.func.text
            elseif tcls == C.CBackendCallExtern then callee = s.target["extern"].text
            elseif tcls == C.CBackendCallIndirect then callee = atom(s.target.callee) end
            local call = callee .. "(" .. table.concat(args, ", ") .. ")"
            if s.dst then out[#out + 1] = "    " .. s.dst.text .. " = " .. call .. ";" else out[#out + 1] = "    " .. call .. ";" end
        elseif cls == C.CBackendComment then out[#out + 1] = "    /* " .. s.text:gsub("%*/", "* /") .. " */"
        end
    end

    local function emit_term(t, out, blocks)
        local cls = pvm.classof(t)
        if cls == C.CBackendGoto then emit_transfer(out, blocks[t.dest.text], t.args)
        elseif cls == C.CBackendIfGoto then
            out[#out + 1] = "    if (" .. atom(t.cond) .. ") {"
            emit_transfer(out, blocks[t.then_dest.text], t.then_args)
            out[#out + 1] = "    } else {"
            emit_transfer(out, blocks[t.else_dest.text], t.else_args)
            out[#out + 1] = "    }"
        elseif cls == C.CBackendSwitchGoto then
            out[#out + 1] = "    switch (" .. atom(t.value) .. ") {"
            for i = 1, #t.cases do
                out[#out + 1] = "    case " .. literal(t.cases[i].literal) .. ":"
                emit_transfer(out, blocks[t.cases[i].dest.text], t.cases[i].args)
            end
            out[#out + 1] = "    default:"
            emit_transfer(out, blocks[t.default_dest.text], t.default_args)
            out[#out + 1] = "    }"
        elseif cls == C.CBackendReturnVoid then out[#out + 1] = "    return;"
        elseif cls == C.CBackendReturn then out[#out + 1] = "    return " .. atom(t.value) .. ";"
        elseif cls == C.CBackendTrap then out[#out + 1] = "    abort();"
        end
    end

    local function emit_func(f, sigs, out)
        local sig = sigs[f.sig.text]
        out[#out + 1] = emit_type(sig.result) .. " " .. f.name.text .. "(" .. func_params(f.params) .. ") {"
        for i = 1, #f.locals do
            local lty = f.locals[i].ty
            local lcls = pvm.classof(lty)
            if lcls == C.CBackendArray or lcls == C.CBackendSliceDescriptor or lcls == C.CBackendViewDescriptor or lcls == C.CBackendClosureDescriptor or lcls == C.CBackendNamed then
                out[#out + 1] = "    " .. decl(lty, f.locals[i].id.text) .. ";"
            else
                out[#out + 1] = "    " .. decl(lty, f.locals[i].id.text) .. " = 0;"
            end
        end
        local blocks = {}; for i = 1, #f.blocks do blocks[f.blocks[i].label.text] = f.blocks[i] end
        for i = 1, #f.blocks do
            local b = f.blocks[i]
            for j = 1, #b.params do
                out[#out + 1] = "    " .. decl(b.params[j].ty, b.params[j]["local"].text) .. " = 0;"
                out[#out + 1] = "    " .. decl(b.params[j].ty, "__xfer_" .. b.label.text .. "_" .. tostring(j)) .. " = 0;"
            end
        end
        for i = 1, #f.blocks do
            local b = f.blocks[i]
            out[#out + 1] = b.label.text .. ":"
            for j = 1, #b.params do out[#out + 1] = "    " .. b.params[j]["local"].text .. " = __xfer_" .. b.label.text .. "_" .. tostring(j) .. ";" end
            for j = 1, #b.stmts do emit_stmt(b.stmts[j], out, blocks) end
            emit_term(b.term, out, blocks)
        end
        out[#out + 1] = "}"
    end

    local function helper_is_atomic(h)
        local k = h.kind or h
        local cls = pvm.classof(k)
        return cls == C.CBackendHelperAtomicLoad or cls == C.CBackendHelperAtomicStore
            or cls == C.CBackendHelperAtomicRmw or cls == C.CBackendHelperAtomicCas
            or cls == C.CBackendHelperAtomicFence
    end

    local function target_supports_c11_atomics(target)
        if target == nil then return false end
        local dcls = pvm.classof(target.dialect)
        return target.dialect == C.CBackendC11 or target.dialect == C.CBackendGnuC or target.dialect == C.CBackendClangC
            or dcls == C.CBackendC11 or dcls == C.CBackendGnuC or dcls == C.CBackendClangC
    end

    local function emit(unit, opts)
        opts = opts or {}
        local out = {}
        local needs_atomics = false
        for i = 1, #unit.helpers do if helper_is_atomic(unit.helpers[i]) then needs_atomics = true end end

        out[#out + 1] = "/* generated by moonlift C backend */"
        out[#out + 1] = "/* target: pointer_bits=" .. tostring(unit.target and unit.target.pointer_bits or 64)
            .. " index_bits=" .. tostring(unit.target and unit.target.index_bits or 64)
            .. " hosted=" .. tostring(unit.target and unit.target.hosted ~= false) .. " */"
        out[#out + 1] = "#include <stdint.h>"
        out[#out + 1] = "#include <stddef.h>"
        out[#out + 1] = "#include <string.h>"
        out[#out + 1] = "#include <stdlib.h>"
        out[#out + 1] = "#include <math.h>"
        if needs_atomics and target_supports_c11_atomics(unit.target) then out[#out + 1] = "#include <stdatomic.h>" end
        if needs_atomics and not target_supports_c11_atomics(unit.target) then out[#out + 1] = "/* atomics require C11 <stdatomic.h> or a runtime helper provider */" end
        out[#out + 1] = ""

        out[#out + 1] = "/* typedefs */"
        local index_ty = (unit.target and unit.target.index_bits == 32) and "int32_t" or "int64_t"
        out[#out + 1] = "typedef " .. index_ty .. " ml_index;"
        out[#out + 1] = ""

        local closure_types, closure_order = collect_closure_types(unit)

        out[#out + 1] = "/* type forwards for signatures */"
        for i = 1, #closure_order do out[#out + 1] = "typedef struct " .. closure_order[i] .. " " .. closure_order[i] .. ";" end
        for i = 1, #unit.types do
            local td = unit.types[i]
            local cls = pvm.classof(td)
            local name = (td.id.module_name .. "_" .. td.id.spelling):gsub("[^%w_]", "_")
            if cls == C.CBackendStructDecl or cls == C.CBackendOpaqueDecl then out[#out + 1] = "typedef struct " .. name .. " " .. name .. ";"
            elseif cls == C.CBackendUnionDecl then out[#out + 1] = "typedef union " .. name .. " " .. name .. ";" end
        end
        out[#out + 1] = ""

        out[#out + 1] = "/* signatures */"
        for i = 1, #unit.sigs do
            local s = unit.sigs[i]
            out[#out + 1] = "typedef " .. emit_type(s.result) .. " (*" .. s.id.text .. ")(" .. sig_params(s.params) .. ");"
        end
        out[#out + 1] = ""

        out[#out + 1] = "/* type declarations and layout assertions */"
        emit_closure_type_decls(closure_types, closure_order, out)
        emit_type_decls(unit, out)
        out[#out + 1] = ""

        local sigs = sig_by_id(unit)
        out[#out + 1] = "/* externs */"
        for i = 1, #unit.externs do
            local e = unit.externs[i]
            local s = sigs[e.sig.text]
            out[#out + 1] = "extern " .. emit_type(s.result) .. " " .. e.name.text .. "(" .. sig_params(s.params) .. ");"
        end
        out[#out + 1] = ""

        out[#out + 1] = "/* globals */"
        emit_globals(unit, out)
        out[#out + 1] = ""

        out[#out + 1] = "/* helpers */"
        for i = 1, #unit.helpers do append_all(out, Helpers.emit_helper(unit.helpers[i], emit_type)) end
        out[#out + 1] = ""

        out[#out + 1] = "/* prototypes */"
        for i = 1, #unit.funcs do
            local f = unit.funcs[i]
            local s = sigs[f.sig.text]
            out[#out + 1] = emit_type(s.result) .. " " .. f.name.text .. "(" .. func_params(f.params) .. ");"
        end
        out[#out + 1] = ""

        out[#out + 1] = "/* bodies */"
        for i = 1, #unit.funcs do emit_func(unit.funcs[i], sigs, out) end
        return table.concat(out, "\n") .. "\n"
    end

    local api = { emit = emit, emit_type = emit_type }
    T._moonlift_api_cache.c_emit = api
    return api
end

return M
