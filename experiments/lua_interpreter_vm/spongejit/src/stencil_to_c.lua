-- stencil_to_c.lua -- emit C from hole-parametric Stencil IR.
-- C emission consumes preallocated stencil.holes; it must not allocate holes or
-- perform semantic rewrites.

local M = {}
local unique_call_id = 0

local HOLE_PREAMBLE = [[
#include <stdint.h>
#include <stddef.h>

typedef struct TValue { unsigned long long value_; unsigned char tt_; } TValue;

typedef struct SponExecCtx {
    void *stack;
    TValue *k;
    TValue scratch[256];
    unsigned int exit_kind;
    unsigned int exit_pc;
    unsigned int exit_op_idx;
    unsigned int exit_hole;
} SponExecCtx;

enum {
    SPON_EXIT_NONE = 0,
    SPON_EXIT_GUARD = 1,
    SPON_EXIT_RESIDUAL = 2,
    SPON_EXIT_BOUNDARY = 3,
    SPON_EXIT_BARRIER = 4,
    SPON_EXIT_UNLOWERED = 5
};

/* Hole declarations — extern symbols produce R_X86_64_32 relocations */
extern const char __H_0[]; extern const char __H_1[]; extern const char __H_2[]; extern const char __H_3[];
extern const char __H_4[]; extern const char __H_5[]; extern const char __H_6[]; extern const char __H_7[];
extern const char __H_8[]; extern const char __H_9[]; extern const char __H_10[]; extern const char __H_11[];
extern const char __H_12[]; extern const char __H_13[]; extern const char __H_14[]; extern const char __H_15[];
extern const char __H_16[]; extern const char __H_17[]; extern const char __H_18[]; extern const char __H_19[];
extern const char __H_20[]; extern const char __H_21[]; extern const char __H_22[]; extern const char __H_23[];
extern const char __H_24[]; extern const char __H_25[]; extern const char __H_26[]; extern const char __H_27[];
extern const char __H_28[]; extern const char __H_29[]; extern const char __H_30[]; extern const char __H_31[];
extern const char __H_32[]; extern const char __H_33[]; extern const char __H_34[]; extern const char __H_35[];
extern const char __H_36[]; extern const char __H_37[]; extern const char __H_38[]; extern const char __H_39[];
extern const char __H_40[]; extern const char __H_41[]; extern const char __H_42[]; extern const char __H_43[];
extern const char __H_44[]; extern const char __H_45[]; extern const char __H_46[]; extern const char __H_47[];
extern const char __H_48[]; extern const char __H_49[]; extern const char __H_50[]; extern const char __H_51[];
extern const char __H_52[]; extern const char __H_53[]; extern const char __H_54[]; extern const char __H_55[];
extern const char __H_56[]; extern const char __H_57[]; extern const char __H_58[]; extern const char __H_59[];
extern const char __H_60[]; extern const char __H_61[]; extern const char __H_62[]; extern const char __H_63[];
extern const char __H_64[]; extern const char __H_65[]; extern const char __H_66[]; extern const char __H_67[];
extern const char __H_68[]; extern const char __H_69[]; extern const char __H_70[]; extern const char __H_71[];
extern const char __H_72[]; extern const char __H_73[]; extern const char __H_74[]; extern const char __H_75[];
extern const char __H_76[]; extern const char __H_77[]; extern const char __H_78[]; extern const char __H_79[];
extern const char __H_80[]; extern const char __H_81[]; extern const char __H_82[]; extern const char __H_83[];
extern const char __H_84[]; extern const char __H_85[]; extern const char __H_86[]; extern const char __H_87[];
extern const char __H_88[]; extern const char __H_89[]; extern const char __H_90[]; extern const char __H_91[];
extern const char __H_92[]; extern const char __H_93[]; extern const char __H_94[]; extern const char __H_95[];
extern const char __H_96[]; extern const char __H_97[]; extern const char __H_98[]; extern const char __H_99[];
extern const char __H_100[]; extern const char __H_101[]; extern const char __H_102[]; extern const char __H_103[];
extern const char __H_104[]; extern const char __H_105[]; extern const char __H_106[]; extern const char __H_107[];
extern const char __H_108[]; extern const char __H_109[]; extern const char __H_110[]; extern const char __H_111[];
extern const char __H_112[]; extern const char __H_113[]; extern const char __H_114[]; extern const char __H_115[];
extern const char __H_116[]; extern const char __H_117[]; extern const char __H_118[]; extern const char __H_119[];
extern const char __H_120[]; extern const char __H_121[]; extern const char __H_122[]; extern const char __H_123[];
extern const char __H_124[]; extern const char __H_125[]; extern const char __H_126[]; extern const char __H_127[];
]]

