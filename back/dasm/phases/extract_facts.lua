local pvm = require("lalin.pvm")
local bit = require("bit")
local Mx = require("back.dasm.model")

local function emit_many(xs)
    if #xs == 0 then return pvm.empty() end
    if #xs == 1 then return pvm.once(xs[1]) end
    return pvm.seq(xs)
end

local function scalar_obj(B, sk)
    if type(sk) == "table" then
        if sk.kind then return sk end
        return nil
    end
    if type(sk) == "string" then return B[sk] end
    return nil
end

local function value_class_of(D, B, sk)
    local s = scalar_obj(B, sk) or B.BackI64
    local k = s and s.kind or nil
    if k == "BackF32" or k == "BackF64" then return D.DValueXmm(s) end
    return D.DValueGpr(s)
end

local function shape_from_scalar(B, sk)
    local s = scalar_obj(B, sk)
    if not s then return nil end
    return B.BackShapeScalar(s)
end

local function const_kind_of(D, lit)
    if not lit then return D.DConstUnknown end
    local k = lit.kind
    if k == "BackLitInt" then return D.DConstInt(lit.raw)
    elseif k == "BackLitFloat" then return D.DConstFloat(lit.raw)
    elseif k == "BackLitBool" then return D.DConstBool(lit.value)
    elseif k == "BackLitNull" then return D.DConstNull
    end
    return D.DConstUnknown
end

local function const_is_zero(c)
    if not c then return false end
    local k = c.kind
    if k == "DConstInt" then return tonumber(c.raw) == 0 end
    if k == "DConstFloat" then return tonumber(c.raw) == 0 end
    if k == "DConstBool" then return c.value == false end
    if k == "DConstNull" then return true end
    return false
end

local function int_const_pow2(c)
    if not c or c.kind ~= "DConstInt" then return false end
    local n = tonumber(c.raw)
    if not n or n <= 0 then return false end
    if math.floor(n) ~= n then return false end
    if n > 0x7fffffff then return false end
    local ni = math.floor(n)
    return bit.band(ni, ni - 1) == 0
end

local function intbin_commutative(op)
    local k = op and op.kind
    return k == "BackIntAdd" or k == "BackIntMul"
end

local function addr_base_kind(D, base)
    local bk = base and base.kind
    if bk == "BackAddrValue" then return D.DBaseValue
    elseif bk == "BackAddrStack" then return D.DBaseStack
    elseif bk == "BackAddrData" then return D.DBaseData end
    return D.DBaseUnknown
end

local function align_bytes(memory)
    local a = memory and memory.alignment
    if not a then return 0 end
    local k = a.kind
    if k == "BackAlignKnown" or k == "BackAlignAtLeast" or k == "BackAlignAssumed" then
        return tonumber(a.bytes) or 0
    end
    return 0
end

local function trap_kind(memory)
    local t = memory and memory.trap
    return (t and t.kind) or "BackTrapUnknown"
end

local function cmd_defs(cmd)
    local k = cmd.kind
    if k == "CmdConst" or k == "CmdAlias" or k == "CmdUnary" or k == "CmdIntrinsic"
        or k == "CmdCompare" or k == "CmdCast" or k == "CmdPtrOffset" or k == "CmdLoadInfo"
        or k == "CmdIntBinary" or k == "CmdBitBinary" or k == "CmdBitNot" or k == "CmdShift"
        or k == "CmdRotate" or k == "CmdFloatBinary" or k == "CmdSelect" or k == "CmdFma"
        or k == "CmdVecSplat" or k == "CmdVecBinary" or k == "CmdVecCompare" or k == "CmdVecSelect"
        or k == "CmdVecMask" or k == "CmdVecInsertLane" or k == "CmdVecExtractLane"
        or k == "CmdStackAddr" or k == "CmdDataAddr" or k == "CmdFuncAddr" or k == "CmdExternAddr" then
        return { cmd.dst }
    elseif k == "CmdCall" then
        if cmd.result and cmd.result.kind == "BackCallValue" then return { cmd.result.dst } end
    elseif k == "CmdBindEntryParams" then
        return cmd.values or {}
    end
    return {}
