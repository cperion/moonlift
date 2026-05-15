-- Native-token MoonTree materializer for MOM.
--
-- The token tape comes from compiled Moonlift code (`native_lexer.mlua`). This
-- module materializes that native token stream into the existing MoonTree ASDL
-- value representation, so the native front-end feeds the real typecheck,
-- lowering, validation, and JIT pipeline.

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

local M = {}

local TK = {
    eof = 0, name = 1, int = 2, float = 3, string = 4, nl = 5, hole = 6, invalid = 7,
    lparen = 10, rparen = 11, lbrack = 12, rbrack = 13, lbrace = 14, rbrace = 15,
    comma = 16, colon = 17, dot = 18, semi = 19,
    plus = 20, minus = 21, star = 22, slash = 23, percent = 24, eq = 25, arrow = 26,
    eqeq = 27, ne = 28, lt = 29, le = 30, gt = 31, ge = 32,
    amp = 33, pipe = 34, caret = 35, tilde = 36, shl = 37, lshr = 38, ashr = 39,
    func_kw = 102, type_kw = 106, let_kw = 110, var_kw = 111, if_kw = 112, then_kw = 113,
    elseif_kw = 114, else_kw = 115, switch_kw = 116, case_kw = 117, default_kw = 118, do_kw = 119,
    end_kw = 120, block_kw = 130, jump_kw = 132, yield_kw = 133, return_kw = 134,
    region_kw = 135, entry_kw = 136, emit_kw = 137, expr_kw = 138,
    true_kw = 140, false_kw = 141, nil_kw = 142, and_kw = 143, or_kw = 144, not_kw = 145,
    view_kw = 150, noalias_kw = 151, readonly_kw = 152, writeonly_kw = 153,
    requires_kw = 154, bounds_kw = 155, disjoint_kw = 156, len_kw = 157, same_len_kw = 158,
    window_bounds_kw = 159, as_kw = 170, struct_kw = 180, union_kw = 181, extern_kw = 182,
}
M.TK = TK

local native_unit
local function native_lexer()
    if native_unit then return native_unit end
    local mod = Host.dofile("lua/moonlift/mom/parser/native_lexer.mlua")
    native_unit = mod:compile()
    return native_unit
end

function M.free_native()
    if native_unit then native_unit.artifact:free(); native_unit = nil end
end

function M.lex(src)
    local unit = native_lexer()
    local lex = unit:get("mom_lex_into")
    local n = #src
    local p = ffi.new("uint8_t[?]", n > 0 and n or 1)
    if n > 0 then ffi.copy(p, src, n) end

    local cap = math.max(32, n + 8)
    while true do
        local kinds = ffi.new("int32_t[?]", cap)
        local starts = ffi.new("int32_t[?]", cap)
        local stops = ffi.new("int32_t[?]", cap)
        local lines = ffi.new("int32_t[?]", cap)
        local cols = ffi.new("int32_t[?]", cap)
        local count = tonumber(lex(p, n, kinds, starts, stops, lines, cols, cap))
        if count <= cap then
            local toks = { src = src, n = count, kind = {}, text = {}, start = {}, stop = {}, line = {}, col = {} }
            for i = 1, count do
                local j = i - 1
                local s, e = tonumber(starts[j]), tonumber(stops[j])
                toks.kind[i] = tonumber(kinds[j])
                toks.start[i] = s
                toks.stop[i] = e
                toks.line[i] = tonumber(lines[j])
                toks.col[i] = tonumber(cols[j])
                toks.text[i] = src:sub(s + 1, e)
            end
            return toks
        end
        cap = count + 8
    end
end

local Parser = {}
Parser.__index = Parser

