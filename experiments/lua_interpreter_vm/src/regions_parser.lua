-- Lua Interpreter VM — source parser: bytes/tokens -> parse products only.
--
-- This module intentionally contains no direct bytecode emission. Source
-- nesting is represented as ParseNode/ParseFrame products, never as recursive
-- region emits. The only emitted regions here are bounded helpers (lexer and
-- product vector operations).

local moon = require("moonlift")
local host = require("moonlift.host")
local pconst = require("experiments.lua_interpreter_vm.src.parser_constants")
local lexer = require("experiments.lua_interpreter_vm.src.regions_lexer")

local V = {
    lex_next = lexer.lex_next,
}
for k, v in pairs(pconst.Tok) do V["TOK_" .. k] = moon.int(v) end
for k, v in pairs(pconst.Kw) do V["KW_" .. k] = moon.int(v) end
for k, v in pairs(pconst.ParseErr) do V["PERR_" .. k] = moon.int(v) end
for k, v in pairs(pconst.ParseNodeKind) do V["PNODE_" .. k] = moon.int(v) end
for k, v in pairs(pconst.ParseFrameKind) do V["PFRAME_" .. k] = moon.int(v) end
for k, v in pairs(pconst.SourcePhase) do V["SOURCE_" .. k] = moon.int(v) end

local source_error_at_current = host.region(V) [[
region source_error_at_current(cu: ptr(CompileUnit), code: i32;
                              error(err: CompileError))
entry start()
    let tok: Token = cu.lexer.current
    let err: CompileError = {
        code = code,
        pos = { offset = tok.start, line = tok.line, col = 0 },
        token = tok.kind
    }
    jump error(err = err)
end
end
]]

local source_error_at_span = host.region(V) [[
region source_error_at_span(cu: ptr(CompileUnit), code: i32, token: u16, span: SourceSpan;
                           error(err: CompileError))
entry start()
    let err: CompileError = {
        code = code,
        pos = { offset = span.start, line = span.line, col = span.col },
        token = token
    }
    jump error(err = err)
end
end
]]

local append_parse_node = host.region(V) [[
region append_parse_node(cu: ptr(CompileUnit), node: ParseNode;
                         ok(ref: index) | oom)
entry start()
    if cu.parse_nodes.data == nil then jump oom() end
    let ref: index = cu.parse_nodes.len + 1
    if ref >= cu.parse_nodes.cap then jump oom() end
    cu.parse_nodes.data[ref] = node
    cu.parse_nodes.len = ref
    jump ok(ref = ref)
end
end
]]

local append_parse_child = host.region(V) [[
region append_parse_child(cu: ptr(CompileUnit), child_ref: index;
                          ok(slot: index) | oom)
entry start()
    if cu.parse_children.data == nil then jump oom() end
    let slot: index = cu.parse_children.len + 1
    if slot >= cu.parse_children.cap then jump oom() end
    cu.parse_children.data[slot] = child_ref
    cu.parse_children.len = slot
    jump ok(slot = slot)
end
end
]]

local append_parse_function = host.region(V) [[
region append_parse_function(cu: ptr(CompileUnit), fn: ParseFunction;
                             ok(ref: index) | oom)
entry start()
    if cu.parse_functions.data == nil then jump oom() end
    let ref: index = cu.parse_functions.len + 1
    if ref >= cu.parse_functions.cap then jump oom() end
    cu.parse_functions.data[ref] = fn
    cu.parse_functions.len = ref
    jump ok(ref = ref)
end
end
]]

