-- Lua Interpreter VM — semantic phase: verified parse products -> HIR.
--
-- This phase does not call the lexer or codegen. It walks parse products and
-- constructs function-centric HIR/binding products with explicit vectors. The
-- parser currently supplies a typed token/source product tape; this phase owns
-- grammar validation, local binding, and expression precedence reduction into
-- HIR.

local moon = require("moonlift")
local host = require("moonlift.host")
local pconst = require("experiments.lua_interpreter_vm.src.parser_constants")
local parser = require("experiments.lua_interpreter_vm.src.regions_parser")

local V = {
    source_error_at_span = parser.source_error_at_span,
    source_error_at_current = parser.source_error_at_current,
}
for k, v in pairs(pconst.Tok) do V["TOK_" .. k] = moon.int(v) end
for k, v in pairs(pconst.Kw) do V["KW_" .. k] = moon.int(v) end
for k, v in pairs(pconst.ParseErr) do V["PERR_" .. k] = moon.int(v) end
for k, v in pairs(pconst.SourcePhase) do V["SOURCE_" .. k] = moon.int(v) end
for k, v in pairs(pconst.HirStmtKind) do V["HSTMT_" .. k] = moon.int(v) end
for k, v in pairs(pconst.HirExprKind) do V["HEXPR_" .. k] = moon.int(v) end
for k, v in pairs(pconst.SymbolKind) do V["SYM_" .. k] = moon.int(v) end

local append_scope = host.region(V) [[
region append_scope(cu: ptr(CompileUnit), scope: ScopeRec;
                    ok(ref: index) | oom)
entry start()
    if cu.scopes.data == nil then jump oom() end
    let ref: index = cu.scopes.len + 1
    if ref >= cu.scopes.cap then jump oom() end
    cu.scopes.data[ref] = scope
    cu.scopes.len = ref
    jump ok(ref = ref)
end
end
]]

local append_symbol = host.region(V) [[
region append_symbol(cu: ptr(CompileUnit), sym: SymbolRec;
                     ok(ref: index) | oom)
entry start()
    if cu.symbols.data == nil then jump oom() end
    let ref: index = cu.symbols.len + 1
    if ref >= cu.symbols.cap then jump oom() end
    cu.symbols.data[ref] = sym
    cu.symbols.len = ref
    jump ok(ref = ref)
end
end
]]

local append_capture = host.region(V) [[
region append_capture(cu: ptr(CompileUnit), cap: CaptureRec;
                      ok(ref: index) | oom)
entry start()
    if cu.captures.data == nil then jump oom() end
    let ref: index = cu.captures.len + 1
    if ref >= cu.captures.cap then jump oom() end
    cu.captures.data[ref] = cap
    cu.captures.len = ref
    jump ok(ref = ref)
end
end
]]

local append_name_use = host.region(V) [[
region append_name_use(cu: ptr(CompileUnit), use: NameUse;
                       ok(ref: index) | oom)
entry start()
    if cu.name_uses.data == nil then jump oom() end
    let ref: index = cu.name_uses.len + 1
    if ref >= cu.name_uses.cap then jump oom() end
    cu.name_uses.data[ref] = use
    cu.name_uses.len = ref
    jump ok(ref = ref)
end
end
]]

local append_hir_function = host.region(V) [[
region append_hir_function(cu: ptr(CompileUnit), fn: HirFunction;
                           ok(ref: index) | oom)
entry start()
    if cu.hir_functions.data == nil then jump oom() end
    let ref: index = cu.hir_functions.len + 1
    if ref >= cu.hir_functions.cap then jump oom() end
    cu.hir_functions.data[ref] = fn
    cu.hir_functions.len = ref
    jump ok(ref = ref)
end
end
]]

local append_hir_block = host.region(V) [[
region append_hir_block(cu: ptr(CompileUnit), block_rec: HirBlock;
                        ok(ref: index) | oom)
entry start()
    if cu.hir_blocks.data == nil then jump oom() end
    let ref: index = cu.hir_blocks.len + 1
    if ref >= cu.hir_blocks.cap then jump oom() end
    cu.hir_blocks.data[ref] = block_rec
    cu.hir_blocks.len = ref
    jump ok(ref = ref)
end
end
]]

local append_hir_stmt = host.region(V) [[
region append_hir_stmt(cu: ptr(CompileUnit), stmt: HirStmt;
                       ok(ref: index) | oom)
entry start()
    if cu.hir_stmts.data == nil then jump oom() end
    let ref: index = cu.hir_stmts.len + 1
    if ref >= cu.hir_stmts.cap then jump oom() end
    cu.hir_stmts.data[ref] = stmt
    cu.hir_stmts.len = ref
    jump ok(ref = ref)
end
end
]]

local append_hir_expr = host.region(V) [[
region append_hir_expr(cu: ptr(CompileUnit), expr_rec: HirExpr;
                       ok(ref: index) | oom)
entry start()
    if cu.hir_exprs.data == nil then jump oom() end
    let ref: index = cu.hir_exprs.len + 1
    if ref >= cu.hir_exprs.cap then jump oom() end
    cu.hir_exprs.data[ref] = expr_rec
    cu.hir_exprs.len = ref
    jump ok(ref = ref)
end
end
]]

local push_semantic_frame = host.region(V) [[
region push_semantic_frame(cu: ptr(CompileUnit), frame: SemanticFrame;
                           ok | limit_error(err: CompileError) | oom)
entry start()
    if cu.semantic_frames.data == nil then jump out_of_mem() end
    let slot: index = cu.semantic_frames.len + 1
    if slot >= cu.semantic_frames.cap then
        emit @{source_error_at_span}(cu, @{PERR_INTERNAL_PHASE_ERROR}, as(u16, 0), frame.span; error = too_big)
    end
    cu.semantic_frames.data[slot] = frame
    cu.semantic_frames.len = slot
    jump ok()
end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local pop_semantic_frame = host.region(V) [[
region pop_semantic_frame(cu: ptr(CompileUnit);
                          popped(frame: SemanticFrame) | semantic_error(err: CompileError))
entry start()
    if cu.semantic_frames.len == 0 then
        emit @{source_error_at_current}(cu, @{PERR_INTERNAL_PHASE_ERROR}; error = bad)
    end
    let slot: index = cu.semantic_frames.len
    let frame: SemanticFrame = cu.semantic_frames.data[slot]
    cu.semantic_frames.len = slot - 1
    jump popped(frame = frame)
end
block bad(err: CompileError) jump semantic_error(err = err) end
end
]]

local token_node_at = host.region(V) [[
region token_node_at(cu: ptr(CompileUnit), slot: index;
                     ok(node: ParseNode) | eof | semantic_error(err: CompileError))
entry start()
    cu.semantic_mark = slot
    if slot > cu.parse_children.len then jump eof() end
    let ref: index = cu.parse_children.data[slot]
    if ref == 0 then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_PARSE_PRODUCT}; error = bad) end
    if ref > cu.parse_nodes.len then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_PARSE_PRODUCT}; error = bad) end
    let node: ParseNode = cu.parse_nodes.data[ref]
    jump ok(node = node)
end
block bad(err: CompileError) jump semantic_error(err = err) end
end
]]

local is_expr_terminator = host.region(V) [[
region is_expr_terminator(kind: u16; yes | no)

entry start()
    if kind == @{TOK_EOF} then jump yes() end
    if kind == @{TOK_SEMI} then jump yes() end
    if kind == @{TOK_COMMA} then jump yes() end
    if kind == @{KW_END} then jump yes() end
    if kind == @{KW_ELSE} then jump yes() end
    if kind == @{KW_ELSEIF} then jump yes() end
    if kind == @{KW_UNTIL} then jump yes() end
    if kind == @{KW_THEN} then jump yes() end
    if kind == @{KW_DO} then jump yes() end
    jump no()
end
end
]]

local binary_precedence = host.region(V) [[
region binary_precedence(kind: u16; op(prec: u8) | not_op)

entry start()
    if kind == @{TOK_EQ} or kind == @{TOK_NE} or kind == @{TOK_LT} or kind == @{TOK_LE} or kind == @{TOK_GT} or kind == @{TOK_GE} then jump op(prec = as(u8, 3)) end
    if kind == @{TOK_PIPE} then jump op(prec = as(u8, 4)) end
    if kind == @{TOK_TILDE} then jump op(prec = as(u8, 5)) end
    if kind == @{TOK_AMP} then jump op(prec = as(u8, 6)) end
    if kind == @{TOK_LTLT} or kind == @{TOK_GTGT} then jump op(prec = as(u8, 7)) end
    if kind == @{TOK_PLUS} then jump op(prec = as(u8, 8)) end
    if kind == @{TOK_MINUS} then jump op(prec = as(u8, 8)) end
    if kind == @{TOK_STAR} then jump op(prec = as(u8, 9)) end
    if kind == @{TOK_SLASH} then jump op(prec = as(u8, 9)) end
    if kind == @{TOK_PERCENT} then jump op(prec = as(u8, 9)) end
    if kind == @{TOK_SLASHSLASH} then jump op(prec = as(u8, 9)) end
    if kind == @{TOK_CARET} then jump op(prec = as(u8, 10)) end
    jump not_op()
end
end
]]

