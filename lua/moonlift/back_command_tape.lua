local M = {}

local SCALAR = { BackBool = 1, BackI8 = 2, BackI16 = 3, BackI32 = 4, BackI64 = 5, BackU8 = 6, BackU16 = 7, BackU32 = 8, BackU64 = 9, BackF32 = 10, BackF64 = 11, BackPtr = 12, BackIndex = 13 }

local function esc(s)
    s = tostring(s)
    local out = s:gsub("([\\\t\n])", function(c)
        if c == "\\" then return "\\\\" end
        if c == "\t" then return "\\t" end
        return "\\n"
    end)
    return out
end

local function id(x) return esc(type(x) == "string" and x or x.text) end
local function scalar(s) return tostring(assert(SCALAR[s.kind], "unsupported scalar " .. tostring(s.kind))) end
local function scalars(xs) local out = { tostring(#xs) }; for i = 1, #xs do out[#out + 1] = scalar(xs[i]) end; return out end
local function ids(xs) local out = { tostring(#xs) }; for i = 1, #xs do out[#out + 1] = id(xs[i]) end; return out end
local function bool(v) return v and "1" or "0" end

local function shape_parts(shape)
    if shape.kind == "BackShapeScalar" then return { "S", scalar(shape.scalar) } end
    return { "V", scalar(shape.vec.elem), tostring(shape.vec.lanes) }
end

local function base_parts(base)
    if base.kind == "BackAddrValue" then return { "V", id(base.value) } end
    if base.kind == "BackAddrStack" then return { "S", id(base.slot) } end
    if base.kind == "BackAddrData" then return { "D", id(base.data) } end
    error("unsupported address base " .. tostring(base.kind))
end

local function addr_parts(addr)
    local out = base_parts(addr.base)
    out[#out + 1] = id(addr.byte_offset)
    return out
end

local function mem_parts(m)
    local ak, ab = 0, 0
    if m.alignment.kind == "BackAlignKnown" then ak, ab = 1, m.alignment.bytes
    elseif m.alignment.kind == "BackAlignAtLeast" then ak, ab = 2, m.alignment.bytes
    elseif m.alignment.kind == "BackAlignAssumed" then ak, ab = 3, m.alignment.bytes end
    local dk, db = 0, 0
    if m.dereference.kind == "BackDerefBytes" then dk, db = 1, m.dereference.bytes
    elseif m.dereference.kind == "BackDerefAssumed" then dk, db = 2, m.dereference.bytes end
    local tk = m.trap.kind == "BackNonTrapping" and 1 or (m.trap.kind == "BackChecked" and 2 or 0)
    local mk = m.motion.kind == "BackCanMove" and 1 or 0
    local mode = m.mode == M._Back.BackAccessWrite and 2 or (m.mode == M._Back.BackAccessReadWrite and 3 or 1)
    return { id(m.access), tostring(ak), tostring(ab), tostring(dk), tostring(db), tostring(tk), tostring(mk), tostring(mode) }
end

local function lit_parts(v)
    if v.kind == "BackLitInt" then return { "I", esc(v.raw) } end
    if v.kind == "BackLitFloat" then return { "F", esc(v.raw) } end
    if v.kind == "BackLitBool" then return { "B", bool(v.value) } end
    if v.kind == "BackLitNull" then return { "N" } end
    error("unsupported literal " .. tostring(v.kind))
end

local function int_sem_parts(s)
    local ok = ({ BackIntWrap = 0, BackIntNoSignedWrap = 1, BackIntNoUnsignedWrap = 2, BackIntNoWrap = 3 })[s.overflow.kind] or 0
    local ek = s.exact.kind == "BackIntExact" and 1 or 0
    return { tostring(ok), tostring(ek) }
end

local function float_sem(s) return s.kind == "BackFloatFastMath" and "1" or "0" end
local function append(out, xs) for i = 1, #xs do out[#out + 1] = xs[i] end end
local function line(op, fields) local out = { op }; append(out, fields or {}); return table.concat(out, "\t") end

function M.Define(T)
    local Back = T.MoonBack or T.MoonBack
    assert(Back, "moonlift.back_command_tape.Define expects MoonBack/MoonBack in the context")

    local function encode_cmd(cmd)
        local k = cmd.kind
        if k == "CmdTargetModel" or k == "CmdAliasFact" then return line(k) end
        if k == "CmdCreateSig" then local f = { id(cmd.sig) }; append(f, scalars(cmd.params)); append(f, scalars(cmd.results)); return line(k, f) end
        if k == "CmdDeclareData" then return line(k, { id(cmd.data), tostring(cmd.size), tostring(cmd.align) }) end
        if k == "CmdDataInitZero" then return line(k, { id(cmd.data), tostring(cmd.offset), tostring(cmd.size) }) end
        if k == "CmdDataInit" then local f = { id(cmd.data), tostring(cmd.offset), scalar(cmd.ty) }; append(f, lit_parts(cmd.value)); return line(k, f) end
        if k == "CmdDataAddr" then return line(k, { id(cmd.dst), id(cmd.data) }) end
        if k == "CmdFuncAddr" then return line(k, { id(cmd.dst), id(cmd.func) }) end
        if k == "CmdExternAddr" then return line(k, { id(cmd.dst), id(cmd.func) }) end
        if k == "CmdDeclareFunc" then return line(k, { cmd.visibility.kind == "VisibilityExport" and "E" or "L", id(cmd.func), id(cmd.sig) }) end
        if k == "CmdDeclareExtern" then return line(k, { id(cmd.func), esc(cmd.symbol), id(cmd.sig) }) end
        if k == "CmdBeginFunc" or k == "CmdFinishFunc" then return line(k, { id(cmd.func) }) end
        if k == "CmdCreateBlock" or k == "CmdSwitchToBlock" or k == "CmdSealBlock" then return line(k, { id(cmd.block) }) end
        if k == "CmdBindEntryParams" then local f = { id(cmd.block) }; append(f, ids(cmd.values)); return line(k, f) end
        if k == "CmdAppendBlockParam" then local f = { id(cmd.block), id(cmd.value) }; append(f, shape_parts(cmd.ty)); return line(k, f) end
        if k == "CmdCreateStackSlot" then return line(k, { id(cmd.slot), tostring(cmd.size), tostring(cmd.align) }) end
        if k == "CmdAlias" then return line(k, { id(cmd.dst), id(cmd.src) }) end
        if k == "CmdStackAddr" then return line(k, { id(cmd.dst), id(cmd.slot) }) end
        if k == "CmdConst" then local f = { id(cmd.dst), scalar(cmd.ty) }; append(f, lit_parts(cmd.value)); return line(k, f) end
        if k == "CmdUnary" then local f = { id(cmd.dst), cmd.op.kind }; append(f, shape_parts(cmd.ty)); f[#f + 1] = id(cmd.value); return line(k, f) end
        if k == "CmdIntrinsic" then local f = { id(cmd.dst), cmd.op.kind }; append(f, shape_parts(cmd.ty)); append(f, ids(cmd.args)); return line(k, f) end
        if k == "CmdCompare" then local f = { id(cmd.dst), cmd.op.kind }; append(f, shape_parts(cmd.ty)); f[#f + 1] = id(cmd.lhs); f[#f + 1] = id(cmd.rhs); return line(k, f) end
        if k == "CmdCast" then return line(k, { id(cmd.dst), cmd.op.kind, scalar(cmd.ty), id(cmd.value) }) end
        if k == "CmdPtrOffset" then local f = { id(cmd.dst) }; append(f, base_parts(cmd.base)); f[#f + 1] = id(cmd.index); f[#f + 1] = tostring(cmd.elem_size); f[#f + 1] = tostring(cmd.const_offset); return line(k, f) end
        if k == "CmdLoadInfo" then local f = { id(cmd.dst) }; append(f, shape_parts(cmd.ty)); append(f, addr_parts(cmd.addr)); append(f, mem_parts(cmd.memory)); return line(k, f) end
        if k == "CmdStoreInfo" then local f = {}; append(f, shape_parts(cmd.ty)); append(f, addr_parts(cmd.addr)); f[#f + 1] = id(cmd.value); append(f, mem_parts(cmd.memory)); return line(k, f) end
        if k == "CmdIntBinary" then local f = { id(cmd.dst), cmd.op.kind, scalar(cmd.scalar) }; append(f, int_sem_parts(cmd.semantics)); f[#f + 1] = id(cmd.lhs); f[#f + 1] = id(cmd.rhs); return line(k, f) end
        if k == "CmdBitBinary" or k == "CmdShift" or k == "CmdRotate" then return line(k, { id(cmd.dst), cmd.op.kind, scalar(cmd.scalar), id(cmd.lhs), id(cmd.rhs) }) end
        if k == "CmdBitNot" then return line(k, { id(cmd.dst), scalar(cmd.scalar), id(cmd.value) }) end
        if k == "CmdFloatBinary" then return line(k, { id(cmd.dst), cmd.op.kind, scalar(cmd.scalar), float_sem(cmd.semantics), id(cmd.lhs), id(cmd.rhs) }) end
        if k == "CmdMemcpy" or k == "CmdMemset" then return line(k, { id(cmd.dst), id(cmd.src or cmd.byte), id(cmd.len) }) end
        if k == "CmdSelect" then local f = { id(cmd.dst) }; append(f, shape_parts(cmd.ty)); f[#f + 1] = id(cmd.cond); f[#f + 1] = id(cmd.then_value); f[#f + 1] = id(cmd.else_value); return line(k, f) end
        if k == "CmdFma" then return line(k, { id(cmd.dst), scalar(cmd.ty), float_sem(cmd.semantics), id(cmd.a), id(cmd.b), id(cmd.c) }) end
        if k == "CmdVecSplat" then return line(k, { id(cmd.dst), scalar(cmd.ty.elem), tostring(cmd.ty.lanes), id(cmd.value) }) end
        if k == "CmdVecBinary" or k == "CmdVecCompare" then return line(k, { id(cmd.dst), cmd.op.kind, scalar(cmd.ty.elem), tostring(cmd.ty.lanes), id(cmd.lhs), id(cmd.rhs) }) end
        if k == "CmdVecSelect" then return line(k, { id(cmd.dst), scalar(cmd.ty.elem), tostring(cmd.ty.lanes), id(cmd.mask), id(cmd.then_value), id(cmd.else_value) }) end
        if k == "CmdVecMask" then local f = { id(cmd.dst), cmd.op.kind, scalar(cmd.ty.elem), tostring(cmd.ty.lanes) }; append(f, ids(cmd.args)); return line(k, f) end
        if k == "CmdVecInsertLane" then return line(k, { id(cmd.dst), scalar(cmd.ty.elem), tostring(cmd.ty.lanes), id(cmd.value), id(cmd.lane_value), tostring(cmd.lane) }) end
        if k == "CmdVecExtractLane" then return line(k, { id(cmd.dst), scalar(cmd.ty), id(cmd.value), tostring(cmd.lane) }) end
        if k == "CmdCall" then local f = { cmd.result.kind, cmd.result.dst and id(cmd.result.dst) or "", cmd.result.ty and scalar(cmd.result.ty) or "0", cmd.target.kind, id(cmd.target.func or cmd.target.callee), id(cmd.sig) }; append(f, ids(cmd.args)); return line(k, f) end
        if k == "CmdJump" then local f = { id(cmd.dest) }; append(f, ids(cmd.args)); return line(k, f) end
        if k == "CmdBrIf" then local f = { id(cmd.cond), id(cmd.then_block) }; append(f, ids(cmd.then_args)); f[#f + 1] = id(cmd.else_block); append(f, ids(cmd.else_args)); return line(k, f) end
        if k == "CmdSwitchInt" then local f = { id(cmd.value), scalar(cmd.ty), tostring(#cmd.cases) }; for i = 1, #cmd.cases do f[#f + 1] = esc(cmd.cases[i].raw); f[#f + 1] = id(cmd.cases[i].dest) end; f[#f + 1] = id(cmd.default_dest); return line(k, f) end
        if k == "CmdReturnVoid" or k == "CmdTrap" or k == "CmdFinalizeModule" then return line(k) end
        if k == "CmdReturnValue" then return line(k, { id(cmd.value) }) end
        error("unsupported BackCommandTape command " .. tostring(k))
    end

    M._Back = Back

    local function encode(program)
        local lines = { "moonlift-back-command-tape-v2" }
        for i = 1, #program.cmds do lines[#lines + 1] = encode_cmd(program.cmds[i]) end
        return Back.BackCommandTape(2, #program.cmds, table.concat(lines, "\n"))
    end

    return { encode = encode }
end

return M