local push_parse_frame = host.region(V) [[
region push_parse_frame(cu: ptr(CompileUnit), frame: ParseFrame;
                        ok | limit_error(err: CompileError) | oom)
entry start()
    if cu.parse_frames.data == nil then jump out_of_mem() end
    let slot: index = cu.parse_frames.len + 1
    if slot >= cu.parse_frames.cap then
        emit source_error_at_span(cu, @{PERR_PARSE_STACK_OVERFLOW}, as(u16, 0), frame.span; error = too_big)
    end
    cu.parse_frames.data[slot] = frame
    cu.parse_frames.len = slot
    jump ok()
end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local pop_parse_frame = host.region(V) [[
region pop_parse_frame(cu: ptr(CompileUnit);
                       popped(frame: ParseFrame) | syntax_error(err: CompileError))
entry start()
    if cu.parse_frames.len == 0 then
        emit source_error_at_current(cu, @{PERR_MALFORMED_PARSE_PRODUCT}; error = bad)
    end
    let slot: index = cu.parse_frames.len
    let frame: ParseFrame = cu.parse_frames.data[slot]
    cu.parse_frames.len = slot - 1
    jump popped(frame = frame)
end
block bad(err: CompileError) jump syntax_error(err = err) end
end
]]

local push_expr_op = host.region(V) [[
region push_expr_op(cu: ptr(CompileUnit), op: ExprOpEntry;
                    ok | limit_error(err: CompileError) | oom)
entry start()
    if cu.expr_ops.data == nil then jump out_of_mem() end
    let slot: index = cu.expr_ops.len + 1
    if slot >= cu.expr_ops.cap then
        emit source_error_at_span(cu, @{PERR_EXPR_STACK_OVERFLOW}, op.op, op.span; error = too_big)
    end
    cu.expr_ops.data[slot] = op
    cu.expr_ops.len = slot
    jump ok()
end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local push_expr_val = host.region(V) [[
region push_expr_val(cu: ptr(CompileUnit), val: ExprValEntry;
                     ok | limit_error(err: CompileError) | oom)
entry start()
    if cu.expr_vals.data == nil then jump out_of_mem() end
    let slot: index = cu.expr_vals.len + 1
    if slot >= cu.expr_vals.cap then
        emit source_error_at_span(cu, @{PERR_EXPR_STACK_OVERFLOW}, as(u16, 0), val.span; error = too_big)
    end
    cu.expr_vals.data[slot] = val
    cu.expr_vals.len = slot
    jump ok()
end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local reduce_expr_once = host.region(V) [[
region reduce_expr_once(cu: ptr(CompileUnit);
                        ok | syntax_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    -- Reserved non-recursive reduction boundary for parser-owned expression
    -- stacks. Current statement/expression HIR construction is performed in
    -- regions_semantic over the parser's typed token products.
    jump ok()
end
end
]]

local parse_source_to_products = host.region(V) [[
region parse_source_to_products(cu: ptr(CompileUnit);
                                ok |
                                syntax_error(err: CompileError) |
                                limit_error(err: CompileError) |
                                oom)
entry start()
    cu.phase = @{SOURCE_PARSE}
    cu.status = 0
    cu.root_parse_function = 0
    cu.parse_nodes.len = 0
    cu.parse_functions.len = 0
    cu.parse_children.len = 0
    cu.parse_frames.len = 0
    cu.expr_ops.len = 0
    cu.expr_vals.len = 0
    let span: SourceSpan = { start = 0, len = cu.lexer.src.len, line = 1, col = 1 }
    let fn: ParseFunction = { parent = 0, root_node = 0, param_first = 0, param_len = 0, child_func_first = 0, child_func_len = 0, flags = 0, reserved = 0, span = span }
    emit append_parse_function(cu, fn; ok = got_root_fn, oom = out_of_mem)
end
block got_root_fn(ref: index)
    cu.root_parse_function = ref
    let span: SourceSpan = { start = 0, len = cu.lexer.src.len, line = 1, col = 1 }
    let node: ParseNode = { kind = as(u16, @{PNODE_CHUNK}), flags = 0, token = as(u16, @{TOK_EOF}), reserved = 0, first_child = 1, child_len = 0, a = 0, b = 0, c = 0, span = span }
    emit append_parse_node(cu, node; ok = got_root_node, oom = out_of_mem)
end
block got_root_node(ref: index)
    cu.parse_functions.data[cu.root_parse_function].root_node = ref
    let span: SourceSpan = { start = 0, len = cu.lexer.src.len, line = 1, col = 1 }
    let frame: ParseFrame = { kind = as(u16, @{PFRAME_CHUNK}), pc = 0, flags = 0, return_seen = 0, reserved = 0, parent = 0, node = ref, function_ref = cu.root_parse_function, block_ref = 0, first_child = 1, child_count = 0, terminator_mask = 0, a = 0, b = 0, c = 0, span = span }
    emit push_parse_frame(cu, frame; ok = frame_ready, limit_error = too_big, oom = out_of_mem)
end
block frame_ready()
    emit @{lex_next}(cu; token = got_token, lexical_error = syntax_bad, oom = out_of_mem)
end
block loop()
    emit @{lex_next}(cu; token = got_token, lexical_error = syntax_bad, oom = out_of_mem)
end
block got_token(tok: Token)
    let span: SourceSpan = { start = tok.start, len = tok.len, line = tok.line, col = 0 }
    if tok.kind == @{TOK_EOF} then jump finish(span = span) end
    let node: ParseNode = { kind = as(u16, @{PNODE_NONE}), flags = 0, token = tok.kind, reserved = 0, first_child = 0, child_len = 0, a = tok.start, b = tok.len, c = as(index, tok.bits), span = span }
    if tok.kind == @{TOK_NAME} then
        let name_node: ParseNode = { kind = as(u16, @{PNODE_NAME}), flags = 0, token = tok.kind, reserved = 0, first_child = 0, child_len = 0, a = tok.start, b = tok.len, c = as(index, tok.bits), span = span }
        emit append_parse_node(cu, name_node; ok = token_node, oom = out_of_mem)
    end
    if tok.kind == @{TOK_INT} then
        let int_node: ParseNode = { kind = as(u16, @{PNODE_INT_EXPR}), flags = 0, token = tok.kind, reserved = 0, first_child = 0, child_len = 0, a = tok.start, b = tok.len, c = as(index, tok.bits), span = span }
        emit append_parse_node(cu, int_node; ok = token_node, oom = out_of_mem)
    end
    if tok.kind == @{TOK_FLOAT} then
        let float_node: ParseNode = { kind = as(u16, @{PNODE_FLOAT_EXPR}), flags = 0, token = tok.kind, reserved = 0, first_child = 0, child_len = 0, a = tok.start, b = tok.len, c = as(index, tok.bits), span = span }
        emit append_parse_node(cu, float_node; ok = token_node, oom = out_of_mem)
    end
    if tok.kind == @{TOK_STRING} then
        let str_node: ParseNode = { kind = as(u16, @{PNODE_STRING_EXPR}), flags = 0, token = tok.kind, reserved = 0, first_child = 0, child_len = 0, a = tok.start, b = tok.len, c = as(index, tok.bits), span = span }
        emit append_parse_node(cu, str_node; ok = token_node, oom = out_of_mem)
    end
    if tok.kind == @{KW_TRUE} or tok.kind == @{KW_FALSE} then
        let bool_node: ParseNode = { kind = as(u16, @{PNODE_BOOL_EXPR}), flags = 0, token = tok.kind, reserved = 0, first_child = 0, child_len = 0, a = tok.start, b = tok.len, c = as(index, tok.bits), span = span }
        emit append_parse_node(cu, bool_node; ok = token_node, oom = out_of_mem)
    end
    if tok.kind == @{KW_NIL} then
        let nil_node: ParseNode = { kind = as(u16, @{PNODE_NIL_EXPR}), flags = 0, token = tok.kind, reserved = 0, first_child = 0, child_len = 0, a = tok.start, b = tok.len, c = as(index, tok.bits), span = span }
        emit append_parse_node(cu, nil_node; ok = token_node, oom = out_of_mem)
    end
    if tok.kind == @{KW_RETURN} then
        let ret_node: ParseNode = { kind = as(u16, @{PNODE_RETURN_STMT}), flags = 0, token = tok.kind, reserved = 0, first_child = 0, child_len = 0, a = tok.start, b = tok.len, c = 0, span = span }
        emit append_parse_node(cu, ret_node; ok = token_node, oom = out_of_mem)
    end
    if tok.kind == @{KW_LOCAL} then
        let local_node: ParseNode = { kind = as(u16, @{PNODE_LOCAL_STMT}), flags = 0, token = tok.kind, reserved = 0, first_child = 0, child_len = 0, a = tok.start, b = tok.len, c = 0, span = span }
        emit append_parse_node(cu, local_node; ok = token_node, oom = out_of_mem)
    end
    emit append_parse_node(cu, node; ok = token_node, oom = out_of_mem)
end
block token_node(ref: index)
    emit append_parse_child(cu, ref; ok = child_added, oom = out_of_mem)
end
block child_added(slot: index)
    let root_node: index = cu.parse_functions.data[cu.root_parse_function].root_node
    cu.parse_nodes.data[root_node].child_len = cu.parse_children.len
    jump loop()
end
block finish(span: SourceSpan)
    let root_node: index = cu.parse_functions.data[cu.root_parse_function].root_node
    cu.parse_nodes.data[root_node].child_len = cu.parse_children.len
    emit pop_parse_frame(cu; popped = popped_root, syntax_error = syntax_bad)
end
block popped_root(frame: ParseFrame)
    jump ok()
end
block syntax_bad(err: CompileError) jump syntax_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local verify_parse_products = host.region(V) [[
region verify_parse_products(cu: ptr(CompileUnit);
                             ok | syntax_error(err: CompileError) | limit_error(err: CompileError))
entry start()
    cu.phase = @{SOURCE_PARSE_VERIFY}
    if cu.root_parse_function == 0 then
        emit source_error_at_current(cu, @{PERR_MALFORMED_PARSE_PRODUCT}; error = bad)
    end
    if cu.root_parse_function > cu.parse_functions.len then
        emit source_error_at_current(cu, @{PERR_MALFORMED_PARSE_PRODUCT}; error = bad)
    end
    if cu.parse_functions.data[cu.root_parse_function].root_node == 0 then
        emit source_error_at_current(cu, @{PERR_MALFORMED_PARSE_PRODUCT}; error = bad)
    end
    if cu.parse_functions.data[cu.root_parse_function].root_node > cu.parse_nodes.len then
        emit source_error_at_current(cu, @{PERR_MALFORMED_PARSE_PRODUCT}; error = bad)
    end
    if cu.parse_frames.len ~= 0 then
        emit source_error_at_current(cu, @{PERR_MALFORMED_PARSE_PRODUCT}; error = bad)
    end
    jump ok()
end
block bad(err: CompileError) jump syntax_error(err = err) end
end
]]

return {
    source_error_at_current = source_error_at_current,
    source_error_at_span = source_error_at_span,
    append_parse_node = append_parse_node,
    append_parse_child = append_parse_child,
    append_parse_function = append_parse_function,
    push_parse_frame = push_parse_frame,
    pop_parse_frame = pop_parse_frame,
    push_expr_op = push_expr_op,
    push_expr_val = push_expr_val,
    reduce_expr_once = reduce_expr_once,
    parse_source_to_products = parse_source_to_products,
    verify_parse_products = verify_parse_products,
}
