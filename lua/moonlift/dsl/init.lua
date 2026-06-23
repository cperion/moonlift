-- Lua-owned Moonlift DSL.
--
-- This surface does not treat [] as textual splice syntax. Lua evaluates the
-- bracket expression before this module sees it, so x[T] carries the actual
-- Lua value T. Normalization then consumes those already-resolved values by
-- role and emits MoonTree/MoonOpen ASDL directly.

local pvm = require("moonlift.pvm")
local schema = require("moonlift.asdl")
local llb = require("llb")
local ErrorSpan = require("moonlift.error.span")
local SourceAnalysis = require("moonlift.source_analysis")

local M = {}

local T = pvm.context()
schema.Define(T)

local C, Ty, B, Tr, O = T.MoonCore, T.MoonType, T.MoonBind, T.MoonTree, T.MoonOpen

local function class(name)
    local mt = { __dsl_class = name }
    mt.__index = mt
    return mt
end

local Name = class("Name")
local TypedName = class("TypedName")
local Payload = class("Payload")
local TypeCtor = class("TypeCtor")
local Expr = class("Expr")
local Stmt = class("Stmt")
local Decl = class("Decl")
local Case = class("Case")
local Default = class("Default")
local Requires = class("Requires")

local function is(v, mt) return type(v) == "table" and getmetatable(v) == mt end

local function die(msg, level)
    error("moonlift.dsl: " .. msg, (level or 1) + 1)
end

local function ident(s, site)
    if type(s) ~= "string" or not s:match("^[_%a][_%w]*$") then
        die((site or "name") .. " expects an identifier, got " .. tostring(s), 2)
    end
    return s
end

local function path(text)
    local parts = {}
    for part in tostring(text):gmatch("[^%.]+") do
        parts[#parts + 1] = C.Name(ident(part, "path"))
    end
    return C.Path(parts)
end

local function classof(v)
    if type(v) ~= "table" and type(v) ~= "userdata" then return false end
    local ok, cls = pcall(pvm.classof, v)
    return ok and cls or false
end

local function is_member(sum, v)
    local cls = classof(v)
    return cls == sum or (sum and sum.members and sum.members[cls]) or false
end

if not llb._moonlift_asdl_type_like then
    llb._moonlift_asdl_type_like = true
    llb.register_type_like(function(v)
        return is_member(Ty.Type, v)
    end)
end

local function name_token(s, origin) return setmetatable({ name = ident(s, "name"), origin = origin }, Name) end

local scalar = {
    void = C.ScalarVoid, bool = C.ScalarBool,
    i8 = C.ScalarI8, i16 = C.ScalarI16, i32 = C.ScalarI32, i64 = C.ScalarI64,
    u8 = C.ScalarU8, u16 = C.ScalarU16, u32 = C.ScalarU32, u64 = C.ScalarU64,
    f32 = C.ScalarF32, f64 = C.ScalarF64, index = C.ScalarIndex, rawptr = C.ScalarRawPtr,
}

local function scalar_type(name) return Ty.TScalar(assert(scalar[name], "unknown scalar")) end
local tree_expr
local merge_source_ctx
local attach_source_context
local build_source_context

local function frag_ref(v, expr)
    local name
    if is(v, Name) then name = v.name
    elseif type(v) == "string" then name = v
    elseif is(v, Decl) and (v.kind == "region" or v.kind == "expr_frag") then name = v.name
    else name = tostring(v) end
    name = table.concat((function(p)
        local out = {}
        for i = 1, #p.parts do out[i] = p.parts[i].text end
        return out
    end)(path(name)), ".")
    return expr and O.ExprFragRefName(name) or O.RegionFragRefName(name), name
end

local function concrete_type(v)
    if is_member(Ty.Type, v) then return v end
    if is(v, Decl) and v.type_name then return Ty.TNamed(Ty.TypeRefPath(path(v.type_name))) end
    if is(v, Name) then return Ty.TNamed(Ty.TypeRefPath(path(v.name))) end
    if type(v) == "string" then return Ty.TNamed(Ty.TypeRefPath(path(v))) end
    die("expected type value, got " .. tostring(v), 2)
end

local function is_array_lit_table(v)
    if type(v) ~= "table" then return false end
    local n = #v
    if n == 0 then return false end
    for i = 1, n do
        if v[i] == nil then return false end
    end
    for k in pairs(v) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
            return false
        end
    end
    return true
end

local function is_record_lit_table(v)
    if type(v) ~= "table" then return false end
    for k in pairs(v) do
        if type(k) ~= "string" then
            return false
        end
    end
    return true
end

local function field_inits_from_record(t)
    local names = {}
    local n = 0
    for k in pairs(t) do
        n = n + 1
        names[n] = k
    end
    table.sort(names)
    local fields = {}
    for i = 1, n do
        local name = names[i]
        fields[i] = Tr.FieldInit(name, tree_expr(t[name]), 0)
    end
    return fields
end

tree_expr = function(v)
    if is(v, Expr) then return v:tree() end
    if is_member(Tr.Expr, v) then return v end
    if is(v, Name) then return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(v.name)) end
    if is_array_lit_table(v) then
        local elems = {}
        for i = 1, #v do elems[i] = tree_expr(v[i]) end
        return Tr.ExprArray(Tr.ExprSurface, Ty.TScalar(C.ScalarVoid), elems)
    end
    if is_record_lit_table(v) then
        return Tr.ExprAgg(Tr.ExprSurface, Ty.TScalar(C.ScalarVoid), field_inits_from_record(v))
    end
    if v == nil then return Tr.ExprLit(Tr.ExprSurface, C.LitNil) end
    if type(v) == "number" then
        if v == v and v % 1 == 0 then return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(v))) end
        return Tr.ExprLit(Tr.ExprSurface, C.LitFloat(tostring(v)))
    end
    if type(v) == "boolean" then return Tr.ExprLit(Tr.ExprSurface, C.LitBool(v)) end
    if type(v) == "string" then return Tr.ExprLit(Tr.ExprSurface, C.LitString(v)) end
    die("expected expression value, got " .. tostring(v), 2)
end

local expand_array

local function expr_items(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "expr")) do out[i] = tree_expr(v) end
    return out
end
local function stmt_item(v)
    if llb.is(v, "Spread") then die("statement spread needs a statement fragment", 2) end
    if is(v, Stmt) then return v:tree() end
    if is_member(Tr.Stmt, v) then return v end
    return Tr.StmtExpr(Tr.StmtSurface, tree_expr(v))
end

