-- Canonical formatter for evaluated Lalin DSL values.
--
-- This is deliberately semantic formatting: it prints Lalin values produced
-- by evaluating Lua/LLBL DSL code. It is not a Lua token formatter and does not
-- promise comment or metaprogram source preservation.

local llbl = require("llbl")
local asdl = require("lalin.asdl")
local schema = require("lalin.schema_projection")

local M = {}

local T = asdl.context()
schema(T)

local C, Ty, Tr = T.LalinCore, T.LalinType, T.LalinTree
local d = llbl.doc

local scalar_labels = {
    ScalarVoid = "void", ScalarBool = "bool",
    ScalarI8 = "i8", ScalarI16 = "i16", ScalarI32 = "i32", ScalarI64 = "i64",
    ScalarU8 = "u8", ScalarU16 = "u16", ScalarU32 = "u32", ScalarU64 = "u64",
    ScalarF32 = "f32", ScalarF64 = "f64", ScalarRawPtr = "rawptr", ScalarIndex = "index",
}

local bin_symbols = {
    add = "+", sub = "-", mul = "*", div = "/", rem = "%",
    band = "&", bor = "|", bxor = "~", shl = "<<", lshr = ">>>", ashr = ">>",
}

local cmp_names = { eq = "eq", ne = "ne", lt = "lt", le = "le", gt = "gt", ge = "ge" }

local bin_kind_symbols = {
    BinAdd = "+", BinSub = "-", BinMul = "*", BinDiv = "/", BinRem = "%",
    BinBitAnd = "&", BinBitOr = "|", BinBitXor = "~", BinShl = "<<", BinLShr = ">>>", BinAShr = ">>",
}

local cmp_kind_names = {
    CmpEq = "eq", CmpNe = "ne", CmpLt = "lt", CmpLe = "le", CmpGt = "gt", CmpGe = "ge",
}

local access_names = {
    TypeAccessNoAlias = "noalias",
    TypeAccessReadonly = "readonly",
    TypeAccessWriteonly = "writeonly",
    TypeAccessNoEscape = "noescape",
    TypeAccessInvalidate = "invalidate",
    TypeAccessPreserve = "preserve",
}

local function cls_kind(v)
    local cls = asdl.classof(v)
    return cls and cls.kind or nil
end

local function dsl_class(v)
    local mt = type(v) == "table" and getmetatable(v) or nil
    return mt and rawget(mt, "__dsl_class") or nil
end

local function is_array(t)
    if type(t) ~= "table" then return false end
    local n = #t
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then return false end
    end
    return true
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t or {}) do
        if type(k) ~= "number" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function path_text(path)
    local parts = {}
    for i = 1, #(path and path.parts or {}) do parts[i] = path.parts[i].text end
    return table.concat(parts, ".")
end

local function type_ref_text(ref)
    local k = cls_kind(ref)
    if k == "TypeRefGlobal" then return ref.type_name end
    if k == "TypeRefLocal" then return ref.sym and ref.sym.name or tostring(ref.sym) end
    if k == "TypeRefPath" then return path_text(ref.path) end
    return tostring(ref)
end

local function array_len_text(len)
    local k = cls_kind(len)
    if k == "ArrayLenConst" then return tostring(len.count) end
    return tostring(len)
end

local function make_context(opts)
    if getmetatable(opts) == llbl.FormatContext then return opts end
    opts = opts or {}
    local ctx = llbl.FormatContext and setmetatable({
        opts = opts,
        dialect = opts.dialect,
        width = opts.width or 100,
        indent_width = opts.indent or 2,
        seen = opts.seen or {},
    }, llbl.FormatContext)
    return ctx
end

local fmt_value, fmt_type, fmt_expr, fmt_stmt, fmt_decl, fmt_tree_expr, fmt_tree_stmt

local function paren_expr(v, f)
    return d.parens(fmt_expr(v, f))
end

local function dot_name(name)
    return d.concat { ". ", tostring(name) }
end

