local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    local V = T.MoonVec
    local Back = T.MoonBack

    local elem_scalar
    local shape_to_back
    local shape_scalar
    local shape_vec
    local param_shape
    local scalar_bin_cmd
    local vector_bin_op
    local cmd_to_back
    local terminator_to_back
    local block_to_back
    local func_to_back
    local program_to_back

    local function value_id(id) return Back.BackValId(id.text) end
    local function block_id(id) return Back.BackBlockId(id.text) end

    local function append_all(out, xs)
        for i = 1, #xs do out[#out + 1] = xs[i] end
    end

    local function env_empty()
        return V.VecBackEnv({})
    end

    local function env_add(env, id, shape)
        local values = {}
        for i = 1, #env.values do values[#values + 1] = env.values[i] end
        values[#values + 1] = V.VecBackValueShape(id, shape)
        return V.VecBackEnv(values)
    end

    local function env_lookup(env, id)
        for i = #env.values, 1, -1 do
            if env.values[i].id == id then return env.values[i].shape end
        end
        return nil
    end

    local function reject(env, id, reason)
        return V.VecBackReject(env, V.VecRejectUnsupportedExpr(id and V.VecExprId(id.text) or V.VecExprId("vec.back"), reason))
    end

    local function cmds(env, xs)
        return V.VecBackCmds(env, xs)
    end

    elem_scalar = pvm.phase("moonlift_vec_elem_to_back_scalar", {
        [V.VecElemBool] = function() return pvm.once(Back.BackBool) end,
        [V.VecElemI8] = function() return pvm.once(Back.BackI8) end,
        [V.VecElemI16] = function() return pvm.once(Back.BackI16) end,
        [V.VecElemI32] = function() return pvm.once(Back.BackI32) end,
        [V.VecElemI64] = function() return pvm.once(Back.BackI64) end,
        [V.VecElemU8] = function() return pvm.once(Back.BackU8) end,
        [V.VecElemU16] = function() return pvm.once(Back.BackU16) end,
        [V.VecElemU32] = function() return pvm.once(Back.BackU32) end,
        [V.VecElemU64] = function() return pvm.once(Back.BackU64) end,
        [V.VecElemF32] = function() return pvm.once(Back.BackF32) end,
        [V.VecElemF64] = function() return pvm.once(Back.BackF64) end,
        [V.VecElemPtr] = function() return pvm.once(Back.BackPtr) end,
        [V.VecElemIndex] = function() return pvm.once(Back.BackIndex) end,
    })

    shape_to_back = pvm.phase("moonlift_vec_shape_to_back_shape", {
        [V.VecScalarShape] = function(self) return pvm.once(Back.BackShapeScalar(pvm.one(elem_scalar(self.elem)))) end,
        [V.VecVectorShape] = function(self) return pvm.once(Back.BackShapeVec(Back.BackVec(pvm.one(elem_scalar(self.elem)), self.lanes))) end,
    })

    shape_scalar = pvm.phase("moonlift_vec_shape_scalar", {
        [V.VecScalarShape] = function(self) return pvm.once(pvm.one(elem_scalar(self.elem))) end,
        [V.VecVectorShape] = function() return pvm.empty() end,
    })

    shape_vec = pvm.phase("moonlift_vec_shape_vec", {
        [V.VecVectorShape] = function(self) return pvm.once(Back.BackVec(pvm.one(elem_scalar(self.elem)), self.lanes)) end,
        [V.VecScalarShape] = function() return pvm.empty() end,
    })

    param_shape = pvm.phase("moonlift_vec_param_shape", {
        [V.VecScalarParam] = function(self) return pvm.once(V.VecScalarShape(self.elem)) end,
        [V.VecVectorParam] = function(self) return pvm.once(V.VecVectorShape(self.elem, self.lanes)) end,
    })


    vector_bin_op = pvm.phase("moonlift_vec_vector_bin_to_back", {
        [V.VecAdd] = function() return pvm.once(Back.BackVecIntAdd) end,
        [V.VecSub] = function() return pvm.once(Back.BackVecIntSub) end,
        [V.VecMul] = function() return pvm.once(Back.BackVecIntMul) end,
        [V.VecBitAnd] = function() return pvm.once(Back.BackVecBitAnd) end,
        [V.VecBitOr] = function() return pvm.once(Back.BackVecBitOr) end,
        [V.VecBitXor] = function() return pvm.once(Back.BackVecBitXor) end,
        [V.VecRem] = function() return pvm.empty() end,
        [V.VecShl] = function() return pvm.empty() end,
        [V.VecLShr] = function() return pvm.empty() end,
        [V.VecAShr] = function() return pvm.empty() end,
        [V.VecEq] = function() return pvm.empty() end,
        [V.VecNe] = function() return pvm.empty() end,
        [V.VecLt] = function() return pvm.empty() end,
        [V.VecLe] = function() return pvm.empty() end,
        [V.VecGt] = function() return pvm.empty() end,
        [V.VecGe] = function() return pvm.empty() end,
    })

    local function result_with_shape(env, id, shape, cmd)
        return cmds(env_add(env, id, shape), { cmd })
    end

    local function int_sem_wrap()
        return Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose)
    end

    scalar_bin_cmd = pvm.phase("moonlift_vec_scalar_bin_to_back_cmd", {
        [V.VecAdd] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdIntBinary(dst, Back.BackIntAdd, scalar, int_sem_wrap(), lhs, rhs)) end,
        [V.VecSub] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdIntBinary(dst, Back.BackIntSub, scalar, int_sem_wrap(), lhs, rhs)) end,
        [V.VecMul] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdIntBinary(dst, Back.BackIntMul, scalar, int_sem_wrap(), lhs, rhs)) end,
        [V.VecRem] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdIntBinary(dst, Back.BackIntSRem, scalar, int_sem_wrap(), lhs, rhs)) end,
        [V.VecBitAnd] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdBitBinary(dst, Back.BackBitAnd, scalar, lhs, rhs)) end,
        [V.VecBitOr] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdBitBinary(dst, Back.BackBitOr, scalar, lhs, rhs)) end,
        [V.VecBitXor] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdBitBinary(dst, Back.BackBitXor, scalar, lhs, rhs)) end,
        [V.VecShl] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdShift(dst, Back.BackShiftLeft, scalar, lhs, rhs)) end,
        [V.VecLShr] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdShift(dst, Back.BackShiftLogicalRight, scalar, lhs, rhs)) end,
        [V.VecAShr] = function(_, dst, scalar, lhs, rhs) return pvm.once(Back.CmdShift(dst, Back.BackShiftArithmeticRight, scalar, lhs, rhs)) end,
        [V.VecEq] = function() return pvm.empty() end,
        [V.VecNe] = function() return pvm.empty() end,
        [V.VecLt] = function() return pvm.empty() end,
        [V.VecLe] = function() return pvm.empty() end,
        [V.VecGt] = function() return pvm.empty() end,
        [V.VecGe] = function() return pvm.empty() end,
    })

    local function elem_size(elem)
        if elem == V.VecElemBool or elem == V.VecElemI8 or elem == V.VecElemU8 then return 1 end
        if elem == V.VecElemI16 or elem == V.VecElemU16 then return 2 end
        if elem == V.VecElemI32 or elem == V.VecElemU32 or elem == V.VecElemF32 then return 4 end
        if elem == V.VecElemI64 or elem == V.VecElemU64 or elem == V.VecElemF64 then return 8 end
        if elem == V.VecElemPtr or elem == V.VecElemIndex then return 8 end
        return nil
    end

    local function shape_bytes(shape)
        if pvm.classof(shape) == V.VecScalarShape then return elem_size(shape.elem) end
        if pvm.classof(shape) == V.VecVectorShape then local size = elem_size(shape.elem); return size and (size * shape.lanes) or nil end
        return nil
    end

    local function alignment_from_vec(access)
        local cls = pvm.classof(access.alignment)
        if cls == V.VecAlignmentKnown then return Back.BackAlignKnown(access.alignment.bytes) end
        if cls == V.VecAlignmentAssumed then return Back.BackAlignAssumed(access.alignment.bytes, "vec alignment proof") end
        return Back.BackAlignUnknown
    end

    local function dereference_from_vec(access, shape)
        local bytes = shape_bytes(shape)
        if bytes == nil then return Back.BackDerefUnknown end
        local cls = pvm.classof(access.bounds)
        if cls == V.VecBoundsProven then return Back.BackDerefBytes(bytes, "vec bounds proof") end
        return Back.BackDerefUnknown
    end

    local function trap_from_vec(access)
        if pvm.classof(access.bounds) == V.VecBoundsProven then return Back.BackNonTrapping("vec bounds proof") end
        return Back.BackMayTrap
    end

    local function memory_info_from_access(access, shape, mode)
        return Back.BackMemoryInfo(Back.BackAccessId(access.id.text), alignment_from_vec(access), dereference_from_vec(access, shape), trap_from_vec(access), Back.BackMayNotMove, mode)
    end

    local function address(base, off)
        return Back.BackAddress(Back.BackAddrValue(base), off, Back.BackProvUnknown, Back.BackPtrBoundsUnknown)
    end

    cmd_to_back = pvm.phase("moonlift_vec_cmd_to_back", {
        [V.VecCmdConstInt] = function(self, env)
            local scalar = pvm.one(elem_scalar(self.elem))
            return pvm.once(result_with_shape(env, self.dst, V.VecScalarShape(self.elem), Back.CmdConst(value_id(self.dst), scalar, Back.BackLitInt(self.raw))))
        end,
        [V.VecCmdSplat] = function(self, env)
            local vec = pvm.drain(shape_vec(self.shape))[1]
            if vec == nil then return pvm.once(reject(env, self.dst, "splat requires vector shape")) end
            return pvm.once(result_with_shape(env, self.dst, self.shape, Back.CmdVecSplat(value_id(self.dst), vec, value_id(self.scalar))))
        end,
        [V.VecCmdBin] = function(self, env)
            local shape_cls = pvm.classof(self.shape)
            local op = nil
            if shape_cls == V.VecScalarShape then
                local scalar = pvm.drain(shape_scalar(self.shape))[1]
                local cmd = scalar ~= nil and pvm.drain(scalar_bin_cmd(self.op, value_id(self.dst), scalar, value_id(self.lhs), value_id(self.rhs)))[1] or nil
                if cmd == nil then return pvm.once(reject(env, self.dst, "unsupported scalar vector binary op/shape")) end
                return pvm.once(result_with_shape(env, self.dst, self.shape, cmd))
            else
                op = pvm.drain(vector_bin_op(self.op))[1]
                local vec = pvm.drain(shape_vec(self.shape))[1]
                if op == nil or vec == nil then return pvm.once(reject(env, self.dst, "unsupported vector binary op/shape")) end
                return pvm.once(result_with_shape(env, self.dst, self.shape, Back.CmdVecBinary(value_id(self.dst), op, vec, value_id(self.lhs), value_id(self.rhs))))
            end
        end,
        [V.VecCmdIreduce] = function(self, env)
            local scalar = pvm.one(elem_scalar(self.narrow_elem))
            return pvm.once(result_with_shape(env, self.dst, V.VecScalarShape(self.narrow_elem), Back.CmdCast(value_id(self.dst), Back.BackIreduce, scalar, value_id(self.value))))
        end,
        [V.VecCmdUextend] = function(self, env)
            local scalar = pvm.one(elem_scalar(self.wide_elem))
            return pvm.once(result_with_shape(env, self.dst, V.VecScalarShape(self.wide_elem), Back.CmdCast(value_id(self.dst), Back.BackUextend, scalar, value_id(self.value))))
        end,
        [V.VecCmdExtractLane] = function(self, env)
            local shape = env_lookup(env, self.vec)
            if shape == nil or pvm.classof(shape) ~= V.VecVectorShape then return pvm.once(reject(env, self.dst, "extract lane requires known vector value")) end
            local scalar = pvm.one(elem_scalar(shape.elem))
            return pvm.once(result_with_shape(env, self.dst, V.VecScalarShape(shape.elem), Back.CmdVecExtractLane(value_id(self.dst), scalar, value_id(self.vec), self.lane)))
        end,
        [V.VecCmdLoad] = function(self, env)
            if self.access.access_kind ~= V.VecAccessLoad then return pvm.once(reject(env, self.dst, "load command requires load memory fact")) end
            local zero = Back.BackValId("vec.load.zero:" .. self.dst.text)
            return pvm.once(cmds(env_add(env, self.dst, self.shape), {
                Back.CmdConst(zero, Back.BackIndex, Back.BackLitInt("0")),
                Back.CmdLoadInfo(value_id(self.dst), pvm.one(shape_to_back(self.shape)), address(value_id(self.addr), zero), memory_info_from_access(self.access, self.shape, Back.BackAccessRead)),
            }))
        end,
        [V.VecCmdStore] = function(self, env)
            if self.access.access_kind ~= V.VecAccessStore then return pvm.once(reject(env, nil, "store command requires store memory fact")) end
            local zero = Back.BackValId("vec.store.zero:" .. self.addr.text)
            return pvm.once(cmds(env, {
                Back.CmdConst(zero, Back.BackIndex, Back.BackLitInt("0")),
                Back.CmdStoreInfo(pvm.one(shape_to_back(self.shape)), address(value_id(self.addr), zero), value_id(self.value), memory_info_from_access(self.access, self.shape, Back.BackAccessWrite)),
            }))
        end,
        [V.VecCmdSelect] = function(self, env)
            if pvm.classof(self.shape) ~= V.VecScalarShape then return pvm.once(reject(env, self.dst, "vector select lowering deferred")) end
            return pvm.once(result_with_shape(env, self.dst, self.shape, Back.CmdSelect(value_id(self.dst), pvm.one(shape_to_back(self.shape)), value_id(self.cond), value_id(self.then_value), value_id(self.else_value))))
        end,
        [V.VecCmdRamp] = function(self, env) return pvm.once(reject(env, self.dst, "ramp lowering deferred")) end,
        [V.VecCmdHorizontalReduce] = function(self, env) return pvm.once(reject(env, self.dst, "horizontal reduce lowering deferred")) end,
    }, { args_cache = "last" })

    terminator_to_back = pvm.phase("moonlift_vec_terminator_to_back", {
        [V.VecJump] = function(self) local args = {}; for i = 1, #self.args do args[#args + 1] = value_id(self.args[i]) end; return pvm.once({ Back.CmdJump(block_id(self.dest), args) }) end,
        [V.VecBrIf] = function(self) local ta = {}; for i = 1, #self.then_args do ta[#ta + 1] = value_id(self.then_args[i]) end; local ea = {}; for i = 1, #self.else_args do ea[#ea + 1] = value_id(self.else_args[i]) end; return pvm.once({ Back.CmdBrIf(value_id(self.cond), block_id(self.then_block), ta, block_id(self.else_block), ea) }) end,
        [V.VecReturnVoid] = function() return pvm.once({ Back.CmdReturnVoid }) end,
        [V.VecReturnValue] = function(self) return pvm.once({ Back.CmdReturnValue(value_id(self.value)) }) end,
    })

    block_to_back = pvm.phase("moonlift_vec_block_to_back", {
        [V.VecBlock] = function(block, env)
            local current = env
            local out = { Back.CmdCreateBlock(block_id(block.id)) }
            for i = 1, #block.params do
                local shape = pvm.one(param_shape(block.params[i]))
                current = env_add(current, block.params[i].id, shape)
                out[#out + 1] = Back.CmdAppendBlockParam(block_id(block.id), value_id(block.params[i].id), pvm.one(shape_to_back(shape)))
            end
            out[#out + 1] = Back.CmdSwitchToBlock(block_id(block.id))
            for i = 1, #block.cmds do
                local lowered = pvm.one(cmd_to_back(block.cmds[i], current))
                if pvm.classof(lowered) == V.VecBackReject then return pvm.once(lowered) end
                current = lowered.env
                append_all(out, lowered.cmds)
            end
            append_all(out, pvm.one(terminator_to_back(block.terminator)))
            out[#out + 1] = Back.CmdSealBlock(block_id(block.id))
            return pvm.once(cmds(current, out))
        end,
    }, { args_cache = "last" })

    local function sig_scalars(params, results)
        local ps = {}
        for i = 1, #params do
            local shape = pvm.one(param_shape(params[i]))
            local scalar = pvm.drain(shape_scalar(shape))[1]
            if scalar == nil then return nil, nil end
            ps[#ps + 1] = scalar
        end
        local rs = {}
        for i = 1, #results do
            local scalar = pvm.drain(shape_scalar(results[i]))[1]
            if scalar == nil then return nil, nil end
            rs[#rs + 1] = scalar
        end
        return ps, rs
    end

    func_to_back = pvm.phase("moonlift_vec_func_to_back", {
        [V.VecBackFuncSpec] = function(func)
            local ps, rs = sig_scalars(func.params, func.results)
            if ps == nil then return pvm.once(V.VecBackReject(env_empty(), V.VecRejectUnsupportedLoop(V.VecLoopId(func.name), "function ABI only supports scalar params/results"))) end
            local sig = Back.BackSigId("sig:" .. func.name)
            local fid = Back.BackFuncId(func.name)
            local env = env_empty()
            local out = { Back.CmdCreateSig(sig, ps, rs), Back.CmdDeclareFunc(func.visibility, fid, sig), Back.CmdBeginFunc(fid) }
            if #func.blocks == 0 then
                out[#out + 1] = Back.CmdTrap
            else
                local entry = func.blocks[1]
                local entry_values = {}
                for i = 1, #func.params do
                    local shape = pvm.one(param_shape(func.params[i]))
                    env = env_add(env, func.params[i].id, shape)
                    entry_values[#entry_values + 1] = value_id(func.params[i].id)
                end
                out[#out + 1] = Back.CmdCreateBlock(block_id(entry.id))
                out[#out + 1] = Back.CmdSwitchToBlock(block_id(entry.id))
                out[#out + 1] = Back.CmdBindEntryParams(block_id(entry.id), entry_values)
                for i = 1, #entry.cmds do
                    local lowered = pvm.one(cmd_to_back(entry.cmds[i], env))
                    if pvm.classof(lowered) == V.VecBackReject then return pvm.once(lowered) end
                    env = lowered.env
                    append_all(out, lowered.cmds)
                end
                append_all(out, pvm.one(terminator_to_back(entry.terminator)))
                out[#out + 1] = Back.CmdSealBlock(block_id(entry.id))
                for i = 2, #func.blocks do
                    local lowered = pvm.one(block_to_back(func.blocks[i], env))
                    if pvm.classof(lowered) == V.VecBackReject then return pvm.once(lowered) end
                    append_all(out, lowered.cmds)
                    env = lowered.env
                end
            end
            out[#out + 1] = Back.CmdFinishFunc(fid)
            return pvm.once(cmds(env, out))
        end,
    })

    program_to_back = pvm.phase("moonlift_vec_program_to_back", {
        [V.VecBackProgramSpec] = function(program)
            local out = {}
            local env = env_empty()
            for i = 1, #program.funcs do
                local lowered = pvm.one(func_to_back(program.funcs[i]))
                if pvm.classof(lowered) == V.VecBackReject then return pvm.once(lowered) end
                append_all(out, lowered.cmds)
                env = lowered.env
            end
            out[#out + 1] = Back.CmdFinalizeModule
            return pvm.once(Back.BackProgram(out))
        end,
    })

    return {
        env_empty = env_empty,
        elem_scalar = elem_scalar,
        shape_to_back = shape_to_back,
        cmd_to_back = cmd_to_back,
        block_to_back = block_to_back,
        func_to_back = func_to_back,
        program_to_back = program_to_back,
        program = function(program)
            local lowered = pvm.one(program_to_back(program))
            if pvm.classof(lowered) == V.VecBackReject then return lowered end
            return lowered
        end,
    }
end

return M
