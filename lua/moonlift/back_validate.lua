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
    local B = T.Moon2Back

    local cmd_facts
    local call_target_facts
    local call_result_facts
    local binary_shape_requirement

    call_target_facts = pvm.phase("moon2_back_call_target_facts", {
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

    call_result_facts = pvm.phase("moon2_back_call_result_facts", {
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

    binary_shape_requirement = pvm.phase("moon2_back_binary_shape_requirement", {
        [B.BackIadd] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackIsub] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackImul] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackFadd] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackFsub] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackFmul] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackSdiv] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackUdiv] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackFdiv] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackSrem] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackUrem] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackBand] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackBor] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackBxor] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackIshl] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackUshr] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackSshr] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackRotl] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackRotr] = function() return pvm.once(B.BackShapeRequiresScalar) end,
        [B.BackVecIadd] = function() return pvm.once(B.BackShapeRequiresVector) end,
        [B.BackVecIsub] = function() return pvm.once(B.BackShapeRequiresVector) end,
        [B.BackVecImul] = function() return pvm.once(B.BackShapeRequiresVector) end,
        [B.BackVecBand] = function() return pvm.once(B.BackShapeRequiresVector) end,
        [B.BackVecBor] = function() return pvm.once(B.BackShapeRequiresVector) end,
        [B.BackVecBxor] = function() return pvm.once(B.BackShapeRequiresVector) end,
    })

    cmd_facts = pvm.phase("moon2_back_cmd_facts", {
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
        [B.CmdBinary] = function(self, index)
            return facts_triplet({ body(index), shape(index, self.ty, pvm.one(binary_shape_requirement(self.op))), B.BackFactValueUse(index, self.lhs), B.BackFactValueUse(index, self.rhs), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdCompare] = function(self, index)
            return facts_triplet({ body(index), shape(index, self.ty, B.BackShapeRequiresScalar), B.BackFactValueUse(index, self.lhs), B.BackFactValueUse(index, self.rhs), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdCast] = function(self, index)
            return facts_triplet({ body(index), B.BackFactValueUse(index, self.value), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdLoad] = function(self, index)
            return facts_triplet({ body(index), shape(index, self.ty, B.BackShapeAllowsScalarOrVector), B.BackFactValueUse(index, self.addr), B.BackFactValueDef(index, self.dst) })
        end,
        [B.CmdStore] = function(self, index)
            return facts_triplet({ body(index), shape(index, self.ty, B.BackShapeAllowsScalarOrVector), B.BackFactValueUse(index, self.addr), B.BackFactValueUse(index, self.value) })
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

    local validate_program = pvm.phase("moon2_back_validate_program", function(program)
        local issues = {}
        local cmds = program.cmds
        if #cmds == 0 then
            add_issue(issues, B.BackIssueEmptyProgram)
            add_issue(issues, B.BackIssueMissingFinalize)
            return B.BackValidationReport(issues)
        end

        local facts = {}
        for i = 1, #cmds do
            local g, p, c = cmd_facts(cmds[i], i)
            pvm.drain_into(g, p, c, facts)
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
                else
                    active_func = nil
                    seen_block = nil
                    seen_slot = nil
                    seen_value = nil
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
            elseif cls == B.BackFactShapeUse then
                local shape_cls = pvm.classof(fact.shape)
                if fact.requirement == B.BackShapeRequiresScalar and shape_cls ~= B.BackShapeScalar then
                    add_issue(issues, B.BackIssueShapeRequiresScalar(fact.index, fact.shape))
                elseif fact.requirement == B.BackShapeRequiresVector and shape_cls ~= B.BackShapeVec then
                    add_issue(issues, B.BackIssueShapeRequiresVector(fact.index, fact.shape))
                end
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
    end)

    return {
        cmd_facts = cmd_facts,
        validate_program = validate_program,
        validate = function(program)
            return pvm.one(validate_program(program))
        end,
    }
end

return M