local sem_push_op = host.region(V) [[
region sem_push_op(cu: ptr(CompileUnit), op: ExprOpEntry;
                   ok | limit_error(err: CompileError) | oom)
entry start()
    if cu.expr_ops.data == nil then jump out_of_mem() end
    let slot: index = cu.expr_ops.len + 1
    if slot >= cu.expr_ops.cap then
        emit @{source_error_at_span}(cu, @{PERR_EXPR_STACK_OVERFLOW}, op.op, op.span; error = too_big)
    end
    cu.expr_ops.data[slot] = op
    cu.expr_ops.len = slot
    jump ok()
end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local sem_push_val = host.region(V) [[
region sem_push_val(cu: ptr(CompileUnit), ref: index, span: SourceSpan;
                    ok | limit_error(err: CompileError) | oom)
entry start()
    if cu.expr_vals.data == nil then jump out_of_mem() end
    let slot: index = cu.expr_vals.len + 1
    if slot >= cu.expr_vals.cap then
        emit @{source_error_at_span}(cu, @{PERR_EXPR_STACK_OVERFLOW}, as(u16, 0), span; error = too_big)
    end
    cu.expr_vals.data[slot] = { node = ref, span = span }
    cu.expr_vals.len = slot
    jump ok()
end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local current_semantic_function = host.region(V) [[
region current_semantic_function(cu: ptr(CompileUnit); ok(function_ref: index))

entry start()
    if cu.semantic_frames.len == 0 then jump ok(function_ref = cu.root_hir_function) end
    let frame: SemanticFrame = cu.semantic_frames.data[cu.semantic_frames.len]
    jump ok(function_ref = frame.function_ref)
end
end
]]

local find_capture_for_symbol = host.region(V) [[
region find_capture_for_symbol(cu: ptr(CompileUnit), function_ref: index, symbol_ref: index;
                               found(ref: index) | missing)
entry start()
    let fn: HirFunction = cu.hir_functions.data[function_ref]
    if fn.captures_len == 0 then jump missing() end
    jump scan(i = as(index, 0), first = fn.captures_first, n = fn.captures_len)
end
block scan(i: index, first: index, n: index)
    if i >= n then jump missing() end
    let ref: index = first + i
    let cap: CaptureRec = cu.captures.data[ref]
    if cap.symbol == symbol_ref then jump found(ref = ref) end
    jump scan(i = i + 1, first = first, n = n)
end
end
]]

local ensure_capture_for_symbol = host.region(V) [[
region ensure_capture_for_symbol(cu: ptr(CompileUnit), function_ref: index, symbol_ref: index;
                                 ok(ref: index) | oom)
entry start()
    emit find_capture_for_symbol(cu, function_ref, symbol_ref; found = already, missing = make_new)
end
block already(ref: index) jump ok(ref = ref) end
block make_new()
    let fn: HirFunction = cu.hir_functions.data[function_ref]
    let sym: SymbolRec = cu.symbols.data[symbol_ref]
    let first: index = cu.captures.len + 1
    if fn.captures_len ~= 0 then first = fn.captures_first end
    let idx: u16 = as(u16, fn.captures_len)
    let cap: CaptureRec = { symbol = symbol_ref, source_function = sym.owner_function, through_parent = 0, reserved = 0, upvalue_index = idx, span = sym.span }
    emit append_capture(cu, cap; ok = made, oom = out_of_mem)
end
block made(ref: index)
    let cap: CaptureRec = cu.captures.data[ref]
    let function_ref: index = cu.semantic_frames.data[cu.semantic_frames.len].function_ref
    if cu.hir_functions.data[function_ref].captures_len == 0 then cu.hir_functions.data[function_ref].captures_first = ref end
    cu.hir_functions.data[function_ref].captures_len = cu.hir_functions.data[function_ref].captures_len + 1
    jump ok(ref = ref)
end
block out_of_mem() jump oom() end
end
]]

local resolve_name_symbol = host.region(V) [[
region resolve_name_symbol(cu: ptr(CompileUnit), name_node: ParseNode;
                           local_found(ref: index) | upvalue_found(ref: index) | missing | oom)
entry start()
    emit current_semantic_function(cu; ok = got_function)
end
block got_function(function_ref: index)
    if cu.symbols.len == 0 then jump missing() end
    jump scan(i = cu.symbols.len + 1, function_ref = function_ref)
end
block scan(i: index, function_ref: index)
    if i <= 1 then jump missing() end
    let j: index = i - 1
    let sym: SymbolRec = cu.symbols.data[j]
    if sym.name_len == name_node.b then jump compare(idx = j, off = as(index, 0), function_ref = function_ref) end
    jump scan(i = j, function_ref = function_ref)
end
block compare(idx: index, off: index, function_ref: index)
    let sym: SymbolRec = cu.symbols.data[idx]
    if off >= name_node.b then jump matched(idx = idx, function_ref = function_ref) end
    if cu.lexer.src.bytes[sym.name_start + off] ~= cu.lexer.src.bytes[name_node.a + off] then jump scan(i = idx, function_ref = function_ref) end
    jump compare(idx = idx, off = off + 1, function_ref = function_ref)
end
block matched(idx: index, function_ref: index)
    let sym: SymbolRec = cu.symbols.data[idx]
    if sym.owner_function == function_ref then jump local_found(ref = idx) end
    if function_ref == cu.root_hir_function then jump missing() end
    emit ensure_capture_for_symbol(cu, function_ref, idx; ok = captured, oom = out_of_mem)
end
block captured(ref: index) jump upvalue_found(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local add_symbol_to_function_from_node = host.region(V) [[
region add_symbol_to_function_from_node(cu: ptr(CompileUnit), name_node: ParseNode, scope_ref: index, owner_function: index, kind: u16;
                                        ok(ref: index) | semantic_error(err: CompileError) | oom)
entry start()
    if owner_function == 0 or owner_function > cu.hir_functions.len then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, name_node.token, name_node.span; error = sem_bad) end
    let fn: HirFunction = cu.hir_functions.data[owner_function]
    let local_reg: u16 = as(u16, fn.symbols_len)
    let sym: SymbolRec = { kind = kind, flags = 0, owner_function = owner_function, scope = scope_ref, name_start = name_node.a, name_len = name_node.b, local_index = local_reg, upvalue_index = 0, span = name_node.span }
    emit append_symbol(cu, sym; ok = made, oom = out_of_mem)
end
block made(ref: index)
    let owner_function: index = cu.symbols.data[ref].owner_function
    if cu.hir_functions.data[owner_function].symbols_len == 0 then cu.hir_functions.data[owner_function].symbols_first = ref end
    cu.hir_functions.data[owner_function].symbols_len = cu.hir_functions.data[owner_function].symbols_len + 1
    if cu.scopes.len > 0 then cu.scopes.data[cu.symbols.data[ref].scope].symbol_len = cu.scopes.data[cu.symbols.data[ref].scope].symbol_len + 1 end
    jump ok(ref = ref)
end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local add_local_symbol_from_node = host.region(V) [[
region add_local_symbol_from_node(cu: ptr(CompileUnit), name_node: ParseNode, scope_ref: index;
                                  ok(ref: index) | semantic_error(err: CompileError) | oom)
entry start()
    emit current_semantic_function(cu; ok = got_function)
end
block got_function(function_ref: index)
    let body: index = cu.hir_functions.data[function_ref].body
    let actual_scope: index = cu.hir_blocks.data[body].scope
    emit add_symbol_to_function_from_node(cu, name_node, actual_scope, function_ref, as(u16, @{SYM_LOCAL}); ok = made, semantic_error = sem_bad, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local append_integer_expr = host.region(V) [[
region append_integer_expr(cu: ptr(CompileUnit), node: ParseNode;
                           ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_INTEGER}), op = 0, flags = 0, reserved = 0, a = 0, b = 0, c = 0, next = 0, value = { tag = 0, aux = 0, bits = as(u64, node.c) }, span = node.span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_bool_expr = host.region(V) [[
region append_bool_expr(cu: ptr(CompileUnit), node: ParseNode, bit: index;
                        ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_BOOL}), op = 0, flags = 0, reserved = 0, a = bit, b = 0, c = 0, next = 0, value = { tag = 0, aux = 0, bits = as(u64, bit) }, span = node.span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_nil_expr = host.region(V) [[
region append_nil_expr(cu: ptr(CompileUnit), node: ParseNode;
                       ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_NIL}), op = 0, flags = 0, reserved = 0, a = 0, b = 0, c = 0, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = node.span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_string_expr = host.region(V) [[
region append_string_expr(cu: ptr(CompileUnit), node: ParseNode;
                          ok(ref: index) | oom)
entry start()
    -- String lowering needs durable string/constant storage. HIR records the
    -- stable source slice now; regions_lower rejects it until that storage
    -- boundary exists.
    let e: HirExpr = { kind = as(u16, @{HEXPR_STRING}), op = 0, flags = 0, reserved = 0, a = node.a, b = node.b, c = 0, next = 0, value = { tag = 0, aux = 0, bits = as(u64, node.a) }, span = node.span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_integer_const = host.region(V) [[
region append_integer_const(cu: ptr(CompileUnit), span: SourceSpan, value: i64;
                            ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_INTEGER}), op = 0, flags = 0, reserved = 0, a = 0, b = 0, c = 0, next = 0, value = { tag = 0, aux = 0, bits = as(u64, value) }, span = span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_local_expr = host.region(V) [[
region append_local_expr(cu: ptr(CompileUnit), node: ParseNode, sym_ref: index;
                         ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_LOCAL}), op = 0, flags = 0, reserved = 0, a = sym_ref, b = 0, c = 0, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = node.span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_global_expr = host.region(V) [[
region append_global_expr(cu: ptr(CompileUnit), node: ParseNode;
                          ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_GLOBAL}), op = 0, flags = 0, reserved = 0, a = node.a, b = node.b, c = 0, next = 0, value = { tag = 0, aux = 0, bits = as(u64, node.c) }, span = node.span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_upvalue_expr = host.region(V) [[
region append_upvalue_expr(cu: ptr(CompileUnit), node: ParseNode, capture_ref: index;
                           ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_UPVALUE}), op = 0, flags = 0, reserved = 0, a = capture_ref, b = 0, c = 0, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = node.span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_closure_expr = host.region(V) [[
region append_closure_expr(cu: ptr(CompileUnit), function_ref: index, span: SourceSpan;
                           ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_CLOSURE}), op = 0, flags = 0, reserved = 0, a = function_ref, b = 0, c = 0, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_vararg_expr = host.region(V) [[
region append_vararg_expr(cu: ptr(CompileUnit), node: ParseNode;
                          ok(ref: index) | semantic_error(err: CompileError) | oom)
entry start()
    emit current_semantic_function(cu; ok = got_function)
end
block got_function(function_ref: index)
    if cu.hir_functions.data[function_ref].is_vararg == 0 then emit @{source_error_at_span}(cu, @{PERR_VARARG_OUTSIDE_VARARG}, node.token, node.span; error = sem_bad) end
    let e: HirExpr = { kind = as(u16, @{HEXPR_VARARG}), op = 0, flags = 0, reserved = 0, a = 0, b = 0, c = 0, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = node.span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local append_table_expr = host.region(V) [[
region append_table_expr(cu: ptr(CompileUnit), first_item: index, count: index, span: SourceSpan;
                         ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_TABLE}), op = 0, flags = 0, reserved = 0, a = first_item, b = count, c = 0, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_table_item_expr = host.region(V) [[
region append_table_item_expr(cu: ptr(CompileUnit), key_ref: index, value_ref: index, array_index: index, is_array: u16, span: SourceSpan;
                              ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_TABLE_ITEM}), op = 0, flags = is_array, reserved = 0, a = key_ref, b = value_ref, c = array_index, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_index_expr = host.region(V) [[
region append_index_expr(cu: ptr(CompileUnit), table_ref: index, key_ref: index, span: SourceSpan;
                         ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_INDEX}), op = 0, flags = 0, reserved = 0, a = table_ref, b = key_ref, c = 0, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_field_expr = host.region(V) [[
region append_field_expr(cu: ptr(CompileUnit), table_ref: index, name_node: ParseNode, span: SourceSpan;
                         ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_FIELD}), op = 0, flags = 0, reserved = 0, a = table_ref, b = name_node.a, c = name_node.b, next = 0, value = { tag = 0, aux = 0, bits = as(u64, name_node.c) }, span = span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_call_expr = host.region(V) [[
region append_call_expr(cu: ptr(CompileUnit), callee_ref: index, first_arg: index, argc: index, span: SourceSpan;
                        ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_CALL}), op = 0, flags = 0, reserved = 0, a = callee_ref, b = first_arg, c = argc, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_method_call_expr = host.region(V) [[
region append_method_call_expr(cu: ptr(CompileUnit), receiver_ref: index, name_node: ParseNode, first_arg: index, argc: index, span: SourceSpan;
                               ok(ref: index) | oom)
entry start()
    let e: HirExpr = { kind = as(u16, @{HEXPR_METHOD_CALL}), op = 0, flags = as(u16, argc), reserved = 0, a = receiver_ref, b = name_node.a, c = name_node.b, next = first_arg, value = { tag = 0, aux = 0, bits = as(u64, name_node.c) }, span = span }
    emit append_hir_expr(cu, e; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(ref = ref) end
block out_of_mem() jump oom() end
end
]]

local append_simple_value_expr = host.region(V) [[
region append_simple_value_expr(cu: ptr(CompileUnit), slot: index;
                                ok(expr_ref: index, next_slot: index) |
                                not_simple(node: ParseNode) |
                                semantic_error(err: CompileError) |
                                oom)
entry start()
    emit token_node_at(cu, slot; ok = value_token, eof = missing_expr, semantic_error = sem_bad)
end
block missing_expr()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_EXPR}; error = sem_bad)
end
block value_token(node: ParseNode)
    if node.token == @{TOK_INT} then emit append_integer_expr(cu, node; ok = made, oom = out_of_mem) end
    if node.token == @{KW_TRUE} then emit append_bool_expr(cu, node, as(index, 1); ok = made, oom = out_of_mem) end
    if node.token == @{KW_FALSE} then emit append_bool_expr(cu, node, as(index, 0); ok = made, oom = out_of_mem) end
    if node.token == @{KW_NIL} then emit append_nil_expr(cu, node; ok = made, oom = out_of_mem) end
    if node.token == @{TOK_STRING} then emit append_string_expr(cu, node; ok = made, oom = out_of_mem) end
    if node.token == @{TOK_NAME} then emit resolve_name_symbol(cu, node; local_found = name_found, upvalue_found = name_upvalue, missing = name_missing, oom = out_of_mem) end
    if node.token == @{TOK_DOTDOTDOT} then emit append_vararg_expr(cu, node; ok = made, semantic_error = sem_bad, oom = out_of_mem) end
    jump not_simple(node = node)
end
block name_found(ref: index)
    let node_ref: index = cu.parse_children.data[cu.semantic_mark]
    let node: ParseNode = cu.parse_nodes.data[node_ref]
    emit append_local_expr(cu, node, ref; ok = made, oom = out_of_mem)
end
block name_upvalue(ref: index)
    let node_ref: index = cu.parse_children.data[cu.semantic_mark]
    let node: ParseNode = cu.parse_nodes.data[node_ref]
    emit append_upvalue_expr(cu, node, ref; ok = made, oom = out_of_mem)
end
block name_missing()
    let node_ref: index = cu.parse_children.data[cu.semantic_mark]
    let node: ParseNode = cu.parse_nodes.data[node_ref]
    emit append_global_expr(cu, node; ok = made, oom = out_of_mem)
end
block made(ref: index)
    jump ok(expr_ref = ref, next_slot = cu.semantic_mark + 1)
end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local reduce_hir_expr_once = host.region(V) [[
region reduce_hir_expr_once(cu: ptr(CompileUnit);
                            ok | semantic_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    if cu.expr_ops.len == 0 then emit @{source_error_at_current}(cu, @{PERR_EXPECTED_EXPR}; error = sem_bad) end
    let op_slot: index = cu.expr_ops.len
    let op: ExprOpEntry = cu.expr_ops.data[op_slot]
    cu.expr_ops.len = op_slot - 1
    if op.op == @{TOK_LPAREN} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_RPAREN}, op.op, op.span; error = sem_bad) end
    if op.right_assoc == 2 then jump unary(op = op) end
    jump binary(op = op)
end
block unary(op: ExprOpEntry)
    if cu.expr_vals.len == 0 then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_EXPR}, op.op, op.span; error = sem_bad) end
    let val_slot: index = cu.expr_vals.len
    let child: ExprValEntry = cu.expr_vals.data[val_slot]
    cu.expr_vals.len = val_slot - 1
    let e: HirExpr = { kind = as(u16, @{HEXPR_UNARY}), op = op.op, flags = 0, reserved = 0, a = child.node, b = 0, c = 0, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = op.span }
    emit append_hir_expr(cu, e; ok = unary_made, oom = out_of_mem)
end
block unary_made(ref: index)
    let span: SourceSpan = cu.hir_exprs.data[ref].span
    emit sem_push_val(cu, ref, span; ok = done, limit_error = too_big, oom = out_of_mem)
end
block binary(op: ExprOpEntry)
    if cu.expr_vals.len < 2 then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_EXPR}, op.op, op.span; error = sem_bad) end
    let rhs_slot: index = cu.expr_vals.len
    let rhs: ExprValEntry = cu.expr_vals.data[rhs_slot]
    let lhs_slot: index = rhs_slot - 1
    let lhs: ExprValEntry = cu.expr_vals.data[lhs_slot]
    cu.expr_vals.len = lhs_slot - 1
    let e: HirExpr = { kind = as(u16, @{HEXPR_BINARY}), op = op.op, flags = 0, reserved = 0, a = lhs.node, b = rhs.node, c = 0, next = 0, value = { tag = 0, aux = 0, bits = 0 }, span = op.span }
    emit append_hir_expr(cu, e; ok = binary_made, oom = out_of_mem)
end
block binary_made(ref: index)
    let span: SourceSpan = cu.hir_exprs.data[ref].span
    emit sem_push_val(cu, ref, span; ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local build_hir_expr = host.region(V) [[
region build_hir_expr(cu: ptr(CompileUnit), start_slot: index;
                      parsed(expr_ref: index, next_slot: index) |
                      semantic_error(err: CompileError) |
                      limit_error(err: CompileError) |
                      oom)
entry start()
    cu.expr_ops.len = 0
    cu.expr_vals.len = 0
    jump expect_value(slot = start_slot)
end
block expect_value(slot: index)
    emit token_node_at(cu, slot; ok = value_token, eof = missing_expr, semantic_error = sem_bad)
end
block missing_expr()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_EXPR}; error = sem_bad)
end
block value_token(node: ParseNode)
    if node.token == @{TOK_INT} then emit append_integer_expr(cu, node; ok = push_value, oom = out_of_mem) end
    if node.token == @{KW_TRUE} then emit append_bool_expr(cu, node, as(index, 1); ok = push_value, oom = out_of_mem) end
    if node.token == @{KW_FALSE} then emit append_bool_expr(cu, node, as(index, 0); ok = push_value, oom = out_of_mem) end
    if node.token == @{KW_NIL} then emit append_nil_expr(cu, node; ok = push_value, oom = out_of_mem) end
    if node.token == @{TOK_STRING} then emit append_string_expr(cu, node; ok = push_value, oom = out_of_mem) end
    if node.token == @{TOK_NAME} then emit resolve_name_symbol(cu, node; local_found = name_found, upvalue_found = name_upvalue, missing = name_missing, oom = out_of_mem) end
    if node.token == @{TOK_DOTDOTDOT} then emit append_vararg_expr(cu, node; ok = push_value, semantic_error = sem_bad, oom = out_of_mem) end
    if node.token == @{TOK_MINUS} or node.token == @{KW_NOT} or node.token == @{TOK_TILDE} or node.token == @{TOK_HASH} then jump unary_prefix(node = node) end
    if node.token == @{TOK_LPAREN} then jump open_paren(node = node) end
    if node.token == @{TOK_LBRACE} then jump table_begin(node = node) end
    emit @{source_error_at_span}(cu, @{PERR_EXPECTED_EXPR}, node.token, node.span; error = sem_bad)
end
block push_value(ref: index)
    let span: SourceSpan = cu.hir_exprs.data[ref].span
    emit sem_push_val(cu, ref, span; ok = value_pushed, limit_error = too_big, oom = out_of_mem)
end
block value_pushed()
    jump expect_op(slot = cu.semantic_mark + 1)
end
block name_found(ref: index)
    let node_ref: index = cu.parse_children.data[cu.semantic_mark]
    let node: ParseNode = cu.parse_nodes.data[node_ref]
    emit append_local_expr(cu, node, ref; ok = push_value, oom = out_of_mem)
end
block name_upvalue(ref: index)
    let node_ref: index = cu.parse_children.data[cu.semantic_mark]
    let node: ParseNode = cu.parse_nodes.data[node_ref]
    emit append_upvalue_expr(cu, node, ref; ok = push_value, oom = out_of_mem)
end
block name_missing()
    let node_ref: index = cu.parse_children.data[cu.semantic_mark]
    let node: ParseNode = cu.parse_nodes.data[node_ref]
    emit append_global_expr(cu, node; ok = push_value, oom = out_of_mem)
end
block unary_prefix(node: ParseNode)
    let op: ExprOpEntry = { op = node.token, precedence = as(u8, 11), right_assoc = as(u8, 2), span = node.span }
    emit sem_push_op(cu, op; ok = unary_pushed, limit_error = too_big, oom = out_of_mem)
end
block unary_pushed()
    jump expect_value(slot = cu.semantic_mark + 1)
end
block open_paren(node: ParseNode)
    let op: ExprOpEntry = { op = node.token, precedence = as(u8, 0), right_assoc = 0, span = node.span }
    emit sem_push_op(cu, op; ok = paren_pushed, limit_error = too_big, oom = out_of_mem)
end
block paren_pushed()
    jump expect_value(slot = cu.semantic_mark + 1)
end
block expect_op(slot: index)
    emit token_node_at(cu, slot; ok = op_token, eof = finish_all, semantic_error = sem_bad)
end
block finish_all()
    jump finish_reduce(next_slot = cu.semantic_mark)
end
block op_token(node: ParseNode)
    emit is_expr_terminator(node.token; yes = finish_all_at_current, no = not_term)
end
block finish_all_at_current()
    jump finish_reduce(next_slot = cu.semantic_mark)
end
block not_term()
    let node_ref: index = cu.parse_children.data[cu.semantic_mark]
    let node: ParseNode = cu.parse_nodes.data[node_ref]
    if node.token == @{TOK_RPAREN} then jump close_paren() end
    if node.token == @{TOK_DOT} then jump field_postfix(node = node) end
    if node.token == @{TOK_COLON} then jump method_postfix(node = node) end
    if node.token == @{TOK_LBRACKET} then jump index_postfix(node = node) end
    if node.token == @{TOK_LPAREN} then jump call_postfix(node = node) end
    emit binary_precedence(node.token; op = got_binary, not_op = finish_reduce_at_current)
end
block table_begin(node: ParseNode)
    cu.parse_mark = 0
    cu.lower_mark = 0
    cu.durable_mark = 0
    emit token_node_at(cu, cu.semantic_mark + 1; ok = table_first_or_end, eof = table_missing_end, semantic_error = sem_bad)
end
block table_missing_end()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_END}; error = sem_bad)
end
block table_first_or_end(node: ParseNode)
    if node.token == @{TOK_RBRACE} then jump table_finish(span = node.span) end
    if node.token == @{TOK_LBRACKET} then jump table_bracket_key(node = node) end
    if node.token == @{TOK_NAME} then jump table_name_or_array(node = node) end
    emit append_simple_value_expr(cu, cu.semantic_mark; ok = table_array_value, not_simple = table_bad_item, semantic_error = sem_bad, oom = out_of_mem)
end
block table_bad_item(node: ParseNode)
    emit @{source_error_at_span}(cu, @{PERR_UNSUPPORTED_SOURCE}, node.token, node.span; error = sem_bad)
end
block table_name_or_array(node: ParseNode)
    cu.status = as(u16, cu.semantic_mark)
    emit token_node_at(cu, cu.semantic_mark + 1; ok = table_name_after, eof = table_missing_end, semantic_error = sem_bad)
end
block table_name_after(node: ParseNode)
    if node.token == @{TOK_ASSIGN} then jump table_name_keyed(assign_node = node) end
    emit append_simple_value_expr(cu, as(index, cu.status); ok = table_array_value, not_simple = table_bad_item, semantic_error = sem_bad, oom = out_of_mem)
end
block table_name_keyed(assign_node: ParseNode)
    let name_ref: index = cu.parse_children.data[as(index, cu.status)]
    let name_node: ParseNode = cu.parse_nodes.data[name_ref]
    emit append_string_expr(cu, name_node; ok = table_key_ready, oom = out_of_mem)
end
block table_bracket_key(node: ParseNode)
    emit append_simple_value_expr(cu, cu.semantic_mark + 1; ok = table_bracket_key_expr, not_simple = table_bad_item, semantic_error = sem_bad, oom = out_of_mem)
end
block table_bracket_key_expr(expr_ref: index, next_slot: index)
    cu.status = as(u16, expr_ref)
    emit token_node_at(cu, next_slot; ok = table_bracket_close, eof = table_missing_end, semantic_error = sem_bad)
end
block table_bracket_close(node: ParseNode)
    if node.token ~= @{TOK_RBRACKET} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_RPAREN}, node.token, node.span; error = sem_bad) end
    emit token_node_at(cu, cu.semantic_mark + 1; ok = table_bracket_assign, eof = table_missing_end, semantic_error = sem_bad)
end
block table_bracket_assign(node: ParseNode)
    if node.token ~= @{TOK_ASSIGN} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_ASSIGN}, node.token, node.span; error = sem_bad) end
    jump table_key_ready(ref = as(index, cu.status))
end
block table_key_ready(ref: index)
    cu.status = as(u16, ref)
    emit append_simple_value_expr(cu, cu.semantic_mark + 1; ok = table_keyed_value, not_simple = table_bad_item, semantic_error = sem_bad, oom = out_of_mem)
end
block table_array_value(expr_ref: index, next_slot: index)
    let item_index: index = cu.durable_mark + 1
    cu.semantic_mark = next_slot
    emit append_table_item_expr(cu, as(index, 0), expr_ref, item_index, as(u16, 1), cu.hir_exprs.data[expr_ref].span; ok = table_item, oom = out_of_mem)
end
block table_keyed_value(expr_ref: index, next_slot: index)
    cu.semantic_mark = next_slot
    emit append_table_item_expr(cu, as(index, cu.status), expr_ref, as(index, 0), as(u16, 0), cu.hir_exprs.data[expr_ref].span; ok = table_item, oom = out_of_mem)
end
block table_item(ref: index)
    if cu.durable_mark == 0 then cu.parse_mark = ref end
    if cu.lower_mark ~= 0 then cu.hir_exprs.data[cu.lower_mark].next = ref end
    cu.lower_mark = ref
    cu.durable_mark = cu.durable_mark + 1
    emit token_node_at(cu, cu.semantic_mark; ok = table_after_item, eof = table_missing_end, semantic_error = sem_bad)
end
block table_after_item(node: ParseNode)
    if node.token == @{TOK_COMMA} then jump table_after_comma() end
    if node.token == @{TOK_RBRACE} then jump table_finish(span = node.span) end
    emit @{source_error_at_span}(cu, @{PERR_EXPECTED_COMMA}, node.token, node.span; error = sem_bad)
end
block table_after_comma()
    emit token_node_at(cu, cu.semantic_mark + 1; ok = table_first_or_end, eof = table_missing_end, semantic_error = sem_bad)
end
block table_finish(span: SourceSpan)
    emit append_table_expr(cu, cu.parse_mark, cu.durable_mark, span; ok = push_value, oom = out_of_mem)
end
block field_postfix(node: ParseNode)
    if cu.expr_vals.len == 0 then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_EXPR}, node.token, node.span; error = sem_bad) end
    let top: ExprValEntry = cu.expr_vals.data[cu.expr_vals.len]
    cu.parse_mark = top.node
    emit token_node_at(cu, cu.semantic_mark + 1; ok = field_name, eof = field_missing_name, semantic_error = sem_bad)
end
block field_missing_name()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_NAME}; error = sem_bad)
end
block field_name(node: ParseNode)
    if node.token ~= @{TOK_NAME} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_NAME}, node.token, node.span; error = sem_bad) end
    emit append_field_expr(cu, cu.parse_mark, node, node.span; ok = postfix_made, oom = out_of_mem)
end
block index_postfix(node: ParseNode)
    if cu.expr_vals.len == 0 then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_EXPR}, node.token, node.span; error = sem_bad) end
    let top: ExprValEntry = cu.expr_vals.data[cu.expr_vals.len]
    cu.parse_mark = top.node
    emit append_simple_value_expr(cu, cu.semantic_mark + 1; ok = index_key, not_simple = index_bad_key, semantic_error = sem_bad, oom = out_of_mem)
end
block index_bad_key(node: ParseNode)
    emit @{source_error_at_span}(cu, @{PERR_UNSUPPORTED_SOURCE}, node.token, node.span; error = sem_bad)
end
block index_key(expr_ref: index, next_slot: index)
    cu.lower_mark = expr_ref
    emit token_node_at(cu, next_slot; ok = index_close, eof = index_missing_close, semantic_error = sem_bad)
end
block index_missing_close()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_RPAREN}; error = sem_bad)
end
block index_close(node: ParseNode)
    if node.token ~= @{TOK_RBRACKET} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_RPAREN}, node.token, node.span; error = sem_bad) end
    emit append_index_expr(cu, cu.parse_mark, cu.lower_mark, node.span; ok = postfix_made, oom = out_of_mem)
end
block call_postfix(node: ParseNode)
    if cu.expr_vals.len == 0 then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_EXPR}, node.token, node.span; error = sem_bad) end
    let top: ExprValEntry = cu.expr_vals.data[cu.expr_vals.len]
    cu.parse_mark = top.node
    cu.durable_mark = 0
    cu.lower_mark = 0
    cu.status = 0
    emit token_node_at(cu, cu.semantic_mark + 1; ok = call_first_or_end, eof = call_missing_close, semantic_error = sem_bad)
end
block call_missing_close()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_RPAREN}; error = sem_bad)
end
block call_first_or_end(node: ParseNode)
    if node.token == @{TOK_RPAREN} then emit append_call_expr(cu, cu.parse_mark, as(index, 0), as(index, 0), node.span; ok = postfix_made, oom = out_of_mem) end
    emit append_simple_value_expr(cu, cu.semantic_mark; ok = call_arg, not_simple = call_bad_arg, semantic_error = sem_bad, oom = out_of_mem)
end
block call_bad_arg(node: ParseNode)
    emit @{source_error_at_span}(cu, @{PERR_UNSUPPORTED_SOURCE}, node.token, node.span; error = sem_bad)
end
block call_arg(expr_ref: index, next_slot: index)
    if cu.status == 0 then cu.durable_mark = expr_ref end
    if cu.lower_mark ~= 0 then cu.hir_exprs.data[cu.lower_mark].next = expr_ref end
    cu.lower_mark = expr_ref
    cu.status = cu.status + 1
    emit token_node_at(cu, next_slot; ok = call_after_arg, eof = call_missing_close, semantic_error = sem_bad)
end
block call_after_arg(node: ParseNode)
    if node.token == @{TOK_COMMA} then jump call_after_comma() end
    if node.token == @{TOK_RPAREN} then emit append_call_expr(cu, cu.parse_mark, cu.durable_mark, as(index, cu.status), node.span; ok = postfix_made, oom = out_of_mem) end
    emit @{source_error_at_span}(cu, @{PERR_EXPECTED_RPAREN}, node.token, node.span; error = sem_bad)
end
block call_after_comma()
    emit token_node_at(cu, cu.semantic_mark + 1; ok = call_first_or_end, eof = call_missing_close, semantic_error = sem_bad)
end
block method_postfix(node: ParseNode)
    if cu.expr_vals.len == 0 then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_EXPR}, node.token, node.span; error = sem_bad) end
    let top: ExprValEntry = cu.expr_vals.data[cu.expr_vals.len]
    cu.parse_mark = top.node
    emit token_node_at(cu, cu.semantic_mark + 1; ok = method_name, eof = field_missing_name, semantic_error = sem_bad)
end
block method_name(node: ParseNode)
    if node.token ~= @{TOK_NAME} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_NAME}, node.token, node.span; error = sem_bad) end
    let name_ref: index = cu.parse_children.data[cu.semantic_mark]
    cu.status = as(u16, name_ref)
    emit token_node_at(cu, cu.semantic_mark + 1; ok = method_open, eof = call_missing_close, semantic_error = sem_bad)
end
block method_open(node: ParseNode)
    if node.token ~= @{TOK_LPAREN} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_RPAREN}, node.token, node.span; error = sem_bad) end
    cu.lower_mark = 0
    cu.durable_mark = 0
    emit token_node_at(cu, cu.semantic_mark + 1; ok = method_first_or_end, eof = call_missing_close, semantic_error = sem_bad)
end
block method_first_or_end(node: ParseNode)
    if node.token == @{TOK_RPAREN} then jump method_finish(span = node.span) end
    emit append_simple_value_expr(cu, cu.semantic_mark; ok = method_arg, not_simple = call_bad_arg, semantic_error = sem_bad, oom = out_of_mem)
end
block method_arg(expr_ref: index, next_slot: index)
    cu.lower_mark = expr_ref
    cu.durable_mark = 1
    emit token_node_at(cu, next_slot; ok = method_close, eof = call_missing_close, semantic_error = sem_bad)
end
block method_close(node: ParseNode)
    if node.token ~= @{TOK_RPAREN} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_RPAREN}, node.token, node.span; error = sem_bad) end
    jump method_finish(span = node.span)