local lbp = {
    [TK.or_kw] = 10, [TK.and_kw] = 20,
    [TK.eqeq] = 30, [TK.ne] = 30, [TK.lt] = 30, [TK.le] = 30, [TK.gt] = 30, [TK.ge] = 30,
    [TK.pipe] = 40, [TK.caret] = 50, [TK.amp] = 60,
    [TK.shl] = 70, [TK.ashr] = 70, [TK.lshr] = 70,
    [TK.plus] = 80, [TK.minus] = 80,
    [TK.star] = 90, [TK.slash] = 90, [TK.percent] = 90,
    [TK.lparen] = 100, [TK.lbrack] = 100, [TK.dot] = 100,
}

function Parser:kind(off) return self.toks.kind[self.i + (off or 0)] or TK.eof end
function Parser:text(off) return self.toks.text[self.i + (off or 0)] or "" end
function Parser:skip_nl() while self:kind() == TK.nl do self.i = self.i + 1 end end
function Parser:skip_sep() while self:kind() == TK.nl or self:kind() == TK.semi do self.i = self.i + 1 end end
function Parser:accept(k) if self:kind() == k then self.i = self.i + 1; return true end; return false end
function Parser:expect(k, msg)
    if self:kind() == k then local t = self:text(); self.i = self.i + 1; return t end
    self:issue(msg or ("expected token " .. tostring(k)))
    return "<missing>"
end
function Parser:expect_name(msg)
    if self:kind() == TK.name then local t = self:text(); self.i = self.i + 1; return t end
    self:issue(msg or "expected name")
    return "<missing>"
end
function Parser:issue(msg)
    local Pm = self.Pm
    self.issues[#self.issues + 1] = Pm.ParseIssue(msg, self.toks.start[self.i] or 0, self.toks.line[self.i] or 0, self.toks.col[self.i] or 0)
end

function Parser:type_name(name)
    local C, Ty = self.C, self.Ty
    local scalars = {
        void = C.ScalarVoid, bool = C.ScalarBool,
        i8 = C.ScalarI8, i16 = C.ScalarI16, i32 = C.ScalarI32, i64 = C.ScalarI64,
        u8 = C.ScalarU8, u16 = C.ScalarU16, u32 = C.ScalarU32, u64 = C.ScalarU64,
        f32 = C.ScalarF32, f64 = C.ScalarF64, index = C.ScalarIndex,
    }
    if scalars[name] then return Ty.TScalar(scalars[name]) end
    return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) })))
end

