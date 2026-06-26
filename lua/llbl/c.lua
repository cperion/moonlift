local llbl = require("llbl")
local g, ch = llbl.grammar, llbl.channel
local lua_type = type

local M = {}

local function cnode(role, kind, fields)
    fields = fields or {}
    fields.__llbl_c = role
    fields.kind = kind
    fields.origin = fields.origin or llbl.here("llbl.c." .. tostring(kind), { skip = 3 })
    return fields
end

local function role(v) return lua_type(v) == "table" and rawget(v, "__llbl_c") or nil end
local function is_type(v) return role(v) == "type" end
llbl.register_type_like(is_type)

local function fail(msg, origin, level)
    error("llbl.c: " .. msg, (level or 1) + 1)
end

local function is_unit(v)
    if v == nil or v == llbl.UNIT then return true end
    if lua_type(v) ~= "table" then return false end
    return rawget(v, "__llbl_tag") == "Sentinel"
end

local function cname(v, site)
    if lua_type(v) == "table" then
        if llbl.is(v, "Name") or llbl.is(v, "Symbol") then v = v.text end
        if role(v) == "expr" and v.kind == "name" then v = v.name end
    end
    local s = tostring(v or "")
    if not s:match("^[_%a][_%w]*$") then fail((site or "name") .. " expected C identifier, got " .. s, nil, 2) end
    return s
end

