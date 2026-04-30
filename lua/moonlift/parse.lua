local pvm = require("moonlift.pvm")

local M = {}

local TK = {
    eof = 0, name = 1, int = 2, float = 3, string = 4, nl = 5,
    lparen = 10, rparen = 11, lbrack = 12, rbrack = 13, lbrace = 14, rbrace = 15, comma = 16, colon = 17, dot = 18, semi = 19,
    plus = 20, minus = 21, star = 22, slash = 23, percent = 24, eq = 25, arrow = 26,
    eqeq = 27, ne = 28, lt = 29, le = 30, gt = 31, ge = 32,
    amp = 33, pipe = 34, caret = 35, tilde = 36,
    export = 100, extern = 101, func = 102, const = 103, static = 104, import = 105, type_kw = 106,
    let = 110, var = 111, if_kw = 112, then_kw = 113, elseif_kw = 114, else_kw = 115, switch = 116, case = 117, default = 118, do_kw = 119, end_kw = 120,
    block = 130, control = 131, jump = 132, yield = 133, return_kw = 134, region = 135, entry = 136, emit = 137, expr = 138,
    true_kw = 140, false_kw = 141, nil_kw = 142, and_kw = 143, or_kw = 144, not_kw = 145,
    view = 150, noalias = 151, readonly = 152, writeonly = 153, requires = 154, bounds = 155, disjoint = 156, len = 157, same_len = 158, view_window = 159, window_bounds = 160,
    as_kw = 170,
    struct = 180, union = 181, enum = 182,
}

local keywords = {
    export = TK.export, extern = TK.extern, func = TK.func, const = TK.const, static = TK.static, import = TK.import, ["type"] = TK.type_kw,
    let = TK.let, var = TK.var, ["if"] = TK.if_kw, ["then"] = TK.then_kw, ["elseif"] = TK.elseif_kw, ["else"] = TK.else_kw, switch = TK.switch, case = TK.case, default = TK.default, ["do"] = TK.do_kw, ["end"] = TK.end_kw,
    block = TK.block, control = TK.control, jump = TK.jump, ["yield"] = TK.yield, ["return"] = TK.return_kw, region = TK.region, entry = TK.entry, emit = TK.emit, expr = TK.expr,
    ["true"] = TK.true_kw, ["false"] = TK.false_kw, ["nil"] = TK.nil_kw, ["and"] = TK.and_kw, ["or"] = TK.or_kw, ["not"] = TK.not_kw,
    view = TK.view, noalias = TK.noalias, readonly = TK.readonly, writeonly = TK.writeonly, requires = TK.requires, bounds = TK.bounds, disjoint = TK.disjoint, len = TK.len, same_len = TK.same_len, view_window = TK.view_window, window_bounds = TK.window_bounds,
    ["as"] = TK.as_kw,
    struct = TK.struct, union = TK.union, enum = TK.enum,
}

local function is_alpha(b)
    return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
end

local function is_digit(b)
    return b >= 48 and b <= 57
end

local function new_tokens(src)
    return { src = src, kind = {}, text = {}, start = {}, stop = {}, line = {}, col = {}, n = 0 }
end

local function push(t, kind, text, s, e, line, col)
    local n = t.n + 1
    t.n = n
    t.kind[n] = kind
    t.text[n] = text
    t.start[n] = s
    t.stop[n] = e
    t.line[n] = line
    t.col[n] = col
end

local two_char = { ["->"] = TK.arrow, ["=="] = TK.eqeq, ["~="] = TK.ne, ["<="] = TK.le, [">="] = TK.ge }
local one_char = { ["("] = TK.lparen, [")"] = TK.rparen, ["["] = TK.lbrack, ["]"] = TK.rbrack, ["{"] = TK.lbrace, ["}"] = TK.rbrace, [","] = TK.comma, [":"] = TK.colon, ["."] = TK.dot, [";"] = TK.semi, ["+"] = TK.plus, ["-"] = TK.minus, ["*"] = TK.star, ["/"] = TK.slash, ["%"] = TK.percent, ["="] = TK.eq, ["<"] = TK.lt, [">"] = TK.gt, ["&"] = TK.amp, ["|"] = TK.pipe, ["^"] = TK.caret, ["~"] = TK.tilde }

function M.lex(src)
    local t = new_tokens(src)
    local i, n, line, col = 1, #src, 1, 1
    while i <= n do
        local b = src:byte(i)
        if b == 32 or b == 9 or b == 13 then
            i = i + 1; col = col + 1
        elseif b == 10 then
            push(t, TK.nl, "\n", i, i, line, col)
            i = i + 1; line = line + 1; col = 1
        elseif b == 45 and src:sub(i, i + 1) == "--" then
            if src:sub(i, i + 3) == "--[[" then
                i = i + 4; col = col + 4
                while i <= n and src:sub(i, i + 1) ~= "]]" do
                    if src:byte(i) == 10 then line = line + 1; col = 1; i = i + 1 else i = i + 1; col = col + 1 end
                end
                if i <= n then i = i + 2; col = col + 2 end
            else
                while i <= n and src:byte(i) ~= 10 do i = i + 1; col = col + 1 end
            end
        elseif is_alpha(b) then
            local s, c = i, col
            i = i + 1; col = col + 1
            while i <= n do
                local x = src:byte(i)
                if not (is_alpha(x) or is_digit(x)) then break end
                i = i + 1; col = col + 1
            end
            local text = src:sub(s, i - 1)
            push(t, keywords[text] or TK.name, text, s, i - 1, line, c)
        elseif is_digit(b) then
            local s, c, is_float = i, col, false
            i = i + 1; col = col + 1
            while i <= n and is_digit(src:byte(i)) do i = i + 1; col = col + 1 end
            if i <= n and src:byte(i) == 46 and not (i < n and src:byte(i + 1) == 46) then
                is_float = true; i = i + 1; col = col + 1
                while i <= n and is_digit(src:byte(i)) do i = i + 1; col = col + 1 end
            end
            local x = src:byte(i)
            if x == 101 or x == 69 then
                is_float = true; i = i + 1; col = col + 1
                local sign = src:byte(i); if sign == 43 or sign == 45 then i = i + 1; col = col + 1 end
                while i <= n and is_digit(src:byte(i)) do i = i + 1; col = col + 1 end
            end
            push(t, is_float and TK.float or TK.int, src:sub(s, i - 1), s, i - 1, line, c)
        elseif b == 34 then
            local s, c = i, col
            i = i + 1; col = col + 1
            while i <= n and src:byte(i) ~= 34 do
                if src:byte(i) == 10 then line = line + 1; col = 1; i = i + 1 else i = i + 1; col = col + 1 end
            end
            if i <= n then i = i + 1; col = col + 1 end
            push(t, TK.string, src:sub(s + 1, i - 2), s, i - 1, line, c)
        else
            local s2 = src:sub(i, i + 1)
            local kind = two_char[s2]
            if kind then
                push(t, kind, s2, i, i + 1, line, col); i = i + 2; col = col + 2
            else
                local ch = src:sub(i, i)
                kind = one_char[ch]
                if kind then push(t, kind, ch, i, i, line, col) end
                i = i + 1; col = col + 1
            end
        end
    end
    push(t, TK.eof, "", n + 1, n + 1, line, col)
    return t