function expand_array(t, role)
    local out = {}
    for i = 1, #(t or {}) do
        local v = t[i]
        if llb.is(v, "Spread") then
            local frag = v.value
            if llb.is(frag, "Fragment") then
                if frag.role ~= role then die("expected " .. role .. " fragment, got " .. tostring(frag.role), 2) end
                for j = 1, #frag.items do out[#out + 1] = frag.items[j] end
            elseif type(frag) == "table" then
                for j = 1, #frag do out[#out + 1] = frag[j] end
            else
                die("spread expects a fragment or array", 2)
            end
        elseif llb.is(v, "Fragment") and v.role == role then
            for j = 1, #v.items do out[#out + 1] = v.items[j] end
        else
            out[#out + 1] = v
        end
    end
    return out
end

local function param_items(t, open)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("parameter expects name [type]", 2) end
        out[i] = open and O.OpenParam("param:dsl:" .. v.name .. ":" .. tostring(i), v.name, concrete_type(v.ty))
            or Ty.Param(v.name, concrete_type(v.ty))
    end
    return out
end

local function field_items(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("field expects name [type]", 2) end
        out[i] = Ty.FieldDecl(v.name, concrete_type(v.ty))
    end
    return out
end

local function block_param_items(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("block parameter expects name [type]", 2) end
        out[i] = Tr.BlockParam(v.name, concrete_type(v.ty))
    end
    return out
end

local function entry_param_items(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("entry parameter expects name [type](init)", 2) end
        out[i] = Tr.EntryBlockParam(v.name, concrete_type(v.ty), tree_expr(v.init or 0))
    end
    return out
end

local function stmt_items(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "stmt")) do out[i] = stmt_item(v) end
    return out
end

local function tree_stmt(v) return stmt_item(v) end

local function tree_stmts(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "stmt")) do out[i] = tree_stmt(v) end
    return out
end

local function tree_entry_params(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("entry parameter expects name [type](init)", 2) end
        out[i] = Tr.EntryBlockParam(v.name, concrete_type(v.ty), tree_expr(v.init or 0))
    end
    return out
end

local function tree_block_params(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("block parameter expects name [type]", 2) end
        out[i] = Tr.BlockParam(v.name, concrete_type(v.ty))
    end
    return out
end

local function tree_params(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("parameter expects name [type]", 2) end
        out[i] = Ty.Param(v.name, concrete_type(v.ty))
    end
    return out
end

local function tree_place(v)
    if is_member(Tr.Place, v) then return v end
    if is(v, Name) then return Tr.PlaceRef(Tr.PlaceSurface, B.ValueRefName(v.name)) end
    if is(v, Expr) and v.kind == "dot" then return Tr.PlaceDot(Tr.PlaceSurface, tree_place(v.base), v.field) end
    if is(v, Expr) and v.kind == "index" then return Tr.PlaceIndex(Tr.PlaceSurface, Tr.IndexBaseExpr(tree_expr(v.base)), tree_expr(v.index)) end
    die("expected place", 2)
end

local function function_body_items(name, body)
    local items = expand_array(body or {}, "stmt")
    local has_control = false
    for i = 1, #items do
        if type(items[i]) == "table" and (items[i].kind == "entry_decl" or items[i].kind == "block_decl") then
            has_control = true
            break
        end
    end
    if not has_control then return stmt_items(body) end

    local entry, blocks = nil, {}
    for i = 1, #items do
        local item = items[i]
        if type(item) == "table" and item.kind == "entry_decl" then
            if entry ~= nil then die("function body has duplicate entry block", 2) end
            entry = Tr.EntryControlBlock(Tr.BlockLabel(item.name), tree_entry_params(item.params), tree_stmts(item.body))
        elseif type(item) == "table" and item.kind == "block_decl" then
            blocks[#blocks + 1] = Tr.ControlBlock(Tr.BlockLabel(item.name), tree_block_params(item.params), tree_stmts(item.body))
        else
            die("function body cannot mix entry/block declarations with ordinary statements", 2)
        end
    end
    if entry == nil then die("function control body requires an entry block", 2) end
    return { Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion("dsl.func." .. tostring(name), entry, blocks)) }
end

function Name:__tostring() return self.name end
function Name:__call(payload)
    if type(payload) == "table" then return setmetatable({ name = self.name, payload = payload }, Payload) end
    return setmetatable({ kind = "call", callee = self, args = { payload } }, Expr)
end
function Name:__add(r) return M.add(self, r) end
function Name:__sub(r) return M.sub(self, r) end
function Name:__mul(r) return M.mul(self, r) end
function Name:__div(r) return M.div(self, r) end
function Name:__mod(r) return M.rem(self, r) end
function Name:__unm() return M.neg(self) end
function Name:ge(r) return M.ge(self, r) end
function Name:gt(r) return M.gt(self, r) end
function Name:le(r) return M.le(self, r) end
function Name:lt(r) return M.lt(self, r) end
function Name:eq(r) return M.eq(self, r) end
function Name:ne(r) return M.ne(self, r) end
function Name:land(r) return M.And(self, r) end
function Name:lor(r) return M.Or(self, r) end
function Name:lnot() return M.Not(self) end
function Name:addr() return M.addr(self) end
function Name:deref() return M.deref(self) end
function Name:load() return M.deref(self) end
Name.__index = function(self, k)
    if Name[k] then return Name[k] end
    if type(k) == "string" then return setmetatable({ kind = "dot", base = self, field = ident(k, "field") }, Expr) end
    if is_member(Ty.Type, k) then
        return setmetatable({ name = self.name, ty = k }, TypedName)
    end
    return setmetatable({ kind = "index", base = self, index = k }, Expr)
end

function TypedName:__call(init)
    return setmetatable({ name = self.name, ty = self.ty, init = init }, TypedName)
end

local bin_op = {
    add = C.BinAdd, sub = C.BinSub, mul = C.BinMul, div = C.BinDiv, rem = C.BinRem,
    band = C.BinBitAnd, bor = C.BinBitOr, bxor = C.BinBitXor, shl = C.BinShl, lshr = C.BinLShr, ashr = C.BinAShr,
}
local cmp_op = { eq = C.CmpEq, ne = C.CmpNe, lt = C.CmpLt, le = C.CmpLe, gt = C.CmpGt, ge = C.CmpGe }
local logic_op = { ["and"] = C.LogicAnd, ["or"] = C.LogicOr }
local atomic_rmw_op = {
    add = C.AtomicRmwAdd, sub = C.AtomicRmwSub,
    band = C.AtomicRmwAnd, bor = C.AtomicRmwOr, bxor = C.AtomicRmwXor,
    xchg = C.AtomicRmwXchg,
}

function Expr:__add(r) return M.add(self, r) end
function Expr:__sub(r) return M.sub(self, r) end
function Expr:__mul(r) return M.mul(self, r) end
function Expr:__div(r) return M.div(self, r) end
function Expr:__mod(r) return M.rem(self, r) end
function Expr:__unm() return M.neg(self) end
function Expr:__call(...) return setmetatable({ kind = "call", callee = self, args = { ... } }, Expr) end
function Expr:ge(r) return M.ge(self, r) end
function Expr:gt(r) return M.gt(self, r) end
function Expr:le(r) return M.le(self, r) end
function Expr:lt(r) return M.lt(self, r) end
function Expr:eq(r) return M.eq(self, r) end
function Expr:ne(r) return M.ne(self, r) end
function Expr:land(r) return M.And(self, r) end
function Expr:lor(r) return M.Or(self, r) end
function Expr:lnot() return M.Not(self) end
function Expr:addr() return M.addr(self) end
function Expr:deref() return M.deref(self) end
function Expr:load() return M.deref(self) end
Expr.__index = function(self, k)
    if Expr[k] then return Expr[k] end
    if type(k) == "string" then return setmetatable({ kind = "dot", base = self, field = ident(k, "field") }, Expr) end
    return setmetatable({ kind = "index", base = self, index = k }, Expr)
end

function Expr:tree()
    local k = self.kind
    if k == "tree" then return self.value end
    if k == "binary" then return Tr.ExprBinary(Tr.ExprSurface, bin_op[self.op], tree_expr(self.lhs), tree_expr(self.rhs)) end
    if k == "cmp" then return Tr.ExprCompare(Tr.ExprSurface, cmp_op[self.op], tree_expr(self.lhs), tree_expr(self.rhs)) end
    if k == "logic" then return Tr.ExprLogic(Tr.ExprSurface, logic_op[self.op], tree_expr(self.lhs), tree_expr(self.rhs)) end
    if k == "not" then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNot, tree_expr(self.value)) end
    if k == "bitnot" then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryBitNot, tree_expr(self.value)) end
    if k == "neg" then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNeg, tree_expr(self.value)) end
    if k == "dot" then return Tr.ExprDot(Tr.ExprSurface, tree_expr(self.base), self.field) end
    if k == "index" then return Tr.ExprIndex(Tr.ExprSurface, Tr.IndexBaseExpr(tree_expr(self.base)), tree_expr(self.index)) end
    if k == "call" then
        local args = {}
        for i = 1, #(self.args or {}) do args[i] = tree_expr(self.args[i]) end
        return Tr.ExprCall(Tr.ExprSurface, tree_expr(self.callee), args)
    end
    if k == "cast" then return Tr.ExprCast(Tr.ExprSurface, self.cast, concrete_type(self.ty), tree_expr(self.value)) end
    if k == "len" then return Tr.ExprLen(Tr.ExprSurface, tree_expr(self.value)) end
    if k == "addr" then return Tr.ExprAddrOf(Tr.ExprSurface, tree_place(self.value)) end
    if k == "deref" then return Tr.ExprDeref(Tr.ExprSurface, tree_expr(self.value)) end
    if k == "load" then return Tr.ExprDeref(Tr.ExprSurface, tree_expr(self.value)) end
    if k == "null" then return Tr.ExprNull(Tr.ExprSurface, concrete_type(self.ty)) end
    if k == "sizeof" then return Tr.ExprSizeOf(Tr.ExprSurface, concrete_type(self.ty)) end
    if k == "alignof" then return Tr.ExprAlignOf(Tr.ExprSurface, concrete_type(self.ty)) end
    if k == "is_null" then return Tr.ExprIsNull(Tr.ExprSurface, tree_expr(self.value)) end
    if k == "intrinsic" then
        local args = {}
        for i = 1, #(self.args or {}) do args[i] = tree_expr(self.args[i]) end
        return Tr.ExprIntrinsic(Tr.ExprSurface, self.op, args)
    end
    if k == "ctor" then
        local args = {}
        for i = 1, #(self.args or {}) do args[i] = tree_expr(self.args[i]) end
        return Tr.ExprCtor(Tr.ExprSurface, self.type_name, self.variant_name, args)
    end
    if k == "emit_expr" then
        local ref, name = frag_ref(self.target, true)
        return Tr.ExprUseExprFrag(Tr.ExprSurface, "emit.expr." .. name, ref, expr_items(self.args), {})
    end
    if k == "select" then return Tr.ExprSelect(Tr.ExprSurface, tree_expr(self.cond), tree_expr(self.a), tree_expr(self.b)) end
    if k == "atomic_load" then return Tr.ExprAtomicLoad(Tr.ExprSurface, concrete_type(self.ty), tree_expr(self.addr), C.AtomicSeqCst) end
    if k == "atomic_rmw" then return Tr.ExprAtomicRmw(Tr.ExprSurface, assert(atomic_rmw_op[self.op], "unknown atomic rmw op: " .. tostring(self.op)), concrete_type(self.ty), tree_expr(self.addr), tree_expr(self.value), C.AtomicSeqCst) end
    if k == "atomic_cas" then return Tr.ExprAtomicCas(Tr.ExprSurface, concrete_type(self.ty), tree_expr(self.addr), tree_expr(self.expected), tree_expr(self.replacement), C.AtomicSeqCst) end
    die("unsupported expression kind " .. tostring(k), 2)
end

local function bin(name)
    return function(a, b) return setmetatable({ kind = "binary", op = name, lhs = a, rhs = b }, Expr) end
end
local function cmp(name)
    return function(a, b) return setmetatable({ kind = "cmp", op = name, lhs = a, rhs = b }, Expr) end
end

M.add, M.sub, M.mul, M.div, M.rem = bin("add"), bin("sub"), bin("mul"), bin("div"), bin("rem")
M.band, M.bor, M.bxor, M.shl, M.shr = bin("band"), bin("bor"), bin("bxor"), bin("shl"), bin("lshr")
M.eq, M.ne, M.lt, M.le, M.gt, M.ge = cmp("eq"), cmp("ne"), cmp("lt"), cmp("le"), cmp("gt"), cmp("ge")
function M.neg(v) return setmetatable({ kind = "neg", value = v }, Expr) end
function M.And(a, b) return setmetatable({ kind = "logic", op = "and", lhs = a, rhs = b }, Expr) end
function M.Or(a, b) return setmetatable({ kind = "logic", op = "or", lhs = a, rhs = b }, Expr) end
function M.Not(v) return setmetatable({ kind = "not", value = v }, Expr) end
function M.bnot(v) return setmetatable({ kind = "bitnot", value = v }, Expr) end
function M.len(v) return setmetatable({ kind = "len", value = v }, Expr) end
function M.select(c, a, b) return setmetatable({ kind = "select", cond = c, a = a, b = b }, Expr) end
function M.as(ty) return function(v) return setmetatable({ kind = "cast", cast = C.SurfaceCast, ty = ty, value = v }, Expr) end end
function M.bitcast(ty) return function(v) return setmetatable({ kind = "cast", cast = C.SurfaceBitcast, ty = ty, value = v }, Expr) end end
function M.addr(v) return setmetatable({ kind = "addr", value = v }, Expr) end
function M.deref(v) return setmetatable({ kind = "deref", value = v }, Expr) end
function M.load(v) return setmetatable({ kind = "load", value = v }, Expr) end
function M.null(ty) return setmetatable({ kind = "null", ty = ty }, Expr) end
function M.sizeof(ty) return setmetatable({ kind = "sizeof", ty = ty }, Expr) end
function M.alignof(ty) return setmetatable({ kind = "alignof", ty = ty }, Expr) end
function M.is_null(v) return setmetatable({ kind = "is_null", value = v }, Expr) end

-- Atomic expression constructors
function M.aload(ty, addr) return setmetatable({ kind = "atomic_load", ty = ty, addr = addr }, Expr) end
function M.armw(op, ty, addr, value) return setmetatable({ kind = "atomic_rmw", op = op, ty = ty, addr = addr, value = value }, Expr) end
function M.acas(ty, addr, expected, replacement) return setmetatable({ kind = "atomic_cas", ty = ty, addr = addr, expected = expected, replacement = replacement }, Expr) end

-- Variant constructor expression
function M.ctor(type_name, variant_name, args) return setmetatable({ kind = "ctor", type_name = type_name, variant_name = variant_name, args = args or {} }, Expr) end

-- Contract annotation constructors
function M.bounds(base, len) return Tr.ContractBounds(tree_expr(base), tree_expr(len)) end
function M.disjoint(a, b) return Tr.ContractDisjoint(tree_expr(a), tree_expr(b)) end
function M.same_len(a, b) return Tr.ContractSameLen(tree_expr(a), tree_expr(b)) end
function M.window_bounds(base, base_len, start, len) return Tr.ContractWindowBounds(tree_expr(base), tree_expr(base_len), tree_expr(start), tree_expr(len)) end

local bind_seq = 0
local function binding(name, ty, class)
    bind_seq = bind_seq + 1
    return B.Binding(C.Id("dsl:" .. name .. ":" .. bind_seq), name, concrete_type(ty), class)
end

function Stmt:tree()
    local k = self.kind
    if k == "ret" then
        if self.value == nil then return Tr.StmtReturnVoid(Tr.StmtSurface) end
        return Tr.StmtReturnValue(Tr.StmtSurface, tree_expr(self.value))
    end
    if k == "yield" then
        if self.value == nil then return Tr.StmtYieldVoid(Tr.StmtSurface) end
        return Tr.StmtYieldValue(Tr.StmtSurface, tree_expr(self.value))
    end
    if k == "let" then return Tr.StmtLet(Tr.StmtSurface, binding(self.name, self.ty, B.BindingClassLocalValue), tree_expr(self.init)) end
    if k == "var" then return Tr.StmtVar(Tr.StmtSurface, binding(self.name, self.ty, B.BindingClassLocalCell), tree_expr(self.init)) end
    if k == "when" then return Tr.StmtIf(Tr.StmtSurface, tree_expr(self.cond), stmt_items(self.body), {}) end
    if k == "if" then return Tr.StmtIf(Tr.StmtSurface, tree_expr(self.cond), stmt_items(self.then_body), stmt_items(self.else_body or {})) end
    if k == "set" then return Tr.StmtSet(Tr.StmtSurface, tree_place(self.place), tree_expr(self.value)) end
    if k == "assert" then return Tr.StmtAssert(Tr.StmtSurface, tree_expr(self.cond)) end
    if k == "trap" then return Tr.StmtTrap(Tr.StmtSurface) end
    if k == "assume" then return Tr.StmtExpr(Tr.StmtSurface, Tr.ExprIntrinsic(Tr.ExprSurface, C.IntrinsicAssume, { tree_expr(self.cond) })) end
    if k == "jump" then
        local args = {}
        for name, value in pairs(self.args or {}) do args[#args + 1] = Tr.JumpArg(name, tree_expr(value)) end
        return Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel(self.target), args)
    end
    if k == "emit" then
        local ref, name = frag_ref(self.target, false)
        return Tr.StmtUseRegionFrag(Tr.StmtSurface, self.mode or Tr.RegionUseEmit, "emit." .. name, ref, expr_items(self.args), {}, self.conts or {})
    end
    if k == "switch" then return Tr.StmtSwitch(Tr.StmtSurface, tree_expr(self.value), self.arms or {}, self.variant_arms or {}, tree_stmts(self.default_body or {})) end
    if k == "atomic_store" then return Tr.StmtAtomicStore(Tr.StmtSurface, concrete_type(self.ty), tree_expr(self.addr), tree_expr(self.value), C.AtomicSeqCst) end
    if k == "atomic_fence" then return Tr.StmtAtomicFence(Tr.StmtSurface, C.AtomicSeqCst) end
    if k == "expr" then return Tr.StmtExpr(Tr.StmtSurface, tree_expr(self.expr)) end
    die("unsupported statement kind " .. tostring(k), 2)
end

function M.ret(t) return setmetatable({ kind = "ret", value = t }, Stmt) end
function M.yield(t) return setmetatable({ kind = "yield", value = t }, Stmt) end
function M.when(t) return function(b) return setmetatable({ kind = "when", cond = t, body = b or {} }, Stmt) end end
function M.If(t) return function(b) return setmetatable({ kind = "if", cond = t, then_body = b or {} }, { __call = function(self, else_body) self.else_body = else_body or {}; return self end, __index = Stmt }) end end
function M.store(place, value) return setmetatable({ kind = "set", place = place, value = value }, Stmt) end
M.set = M.store
function M.assert_(t) return setmetatable({ kind = "assert", cond = t }, Stmt) end
function M.trap() return setmetatable({ kind = "trap" }, Stmt) end
function M.assume(t) return setmetatable({ kind = "assume", cond = t }, Stmt) end
function M.astore(ty, addr, value) return setmetatable({ kind = "atomic_store", ty = ty, addr = addr, value = value }, Stmt) end
function M.afence() return setmetatable({ kind = "atomic_fence" }, Stmt) end

local function handle_repr(repr)
    if repr == nil then return Ty.HandleReprScalar(C.ScalarU32) end
    if is_member(Ty.HandleRepr, repr) then return repr end
    return Ty.HandleReprScalar(assert(scalar[tostring(repr)], "unsupported handle repr"))
end

local function handle_invalid(v)
    if v == nil then return Ty.HandleInvalidNone end
    if is_member(Ty.HandleInvalid, v) then return v end
    return Ty.HandleInvalidInt(tostring(v))
end

local function type_decl(name, body, union)
    if union then
        local vars = {}
        for i, v in ipairs(body or {}) do
            if is(v, Payload) or (type(v) == "table" and v.name ~= nil and v.payload ~= nil) then vars[i] = Ty.VariantDecl(tostring(v.name), scalar_type("void"), field_items(v.payload))
            elseif is(v, Name) then vars[i] = Ty.VariantDecl(v.name, scalar_type("void"), {})
            else die("union expects alternatives", 2) end
        end
        return Tr.TypeDeclTaggedUnionSugar(name, vars)
    end
    return Tr.TypeDeclStruct(name, field_items(body))
end

function Decl:syntax()
    if self.kind == "module" then
        local items = {}
        for i, d in ipairs(expand_array(self.body, "decl")) do
            if is(d, Decl) then items[#items + 1] = d:syntax_item()
            elseif is_member(Tr.Item, d) then items[#items + 1] = d
            else die("module body expects declarations", 2) end
        end
        return Tr.Module(Tr.ModuleSurface, items)
    end
    die("only modules have standalone syntax()", 2)
end

local function module_ast_of(self)
    if self.kind == "module" then return self:syntax() end
    return Tr.Module(Tr.ModuleSurface, { self:syntax_item() })
end

function Decl:typecheck(opts)
    opts = merge_source_ctx(opts, self)
    local Typecheck = require("moonlift.tree_typecheck").Define(T)
    return Typecheck.check_module(module_ast_of(self), opts)
end

local function retarget_cont_jumps_stmt(stmt, cont_by_name)
    local cls = pvm.classof(stmt)
    if cls == Tr.StmtJump then
        local slot = cont_by_name[stmt.target.name]
        if slot then return Tr.StmtJumpCont(stmt.h, slot, stmt.args) end
        return stmt
    end
    if cls == Tr.StmtIf then
        local then_body, else_body = {}, {}
        for i = 1, #stmt.then_body do then_body[i] = retarget_cont_jumps_stmt(stmt.then_body[i], cont_by_name) end
        for i = 1, #stmt.else_body do else_body[i] = retarget_cont_jumps_stmt(stmt.else_body[i], cont_by_name) end
        return pvm.with(stmt, { then_body = then_body, else_body = else_body })
    end
    if cls == Tr.StmtSwitch then
        local arms, variant_arms, default_body = {}, {}, {}
        for i = 1, #stmt.arms do
            local body = {}
            for j = 1, #stmt.arms[i].body do body[j] = retarget_cont_jumps_stmt(stmt.arms[i].body[j], cont_by_name) end
            arms[i] = pvm.with(stmt.arms[i], { body = body })
        end
        for i = 1, #stmt.variant_arms do
            local body = {}
            for j = 1, #stmt.variant_arms[i].body do body[j] = retarget_cont_jumps_stmt(stmt.variant_arms[i].body[j], cont_by_name) end
            variant_arms[i] = pvm.with(stmt.variant_arms[i], { body = body })
        end
        for i = 1, #stmt.default_body do default_body[i] = retarget_cont_jumps_stmt(stmt.default_body[i], cont_by_name) end
        return pvm.with(stmt, { arms = arms, variant_arms = variant_arms, default_body = default_body })
    end
    return stmt
end

local function retarget_cont_jumps_stmts(stmts, cont_by_name)
    local out = {}
    for i = 1, #(stmts or {}) do out[i] = retarget_cont_jumps_stmt(stmts[i], cont_by_name) end
    return out
end

function Decl:syntax_item()
    if self.kind == "struct" then return Tr.ItemType(type_decl(self.name, self.body, false)) end
    if self.kind == "union" then return Tr.ItemType(type_decl(self.name, self.body, true)) end
    if self.kind == "fn" then
        local contracts, body = {}, {}
        for i, v in ipairs(self.body or {}) do
            if is(v, Requires) then for j = 1, #v.items do contracts[#contracts + 1] = v.items[j] end
            else body[#body + 1] = v end
        end
        if #contracts > 0 then
            return Tr.ItemFunc(Tr.FuncLocalContract(self.name, param_items(self.params), concrete_type(self.result or scalar_type("void")), contracts, function_body_items(self.name, body)))
        end
        return Tr.ItemFunc(Tr.FuncLocal(self.name, param_items(self.params), concrete_type(self.result or scalar_type("void")), function_body_items(self.name, body)))
    end
    if self.kind == "export_fn" then
        local contracts, body = {}, {}
        for i, v in ipairs(self.body or {}) do
            if is(v, Requires) then for j = 1, #v.items do contracts[#contracts + 1] = v.items[j] end
            else body[#body + 1] = v end
        end
        if #contracts > 0 then
            return Tr.ItemFunc(Tr.FuncExportContract(self.name, param_items(self.params), concrete_type(self.result or scalar_type("void")), contracts, function_body_items(self.name, body)))
        end
        return Tr.ItemFunc(Tr.FuncExport(self.name, param_items(self.params), concrete_type(self.result or scalar_type("void")), function_body_items(self.name, body)))
    end
    if self.kind == "extern" then
        return Tr.ItemExtern(Tr.ExternFunc(self.name, self.opts.symbol or self.name, tree_params(self.params), concrete_type(self.result or scalar_type("void"))))
    end
    if self.kind == "handle" then
        local facts = {}
        if self.opts.domain then facts[#facts + 1] = Ty.HandleDomain(Ty.TypeRefPath(path(self.opts.domain))) end
        if self.opts.target then facts[#facts + 1] = Ty.HandleTarget(Ty.TypeRefPath(path(self.opts.target))) end
        return Tr.ItemType(Tr.TypeDeclHandle(self.name, handle_repr(self.repr or self.opts.repr), handle_invalid(self.opts.invalid), facts))
    end
    if self.kind == "const" then
        return Tr.ItemConst(Tr.ConstItem(self.name, concrete_type(self.ty), tree_expr(self.value)))
    end
    if self.kind == "static" then
        return Tr.ItemStatic(Tr.StaticItem(self.name, concrete_type(self.ty), tree_expr(self.value)))
    end
    if self.kind == "import" then
        return Tr.ItemImport(Tr.ImportItem(path(self.name)))
    end
    if self.kind == "expr_frag" then
        return Tr.ItemExprFrag(O.ExprFrag(O.NameRefText(self.name), param_items(self.params, true), O.OpenSet({}, {}, {}, {}), tree_expr(self.body), concrete_type(self.result)))
    end
    if self.kind == "region" then
        local entry = self.entry or { name = "entry", params = {}, body = {} }
        local blocks = {}
        for _, b in ipairs(self.blocks or {}) do
            blocks[#blocks + 1] = Tr.ControlBlock(Tr.BlockLabel(b.name), block_param_items(b.params), stmt_items(b.body))
        end
        local conts = {}
        local cont_by_name = {}
        for i, c in ipairs(self.conts or {}) do
            if is(c, Payload) or (type(c) == "table" and c.name ~= nil and c.payload ~= nil) then conts[i] = O.ContSlot("cont:" .. self.name .. ":" .. tostring(c.name) .. ":" .. tostring(i), tostring(c.name), block_param_items(c.payload))
            elseif is(c, Name) then conts[i] = O.ContSlot("cont:" .. self.name .. ":" .. c.name .. ":" .. tostring(i), c.name, {})
            else die("region continuation expects named payload", 2) end
            cont_by_name[conts[i].pretty_name] = conts[i]
        end
        local retargeted_blocks = {}
        for i = 1, #blocks do
            retargeted_blocks[i] = pvm.with(blocks[i], { body = retarget_cont_jumps_stmts(blocks[i].body, cont_by_name) })
        end
        return Tr.ItemRegionFrag(O.RegionFrag(
            O.NameRefText(self.name),
            param_items(self.params, true),
            conts,
            O.OpenSet({}, {}, {}, {}),
            Tr.EntryControlBlock(Tr.BlockLabel(entry.name), entry_param_items(entry.params), retarget_cont_jumps_stmts(stmt_items(entry.body), cont_by_name)),
            retargeted_blocks))
    end
    die("unsupported declaration kind " .. tostring(self.kind), 2)
end

function Decl:ast()
    if self.kind == "module" then return module_ast_of(self) end
    local items = module_ast_of(self).items
    return items[1]
end

local function write_text_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text or "")
    f:close()
end

local c_artifact_mt = {}

function c_artifact_mt:write(opts)
    opts = opts or {}
    if type(opts) == "string" then opts = { c_path = opts } end
    if opts.c_path or opts.source_path then write_text_file(opts.c_path or opts.source_path, self.source) end
    if opts.h_path or opts.header_path then write_text_file(opts.h_path or opts.header_path, self.header) end
    if opts.support_path then write_text_file(opts.support_path, self.support) end
    if opts.combined_path or opts.single_path then write_text_file(opts.combined_path or opts.single_path, self.combined) end
    return self
end

function c_artifact_mt:source_text() return self.source end
function c_artifact_mt:header_text() return self.header end
function c_artifact_mt:combined_text() return self.combined end

local function add_lua_token_anchors(source, uri, anchors)
    local keyword = {
        ["module"] = true, ["struct"] = true, ["union"] = true, ["region"] = true,
        ["expr"] = true, ["const"] = true, ["static"] = true, ["extern"] = true,
        ["handle"] = true, ["let"] = true, ["var"] = true, ["return"] = true,
        ["if"] = true, ["then"] = true, ["elseif"] = true, ["else"] = true,
        ["switch"] = true, ["case"] = true, ["default"] = true, ["when"] = true,
        ["yield"] = true, ["jump"] = true, ["emit"] = true, ["end"] = true,
        ["do"] = true, ["while"] = true, ["for"] = true, ["in"] = true,
        ["select"] = true, ["assert"] = true, ["and"] = true, ["or"] = true, ["not"] = true,
        ["fn"] = true, ["export_fn"] = true, ["entry"] = true, ["block"] = true,
    }

    local function is_ident_start(b)
        return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
    end
    local function is_ident_part(b)
        return is_ident_start(b) or (b >= 48 and b <= 57)
    end

    local len = #source
    local i = 1
    while i <= len do
        local b = source:byte(i)

        -- skip line comments
        if b == 45 and source:byte(i + 1) == 45 then
            i = i + 2
            while i <= len and source:byte(i) ~= 10 do i = i + 1 end
            if source:byte(i) == 10 then i = i + 1 end
            goto continue
        end

        -- skip short strings
        if b == 34 or b == 39 then
            local quote = b
            i = i + 1
            while i <= len do
                b = source:byte(i)
                if b == 92 and i < len then
                    i = i + 2
                elseif b == quote then
                    i = i + 1
                    break
                else
                    i = i + 1
                end
            end
            goto continue
        end

        -- skip long strings / long comments: [=[ ... ]=]
        if b == 91 then
            local j = i + 1
            local n_eq = 0
            while source:byte(j) == 61 do
                n_eq = n_eq + 1
                j = j + 1
            end
            if source:byte(j) == 91 then
                local close = "]" .. string.rep("=", n_eq) .. "]"
                local k = source:find(close, j + 1, true)
                if k then
                    i = k + #close
                else
                    i = len + 1
                end
                goto continue
            end
        end

        if is_ident_start(b) then
            local start = i
            i = i + 1
            while i <= len and is_ident_part(source:byte(i)) do i = i + 1 end
            local stop = i
            local token = source:sub(start, stop - 1)
            local kind = keyword[token] and "AnchorKeyword" or "AnchorBindingUse"
            local j = i
            while source:byte(j) == 32 or source:byte(j) == 9 do j = j + 1 end
            if source:byte(j) == 40 then kind = "AnchorFunctionUse" end
            anchors[#anchors + 1] = {
                kind = kind,
                label = token,
                range = ErrorSpan.from_source_text(uri, source, start - 1, stop - 1),
            }
            goto continue
        end

        i = i + 1
        ::continue::
    end
end

function build_source_context(uri, source)
    local analysis = SourceAnalysis.build(T, nil, source, nil, { uri = uri })
    if type(analysis.anchors) ~= "table" then analysis.anchors = {} end
    add_lua_token_anchors(source, uri, analysis.anchors)
    return analysis
end

function merge_source_ctx(opts, value)
    opts = opts or {}
    local source_ctx = rawget(value, "_source_analysis")
    if source_ctx then
        local merged = SourceAnalysis.merge_into({}, source_ctx)
        SourceAnalysis.merge_into(merged, opts.analysis_ctx)
        opts.analysis_ctx = merged
    end
    return opts
end

function attach_source_context(value, source_ctx)
    if type(value) ~= "table" then return end
    if rawget(value, "_source_analysis") == nil then rawset(value, "_source_analysis", source_ctx) end
    if type(value.body) == "table" then
        for i = 1, #value.body do
            local item = value.body[i]
            if type(item) == "table" then
                if rawget(item, "_source_analysis") == nil then rawset(item, "_source_analysis", source_ctx) end
                if type(item.body) == "table" then
                    for j = 1, #item.body do
                        local nested = item.body[j]
                        if type(nested) == "table" and rawget(nested, "_source_analysis") == nil then
                            rawset(nested, "_source_analysis", source_ctx)
                        end
                    end
                end
            end
        end
    end
end

function Decl:lower(opts)
    opts = merge_source_ctx(opts, self)
    local Pipeline = require("moonlift.frontend_pipeline").Define(T)
    opts.site = opts.site or "moonlift.dsl"
    local handle = Pipeline.lower_module_process:start(module_ast_of(self), opts)
    for _ in handle:events() do end
    local result = handle:result()
    if result == nil then error("moonlift.dsl lower failed", 2) end
    return result
end

function Decl:emit_c_artifact(opts)
    opts = merge_source_ctx(opts, self)
    local Pipeline = require("moonlift.frontend_pipeline").Define(T)
    opts.site = opts.site or "moonlift.dsl c"
    local handle = Pipeline.lower_module_to_c_process:start(module_ast_of(self), opts)
    for _ in handle:events() do end
    local result = handle:result()
    if result == nil then error("moonlift.dsl C lower failed", 2) end
    local artifact = require("moonlift.c_emit").Define(T).emit_artifact(result.c_unit, opts)
    artifact.dsl_module = self
    artifact.module = self
    artifact.unit = result.c_unit
    if getmetatable(artifact) == nil then
        setmetatable(artifact, { __index = c_artifact_mt })
    end
    return artifact
end

function Decl:compile(opts)
    opts = merge_source_ctx(opts, self)
    if opts.backend == "c" or opts.codegen == "c" then return self:emit_c_artifact(opts) end
    local result = self:lower(opts)
    local jit = require("moonlift.back_jit").Define(T).jit()
    for name, ptr in pairs(opts.symbols or {}) do jit:symbol(name, ptr) end
    return jit:compile(result.program)
end

function Decl:__tostring()
    return "moonlift.dsl." .. tostring(self.kind) .. (self.name and "(" .. tostring(self.name) .. ")" or "")
end

local function llb_format(self, f)
    return require("moonlift.dsl.format").doc(self, f)
end

Name.__llb_format = llb_format
TypedName.__llb_format = llb_format
Payload.__llb_format = llb_format
TypeCtor.__llb_format = llb_format
Expr.__llb_format = llb_format
Stmt.__llb_format = llb_format
Decl.__llb_format = llb_format
Case.__llb_format = llb_format
Default.__llb_format = llb_format
Requires.__llb_format = llb_format

function Decl:format(opts)
    return require("moonlift.dsl.format").format(self, opts)
end

function Stmt:format(opts)
    return require("moonlift.dsl.format").format(self, opts)
end

function Expr:format(opts)
    return require("moonlift.dsl.format").format(self, opts)
end

local function ctor(name, fn)
    return setmetatable({ name = name, fn = fn }, TypeCtor)
end

function TypeCtor:__index(k)
    if TypeCtor[k] then return TypeCtor[k] end
    return self.fn(k)
end

function TypeCtor:__call(a, b)
    local name = rawget(self, "name")
    if name == "lease" and b ~= nil then
        return Ty.TLease(concrete_type(b), Ty.LeaseOriginParam(is(a, Name) and a.name or tostring(a)))
    end
    if name == "noalias" then return Tr.ContractNoAlias(tree_expr(a)) end
    if name == "readonly" then return Tr.ContractReadonly(tree_expr(a)) end
    if name == "writeonly" then return Tr.ContractWriteonly(tree_expr(a)) end
    die("type constructor `" .. tostring(name) .. "` uses [] syntax", 2)
end

local function dsl_fragment(role, items, algebra, payload_role)
    return llb.fragment(role, items or {}, llb.here(role, { skip = 2 }), {
        algebra = algebra,
        payload_role = payload_role,
    })
end

function M.product(t) return dsl_fragment("product", t, "product") end
function M.stmts(t) return dsl_fragment("stmt", t, "list") end
function M.decls(t) return dsl_fragment("decl", t, "list") end
function M.exprs(t) return dsl_fragment("expr", t, "list") end
function M.conts(t) return dsl_fragment("conts", t, "sum", "product") end
function M.variants(t) return dsl_fragment("variants", t, "sum", "product") end
M.spread = llb.spread
M._ = llb.spread

local function case_literal(v)
    return setmetatable({ key = v }, {
        __call = function(self, body) return setmetatable({ key = self.key, body = body or {} }, Case) end,
    })
end

local function case_variant(name)
    return setmetatable({ _case_name = name }, {
        __call = function(self, binds)
            return function(body)
                return setmetatable({ key = name_token(self._case_name), binds = binds or {}, body = body or {} }, Case)
            end
        end,
    })
end

M.case = setmetatable({}, {
    __index = function(_, k)
        if type(k) == "string" and k:match("^[_%a][_%w]*$") then
            return case_variant(ident(k, "case variant"))
        end
        return nil
    end,
    __call = function(_, v)
        return case_literal(v)
    end,
})

function M.default(body) return setmetatable({ body = body or {} }, Default) end

function M.requires(t) return setmetatable({ items = t or {} }, Requires) end

function M.switch(t)
    return function(arms)
        local stmt_arms, variant_arms, default_body = {}, {}, {}
        for _, arm in ipairs(arms or {}) do
            if is(arm, Case) then
                if is(arm.key, Name) then
                    variant_arms[#variant_arms + 1] = Tr.SwitchVariantStmtArm(arm.key.name, {}, tree_stmts(arm.body))
                else
                    stmt_arms[#stmt_arms + 1] = Tr.SwitchStmtArm(tostring(arm.key), tree_stmts(arm.body))
                end
            elseif is(arm, Default) then
                default_body = arm.body
            else
                die("switch expects case/default arms", 2)
            end
        end
        return setmetatable({ kind = "switch", value = t, arms = stmt_arms, variant_arms = variant_arms, default_body = default_body }, Stmt)
    end
end

local access = {
    ro = Ty.TypeAccessReadonly,
    readonly = Ty.TypeAccessReadonly,
    wo = Ty.TypeAccessWriteonly,
    writeonly = Ty.TypeAccessWriteonly,
    noalias = Ty.TypeAccessNoAlias,
    noescape = Ty.TypeAccessNoEscape,
    preserve = Ty.TypeAccessPreserve,
    invalidate = Ty.TypeAccessInvalidate,
}

local function type_list(xs)
    local out = {}
    for i = 1, #(xs or {}) do out[i] = concrete_type(xs[i]) end
    return out
end

local function llb_name_text(v, site)
    if llb.is(v, "Name") then return ident(v.text, site or "name") end
    if is(v, Name) then return ident(v.name, site or "name") end
    if type(v) == "string" then return ident(v, site or "name") end
    die((site or "name") .. " expects a name, got " .. llb.repr(v), 2)
end

local function typed_items_from_llb(items)
    local out = {}
    for i, v in ipairs(items or {}) do
        if is(v, TypedName) then
            out[i] = v
        elseif type(v) == "table" and v.name ~= nil and (v.ty ~= nil or v.type ~= nil) then
            local init = v.init
            if init == llb.NIL or init == llb.ABSENT then init = nil end
            out[i] = setmetatable({ name = ident(tostring(v.name), "field"), ty = v.ty or v.type, init = init }, TypedName)
        else
            out[i] = v
        end
    end
    return out
end

local function region_decl(name, params_, conts, body)
    local entry, blocks = nil, {}
    for _, item in ipairs(body or {}) do
        if type(item) == "table" and item.kind == "entry_decl" then entry = item
        elseif type(item) == "table" and item.kind == "block_decl" then blocks[#blocks + 1] = item
        else die("region body expects entry/block declarations", 2) end
    end
    return setmetatable({ kind = "region", name = name, params = typed_items_from_llb(params_ or {}), conts = conts or {}, entry = entry, blocks = blocks }, Decl)
end

local g = llb.grammar
local ch = llb.channel

local function role_array(fragment_role, label)
    return {
        kind = "array",
        normalize = function(_, ctx, v)
            if llb.is(v, "Fragment") then
                if v.role ~= fragment_role then
                    llb.fail("expected " .. label .. " fragment, got " .. tostring(v.role), {
                        code = "E_MOONLIFT_FRAGMENT_ROLE",
                        primary = v.origin or (ctx and ctx.origin),
                    })
                end
                return v.items or {}
            end
            if type(v) ~= "table" then
                llb.fail("expected " .. label .. " table", {
                    code = "E_MOONLIFT_EXPECTED_TABLE",
                    primary = llb.origin_of(v) or (ctx and ctx.origin),
                })
            end
            return expand_array(v, fragment_role)
        end,
    }
end

local function named_lsp(kind)
    return function(n)
        if n.name then
            return { name = tostring(n.name), kind = kind, origin = n.origin, node = n }
        end
        return nil
    end
end

local function slot_name(slot) return slot[g.name] { channel = ch.index_name } end
local function slot_string(slot) return slot[g.string] { channel = ch.call_value } end
local function slot_type(slot) return slot[g.type] { channel = ch.index_type } end
local function slot_params(slot) return slot[g.params] { channel = ch.call_table } end
local function slot_decls(slot) return slot[g.decls] { channel = ch.call_table } end
local function slot_stmts(slot) return slot[g.stmts] { channel = ch.call_table } end
local function slot_conts(slot) return slot[g.conts] { channel = ch.call_table } end
local function slot_variants(slot) return slot[g.variants] { channel = ch.call_table } end
local function slot_value(slot)
    return slot[g.value] { channels = { ch.call_none, ch.call_value, ch.call_table, ch.call_many } }
end
local function slot_table_value(slot) return slot[g.value] { channel = ch.call_table } end

local conts_role = role_array("conts", "continuation")
conts_role.algebra = "sum"
conts_role.payload_role = "product"

local variants_role = role_array("variants", "variant")
variants_role.algebra = "sum"
variants_role.payload_role = "product"

local MoonLLB = llb.define "MoonliftDSL" {
    g.role .decls  (role_array("decl", "declaration")),
    g.role .stmts  (role_array("stmt", "statement")),
    g.role .params (role_array("product", "product")),
    g.role .conts  (conts_role),
    g.role .variants (variants_role),
    g.role .value  { kind = "value" },

    g.trait .declaration {
        apply = function(_, head)
            head.moonlift_category = "decl"
            head.lsp = head.lsp or { symbol = named_lsp("Declaration") }
        end,
    },

    g.trait .statement {
        apply = function(_, head)
            head.moonlift_category = "stmt"
        end,
    },

    g.trait .control_block {
        apply = function(_, head)
            head.moonlift_category = "control"
            head.lsp = head.lsp or { symbol = named_lsp("Block") }
        end,
    },

    g.head .module {
        g.trait .declaration,
        slot_string(g.slot .name),
        slot_decls(g.slot .body),
        emit = function(n) return setmetatable({ kind = "module", name = tostring(n.name), body = n.body or {} }, Decl) end,
    },

    g.head .struct {
        g.trait .declaration,
        slot_name(g.slot .name),
        slot_params(g.slot .fields),
        emit = function(n)
            local name = llb_name_text(n.name, "struct name")
            return setmetatable({ kind = "struct", name = name, type_name = name, body = typed_items_from_llb(n.fields or {}) }, Decl)
        end,
    },

    g.head .union {
        g.trait .declaration,
        slot_name(g.slot .name),
        slot_variants(g.slot .variants),
        emit = function(n)
            local name = llb_name_text(n.name, "union name")
            return setmetatable({ kind = "union", name = name, type_name = name, body = n.variants or {} }, Decl)
        end,
    },

    g.head .fn {
        g.trait .declaration,
        slot_name(g.slot .name),
        slot_params(g.slot .params),
        slot_type(g.slot .result) { optional = true },
        slot_stmts(g.slot .body),
        emit = function(n)
            return setmetatable({ kind = "fn", name = llb_name_text(n.name, "function name"), params = typed_items_from_llb(n.params or {}), result = n.result, body = n.body or {} }, Decl)
        end,
    },

    g.head .export_fn {
        g.trait .declaration,
        slot_name(g.slot .name),
        slot_params(g.slot .params),
        slot_type(g.slot .result) { optional = true },
        slot_stmts(g.slot .body),
        emit = function(n)
            return setmetatable({ kind = "export_fn", name = llb_name_text(n.name, "function name"), params = typed_items_from_llb(n.params or {}), result = n.result, body = n.body or {} }, Decl)
        end,
    },

    g.head .extern {
        g.trait .declaration,
        slot_name(g.slot .name),
        slot_params(g.slot .params),
        slot_type(g.slot .result) { optional = true },
        slot_table_value(g.slot .opts),
        emit = function(n)
            return setmetatable({ kind = "extern", name = llb_name_text(n.name, "extern name"), params = typed_items_from_llb(n.params or {}), result = n.result, opts = n.opts or {} }, Decl)
        end,
    },

    g.head .handle {
        g.trait .declaration,
        slot_name(g.slot .name),
        slot_table_value(g.slot .opts),
        emit = function(n) return setmetatable({ kind = "handle", name = llb_name_text(n.name, "handle name"), opts = n.opts or {} }, Decl) end,
    },

    g.head .const {
        g.trait .declaration,
        slot_name(g.slot .name),
        slot_type(g.slot .ty),
        slot_value(g.slot .value),
        emit = function(n) return setmetatable({ kind = "const", name = llb_name_text(n.name, "const name"), ty = n.ty, value = n.value }, Decl) end,
    },

    g.head .static {
        g.trait .declaration,
        slot_name(g.slot .name),
        slot_type(g.slot .ty),
        slot_value(g.slot .value),
        emit = function(n) return setmetatable({ kind = "static", name = llb_name_text(n.name, "static name"), ty = n.ty, value = n.value }, Decl) end,
    },

    g.head .import {
        g.trait .declaration,
        slot_value(g.slot .target),
        emit = function(n) return setmetatable({ kind = "import", name = n.target }, Decl) end,
    },

    g.head .expr_frag {
        g.trait .declaration,
        slot_name(g.slot .name),
        slot_params(g.slot .params),
        slot_type(g.slot .result),
        slot_value(g.slot .body),
        emit = function(n)
            return setmetatable({ kind = "expr_frag", name = llb_name_text(n.name, "expr fragment name"), params = typed_items_from_llb(n.params or {}), result = n.result, body = n.body }, Decl)
        end,
    },

    g.head .region {
        g.trait .declaration,
        slot_name(g.slot .name),
        slot_params(g.slot .params),
        slot_conts(g.slot .conts),
        slot_stmts(g.slot .body),
        emit = function(n) return region_decl(llb_name_text(n.name, "region name"), n.params, n.conts, n.body) end,
    },

    g.head .entry {
        g.trait .control_block,
        slot_name(g.slot .name),
        slot_params(g.slot .params),
        slot_stmts(g.slot .body),
        emit = function(n) return { kind = "entry_decl", name = llb_name_text(n.name, "entry name"), params = typed_items_from_llb(n.params or {}), body = n.body or {} } end,
    },

    g.head .block {
        g.trait .control_block,
        slot_name(g.slot .name),
        slot_params(g.slot .params),
        slot_stmts(g.slot .body),
        emit = function(n) return { kind = "block_decl", name = llb_name_text(n.name, "block name"), params = typed_items_from_llb(n.params or {}), body = n.body or {} } end,
    },

    g.head .jump {
        g.trait .statement,
        slot_name(g.slot .target),
        slot_table_value(g.slot .args),
        emit = function(n) return setmetatable({ kind = "jump", target = llb_name_text(n.target, "jump target"), args = n.args or {} }, Stmt) end,
    },

    g.head .emit {
        g.trait .statement,
        slot_name(g.slot .target),
        slot_table_value(g.slot .args),
        slot_table_value(g.slot .fills),
        emit = function(n)
            local conts = {}
            for cname, target in pairs(n.fills or {}) do
                conts[#conts + 1] = O.ContBinding(cname, O.ContTargetLabel(Tr.BlockLabel(is(target, Name) and target.name or tostring(target))))
            end
            return setmetatable({ kind = "emit", target = llb_name_text(n.target, "emit target"), args = n.args or {}, conts = conts }, Stmt)
        end,
    },

    g.head .let {
        g.trait .statement,
        slot_name(g.slot .name),
        slot_type(g.slot .ty),
        slot_value(g.slot .init),
        emit = function(n) return setmetatable({ kind = "let", name = llb_name_text(n.name, "let name"), ty = n.ty, init = n.init }, Stmt) end,
    },

    g.head .var {
        g.trait .statement,
        slot_name(g.slot .name),
        slot_type(g.slot .ty),
        slot_value(g.slot .init),
        emit = function(n) return setmetatable({ kind = "var", name = llb_name_text(n.name, "var name"), ty = n.ty, init = n.init }, Stmt) end,
    },
}

M.llb = llb
M.language = MoonLLB
M.process = llb.process

local _searcher_installed = false

local function ensure_searcher()
    if not _searcher_installed then
        _searcher_installed = true
        M.install_searcher()
    end
end

local function make_env(opts)
    opts = opts or {}
    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    ensure_searcher()
    env.module, env.fn, env.export_fn = MoonLLB.exports.module, MoonLLB.exports.fn, MoonLLB.exports.export_fn
    env.extern, env.handle, env.const, env.static = MoonLLB.exports.extern, MoonLLB.exports.handle, MoonLLB.exports.const, MoonLLB.exports.static
    env.import, env.expr_frag = MoonLLB.exports.import, MoonLLB.exports.expr_frag
    env.struct, env.union, env.region = MoonLLB.exports.struct, MoonLLB.exports.union, MoonLLB.exports.region
    env.entry, env.block, env.jump, env.emit = MoonLLB.exports.entry, MoonLLB.exports.block, MoonLLB.exports.jump, MoonLLB.exports.emit
    env.ret, env.yield, env.when, env.If = M.ret, M.yield, M.when, M.If
    env.let, env.var = MoonLLB.exports.let, MoonLLB.exports.var
    env.store, env.set, env.trap, env.assume, env.assert_ = M.store, M.set, M.trap, M.assume, M.assert_
    env.requires = M.requires
    env.astore, env.afence = M.astore, M.afence
    env.aload, env.armw, env.acas = M.aload, M.armw, M.acas
    env.switch, env.case, env.default = M.switch, M.case, M.default
    env.bit = {
        band = M.band,
        bor = M.bor,
        bxor = M.bxor,
        bnot = M.bnot,
        shl = M.shl,
        shr = M.shr,
        rshift = M.shr,
        lshift = M.shl,
    }
    env.product, env.stmts, env.decls, env.exprs, env.conts, env.variants, env.spread, env._ = M.product, M.stmts, M.decls, M.exprs, M.conts, M.variants, M.spread, M._
    env.process, env.process_opts = llb.process, llb.process_opts
    env.here, env.at_origin, env.with_origin = llb.here, llb.at, llb.with_origin
    env.eq, env.ne, env.lt, env.le, env.gt, env.ge = M.eq, M.ne, M.lt, M.le, M.gt, M.ge
    env.And, env.Or, env.Not, env.len, env.select = M.And, M.Or, M.Not, M.len, M.select
    env.addr, env.deref, env.load, env.is_null = M.addr, M.deref, M.load, M.is_null
    env.ctor = M.ctor
    env.bounds, env.disjoint, env.same_len = M.bounds, M.disjoint, M.same_len
    env.window_bounds = M.window_bounds
    env.as = setmetatable({}, { __index = function(_, ty) return M.as(ty) end })
    env.bitcast = setmetatable({}, { __index = function(_, ty) return M.bitcast(ty) end })
    env.null = setmetatable({}, { __index = function(_, ty) return M.null(ty) end })
    env.sizeof = setmetatable({}, { __index = function(_, ty) return M.sizeof(ty) end })
    env.alignof = setmetatable({}, { __index = function(_, ty) return M.alignof(ty) end })
    env.N = setmetatable({}, { __index = function(_, k) return name_token(k) end })
    for n in pairs(scalar) do env[n] = scalar_type(n) end
    env.ptr = ctor("ptr", function(ty) return Ty.TPtr(concrete_type(ty)) end)
    env.view = ctor("view", function(ty) return Ty.TView(concrete_type(ty)) end)
    env.slice = ctor("slice", function(ty) return Ty.TSlice(concrete_type(ty)) end)
    env.array = ctor("array", function(ty) return ctor("array_len", function(n) return Ty.TArray(Ty.ArrayLenConst(tonumber(n)), concrete_type(ty)) end) end)
    env.fnptr = ctor("fnptr", function(params_) return ctor("fnptr_result", function(result) return Ty.TFunc(type_list(params_), concrete_type(result)) end) end)
    env.func_type = env.fnptr
    env.closure = ctor("closure", function(params_) return ctor("closure_result", function(result) return Ty.TClosure(type_list(params_), concrete_type(result)) end) end)
    env.closure_type = env.closure
    env.lease = ctor("lease", function(ty) return Ty.TLease(concrete_type(ty), Ty.LeaseOriginUnknown) end)
    env.owned = ctor("owned", function(ty) return Ty.TOwned(concrete_type(ty)) end)
    for name, access_kind in pairs(access) do
        env[name] = ctor(name, function(ty) return Ty.TAccess(access_kind, concrete_type(ty)) end)
    end
    return env
end

--- Install Moonlift DSL globals into _G so plain .lua files can use
-- fn, i32, module, struct, region, etc. as unqualified names.
-- Also enables auto-name-token generation for unknown identifiers (a, b, pos, etc.),
-- which is the same behavior as the dsl.loadstring() isolated environment.
-- Call this once at the top of any .lua file that authors Moonlift DSL.
--
--   require("moonlift").use()       -- or require("moonlift.dsl").use()
--
-- Returns a managed LLB UseSession for explicit capture if desired:
--   local moon = require("moonlift").use()
--   moon.env.fn. add { ... }
--
-- opts.scope = "permanent" (default) installs into _G until session:close().
-- opts.scope = "scoped" installs into _G and is intended for explicit cleanup.
-- opts.scope = "env" returns an isolated session.env and does not mutate _G.
function M.use(opts)
    opts = opts or {}
    local exports = make_env(opts)
    local session = llb.use(MoonLLB, {
        scope = opts.scope or (opts.global == false and "env" or "permanent"),
        target = opts.target or _G,
        base = exports,
        exports = exports,
        lang_exports = false,
        helpers = false,
        global = opts.global,
        strict = opts.strict,
        strict_message = "unknown DSL global ",
        override = opts.override,
        auto_names = opts.auto_names ~= false,
        auto_name = name_token,
        searcher = opts.searcher,
        mode = opts.mode,
        provides = opts.provides or { "moonlift.types", "moonlift.dsl" },
        requires = opts.requires,
    })
    if opts.searcher then M.install_searcher() end
    M._installed = true
    return session
end

local function compile_source_chunk(src, chunk_name, opts, ctx)
    opts = opts or {}
    local loader = loadstring or load
    local session = M.use({
        scope = "env",
        global = false,
        strict = opts.strict,
        unsafe = opts.unsafe,
        auto_names = opts.auto_names,
        base = opts.base,
    })
    local env = session.env
    local fn, err
    local source_name = chunk_name or "=(moonlift.dsl)"
    local source_ctx = build_source_context(source_name, src)
    if ctx then
        ctx. load {
            language = "moonlift",
            chunk = source_name,
            bytes = #src,
        }
    end
    local function stamp(...)
        local n = select("#", ...)
        for i = 1, n do
            local result = select(i, ...)
            if type(result) == "table" then attach_source_context(result, source_ctx) end
        end
    end
    if loadstring then
        fn, err = loader(src, source_name)
        if not fn then
            if ctx then
                ctx. error {
                    code = "E_MOONLIFT_DSL_LOAD",
                    message = tostring(err),
                    chunk = source_name,
                }
            end
            die(err, 2)
        end
        setfenv(fn, env)
    else
        fn, err = loader(src, source_name, "t", env)
        if not fn then
            if ctx then
                ctx. error {
                    code = "E_MOONLIFT_DSL_LOAD",
                    message = tostring(err),
                    chunk = source_name,
                }
            end
            die(err, 2)
        end
    end
    if ctx then
        ctx. index {
            language = "moonlift",
            chunk = source_name,
            session = session,
            source = source_ctx,
        }
    end
    return function(...)
        if ctx then
            ctx. eval {
                language = "moonlift",
                chunk = source_name,
                argc = select("#", ...),
            }
        end
        local packed = { fn(...) }
        stamp(unpack(packed))
        if ctx then
            ctx. result {
                language = "moonlift",
                chunk = source_name,
                count = #packed,
            }
        end
        return unpack(packed)
    end, {
        session = session,
        source = source_ctx,
        chunk = source_name,
    }
end

M.source = llb.process. source (function(ctx, src, chunk_name, opts)
    opts = opts or {}
    local chunk, meta = compile_source_chunk(src, chunk_name, opts, ctx)
    if opts.eval then
        local args = opts.args or {}
        return chunk(unpack(args, 1, args.n or #args))
    end
    return {
        chunk = chunk,
        session = meta.session,
        source = meta.source,
        name = meta.chunk,
    }
end)

function M.loadstring(src, chunk_name, opts)
    local chunk = compile_source_chunk(src, chunk_name, opts, nil)
    return chunk
end

function M.loadfile(path_, opts)
    local f, err = io.open(path_, "rb")
    if not f then die(err, 2) end
    local src = f:read("*a")
    f:close()
    return M.loadstring(src, path_, opts)
end

-- Convenience: load and execute in one call.
function M.load(src, name, opts)
    local chunk = M.loadstring(src, name, opts)
    return chunk()
end

-- Module lookup: resolve a name to a .lua file, load it, cache it.
-- Searches standard Lua module paths.
M._cache = {}
M._search_paths = {
    "./?.lua",
    "./?/init.lua",
    "lua/?.lua",
    "lua/?/init.lua",
}

function M.require(mod_name)
    if M._cache[mod_name] ~= nil then return M._cache[mod_name] end
    local tried = {}
    for _, template in ipairs(M._search_paths) do
        local path = template:gsub("%?", mod_name)
        local f = io.open(path)
        if f then f:close()
            local chunk = M.loadfile(path)
            local result = chunk()
            M._cache[mod_name] = result
            return result
        end
        tried[#tried + 1] = path
    end
    die("module '" .. mod_name .. "' not found; tried: " .. table.concat(tried, ", "), 2)
end

-- Install a package.searchers entry so Lua's built-in require()
-- auto-injects the DSL environment into .lua files.
function M.install_searcher()
    local searchers = package.searchers or package.loaders
    if not searchers then return end
    for _, s in ipairs(searchers) do
        if s == M._searcher then return end
    end
    local function searcher(mod_name)
        local tried = {}
        for _, template in ipairs(M._search_paths) do
            local path = template:gsub("%?", mod_name)
            local f = io.open(path, "rb")
            if f then
                f:close()
                return function()
                    local chunk = M.loadfile(path)
                    return chunk()
                end
            end
            tried[#tried + 1] = path
        end
        return "\n\tno file found (tried: " .. table.concat(tried, ", ") .. ")"
    end
    M._searcher = searcher
    table.insert(searchers, searcher)
end

function M.make_env(opts) return make_env(opts) end
function M.describe(value) return llb.describe(value or MoonLLB) end
function M.describe_head(name) return MoonLLB:describe_head(name) end
function M.describe_role(name) return MoonLLB:describe_role(name) end
M.T = T

function M.format(value, opts)
    return require("moonlift.dsl.format").format(value, opts)
end

function M.format_file(path, opts)
    return require("moonlift.dsl.format").format_file(path, opts)
end

function M.write_format_file(path, opts)
    return require("moonlift.dsl.format").write_format_file(path, opts)
end

return M