end
block method_finish(span: SourceSpan)
    let name_node: ParseNode = cu.parse_nodes.data[as(index, cu.status)]
    emit append_method_call_expr(cu, cu.parse_mark, name_node, cu.lower_mark, cu.durable_mark, span; ok = postfix_made, oom = out_of_mem)
end
block postfix_made(ref: index)
    cu.expr_vals.data[cu.expr_vals.len].node = ref
    cu.expr_vals.data[cu.expr_vals.len].span = cu.hir_exprs.data[ref].span
    jump expect_op(slot = cu.semantic_mark + 1)
end
block finish_reduce_at_current()
    jump finish_reduce(next_slot = cu.semantic_mark)
end
block got_binary(prec: u8)
    let node_ref: index = cu.parse_children.data[cu.semantic_mark]
    let node: ParseNode = cu.parse_nodes.data[node_ref]
    jump reduce_before_binary(op_token = node.token, prec = prec, span = node.span)
end
block reduce_before_binary(op_token: u16, prec: u8, span: SourceSpan)
    if cu.expr_ops.len == 0 then jump push_binary(op_token = op_token, prec = prec, span = span) end
    let top: ExprOpEntry = cu.expr_ops.data[cu.expr_ops.len]
    if top.op == @{TOK_LPAREN} then jump push_binary(op_token = op_token, prec = prec, span = span) end
    if top.precedence < prec then jump push_binary(op_token = op_token, prec = prec, span = span) end
    emit reduce_hir_expr_once(cu; ok = reduced_for_binary, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block reduced_for_binary()
    let node_ref: index = cu.parse_children.data[cu.semantic_mark]
    let node: ParseNode = cu.parse_nodes.data[node_ref]
    emit binary_precedence(node.token; op = got_binary, not_op = finish_reduce_at_current)
end
block push_binary(op_token: u16, prec: u8, span: SourceSpan)
    let op: ExprOpEntry = { op = op_token, precedence = prec, right_assoc = 0, span = span }
    emit sem_push_op(cu, op; ok = binary_pushed, limit_error = too_big, oom = out_of_mem)
end
block binary_pushed()
    jump expect_value(slot = cu.semantic_mark + 1)
end
block close_paren()
    if cu.expr_ops.len == 0 then emit @{source_error_at_current}(cu, @{PERR_EXPECTED_EXPR}; error = sem_bad) end
    let top: ExprOpEntry = cu.expr_ops.data[cu.expr_ops.len]
    if top.op == @{TOK_LPAREN} then jump pop_paren() end
    emit reduce_hir_expr_once(cu; ok = close_paren, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block pop_paren()
    cu.expr_ops.len = cu.expr_ops.len - 1
    jump expect_op(slot = cu.semantic_mark + 1)
end
block finish_reduce(next_slot: index)
    if cu.expr_ops.len == 0 then jump finish_values(next_slot = next_slot) end
    let top: ExprOpEntry = cu.expr_ops.data[cu.expr_ops.len]
    if top.op == @{TOK_LPAREN} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_RPAREN}, top.op, top.span; error = sem_bad) end
    emit reduce_hir_expr_once(cu; ok = finish_reduce_again, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block finish_reduce_again()
    jump finish_reduce(next_slot = cu.semantic_mark)
end
block finish_values(next_slot: index)
    if cu.expr_vals.len ~= 1 then emit @{source_error_at_current}(cu, @{PERR_EXPECTED_EXPR}; error = sem_bad) end
    let val: ExprValEntry = cu.expr_vals.data[cu.expr_vals.len]
    cu.expr_vals.len = 0
    jump parsed(expr_ref = val.node, next_slot = next_slot)
end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

-- Small wrapper around build_hir_expr. `cu.semantic_mark` carries the current
-- token slot because Moonlift continuations here do not close over block params.
local build_hir_expr_at = host.region(V) [[
region build_hir_expr_at(cu: ptr(CompileUnit), start_slot: index;
                         parsed(expr_ref: index, next_slot: index) | semantic_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    cu.semantic_mark = start_slot
    emit build_hir_expr(cu, start_slot; parsed = done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block done(expr_ref: index, next_slot: index) jump parsed(expr_ref = expr_ref, next_slot = next_slot) end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local resolve_name_use = host.region(V) [[
region resolve_name_use(cu: ptr(CompileUnit), use_ref: index;
                        ok | semantic_error(err: CompileError))
entry start()
    jump ok()
end
end
]]

local compute_capture = host.region(V) [[
region compute_capture(cu: ptr(CompileUnit), symbol_ref: index, function_ref: index;
                       ok(capture_ref: index) | semantic_error(err: CompileError) | oom)
entry start()
    let span: SourceSpan = { start = 0, len = 0, line = 1, col = 1 }
    let cap: CaptureRec = { symbol = symbol_ref, source_function = function_ref, through_parent = 0, reserved = 0, upvalue_index = 0, span = span }
    emit append_capture(cu, cap; ok = made, oom = out_of_mem)
end
block made(ref: index) jump ok(capture_ref = ref) end
block out_of_mem() jump oom() end
end
]]

local build_hir_from_parse = host.region(V) [[
region build_hir_from_parse(cu: ptr(CompileUnit);
                            ok | semantic_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    cu.phase = @{SOURCE_SEMANTIC}
    cu.root_hir_function = 0
    cu.hir_functions.len = 0
    cu.hir_blocks.len = 0
    cu.hir_stmts.len = 0
    cu.hir_exprs.len = 0
    cu.scopes.len = 0
    cu.symbols.len = 0
    cu.captures.len = 0
    cu.name_uses.len = 0
    cu.semantic_frames.len = 0
    cu.expr_ops.len = 0
    cu.expr_vals.len = 0
    if cu.root_parse_function == 0 then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_PARSE_PRODUCT}; error = sem_bad) end
    let root_node: index = cu.parse_functions.data[cu.root_parse_function].root_node
    let span: SourceSpan = cu.parse_nodes.data[root_node].span
    let scope: ScopeRec = { parent = 0, owner_function = 1, symbol_first = 1, symbol_len = 0, flags = 0, reserved = 0, span = span }
    emit append_scope(cu, scope; ok = got_scope, oom = out_of_mem)
end
block got_scope(ref: index)
    let root_node: index = cu.parse_functions.data[cu.root_parse_function].root_node
    let span: SourceSpan = cu.parse_nodes.data[root_node].span
    let hir_block: HirBlock = { scope = ref, stmt_first = 0, stmt_last = 0, stmt_len = 0, flags = 0, terminator = 0, span = span }
    emit append_hir_block(cu, hir_block; ok = got_block, oom = out_of_mem)
end
block got_block(ref: index)
    let root_node: index = cu.parse_functions.data[cu.root_parse_function].root_node
    let span: SourceSpan = cu.parse_nodes.data[root_node].span
    let fn: HirFunction = { parent = 0, body = ref, params_first = 0, params_len = 0, symbols_first = 1, symbols_len = 0, captures_first = 0, captures_len = 0, nested_first = 0, nested_len = 0, flags = 0, numparams = 0, is_vararg = 0, span = span }
    emit append_hir_function(cu, fn; ok = got_fn, oom = out_of_mem)
end
block got_fn(ref: index)
    cu.root_hir_function = ref
    jump scan(slot = as(index, 1))
end
block scan(slot: index)
    emit token_node_at(cu, slot; ok = stmt_token, eof = done, semantic_error = sem_bad)
end
block stmt_token(node: ParseNode)
    if node.token == @{TOK_EOF} then jump done() end
    if node.token == @{TOK_SEMI} then jump scan(slot = cu.semantic_mark + 1) end
    if node.token == @{KW_RETURN} then jump return_stmt(node = node) end
    if node.token == @{KW_LOCAL} then jump local_stmt(node = node) end
    if node.token == @{KW_FUNCTION} then jump function_stmt(node = node) end
    if node.token == @{TOK_NAME} then jump assign_stmt(node = node) end
    if node.token == @{KW_IF} then jump if_stmt(node = node) end
    if node.token == @{KW_ELSE} then jump else_stmt(node = node) end
    if node.token == @{KW_ELSEIF} then emit @{source_error_at_span}(cu, @{PERR_UNSUPPORTED_SOURCE}, node.token, node.span; error = sem_bad) end
    if node.token == @{KW_END} then jump end_stmt(node = node) end
    if node.token == @{KW_WHILE} then jump while_stmt(node = node) end
    if node.token == @{KW_REPEAT} then jump repeat_stmt(node = node) end
    if node.token == @{KW_UNTIL} then jump until_stmt(node = node) end
    if node.token == @{KW_FOR} then jump for_stmt(node = node) end
    emit @{source_error_at_span}(cu, @{PERR_UNEXPECTED_TOKEN}, node.token, node.span; error = sem_bad)
end
block function_stmt(node: ParseNode)
    emit token_node_at(cu, cu.semantic_mark + 1; ok = function_name, eof = local_missing_name, semantic_error = sem_bad)
end
block function_name(node: ParseNode)
    if node.token ~= @{TOK_NAME} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_NAME}, node.token, node.span; error = sem_bad) end
    let name_ref: index = cu.parse_children.data[cu.semantic_mark]
    jump function_body_start(kind = as(u16, 1), sym_ref = as(index, 0), name_ref = name_ref, slot = cu.semantic_mark + 1)
end
block function_body_start(kind: u16, sym_ref: index, name_ref: index, slot: index)
    cu.status = kind
    cu.durable_mark = sym_ref
    cu.lower_mark = name_ref
    emit token_node_at(cu, slot; ok = function_open, eof = function_missing_body, semantic_error = sem_bad)
end
block function_missing_body()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_FUNCTION_BODY}; error = sem_bad)
end
block function_open(node: ParseNode)
    if node.token ~= @{TOK_LPAREN} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_FUNCTION_BODY}, node.token, node.span; error = sem_bad) end
    emit current_semantic_function(cu; ok = function_parent_ready)
