local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.residual_native ~= nil then return T._lalin_api_cache.residual_native end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Value = T.LalinValue
    local LJ = T.LalinLuaJIT
    local Back = T.LalinBack
    local Stencil = T.LalinStencil
    local Residual = T.LalinResidual

    local api = {}

    local function sanitize(s)
        s = tostring(s or "x"):gsub("[^%w_]", "_")
        if s == "" then s = "x" end
        if s:match("^%d") then s = "_" .. s end
        return s
    end

    local function class_name(x)
        local cls = asdl.classof(x) or x
        return tostring(cls):match("Class%((.-)%)") or tostring(cls)
    end

    local function reason(code, message)
        return Residual.ResidualReason(tostring(code), tostring(message))
    end

    local function unsupported(value, site)
        error("residual_native: unsupported " .. tostring(site or "value") .. " " .. class_name(value), 3)
    end

    local function id_name(id)
        return "v_" .. sanitize(id.text)
    end

    local function func_name(name)
        return "fn_" .. sanitize(name)
    end

    local function native_c_name(prefix, name)
        return "__lalin_native_" .. prefix .. "_" .. sanitize(name)
    end

    local function atom_key(value)
        local name = asdl.class_basename(value)
        if name ~= nil then return name end
        return tostring(value)
    end

    local function value_key(value)
        if value ~= nil and type(value) == "table" and type(value.patch_template_key) == "function" then
            return value:patch_template_key()
        end
        return atom_key(value)
    end

    local function optional_key(value)
        if value == nil then return "_" end
        return value_key(value)
    end

    local function list_key(values)
        local out = {}
        for i = 1, #(values or {}) do out[i] = value_key(values[i]) end
        return table.concat(out, ",")
    end

    local patch_cdef_done = false

    local function cdef_patch_runtime()
        if patch_cdef_done then return true end
        local ffi = require("ffi")
        local ok = pcall(ffi.cdef, [[
typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef unsigned int uint32_t;
typedef int int32_t;
typedef long long int64_t;
typedef unsigned long uint64_t;
typedef unsigned long size_t;
typedef long intptr_t;
typedef unsigned long uintptr_t;
void *mmap(void *addr, size_t length, int prot, int flags, int fd, intptr_t offset);
int mprotect(void *addr, size_t len, int prot);
]])
        patch_cdef_done = ok
        return ok
    end

    local function unsigned_limit(bits)
        bits = tonumber(bits)
        if bits == 8 then return 255 end
        if bits == 16 then return 65535 end
        if bits == 32 then return 4294967295 end
        if bits == 64 then return 18446744073709551615 end
        return nil
    end

    local function signed_min(bits)
        bits = tonumber(bits)
        if bits == 8 then return -128 end
        if bits == 16 then return -32768 end
        if bits == 32 then return -2147483648 end
        if bits == 64 then return -9223372036854775808 end
        return nil
    end

    local function signed_max(bits)
        bits = tonumber(bits)
        if bits == 8 then return 127 end
        if bits == 16 then return 32767 end
        if bits == 32 then return 2147483647 end
        if bits == 64 then return 9223372036854775807 end
        return nil
    end

    local function normalize_int(value, bits, signed)
        value = tonumber(value)
        bits = tonumber(bits)
        if value == nil or bits == nil then
            return nil, reason("patch_non_numeric_value", "patch coordinate did not produce a numeric value")
        end
        if signed then
            local lo, hi = signed_min(bits), signed_max(bits)
            if lo == nil or hi == nil then return nil, reason("patch_bad_width", "unsupported signed patch width " .. tostring(bits)) end
            if value < lo or value > hi then return nil, reason("patch_value_out_of_range", "signed patch value out of range for " .. tostring(bits) .. " bits") end
            if value < 0 then value = unsigned_limit(bits) + 1 + value end
        else
            local hi = unsigned_limit(bits)
            if hi == nil then return nil, reason("patch_bad_width", "unsupported unsigned patch width " .. tostring(bits)) end
            if value < 0 or value > hi then return nil, reason("patch_value_out_of_range", "unsigned patch value out of range for " .. tostring(bits) .. " bits") end
        end
        return math.floor(value)
    end

    local function installed_patch_stencil(materialized, mem, base, size, fn)
        return {
            materialized = materialized,
            memory = mem,
            code = base,
            size = size,
            fn = fn,
        }
    end

    function LJ.LJCType:residual_native_c_spelling()
        unsupported(self, "C type")
    end

    function LJ.LJCTypeVoid:residual_native_c_spelling()
        return "void"
    end

    function LJ.LJCTypeBool:residual_native_c_spelling()
        return "bool"
    end

    function LJ.LJCTypeScalar:residual_native_c_spelling()
        return self.spelling
    end

    function LJ.LJCTypePointer:residual_native_c_spelling()
        local pointee = self.pointee and self.pointee:residual_native_c_spelling() or "void"
        return pointee .. "*"
    end

    function LJ.LJCTypeArray:residual_native_c_spelling()
        return self.elem:residual_native_c_spelling() .. "[" .. tostring(self.count) .. "]"
    end

    function LJ.LJCTypeNamed:residual_native_c_spelling()
        return self.spelling
    end

    function LJ.LJCTypeFuncPtr:residual_native_c_spelling()
        return "void (*)(void)"
    end

    function LJ.LJCType:residual_native_int_literal_suffix()
        return ""
    end

    function LJ.LJCTypeScalar:residual_native_int_literal_suffix()
        if self.scalar == Back.BackI64 then return "LL" end
        if self.scalar == Back.BackU64 then return "ULL" end
        return ""
    end

    function Core.Literal:residual_native_c_literal(_phys)
        unsupported(self, "C literal")
    end

    function Core.LitInt:residual_native_c_literal(phys)
        local suffix = phys and phys.storage and phys.storage:residual_native_int_literal_suffix() or ""
        return tostring(self.raw) .. suffix
    end

    function Core.LitFloat:residual_native_c_literal(_phys)
        return tostring(self.raw)
    end

    function Core.LitBool:residual_native_c_literal(_phys)
        return self.value and "1" or "0"
    end

    function Core.LitString:residual_native_c_literal(_phys)
        local out = { '"' }
        for i = 1, #self.bytes do
            local b = self.bytes:byte(i)
            if b == 34 then out[#out + 1] = '\\"'
            elseif b == 92 then out[#out + 1] = "\\\\"
            elseif b == 10 then out[#out + 1] = "\\n"
            elseif b == 13 then out[#out + 1] = "\\r"
            elseif b == 9 then out[#out + 1] = "\\t"
            elseif b >= 32 and b <= 126 then out[#out + 1] = string.char(b)
            else out[#out + 1] = string.format("\\x%02x", b) end
        end
        out[#out + 1] = '"'
        return table.concat(out)
    end

    function Core.LitNil:residual_native_c_literal(_phys)
        return "0"
    end

    function Core.Literal:residual_patch_number()
        return nil, reason("patch_literal_not_numeric", "literal cannot be used as a numeric patch coordinate")
    end

    function Core.LitInt:residual_patch_number()
        return tonumber(self.raw)
    end

    function Core.LitBool:residual_patch_number()
        return self.value and 1 or 0
    end

    function Code.CodeConst:residual_patch_number()
        return nil, reason("patch_const_not_numeric", "constant cannot be used as a numeric patch coordinate")
    end

    function Code.CodeConstLiteral:residual_patch_number()
        return self.literal:residual_patch_number()
    end

    function Value.ValueExpr:residual_patch_number()
        return nil, reason("patch_expr_not_constant", "value expression cannot be used as a numeric patch coordinate")
    end

    function Value.ValueExprConst:residual_patch_number()
        return self.const:residual_patch_number()
    end

    function LJ.LJPlace:residual_native_c_place()
        unsupported(self, "C place")
    end

    function LJ.LJPlaceLocal:residual_native_c_place()
        return "v_" .. sanitize(self.local_id.text)
    end

    function LJ.LJPlaceGlobal:residual_native_c_place()
        return sanitize(self.global.text)
    end

    function LJ.LJPlaceData:residual_native_c_place()
        return "__lalin_data_" .. sanitize(self.data.text)
    end

    function LJ.LJPlaceDeref:residual_native_c_place()
        return "(*(" .. self.addr:residual_native_c_expr() .. "))"
    end

    function LJ.LJPlaceField:residual_native_c_place()
        return "(" .. self.base:residual_native_c_place() .. ")." .. sanitize(self.name)
    end

    function LJ.LJPlaceIndex:residual_native_c_place()
        return "(" .. self.base:residual_native_c_place() .. ")[" .. self.index:residual_native_c_expr() .. "]"
    end

    function LJ.LJPlaceBytes:residual_native_c_place()
        return "(*(" .. self.ty.abi:residual_native_c_spelling() .. "*)((char*)(" .. self.base:residual_native_c_expr() .. ") + " .. tostring(self.offset or 0) .. "))"
    end

    local native_binop = {
        [Core.BinAdd] = "+",
        [Core.BinSub] = "-",
        [Core.BinMul] = "*",
        [Core.BinDiv] = "/",
        [Core.BinRem] = "%",
        [Core.BinBitAnd] = "&",
        [Core.BinBitOr] = "|",
        [Core.BinBitXor] = "^",
        [Core.BinShl] = "<<",
        [Core.BinLShr] = ">>",
        [Core.BinAShr] = ">>",
    }

    local native_cmpop = {
        [Core.CmpEq] = "==",
        [Core.CmpNe] = "!=",
        [Core.CmpLt] = "<",
        [Core.CmpLe] = "<=",
        [Core.CmpGt] = ">",
        [Core.CmpGe] = ">=",
    }

    function LJ.LJExpr:residual_native_c_expr()
        unsupported(self, "C expression")
    end

    function LJ.LJExprValue:residual_native_c_expr()
        return id_name(self.value)
    end

    function LJ.LJExprLiteral:residual_native_c_expr()
        return self.literal:residual_native_c_literal(self.ty)
    end

    function LJ.LJExprUnary:residual_native_c_expr()
        if self.op == Core.UnaryNeg then return "(-(" .. self.value:residual_native_c_expr() .. "))" end
        if self.op == Core.UnaryNot then return "(!(" .. self.value:residual_native_c_expr() .. "))" end
        if self.op == Core.UnaryBitNot then return "(~(" .. self.value:residual_native_c_expr() .. "))" end
        unsupported(self.op, "C unary op")
    end

    function LJ.LJExprIntBinary:residual_native_c_expr()
        local op = native_binop[self.op]
        if op == nil then unsupported(self.op, "C integer binary op") end
        return "((" .. self.lhs:residual_native_c_expr() .. ") " .. op .. " (" .. self.rhs:residual_native_c_expr() .. "))"
    end

    function LJ.LJExprFloatBinary:residual_native_c_expr()
        local op = native_binop[self.op]
        if op == nil then unsupported(self.op, "C float binary op") end
        return "((" .. self.lhs:residual_native_c_expr() .. ") " .. op .. " (" .. self.rhs:residual_native_c_expr() .. "))"
    end

    function LJ.LJExprCompare:residual_native_c_expr()
        local op = native_cmpop[self.op]
        if op == nil then unsupported(self.op, "C compare op") end
        return "((" .. self.lhs:residual_native_c_expr() .. ") " .. op .. " (" .. self.rhs:residual_native_c_expr() .. "))"
    end

    function LJ.LJExprSelect:residual_native_c_expr()
        return "((" .. self.cond:residual_native_c_expr() .. ") ? (" .. self.then_value:residual_native_c_expr() .. ") : (" .. self.else_value:residual_native_c_expr() .. "))"
    end

    function LJ.LJExprCast:residual_native_c_expr()
        return "((" .. self.to.abi:residual_native_c_spelling() .. ")(" .. self.value:residual_native_c_expr() .. "))"
    end

    function LJ.LJExprCDataCast:residual_native_c_expr()
        return "((" .. self.ty:residual_native_c_spelling() .. ")(" .. self.value:residual_native_c_expr() .. "))"
    end

    function LJ.LJExprAddrOfPlace:residual_native_c_expr()
        return "(&(" .. self.place:residual_native_c_place() .. "))"
    end

    function LJ.LJExprPtrOffset:residual_native_c_expr()
        local offset = tonumber(self.const_offset or 0) or 0
        local elem = tonumber(self.elem_size or 1) or 1
        local terms = { self.base:residual_native_c_expr(), "(" .. self.index:residual_native_c_expr() .. ")" }
        if offset ~= 0 then
            if elem ~= 0 and offset % elem == 0 then
                terms[#terms + 1] = tostring(offset / elem)
            else
                unsupported(self, "byte-granular pointer offset")
            end
        end
        return "(" .. table.concat(terms, " + ") .. ")"
    end

    function LJ.LJExprLoad:residual_native_c_expr()
        return self.place:residual_native_c_place()
    end

    local function c_signature_parts(symbol, c_signature)
        local sig = tostring(c_signature or "")
        local ret, params = sig:match("^%s*(.-)%s*%(%s*%*%s*%)%s*%((.*)%)%s*$")
        if ret == nil then
            local direct_ret, direct_name, direct_params = sig:match("^%s*(.-)%s+([_%a][_%w]*)%s*%((.*)%)%s*;?%s*$")
            if direct_ret ~= nil and direct_name == symbol then
                ret, params = direct_ret, direct_params
            end
        end
        if ret == nil then error("residual_native: cannot derive C prototype from stencil signature " .. sig, 3) end
        return ret, params
    end

    function LJ.LJParam:residual_native_c_param_decl()
        return self.ty.abi:residual_native_c_spelling() .. " " .. id_name(self.value)
    end

    function LJ.LJFunc:residual_native_machine_by_id(machine_id)
        for _, machine in ipairs(self.machines or {}) do
            if machine.id.text == machine_id.text then return machine end
        end
        return nil
    end

    function LJ.LJFunc:residual_native_sig(request)
        for _, sig in ipairs(request.module.sigs or {}) do
            if sig.id.text == self.sig.text then return sig end
        end
        return nil
    end

    function LJ.LJFunc:select_residual_function(request)
        local sig = self:residual_native_sig(request)
        if sig == nil then
            return Residual.ResidualFunctionRejected(self, reason("missing_luajit_signature", "missing LuaJIT signature " .. tostring(self.sig.text)))
        end
        return self.body:select_residual_func_body(self, sig, request)
    end

    function LJ.LJFuncBody:select_residual_func_body(func, _sig, _request)
        return Residual.ResidualFunctionRejected(func, reason("unsupported_luajit_body", "LuaJIT function body is not residual-native materializable"))
    end

    function LJ.LJBodyMachine:select_residual_func_body(func, sig, request)
        local machine = func:residual_native_machine_by_id(self.machine)
        if machine == nil then
            return Residual.ResidualFunctionRejected(func, reason("missing_luajit_machine", "missing LuaJIT machine " .. tostring(self.machine.text)))
        end
        return self.terminal:select_residual_terminal(func, sig, self, machine, request)
    end

    function LJ.LJTerminal:select_residual_terminal(func, _sig, _body, _machine, _request)
        return Residual.ResidualFunctionRejected(func, reason("unsupported_luajit_terminal", "LuaJIT machine terminal is not residual-native materializable"))
    end

    function LJ.LJTerminalFirst:select_residual_terminal(func, sig, _body, machine, request)
        if self.default ~= nil then
            return Residual.ResidualFunctionRejected(func, reason("terminal_default", "first terminal with a default is not a direct native residual stencil call"))
        end
        return machine.op:select_residual_machine_terminal(func, sig, request)
    end

    function LJ.LJMachineOp:select_residual_machine_terminal(func, _sig, _request)
        return Residual.ResidualFunctionRejected(func, reason("unsupported_luajit_machine", "LuaJIT machine op is not a direct residual-native stencil call"))
    end

    function LJ.LJMachineStencilCall:residual_native_call_result(sig)
        local result = self.result_ty or (sig and sig.result)
        if result == nil then return Residual.CResidualCallReturnsVoid end
        return Residual.CResidualCallReturnsValue(result)
    end

    function LJ.LJMachineStencilEffect:residual_native_call_result(_sig)
        return Residual.CResidualCallReturnsVoid
    end

    function LJ.LJMachineStencilCall:residual_native_result_c_type(sig)
        local result = self.result_ty or (sig and sig.result)
        if result == nil then return "void" end
        return result.abi:residual_native_c_spelling()
    end

    function LJ.LJMachineStencilEffect:residual_native_result_c_type(_sig)
        return "void"
    end

    function LJ.LJMachineStencilCall:residual_native_c_call_expr()
        local args = {}
        for i = 1, #self.args do args[i] = self.args[i]:residual_native_c_expr() end
        return self.artifact.symbol.text .. "(" .. table.concat(args, ", ") .. ")"
    end

    function LJ.LJMachineStencilEffect:residual_native_c_call_expr()
        local args = {}
        for i = 1, #self.args do args[i] = self.args[i]:residual_native_c_expr() end
        return self.artifact.symbol.text .. "(" .. table.concat(args, ", ") .. ")"
    end

    function LJ.LJMachineStencilCall:residual_native_wrapper_ctype(func, sig)
        local params = {}
        for i = 1, #func.params do params[i] = func.params[i].ty.abi:residual_native_c_spelling() end
        return self:residual_native_result_c_type(sig) .. " (*)(" .. (#params > 0 and table.concat(params, ", ") or "void") .. ")"
    end

    function LJ.LJMachineStencilEffect:residual_native_wrapper_ctype(func, _sig)
        local params = {}
        for i = 1, #func.params do params[i] = func.params[i].ty.abi:residual_native_c_spelling() end
        return "void (*)(" .. (#params > 0 and table.concat(params, ", ") or "void") .. ")"
    end

    function Stencil.StencilArtifact:select_stencil_storage(_request)
        return Residual.StencilStoredExactMC(self.instance.descriptor, self)
    end

    function Residual.StencilPatchEndian:patch_little_endian(copy)
        return nil, reason("unsupported_patch_endian", "patch endian leaf has no byte-order behavior")
    end

    function Residual.PatchEndianLittle:patch_little_endian(_copy)
        return true
    end

    function Residual.PatchEndianBig:patch_little_endian(_copy)
        return false
    end

    function Residual.PatchEndianTarget:patch_little_endian(copy)
        local endian = copy.target and copy.target.endian or "little"
        if endian == "little" then return true end
        if endian == "big" then return false end
        return nil, reason("unknown_patch_target_endian", "target endian is not little or big: " .. tostring(endian))
    end

    function Residual.StencilPatchCoordinate:patch_integer_value(_hole, _copy)
        return nil, reason("unsupported_patch_coordinate", "coordinate cannot be encoded as an integer patch value")
    end

    function Residual.StencilPatchCoordImmediateI32:patch_integer_value(_hole, _copy)
        return self.value
    end

    function Residual.StencilPatchCoordImmediateI64:patch_integer_value(_hole, _copy)
        return self.value
    end

    function Residual.StencilPatchCoordStride:patch_integer_value(_hole, _copy)
        return self.stride
    end

    function Residual.StencilPatchCoordAffineTerm:patch_integer_value(_hole, _copy)
        return self.coeff:residual_patch_number()
    end

    function Residual.StencilPatchCoordWindowOffset:patch_integer_value(_hole, _copy)
        return self.offset
    end

    function Residual.StencilPatchCoordFieldOffset:patch_integer_value(_hole, _copy)
        return self.offset
    end

    function Residual.StencilPatchCoordComponentIndex:patch_integer_value(_hole, _copy)
        return self.component_index
    end

    function Residual.StencilPatchCoordScalarConst:patch_integer_value(_hole, _copy)
        return self.value:residual_patch_number()
    end

    function Residual.StencilPatchCoordPointExprConst:patch_integer_value(_hole, _copy)
        return self.value:residual_patch_number()
    end

    function Residual.StencilPatchCoordinate:patch_target_address(_hole, _copy)
        return nil, reason("unsupported_patch_target", "coordinate cannot be encoded as a target address")
    end

    function Residual.StencilPatchCoordSymbolAddress:patch_target_address(_hole, copy)
        return copy:symbol_address(self.symbol)
    end

    function Residual.StencilPatchCoordRel32Target:patch_target_address(_hole, copy)
        return copy:symbol_address(self.symbol)
    end

    function Residual.StencilPatchBinding:apply_patch(copy)
        return self.hole:apply_patch(copy, self.coordinate)
    end

    function Residual.StencilPatchHole:apply_patch(_copy, _coordinate)
        return nil, reason("unsupported_patch_hole", "patch hole leaf has no executable copier behavior")
    end

    function Residual.PatchImm32:apply_patch(copy, coordinate)
        local value, value_reason = coordinate:patch_integer_value(self, copy)
        if value == nil then return nil, value_reason end
        return copy:write_integer(self.offset, 32, self.signed, self.endian, value)
    end

    function Residual.PatchImm64:apply_patch(copy, coordinate)
        local value, value_reason = coordinate:patch_integer_value(self, copy)
        if value == nil then return nil, value_reason end
        return copy:write_integer(self.offset, 64, self.signed, self.endian, value)
    end

    function Residual.PatchScalarConst:apply_patch(copy, coordinate)
        local value, value_reason = coordinate:patch_integer_value(self, copy)
        if value == nil then return nil, value_reason end
        return copy:write_integer(self.offset, self.bits, self.signed, self.endian, value)
    end

    function Residual.PatchFieldOffset:apply_patch(copy, coordinate)
        local value, value_reason = coordinate:patch_integer_value(self, copy)
        if value == nil then return nil, value_reason end
        return copy:write_integer(self.offset, self.bits, self.signed, self.endian, value)
    end

    function Residual.PatchStride:apply_patch(copy, coordinate)
        local value, value_reason = coordinate:patch_integer_value(self, copy)
        if value == nil then return nil, value_reason end
        return copy:write_integer(self.offset, self.bits, self.signed, self.endian, value)
    end

    function Residual.PatchPtr:apply_patch(copy, coordinate)
        local target, target_reason = coordinate:patch_target_address(self, copy)
        if target == nil then return nil, target_reason end
        return copy:write_pointer(self.offset, self.pointer_bits, self.endian, target)
    end

    function Residual.PatchRel32:apply_patch(copy, coordinate)
        local target, target_reason = coordinate:patch_target_address(self, copy)
        if target == nil then return nil, target_reason end
        target = copy:address_number(target)
        if target == nil then return nil, reason("patch_address_not_numeric", "rel32 patch target address could not be represented numerically") end
        local site = copy.base_addr + self.offset + self.pc_bias
        local disp = target + self.addend - site
        return copy:write_integer(self.offset, 32, true, self.endian, disp)
    end

    function Residual.StencilArtifactStorage:materialize_stencil()
        return nil, reason("unsupported_stencil_storage", "stencil storage leaf has no materializer")
    end

    function Residual.StencilStoredExactMC:materialize_stencil()
        return Residual.MaterializedExactStencil(self.artifact)
    end

    function Residual.StencilStoredPatchTemplateMC:materialize_stencil()
        return nil, reason("expansion_plan_required", "patch-template stencil storage materializes through StencilPatchExpansionPlan with typed patch bindings")
    end

    function Residual.StencilRequiresCompile:materialize_stencil()
        return nil, self.reason
    end

    function Code.CodeType:patch_template_key()
        unsupported(self, "residual bank code type key")
    end

    function Code.CodeTyVoid:patch_template_key()
        return "void"
    end

    function Code.CodeTyBool8:patch_template_key()
        return "bool8"
    end

    function Code.CodeTyInt:patch_template_key()
        return (self.signedness == Code.CodeSigned and "i" or "u") .. tostring(self.bits)
    end

    function Code.CodeTyFloat:patch_template_key()
        return "f" .. tostring(self.bits)
    end

    function Code.CodeTyIndex:patch_template_key()
        return "index"
    end

    function Code.CodeTyDataPtr:patch_template_key()
        return "dataptr(" .. optional_key(self.pointee) .. ")"
    end

    function Code.CodeTyCodePtr:patch_template_key()
        return "codeptr(" .. self.sig.text .. ")"
    end

    function Code.CodeTyNamed:patch_template_key()
        return "named(" .. self.module_name .. "." .. self.type_name .. ")"
    end

    function Code.CodeTyArray:patch_template_key()
        return "array(" .. self.elem:patch_template_key() .. "," .. tostring(self.count) .. ")"
    end

    function Code.CodeTySlice:patch_template_key()
        return "slice(" .. self.elem:patch_template_key() .. ")"
    end

    function Code.CodeTyView:patch_template_key()
        return "view(" .. self.elem:patch_template_key() .. ")"
    end

    function Code.CodeTyByteSpan:patch_template_key()
        return "bytespan"
    end

    function Code.CodeTyHandle:patch_template_key()
        return "handle(" .. self.repr:patch_template_key() .. ")"
    end

    function Code.CodeTyLease:patch_template_key()
        return "lease(" .. self.base:patch_template_key() .. ")"
    end

    function Code.CodeTyClosure:patch_template_key()
        return "closure(" .. self.sig.text .. ")"
    end

    function Code.CodeTyImportedC:patch_template_key()
        return "imported_c(" .. self.id.text .. ")"
    end

    function Code.CodeTyImportedCFuncPtr:patch_template_key()
        return "imported_c_funcptr(" .. self.sig.text .. ")"
    end

    function Code.CodeTyVector:patch_template_key()
        return "vec(" .. self.elem:patch_template_key() .. "," .. tostring(self.lanes) .. ")"
    end

    function Stencil.StencilAccessRef:patch_template_key()
        return self.name
    end

    function Stencil.StencilAxisRef:patch_template_key()
        return "axis" .. tostring(self.index)
    end

    function Stencil.StencilProducerForward:patch_template_key() return "forward" end
    function Stencil.StencilProducerBackward:patch_template_key() return "backward" end

    function Stencil.StencilWindowBoundaryReject:patch_template_key() return "reject" end
    function Stencil.StencilWindowBoundaryClamp:patch_template_key() return "clamp" end
    function Stencil.StencilWindowBoundaryWrap:patch_template_key() return "wrap" end
    function Stencil.StencilWindowBoundaryZero:patch_template_key() return "zero" end

    function Stencil.StencilProducerAxis:patch_template_key()
        return "axis(" .. self.index_ty:patch_template_key() .. "," .. optional_key(self.start) .. "," .. optional_key(self.stop) .. "," .. tostring(self.step) .. "," .. self.order:patch_template_key() .. ")"
    end

    function Stencil.StencilWindowAxis:patch_template_key()
        return "window(" .. tostring(self.before) .. "," .. tostring(self.after) .. "," .. self.boundary:patch_template_key() .. ")"
    end

    function Stencil.StencilProduceRange1D:patch_template_key()
        return "range1d(" .. self.index_ty:patch_template_key() .. "," .. optional_key(self.start) .. "," .. optional_key(self.stop) .. "," .. tostring(self.step) .. "," .. self.order:patch_template_key() .. ")"
    end

    function Stencil.StencilProduceRangeND:patch_template_key()
        return "range_nd(" .. list_key(self.axes) .. ")"
    end

    function Stencil.StencilProduceWindowND:patch_template_key()
        return "window_nd(" .. list_key(self.axes) .. "|" .. list_key(self.windows) .. ")"
    end

    function Stencil.StencilProduceTiledND:patch_template_key()
        return "tiled_nd(" .. list_key(self.axes) .. "|" .. table.concat(self.tile_sizes or {}, ",") .. ")"
    end

    function Stencil.StencilProducer:patch_template_key()
        return self.shape:patch_template_key()
    end

    function Value.ReductionAdd:patch_template_key() return "add" end
    function Value.ReductionMul:patch_template_key() return "mul" end
    function Value.ReductionMin:patch_template_key() return "min" end
    function Value.ReductionMax:patch_template_key() return "max" end
    function Value.ReductionAnd:patch_template_key() return "and" end
    function Value.ReductionOr:patch_template_key() return "or" end
    function Value.ReductionXor:patch_template_key() return "xor" end

    function Stencil.StencilReducer:patch_template_key()
        return "reducer(" .. self.reduction:patch_template_key() .. "," .. self.result_ty:patch_template_key() .. ")"
    end

    function Stencil.StencilStoreElementwise:patch_template_key() return "elementwise" end
    function Stencil.StencilStoreCopy:patch_template_key() return "copy(" .. value_key(self.semantics) .. ")" end
    function Stencil.StencilStoreScatter:patch_template_key() return "scatter(" .. value_key(self.conflicts) .. ")" end
    function Stencil.StencilStorePartition:patch_template_key() return "partition(" .. value_key(self.semantics) .. ")" end

    function Stencil.StencilReduceScopeDomain:patch_template_key() return "domain" end
    function Stencil.StencilReduceScopeAxes:patch_template_key() return "axes(" .. list_key(self.axes) .. "," .. self.dst:patch_template_key() .. ")" end
    function Stencil.StencilReduceScopeWindow:patch_template_key() return "window(" .. list_key(self.axes) .. "," .. self.dst:patch_template_key() .. ")" end

    function Stencil.StencilReduceFold:patch_template_key() return "fold(" .. self.reducer:patch_template_key() .. ")" end
    function Stencil.StencilReduceCount:patch_template_key() return "count(" .. value_key(self.pred) .. ")" end
    function Stencil.StencilReduceFind:patch_template_key() return "find(" .. value_key(self.pred) .. ")" end

    function Stencil.StencilScanInclusive:patch_template_key() return "inclusive" end
    function Stencil.StencilScanExclusive:patch_template_key() return "exclusive" end

    function Stencil.StencilScatterReduceSequential:patch_template_key() return "sequential" end
    function Stencil.StencilScatterReduceUniqueIndices:patch_template_key() return "unique" end
    function Stencil.StencilScatterReduceAtomic:patch_template_key() return "atomic(" .. value_key(self.ordering) .. ")" end
    function Stencil.StencilScatterReducePrivatized:patch_template_key() return "privatized" end

    function Stencil.StencilSinkStore:patch_template_key()
        return "store(" .. self.dst:patch_template_key() .. "," .. self.semantics:patch_template_key() .. ")"
    end

    function Stencil.StencilSinkReduce:patch_template_key()
        return "reduce(" .. self.result_ty:patch_template_key() .. "," .. self.scope:patch_template_key() .. "," .. self.semantics:patch_template_key() .. ")"
    end

    function Stencil.StencilSinkScan:patch_template_key()
        return "scan(" .. self.dst:patch_template_key() .. "," .. self.axis:patch_template_key() .. "," .. self.reducer:patch_template_key() .. "," .. self.mode:patch_template_key() .. "," .. self.result_ty:patch_template_key() .. ")"
    end

    function Stencil.StencilSinkScatterReduce:patch_template_key()
        return "scatter_reduce(" .. self.dst:patch_template_key() .. "," .. self.reducer:patch_template_key() .. "," .. self.conflicts:patch_template_key() .. "," .. self.result_ty:patch_template_key() .. ")"
    end

    function Stencil.StencilLaneFixed:patch_template_key() return "fixed(" .. tostring(self.lanes) .. ")" end
    function Stencil.StencilLaneNative:patch_template_key() return "native" end
    function Stencil.StencilLaneFromTarget:patch_template_key() return "target" end

    function Stencil.StencilScheduleScalar:patch_template_key()
        return "scalar"
    end

    function Stencil.StencilScheduleVector:patch_template_key()
        return "vector(" .. value_key(self.feature) .. "," .. self.lane_policy:patch_template_key() .. "," .. value_key(self.tail) .. "," .. tostring(self.vector_unroll) .. "," .. tostring(self.interleave) .. ")"
    end

    function Stencil.StencilScheduleAutoVector:patch_template_key()
        return "autovec"
    end

    function Stencil.StencilScheduleUnrolled:patch_template_key()
        return "unrolled(" .. tostring(self.factor) .. ")"
    end

    function Stencil.StencilAbi:patch_template_key()
        return "abi(" .. list_key(self.params) .. "->" .. optional_key(self.result) .. ")"
    end

    function Residual.StencilPatchTemplateFamily:patch_template_key()
        return "family(" .. self.spine:patch_template_key() .. "|" .. list_key(self.fixed_axes) .. ")"
    end

    function Residual.StencilPatchTemplateSpine:patch_template_key()
        return atom_key(self)
    end

    function Residual.StencilSpineRangeND:patch_template_key()
        return "range_nd(" .. tostring(self.rank) .. ")"
    end

    function Residual.StencilSpineWindowND:patch_template_key()
        return "window_nd(" .. tostring(self.rank) .. ")"
    end

    function Residual.StencilSpineTiledND:patch_template_key()
        return "tiled_nd(" .. tostring(self.rank) .. ")"
    end

    function Residual.StencilSpinePointExprApplyChain:patch_template_key()
        return "point_chain(" .. tostring(self.depth) .. "," .. tostring(self.arity) .. ")"
    end

    function Residual.StencilSpineFieldProjectionChain:patch_template_key()
        return "field_chain(" .. tostring(self.depth) .. ")"
    end

    function Residual.StencilSpineSoAComponentChain:patch_template_key()
        return "soa_chain(" .. tostring(self.depth) .. ")"
    end

    function Residual.StencilSpineLayoutAffine:patch_template_key()
        return "layout_affine(" .. tostring(self.rank) .. ")"
    end

    function Residual.StencilPatchTemplateAxis:patch_template_key()
        return atom_key(self)
    end

    function Residual.StencilTemplateSink:patch_template_key()
        return "sink(" .. value_key(self.sink) .. ")"
    end

    function Residual.StencilTemplateProducer:patch_template_key()
        return "producer(" .. value_key(self.producer) .. ")"
    end

    function Residual.StencilTemplateAccessLayout:patch_template_key()
        return "layout_exact(" .. value_key(self.layout) .. ")"
    end

    function Residual.StencilTemplateAccessLayoutShape:patch_template_key()
        return "layout_shape(" .. self.shape:patch_template_key() .. ")"
    end

    function Residual.StencilTemplatePointExpr:patch_template_key()
        return "point_exact(" .. value_key(self.expr) .. ")"
    end

    function Residual.StencilTemplatePointExprShape:patch_template_key()
        return "point_shape(" .. self.shape:patch_template_key() .. ")"
    end

    function Residual.StencilTemplateScalarType:patch_template_key()
        return "scalar(" .. self.ty:patch_template_key() .. ")"
    end

    function Residual.StencilTemplateSchedule:patch_template_key()
        return "schedule(" .. value_key(self.schedule) .. ")"
    end

    function Residual.StencilTemplateProof:patch_template_key()
        return "proof(" .. value_key(self.proof) .. ")"
    end

    function Residual.StencilTemplateTarget:patch_template_key()
        return "target(" .. value_key(self.target) .. ")"
    end

    function Residual.StencilTemplateAbi:patch_template_key()
        return "abi(" .. value_key(self.abi) .. ")"
    end

    function Residual.StencilAccessLayoutShape:patch_template_key()
        return atom_key(self)
    end

    function Residual.StencilLayoutShapeIndexed:patch_template_key()
        return "indexed(" .. self.parent:patch_template_key() .. "," .. self.index_ty:patch_template_key() .. ")"
    end

    function Residual.StencilLayoutShapeAffine1D:patch_template_key()
        return "affine1d(" .. self.parent:patch_template_key() .. "," .. tostring(self.scale) .. ")"
    end

    function Residual.StencilLayoutShapeAffineND:patch_template_key()
        return "affinend(" .. self.parent:patch_template_key() .. "," .. tostring(self.rank) .. ")"
    end

    function Residual.StencilLayoutShapeFieldProjection:patch_template_key()
        return "field(" .. self.parent:patch_template_key() .. "," .. self.record_ty:patch_template_key() .. "," .. self.field_name .. ")"
    end

    function Residual.StencilLayoutShapeSoAComponent:patch_template_key()
        return "soa(" .. self.parent:patch_template_key() .. "," .. self.record_ty:patch_template_key() .. "," .. self.field_name .. ")"
    end

    function Residual.StencilPredicateShape:patch_template_key()
        return atom_key(self)
    end

    function Residual.StencilPredShapeCompareConst:patch_template_key()
        return "cmp_const(" .. value_key(self.cmp) .. "," .. self.operand_ty:patch_template_key() .. ")"
    end

    function Residual.StencilPredShapeRange:patch_template_key()
        return "range(" .. self.operand_ty:patch_template_key() .. "," .. value_key(self.lower_cmp) .. "," .. value_key(self.upper_cmp) .. ")"
    end

    function Residual.StencilPredShapeAnd:patch_template_key()
        return "and(" .. list_key(self.terms) .. ")"
    end

    function Residual.StencilPredShapeOr:patch_template_key()
        return "or(" .. list_key(self.terms) .. ")"
    end

    function Residual.StencilPredShapeNot:patch_template_key()
        return "not(" .. self.term:patch_template_key() .. ")"
    end

    function Residual.StencilPredShapeIsNaN:patch_template_key()
        return "isnan(" .. self.operand_ty:patch_template_key() .. ")"
    end

    function Residual.StencilPredShapeIsInf:patch_template_key()
        return "isinf(" .. self.operand_ty:patch_template_key() .. ")"
    end

    function Residual.StencilPredShapeIsFinite:patch_template_key()
        return "isfinite(" .. self.operand_ty:patch_template_key() .. ")"
    end

    function Residual.StencilPointExprShape:patch_template_key()
        return atom_key(self)
    end

    function Residual.StencilPointShapeWindowInput:patch_template_key()
        return "window_input(" .. tostring(self.offset_count) .. ")"
    end

    function Residual.StencilPointShapeConst:patch_template_key()
        return "const(" .. self.ty:patch_template_key() .. ")"
    end

    function Residual.StencilPointShapeUnary:patch_template_key()
        return "unary(" .. value_key(self.op) .. "," .. self.arg:patch_template_key() .. "," .. optional_key(self.result_ty) .. ")"
    end

    function Residual.StencilPointShapeBinary:patch_template_key()
        return "binary(" .. value_key(self.op) .. "," .. self.left:patch_template_key() .. "," .. self.right:patch_template_key() .. "," .. optional_key(self.result_ty) .. ")"
    end

    function Residual.StencilPointShapeCast:patch_template_key()
        return "cast(" .. value_key(self.op) .. "," .. self.arg:patch_template_key() .. "," .. self.from:patch_template_key() .. "," .. self.to:patch_template_key() .. ")"
    end

    function Residual.StencilPointShapePredicate:patch_template_key()
        return "pred(" .. self.pred:patch_template_key() .. "," .. self.arg:patch_template_key() .. "," .. self.result_ty:patch_template_key() .. ")"
    end

    function Residual.StencilPointShapeCompare:patch_template_key()
        return "cmp(" .. value_key(self.cmp) .. "," .. self.left:patch_template_key() .. "," .. self.right:patch_template_key() .. "," .. self.result_ty:patch_template_key() .. ")"
    end

    function Residual.StencilPointShapeSelect:patch_template_key()
        return "select(" .. self.pred:patch_template_key() .. "," .. self.cond:patch_template_key() .. "," .. self.then_expr:patch_template_key() .. "," .. self.else_expr:patch_template_key() .. "," .. self.result_ty:patch_template_key() .. ")"
    end

    function Stencil.StencilSink:residual_patch_template_spine(_producer)
        return Residual.StencilSpineRangeND(1)
    end

    function Stencil.StencilSinkStore:residual_patch_template_spine(_producer)
        return Residual.StencilSpineStoreNRange1D
    end

    function Stencil.StencilSinkReduce:residual_patch_template_spine(_producer)
        return Residual.StencilSpineReduceNRange1D
    end

    function Stencil.StencilSinkScan:residual_patch_template_spine(_producer)
        return Residual.StencilSpineScanRange1D
    end

    function Stencil.StencilSinkScatterReduce:residual_patch_template_spine(_producer)
        return Residual.StencilSpineScatterReduceRange1D
    end

    function Stencil.StencilAccessLayout:residual_layout_shape()
        unsupported(self, "residual layout shape")
    end

    function Stencil.StencilLayoutScalar:residual_layout_shape()
        return Residual.StencilLayoutShapeScalar
    end

    function Stencil.StencilLayoutContiguous:residual_layout_shape()
        return Residual.StencilLayoutShapeContiguous
    end

    function Stencil.StencilLayoutIndexed:residual_layout_shape()
        return Residual.StencilLayoutShapeIndexed(self.parent:residual_layout_shape(), self.index_ty)
    end

    function Stencil.StencilLayoutAffine1D:residual_layout_shape()
        return Residual.StencilLayoutShapeAffine1D(self.parent:residual_layout_shape(), self.scale)
    end

    function Stencil.StencilLayoutAffineND:residual_layout_shape()
        return Residual.StencilLayoutShapeAffineND(self.parent:residual_layout_shape(), #(self.terms or {}))
    end

    function Stencil.StencilLayoutFieldProjection:residual_layout_shape()
        return Residual.StencilLayoutShapeFieldProjection(self.parent:residual_layout_shape(), self.record_ty, self.field_name)
    end

    function Stencil.StencilLayoutSoAComponent:residual_layout_shape()
        return Residual.StencilLayoutShapeSoAComponent(self.parent:residual_layout_shape(), self.record_ty, self.field_name)
    end

    function Stencil.StencilLayoutSliceDescriptor:residual_layout_shape()
        return Residual.StencilLayoutShapeSliceDescriptor
    end

    function Stencil.StencilLayoutByteSpanDescriptor:residual_layout_shape()
        return Residual.StencilLayoutShapeByteSpanDescriptor
    end

    function Stencil.StencilLayoutViewDescriptor:residual_layout_shape()
        return Residual.StencilLayoutShapeViewDescriptor
    end

    function Stencil.StencilPredicate:residual_predicate_shape()
        unsupported(self, "residual predicate shape")
    end

    function Stencil.StencilPredNonZero:residual_predicate_shape()
        return Residual.StencilPredShapeNonZero
    end

    function Stencil.StencilPredCompareConst:residual_predicate_shape()
        return Residual.StencilPredShapeCompareConst(self.cmp, self.operand_ty)
    end

    function Stencil.StencilPredRange:residual_predicate_shape()
        return Residual.StencilPredShapeRange(self.operand_ty, self.lower_cmp, self.upper_cmp)
    end

    function Stencil.StencilPredAnd:residual_predicate_shape()
        local terms = {}
        for i = 1, #(self.terms or {}) do terms[i] = self.terms[i]:residual_predicate_shape() end
        return Residual.StencilPredShapeAnd(terms)
    end

    function Stencil.StencilPredOr:residual_predicate_shape()
        local terms = {}
        for i = 1, #(self.terms or {}) do terms[i] = self.terms[i]:residual_predicate_shape() end
        return Residual.StencilPredShapeOr(terms)
    end

    function Stencil.StencilPredNot:residual_predicate_shape()
        return Residual.StencilPredShapeNot(self.term:residual_predicate_shape())
    end

    function Stencil.StencilPredIsNaN:residual_predicate_shape()
        return Residual.StencilPredShapeIsNaN(self.operand_ty)
    end

    function Stencil.StencilPredIsInf:residual_predicate_shape()
        return Residual.StencilPredShapeIsInf(self.operand_ty)
    end

    function Stencil.StencilPredIsFinite:residual_predicate_shape()
        return Residual.StencilPredShapeIsFinite(self.operand_ty)
    end

    function Stencil.StencilPointExpr:residual_point_shape()
        unsupported(self, "residual point expression shape")
    end

    function Stencil.StencilPointInput:residual_point_shape()
        return Residual.StencilPointShapeInput
    end

    function Stencil.StencilPointWindowInput:residual_point_shape()
        return Residual.StencilPointShapeWindowInput(#(self.offsets or {}))
    end

    function Stencil.StencilPointConst:residual_point_shape()
        return Residual.StencilPointShapeConst(self.ty)
    end

    function Stencil.StencilPointUnary:residual_point_shape()
        return Residual.StencilPointShapeUnary(self.op, self.arg:residual_point_shape(), self.result_ty)
    end

    function Stencil.StencilPointBinary:residual_point_shape()
        return Residual.StencilPointShapeBinary(self.op, self.left:residual_point_shape(), self.right:residual_point_shape(), self.result_ty)
    end

    function Stencil.StencilPointCast:residual_point_shape()
        return Residual.StencilPointShapeCast(self.op, self.arg:residual_point_shape(), self.from, self.to)
    end

    function Stencil.StencilPointPredicate:residual_point_shape()
        return Residual.StencilPointShapePredicate(self.pred:residual_predicate_shape(), self.arg:residual_point_shape(), self.result_ty)
    end

    function Stencil.StencilPointCompare:residual_point_shape()
        return Residual.StencilPointShapeCompare(self.cmp, self.left:residual_point_shape(), self.right:residual_point_shape(), self.result_ty)
    end

    function Stencil.StencilPointSelect:residual_point_shape()
        return Residual.StencilPointShapeSelect(
            self.pred:residual_predicate_shape(),
            self.cond:residual_point_shape(),
            self.then_expr:residual_point_shape(),
            self.else_expr:residual_point_shape(),
            self.result_ty
        )
    end

    function Stencil.StencilInstance:select_patch_template(input)
        return self.descriptor:project_patch_template(self, input)
    end

    function Stencil.StencilDescriptor:project_patch_template(instance, _input)
        local axes = {
            Residual.StencilTemplateProducer(self.producer),
            Residual.StencilTemplateSink(self.sink),
            Residual.StencilTemplateSchedule(instance.schedule),
            Residual.StencilTemplateAbi(instance.abi),
        }
        for _, proof in ipairs(instance.proofs or {}) do
            axes[#axes + 1] = Residual.StencilTemplateProof(proof)
        end
        for _, access in ipairs(self.accesses or {}) do
            axes[#axes + 1] = Residual.StencilTemplateAccessLayoutShape(access.layout:residual_layout_shape())
            axes[#axes + 1] = Residual.StencilTemplateScalarType(access.ty)
        end
        local body_axis = self.body:residual_patch_template_axis()
        if body_axis ~= nil then axes[#axes + 1] = body_axis end
        local family = Residual.StencilPatchTemplateFamily(self.sink:residual_patch_template_spine(self.producer), axes)
        return Residual.StencilPatchTemplateSelected(
            instance,
            family,
            self:residual_patch_template_coordinates(),
            instance.abi.params
        )
    end

    function Stencil.StencilBody:residual_patch_template_axis()
        return nil
    end

    function Stencil.StencilBodyPoint:residual_patch_template_axis()
        return Residual.StencilTemplatePointExprShape(self.expr:residual_point_shape())
    end

    function Stencil.StencilDescriptor:residual_patch_template_coordinates()
        local out = {}
        self.body:append_residual_patch_template_coordinates(out)
        for _, access in ipairs(self.accesses or {}) do
            access:append_residual_patch_template_coordinates(out)
        end
        return out
    end

    function Stencil.StencilBody:append_residual_patch_template_coordinates(_out)
    end

    function Stencil.StencilBodyPoint:append_residual_patch_template_coordinates(out)
        self.expr:append_residual_patch_template_coordinates(out)
    end

    function Stencil.StencilPointExpr:append_residual_patch_template_coordinates(_out)
    end

    function Stencil.StencilPointWindowInput:append_residual_patch_template_coordinates(out)
        for _, offset in ipairs(self.offsets or {}) do
            out[#out + 1] = Residual.StencilPatchCoordWindowOffset(offset.axis.index, offset.offset)
        end
    end

    function Stencil.StencilPointConst:append_residual_patch_template_coordinates(out)
        out[#out + 1] = Residual.StencilPatchCoordPointExprConst(self.value, self.ty)
    end

    function Stencil.StencilPointUnary:append_residual_patch_template_coordinates(out)
        self.arg:append_residual_patch_template_coordinates(out)
    end

    function Stencil.StencilPointBinary:append_residual_patch_template_coordinates(out)
        self.left:append_residual_patch_template_coordinates(out)
        self.right:append_residual_patch_template_coordinates(out)
    end

    function Stencil.StencilPointCast:append_residual_patch_template_coordinates(out)
        self.arg:append_residual_patch_template_coordinates(out)
    end

    function Stencil.StencilPointPredicate:append_residual_patch_template_coordinates(out)
        self.pred:append_residual_patch_template_coordinates(out)
        self.arg:append_residual_patch_template_coordinates(out)
    end

    function Stencil.StencilPointCompare:append_residual_patch_template_coordinates(out)
        self.left:append_residual_patch_template_coordinates(out)
        self.right:append_residual_patch_template_coordinates(out)
    end

    function Stencil.StencilPointSelect:append_residual_patch_template_coordinates(out)
        self.pred:append_residual_patch_template_coordinates(out)
        self.cond:append_residual_patch_template_coordinates(out)
        self.then_expr:append_residual_patch_template_coordinates(out)
        self.else_expr:append_residual_patch_template_coordinates(out)
    end

    function Stencil.StencilPredicate:append_residual_patch_template_coordinates(_out)
    end

    function Stencil.StencilPredCompareConst:append_residual_patch_template_coordinates(out)
        out[#out + 1] = Residual.StencilPatchCoordScalarConst(self.value, self.operand_ty)
    end

    function Stencil.StencilPredRange:append_residual_patch_template_coordinates(out)
        out[#out + 1] = Residual.StencilPatchCoordScalarConst(self.lower, self.operand_ty)
        out[#out + 1] = Residual.StencilPatchCoordScalarConst(self.upper, self.operand_ty)
    end

    function Stencil.StencilPredAnd:append_residual_patch_template_coordinates(out)
        for _, term in ipairs(self.terms or {}) do term:append_residual_patch_template_coordinates(out) end
    end

    function Stencil.StencilPredOr:append_residual_patch_template_coordinates(out)
        for _, term in ipairs(self.terms or {}) do term:append_residual_patch_template_coordinates(out) end
    end

    function Stencil.StencilPredNot:append_residual_patch_template_coordinates(out)
        self.term:append_residual_patch_template_coordinates(out)
    end

    function Stencil.StencilAccess:append_residual_patch_template_coordinates(out)
        self.layout:append_residual_patch_template_coordinates(out, self)
    end

    function Stencil.StencilAccessLayout:append_residual_patch_template_coordinates(_out)
    end

    function Stencil.StencilLayoutScalar:append_residual_patch_template_coordinates(out, access)
        if self.value ~= nil then out[#out + 1] = Residual.StencilPatchCoordScalarConst(self.value, access.ty) end
    end

    function Stencil.StencilLayoutContiguous:append_residual_patch_template_coordinates(out)
        if self.stride ~= 1 then out[#out + 1] = Residual.StencilPatchCoordStride(self.stride) end
    end

    function Stencil.StencilLayoutIndexed:append_residual_patch_template_coordinates(out)
        self.parent:append_residual_patch_template_coordinates(out)
        if self.stride ~= 1 then out[#out + 1] = Residual.StencilPatchCoordStride(self.stride) end
    end

    function Stencil.StencilLayoutAffine1D:append_residual_patch_template_coordinates(out)
        self.parent:append_residual_patch_template_coordinates(out)
        if self.offset ~= nil then out[#out + 1] = Residual.StencilPatchCoordAffineOffset(self.offset) end
    end

    function Stencil.StencilLayoutAffineND:append_residual_patch_template_coordinates(out)
        self.parent:append_residual_patch_template_coordinates(out)
        for _, term in ipairs(self.terms or {}) do
            out[#out + 1] = Residual.StencilPatchCoordAffineTerm(term.axis.index, term.coeff)
        end
        if self.offset ~= nil then out[#out + 1] = Residual.StencilPatchCoordAffineOffset(self.offset) end
    end

    function Stencil.StencilLayoutFieldProjection:append_residual_patch_template_coordinates(out)
        self.parent:append_residual_patch_template_coordinates(out)
        out[#out + 1] = Residual.StencilPatchCoordFieldOffset(self.field_name, self.field_offset)
    end

    function Stencil.StencilLayoutSoAComponent:append_residual_patch_template_coordinates(out)
        self.parent:append_residual_patch_template_coordinates(out)
        out[#out + 1] = Residual.StencilPatchCoordComponentIndex(self.field_name, self.component_index)
    end

    function Stencil.StencilLayoutViewDescriptor:append_residual_patch_template_coordinates(out)
        if self.stride_const ~= nil then out[#out + 1] = Residual.StencilPatchCoordStride(self.stride_const) end
    end

    function LJ.LJMachineStencilCall:residual_native_c_unit(func, sig, request)
        local storage = self.artifact:select_stencil_storage(request)
        local stencil, stencil_reason = storage:materialize_stencil()
        if stencil == nil then
            return nil, stencil_reason
        end
        local wrapper = native_c_name("fn", func.name)
        local ret = self:residual_native_result_c_type(sig)
        local params = {}
        for i = 1, #func.params do params[i] = func.params[i]:residual_native_c_param_decl() end
        local symbol = self.artifact.symbol.text
        local stencil_ret, stencil_params = c_signature_parts(symbol, self.artifact.c_signature)
        local call = self:residual_native_c_call_expr()
        local out = {
            stencil_ret .. " " .. symbol .. "(" .. stencil_params .. ");",
            "",
            ret .. " " .. wrapper .. "(" .. (#params > 0 and table.concat(params, ", ") or "void") .. ") {",
        }
        if ret == "void" then
            out[#out + 1] = "  " .. call .. ";"
        else
            out[#out + 1] = "  return " .. call .. ";"
        end
        out[#out + 1] = "}"
        local descriptor = Residual.CResidualFunctionDescriptor(
            func,
            wrapper,
            self:residual_native_wrapper_ctype(func, sig),
            {},
            { Residual.CResidualCallToStencil(stencil, self.args, self:residual_native_call_result(sig)) }
        )
        local unit = Residual.CResidualCUnit(
            table.concat(out, "\n"),
            { Residual.CResidualWrapper(func_name(func.name), wrapper, descriptor.wrapper_ctype) },
            { Residual.CResidualHostSymbol(symbol, stencil) }
        )
        return descriptor, unit
    end

    function LJ.LJMachineStencilEffect:residual_native_c_unit(func, sig, request)
        return LJ.LJMachineStencilCall.residual_native_c_unit(self, func, sig, request)
    end

    function LJ.LJMachineStencilCall:select_residual_machine_terminal(func, sig, request)
        local descriptor, unit_or_reason = self:residual_native_c_unit(func, sig, request)
        if descriptor == nil then
            return Residual.ResidualFunctionRejected(func, unit_or_reason)
        end
        return Residual.ResidualFunctionC(func, descriptor, unit_or_reason)
    end

    function LJ.LJMachineStencilEffect:select_residual_machine_terminal(func, sig, request)
        local descriptor, unit_or_reason = self:residual_native_c_unit(func, sig, request)
        if descriptor == nil then
            return Residual.ResidualFunctionRejected(func, unit_or_reason)
        end
        return Residual.ResidualFunctionC(func, descriptor, unit_or_reason)
    end

    function Residual.StencilPatchTemplateSelection:select_expansion_plan(_target, _template)
        return nil, reason("unsupported_patch_template_selection", "template selection leaf has no patch expansion plan")
    end

    function Residual.StencilPatchTemplateRejected:select_expansion_plan(_target, _template)
        return nil, self.reason
    end

    function Residual.StencilPatchTemplateSelected:select_expansion_plan(target, template)
        if template == nil then
            return nil, reason("missing_patch_template", "patch-template stencil requires a typed patch template")
        end
        if template.family ~= self.family then
            return nil, reason("patch_template_family_mismatch", "patch template family does not match template selection family")
        end
        local bindings = {}
        for i = 1, #self.coordinates do
            local hole = template.holes[i]
            if hole == nil then
                return nil, reason("missing_patch_hole", "patch template has fewer holes than coordinates")
            end
            bindings[#bindings + 1] = Residual.StencilPatchBinding(hole, self.coordinates[i])
        end
        return Residual.StencilPatchExpansionPlan(self.instance.descriptor, self.family, template, bindings, target)
    end

    local function make_patch_copy(plan, opts)
        opts = opts or {}
        if not cdef_patch_runtime() then
            return nil, reason("ffi_unavailable", "LuaJIT ffi could not define copy-patch runtime C ABI")
        end
        local ffi = require("ffi")
        local bit = require("bit")
        local bytes = plan.template.code_blob
        local size = #bytes
        local install = opts.install or {}
        local low32 = install.low32 == true
        if low32 and not (ffi.os == "Linux" and ffi.arch == "x64") then
            return nil, reason("low32_unsupported", "low32 patch template installation requires Linux/x64")
        end
        local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4
        local MAP_PRIVATE, MAP_ANON, MAP_32BIT = 2, 32, 64
        local MAP_FAILED = ffi.cast("void *", -1)
        local prot = install.rwx and bit.bor(PROT_READ, PROT_WRITE, PROT_EXEC) or bit.bor(PROT_READ, PROT_WRITE)
        local flags = bit.bor(MAP_PRIVATE, MAP_ANON, low32 and MAP_32BIT or 0)
        local mem = ffi.C.mmap(nil, size, prot, flags, -1, 0)
        if mem == MAP_FAILED then return nil, reason("mmap_failed", "mmap failed while installing patch template") end
        ffi.copy(mem, bytes, size)
        local base = ffi.cast("uint8_t *", mem)
        local base_addr = tonumber(ffi.cast("uintptr_t", mem))
        if low32 and base_addr + size - 1 > 2147483647 then
            return nil, reason("low32_out_of_range", "low32 patch template installation returned out-of-range address")
        end
        local copy = {
            plan = plan,
            target = plan.target,
            mem = mem,
            base = base,
            base_addr = base_addr,
            size = size,
            symbols = opts.symbols or {},
            rwx = install.rwx == true,
            runtime_little = ffi.abi("le"),
        }

        function copy:check_range(offset, width)
            offset = tonumber(offset)
            width = tonumber(width)
            if offset == nil or width == nil or offset < 0 or width < 0 or offset + width > self.size then
                return nil, reason("patch_out_of_bounds", "patch write is outside template code blob")
            end
            return true
        end

        function copy:symbol_address(symbol)
            local text = symbol and symbol.text
            if text == nil then return nil, reason("patch_missing_symbol", "patch coordinate has no symbol") end
            if text == self.plan.template.symbol.text then return self.base_addr end
            local value = self.symbols[text]
            if value == nil then return nil, reason("patch_unknown_symbol", "missing patch symbol address " .. tostring(text)) end
            if type(value) == "number" then return value end
            return value
        end

        function copy:address_number(value)
            if type(value) == "number" then return value end
            return tonumber(ffi.cast("uintptr_t", value))
        end

        function copy:write_integer(offset, bits, signed, endian, value)
            bits = tonumber(bits)
            local width = bits and (bits / 8) or nil
            local range_ok, range_reason = self:check_range(offset, width)
            if not range_ok then return nil, range_reason end
            local normalized, normalize_reason = normalize_int(value, bits, signed)
            if normalized == nil then return nil, normalize_reason end
            local little, endian_reason = endian:patch_little_endian(self)
            if little == nil then return nil, endian_reason end
            local bytes_out = {}
            for i = 1, width do
                bytes_out[i] = normalized % 256
                normalized = math.floor(normalized / 256)
            end
            for i = 1, width do
                local b = little and bytes_out[i] or bytes_out[width - i + 1]
                self.base[offset + i - 1] = b
            end
            return true
        end

        function copy:write_pointer(offset, bits, endian, value)
            bits = tonumber(bits)
            local width = bits and (bits / 8) or nil
            local range_ok, range_reason = self:check_range(offset, width)
            if not range_ok then return nil, range_reason end
            local little, endian_reason = endian:patch_little_endian(self)
            if little == nil then return nil, endian_reason end
            if type(value) == "number" then
                return self:write_integer(offset, bits, false, endian, value)
            end
            if little ~= self.runtime_little then
                return nil, reason("patch_pointer_endian_mismatch", "cdata pointer patching requires target endian to match runtime endian")
            end
            if bits == 64 then
                ffi.cast("uint64_t *", self.base + offset)[0] = ffi.cast("uint64_t", ffi.cast("uintptr_t", value))
                return true
            end
            if bits == 32 then
                ffi.cast("uint32_t *", self.base + offset)[0] = ffi.cast("uint32_t", ffi.cast("uintptr_t", value))
                return true
            end
            return nil, reason("patch_bad_pointer_width", "unsupported pointer patch width " .. tostring(bits))
        end

        function copy:seal()
            if self.rwx then return true end
            local ok = ffi.C.mprotect(self.mem, self.size, bit.bor(PROT_READ, PROT_EXEC))
            if ok ~= 0 then return nil, reason("mprotect_failed", "mprotect failed while sealing patch template") end
            return true
        end

        function copy:installed(materialized)
            return installed_patch_stencil(materialized, self.mem, self.base, self.size, ffi.cast(self.plan.template.c_signature, self.mem))
        end

        return copy
    end

    function Residual.StencilPatchExpansionPlan:materialize_stencil()
        return Residual.MaterializedPatchedStencil(self.descriptor, self.family, self.template.symbol, self.template.c_signature)
    end

    function Residual.StencilPatchExpansionPlan:install_patched_stencil(opts)
        local copy, copy_reason = make_patch_copy(self, opts)
        if copy == nil then return nil, copy_reason end
        for _, binding in ipairs(self.bindings or {}) do
            local ok, patch_reason = binding:apply_patch(copy)
            if not ok then return nil, patch_reason end
        end
        local seal_ok, seal_reason = copy:seal()
        if not seal_ok then return nil, seal_reason end
        return copy:installed(self:materialize_stencil())
    end

    function Residual.CResidualCUnit:compile_with_tcc_request()
        return Residual.CResidualCompileRequest(self, { "m" })
    end

    function LJ.LJModule:select_residual_luajit_module(request)
        local functions = {}
        local c_units = {}
        for _, func in ipairs(self.funcs or {}) do
            local plan = func:select_residual_function(request)
            functions[#functions + 1] = plan
            plan:append_residual_c_units(c_units)
        end
        return Residual.ResidualModulePlan(request, functions, c_units)
    end

    function Residual.ResidualFunctionPlan:append_residual_c_units(_out)
    end

    function Residual.ResidualFunctionC:append_residual_c_units(out)
        out[#out + 1] = self.unit
    end

    function api.select_luajit_module(module, opts)
        opts = opts or {}
        local target = opts.target or Residual.ResidualTargetNativeTcc
        local storage = opts.storage or Residual.ResidualStorageAllowExactOrPatchTemplate
        local request = Residual.ResidualLuaJITModuleRequest(module, target, storage)
        return module:select_residual_luajit_module(request)
    end

    api.reason = reason
    api.sanitize = sanitize
    api.func_name = func_name

    T._lalin_api_cache.residual_native = api
    return api
end

return bind_context
