-- Lua Interpreter VM — lowering phase: verified HIR -> bytecode/proto.
--
-- Lowering is the only source-compiler phase that may touch FuncBuilder or
-- bytecode. It consumes resolved HIR and emits through regions_codegen. HIR
-- expression nesting is traversed with LowerFrame records, not recursive emits.

local lalin = require("lalin")
local host = require("lalin.host")
local const = require("experiments.lua_interpreter_vm.src.constants")
local pconst = require("experiments.lua_interpreter_vm.src.parser_constants")
local codegen = require("experiments.lua_interpreter_vm.src.regions_codegen")
local parser = require("experiments.lua_interpreter_vm.src.regions_parser")

local V = {
    emit_load_integer = codegen.emit_load_integer,
    emit_load_false = codegen.emit_load_false,
    emit_load_true = codegen.emit_load_true,
    emit_load_nil = codegen.emit_load_nil,
    emit_move = codegen.emit_move,
    emit_loadk = codegen.emit_loadk,
    get_string_constant = codegen.get_string_constant,
    arena_alloc_bytes = codegen.arena_alloc_bytes,
    constant_push = codegen.constant_push,
    upvaldesc_push = codegen.upvaldesc_push,
    proto_ptr_push = codegen.proto_ptr_push,
    ensure_env_upvalue = codegen.ensure_env_upvalue,
    emit_getupval = codegen.emit_getupval,
    emit_setupval = codegen.emit_setupval,
    emit_gettabup = codegen.emit_gettabup,
    emit_settabup = codegen.emit_settabup,
    emit_gettable = codegen.emit_gettable,
    emit_settable = codegen.emit_settable,
    emit_getfield = codegen.emit_getfield,
    emit_setfield = codegen.emit_setfield,
    emit_closure = codegen.emit_closure,
    emit_call = codegen.emit_call,
    emit_vararg = codegen.emit_vararg,
    emit_newtable = codegen.emit_newtable,
    emit_setlist = codegen.emit_setlist,
    emit_add = codegen.emit_add,
    emit_sub = codegen.emit_sub,
    emit_mul = codegen.emit_mul,
    emit_div = codegen.emit_div,
    emit_mod = codegen.emit_mod,
    emit_idiv = codegen.emit_idiv,
    emit_band = codegen.emit_band,
    emit_bor = codegen.emit_bor,
    emit_bxor = codegen.emit_bxor,
    emit_shl = codegen.emit_shl,
    emit_shr = codegen.emit_shr,
    emit_pow = codegen.emit_pow,
    emit_unary_minus = codegen.emit_unary_minus,
    emit_bnot = codegen.emit_bnot,
    emit_not = codegen.emit_not,
    emit_len = codegen.emit_len,
    emit_return0 = codegen.emit_return0,
    emit_return1 = codegen.emit_return1,
    emit_return_n = codegen.emit_return_n,
    emit_test_jump_false = codegen.emit_test_jump_false,
    emit_compare_jump_false = codegen.emit_compare_jump_false,
    emit_jump_placeholder = codegen.emit_jump_placeholder,
    patch_jump_to_current = codegen.patch_jump_to_current,
    patch_jump_to_pc = codegen.patch_jump_to_pc,
    emit_jump_to_pc = codegen.emit_jump_to_pc,
    emit_forprep_placeholder = codegen.emit_forprep_placeholder,
    emit_forloop_patch = codegen.emit_forloop_patch,
    ensure_stack_reg = codegen.ensure_stack_reg,
    add_local = codegen.add_local,
    close_func_builder = codegen.close_func_builder,
    source_error_at_current = parser.source_error_at_current,
    source_error_at_span = parser.source_error_at_span,
}
for k, v in pairs(const.Op) do V["OP_" .. k] = lalin.int(v) end
for k, v in pairs(const.ProtoFlag) do V[k] = lalin.int(v) end
for k, v in pairs(pconst.Tok) do V["TOK_" .. k] = lalin.int(v) end
for k, v in pairs(pconst.Kw) do V["KW_" .. k] = lalin.int(v) end
for k, v in pairs(pconst.ParseErr) do V["PERR_" .. k] = lalin.int(v) end
for k, v in pairs(pconst.SourcePhase) do V["SOURCE_" .. k] = lalin.int(v) end
for k, v in pairs(pconst.HirStmtKind) do V["HSTMT_" .. k] = lalin.int(v) end
for k, v in pairs(pconst.HirExprKind) do V["HEXPR_" .. k] = lalin.int(v) end
for k, v in pairs(pconst.LowerFrameKind) do V["LFRAME_" .. k] = lalin.int(v) end
V.SIZE_PROTO = lalin.int(136)
V.SIZE_FUNC_BUILDER = lalin.int(248)
V.SIZE_INSTR = lalin.int(4)
V.SIZE_VALUE = lalin.int(16)
V.SIZE_UPVALDESC = lalin.int(16)
V.SIZE_PROTO_PTR = lalin.int(8)
V.SIZE_COMPILE_LOCAL = lalin.int(24)
V.CHILD_CODE_CAP = lalin.int(128)
V.CHILD_CONST_CAP = lalin.int(64)
V.CHILD_UPVAL_CAP = lalin.int(16)
V.CHILD_CHILD_CAP = lalin.int(16)
V.CHILD_LOCAL_CAP = lalin.int(32)
V.CHILD_OFF_PROTO = lalin.int(248)
V.CHILD_OFF_CODE = lalin.int(384)
V.CHILD_OFF_CONSTANTS = lalin.int(896)
V.CHILD_OFF_UPVALS = lalin.int(1920)
V.CHILD_OFF_CHILDREN = lalin.int(2176)
V.CHILD_OFF_LOCALS = lalin.int(2304)
V.CHILD_TOTAL = lalin.int(3072)