end
block function_parent_ready(function_ref: index)
    let span: SourceSpan = cu.parse_nodes.data[cu.lower_mark].span
    let fn: HirFunction = { parent = function_ref, body = 0, params_first = 0, params_len = 0, symbols_first = 0, symbols_len = 0, captures_first = 0, captures_len = 0, nested_first = 0, nested_len = 0, flags = 0, numparams = 0, is_vararg = 0, span = span }
    emit append_hir_function(cu, fn; ok = function_allocated, oom = out_of_mem)
end
block function_allocated(ref: index)
    cu.parse_mark = ref
    let span: SourceSpan = cu.hir_functions.data[ref].span
    let scope: ScopeRec = { parent = 0, owner_function = ref, symbol_first = cu.symbols.len + 1, symbol_len = 0, flags = 0, reserved = 0, span = span }
    emit append_scope(cu, scope; ok = function_scope_ready, oom = out_of_mem)
end
block function_scope_ready(ref: index)
    let fn_ref: index = cu.parse_mark
    let scope_ref: index = ref
    let span: SourceSpan = cu.hir_functions.data[fn_ref].span
    let block_rec: HirBlock = { scope = scope_ref, stmt_first = 0, stmt_last = 0, stmt_len = 0, flags = 0, terminator = 0, span = span }
    emit append_hir_block(cu, block_rec; ok = function_block_ready, oom = out_of_mem)
