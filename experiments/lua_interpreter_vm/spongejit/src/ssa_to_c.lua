-- ssa_to_c.lua — Compile optimized SSA graph to monolithic C stencil
-- with HOLEs that get patched at JIT materialization time.
--
-- Each stencil is a void function taking a SponExecCtx pointer:
--   void stencil(SponExecCtx *ctx);
--
-- The context carries stack, constants, scratch slots, and structured exit state.
-- All opcode-specific values (register slots, immediates, resume PCs) are HOLEs:
--   int slot_A = (int)(uintptr_t)__H_0;  // patched at JIT time
--
-- The holes produce R_X86_64_32 relocations in the .o file.
-- At JIT time: copy .text bytes to executable image memory, patch holes, call.

local IR = require("src.ssa_ir")
local M = {}

-- Per-call unique ID to prevent function name collisions
local unique_call_id = 0

-- ── Hole tracking ───────────────────────────────────────────────────────

local function HoleTracker()
    local next_id = 0
    local holes = {}  -- {hole_id, role_name, source_op_idx}
    return {
        alloc = function(self, role, op_idx)
            local id = next_id
            next_id = next_id + 1
            holes[#holes + 1] = {id = id, role = role, op_idx = op_idx}
            return id
        end,
        catalog = function(self)
            return holes
        end,
        count = function(self) return next_id end,
    }
end

-- ── C Preamble ──────────────────────────────────────────────────────────

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

-- ── Type-to-C mapping ───────────────────────────────────────────────────

local TYPE_C = { TValue = "TValue *", I64 = "long long", F64 = "double", Bool = "int",
    PtrTable = "void *", PtrClosure = "void *", Unknown = "TValue *" }

local function var_name(val)
    return "v_" .. tostring(val.id):gsub("[^%w]", "_")
end

local function value_expr(g, vid)
    local v = g.values[vid]
    if not v then return "NULL" end
    return var_name(v)
end

-- ── SSA→C codegen ───────────────────────────────────────────────────────

function M.generate(ssa_result, source_ops, config)
    config = config or {}
    local g = ssa_result.graph
    source_ops = source_ops or ssa_result.source_ops or {}

    local holes = HoleTracker()
    local lines = {}
    local function emit(s) lines[#lines + 1] = s end
    local forwarded = {}  -- forwarded[vid] = raw expression string

    -- Header
    local opnames = {}
    for _, op in ipairs(source_ops) do
        opnames[#opnames + 1] = type(op) == "table" and op.op or tostring(op)
    end
    local nf = table.concat(ssa_result.normal_form or {}, "|")
    emit(string.format("/* SponJIT C&P stencil  NF=%s  ops=%s */", nf, table.concat(opnames, " ")))
    emit("")

    -- Preamble
    emit(HOLE_PREAMBLE)
    emit("")

    -- Function name from hash + seq fingerprint
    local name_parts = {}
    for _, op in ipairs(source_ops) do
        name_parts[#name_parts + 1] = type(op) == "table" and op.op or tostring(op)
    end
    local op_str = table.concat(name_parts, "_")
    local fact_str = ""
    for _, fx in ipairs(config.facts or {}) do
        fact_str = fact_str .. tostring(fx.predicate or "") .. tostring(fx.subject and fx.subject.id or "")
    end
    local base_str = op_str .. fact_str
    local seq_hash = 0
    for i = 1, #base_str do
        seq_hash = ((seq_hash * 31) + base_str:byte(i)) % 0x1000000
    end
    local hash = (ssa_result.normal_form_hash or "00000000"):sub(1, 8)
    local salt = tostring(config.func_salt or os.getenv("SPON_FUNC_SALT") or "")
    salt = salt:gsub("[^%w_]", "_")
    unique_call_id = unique_call_id + 1
    local func_name
    if salt ~= "" then
        func_name = string.format("z_%s_%s_%06x_%04x", salt, hash, seq_hash, unique_call_id)
    else
        func_name = string.format("z_%s_%06x_%04x", hash, seq_hash, unique_call_id)
    end

    -- Function signature
    emit(string.format("void %s(SponExecCtx *ctx) {", func_name))
    emit("    TValue *base = (TValue*)ctx->stack;")
    emit("    ctx->exit_kind = SPON_EXIT_NONE;")
    emit("    ctx->exit_pc = 0;")
    emit("    ctx->exit_op_idx = 0;")
    emit("    ctx->exit_hole = 0;")

    -- Declare local variables
    local declared = {}
    for _, n in ipairs(g.nodes) do
        if not n.removed then
            for _, vid in ipairs(n.outputs or {}) do
                local v = g.values[vid]
                if v and not declared[vid] then
                    local cty = TYPE_C[v.ty or "Unknown"] or "TValue *"
                    emit(string.format("    %s %s;", cty, var_name(v)))
                    declared[vid] = true
                end
            end
        end
    end
    emit("")

    -- Node-by-node codegen
    local function emit_exit(kind, h, op_idx, comment)
        emit(string.format("    ctx->exit_kind = %s; ctx->exit_pc = (unsigned int)(uintptr_t)__H_%d; ctx->exit_op_idx = %d; ctx->exit_hole = %d; return; /* %s */",
            kind, h, tonumber(op_idx or 0) or 0, h, tostring(comment or "exit")))
    end

    local skip_nodes = {}
    for idx, n in ipairs(g.nodes) do
        if n.removed or skip_nodes[n.id] then goto continue end

        local op = n.op
        local args = n.args or {}
        local inputs = n.inputs or {}
        local outputs = n.outputs or {}
        local indent = "    "

        if op == "FrameLoad" then
            local slot_name = args.slot or "cur"
            local h = holes:alloc(slot_name, n.source and (n.source - 1) or 0)
            emit(string.format("    int sl_%d = (int)(uintptr_t)__H_%d; /* %s */", h, h, slot_name))
            local out_v = g.values[outputs[1]]
            local vn = var_name(out_v)
            emit(string.format("    %s = base + sl_%d;", vn, h))

        elseif op == "FrameStore" then
            local slot_name = args.slot or "cur"
            local h = holes:alloc(slot_name, n.source and (n.source - 1) or 0)
            emit(string.format("    int ss_%d = (int)(uintptr_t)__H_%d; /* %s */", h, h, slot_name))
            local vn = value_expr(g, inputs[1])
            emit(string.format("    base[ss_%d] = *%s;", h, vn))

        elseif op == "GuardTypeI64" then
            local vn = value_expr(g, inputs[1])
            local raw = forwarded[inputs[1]]
            if raw then
                emit(string.format("    /* guard_i64 skipped — value just stored */"))
            else
                local fh = holes:alloc("fail", n.source and (n.source - 1) or 0)
                emit(string.format("    if (__builtin_expect(%s->tt_ != 3, 0)) {", vn))
                emit_exit("SPON_EXIT_GUARD", fh, n.source and (n.source - 1) or 0, "guard_i64")
                emit("    }")
            end

        elseif op == "GuardTable" then
            local vn = value_expr(g, inputs[1])
            local fh = holes:alloc("fail", n.source and (n.source - 1) or 0)
            emit(string.format("    if (__builtin_expect(%s->tt_ != 69, 0)) {", vn))
            emit_exit("SPON_EXIT_GUARD", fh, n.source and (n.source - 1) or 0, "guard_table")
            emit("    }")

        elseif op == "GuardShape" then
            local vn = value_expr(g, inputs[1])
            local off = holes:alloc("shape_offset", 0)
            local sid = holes:alloc("shape_id", 0)
            local fh = holes:alloc("fail", n.source and (n.source - 1) or 0)
            emit(string.format("    if (__builtin_expect(*(unsigned int*)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)__H_%d) != (unsigned int)(uintptr_t)__H_%d, 0)) {", vn, off, sid))
            emit_exit("SPON_EXIT_GUARD", fh, n.source and (n.source - 1) or 0, "guard_shape")
            emit("    }")

        elseif op == "GuardMetatableAbsent" then
            local vn = value_expr(g, inputs[1])
            local off = holes:alloc("metatable_offset", 0)
            local fh = holes:alloc("fail", n.source and (n.source - 1) or 0)
            emit(string.format("    if (__builtin_expect(*(void**)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)__H_%d) != 0, 0)) {", vn, off))
            emit_exit("SPON_EXIT_GUARD", fh, n.source and (n.source - 1) or 0, "guard_metatable_absent")
            emit("    }")

        elseif op == "GuardArrayHit" then
            emit("    /* guard_array_hit covered by array/bounds lease */")

        elseif op == "GuardBounds" then
            local fh = holes:alloc("fail", n.source and (n.source - 1) or 0)
            emit("    if (0) {")
            emit_exit("SPON_EXIT_GUARD", fh, n.source and (n.source - 1) or 0, "bounds lease")
            emit("    } /* bounds lease */")

        elseif op == "GuardCallTarget" then
            local fn = value_expr(g, inputs[1])
            local target = holes:alloc("call_target", 0)
            local fh = holes:alloc("fail", n.source and (n.source - 1) or 0)
            emit(string.format("    if (__builtin_expect((void*)(uintptr_t)%s->value_ != (void*)__H_%d, 0)) {", fn, target))
            emit_exit("SPON_EXIT_GUARD", fh, n.source and (n.source - 1) or 0, "guard_call_target")
            emit("    }")

        elseif op == "UnboxI64" then
            local vn = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            local raw = forwarded[inputs[1]]
            if raw then
                emit(string.format("    %s = %s;", oname, raw))
            else
                emit(string.format("    %s = (long long)%s->value_;", oname, vn))
            end

        elseif op == "BoxI64" then
            local in_v = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            -- Check for fusion with next FrameStore
            local store_id = nil
            local store_slot_name = nil
            local store_source = n.source
            for j = idx + 1, #g.nodes do
                local m = g.nodes[j]
                if not m.removed then
                    if m.op == "FrameStore" and m.inputs and m.inputs[1] == outputs[1] then
                        store_id = m.id
                        store_slot_name = m.args and m.args.slot or "cur"
                        store_source = m.source or store_source
                    end
                    break
                end
            end
            if store_id then
                local h = holes:alloc("slot_" .. (store_slot_name or "0"), store_source and (store_source - 1) or 0)
                emit(string.format("    int f_slot_%d = (int)(uintptr_t)__H_%d; /* fused %s */", h, h, store_slot_name or "?"))
                emit(string.format("    base[f_slot_%d].value_ = (unsigned long long)(%s);", h, in_v))
                emit(string.format("    base[f_slot_%d].tt_ = 3;", h))
                -- Check if any node other than FrameStore consumes this BoxI64 output
                local has_other_consumer = false
                for j = idx + 1, #g.nodes do
                    local m = g.nodes[j]
                    if not m.removed and m.id ~= store_id then
                        for _, vid in ipairs(m.inputs or {}) do
                            if vid == outputs[1] then has_other_consumer = true end
                        end
                        if has_other_consumer then break end
                    end
                end
                if has_other_consumer then
                    emit(string.format("    %s = &base[f_slot_%d];", oname, h))
                    -- Don't set forwarded — other consumers must read from frame
                else
                    forwarded[outputs[1]] = in_v
                end
                skip_nodes[store_id] = true
            else
                emit(string.format("    /* BoxI64 — not fused */"))
                emit(string.format("    %s = &ctx->scratch[0]; /* temp slot */", oname))
                emit(string.format("    %s->value_ = (unsigned long long)(%s);", oname, in_v))
                emit(string.format("    %s->tt_ = 3;", oname))
            end

        elseif op == "AddI64" then
            local lhs = value_expr(g, inputs[1])
            local rhs = value_expr(g, inputs[2])
            local out_v = g.values[outputs[1]]
            emit(string.format("    %s = %s + %s;", var_name(out_v), lhs, rhs))

        elseif op == "SubI64" then
            local lhs = value_expr(g, inputs[1])
            local rhs = value_expr(g, inputs[2])
            local out_v = g.values[outputs[1]]
            emit(string.format("    %s = %s - %s;", var_name(out_v), lhs, rhs))

        elseif op == "MulI64" then
            local lhs = value_expr(g, inputs[1])
            local rhs = value_expr(g, inputs[2])
            local out_v = g.values[outputs[1]]
            emit(string.format("    %s = %s * %s;", var_name(out_v), lhs, rhs))

        elseif op == "I64BinOp" then
            local lhs = value_expr(g, inputs[1])
            local rhs = value_expr(g, inputs[2])
            local out_v = g.values[outputs[1]]
            local bop = (args or {}).op or "ADD"
            local c_op = "+"
            if bop == "DIV" or bop == "IDIV" then c_op = "/"
            elseif bop == "MOD" then c_op = "%"
            elseif bop == "BAND" then c_op = "&"
            elseif bop == "BOR" then c_op = "|"
            elseif bop == "BXOR" then c_op = "^"
            elseif bop == "SHL" then c_op = "<<"
            elseif bop == "SHR" then c_op = ">>"
            elseif bop == "SUB" then c_op = "-"
            elseif bop == "MUL" then c_op = "*"
            end
            emit(string.format("    %s = %s %s %s;", var_name(out_v), lhs, c_op, rhs))

        elseif op == "I64UnaryOp" then
            local x = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            local uop = (args or {}).op or "UNM"
            local c_op = (uop == "BNOT") and "~" or "-"
            emit(string.format("    %s = %s%s;", var_name(out_v), c_op, x))

        elseif op == "CmpI64" then
            local lhs = value_expr(g, inputs[1])
            local rhs = value_expr(g, inputs[2])
            local out_v = g.values[outputs[1]]
            local cmp_op = (args or {}).cmp_op or "LT"
            local c_op = "=="
            if cmp_op == "EQ" or cmp_op == "EQI" then c_op = "=="
            elseif cmp_op == "LT" or cmp_op == "LTI" then c_op = "<"
            elseif cmp_op == "LE" or cmp_op == "LEI" then c_op = "<="
            elseif cmp_op == "GTI" then c_op = ">"
            elseif cmp_op == "GEI" then c_op = ">="
            end
            emit(string.format("    %s = (%s) %s (%s) ? 1LL : 0LL;", var_name(out_v), lhs, c_op, rhs))

        elseif op == "ConstI64" then
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            -- Check if this came from an opcode with a runtime-determined value
            local pc_info = nil
            if n.source ~= nil then
                local src = source_ops[n.source]
                if src then
                    local on = type(src) == "table" and src.op or tostring(src)
                    if on == "LOADI" or on == "LOADF" then
                        -- Immediate from sBx field — use a hole
                        local h = holes:alloc("imm", n.source - 1)
                        emit(string.format("    %s = (long long)(uintptr_t)__H_%d; /* LOADI imm */", oname, h))
                        goto handled_const
                    elseif on == "ADDI" or on == "SHLI" or on == "SHRI" then
                        local h = holes:alloc("sC", n.source - 1)
                        emit(string.format("    %s = (long long)(uintptr_t)__H_%d; /* ADDI sC */", oname, h))
                        goto handled_const
                    elseif on:match("K$") or on == "EQK" then
                        local h = holes:alloc("k_i64", n.source - 1)
                        emit(string.format("    %s = (long long)(uintptr_t)__H_%d; /* K i64 */", oname, h))
                        goto handled_const
                    elseif on == "JMP" or on == "FORPREP" or on == "FORLOOP" then
                        local h = holes:alloc("sBx", n.source - 1)
                        emit(string.format("    %s = (long long)(uintptr_t)__H_%d; /* JMP sBx */", oname, h))
                        goto handled_const
                    end
                end
            end
            -- Fallback: use the SSA-decoded value
            local val = tonumber(args.value) or 0
            emit(string.format("    %s = %dLL;", oname, val))
            ::handled_const::

        elseif op == "ConstNil" then
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("    /* ConstNil */"))
            emit(string.format("    %s = &ctx->scratch[1]; /* temp slot */", oname))
            emit(string.format("    %s->value_ = 0; %s->tt_ = 0;", oname, oname))

        elseif op == "ConstBool" then
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            local b = args.value and 1 or 0
            emit(string.format("    /* ConstBool */"))
            emit(string.format("    %s = &ctx->scratch[2]; /* temp slot */", oname))
            emit(string.format("    %s->value_ = %dULL;", oname, b))
            emit(string.format("    %s->tt_ = %d;", oname, b ~= 0 and 17 or 1))

        elseif op == "Move" then
            local vn = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            emit(string.format("    %s = %s;", var_name(out_v), vn))

        elseif op == "LoadConst" then
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            local h = holes:alloc("k_idx", 0)
            emit(string.format("    %s = ctx->k + (int)(uintptr_t)__H_%d; /* K index */", oname, h))

        elseif op == "FieldLoad" then
            local tab = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            local h = holes:alloc("field_offset", n.source and (n.source - 1) or 0)
            emit(string.format("    %s = (TValue*)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)__H_%d);", var_name(out_v), tab, h))

        elseif op == "FieldStore" then
            local tab = value_expr(g, inputs[1])
            local val = value_expr(g, inputs[2])
            local h = holes:alloc("field_offset", n.source and (n.source - 1) or 0)
            emit(string.format("    *(TValue*)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)__H_%d) = *%s;", tab, h, val))

        elseif op == "ArrayLoad" then
            local tab = value_expr(g, inputs[1])
            local idxv = value_expr(g, inputs[2])
            local out_v = g.values[outputs[1]]
            local h = holes:alloc("array_base_offset", n.source and (n.source - 1) or 0)
            emit(string.format("    %s = (TValue*)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)__H_%d + ((long long)%s * (long long)sizeof(TValue)));", var_name(out_v), tab, h, idxv))

        elseif op == "ArrayStore" then
            local tab = value_expr(g, inputs[1])
            local idxv = value_expr(g, inputs[2])
            local val = value_expr(g, inputs[3])
            local h = holes:alloc("array_base_offset", n.source and (n.source - 1) or 0)
            emit(string.format("    *(TValue*)((char*)(uintptr_t)%s->value_ + (int)(uintptr_t)__H_%d + ((long long)%s * (long long)sizeof(TValue))) = *%s;", tab, h, idxv, val))

        elseif op == "BarrierCheck" then
            local h = holes:alloc("barrier", n.source and (n.source - 1) or 0)
            emit(string.format("    if ((uintptr_t)__H_%d) {", h))
            emit_exit("SPON_EXIT_BARRIER", h, n.source and (n.source - 1) or 0, "barrier")
            emit("    } /* barrier */")

        elseif op == "GenericExit" or op == "Residual" then
            local role = "exit_" .. tostring((args or {}).opcode or op)
            local h = holes:alloc(role, (n.source or 1) - 1)
            emit_exit("SPON_EXIT_RESIDUAL", h, (n.source or 1) - 1, role)

        elseif op == "Jump" or op == "Return1" or op == "Return0" or
               op == "Call" or op == "KnownCall" or op == "TailCall" then
            local role = "exit_" .. tostring(op)
            local h = holes:alloc(role, (n.source or 1) - 1)
            emit_exit("SPON_EXIT_BOUNDARY", h, (n.source or 1) - 1, "boundary: " .. tostring(op))

        else
            local role = "unlowered_" .. tostring(op)
            local h = holes:alloc(role, (n.source or 1) - 1)
            emit_exit("SPON_EXIT_UNLOWERED", h, (n.source or 1) - 1, "UNLOWERED: " .. tostring(op))
        end

        ::continue::
    end

    -- Continuation (return to interpreter for now)
    emit("")
    emit("}")

    local node_count, exit_count = 0, 0
    for _, n in ipairs(g.nodes or {}) do
        if not n.removed then
            node_count = node_count + 1
            if n.exit then exit_count = exit_count + 1 end
        end
    end
    local hc = holes:catalog()
    local hole_roles = {}
    for _, h in ipairs(hc) do hole_roles[#hole_roles + 1] = tostring(h.role or h.name or "hole") end
    return {
        c_code = table.concat(lines, "\n"),
        func_name = func_name,
        hole_catalog = hc,
        holes = hole_roles,
        hole_count = holes:count(),
        node_count = node_count,
        exit_count = exit_count,
        n_absorbed = #source_ops,
        n_total = #source_ops,
    }
end

function M.compile_to_file(ssa_result, source_ops, out_path, config)
    if type(source_ops) == "string" and out_path == nil then
        out_path = source_ops
        source_ops = nil
    end
    local r = M.generate(ssa_result, source_ops, config)
    local f, err = io.open(out_path, "w")
    if not f then return nil, err end
    f:write(r.c_code)
    f:close()
    return r
end

return M
