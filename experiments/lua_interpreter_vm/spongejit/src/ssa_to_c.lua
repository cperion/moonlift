-- ssa_to_c.lua — Compile an optimized SSA graph to a monolithic C function
-- in the StencilCtx ABI (compatible with stencils_puc.c / sponjit_block.h).
--
-- ONE SSA sponge → ONE C function → gcc -O2 -c → ONE binary stencil → plug into real VM.
--
-- ABI (from stencils_puc.c):
--   void stencil_mono_HASH(StencilCtx *ctx)
--   - reads slots via ctx->base + slot_index  (slot index from source opcode operands)
--   - TValue is struct { value_; tt_ } with separate tag byte
--   - guards: ctx->status = SJ_GUARD_FAIL; return;
--   - success: ctx->pc += n_absorbed; ctx->status = SJ_OK;
--   - boundary ops (RETURN, CALL, JMP) are NOT absorbed; stencil stops before them.
--
-- No holes. No externs. Slot indices decoded from the known opcode operands at codegen time.

local IR = require("src.ssa_ir")

local M = {}

-- ── PUC Lua opcode operand decoding ─────────────────────────────────────
-- Knowing the opcode and which operand position, we emit GETARG_* macros.

local OPCODE_OPERANDS = {
    -- { out_slot, in_slots... }  where nil means "no slot" (constant/immediate)
    MOVE     = {"A","B"},
    LOADI    = {"A"},         -- sBx = immediate constant
    LOADF    = {"A"},
    LOADK    = {"A"},         -- Bx = constant table index
    LOADTRUE = {"A"},
    LOADFALSE= {"A"},
    LOADNIL  = {"A"},
    ADD      = {"A","B","C"},
    ADDI     = {"A","B"},     -- sC = immediate
    SUB      = {"A","B","C"},
    MUL      = {"A","B","C"},
    DIV      = {"A","B","C"},
    MOD      = {"A","B","C"},
    GETFIELD = {"A","B"},     -- C = constant key index
    GETTABUP = {"A","B"},     -- C = constant key index
    SELF     = {"A","B"},     -- C = constant key index
    SETFIELD = {"A","B","C"}, -- A=table, B=field key, C=value
    SETTABUP = {"A","B","C"},
    GETTABLE = {"A","B","C"}, -- C = register key
    GETI     = {"A","B"},     -- C = immediate?
    SETTABLE = {"A","B","C"},
    SETI     = {"A","B","C"},
    CALL     = {"A"},         -- A = function + nresults
    TAILCALL = {"A"},
    RETURN   = {"A"},
    RETURN0  = {},
    RETURN1  = {"A"},
    JMP      = {},            -- sBx = offset (not a slot)
    EQ       = {"A","B","C"}, -- A is bool output
    LT       = {"A","B","C"},
    LE       = {"A","B","C"},
    TEST     = {"A"},         -- A = condition, C = 0/1
    TESTSET  = {"A","B"},     -- C = 0/1
    FORLOOP  = {"A"},         -- A = internal index (complex)
    FORPREP  = {"A"},
    TFORCALL = {"A"},         -- C = nresults?
    TFORLOOP = {"A"},
    SETLIST  = {"A","B","C"}, -- complex, A=table, B=base, C=count
    CONCAT   = {"A","B","C"},
    CLOSURE  = {"A"},         -- Bx = proto index
    VARARG   = {"A"},         -- B = nresults?
    NEWTABLE = {"A"},         -- B/C = array/hash size hints
    LEN      = {"A","B"},
    GETUPVAL = {"A","B"},
    SETUPVAL = {"A","B"},
    NOT      = {"A","B"},
    UNM      = {"A","B"},
    BNOT     = {"A","B"},
    CLOSE    = {"A"},
    TBC      = {"A"},
    MMBIN    = {"A","B","C"},
    MMBINI   = {"A","B"},     -- sC = immediate
    MMBINK   = {"A","B"},     -- C = constant
    EXTRAARG = {},
}

-- Which opcodes are boundaries (cannot be absorbed; left for interpreter)
local BOUNDARY_OPS = {
    RETURN=true, RETURN0=true, RETURN1=true,
    CALL=true, TAILCALL=true,
    JMP=true, FORLOOP=true, FORPREP=true,
    TFORCALL=true, TFORLOOP=true,
}

