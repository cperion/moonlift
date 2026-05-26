-- candidate_emit.lua
-- Emits low-level Moonlift stencil kernels from candidate descriptions.
-- The emitted kernels are self-contained object-emission units with the same
-- leading VM product layout as experiments/lua_interpreter_vm/src/products.lua.

local M = {}
local util = require("tools.jit_harness.util")
local lowering_plan = require("tools.jit_harness.lowering_plan")

local TAG_NIL = 0
local TAG_FALSE = 1
local TAG_TRUE = 2
local TAG_INTEGER = 4
local TAG_NUM = 5
local TAG_STR = 6
local TAG_TABLE = 7
local TAG_LCLOSURE = 8
local TAG_CCLOSURE = 9

local function sanitize(name)
    name = tostring(name or "kernel"):gsub("[^%w_]", "_")
    if name:match("^%d") then name = "k_" .. name end
    return name
end

local function op_list(candidate)
    if candidate.ops and #candidate.ops > 0 then return candidate.ops end
    local name = candidate.name or candidate.id or ""
    local ops = {}
    for op in tostring(name):gmatch("[A-Z][A-Z0-9_]*") do table.insert(ops, op) end
    if #ops == 0 then ops[1] = name end
    return ops
end

local function emit_header(candidate, kernel_name)
    local s = {}
    s[#s + 1] = "-- Auto-generated Lua VM JIT stencil kernel"
    s[#s + 1] = "-- Candidate: " .. tostring(candidate.id or "unknown")
    s[#s + 1] = "-- Ops: " .. table.concat(op_list(candidate), ",")
    s[#s + 1] = "-- Shape: " .. tostring(candidate.shape_kind or "unspecified")
    s[#s + 1] = "-- Lowering: " .. tostring(candidate.lowering or candidate.rewrite_kind or "generic_opcode_sequence")
    s[#s + 1] = "-- Continuation: " .. tostring(candidate.continuation or "unspecified")
    s[#s + 1] = "-- ABI: jit_stencil_v0(L, frame, code, constants, pc, base, top) -> next_pc_or_side_exit_pc"
    s[#s + 1] = ""
    s[#s + 1] = "struct Value tag: u32; aux: u32; bits: u64 end"
    s[#s + 1] = "struct GCHeader next: ptr(GCHeader); tt: u8; marked: u8 end"
    s[#s + 1] = "struct String gc: GCHeader; reserved: u8; hash: u32; len: index; bytes: ptr(u8) end"
    s[#s + 1] = "struct Node key: Value; value: Value; next: ptr(Node) end"
    s[#s + 1] = "struct Table gc: GCHeader; flags: u32; array_len: index; array: ptr(Value); node_mask: u32; nodes: ptr(Node); lastfree: ptr(Node); metatable: ptr(Table); shape_epoch: u32 end"
    s[#s + 1] = "struct Instr word: u32 end"
    s[#s + 1] = "struct Frame closure: Value; base: index; top: index; pc: index; wanted: i32; tailcalls: i32; resume_mode: u16; resume_a: u16; resume_b: u16; resume_c: u16; resume_pc: index; resume_base: index; resume_value: Value end"
    -- Leading layout matches LuaThread through the fields touched by stencils.
    s[#s + 1] = "struct LuaThread gc_next: ptr(u8); gc_tt: u8; gc_marked: u8; status: u8; stack: ptr(Value); stack_size: index; top: index; frames: ptr(Frame); frame_count: index; frame_cap: index end"
    s[#s + 1] = ""
    s[#s + 1] = "func stencil_" .. kernel_name .. "(L: ptr(LuaThread), frame: ptr(Frame), code: ptr(Instr), constants: ptr(Value), pc: index, base: index, top: index) -> index"
    return table.concat(s, "\n") .. "\n"
end

local function decode_lines(i, pc_expr)
    return string.format([[    let word_%d: u32 = code[%s].word
    let a_%d: index = as(index, (word_%d >> 7) & 255)
    let b_%d: index = as(index, (word_%d >> 16) & 255)
    let c_%d: index = as(index, (word_%d >> 24) & 255)
    let k_%d: u8 = as(u8, (word_%d >> 15) & 1)
    let bx_%d: index = as(index, (word_%d >> 15) & 131071)
    let sbx_%d: i32 = as(i32, (word_%d >> 15) & 131071) - 65535
]], i, pc_expr, i, i, i, i, i, i, i, i, i, i, i, i)
end

local function emit_const_string_field_get(i, obj_expr, key_expr, dst_expr, exit_pc)
    return string.format([[    let obj_%d: ptr(Value) = %s
    let key_%d: ptr(Value) = %s
    if obj_%d.tag ~= %d then return %s end
    if key_%d.tag ~= %d then return %s end
    let table_%d: ptr(Table) = as(ptr(Table), obj_%d.bits)
    if table_%d.metatable ~= nil then return %s end
    if table_%d.nodes == nil then return %s end
    let keystr_%d: ptr(String) = as(ptr(String), key_%d.bits)
    let bucket_%d: index = as(index, keystr_%d.hash & table_%d.node_mask)
    let node_%d: ptr(Node) = table_%d.nodes + bucket_%d
    if node_%d.key.tag ~= %d then return %s end
    if node_%d.key.bits ~= key_%d.bits then return %s end
    if node_%d.value.tag == %d then return %s end
    %s = node_%d.value
]], i, obj_expr,
        i, key_expr,
        i, TAG_TABLE, exit_pc,
        i, TAG_STR, exit_pc,
        i, i,
        i, exit_pc,
        i, exit_pc,
        i, i,
        i, i, i,
        i, i, i,
        i, TAG_STR, exit_pc,
        i, i, exit_pc,
        i, TAG_NIL, exit_pc,
        dst_expr, i)
end

local function emit_table_get(i, obj_expr, key_expr, dst_expr, exit_pc)
    return string.format([[    let obj_%d: ptr(Value) = %s
    let key_%d: ptr(Value) = %s
    if obj_%d.tag ~= %d then return %s end
    let table_%d: ptr(Table) = as(ptr(Table), obj_%d.bits)
    if table_%d.metatable ~= nil then return %s end
    if key_%d.tag == %d then
        let idx_%d: i64 = as(i64, key_%d.bits)
        if idx_%d <= 0 then return %s end
        if as(index, idx_%d) > table_%d.array_len then return %s end
        let arrv_%d: Value = table_%d.array[as(index, idx_%d - 1)]
        if arrv_%d.tag == %d then return %s end
        %s = arrv_%d
        return %s + 1
    end
    if key_%d.tag ~= %d then return %s end
    if table_%d.nodes == nil then return %s end
    let keystr_%d: ptr(String) = as(ptr(String), key_%d.bits)
    let bucket_%d: index = as(index, keystr_%d.hash & table_%d.node_mask)
    let node_%d: ptr(Node) = table_%d.nodes + bucket_%d
    if node_%d.key.tag ~= %d then return %s end
    if node_%d.key.bits ~= key_%d.bits then return %s end
    if node_%d.value.tag == %d then return %s end
    %s = node_%d.value
]], i, obj_expr,
        i, key_expr,
        i, TAG_TABLE, exit_pc,
        i, i,
        i, exit_pc,
        i, TAG_INTEGER,
        i, i,
        i, exit_pc,
        i, i, exit_pc,
        i, i, i,
        i, TAG_NIL, exit_pc,
        dst_expr, i,
        exit_pc,
        i, TAG_STR, exit_pc,
        i, exit_pc,
        i, i,
        i, i, i,
        i, i, i,
        i, TAG_STR, exit_pc,
        i, i, exit_pc,
        i, TAG_NIL, exit_pc,
        dst_expr, i)
end

local function emit_eq_branch(i, lhs_expr, rhs_expr, sense_expr, exit_pc)
    return string.format([[    let eqlhs_%d: ptr(Value) = %s
    let eqrhs_%d: ptr(Value) = %s
    var is_eq_%d: bool = false
    if eqlhs_%d.tag ~= eqrhs_%d.tag then
        if eqlhs_%d.tag == %d then return %s end
        if eqrhs_%d.tag == %d then return %s end
        is_eq_%d = false
    end
    if eqlhs_%d.tag == eqrhs_%d.tag then
        if eqlhs_%d.tag == %d then return %s end
        if eqlhs_%d.tag == %d then return %s end
        if eqlhs_%d.tag == %d then return %s end
        if eqlhs_%d.tag == %d then is_eq_%d = true end
        if eqlhs_%d.tag == %d then is_eq_%d = true end
        if eqlhs_%d.tag == %d then is_eq_%d = true end
        if eqlhs_%d.tag == %d then is_eq_%d = eqlhs_%d.bits == eqrhs_%d.bits end
        if eqlhs_%d.tag == %d then is_eq_%d = eqlhs_%d.bits == eqrhs_%d.bits end
    end
    if is_eq_%d == (%s) then return %s + 2 end
    return %s + 1
]], i, lhs_expr,
        i, rhs_expr,
        i,
        i, i,
        i, TAG_NUM, exit_pc,
        i, TAG_NUM, exit_pc,
        i,
        i, i,
        i, TAG_TABLE, exit_pc,
        i, TAG_NUM, exit_pc,
        i, TAG_STR, exit_pc,
        i, TAG_NIL, i,
        i, TAG_FALSE, i,
        i, TAG_TRUE, i,
        i, TAG_INTEGER, i, i, i,
        i, TAG_STR, i, i, i,
        i, sense_expr, exit_pc, exit_pc)
end

local function emit_lt_branch(i, lhs_expr, rhs_expr, sense_expr, exit_pc)
    return string.format([[    let ltlhs_%d: ptr(Value) = %s
    let ltrhs_%d: ptr(Value) = %s
    if ltlhs_%d.tag ~= %d then return %s end
    if ltrhs_%d.tag ~= %d then return %s end
    let is_lt_%d: bool = as(i64, ltlhs_%d.bits) < as(i64, ltrhs_%d.bits)
    if is_lt_%d == (%s) then return %s + 2 end
    return %s + 1
]], i, lhs_expr,
        i, rhs_expr,
        i, TAG_INTEGER, exit_pc,
        i, TAG_INTEGER, exit_pc,
        i, i, i,
        i, sense_expr, exit_pc, exit_pc)
end

local function fact_kind_for(candidate, op, ordinal)
    local seen = 0
    for _, f in ipairs(candidate.facts or {}) do
        if f.op == op then
            seen = seen + 1
            if seen == ordinal then return f.kind end
        end
    end
    return nil
end

local function op_ordinal(ops, idx)
    local count = 0
    for j = 1, idx do if ops[j] == ops[idx] then count = count + 1 end end
    return count
end

local function emit_op(candidate, op, i, pc_expr)
    op = tostring(op or "")
    local s = { decode_lines(i, pc_expr) }
    local kind = fact_kind_for(candidate, op, op_ordinal(candidate.ops or {}, i)) or "generic"
    local function add(x) s[#s + 1] = x end

    if op == "MOVE" then
        add(string.format("    L.stack[base + a_%d] = L.stack[base + b_%d]\n", i, i))
    elseif op == "LOADI" then
        add(string.format("    L.stack[base + a_%d].tag = %d\n", i, TAG_INTEGER))
        add(string.format("    L.stack[base + a_%d].aux = 0\n", i))
        add(string.format("    L.stack[base + a_%d].bits = as(u64, as(i64, sbx_%d))\n", i, i))
    elseif op == "LOADF" then
        add(string.format("    L.stack[base + a_%d].tag = %d\n", i, TAG_NUM))
        add(string.format("    L.stack[base + a_%d].aux = 0\n", i))
        add(string.format("    L.stack[base + a_%d].bits = as(u64, as(f64, sbx_%d))\n", i, i))
    elseif op == "LOADK" then
        add(string.format("    L.stack[base + a_%d] = constants[bx_%d]\n", i, i))
    elseif op == "LOADFALSE" then
        add(string.format("    L.stack[base + a_%d].tag = %d\n    L.stack[base + a_%d].aux = 0\n    L.stack[base + a_%d].bits = 0\n", i, TAG_FALSE, i, i))
    elseif op == "LOADTRUE" then
        add(string.format("    L.stack[base + a_%d].tag = %d\n    L.stack[base + a_%d].aux = 0\n    L.stack[base + a_%d].bits = 1\n", i, TAG_TRUE, i, i))
    elseif op == "LOADNIL" then
        add(string.format("    L.stack[base + a_%d].tag = %d\n    L.stack[base + a_%d].aux = 0\n    L.stack[base + a_%d].bits = 0\n", i, TAG_NIL, i, i))
    elseif op == "GETFIELD" then
        if kind ~= "raw_string_slot" then add("    return " .. pc_expr .. "\n")
        else
            add(emit_const_string_field_get(i,
                string.format("L.stack + (base + b_%d)", i),
                string.format("constants + c_%d", i),
                string.format("L.stack[base + a_%d]", i),
                pc_expr))
        end
    elseif op == "GETTABLE" then
        if kind ~= "raw_array_i64" and kind ~= "raw_string_slot" then add("    return " .. pc_expr .. "\n")
        else
            add(emit_table_get(i,
                string.format("L.stack + (base + b_%d)", i),
                string.format("L.stack + (base + c_%d)", i),
                string.format("L.stack[base + a_%d]", i),
                pc_expr))
        end
    elseif op == "SELF" then
        if kind ~= "raw_string_slot" then add("    return " .. pc_expr .. "\n")
        else
            add(string.format("    L.stack[base + a_%d + 1] = L.stack[base + b_%d]\n", i, i))
            add(emit_const_string_field_get(i,
                string.format("L.stack + (base + b_%d)", i),
                string.format("constants + c_%d", i),
                string.format("L.stack[base + a_%d]", i),
                pc_expr))
        end
    elseif op == "ADDI" then
        if kind ~= "i64" and kind ~= "i64_result_dead" then add("    return " .. pc_expr .. "\n")
        elseif kind == "i64_result_dead" then add("    -- pure ADDI result dead under liveness fact: rewrite to empty\n")
        else
            add(string.format("    let lhs_%d: ptr(Value) = L.stack + (base + b_%d)\n", i, i))
            add(string.format("    if lhs_%d.tag ~= %d then return %s end\n", i, TAG_INTEGER, pc_expr))
            add(string.format("    L.stack[base + a_%d].tag = %d\n", i, TAG_INTEGER))
            add(string.format("    L.stack[base + a_%d].aux = 0\n", i))
            add(string.format("    L.stack[base + a_%d].bits = lhs_%d.bits + as(u64, as(i32, c_%d))\n", i, i, i))
        end
    elseif op == "EQ" then
        if kind ~= "primitive_eq" and kind ~= "i64_eq" then add("    return " .. pc_expr .. "\n")
        else
            add(emit_eq_branch(i,
                string.format("L.stack + (base + b_%d)", i),
                string.format("L.stack + (base + c_%d)", i),
                string.format("a_%d ~= 0", i),
                pc_expr))
        end
    elseif op == "EQK" then
        if kind ~= "primitive_eq" and kind ~= "i64_eq" then add("    return " .. pc_expr .. "\n")
        else
            add(emit_eq_branch(i,
                string.format("L.stack + (base + a_%d)", i),
                string.format("constants + bx_%d", i),
                string.format("k_%d == 0", i),
                pc_expr))
        end
    elseif op == "LT" then
        if kind ~= "i64_compare" then add("    return " .. pc_expr .. "\n")
        else
            add(emit_lt_branch(i,
                string.format("L.stack + (base + b_%d)", i),
                string.format("L.stack + (base + c_%d)", i),
                string.format("a_%d ~= 0", i),
                pc_expr))
        end
    elseif op == "ADD" or op == "SUB" or op == "MUL" then
        if kind ~= "i64" and kind ~= "i64_result_dead" then add("    return " .. pc_expr .. "\n")
        elseif kind == "i64_result_dead" then add("    -- pure arithmetic result dead under liveness fact: rewrite to empty\n")
        else
            add(string.format("    let lhs_%d: ptr(Value) = L.stack + (base + b_%d)\n", i, i))
            add(string.format("    let rhs_%d: ptr(Value) = L.stack + (base + c_%d)\n", i, i))
            add(string.format("    if lhs_%d.tag ~= %d then return %s end\n", i, TAG_INTEGER, pc_expr))
            add(string.format("    if rhs_%d.tag ~= %d then return %s end\n", i, TAG_INTEGER, pc_expr))
            add(string.format("    let lx_%d: i64 = as(i64, lhs_%d.bits)\n", i, i))
            add(string.format("    let ry_%d: i64 = as(i64, rhs_%d.bits)\n", i, i))
            local expr = op == "ADD" and string.format("lx_%d + ry_%d", i, i) or op == "SUB" and string.format("lx_%d - ry_%d", i, i) or string.format("lx_%d * ry_%d", i, i)
            add(string.format("    L.stack[base + a_%d].tag = %d\n", i, TAG_INTEGER))
            add(string.format("    L.stack[base + a_%d].aux = 0\n", i))
            add(string.format("    L.stack[base + a_%d].bits = as(u64, %s)\n", i, expr))
        end
    elseif op == "RETURN0" then
        add(string.format("    frame.pc = %s + 1\n    L.top = base\n    return %s + 1\n", pc_expr, pc_expr))
    elseif op == "RETURN1" then
        add(string.format("    frame.pc = %s + 1\n    L.top = base + a_%d + 1\n    return %s + 1\n", pc_expr, i, pc_expr))
    elseif op == "CALL" or op == "TAILCALL" or op == "SETFIELD" or op == "SETTABLE" or op == "LE" or op == "TEST" or op == "FORPREP" or op == "FORLOOP" or op == "CLOSURE" or op == "NEWTABLE" then
        add("    -- Effectful/control opcode boundary: side-exit to interpreter at this pc.\n")
        add("    return " .. pc_expr .. "\n")
    else
        add("    -- Unsupported opcode boundary: side-exit to interpreter at this pc.\n")
        add("    return " .. pc_expr .. "\n")
    end
    return table.concat(s)
end

local function emit_rewrite_body(candidate, ops)
    local rk = candidate.rewrite_kind
    local parts = { emit_header(candidate, sanitize(candidate.id or candidate.name or "kernel")) }
    parts[#parts + 1] = decode_lines(1, "pc")
    if #ops >= 2 then parts[#parts + 1] = decode_lines(2, "pc + 1") end

    if rk == "move_move_empty" then
        parts[#parts + 1] = "    -- redundant MOVE;MOVE pair eliminated under src==dst facts\n"
        parts[#parts + 1] = "    return pc + 2\n"
    elseif rk == "move_move_forward" then
        parts[#parts + 1] = "    -- MOVE;MOVE collapsed to one direct move\n"
        parts[#parts + 1] = "    L.stack[base + a_2] = L.stack[base + b_1]\n"
        parts[#parts + 1] = "    return pc + 2\n"
    elseif rk == "load_move_final_dst" then
        parts[#parts + 1] = "    -- LOAD*;MOVE collapsed to load final destination\n"
        if ops[1] == "LOADK" then
            parts[#parts + 1] = "    L.stack[base + a_2] = constants[bx_1]\n"
        elseif ops[1] == "LOADF" then
            parts[#parts + 1] = string.format("    L.stack[base + a_2].tag = %d\n    L.stack[base + a_2].aux = 0\n    L.stack[base + a_2].bits = as(u64, as(f64, sbx_1))\n", TAG_NUM)
        else
            parts[#parts + 1] = string.format("    L.stack[base + a_2].tag = %d\n    L.stack[base + a_2].aux = 0\n    L.stack[base + a_2].bits = as(u64, as(i64, sbx_1))\n", TAG_INTEGER)
        end
        parts[#parts + 1] = "    return pc + 2\n"
    elseif rk == "op_move_final_dst" or rk == "op_return1" then
        local dst = rk == "op_return1" and "a_2" or "a_2"
        parts[#parts + 1] = "    -- arithmetic producer fused with consumer under def-use/liveness facts\n"
        parts[#parts + 1] = "    let lhs_r: ptr(Value) = L.stack + (base + b_1)\n"
        if ops[1] == "ADDI" then
            parts[#parts + 1] = string.format("    if lhs_r.tag ~= %d then return pc end\n", TAG_INTEGER)
            parts[#parts + 1] = string.format("    L.stack[base + %s].tag = %d\n    L.stack[base + %s].aux = 0\n    L.stack[base + %s].bits = lhs_r.bits + as(u64, as(i32, c_1))\n", dst, TAG_INTEGER, dst, dst)
        else
            parts[#parts + 1] = "    let rhs_r: ptr(Value) = L.stack + (base + c_1)\n"
            parts[#parts + 1] = string.format("    if lhs_r.tag ~= %d then return pc end\n    if rhs_r.tag ~= %d then return pc end\n", TAG_INTEGER, TAG_INTEGER)
            parts[#parts + 1] = "    let lx_r: i64 = as(i64, lhs_r.bits)\n    let ry_r: i64 = as(i64, rhs_r.bits)\n"
            local expr = ops[1] == "SUB" and "lx_r - ry_r" or ops[1] == "MUL" and "lx_r * ry_r" or "lx_r + ry_r"
            parts[#parts + 1] = string.format("    L.stack[base + %s].tag = %d\n    L.stack[base + %s].aux = 0\n    L.stack[base + %s].bits = as(u64, %s)\n", dst, TAG_INTEGER, dst, dst, expr)
        end
        if rk == "op_return1" then
            parts[#parts + 1] = "    frame.pc = pc + 2\n    L.top = base + a_2 + 1\n"
        end
        parts[#parts + 1] = "    return pc + 2\n"
    else
        return nil
    end
    parts[#parts + 1] = "end\n"
    return table.concat(parts)
end

local function c_decode_lines(i, pc_expr)
    return string.format([[    uint32_t word_%d = code[(size_t)(%s)].word;
    size_t a_%d = (size_t)((word_%d >> 7) & 255u);
    size_t b_%d = (size_t)((word_%d >> 16) & 255u);
    size_t c_%d = (size_t)((word_%d >> 24) & 255u);
    uint8_t k_%d = (uint8_t)((word_%d >> 15) & 1u);
    size_t bx_%d = (size_t)((word_%d >> 15) & 131071u);
    int32_t sbx_%d = (int32_t)((word_%d >> 15) & 131071u) - 65535;
    int32_t sj_%d = (int32_t)((word_%d >> 7) & 33554431u) - 16777215;
]], i, pc_expr, i, i, i, i, i, i, i, i, i, i, i, i, i, i)
end

local function emit_c_header(candidate, kernel_name)
    local s = {}
    s[#s + 1] = "/* Auto-generated Lua VM JIT stencil kernel (GCC backend) */"
    s[#s + 1] = "/* Candidate: " .. tostring(candidate.id or "unknown") .. " */"
    s[#s + 1] = "/* Ops: " .. table.concat(op_list(candidate), ",") .. " */"
    s[#s + 1] = "/* Shape: " .. tostring(candidate.shape_kind or "unspecified") .. " */"
    s[#s + 1] = "/* Lowering: " .. tostring(candidate.lowering or candidate.rewrite_kind or "generic_opcode_sequence") .. " */"
    s[#s + 1] = "#include <stdint.h>"
    s[#s + 1] = "#include <stddef.h>"
    s[#s + 1] = "typedef struct Value { uint32_t tag; uint32_t aux; uint64_t bits; } Value;"
    s[#s + 1] = "typedef struct GCHeader { struct GCHeader* next; uint8_t tt; uint8_t marked; } GCHeader;"
    s[#s + 1] = "typedef struct String { GCHeader gc; uint8_t reserved; uint32_t hash; size_t len; uint8_t* bytes; } String;"
    s[#s + 1] = "typedef struct Node { Value key; Value value; struct Node* next; } Node;"
    s[#s + 1] = "typedef struct Table { GCHeader gc; uint32_t flags; size_t array_len; Value* array; uint32_t node_mask; Node* nodes; Node* lastfree; struct Table* metatable; uint32_t shape_epoch; } Table;"
    s[#s + 1] = "typedef struct Instr { uint32_t word; } Instr;"
    s[#s + 1] = "typedef struct Proto { GCHeader gc; Instr* code; size_t code_len; Value* constants; size_t constants_len; void* children; size_t children_len; int32_t* lineinfo; size_t lineinfo_len; void* locvars; size_t locvars_len; void* upvals; size_t upvals_len; String* source; int32_t linedefined; int32_t lastlinedefined; uint8_t numparams; uint8_t flag; uint16_t maxstack; } Proto;"
    s[#s + 1] = "typedef struct UpVal { GCHeader gc; Value* v; Value closed; size_t stack_index; struct UpVal* next_open; } UpVal;"
    s[#s + 1] = "typedef struct LClosure { GCHeader gc; Table* env; Proto* proto; UpVal** upvals; uint8_t nupvals; } LClosure;"
    s[#s + 1] = "typedef struct Frame { Value closure; size_t base; size_t top; size_t pc; int32_t wanted; int32_t tailcalls; uint16_t resume_mode; uint16_t resume_a; uint16_t resume_b; uint16_t resume_c; size_t resume_pc; size_t resume_base; Value resume_value; } Frame;"
    s[#s + 1] = "typedef struct LuaThread { uint8_t* gc_next; uint8_t gc_tt; uint8_t gc_marked; uint8_t status; Value* stack; size_t stack_size; size_t top; Frame* frames; size_t frame_count; size_t frame_cap; } LuaThread;"
    s[#s + 1] = string.format("size_t stencil_%s(LuaThread* L, Frame* frame, Instr* code, Value* constants, size_t pc, size_t base, size_t top) {", kernel_name)
    return table.concat(s, "\n") .. "\n"
end

local function c_raw_getfield(i, obj_expr, key_expr, dst_expr, exit_pc)
    local s = {}
    s[#s+1] = string.format("    Value* obj_%d = %s;\n", i, obj_expr)
    s[#s+1] = string.format("    Value* key_%d = %s;\n", i, key_expr)
    s[#s+1] = string.format("    if (obj_%d->tag != %du) return %s;\n", i, TAG_TABLE, exit_pc)
    s[#s+1] = string.format("    if (key_%d->tag != %du) return %s;\n", i, TAG_STR, exit_pc)
    s[#s+1] = string.format("    Table* table_%d = (Table*)(uintptr_t)obj_%d->bits;\n", i, i)
    s[#s+1] = string.format("    if (table_%d->metatable != 0) return %s;\n", i, exit_pc)
    s[#s+1] = string.format("    if (table_%d->nodes == 0) return %s;\n", i, exit_pc)
    s[#s+1] = string.format("    String* keystr_%d = (String*)(uintptr_t)key_%d->bits;\n", i, i)
    s[#s+1] = string.format("    size_t bucket_%d = (size_t)(keystr_%d->hash & table_%d->node_mask);\n", i, i, i)
    s[#s+1] = string.format("    Node* node_%d = table_%d->nodes + bucket_%d;\n", i, i, i)
    s[#s+1] = string.format("    if (node_%d->key.tag != %du) return %s;\n", i, TAG_STR, exit_pc)
    s[#s+1] = string.format("    if (node_%d->key.bits != key_%d->bits) return %s;\n", i, i, exit_pc)
    s[#s+1] = string.format("    if (node_%d->value.tag == %du) return %s;\n", i, TAG_NIL, exit_pc)
    s[#s+1] = string.format("    %s = node_%d->value;\n", dst_expr, i)
    return table.concat(s)
end

local function c_table_get(i, obj_expr, key_expr, dst_expr, exit_pc)
    local s = {}
    s[#s+1] = string.format("    Value* obj_%d = %s;\n", i, obj_expr)
    s[#s+1] = string.format("    Value* key_%d = %s;\n", i, key_expr)
    s[#s+1] = string.format("    if (obj_%d->tag != %du) return %s;\n", i, TAG_TABLE, exit_pc)
    s[#s+1] = string.format("    Table* table_%d = (Table*)(uintptr_t)obj_%d->bits;\n", i, i)
    s[#s+1] = string.format("    if (table_%d->metatable != 0) return %s;\n", i, exit_pc)
    s[#s+1] = string.format("    if (key_%d->tag == %du) {\n", i, TAG_INTEGER)
    s[#s+1] = string.format("        int64_t idx_%d = (int64_t)key_%d->bits;\n", i, i)
    s[#s+1] = string.format("        if (idx_%d <= 0) return %s;\n", i, exit_pc)
    s[#s+1] = string.format("        if ((size_t)idx_%d > table_%d->array_len) return %s;\n", i, i, exit_pc)
    s[#s+1] = string.format("        Value arrv_%d = table_%d->array[(size_t)(idx_%d - 1)];\n", i, i, i)
    s[#s+1] = string.format("        if (arrv_%d.tag == %du) return %s;\n", i, TAG_NIL, exit_pc)
    s[#s+1] = string.format("        %s = arrv_%d;\n", dst_expr, i)
    s[#s+1] = "    } else {\n"
    s[#s+1] = string.format("        if (key_%d->tag != %du) return %s;\n", i, TAG_STR, exit_pc)
    s[#s+1] = string.format("        if (table_%d->nodes == 0) return %s;\n", i, exit_pc)
    s[#s+1] = string.format("        String* keystr_%d = (String*)(uintptr_t)key_%d->bits;\n", i, i)
    s[#s+1] = string.format("        size_t bucket_%d = (size_t)(keystr_%d->hash & table_%d->node_mask);\n", i, i, i)
    s[#s+1] = string.format("        Node* node_%d = table_%d->nodes + bucket_%d;\n", i, i, i)
    s[#s+1] = string.format("        if (node_%d->key.tag != %du) return %s;\n", i, TAG_STR, exit_pc)
    s[#s+1] = string.format("        if (node_%d->key.bits != key_%d->bits) return %s;\n", i, i, exit_pc)
    s[#s+1] = string.format("        if (node_%d->value.tag == %du) return %s;\n", i, TAG_NIL, exit_pc)
    s[#s+1] = string.format("        %s = node_%d->value;\n", dst_expr, i)
    s[#s+1] = "    }\n"
    return table.concat(s)
end

local function c_eq_branch(i, lhs_expr, rhs_expr, sense_expr, exit_pc, mode)
    local s = {}
    s[#s+1] = string.format("    Value* eqlhs_%d = %s;\n", i, lhs_expr)
    s[#s+1] = string.format("    Value* eqrhs_%d = %s;\n", i, rhs_expr)
    if mode == "i64" then
        s[#s+1] = string.format("    if (eqlhs_%d->tag != %du || eqrhs_%d->tag != %du) return %s;\n", i, TAG_INTEGER, i, TAG_INTEGER, exit_pc)
        s[#s+1] = string.format("    int is_eq_%d = eqlhs_%d->bits == eqrhs_%d->bits;\n", i, i, i)
    else
        s[#s+1] = string.format("    if (eqlhs_%d->tag != eqrhs_%d->tag) return %s;\n", i, i, exit_pc)
        s[#s+1] = string.format("    if (eqlhs_%d->tag == %du || eqlhs_%d->tag == %du || eqlhs_%d->tag == %du) return %s;\n", i, TAG_TABLE, i, TAG_NUM, i, TAG_STR, exit_pc)
        s[#s+1] = string.format("    int is_eq_%d = 0;\n", i)
        s[#s+1] = string.format("    if (eqlhs_%d->tag == %du || eqlhs_%d->tag == %du || eqlhs_%d->tag == %du) is_eq_%d = 1;\n", i, TAG_NIL, i, TAG_FALSE, i, TAG_TRUE, i)
        s[#s+1] = string.format("    if (eqlhs_%d->tag == %du) is_eq_%d = eqlhs_%d->bits == eqrhs_%d->bits;\n", i, TAG_INTEGER, i, i, i)
    end
    s[#s+1] = string.format("    if (is_eq_%d == (%s)) return %s + 2;\n", i, sense_expr, exit_pc)
    s[#s+1] = "    return " .. exit_pc .. " + 1;\n"
    return table.concat(s)
end

local function c_rel_branch(i, lhs_expr, rhs_expr, sense_expr, exit_pc, op)
    local s = {}
    s[#s+1] = string.format("    Value* rellhs_%d = %s;\n", i, lhs_expr)
    s[#s+1] = string.format("    Value* relrhs_%d = %s;\n", i, rhs_expr)
    s[#s+1] = string.format("    if (rellhs_%d->tag != %du || relrhs_%d->tag != %du) return %s;\n", i, TAG_INTEGER, i, TAG_INTEGER, exit_pc)
    local cmp = op == "le" and "<=" or "<"
    s[#s+1] = string.format("    int is_rel_%d = (int64_t)rellhs_%d->bits %s (int64_t)relrhs_%d->bits;\n", i, i, cmp, i)
    s[#s+1] = string.format("    if (is_rel_%d == (%s)) return %s + 2;\n", i, sense_expr, exit_pc)
    s[#s+1] = "    return " .. exit_pc .. " + 1;\n"
    return table.concat(s)
end

local function c_lt_branch(i, lhs_expr, rhs_expr, sense_expr, exit_pc)
    local s = {}
    s[#s+1] = string.format("    Value* ltlhs_%d = %s;\n", i, lhs_expr)
    s[#s+1] = string.format("    Value* ltrhs_%d = %s;\n", i, rhs_expr)
    s[#s+1] = string.format("    if (ltlhs_%d->tag != %du || ltrhs_%d->tag != %du) return %s;\n", i, TAG_INTEGER, i, TAG_INTEGER, exit_pc)
    s[#s+1] = string.format("    int is_lt_%d = (int64_t)ltlhs_%d->bits < (int64_t)ltrhs_%d->bits;\n", i, i, i)
    s[#s+1] = string.format("    if (is_lt_%d == (%s)) return %s + 2;\n", i, sense_expr, exit_pc)
    s[#s+1] = "    return " .. exit_pc .. " + 1;\n"
    return table.concat(s)
end

local function c_getupval(i, dst_expr, upidx_expr, exit_pc)
    local s = {}
    s[#s+1] = string.format("    if (frame->closure.tag != %du) return %s;\n", TAG_LCLOSURE, exit_pc)
    s[#s+1] = "    LClosure* cl = (LClosure*)(uintptr_t)frame->closure.bits;\n"
    s[#s+1] = string.format("    if ((size_t)%s >= (size_t)cl->nupvals) return %s;\n", upidx_expr, exit_pc)
    s[#s+1] = string.format("    UpVal* uv_%d = cl->upvals[%s];\n", i, upidx_expr)
    s[#s+1] = string.format("    if (uv_%d == 0 || uv_%d->v == 0) return %s;\n", i, i, exit_pc)
    s[#s+1] = string.format("    %s = *uv_%d->v;\n", dst_expr, i)
    return table.concat(s)
end

local function c_value_is_barrier_clean_expr(var)
    return string.format("(%s.tag <= %du)", var, TAG_NUM)
end

local function c_set_raw_slot(i, table_expr, key_expr, val_expr, exit_pc, require_barrier_clean)
    local s = {}
    s[#s+1] = string.format("    Value* setobj_%d = %s;\n", i, table_expr)
    s[#s+1] = string.format("    Value* setkey_%d = %s;\n", i, key_expr)
    s[#s+1] = string.format("    Value setval_%d = %s;\n", i, val_expr)
    if require_barrier_clean then
        s[#s+1] = string.format("    if (!%s) return %s;\n", c_value_is_barrier_clean_expr(string.format("setval_%d", i)), exit_pc)
    end
    s[#s+1] = string.format("    if (setobj_%d->tag != %du) return %s;\n", i, TAG_TABLE, exit_pc)
    s[#s+1] = string.format("    Table* settab_%d = (Table*)(uintptr_t)setobj_%d->bits;\n", i, i)
    s[#s+1] = string.format("    if (settab_%d->metatable != 0) return %s;\n", i, exit_pc)
    s[#s+1] = string.format("    if (setkey_%d->tag == %du) {\n", i, TAG_INTEGER)
    s[#s+1] = string.format("        int64_t setidx_%d = (int64_t)setkey_%d->bits;\n", i, i)
    s[#s+1] = string.format("        if (setidx_%d <= 0 || (size_t)setidx_%d > settab_%d->array_len) return %s;\n", i, i, i, exit_pc)
    s[#s+1] = string.format("        settab_%d->array[(size_t)(setidx_%d - 1)] = setval_%d;\n", i, i, i)
    s[#s+1] = "    } else {\n"
    s[#s+1] = string.format("        if (settab_%d->nodes == 0) return %s;\n", i, exit_pc)
    s[#s+1] = string.format("        if (setkey_%d->tag != %du) return %s;\n", i, TAG_STR, exit_pc)
    s[#s+1] = string.format("        String* setstr_%d = (String*)(uintptr_t)setkey_%d->bits;\n", i, i)
    s[#s+1] = string.format("        size_t setbucket_%d = (size_t)(setstr_%d->hash & settab_%d->node_mask);\n", i, i, i)
    s[#s+1] = string.format("        Node* setnode_%d = settab_%d->nodes + setbucket_%d;\n", i, i, i)
    s[#s+1] = string.format("        if (setnode_%d->key.tag != %du || setnode_%d->key.bits != setkey_%d->bits) return %s;\n", i, TAG_STR, i, i, exit_pc)
    s[#s+1] = string.format("        setnode_%d->value = setval_%d;\n", i, i)
    s[#s+1] = "    }\n"
    return table.concat(s)
end

local function c_gettabup(i, dst_expr, upidx_expr, key_expr, exit_pc)
    local s = {}
    s[#s+1] = string.format("    if (frame->closure.tag != %du) return %s;\n", TAG_LCLOSURE, exit_pc)
    s[#s+1] = "    LClosure* gtcl = (LClosure*)(uintptr_t)frame->closure.bits;\n"
    s[#s+1] = string.format("    if ((size_t)%s >= (size_t)gtcl->nupvals) return %s;\n", upidx_expr, exit_pc)
    s[#s+1] = string.format("    UpVal* gtuv_%d = gtcl->upvals[%s];\n", i, upidx_expr)
    s[#s+1] = string.format("    if (gtuv_%d == 0 || gtuv_%d->v == 0) return %s;\n", i, i, exit_pc)
    s[#s+1] = c_raw_getfield(i, string.format("gtuv_%d->v", i), key_expr, dst_expr, exit_pc)
    return table.concat(s)
end

local function c_call_known_boundary(i, a_expr, exit_pc, tag)
    local s = {}
    s[#s+1] = string.format("    Value* callee_%d = &L->stack[base + %s];\n", i, a_expr)
    if tag then
        s[#s+1] = string.format("    if (callee_%d->tag != %du) return %s;\n", i, tag, exit_pc)
    else
        s[#s+1] = string.format("    if (callee_%d->tag != %du && callee_%d->tag != %du) return %s;\n", i, TAG_LCLOSURE, i, TAG_CCLOSURE, exit_pc)
    end
    s[#s+1] = string.format("    frame->pc = %s; L->top = top; return %s;\n", exit_pc, exit_pc)
    return table.concat(s)
end

local function c_test_branch(i, exit_pc)
    local s = {}
    s[#s+1] = string.format("    Value* testv_%d = &L->stack[base + a_%d];\n", i, i)
    s[#s+1] = string.format("    int truth_%d = !(testv_%d->tag == %du || testv_%d->tag == %du);\n", i, i, TAG_NIL, i, TAG_FALSE)
    s[#s+1] = string.format("    if (truth_%d == (k_%d != 0)) return %s + 1;\n", i, i, exit_pc)
    s[#s+1] = string.format("    return %s + 2;\n", exit_pc)
    return table.concat(s)
end

local function c_number_expr(i, name, expr, exit_pc)
    local s = {}
    s[#s+1] = string.format("    double %s_%d;\n", name, i)
    s[#s+1] = string.format("    if ((%s)->tag == %du) %s_%d = (double)(int64_t)(%s)->bits;\n", expr, TAG_INTEGER, name, i, expr)
    s[#s+1] = string.format("    else if ((%s)->tag == %du) { union { double d; uint64_t u; } cvt_%s_%d; cvt_%s_%d.u = (%s)->bits; %s_%d = cvt_%s_%d.d; }\n", expr, TAG_NUM, name, i, name, i, expr, name, i, name, i)
    s[#s+1] = string.format("    else return %s;\n", exit_pc)
    return table.concat(s)
end

local function c_div_number(i, exit_pc)
    local s = {}
    s[#s+1] = string.format("    Value* divlhs_%d = &L->stack[base + b_%d]; Value* divrhs_%d = &L->stack[base + c_%d];\n", i, i, i, i)
    s[#s+1] = c_number_expr(i, "divx", string.format("divlhs_%d", i), exit_pc)
    s[#s+1] = c_number_expr(i, "divy", string.format("divrhs_%d", i), exit_pc)
    s[#s+1] = string.format("    union { double d; uint64_t u; } divout_%d; divout_%d.d = divx_%d / divy_%d;\n", i, i, i, i)
    s[#s+1] = string.format("    L->stack[base + a_%d].tag = %du; L->stack[base + a_%d].aux = 0; L->stack[base + a_%d].bits = divout_%d.u;\n", i, TAG_NUM, i, i, i)
    return table.concat(s)
end

local function c_return_variable(i, exit_pc)
    local s = {}
    s[#s+1] = string.format("    frame->pc = %s + 1;\n", exit_pc)
    s[#s+1] = string.format("    if (b_%d == 0) L->top = top; else L->top = base + a_%d + b_%d - 1;\n", i, i, i)
    s[#s+1] = string.format("    return %s + 1;\n", exit_pc)
    return table.concat(s)
end

local function c_forprep_i64(i, exit_pc)
    local s = {}
    s[#s+1] = string.format("    Value* init_%d = &L->stack[base + a_%d]; Value* step_%d = &L->stack[base + a_%d + 2];\n", i, i, i, i)
    s[#s+1] = string.format("    if (init_%d->tag != %du || step_%d->tag != %du) return %s;\n", i, TAG_INTEGER, i, TAG_INTEGER, exit_pc)
    s[#s+1] = string.format("    init_%d->bits = (uint64_t)((int64_t)init_%d->bits - (int64_t)step_%d->bits);\n", i, i, i)
    s[#s+1] = string.format("    return (size_t)((int64_t)%s + (int64_t)sbx_%d);\n", exit_pc, i)
    return table.concat(s)
end

local function c_forloop_i64(i, exit_pc)
    local s = {}
    s[#s+1] = string.format("    Value* idxv_%d = &L->stack[base + a_%d]; Value* limv_%d = &L->stack[base + a_%d + 1]; Value* stepv_%d = &L->stack[base + a_%d + 2];\n", i, i, i, i, i, i)
    s[#s+1] = string.format("    if (idxv_%d->tag != %du || limv_%d->tag != %du || stepv_%d->tag != %du) return %s;\n", i, TAG_INTEGER, i, TAG_INTEGER, i, TAG_INTEGER, exit_pc)
    s[#s+1] = string.format("    int64_t nidx_%d = (int64_t)idxv_%d->bits + (int64_t)stepv_%d->bits;\n", i, i, i)
    s[#s+1] = string.format("    idxv_%d->bits = (uint64_t)nidx_%d;\n", i, i)
    s[#s+1] = string.format("    int64_t lim_%d = (int64_t)limv_%d->bits; int64_t step_%d = (int64_t)stepv_%d->bits;\n", i, i, i, i)
    s[#s+1] = string.format("    if ((step_%d >= 0 && nidx_%d <= lim_%d) || (step_%d < 0 && nidx_%d >= lim_%d)) { L->stack[base + a_%d + 3] = *idxv_%d; return (size_t)((int64_t)%s + (int64_t)sbx_%d); }\n", i, i, i, i, i, i, i, i, exit_pc, i)
    s[#s+1] = string.format("    return %s + 1;\n", exit_pc)
    return table.concat(s)
end

local function c_emit_op(candidate, op, i, pc_expr)
    local s = { c_decode_lines(i, pc_expr) }
    local kind = fact_kind_for(candidate, op, op_ordinal(candidate.ops or {}, i)) or "generic"
    local function add(x) s[#s + 1] = x end
    if op == "MOVE" then
        add(string.format("    L->stack[base + a_%d] = L->stack[base + b_%d];\n", i, i))
    elseif op == "LOADI" then
        add(string.format("    L->stack[base + a_%d].tag = %du; L->stack[base + a_%d].aux = 0; L->stack[base + a_%d].bits = (uint64_t)(int64_t)sbx_%d;\n", i, TAG_INTEGER, i, i, i))
    elseif op == "LOADF" then
        add(string.format("    { union { double d; uint64_t u; } cvt; cvt.d = (double)sbx_%d; L->stack[base + a_%d].tag = %du; L->stack[base + a_%d].aux = 0; L->stack[base + a_%d].bits = cvt.u; }\n", i, i, TAG_NUM, i, i))
    elseif op == "LOADK" then
        add(string.format("    L->stack[base + a_%d] = constants[bx_%d];\n", i, i))
    elseif op == "LOADFALSE" or op == "LOADTRUE" or op == "LOADNIL" then
        local tag = op == "LOADFALSE" and TAG_FALSE or op == "LOADTRUE" and TAG_TRUE or TAG_NIL
        local bits = op == "LOADTRUE" and 1 or 0
        add(string.format("    L->stack[base + a_%d].tag = %du; L->stack[base + a_%d].aux = 0; L->stack[base + a_%d].bits = %du;\n", i, tag, i, i, bits))
    elseif op == "GETFIELD" then
        if kind ~= "raw_string_slot" and kind ~= "generic_boundary" then add("    return " .. pc_expr .. ";\n") else add(c_raw_getfield(i, string.format("&L->stack[base + b_%d]", i), string.format("&constants[c_%d]", i), string.format("L->stack[base + a_%d]", i), pc_expr)) end
    elseif op == "GETTABLE" then
        if kind ~= "raw_array_i64" and kind ~= "raw_string_slot" and kind ~= "generic_boundary" then add("    return " .. pc_expr .. ";\n") else add(c_table_get(i, string.format("&L->stack[base + b_%d]", i), string.format("&L->stack[base + c_%d]", i), string.format("L->stack[base + a_%d]", i), pc_expr)) end
    elseif op == "GETTABUP" then
        add(c_gettabup(i, string.format("L->stack[base + a_%d]", i), string.format("b_%d", i), string.format("&constants[c_%d]", i), pc_expr))
    elseif op == "SELF" then
        if kind ~= "raw_string_slot" and kind ~= "generic_boundary" then add("    return " .. pc_expr .. ";\n") else add(string.format("    L->stack[base + a_%d + 1] = L->stack[base + b_%d];\n", i, i)); add(c_raw_getfield(i, string.format("&L->stack[base + b_%d]", i), string.format("&constants[c_%d]", i), string.format("L->stack[base + a_%d]", i), pc_expr)) end
    elseif op == "GETUPVAL" then
        add(c_getupval(i, string.format("L->stack[base + a_%d]", i), string.format("b_%d", i), pc_expr))
    elseif op == "SETFIELD" then
        if kind ~= "raw_write_barrier_clean" and kind ~= "generic_write_boundary" then add("    return " .. pc_expr .. ";\n") else add(c_set_raw_slot(i, string.format("&L->stack[base + a_%d]", i), string.format("&constants[b_%d]", i), string.format("k_%d ? constants[c_%d] : L->stack[base + c_%d]", i, i, i), pc_expr, kind == "generic_write_boundary")) end
    elseif op == "SETTABLE" then
        if kind ~= "raw_write_barrier_clean" and kind ~= "generic_write_boundary" then add("    return " .. pc_expr .. ";\n") else add(c_set_raw_slot(i, string.format("&L->stack[base + a_%d]", i), string.format("&L->stack[base + b_%d]", i), string.format("k_%d ? constants[c_%d] : L->stack[base + c_%d]", i, i, i), pc_expr, kind == "generic_write_boundary")) end
    elseif op == "ADDI" then
        if kind ~= "i64" and kind ~= "i64_result_dead" and kind ~= "generic_boundary" then add("    return " .. pc_expr .. ";\n") elseif kind ~= "i64_result_dead" then add(string.format("    Value* lhs_%d = &L->stack[base + b_%d]; if (lhs_%d->tag != %du) return %s; L->stack[base + a_%d].tag = %du; L->stack[base + a_%d].aux = 0; L->stack[base + a_%d].bits = lhs_%d->bits + (uint64_t)(int32_t)c_%d;\n", i, i, i, TAG_INTEGER, pc_expr, i, TAG_INTEGER, i, i, i, i)) end
    elseif op == "ADD" or op == "SUB" or op == "MUL" then
        if kind ~= "i64" and kind ~= "i64_result_dead" and kind ~= "generic_boundary" then add("    return " .. pc_expr .. ";\n") elseif kind ~= "i64_result_dead" then local expr = op == "ADD" and string.format("lx_%d + ry_%d", i, i) or op == "SUB" and string.format("lx_%d - ry_%d", i, i) or string.format("lx_%d * ry_%d", i, i); add(string.format("    Value* lhs_%d = &L->stack[base + b_%d]; Value* rhs_%d = &L->stack[base + c_%d]; if (lhs_%d->tag != %du || rhs_%d->tag != %du) return %s; int64_t lx_%d = (int64_t)lhs_%d->bits; int64_t ry_%d = (int64_t)rhs_%d->bits; L->stack[base + a_%d].tag = %du; L->stack[base + a_%d].aux = 0; L->stack[base + a_%d].bits = (uint64_t)(%s);\n", i, i, i, i, i, TAG_INTEGER, i, TAG_INTEGER, pc_expr, i, i, i, i, i, TAG_INTEGER, i, i, expr)) end
    elseif op == "EQ" then
        if kind ~= "primitive_eq" and kind ~= "i64_eq" and kind ~= "generic_boundary" then add("    return " .. pc_expr .. ";\n") else add(c_eq_branch(i, string.format("&L->stack[base + b_%d]", i), string.format("&L->stack[base + c_%d]", i), string.format("a_%d != 0", i), pc_expr, kind == "i64_eq" and "i64" or "primitive")) end
    elseif op == "EQK" then
        if kind ~= "primitive_eq" and kind ~= "i64_eq" and kind ~= "generic_boundary" then add("    return " .. pc_expr .. ";\n") else add(c_eq_branch(i, string.format("&L->stack[base + a_%d]", i), string.format("&constants[bx_%d]", i), string.format("k_%d == 0", i), pc_expr, kind == "i64_eq" and "i64" or "primitive")) end
    elseif op == "LT" then
        if kind ~= "i64_compare" and kind ~= "generic_boundary" then add("    return " .. pc_expr .. ";\n") else add(c_lt_branch(i, string.format("&L->stack[base + b_%d]", i), string.format("&L->stack[base + c_%d]", i), string.format("a_%d != 0", i), pc_expr)) end
    elseif op == "LE" then
        if kind ~= "i64_compare" and kind ~= "generic_boundary" then add("    return " .. pc_expr .. ";\n") else add(c_rel_branch(i, string.format("&L->stack[base + b_%d]", i), string.format("&L->stack[base + c_%d]", i), string.format("a_%d != 0", i), pc_expr, "le")) end
    elseif op == "CALL" then
        if kind == "known_lua_target" then add(c_call_known_boundary(i, string.format("a_%d", i), pc_expr, TAG_LCLOSURE)) elseif kind == "known_c_target" then add(c_call_known_boundary(i, string.format("a_%d", i), pc_expr, TAG_CCLOSURE)) elseif kind == "generic_call_boundary" then add(c_call_known_boundary(i, string.format("a_%d", i), pc_expr, nil)) else add("    return " .. pc_expr .. ";\n") end
    elseif op == "TAILCALL" then
        if kind == "known_lua_target" then add(c_call_known_boundary(i, string.format("a_%d", i), pc_expr, TAG_LCLOSURE)) elseif kind == "known_c_target" then add(c_call_known_boundary(i, string.format("a_%d", i), pc_expr, TAG_CCLOSURE)) elseif kind == "generic_call_boundary" then add(c_call_known_boundary(i, string.format("a_%d", i), pc_expr, nil)) else add("    return " .. pc_expr .. ";\n") end
    elseif op == "TEST" then
        add(c_test_branch(i, pc_expr))
    elseif op == "JMP" then
        add(string.format("    return (size_t)((int64_t)%s + (int64_t)sj_%d);\n", pc_expr, i))
    elseif op == "FORPREP" then
        add(c_forprep_i64(i, pc_expr))
    elseif op == "FORLOOP" then
        add(c_forloop_i64(i, pc_expr))
    elseif op == "DIV" then
        add(c_div_number(i, pc_expr))
    elseif op == "RETURN" then
        add(c_return_variable(i, pc_expr))
    elseif op == "NEWTABLE" then
        add("    return " .. pc_expr .. ";\n")
    elseif op == "RETURN0" then
        add("    frame->pc = " .. pc_expr .. " + 1; L->top = base; return " .. pc_expr .. " + 1;\n")
    elseif op == "RETURN1" then
        add(string.format("    frame->pc = %s + 1; L->top = base + a_%d + 1; return %s + 1;\n", pc_expr, i, pc_expr))
    else
        add("    return " .. pc_expr .. ";\n")
    end
    return table.concat(s)
end

local function emit_c_rewrite_body(candidate, ops)
    local rk = candidate.rewrite_kind
    local parts = { emit_c_header(candidate, sanitize(candidate.id or candidate.name or "kernel")), c_decode_lines(1, "pc") }
    if #ops >= 2 then parts[#parts + 1] = c_decode_lines(2, "pc + 1") end
    if rk == "move_move_empty" then
        parts[#parts + 1] = "    return pc + 2;\n"
    elseif rk == "move_move_forward" then
        parts[#parts + 1] = "    L->stack[base + a_2] = L->stack[base + b_1]; return pc + 2;\n"
    elseif rk == "load_move_final_dst" then
        if ops[1] == "LOADK" then parts[#parts + 1] = "    L->stack[base + a_2] = constants[bx_1];\n"
        elseif ops[1] == "LOADF" then parts[#parts + 1] = string.format("    { union { double d; uint64_t u; } cvt; cvt.d = (double)sbx_1; L->stack[base + a_2].tag = %du; L->stack[base + a_2].aux = 0; L->stack[base + a_2].bits = cvt.u; }\n", TAG_NUM)
        else parts[#parts + 1] = string.format("    L->stack[base + a_2].tag = %du; L->stack[base + a_2].aux = 0; L->stack[base + a_2].bits = (uint64_t)(int64_t)sbx_1;\n", TAG_INTEGER) end
        parts[#parts + 1] = "    return pc + 2;\n"
    elseif rk == "op_move_final_dst" or rk == "op_return1" then
        parts[#parts + 1] = "    Value* lhs_r = &L->stack[base + b_1];\n"
        if ops[1] == "ADDI" then
            parts[#parts + 1] = string.format("    if (lhs_r->tag != %du) return pc;\n", TAG_INTEGER)
            parts[#parts + 1] = string.format("    L->stack[base + a_2].tag = %du; L->stack[base + a_2].aux = 0; L->stack[base + a_2].bits = lhs_r->bits + (uint64_t)(int32_t)c_1;\n", TAG_INTEGER)
        else
            parts[#parts + 1] = "    Value* rhs_r = &L->stack[base + c_1];\n"
            parts[#parts + 1] = string.format("    if (lhs_r->tag != %du || rhs_r->tag != %du) return pc;\n", TAG_INTEGER, TAG_INTEGER)
            parts[#parts + 1] = "    int64_t lx_r = (int64_t)lhs_r->bits; int64_t ry_r = (int64_t)rhs_r->bits;\n"
            local expr = ops[1] == "SUB" and "lx_r - ry_r" or ops[1] == "MUL" and "lx_r * ry_r" or "lx_r + ry_r"
            parts[#parts + 1] = string.format("    L->stack[base + a_2].tag = %du; L->stack[base + a_2].aux = 0; L->stack[base + a_2].bits = (uint64_t)(%s);\n", TAG_INTEGER, expr)
        end
        if rk == "op_return1" then parts[#parts + 1] = "    frame->pc = pc + 2; L->top = base + a_2 + 1;\n" end
        parts[#parts + 1] = "    return pc + 2;\n"
    else
        error("unsupported GCC rewrite lowering " .. tostring(rk))
    end
    parts[#parts + 1] = "}\n"
    return table.concat(parts)
end

local function emit_c_candidate_kernel(candidate, config)
    local plan = lowering_plan.build(candidate, { backend = "gcc" })
    if not plan.valid then error("unsupported GCC lowering for " .. tostring(candidate.id) .. ": " .. table.concat(plan.errors, "; ")) end
    local kernel_name = sanitize(candidate.id or candidate.name or "kernel")
    local ops = op_list(candidate)
    local source
    if candidate.rewrite_kind then
        source = emit_c_rewrite_body(candidate, ops)
    else
        local parts = { emit_c_header(candidate, kernel_name) }
        for i, op in ipairs(ops) do
            parts[#parts + 1] = c_emit_op(candidate, op, i, i == 1 and "pc" or ("pc + " .. tostring(i - 1)))
        end
        parts[#parts + 1] = "    frame->pc = pc + " .. tostring(#ops) .. ";\n"
        parts[#parts + 1] = "    L->top = top;\n"
        parts[#parts + 1] = "    return pc + " .. tostring(#ops) .. ";\n"
        parts[#parts + 1] = "}\n"
        source = table.concat(parts)
    end
    return { id = kernel_name, name = kernel_name, source = source, path = config.output_dir and (config.output_dir .. "/" .. kernel_name .. ".c") or nil, candidate_id = candidate.id, arity = candidate.arity or #ops, ops = ops, abi = "jit_stencil_v0", language = "c", backend = "gcc" }
end

-- Emit a candidate kernel in Moonlift or C source format.
function M.emit_candidate_kernel(candidate, config)
    config = config or {}
    if config.backend == "gcc" or config.backend == "c" then
        return emit_c_candidate_kernel(candidate, config)
    end

    local kernel_name = sanitize(candidate.id or candidate.name or "kernel")
    local ops = op_list(candidate)
    local source

    if config.trivial then
        source = "func stencil_" .. kernel_name .. "() -> i64\n    return 0\nend\n"
    elseif candidate.rewrite_kind or (candidate.lowering and candidate.lowering ~= "generic_opcode_sequence") then
        source = emit_rewrite_body(candidate, ops)
        if not source then source = "func stencil_" .. kernel_name .. "() -> i64\n    return 0\nend\n" end
    else
        local parts = { emit_header(candidate, kernel_name) }
        for i, op in ipairs(ops) do
            parts[#parts + 1] = emit_op(candidate, op, i, i == 1 and "pc" or ("pc + " .. tostring(i - 1)))
        end
        parts[#parts + 1] = "    frame.pc = pc + " .. tostring(#ops) .. "\n"
        parts[#parts + 1] = "    L.top = top\n"
        parts[#parts + 1] = "    return pc + " .. tostring(#ops) .. "\n"
        parts[#parts + 1] = "end\n"
        source = table.concat(parts)
    end

    return {
        id = kernel_name,
        name = kernel_name,
        source = source,
        path = config.output_dir and (config.output_dir .. "/" .. kernel_name .. ".mlua") or nil,
        candidate_id = candidate.id,
        arity = candidate.arity or #ops,
        ops = ops,
        abi = config.trivial and "trivial" or "jit_stencil_v0",
    }
end

function M.emit_code_stencil_kernel(candidate, config)
    return M.emit_candidate_kernel(candidate, config)
end

function M.emit_rewrite_stencil_spec(candidate, config)
    return {
        id = candidate.id or "rewrite",
        type = "rewrite",
        pattern = candidate.pattern or {},
        required_facts = candidate.facts or {},
        replacement = candidate.replacement or {},
        proof = candidate.proof or "unproven",
    }
end

function M.write_kernel_source(kernel, output_dir)
    if not output_dir then return nil, "output_dir required" end
    util.mkdir_p(output_dir)
    local ext = kernel.language == "c" and ".c" or ".mlua"
    local path = output_dir .. "/" .. kernel.name .. ext
    local ok, err = util.write_file(path, kernel.source)
    if not ok then return nil, "cannot write to " .. path .. ": " .. tostring(err) end
    kernel.path = path
    return path
end

function M.emit_kernel_batch(candidates, config)
    config = config or {}
    local kernels, written = {}, 0
    for _, candidate in ipairs(candidates or {}) do
        local kernel = M.emit_candidate_kernel(candidate, config)
        if config.output_dir then
            local path, err = M.write_kernel_source(kernel, config.output_dir)
            if path then written = written + 1 elseif not config.ignore_errors then return nil, err end
        end
        table.insert(kernels, kernel)
    end
    return { kernels = kernels, emitted = #kernels, written = written }
end

function M.report_emission(result)
    print("\n=== Kernel Emission ===")
    print(string.format("Emitted: %d kernels", result.emitted or 0))
    print(string.format("Written: %d files", result.written or 0))
end

return M
