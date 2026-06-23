-- Lua-owned Moonlift DSL.
--
-- This surface does not treat [] as textual splice syntax. Lua evaluates the
-- bracket expression before this module sees it, so x[T] carries the actual
-- Lua value T. Normalization then consumes those already-resolved values by
-- role and emits MoonSyntax/MoonTree ASDL directly.

local pvm = require("moonlift.pvm")
local schema = require("moonlift.asdl")
local SyntaxLower = require("moonlift.syntax_lower")

local M = {}

local T = pvm.context()
schema.Define(T)

local C, Ty, B, Tr, O, S = T.MoonCore, T.MoonType, T.MoonBind, T.MoonTree, T.MoonOpen, T.MoonSyntax
local lower = SyntaxLower.Define(T)

local function class(name)
    local mt = { __dsl_class = name }
    mt.__index = mt
    return mt
end

local Name = class("Name")
local TypedName = class("TypedName")
local Payload = class("Payload")
local Head = class("Head")
local TypeCtor = class("TypeCtor")
local Expr = class("Expr")
local Stmt = class("Stmt")
local Decl = class("Decl")
local Fragment = class("Fragment")
local Spread = class("Spread")
local Case = class("Case")
local Default = class("Default")

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

local function name_token(s) return setmetatable({ name = ident(s, "name") }, Name) end

local scalar = {
    void = C.ScalarVoid, bool = C.ScalarBool,
    i8 = C.ScalarI8, i16 = C.ScalarI16, i32 = C.ScalarI32, i64 = C.ScalarI64,
    u8 = C.ScalarU8, u16 = C.ScalarU16, u32 = C.ScalarU32, u64 = C.ScalarU64,
    f32 = C.ScalarF32, f64 = C.ScalarF64, index = C.ScalarIndex, rawptr = C.ScalarRawPtr,
}

local function scalar_type(name) return Ty.TScalar(assert(scalar[name], "unknown scalar")) end

local function syn_name(v)
    if is(v, Name) then return S.SyntaxNameText(v.name) end
    if type(v) == "string" then return S.SyntaxNameText(ident(v, "name")) end
    die("expected name", 2)
end

local function frag_ref(v, expr)
    if is(v, Name) then return S.SyntaxFragRefPath(path(v.name)) end
    if type(v) == "string" then return S.SyntaxFragRefPath(path(v)) end
    if is(v, Decl) and (v.kind == "region" or v.kind == "expr_frag") then return S.SyntaxFragRefPath(path(v.name)) end
    if expr and is_member(O.ExprFrag, v) then return S.SyntaxFragRefSplice(S.SpliceId("__dsl_expr_frag", "expr_frag")) end
    if (not expr) and is_member(O.RegionFrag, v) then return S.SyntaxFragRefSplice(S.SpliceId("__dsl_region_frag", "region_frag")) end
    return S.SyntaxFragRefPath(path(tostring(v)))
end

local function syn_type(v)
    if is_member(S.Type, v) then return v end
    if is_member(Ty.Type, v) then return S.SyntaxTypeTree(v) end
    if is(v, Decl) and v.type_name then return S.SyntaxTypeTree(Ty.TNamed(Ty.TypeRefPath(path(v.type_name)))) end
    if type(v) == "string" then return S.SyntaxTypePath(path(v)) end
    die("expected type value, got " .. tostring(v), 2)
end

local function concrete_type(v) return lower.type(syn_type(v)) end

local function tree_expr(v)
    if is(v, Expr) then return v:tree() end
    if is_member(Tr.Expr, v) then return v end
    if v == nil then return Tr.ExprLit(Tr.ExprSurface, C.LitNil) end
    if type(v) == "number" then return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(v))) end
    if type(v) == "boolean" then return Tr.ExprLit(Tr.ExprSurface, C.LitBool(v)) end
    if type(v) == "string" then return Tr.ExprLit(Tr.ExprSurface, C.LitString(v)) end
    if is(v, Name) then return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(v.name)) end
    die("expected expression value, got " .. tostring(v), 2)
end

local syn_expr
local expand_array