end

local Parser = {}
Parser.__index = Parser

local function parser(T, src, opts)
    opts = opts or {}
    return setmetatable({ T = T, C = T.MoonCore, Ty = T.MoonType, B = T.MoonBind, O = T.MoonOpen, Sem = T.MoonSem, Tr = T.MoonTree, Pm = T.MoonParse, toks = M.lex(src), i = 1, issues = {}, region_seq = 0, value_env = opts.value_env or {}, cont_env = opts.cont_env or {}, region_frags = opts.region_frags or {}, expr_frags = opts.expr_frags or {} }, Parser)
end

function Parser:kind(offset) return self.toks.kind[self.i + (offset or 0)] end
function Parser:text(offset) return self.toks.text[self.i + (offset or 0)] end
function Parser:skip_nl() while self:kind() == TK.nl do self.i = self.i + 1 end end
function Parser:accept(k) if self:kind() == k then local text = self:text(); self.i = self.i + 1; return text end end
function Parser:issue(msg)
    local i = self.i
    self.issues[#self.issues + 1] = self.Pm.ParseIssue(msg, self.toks.start[i] or 0, self.toks.line[i] or 0, self.toks.col[i] or 0)
end
function Parser:expect(k, msg)
    local text = self:accept(k)
    if text == nil then self:issue(msg or ("expected token " .. tostring(k))); return "" end
    return text
end
function Parser:expect_name(msg) return self:expect(TK.name, msg or "expected identifier") end
function Parser:expect_field_name(msg)
    if self:kind() == TK.name or self:kind() == TK.len then
        local text = self:text()
        self.i = self.i + 1
        return text
    end
    return self:expect(TK.name, msg or "expected field name")
end
function Parser:is_stop(stops) return stops[self:kind()] == true end
function Parser:next_region_id(prefix)
    self.region_seq = self.region_seq + 1
    return "control." .. prefix .. "." .. tostring(self.region_seq)
end

function Parser:type_name(name)
    local C, Ty = self.C, self.Ty
    local m = { void = C.ScalarVoid, bool = C.ScalarBool, i8 = C.ScalarI8, i16 = C.ScalarI16, i32 = C.ScalarI32, i64 = C.ScalarI64, u8 = C.ScalarU8, u16 = C.ScalarU16, u32 = C.ScalarU32, u64 = C.ScalarU64, f32 = C.ScalarF32, f64 = C.ScalarF64, index = C.ScalarIndex, ptr = C.ScalarRawPtr }
    if m[name] then return Ty.TScalar(m[name]) end
    return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) })))
end

function Parser:parse_type()
    if self:accept(TK.view) then
        self:expect(TK.lparen); local elem = self:parse_type(); self:expect(TK.rparen); return self.Ty.TView(elem)
    end
    local name = self:expect_name("expected type")
    if name == "ptr" and self:accept(TK.lparen) then
        local elem = self:parse_type(); self:expect(TK.rparen); return self.Ty.TPtr(elem)
    end
    return self:type_name(name)
end