end
block function_block_ready(ref: index)
    let fn_ref: index = cu.parse_mark
    cu.hir_functions.data[fn_ref].body = ref
    emit token_node_at(cu, cu.semantic_mark + 1; ok = function_param_or_close, eof = function_missing_body, semantic_error = sem_bad)
end
block function_param_or_close(node: ParseNode)
    if node.token == @{TOK_RPAREN} then jump function_params_done(close_node = node) end
    if node.token == @{TOK_DOTDOTDOT} then jump function_vararg(node = node) end
    if node.token ~= @{TOK_NAME} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_NAME}, node.token, node.span; error = sem_bad) end
    let fn_ref: index = cu.parse_mark
    let body: index = cu.hir_functions.data[fn_ref].body
    let scope_ref: index = cu.hir_blocks.data[body].scope
    emit add_symbol_to_function_from_node(cu, node, scope_ref, fn_ref, as(u16, @{SYM_PARAM}); ok = function_param_added, semantic_error = sem_bad, oom = out_of_mem)
end
block function_param_added(ref: index)
    let fn_ref: index = cu.symbols.data[ref].owner_function
    if cu.hir_functions.data[fn_ref].params_len == 0 then cu.hir_functions.data[fn_ref].params_first = ref end
    cu.hir_functions.data[fn_ref].params_len = cu.hir_functions.data[fn_ref].params_len + 1
    cu.hir_functions.data[fn_ref].numparams = as(u8, cu.hir_functions.data[fn_ref].params_len)
    emit token_node_at(cu, cu.semantic_mark + 1; ok = function_after_param, eof = function_missing_body, semantic_error = sem_bad)
