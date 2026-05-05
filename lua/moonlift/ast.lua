---Moonlift source AST constructor facade.
---
---This module is the hosted-Lua language surface for constructing Moonlift
---programs as ASDL values.  Every public constructor below returns a plain
---Moon* ASDL node from the supplied context; there are no wrapper objects,
---hidden compiler contexts, string tags, or phase-side caches.
---
---Usage with an existing compiler context:
---```lua
---local pvm = require("moonlift.pvm")
---local schema = require("moonlift.asdl")
---local ast = require("moonlift.ast")
---local T = pvm.context(); schema.Define(T)
---local m = ast.new(T).module { ... }
---```
---
---For standalone generation, `require("moonlift.ast")` is itself a default
---API bound to a fresh Moonlift ASDL context.  Compiler pipelines that already
---own a context should prefer `ast.new(T)` so all nodes share the same ASDL
---universe.

local pvm = require("moonlift.pvm")
local schema = require("moonlift.asdl")

local M = {}

---@alias moonlift.ast.Type MoonType.Type
---@alias moonlift.ast.Expr MoonTree.Expr
---@alias moonlift.ast.Place MoonTree.Place
---@alias moonlift.ast.Stmt MoonTree.Stmt
---@alias moonlift.ast.Item MoonTree.Item
---@alias moonlift.ast.Func MoonTree.Func
---@alias moonlift.ast.Module MoonTree.Module
---@alias moonlift.ast.FieldInit MoonTree.FieldInit
---@alias moonlift.ast.FuncContract MoonTree.FuncContract
---@alias moonlift.ast.TypeDecl MoonTree.TypeDecl
---@alias moonlift.ast.View MoonTree.View
---@alias moonlift.ast.Domain MoonTree.Domain

---@class moonlift.ast.ParamSpec
---@field name string User-authored parameter name.
---@field ty moonlift.ast.Type User-authored parameter type. Inferred types do not live here.

---@class moonlift.ast.FieldSpec
---@field name string User-authored field name.
---@field ty moonlift.ast.Type User-authored field type.

---@class moonlift.ast.VariantSpec
---@field name string User-authored variant name.
---@field payload moonlift.ast.Type Payload type for tagged-union sugar.

---@class moonlift.ast.FuncSpec
---@field name string Function name in the enclosing module.
---@field params MoonType.Param[] Ordered user-authored parameters.
---@field ret moonlift.ast.Type? Optional result type. Defaults to `void`.
---@field result moonlift.ast.Type? Alias for `ret`.
---@field contracts moonlift.ast.FuncContract[]? Source `requires` contracts.
---@field body moonlift.ast.Stmt[] Function body statements.

---@class moonlift.ast.ExternFuncSpec
---@field name string Source name of the extern function.
---@field symbol string? Linker/host symbol. Defaults to `name`.
---@field params MoonType.Param[] Ordered parameters.
---@field ret moonlift.ast.Type? Optional result type. Defaults to `void`.
---@field result moonlift.ast.Type? Alias for `ret`.

---@class moonlift.ast.ConstSpec
---@field name string Constant name.
---@field ty moonlift.ast.Type Constant type annotation.
---@field value moonlift.ast.Expr Constant expression.

---@class moonlift.ast.StaticSpec
---@field name string Static name.
---@field ty moonlift.ast.Type Static type annotation.
---@field value moonlift.ast.Expr Static initializer expression.

---@class moonlift.ast.ModuleSpec
---@field items moonlift.ast.Item[]? Module item list. Positional entries are also accepted.
---@field name string? Optional module name for typed/semantic module headers only.
---@field h MoonTree.ModuleHeader? Explicit module header. Defaults to `ModuleSurface`.

local scalar_names = {
    void = "ScalarVoid", bool = "ScalarBool",
    i8 = "ScalarI8", i16 = "ScalarI16", i32 = "ScalarI32", i64 = "ScalarI64",
    u8 = "ScalarU8", u16 = "ScalarU16", u32 = "ScalarU32", u64 = "ScalarU64",
    f32 = "ScalarF32", f64 = "ScalarF64", rawptr = "ScalarRawPtr", index = "ScalarIndex",
}

local unary_ops = { neg = "UnaryNeg", ["-"] = "UnaryNeg", not_ = "UnaryNot", ["not"] = "UnaryNot", bitnot = "UnaryBitNot", ["~"] = "UnaryBitNot" }
local binary_ops = {
    add = "BinAdd", ["+"] = "BinAdd", sub = "BinSub", ["-"] = "BinSub", mul = "BinMul", ["*"] = "BinMul", div = "BinDiv", ["/"] = "BinDiv", rem = "BinRem", ["%"] = "BinRem",
    band = "BinBitAnd", ["&"] = "BinBitAnd", bor = "BinBitOr", ["|"] = "BinBitOr", bxor = "BinBitXor", ["^"] = "BinBitXor",
    shl = "BinShl", lshr = "BinLShr", ashr = "BinAShr",
}
local cmp_ops = { eq = "CmpEq", ["=="] = "CmpEq", ne = "CmpNe", ["~="] = "CmpNe", lt = "CmpLt", ["<"] = "CmpLt", le = "CmpLe", ["<="] = "CmpLe", gt = "CmpGt", [">"] = "CmpGt", ge = "CmpGe", [">="] = "CmpGe" }
local logic_ops = { and_ = "LogicAnd", ["and"] = "LogicAnd", or_ = "LogicOr", ["or"] = "LogicOr" }
local intrinsic_ops = {
    popcount = "IntrinsicPopcount", clz = "IntrinsicClz", ctz = "IntrinsicCtz", rotl = "IntrinsicRotl", rotr = "IntrinsicRotr", bswap = "IntrinsicBswap",
    fma = "IntrinsicFma", sqrt = "IntrinsicSqrt", abs = "IntrinsicAbs", floor = "IntrinsicFloor", ceil = "IntrinsicCeil", trunc_float = "IntrinsicTruncFloat", round = "IntrinsicRound",
    trap = "IntrinsicTrap", assume = "IntrinsicAssume",
}
local cast_ops = {
    surface = "SurfaceCast", cast = "SurfaceCast", as = "SurfaceCast",
    trunc = "SurfaceTrunc", zext = "SurfaceZExt", sext = "SurfaceSExt", bitcast = "SurfaceBitcast", satcast = "SurfaceSatCast",
}

local function assert_name(name, site)
    assert(type(name) == "string" and name:match("^[_%a][_%w]*$"), site .. " expects an identifier")
    return name
end

local function array(v, site)
    if v == nil then return {} end
    assert(type(v) == "table", site .. " expects an array")
    return v
end

