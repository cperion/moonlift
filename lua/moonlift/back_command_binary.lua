-- BackProgram binary wire format encoder.
--
-- Encodes MoonBack.BackProgram into the MLBT v3 binary format described in
-- BACK_WIRE_FORMAT.md.  Replaces the text-based BackCommandTape path with
-- zero string escaping, zero string parsing, and identifier deduplication
-- via a string pool.

local ffi = require("ffi")
local bit = require("bit")

local M = {}

-- Scalar kind → numeric tag (matches BACK_WIRE_FORMAT.md §8.1).
local SCALAR_TAG = {
    BackBool  = 1,  BackI8  = 2,  BackI16 = 3,  BackI32 = 4,  BackI64 = 5,
    BackU8    = 6,  BackU16 = 7,  BackU32 = 8,  BackU64 = 9,  BackF32 = 10,
    BackF64   = 11, BackPtr = 12, BackIndex = 13,
}

-- Command kind → numeric tag (matches BACK_WIRE_FORMAT.md §7).
local CMD_TAG = {
    CmdTargetModel     = 1,  CmdAliasFact       = 2,
    CmdCreateSig       = 3,  CmdDeclareData     = 4,
    CmdDataInitZero    = 5,  CmdDataInit        = 6,
    CmdDataAddr        = 7,  CmdFuncAddr        = 8,
    CmdExternAddr      = 9,  CmdDeclareFunc     = 10,
    CmdDeclareExtern   = 11, CmdBeginFunc       = 12,
    CmdCreateBlock     = 13, CmdSwitchToBlock   = 14,
    CmdSealBlock       = 15, CmdBindEntryParams = 16,
    CmdAppendBlockParam= 17, CmdCreateStackSlot = 18,
    CmdAlias           = 19, CmdStackAddr       = 20,
    CmdConst           = 21, CmdUnary           = 22,
    CmdIntrinsic       = 23, CmdCompare         = 24,
    CmdCast            = 25, CmdPtrOffset       = 26,
    CmdLoadInfo        = 27, CmdStoreInfo       = 28,
    CmdAtomicLoad      = 29, CmdAtomicStore     = 30,
    CmdAtomicRmw       = 31, CmdAtomicCas       = 32,
    CmdAtomicFence     = 33,
    CmdIntBinary       = 34, CmdBitBinary       = 35,
    CmdBitNot          = 36, CmdShift           = 37,
    CmdRotate          = 38, CmdFloatBinary     = 39,
    CmdMemcpy          = 40, CmdMemset          = 41,
    CmdSelect          = 42, CmdFma             = 43,
    CmdVecSplat        = 44, CmdVecBinary       = 45,
    CmdVecCompare      = 46, CmdVecSelect       = 47,
    CmdVecMask         = 48, CmdVecInsertLane   = 49,
    CmdVecExtractLane  = 50, CmdVecLoadInfo     = 51,
    CmdVecStoreInfo    = 52,
    CmdCall            = 53, CmdJump            = 54,
    CmdBrIf            = 55, CmdSwitchInt       = 56,
    CmdReturnVoid      = 57, CmdReturnValue     = 58,
    CmdTrap            = 59, CmdFinishFunc      = 60,
    CmdFinalizeModule  = 61,
}

-- Integer overflow kind → numeric tag.
local OVERFLOW_TAG = {
    BackIntWrap = 0, BackIntNoSignedWrap = 1,
    BackIntNoUnsignedWrap = 2, BackIntNoWrap = 3,
}