end
block function_after_param(node: ParseNode)
    if node.token == @{TOK_COMMA} then emit token_node_at(cu, cu.semantic_mark + 1; ok = function_param_or_close, eof = function_missing_body, semantic_error = sem_bad) end
    if node.token == @{TOK_RPAREN} then jump function_params_done(close_node = node) end
    emit @{source_error_at_span}(cu, @{PERR_EXPECTED_RPAREN}, node.token, node.span; error = sem_bad)
end
block function_vararg(node: ParseNode)
    let fn_ref: index = cu.parse_mark
    cu.hir_functions.data[fn_ref].is_vararg = 1
    cu.hir_functions.data[fn_ref].flags = 1
    emit token_node_at(cu, cu.semantic_mark + 1; ok = function_vararg_close, eof = function_missing_body, semantic_error = sem_bad)
end
block function_vararg_close(node: ParseNode)
    if node.token ~= @{TOK_RPAREN} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_RPAREN}, node.token, node.span; error = sem_bad) end
    jump function_params_done(close_node = node)
end
block function_params_done(close_node: ParseNode)
    let fn_ref: index = cu.parse_mark
    let frame: SemanticFrame = { kind = as(u16, @{HSTMT_FUNCTION_DECL}), pc = cu.status, flags = 0, reserved = 0, parse_ref = cu.lower_mark, hir_parent = 0, scope = cu.hir_blocks.data[cu.hir_functions.data[fn_ref].body].scope, function_ref = fn_ref, a = cu.durable_mark, b = 0, c = fn_ref, span = cu.hir_functions.data[fn_ref].span }
    cu.semantic_mark = cu.semantic_mark + 1
    emit push_semantic_frame(cu, frame; ok = function_frame_pushed, limit_error = too_big, oom = out_of_mem)
end
block function_frame_pushed()
    jump scan(slot = cu.semantic_mark)
end
block return_stmt(node: ParseNode)
    cu.semantic_mark = cu.semantic_mark + 1
    emit token_node_at(cu, cu.semantic_mark; ok = return_after, eof = return_empty, semantic_error = sem_bad)
end
block return_after(node: ParseNode)
    emit is_expr_terminator(node.token; yes = return_empty, no = return_expr)
end
block return_empty()
    let ret_slot: index = cu.semantic_mark - 1
    let ret_ref: index = cu.parse_children.data[ret_slot]
    let span: SourceSpan = cu.parse_nodes.data[ret_ref].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_RETURN}), flags = 0, a = 0, b = 0, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = span }
    emit append_hir_stmt(cu, stmt; ok = stmt_added, oom = out_of_mem)
end
block return_expr()
    emit build_hir_expr_at(cu, cu.semantic_mark; parsed = got_return_expr, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block got_return_expr(expr_ref: index, next_slot: index)
    cu.parse_mark = expr_ref
    cu.lower_mark = expr_ref
    cu.durable_mark = 1
    cu.semantic_mark = next_slot
    emit token_node_at(cu, next_slot; ok = return_list_after, eof = return_list_finish, semantic_error = sem_bad)
end
block return_list_after(node: ParseNode)
    if node.token == @{TOK_COMMA} then jump return_list_comma() end
    jump return_list_finish()
end
block return_list_comma()
    emit build_hir_expr_at(cu, cu.semantic_mark + 1; parsed = got_return_list_expr, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block got_return_list_expr(expr_ref: index, next_slot: index)
    cu.hir_exprs.data[cu.lower_mark].next = expr_ref
    cu.lower_mark = expr_ref
    cu.durable_mark = cu.durable_mark + 1
    cu.semantic_mark = next_slot
    emit token_node_at(cu, next_slot; ok = return_list_after, eof = return_list_finish, semantic_error = sem_bad)
end
block return_list_finish()
    let span: SourceSpan = cu.hir_exprs.data[cu.parse_mark].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_RETURN}), flags = 0, a = cu.parse_mark, b = cu.durable_mark, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = span }
    emit append_hir_stmt(cu, stmt; ok = stmt_added, oom = out_of_mem)
end
block local_stmt(node: ParseNode)
    let name_slot: index = cu.semantic_mark + 1
    emit token_node_at(cu, name_slot; ok = local_first, eof = local_missing_name, semantic_error = sem_bad)
end
block local_missing_name()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_NAME}; error = sem_bad)
end
block local_first(node: ParseNode)
    if node.token == @{KW_FUNCTION} then emit token_node_at(cu, cu.semantic_mark + 1; ok = local_function_name, eof = local_missing_name, semantic_error = sem_bad) end
    jump local_name(node = node)
end
block local_function_name(node: ParseNode)
    if node.token ~= @{TOK_NAME} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_NAME}, node.token, node.span; error = sem_bad) end
    cu.lower_mark = cu.parse_children.data[cu.semantic_mark]
    emit add_local_symbol_from_node(cu, node, as(index, 1); ok = local_function_symbol, semantic_error = sem_bad, oom = out_of_mem)
end
block local_function_symbol(ref: index)
    jump function_body_start(kind = as(u16, 0), sym_ref = ref, name_ref = cu.lower_mark, slot = cu.semantic_mark + 1)
end
block local_name(node: ParseNode)
    if node.token ~= @{TOK_NAME} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_NAME}, node.token, node.span; error = sem_bad) end
    emit add_local_symbol_from_node(cu, node, as(index, 1); ok = local_symbol, semantic_error = sem_bad, oom = out_of_mem)
end
block local_symbol(ref: index)
    cu.semantic_mark = cu.semantic_mark + 1
    emit token_node_at(cu, cu.semantic_mark; ok = local_after_name, eof = local_no_init, semantic_error = sem_bad)
end
block local_after_name(node: ParseNode)
    if node.token == @{TOK_ASSIGN} then jump local_has_init() end
    jump local_no_init()
end
block local_no_init()
    let sym_ref: index = cu.symbols.len
    let span: SourceSpan = cu.symbols.data[sym_ref].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_LOCAL}), flags = 0, a = sym_ref, b = 0, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = span }
    emit append_hir_stmt(cu, stmt; ok = stmt_added, oom = out_of_mem)