local function positional_or_named(a, b, first_name, second_name)
    if type(a) == "table" and b == nil and (a[first_name] ~= nil or a[second_name] ~= nil or a[1] ~= nil) then
        return a
    end
    return { [first_name] = a, [second_name] = b, [1] = a, [2] = b }
end

local function copy_array(src)
    local out = {}
    for i = 1, #(src or {}) do out[i] = src[i] end
    return out
end

local function install(api, T)
    local C, Ty, B, Sem, Tr = T.MoonCore, T.MoonType, T.MoonBind, T.MoonSem, T.MoonTree

    api.T = T
    api.raw = T
    api.builders = T:Builders()
    api.fast_builders = T:FastBuilders()

    local function is_a(cls, v)
        return type(cls) == "table" and cls.isclassof and cls:isclassof(v) or false
    end

    local function as_type(v, site)
        assert(is_a(Ty.Type, v), (site or "expected Moonlift type") .. ": got " .. type(v))
        return v
    end

    local function as_expr(v, site)
        if type(v) == "number" then return api.int(v) end
        if type(v) == "boolean" then return api.bool_lit(v) end
        assert(is_a(Tr.Expr, v), (site or "expected Moonlift expression") .. ": got " .. type(v))
        return v
    end

    local function as_place(v, site)
        assert(is_a(Tr.Place, v), (site or "expected Moonlift place") .. ": got " .. type(v))
        return v
    end

    local function as_value_ref(v, site)
        if type(v) == "string" then return B.ValueRefName(assert_name(v, site or "value ref")) end
        assert(is_a(B.ValueRef, v), (site or "expected value ref") .. ": got " .. type(v))
        return v
    end

    local function as_path(v, site)
        if type(v) == "string" then
            local parts = {}
            for part in v:gmatch("[^%.]+") do parts[#parts + 1] = C.Name(assert_name(part, site or "path")) end
            return C.Path(parts)
        end
        if pvm.classof(v) == C.Path then return v end
        local parts = {}
        for i = 1, #array(v, site or "path") do parts[i] = C.Name(assert_name(v[i], site or "path")) end
        return C.Path(parts)
    end

    local function exprs(xs, site)
        local out = {}
        for i = 1, #array(xs, site) do out[i] = as_expr(xs[i], site .. " expression") end
        return out
    end

    local function stmts(xs, site)
        local out = {}
        for i = 1, #array(xs, site) do
            assert(is_a(Tr.Stmt, xs[i]), (site or "statements") .. " expects statement at index " .. i)
            out[i] = xs[i]
        end
        return out
    end

    local function items(xs, site)
        local out = {}
        for i = 1, #array(xs, site) do out[i] = api.item(xs[i]) end
        return out
    end

    local function type_or_void(v)
        if v == nil then return Ty.TScalar(C.ScalarVoid) end
        return as_type(v, "result type")
    end

    local function binding(name, ty, class, id)
        name = assert_name(name, "binding")
        ty = as_type(ty, "binding type")
        return B.Binding(C.Id(id or ("local:" .. name)), name, ty, class or B.BindingClassLocalValue)
    end

    -- Core atoms -----------------------------------------------------------

    ---Create a source identifier atom.
    ---@param text string Identifier text.
    ---@return MoonCore.Name
    function api.core_name(text) return C.Name(assert_name(text, "core_name")) end

    ---Create a dotted source path.
    ---@param parts string|string[] Either `"a.b"` or `{ "a", "b" }`.
    ---@return MoonCore.Path
    function api.path(parts) return as_path(parts, "path") end

    ---Create a source id atom.  Use this only when constructing explicit bindings.
    ---@param text string Stable id text.
    ---@return MoonCore.Id
    function api.id(text) assert(type(text) == "string", "id expects a string"); return C.Id(text) end

    -- Type nodes -----------------------------------------------------------

    ---Create a scalar type node.
    ---@param name string One of: void,bool,i8,i16,i32,i64,u8,u16,u32,u64,f32,f64,index,rawptr.
    ---@return moonlift.ast.Type
    function api.scalar(name)
        local ctor = assert(scalar_names[name], "unknown scalar type: " .. tostring(name))
        return Ty.TScalar(C[ctor])
    end

    ---Void type. User-authored as `void` or omitted function result.
    ---@return moonlift.ast.Type
    function api.void() return Ty.TScalar(C.ScalarVoid) end
    ---Boolean type.
    ---@return moonlift.ast.Type
    function api.bool() return Ty.TScalar(C.ScalarBool) end
    ---Signed 8-bit integer type.
    ---@return moonlift.ast.Type
    function api.i8() return Ty.TScalar(C.ScalarI8) end
    ---Signed 16-bit integer type.
    ---@return moonlift.ast.Type
    function api.i16() return Ty.TScalar(C.ScalarI16) end
    ---Signed 32-bit integer type.
    ---@return moonlift.ast.Type
    function api.i32() return Ty.TScalar(C.ScalarI32) end
    ---Signed 64-bit integer type.
    ---@return moonlift.ast.Type
    function api.i64() return Ty.TScalar(C.ScalarI64) end
    ---Unsigned 8-bit integer type.
    ---@return moonlift.ast.Type
    function api.u8() return Ty.TScalar(C.ScalarU8) end
    ---Unsigned 16-bit integer type.
    ---@return moonlift.ast.Type
    function api.u16() return Ty.TScalar(C.ScalarU16) end
    ---Unsigned 32-bit integer type.
    ---@return moonlift.ast.Type
    function api.u32() return Ty.TScalar(C.ScalarU32) end
    ---Unsigned 64-bit integer type.
    ---@return moonlift.ast.Type
    function api.u64() return Ty.TScalar(C.ScalarU64) end
    ---32-bit float type.
    ---@return moonlift.ast.Type
    function api.f32() return Ty.TScalar(C.ScalarF32) end
    ---64-bit float type.
    ---@return moonlift.ast.Type
    function api.f64() return Ty.TScalar(C.ScalarF64) end
    ---Machine index type.
    ---@return moonlift.ast.Type
    function api.index() return Ty.TScalar(C.ScalarIndex) end
    ---Raw pointer scalar type. Prefer `ptr(elem)` for typed source pointers.
    ---@return moonlift.ast.Type
    function api.rawptr() return Ty.TScalar(C.ScalarRawPtr) end

    ---Pointer type.
    ---@param elem moonlift.ast.Type Pointee type.
    ---@return moonlift.ast.Type
    function api.ptr(elem) return Ty.TPtr(as_type(elem, "ptr element type")) end

    ---Array type.
    ---@param count number|MoonTree.Expr|MoonOpen.ExprSlot Constant count, source length expression, or open length slot.
    ---@param elem moonlift.ast.Type Element type.
    ---@return moonlift.ast.Type
    function api.array(count, elem)
        local c
        if type(count) == "number" then c = Ty.ArrayLenConst(count)
        elseif is_a(Tr.Expr, count) then c = Ty.ArrayLenExpr(count)
        else c = Ty.ArrayLenSlot(count) end
        return Ty.TArray(c, as_type(elem, "array element type"))
    end

    ---Slice type.
    ---@param elem moonlift.ast.Type Element type.
    ---@return moonlift.ast.Type
    function api.slice(elem) return Ty.TSlice(as_type(elem, "slice element type")) end

    ---Moonlift semantic view type.
    ---@param elem moonlift.ast.Type Element type.
    ---@return moonlift.ast.Type
    function api.view_type(elem) return Ty.TView(as_type(elem, "view element type")) end
    api.view_t = api.view_type
    api.view = api.view_type

    ---Function type.
    ---@param params moonlift.ast.Type[] Parameter types.
    ---@param result moonlift.ast.Type Result type.
    ---@return moonlift.ast.Type
    function api.fn_type(params, result)
        local out = {}
        for i = 1, #array(params, "fn_type params") do out[i] = as_type(params[i], "fn_type param") end
        return Ty.TFunc(out, as_type(result, "fn_type result"))
    end

    ---Closure type.
    ---@param params moonlift.ast.Type[] Parameter types.
    ---@param result moonlift.ast.Type Result type.
    ---@return moonlift.ast.Type
    function api.closure_type(params, result)
        local out = {}
        for i = 1, #array(params, "closure_type params") do out[i] = as_type(params[i], "closure_type param") end
        return Ty.TClosure(out, as_type(result, "closure_type result"))
    end

    ---Named type reference.
    ---@param name string|string[] Dotted path or path parts.
    ---@return moonlift.ast.Type
    function api.named(name) return Ty.TNamed(Ty.TypeRefPath(as_path(name, "named type"))) end

    ---Function/type parameter declaration.
    ---@param spec moonlift.ast.ParamSpec|string Parameter table or name.
    ---@param ty moonlift.ast.Type? Type when first argument is a name.
    ---@return MoonType.Param
    function api.param(spec, ty)
        if type(spec) == "table" and ty == nil then return Ty.Param(assert_name(spec.name, "param"), as_type(spec.ty or spec.type, "param type")) end
        return Ty.Param(assert_name(spec, "param"), as_type(ty, "param type"))
    end

    ---Struct/union field declaration.
    ---@param spec moonlift.ast.FieldSpec|string Field table or name.
    ---@param ty moonlift.ast.Type? Field type when first argument is a name.
    ---@return MoonType.FieldDecl
    function api.field_decl(spec, ty)
        if type(spec) == "table" and ty == nil then return Ty.FieldDecl(assert_name(spec.name or spec.field_name, "field_decl"), as_type(spec.ty or spec.type, "field_decl type")) end
        return Ty.FieldDecl(assert_name(spec, "field_decl"), as_type(ty, "field_decl type"))
    end

    ---Tagged-union variant declaration.
    ---@param spec moonlift.ast.VariantSpec|string Variant table or name.
    ---@param payload moonlift.ast.Type? Payload type when first argument is a name.
    ---@return MoonType.VariantDecl
    function api.variant_decl(spec, payload)
        if type(spec) == "table" and payload == nil then return Ty.VariantDecl(assert_name(spec.name, "variant_decl"), as_type(spec.payload, "variant payload type")) end
        return Ty.VariantDecl(assert_name(spec, "variant_decl"), as_type(payload, "variant payload type"))
    end

    -- Binding and reference nodes -----------------------------------------

    ---Create an explicit local binding value. Most users should call `let`/`var`.
    ---@param name string Source binding name.
    ---@param ty moonlift.ast.Type User-authored binding type.
    ---@param id_text string? Stable id. Defaults to `local:<name>`.
    ---@return MoonBind.Binding
    function api.binding(name, ty, id_text) return binding(name, ty, B.BindingClassLocalValue, id_text) end

    ---Create an explicit mutable-cell binding value. Most users should call `var`.
    ---@param name string Source binding name.
    ---@param ty moonlift.ast.Type User-authored binding type.
    ---@param id_text string? Stable id. Defaults to `local:<name>`.
    ---@return MoonBind.Binding
    function api.cell_binding(name, ty, id_text) return binding(name, ty, B.BindingClassLocalCell, id_text) end

    ---Create a value reference by source name, dotted path, or explicit binding.
    ---@param v string|string[]|MoonBind.Binding|MoonBind.ValueRef Reference subject.
    ---@return MoonBind.ValueRef
    function api.value_ref(v)
        if type(v) == "table" and pvm.classof(v) == B.Binding then return B.ValueRefBinding(v) end
        if type(v) == "table" and pvm.classof(v) == C.Path then return B.ValueRefPath(v) end
        if type(v) == "table" and not pvm.classof(v) then return B.ValueRefPath(as_path(v, "value_ref path")) end
        if type(v) == "string" and v:find("%.") then return B.ValueRefPath(as_path(v, "value_ref path")) end
        return as_value_ref(v, "value_ref")
    end

    -- Literal and expression nodes ----------------------------------------

    ---Integer literal expression. Numeric meaning is decided by later type phases.
    ---@param raw string|number Raw source spelling.
    ---@return moonlift.ast.Expr
    function api.int(raw) return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(raw))) end

    ---Float literal expression. Numeric meaning is decided by later type phases.
    ---@param raw string|number Raw source spelling.
    ---@return moonlift.ast.Expr
    function api.float(raw) return Tr.ExprLit(Tr.ExprSurface, C.LitFloat(tostring(raw))) end

    ---Boolean literal expression.
    ---@param value boolean Lua boolean value.
    ---@return moonlift.ast.Expr
    function api.bool_lit(value) return Tr.ExprLit(Tr.ExprSurface, C.LitBool(value and true or false)) end

    ---C string literal expression. The supplied Lua string is stored as bytes and
    ---lowered to a NUL-terminated static `ptr(u8)` object.
    ---@param bytes string Decoded string bytes, without the trailing NUL.
    ---@return moonlift.ast.Expr
    function api.string_lit(bytes) return Tr.ExprLit(Tr.ExprSurface, C.LitString(bytes)) end

    ---Nil literal expression.
    ---@return moonlift.ast.Expr
    function api.nil_lit() return Tr.ExprLit(Tr.ExprSurface, C.LitNil) end

    ---Reference expression. This is the source-level `name` expression.
    ---@param v string|string[]|MoonBind.Binding|MoonBind.ValueRef Reference subject.
    ---@return moonlift.ast.Expr
    function api.name(v) return Tr.ExprRef(Tr.ExprSurface, api.value_ref(v)) end
    api.ref = api.name

    ---Dot projection expression before field/layout resolution.
    ---@param base moonlift.ast.Expr Base expression.
    ---@param name string Field/member name.
    ---@return moonlift.ast.Expr
    function api.dot(base, name) return Tr.ExprDot(Tr.ExprSurface, as_expr(base, "dot base"), assert_name(name, "dot")) end

    ---Unary expression.
    ---@param op string Operator name or spelling: neg,-,not,bitnot,~.
    ---@param value moonlift.ast.Expr Operand.
    ---@return moonlift.ast.Expr
    function api.unary(op, value) return Tr.ExprUnary(Tr.ExprSurface, C[assert(unary_ops[op], "unknown unary op: " .. tostring(op))], as_expr(value, "unary value")) end

    ---Binary expression.
    ---@param spec table Table with `op,lhs,rhs` or positional `{ lhs, rhs, op = "+" }`.
    ---@return moonlift.ast.Expr
    function api.binary(spec)
        local op = spec.op or spec[3]
        return Tr.ExprBinary(Tr.ExprSurface, C[assert(binary_ops[op], "unknown binary op: " .. tostring(op))], as_expr(spec.lhs or spec[1], "binary lhs"), as_expr(spec.rhs or spec[2], "binary rhs"))
    end

    local function binary_fn(op)
        return function(a, b)
            local t = positional_or_named(a, b, "lhs", "rhs"); t.op = op
            return api.binary(t)
        end
    end

    ---Addition expression.
    ---@param lhs moonlift.ast.Expr|number Left operand.
    ---@param rhs moonlift.ast.Expr|number Right operand.
    ---@return moonlift.ast.Expr
    api.add = binary_fn("add")
    ---Subtraction expression.
    ---@param lhs moonlift.ast.Expr|number Left operand.
    ---@param rhs moonlift.ast.Expr|number Right operand.
    ---@return moonlift.ast.Expr
    api.sub = binary_fn("sub")
    ---Multiplication expression.
    ---@param lhs moonlift.ast.Expr|number Left operand.
    ---@param rhs moonlift.ast.Expr|number Right operand.
    ---@return moonlift.ast.Expr
    api.mul = binary_fn("mul")
    ---Division expression.
    ---@param lhs moonlift.ast.Expr|number Left operand.
    ---@param rhs moonlift.ast.Expr|number Right operand.
    ---@return moonlift.ast.Expr
    api.div = binary_fn("div")
    ---Remainder expression.
    ---@param lhs moonlift.ast.Expr|number Left operand.
    ---@param rhs moonlift.ast.Expr|number Right operand.
    ---@return moonlift.ast.Expr
    api.rem = binary_fn("rem")
    ---Bitwise and expression.
    api.band = binary_fn("band")
    ---Bitwise or expression.
    api.bor = binary_fn("bor")
    ---Bitwise xor expression.
    api.bxor = binary_fn("bxor")
    ---Left shift expression.
    api.shl = binary_fn("shl")
    ---Logical right shift expression.
    api.lshr = binary_fn("lshr")
    ---Arithmetic right shift expression.
    api.ashr = binary_fn("ashr")

    ---Comparison expression.
    ---@param spec table Table with `op,lhs,rhs` or positional `{ lhs, rhs, op = "==" }`.
    ---@return moonlift.ast.Expr
    function api.compare(spec)
        local op = spec.op or spec[3]
        return Tr.ExprCompare(Tr.ExprSurface, C[assert(cmp_ops[op], "unknown compare op: " .. tostring(op))], as_expr(spec.lhs or spec[1], "compare lhs"), as_expr(spec.rhs or spec[2], "compare rhs"))
    end

    local function cmp_fn(op)
        return function(a, b)
            local t = positional_or_named(a, b, "lhs", "rhs"); t.op = op
            return api.compare(t)
        end
    end

    ---Equality comparison.
    api.eq = cmp_fn("eq")
    ---Inequality comparison.
    api.ne = cmp_fn("ne")
    ---Less-than comparison.
    api.lt = cmp_fn("lt")
    ---Less-or-equal comparison.
    api.le = cmp_fn("le")
    ---Greater-than comparison.
    api.gt = cmp_fn("gt")
    ---Greater-or-equal comparison.
    api.ge = cmp_fn("ge")

    ---Logical expression.
    ---@param op string `and`, `and_`, `or`, or `or_`.
    ---@param lhs moonlift.ast.Expr Left operand.
    ---@param rhs moonlift.ast.Expr Right operand.
    ---@return moonlift.ast.Expr
    function api.logic(op, lhs, rhs) return Tr.ExprLogic(Tr.ExprSurface, C[assert(logic_ops[op], "unknown logic op: " .. tostring(op))], as_expr(lhs, "logic lhs"), as_expr(rhs, "logic rhs")) end
    function api.and_(lhs, rhs) return api.logic("and", lhs, rhs) end
    function api.or_(lhs, rhs) return api.logic("or", lhs, rhs) end

    ---Source cast expression, equivalent to `as(type, expr)` by default.
    ---@param ty moonlift.ast.Type Target type.
    ---@param value moonlift.ast.Expr Source expression.
    ---@param op string? Cast op name: as, cast, trunc, zext, sext, bitcast, satcast.
    ---@return moonlift.ast.Expr
    function api.cast(ty, value, op) return Tr.ExprCast(Tr.ExprSurface, C[assert(cast_ops[op or "as"], "unknown cast op: " .. tostring(op))], as_type(ty, "cast type"), as_expr(value, "cast value")) end
    api.as = api.cast

    ---Intrinsic-call expression.
    ---@param name string Intrinsic name such as `popcount`, `sqrt`, or `assume`.
    ---@param args moonlift.ast.Expr[] Argument expressions.
    ---@return moonlift.ast.Expr
    function api.intrinsic(name, args)
        return Tr.ExprIntrinsic(Tr.ExprSurface, C[assert(intrinsic_ops[name], "unknown intrinsic: " .. tostring(name))], exprs(args or {}, "intrinsic args"))
    end

    ---Function call expression. The call target remains unresolved until semantic phases.
    ---@param callee moonlift.ast.Expr|string Callee expression or source name.
    ---@param args moonlift.ast.Expr[]? Argument expressions.
    ---@return moonlift.ast.Expr
    function api.call(callee, args)
        if type(callee) == "table" and args == nil and (callee.callee or callee.fn or callee[1]) then
            args = callee.args or callee[2]
            callee = callee.callee or callee.fn or callee[1]
        end
        if type(callee) == "string" then callee = api.name(callee) end
        return Tr.ExprCall(Tr.ExprSurface, Sem.CallUnresolved(as_expr(callee, "call callee")), exprs(args or {}, "call args"))
    end

    ---Length expression, currently used for `len(view)`.
    ---@param value moonlift.ast.Expr Subject expression.
    ---@return moonlift.ast.Expr
    function api.len(value) return Tr.ExprLen(Tr.ExprSurface, as_expr(value, "len value")) end

    ---Resolved field expression when the field type is already explicit.
    ---@param base moonlift.ast.Expr Base expression.
    ---@param name string Field name.
    ---@param ty moonlift.ast.Type Field type.
    ---@return moonlift.ast.Expr
    function api.field(base, name, ty) return Tr.ExprField(Tr.ExprSurface, as_expr(base, "field base"), Sem.FieldByName(assert_name(name, "field"), as_type(ty, "field type"))) end

    ---Index expression.
    ---@param base moonlift.ast.Expr|moonlift.ast.Place|moonlift.ast.View Base expression/place/view.
    ---@param index moonlift.ast.Expr|number Index expression.
    ---@return moonlift.ast.Expr
    function api.index_expr(base, index)
        local ib
        if is_a(Tr.Place, base) then ib = Tr.IndexBasePlace(base, Ty.TScalar(C.ScalarVoid))
        elseif is_a(Tr.View, base) then ib = Tr.IndexBaseView(base)
        else ib = Tr.IndexBaseExpr(as_expr(base, "index base")) end
        return Tr.ExprIndex(Tr.ExprSurface, ib, as_expr(index, "index value"))
    end
    api.index_at = api.index_expr

    ---Aggregate expression with named field initializers.
    ---@param ty moonlift.ast.Type Aggregate type.
    ---@param fields MoonTree.FieldInit[] Field initializers.
    ---@return moonlift.ast.Expr
    function api.agg(ty, fields) return Tr.ExprAgg(Tr.ExprSurface, as_type(ty, "aggregate type"), fields or {}) end

    ---Field initializer for aggregate expressions.
    ---@param name string Field name.
    ---@param value moonlift.ast.Expr Field value.
    ---@return moonlift.ast.FieldInit
    function api.field_init(name, value) return Tr.FieldInit(assert_name(name, "field_init"), as_expr(value, "field_init value")) end

    ---Array expression.
    ---@param elem_ty moonlift.ast.Type Element type.
    ---@param elems moonlift.ast.Expr[] Element expressions.
    ---@return moonlift.ast.Expr
    function api.array_expr(elem_ty, elems) return Tr.ExprArray(Tr.ExprSurface, as_type(elem_ty, "array element type"), exprs(elems or {}, "array elements")) end

    ---Conditional expression.
    ---@param cond moonlift.ast.Expr Condition.
    ---@param then_expr moonlift.ast.Expr Then expression.
    ---@param else_expr moonlift.ast.Expr Else expression.
    ---@return moonlift.ast.Expr
    function api.if_expr(cond, then_expr, else_expr) return Tr.ExprIf(Tr.ExprSurface, as_expr(cond, "if cond"), as_expr(then_expr, "if then"), as_expr(else_expr, "if else")) end

    ---Select expression.
    ---@param cond moonlift.ast.Expr Condition.
    ---@param then_expr moonlift.ast.Expr Then expression.
    ---@param else_expr moonlift.ast.Expr Else expression.
    ---@return moonlift.ast.Expr
    function api.select(cond, then_expr, else_expr) return Tr.ExprSelect(Tr.ExprSurface, as_expr(cond, "select cond"), as_expr(then_expr, "select then"), as_expr(else_expr, "select else")) end

    ---Expression block.
    ---@param body moonlift.ast.Stmt[] Statements executed before the result.
    ---@param result moonlift.ast.Expr Result expression.
    ---@return moonlift.ast.Expr
    function api.expr_block(body, result) return Tr.ExprBlock(Tr.ExprSurface, stmts(body or {}, "expr_block body"), as_expr(result, "expr_block result")) end

    ---Closure expression.
    ---@param params MoonType.Param[] Closure parameters.
    ---@param result moonlift.ast.Type Closure result type.
    ---@param body moonlift.ast.Stmt[] Closure body.
    ---@return moonlift.ast.Expr
    function api.closure(params, result, body) return Tr.ExprClosure(Tr.ExprSurface, params or {}, as_type(result, "closure result"), stmts(body or {}, "closure body")) end

    ---Address-of expression.
    ---@param place moonlift.ast.Place Place to address.
    ---@return moonlift.ast.Expr
    function api.addr_of(place) return Tr.ExprAddrOf(Tr.ExprSurface, as_place(place, "addr_of place")) end

    ---Deref expression.
    ---@param value moonlift.ast.Expr Pointer expression.
    ---@return moonlift.ast.Expr
    function api.deref(value) return Tr.ExprDeref(Tr.ExprSurface, as_expr(value, "deref value")) end

    ---Load expression from address.
    ---@param ty moonlift.ast.Type Loaded value type.
    ---@param addr moonlift.ast.Expr Address expression.
    ---@return moonlift.ast.Expr
    function api.load(ty, addr) return Tr.ExprLoad(Tr.ExprSurface, as_type(ty, "load type"), as_expr(addr, "load addr")) end

    -- View/domain nodes ----------------------------------------------------

    ---View node derived from an expression.
    ---@param base moonlift.ast.Expr Base view expression.
    ---@param elem moonlift.ast.Type Element type.
    ---@return moonlift.ast.View
    function api.view_from_expr(base, elem) return Tr.ViewFromExpr(as_expr(base, "view base"), as_type(elem, "view elem")) end

    ---Contiguous view node.
    ---@param data moonlift.ast.Expr Data pointer expression.
    ---@param elem moonlift.ast.Type Element type.
    ---@param len moonlift.ast.Expr|number Length expression.
    ---@return moonlift.ast.View
    function api.view_contiguous(data, elem, len) return Tr.ViewContiguous(as_expr(data, "view data"), as_type(elem, "view elem"), as_expr(len, "view len")) end

    ---Strided view node. Stride is in elements.
    ---@param data moonlift.ast.Expr Data pointer expression.
    ---@param elem moonlift.ast.Type Element type.
    ---@param len moonlift.ast.Expr|number Length expression.
    ---@param stride moonlift.ast.Expr|number Stride expression in elements.
    ---@return moonlift.ast.View
    function api.view_strided(data, elem, len, stride) return Tr.ViewStrided(as_expr(data, "view data"), as_type(elem, "view elem"), as_expr(len, "view len"), as_expr(stride, "view stride")) end

    ---Window view node.
    ---@param base moonlift.ast.View Base view.
    ---@param start moonlift.ast.Expr|number Start index.
    ---@param len moonlift.ast.Expr|number Window length.
    ---@return moonlift.ast.View
    function api.view_window(base, start, len) return Tr.ViewWindow(base, as_expr(start, "window start"), as_expr(len, "window len")) end

    ---View expression wrapping a view node.
    ---@param view moonlift.ast.View View node.
    ---@return moonlift.ast.Expr
    function api.view_expr(view) assert(is_a(Tr.View, view), "view_expr expects a view"); return Tr.ExprView(Tr.ExprSurface, view) end

    ---Range domain from zero to stop.
    ---@param stop moonlift.ast.Expr|number Stop expression.
    ---@return moonlift.ast.Domain
    function api.domain_range(stop) return Tr.DomainRange(as_expr(stop, "domain stop")) end

    ---Range domain from start to stop.
    ---@param start moonlift.ast.Expr|number Start expression.
    ---@param stop moonlift.ast.Expr|number Stop expression.
    ---@return moonlift.ast.Domain
    function api.domain_range2(start, stop) return Tr.DomainRange2(as_expr(start, "domain start"), as_expr(stop, "domain stop")) end

    ---Domain over a view.
    ---@param view moonlift.ast.View View node.
    ---@return moonlift.ast.Domain
    function api.domain_view(view) assert(is_a(Tr.View, view), "domain_view expects a view"); return Tr.DomainView(view) end

    -- Place nodes ----------------------------------------------------------

    ---Reference place.
    ---@param v string|MoonBind.Binding|MoonBind.ValueRef Reference subject.
    ---@return moonlift.ast.Place
    function api.place_ref(v) return Tr.PlaceRef(Tr.PlaceSurface, api.value_ref(v)) end

    ---Deref place.
    ---@param base moonlift.ast.Expr Pointer expression.
    ---@return moonlift.ast.Place
    function api.place_deref(base) return Tr.PlaceDeref(Tr.PlaceSurface, as_expr(base, "place_deref base")) end

    ---Dot place before field/layout resolution.
    ---@param base moonlift.ast.Place Base place.
    ---@param name string Field name.
    ---@return moonlift.ast.Place
    function api.place_dot(base, name) return Tr.PlaceDot(Tr.PlaceSurface, as_place(base, "place_dot base"), assert_name(name, "place_dot")) end

    ---Resolved field place when the field type is already explicit.
    ---@param base moonlift.ast.Place Base place.
    ---@param name string Field name.
    ---@param ty moonlift.ast.Type Field type.
    ---@return moonlift.ast.Place
    function api.place_field(base, name, ty) return Tr.PlaceField(Tr.PlaceSurface, as_place(base, "place_field base"), Sem.FieldByName(assert_name(name, "place_field"), as_type(ty, "place_field type"))) end

    ---Indexed place.
    ---@param base moonlift.ast.Expr|moonlift.ast.Place|moonlift.ast.View Base expression/place/view.
    ---@param index moonlift.ast.Expr|number Index expression.
    ---@return moonlift.ast.Place
    function api.place_index(base, index)
        local ib
        if is_a(Tr.Place, base) then ib = Tr.IndexBasePlace(base, Ty.TScalar(C.ScalarVoid))
        elseif is_a(Tr.View, base) then ib = Tr.IndexBaseView(base)
        else ib = Tr.IndexBaseExpr(as_expr(base, "place_index base")) end
        return Tr.PlaceIndex(Tr.PlaceSurface, ib, as_expr(index, "place_index index"))
    end

    -- Statement and control nodes -----------------------------------------

    ---Let statement. Creates a source local-value binding.
    ---@param spec table `{ name, ty, init }` or `{ binding, init }`.
    ---@return moonlift.ast.Stmt
    function api.let(spec)
        local bind = spec.binding or binding(spec.name, spec.ty or spec.type, B.BindingClassLocalValue, spec.id)
        return Tr.StmtLet(Tr.StmtSurface, bind, as_expr(spec.init or spec.value, "let init"))
    end

    ---Var statement. Creates a source mutable-cell binding.
    ---@param spec table `{ name, ty, init }` or `{ binding, init }`.
    ---@return moonlift.ast.Stmt
    function api.var(spec)
        local bind = spec.binding or binding(spec.name, spec.ty or spec.type, B.BindingClassLocalCell, spec.id)
        return Tr.StmtVar(Tr.StmtSurface, bind, as_expr(spec.init or spec.value, "var init"))
    end

    ---Assignment statement.
    ---@param place moonlift.ast.Place Assigned place.
    ---@param value moonlift.ast.Expr Assigned value.
    ---@return moonlift.ast.Stmt
    function api.set(place, value) return Tr.StmtSet(Tr.StmtSurface, as_place(place, "set place"), as_expr(value, "set value")) end

    ---Expression statement.
    ---@param expr moonlift.ast.Expr Expression to evaluate for effect.
    ---@return moonlift.ast.Stmt
    function api.expr_stmt(expr) return Tr.StmtExpr(Tr.StmtSurface, as_expr(expr, "expr_stmt expr")) end

    ---Assert statement.
    ---@param cond moonlift.ast.Expr Condition expression.
    ---@return moonlift.ast.Stmt
    function api.assert_(cond) return Tr.StmtAssert(Tr.StmtSurface, as_expr(cond, "assert cond")) end

    ---If statement.
    ---@param spec table `{ cond, then_body, else_body }`.
    ---@return moonlift.ast.Stmt
    function api.if_stmt(spec) return Tr.StmtIf(Tr.StmtSurface, as_expr(spec.cond or spec[1], "if cond"), stmts(spec.then_body or spec[2] or {}, "if then_body"), stmts(spec.else_body or spec[3] or {}, "if else_body")) end

    ---Jump argument for named block jumps.
    ---@param name string Target parameter name.
    ---@param value moonlift.ast.Expr Argument value.
    ---@return MoonTree.JumpArg
    function api.jump_arg(name, value) return Tr.JumpArg(assert_name(name, "jump_arg"), as_expr(value, "jump_arg value")) end

    ---Jump statement.
    ---@param target string|MoonTree.BlockLabel Target block label.
    ---@param args MoonTree.JumpArg[]? Named jump arguments.
    ---@return moonlift.ast.Stmt
    function api.jump(target, args)
        local label = pvm.classof(target) == Tr.BlockLabel and target or Tr.BlockLabel(assert_name(target, "jump target"))
        return Tr.StmtJump(Tr.StmtSurface, label, args or {})
    end

    ---Void yield statement.
    ---@return moonlift.ast.Stmt
    function api.yield_void() return Tr.StmtYieldVoid(Tr.StmtSurface) end

    ---Yield statement. Without a value, emits `StmtYieldVoid`.
    ---@param value moonlift.ast.Expr? Yielded value.
    ---@return moonlift.ast.Stmt
    function api.yield_(value) if value == nil then return Tr.StmtYieldVoid(Tr.StmtSurface) end; return Tr.StmtYieldValue(Tr.StmtSurface, as_expr(value, "yield value")) end

    ---Void return statement.
    ---@return moonlift.ast.Stmt
    function api.return_void() return Tr.StmtReturnVoid(Tr.StmtSurface) end

    ---Return statement. Without a value, emits `StmtReturnVoid`.
    ---@param value moonlift.ast.Expr? Returned value.
    ---@return moonlift.ast.Stmt
    function api.return_(value) if value == nil then return Tr.StmtReturnVoid(Tr.StmtSurface) end; return Tr.StmtReturnValue(Tr.StmtSurface, as_expr(value, "return value")) end

    ---Block label.
    ---@param name string Label name.
    ---@return MoonTree.BlockLabel
    function api.block_label(name) return Tr.BlockLabel(assert_name(name, "block_label")) end

    ---Block parameter.
    ---@param name string Parameter name.
    ---@param ty moonlift.ast.Type Parameter type.
    ---@return MoonTree.BlockParam
    function api.block_param(name, ty) return Tr.BlockParam(assert_name(name, "block_param"), as_type(ty, "block_param type")) end

    ---Entry block parameter with an initial value.
    ---@param name string Parameter name.
    ---@param ty moonlift.ast.Type Parameter type.
    ---@param init moonlift.ast.Expr Initial value.
    ---@return MoonTree.EntryBlockParam
    function api.entry_param(name, ty, init) return Tr.EntryBlockParam(assert_name(name, "entry_param"), as_type(ty, "entry_param type"), as_expr(init, "entry_param init")) end

    ---Entry control block.
    ---@param spec table `{ label/name, params, body }`.
    ---@return MoonTree.EntryControlBlock
    function api.entry_block(spec)
        local label = spec.label or spec.name or spec[1]
        if pvm.classof(label) ~= Tr.BlockLabel then label = Tr.BlockLabel(assert_name(label, "entry_block label")) end
        return Tr.EntryControlBlock(label, spec.params or spec[2] or {}, stmts(spec.body or spec[3] or {}, "entry_block body"))
    end

    ---Non-entry control block.
    ---@param spec table `{ label/name, params, body }`.
    ---@return MoonTree.ControlBlock
    function api.control_block(spec)
        local label = spec.label or spec.name or spec[1]
        if pvm.classof(label) ~= Tr.BlockLabel then label = Tr.BlockLabel(assert_name(label, "control_block label")) end
        return Tr.ControlBlock(label, spec.params or spec[2] or {}, stmts(spec.body or spec[3] or {}, "control_block body"))
    end

    ---Statement control region.
    ---@param spec table `{ id/region_id, entry, blocks }`.
    ---@return MoonTree.ControlStmtRegion
    function api.control_stmt_region(spec) return Tr.ControlStmtRegion(spec.id or spec.region_id or "control.hosted.1", spec.entry, spec.blocks or {}) end

    ---Expression control region.
    ---@param spec table `{ id/region_id, result_ty, entry, blocks }`.
    ---@return MoonTree.ControlExprRegion
    function api.control_expr_region(spec) return Tr.ControlExprRegion(spec.id or spec.region_id or "control.hosted.1", as_type(spec.result_ty or spec.result, "control result type"), spec.entry, spec.blocks or {}) end

    ---Control-region statement.
    ---@param region MoonTree.ControlStmtRegion Statement control region.
    ---@return moonlift.ast.Stmt
    function api.control_stmt(region) return Tr.StmtControl(Tr.StmtSurface, region) end

    ---Control-region expression.
    ---@param region MoonTree.ControlExprRegion Expression control region.
    ---@return moonlift.ast.Expr
    function api.control_expr(region) return Tr.ExprControl(Tr.ExprSurface, region) end

    -- Contracts, functions, items, modules --------------------------------

    ---Bounds contract `requires bounds(base, len)`.
    ---@param base moonlift.ast.Expr Base expression.
    ---@param len moonlift.ast.Expr Length expression.
    ---@return moonlift.ast.FuncContract
    function api.contract_bounds(base, len) return Tr.ContractBounds(as_expr(base, "bounds base"), as_expr(len, "bounds len")) end

    ---Window bounds contract.
    function api.contract_window_bounds(base, base_len, start, len) return Tr.ContractWindowBounds(as_expr(base, "window base"), as_expr(base_len, "window base_len"), as_expr(start, "window start"), as_expr(len, "window len")) end
    ---Disjoint contract.
    function api.contract_disjoint(a, b) return Tr.ContractDisjoint(as_expr(a, "disjoint a"), as_expr(b, "disjoint b")) end
    ---Same-length contract.
    function api.contract_same_len(a, b) return Tr.ContractSameLen(as_expr(a, "same_len a"), as_expr(b, "same_len b")) end
    ---Noalias contract.
    function api.contract_noalias(base) return Tr.ContractNoAlias(as_expr(base, "noalias base")) end
    ---Readonly contract.
    function api.contract_readonly(base) return Tr.ContractReadonly(as_expr(base, "readonly base")) end
    ---Writeonly contract.
    function api.contract_writeonly(base) return Tr.ContractWriteonly(as_expr(base, "writeonly base")) end

    ---Local function node.
    ---@param spec moonlift.ast.FuncSpec Function fields.
    ---@return moonlift.ast.Func
    function api.func(spec)
        local result = type_or_void(spec.ret or spec.result)
        local contracts = spec.contracts or {}
        if #contracts > 0 then return Tr.FuncLocalContract(assert_name(spec.name, "func"), spec.params or {}, result, contracts, stmts(spec.body or {}, "func body")) end
        return Tr.FuncLocal(assert_name(spec.name, "func"), spec.params or {}, result, stmts(spec.body or {}, "func body"))
    end
    api.fn = api.func

    ---Exported function node.
    ---@param spec moonlift.ast.FuncSpec Function fields.
    ---@return moonlift.ast.Func
    function api.export_func(spec)
        local result = type_or_void(spec.ret or spec.result)
        local contracts = spec.contracts or {}
        if #contracts > 0 then return Tr.FuncExportContract(assert_name(spec.name, "export_func"), spec.params or {}, result, contracts, stmts(spec.body or {}, "export_func body")) end
        return Tr.FuncExport(assert_name(spec.name, "export_func"), spec.params or {}, result, stmts(spec.body or {}, "export_func body"))
    end
    api.export_fn = api.export_func

    ---Extern function node.
    ---@param spec moonlift.ast.ExternFuncSpec Extern fields.
    ---@return MoonTree.ExternFunc
    function api.extern_func(spec) return Tr.ExternFunc(assert_name(spec.name, "extern_func"), spec.symbol or spec.name, spec.params or {}, type_or_void(spec.ret or spec.result)) end
    api.extern = api.extern_func

    ---Const item payload.
    ---@param spec moonlift.ast.ConstSpec Const fields.
    ---@return MoonTree.ConstItem
    function api.const_item(spec) return Tr.ConstItem(assert_name(spec.name, "const"), as_type(spec.ty or spec.type, "const type"), as_expr(spec.value, "const value")) end
    api.const = api.const_item

    ---Static item payload.
    ---@param spec moonlift.ast.StaticSpec Static fields.
    ---@return MoonTree.StaticItem
    function api.static_item(spec) return Tr.StaticItem(assert_name(spec.name, "static"), as_type(spec.ty or spec.type, "static type"), as_expr(spec.value, "static value")) end
    api.static = api.static_item

    ---Import item payload.
    ---@param path string|string[] Imported path.
    ---@return MoonTree.ImportItem
    function api.import_item(path) return Tr.ImportItem(as_path(path, "import")) end

    local function field_decls(fields)
        local out = {}
        for i = 1, #array(fields, "fields") do
            local f = fields[i]
            out[i] = pvm.classof(f) == Ty.FieldDecl and f or api.field_decl(f)
        end
        return out
    end

    ---Struct type declaration.
    ---@param spec table `{ name, fields }`.
    ---@return moonlift.ast.TypeDecl
    function api.struct(spec) return Tr.TypeDeclStruct(assert_name(spec.name, "struct"), field_decls(spec.fields or spec[1] or {})) end

    ---Union type declaration.
    ---@param spec table `{ name, fields }`.
    ---@return moonlift.ast.TypeDecl
    function api.union(spec) return Tr.TypeDeclUnion(assert_name(spec.name, "union"), field_decls(spec.fields or spec[1] or {})) end

    ---Enum-sugar type declaration.
    ---@param spec table `{ name, variants = { "A", "B" } }`.
    ---@return moonlift.ast.TypeDecl
    function api.enum(spec)
        local vars = {}
        for i = 1, #array(spec.variants or spec[1] or {}, "enum variants") do vars[i] = C.Name(assert_name((spec.variants or spec[1])[i], "enum variant")) end
        return Tr.TypeDeclEnumSugar(assert_name(spec.name, "enum"), vars)
    end

    ---Tagged-union-sugar type declaration.
    ---@param spec table `{ name, variants }`.
    ---@return moonlift.ast.TypeDecl
    function api.tagged_union(spec)
        local vars = {}
        for i = 1, #array(spec.variants or spec[1] or {}, "tagged variants") do
            local v = (spec.variants or spec[1])[i]
            vars[i] = pvm.classof(v) == Ty.VariantDecl and v or api.variant_decl(v)
        end
        return Tr.TypeDeclTaggedUnionSugar(assert_name(spec.name, "tagged_union"), vars)
    end

    ---Wrap any item payload as a MoonTree.Item. Already wrapped items pass through.
    ---@param v moonlift.ast.Func|MoonTree.ExternFunc|MoonTree.ConstItem|MoonTree.StaticItem|MoonTree.ImportItem|moonlift.ast.TypeDecl|moonlift.ast.Item Item payload.
    ---@return moonlift.ast.Item
    function api.item(v)
        local cls = pvm.classof(v)
        if is_a(Tr.Item, v) then return v end
        if is_a(Tr.Func, v) then return Tr.ItemFunc(v) end
        if is_a(Tr.ExternFunc, v) then return Tr.ItemExtern(v) end
        if is_a(Tr.ConstItem, v) then return Tr.ItemConst(v) end
        if is_a(Tr.StaticItem, v) then return Tr.ItemStatic(v) end
        if cls == Tr.ImportItem then return Tr.ItemImport(v) end
        if is_a(Tr.TypeDecl, v) then return Tr.ItemType(v) end
        error("item expects a MoonTree item payload", 2)
    end

    ---Construct a source module. Positional entries are wrapped with `item`.
    ---@param spec moonlift.ast.ModuleSpec|moonlift.ast.Item[] Module table or item array.
    ---@return moonlift.ast.Module
    function api.module(spec)
        spec = spec or {}
        local src_items = spec.items or spec
        return Tr.Module(spec.h or Tr.ModuleSurface, items(src_items, "module items"))
    end

    ---Convenience exported-function item.
    ---@param spec moonlift.ast.FuncSpec Function fields.
    ---@return moonlift.ast.Item
    function api.export_func_item(spec) return Tr.ItemFunc(api.export_func(spec)) end

    ---Convenience local-function item.
    ---@param spec moonlift.ast.FuncSpec Function fields.
    ---@return moonlift.ast.Item
    function api.func_item(spec) return Tr.ItemFunc(api.func(spec)) end

    ---Convenience extern-function item.
    ---@param spec moonlift.ast.ExternFuncSpec Extern fields.
    ---@return moonlift.ast.Item
    function api.extern_item(spec) return Tr.ItemExtern(api.extern_func(spec)) end

    ---Convenience struct item.
    ---@param spec table Struct fields.
    ---@return moonlift.ast.Item
    function api.struct_item(spec) return Tr.ItemType(api.struct(spec)) end

    api.as_type = as_type
    api.as_expr = as_expr
    api.as_place = as_place
    api.copy_array = copy_array

    return api
end

---Create a Moonlift AST constructor API bound to an existing ASDL context.
---The context must already have `moonlift.asdl` defined.
---@param T table ASDL context containing the Moonlift schema.
---@return table api Constructor API.
function M.new(T)
    assert(T and T.MoonTree and T.MoonType, "moonlift.ast.new expects a context with moonlift.asdl defined")
    return install({}, T)
end

---Alias for `new(T)` kept near other Moonlift `Define(T)` modules.
---@param T table ASDL context containing the Moonlift schema.
---@return table api Constructor API.
function M.Define(T)
    return M.new(T)
end

local default_T = pvm.context()
schema.Define(default_T)
local default_api = install(M, default_T)

default_api.new = M.new
default_api.Define = M.Define

return default_api