function Parser:parse_param_list()
    local params, contracts = {}, {}
    local Tr, B = self.Tr, self.B
    if self:kind() == TK.rparen then return params, contracts end
    while true do
        local mods = {}
        while self:kind() == TK.noalias or self:kind() == TK.readonly or self:kind() == TK.writeonly do
            mods[#mods + 1] = self:kind()
            self.i = self.i + 1
        end
        local name = self:expect_name("expected parameter name")
        self:expect(TK.colon, "expected ':' in parameter")
        params[#params + 1] = self.Ty.Param(name, self:parse_type())
        local ref = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name))
        for i = 1, #mods do
            if mods[i] == TK.noalias then contracts[#contracts + 1] = Tr.ContractNoAlias(ref)
            elseif mods[i] == TK.readonly then contracts[#contracts + 1] = Tr.ContractReadonly(ref)
            elseif mods[i] == TK.writeonly then contracts[#contracts + 1] = Tr.ContractWriteonly(ref) end
        end
        if not self:accept(TK.comma) then break end
    end
    return params, contracts
end

local lbp = { [TK.or_kw] = 10, [TK.and_kw] = 20, [TK.eqeq] = 30, [TK.ne] = 30, [TK.lt] = 30, [TK.le] = 30, [TK.gt] = 30, [TK.ge] = 30, [TK.pipe] = 40, [TK.caret] = 45, [TK.amp] = 50, [TK.plus] = 60, [TK.minus] = 60, [TK.star] = 70, [TK.slash] = 70, [TK.percent] = 70, [TK.lparen] = 90, [TK.lbrack] = 90, [TK.dot] = 90 }

function Parser:parse_expr(rbp)
    self:skip_nl()
    local left = self:nud()
    while rbp < (lbp[self:kind()] or 0) do
        local k = self:kind(); self.i = self.i + 1
        left = self:led(k, left)
    end
    return left
end

function Parser:parse_as_expr()
    local C, Tr = self.C, self.Tr
    self:expect(TK.lparen, "expected '(' in as expression")
    local ty = self:parse_type()
    self:expect(TK.comma, "expected ',' after target type in as expression")
    local value = self:parse_expr(0)
    self:expect(TK.rparen, "expected ')' in as expression")
    return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, ty, value)
end

function Parser:nud()
    local C, B, Tr = self.C, self.B, self.Tr
    local k, text = self:kind(), self:text()
    self.i = self.i + 1
    if k == TK.as_kw then return self:parse_as_expr() end
    if k == TK.int then return Tr.ExprLit(Tr.ExprSurface, C.LitInt(text)) end
    if k == TK.float then return Tr.ExprLit(Tr.ExprSurface, C.LitFloat(text)) end
    if k == TK.true_kw then return Tr.ExprLit(Tr.ExprSurface, C.LitBool(true)) end
    if k == TK.false_kw then return Tr.ExprLit(Tr.ExprSurface, C.LitBool(false)) end
    if k == TK.nil_kw then return Tr.ExprLit(Tr.ExprSurface, C.LitNil) end
    if k == TK.name then
        local binding = self.value_env and self.value_env[text]
        if binding then return Tr.ExprRef(Tr.ExprSurface, B.ValueRefBinding(binding)) end
        return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(text))
    end
    if k == TK.view then
        self:expect(TK.lparen)
        local data = self:parse_expr(0); self:expect(TK.comma); local len = self:parse_expr(0)
        if self:accept(TK.comma) then local stride = self:parse_expr(0); self:expect(TK.rparen); return Tr.ExprView(Tr.ExprSurface, Tr.ViewStrided(data, self.Ty.TScalar(C.ScalarVoid), len, stride)) end
        self:expect(TK.rparen)
        return Tr.ExprView(Tr.ExprSurface, Tr.ViewContiguous(data, self.Ty.TScalar(C.ScalarVoid), len))
    end
    if k == TK.len then self:expect(TK.lparen); local value = self:parse_expr(0); self:expect(TK.rparen); return Tr.ExprLen(Tr.ExprSurface, value) end
    if k == TK.view_window then self:expect(TK.lparen); local base = self:parse_expr(0); self:expect(TK.comma); local start = self:parse_expr(0); self:expect(TK.comma); local len = self:parse_expr(0); self:expect(TK.rparen); return Tr.ExprView(Tr.ExprSurface, Tr.ViewWindow(Tr.ViewFromExpr(base, self.Ty.TScalar(C.ScalarVoid)), start, len)) end
    if k == TK.lparen then local e = self:parse_expr(0); self:expect(TK.rparen); return e end
    if k == TK.minus then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNeg, self:parse_expr(80)) end
    if k == TK.not_kw then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNot, self:parse_expr(80)) end
    if k == TK.tilde then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryBitNot, self:parse_expr(80)) end
    if k == TK.switch then return self:parse_switch_expr() end
    if k == TK.emit then return self:parse_emit_expr() end
    if k == TK.block then return self:parse_control_expr_after_block() end
    if k == TK.control or k == TK.region then return self:parse_multi_control_expr() end
    self:issue("expected expression")
    return Tr.ExprLit(Tr.ExprSurface, C.LitInt("0"))
end