local push_lower_frame = host.region(V) [[
region push_lower_frame(cu: ptr(CompileUnit), frame: LowerFrame;
                        ok | limit_error(err: CompileError) | oom)
entry start()
    if cu.lower_frames.data == nil then jump out_of_mem() end
    let slot: index = cu.lower_frames.len + 1
    if slot >= cu.lower_frames.cap then
        emit @{source_error_at_span}(cu, @{PERR_INTERNAL_PHASE_ERROR}, as(u16, 0), frame.span; error = too_big)
    end
    cu.lower_frames.data[slot] = frame
    cu.lower_frames.len = slot
    jump ok()
end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local pop_lower_frame = host.region(V) [[
region pop_lower_frame(cu: ptr(CompileUnit);
                       popped(frame: LowerFrame) | semantic_error(err: CompileError))
entry start()
    if cu.lower_frames.len == 0 then emit @{source_error_at_current}(cu, @{PERR_INTERNAL_PHASE_ERROR}; error = bad) end
    let slot: index = cu.lower_frames.len
    let frame: LowerFrame = cu.lower_frames.data[slot]
    cu.lower_frames.len = slot - 1
    jump popped(frame = frame)
end
block bad(err: CompileError) jump semantic_error(err = err) end
end
]]

local push_lower_scope = host.region(V) [[
region push_lower_scope(cu: ptr(CompileUnit), scope: LowerScope;
                        ok | limit_error(err: CompileError) | oom)
entry start()
    if cu.lower_scopes.data == nil then jump out_of_mem() end
    let slot: index = cu.lower_scopes.len + 1
    if slot >= cu.lower_scopes.cap then emit @{source_error_at_current}(cu, @{PERR_INTERNAL_PHASE_ERROR}; error = too_big) end
    cu.lower_scopes.data[slot] = scope
    cu.lower_scopes.len = slot
    jump ok()
end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local pop_lower_scope = host.region(V) [[
region pop_lower_scope(cu: ptr(CompileUnit);
                       popped(scope: LowerScope) | semantic_error(err: CompileError))
entry start()
    if cu.lower_scopes.len == 0 then emit @{source_error_at_current}(cu, @{PERR_INTERNAL_PHASE_ERROR}; error = bad) end
    let slot: index = cu.lower_scopes.len
    let scope: LowerScope = cu.lower_scopes.data[slot]
    cu.lower_scopes.len = slot - 1
    jump popped(scope = scope)
end
block bad(err: CompileError) jump semantic_error(err = err) end
end
]]

local push_patch = host.region(V) [[
region push_patch(cu: ptr(CompileUnit), patch: PatchRec;
                  ok(ref: index) | oom)
entry start()
    if cu.patches.data == nil then jump oom() end
    let ref: index = cu.patches.len + 1
    if ref >= cu.patches.cap then jump oom() end
    cu.patches.data[ref] = patch
    cu.patches.len = ref
    jump ok(ref = ref)
end
end
]]

local patch_pending = host.region(V) [[
region patch_pending(cu: ptr(CompileUnit), target_stmt: index;
                     ok | limit_error(err: CompileError))
entry start()
    if cu.patches.len == 0 then jump ok() end
    jump scan(i = as(index, 1))
end
block scan(i: index)
    if i > cu.patches.len then jump ok() end
    let p: PatchRec = cu.patches.data[i]
    if p.target == target_stmt and p.flags == 0 then jump patch_one(i = i, pc = p.pc) end
    jump scan(i = i + 1)
end
block patch_one(i: index, pc: index)
    cu.status = as(u16, i)
    emit @{patch_jump_to_current}(cu, pc; ok = patched)
end
block patched()
    jump scan(i = as(index, cu.status) + 1)
end
end
]]

local lower_compare_bool = host.region(V) [[
region lower_compare_bool(cu: ptr(CompileUnit), op: u16, expect: u16, dst: u16, lhs: u16, rhs: u16;
                          ok | limit_error(err: CompileError) | oom)
entry start()
    emit @{emit_compare_jump_false}(cu, op, expect, lhs, rhs;
        emitted = got_false_jump, limit_error = too_big, oom = out_of_mem)
end
block got_false_jump(jmp_pc: index)
    cu.durable_mark = jmp_pc
    emit @{emit_load_true}(cu, dst; ok = true_loaded, limit_error = too_big, oom = out_of_mem)
end
block true_loaded()
    emit @{emit_jump_placeholder}(cu; emitted = got_after_jump, limit_error = too_big, oom = out_of_mem)
end
block got_after_jump(pc: index)
    cu.parse_mark = pc
    emit @{patch_jump_to_current}(cu, cu.durable_mark; ok = false_target_ready)
end
block false_target_ready()
    emit @{emit_load_false}(cu, dst; ok = false_loaded, limit_error = too_big, oom = out_of_mem)
end
block false_loaded()
    emit @{patch_jump_to_current}(cu, cu.parse_mark; ok = done)
end
block done() jump ok() end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local lower_binary_op = host.region(V) [[
region lower_binary_op(cu: ptr(CompileUnit), op: u16, dst: u16, lhs: u16, rhs: u16;
                       ok | semantic_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    if op == @{TOK_PLUS} then emit @{emit_add}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_MINUS} then emit @{emit_sub}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_STAR} then emit @{emit_mul}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_SLASH} then emit @{emit_div}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_PERCENT} then emit @{emit_mod}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_SLASHSLASH} then emit @{emit_idiv}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_CARET} then emit @{emit_pow}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_AMP} then emit @{emit_band}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_PIPE} then emit @{emit_bor}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_TILDE} then emit @{emit_bxor}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_LTLT} then emit @{emit_shl}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_GTGT} then emit @{emit_shr}(cu, dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_EQ} then emit lower_compare_bool(cu, as(u16, @{OP_EQ}), as(u16, 1), dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_NE} then emit lower_compare_bool(cu, as(u16, @{OP_EQ}), as(u16, 0), dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_LT} then emit lower_compare_bool(cu, as(u16, @{OP_LT}), as(u16, 1), dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_LE} then emit lower_compare_bool(cu, as(u16, @{OP_LE}), as(u16, 1), dst, lhs, rhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_GT} then emit lower_compare_bool(cu, as(u16, @{OP_LT}), as(u16, 1), dst, rhs, lhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_GE} then emit lower_compare_bool(cu, as(u16, @{OP_LE}), as(u16, 1), dst, rhs, lhs; ok = done, limit_error = too_big, oom = out_of_mem) end
    emit @{source_error_at_current}(cu, @{PERR_UNSUPPORTED_SOURCE}; error = sem_bad)