-- Which operand slot positions are the "output" (A) slot
local function slot_arg_type(pos, opcode)
    local slots = OPCODE_OPERANDS[opcode] or {}
    if pos > #slots then return nil end
    local arg = slots[pos]
    if arg == "A" then return "out"
    elseif arg == "B" or arg == "C" then return "in"
    else return nil
    end
end

-- GETARG macro for a specific operand position in the instruction
local function getarg_expr(opcode, pos, ins_var)
    local slots = OPCODE_OPERANDS[opcode] or {}
    if pos > #slots then return nil end
    local arg = slots[pos]
    if arg == "A" then return string.format("GETARG_A(%s)", ins_var)
    elseif arg == "B" then return string.format("GETARG_B(%s)", ins_var)
    elseif arg == "C" then return string.format("GETARG_C(%s)", ins_var)
    else return nil
    end
end

-- ── collect the opcode window and slot info from the SSA graph ──────────

local function analyze_graph(g, source_ops)
    -- source_ops: array of {op="ADD", a=..., b=..., c=...} from the original bytecode window
    -- Returns: { n_total = N, absorbed = M, slot_names = {[node_id]="R0"}, ... }

    -- Find the first boundary opcode position (0-indexed within source_ops)
    local first_boundary = #source_ops  -- default: absorb all
    for i, op in ipairs(source_ops) do
        local opname = type(op) == "table" and op.op or op
        if BOUNDARY_OPS[opname] then
            first_boundary = i - 1  -- ops before the boundary
            break
        end
    end

    -- Collect which source opcode each FrameLoad/FrameStore belongs to
    -- FrameLoad/FrameStore nodes have args.slot with the decoded slot name
    local slot_of_node = {}

    -- Map from source pc to opcode info
    local ops_by_pc = {}
    for i, op in ipairs(source_ops) do
        ops_by_pc[i - 1] = op  -- pc is 0-indexed
    end

    -- Walk active nodes, find FrameLoad/FrameStore, determine their slot and opcode
    local load_nodes = {}  -- {node_id = {slot_idx, opcode_name, pc}}
    local store_nodes = {}

    local current_pc = 0  -- rough heuristic: advance pc at FrameStore
    for _, n in ipairs(g.nodes) do
        if not n.removed then
            local src = n.source  -- pc from SSA lift
            if n.op == "FrameLoad" and n.args and n.args.slot then
                local slot_name = n.args.slot
                local idx = tonumber(slot_name:match("^R(%d+)$")) or 0
                slot_of_node[n.id] = { idx = idx, name = slot_name }
                load_nodes[#load_nodes + 1] = { node_id = n.id, slot_idx = idx, slot_name = slot_name }
            elseif n.op == "FrameStore" and n.args and n.args.slot then
                local slot_name = n.args.slot
                local idx = tonumber(slot_name:match("^R(%d+)$")) or 0
                slot_of_node[n.id] = { idx = idx, name = slot_name }
                store_nodes[#store_nodes + 1] = { node_id = n.id, slot_idx = idx, slot_name = slot_name }
            end
        end
    end

    -- Collect all distinct slots used (for local variable naming)
    local slots_used = {}
    for _, info in pairs(slot_of_node) do
        slots_used[info.name] = true
    end

    return {
        n_total = #source_ops,
        n_absorbed = math.max(0, first_boundary),
        slot_of_node = slot_of_node,
        load_nodes = load_nodes,
        store_nodes = store_nodes,
        slots_used = slots_used,
    }
end

-- ── C code generation ───────────────────────────────────────────────────

local PUC_PREAMBLE = [[
/* PUC-Lua SponJIT monolithic region stencil — StencilCtx ABI */
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
#define GETARG_Bx(i)  ((int)(((i) >> POS_B) & ((1u << 17) - 1)))
#define GETARG_sBx(i) (GETARG_Bx(i) - (((1u << 17) - 1) >> 1))
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
    local info = analyze_graph(g, source_ops or ssa_result.source_ops or {})

    local lines = {}
    local function emit(s) lines[#lines + 1] = s end

    -- Preamble
    local nf = table.concat(ssa_result.normal_form or {}, "|")
    local ops_str = table.concat(ssa_result.active_ops or {}, " ")
    emit(string.format("/* SponJIT mono stencil  NF=%s  nops=%d/%d */", nf, info.n_absorbed, info.n_total))
    emit(string.format("/* active: %s */", ops_str))
    emit("")
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

    -- Declare slot pointer locals
    for _, info_slot in pairs(info.slot_of_node) do
        local vname = string.format("slot_%s", info_slot.name)
        if not declared[vname] then
            emit(string.format("    TValue *%s;", vname))
            declared[vname] = true
        end
    end
    emit("")

    -- Load instruction (first opcode)
    local first_op = (source_ops or {})[1]
    local first_opname = type(first_op) == "table" and first_op.op or "?"
    emit(string.format("    Instruction ins = ctx->pc[0];  /* %s */", first_opname))
    emit(string.format("    (void)ins;"))
    emit("")

    -- Early exit: if ctx->status != SJ_OK from a prior substencil miss, bail
    emit("    if (ctx->status != SJ_OK) return;")
    emit("")

    -- Emit nodes
    for _, n in ipairs(g.nodes) do
        if n.removed then goto continue end
        local op = n.op
        local args = n.args or {}
        local inputs = n.inputs or {}
        local outputs = n.outputs or {}
        local indent = "    "

        if op == "FrameLoad" then
            local slot_info = info.slot_of_node[n.id]
            local sidx = slot_info and slot_info.idx or 0
            local sname = slot_info and slot_info.name or "cur"
            local out_v = g.values[outputs[1]]
            local vn = var_name(out_v)
            emit(string.format("%s%s = s2v(ctx->base + %d);  /* slot %s */", indent, vn, sidx, sname))

        elseif op == "FrameStore" then
            local slot_info = info.slot_of_node[n.id]
            local sidx = slot_info and slot_info.idx or 0
            local sname = slot_info and slot_info.name or "cur"
            local vn = value_expr(g, inputs[1])
            emit(string.format("%s*s2v(ctx->base + %d) = *%s;  /* slot %s */", indent, sidx, vn, sname))

        elseif op == "GuardTypeI64" then
            local vn = value_expr(g, inputs[1])
            emit(string.format("%sif (!ttisinteger(%s)) { ctx->status = SJ_GUARD_FAIL; return; }", indent, vn))

        elseif op == "GuardTable" then
            local vn = value_expr(g, inputs[1])
            emit(string.format("%sif (!ttistable(%s)) { ctx->status = SJ_GUARD_FAIL; return; }", indent, vn))

        elseif string.match(op, "^Guard") then
            -- GuardShape, GuardMetatableAbsent, GuardCallTarget, GuardArrayHit, GuardBounds
            emit(string.format("%s/* %s — unsupported, residualize */", indent, op))
            emit(string.format("%sctx->status = SJ_UNSUPPORTED; return;", indent))

        elseif op == "UnboxI64" then
            local vn = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%s%s = ivalue(%s);", indent, oname, vn))

        elseif op == "BoxI64" then
            local in_v = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%ssetivalue(&ctx->scratch, %s); %s = &ctx->scratch;", indent, in_v, oname))

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
            local val = tonumber(args.value) or 0
            emit(string.format("%s%s = %dLL;", indent, oname, val))

        elseif op == "ConstNil" then
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%ssetnilvalue(&ctx->scratch); %s = &ctx->scratch;", indent, oname))

        elseif op == "ConstBool" then
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%sif (GET_OPCODE(ctx->pc[0]) == OP_LOADTRUE) setbtvalue(&ctx->scratch); else setbfvalue(&ctx->scratch); %s = &ctx->scratch;", indent, oname))

        elseif op == "Move" then
            -- Value forwarding, usually eliminated by SSA. If present, copy pointer.
            local vn = value_expr(g, inputs[1])
            local out_v = g.values[outputs[1]]
            local oname = var_name(out_v)
            emit(string.format("%s%s = %s;", indent, oname, vn))

        elseif op == "Return1" or op == "Return0" or op == "Jump" or op == "Call" or op == "KnownCall" or op == "TailCall" then
            -- Boundary: stop here. The interpreter handles this opcode.
            emit(string.format("%s/* boundary: %s — let interpreter handle it */", indent, op))

        elseif op == "Residual" then
            emit(string.format("%s/* residual boundary */", indent))
            emit(string.format("%sctx->status = SJ_UNSUPPORTED; return;", indent))

        elseif op == "BarrierCheck" then
            emit(string.format("%s/* barrier — unsupported */", indent))
            emit(string.format("%sctx->status = SJ_UNSUPPORTED; return;", indent))

        elseif op == "FieldLoad" or op == "FieldStore" or op == "ArrayLoad" or op == "ArrayStore" then
            emit(string.format("%s/* %s — unsupported (table access) */", indent, op))
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