end

local function cmd_uses(cmd)
    local k = cmd.kind
    local uses = {}
    local function add(v) if v then uses[#uses + 1] = v end end

    if k == "CmdAlias" then add(cmd.src)
    elseif k == "CmdUnary" then add(cmd.value)
    elseif k == "CmdIntrinsic" then for i = 1, #(cmd.args or {}) do add(cmd.args[i]) end
    elseif k == "CmdCompare" then add(cmd.lhs); add(cmd.rhs)
    elseif k == "CmdCast" then add(cmd.value)
    elseif k == "CmdPtrOffset" then add(cmd.index)
    elseif k == "CmdLoadInfo" then add(cmd.addr and cmd.addr.byte_offset)
    elseif k == "CmdStoreInfo" then add(cmd.addr and cmd.addr.byte_offset); add(cmd.value)
    elseif k == "CmdIntBinary" or k == "CmdBitBinary" or k == "CmdShift" or k == "CmdRotate" or k == "CmdFloatBinary" then
        add(cmd.lhs); add(cmd.rhs)
    elseif k == "CmdBitNot" then add(cmd.value)
    elseif k == "CmdSelect" then add(cmd.cond); add(cmd.then_value); add(cmd.else_value)
    elseif k == "CmdFma" then add(cmd.a); add(cmd.b); add(cmd.c)
    elseif k == "CmdMemcpy" then add(cmd.dst); add(cmd.src); add(cmd.len)
    elseif k == "CmdMemset" then add(cmd.dst); add(cmd.byte); add(cmd.len)
    elseif k == "CmdCall" then
        for i = 1, #(cmd.args or {}) do add(cmd.args[i]) end
        if cmd.target and cmd.target.kind == "BackCallIndirect" then add(cmd.target.callee) end
    elseif k == "CmdJump" then for i = 1, #(cmd.args or {}) do add(cmd.args[i]) end
    elseif k == "CmdBrIf" then add(cmd.cond); for i = 1, #(cmd.then_args or {}) do add(cmd.then_args[i]) end; for i = 1, #(cmd.else_args or {}) do add(cmd.else_args[i]) end
    elseif k == "CmdSwitchInt" then add(cmd.value)
    elseif k == "CmdReturnValue" then add(cmd.value)
    end

    return uses
end

local function mk_generic_atoms(D, cmd, idx, block)
    local out = { D.DFactCmdKind(idx, cmd.kind) }
    if block then out[#out + 1] = D.DFactBlockAt(idx, block) end

    local defs = cmd_defs(cmd)
    for i = 1, #defs do out[#out + 1] = D.DFactDef(defs[i], idx) end

    local uses = cmd_uses(cmd)
    for i = 1, #uses do out[#out + 1] = D.DFactUse(uses[i], idx, i) end

    return out
end

local PHASE_CONST = nil
local PHASE_ATOM = nil
local PHASE_FAMILY = nil

local function phase_const()
    if PHASE_CONST then return PHASE_CONST end
    local B = Mx.back()
    local D = Mx.dasm()

    PHASE_CONST = pvm.phase("lalin_dasm_cmd_const_fact", {
        [B.CmdConst] = function(cmd)
            return pvm.once(D.DFactValueConst(cmd.dst, const_kind_of(D, cmd.value)))
        end,
    })

    return PHASE_CONST
end

local function phase_atom()
    if PHASE_ATOM then return PHASE_ATOM end
    local B = Mx.back()
    local D = Mx.dasm()

    local handlers = {}

    local cmd_variants = {
        "CmdTargetModel", "CmdCreateSig", "CmdDeclareData", "CmdDataInitZero", "CmdDataInit",
        "CmdDataAddr", "CmdFuncAddr", "CmdExternAddr", "CmdDeclareFunc", "CmdDeclareExtern",
        "CmdBeginFunc", "CmdCreateBlock", "CmdSwitchToBlock", "CmdSealBlock", "CmdBindEntryParams",
        "CmdAppendBlockParam", "CmdCreateStackSlot", "CmdAlias", "CmdStackAddr", "CmdConst", "CmdUnary",
        "CmdIntrinsic", "CmdCompare", "CmdCast", "CmdPtrOffset", "CmdLoadInfo", "CmdStoreInfo",
        "CmdIntBinary", "CmdBitBinary", "CmdBitNot", "CmdShift", "CmdRotate", "CmdFloatBinary",
        "CmdAliasFact", "CmdMemcpy", "CmdMemset", "CmdSelect", "CmdFma", "CmdVecSplat", "CmdVecBinary",
        "CmdVecCompare", "CmdVecSelect", "CmdVecMask", "CmdVecInsertLane", "CmdVecExtractLane",
        "CmdCall", "CmdJump", "CmdBrIf", "CmdSwitchInt", "CmdReturnVoid", "CmdReturnValue",
        "CmdTrap", "CmdFinishFunc", "CmdFinalizeModule",
    }

    local function generic(cmd, idx, block)
        return emit_many(mk_generic_atoms(D, cmd, idx, block))
    end

    for i = 1, #cmd_variants do
        local name = cmd_variants[i]
        handlers[B[name]] = generic
    end

    -- CmdConst adds explicit value-const atom.
    handlers[B.CmdConst] = function(cmd, idx, block)
        local out = mk_generic_atoms(D, cmd, idx, block)
        out[#out + 1] = D.DFactValueConst(cmd.dst, const_kind_of(D, cmd.value))
        return emit_many(out)
    end

    PHASE_ATOM = pvm.phase("lalin_dasm_cmd_atoms", handlers)
    return PHASE_ATOM
end

local function phase_family()
    if PHASE_FAMILY then return PHASE_FAMILY end
    local B = Mx.back()
    local D = Mx.dasm()

    local handlers = {}
    local function none() return pvm.empty() end

    handlers[B.CmdAlias] = function(cmd, idx, block, value_scalars, const_map)
        local sk = value_scalars and value_scalars[Mx.idkey(cmd.dst)]
        local cls = value_class_of(D, B, sk)
        local csrc = const_map[Mx.idkey(cmd.src)] or D.DConstUnknown
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyCopy, D.DKeyCopy(cls, csrc, Mx.idkey(cmd.dst) == Mx.idkey(cmd.src))))
    end

    handlers[B.CmdIntBinary] = function(cmd, idx, block, _, const_map)
        local lc = const_map[Mx.idkey(cmd.lhs)] or D.DConstUnknown
        local rc = const_map[Mx.idkey(cmd.rhs)] or D.DConstUnknown
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyIntBin,
            D.DKeyIntBin(cmd.op.kind, cmd.scalar, lc, rc, intbin_commutative(cmd.op), int_const_pow2(rc))))
    end

    handlers[B.CmdBitBinary] = function(cmd, idx, block, _, const_map)
        local rc = const_map[Mx.idkey(cmd.rhs)] or D.DConstUnknown
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyBitBin, D.DKeyBitBin(cmd.op.kind, cmd.scalar, rc)))
    end

    handlers[B.CmdShift] = function(cmd, idx, block, _, const_map)
        local rc = const_map[Mx.idkey(cmd.rhs)] or D.DConstUnknown
        local n = (rc.kind == "DConstInt") and tonumber(rc.raw) or nil
        local small = n and n >= 0 and n <= 63 or false
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyShiftRotate, D.DKeyShiftRotate(cmd.op.kind, cmd.scalar, rc, small)))
    end

    handlers[B.CmdRotate] = handlers[B.CmdShift]

    handlers[B.CmdCompare] = function(cmd, idx, block, _, const_map, next_cmd)
        local rc = const_map[Mx.idkey(cmd.rhs)] or D.DConstUnknown
        local fused = next_cmd and next_cmd.kind == "CmdBrIf" and Mx.idkey(next_cmd.cond) == Mx.idkey(cmd.dst) or false
        local scalar = (cmd.ty and cmd.ty.kind == "BackShapeScalar") and cmd.ty.scalar or B.BackI64
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyCompareBranch,
            D.DKeyCompareBranch(cmd.op.kind, scalar, rc, fused, const_is_zero(rc))))
    end

    handlers[B.CmdLoadInfo] = function(cmd, idx, block, _, const_map)
        local addr = cmd.addr
        local has_index = addr and addr.byte_offset ~= nil
        local cdisp = false
        if has_index then cdisp = (const_map[Mx.idkey(addr.byte_offset)] or D.DConstUnknown).kind ~= "DConstUnknown" end
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyLoadStore,
            D.DKeyLoadStore(true, cmd.ty, addr_base_kind(D, addr and addr.base), has_index, cdisp, align_bytes(cmd.memory), trap_kind(cmd.memory))))
    end

    handlers[B.CmdStoreInfo] = function(cmd, idx, block, _, const_map)
        local addr = cmd.addr
        local has_index = addr and addr.byte_offset ~= nil
        local cdisp = false
        if has_index then cdisp = (const_map[Mx.idkey(addr.byte_offset)] or D.DConstUnknown).kind ~= "DConstUnknown" end
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyLoadStore,
            D.DKeyLoadStore(false, cmd.ty, addr_base_kind(D, addr and addr.base), has_index, cdisp, align_bytes(cmd.memory), trap_kind(cmd.memory))))
    end

    handlers[B.CmdPtrOffset] = function(cmd, idx, block)
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyAddress,
            D.DKeyAddress(addr_base_kind(D, cmd.base), cmd.elem_size or 1, cmd.const_offset or 0)))
    end

    handlers[B.CmdStackAddr] = function(cmd, idx, block)
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyAddress,
            D.DKeyAddress(D.DBaseStack, 1, 0)))
    end
    handlers[B.CmdDataAddr] = function(cmd, idx, block)
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyAddress,
            D.DKeyAddress(D.DBaseData, 1, 0)))
    end
    handlers[B.CmdFuncAddr] = handlers[B.CmdDataAddr]
    handlers[B.CmdExternAddr] = handlers[B.CmdDataAddr]

    handlers[B.CmdCall] = function(cmd, idx, block, value_scalars)
        local has_result = cmd.result and cmd.result.kind == "BackCallValue"
        local rcls = D.DValueGpr(B.BackVoid)
        if has_result then
            local sk = value_scalars and value_scalars[Mx.idkey(cmd.result.dst)]
            rcls = value_class_of(D, B, sk)
        end
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyCall,
            D.DKeyCall(cmd.target and cmd.target.kind or "BackCallUnknown", #(cmd.args or {}), has_result, rcls)))
    end

    handlers[B.CmdJump] = function(cmd, idx, block)
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyControl, D.DKeyControl("CmdJump")))
    end
    handlers[B.CmdBrIf] = function(cmd, idx, block)
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyControl, D.DKeyControl("CmdBrIf")))
    end
    handlers[B.CmdSwitchInt] = function(cmd, idx, block)
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyControl, D.DKeyControl("CmdSwitchInt")))
    end

    handlers[B.CmdReturnVoid] = function(cmd, idx, block)
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyReturn, D.DKeyReturn(false, D.DValueGpr(B.BackVoid))))
    end

    handlers[B.CmdReturnValue] = function(cmd, idx, block, value_scalars)
        local sk = value_scalars and value_scalars[Mx.idkey(cmd.value)]
        return pvm.once(D.DFamilyInstance(idx, block, D.DFamilyReturn, D.DKeyReturn(true, value_class_of(D, B, sk))))
    end

    -- default empty handlers for all remaining command variants
    local cmd_variants = {
        "CmdTargetModel", "CmdCreateSig", "CmdDeclareData", "CmdDataInitZero", "CmdDataInit",
        "CmdDeclareFunc", "CmdDeclareExtern", "CmdBeginFunc", "CmdCreateBlock", "CmdSwitchToBlock",
        "CmdSealBlock", "CmdBindEntryParams", "CmdAppendBlockParam", "CmdCreateStackSlot", "CmdConst",
        "CmdUnary", "CmdIntrinsic", "CmdCast", "CmdBitNot", "CmdFloatBinary", "CmdAliasFact",
        "CmdMemcpy", "CmdMemset", "CmdSelect", "CmdFma", "CmdVecSplat", "CmdVecBinary",
        "CmdVecCompare", "CmdVecSelect", "CmdVecMask", "CmdVecInsertLane", "CmdVecExtractLane",
        "CmdTrap", "CmdFinishFunc", "CmdFinalizeModule",
    }
    for i = 1, #cmd_variants do
        local n = cmd_variants[i]
        if not handlers[B[n]] then handlers[B[n]] = none end
    end

    PHASE_FAMILY = pvm.phase("lalin_dasm_cmd_family", handlers)
    return PHASE_FAMILY