end
block done() jump ok() end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local lower_unary_op = host.region(V) [[
region lower_unary_op(cu: ptr(CompileUnit), op: u16, dst: u16, src: u16;
                      ok | semantic_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    if op == @{TOK_MINUS} then emit @{emit_unary_minus}(cu, dst, src; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_TILDE} then emit @{emit_bnot}(cu, dst, src; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{KW_NOT} then emit @{emit_not}(cu, dst, src; ok = done, limit_error = too_big, oom = out_of_mem) end
    if op == @{TOK_HASH} then emit @{emit_len}(cu, dst, src; ok = done, limit_error = too_big, oom = out_of_mem) end
    emit @{source_error_at_current}(cu, @{PERR_UNSUPPORTED_SOURCE}; error = sem_bad)
end
block done() jump ok() end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local lower_expr = host.region(V) [[
region lower_expr(cu: ptr(CompileUnit), expr_ref: index, target: u16;
                  ok | semantic_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    cu.lower_frames.len = 0
    if expr_ref == 0 then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = sem_bad) end
    if expr_ref > cu.hir_exprs.len then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = sem_bad) end
    let e: HirExpr = cu.hir_exprs.data[expr_ref]
    let frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = expr_ref, function_ref = cu.root_hir_function, target_reg = target, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = e.span }
    emit push_lower_frame(cu, frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block loop()
    if cu.lower_frames.len == 0 then jump ok() end
    let slot: index = cu.lower_frames.len
    let frame: LowerFrame = cu.lower_frames.data[slot]
    let ex: HirExpr = cu.hir_exprs.data[frame.hir_ref]
    if frame.pc == 0 then jump dispatch(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 10 then jump finish_unary(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 20 then jump push_rhs(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 21 then jump finish_binary(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 30 then jump push_index_key(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 31 then jump finish_index(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 40 then jump finish_field(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 50 then jump table_items(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 51 then jump table_key_ready(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 52 then jump table_value_ready(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 60 then jump call_args(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 61 then jump call_args(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 70 then jump method_receiver_ready(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 71 then jump method_args(slot = slot, frame = frame, ex = ex) end
    if frame.pc == 72 then jump method_args(slot = slot, frame = frame, ex = ex) end
    emit @{source_error_at_span}(cu, @{PERR_INTERNAL_PHASE_ERROR}, ex.op, ex.span; error = sem_bad)
end
block dispatch(slot: index, frame: LowerFrame, ex: HirExpr)
    emit @{ensure_stack_reg}(cu, frame.target_reg; ok = stack_ok, limit_error = too_big)
end
block stack_ok()
    let slot: index = cu.lower_frames.len
    let frame: LowerFrame = cu.lower_frames.data[slot]
    let ex: HirExpr = cu.hir_exprs.data[frame.hir_ref]
    if ex.kind == @{HEXPR_INTEGER} then emit @{emit_load_integer}(cu, frame.target_reg, as(i64, ex.value.bits); ok = pop_done, limit_error = too_big, oom = out_of_mem) end
    if ex.kind == @{HEXPR_BOOL} then jump bool_expr(frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_NIL} then emit @{emit_load_nil}(cu, frame.target_reg; ok = pop_done, limit_error = too_big, oom = out_of_mem) end
    if ex.kind == @{HEXPR_STRING} then jump string_expr(frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_LOCAL} then jump local_expr(frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_GLOBAL} then jump global_expr(frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_UPVALUE} then jump upvalue_expr(frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_CLOSURE} then jump closure_expr(frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_VARARG} then jump vararg_expr(frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_UNARY} then jump unary_expr(slot = slot, frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_BINARY} then jump binary_expr(slot = slot, frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_TABLE} then jump table_expr(slot = slot, frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_INDEX} then jump index_expr(slot = slot, frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_FIELD} then jump field_expr(slot = slot, frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_CALL} then jump call_expr(slot = slot, frame = frame, ex = ex) end
    if ex.kind == @{HEXPR_METHOD_CALL} then jump method_expr(slot = slot, frame = frame, ex = ex) end
    emit @{source_error_at_span}(cu, @{PERR_UNSUPPORTED_SOURCE}, ex.op, ex.span; error = sem_bad)
end
block bool_expr(frame: LowerFrame, ex: HirExpr)
    if ex.a == 0 then emit @{emit_load_false}(cu, frame.target_reg; ok = pop_done, limit_error = too_big, oom = out_of_mem) end
    emit @{emit_load_true}(cu, frame.target_reg; ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block local_expr(frame: LowerFrame, ex: HirExpr)
    if ex.a == 0 or ex.a > cu.symbols.len then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, ex.op, ex.span; error = sem_bad) end
    let sym: SymbolRec = cu.symbols.data[ex.a]
    emit @{emit_move}(cu, frame.target_reg, sym.local_index; ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block string_expr(frame: LowerFrame, ex: HirExpr)
    emit @{get_string_constant}(cu, ex.a, ex.b; ok = got_loadk_string, oom = out_of_mem)
end
block got_loadk_string(idx: index)
    let slot: index = cu.lower_frames.len
    let frame: LowerFrame = cu.lower_frames.data[slot]
    emit @{emit_loadk}(cu, frame.target_reg, idx; ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block global_expr(frame: LowerFrame, ex: HirExpr)
    emit @{ensure_env_upvalue}(cu; ok = env_ready_for_get, oom = out_of_mem)
end
block env_ready_for_get()
    let slot: index = cu.lower_frames.len
    let frame: LowerFrame = cu.lower_frames.data[slot]
    let ex: HirExpr = cu.hir_exprs.data[frame.hir_ref]
    emit @{get_string_constant}(cu, ex.a, ex.b; ok = got_global_key, oom = out_of_mem)
end
block got_global_key(idx: index)
    let slot: index = cu.lower_frames.len
    let frame: LowerFrame = cu.lower_frames.data[slot]
    emit @{emit_gettabup}(cu, frame.target_reg, as(u16, 0), idx; ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block upvalue_expr(frame: LowerFrame, ex: HirExpr)
    if ex.a == 0 or ex.a > cu.captures.len then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, ex.op, ex.span; error = sem_bad) end
    let cap: CaptureRec = cu.captures.data[ex.a]
    emit @{emit_getupval}(cu, frame.target_reg, cap.upvalue_index; ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block closure_expr(frame: LowerFrame, ex: HirExpr)
    if ex.a == 0 or ex.a > cu.hir_functions.len then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, ex.op, ex.span; error = sem_bad) end
    let child: HirFunction = cu.hir_functions.data[ex.a]
    emit @{emit_closure}(cu, frame.target_reg, child.nested_first; ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block vararg_expr(frame: LowerFrame, ex: HirExpr)
    emit @{emit_vararg}(cu, frame.target_reg, as(u16, 1); ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block unary_expr(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 10
    let child: HirExpr = cu.hir_exprs.data[ex.a]
    let child_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = ex.a, function_ref = frame.function_ref, target_reg = frame.target_reg, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = child.span }
    emit push_lower_frame(cu, child_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block binary_expr(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 20
    let lhs_reg: u16 = cu.current.freereg
    cu.lower_frames.data[slot].a = as(index, lhs_reg)
    let child: HirExpr = cu.hir_exprs.data[ex.a]
    let child_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = ex.a, function_ref = frame.function_ref, target_reg = lhs_reg, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = child.span }
    emit push_lower_frame(cu, child_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block push_rhs(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 21
    let rhs_reg: u16 = as(u16, frame.a) + 1
    cu.lower_frames.data[slot].b = as(index, rhs_reg)
    let child: HirExpr = cu.hir_exprs.data[ex.b]
    let child_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = ex.b, function_ref = frame.function_ref, target_reg = rhs_reg, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = child.span }
    emit push_lower_frame(cu, child_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block index_expr(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 30
    let child: HirExpr = cu.hir_exprs.data[ex.a]
    let child_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = ex.a, function_ref = frame.function_ref, target_reg = frame.target_reg, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = child.span }
    emit push_lower_frame(cu, child_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block push_index_key(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 31
    let key_reg: u16 = frame.target_reg + 1
    let child: HirExpr = cu.hir_exprs.data[ex.b]
    let child_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = ex.b, function_ref = frame.function_ref, target_reg = key_reg, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = child.span }
    emit push_lower_frame(cu, child_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block finish_index(slot: index, frame: LowerFrame, ex: HirExpr)
    emit @{emit_gettable}(cu, frame.target_reg, frame.target_reg, frame.target_reg + 1; ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block field_expr(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 40
    let child: HirExpr = cu.hir_exprs.data[ex.a]
    let child_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = ex.a, function_ref = frame.function_ref, target_reg = frame.target_reg, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = child.span }
    emit push_lower_frame(cu, child_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block finish_field(slot: index, frame: LowerFrame, ex: HirExpr)
    emit @{get_string_constant}(cu, ex.b, ex.c; ok = field_key_ready, oom = out_of_mem)
end
block field_key_ready(idx: index)
    let slot: index = cu.lower_frames.len
    let frame: LowerFrame = cu.lower_frames.data[slot]
    emit @{emit_getfield}(cu, frame.target_reg, frame.target_reg, idx; ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block table_expr(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 50
    cu.lower_frames.data[slot].a = ex.a
    cu.lower_frames.data[slot].b = 0
    cu.lower_frames.data[slot].c = ex.b
    emit @{emit_newtable}(cu, frame.target_reg, as(u16, ex.b); ok = table_created, limit_error = too_big, oom = out_of_mem)
end
block table_created()
    jump loop()
end
block table_items(slot: index, frame: LowerFrame, ex: HirExpr)
    if frame.b >= frame.c then jump table_finish(slot = slot, frame = frame, ex = ex) end
    if frame.a == 0 then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), ex.span; error = sem_bad) end
    let item: HirExpr = cu.hir_exprs.data[frame.a]
    if item.kind ~= @{HEXPR_TABLE_ITEM} then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), item.span; error = sem_bad) end
    cu.lower_frames.data[slot].patch_base = frame.a
    cu.lower_frames.data[slot].a = item.next
    cu.lower_frames.data[slot].b = frame.b + 1
    if item.flags ~= 0 then jump table_array_key(slot = slot, frame = frame, item = item) end
    cu.lower_frames.data[slot].pc = 51
    let key: HirExpr = cu.hir_exprs.data[item.a]
    let key_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = item.a, function_ref = frame.function_ref, target_reg = frame.target_reg + 1, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = key.span }
    emit push_lower_frame(cu, key_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block table_array_key(slot: index, frame: LowerFrame, item: HirExpr)
    cu.lower_frames.data[slot].pc = 51
    emit @{emit_load_integer}(cu, frame.target_reg + 1, as(i64, item.c); ok = table_key_ready_now, limit_error = too_big, oom = out_of_mem)
end
block table_key_ready_now()
    jump loop()
end
block table_key_ready(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 52
    let item: HirExpr = cu.hir_exprs.data[frame.patch_base]
    let val: HirExpr = cu.hir_exprs.data[item.b]
    let val_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = item.b, function_ref = frame.function_ref, target_reg = frame.target_reg + 2, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = val.span }
    emit push_lower_frame(cu, val_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block table_value_ready(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 50
    emit @{emit_settable}(cu, frame.target_reg + 2, frame.target_reg, frame.target_reg + 1; ok = table_item_stored, limit_error = too_big, oom = out_of_mem)
end
block table_item_stored()
    jump loop()
end
block table_finish(slot: index, frame: LowerFrame, ex: HirExpr)
    jump pop_done()
end
block call_expr(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 60
    cu.lower_frames.data[slot].a = ex.b
    cu.lower_frames.data[slot].b = 0
    cu.lower_frames.data[slot].c = ex.c
    let child: HirExpr = cu.hir_exprs.data[ex.a]
    let child_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = ex.a, function_ref = frame.function_ref, target_reg = frame.target_reg, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = child.span }
    emit push_lower_frame(cu, child_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block call_args(slot: index, frame: LowerFrame, ex: HirExpr)
    if frame.b >= frame.c then jump call_finish(slot = slot, frame = frame, ex = ex) end
    if frame.a == 0 then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), ex.span; error = sem_bad) end
    let arg: HirExpr = cu.hir_exprs.data[frame.a]
    cu.lower_frames.data[slot].pc = 61
    cu.lower_frames.data[slot].a = arg.next
    cu.lower_frames.data[slot].b = frame.b + 1
    let arg_reg: u16 = frame.target_reg + 1 + as(u16, frame.b)
    let child_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = frame.a, function_ref = frame.function_ref, target_reg = arg_reg, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = arg.span }
    emit push_lower_frame(cu, child_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block call_finish(slot: index, frame: LowerFrame, ex: HirExpr)
    emit @{emit_call}(cu, frame.target_reg, as(u16, frame.c), as(u16, 1); ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block method_expr(slot: index, frame: LowerFrame, ex: HirExpr)
    cu.lower_frames.data[slot].pc = 70
    cu.lower_frames.data[slot].a = ex.next
    cu.lower_frames.data[slot].b = 0
    cu.lower_frames.data[slot].c = as(index, ex.flags)
    let recv: HirExpr = cu.hir_exprs.data[ex.a]
    let recv_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = ex.a, function_ref = frame.function_ref, target_reg = frame.target_reg + 1, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = recv.span }
    emit push_lower_frame(cu, recv_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block method_receiver_ready(slot: index, frame: LowerFrame, ex: HirExpr)
    emit @{get_string_constant}(cu, ex.b, ex.c; ok = method_key_ready_const, oom = out_of_mem)
end
block method_key_ready_const(idx: index)
    let slot: index = cu.lower_frames.len
    let frame: LowerFrame = cu.lower_frames.data[slot]
    cu.lower_frames.data[slot].pc = 71
    emit @{emit_getfield}(cu, frame.target_reg, frame.target_reg + 1, idx; ok = method_callee_ready, limit_error = too_big, oom = out_of_mem)
end
block method_callee_ready()
    jump loop()
end
block method_args(slot: index, frame: LowerFrame, ex: HirExpr)
    if frame.b >= frame.c then jump method_finish(slot = slot, frame = frame, ex = ex) end
    if frame.a == 0 then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), ex.span; error = sem_bad) end
    let arg: HirExpr = cu.hir_exprs.data[frame.a]
    cu.lower_frames.data[slot].pc = 72
    cu.lower_frames.data[slot].a = arg.next
    cu.lower_frames.data[slot].b = frame.b + 1
    let arg_reg: u16 = frame.target_reg + 2 + as(u16, frame.b)
    let child_frame: LowerFrame = { kind = as(u16, @{LFRAME_EXPR}), pc = 0, flags = 0, reserved = 0, hir_ref = frame.a, function_ref = frame.function_ref, target_reg = arg_reg, result_count = 1, patch_base = 0, a = 0, b = 0, c = 0, span = arg.span }
    emit push_lower_frame(cu, child_frame; ok = loop, limit_error = too_big, oom = out_of_mem)
end
block method_finish(slot: index, frame: LowerFrame, ex: HirExpr)
    emit @{emit_call}(cu, frame.target_reg, as(u16, frame.c + 1), as(u16, 1); ok = pop_done, limit_error = too_big, oom = out_of_mem)
end
block finish_unary(slot: index, frame: LowerFrame, ex: HirExpr)
    emit lower_unary_op(cu, ex.op, frame.target_reg, frame.target_reg; ok = pop_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block finish_binary(slot: index, frame: LowerFrame, ex: HirExpr)
    emit lower_binary_op(cu, ex.op, frame.target_reg, as(u16, frame.a), as(u16, frame.b); ok = pop_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block pop_done()
    cu.lower_frames.len = cu.lower_frames.len - 1
    jump loop()
end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local lower_stmt = host.region(V) [[
region lower_stmt(cu: ptr(CompileUnit), stmt_ref: index;
                  ok | returned | semantic_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    if stmt_ref == 0 or stmt_ref > cu.hir_stmts.len then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = sem_bad) end
    cu.lower_mark = stmt_ref
    cu.hir_stmts.data[stmt_ref].pc = cu.current.code.len
    emit patch_pending(cu, stmt_ref; ok = patched_start, limit_error = too_big)
end
block patched_start()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    if stmt.kind == @{HSTMT_LOCAL} then jump local_stmt(stmt = stmt) end
    if stmt.kind == @{HSTMT_ASSIGN} then jump assign_stmt(stmt = stmt) end
    if stmt.kind == @{HSTMT_RETURN} then jump return_stmt(stmt = stmt) end
    if stmt.kind == @{HSTMT_IF} then jump cond_stmt(stmt = stmt) end
    if stmt.kind == @{HSTMT_WHILE} then jump cond_stmt(stmt = stmt) end
    if stmt.kind == @{HSTMT_GOTO} then jump goto_stmt(stmt = stmt) end
    if stmt.kind == @{HSTMT_REPEAT} then jump repeat_stmt(stmt = stmt) end
    if stmt.kind == @{HSTMT_FOR_NUM} then jump for_num_stmt(stmt = stmt) end
    if stmt.kind == @{HSTMT_CALL} then jump call_stmt(stmt = stmt) end
    emit @{source_error_at_span}(cu, @{PERR_UNSUPPORTED_SOURCE}, as(u16, 0), stmt.span; error = sem_bad)
end
block local_stmt(stmt: HirStmt)
    if stmt.a == 0 or stmt.a > cu.symbols.len then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), stmt.span; error = sem_bad) end
    let sym: SymbolRec = cu.symbols.data[stmt.a]
    emit @{ensure_stack_reg}(cu, sym.local_index; ok = local_stack_ok, limit_error = too_big)
end
block local_stack_ok()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let sym: SymbolRec = cu.symbols.data[stmt.a]
    if stmt.b == 0 then emit @{emit_load_nil}(cu, sym.local_index; ok = local_loaded, limit_error = too_big, oom = out_of_mem) end
    emit lower_expr(cu, stmt.b, sym.local_index; ok = local_loaded, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block local_loaded()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let sym: SymbolRec = cu.symbols.data[stmt.a]
    let tok: Token = { kind = as(u16, @{TOK_NAME}), start = sym.name_start, len = sym.name_len, line = sym.span.line, aux = 0, bits = 0 }
    emit @{add_local}(cu, tok, sym.local_index; ok = done, limit_error = too_big)
end
block assign_stmt(stmt: HirStmt)
    if stmt.flags == 0 then jump assign_legacy_local(stmt = stmt) end
    if stmt.a == 0 or stmt.a > cu.hir_exprs.len then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), stmt.span; error = sem_bad) end
    let lv: HirExpr = cu.hir_exprs.data[stmt.a]
    if lv.kind == @{HEXPR_LOCAL} then jump assign_local_lvalue(stmt = stmt, lv = lv) end
    if lv.kind == @{HEXPR_UPVALUE} then jump assign_upvalue_lvalue(stmt = stmt, lv = lv) end
    if lv.kind == @{HEXPR_GLOBAL} then jump assign_global_lvalue(stmt = stmt, lv = lv) end
    if lv.kind == @{HEXPR_INDEX} then jump assign_index_lvalue(stmt = stmt, lv = lv) end
    if lv.kind == @{HEXPR_FIELD} then jump assign_field_lvalue(stmt = stmt, lv = lv) end
    emit @{source_error_at_span}(cu, @{PERR_INVALID_ASSIGN_TARGET}, as(u16, 0), lv.span; error = sem_bad)
end
block assign_legacy_local(stmt: HirStmt)
    if stmt.a == 0 or stmt.a > cu.symbols.len then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), stmt.span; error = sem_bad) end
    let sym: SymbolRec = cu.symbols.data[stmt.a]
    emit lower_expr(cu, stmt.b, sym.local_index; ok = done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block assign_local_lvalue(stmt: HirStmt, lv: HirExpr)
    if lv.a == 0 or lv.a > cu.symbols.len then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), lv.span; error = sem_bad) end
    let sym: SymbolRec = cu.symbols.data[lv.a]
    emit lower_expr(cu, stmt.b, sym.local_index; ok = done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block assign_upvalue_lvalue(stmt: HirStmt, lv: HirExpr)
    if lv.a == 0 or lv.a > cu.captures.len then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), lv.span; error = sem_bad) end
    let r: u16 = cu.current.freereg
    cu.hir_stmts.data[cu.lower_mark].d = as(index, r)
    emit lower_expr(cu, stmt.b, r; ok = assign_upvalue_value, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block assign_upvalue_value()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let lv: HirExpr = cu.hir_exprs.data[stmt.a]
    let cap: CaptureRec = cu.captures.data[lv.a]
    emit @{emit_setupval}(cu, as(u16, stmt.d), cap.upvalue_index; ok = done, limit_error = too_big, oom = out_of_mem)
end
block assign_global_lvalue(stmt: HirStmt, lv: HirExpr)
    let r: u16 = cu.current.freereg
    cu.hir_stmts.data[cu.lower_mark].d = as(index, r)
    emit lower_expr(cu, stmt.b, r; ok = assign_global_value, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block assign_global_value()
    emit @{ensure_env_upvalue}(cu; ok = assign_global_env_ready, oom = out_of_mem)
end
block assign_global_env_ready()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let lv: HirExpr = cu.hir_exprs.data[stmt.a]
    emit @{get_string_constant}(cu, lv.a, lv.b; ok = assign_global_key, oom = out_of_mem)
end
block assign_global_key(idx: index)
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    emit @{emit_settabup}(cu, as(u16, 0), idx, as(u16, stmt.d); ok = done, limit_error = too_big, oom = out_of_mem)
end
block assign_index_lvalue(stmt: HirStmt, lv: HirExpr)
    let base: u16 = cu.current.freereg
    cu.hir_stmts.data[cu.lower_mark].d = as(index, base)
    emit lower_expr(cu, lv.a, base; ok = assign_index_table, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block assign_index_table()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let lv: HirExpr = cu.hir_exprs.data[stmt.a]
    emit lower_expr(cu, lv.b, as(u16, stmt.d) + 1; ok = assign_index_key_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block assign_index_key_done()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    emit lower_expr(cu, stmt.b, as(u16, stmt.d) + 2; ok = assign_index_value_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block assign_index_value_done()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let base: u16 = as(u16, stmt.d)
    emit @{emit_settable}(cu, base + 2, base, base + 1; ok = done, limit_error = too_big, oom = out_of_mem)
end
block assign_field_lvalue(stmt: HirStmt, lv: HirExpr)
    let base: u16 = cu.current.freereg
    cu.hir_stmts.data[cu.lower_mark].d = as(index, base)
    emit lower_expr(cu, lv.a, base; ok = assign_field_table, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block assign_field_table()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    emit lower_expr(cu, stmt.b, as(u16, stmt.d) + 1; ok = assign_field_value_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block assign_field_value_done()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let lv: HirExpr = cu.hir_exprs.data[stmt.a]
    emit @{get_string_constant}(cu, lv.b, lv.c; ok = assign_field_key, oom = out_of_mem)
end
block assign_field_key(idx: index)
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let base: u16 = as(u16, stmt.d)
    emit @{emit_setfield}(cu, base, idx, base + 1; ok = done, limit_error = too_big, oom = out_of_mem)
end
block call_stmt(stmt: HirStmt)
    let r: u16 = cu.current.freereg
    emit lower_expr(cu, stmt.a, r; ok = done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block return_stmt(stmt: HirStmt)
    if stmt.a == 0 then emit @{emit_return0}(cu; ok = done, limit_error = too_big, oom = out_of_mem) end
    let ret_base: u16 = cu.current.freereg
    cu.hir_stmts.data[cu.lower_mark].c = as(index, ret_base)
    cu.hir_stmts.data[cu.lower_mark].d = stmt.a
    cu.hir_stmts.data[cu.lower_mark].e = 0
    emit lower_expr(cu, stmt.a, ret_base; ok = return_expr_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block return_expr_done()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let done_count: index = stmt.e + 1
    if done_count >= stmt.b then jump return_move_results() end
    let cur: HirExpr = cu.hir_exprs.data[stmt.d]
    if cur.next == 0 then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), stmt.span; error = sem_bad) end
    cu.hir_stmts.data[cu.lower_mark].d = cur.next
    cu.hir_stmts.data[cu.lower_mark].e = done_count
    emit lower_expr(cu, cur.next, as(u16, stmt.c + done_count); ok = return_expr_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block return_move_results()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    if stmt.c == 0 then emit @{emit_return_n}(cu, as(u16, 0), as(u16, stmt.b); ok = done, limit_error = too_big, oom = out_of_mem) end
    jump return_move_loop(i = as(index, 0))
end
block return_move_loop(i: index)
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    if i >= stmt.b then emit @{emit_return_n}(cu, as(u16, 0), as(u16, stmt.b); ok = done, limit_error = too_big, oom = out_of_mem) end
    cu.durable_mark = i
    emit @{emit_move}(cu, as(u16, i), as(u16, stmt.c + i); ok = return_moved_one, limit_error = too_big, oom = out_of_mem)
end
block return_moved_one()
    jump return_move_loop(i = cu.durable_mark + 1)
end
block cond_stmt(stmt: HirStmt)
    if stmt.a == 0 or stmt.b == 0 then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), stmt.span; error = sem_bad) end
    let r: u16 = cu.current.freereg
    cu.hir_stmts.data[cu.lower_mark].d = as(index, r)
    emit lower_expr(cu, stmt.a, r; ok = cond_loaded, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block cond_loaded()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    emit @{emit_test_jump_false}(cu, as(u16, stmt.d); emitted = got_cond_jump, limit_error = too_big, oom = out_of_mem)
end
block got_cond_jump(jmp_pc: index)
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let patch: PatchRec = { kind = 0, flags = 0, pc = jmp_pc, target = stmt.b, next = 0, span = stmt.span }
    emit push_patch(cu, patch; ok = cond_patch_saved, oom = out_of_mem)
end
block cond_patch_saved(ref: index) jump done() end
block goto_stmt(stmt: HirStmt)
    if stmt.flags == 2 then jump for_end(stmt = stmt) end
    if stmt.a == 0 then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), stmt.span; error = sem_bad) end
    if stmt.a < cu.lower_mark then jump goto_back(target = stmt.a) end
    emit @{emit_jump_placeholder}(cu; emitted = got_goto_jump, limit_error = too_big, oom = out_of_mem)
end
block goto_back(target: index)
    let pc: index = cu.hir_stmts.data[target].pc
    emit @{emit_jump_to_pc}(cu, pc; ok = done, limit_error = too_big, oom = out_of_mem)
end
block got_goto_jump(pc: index)
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let patch: PatchRec = { kind = 0, flags = 0, pc = pc, target = stmt.a, next = 0, span = stmt.span }
    emit push_patch(cu, patch; ok = goto_patch_saved, oom = out_of_mem)
end
block goto_patch_saved(ref: index) jump done() end
block repeat_stmt(stmt: HirStmt)
    if stmt.a == 0 or stmt.b == 0 then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), stmt.span; error = sem_bad) end
    let r: u16 = cu.current.freereg
    cu.hir_stmts.data[cu.lower_mark].d = as(index, r)
    emit lower_expr(cu, stmt.a, r; ok = repeat_cond_loaded, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block repeat_cond_loaded()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    emit @{emit_test_jump_false}(cu, as(u16, stmt.d); emitted = got_repeat_jump, limit_error = too_big, oom = out_of_mem)
end
block got_repeat_jump(jmp_pc: index)
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    if stmt.b < cu.lower_mark then jump repeat_back(jmp_pc = jmp_pc, target = stmt.b) end
    let patch: PatchRec = { kind = 0, flags = 0, pc = jmp_pc, target = stmt.b, next = 0, span = stmt.span }
    emit push_patch(cu, patch; ok = repeat_patch_saved, oom = out_of_mem)
end
block repeat_back(jmp_pc: index, target: index)
    let pc: index = cu.hir_stmts.data[target].pc
    emit @{patch_jump_to_pc}(cu, jmp_pc, pc; ok = done)
end
block repeat_patch_saved(ref: index) jump done() end
block for_num_stmt(stmt: HirStmt)
    if stmt.a == 0 or stmt.b == 0 or stmt.c == 0 or stmt.d == 0 then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), stmt.span; error = sem_bad) end
    let base: u16 = cu.current.freereg
    cu.hir_stmts.data[cu.lower_mark].e = as(index, base)
    cu.symbols.data[stmt.a].local_index = base + 3
    emit @{ensure_stack_reg}(cu, base + 3; ok = for_stack_ok, limit_error = too_big)
end
block for_stack_ok()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    let sym: SymbolRec = cu.symbols.data[stmt.a]
    let tok: Token = { kind = as(u16, @{TOK_NAME}), start = sym.name_start, len = sym.name_len, line = sym.span.line, aux = 0, bits = 0 }
    emit @{add_local}(cu, tok, sym.local_index; ok = for_local_added, limit_error = too_big)
end
block for_local_added()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    emit lower_expr(cu, stmt.b, as(u16, stmt.e); ok = for_init_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block for_init_done()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    emit lower_expr(cu, stmt.c, as(u16, stmt.e) + 1; ok = for_limit_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block for_limit_done()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    emit lower_expr(cu, stmt.d, as(u16, stmt.e) + 2; ok = for_step_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block for_step_done()
    let stmt: HirStmt = cu.hir_stmts.data[cu.lower_mark]
    emit @{emit_forprep_placeholder}(cu, as(u16, stmt.e); emitted = got_forprep, limit_error = too_big, oom = out_of_mem)
end
block got_forprep(pc: index)
    cu.hir_stmts.data[cu.lower_mark].pc = pc
    jump done()
end
block for_end(stmt: HirStmt)
    if stmt.a == 0 or stmt.a > cu.hir_stmts.len then emit @{source_error_at_span}(cu, @{PERR_MALFORMED_HIR}, as(u16, 0), stmt.span; error = sem_bad) end
    let start_stmt: HirStmt = cu.hir_stmts.data[stmt.a]
    emit @{emit_forloop_patch}(cu, as(u16, start_stmt.e), start_stmt.pc; ok = done, limit_error = too_big, oom = out_of_mem)
end
block done() jump ok() end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local lower_block = host.region(V) [[
region lower_block(cu: ptr(CompileUnit), block_ref: index;
                   ok(returned: u8) | semantic_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    if block_ref == 0 or block_ref > cu.hir_blocks.len then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = sem_bad) end
    let block_rec: HirBlock = cu.hir_blocks.data[block_ref]
    if cu.lower_scopes.data == nil then jump out_of_mem() end
    cu.lower_scopes.len = 1
    cu.lower_scopes.data[1] = { scope = block_ref, first_reg = 0, first_local = 0, patch_base = block_rec.stmt_first, span = block_rec.span }
    jump loop()
end
block loop()
    let st: LowerScope = cu.lower_scopes.data[1]
    let block_rec: HirBlock = cu.hir_blocks.data[st.scope]
    if st.first_local >= block_rec.stmt_len then jump finish_after(n = block_rec.stmt_len, last_ref = block_rec.stmt_last) end
    let ref: index = st.patch_base
    if ref == 0 then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = sem_bad) end
    cu.lower_scopes.data[1].first_local = st.first_local + 1
    cu.lower_scopes.data[1].patch_base = cu.hir_stmts.data[ref].next_stmt
    cu.lower_mark = ref
    emit lower_stmt(cu, ref; ok = stmt_done, returned = stmt_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block stmt_done()
    jump loop()
end
block finish_after(n: index, last_ref: index)
    cu.durable_mark = n
    cu.parse_mark = last_ref
    emit patch_pending(cu, last_ref + 1; ok = after_patched, limit_error = too_big)
end
block after_patched()
    if cu.durable_mark == 0 then jump ok(returned = as(u8, 0)) end
    let last_stmt: HirStmt = cu.hir_stmts.data[cu.parse_mark]
    if last_stmt.kind == @{HSTMT_RETURN} then jump ok(returned = as(u8, 1)) end
    jump ok(returned = as(u8, 0))
end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local close_lowered_function = host.region(V) [[
region close_lowered_function(cu: ptr(CompileUnit);
                              ok(proto: ptr(Proto)) | oom)
entry start()
    emit @{close_func_builder}(cu; ok = closed, oom = out_of_mem)
end
block closed(proto: ptr(Proto)) jump ok(proto = proto) end
block out_of_mem() jump oom() end
end
]]

local begin_child_builder = host.region(V) [[
region begin_child_builder(cu: ptr(CompileUnit), function_ref: index;
                           ok | semantic_error(err: CompileError) | oom)
entry start()
    if function_ref == 0 or function_ref > cu.hir_functions.len then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = sem_bad) end
    emit @{arena_alloc_bytes}(cu, as(index, @{CHILD_TOTAL}), as(u32, 8); ok = allocated, oom = out_of_mem)
end
block allocated(ptr: ptr(u8))
    let b: ptr(FuncBuilder) = as(ptr(FuncBuilder), ptr)
    let p: ptr(Proto) = as(ptr(Proto), ptr + as(index, @{CHILD_OFF_PROTO}))
    let code: ptr(Instr) = as(ptr(Instr), ptr + as(index, @{CHILD_OFF_CODE}))
    let constants: ptr(Value) = as(ptr(Value), ptr + as(index, @{CHILD_OFF_CONSTANTS}))
    let upvals: ptr(UpValDesc) = as(ptr(UpValDesc), ptr + as(index, @{CHILD_OFF_UPVALS}))
    let children: ptr(ptr(Proto)) = as(ptr(ptr(Proto)), ptr + as(index, @{CHILD_OFF_CHILDREN}))
    let locals: ptr(CompileLocal) = as(ptr(CompileLocal), ptr + as(index, @{CHILD_OFF_LOCALS}))
    let fn: HirFunction = cu.hir_functions.data[function_ref]
    b.parent = cu.current
    b.out_proto = p
    b.code = { data = code, len = 0, cap = as(index, @{CHILD_CODE_CAP}) }
    b.constants = { data = constants, len = 0, cap = as(index, @{CHILD_CONST_CAP}) }
    b.children = { data = children, len = 0, cap = as(index, @{CHILD_CHILD_CAP}) }
    b.locvars = { data = nil, len = 0, cap = 0 }
    b.upvals = { data = upvals, len = 0, cap = as(index, @{CHILD_UPVAL_CAP}) }
    b.locals = locals
    b.locals_len = 0
    b.locals_cap = as(index, @{CHILD_LOCAL_CAP})
    b.labels = nil
    b.labels_len = 0
    b.labels_cap = 0
    b.gotos = nil
    b.gotos_len = 0
    b.gotos_cap = 0
    b.firstlocal = function_ref
    b.nactvar = as(u16, fn.numparams)
    b.freereg = as(u16, fn.numparams)
    b.maxstack = as(u16, fn.numparams)
    if b.maxstack == 0 then b.maxstack = 1 end
    b.pc = 0
    b.lasttarget = 0
    b.numparams = fn.numparams
    b.flag = 0
    if fn.is_vararg ~= 0 then b.flag = as(u8, @{PF_VAHID}) end
    cu.current = b
    cu.root_hir_function = function_ref
    jump ok()
end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local add_function_captures = host.region(V) [[
region add_function_captures(cu: ptr(CompileUnit), function_ref: index;
                             ok | oom)
entry start()
    let fn: HirFunction = cu.hir_functions.data[function_ref]
    if fn.captures_len == 0 then jump ok() end
    jump loop(i = as(index, 0), first = fn.captures_first, n = fn.captures_len)
end
block loop(i: index, first: index, n: index)
    if i >= n then jump ok() end
    let cap: CaptureRec = cu.captures.data[first + i]
    let sym: SymbolRec = cu.symbols.data[cap.symbol]
    let desc: UpValDesc = { name = nil, instack = 1, index = sym.local_index }
    emit @{upvaldesc_push}(cu, desc; ok = pushed, oom = out_of_mem)
end
block pushed(idx: index)
    jump loop(i = idx + 1, first = cu.hir_functions.data[cu.root_hir_function].captures_first, n = cu.hir_functions.data[cu.root_hir_function].captures_len)
end
block out_of_mem() jump oom() end
end
]]

local finish_child_builder = host.region(V) [[
region finish_child_builder(cu: ptr(CompileUnit), proto: ptr(Proto);
                            ok | oom)
entry start()
    let fn_ref: index = cu.current.firstlocal
    let parent: ptr(FuncBuilder) = cu.current.parent
    cu.current = parent
    cu.durable_mark = fn_ref
    emit @{proto_ptr_push}(cu, proto; ok = attached, oom = out_of_mem)
end
block attached(idx: index)
    cu.hir_functions.data[cu.durable_mark].nested_first = idx
    jump ok()
end
block out_of_mem() jump oom() end
end
]]

local lower_function = host.region(V) [[
region lower_function(cu: ptr(CompileUnit), function_ref: index;
                      ok(proto: ptr(Proto)) | semantic_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    if function_ref == 0 then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = sem_bad) end
    if function_ref > cu.hir_functions.len then emit @{source_error_at_current}(cu, @{PERR_MALFORMED_HIR}; error = sem_bad) end
    cu.root_hir_function = function_ref
    let body: index = cu.hir_functions.data[function_ref].body
    emit lower_block(cu, body; ok = block_done, semantic_error = sem_bad, limit_error = too_big, oom = out_of_mem)
end
block block_done(returned: u8)
    if returned ~= 0 then jump close_now() end
    emit @{emit_return0}(cu; ok = close_now, limit_error = too_big, oom = out_of_mem)
end
block close_now()
    emit close_lowered_function(cu; ok = closed, oom = out_of_mem)
end
block closed(proto: ptr(Proto)) jump ok(proto = proto) end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

local lower_hir_to_proto = host.region(V) [[
region lower_hir_to_proto(cu: ptr(CompileUnit);
                          ok(proto: ptr(Proto)) | semantic_error(err: CompileError) | limit_error(err: CompileError) | oom)
entry start()
    cu.phase = @{SOURCE_LOWER}
    cu.lower_frames.len = 0
    cu.lower_scopes.len = 0
    cu.patches.len = 0
    cu.expr_slots.len = 0
    cu.root_hir_function = 1
    cu.current = cu.root
    jump lower_children(function_ref = as(index, 2))
end
block lower_children(function_ref: index)
    if function_ref > cu.hir_functions.len then jump lower_root() end
    let fn: HirFunction = cu.hir_functions.data[function_ref]
    if fn.parent ~= 1 then emit @{source_error_at_span}(cu, @{PERR_UNSUPPORTED_SOURCE}, as(u16, 0), fn.span; error = sem_bad) end
    emit begin_child_builder(cu, function_ref; ok = child_builder_ready, semantic_error = sem_bad, oom = out_of_mem)
end
block child_builder_ready()
    emit add_function_captures(cu, cu.root_hir_function; ok = child_captures_ready, oom = out_of_mem)
end
block child_captures_ready()
    cu.status = 1
    jump lower_selected()
end
block lower_selected()
    emit lower_function(cu, cu.root_hir_function;
        ok = selected_lowered,
        semantic_error = sem_bad,
        limit_error = too_big,
        oom = out_of_mem)
end
block selected_lowered(proto: ptr(Proto))
    if cu.status ~= 0 then emit finish_child_builder(cu, proto; ok = child_attached, oom = out_of_mem) end
    cu.phase = @{SOURCE_DONE}
    jump ok(proto = proto)
end
block child_attached()
    let next_fn: index = cu.durable_mark + 1
    cu.root_hir_function = 1
    cu.current = cu.root
    jump lower_children(function_ref = next_fn)
end
block lower_root()
    cu.status = 0
    cu.root_hir_function = 1
    cu.current = cu.root
    jump lower_selected()
end
block sem_bad(err: CompileError) jump semantic_error(err = err) end
block too_big(err: CompileError) jump limit_error(err = err) end
block out_of_mem() jump oom() end
end
]]

return {
    push_lower_frame = push_lower_frame,
    pop_lower_frame = pop_lower_frame,
    push_lower_scope = push_lower_scope,
    pop_lower_scope = pop_lower_scope,
    push_patch = push_patch,
    patch_pending = patch_pending,
    lower_hir_to_proto = lower_hir_to_proto,
    lower_compare_bool = lower_compare_bool,
    begin_child_builder = begin_child_builder,
    add_function_captures = add_function_captures,
    finish_child_builder = finish_child_builder,
    lower_function = lower_function,
    lower_block = lower_block,
    lower_stmt = lower_stmt,
    lower_expr = lower_expr,
    close_lowered_function = close_lowered_function,
}