end
block local_has_init()
    emit token_node_at(cu, cu.semantic_mark + 1; ok = local_init_first, eof = local_missing_name, semantic_error = sem_bad)
end
block local_init_first(node: ParseNode)
    if node.token == @{KW_FUNCTION} then jump local_function_literal(node = node) end
    emit build_hir_expr_at(cu, cu.semantic_mark; parsed = got_local_expr, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block local_function_literal(node: ParseNode)
    let sym_ref: index = cu.symbols.len
    let name_ref: index = cu.parse_children.data[cu.semantic_mark]
    jump function_body_start(kind = as(u16, 0), sym_ref = sym_ref, name_ref = name_ref, slot = cu.semantic_mark + 1)
end
block got_local_expr(expr_ref: index, next_slot: index)
    let sym_ref: index = cu.symbols.len
    let span: SourceSpan = cu.symbols.data[sym_ref].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_LOCAL}), flags = 0, a = sym_ref, b = expr_ref, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = span }
    cu.semantic_mark = next_slot
    emit append_hir_stmt(cu, stmt; ok = stmt_added, oom = out_of_mem)
end
block assign_stmt(node: ParseNode)
    emit build_hir_expr_at(cu, cu.semantic_mark; parsed = got_assign_lvalue, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block got_assign_lvalue(expr_ref: index, next_slot: index)
    cu.durable_mark = expr_ref
    cu.semantic_mark = next_slot
    emit token_node_at(cu, next_slot; ok = assign_after_lvalue, eof = assign_or_call_eof, semantic_error = sem_bad)
end
block assign_or_call_eof()
    jump maybe_call_stmt()
end
block assign_after_lvalue(node: ParseNode)
    if node.token == @{TOK_ASSIGN} then emit build_hir_expr_at(cu, cu.semantic_mark + 1; parsed = got_assign_expr, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem) end
    emit is_expr_terminator(node.token; yes = maybe_call_stmt, no = assign_expected_token)
end
block maybe_call_stmt()
    let e: HirExpr = cu.hir_exprs.data[cu.durable_mark]
    if e.kind == @{HEXPR_CALL} then jump make_call_stmt(e = e) end
    if e.kind == @{HEXPR_METHOD_CALL} then jump make_call_stmt(e = e) end
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_ASSIGN}; error = sem_bad)
end
block make_call_stmt(e: HirExpr)
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_CALL}), flags = 0, a = cu.durable_mark, b = 0, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = e.span }
    emit append_hir_stmt(cu, stmt; ok = stmt_added, oom = out_of_mem)
end
block assign_expected_token()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_ASSIGN}; error = sem_bad)
end
block assign_expected()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_ASSIGN}; error = sem_bad)
end
block got_assign_expr(expr_ref: index, next_slot: index)
    let lvalue_ref: index = cu.durable_mark
    let span: SourceSpan = cu.hir_exprs.data[expr_ref].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_ASSIGN}), flags = 1, a = lvalue_ref, b = expr_ref, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = span }
    cu.semantic_mark = next_slot
    emit append_hir_stmt(cu, stmt; ok = stmt_added, oom = out_of_mem)
end
block if_stmt(node: ParseNode)
    emit build_hir_expr_at(cu, cu.semantic_mark + 1; parsed = got_if_cond, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block got_if_cond(expr_ref: index, next_slot: index)
    cu.parse_mark = expr_ref
    emit token_node_at(cu, next_slot; ok = if_then, eof = if_expected_then, semantic_error = sem_bad)
end
block if_expected_then()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_THEN}; error = sem_bad)
end
block if_then(node: ParseNode)
    if node.token ~= @{KW_THEN} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_THEN}, node.token, node.span; error = sem_bad) end
    let expr_ref: index = cu.parse_mark
    let span: SourceSpan = cu.hir_exprs.data[expr_ref].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_IF}), flags = 0, a = expr_ref, b = 0, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = span }
    cu.semantic_mark = cu.semantic_mark + 1
    emit append_hir_stmt(cu, stmt; ok = if_stmt_added, oom = out_of_mem)
end
block if_stmt_added(ref: index)
    cu.durable_mark = ref
    let span: SourceSpan = cu.hir_stmts.data[ref].span
    var fn_ref: index = cu.root_hir_function
    if cu.semantic_frames.len ~= 0 then fn_ref = cu.semantic_frames.data[cu.semantic_frames.len].function_ref end
    let frame: SemanticFrame = { kind = as(u16, @{HSTMT_IF}), pc = 0, flags = 0, reserved = 0, parse_ref = ref, hir_parent = 0, scope = 1, function_ref = fn_ref, a = 0, b = 0, c = 0, span = span }
    emit push_semantic_frame(cu, frame; ok = control_frame_pushed, limit_error = too_big, oom = out_of_mem)
end
block while_stmt(node: ParseNode)
    emit build_hir_expr_at(cu, cu.semantic_mark + 1; parsed = got_while_cond, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block got_while_cond(expr_ref: index, next_slot: index)
    cu.parse_mark = expr_ref
    emit token_node_at(cu, next_slot; ok = while_do, eof = while_expected_do, semantic_error = sem_bad)
end
block while_expected_do()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_DO}; error = sem_bad)
end
block while_do(node: ParseNode)
    if node.token ~= @{KW_DO} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_DO}, node.token, node.span; error = sem_bad) end
    let expr_ref: index = cu.parse_mark
    let span: SourceSpan = cu.hir_exprs.data[expr_ref].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_WHILE}), flags = 0, a = expr_ref, b = 0, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = span }
    cu.semantic_mark = cu.semantic_mark + 1
    emit append_hir_stmt(cu, stmt; ok = while_stmt_added, oom = out_of_mem)
end
block while_stmt_added(ref: index)
    cu.durable_mark = ref
    let span: SourceSpan = cu.hir_stmts.data[ref].span
    var fn_ref: index = cu.root_hir_function
    if cu.semantic_frames.len ~= 0 then fn_ref = cu.semantic_frames.data[cu.semantic_frames.len].function_ref end
    let frame: SemanticFrame = { kind = as(u16, @{HSTMT_WHILE}), pc = 0, flags = 0, reserved = 0, parse_ref = ref, hir_parent = 0, scope = 1, function_ref = fn_ref, a = 0, b = 0, c = 0, span = span }
    emit push_semantic_frame(cu, frame; ok = control_frame_pushed, limit_error = too_big, oom = out_of_mem)
end
block repeat_stmt(node: ParseNode)
    let body_start: index = cu.hir_stmts.len + 1
    var fn_ref: index = cu.root_hir_function
    if cu.semantic_frames.len ~= 0 then fn_ref = cu.semantic_frames.data[cu.semantic_frames.len].function_ref end
    let frame: SemanticFrame = { kind = as(u16, @{HSTMT_REPEAT}), pc = 0, flags = 0, reserved = 0, parse_ref = 0, hir_parent = 0, scope = 1, function_ref = fn_ref, a = body_start, b = 0, c = 0, span = node.span }
    cu.semantic_mark = cu.semantic_mark + 1
    emit push_semantic_frame(cu, frame; ok = repeat_frame_pushed, limit_error = too_big, oom = out_of_mem)
end
block repeat_frame_pushed()
    jump scan(slot = cu.semantic_mark)
end
block until_stmt(node: ParseNode)
    if cu.semantic_frames.len == 0 then emit @{source_error_at_span}(cu, @{PERR_UNEXPECTED_TOKEN}, node.token, node.span; error = sem_bad) end
    let frame: SemanticFrame = cu.semantic_frames.data[cu.semantic_frames.len]
    if frame.kind ~= @{HSTMT_REPEAT} then emit @{source_error_at_span}(cu, @{PERR_UNEXPECTED_TOKEN}, node.token, node.span; error = sem_bad) end
    emit pop_semantic_frame(cu; popped = until_popped, semantic_error = sem_bad)
end
block until_popped(frame: SemanticFrame)
    cu.durable_mark = frame.a
    emit build_hir_expr_at(cu, cu.semantic_mark + 1; parsed = got_until_expr, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block got_until_expr(expr_ref: index, next_slot: index)
    let span: SourceSpan = cu.hir_exprs.data[expr_ref].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_REPEAT}), flags = 0, a = expr_ref, b = cu.durable_mark, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = span }
    cu.semantic_mark = next_slot
    emit append_hir_stmt(cu, stmt; ok = stmt_added, oom = out_of_mem)
end
block for_stmt(node: ParseNode)
    let name_slot: index = cu.semantic_mark + 1
    emit token_node_at(cu, name_slot; ok = for_name, eof = local_missing_name, semantic_error = sem_bad)
end
block for_name(node: ParseNode)
    if node.token ~= @{TOK_NAME} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_NAME}, node.token, node.span; error = sem_bad) end
    emit add_local_symbol_from_node(cu, node, as(index, 1); ok = for_symbol, semantic_error = sem_bad, oom = out_of_mem)
end
block for_symbol(ref: index)
    cu.durable_mark = ref
    cu.semantic_mark = cu.semantic_mark + 1
    emit token_node_at(cu, cu.semantic_mark; ok = for_after_name, eof = assign_expected, semantic_error = sem_bad)
