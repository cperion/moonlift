local pvm = require("lalin.pvm")
local Mx = require("back.dasm.model")

local function emit_entries(pairs, D)
    if #pairs == 0 then return pvm.empty() end
    local out = {}
    for i = 1, #pairs do
        local kv = pairs[i]
        out[#out + 1] = D.DScalarMapEntry(kv[1], kv[2])
    end
    if #out == 1 then return pvm.once(out[1]) end
    return pvm.seq(out)
end

local PHASE_CMD = nil
local function cmd_phase()
    if PHASE_CMD then return PHASE_CMD end
    local B = Mx.back()
    local D = Mx.dasm()

    local handlers = {}
    local function none() return pvm.empty() end

    handlers[B.CmdBindEntryParams] = function(cmd, sig)
        local pairs = {}
        local params = sig and sig.params or {}
        for i, v in ipairs(cmd.values or {}) do
            local sk = Mx.scalar_kind(params[i])
            if sk then pairs[#pairs + 1] = { Mx.idkey(v), sk } end
        end
        return emit_entries(pairs, D)
    end

    handlers[B.CmdAppendBlockParam] = function(cmd)
        return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.value), Mx.shape_scalar_kind(cmd.ty)))
    end

    handlers[B.CmdConst] = function(cmd)
        return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.dst), Mx.scalar_kind(cmd.ty)))
    end

    handlers[B.CmdUnary] = function(cmd)
        return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.dst), Mx.shape_scalar_kind(cmd.ty)))
    end

    handlers[B.CmdIntrinsic] = handlers[B.CmdUnary]

    handlers[B.CmdCompare] = function(cmd)
        return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.dst), "BackBool"))
    end

    handlers[B.CmdCast] = function(cmd)
        return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.dst), Mx.scalar_kind(cmd.ty)))
    end

    handlers[B.CmdPtrOffset] = function(cmd)
        return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.dst), "BackPtr"))
    end
    handlers[B.CmdStackAddr] = handlers[B.CmdPtrOffset]
    handlers[B.CmdDataAddr] = handlers[B.CmdPtrOffset]
    handlers[B.CmdFuncAddr] = handlers[B.CmdPtrOffset]
    handlers[B.CmdExternAddr] = handlers[B.CmdPtrOffset]

    handlers[B.CmdLoadInfo] = function(cmd)
        return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.dst), Mx.shape_scalar_kind(cmd.ty)))
    end

    handlers[B.CmdIntBinary] = function(cmd)
        return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.dst), Mx.scalar_kind(cmd.scalar)))
    end
    handlers[B.CmdBitBinary] = handlers[B.CmdIntBinary]
    handlers[B.CmdBitNot] = handlers[B.CmdIntBinary]
    handlers[B.CmdShift] = handlers[B.CmdIntBinary]
    handlers[B.CmdRotate] = handlers[B.CmdIntBinary]
    handlers[B.CmdFloatBinary] = handlers[B.CmdIntBinary]

    handlers[B.CmdSelect] = function(cmd)
        return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.dst), Mx.shape_scalar_kind(cmd.ty)))
    end

    handlers[B.CmdFma] = function(cmd)
        return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.dst), Mx.scalar_kind(cmd.ty)))
    end

    handlers[B.CmdCall] = function(cmd)
        if cmd.result and cmd.result.kind == "BackCallValue" then
            return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.result.dst), Mx.scalar_kind(cmd.result.ty)))
        end
        return pvm.empty()
    end

    handlers[B.CmdAlias] = function(cmd, sig, out)
        local sk = out and out[Mx.idkey(cmd.src)] or nil
        if sk then return pvm.once(D.DScalarMapEntry(Mx.idkey(cmd.dst), sk)) end
        return pvm.empty()
    end

    local cmd_variants = {
        "CmdTargetModel", "CmdCreateSig", "CmdDeclareData", "CmdDataInitZero", "CmdDataInit",
        "CmdDeclareFunc", "CmdDeclareExtern", "CmdBeginFunc", "CmdCreateBlock", "CmdSwitchToBlock",
        "CmdSealBlock", "CmdCreateStackSlot", "CmdStoreInfo", "CmdAliasFact", "CmdMemcpy", "CmdMemset",
        "CmdVecSplat", "CmdVecBinary", "CmdVecCompare", "CmdVecSelect", "CmdVecMask",
        "CmdVecInsertLane", "CmdVecExtractLane", "CmdJump", "CmdBrIf", "CmdSwitchInt", "CmdReturnVoid",
        "CmdReturnValue", "CmdTrap", "CmdFinishFunc", "CmdFinalizeModule",
    }
    for i = 1, #cmd_variants do
        local n = cmd_variants[i]
        if not handlers[B[n]] then handlers[B[n]] = none end
    end

    PHASE_CMD = pvm.phase("lalin_dasm_type_values_cmd", handlers)
    return PHASE_CMD
end

local function infer_type_values(pf, sig)
    local D = Mx.dasm()

    local func = Mx.phase_func_id(pf)
    local body = Mx.phase_func_cmds(pf)

    local out = {}
    local phase = cmd_phase()
    for i = 1, #body do
        local cmd = body[i]
        local entries = pvm.drain(phase(cmd, sig, out))
        for j = 1, #entries do
            local e = entries[j]
            out[e.key] = e.scalar
        end
    end

    return D.DTypedFunc(func, body, Mx.scalar_entries_from_map(out))
end

local PHASE = nil
local function phase()
    if PHASE then return PHASE end
    local D = Mx.dasm()

    PHASE = pvm.phase("lalin_dasm_type_values", {
        [D.DPhaseFunc] = function(pf, sig)
            return pvm.once(infer_type_values(pf, sig))
        end,
    })

    return PHASE
end

return {
    phase = function() return phase() end,
    run = function(phase_func, sig)
        local D = Mx.dasm()
        if pvm.classof(phase_func) ~= D.DPhaseFunc then
            error("type_values.run expects LalinDasm.DPhaseFunc", 2)
        end
        return pvm.one(phase()(phase_func, sig))
    end,
}