local TYPE_C = { TValue = "TValue *", I64 = "long long", F64 = "double", Bool = "int", PtrTable = "void *", PtrClosure = "void *", Unknown = "TValue *" }

local function var_name(id)
  return "v_" .. tostring(id):gsub("[^%w]", "_")
end

local function value_expr(st, vid)
  if not vid then return "NULL" end
  return var_name(vid)
end

local function hole_expr(h)
  assert(h and h.id ~= nil, "stencil op missing preallocated hole")
  return string.format("__H_%d", h.id)
end

local function exit_code_for(op, n)
  if op == "GuardI64" or op == "GuardTable" or op == "GuardShape" or op == "GuardMetatableAbsent" or op == "GuardCallTarget" or op == "GuardBounds" then return "SPON_EXIT_GUARD" end
  if op == "BarrierCheck" then return "SPON_EXIT_BARRIER" end
  if op == "ExitUnlowered" then return "SPON_EXIT_UNLOWERED" end
  if op == "ExitResidual" then return "SPON_EXIT_RESIDUAL" end
  return "SPON_EXIT_BOUNDARY"
end

function M.generate(ssa_result_or_stencil, source_ops, config)
  config = config or {}
  local st = ssa_result_or_stencil.stencil or ssa_result_or_stencil
  source_ops = source_ops or st.source_ops or ssa_result_or_stencil.source_ops or {}
  local lines = {}
  local function emit(s) lines[#lines + 1] = s end

  local opnames = {}
  for _, op in ipairs(source_ops or {}) do opnames[#opnames + 1] = type(op) == "table" and tostring(op.op) or tostring(op) end
  local form = ssa_result_or_stencil.stencil_form or {}
  emit(string.format("/* SponJIT stencil IR  FORM=%s  ops=%s */", table.concat(form, "|"), table.concat(opnames, " ")))
  emit("")
  emit(HOLE_PREAMBLE)
  emit("")

  local hash = (ssa_result_or_stencil.stencil_hash or "00000000"):sub(1, 8)
  local salt = tostring(config.func_salt or os.getenv("SPON_FUNC_SALT") or ""):gsub("[^%w_]", "_")
  unique_call_id = unique_call_id + 1
  local func_name = salt ~= "" and string.format("z_%s_%s_%04x", salt, hash, unique_call_id) or string.format("z_%s_%04x", hash, unique_call_id)

  emit(string.format("void %s(SponExecCtx *ctx) {", func_name))
  emit("    TValue *base = (TValue*)ctx->stack;")
  emit("    ctx->exit_kind = SPON_EXIT_NONE;")
  emit("    ctx->exit_pc = 0;")
  emit("    ctx->exit_op_idx = 0;")
  emit("    ctx->exit_hole = 0;")

  local declared = {}
  for _, vid in ipairs(st.value_order or {}) do
    local v = st.values[vid]
    if v and not declared[vid] then
      emit(string.format("    %s %s;", TYPE_C[v.ty or "Unknown"] or "TValue *", var_name(vid)))
      declared[vid] = true
    end
  end
  emit("")

  local function emit_exit(kind, h, op_idx, comment)
    emit(string.format("    ctx->exit_kind = %s; ctx->exit_pc = (unsigned int)(uintptr_t)__H_%d; ctx->exit_op_idx = %d; ctx->exit_hole = %d; return; /* %s */", kind, h.id, tonumber(op_idx or 0) or 0, h.id, tostring(comment or "exit")))
  end

  for _, n in ipairs(st.ops or {}) do
    local op, inputs, outputs, args = n.op, n.inputs or {}, n.outputs or {}, n.args or {}
    local h = n.hole
    if op == "LoadSlot" then
      emit(string.format("    int sl_%d = (int)(uintptr_t)%s; /* S%d */", h.id, hole_expr(h), tonumber(h.role_arg or 0)))
      emit(string.format("    %s = base + sl_%d;", var_name(outputs[1]), h.id))
    elseif op == "StoreSlot" then
      emit(string.format("    int ss_%d = (int)(uintptr_t)%s; /* S%d */", h.id, hole_expr(h), tonumber(h.role_arg or 0)))
      emit(string.format("    base[ss_%d] = *%s;", h.id, value_expr(st, inputs[1])))
    elseif op == "StoreI64Slot" then
      emit(string.format("    int f_slot_%d = (int)(uintptr_t)%s; /* S%d */", h.id, hole_expr(h), tonumber(h.role_arg or 0)))
      emit(string.format("    base[f_slot_%d].value_ = (unsigned long long)(%s);", h.id, value_expr(st, inputs[1])))
      emit(string.format("    base[f_slot_%d].tt_ = 3;", h.id))
      if outputs[1] then emit(string.format("    %s = &base[f_slot_%d];", var_name(outputs[1]), h.id)) end
    elseif op == "GuardI64" then
      local vn = value_expr(st, inputs[1])
      emit(string.format("    if (__builtin_expect(%s->tt_ != 3, 0)) {", vn))
      emit_exit("SPON_EXIT_GUARD", h, n.source and (n.source - 1) or 0, "guard_i64")
      emit("    }")
    elseif op == "GuardTable" then
      local vn = value_expr(st, inputs[1])
      emit(string.format("    if (__builtin_expect(%s->tt_ != 69, 0)) {", vn))
      emit_exit("SPON_EXIT_GUARD", h, n.source and (n.source - 1) or 0, "guard_table")
      emit("    }")
    elseif op == "GuardShape" then
      local vn = value_expr(st, inputs[1])
      emit(string.format("    if (__builtin_expect(*(unsigned int*)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)__H_%d) != (unsigned int)(uintptr_t)__H_%d, 0)) {", vn, args.shape_offset, args.shape_id))
      emit_exit("SPON_EXIT_GUARD", h, n.source and (n.source - 1) or 0, "guard_shape")
      emit("    }")
    elseif op == "GuardMetatableAbsent" then
      local vn = value_expr(st, inputs[1])
      emit(string.format("    if (__builtin_expect(*(void**)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)__H_%d) != 0, 0)) {", vn, args.metatable_offset))
      emit_exit("SPON_EXIT_GUARD", h, n.source and (n.source - 1) or 0, "guard_metatable_absent")
      emit("    }")
    elseif op == "GuardArrayHit" then
      emit("    /* guard_array_hit covered by array/bounds lease */")
    elseif op == "GuardBounds" then
      emit("    if (0) {")
      emit_exit("SPON_EXIT_GUARD", h, n.source and (n.source - 1) or 0, "bounds lease")
      emit("    } /* bounds lease */")
    elseif op == "GuardCallTarget" then
      local fn = value_expr(st, inputs[1])
      emit(string.format("    if (__builtin_expect((void*)(uintptr_t)%s->value_ != (void*)__H_%d, 0)) {", fn, args.call_target))
      emit_exit("SPON_EXIT_GUARD", h, n.source and (n.source - 1) or 0, "guard_call_target")
      emit("    }")
    elseif op == "UnboxI64" then
      emit(string.format("    %s = (long long)%s->value_;", var_name(outputs[1]), value_expr(st, inputs[1])))
    elseif op == "BoxI64Scratch" then
      local on = var_name(outputs[1])
      emit(string.format("    %s = &ctx->scratch[0];", on))
      emit(string.format("    %s->value_ = (unsigned long long)(%s);", on, value_expr(st, inputs[1])))
      emit(string.format("    %s->tt_ = 3;", on))
    elseif op == "AddI64" or op == "SubI64" or op == "MulI64" then
      local c_op = op == "SubI64" and "-" or (op == "MulI64" and "*" or "+")
      emit(string.format("    %s = %s %s %s;", var_name(outputs[1]), value_expr(st, inputs[1]), c_op, value_expr(st, inputs[2])))
    elseif op == "I64BinOp" then
      local bop = args.op or "ADD"
      local c_op = ({DIV="/", IDIV="/", MOD="%", BAND="&", BOR="|", BXOR="^", SHL="<<", SHR=">>", SUB="-", MUL="*"})[bop] or "+"
      emit(string.format("    %s = %s %s %s;", var_name(outputs[1]), value_expr(st, inputs[1]), c_op, value_expr(st, inputs[2])))
    elseif op == "I64UnaryOp" then
      local c_op = args.op == "BNOT" and "~" or "-"
      emit(string.format("    %s = %s%s;", var_name(outputs[1]), c_op, value_expr(st, inputs[1])))
    elseif op == "CmpI64" then
      local cmp_op = args.cmp_op or "LT"
      local c_op = ({EQ="==", EQI="==", LT="<", LTI="<", LE="<=", LEI="<=", GTI=">", GEI=">="})[cmp_op] or "=="
      emit(string.format("    %s = (%s) %s (%s) ? 1LL : 0LL;", var_name(outputs[1]), value_expr(st, inputs[1]), c_op, value_expr(st, inputs[2])))
    elseif op == "ConstI64Hole" then
      emit(string.format("    %s = (long long)(uintptr_t)%s; /* %s */", var_name(outputs[1]), hole_expr(h), tostring(args.role or h.role)))
    elseif op == "ConstI64" then
      emit(string.format("    %s = %dLL;", var_name(outputs[1]), tonumber(args.value) or 0))
    elseif op == "ConstNil" then
      local on = var_name(outputs[1])
      emit(string.format("    %s = &ctx->scratch[1]; %s->value_ = 0; %s->tt_ = 0;", on, on, on))
    elseif op == "ConstBool" then
      local on = var_name(outputs[1])
      emit(string.format("    %s = &ctx->scratch[2]; %s->value_ = (unsigned long long)(uintptr_t)%s; %s->tt_ = ((uintptr_t)%s) ? 17 : 1;", on, on, hole_expr(h), on, hole_expr(h)))
    elseif op == "Move" then
      emit(string.format("    %s = %s;", var_name(outputs[1]), value_expr(st, inputs[1])))
    elseif op == "LoadConst" then
      emit(string.format("    %s = ctx->k + (int)(uintptr_t)%s;", var_name(outputs[1]), hole_expr(h)))
    elseif op == "FieldLoad" then
      emit(string.format("    %s = (TValue*)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)%s);", var_name(outputs[1]), value_expr(st, inputs[1]), hole_expr(h)))
    elseif op == "FieldStore" then
      emit(string.format("    *(TValue*)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)%s) = *%s;", value_expr(st, inputs[1]), hole_expr(h), value_expr(st, inputs[2])))
    elseif op == "ArrayLoad" then
      emit(string.format("    %s = (TValue*)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)%s + ((long long)%s * (long long)sizeof(TValue)));", var_name(outputs[1]), value_expr(st, inputs[1]), hole_expr(h), value_expr(st, inputs[2])))
    elseif op == "ArrayStore" then
      emit(string.format("    *(TValue*)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)%s + ((long long)%s * (long long)sizeof(TValue))) = *%s;", value_expr(st, inputs[1]), hole_expr(h), value_expr(st, inputs[2]), value_expr(st, inputs[3])))
    elseif op == "BarrierCheck" then
      emit(string.format("    if ((uintptr_t)%s) {", hole_expr(h)))
      emit_exit("SPON_EXIT_BARRIER", h, n.source and (n.source - 1) or 0, "barrier")
      emit("    }")
    elseif op == "ExitResidual" or op == "ExitBoundary" or op == "ExitUnlowered" then
      emit_exit(exit_code_for(op, n), h, n.source and (n.source - 1) or 0, op)
    else
      error("unhandled Stencil IR op in C emitter: " .. tostring(op))
    end
  end
  emit("")
  emit("}")

  local exit_count = 0
  for _, n in ipairs(st.ops or {}) do if n.exit or n.op:match("^Exit") then exit_count = exit_count + 1 end end
  local hole_roles = {}
  for _, h in ipairs(st.holes or {}) do hole_roles[#hole_roles + 1] = h.role end
  return {
    c_code = table.concat(lines, "\n"),
    func_name = func_name,
    hole_catalog = st.holes,
    holes = hole_roles,
    hole_count = #(st.holes or {}),
    stencil_op_count = #(st.ops or {}),
    node_count = #(st.ops or {}),
    exit_count = exit_count,
    n_absorbed = #(source_ops or {}),
    n_total = #(source_ops or {}),
  }
end

function M.compile_to_file(ssa_result_or_stencil, source_ops, out_path, config)
  if type(source_ops) == "string" and out_path == nil then out_path = source_ops; source_ops = nil end
  local r = M.generate(ssa_result_or_stencil, source_ops, config)
  local f, err = io.open(out_path, "w")
  if not f then return nil, err end
  f:write(r.c_code)
  f:close()
  return r
end

return M
