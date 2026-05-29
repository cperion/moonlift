-- ssa_to_c.lua — Compile an optimized SSA graph to a monolithic C function
-- in the StencilCtx ABI (compatible with stencils_puc.c / sponjit_block.h).
--
-- ONE SSA sponge → ONE C function → gcc -O2 -c → ONE binary stencil.
--
-- Slot indices are decoded from the instruction(s) at runtime via GETARG_*
-- so that ONE stencil serves ALL register assignments for a given opcode pattern.
-- This matches how sponjit_scan_proto matches on opcode only (not registers).
--
-- ABI (from stencils_puc.c):
--   void stencil_mono_HASH(StencilCtx *ctx)
--   - reads slot indices via GETARG_*(ctx->pc[N]) from the instruction stream
--   - TValue is struct { value_; tt_ } with separate tag byte
--   - guards: ctx->status = SJ_GUARD_FAIL; return;
--   - success: ctx->pc += n_absorbed; ctx->status = SJ_OK;
--   - boundary ops (RETURN, CALL, JMP) are NOT absorbed; stencil stops before them.
--   - ctx->scratch is used for intermediate boxed values (no malloc)

local IR = require("src.ssa_ir")

local M = {}

-- ── PUC Lua opcode operand layout ───────────────────────────────────────

-- Maps opcode → { out_pos, in_positions... }
-- "out" means this operand is a destination slot (GETARG_A usually)
-- "in" means this operand is a source slot (GETARG_B or GETARG_C)
-- nil means "not a slot" (immediate, constant index, etc.)
local OPCODE_OPERANDS = {
    MOVE     = {"A_out","B_in"},
    LOADI    = {"A_out"},         -- sBx = immediate
    LOADF    = {"A_out"},
    LOADK    = {"A_out"},         -- Bx = constant index
    LOADTRUE = {"A_out"},
    LOADFALSE= {"A_out"},
    LOADNIL  = {"A_out"},
    ADD      = {"A_out","B_in","C_in"},
    ADDI     = {"A_out","B_in"},  -- sC = immediate
    SUB      = {"A_out","B_in","C_in"},
    MUL      = {"A_out","B_in","C_in"},
    DIV      = {"A_out","B_in","C_in"},
    MOD      = {"A_out","B_in","C_in"},
    GETFIELD = {"A_out","B_in"},  -- C = constant key
    GETTABUP = {"A_out","B_in"},
    SELF     = {"A_out","B_in"},
    SETFIELD = {"A_in","B_in","C_in"},  -- A=table, B=key, C=value
    SETTABUP = {"A_in","B_in","C_in"},
    GETTABLE = {"A_out","B_in","C_in"},
    GETI     = {"A_out","B_in"},  -- C = immediate?
    SETTABLE = {"A_in","B_in","C_in"},
    SETI     = {"A_in","B_in"},
    CALL     = {"A_out"},
    TAILCALL = {"A_out"},
    RETURN   = {"A_in"},
    RETURN0  = {},
    RETURN1  = {"A_in"},
    JMP      = {},               -- sBx = offset
    FORLOOP  = {"A"},
    FORPREP  = {"A"},
    EQ       = {"A_out","B_in","C_in"},
    LT       = {"A_out","B_in","C_in"},
    LE       = {"A_out","B_in","C_in"},
    TEST     = {"A_in"},
    TESTSET  = {"A_out","B_in"},
}

-- Which opcodes are boundaries (cannot be absorbed; left for interpreter)
local BOUNDARY_OPS = {
    RETURN=true, RETURN0=true, RETURN1=true,
    CALL=true, TAILCALL=true,
    JMP=true, FORLOOP=true, FORPREP=true,
    TFORCALL=true, TFORLOOP=true,
}

-- Helper: generate a GETARG expression for a given operand role
local function getarg_for_role(role, ins_var)
    if role == "A_in" or role == "A_out" then
        return string.format("GETARG_A(%s)", ins_var)
    elseif role == "B_in" then
        return string.format("GETARG_B(%s)", ins_var)
    elseif role == "C_in" then
        return string.format("GETARG_C(%s)", ins_var)
    end
    return nil
end

