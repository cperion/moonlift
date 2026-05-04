local pvm = require("moonlift.pvm")

local M = {}

local function add_issue(issues, issue)
    issues[#issues + 1] = issue
end

local function note_unique(seen, key, issue_fn, issues)
    if seen[key] then
        add_issue(issues, issue_fn())
        return false
    end
    seen[key] = true
    return true
end

local function has(seen, key)
    return seen ~= nil and seen[key] == true
end

local function facts_triplet(facts)
    local trips = {}
    for i = 1, #facts do
        trips[i] = { pvm.once(facts[i]) }
    end
    return pvm.concat_all(trips)
end

local function append_value_uses(out, B, index, values)
    for i = 1, #values do
        out[#out + 1] = B.BackFactValueUse(index, values[i])
    end
end

local function append_value_defs(out, B, index, values)
    for i = 1, #values do
        out[#out + 1] = B.BackFactValueDef(index, values[i])
    end
end

function M.Define(T)
    local B = T.MoonBack or T.MoonBack
    assert(B, "moonlift.back_validate.Define expects MoonBack/MoonBack in the context")

    local function append_address_base_uses(out, index, base)
        local cls = pvm.classof(base)
        if cls == B.BackAddrValue then
            out[#out + 1] = B.BackFactValueUse(index, base.value)
        elseif cls == B.BackAddrStack then
            out[#out + 1] = B.BackFactStackSlotRef(index, base.slot)
        elseif cls == B.BackAddrData then
            out[#out + 1] = B.BackFactDataRef(index, base.data)
        end
    end

    local function append_address_uses(out, index, addr)
        append_address_base_uses(out, index, addr.base)
        out[#out + 1] = B.BackFactValueUse(index, addr.byte_offset)
    end

    local function append_alias_access_refs(out, index, fact)
        local cls = pvm.classof(fact)
        if cls == B.BackAliasScope then
            out[#out + 1] = B.BackFactAliasAccessRef(index, fact.access)
        else
            out[#out + 1] = B.BackFactAliasAccessRef(index, fact.a)
            out[#out + 1] = B.BackFactAliasAccessRef(index, fact.b)
        end
    end

    local function scalar_size_bytes(scalar)
        if scalar == B.BackBool or scalar == B.BackI8 or scalar == B.BackU8 then return 1 end
        if scalar == B.BackI16 or scalar == B.BackU16 then return 2 end
        if scalar == B.BackI32 or scalar == B.BackU32 or scalar == B.BackF32 then return 4 end
        if scalar == B.BackI64 or scalar == B.BackU64 or scalar == B.BackF64 or scalar == B.BackPtr or scalar == B.BackIndex then return 8 end
        return nil
    end

    local function shape_size_bytes(shape)
        local cls = pvm.classof(shape)
        if cls == B.BackShapeScalar then return scalar_size_bytes(shape.scalar) end
        if cls == B.BackShapeVec then
            local elem = scalar_size_bytes(shape.vec.elem)
            if elem ~= nil then return elem * shape.vec.lanes end
        end
        return nil
    end

    local function is_power_of_two(n)
        if type(n) ~= "number" or n < 1 or n % 1 ~= 0 then return false end
        while n > 1 do
            if n % 2 ~= 0 then return false end
            n = n / 2
        end
        return true
    end

    local function alignment_bytes(alignment)
        local cls = pvm.classof(alignment)
        if cls == B.BackAlignKnown or cls == B.BackAlignAtLeast or cls == B.BackAlignAssumed then return alignment.bytes end
        return nil
    end

    local function dereference_bytes(deref)
        local cls = pvm.classof(deref)
        if cls == B.BackDerefBytes or cls == B.BackDerefAssumed then return deref.bytes end
        return nil
    end

    local function validate_memory_info(issues, index, shape, memory, expected_mode)
        local mode = memory.mode
        if expected_mode == B.BackAccessRead and mode ~= B.BackAccessRead and mode ~= B.BackAccessReadWrite then
            add_issue(issues, B.BackIssueLoadAccessMode(index, mode))
        elseif expected_mode == B.BackAccessWrite and mode ~= B.BackAccessWrite and mode ~= B.BackAccessReadWrite then
            add_issue(issues, B.BackIssueStoreAccessMode(index, mode))
        end
        local align = alignment_bytes(memory.alignment)
        if align ~= nil and not is_power_of_two(align) then
            add_issue(issues, B.BackIssueInvalidAlignment(index, align))
        end
        local deref = dereference_bytes(memory.dereference)
        local access = shape_size_bytes(shape)
        if deref ~= nil and access ~= nil and deref < access then
            add_issue(issues, B.BackIssueDereferenceTooSmall(index, deref, access))
        end
        if pvm.classof(memory.trap) == B.BackNonTrapping and deref == nil then
            add_issue(issues, B.BackIssueNonTrappingWithoutDereference(index))
        end
        if pvm.classof(memory.motion) == B.BackCanMove and pvm.classof(memory.trap) ~= B.BackNonTrapping then
            add_issue(issues, B.BackIssueCanMoveWithoutNonTrapping(index))
        end
    end

    local function is_int_scalar(scalar)
        return scalar == B.BackI8 or scalar == B.BackI16 or scalar == B.BackI32 or scalar == B.BackI64
            or scalar == B.BackU8 or scalar == B.BackU16 or scalar == B.BackU32 or scalar == B.BackU64
            or scalar == B.BackIndex
    end

    local function is_bit_scalar(scalar)
        return scalar == B.BackBool or is_int_scalar(scalar)
    end

    local function is_float_scalar(scalar)
        return scalar == B.BackF32 or scalar == B.BackF64
    end

    local function shape_key(shape)
        local cls = pvm.classof(shape)
        if cls == B.BackShapeScalar then return "s:" .. shape.scalar.kind end
        if cls == B.BackShapeVec then return "v:" .. shape.vec.elem.kind .. ":" .. tostring(shape.vec.lanes) end
        return tostring(shape)
    end

    local function target_supported_shapes(cmds)
        local supported = nil
        for i = 1, #cmds do
            local cmd = cmds[i]
            if pvm.classof(cmd) == B.CmdTargetModel then
                supported = supported or {}
                for j = 1, #cmd.target.facts do
                    local fact = cmd.target.facts[j]
                    if pvm.classof(fact) == B.BackTargetSupportsShape then supported[shape_key(fact.shape)] = true end
                end
            end
        end
        return supported
    end

    local cmd_facts
    local call_target_facts
    local call_result_facts

    call_target_facts = pvm.phase("moonlift_back_call_target_facts", {
        [B.BackCallDirect] = function(self, index)
            return pvm.once(B.BackFactFuncRef(index, self.func))
        end,
        [B.BackCallExtern] = function(self, index)
            return pvm.once(B.BackFactExternRef(index, self.func))
        end,
        [B.BackCallIndirect] = function(self, index)
            return pvm.once(B.BackFactValueUse(index, self.callee))
        end,
    })

    call_result_facts = pvm.phase("moonlift_back_call_result_facts", {
        [B.BackCallStmt] = function()
            return pvm.empty()
        end,
        [B.BackCallValue] = function(self, index)
            return pvm.once(B.BackFactValueDef(index, self.dst))
        end,
    })

    local function body(index)
        return B.BackFactFunctionBodyCommand(index)
    end

    local function shape(index, ty, requirement)
        return B.BackFactShapeUse(index, ty, requirement)
    end

    local function append_cmd_facts_flat(out, cmd, index)
        if cmd == B.CmdFinalizeModule then out[#out + 1] = B.BackFactFinalizeModule(index); return end
        if cmd == B.CmdReturnVoid or cmd == B.CmdTrap then out[#out + 1] = body(index); return end
        local cls = pvm.classof(cmd)
        if cls == B.CmdTargetModel then return end
        if cls == B.CmdCreateSig then out[#out + 1] = B.BackFactCreateSig(index, cmd.sig); return end
        if cls == B.CmdDeclareData then out[#out + 1] = B.BackFactDeclareData(index, cmd.data); return end
        if cls == B.CmdDataInitZero or cls == B.CmdDataInit then out[#out + 1] = B.BackFactDataRef(index, cmd.data); return end
        if cls == B.CmdDeclareFunc then out[#out + 1] = B.BackFactDeclareFunc(index, cmd.func); out[#out + 1] = B.BackFactSigRef(index, cmd.sig); return end
        if cls == B.CmdDeclareExtern then out[#out + 1] = B.BackFactDeclareExtern(index, cmd.func); out[#out + 1] = B.BackFactSigRef(index, cmd.sig); return end
        if cls == B.CmdBeginFunc then out[#out + 1] = B.BackFactBeginFunc(index, cmd.func); out[#out + 1] = B.BackFactFuncRef(index, cmd.func); return end
        if cls == B.CmdFinishFunc then out[#out + 1] = B.BackFactFinishFunc(index, cmd.func); out[#out + 1] = B.BackFactFuncRef(index, cmd.func); return end
        if cls == B.CmdCreateBlock then out[#out + 1] = body(index); out[#out + 1] = B.BackFactCreateBlock(index, cmd.block); return end
        if cls == B.CmdSwitchToBlock or cls == B.CmdSealBlock then out[#out + 1] = body(index); out[#out + 1] = B.BackFactBlockRef(index, cmd.block); return end
        if cls == B.CmdBindEntryParams then out[#out + 1] = body(index); out[#out + 1] = B.BackFactBlockRef(index, cmd.block); append_value_defs(out, B, index, cmd.values); return end
        if cls == B.CmdAppendBlockParam then out[#out + 1] = body(index); out[#out + 1] = B.BackFactBlockRef(index, cmd.block); out[#out + 1] = B.BackFactValueDef(index, cmd.value); return end
        if cls == B.CmdCreateStackSlot then out[#out + 1] = body(index); out[#out + 1] = B.BackFactStackSlotDef(index, cmd.slot); return end
        if cls == B.CmdAlias then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.src); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdStackAddr then out[#out + 1] = body(index); out[#out + 1] = B.BackFactStackSlotRef(index, cmd.slot); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdDataAddr then out[#out + 1] = body(index); out[#out + 1] = B.BackFactDataRef(index, cmd.data); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdFuncAddr then out[#out + 1] = body(index); out[#out + 1] = B.BackFactFuncRef(index, cmd.func); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdExternAddr then out[#out + 1] = body(index); out[#out + 1] = B.BackFactExternRef(index, cmd.func); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdConst then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdUnary then out[#out + 1] = body(index); out[#out + 1] = shape(index, cmd.ty, B.BackShapeRequiresScalar); out[#out + 1] = B.BackFactValueUse(index, cmd.value); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdIntrinsic then out[#out + 1] = body(index); out[#out + 1] = shape(index, cmd.ty, B.BackShapeRequiresScalar); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); append_value_uses(out, B, index, cmd.args); return end
        if cls == B.CmdCompare then out[#out + 1] = body(index); out[#out + 1] = shape(index, cmd.ty, B.BackShapeRequiresScalar); out[#out + 1] = B.BackFactValueUse(index, cmd.lhs); out[#out + 1] = B.BackFactValueUse(index, cmd.rhs); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdCast then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.value); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdPtrOffset then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.index); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); append_address_base_uses(out, index, cmd.base); return end
        if cls == B.CmdLoadInfo then out[#out + 1] = body(index); out[#out + 1] = shape(index, cmd.ty, B.BackShapeAllowsScalarOrVector); out[#out + 1] = B.BackFactAccessDef(index, cmd.memory.access); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); append_address_uses(out, index, cmd.addr); return end
        if cls == B.CmdStoreInfo then out[#out + 1] = body(index); out[#out + 1] = shape(index, cmd.ty, B.BackShapeAllowsScalarOrVector); out[#out + 1] = B.BackFactAccessDef(index, cmd.memory.access); out[#out + 1] = B.BackFactValueUse(index, cmd.value); append_address_uses(out, index, cmd.addr); return end
        if cls == B.CmdIntBinary or cls == B.CmdBitBinary or cls == B.CmdShift or cls == B.CmdRotate or cls == B.CmdFloatBinary then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.lhs); out[#out + 1] = B.BackFactValueUse(index, cmd.rhs); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdBitNot then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.value); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdAliasFact then out[#out + 1] = body(index); append_alias_access_refs(out, index, cmd.fact); return end
        if cls == B.CmdMemcpy then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.dst); out[#out + 1] = B.BackFactValueUse(index, cmd.src); out[#out + 1] = B.BackFactValueUse(index, cmd.len); return end
        if cls == B.CmdMemset then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.dst); out[#out + 1] = B.BackFactValueUse(index, cmd.byte); out[#out + 1] = B.BackFactValueUse(index, cmd.len); return end
        if cls == B.CmdSelect then out[#out + 1] = body(index); out[#out + 1] = shape(index, cmd.ty, B.BackShapeRequiresScalar); out[#out + 1] = B.BackFactValueUse(index, cmd.cond); out[#out + 1] = B.BackFactValueUse(index, cmd.then_value); out[#out + 1] = B.BackFactValueUse(index, cmd.else_value); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdFma then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.a); out[#out + 1] = B.BackFactValueUse(index, cmd.b); out[#out + 1] = B.BackFactValueUse(index, cmd.c); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdVecSplat then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.value); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdVecBinary or cls == B.CmdVecCompare then out[#out + 1] = body(index); out[#out + 1] = shape(index, B.BackShapeVec(cmd.ty), B.BackShapeRequiresVector); out[#out + 1] = B.BackFactValueUse(index, cmd.lhs); out[#out + 1] = B.BackFactValueUse(index, cmd.rhs); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdVecSelect then out[#out + 1] = body(index); out[#out + 1] = shape(index, B.BackShapeVec(cmd.ty), B.BackShapeRequiresVector); out[#out + 1] = B.BackFactValueUse(index, cmd.mask); out[#out + 1] = B.BackFactValueUse(index, cmd.then_value); out[#out + 1] = B.BackFactValueUse(index, cmd.else_value); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdVecMask then out[#out + 1] = body(index); out[#out + 1] = shape(index, B.BackShapeVec(cmd.ty), B.BackShapeRequiresVector); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); append_value_uses(out, B, index, cmd.args); return end
        if cls == B.CmdVecInsertLane then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.value); out[#out + 1] = B.BackFactValueUse(index, cmd.lane_value); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdVecExtractLane then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.value); out[#out + 1] = B.BackFactValueDef(index, cmd.dst); return end
        if cls == B.CmdCall then
            out[#out + 1] = body(index); out[#out + 1] = B.BackFactSigRef(index, cmd.sig)
            local target_cls = pvm.classof(cmd.target)
            if target_cls == B.BackCallDirect then out[#out + 1] = B.BackFactFuncRef(index, cmd.target.func)
            elseif target_cls == B.BackCallExtern then out[#out + 1] = B.BackFactExternRef(index, cmd.target.func)
            elseif target_cls == B.BackCallIndirect then out[#out + 1] = B.BackFactValueUse(index, cmd.target.callee) end
            if cmd.result ~= B.BackCallStmt and pvm.classof(cmd.result) == B.BackCallValue then out[#out + 1] = B.BackFactValueDef(index, cmd.result.dst) end
            append_value_uses(out, B, index, cmd.args)
            return
        end
        if cls == B.CmdJump then out[#out + 1] = body(index); out[#out + 1] = B.BackFactBlockRef(index, cmd.dest); append_value_uses(out, B, index, cmd.args); return end
        if cls == B.CmdBrIf then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.cond); out[#out + 1] = B.BackFactBlockRef(index, cmd.then_block); out[#out + 1] = B.BackFactBlockRef(index, cmd.else_block); append_value_uses(out, B, index, cmd.then_args); append_value_uses(out, B, index, cmd.else_args); return end
        if cls == B.CmdSwitchInt then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.value); out[#out + 1] = B.BackFactBlockRef(index, cmd.default_dest); for i = 1, #cmd.cases do out[#out + 1] = B.BackFactBlockRef(index, cmd.cases[i].dest) end; return end
        if cls == B.CmdReturnValue then out[#out + 1] = body(index); out[#out + 1] = B.BackFactValueUse(index, cmd.value); return end
        local g, p, c = cmd_facts(cmd, index)
        pvm.drain_into(g, p, c, out)
    end

    cmd_facts = pvm.phase("moonlift_back_cmd_facts", {
        [B.CmdTargetModel] = function(_, _)
            return pvm.empty()
        end,
        [B.CmdCreateSig] = function(self, index)
            return facts_triplet({ B.BackFactCreateSig(index, self.sig) })
        end,
        [B.CmdDeclareData] = function(self, index)
            return facts_triplet({ B.BackFactDeclareData(index, self.data) })
        end,
        [B.CmdDataInitZero] = function(self, index)
            return facts_triplet({ B.BackFactDataRef(index, self.data) })
        end,
        [B.CmdDataInit] = function(self, index)
            return facts_triplet({ B.BackFactDataRef(index, self.data) })
        end,
        [B.CmdDeclareFunc] = function(self, index)
            return facts_triplet({ B.BackFactDeclareFunc(index, self.func), B.BackFactSigRef(index, self.sig) })
        end,
        [B.CmdDeclareExtern] = function(self, index)
            return facts_triplet({ B.BackFactDeclareExtern(index, self.func), B.BackFactSigRef(index, self.sig) })
        end,
        [B.CmdBeginFunc] = function(self, index)
            return facts_triplet({ B.BackFactBeginFunc(index, self.func), B.BackFactFuncRef(index, self.func) })
        end,
        [B.CmdFinishFunc] = function(self, index)
            return facts_triplet({ B.BackFactFinishFunc(index, self.func), B.BackFactFuncRef(index, self.func) })
        end,
        [B.CmdFinalizeModule] = function(_, index)
            return facts_triplet({ B.BackFactFinalizeModule(index) })
        end,

        [B.CmdCreateBlock] = function(self, index)
            return facts_triplet({ body(index), B.BackFactCreateBlock(index, self.block) })
        end,
        [B.CmdSwitchToBlock] = function(self, index)
            return facts_triplet({ body(index), B.BackFactBlockRef(index, self.block) })
        end,
        [B.CmdSealBlock] = function(self, index)
            return facts_triplet({ body(index), B.BackFactBlockRef(index, self.block) })
        end,
        [B.CmdBindEntryParams] = function(self, index)
            local out = { body(index), B.BackFactBlockRef(index, self.block) }
            append_value_defs(out, B, index, self.values)
            return facts_triplet(out)
        end,
        [B.CmdAppendBlockParam] = function(self, index)
            return facts_triplet({ body(index), B.BackFactBlockRef(index, self.block), B.BackFactValueDef(index, self.value) })
        end,
        [B.CmdCreateStackSlot] = function(self, index)
            return facts_triplet({ body(index), B.BackFactStackSlotDef(index, self.slot) })
        end,
        [B.CmdAlias] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.src), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdStackAddr] = function(self, index)
            return facts_triplet({ body(index), B.BackFactStackSlotRef(index, self.slot), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdDataAddr] = function(self, index)
            return facts_triplet({ body(index), B.BackFactDataRef(index, self.data), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdFuncAddr] = function(self, index)
            return facts_triplet({ body(index), B.BackFactFuncRef(index, self.func), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdExternAddr] = function(self, index)
            return facts_triplet({ body(index), B.BackFactExternRef(index, self.func), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdConst] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdUnary] = function(self, index)
            return facts_triplet({ body(index), shape(index, self.ty, B.BackShapeRequiresScalar), B.BackFactValueUse(index, self.value), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdIntrinsic] = function(self, index)
            local out = { body(index), shape(index, self.ty, B.BackShapeRequiresScalar), B.BackFactValueDef(index, self.dst) }
            append_value_uses(out, B, index, self.args)
            return facts_triplet(out)
        end,
        [B.CmdCompare] = function(self, index)
            return facts_triplet({ body(index), shape(index, self.ty, B.BackShapeRequiresScalar), B.BackFactValueUse(index, self.lhs), B.BackFactValueUse(index, self.rhs), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdCast] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.value), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdPtrOffset] = function(self, index)
            local out = { body(index), B.BackFactValueUse(index, self.index), B.BackFactValueDef(index, self.dst) }
            append_address_base_uses(out, index, self.base)
            return facts_triplet(out)
        end,
        [B.CmdLoadInfo] = function(self, index)
            local out = { body(index), shape(index, self.ty, B.BackShapeAllowsScalarOrVector), B.BackFactAccessDef(index, self.memory.access), B.BackFactValueDef(index, self.dst) }
            append_address_uses(out, index, self.addr)
            return facts_triplet(out)
        end,
        [B.CmdStoreInfo] = function(self, index)
            local out = { body(index), shape(index, self.ty, B.BackShapeAllowsScalarOrVector), B.BackFactAccessDef(index, self.memory.access), B.BackFactValueUse(index, self.value) }
            append_address_uses(out, index, self.addr)
            return facts_triplet(out)
        end,
        [B.CmdIntBinary] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.lhs), B.BackFactValueUse(index, self.rhs), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdBitBinary] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.lhs), B.BackFactValueUse(index, self.rhs), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdBitNot] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.value), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdShift] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.lhs), B.BackFactValueUse(index, self.rhs), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdRotate] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.lhs), B.BackFactValueUse(index, self.rhs), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdFloatBinary] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.lhs), B.BackFactValueUse(index, self.rhs), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdAliasFact] = function(self, index)
            local out = { body(index) }
            append_alias_access_refs(out, index, self.fact)
            return facts_triplet(out)
        end,
        [B.CmdMemcpy] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.dst), B.BackFactValueUse(index, self.src), B.BackFactValueUse(index, self.len) })
        end,
        [B.CmdMemset] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.dst), B.BackFactValueUse(index, self.byte), B.BackFactValueUse(index, self.len) })
        end,
        [B.CmdSelect] = function(self, index)
            return facts_triplet({ body(index), shape(index, self.ty, B.BackShapeRequiresScalar), B.BackFactValueUse(index, self.cond), B.BackFactValueUse(index, self.then_value), B.BackFactValueUse(index, self.else_value), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdFma] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.a), B.BackFactValueUse(index, self.b), B.BackFactValueUse(index, self.c), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdVecSplat] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.value), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdVecBinary] = function(self, index)
            return facts_triplet({ body(index), shape(index, B.BackShapeVec(self.ty), B.BackShapeRequiresVector), B.BackFactValueUse(index, self.lhs), B.BackFactValueUse(index, self.rhs), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdVecCompare] = function(self, index)
            return facts_triplet({ body(index), shape(index, B.BackShapeVec(self.ty), B.BackShapeRequiresVector), B.BackFactValueUse(index, self.lhs), B.BackFactValueUse(index, self.rhs), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdVecSelect] = function(self, index)
            return facts_triplet({ body(index), shape(index, B.BackShapeVec(self.ty), B.BackShapeRequiresVector), B.BackFactValueUse(index, self.mask), B.BackFactValueUse(index, self.then_value), B.BackFactValueUse(index, self.else_value), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdVecMask] = function(self, index)
            local out = { body(index), shape(index, B.BackShapeVec(self.ty), B.BackShapeRequiresVector), B.BackFactValueDef(index, self.dst) }
            append_value_uses(out, B, index, self.args)
            return facts_triplet(out)
        end,
        [B.CmdVecInsertLane] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.value), B.BackFactValueUse(index, self.lane_value), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdVecExtractLane] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.value), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdCall] = function(self, index)
            return pvm.concat_all({
                { facts_triplet({ body(index), B.BackFactSigRef(index, self.sig) }) },
                { call_target_facts(self.target, index) },
                { call_result_facts(self.result, index) },
                { facts_triplet((function()
                    local out = {}
                    append_value_uses(out, B, index, self.args)
                    return out
                end)()) },
            })
        end,
        [B.CmdJump] = function(self, index)
            local out = { body(index), B.BackFactBlockRef(index, self.dest) }
            append_value_uses(out, B, index, self.args)
            return facts_triplet(out)
        end,
        [B.CmdBrIf] = function(self, index)
            local out = { body(index), B.BackFactValueUse(index, self.cond), B.BackFactBlockRef(index, self.then_block), B.BackFactBlockRef(index, self.else_block) }
            append_value_uses(out, B, index, self.then_args)
            append_value_uses(out, B, index, self.else_args)
            return facts_triplet(out)
        end,
        [B.CmdSwitchInt] = function(self, index)
            local out = { body(index), B.BackFactValueUse(index, self.value), B.BackFactBlockRef(index, self.default_dest) }
            for i = 1, #self.cases do
                out[#out + 1] = B.BackFactBlockRef(index, self.cases[i].dest)
            end
            return facts_triplet(out)
        end,
        [B.CmdReturnVoid] = function(_, index)
            return facts_triplet({ body(index) })
        end,
        [B.CmdReturnValue] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.value) })
        end,
        [B.CmdTrap] = function(_, index)
            return facts_triplet({ body(index) })
        end,
    })

    local function validate_program_impl(program, use_flat)
        local issues = {}
        local cmds = program.cmds
        if #cmds == 0 then
            add_issue(issues, B.BackIssueEmptyProgram)
            add_issue(issues, B.BackIssueMissingFinalize)
            return B.BackValidationReport(issues)
        end

        local facts = {}
        if use_flat then
            for i = 1, #cmds do append_cmd_facts_flat(facts, cmds[i], i) end
        else
            for i = 1, #cmds do
                local g, p, c = cmd_facts(cmds[i], i)
                pvm.drain_into(g, p, c, facts)
            end
        end

        local seen_sig = {}
        local seen_data = {}
        local seen_func = {}
        local seen_extern = {}
        local finalized_index = nil
        local active_func = nil
        local seen_block = nil
        local seen_slot = nil
        local seen_value = nil
        local seen_access = nil

        for i = 1, #facts do
            local fact = facts[i]
            local cls = pvm.classof(fact)

            if cls == B.BackFactCreateSig then
                note_unique(seen_sig, fact.sig, function() return B.BackIssueDuplicateSig(fact.index, fact.sig) end, issues)
            elseif cls == B.BackFactSigRef then
                if not has(seen_sig, fact.sig) then add_issue(issues, B.BackIssueMissingSig(fact.index, fact.sig)) end
            elseif cls == B.BackFactDeclareData then
                note_unique(seen_data, fact.data, function() return B.BackIssueDuplicateData(fact.index, fact.data) end, issues)
            elseif cls == B.BackFactDataRef then
                if not has(seen_data, fact.data) then add_issue(issues, B.BackIssueMissingData(fact.index, fact.data)) end
            elseif cls == B.BackFactDeclareFunc then
                note_unique(seen_func, fact.func, function() return B.BackIssueDuplicateFunc(fact.index, fact.func) end, issues)
            elseif cls == B.BackFactFuncRef then
                if not has(seen_func, fact.func) then add_issue(issues, B.BackIssueMissingFunc(fact.index, fact.func)) end
            elseif cls == B.BackFactDeclareExtern then
                note_unique(seen_extern, fact.func, function() return B.BackIssueDuplicateExtern(fact.index, fact.func) end, issues)
            elseif cls == B.BackFactExternRef then
                if not has(seen_extern, fact.func) then add_issue(issues, B.BackIssueMissingExtern(fact.index, fact.func)) end
            elseif cls == B.BackFactBeginFunc then
                if active_func ~= nil then
                    add_issue(issues, B.BackIssueNestedFunction(fact.index, active_func, fact.func))
                else
                    active_func = fact.func
                    seen_block = {}
                    seen_slot = {}
                    seen_value = {}
                    seen_access = {}
                end
            elseif cls == B.BackFactFinishFunc then
                if active_func == nil then
                    add_issue(issues, B.BackIssueFinishWithoutBegin(fact.index, fact.func))
                elseif active_func ~= fact.func then
                    add_issue(issues, B.BackIssueFinishWrongFunction(fact.index, active_func, fact.func))
                    active_func = nil
                    seen_block = nil
                    seen_slot = nil
                    seen_value = nil
                    seen_access = nil
                else
                    active_func = nil
                    seen_block = nil
                    seen_slot = nil
                    seen_value = nil
                    seen_access = nil
                end
            elseif cls == B.BackFactFinalizeModule then
                if finalized_index == nil then finalized_index = fact.index end
            elseif cls == B.BackFactFunctionBodyCommand then
                if active_func == nil then add_issue(issues, B.BackIssueCommandOutsideFunction(fact.index)) end
            elseif cls == B.BackFactCreateBlock then
                if active_func ~= nil then
                    note_unique(seen_block, fact.block, function() return B.BackIssueDuplicateBlock(fact.index, fact.block) end, issues)
                end
            elseif cls == B.BackFactBlockRef then
                if active_func ~= nil and not has(seen_block, fact.block) then add_issue(issues, B.BackIssueMissingBlock(fact.index, fact.block)) end
            elseif cls == B.BackFactStackSlotDef then
                if active_func ~= nil then
                    note_unique(seen_slot, fact.slot, function() return B.BackIssueDuplicateStackSlot(fact.index, fact.slot) end, issues)
                end
            elseif cls == B.BackFactStackSlotRef then
                if active_func ~= nil and not has(seen_slot, fact.slot) then add_issue(issues, B.BackIssueMissingStackSlot(fact.index, fact.slot)) end
            elseif cls == B.BackFactValueDef then
                if active_func ~= nil then
                    note_unique(seen_value, fact.value, function() return B.BackIssueDuplicateValue(fact.index, fact.value) end, issues)
                end
            elseif cls == B.BackFactValueUse then
                if active_func ~= nil and not has(seen_value, fact.value) then add_issue(issues, B.BackIssueMissingValue(fact.index, fact.value)) end
            elseif cls == B.BackFactAccessDef then
                if active_func ~= nil then
                    note_unique(seen_access, fact.access, function() return B.BackIssueDuplicateAccess(fact.index, fact.access) end, issues)
                end
            elseif cls == B.BackFactAccessRef or cls == B.BackFactAliasAccessRef then
                if active_func ~= nil and not has(seen_access, fact.access) then add_issue(issues, B.BackIssueMissingAccess(fact.index, fact.access)) end
            elseif cls == B.BackFactShapeUse then
                local shape_cls = pvm.classof(fact.shape)
                if fact.requirement == B.BackShapeRequiresScalar and shape_cls ~= B.BackShapeScalar then
                    add_issue(issues, B.BackIssueShapeRequiresScalar(fact.index, fact.shape))
                elseif fact.requirement == B.BackShapeRequiresVector and shape_cls ~= B.BackShapeVec then
                    add_issue(issues, B.BackIssueShapeRequiresVector(fact.index, fact.shape))
                end
            end
        end

        local supported_shapes = target_supported_shapes(cmds)
        for index = 1, #cmds do
            local cmd = cmds[index]
            local cls = pvm.classof(cmd)
            if cls == B.CmdLoadInfo then
                validate_memory_info(issues, index, cmd.ty, cmd.memory, B.BackAccessRead)
                if supported_shapes ~= nil and not supported_shapes[shape_key(cmd.ty)] then add_issue(issues, B.BackIssueTargetUnsupportedShape(index, cmd.ty)) end
            elseif cls == B.CmdStoreInfo then
                validate_memory_info(issues, index, cmd.ty, cmd.memory, B.BackAccessWrite)
                if supported_shapes ~= nil and not supported_shapes[shape_key(cmd.ty)] then add_issue(issues, B.BackIssueTargetUnsupportedShape(index, cmd.ty)) end
            elseif cls == B.CmdAppendBlockParam then
                if supported_shapes ~= nil and not supported_shapes[shape_key(cmd.ty)] then add_issue(issues, B.BackIssueTargetUnsupportedShape(index, cmd.ty)) end
            elseif cls == B.CmdUnary or cls == B.CmdIntrinsic or cls == B.CmdCompare or cls == B.CmdSelect then
                if supported_shapes ~= nil and not supported_shapes[shape_key(cmd.ty)] then add_issue(issues, B.BackIssueTargetUnsupportedShape(index, cmd.ty)) end
            elseif cls == B.CmdVecBinary or cls == B.CmdVecCompare or cls == B.CmdVecSelect or cls == B.CmdVecMask or cls == B.CmdVecSplat then
                local shapev = B.BackShapeVec(cmd.ty)
                if supported_shapes ~= nil and not supported_shapes[shape_key(shapev)] then add_issue(issues, B.BackIssueTargetUnsupportedShape(index, shapev)) end
            elseif cls == B.CmdIntBinary then
                if not is_int_scalar(cmd.scalar) then add_issue(issues, B.BackIssueIntScalarExpected(index, cmd.scalar)) end
                if supported_shapes ~= nil and not supported_shapes[shape_key(B.BackShapeScalar(cmd.scalar))] then add_issue(issues, B.BackIssueTargetUnsupportedShape(index, B.BackShapeScalar(cmd.scalar))) end
            elseif cls == B.CmdFloatBinary or cls == B.CmdFma then
                if not is_float_scalar(cmd.ty or cmd.scalar) then add_issue(issues, B.BackIssueFloatScalarExpected(index, cmd.ty or cmd.scalar)) end
                local scalar = cmd.ty or cmd.scalar
                if supported_shapes ~= nil and not supported_shapes[shape_key(B.BackShapeScalar(scalar))] then add_issue(issues, B.BackIssueTargetUnsupportedShape(index, B.BackShapeScalar(scalar))) end
            elseif cls == B.CmdBitBinary or cls == B.CmdBitNot then
                if not is_bit_scalar(cmd.scalar) then add_issue(issues, B.BackIssueBitScalarExpected(index, cmd.scalar)) end
                if supported_shapes ~= nil and not supported_shapes[shape_key(B.BackShapeScalar(cmd.scalar))] then add_issue(issues, B.BackIssueTargetUnsupportedShape(index, B.BackShapeScalar(cmd.scalar))) end
            elseif cls == B.CmdShift or cls == B.CmdRotate then
                if not is_int_scalar(cmd.scalar) then add_issue(issues, B.BackIssueShiftScalarExpected(index, cmd.scalar)) end
                if supported_shapes ~= nil and not supported_shapes[shape_key(B.BackShapeScalar(cmd.scalar))] then add_issue(issues, B.BackIssueTargetUnsupportedShape(index, B.BackShapeScalar(cmd.scalar))) end
            end
        end

        if active_func ~= nil then
            add_issue(issues, B.BackIssueUnfinishedFunction(active_func))
        end
        if finalized_index == nil then
            add_issue(issues, B.BackIssueMissingFinalize)
        else
            for index = finalized_index + 1, #cmds do
                add_issue(issues, B.BackIssueCommandAfterFinalize(index))
            end
        end

        return B.BackValidationReport(issues)
    end

    local validate_program = pvm.phase("moonlift_back_validate_program", function(program)
        return validate_program_impl(program, true)
    end)

    return {
        cmd_facts = cmd_facts,
        cmd_facts_flat_into = function(program, out)
            for i = 1, #program.cmds do append_cmd_facts_flat(out, program.cmds[i], i) end
            return out
        end,
        validate_program = validate_program,
        validate_pvm_cold = function(program)
            return validate_program_impl(program, false)
        end,
        validate_lua_cold = function(program)
            return validate_program_impl(program, false)
        end,
        validate_lua = function(program)
            return validate_program_impl(program, false)
        end,
        validate_ll = function(program)
            return validate_program_impl(program, true)
        end,
        validate = function(program)
            return pvm.one(validate_program(program))
        end,

        validate_verify = function(program)
            local ref = validate_program_impl(program, false)
            local fast = validate_program_impl(program, true)
            local ref_n, fast_n = #ref.issues, #fast.issues
            if ref_n ~= fast_n then
                error(string.format(
                    "back_validate verify MISMATCH: issue count ref=%d fast=%d",
                    ref_n, fast_n
                ), 2)
            end
            for i = 1, ref_n do
                if ref.issues[i] ~= fast.issues[i] then
                    local ri, fi = ref.issues[i], fast.issues[i]
                    error(string.format(
                        "back_validate verify MISMATCH at issue %d: ref=%s fast=%s",
                        i, tostring(ri and ri.kind or ri), tostring(fi and fi.kind or fi)
                    ), 2)
                end
            end
            return ref
        end,
    }
end

return M