end

local function run_extract(pf, value_scalars)
    local D = Mx.dasm()
    local B = Mx.back()

    local func = Mx.phase_func_id(pf)
    local cmds = Mx.phase_func_cmds(pf)

    local const_map = {}
    local cphase = phase_const()
    for i = 1, #cmds do
        local cmd = cmds[i]
        if cmd.kind == "CmdConst" then
            local f = pvm.one(cphase(cmd))
            const_map[Mx.idkey(f.value)] = f.const_kind
        end
    end

    local atoms, families = {}, {}
    local block = nil
    local aphase = phase_atom()
    local fphase = phase_family()

    for i = 1, #cmds do
        local cmd = cmds[i]
        if cmd.kind == "CmdSwitchToBlock" then block = cmd.block end

        local atom_items = pvm.drain(aphase(cmd, i, block, value_scalars, const_map))
        for j = 1, #atom_items do atoms[#atoms + 1] = atom_items[j] end

        local next_cmd = cmds[i + 1]
        local fam_items = pvm.drain(fphase(cmd, i, block, value_scalars, const_map, next_cmd))
        for j = 1, #fam_items do families[#families + 1] = fam_items[j] end
    end

    for key, sk in pairs(value_scalars or {}) do
        local vid = B.BackValId(key)
        local shape = shape_from_scalar(B, sk)
        if shape then atoms[#atoms + 1] = D.DFactValueShape(vid, shape) end
        atoms[#atoms + 1] = D.DFactValueClass(vid, value_class_of(D, B, sk))
        local ck = const_map[key]
        if ck then atoms[#atoms + 1] = D.DFactValueConst(vid, ck) end
    end

    return D.DFactSet(func, cmds, atoms, families)
end

local PHASE_EXTRACT = nil
local function phase_extract()
    if PHASE_EXTRACT then return PHASE_EXTRACT end
    local D = Mx.dasm()
    PHASE_EXTRACT = pvm.phase("lalin_dasm_extract_facts", {
        [D.DPhaseFunc] = function(pf, value_scalars)
            return pvm.once(run_extract(pf, value_scalars))
        end,
    })
    return PHASE_EXTRACT
end

return {
    phase = function() return phase_extract() end,
    run = function(phase_func, value_scalars)
        local D = Mx.dasm()
        if pvm.classof(phase_func) ~= D.DPhaseFunc then
            error("extract_facts.run expects LalinDasm.DPhaseFunc", 2)
        end
        return pvm.one(phase_extract()(phase_func, value_scalars or {}))
    end,
}