-- Op kind → numeric tag tables (match BACK_WIRE_FORMAT.md §8.13–§8.24).
local INT_OP_TAG = {
    BackIntAdd = 1, BackIntSub = 2, BackIntMul = 3,
    BackIntSDiv = 4, BackIntUDiv = 5, BackIntSRem = 6, BackIntURem = 7,
}
local BIT_OP_TAG = {
    BackBitAnd = 1, BackBitOr = 2, BackBitXor = 3,
}
local SHIFT_OP_TAG = {
    BackShiftLeft = 1, BackShiftLogicalRight = 2, BackShiftArithmeticRight = 3,
}
local ROTATE_OP_TAG = {
    BackRotateLeft = 1, BackRotateRight = 2,
}
local FLOAT_OP_TAG = {
    BackFloatAdd = 1, BackFloatSub = 2, BackFloatMul = 3, BackFloatDiv = 4,
}
local UNARY_OP_TAG = {
    BackUnaryIneg = 1, BackUnaryFneg = 2, BackUnaryBnot = 3, BackUnaryBoolNot = 4,
}
local INTRINSIC_OP_TAG = {
    BackIntrinsicPopcount = 1, BackIntrinsicClz = 2, BackIntrinsicCtz = 3,
    BackIntrinsicBswap = 4, BackIntrinsicSqrt = 5, BackIntrinsicAbs = 6,
    BackIntrinsicFloor = 7, BackIntrinsicCeil = 8, BackIntrinsicTruncFloat = 9,
    BackIntrinsicRound = 10,
}
local COMPARE_OP_TAG = {
    BackIcmpEq = 1, BackIcmpNe = 2,
    BackSIcmpLt = 3, BackSIcmpLe = 4, BackSIcmpGt = 5, BackSIcmpGe = 6,
    BackUIcmpLt = 7, BackUIcmpLe = 8, BackUIcmpGt = 9, BackUIcmpGe = 10,
    BackFCmpEq = 11, BackFCmpNe = 12, BackFCmpLt = 13, BackFCmpLe = 14,
    BackFCmpGt = 15, BackFCmpGe = 16,
}
local CAST_OP_TAG = {
    BackBitcast = 1, BackIreduce = 2, BackSextend = 3, BackUextend = 4,
    BackFpromote = 5, BackFdemote = 6, BackSToF = 7, BackUToF = 8,
    BackFToS = 9, BackFToU = 10,
}
local VEC_BIN_OP_TAG = {
    BackVecIntAdd = 1, BackVecIntSub = 2, BackVecIntMul = 3,
    BackVecBitAnd = 4, BackVecBitOr = 5, BackVecBitXor = 6,
}
local VEC_CMP_OP_TAG = {
    BackVecIcmpEq = 1, BackVecIcmpNe = 2,
    BackVecSIcmpLt = 3, BackVecSIcmpLe = 4, BackVecSIcmpGt = 5, BackVecSIcmpGe = 6,
    BackVecUIcmpLt = 7, BackVecUIcmpLe = 8, BackVecUIcmpGt = 9, BackVecUIcmpGe = 10,
}
local VEC_MASK_OP_TAG = {
    BackVecMaskNot = 1, BackVecMaskAnd = 2, BackVecMaskOr = 3,
}
local ATOMIC_RMW_OP_TAG = {
    BackAtomicRmwAdd = 1, BackAtomicRmwSub = 2, BackAtomicRmwAnd = 3,
    BackAtomicRmwOr = 4, BackAtomicRmwXor = 5, BackAtomicRmwXchg = 6,
}

local function id_text(node) return type(node) == "string" and node or node.text end

local function scalar_tag(s)
    return assert(SCALAR_TAG[s.kind], "unsupported scalar kind " .. tostring(s.kind))
end

local function op_tag(table, op)
    return assert(table[op.kind], "unsupported op kind " .. tostring(op.kind))
end

-- Shape encoding: returns (shape_tag, scalar, lanes).
-- shape_tag: 0=scalar, 1=vector.
local function shape_parts(shape)
    if shape.kind == "BackShapeScalar" then
        return 0, scalar_tag(shape.scalar), 0
    end
    return 1, scalar_tag(shape.vec.elem), shape.vec.lanes
end

-- Address base encoding: returns (base_tag, base_id_string).
-- base_tag: 0=value, 1=stack, 2=data.
local function base_parts(base)
    if base.kind == "BackAddrValue" then return 0, id_text(base.value) end
    if base.kind == "BackAddrStack" then return 1, id_text(base.slot)  end
    if base.kind == "BackAddrData"  then return 2, id_text(base.data)  end
    error("unsupported address base kind " .. tostring(base.kind))