local function private_name(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function ctype(kind, fields) return cnode("type", kind, fields) end
local function named_type(name) return ctype("name", { name = tostring(name) }) end

local function type_any(v)
    if role(v) == "type" then return v end
    if lua_type(v) == "table" and (llbl.is(v, "Name") or llbl.is(v, "Symbol")) then return named_type(v.text) end
    return named_type(v)
end

local Expr = {}
local function expr(kind, fields) return setmetatable(cnode("expr", kind, fields), Expr) end

local to_expr
local function bin(op, a, b) return expr("bin", { op = op, lhs = to_expr(a), rhs = to_expr(b) }) end
local function plain_list(v)
    return lua_type(v) == "table" and role(v) == nil and not llbl.is(v, "Expr") and not llbl.is(v, "Symbol") and not llbl.is(v, "Name")
end

Expr.__add = function(a, b) return bin("+", a, b) end
Expr.__sub = function(a, b) return bin("-", a, b) end
Expr.__mul = function(a, b) return bin("*", a, b) end
Expr.__div = function(a, b) return bin("/", a, b) end
Expr.__mod = function(a, b) return bin("%", a, b) end
Expr.__unm = function(a) return expr("un", { op = "-", value = to_expr(a) }) end
Expr.__call = function(self, args)
    local out = {}
    for i = 1, #(args or {}) do out[i] = to_expr(args[i]) end
    return expr("call", { callee = self, args = out })
end
Expr.__index = function(self, key)
    if Expr[key] then return Expr[key] end
    if lua_type(key) == "number" or role(key) == "expr" or (lua_type(key) == "table" and llbl.is(key, "Symbol")) then
        return expr("index", { base = self, index = to_expr(key) })
    end
    return expr("field", { base = self, field = cname(key, "field") })
end

local function llbl_expr(v)
    local k = v.kind
    if k == "binop" then return bin(v.op, v.a, v.b) end
    if k == "unop" then return expr("un", { op = v.op, value = to_expr(v.a) }) end
    if k == "field" then return expr("field", { base = to_expr(v.base), field = cname(v.field, "field") }) end
    if k == "index" then return expr("index", { base = to_expr(v.base), index = to_expr(v.index) }) end
    if k == "call" then
        local args, raw = {}, v.args or {}
        if (raw.n or #raw) == 1 and plain_list(raw[1]) then raw = raw[1] end
        local n = raw.n or #raw
        for i = 1, n do args[i] = to_expr(raw[i]) end
        return expr("call", { callee = to_expr(v.callee), args = args })
    end
    fail("unsupported LLBL expression kind " .. tostring(k), v.origin, 2)
end

to_expr = function(v)
    if v == nil or v == llbl.NIL then return expr("null", {}) end
    if lua_type(v) == "table" and rawget(v, "__llbl_tag") == "Sentinel" then return expr("unit", {}) end
    if role(v) == "expr" then return v end
    if lua_type(v) == "table" then
        if llbl.is(v, "Symbol") or llbl.is(v, "Name") then return expr("name", { name = cname(v, "symbol") }) end
        if llbl.is(v, "Expr") then return llbl_expr(v) end
    end
    if lua_type(v) == "number" then return expr("number", { value = v }) end
    if lua_type(v) == "string" then return expr("string", { value = v }) end
    if lua_type(v) == "boolean" then return expr("number", { value = v and 1 or 0 }) end
    local detail = role(v) or lua_type(v)
    if lua_type(v) == "table" then
        detail = tostring(detail) .. " tag=" .. tostring(rawget(v, "__llbl_tag")) .. " kind=" .. tostring(rawget(v, "kind")) .. " name=" .. tostring(rawget(v, "name"))
    end
    fail("expected C expression, got " .. detail, lua_type(v) == "table" and v.origin or nil, 2)
end

local function stmt(kind, fields) return cnode("stmt", kind, fields) end
local function decl(kind, fields) return cnode("decl", kind, fields) end

local function product_items(value)
    local out = {}
    for i = 1, #(value or {}) do
        local f = value[i]
        if f.raw then
            out[i] = { raw = f.raw, origin = f.origin }
        else
            out[i] = { name = cname(f.name, "field"), ty = type_any(f.type), init = f.init and to_expr(f.init) or nil, origin = f.origin }
        end
    end
    return out
end

local function c_name_slot(v) return cname(v, "name") end

local C = llbl.dialect "llbl.c" {
    g.role. decl  { kind = "identity" },
    g.role. stmt  { kind = "identity" },
    g.role. decls { kind = "array", item = "decl" },
    g.role. stmts { kind = "array", item = "stmt" },
    g.role. fields { kind = "product", type_role = "type", unique_names = true },
    g.role. params { kind = "product", type_role = "type", unique_names = true },

    g.head. unit {
        g.slot. name  [g.identity] { channels = { ch.index_name, ch.index_value } },
        g.slot. decls [g.decls],
        emit = function(n, _, meta) return cnode("unit", "unit", { name = c_name_slot(meta.raw.name), decls = n.decls }) end,
    },

    g.head. typedef_struct {
        g.slot. name [g.identity] { channels = { ch.index_name, ch.index_value } },
        g.slot. fields [g.fields],
        emit = function(n, _, meta) return decl("typedef_struct", { name = c_name_slot(meta.raw.name), fields = product_items(n.fields) }) end,
    },

    g.head. typedef {
        g.slot. name [g.identity] { channels = { ch.index_name, ch.index_value } },
        g.slot. type [g.type],
        emit = function(n, _, meta) return decl("typedef", { name = c_name_slot(meta.raw.name), ty = type_any(n.type) }) end,
    },

    g.head. fn {
        g.slot. name [g.identity] { channels = { ch.index_name, ch.index_value } },
        g.slot. params [g.params],
        g.slot. result [g.type],
        g.slot. body [g.stmts],
        emit = function(n, _, meta) return decl("fn", { name = c_name_slot(meta.raw.name), params = product_items(n.params), result = type_any(n.result), body = n.body }) end,
    },

    g.head. static_fn {
        g.slot. name [g.identity] { channels = { ch.index_name, ch.index_value } },
        g.slot. params [g.params],
        g.slot. result [g.type],
        g.slot. body [g.stmts],
        emit = function(n, _, meta) return decl("fn", { storage = "static", name = c_name_slot(meta.raw.name), params = product_items(n.params), result = type_any(n.result), body = n.body }) end,
    },

    g.head. static_inline_fn {
        g.slot. name [g.identity] { channels = { ch.index_name, ch.index_value } },
        g.slot. params [g.params],
        g.slot. result [g.type],
        g.slot. body [g.stmts],
        emit = function(n, _, meta) return decl("fn", { storage = "static inline", name = c_name_slot(meta.raw.name), params = product_items(n.params), result = type_any(n.result), body = n.body }) end,
    },

    g.head. include {
        g.slot. header [g.string],
        emit = function(n) return decl("include", { header = n.header }) end,
    },

    g.head. define {
        g.slot. name [g.identity] { channels = { ch.index_name, ch.index_value } },
        g.slot. value [g.identity] { channels = { ch.call_value, ch.call_table } },
        emit = function(n, _, meta) return decl("define", { name = c_name_slot(meta.raw.name), value = meta.raw.value }) end,
    },

    g.head. return_ {
        g.slot. value [g.identity] { channels = { ch.call_none, ch.call_value, ch.call_table } },
        emit = function(_, _, meta)
            local v = meta.raw.value
            return stmt("return", { value = is_unit(v) and nil or to_expr(v) })
        end,
    },

    g.head. decl {
        g.slot. name [g.identity] { channels = { ch.index_name, ch.index_value } },
        g.slot. type [g.type],
        g.slot. init [g.identity] { channels = { ch.call_none, ch.call_value, ch.call_table } },
        emit = function(n, _, meta)
            local init = meta.raw.init
            return stmt("decl", { name = c_name_slot(meta.raw.name), ty = type_any(n.type), init = is_unit(init) and nil or to_expr(init) })
        end,
    },

    g.head. auto {
        g.slot. name [g.identity] { channels = { ch.index_name, ch.index_value } },
        g.slot. init [g.identity] { channels = { ch.call_value, ch.call_table } },
        emit = function(_, _, meta) return stmt("auto", { name = c_name_slot(meta.raw.name), init = to_expr(meta.raw.init) }) end,
    },

    g.head. for_ {
        g.slot. spec [g.identity] { channel = ch.call_table },
        g.slot. body [g.stmts],
        emit = function(n, _, meta)
            local s = meta.raw.spec or {}
            return stmt("for", { init = s[1], cond = to_expr(s[2]), step = s[3], body = n.body })
        end,
    },
}

local E = C.exports

local function ptr_type(kind)
    return setmetatable({}, {
        __index = function(_, t) return ctype(kind, { base = type_any(t) }) end,
    })
end

E.ptr = ptr_type("ptr")
E.const = ptr_type("const")
E.restrict = ptr_type("restrict")
E.array = setmetatable({}, {
    __index = function(_, t)
        local elem = type_any(t)
        return setmetatable({}, { __index = function(_, n) return ctype("array", { elem = elem, count = n }) end })
    end,
})
E.fnptr = setmetatable({}, {
    __index = function(_, params)
        local ps = {}
        for i = 1, #(params or {}) do ps[i] = type_any(params[i]) end
        return setmetatable({}, { __index = function(_, result) return ctype("fnptr", { params = ps, result = type_any(result) }) end })
    end,
})
E.vector = setmetatable({}, {
    __index = function(_, t)
        local elem = type_any(t)
        return function(bytes) return ctype("attribute", { base = elem, attrs = { "vector_size(" .. tostring(bytes) .. ")" } }) end
    end,
})
E.typeof = setmetatable({}, {
    __index = function(_, v)
        if role(v) == "type" then return ctype("typeof_type", { ty = v }) end
        return ctype("typeof_expr", { value = to_expr(v) })
    end,
})
E.type = setmetatable({}, {
    __index = function(_, name) return named_type(cname(name, "type")) end,
    __call = function(_, name) return named_type(cname(name, "type")) end,
})

E.void, E.bool, E.char = named_type("void"), named_type("_Bool"), named_type("char")
E.int, E.uint, E.i32, E.u32 = named_type("int"), named_type("unsigned int"), named_type("int32_t"), named_type("uint32_t")
E.i8, E.u8, E.i16, E.u16 = named_type("int8_t"), named_type("uint8_t"), named_type("int16_t"), named_type("uint16_t")
E.i64, E.u64, E.f32, E.f64 = named_type("int64_t"), named_type("uint64_t"), named_type("float"), named_type("double")
E.size_t, E.uintptr_t, E.intptr_t = named_type("size_t"), named_type("uintptr_t"), named_type("intptr_t")
E.void_ptr = E.ptr[E.void]

E.assign = function(place, value) return stmt("assign", { lhs = to_expr(place), rhs = to_expr(value) }) end
E.expr = function(value) return stmt("expr", { value = to_expr(value) }) end
E.if_ = function(cond)
    return function(then_body)
        local out = stmt("if", { cond = to_expr(cond), then_body = C:fragment("stmts", then_body or {}).items, else_body = {} })
        return setmetatable(out, {
            __call = function(self, else_body)
                self.else_body = C:fragment("stmts", else_body or {}).items
                return self
            end,
        })
    end
end
E.while_ = function(cond) return function(body) return stmt("while", { cond = to_expr(cond), body = C:fragment("stmts", body or {}).items }) end end
E.stmt_expr = function(body) return expr("stmt_expr", { body = C:fragment("stmts", body or {}).items }) end
E.compound = setmetatable({}, {
    __index = function(_, ty) return function(items) return expr("compound", { ty = type_any(ty), items = items or {} }) end end,
})
E.init = setmetatable({}, {
    __index = function(_, name) return function(value) return { name = cname(name, "initializer"), value = to_expr(value) } end end,
})
E.list = function(items)
    local out = {}
    for i = 1, #(items or {}) do out[i] = to_expr(items[i]) end
    return expr("init_list", { items = out })
end
E.cast = setmetatable({}, { __index = function(_, ty) return function(value) return expr("cast", { ty = type_any(ty), value = to_expr(value) }) end end })
E.null = setmetatable({}, { __index = function(_, ty) return expr("null", { ty = type_any(ty) }) end })
E.builtin = setmetatable({}, {
    __index = function(_, name)
        return function(args)
            local out = {}
            for i = 1, #(args or {}) do out[i] = to_expr(args[i]) end
            return expr("builtin", { name = cname(name, "builtin"), args = out })
        end
    end,
})
E.lt, E.le, E.gt, E.ge = function(a, b) return bin("<", a, b) end, function(a, b) return bin("<=", a, b) end, function(a, b) return bin(">", a, b) end, function(a, b) return bin(">=", a, b) end
E.eq, E.ne = function(a, b) return bin("==", a, b) end, function(a, b) return bin("!=", a, b) end
E.land, E.lor = function(a, b) return bin("&&", a, b) end, function(a, b) return bin("||", a, b) end
E.band, E.bor, E.bxor = function(a, b) return bin("&", a, b) end, function(a, b) return bin("|", a, b) end, function(a, b) return bin("^", a, b) end
E.shl, E.shr = function(a, b) return bin("<<", a, b) end, function(a, b) return bin(">>", a, b) end
E.select = function(cond, then_value, else_value) return expr("select", { cond = to_expr(cond), then_value = to_expr(then_value), else_value = to_expr(else_value) }) end
E.addr = function(v) return expr("un", { op = "&", value = to_expr(v) }) end
E.deref = function(v) return expr("un", { op = "*", value = to_expr(v) }) end
E.not_ = function(v) return expr("un", { op = "!", value = to_expr(v) }) end
E.bnot = function(v) return expr("un", { op = "~", value = to_expr(v) }) end
E.raw_expr = function(text) return expr("raw", { text = tostring(text) }) end
E.raw_stmt = function(text) return stmt("raw", { text = tostring(text) }) end
E.raw_decl = function(text) return decl("raw", { text = tostring(text) }) end
E.raw_param = function(text)
    text = tostring(text)
    return llbl.spread(llbl.fragment("params", { { name = "__raw_param_" .. private_name(text), raw = text } }))
end

local function emit_context(opts)
    opts = opts or {}
    local d = tostring(opts.dialect or "gnu99"):lower()
    if d == "gnu" or d == "gnu99" or d == "gcc" then return { gnu = true } end
    if d == "c11" or d == "pure_c11" then return { gnu = false } end
    fail("unsupported C dialect " .. tostring(opts.dialect), nil, 2)
end

local function need_gnu(ctx, feature) if not ctx.gnu then fail(feature .. " requires GNU C dialect", nil, 2) end end

local expr_s
local function type_s(t, ctx)
    t = type_any(t)
    if t.kind == "name" then return t.name end
    if t.kind == "ptr" then return type_s(t.base, ctx) .. " *" end
    if t.kind == "const" then return type_s(t.base, ctx) .. " const" end
    if t.kind == "restrict" then return type_s(t.base, ctx) .. (ctx.gnu and " __restrict" or " restrict") end
    if t.kind == "array" then return type_s(t.elem, ctx) .. "[" .. tostring(t.count) .. "]" end
    if t.kind == "attribute" then need_gnu(ctx, "__attribute__"); return type_s(t.base, ctx) .. " __attribute__((" .. table.concat(t.attrs, ", ") .. "))" end
    if t.kind == "typeof_type" then need_gnu(ctx, "__typeof__"); return "__typeof__(" .. type_s(t.ty, ctx) .. ")" end
    if t.kind == "typeof_expr" then need_gnu(ctx, "__typeof__"); return "__typeof__(" .. expr_s(t.value, ctx) .. ")" end
    if t.kind == "fnptr" then fail("function pointer type requires a declarator name", t.origin, 2) end
    fail("unsupported C type kind " .. tostring(t.kind), t.origin, 2)
end

local function declarator(t, name, ctx)
    if lua_type(t) == "table" and t.raw then return t.raw end
    t = type_any(t)
    if t.kind == "fnptr" then
        local ps = {}
        for i = 1, #(t.params or {}) do ps[i] = type_s(t.params[i], ctx) end
        if #ps == 0 then ps[1] = "void" end
        return type_s(t.result, ctx) .. " (*" .. cname(name, "declarator") .. ")(" .. table.concat(ps, ", ") .. ")"
    end
    if t.kind == "array" then return type_s(t.elem, ctx) .. " " .. cname(name, "declarator") .. "[" .. tostring(t.count) .. "]" end
    local s = type_s(t, ctx)
    return s .. (s:match("[%*%s]$") and "" or " ") .. cname(name, "declarator")
end

local prec = { raw = 100, name = 100, number = 100, string = 100, null = 100, call = 90, index = 90, field = 90, un = 80, ["*"] = 70, ["/"] = 70, ["%"] = 70, ["+"] = 60, ["-"] = 60, ["<<"] = 55, [">>"] = 55, ["<"] = 50, ["<="] = 50, [">"] = 50, [">="] = 50, ["=="] = 45, ["!="] = 45, ["&"] = 42, ["^"] = 41, ["|"] = 40, ["&&"] = 30, ["||"] = 20, select = 15 }
local function par(e, parent, ctx)
    local s = expr_s(e, ctx)
    return (prec[e.kind == "bin" and e.op or e.kind] or 0) < (prec[parent] or 0) and ("(" .. s .. ")") or s
end
expr_s = function(e, ctx)
    e = to_expr(e)
    if e.kind == "raw" then return e.text end
    if e.kind == "name" then return e.name end
    if e.kind == "number" then return tostring(e.value) end
    if e.kind == "string" then return string.format("%q", e.value) end
    if e.kind == "null" then return "NULL" end
    if e.kind == "bin" then return par(e.lhs, e.op, ctx) .. " " .. e.op .. " " .. par(e.rhs, e.op, ctx) end
    if e.kind == "un" then return e.op .. par(e.value, "un", ctx) end
    if e.kind == "select" then return par(e.cond, "select", ctx) .. " ? " .. par(e.then_value, "select", ctx) .. " : " .. par(e.else_value, "select", ctx) end
    if e.kind == "index" then return par(e.base, "index", ctx) .. "[" .. expr_s(e.index, ctx) .. "]" end
    if e.kind == "field" then return par(e.base, "field", ctx) .. "." .. e.field end
    if e.kind == "cast" then return "(" .. type_s(e.ty, ctx) .. ")(" .. expr_s(e.value, ctx) .. ")" end
    if e.kind == "call" then
        local args = {}; for i = 1, #e.args do args[i] = expr_s(e.args[i], ctx) end
        return expr_s(e.callee, ctx) .. "(" .. table.concat(args, ", ") .. ")"
    end
    if e.kind == "builtin" then
        need_gnu(ctx, "__builtin_" .. e.name)
        local args = {}; for i = 1, #e.args do args[i] = expr_s(e.args[i], ctx) end
        return "__builtin_" .. e.name .. "(" .. table.concat(args, ", ") .. ")"
    end
    if e.kind == "compound" then
        local xs = {}
        for i = 1, #e.items do local item = e.items[i]; xs[i] = item.name and ("." .. item.name .. " = " .. expr_s(item.value, ctx)) or expr_s(item, ctx) end
        return "(" .. type_s(e.ty, ctx) .. "){" .. table.concat(xs, ", ") .. "}"
    end
    if e.kind == "init_list" then
        local xs = {}; for i = 1, #e.items do xs[i] = expr_s(e.items[i], ctx) end
        return "{ " .. table.concat(xs, ", ") .. " }"
    end
    if e.kind == "stmt_expr" then
        need_gnu(ctx, "statement expression")
        local out = { "({" }; M.emit_block(e.body, out, 1, ctx); out[#out + 1] = "})"; return table.concat(out, "\n")
    end
    fail("unsupported C expression kind " .. tostring(e.kind), e.origin, 2)
end

local function indent(n) return string.rep("    ", n) end
local function header_component(x, ctx)
    if x == nil or x == "" then return "" end
    if lua_type(x) == "string" then return x end
    if role(x) == "expr" then return expr_s(x, ctx) end
    if role(x) ~= "stmt" then return expr_s(x, ctx) end
    if x.kind == "decl" then return declarator(x.ty, x.name, ctx) .. (x.init and (" = " .. expr_s(x.init, ctx)) or "") end
    if x.kind == "assign" then return expr_s(x.lhs, ctx) .. " = " .. expr_s(x.rhs, ctx) end
    if x.kind == "expr" then return expr_s(x.value, ctx) end
    fail("unsupported for-header statement " .. tostring(x.kind), x.origin, 2)
end

function M.emit_block(stmts, out, level, ctx)
    for i = 1, #(stmts or {}) do
        local s, p = stmts[i], indent(level)
        if role(s) ~= "stmt" then fail("function body expected stmt", s and s.origin, 2) end
        if s.kind == "raw" then out[#out + 1] = p .. s.text
        elseif s.kind == "return" then out[#out + 1] = p .. "return" .. (s.value and s.value.kind ~= "unit" and (" " .. expr_s(s.value, ctx)) or "") .. ";"
        elseif s.kind == "expr" then out[#out + 1] = p .. expr_s(s.value, ctx) .. ";"
        elseif s.kind == "assign" then out[#out + 1] = p .. expr_s(s.lhs, ctx) .. " = " .. expr_s(s.rhs, ctx) .. ";"
        elseif s.kind == "decl" then out[#out + 1] = p .. declarator(s.ty, s.name, ctx) .. (s.init and s.init.kind ~= "unit" and (" = " .. expr_s(s.init, ctx)) or "") .. ";"
        elseif s.kind == "auto" then need_gnu(ctx, "__auto_type"); out[#out + 1] = p .. "__auto_type " .. s.name .. " = " .. expr_s(s.init, ctx) .. ";"
        elseif s.kind == "if" then
            out[#out + 1] = p .. "if (" .. expr_s(s.cond, ctx) .. ") {"
            M.emit_block(s.then_body, out, level + 1, ctx)
            if #(s.else_body or {}) > 0 then out[#out + 1] = p .. "} else {"; M.emit_block(s.else_body, out, level + 1, ctx) end
            out[#out + 1] = p .. "}"
        elseif s.kind == "for" then
            out[#out + 1] = p .. "for (" .. header_component(s.init, ctx) .. "; " .. expr_s(s.cond, ctx) .. "; " .. header_component(s.step, ctx) .. ") {"
            M.emit_block(s.body, out, level + 1, ctx); out[#out + 1] = p .. "}"
        elseif s.kind == "while" then
            out[#out + 1] = p .. "while (" .. expr_s(s.cond, ctx) .. ") {"
            M.emit_block(s.body, out, level + 1, ctx); out[#out + 1] = p .. "}"
        else fail("unsupported C statement kind " .. tostring(s.kind), s.origin, 2) end
    end
end

local function emit_decl(d, out, ctx)
    if role(d) ~= "decl" then fail("unit expected decl", d and d.origin, 2) end
    if d.kind == "include" then out[#out + 1] = "#include <" .. d.header .. ">"
    elseif d.kind == "define" then out[#out + 1] = "#define " .. d.name .. " " .. tostring(d.value)
    elseif d.kind == "raw" then out[#out + 1] = d.text
    elseif d.kind == "typedef" then
        out[#out + 1] = "typedef " .. declarator(d.ty, d.name, ctx) .. ";"
    elseif d.kind == "typedef_struct" then
        out[#out + 1] = "typedef struct " .. d.name .. " {"
        for i = 1, #d.fields do local f = d.fields[i]; out[#out + 1] = "    " .. declarator(f.ty, f.name, ctx) .. ";" end
        out[#out + 1] = "} " .. d.name .. ";"
    elseif d.kind == "fn" then
        local ps = {}; for i = 1, #d.params do local p = d.params[i]; ps[i] = p.raw or declarator(p.ty, p.name, ctx) end
        if #ps == 0 then ps[1] = "void" end
        out[#out + 1] = (d.storage and (d.storage .. " ") or "") .. type_s(d.result, ctx) .. " " .. d.name .. "(" .. table.concat(ps, ", ") .. ") {"
        M.emit_block(d.body, out, 1, ctx); out[#out + 1] = "}"
    else fail("unsupported C declaration kind " .. tostring(d.kind), d.origin, 2) end
end

function M.emit_unit(unit, opts)
    if role(unit) ~= "unit" then fail("emit_unit expected C unit", unit and unit.origin, 2) end
    local ctx, out = emit_context(opts), {}
    for i = 1, #unit.decls do emit_decl(unit.decls[i], out, ctx); if i < #unit.decls then out[#out + 1] = "" end end
    return table.concat(out, "\n")
end

function M.emit_decl(decl0, opts) local out = {}; emit_decl(decl0, out, emit_context(opts)); return table.concat(out, "\n") end
function M.type_spelling(t, opts) return type_s(t, emit_context(opts)) end
function M.expr_spelling(e, opts) return expr_s(e, emit_context(opts)) end
function M.role(v) return role(v) end

local d = llbl.doc

local function quote(v) return string.format("%q", tostring(v)) end
local function head_name(head, name) return d.concat { "c.", head, ". ", tostring(name) } end

local format_type_doc, format_expr_doc, format_stmt_doc, format_decl_doc

local function list_doc(items, f)
    local docs = {}
    for i = 1, #(items or {}) do docs[i] = format_expr_doc(items[i], f) end
    return d.braces(d.concat { " ", d.join(d.concat { ",", d.line() }, docs), " " })
end

local function block_doc(items, f, item_fmt)
    item_fmt = item_fmt or function(x, f0) return f0:format(x) end
    if #(items or {}) == 0 then return d.text("{}") end
    local docs = {}
    for i = 1, #items do
        docs[#docs + 1] = item_fmt(items[i], f)
        docs[#docs + 1] = ","
        if i < #items then docs[#docs + 1] = d.line() end
    end
    return d.concat {
        "{",
        d.indent({ d.line(), docs }, f.indent_width),
        d.line(),
        "}",
    }
end

local primitive_type_names = {
    void = "void", ["_Bool"] = "bool", char = "char", int = "int", ["unsigned int"] = "uint",
    int8_t = "i8", uint8_t = "u8", int16_t = "i16", uint16_t = "u16",
    int32_t = "i32", uint32_t = "u32", int64_t = "i64", uint64_t = "u64",
    float = "f32", double = "f64", size_t = "size_t", uintptr_t = "uintptr_t", intptr_t = "intptr_t",
}

format_type_doc = function(t, f)
    t = type_any(t)
    if t.kind == "name" then
        local prim = primitive_type_names[t.name]
        if prim then return d.text("c." .. prim) end
        return head_name("type", t.name)
    end
    if t.kind == "ptr" then return d.group { "c.ptr [", format_type_doc(t.base, f), "]" } end
    if t.kind == "const" then return d.group { "c.const [", format_type_doc(t.base, f), "]" } end
    if t.kind == "restrict" then return d.group { "c.restrict [", format_type_doc(t.base, f), "]" } end
    if t.kind == "array" then return d.group { "c.array [", format_type_doc(t.elem, f), "] [", tostring(t.count), "]" } end
    if t.kind == "fnptr" then
        local params = {}
        for i = 1, #(t.params or {}) do params[i] = format_type_doc(t.params[i], f) end
        return d.group { "c.fnptr [{ ", d.join(d.concat { ",", d.line() }, params), " }] [", format_type_doc(t.result, f), "]" }
    end
    if t.kind == "attribute" then
        local vec = t.attrs and t.attrs[1] and tostring(t.attrs[1]):match("^vector_size%((.+)%)$")
        if vec then return d.group { "c.vector [", format_type_doc(t.base, f), "] (", vec, ")" } end
        return d.text("c.raw_type " .. quote(type_s(t, emit_context({ dialect = "gnu99" }))))
    end
    if t.kind == "typeof_type" then return d.group { "c.typeof [", format_type_doc(t.ty, f), "]" } end
    if t.kind == "typeof_expr" then return d.group { "c.typeof [", format_expr_doc(t.value, f), "]" } end
    return d.text("c.raw_type " .. quote(type_s(t, emit_context({ dialect = "gnu99" }))))
end

local function arg_list_doc(args, f)
    if #(args or {}) == 0 then return d.text("{}") end
    local docs = {}
    for i = 1, #args do docs[i] = format_expr_doc(args[i], f) end
    return d.group { "{ ", d.join(d.concat { ",", d.line() }, docs), " }" }
end

format_expr_doc = function(e, f)
    e = to_expr(e)
    if e.kind == "unit" then return d.text("()") end
    if e.kind == "raw" then return d.text("c.raw_expr(" .. quote(e.text) .. ")") end
    if e.kind == "name" then return d.text(e.name) end
    if e.kind == "number" then return d.text(tostring(e.value)) end
    if e.kind == "string" then return d.text(quote(e.value)) end
    if e.kind == "null" then return d.text(e.ty and ("c.null [" .. llbl.render(format_type_doc(e.ty, f)) .. "]") or "nil") end
    if e.kind == "bin" then return d.group { format_expr_doc(e.lhs, f), " ", e.op, " ", format_expr_doc(e.rhs, f) } end
    if e.kind == "un" then return d.group { e.op, format_expr_doc(e.value, f) } end
    if e.kind == "select" then return d.group { "c.select(", format_expr_doc(e.cond, f), ", ", format_expr_doc(e.then_value, f), ", ", format_expr_doc(e.else_value, f), ")" } end
    if e.kind == "index" then return d.group { format_expr_doc(e.base, f), "[", format_expr_doc(e.index, f), "]" } end
    if e.kind == "field" then return d.group { format_expr_doc(e.base, f), ".", e.field } end
    if e.kind == "cast" then return d.group { "c.cast [", format_type_doc(e.ty, f), "] (", format_expr_doc(e.value, f), ")" } end
    if e.kind == "call" then return d.group { format_expr_doc(e.callee, f), " ", arg_list_doc(e.args, f) } end
    if e.kind == "builtin" then return d.group { "c.builtin. ", e.name, " ", arg_list_doc(e.args, f) } end
    if e.kind == "compound" then
        local items = {}
        for i = 1, #(e.items or {}) do
            local item = e.items[i]
            if item.name then items[i] = d.group { head_name("init", item.name), "(", format_expr_doc(item.value, f), ")" }
            else items[i] = format_expr_doc(item, f) end
        end
        return d.group { "c.compound [", format_type_doc(e.ty, f), "] ", block_doc(items, f, function(x) return x end) }
    end
    if e.kind == "init_list" then return d.group { "c.list ", list_doc(e.items, f) } end
    if e.kind == "stmt_expr" then return d.group { "c.stmt_expr ", block_doc(e.body, f, format_stmt_doc) } end
    return d.text("c.raw_expr(" .. quote(expr_s(e, emit_context({ dialect = "gnu99" }))) .. ")")
end

local function header_component_doc(x, f)
    if x == nil or x == "" then return d.text(quote("")) end
    if lua_type(x) == "string" then return d.text(quote(x)) end
    if role(x) == "stmt" then return format_stmt_doc(x, f) end
    return format_expr_doc(x, f)
end

format_stmt_doc = function(s, f)
    if role(s) ~= "stmt" then return f:format(s) end
    if s.kind == "raw" then return d.text("c.raw_stmt(" .. quote(s.text) .. ")") end
    if s.kind == "return" then
        if not s.value or s.value.kind == "unit" then return d.text("c.return_()") end
        return d.group { "c.return_ (", format_expr_doc(s.value, f), ")" }
    end
    if s.kind == "expr" then return d.group { "c.expr(", format_expr_doc(s.value, f), ")" } end
    if s.kind == "assign" then return d.group { "c.assign(", format_expr_doc(s.lhs, f), ", ", format_expr_doc(s.rhs, f), ")" } end
    if s.kind == "decl" then
        return d.group { head_name("decl", s.name), " [", format_type_doc(s.ty, f), "] (", s.init and format_expr_doc(s.init, f) or d.text(""), ")" }
    end
    if s.kind == "auto" then return d.group { head_name("auto", s.name), "(", format_expr_doc(s.init, f), ")" } end
    if s.kind == "if" then
        local out = { "c.if_ (", format_expr_doc(s.cond, f), ") ", block_doc(s.then_body, f, format_stmt_doc) }
        if #(s.else_body or {}) > 0 then out[#out + 1] = " "; out[#out + 1] = block_doc(s.else_body, f, format_stmt_doc) end
        return d.group(out)
    end
    if s.kind == "for" then
        return d.group {
            "c.for_ { ", header_component_doc(s.init, f), ", ", format_expr_doc(s.cond, f), ", ", header_component_doc(s.step, f), " } ",
            block_doc(s.body, f, format_stmt_doc),
        }
    end
    if s.kind == "while" then return d.group { "c.while_ (", format_expr_doc(s.cond, f), ") ", block_doc(s.body, f, format_stmt_doc) } end
    return d.text("c.raw_stmt(" .. quote(s.kind) .. ")")
end

local function product_doc(items, f)
    return block_doc(items or {}, f, function(item)
        if item.raw then return d.text("c.raw_param(" .. quote(item.raw) .. ")") end
        return d.group { tostring(item.name), " [", format_type_doc(item.ty or item.type, f), "]" }
    end)
end

format_decl_doc = function(x, f)
    if role(x) == "unit" then return d.group { head_name("unit", x.name), " ", block_doc(x.decls, f, format_decl_doc) } end
    if role(x) ~= "decl" then return f:format(x) end
    if x.kind == "raw" then return d.text("c.raw_decl(" .. quote(x.text) .. ")") end
    if x.kind == "include" then return d.text("c.include " .. quote(x.header)) end
    if x.kind == "define" then return d.group { head_name("define", x.name), "(", f:format(x.value), ")" } end
    if x.kind == "typedef" then return d.group { head_name("typedef", x.name), " [", format_type_doc(x.ty, f), "]" } end
    if x.kind == "typedef_struct" then return d.group { head_name("typedef_struct", x.name), " ", product_doc(x.fields, f) } end
    if x.kind == "fn" then
        local head = x.storage == "static inline" and "static_inline_fn" or (x.storage == "static" and "static_fn" or "fn")
        return d.group { head_name(head, x.name), " ", product_doc(x.params, f), " [", format_type_doc(x.result, f), "] ", block_doc(x.body, f, format_stmt_doc) }
    end
    return d.text("c.raw_decl(" .. quote(x.kind) .. ")")
end

C.format = {
    namespace = "c",
    role_of = function(v) return role(v) end,
    role_formatters = {
        type = format_type_doc,
        expr = format_expr_doc,
        stmt = format_stmt_doc,
        decl = format_decl_doc,
        unit = format_decl_doc,
    },
    slot_formatters = {
        params = product_doc,
        fields = product_doc,
        decls = function(items, f) return block_doc(items, f, format_decl_doc) end,
        stmts = function(items, f) return block_doc(items, f, format_stmt_doc) end,
    },
    head_slot_formatters = {
        for_ = {
            spec = function(spec, f)
                spec = spec or {}
                return d.group {
                    "{ ",
                    header_component_doc(spec[1], f),
                    ", ",
                    spec[2] and format_expr_doc(spec[2], f) or d.text(""),
                    ", ",
                    header_component_doc(spec[3], f),
                    " }",
                }
            end,
        },
    },
}

local function with_c_lang(opts)
    opts = opts or {}
    if opts.dialect == nil then
        local out = {}
        for k, v in pairs(opts) do out[k] = v end
        out.dialect = C
        return out
    end
    return opts
end

function M.format(value, opts) return llbl.format(value, with_c_lang(opts)) end
function M.format_doc(value, opts) return llbl.format_doc(value, with_c_lang(opts)) end
function M.format_region(value, opts) return llbl.format_region(value, with_c_lang(opts)) end

function M.use(env)
    env = env or _G
    env.c = E
    env._ = llbl.spread
    local mt, old = getmetatable(env) or {}, getmetatable(env) and getmetatable(env).__index
    mt.__index = function(t, key)
        local v = E[key]
        if v ~= nil then return v end
        if old then
            local ov = lua_type(old) == "function" and old(t, key) or old[key]
            if ov ~= nil then return ov end
        end
        local s = llbl.shared.symbols.source(key)
        rawset(t, key, s)
        return s
    end
    setmetatable(env, mt)
    return E
end

for k, v in pairs(E) do M[k] = v end
M.Dialect = C
M.exports = E

return M