-- Opcodes whose immediate field should be runtime-decoded (generic stencils)
local OPCODE_IMMEDIATE = {
    LOADI   = "GETARG_sBx(ctx->pc[%d])",
    LOADF   = "GETARG_sBx(ctx->pc[%d])",
    ADDI    = "GETARG_sC(ctx->pc[%d])",
    SHLI    = "GETARG_sC(ctx->pc[%d])",
    SHRI    = "GETARG_sC(ctx->pc[%d])",
    FORPREP = "GETARG_sBx(ctx->pc[%d])",
    JMP     = "GETARG_sBx(ctx->pc[%d])",
}

-- Resolve a slot name ("R0", "R1", etc.) to a GETARG expression by matching
-- the slot index against the opcode's specific operand values (a=2, b=0, c=1, etc.)
-- and consulting OPCODE_OPERANDS for the operand layout.
--
-- Example: ADD(a=2, b=0, c=1) with slot "R0" (idx=0) matches b=0 → GETARG_B
--          ADD(a=2, b=0, c=1) with slot "R2" (idx=2) matches a=2 → GETARG_A
-- node_op: "FrameLoad" (match _in roles) or "FrameStore" (match _out roles)
local function slot_to_getarg(slot_name, source_op, op_idx, node_op)
    local idx = tonumber(slot_name:match("^R(%d+)$"))
    if idx == nil then return nil, nil end  -- "cur" or unknown
    
    local opcode = type(source_op) == "table" and source_op.op or source_op
    local operands = OPCODE_OPERANDS[opcode] or {}
    
    -- Map operand role to the operand's actual register value and GETARG macro
    local role_info = {
        A_out = { val = source_op.a, macro = "GETARG_A" },
        A_in  = { val = source_op.a, macro = "GETARG_A" },
        B_in  = { val = source_op.b, macro = "GETARG_B" },
        C_in  = { val = source_op.c, macro = "GETARG_C" },
    }
    
    local match_suffix = (node_op == "FrameStore") and "_out" or "_in"
    
    for _, role in ipairs(operands) do
        if role:match(match_suffix .. "$") then
            local info = role_info[role]
            if info and info.val ~= nil and info.val == idx then
                return string.format("%s(ctx->pc[%d])", info.macro, op_idx), role
            end
        end
    end
    
    -- Fallback: emit as hardcoded index
    return tostring(idx), "hardcoded"
end

-- ── Analyze graph for opcode mapping ────────────────────────────────────

local function analyze_graph(g, source_ops)
    -- Map each node to its source opcode position (pc index within the window)
    local node_to_pc = {}  -- node.id -> { op_idx, opcode }
    for _, n in ipairs(g.nodes) do
        if not n.removed and n.source ~= nil then
            local src = n.source  -- 1-indexed
            local op_info = source_ops[src]  -- source_ops is 1-indexed
            if op_info then
                local oname = type(op_info) == "table" and op_info.op or tostring(op_info)
                node_to_pc[n.id] = { op_idx = src - 1, opcode = oname, op_info = op_info }
            end
        end
    end

    -- Find the first boundary in the opcode window
    local first_boundary = #source_ops
    for i, op in ipairs(source_ops) do
        local oname = type(op) == "table" and op.op or op
        if BOUNDARY_OPS[oname] then
            first_boundary = i - 1
            break
        end
    end

    -- Collect FrameLoad/FrameStore node info
    local load_store_info = {}
    for _, n in ipairs(g.nodes) do
        if not n.removed and (n.op == "FrameLoad" or n.op == "FrameStore") then
            local pc_info = node_to_pc[n.id]
            if pc_info then
                local slot_name = n.args and n.args.slot or "cur"
                local getarg_expr, arg_role = slot_to_getarg(slot_name, pc_info.op_info, pc_info.op_idx, n.op)
                if getarg_expr then
                    load_store_info[n.id] = {
                        getarg = getarg_expr,
                        role = arg_role,
                        slot_name = slot_name,
                        op_idx = pc_info.op_idx,
                    }
                else
                    -- Fallback: use slot index directly
                    local idx = tonumber(slot_name:match("^R(%d+)$")) or 0
                    load_store_info[n.id] = {
                        getarg = tostring(idx),
                        role = "hardcoded",
                        slot_name = slot_name,
                        op_idx = pc_info.op_idx,
                    }
                end
            else
                -- No source info — use hardcoded slot index
                local slot_name = n.args and n.args.slot or "cur"
                local idx = tonumber(slot_name:match("^R(%d+)$")) or 0
                load_store_info[n.id] = {
                    getarg = tostring(idx),
                    role = "hardcoded",
                    slot_name = slot_name,
                    op_idx = -1,
                }
            end
        end
    end

    return {
        n_total = #source_ops,
        n_absorbed = math.max(0, first_boundary),
        load_store_info = load_store_info,
        node_to_pc = node_to_pc,
    }