end

-- Memory info encoding: returns 8 values.
-- access_id_string, align_k, align_b, deref_k, deref_b, trap_k, motion_k, mode_k
local function mem_parts(m, Back)
    local ak, ab = 0, 0
    if m.alignment.kind == "BackAlignKnown"      then ak, ab = 1, m.alignment.bytes
    elseif m.alignment.kind == "BackAlignAtLeast" then ak, ab = 2, m.alignment.bytes
    elseif m.alignment.kind == "BackAlignAssumed" then ak, ab = 3, m.alignment.bytes end
    local dk, db = 0, 0
    if m.dereference.kind == "BackDerefBytes"     then dk, db = 1, m.dereference.bytes
    elseif m.dereference.kind == "BackDerefAssumed" then dk, db = 2, m.dereference.bytes end
    local tk = 0
    if m.trap.kind == "BackNonTrapping" then tk = 1
    elseif m.trap.kind == "BackChecked"  then tk = 2 end
    local mk = m.motion.kind == "BackCanMove" and 1 or 0
    local mode = 1
    if m.mode == Back.BackAccessWrite       then mode = 2
    elseif m.mode == Back.BackAccessReadWrite then mode = 3 end
    return id_text(m.access), ak, ab, dk, db, tk, mk, mode
end

local function u64_parts_from_number(raw)
    local text = tostring(raw or "0")
    local neg = false
    if text:sub(1, 1) == "-" then
        neg = true
        text = text:sub(2)
    elseif text:sub(1, 1) == "+" then
        text = text:sub(2)
    end
    local lo, hi = 0, 0
    for i = 1, #text do
        local d = text:byte(i) - 48
        if d >= 0 and d <= 9 then
            local x = lo * 10 + d
            lo = x % 4294967296
            hi = (hi * 10 + math.floor(x / 4294967296)) % 4294967296
        end
    end
    if neg then
        if lo == 0 then
            hi = (-hi) % 4294967296
        else
            lo = 4294967296 - lo
            hi = (4294967295 - hi) % 4294967296
        end
    end
    return lo, hi
end

-- Literal encoding: returns (lit_tag, lit_lo, lit_hi).
-- lit_tag: 0=null, 1=bool, 2=int, 3=float.
local function lit_parts(v)
    if v.kind == "BackLitNull"  then return 0, 0, 0 end
    if v.kind == "BackLitBool"  then return 1, v.value and 1 or 0, 0 end
    if v.kind == "BackLitInt"   then
        local lo, hi = u64_parts_from_number(v.raw)
        return 2, lo, hi
    end
    if v.kind == "BackLitFloat" then
        local bits = ffi.new("union { double d; uint32_t w[2]; }")
        bits.d = tonumber(v.raw) or 0.0
        return 3, tonumber(bits.w[0]), tonumber(bits.w[1])
    end
    error("unsupported literal kind " .. tostring(v.kind))
end

-- Call result encoding: returns (result_tag, result_dst_string, result_scalar).
-- result_tag: 0=stmt, 1=value.
local function call_result_parts(result)
    if result.kind == "BackCallStmt" then return 0, nil, 0 end
    return 1, id_text(result.dst), scalar_tag(result.ty)
end

-- Call target encoding: returns (target_tag, target_id_string).
-- target_tag: 0=direct, 1=extern, 2=indirect.
local function call_target_parts(target)
    if target.kind == "BackCallDirect"   then return 0, id_text(target.func) end
    if target.kind == "BackCallExtern"   then return 1, id_text(target.func) end
    if target.kind == "BackCallIndirect" then return 2, id_text(target.callee) end
    error("unsupported call target kind " .. tostring(target.kind))
end

-- Atomic ordering encoding.
local function ordering_tag(o)
    if o.kind == "BackAtomicSeqCst" then return 1 end
    error("unsupported atomic ordering kind " .. tostring(o.kind))
end