function Parser:led(k, left)
    local C, Sem, Tr = self.C, self.Sem, self.Tr
    if k == TK.lparen then
        local args = {}
        if self:kind() ~= TK.rparen then repeat args[#args + 1] = self:parse_expr(0) until not self:accept(TK.comma) end
        self:expect(TK.rparen)
        if pvm.classof(left) == Tr.ExprRef and pvm.classof(left.ref) == self.B.ValueRefName and left.ref.name == "select" and #args == 3 then
            return Tr.ExprSelect(Tr.ExprSurface, args[1], args[2], args[3])
        end
        return Tr.ExprCall(Tr.ExprSurface, Sem.CallUnresolved(left), args)
    elseif k == TK.lbrack then
        local index = self:parse_expr(0); self:expect(TK.rbrack)
        return Tr.ExprIndex(Tr.ExprSurface, Tr.IndexBaseExpr(left), index)
    elseif k == TK.dot then
        return Tr.ExprDot(Tr.ExprSurface, left, self:expect_name("expected field name"))
    end
    local bin = { [TK.plus] = C.BinAdd, [TK.minus] = C.BinSub, [TK.star] = C.BinMul, [TK.slash] = C.BinDiv, [TK.percent] = C.BinRem, [TK.amp] = C.BinBitAnd, [TK.pipe] = C.BinBitOr, [TK.caret] = C.BinBitXor }
    local cmp = { [TK.eqeq] = C.CmpEq, [TK.ne] = C.CmpNe, [TK.lt] = C.CmpLt, [TK.le] = C.CmpLe, [TK.gt] = C.CmpGt, [TK.ge] = C.CmpGe }
    if bin[k] then return Tr.ExprBinary(Tr.ExprSurface, bin[k], left, self:parse_expr(lbp[k])) end
    if cmp[k] then return Tr.ExprCompare(Tr.ExprSurface, cmp[k], left, self:parse_expr(lbp[k])) end
    if k == TK.and_kw then return Tr.ExprLogic(Tr.ExprSurface, C.LogicAnd, left, self:parse_expr(lbp[k])) end
    if k == TK.or_kw then return Tr.ExprLogic(Tr.ExprSurface, C.LogicOr, left, self:parse_expr(lbp[k])) end
    self:issue("unknown infix operator")
    return left
end

function Parser:expr_to_place(expr)
    local Tr, B = self.Tr, self.B
    local cls = require("moonlift.pvm").classof(expr)
    if cls == Tr.ExprRef then return Tr.PlaceRef(Tr.PlaceSurface, expr.ref) end
    if cls == Tr.ExprIndex then return Tr.PlaceIndex(Tr.PlaceSurface, expr.base, expr.index) end
    self:issue("assignment target is not a place")
    return Tr.PlaceRef(Tr.PlaceSurface, B.ValueRefName("<bad-place>"))
end

function Parser:parse_jump_args()
    local Tr = self.Tr
    local args = {}
    self:expect(TK.lparen)
    self:skip_nl()
    if self:kind() ~= TK.rparen then
        while true do
            self:skip_nl()
            local name = self:expect_name("expected jump arg name")
            self:expect(TK.eq, "expected '=' in jump arg")
            args[#args + 1] = Tr.JumpArg(name, self:parse_expr(0))
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.rparen then break end
        end
    end
    self:expect(TK.rparen)
    return args
end

function Parser:parse_block_params(entry)
    local Tr = self.Tr
    local params = {}
    self:expect(TK.lparen)
    self:skip_nl()
    if self:kind() ~= TK.rparen then
        while true do
            self:skip_nl()
            local name = self:expect_name("expected block parameter")
            self:expect(TK.colon)
            local ty = self:parse_type()
            if entry then
                self:expect(TK.eq, "entry block params need initializers")
                params[#params + 1] = Tr.EntryBlockParam(name, ty, self:parse_expr(0))
            else
                params[#params + 1] = Tr.BlockParam(name, ty)
            end
            self:skip_nl()
            if not self:accept(TK.comma) then break end
        end
    end
    self:expect(TK.rparen)
    return params
end

function Parser:parse_stmt_until(stops)
    local out = {}
    self:skip_nl()
    while not self:is_stop(stops) and self:kind() ~= TK.eof do
        out[#out + 1] = self:parse_stmt()
        self:skip_nl()
    end
    return out
end

function Parser:parse_if_stmt()
    local Tr = self.Tr
    local cond = self:parse_expr(0)
    self:expect(TK.then_kw, "expected then")
    local then_body = self:parse_stmt_until({ [TK.else_kw] = true, [TK.end_kw] = true })
    local else_body = {}
    if self:accept(TK.else_kw) then else_body = self:parse_stmt_until({ [TK.end_kw] = true }) end
    self:expect(TK.end_kw, "expected end")
    return Tr.StmtIf(Tr.StmtSurface, cond, then_body, else_body)
end

function Parser:switch_key_from_expr(expr)
    local C, Sem, Tr, B = self.C, self.Sem, self.Tr, self.B
    local cls = pvm.classof(expr)
    if cls == Tr.ExprLit then
        local lit = pvm.classof(expr.value)
        if lit == C.LitInt then return Sem.SwitchKeyRaw(expr.value.raw) end
        if lit == C.LitBool then return Sem.SwitchKeyRaw(expr.value.value and "true" or "false") end
    end
    if cls == Tr.ExprRef then
        if pvm.classof(expr.ref) == B.ValueRefName then
            return Sem.SwitchKeyRaw(expr.ref.name)
        end
    end
    return Sem.SwitchKeyExpr(expr)
end

function Parser:parse_switch_stmt()
    local Tr, Sem = self.Tr, self.Sem
    local value = self:parse_expr(0)
    self:expect(TK.do_kw, "expected do after switch expression")
    self:skip_nl()
    local arms = {}
    while self:kind() == TK.case do
        self.i = self.i + 1
        local key_expr = self:parse_expr(0)
        self:expect(TK.then_kw, "expected then after case expression")
        local body = self:parse_stmt_until({ [TK.case] = true, [TK.default] = true, [TK.end_kw] = true })
        arms[#arms + 1] = Tr.SwitchStmtArm(self:switch_key_from_expr(key_expr), body)
    end
    if #arms == 0 then self:issue("switch statement must have at least one case arm") end
    self:expect(TK.default, "expected default in switch")
    self:expect(TK.then_kw, "expected then after default")
    local default_body = self:parse_stmt_until({ [TK.end_kw] = true })
    self:expect(TK.end_kw, "expected end")
    return Tr.StmtSwitch(Tr.StmtSurface, value, arms, default_body)
end

function Parser:parse_switch_expr()
    local Tr, Sem = self.Tr, self.Sem
    local value = self:parse_expr(0)
    self:expect(TK.do_kw, "expected do after switch expression")
    self:skip_nl()
    local arms = {}
    while self:kind() == TK.case do
        self.i = self.i + 1
        local key_expr = self:parse_expr(0)
        self:expect(TK.then_kw, "expected then after case expression")
        local body, result = self:parse_expr_block({ [TK.case] = true, [TK.default] = true, [TK.end_kw] = true })
        arms[#arms + 1] = Tr.SwitchExprArm(self:switch_key_from_expr(key_expr), body, result)
    end
    if #arms == 0 then self:issue("switch expression must have at least one case arm") end
    self:expect(TK.default, "expected default in switch")
    self:expect(TK.then_kw, "expected then after default")
    local default_body, default_expr = self:parse_expr_block({ [TK.end_kw] = true })
    self:expect(TK.end_kw, "expected end")
    return Tr.ExprSwitch(Tr.ExprSurface, value, arms, default_expr)
end

function Parser:parse_expr_block(stops)
    local C, Tr = self.C, self.Tr
    local stmts = {}
    self:skip_nl()
    while not self:is_stop(stops) and self:kind() ~= TK.eof do
        stmts[#stmts + 1] = self:parse_stmt()
        self:skip_nl()
    end
    if #stmts == 0 then
        self:issue("expected expression in switch arm")
        return {}, Tr.ExprLit(Tr.ExprSurface, C.LitInt("0"))
    end
    local last = stmts[#stmts]
    stmts[#stmts] = nil
    if pvm.classof(last) ~= Tr.StmtExpr then
        self:issue("expected expression as last item in switch arm")
        return stmts, Tr.ExprLit(Tr.ExprSurface, C.LitInt("0"))
    end
    return stmts, last.expr
end

function Parser:parse_stmt_control_after_block()
    local Tr = self.Tr
    local label = Tr.BlockLabel(self:expect_name("expected block label"))
    local params = self:parse_block_params(true)
    local body = self:parse_stmt_until({ [TK.end_kw] = true })
    self:expect(TK.end_kw)
    return Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion(self:next_region_id(label.name), Tr.EntryControlBlock(label, params, body), {}))
end

function Parser:parse_control_expr_after_block()
    local Tr = self.Tr
    local label = Tr.BlockLabel(self:expect_name("expected block label"))
    local params = self:parse_block_params(true)
    self:expect(TK.arrow, "expected -> for block expression")
    local result_ty = self:parse_type()
    local body = self:parse_stmt_until({ [TK.end_kw] = true })
    self:expect(TK.end_kw)
    return Tr.ExprControl(Tr.ExprSurface, Tr.ControlExprRegion(self:next_region_id(label.name), result_ty, Tr.EntryControlBlock(label, params, body), {}))
end

function Parser:parse_multi_control_expr()
    local Tr = self.Tr
    self:expect(TK.arrow, "expected -> after control")
    local result_ty = self:parse_type()
    self:skip_nl()
    if not (self:accept(TK.entry) or self:accept(TK.block)) then self:expect(TK.entry, "expected entry block") end
    local entry_label = Tr.BlockLabel(self:expect_name("expected block label"))
    local entry_params = self:parse_block_params(true)
    local entry_body = self:parse_stmt_until({ [TK.end_kw] = true })
    self:expect(TK.end_kw)
    local blocks = {}
    self:skip_nl()
    while self:kind() == TK.block do
        self.i = self.i + 1
        local label = Tr.BlockLabel(self:expect_name("expected block label"))
        local params = self:parse_block_params(false)
        local body = self:parse_stmt_until({ [TK.end_kw] = true })
        self:expect(TK.end_kw)
        blocks[#blocks + 1] = Tr.ControlBlock(label, params, body)
        self:skip_nl()
    end
    self:expect(TK.end_kw, "expected control end")
    return Tr.ExprControl(Tr.ExprSurface, Tr.ControlExprRegion(self:next_region_id(entry_label.name), result_ty, Tr.EntryControlBlock(entry_label, entry_params, entry_body), blocks))
end

function Parser:parse_call_expr_args()
    local args = {}
    self:expect(TK.lparen, "expected '(' in argument list")
    self:skip_nl()
    if self:kind() ~= TK.rparen then
        while true do
            args[#args + 1] = self:parse_expr(0)
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.rparen then break end
        end
    end
    self:expect(TK.rparen, "expected ')' after argument list")
    return args
end

function Parser:parse_emit_expr()
    local Tr = self.Tr
    local frag_name = self:expect_name("expected expression fragment name after emit")
    local frag_value = self.expr_frags[frag_name]
    local args = self:parse_call_expr_args()
    if frag_value == nil then
        self:issue("unknown expression fragment in emit: " .. frag_name)
        return Tr.ExprLit(Tr.ExprSurface, self.C.LitInt("0"))
    end
    return Tr.ExprUseExprFrag(Tr.ExprSurface, "emit.expr." .. frag_name .. "." .. tostring(self.i), frag_value.frag, args, {})
end

function Parser:parse_emit_stmt()
    local Tr, O = self.Tr, self.O
    local frag_name = self:expect_name("expected region fragment name after emit")
    local frag_value = self.region_frags[frag_name]
    if frag_value == nil then self:issue("unknown region fragment in emit: " .. frag_name) end
    local args, fills = {}, {}
    self:expect(TK.lparen, "expected '(' after emitted fragment name")
    self:skip_nl()
    if self:kind() ~= TK.rparen and self:kind() ~= TK.semi then
        while true do
            args[#args + 1] = self:parse_expr(0)
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.semi or self:kind() == TK.rparen then break end
        end
    end
    self:skip_nl()
    local seen_fills = {}
    if self:accept(TK.semi) then
        self:skip_nl()
        while self:kind() ~= TK.rparen and self:kind() ~= TK.eof do
            local name = self:expect_name("expected continuation fill name")
            self:expect(TK.eq, "expected '=' in continuation fill")
            local label = self:expect_name("expected block label in continuation fill")
            if seen_fills[name] then self:issue("duplicate continuation fill for fragment " .. frag_name .. ": " .. name) end
            seen_fills[name] = true
            if frag_value and frag_value.cont_slots and frag_value.cont_slots[name] then
                if self.cont_env and self.cont_env[label] then
                    fills[#fills + 1] = O.SlotBinding(O.SlotCont(frag_value.cont_slots[name]), O.SlotValueContSlot(self.cont_env[label]))
                else
                    fills[#fills + 1] = O.SlotBinding(O.SlotCont(frag_value.cont_slots[name]), O.SlotValueCont(Tr.BlockLabel(label)))
                end
            else
                self:issue("unknown continuation fill for fragment " .. frag_name .. ": " .. name)
            end
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
        end
    end
    if frag_value and frag_value.cont_slots then
        for name, _ in pairs(frag_value.cont_slots) do
            if not seen_fills[name] then self:issue("missing continuation fill for fragment " .. frag_name .. ": " .. name) end
        end
    end
    self:expect(TK.rparen, "expected ')' after emit")
    if frag_value == nil then return Tr.StmtExpr(Tr.StmtSurface, Tr.ExprLit(Tr.ExprSurface, self.C.LitInt("0"))) end
    return Tr.StmtUseRegionFrag(Tr.StmtSurface, "emit." .. frag_name .. "." .. tostring(self.i), frag_value.frag, args, fills)
end

function Parser:parse_stmt()
    local Tr, B, C = self.Tr, self.B, self.C
    self:skip_nl()
    if self:accept(TK.emit) then return self:parse_emit_stmt() end
    if self:accept(TK.let) or self:accept(TK.var) then
        local is_var = self.toks.kind[self.i - 1] == TK.var
        local name = self:expect_name(); self:expect(TK.colon); local ty = self:parse_type(); self:expect(TK.eq); local init = self:parse_expr(0)
        local binding = B.Binding(C.Id("local:" .. name), name, ty, is_var and B.BindingClassLocalCell or B.BindingClassLocalValue)
        return is_var and Tr.StmtVar(Tr.StmtSurface, binding, init) or Tr.StmtLet(Tr.StmtSurface, binding, init)
    end
    if self:accept(TK.if_kw) then return self:parse_if_stmt() end
    if self:accept(TK.switch) then return self:parse_switch_stmt() end
    if self:accept(TK.return_kw) then if self:kind() == TK.nl or self:kind() == TK.end_kw then return Tr.StmtReturnVoid(Tr.StmtSurface) end; return Tr.StmtReturnValue(Tr.StmtSurface, self:parse_expr(0)) end
    if self:accept(TK.yield) then if self:kind() == TK.nl or self:kind() == TK.end_kw then return Tr.StmtYieldVoid(Tr.StmtSurface) end; return Tr.StmtYieldValue(Tr.StmtSurface, self:parse_expr(0)) end
    if self:accept(TK.jump) then
        local name = self:expect_name()
        local args = self:parse_jump_args()
        if self.cont_env and self.cont_env[name] then return Tr.StmtJumpCont(Tr.StmtSurface, self.cont_env[name], args) end
        return Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel(name), args)
    end
    if self:accept(TK.block) then return self:parse_stmt_control_after_block() end
    local e = self:parse_expr(0)
    if self:accept(TK.eq) then return Tr.StmtSet(Tr.StmtSurface, self:expr_to_place(e), self:parse_expr(0)) end
    return Tr.StmtExpr(Tr.StmtSurface, e)
end

function Parser:parse_contract()
    local Tr = self.Tr
    self:expect(TK.requires, "expected requires")
    if self:accept(TK.bounds) then
        self:expect(TK.lparen); local base = self:parse_expr(0); self:expect(TK.comma); local len = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractBounds(base, len)
    elseif self:accept(TK.window_bounds) then
        self:expect(TK.lparen); local base = self:parse_expr(0); self:expect(TK.comma); local base_len = self:parse_expr(0); self:expect(TK.comma); local start = self:parse_expr(0); self:expect(TK.comma); local len = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractWindowBounds(base, base_len, start, len)
    elseif self:accept(TK.disjoint) then
        self:expect(TK.lparen); local a = self:parse_expr(0); self:expect(TK.comma); local b = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractDisjoint(a, b)
    elseif self:accept(TK.same_len) then
        self:expect(TK.lparen); local a = self:parse_expr(0); self:expect(TK.comma); local b = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractSameLen(a, b)
    elseif self:accept(TK.noalias) then
        self:expect(TK.lparen); local base = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractNoAlias(base)
    elseif self:accept(TK.readonly) then
        self:expect(TK.lparen); local base = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractReadonly(base)
    elseif self:accept(TK.writeonly) then
        self:expect(TK.lparen); local base = self:parse_expr(0); self:expect(TK.rparen)
        return Tr.ContractWriteonly(base)
    end
    self:issue("expected contract predicate")
    return Tr.ContractNoAlias(Tr.ExprRef(Tr.ExprSurface, self.B.ValueRefName("<bad-contract>")))
end

function Parser:parse_extern_func()
    local Tr, Ty, C = self.Tr, self.Ty, self.C
    local name = self:expect_name("expected extern function name")
    self:expect(TK.lparen); local params = self:parse_param_list(); self:expect(TK.rparen)
    local result = Ty.TScalar(C.ScalarVoid)
    if self:accept(TK.arrow) then result = self:parse_type() end
    return Tr.ExternFunc(name, name, params, result)
end

function Parser:parse_func(exported)
    local Tr, Ty, C = self.Tr, self.Ty, self.C
    local name = self:expect_name("expected function name")
    self:expect(TK.lparen); local params, contracts = self:parse_param_list(); self:expect(TK.rparen)
    local result = Ty.TScalar(C.ScalarVoid)
    if self:accept(TK.arrow) then result = self:parse_type() end
    self:skip_nl()
    while self:kind() == TK.requires do
        contracts[#contracts + 1] = self:parse_contract()
        self:skip_nl()
    end
    local body = self:parse_stmt_until({ [TK.end_kw] = true })
    self:expect(TK.end_kw, "expected end after function")
    if #contracts > 0 then
        if exported then return Tr.FuncExportContract(name, params, result, contracts, body) end
        return Tr.FuncLocalContract(name, params, result, contracts, body)
    end
    if exported then return Tr.FuncExport(name, params, result, body) end
    return Tr.FuncLocal(name, params, result, body)
end

function Parser:parse_cont_params()
    local Tr, O = self.Tr, self.O
    local cont_slots = {}
    local slots = {}
    while self:kind() ~= TK.rparen and self:kind() ~= TK.eof do
        local name = self:expect_name("expected continuation parameter name")
        self:expect(TK.colon, "expected ':' in continuation parameter")
        self:expect(TK.name, "expected cont in continuation parameter")
        self:expect(TK.lparen, "expected '(' in cont type")
        local params = {}
        self:skip_nl()
        if self:kind() ~= TK.rparen then
            while true do
                local pname = self:expect_name("expected continuation arg name")
                self:expect(TK.colon, "expected ':' in continuation arg")
                params[#params + 1] = Tr.BlockParam(pname, self:parse_type())
                self:skip_nl()
                if not self:accept(TK.comma) then break end
                self:skip_nl()
            end
        end
        self:expect(TK.rparen, "expected ')' after cont type")
        local slot = O.ContSlot("cont:" .. name .. ":" .. tostring(#slots + 1), name, params)
        cont_slots[name] = slot
        slots[#slots + 1] = O.SlotCont(slot)
        self:skip_nl()
        if not self:accept(TK.comma) then break end
        self:skip_nl()
    end
    return cont_slots, slots
end

function Parser:parse_open_expr_params(owner_name)
    local O, B, C = self.O, self.B, self.C
    local params, param_bindings = {}, {}
    self:skip_nl()
    if self:kind() ~= TK.rparen then
        while true do
            local pname = self:expect_name("expected parameter name")
            self:expect(TK.colon, "expected ':' in parameter")
            local ty = self:parse_type()
            local param = O.OpenParam("param:" .. owner_name .. ":" .. pname .. ":" .. tostring(#params + 1), pname, ty)
            params[#params + 1] = param
            param_bindings[pname] = B.Binding(C.Id("open-param:" .. owner_name .. ":" .. pname), pname, ty, B.BindingClassOpenParam(param))
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.rparen then break end
        end
    end
    return params, param_bindings
end

function Parser:parse_expr_frag()
    local O = self.O
    self:expect(TK.expr, "expected expr")
    local name = self:expect_name("expected expression fragment name")
    self:expect(TK.lparen, "expected '(' in expression fragment")
    local params, param_bindings = self:parse_open_expr_params(name)
    self:expect(TK.rparen, "expected ')' after expression fragment params")
    self:expect(TK.arrow, "expected -> in expression fragment")
    local result = self:parse_type()
    local old_value_env = self.value_env
    self.value_env = param_bindings
    local body = self:parse_expr(0)
    self:skip_nl()
    self:expect(TK.end_kw, "expected end after expression fragment")
    self.value_env = old_value_env
    return { name = name, frag = O.ExprFrag(params, O.OpenSet({}, {}, {}, {}), body, result) }
end

function Parser:validate_cont_jump_args_in_stmts(stmts, cont_slots)
    local Tr = self.Tr
    for i = 1, #stmts do
        local stmt = stmts[i]
        local cls = require("moonlift.pvm").classof(stmt)
        if cls == Tr.StmtJumpCont then
            local slot = stmt.slot
            local expected, actual = {}, {}
            for j = 1, #slot.params do expected[slot.params[j].name] = true end
            for j = 1, #stmt.args do
                local name = stmt.args[j].name
                if actual[name] then self:issue("duplicate continuation jump arg for " .. slot.pretty_name .. ": " .. name) end
                actual[name] = true
                if not expected[name] then self:issue("extra continuation jump arg for " .. slot.pretty_name .. ": " .. name) end
            end
            for j = 1, #slot.params do
                local name = slot.params[j].name
                if not actual[name] then self:issue("missing continuation jump arg for " .. slot.pretty_name .. ": " .. name) end
            end
        elseif cls == Tr.StmtIf then
            self:validate_cont_jump_args_in_stmts(stmt.then_body, cont_slots)
            self:validate_cont_jump_args_in_stmts(stmt.else_body, cont_slots)
        elseif cls == Tr.StmtSwitch then
            for j = 1, #stmt.arms do self:validate_cont_jump_args_in_stmts(stmt.arms[j].body, cont_slots) end
            self:validate_cont_jump_args_in_stmts(stmt.default_body, cont_slots)
        end
    end
end

function Parser:parse_region_frag()
    local O, B, C, Tr = self.O, self.B, self.C, self.Tr
    self:expect(TK.region, "expected region")
    local name = self:expect_name("expected region fragment name")
    self:expect(TK.lparen, "expected '(' in region fragment")
    local params, param_bindings, slots = {}, {}, {}
    self:skip_nl()
    if self:kind() ~= TK.rparen and self:kind() ~= TK.semi then
        while true do
            local pname = self:expect_name("expected region parameter name")
            self:expect(TK.colon, "expected ':' in region parameter")
            local ty = self:parse_type()
            local param = O.OpenParam("param:" .. name .. ":" .. pname .. ":" .. tostring(#params + 1), pname, ty)
            params[#params + 1] = param
            param_bindings[pname] = B.Binding(C.Id("open-param:" .. name .. ":" .. pname), pname, ty, B.BindingClassOpenParam(param))
            self:skip_nl()
            if not self:accept(TK.comma) then break end
            self:skip_nl()
            if self:kind() == TK.semi or self:kind() == TK.rparen then break end
        end
    end
    local cont_slots = {}
    if self:accept(TK.semi) then
        self:skip_nl()
        cont_slots, slots = self:parse_cont_params()
    end
    self:expect(TK.rparen, "expected ')' after region fragment params")
    self:skip_nl()
    if not (self:accept(TK.entry) or self:accept(TK.block)) then self:expect(TK.entry, "expected entry block in region fragment") end
    local entry_label = Tr.BlockLabel(self:expect_name("expected entry label in region fragment"))
    local entry_params = self:parse_block_params(true)
    local old_value_env, old_cont_env = self.value_env, self.cont_env
    self.value_env, self.cont_env = param_bindings, cont_slots
    local body = self:parse_stmt_until({ [TK.end_kw] = true })
    self:expect(TK.end_kw, "expected end after region fragment entry")
    local blocks = {}
    self:skip_nl()
    while self:kind() == TK.block do
        self.i = self.i + 1
        local label = Tr.BlockLabel(self:expect_name("expected fragment block label"))
        local block_params = self:parse_block_params(false)
        local block_body = self:parse_stmt_until({ [TK.end_kw] = true })
        self:expect(TK.end_kw, "expected end after fragment block")
        blocks[#blocks + 1] = Tr.ControlBlock(label, block_params, block_body)
        self:skip_nl()
    end
    self:validate_cont_jump_args_in_stmts(body, cont_slots)
    for i = 1, #blocks do self:validate_cont_jump_args_in_stmts(blocks[i].body, cont_slots) end
    self:expect(TK.end_kw, "expected end after region fragment")
    self.value_env, self.cont_env = old_value_env, old_cont_env
    return { name = name, frag = O.RegionFrag(params, O.OpenSet({}, {}, {}, slots), Tr.EntryControlBlock(entry_label, entry_params, body), blocks), cont_slots = cont_slots }
end

function Parser:parse_type_fields()
    local fields = {}
    self:skip_nl()
    if self:kind() == TK.lbrace then self:issue("type declarations use keyword...end, not braces"); self.i = self.i + 1 end
    while self:kind() ~= TK.end_kw and self:kind() ~= TK.rbrace and self:kind() ~= TK.eof do
        local name = self:expect_field_name("expected field name")
        self:expect(TK.colon, "expected ':' in field declaration")
        fields[#fields + 1] = self.Ty.FieldDecl(name, self:parse_type())
        self:skip_nl()
        if self:accept(TK.comma) then self:skip_nl() end
    end
    if self:kind() == TK.rbrace then self.i = self.i + 1 end
    self:expect(TK.end_kw, "expected end after type declaration")
    return fields
end

function Parser:parse_enum_variants()
    local variants = {}
    self:skip_nl()
    if self:kind() == TK.lbrace then self:issue("enum declarations use keyword...end, not braces"); self.i = self.i + 1 end
    while self:kind() ~= TK.end_kw and self:kind() ~= TK.rbrace and self:kind() ~= TK.eof do
        variants[#variants + 1] = self.C.Name(self:expect_name("expected enum variant"))
        self:skip_nl()
        if self:accept(TK.comma) then self:skip_nl() end
    end
    if self:kind() == TK.rbrace then self.i = self.i + 1 end
    self:expect(TK.end_kw, "expected end after enum declaration")
    return variants
end

function Parser:parse_tagged_union_variants()
    local variants = {}
    while self:kind() ~= TK.eof do
        self:skip_nl()
        local name = self:expect_name("expected tagged union variant")
        local payload = self.Ty.TScalar(self.C.ScalarVoid)
        if self:accept(TK.lparen) then
            payload = self:parse_type()
            self:expect(TK.rparen, "expected ')' after tagged union payload")
        end
        variants[#variants + 1] = self.Ty.VariantDecl(name, payload)
        self:skip_nl()
        if not self:accept(TK.pipe) then break end
    end
    return variants
end

function Parser:parse_type_item()
    local Tr = self.Tr
    local name = self:expect_name("expected type name")
    self:expect(TK.eq, "expected '=' in type item")
    if self:accept(TK.struct) then return Tr.ItemType(Tr.TypeDeclStruct(name, self:parse_type_fields())) end
    if self:accept(TK.union) then return Tr.ItemType(Tr.TypeDeclUnion(name, self:parse_type_fields())) end
    if self:accept(TK.enum) then return Tr.ItemType(Tr.TypeDeclEnumSugar(name, self:parse_enum_variants())) end
    return Tr.ItemType(Tr.TypeDeclTaggedUnionSugar(name, self:parse_tagged_union_variants()))
end

function Parser:parse_item()
    local Tr = self.Tr
    self:skip_nl()
    local exported = self:accept(TK.export) ~= nil
    if self:accept(TK.func) then return Tr.ItemFunc(self:parse_func(exported)) end
    if self:accept(TK.extern) then self:expect(TK.func, "expected func after extern"); return Tr.ItemExtern(self:parse_extern_func()) end
    if self:accept(TK.const) then local name = self:expect_name("expected const name"); self:expect(TK.colon); local ty = self:parse_type(); self:expect(TK.eq); return Tr.ItemConst(Tr.ConstItem(name, ty, self:parse_expr(0))) end
    if self:accept(TK.static) then local name = self:expect_name("expected static name"); self:expect(TK.colon); local ty = self:parse_type(); self:expect(TK.eq); return Tr.ItemStatic(Tr.StaticItem(name, ty, self:parse_expr(0))) end
    if self:accept(TK.type_kw) then return self:parse_type_item() end
    self:issue("expected item")
    self.i = self.i + 1
    return nil
end

function Parser:parse_module()
    local Tr = self.Tr
    local items = {}
    self:skip_nl()
    while self:kind() ~= TK.eof do
        local item = self:parse_item()
        if item ~= nil then items[#items + 1] = item end
        self:skip_nl()
    end
    return Tr.Module(Tr.ModuleSurface, items)
end

function M.parse(T, src, opts)
    local p = parser(T, src, opts)
    local module = p:parse_module()
    return T.MoonParse.ParseResult(module, p.issues)
end

function M.parse_region_frag(T, src, opts)
    local p = parser(T, src, opts)
    local value = p:parse_region_frag()
    return { value = value, issues = p.issues }
end

function M.parse_expr_frag(T, src)
    local p = parser(T, src)
    local value = p:parse_expr_frag()
    return { value = value, issues = p.issues }
end

function M.Define(T)
    return {
        TK = TK,
        lex = M.lex,
        parse_module = function(src, opts) return M.parse(T, src, opts) end,
        parse_region_frag = function(src, opts) return M.parse_region_frag(T, src, opts) end,
        parse_expr_frag = function(src) return M.parse_expr_frag(T, src) end,
    }
end

return M