local function expr_item(v) return S.SyntaxExprItemOne(syn_expr(v)) end
local function expr_items(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "expr")) do out[i] = expr_item(v) end
    return out
end
local function stmt_item(v)
    if is(v, Spread) then die("statement spread needs a statement fragment", 2) end
    if is_member(S.Stmt, v) then return S.SyntaxStmtItemOne(v) end
    if is(v, Stmt) then return S.SyntaxStmtItemOne(v:syntax()) end
    if is_member(Tr.Stmt, v) then return S.SyntaxStmtItemOne(S.SyntaxStmtTree(v)) end
    return S.SyntaxStmtItemOne(S.SyntaxStmtExpr(syn_expr(v)))
end

function expand_array(t, role)
    local out = {}
    for i = 1, #(t or {}) do
        local v = t[i]
        if is(v, Spread) then
            local frag = v.value
            if is(frag, Fragment) then
                if frag.role ~= role then die("expected " .. role .. " fragment, got " .. tostring(frag.role), 2) end
                for j = 1, #frag.items do out[#out + 1] = frag.items[j] end
            elseif type(frag) == "table" then
                for j = 1, #frag do out[#out + 1] = frag[j] end
            else
                die("spread expects a fragment or array", 2)
            end
        elseif is(v, Fragment) and v.role == role then
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
        out[i] = open and S.SyntaxOpenParamItemOne(v.name, syn_type(v.ty))
            or S.SyntaxParamItemOne(v.name, syn_type(v.ty))
    end
    return out
end