-- Integer semantics encoding: returns (overflow, exact).
local function int_sem_parts(s)
    local ok = assert(OVERFLOW_TAG[s.overflow.kind], "unsupported overflow kind " .. tostring(s.overflow.kind))
    local ek = s.exact.kind == "BackIntExact" and 1 or 0
    return ok, ek
end

-- Float semantics encoding: returns u32.
local function float_sem_tag(s)
    return s.kind == "BackFloatFastMath" and 1 or 0
end

-- =========================================================================
-- WireBuilder: accumulates the four sections of the wire format.
-- =========================================================================

local WireBuilder = {}
WireBuilder.__index = WireBuilder

function WireBuilder.new()
    local self = setmetatable({}, WireBuilder)
    self._pool_map = {}        -- [string] → pool index (0-based)
    self._pool_buf = {}        -- list: alternating len_u32, byte1, byte2, ..., pad_bytes
    self._pool_count = 0
    self._aux_entries = {}     -- list of { count, data[] }
    self._aux_count = 0
    self._cmd_buf = {}         -- flat u32 list: tag, slots..., tag, slots...
    return self
end

-- Intern a string into the pool. Returns the pool index (0-based).
function WireBuilder:pool(text)
    text = tostring(text)
    local idx = self._pool_map[text]
    if idx ~= nil then return idx end
    idx = self._pool_count
    self._pool_map[text] = idx
    self._pool_count = idx + 1
    -- Store as: len + raw bytes + padding (will be serialized in :tostring()).
    self._pool_buf[#self._pool_buf + 1] = { len = #text, text = text }
    return idx
end

-- Append a u32 array to aux data. Returns the aux index (0-based).
function WireBuilder:aux(data)
    local idx = self._aux_count
    self._aux_count = idx + 1
    self._aux_entries[#self._aux_entries + 1] = { count = #data, data = data }
    return idx
end

-- Append a command: tag followed by slot values.
function WireBuilder:cmd(tag, slots)
    self._cmd_buf[#self._cmd_buf + 1] = tag
    for i = 1, #slots do
        self._cmd_buf[#self._cmd_buf + 1] = slots[i]
    end
end

-- Serialize the full wire buffer into a Lua string.
function WireBuilder:tostring()
    local buf = {}
    local function w32(v)
        buf[#buf + 1] = string.char(
            bit.band(v, 0xff),
            bit.band(bit.rshift(v, 8), 0xff),
            bit.band(bit.rshift(v, 16), 0xff),
            bit.band(bit.rshift(v, 24), 0xff)
        )
    end

    -- 1. Header.
    w32(0x4D4C4254)    -- magic "MLBT"
    w32(3)              -- version
    w32(self._pool_count)
    w32(self._aux_count)

    -- 2. String pool.
    for i = 1, #self._pool_buf do
        local entry = self._pool_buf[i]
        w32(entry.len)
        if entry.len > 0 then
            buf[#buf + 1] = entry.text
        end
        local pad = (4 - (entry.len % 4)) % 4
        if pad > 0 then
            buf[#buf + 1] = ("\0"):rep(pad)
        end
    end

    -- 3. Aux data.
    for i = 1, #self._aux_entries do
        local entry = self._aux_entries[i]
        w32(entry.count)
        for j = 1, entry.count do
            w32(entry.data[j])
        end
    end

    -- 4. Command stream.
    for i = 1, #self._cmd_buf do
        w32(self._cmd_buf[i])
    end

    return table.concat(buf)
end

-- =========================================================================
-- Encoder: walks a BackProgram and writes into a WireBuilder.
-- =========================================================================

local Encoder = {}
Encoder.__index = Encoder

function Encoder.new(Back)
    local self = setmetatable({}, Encoder)
    self._Back = Back
    self._wb = WireBuilder.new()
    return self
end

-- Intern an ID string into the pool and return its pool index.
function Encoder:pid(node)
    return self._wb:pool(id_text(node))
end

-- Intern a list of ID strings into aux and return (aux_idx, count).
function Encoder:val_ids(nodes)
    local data = {}
    for i = 1, #nodes do data[i] = self._wb:pool(id_text(nodes[i])) end
    return self._wb:aux(data), #nodes
end

-- Intern a list of scalar tags into aux and return (aux_idx, count).
function Encoder:scalar_ids(nodes)
    local data = {}
    for i = 1, #nodes do data[i] = scalar_tag(nodes[i]) end
    return self._wb:aux(data), #nodes
end

-- Memory info: returns 8 u32 values for the slots.
function Encoder:mem(m)
    local access_id, ak, ab, dk, db, tk, mk, mode = mem_parts(m, self._Back)
    return self._wb:pool(access_id), ak, ab, dk, db, tk, mk, mode
end

-- Encode a single command.
function Encoder:encode_cmd(cmd)
    local k = cmd.kind
    local wb = self._wb
    local tag = assert(CMD_TAG[k], "unsupported command kind " .. tostring(k))

    if k == "CmdTargetModel" or k == "CmdAliasFact" then
        wb:cmd(tag, {})

    elseif k == "CmdCreateSig" then
        local pa, pn = self:scalar_ids(cmd.params)
        local ra, rn = self:scalar_ids(cmd.results)
        wb:cmd(tag, { self:pid(cmd.sig), pa, pn, ra, rn })

    elseif k == "CmdDeclareData" then
        wb:cmd(tag, { self:pid(cmd.data), cmd.size, cmd.align })

    elseif k == "CmdDataInitZero" then
        wb:cmd(tag, { self:pid(cmd.data), cmd.offset, cmd.size })

    elseif k == "CmdDataInit" then
        local lt, ll, lh = lit_parts(cmd.value)
        wb:cmd(tag, { self:pid(cmd.data), cmd.offset, scalar_tag(cmd.ty), lt, ll, lh })

    elseif k == "CmdDataAddr" then
        wb:cmd(tag, { self:pid(cmd.dst), self:pid(cmd.data) })

    elseif k == "CmdFuncAddr" then
        wb:cmd(tag, { self:pid(cmd.dst), self:pid(cmd.func) })

    elseif k == "CmdExternAddr" then
        wb:cmd(tag, { self:pid(cmd.dst), self:pid(cmd.func) })

    elseif k == "CmdDeclareFunc" then
        local vis = cmd.visibility.kind == "VisibilityExport" and 1 or 0
        wb:cmd(tag, { vis, self:pid(cmd.func), self:pid(cmd.sig) })

    elseif k == "CmdDeclareExtern" then
        wb:cmd(tag, { self:pid(cmd.func), wb:pool(cmd.symbol), self:pid(cmd.sig) })

    elseif k == "CmdBeginFunc" then
        wb:cmd(tag, { self:pid(cmd.func) })

    elseif k == "CmdCreateBlock" then
        wb:cmd(tag, { self:pid(cmd.block) })

    elseif k == "CmdSwitchToBlock" then
        wb:cmd(tag, { self:pid(cmd.block) })

    elseif k == "CmdSealBlock" then
        wb:cmd(tag, { self:pid(cmd.block) })

    elseif k == "CmdBindEntryParams" then
        local va, vc = self:val_ids(cmd.values)
        wb:cmd(tag, { self:pid(cmd.block), va, vc })

    elseif k == "CmdAppendBlockParam" then
        local st, sc, sl = shape_parts(cmd.ty)
        wb:cmd(tag, { self:pid(cmd.block), self:pid(cmd.value), st, sc, sl })

    elseif k == "CmdCreateStackSlot" then
        wb:cmd(tag, { self:pid(cmd.slot), cmd.size, cmd.align })

    elseif k == "CmdAlias" then
        wb:cmd(tag, { self:pid(cmd.dst), self:pid(cmd.src) })

    elseif k == "CmdStackAddr" then
        wb:cmd(tag, { self:pid(cmd.dst), self:pid(cmd.slot) })

    elseif k == "CmdConst" then
        local lt, ll, lh = lit_parts(cmd.value)
        wb:cmd(tag, { self:pid(cmd.dst), scalar_tag(cmd.ty), lt, ll, lh })

    elseif k == "CmdUnary" then
        local st, sc, sl = shape_parts(cmd.ty)
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(UNARY_OP_TAG, cmd.op), st, sc, sl, self:pid(cmd.value) })

    elseif k == "CmdIntrinsic" then
        local st, sc, sl = shape_parts(cmd.ty)
        local aa, ac = self:val_ids(cmd.args)
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(INTRINSIC_OP_TAG, cmd.op), st, sc, sl, aa, ac })

    elseif k == "CmdCompare" then
        local st, sc, sl = shape_parts(cmd.ty)
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(COMPARE_OP_TAG, cmd.op), st, sc, sl, self:pid(cmd.lhs), self:pid(cmd.rhs) })

    elseif k == "CmdCast" then
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(CAST_OP_TAG, cmd.op), scalar_tag(cmd.ty), self:pid(cmd.value) })

    elseif k == "CmdPtrOffset" then
        local bt, bi_str = base_parts(cmd.base)
        local co_lo, co_hi = u64_parts_from_number(cmd.const_offset)
        wb:cmd(tag, { self:pid(cmd.dst), bt, wb:pool(bi_str), self:pid(cmd.index), cmd.elem_size, co_lo, co_hi })

    elseif k == "CmdLoadInfo" then
        local st, sc, sl = shape_parts(cmd.ty)
        local bt, bi_str = base_parts(cmd.addr.base)
        local bi = wb:pool(bi_str)
        local m1, m2, m3, m4, m5, m6, m7, m8 = self:mem(cmd.memory)
        wb:cmd(tag, { self:pid(cmd.dst), st, sc, sl, bt, bi, self:pid(cmd.addr.byte_offset), m1, m2, m3, m4, m5, m6, m7, m8 })

    elseif k == "CmdStoreInfo" then
        local st, sc, sl = shape_parts(cmd.ty)
        local bt, bi_str = base_parts(cmd.addr.base)
        local bi = wb:pool(bi_str)
        local m1, m2, m3, m4, m5, m6, m7, m8 = self:mem(cmd.memory)
        wb:cmd(tag, { st, sc, sl, bt, bi, self:pid(cmd.addr.byte_offset), self:pid(cmd.value), m1, m2, m3, m4, m5, m6, m7, m8 })

    elseif k == "CmdAtomicLoad" then
        local bt, bi_str = base_parts(cmd.addr.base)
        local bi = wb:pool(bi_str)
        local m1, m2, m3, m4, m5, m6, m7, m8 = self:mem(cmd.memory)
        wb:cmd(tag, { self:pid(cmd.dst), scalar_tag(cmd.ty), bt, bi, self:pid(cmd.addr.byte_offset), m1, m2, m3, m4, m5, m6, m7, m8, ordering_tag(cmd.ordering), 0 })

    elseif k == "CmdAtomicStore" then
        local bt, bi_str = base_parts(cmd.addr.base)
        local bi = wb:pool(bi_str)
        local m1, m2, m3, m4, m5, m6, m7, m8 = self:mem(cmd.memory)
        wb:cmd(tag, { scalar_tag(cmd.ty), bt, bi, self:pid(cmd.addr.byte_offset), self:pid(cmd.value), m1, m2, m3, m4, m5, m6, m7, m8, ordering_tag(cmd.ordering) })

    elseif k == "CmdAtomicRmw" then
        local bt, bi_str = base_parts(cmd.addr.base)
        local bi = wb:pool(bi_str)
        local m1, m2, m3, m4, m5, m6, m7, m8 = self:mem(cmd.memory)
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(ATOMIC_RMW_OP_TAG, cmd.op), scalar_tag(cmd.ty), bt, bi, self:pid(cmd.addr.byte_offset), self:pid(cmd.value), m1, m2, m3, m4, m5, m6, m7, m8, ordering_tag(cmd.ordering) })

    elseif k == "CmdAtomicCas" then
        local bt, bi_str = base_parts(cmd.addr.base)
        local bi = wb:pool(bi_str)
        local m1, m2, m3, m4, m5, m6, m7, m8 = self:mem(cmd.memory)
        wb:cmd(tag, { self:pid(cmd.dst), scalar_tag(cmd.ty), bt, bi, self:pid(cmd.addr.byte_offset), self:pid(cmd.expected), self:pid(cmd.replacement), m1, m2, m3, m4, m5, m6, m7, m8, ordering_tag(cmd.ordering), 0 })

    elseif k == "CmdAtomicFence" then
        wb:cmd(tag, { ordering_tag(cmd.ordering) })

    elseif k == "CmdIntBinary" then
        local ok, ek = int_sem_parts(cmd.semantics)
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(INT_OP_TAG, cmd.op), scalar_tag(cmd.scalar), ok, ek, self:pid(cmd.lhs), self:pid(cmd.rhs) })

    elseif k == "CmdBitBinary" then
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(BIT_OP_TAG, cmd.op), scalar_tag(cmd.scalar), self:pid(cmd.lhs), self:pid(cmd.rhs) })

    elseif k == "CmdBitNot" then
        wb:cmd(tag, { self:pid(cmd.dst), scalar_tag(cmd.scalar), self:pid(cmd.value) })

    elseif k == "CmdShift" then
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(SHIFT_OP_TAG, cmd.op), scalar_tag(cmd.scalar), self:pid(cmd.lhs), self:pid(cmd.rhs) })

    elseif k == "CmdRotate" then
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(ROTATE_OP_TAG, cmd.op), scalar_tag(cmd.scalar), self:pid(cmd.lhs), self:pid(cmd.rhs) })

    elseif k == "CmdFloatBinary" then
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(FLOAT_OP_TAG, cmd.op), scalar_tag(cmd.scalar), float_sem_tag(cmd.semantics), self:pid(cmd.lhs), self:pid(cmd.rhs) })

    elseif k == "CmdMemcpy" then
        wb:cmd(tag, { self:pid(cmd.dst), self:pid(cmd.src), self:pid(cmd.len) })

    elseif k == "CmdMemset" then
        wb:cmd(tag, { self:pid(cmd.dst), self:pid(cmd.byte), self:pid(cmd.len) })

    elseif k == "CmdSelect" then
        local st, sc, sl = shape_parts(cmd.ty)
        wb:cmd(tag, { self:pid(cmd.dst), st, sc, sl, self:pid(cmd.cond), self:pid(cmd.then_value), self:pid(cmd.else_value) })

    elseif k == "CmdFma" then
        wb:cmd(tag, { self:pid(cmd.dst), scalar_tag(cmd.ty), float_sem_tag(cmd.semantics), self:pid(cmd.a), self:pid(cmd.b), self:pid(cmd.c) })

    elseif k == "CmdVecSplat" then
        wb:cmd(tag, { self:pid(cmd.dst), scalar_tag(cmd.ty.elem), cmd.ty.lanes, self:pid(cmd.value) })

    elseif k == "CmdVecBinary" then
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(VEC_BIN_OP_TAG, cmd.op), scalar_tag(cmd.ty.elem), cmd.ty.lanes, self:pid(cmd.lhs), self:pid(cmd.rhs) })

    elseif k == "CmdVecCompare" then
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(VEC_CMP_OP_TAG, cmd.op), scalar_tag(cmd.ty.elem), cmd.ty.lanes, self:pid(cmd.lhs), self:pid(cmd.rhs) })

    elseif k == "CmdVecSelect" then
        wb:cmd(tag, { self:pid(cmd.dst), scalar_tag(cmd.ty.elem), cmd.ty.lanes, self:pid(cmd.mask), self:pid(cmd.then_value), self:pid(cmd.else_value) })

    elseif k == "CmdVecMask" then
        local aa, ac = self:val_ids(cmd.args)
        wb:cmd(tag, { self:pid(cmd.dst), op_tag(VEC_MASK_OP_TAG, cmd.op), scalar_tag(cmd.ty.elem), cmd.ty.lanes, aa, ac })

    elseif k == "CmdVecInsertLane" then
        wb:cmd(tag, { self:pid(cmd.dst), scalar_tag(cmd.ty.elem), cmd.ty.lanes, self:pid(cmd.value), self:pid(cmd.lane_value), cmd.lane })

    elseif k == "CmdVecExtractLane" then
        wb:cmd(tag, { self:pid(cmd.dst), scalar_tag(cmd.ty), self:pid(cmd.value), cmd.lane })

    elseif k == "CmdVecLoadInfo" then
        local bt, bi_str = base_parts(cmd.addr.base)
        local bi = wb:pool(bi_str)
        local m1, m2, m3, m4, m5, m6, m7, m8 = self:mem(cmd.memory)
        wb:cmd(tag, { self:pid(cmd.dst), scalar_tag(cmd.ty.elem), cmd.ty.lanes, bt, bi, self:pid(cmd.addr.byte_offset), m1, m2, m3, m4, m5, m6, m7, m8, 0 })

    elseif k == "CmdVecStoreInfo" then
        local bt, bi_str = base_parts(cmd.addr.base)
        local bi = wb:pool(bi_str)
        local m1, m2, m3, m4, m5, m6, m7, m8 = self:mem(cmd.memory)
        wb:cmd(tag, { scalar_tag(cmd.ty.elem), cmd.ty.lanes, bt, bi, self:pid(cmd.addr.byte_offset), self:pid(cmd.value), m1, m2, m3, m4, m5, m6, m7, m8 })

    elseif k == "CmdCall" then
        local rt, rd_str, rs = call_result_parts(cmd.result)
        local tt, ti_str = call_target_parts(cmd.target)
        local rd = rd_str and wb:pool(rd_str) or 0xFFFFFFFF
        local ti = wb:pool(ti_str)
        local aa, ac = self:val_ids(cmd.args)
        wb:cmd(tag, { rt, rd, rs, tt, ti, self:pid(cmd.sig), aa, ac })

    elseif k == "CmdJump" then
        local aa, ac = self:val_ids(cmd.args)
        wb:cmd(tag, { self:pid(cmd.dest), aa, ac })

    elseif k == "CmdBrIf" then
        local ta, tc = self:val_ids(cmd.then_args)
        local ea, ec = self:val_ids(cmd.else_args)
        wb:cmd(tag, { self:pid(cmd.cond), self:pid(cmd.then_block), ta, tc, self:pid(cmd.else_block), ea, ec })

    elseif k == "CmdSwitchInt" then
        local cases_data = {}
        for i = 1, #cmd.cases do
            local lo, hi = u64_parts_from_number(cmd.cases[i].raw)
            cases_data[#cases_data + 1] = lo
            cases_data[#cases_data + 1] = hi
            cases_data[#cases_data + 1] = wb:pool(id_text(cmd.cases[i].dest))
        end
        local ca = wb:aux(cases_data)
        wb:cmd(tag, { self:pid(cmd.value), scalar_tag(cmd.ty), ca, #cmd.cases, self:pid(cmd.default_dest) })

    elseif k == "CmdReturnVoid" then
        wb:cmd(tag, {})

    elseif k == "CmdReturnValue" then
        wb:cmd(tag, { self:pid(cmd.value) })

    elseif k == "CmdTrap" then
        wb:cmd(tag, {})

    elseif k == "CmdFinishFunc" then
        wb:cmd(tag, { self:pid(cmd.func) })

    elseif k == "CmdFinalizeModule" then
        wb:cmd(tag, {})

    else
        error("unsupported command kind " .. tostring(k))
    end
end

-- Encode a full BackProgram into a binary string.
function Encoder:encode(program)
    for i = 1, #program.cmds do
        self:encode_cmd(program.cmds[i])
    end
    return self._wb:tostring()
end

-- =========================================================================
-- Public API: same interface as back_command_tape.
-- =========================================================================

function M.Define(T)
    local Back = T.MoonBack or T.MoonBack
    assert(Back, "moonlift.back_command_binary.Define expects MoonBack in the context")

    local function encode(program)
        local enc = Encoder.new(Back)
        return enc:encode(program)
    end

    return { encode = encode }
end

return M