function Parser:parse_type()
    local Ty, C = self.Ty, self.C
    self:skip_nl()
    if self:kind() == TK.name then
        local name = self:text(); self.i = self.i + 1
        if (name == "ptr" or name == "view") and self:accept(TK.lparen) then
            local elem = self:parse_type(); self:skip_nl(); self:expect(TK.rparen)
            return name == "ptr" and Ty.TPtr(elem) or Ty.TView(elem)
        end
        return self:type_name(name)
    end
    if self:accept(TK.view_kw) then
        self:expect(TK.lparen); local elem = self:parse_type(); self:skip_nl(); self:expect(TK.rparen)
        return Ty.TView(elem)
    end
    if self:accept(TK.func_kw) then
        self:expect(TK.lparen)
        local params = {}
        self:skip_nl()
        if self:kind() ~= TK.rparen then
            while true do
                params[#params + 1] = self:parse_type()
                self:skip_nl()
                if not self:accept(TK.comma) then break end
                self:skip_nl()
                if self:kind() == TK.rparen then break end
            end
        end
        self:expect(TK.rparen)
        local result = Ty.TScalar(C.ScalarVoid)
        self:skip_nl()
        if self:accept(TK.arrow) then result = self:parse_type() end
        return Ty.TFunc(params, result)
    end
    self:issue("expected type")
    return Ty.TScalar(C.ScalarVoid)
end

function Parser:parse_expr(rbp)
    self:skip_nl()
    local left = self:nud()
    self:skip_nl()
    while rbp < (lbp[self:kind()] or 0) do
        local k = self:kind(); self.i = self.i + 1
        left = self:led(k, left)
        self:skip_nl()
    end
    return left
end

function Parser:nud()
    local C, B, Tr = self.C, self.B, self.Tr
    local k, text = self:kind(), self:text()
    self.i = self.i + 1
    if k == TK.int then return Tr.ExprLit(Tr.ExprSurface, C.LitInt(text)) end
    if k == TK.float then return Tr.ExprLit(Tr.ExprSurface, C.LitFloat(text)) end
    if k == TK.string then return Tr.ExprLit(Tr.ExprSurface, C.LitString(text)) end
    if k == TK.true_kw then return Tr.ExprLit(Tr.ExprSurface, C.LitBool(true)) end
    if k == TK.false_kw then return Tr.ExprLit(Tr.ExprSurface, C.LitBool(false)) end
    if k == TK.nil_kw then return Tr.ExprLit(Tr.ExprSurface, C.LitNil) end
    if k == TK.name then return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(text)) end
    if k == TK.lparen then local e = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen); return e end
    if k == TK.minus then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNeg, self:parse_expr(80)) end
    if k == TK.not_kw then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryNot, self:parse_expr(80)) end
    if k == TK.tilde then return Tr.ExprUnary(Tr.ExprSurface, C.UnaryBitNot, self:parse_expr(80)) end
    if k == TK.star then return Tr.ExprDeref(Tr.ExprSurface, self:parse_expr(80)) end
    if k == TK.amp then return Tr.ExprAddrOf(Tr.ExprSurface, self:expr_to_place(self:parse_expr(80))) end
    if k == TK.as_kw then
        self:expect(TK.lparen); local ty = self:parse_type(); self:skip_nl(); self:expect(TK.comma)
        local v = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen)
        return Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, ty, v)
    end
    if k == TK.view_kw then
        self:expect(TK.lparen); local data = self:parse_expr(0); self:skip_nl(); self:expect(TK.comma)
        local len = self:parse_expr(0); self:skip_nl()
        if self:accept(TK.comma) then local stride = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen); return Tr.ExprView(Tr.ExprSurface, Tr.ViewStrided(data, self.Ty.TScalar(C.ScalarVoid), len, stride)) end
        self:expect(TK.rparen); return Tr.ExprView(Tr.ExprSurface, Tr.ViewContiguous(data, self.Ty.TScalar(C.ScalarVoid), len))
    end
    if k == TK.len_kw then
        if self:accept(TK.lparen) then local v = self:parse_expr(0); self:skip_nl(); self:expect(TK.rparen); return Tr.ExprLen(Tr.ExprSurface, v) end
        return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("len"))
    end
    if k == TK.block_kw then return self:parse_control_expr_after_block() end
    self:issue("expected expression")
    return Tr.ExprLit(Tr.ExprSurface, C.LitInt("0"))
end

function Parser:led(k, left)
    local C, B, Tr, Sem = self.C, self.B, self.Tr, self.Sem
    if k == TK.lparen then
        local args = {}
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
        self:expect(TK.rparen)
        local pvm = require("moonlift.pvm")
        if pvm.classof(left) == Tr.ExprRef and pvm.classof(left.ref) == B.ValueRefName and left.ref.name == "select" and #args == 3 then
            return Tr.ExprSelect(Tr.ExprSurface, args[1], args[2], args[3])
        end
        return Tr.ExprCall(Tr.ExprSurface, Sem.CallUnresolved(left), args)
    end
    if k == TK.lbrack then local idx = self:parse_expr(0); self:skip_nl(); self:expect(TK.rbrack); return Tr.ExprIndex(Tr.ExprSurface, Tr.IndexBaseExpr(left), idx) end
    if k == TK.dot then local name = self:expect_name("expected field name"); return Tr.ExprDot(Tr.ExprSurface, left, name) end
    local bin = { [TK.plus]=C.BinAdd, [TK.minus]=C.BinSub, [TK.star]=C.BinMul, [TK.slash]=C.BinDiv, [TK.percent]=C.BinRem, [TK.amp]=C.BinBitAnd, [TK.pipe]=C.BinBitOr, [TK.caret]=C.BinBitXor, [TK.shl]=C.BinShl, [TK.lshr]=C.BinLShr, [TK.ashr]=C.BinAShr }
    local cmp = { [TK.eqeq]=C.CmpEq, [TK.ne]=C.CmpNe, [TK.lt]=C.CmpLt, [TK.le]=C.CmpLe, [TK.gt]=C.CmpGt, [TK.ge]=C.CmpGe }
    if bin[k] then return Tr.ExprBinary(Tr.ExprSurface, bin[k], left, self:parse_expr(lbp[k])) end
    if cmp[k] then return Tr.ExprCompare(Tr.ExprSurface, cmp[k], left, self:parse_expr(lbp[k])) end
    if k == TK.and_kw then return Tr.ExprLogic(Tr.ExprSurface, C.LogicAnd, left, self:parse_expr(lbp[k])) end
    if k == TK.or_kw then return Tr.ExprLogic(Tr.ExprSurface, C.LogicOr, left, self:parse_expr(lbp[k])) end
    self:issue("unknown infix operator")
    return left