local function field_items(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("field expects name [type]", 2) end
        out[i] = S.SyntaxFieldItemOne(v.name, syn_type(v.ty))
    end
    return out
end

local function block_param_items(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("block parameter expects name [type]", 2) end
        out[i] = S.SyntaxBlockParamItemOne(v.name, syn_type(v.ty))
    end
    return out
end

local function entry_param_items(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("entry parameter expects name [type](init)", 2) end
        out[i] = S.SyntaxEntryParamItemOne(v.name, syn_type(v.ty), syn_expr(v.init or 0))
    end
    return out
end

local function stmt_items(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "stmt")) do out[i] = stmt_item(v) end
    return out
end

local function tree_stmt(v) return lower.stmt(stmt_item(v).stmt) end

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

local function tree_fields(t)
    local out = {}
    for i, v in ipairs(expand_array(t or {}, "product")) do
        if not is(v, TypedName) then die("field expects name [type]", 2) end
        out[i] = Ty.FieldDecl(v.name, concrete_type(v.ty))
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
    return { S.SyntaxStmtItemOne(S.SyntaxStmtTree(Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion("dsl.func." .. tostring(name), entry, blocks)))) }
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
    local k_class = pvm.classof(k)
    if type(k_class) == "table" and tostring(k_class):match("^Class%(%s*MoonType%.") then
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
    if k == "cast" then return Tr.ExprCast(Tr.ExprSurface, self.cast, lower.type(syn_type(self.ty)), tree_expr(self.value)) end
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
    if k == "emit_expr" then return lower.expr(S.SyntaxExprEmit(frag_ref(self.target, true), expr_items(self.args)), self.env) end
    if k == "select" then return Tr.ExprSelect(Tr.ExprSurface, tree_expr(self.cond), tree_expr(self.a), tree_expr(self.b)) end
    die("unsupported expression kind " .. tostring(k), 2)
end

function Expr:syntax() return S.SyntaxExprTree(self:tree()) end

syn_expr = function(v)
    if is_member(S.Expr, v) then return v end
    if is(v, Expr) then return v:syntax() end
    if is_member(Tr.Expr, v) then return S.SyntaxExprTree(v) end
    return S.SyntaxExprTree(tree_expr(v))
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

local bind_seq = 0
local function binding(name, ty, class)
    bind_seq = bind_seq + 1
    return B.Binding(C.Id("dsl:" .. name .. ":" .. bind_seq), name, lower.type(syn_type(ty)), class)
end

function Stmt:syntax()
    local k = self.kind
    if k == "ret" then
        if self.value == nil then return S.SyntaxStmtTree(Tr.StmtReturnVoid(Tr.StmtSurface)) end
        return S.SyntaxStmtReturnValue(syn_expr(self.value))
    end
    if k == "yield" then
        if self.value == nil then return S.SyntaxStmtTree(Tr.StmtYieldVoid(Tr.StmtSurface)) end
        return S.SyntaxStmtYieldValue(syn_expr(self.value))
    end
    if k == "let" then return S.SyntaxStmtLet(binding(self.name, self.ty, B.BindingClassLocalValue), syn_expr(self.init)) end
    if k == "var" then return S.SyntaxStmtVar(binding(self.name, self.ty, B.BindingClassLocalCell), syn_expr(self.init)) end
    if k == "when" then return S.SyntaxStmtIf(syn_expr(self.cond), stmt_items(self.body), {}) end
    if k == "if" then return S.SyntaxStmtIf(syn_expr(self.cond), stmt_items(self.then_body), stmt_items(self.else_body or {})) end
    if k == "set" then return S.SyntaxStmtTree(Tr.StmtSet(Tr.StmtSurface, tree_place(self.place), tree_expr(self.value))) end
    if k == "assert" then return S.SyntaxStmtTree(Tr.StmtAssert(Tr.StmtSurface, tree_expr(self.cond))) end
    if k == "trap" then return S.SyntaxStmtTree(Tr.StmtTrap(Tr.StmtSurface)) end
    if k == "assume" then return S.SyntaxStmtTree(Tr.StmtExpr(Tr.StmtSurface, Tr.ExprIntrinsic(Tr.ExprSurface, C.IntrinsicAssume, { tree_expr(self.cond) }))) end
    if k == "jump" then
        local args = {}
        for name, value in pairs(self.args or {}) do args[#args + 1] = Tr.JumpArg(name, tree_expr(value)) end
        return S.SyntaxStmtTree(Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel(self.target), args))
    end
    if k == "emit" then
        return S.SyntaxStmtEmit(self.mode or Tr.RegionUseEmit, frag_ref(self.target, false), expr_items(self.args), self.conts or {})
    end
    if k == "switch" then return S.SyntaxStmtTree(Tr.StmtSwitch(Tr.StmtSurface, tree_expr(self.value), self.arms or {}, self.variant_arms or {}, tree_stmts(self.default_body or {}))) end
    if k == "expr" then return S.SyntaxStmtExpr(syn_expr(self.expr)) end
    die("unsupported statement kind " .. tostring(k), 2)
end

function Stmt:ast() return lower.stmt(self:syntax()) end

function M.ret(t) return setmetatable({ kind = "ret", value = t }, Stmt) end
function M.yield(t) return setmetatable({ kind = "yield", value = t }, Stmt) end
function M.when(t) return function(b) return setmetatable({ kind = "when", cond = t, body = b or {} }, Stmt) end end
function M.If(t) return function(b) return setmetatable({ kind = "if", cond = t, then_body = b or {} }, { __call = function(self, else_body) self.else_body = else_body or {}; return self end, __index = Stmt }) end end
function M.store(place, value) return setmetatable({ kind = "set", place = place, value = value }, Stmt) end
M.set = M.store
function M.assert_(t) return setmetatable({ kind = "assert", cond = t }, Stmt) end
function M.trap() return setmetatable({ kind = "trap" }, Stmt) end
function M.assume(t) return setmetatable({ kind = "assume", cond = t }, Stmt) end

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
            if is(v, Payload) then vars[i] = S.SyntaxVariantItemOne(v.name, S.SyntaxTypeTree(scalar_type("void")), field_items(v.payload))
            elseif is(v, Name) then vars[i] = S.SyntaxVariantItemOne(v.name, S.SyntaxTypeTree(scalar_type("void")), {})
            else die("union expects alternatives", 2) end
        end
        return S.SyntaxTypeDeclUnion(S.SyntaxNameText(name), vars)
    end
    return S.SyntaxTypeDeclStruct(S.SyntaxNameText(name), field_items(body))
end

function Decl:syntax()
    if self.kind == "module" then
        local items = {}
        for i, d in ipairs(expand_array(self.body, "decl")) do
            if is(d, Decl) then items[#items + 1] = d:syntax_item()
            elseif is_member(S.Item, d) then items[#items + 1] = d
            elseif is_member(Tr.Item, d) then items[#items + 1] = S.SyntaxItemTree(d)
            else die("module body expects declarations", 2) end
        end
        return S.Module(items)
    end
    die("only modules have standalone syntax()", 2)
end

local function module_ast_of(self)
    if self.kind == "module" then return lower.module(self:syntax()) end
    return lower.module(S.Module({ self:syntax_item() }))
end

function Decl:typecheck(opts)
    opts = opts or {}
    local Typecheck = require("moonlift.tree_typecheck").Define(T)
    return Typecheck.check_module(module_ast_of(self), opts)
end

function Decl:syntax_item()
    if self.kind == "struct" then return S.SyntaxItemTypeDecl(type_decl(self.name, self.body, false)) end
    if self.kind == "union" then return S.SyntaxItemTypeDecl(type_decl(self.name, self.body, true)) end
    if self.kind == "fn" then
        return S.SyntaxItemFunc(S.SyntaxFuncLocal(self.name, param_items(self.params), syn_type(self.result or scalar_type("void")), {}, function_body_items(self.name, self.body)))
    end
    if self.kind == "export_fn" then
        return S.SyntaxItemFunc(S.SyntaxFuncExport(self.name, param_items(self.params), syn_type(self.result or scalar_type("void")), {}, function_body_items(self.name, self.body)))
    end
    if self.kind == "extern" then
        return S.SyntaxItemTree(Tr.ItemExtern(Tr.ExternFunc(self.name, self.opts.symbol or self.name, tree_params(self.params), concrete_type(self.result or scalar_type("void")))))
    end
    if self.kind == "handle" then
        local facts = {}
        if self.opts.domain then facts[#facts + 1] = Ty.HandleDomain(Ty.TypeRefPath(path(self.opts.domain))) end
        if self.opts.target then facts[#facts + 1] = Ty.HandleTarget(Ty.TypeRefPath(path(self.opts.target))) end
        return S.SyntaxItemTree(Tr.ItemType(Tr.TypeDeclHandle(self.name, handle_repr(self.repr or self.opts.repr), handle_invalid(self.opts.invalid), facts)))
    end
    if self.kind == "const" then
        return S.SyntaxItemTree(Tr.ItemConst(Tr.ConstItem(self.name, concrete_type(self.ty), tree_expr(self.value))))
    end
    if self.kind == "static" then
        return S.SyntaxItemTree(Tr.ItemStatic(Tr.StaticItem(self.name, concrete_type(self.ty), tree_expr(self.value))))
    end
    if self.kind == "import" then
        return S.SyntaxItemTree(Tr.ItemImport(Tr.ImportItem(path(self.name))))
    end
    if self.kind == "expr_frag" then
        return S.SyntaxItemExprFrag(S.ExprFrag(O.NameRefText(self.name), param_items(self.params, true), syn_type(self.result), syn_expr(self.body)))
    end
    if self.kind == "region" then
        local entry = self.entry or { name = "entry", params = {}, body = {} }
        local blocks = {}
        for _, b in ipairs(self.blocks or {}) do
            blocks[#blocks + 1] = S.SyntaxControlBlockItemOne(S.SyntaxNameText(b.name), block_param_items(b.params), stmt_items(b.body))
        end
        local conts = {}
        for i, c in ipairs(self.conts or {}) do
            if is(c, Payload) then conts[i] = S.SyntaxContItemOne(S.SyntaxNameText(c.name), block_param_items(c.payload))
            elseif is(c, Name) then conts[i] = S.SyntaxContItemOne(S.SyntaxNameText(c.name), {})
            else die("region continuation expects named payload", 2) end
        end
        return S.SyntaxItemRegionFrag(S.RegionFrag(O.NameRefText(self.name), param_items(self.params, true), conts, S.SyntaxNameText(entry.name), entry_param_items(entry.params), stmt_items(entry.body), blocks))
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

function Decl:lower(opts)
    opts = opts or {}
    local Pipeline = require("moonlift.frontend_pipeline").Define(T)
    opts.site = opts.site or "moonlift.dsl"
    return Pipeline.lower_module(module_ast_of(self), opts)
end

function Decl:emit_c_artifact(opts)
    opts = opts or {}
    local Pipeline = require("moonlift.frontend_pipeline").Define(T)
    opts.site = opts.site or "moonlift.dsl c"
    local result = Pipeline.lower_module_to_c(module_ast_of(self), opts)
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
    opts = opts or {}
    if opts.backend == "c" or opts.codegen == "c" then return self:emit_c_artifact(opts) end
    local result = self:lower(opts)
    local jit = require("moonlift.back_jit").Define(T).jit()
    for name, ptr in pairs(opts.symbols or {}) do jit:symbol(name, ptr) end
    return jit:compile(result.program)
end

function Decl:__tostring()
    return "moonlift.dsl." .. tostring(self.kind) .. (self.name and "(" .. tostring(self.name) .. ")" or "")
end

local function head(kind, name) return setmetatable({ kind = kind, name = name }, Head) end

Head.__index = function(self, k)
    if Head[k] then return Head[k] end
    local kind = rawget(self, "kind")
    local name = rawget(self, "name")
    if type(k) ~= "string" then
        if kind == "const" or kind == "static" then
            return function(value) return setmetatable({ kind = kind, name = name, ty = k, value = value }, Decl) end
        end
        return setmetatable({ kind = kind, name = is(k, Name) and k.name or nil, target = k }, Head)
    end
    return head(kind, ident(k, "head name"))
end

local function fn_stage(kind, name, params_)
    return setmetatable({ params = params_ or {} }, {
        __index = function(_, result)
            return function(body) return setmetatable({ kind = kind, name = name, params = params_ or {}, result = result, body = body or {} }, Decl) end
        end,
        __call = function(_, body) return setmetatable({ kind = kind, name = name, params = params_ or {}, body = body or {} }, Decl) end,
    })
end

local function extern_stage(name, params_)
    return setmetatable({ params = params_ or {} }, {
        __index = function(_, result)
            return function(opts) return setmetatable({ kind = "extern", name = name, params = params_ or {}, result = result, opts = opts or {} }, Decl) end
        end,
        __call = function(_, opts) return setmetatable({ kind = "extern", name = name, params = params_ or {}, opts = opts or {} }, Decl) end,
    })
end

local function typed_decl_stage(kind, name)
    return setmetatable({}, {
        __index = function(_, ty)
            return function(value) return setmetatable({ kind = kind, name = name, ty = ty, value = value }, Decl) end
        end,
    })
end

function Head:__call(t)
    local kind = rawget(self, "kind")
    local name = rawget(self, "name")
    if kind == "module" and name == nil then return head("module", tostring(t)) end
    if kind == "module" then return setmetatable({ kind = "module", name = name, body = t or {} }, Decl) end
    if kind == "struct" or kind == "union" then return setmetatable({ kind = kind, name = name, type_name = name, body = t or {} }, Decl) end
    if kind == "fn" or kind == "export_fn" then return fn_stage(kind, name, t or {}) end
    if kind == "region" then
        if type(t) == "table" and (t.params or t.conts or t.body) then
            local entry, blocks = nil, {}
            for _, item in ipairs(t.body or {}) do
                if type(item) == "table" and item.kind == "entry_decl" then entry = item
                elseif type(item) == "table" and item.kind == "block_decl" then blocks[#blocks + 1] = item
                else die("region body expects entry/block declarations", 2) end
            end
            return setmetatable({ kind = "region", name = name, params = t.params or {}, conts = t.conts or {}, entry = entry, blocks = blocks }, Decl)
        end
        return function(conts)
            return function(body)
                local entry, blocks = nil, {}
                for _, item in ipairs(body or {}) do
                    if type(item) == "table" and item.kind == "entry_decl" then entry = item
                    elseif type(item) == "table" and item.kind == "block_decl" then blocks[#blocks + 1] = item
                    else die("region body expects entry/block declarations", 2) end
                end
                return setmetatable({ kind = "region", name = name, params = t or {}, conts = conts or {}, entry = entry, blocks = blocks }, Decl)
            end
        end
    end
    if kind == "extern" then return extern_stage(name, t or {}) end
    if kind == "handle" then return setmetatable({ kind = "handle", name = name, opts = t or {} }, Decl) end
    if kind == "const" or kind == "static" then return typed_decl_stage(kind, name) end
    if kind == "import" then return setmetatable({ kind = "import", name = t or name }, Decl) end
    if kind == "expr_frag" then
        return setmetatable({ params = t or {} }, {
            __index = function(_, result)
                return function(body) return setmetatable({ kind = "expr_frag", name = name, params = t or {}, result = result, body = body }, Decl) end
            end,
        })
    end
    if kind == "jump" then return setmetatable({ kind = "jump", target = name, args = t or {} }, Stmt) end
    if kind == "emit" then
        return setmetatable({ kind = "emit", target = rawget(self, "target") or name, args = t or {} }, {
            __call = function(self, fills)
                local conts = {}
                for cname, target in pairs(fills or {}) do
                    conts[#conts + 1] = O.ContBinding(cname, O.ContTargetLabel(Tr.BlockLabel(is(target, Name) and target.name or tostring(target))))
                end
                self.conts = conts
                return setmetatable(self, Stmt)
            end,
            __index = Stmt,
        })
    end
    if kind == "case" then
        return function(body) return setmetatable({ key = name_token(name), binds = t or {}, body = body or {} }, Case) end
    end
    if kind == "entry" then return function(body) return { kind = "entry_decl", name = name, params = t or {}, body = body or {} } end end
    if kind == "block" then return function(body) return { kind = "block_decl", name = name, params = t or {}, body = body or {} } end end
    die("unsupported head call " .. tostring(kind), 2)
end

local function ctor(name, fn)
    return setmetatable({ name = name, fn = fn }, TypeCtor)
end

function TypeCtor:__index(k)
    if TypeCtor[k] then return TypeCtor[k] end
    return self.fn(k)
end

function TypeCtor:__call(a, b)
    if rawget(self, "name") == "lease" and b ~= nil then
        return Ty.TLease(concrete_type(b), Ty.LeaseOriginParam(is(a, Name) and a.name or tostring(a)))
    end
    die("type constructor `" .. tostring(rawget(self, "name")) .. "` uses [] syntax", 2)
end

function M.product(t) return setmetatable({ role = "product", items = t or {} }, Fragment) end
function M.stmts(t) return setmetatable({ role = "stmt", items = t or {} }, Fragment) end
function M.decls(t) return setmetatable({ role = "decl", items = t or {} }, Fragment) end
function M.exprs(t) return setmetatable({ role = "expr", items = t or {} }, Fragment) end
function M.spread(v) return setmetatable({ value = v }, Spread) end

function Fragment:__len() return #(self.items or {}) end
function Fragment:__tostring() return "moonlift.dsl.fragment(" .. tostring(self.role) .. ", " .. tostring(#(self.items or {})) .. ")" end

local function name_head_stmt(kind)
    return setmetatable({}, {
        __index = function(_, k)
            return setmetatable({ name = ident(k, kind) }, {
                __index = function(stage, ty)
                    return function(init) return setmetatable({ kind = kind, name = stage.name, ty = ty, init = init }, Stmt) end
                end,
            })
        end,
    })
end

function M.case(v)
    return setmetatable({ key = v }, {
        __call = function(self, body) return setmetatable({ key = self.key, body = body or {} }, Case) end,
    })
end

function M.default(body) return setmetatable({ body = body or {} }, Default) end

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

local function make_env(opts)
    opts = opts or {}
    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env.module, env.fn, env.export_fn = head("module"), head("fn"), head("export_fn")
    env.extern, env.handle, env.const, env.static = head("extern"), head("handle"), head("const"), head("static")
    env.import, env.expr_frag = head("import"), head("expr_frag")
    env.struct, env.union, env.region = head("struct"), head("union"), head("region")
    env.entry, env.block, env.jump, env.emit = head("entry"), head("block"), head("jump"), head("emit")
    env.ret, env.yield, env.when, env.If = M.ret, M.yield, M.when, M.If
    env.let, env.var = name_head_stmt("let"), name_head_stmt("var")
    env.store, env.set, env.trap, env.assume, env.assert_ = M.store, M.set, M.trap, M.assume, M.assert_
    env.switch, env.case, env.default = M.switch, head("case"), M.default
    env.case_value = M.case
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
    env.product, env.stmts, env.decls, env.exprs, env.spread = M.product, M.stmts, M.decls, M.exprs, M.spread
    env.eq, env.ne, env.lt, env.le, env.gt, env.ge = M.eq, M.ne, M.lt, M.le, M.gt, M.ge
    env.And, env.Or, env.Not, env.len, env.select = M.And, M.Or, M.Not, M.len, M.select
    env.addr, env.deref, env.load, env.is_null = M.addr, M.deref, M.load, M.is_null
    env.as = setmetatable({}, { __index = function(_, ty) return M.as(ty) end })
    env.bitcast = setmetatable({}, { __index = function(_, ty) return M.bitcast(ty) end })
    env.null = setmetatable({}, { __index = function(_, ty) return M.null(ty) end })
    env.sizeof = setmetatable({}, { __index = function(_, ty) return M.sizeof(ty) end })
    env.alignof = setmetatable({}, { __index = function(_, ty) return M.alignof(ty) end })
    env.N = setmetatable({}, { __index = function(_, k) return name_token(k) end })
    for n in pairs(scalar) do env[n] = scalar_type(n) end
    env.ptr = ctor("ptr", function(ty) return S.SyntaxTypePtr(syn_type(ty)) end)
    env.view = ctor("view", function(ty) return S.SyntaxTypeView(syn_type(ty)) end)
    env.slice = ctor("slice", function(ty) return S.SyntaxTypeSlice(syn_type(ty)) end)
    env.array = ctor("array", function(ty) return ctor("array_len", function(n) return Ty.TArray(Ty.ArrayLenConst(tonumber(n)), concrete_type(ty)) end) end)
    env.fnptr = ctor("fnptr", function(params_) return ctor("fnptr_result", function(result) return Ty.TFunc(type_list(params_), concrete_type(result)) end) end)
    env.func_type = env.fnptr
    env.closure = ctor("closure", function(params_) return ctor("closure_result", function(result) return Ty.TClosure(type_list(params_), concrete_type(result)) end) end)
    env.closure_type = env.closure
    env.lease = ctor("lease", function(ty) return S.SyntaxTypeLease(syn_type(ty)) end)
    env.owned = ctor("owned", function(ty) return Ty.TOwned(lower.type(syn_type(ty))) end)
    for name, access_kind in pairs(access) do
        env[name] = ctor(name, function(ty) return Ty.TAccess(access_kind, concrete_type(ty)) end)
    end
    return setmetatable(env, {
        __index = function(t, k)
            local n = name_token(k)
            rawset(t, k, n)
            return n
        end,
        __newindex = function(t, k, v)
            if opts.strict and rawget(t, k) == nil then die("assignment to unknown DSL global `" .. tostring(k) .. "`", 2) end
            rawset(t, k, v)
        end,
    })
end

function M.loadstring(src, chunk_name, opts)
    local loader = loadstring or load
    local env = make_env(opts)
    local fn, err
    if loadstring then
        fn, err = loader(src, chunk_name or "=(moonlift.dsl)")
        if not fn then die(err, 2) end
        setfenv(fn, env)
    else
        fn, err = loader(src, chunk_name or "=(moonlift.dsl)", "t", env)
        if not fn then die(err, 2) end
    end
    return fn
end

function M.loadfile(path_, opts)
    local f, err = io.open(path_, "rb")
    if not f then die(err, 2) end
    local src = f:read("*a")
    f:close()
    return M.loadstring(src, path_, opts)
end

function M.make_env(opts) return make_env(opts) end
M.T = T
M.lower = lower

return M