end

-- ── C code generation ───────────────────────────────────────────────────

local PUC_PREAMBLE = [[
/* PUC-Lua SponJIT monolithic stencil — StencilCtx ABI */
#include <stdint.h>
#include <stddef.h>

typedef struct TValue { unsigned long long value_; unsigned char tt_; } TValue;
typedef union StackValue { TValue val; } StackValue;
typedef StackValue *StkId;
typedef unsigned int Instruction;

#define LUA_VNIL       0
#define LUA_VFALSE     1
#define LUA_VTRUE      17
#define LUA_VNUMINT    3
#define LUA_VTABLE     69

#define s2v(o) (&(o)->val)
#define rawtt(o) ((o)->tt_)
#define ttisinteger(o) (rawtt(o) == LUA_VNUMINT)
#define ttistable(o)   (rawtt(o) == LUA_VTABLE)
#define ivalue(o) ((long long)((o)->value_))
#define setivalue(o,i) do { (o)->value_ = (unsigned long long)(i); (o)->tt_ = LUA_VNUMINT; } while (0)
#define setnilvalue(o) do { (o)->value_ = 0; (o)->tt_ = LUA_VNIL; } while (0)
#define setbfvalue(o)  do { (o)->value_ = 0; (o)->tt_ = LUA_VFALSE; } while (0)
#define setbtvalue(o)  do { (o)->value_ = 0; (o)->tt_ = LUA_VTRUE; } while (0)

#define POS_OP 0
#define POS_A  7
#define POS_B  16
#define POS_C  24
#define SIZE_OP 7

#define GET_OPCODE(i) ((int)(((i) >> POS_OP) & ((1u << SIZE_OP) - 1)))
#define GETARG_A(i)   ((int)(((i) >> POS_A) & 0xffu))
#define GETARG_B(i)   ((int)(((i) >> POS_B) & 0xffu))
#define GETARG_C(i)   ((int)(((i) >> POS_C) & 0xffu))
#define GETARG_Bx(i)  ((int)(((i) >> 15) & ((1u << 17) - 1)))    /* Bx at bit 15 (POS_k) */
#define GETARG_sBx(i) (GETARG_Bx(i) - 65535)    /* excess-K for 17-bit signed */
#define GETARG_sC(i)  (GETARG_C(i) - (((1u << 8) - 1) >> 1))

enum { SJ_OK = 0, SJ_GUARD_FAIL = 1, SJ_UNSUPPORTED = 2, SJ_BOUNDARY = 3 };

typedef struct {
    StkId              base;
    TValue            *k;
    const Instruction *pc;
    TValue            *current;
    long long          acc;
    int                status;
    int                load_count;
    int                store_count;
    int                unbox_count;
    TValue             scratch;
} StencilCtx;
]]

local TYPE_C = { TValue = "TValue *", I64 = "long long", F64 = "double", Bool = "int",
    PtrTable = "void *", PtrClosure = "void *", Unknown = "TValue *" }

local function var_name(val) return "v_" .. tostring(val.id):gsub("[^%w]", "_") end

local function value_expr(g, vid)
    local v = g.values[vid]
    if not v then return "NULL" end
    return var_name(v)
end

local function type_decl(v)
    local cty = TYPE_C[v.ty or "Unknown"] or "TValue *"
    return string.format("%s %s", cty, var_name(v))
end