end

function Parser:expr_to_place(e)
    local pvm = require("moonlift.pvm")
    local Tr, B = self.Tr, self.B
    local cls = pvm.classof(e)
    if cls == Tr.ExprRef then return Tr.PlaceRef(Tr.PlaceSurface, e.ref) end
    if cls == Tr.ExprDeref then return Tr.PlaceDeref(Tr.PlaceSurface, e.value) end
    if cls == Tr.ExprDot then return Tr.PlaceDot(Tr.PlaceSurface, self:expr_to_place(e.base), e.name) end
    if cls == Tr.ExprIndex then return Tr.PlaceIndex(Tr.PlaceSurface, Tr.IndexBaseExpr(e.base.base), e.index) end
    self:issue("expression is not assignable")
    return Tr.PlaceRef(Tr.PlaceSurface, B.ValueRefName("<bad-place>"))
end

function Parser:parse_jump_args()
    local Tr = self.Tr
    local args = {}
    self:expect(TK.lparen)
    self:skip_nl()
    if self:kind() ~= TK.rparen then
        while true do
            local name = self:expect_name("expected jump argument name")
            self:expect(TK.eq)
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
    self:expect(TK.lparen); self:skip_nl()
    if self:kind() ~= TK.rparen then
        while true do
            local name = self:expect_name("expected block parameter")
            self:expect(TK.colon); local ty = self:parse_type(); self:skip_nl()
            if entry then self:expect(TK.eq); params[#params + 1] = Tr.EntryBlockParam(name, ty, self:parse_expr(0))
            else params[#params + 1] = Tr.BlockParam(name, ty) end
            self:skip_nl(); if not self:accept(TK.comma) then break end; self:skip_nl(); if self:kind() == TK.rparen then break end
        end
    end
    self:expect(TK.rparen)
    return params
end

function Parser:parse_control_expr_after_block()
    local Tr = self.Tr
    local label = Tr.BlockLabel(self:expect_name("expected block label"))
    local params = self:parse_block_params(true)
    self:skip_nl(); self:expect(TK.arrow); local result_ty = self:parse_type(); self:skip_nl()
    local body = self:parse_stmt_until({ [TK.end_kw] = true })
    self:expect(TK.end_kw)
    self.control_seq = self.control_seq + 1
    local region = Tr.ControlExprRegion("native.expr." .. tostring(self.control_seq), result_ty, Tr.EntryControlBlock(label, params, body), {})
    return Tr.ExprControl(Tr.ExprSurface, region)
end

function Parser:parse_stmt_until(stops)
    local out = {}
    self:skip_sep()
    while not stops[self:kind()] and self:kind() ~= TK.eof do
        out[#out + 1] = self:parse_stmt()
        self:skip_sep()
    end
    return out
end

function Parser:parse_if_stmt()
    local Tr = self.Tr
    local cond = self:parse_expr(0); self:skip_nl(); self:expect(TK.then_kw)
    local then_body = self:parse_stmt_until({ [TK.else_kw]=true, [TK.elseif_kw]=true, [TK.end_kw]=true })
    local else_body = {}
    if self:accept(TK.elseif_kw) then else_body = { self:parse_if_stmt() }
    elseif self:accept(TK.else_kw) then else_body = self:parse_stmt_until({ [TK.end_kw]=true }) end
    self:expect(TK.end_kw)
    return Tr.StmtIf(Tr.StmtSurface, cond, then_body, else_body)
end

function Parser:parse_stmt_control_after_block()
    local Tr = self.Tr
    local label = Tr.BlockLabel(self:expect_name("expected block label"))
    local params = self:parse_block_params(true)
    local body = self:parse_stmt_until({ [TK.end_kw] = true })
    self:expect(TK.end_kw)
    self.control_seq = self.control_seq + 1
    local region = Tr.ControlStmtRegion("native.stmt." .. tostring(self.control_seq), Tr.EntryControlBlock(label, params, body), {})
    return Tr.StmtControl(Tr.StmtSurface, region)
end

function Parser:parse_stmt()
    local Tr, B, C = self.Tr, self.B, self.C
    self:skip_nl()
    if self:accept(TK.let_kw) or self:accept(TK.var_kw) then
        local is_var = self.toks.kind[self.i - 1] == TK.var_kw
        local name = self:expect_name(); local ty = self.Ty.TScalar(C.ScalarVoid)
        if self:accept(TK.colon) then ty = self:parse_type() end
        self:skip_nl(); self:expect(TK.eq); local init = self:parse_expr(0)
        local binding = B.Binding(C.Id("local:" .. name), name, ty, is_var and B.BindingClassLocalCell or B.BindingClassLocalValue)
        return is_var and Tr.StmtVar(Tr.StmtSurface, binding, init) or Tr.StmtLet(Tr.StmtSurface, binding, init)
    end
    if self:accept(TK.if_kw) then return self:parse_if_stmt() end
    if self:accept(TK.return_kw) then if self:kind() == TK.nl or self:kind() == TK.end_kw then return Tr.StmtReturnVoid(Tr.StmtSurface) end; return Tr.StmtReturnValue(Tr.StmtSurface, self:parse_expr(0)) end
    if self:accept(TK.yield_kw) then if self:kind() == TK.nl or self:kind() == TK.end_kw then return Tr.StmtYieldVoid(Tr.StmtSurface) end; return Tr.StmtYieldValue(Tr.StmtSurface, self:parse_expr(0)) end
    if self:accept(TK.jump_kw) then local name = self:expect_name(); return Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel(name), self:parse_jump_args()) end
    if self:accept(TK.block_kw) then return self:parse_stmt_control_after_block() end
    local e = self:parse_expr(0)
    if self:accept(TK.eq) then return Tr.StmtSet(Tr.StmtSurface, self:expr_to_place(e), self:parse_expr(0)) end
    return Tr.StmtExpr(Tr.StmtSurface, e)
end

function Parser:parse_param_list()
    local Ty = self.Ty
    local params = {}
    self:expect(TK.lparen); self:skip_nl()
    if self:kind() ~= TK.rparen then
        while true do
            local name = self:expect_name("expected parameter name")
            self:expect(TK.colon); params[#params + 1] = Ty.Param(name, self:parse_type())
            self:skip_nl(); if not self:accept(TK.comma) then break end; self:skip_nl(); if self:kind() == TK.rparen then break end
        end
    end
    self:expect(TK.rparen)
    return params
end

function Parser:parse_func()
    local Tr, Ty, C = self.Tr, self.Ty, self.C
    self:expect(TK.func_kw)
    local name = self:expect_name("expected function name")
    local params = self:parse_param_list()
    local result = Ty.TScalar(C.ScalarVoid)
    self:skip_nl(); if self:accept(TK.arrow) then result = self:parse_type() end
    local body = self:parse_stmt_until({ [TK.end_kw] = true })
    self:expect(TK.end_kw)
    return Tr.FuncExport(name, params, result, body)
end

function Parser:parse_extern()
    local Tr, Ty, C = self.Tr, self.Ty, self.C
    self:expect(TK.extern_kw)
    local name = self:expect_name("expected extern name")
    local params = self:parse_param_list()
    local result = Ty.TScalar(C.ScalarVoid)
    self:skip_nl(); if self:accept(TK.arrow) then result = self:parse_type() end
    local symbol = name
    if self:accept(TK.as_kw) then symbol = self:expect(TK.string, "expected extern symbol string"):gsub('^([\"\'])(.*)%1$', '%2') end
    self:skip_nl(); self:expect(TK.end_kw)
    return Tr.ExternFunc(name, symbol, params, result)
end

function Parser:parse_struct()
    local Tr, Ty = self.Tr, self.Ty
    self:expect(TK.struct_kw); local name = self:expect_name("expected struct name")
    local fields = {}; self:skip_sep()
    while self:kind() ~= TK.end_kw and self:kind() ~= TK.eof do
        local fname = self:expect_name("expected field name"); self:expect(TK.colon)
        fields[#fields + 1] = Ty.FieldDecl(fname, self:parse_type())
        self:skip_sep(); self:accept(TK.comma); self:skip_sep()
    end
    self:expect(TK.end_kw)
    return Tr.TypeDeclStruct(name, fields)
end

function Parser:parse_union()
    local Tr, Ty, C = self.Tr, self.Ty, self.C
    self:expect(TK.union_kw); local name = self:expect_name("expected union name")
    local variants = {}; self:skip_sep()
    while self:kind() ~= TK.end_kw and self:kind() ~= TK.eof do
        if self:accept(TK.pipe) then self:skip_sep() end
        local vname = self:expect_name("expected variant name")
        local payload = Ty.TScalar(C.ScalarVoid); local fields = {}
        if self:accept(TK.lparen) then
            self:skip_nl()
            if self:kind() ~= TK.rparen then payload = self:parse_type() end
            self:expect(TK.rparen)
        end
        variants[#variants + 1] = Ty.VariantDecl(vname, payload, fields)
        self:skip_sep(); if not self:accept(TK.pipe) then self:skip_sep() else self.i = self.i - 1 end
    end
    self:expect(TK.end_kw)
    return Tr.TypeDeclTaggedUnionSugar(name, variants)
end

function Parser:parse_module()
    local Tr = self.Tr
    local items = {}
    self:skip_sep()
    while self:kind() ~= TK.eof do
        local k = self:kind()
        if k == TK.func_kw then items[#items + 1] = Tr.ItemFunc(self:parse_func())
        elseif k == TK.extern_kw then items[#items + 1] = Tr.ItemExtern(self:parse_extern())
        elseif k == TK.struct_kw then items[#items + 1] = Tr.ItemType(self:parse_struct())
        elseif k == TK.union_kw then items[#items + 1] = Tr.ItemType(self:parse_union())
        else self:issue("expected top-level declaration"); self.i = self.i + 1 end
        self:skip_sep()
    end
    return Tr.Module(Tr.ModuleSurface, items)
end

function M.Define(T)
    local api = {}
    function api.lex(src) return M.lex(src) end
    function api.parse_module(src)
        local toks = M.lex(src)
        local p = setmetatable({ T = T, C = T.MoonCore, Ty = T.MoonType, B = T.MoonBind, Sem = T.MoonSem, Tr = T.MoonTree, Pm = T.MoonParse, toks = toks, i = 1, issues = {}, control_seq = 0 }, Parser)
        local module = p:parse_module()
        return { kind = "module", module = module, issues = p.issues, tokens = toks }
    end
    return api
end

return M