end
block for_after_name(node: ParseNode)
    if node.token ~= @{TOK_ASSIGN} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_ASSIGN}, node.token, node.span; error = sem_bad) end
    emit build_hir_expr_at(cu, cu.semantic_mark + 1; parsed = got_for_init, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block got_for_init(expr_ref: index, next_slot: index)
    cu.parse_mark = expr_ref
    emit token_node_at(cu, next_slot; ok = for_after_init, eof = for_expected_comma, semantic_error = sem_bad)
end
block for_expected_comma()
    emit @{source_error_at_current}(cu, @{PERR_EXPECTED_COMMA}; error = sem_bad)
end
block for_after_init(node: ParseNode)
    if node.token ~= @{TOK_COMMA} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_COMMA}, node.token, node.span; error = sem_bad) end
    emit build_hir_expr_at(cu, cu.semantic_mark + 1; parsed = got_for_limit, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block got_for_limit(expr_ref: index, next_slot: index)
    cu.lower_mark = expr_ref
    emit token_node_at(cu, next_slot; ok = for_after_limit, eof = while_expected_do, semantic_error = sem_bad)
end
block for_after_limit(node: ParseNode)
    if node.token == @{TOK_COMMA} then emit build_hir_expr_at(cu, cu.semantic_mark + 1; parsed = got_for_step, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem) end
    if node.token == @{KW_DO} then emit append_integer_const(cu, node.span, as(i64, 1); ok = got_default_for_step, oom = out_of_mem) end
    emit @{source_error_at_span}(cu, @{PERR_EXPECTED_DO}, node.token, node.span; error = sem_bad)
end
block got_for_step(expr_ref: index, next_slot: index)
    cu.status = as(u16, expr_ref)
    emit token_node_at(cu, next_slot; ok = for_step_after, eof = while_expected_do, semantic_error = sem_bad)
end
block for_step_after(node: ParseNode)
    if node.token ~= @{KW_DO} then emit @{source_error_at_span}(cu, @{PERR_EXPECTED_DO}, node.token, node.span; error = sem_bad) end
    jump make_for_stmt()
end
block got_default_for_step(ref: index)
    cu.status = as(u16, ref)
    jump make_for_stmt()
end
block make_for_stmt()
    let sym_ref: index = cu.durable_mark
    let step_ref: index = as(index, cu.status)
    let span: SourceSpan = cu.symbols.data[sym_ref].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_FOR_NUM}), flags = 0, a = sym_ref, b = cu.parse_mark, c = cu.lower_mark, d = step_ref, e = 0, pc = 0, next_stmt = 0, span = span }
    cu.semantic_mark = cu.semantic_mark + 1
    emit append_hir_stmt(cu, stmt; ok = for_stmt_added, oom = out_of_mem)
end
block for_stmt_added(ref: index)
    cu.durable_mark = ref
    let span: SourceSpan = cu.hir_stmts.data[ref].span
    var fn_ref: index = cu.root_hir_function
    if cu.semantic_frames.len ~= 0 then fn_ref = cu.semantic_frames.data[cu.semantic_frames.len].function_ref end
    let frame: SemanticFrame = { kind = as(u16, @{HSTMT_FOR_NUM}), pc = 0, flags = 0, reserved = 0, parse_ref = ref, hir_parent = 0, scope = 1, function_ref = fn_ref, a = 0, b = 0, c = 0, span = span }
    emit push_semantic_frame(cu, frame; ok = control_frame_pushed, limit_error = too_big, oom = out_of_mem)
end
block else_stmt(node: ParseNode)
    if cu.semantic_frames.len == 0 then emit @{source_error_at_span}(cu, @{PERR_UNEXPECTED_TOKEN}, node.token, node.span; error = sem_bad) end
    let top_slot: index = cu.semantic_frames.len
    let frame: SemanticFrame = cu.semantic_frames.data[top_slot]
    if frame.kind ~= @{HSTMT_IF} then emit @{source_error_at_span}(cu, @{PERR_UNEXPECTED_TOKEN}, node.token, node.span; error = sem_bad) end
    if frame.pc ~= 0 then emit @{source_error_at_span}(cu, @{PERR_UNEXPECTED_TOKEN}, node.token, node.span; error = sem_bad) end
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_GOTO}), flags = 1, a = 0, b = 0, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = node.span }
    cu.semantic_mark = cu.semantic_mark + 1
    emit append_hir_stmt(cu, stmt; ok = else_goto_added, oom = out_of_mem)
end
block else_goto_added(ref: index)
    let top_slot: index = cu.semantic_frames.len
    let frame: SemanticFrame = cu.semantic_frames.data[top_slot]
    cu.hir_stmts.data[frame.parse_ref].b = ref + 1
    cu.semantic_frames.data[top_slot].pc = 1
    cu.semantic_frames.data[top_slot].a = ref
    jump stmt_added(ref = ref)
end
block end_stmt(node: ParseNode)
    if cu.semantic_frames.len == 0 then emit @{source_error_at_span}(cu, @{PERR_UNEXPECTED_TOKEN}, node.token, node.span; error = sem_bad) end
    emit pop_semantic_frame(cu; popped = end_popped, semantic_error = sem_bad)
end
block end_popped(frame: SemanticFrame)
    if frame.kind == @{HSTMT_IF} then jump end_if(frame = frame) end
    if frame.kind == @{HSTMT_WHILE} then jump end_while(frame = frame) end
    if frame.kind == @{HSTMT_FOR_NUM} then jump end_for(frame = frame) end
    if frame.kind == @{HSTMT_FUNCTION_DECL} then jump end_function(frame = frame) end
    emit @{source_error_at_span}(cu, @{PERR_EXPECTED_UNTIL}, as(u16, @{KW_END}), frame.span; error = sem_bad)
end
block end_function(frame: SemanticFrame)
    cu.status = frame.pc
    cu.durable_mark = frame.a
    cu.lower_mark = frame.parse_ref
    emit append_closure_expr(cu, frame.c, frame.span; ok = function_closure_ready, oom = out_of_mem)
end
block function_closure_ready(ref: index)
    cu.parse_mark = ref
    cu.semantic_mark = cu.semantic_mark + 1
    if cu.status == 0 then jump function_local_stmt(expr_ref = ref) end
    jump function_global_stmt(expr_ref = ref)
end
block function_local_stmt(expr_ref: index)
    let sym_ref: index = cu.durable_mark
    let span: SourceSpan = cu.hir_exprs.data[expr_ref].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_LOCAL}), flags = 0, a = sym_ref, b = expr_ref, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = span }
    emit append_hir_stmt(cu, stmt; ok = stmt_added, oom = out_of_mem)
end
block function_global_stmt(expr_ref: index)
    let name_node: ParseNode = cu.parse_nodes.data[cu.lower_mark]
    emit append_global_expr(cu, name_node; ok = function_global_lvalue, oom = out_of_mem)
end
block function_global_lvalue(ref: index)
    let expr_ref: index = cu.parse_mark
    let span: SourceSpan = cu.hir_exprs.data[expr_ref].span
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_ASSIGN}), flags = 1, a = ref, b = expr_ref, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = span }
    emit append_hir_stmt(cu, stmt; ok = stmt_added, oom = out_of_mem)
end
block end_if(frame: SemanticFrame)
    if frame.pc == 0 then cu.hir_stmts.data[frame.parse_ref].b = cu.hir_stmts.len + 1 end
    if frame.pc == 1 then cu.hir_stmts.data[frame.a].a = cu.hir_stmts.len + 1 end
    cu.semantic_mark = cu.semantic_mark + 1
    jump scan(slot = cu.semantic_mark)
end
block end_while(frame: SemanticFrame)
    cu.durable_mark = frame.parse_ref
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_GOTO}), flags = 0, a = frame.parse_ref, b = 0, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = frame.span }
    cu.semantic_mark = cu.semantic_mark + 1
    emit append_hir_stmt(cu, stmt; ok = while_end_goto_added, oom = out_of_mem)
end
block while_end_goto_added(ref: index)
    cu.hir_stmts.data[cu.durable_mark].b = ref + 1
    jump stmt_added(ref = ref)
end
block end_for(frame: SemanticFrame)
    let stmt: HirStmt = { kind = as(u16, @{HSTMT_GOTO}), flags = 2, a = frame.parse_ref, b = 0, c = 0, d = 0, e = 0, pc = 0, next_stmt = 0, span = frame.span }
    cu.semantic_mark = cu.semantic_mark + 1
    emit append_hir_stmt(cu, stmt; ok = stmt_added, oom = out_of_mem)
end
block control_frame_pushed()
    jump stmt_added(ref = cu.durable_mark)
end
block stmt_added(ref: index)
    var fn_ref: index = cu.root_hir_function
    if cu.semantic_frames.len ~= 0 then fn_ref = cu.semantic_frames.data[cu.semantic_frames.len].function_ref end
    let body: index = cu.hir_functions.data[fn_ref].body
    if cu.hir_blocks.data[body].stmt_len == 0 then cu.hir_blocks.data[body].stmt_first = ref end
    if cu.hir_blocks.data[body].stmt_last ~= 0 then cu.hir_stmts.data[cu.hir_blocks.data[body].stmt_last].next_stmt = ref end
    cu.hir_blocks.data[body].stmt_last = ref
    cu.hir_blocks.data[body].stmt_len = cu.hir_blocks.data[body].stmt_len + 1
    jump scan(slot = cu.semantic_mark)
end
block done()
    if cu.semantic_frames.len ~= 0 then emit @{source_error_at_current}(cu, @{PERR_EXPECTED_END}; error = sem_bad) end
    jump ok()
end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local verify_hir = host.region(V) [[
region verify_hir(cu: ptr(CompileUnit);
                  ok | semantic_error(err: CompileError) | limit_error(err: CompileError))
entry start()
    cu.phase = @{SOURCE_HIR_VERIFY}
    if cu.root_hir_function == 0 then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = bad) end
    if cu.root_hir_function > cu.hir_functions.len then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = bad) end
    let body: index = cu.hir_functions.data[cu.root_hir_function].body
    if body == 0 then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = bad) end
    if body > cu.hir_blocks.len then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = bad) end
    jump verify_function(fn = as(index, 1))
end
block verify_function(fn: index)
    if fn > cu.hir_functions.len then jump ok() end
    let body: index = cu.hir_functions.data[fn].body
    if body == 0 or body > cu.hir_blocks.len then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = bad) end
    jump verify_stmt(i = as(index, 0), n = cu.hir_blocks.data[body].stmt_len, ref = cu.hir_blocks.data[body].stmt_first, next_fn = fn + 1)
end
block verify_stmt(i: index, n: index, ref: index, next_fn: index)
    if i >= n then jump verify_function(fn = next_fn) end
    if ref == 0 or ref > cu.hir_stmts.len then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = bad) end
    jump verify_stmt(i = i + 1, n = n, ref = cu.hir_stmts.data[ref].next_stmt, next_fn = next_fn)
end
block bad(err: CompileError) jump semantic_error(err = err) end
end
]]

return {
    append_scope = append_scope,
    append_symbol = append_symbol,
    append_capture = append_capture,
    append_name_use = append_name_use,
    append_hir_function = append_hir_function,
    append_hir_block = append_hir_block,
    append_hir_stmt = append_hir_stmt,
    append_hir_expr = append_hir_expr,
    push_semantic_frame = push_semantic_frame,
    pop_semantic_frame = pop_semantic_frame,
    resolve_name_use = resolve_name_use,
    compute_capture = compute_capture,
    build_hir_from_parse = build_hir_from_parse,
    verify_hir = verify_hir,
}