function M.generate(ssa_result, source_ops, config)
    config = config or {}
    local g = ssa_result.graph
    source_ops = source_ops or ssa_result.source_ops or {}
    local info = analyze_graph(g, source_ops)

    local lines = {}
    local function emit(s) lines[#lines + 1] = s end

    -- Header comments
    local nf = table.concat(ssa_result.normal_form or {}, "|")
    local opnames = {}
    for _, op in ipairs(source_ops) do
        opnames[#opnames + 1] = type(op) == "table" and op.op or tostring(op)
    end
    emit(string.format("/* SponJIT mono stencil  NF=%s  nops=%d/%d  opcodes=%s */",
        nf, info.n_absorbed, info.n_total, table.concat(opnames, " ")))
    emit("")

    -- Preamble
    emit(PUC_PREAMBLE)
    emit("")

    -- Function signature
    local hash = (ssa_result.normal_form_hash or "00000000"):sub(1, 8)
    emit(string.format("void stencil_mono_%s(StencilCtx *ctx) {", hash))

    -- Declare local variables for SSA values
    local declared = {}
    for _, n in ipairs(g.nodes) do
        if not n.removed then
            for _, vid in ipairs(n.outputs or {}) do
                local v = g.values[vid]
                if v and not declared[vid] then
                    emit(string.format("    %s;", type_decl(v)))
                    declared[vid] = true
                end
            end
        end
    end
    emit("")

    -- Add __builtin_expect hint for the status check
    emit("    if (__builtin_expect(ctx->status != SJ_OK, 0)) return;")
    emit("")

    -- Emit nodes
    local skip_nodes = {}
    local forwarded = {}  -- boxed_value_vid -> raw_i64_expr_string
    for idx, n in ipairs(g.nodes) do
        if n.removed or skip_nodes[n.id] then goto continue end
        local op = n.op
        local args = n.args or {}
        local inputs = n.inputs or {}
        local outputs = n.outputs or {}
        local indent = "    "

        if op == "FrameLoad" then
            local ls = info.load_store_info[n.id]
            local slot_expr = "0"
            if ls then
                slot_expr = ls.getarg
            else
                local slot_name = args.slot or "cur"
                local sidx = tonumber(slot_name:match("^R(%d+)$")) or 0
                slot_expr = tostring(sidx)
            end
            local out_v = g.values[outputs[1]]
            local vn = var_name(out_v)
            emit(string.format("%s%s = s2v(ctx->base + (%s));", indent, vn, slot_expr))

        elseif op == "FrameStore" then
            local ls = info.load_store_info[n.id]
            local slot_expr = "0"
            if ls then
                slot_expr = ls.getarg
            else
                local slot_name = args.slot or "cur"
                local sidx = tonumber(slot_name:match("^R(%d+)$")) or 0
                slot_expr = tostring(sidx)
            end
            local vn = value_expr(g, inputs[1])
            emit(string.format("%s*s2v(ctx->base + (%s)) = *%s;", indent, slot_expr, vn))

        elseif op == "GuardTypeI64" then
            local vn = value_expr(g, inputs[1])
            emit(string.format("%sif (__builtin_expect(!ttisinteger(%s), 0)) { ctx->status = SJ_GUARD_FAIL; return; }", indent, vn))

        elseif op == "GuardTable" then
            local vn = value_expr(g, inputs[1])
            emit(string.format("%sif (__builtin_expect(!ttistable(%s), 0)) { ctx->status = SJ_GUARD_FAIL; return; }", indent, vn))

        elseif string.match(op, "^Guard") then
            emit(string.format("%s/* %s — unsupported */", indent, op))
            emit(string.format("%sctx->status = SJ_UNSUPPORTED; return;", indent))

        elseif op == "UnboxI64" then
            local vn = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            -- If the boxed value was fused with its store, use raw value directly
            local raw = forwarded[inputs[1]]
            if raw then
                emit(string.format("%s%s = %s;", indent, oname, raw))
            else
                emit(string.format("%s%s = ivalue(%s);", indent, oname, vn))
            end

        elseif op == "BoxI64" then
            local in_v = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            -- Check if the next active node is FrameStore consuming this value.
            local store_slot_expr = nil
            local store_id = nil
            for j = idx + 1, #g.nodes do
                local m = g.nodes[j]
                if not m.removed then
                    if m.op == "FrameStore" and m.inputs and m.inputs[1] == outputs[1] then
                        store_id = m.id
                        local ls = info.load_store_info[m.id]
                        store_slot_expr = ls and ls.getarg or "0"
                    end
                    break
                end
            end
            if store_slot_expr then
                -- Fuse: direct field write. Keep scratch if other nodes consume the boxed value.
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
                    -- Need scratch for subsequent consumers (guards, etc.)
                    emit(string.format("%ssetivalue(&ctx->scratch, %s); %s = &ctx->scratch;", indent, in_v, oname))
                end
                emit(string.format("%ss2v(ctx->base + (%s))->value_ = (unsigned long long)(%s);", indent, store_slot_expr, in_v))
                emit(string.format("%ss2v(ctx->base + (%s))->tt_ = 3;", indent, store_slot_expr))
                if outputs[1] then
                    forwarded[outputs[1]] = in_v
                end
                skip_nodes[store_id] = true
            else
                emit(string.format("%ssetivalue(&ctx->scratch, %s); %s = &ctx->scratch;", indent, in_v, oname))
            end

        elseif op == "AddI64" then
            local lhs = value_expr(g, inputs[1])
            local rhs = value_expr(g, inputs[2])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%s%s = %s + %s;", indent, oname, lhs, rhs))

        elseif op == "SubI64" then
            local lhs = value_expr(g, inputs[1])
            local rhs = value_expr(g, inputs[2])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%s%s = %s - %s;", indent, oname, lhs, rhs))

        elseif op == "MulI64" then
            local lhs = value_expr(g, inputs[1])
            local rhs = value_expr(g, inputs[2])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%s%s = %s * %s;", indent, oname, lhs, rhs))

        elseif op == "LoadConst" then
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%s%s = ctx->k + GETARG_Bx(ctx->pc[0]);", indent, oname))

        elseif op == "ConstI64" then
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            -- Check if this came from an opcode with a runtime immediate field
            local pc_info = info.node_to_pc[n.id]
            if pc_info then
                local imm_fmt = OPCODE_IMMEDIATE[pc_info.opcode]
                if imm_fmt then
                    emit(string.format("%s%s = %s;", indent, oname, string.format(imm_fmt, pc_info.op_idx)))
                    goto handled
                end
            end
            -- Fallback: use the decoded value from SSA
            local val = tonumber(args.value) or 0
            emit(string.format("%s%s = %dLL;", indent, oname, val))
            ::handled::

        elseif op == "ConstNil" then
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%ssetnilvalue(&ctx->scratch); %s = &ctx->scratch;", indent, oname))

        elseif op == "ConstBool" then
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%sif (GET_OPCODE(ctx->pc[0]) == OP_LOADTRUE) setbtvalue(&ctx->scratch); else setbfvalue(&ctx->scratch); %s = &ctx->scratch;", indent, oname))

        elseif op == "Move" then
            local vn = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%s%s = %s;", indent, oname, vn))

        elseif op == "Return1" or op == "Return0" or op == "Jump" or op == "Call" or op == "KnownCall" or op == "TailCall" then
            emit(string.format("%s/* boundary: %s — let interpreter handle it */", indent, op))

        elseif op == "Residual" then
            emit(string.format("%sctx->status = SJ_UNSUPPORTED; return;", indent))

        elseif op == "BarrierCheck" then
            emit(string.format("%sctx->status = SJ_UNSUPPORTED; return;", indent))

        elseif op == "FieldLoad" or op == "FieldStore" or op == "ArrayLoad" or op == "ArrayStore" then
            emit(string.format("%s/* %s — unsupported */", indent, op))
            emit(string.format("%sctx->status = SJ_UNSUPPORTED; return;", indent))

        else
            emit(string.format("%s/* UNLOWERED: %s */", indent, op))
            emit(string.format("%sctx->status = SJ_UNSUPPORTED; return;", indent))
        end

        ::continue::
    end

    -- Success: advance pc past absorbed opcodes
    emit("")
    emit(string.format("    ctx->pc += %d;", info.n_absorbed))
    emit("    ctx->status = SJ_OK;")
    emit("}")

    return {
        c_code = table.concat(lines, "\n"),
        n_absorbed = info.n_absorbed,
        n_total = info.n_total,
        node_count = (function()
            local c = 0
            for _, n in ipairs(g.nodes) do if not n.removed then c = c + 1 end end
            return c
        end)(),
    }
end

function M.compile_to_file(ssa_result, source_ops, out_path, config)
    local result = M.generate(ssa_result, source_ops, config)
    if not result then return nil, "generation failed" end
    local f, err = io.open(out_path, "w")
    if not f then return nil, err end
    f:write(result.c_code)
    f:close()
    return result
end

return M