local function call_args(args, f)
    args = args or {}
    if #args == 0 then return d.text("()") end
    local docs = {}
    for i = 1, #args do docs[i] = fmt_value(args[i], f) end
    return d.group { "(", d.indent({ d.softline(), d.join(d.concat { ",", d.line() }, docs) }, f.indent_width), d.softline(), ")" }
end

local function curried_args(args, f)
    args = args or {}
    if #args == 0 then return d.text("()") end
    local docs = {}
    for i = 1, #args do
        docs[#docs + 1] = i == 1 and " (" or ")("
        docs[#docs + 1] = fmt_value(args[i], f)
    end
    docs[#docs + 1] = ")"
    return d.group(docs)
end

local function braced_product(items, f, item_fmt)
    items = items or {}
    if #items == 0 then return d.text("{}") end
    local docs = {}
    for i = 1, #items do docs[i] = item_fmt(items[i], f) end
    return d.group {
        "{",
        d.indent({ d.softline(), d.join(d.concat { ",", d.line() }, docs) }, f.indent_width),
        d.softline(),
        "}",
    }
end

local function braced_record(t, f)
    local keys = sorted_keys(t)
    if #keys == 0 then return d.text("{}") end
    local docs = {}
    for i = 1, #keys do
        local k = keys[i]
        docs[i] = d.group { tostring(k), " = ", fmt_value(t[k], f) }
    end
    return d.group {
        "{",
        d.indent({ d.softline(), d.join(d.concat { ",", d.line() }, docs) }, f.indent_width),
        d.softline(),
        "}",
    }
end

local function cont_target_doc(target)
    local k = cls_kind(target)
    if k == "ContTargetLabel" and target.label then return d.text(target.label.name) end
    return d.text(tostring(target))
end

local function cont_bindings_record(conts, f)
    conts = conts or {}
    if #conts == 0 then return d.text("{}") end
    local docs = {}
    for i = 1, #conts do
        local c = conts[i]
        if cls_kind(c) == "ContBinding" then
            docs[#docs + 1] = d.group { tostring(c.name), " = ", cont_target_doc(c.target) }
        end
    end
    if #docs == 0 then return d.text("{}") end
    return d.group {
        "{",
        d.indent({ d.softline(), d.join(d.concat { ",", d.line() }, docs) }, f.indent_width),
        d.softline(),
        "}",
    }
end

local function block(items, f, item_fmt)
    items = items or {}
    if #items == 0 then return d.text("{}") end
    local docs = {}
    for i = 1, #items do
        docs[#docs + 1] = item_fmt(items[i], f)
        docs[#docs + 1] = ","
        if i < #items then docs[#docs + 1] = d.line() end
    end
    return d.concat { "{", d.indent({ d.line(), docs }, f.indent_width), d.line(), "}" }
end

local function typed_name(v, f)
    local out = { tostring(v.name), " [", fmt_type(v.ty or v.type, f), "]" }
    if v.init ~= nil then
        out[#out + 1] = " ("
        out[#out + 1] = fmt_expr(v.init, f)
        out[#out + 1] = ")"
    end
    return d.group(out)
end

local function payload(v, f)
    return d.group { dot_name(v.name), " ", braced_product(v.payload or {}, f, typed_name) }
end

fmt_type = function(ty, f)
    if ty == nil then return d.text("void") end
    local c = dsl_class(ty)
    if c == "Name" then return d.text(ty.name) end
    if c == "Decl" and ty.type_name then return d.text(ty.type_name) end
    if type(ty) == "string" then return d.text(ty) end

    local k = cls_kind(ty)
    if scalar_labels[k] then return d.text(scalar_labels[k]) end
    if k == "TScalar" then
        local sk = cls_kind(ty.scalar)
        return d.text(scalar_labels[sk] or tostring(ty.scalar))
    end
    if k == "TPtr" then return d.group { "ptr [", fmt_type(ty.elem, f), "]" } end
    if k == "TView" then return d.group { "view [", fmt_type(ty.elem, f), "]" } end
    if k == "TSlice" then return d.group { "slice [", fmt_type(ty.elem, f), "]" } end
    if k == "TArray" then return d.group { "array [", fmt_type(ty.elem, f), "] [", array_len_text(ty.count), "]" } end
    if k == "TLease" then return d.group { "lease [", fmt_type(ty.base, f), "]" } end
    if k == "TOwned" then return d.group { "owned [", fmt_type(ty.base, f), "]" } end
    if k == "TAccess" then
        local ak = cls_kind(ty.access)
        return d.group { access_names[ak] or tostring(ty.access), " [", fmt_type(ty.base, f), "]" }
    end
    if k == "THandle" then return d.text(type_ref_text(ty.ref)) end
    if k == "TNamed" then return d.text(type_ref_text(ty.ref)) end
    if k == "TFunc" or k == "TClosure" then
        local params = {}
        for i = 1, #(ty.params or {}) do params[i] = fmt_type(ty.params[i], f) end
        return d.group {
            k == "TClosure" and "closure " or "fnptr ",
            braced_product(params, f, function(x) return x end),
            " [",
            fmt_type(ty.result, f),
            "]",
        }
    end
    return d.text(tostring(ty))
end

local function literal(v)
    local tv = type(v)
    if tv == "string" then return d.text(string.format("%q", v)) end
    if tv == "number" or tv == "boolean" then return d.text(tostring(v)) end
    if tv == "nil" then return d.text("nil") end
    return nil
end

local function core_literal(lit)
    local k = cls_kind(lit)
    if k == "LitInt" or k == "LitFloat" then return d.text(lit.raw) end
    if k == "LitBool" then return d.text(tostring(lit.value)) end
    if k == "LitString" then return d.text(string.format("%q", lit.bytes)) end
    if k == "LitNil" then return d.text("nil") end
    return d.text(tostring(lit))
end

local function value_ref(ref)
    local k = cls_kind(ref)
    if k == "ValueRefName" then return d.text(ref.name) end
    if k == "ValueRefPath" then return d.text(path_text(ref.path)) end
    if k == "ValueRefBinding" then return d.text(ref.binding.name) end
    return d.text(tostring(ref))
end

local function fmt_place(place, f)
    local k = cls_kind(place)
    if k == "PlaceRef" then return value_ref(place.ref) end
    if k == "PlaceDeref" then return d.group { "deref (", fmt_tree_expr(place.base, f), ")" } end
    if k == "PlaceDot" then return d.group { fmt_place(place.base, f), ".", place.name } end
    if k == "PlaceIndex" then
        local base = place.base
        local bk = cls_kind(base)
        local base_doc = bk == "IndexBasePlace" and fmt_place(base.base, f) or bk == "IndexBaseExpr" and fmt_tree_expr(base.base, f) or d.text(tostring(base))
        return d.group { base_doc, "[", fmt_tree_expr(place.index, f), "]" }
    end
    return d.text(tostring(place))
end

fmt_tree_expr = function(e, f)
    local k = cls_kind(e)
    if k == "ExprLit" then return core_literal(e.value) end
    if k == "ExprRef" then return value_ref(e.ref) end
    if k == "ExprDot" then return d.group { fmt_tree_expr(e.base, f), ".", e.name } end
    if k == "ExprBinary" then return d.group { fmt_tree_expr(e.lhs, f), " ", bin_kind_symbols[cls_kind(e.op)] or tostring(e.op), " ", fmt_tree_expr(e.rhs, f) } end
    if k == "ExprCompare" then
        return d.group { fmt_tree_expr(e.lhs, f), d.indent({ d.softline(), ":", cmp_kind_names[cls_kind(e.op)] or tostring(e.op), " (", fmt_tree_expr(e.rhs, f), ")" }, f.indent_width) }
    end
    if k == "ExprLogic" then return d.group { fmt_tree_expr(e.lhs, f), " :", cls_kind(e.op) == "LogicAnd" and "land" or "lor", " (", fmt_tree_expr(e.rhs, f), ")" } end
    if k == "ExprUnary" then return d.group { tostring(e.op), " (", fmt_tree_expr(e.value, f), ")" } end
    if k == "ExprCast" then
        local name = cls_kind(e.op) == "SurfaceBitcast" and "bitcast" or "as"
        return d.group { name, " [", fmt_type(e.ty, f), "] (", fmt_tree_expr(e.value, f), ")" }
    end
    if k == "ExprCall" then return d.group { fmt_tree_expr(e.callee, f), call_args(e.args or {}, f) } end
    if k == "ExprLen" then return d.group { "len (", fmt_tree_expr(e.value, f), ")" } end
    if k == "ExprDeref" then return d.group { "deref (", fmt_tree_expr(e.value, f), ")" } end
    if k == "ExprAddrOf" then return d.group { "addr (", fmt_place(e.place, f), ")" } end
    if k == "ExprIndex" then
        local base = e.base
        local bk = cls_kind(base)
        local base_doc = bk == "IndexBaseExpr" and fmt_tree_expr(base.base, f) or bk == "IndexBasePlace" and fmt_place(base.base, f) or d.text(tostring(base))
        return d.group { base_doc, "[", fmt_tree_expr(e.index, f), "]" }
    end
    if k == "ExprSelect" then return d.group { "select", curried_args({ e.cond, e.then_expr, e.else_expr }, f) } end
    if k == "ExprNull" then return d.group { "null [", fmt_type(e.elem, f), "]" } end
    if k == "ExprSizeOf" then return d.group { "sizeof [", fmt_type(e.ty, f), "]" } end
    if k == "ExprAlignOf" then return d.group { "alignof [", fmt_type(e.ty, f), "]" } end
    if k == "ExprIsNull" then return d.group { "is_null (", fmt_tree_expr(e.value, f), ")" } end
    return d.text("<" .. tostring(k or "expr") .. ">")
end

function Tr.SwitchKeyInt:format_tree_switch_key()
    return d.text(tostring(self.raw))
end

function Tr.SwitchKeyBool:format_tree_switch_key()
    return d.text(self.value and "true" or "false")
end

function Tr.SwitchKeyName:format_tree_switch_key()
    return d.text(tostring(self.name))
end

function Tr.SwitchKeyExpr:format_tree_switch_key(f)
    return fmt_tree_expr(self.expr, f)
end

fmt_expr = function(v, f)
    local lit = literal(v)
    if lit then return lit end

    local c = dsl_class(v)
    if c == "Name" then return d.text(v.name) end
    if c == "Expr" then
        local k = v.kind
        if k == "tree" then return d.text("<tree-expr>") end
        if k == "binary" then return d.group { fmt_expr(v.lhs, f), " ", bin_symbols[v.op] or v.op, " ", fmt_expr(v.rhs, f) } end
        if k == "cmp" then
            local lhs = fmt_expr(v.lhs, f)
            return d.group { lhs, d.indent({ d.softline(), ":", cmp_names[v.op] or v.op, " (", fmt_expr(v.rhs, f), ")" }, f.indent_width) }
        end
        if k == "logic" then return d.group { fmt_expr(v.lhs, f), " :", v.op == "and" and "land" or "lor", " (", fmt_expr(v.rhs, f), ")" } end
        if k == "not" then return d.group { "Not (", fmt_expr(v.value, f), ")" } end
        if k == "bitnot" then return d.group { "bit.bnot (", fmt_expr(v.value, f), ")" } end
        if k == "neg" then return d.group { "-", fmt_expr(v.value, f) } end
        if k == "dot" then return d.group { fmt_expr(v.base, f), ".", v.field } end
        if k == "index" then return d.group { fmt_expr(v.base, f), "[", fmt_expr(v.index, f), "]" } end
        if k == "call" then return d.group { fmt_expr(v.callee, f), call_args(v.args or {}, f) } end
        if k == "cast" then
            local name = cls_kind(v.cast) == "SurfaceBitcast" and "bitcast" or "as"
            return d.group { name, " [", fmt_type(v.ty, f), "] (", fmt_expr(v.value, f), ")" }
        end
        if k == "len" then return d.group { "len (", fmt_expr(v.value, f), ")" } end
        if k == "addr" then return d.group { "addr (", fmt_expr(v.value, f), ")" } end
        if k == "deref" or k == "load" then return d.group { k, " (", fmt_expr(v.value, f), ")" } end
        if k == "null" then return d.group { "null [", fmt_type(v.ty, f), "]" } end
        if k == "sizeof" then return d.group { "sizeof [", fmt_type(v.ty, f), "]" } end
        if k == "alignof" then return d.group { "alignof [", fmt_type(v.ty, f), "]" } end
        if k == "is_null" then return d.group { "is_null (", fmt_expr(v.value, f), ")" } end
        if k == "intrinsic" then return d.group { tostring(v.op), " ", call_args(v.args or {}, f) } end
        if k == "ctor" then return d.group { "ctor ", string.format("%q", tostring(v.type_name)), " ", string.format("%q", tostring(v.variant_name)), " ", call_args(v.args or {}, f) } end
        if k == "emit_expr" then return d.group { "emit_expr ", fmt_value(v.target, f), " ", call_args(v.args or {}, f) } end
        if k == "select" then return d.group { "select", curried_args({ v.cond, v.a, v.b }, f) } end
        if k == "atomic_load" then return d.group { "aload (", fmt_type(v.ty, f), ")(", fmt_expr(v.addr, f), ")" } end
        if k == "atomic_rmw" then return d.group { "armw (", string.format("%q", tostring(v.op)), ")(", fmt_type(v.ty, f), ")(", fmt_expr(v.addr, f), ")(", fmt_expr(v.value, f), ")" } end
        if k == "atomic_cas" then return d.group { "acas (", fmt_type(v.ty, f), ")(", fmt_expr(v.addr, f), ")(", fmt_expr(v.expected, f), ")(", fmt_expr(v.replacement, f), ")" } end
    end

    local tk = cls_kind(v)
    if tk and tk:match("^Expr") then return fmt_tree_expr(v, f) end

    if type(v) == "table" and is_array(v) then
        return braced_product(v, f, fmt_expr)
    end
    if type(v) == "table" then
        return braced_record(v, f)
    end
    return d.text(tostring(v))
end

fmt_value = function(v, f)
    local c = dsl_class(v)
    if c == "Decl" then return fmt_decl(v, f) end
    if c == "Stmt" then return fmt_stmt(v, f) end
    if c == "Expr" or c == "Name" then return fmt_expr(v, f) end
    if c == "TypedName" then return typed_name(v, f) end
    if c == "Payload" then return payload(v, f) end
    if c == "Fragment" or llbl.is(v, "Fragment") then return braced_product(v.items or {}, f, fmt_value) end
    if llbl.is(v, "Spread") then return d.group { "_(", fmt_value(v.value, f), ")" } end
    local k = cls_kind(v)
    if k and k:match("^Expr") then return fmt_tree_expr(v, f) end
    if k and k:match("^Stmt") then return fmt_tree_stmt(v, f) end
    if type(v) == "table" and is_array(v) then return braced_product(v, f, fmt_value) end
    if type(v) == "table" then return braced_record(v, f) end
    return fmt_expr(v, f)
end

local function result_suffix(result, f)
    if result == nil then return d.text("") end
    local k = cls_kind(result)
    if k == "TScalar" and cls_kind(result.scalar) == "ScalarVoid" then return d.text("") end
    return d.concat { " [", fmt_type(result, f), "]" }
end

local function jump_args_record(args, f)
    args = args or {}
    if #args == 0 then return d.text("{}") end
    local docs = {}
    for i = 1, #args do
        docs[i] = d.group { tostring(args[i].name), " = ", fmt_tree_expr(args[i].value, f) }
    end
    return d.group {
        "{",
        d.indent({ d.softline(), d.join(d.concat { ",", d.line() }, docs) }, f.indent_width),
        d.softline(),
        "}",
    }
end

fmt_tree_stmt = function(s, f)
    local k = cls_kind(s)
    if k == "StmtReturnVoid" then return d.text("ret ()") end
    if k == "StmtReturnValue" then return d.group { "ret (", fmt_tree_expr(s.value, f), ")" } end
    if k == "StmtYieldVoid" then return d.text("yield ()") end
    if k == "StmtYieldValue" then return d.group { "yield (", fmt_tree_expr(s.value, f), ")" } end
    if k == "StmtExpr" then return fmt_tree_expr(s.expr, f) end
    if k == "StmtTrap" then return d.text("trap ()") end
    if k == "StmtAssert" then return d.group { "assert_ (", fmt_tree_expr(s.cond, f), ")" } end
    if k == "StmtJump" then return d.group { "jump", dot_name(s.target.name), " ", jump_args_record(s.args, f) } end
    if k == "StmtJumpCont" then return d.group { "jump", dot_name(s.cont.name), " ", jump_args_record(s.args, f) } end
    if k == "StmtLet" then return d.group { "let", dot_name(s.binding.name), " [", fmt_type(s.binding.ty, f), "] (", fmt_tree_expr(s.init, f), ")" } end
    if k == "StmtVar" then return d.group { "var", dot_name(s.binding.name), " [", fmt_type(s.binding.ty, f), "] (", fmt_tree_expr(s.init, f), ")" } end
    if k == "StmtSet" then return d.group { "set (", fmt_place(s.place, f), ")(", fmt_tree_expr(s.value, f), ")" } end
    if k == "StmtIf" then return d.group { "If (", fmt_tree_expr(s.cond, f), ") ", block(s.then_body or {}, f, fmt_tree_stmt), " ", block(s.else_body or {}, f, fmt_tree_stmt) } end
    if k == "StmtAtomicStore" then return d.group { "astore (", fmt_type(s.ty, f), ")(", fmt_tree_expr(s.addr, f), ")(", fmt_tree_expr(s.value, f), ")" } end
    if k == "StmtAtomicFence" then return d.text("afence ()") end
    return d.text("<" .. tostring(k or "stmt") .. ">")
end

local function switch_arm_doc(arm, f)
    local k = cls_kind(arm)
    if k == "SwitchStmtArm" then return d.group { "case (", arm.key:format_tree_switch_key(f), ") ", block(arm.body or {}, f, fmt_tree_stmt) } end
    if k == "SwitchVariantStmtArm" then return d.group { "case", dot_name(arm.variant_name), " ", block(arm.body or {}, f, fmt_tree_stmt) } end
    return d.text("<switch-arm>")
end

local function switch_block(s, f)
    local docs = {}
    for i = 1, #(s.arms or {}) do docs[#docs + 1] = switch_arm_doc(s.arms[i], f); docs[#docs + 1] = ","; docs[#docs + 1] = d.line() end
    for i = 1, #(s.variant_arms or {}) do docs[#docs + 1] = switch_arm_doc(s.variant_arms[i], f); docs[#docs + 1] = ","; docs[#docs + 1] = d.line() end
    docs[#docs + 1] = d.group { "default ", block(s.default_body or {}, f, fmt_stmt) }
    return d.concat { "{", d.indent({ d.line(), docs }, f.indent_width), d.line(), "}" }
end

fmt_stmt = function(s, f)
    local sk = cls_kind(s)
    if sk and sk:match("^Stmt") then return fmt_tree_stmt(s, f) end

    if type(s) == "table" and s.kind == "entry_decl" then
        return d.group { "entry", dot_name(s.name), " ", braced_product(s.params or {}, f, typed_name), " ", block(s.body or {}, f, fmt_stmt) }
    end
    if type(s) == "table" and s.kind == "block_decl" then
        return d.group { "block", dot_name(s.name), " ", braced_product(s.params or {}, f, typed_name), " ", block(s.body or {}, f, fmt_stmt) }
    end

    local k = s.kind
    if k == "ret" then
        if s.value == nil then return d.text("ret ()") end
        return d.group { "ret ", paren_expr(s.value, f) }
    end
    if k == "yield" then
        if s.value == nil then return d.text("yield ()") end
        return d.group { "yield ", paren_expr(s.value, f) }
    end
    if k == "let" or k == "var" then return d.group { k, dot_name(s.name), " [", fmt_type(s.ty, f), "] (", fmt_expr(s.init, f), ")" } end
    if k == "when" then return d.group { "when ", paren_expr(s.cond, f), " ", block(s.body or {}, f, fmt_stmt) } end
    if k == "if" then return d.group { "If ", paren_expr(s.cond, f), " ", block(s.then_body or {}, f, fmt_stmt), " ", block(s.else_body or {}, f, fmt_stmt) } end
    if k == "set" then return d.group { "set (", fmt_expr(s.place, f), ")(", fmt_expr(s.value, f), ")" } end
    if k == "assert" then return d.group { "assert_ ", paren_expr(s.cond, f) } end
    if k == "trap" then return d.text("trap ()") end
    if k == "assume" then return d.group { "assume ", paren_expr(s.cond, f) } end
    if k == "jump" then return d.group { "jump", dot_name(s.target), " ", braced_record(s.args or {}, f) } end
    if k == "emit" then return d.group { "emit", dot_name(s.target), " ", braced_product(s.args or {}, f, fmt_expr), " ", cont_bindings_record(s.conts or {}, f) } end
    if k == "switch" then return d.group { "switch ", paren_expr(s.value, f), " ", switch_block(s, f) } end
    if k == "atomic_store" then return d.group { "astore (", fmt_type(s.ty, f), ")(", fmt_expr(s.addr, f), ")(", fmt_expr(s.value, f), ")" } end
    if k == "atomic_fence" then return d.text("afence ()") end
    if k == "expr" then return fmt_expr(s.expr, f) end
    return d.text("<stmt:" .. tostring(k) .. ">")
end

fmt_decl = function(x, f)
    local k = x.kind
    if k == "unit" then
        return d.concat { "unit", dot_name(x.name), " ", block(x.body or {}, f, fmt_decl) }
    end
    if k == "struct" then return d.group { "struct", dot_name(x.name), " ", braced_product(x.body or {}, f, typed_name) } end
    if k == "union" then return d.group { "union", dot_name(x.name), " ", braced_product(x.body or {}, f, fmt_value) } end
    if k == "fn" or k == "export_fn" then
        return d.group {
            k, dot_name(x.name), " ",
            braced_product(x.params or {}, f, typed_name),
            result_suffix(x.result, f),
            " ",
            block(x.body or {}, f, fmt_stmt),
        }
    end
    if k == "extern" then
        return d.group {
            "extern", dot_name(x.name), " ",
            braced_product(x.params or {}, f, typed_name),
            result_suffix(x.result, f),
            " ",
            braced_record(x.opts or {}, f),
        }
    end
    if k == "handle" then return d.group { "handle", dot_name(x.name), " ", braced_record(x.opts or {}, f) } end
    if k == "const" then return d.group { "const", dot_name(x.name), " [", fmt_type(x.ty, f), "] (", fmt_expr(x.value, f), ")" } end
    if k == "static" then return d.group { "static", dot_name(x.name), " [", fmt_type(x.ty, f), "] (", fmt_expr(x.value, f), ")" } end
    if k == "import" then return d.group { "import (", fmt_value(x.name, f), ")" } end
    if k == "region" then
        local body = {}
        if x.entry then body[#body + 1] = x.entry end
        for i = 1, #(x.blocks or {}) do body[#body + 1] = x.blocks[i] end
        return d.group {
            "region", dot_name(x.name), " ",
            braced_product(x.params or {}, f, typed_name),
            " ",
            braced_product(x.conts or {}, f, fmt_value),
            " ",
            block(body, f, fmt_stmt),
        }
    end
    return d.text("<decl:" .. tostring(k) .. ">")
end

function M.doc(value, opts)
    local f = make_context(opts)
    return fmt_value(value, f)
end

function M.format(value, opts)
    opts = opts or {}
    return llbl.render(M.doc(value, opts), opts)
end

function M.file_text(value, opts)
    opts = opts or {}
    local text = M.format(value, opts)
    return table.concat({
        "local lalin = require(\"lalin\")",
        "lalin.language.use()",
        "",
        "return " .. text,
        "",
    }, "\n")
end

function M.format_file(path, opts)
    local dsl = require("lalin.dsl")
    local chunk = dsl.loadfile(path, opts)
    local value = chunk()
    return M.file_text(value, opts)
end

function M.write_format_file(path, opts)
    local text = M.format_file(path, opts)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
    return text
end

return M
