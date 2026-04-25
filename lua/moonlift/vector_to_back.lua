local pvm = require("pvm")

local M = {}

function M.Define(T)
    local Sem = T.MoonliftSem
    local Vec = T.MoonliftVec
    local Back = T.MoonliftBack

    local lower_decision
    local lower_func
    local lower_module

    local function is_class(node, cls)
        return pvm.classof(node) == cls
    end

    local function scalar_of_sem_ty(ty)
        if ty == Sem.SemTIndex then return Back.BackIndex end
        if ty == Sem.SemTI64 then return Back.BackI64 end
        if ty == Sem.SemTU64 then return Back.BackU64 end
        if ty == Sem.SemTI32 then return Back.BackI32 end
        if ty == Sem.SemTU32 then return Back.BackU32 end
        if ty == Sem.SemTRawPtr then return Back.BackPtr end
        if pvm.classof(ty) == Sem.SemTPtrTo then return Back.BackPtr end
        error("vector_to_back: unsupported scalar type " .. tostring(ty))
    end

    local function op_cmd(op, dst, ty, lhs, rhs, vec)
        if vec then
            if op == Vec.VecAdd then return Back.BackCmdVecIadd(dst, ty, lhs, rhs) end
            if op == Vec.VecMul then return Back.BackCmdVecImul(dst, ty, lhs, rhs) end
            if op == Vec.VecBitAnd then return Back.BackCmdVecBand(dst, ty, lhs, rhs) end
        else
            if op == Vec.VecAdd then return Back.BackCmdIadd(dst, ty, lhs, rhs) end
            if op == Vec.VecSub then return Back.BackCmdIsub(dst, ty, lhs, rhs) end
            if op == Vec.VecMul then return Back.BackCmdImul(dst, ty, lhs, rhs) end
            if op == Vec.VecBitAnd then return Back.BackCmdBand(dst, ty, lhs, rhs) end
            if op == Vec.VecBitOr then return Back.BackCmdBor(dst, ty, lhs, rhs) end
            if op == Vec.VecBitXor then return Back.BackCmdBxor(dst, ty, lhs, rhs) end
            if op == Vec.VecShl then return Back.BackCmdIshl(dst, ty, lhs, rhs) end
            if op == Vec.VecLShr then return Back.BackCmdUshr(dst, ty, lhs, rhs) end
            if op == Vec.VecAShr then return Back.BackCmdSshr(dst, ty, lhs, rhs) end
        end
        error("vector_to_back: unsupported " .. (vec and "vector" or "scalar") .. " op " .. tostring(op))
    end

    local function append_all(dst, src)
        for i = 1, #src do dst[#dst + 1] = src[i] end
    end

    local function scalar_of_vec_elem(elem)
        if elem == Vec.VecElemBool then return Back.BackBool end
        if elem == Vec.VecElemI8 then return Back.BackI8 end
        if elem == Vec.VecElemI16 then return Back.BackI16 end
        if elem == Vec.VecElemI32 then return Back.BackI32 end
        if elem == Vec.VecElemI64 then return Back.BackI64 end
        if elem == Vec.VecElemU8 then return Back.BackU8 end
        if elem == Vec.VecElemU16 then return Back.BackU16 end
        if elem == Vec.VecElemU32 then return Back.BackU32 end
        if elem == Vec.VecElemU64 then return Back.BackU64 end
        if elem == Vec.VecElemF32 then return Back.BackF32 end
        if elem == Vec.VecElemF64 then return Back.BackF64 end
        if elem == Vec.VecElemPtr then return Back.BackPtr end
        if elem == Vec.VecElemIndex then return Back.BackIndex end
        error("vector_to_back: unsupported VecElem " .. tostring(elem))
    end

    local function vec_shape_to_back(shape)
        if is_class(shape, Vec.VecVectorShape) then
            return Back.BackVec(scalar_of_vec_elem(shape.elem), shape.lanes)
        end
        return scalar_of_vec_elem(shape.elem)
    end

    local function vec_value_id(id)
        return Back.BackValId(id.text)
    end

    local function vec_block_id(id)
        return Back.BackBlockId(id.text)
    end

    local function lower_scalar_bin_cmd(op, dst, ty, lhs, rhs)
        if op == Vec.VecAdd then return Back.BackCmdIadd(dst, ty, lhs, rhs) end
        if op == Vec.VecSub then return Back.BackCmdIsub(dst, ty, lhs, rhs) end
        if op == Vec.VecMul then return Back.BackCmdImul(dst, ty, lhs, rhs) end
        if op == Vec.VecRem then return Back.BackCmdUrem(dst, ty, lhs, rhs) end
        if op == Vec.VecBitAnd then return Back.BackCmdBand(dst, ty, lhs, rhs) end
        if op == Vec.VecBitOr then return Back.BackCmdBor(dst, ty, lhs, rhs) end
        if op == Vec.VecBitXor then return Back.BackCmdBxor(dst, ty, lhs, rhs) end
        if op == Vec.VecShl then return Back.BackCmdIshl(dst, ty, lhs, rhs) end
        if op == Vec.VecLShr then return Back.BackCmdUshr(dst, ty, lhs, rhs) end
        if op == Vec.VecAShr then return Back.BackCmdSshr(dst, ty, lhs, rhs) end
        if op == Vec.VecEq then return Back.BackCmdIcmpEq(dst, ty, lhs, rhs) end
        if op == Vec.VecNe then return Back.BackCmdIcmpNe(dst, ty, lhs, rhs) end
        if op == Vec.VecLt then return Back.BackCmdUIcmpLt(dst, ty, lhs, rhs) end
        if op == Vec.VecLe then return Back.BackCmdUIcmpLe(dst, ty, lhs, rhs) end
        if op == Vec.VecGt then return Back.BackCmdUIcmpGt(dst, ty, lhs, rhs) end
        if op == Vec.VecGe then return Back.BackCmdUIcmpGe(dst, ty, lhs, rhs) end
        error("vector_to_back: unsupported scalar VecBinOp " .. tostring(op))
    end

    local function lower_vector_bin_cmd(op, dst, ty, lhs, rhs)
        if op == Vec.VecAdd then return Back.BackCmdVecIadd(dst, ty, lhs, rhs) end
        if op == Vec.VecMul then return Back.BackCmdVecImul(dst, ty, lhs, rhs) end
        if op == Vec.VecBitAnd then return Back.BackCmdVecBand(dst, ty, lhs, rhs) end
        error("vector_to_back: unsupported vector VecBinOp " .. tostring(op))
    end

    local function make_id(prefix, n)
        return Back.BackValId(prefix .. "." .. n)
    end

    local function lower_scalar_invariant(expr, scalar_ty, cmds, id)
        if is_class(expr, Sem.SemExprConstInt) then
            cmds[#cmds + 1] = Back.BackCmdConstInt(id, scalar_ty, expr.raw)
            return id
        end
        if is_class(expr, Sem.SemExprBinding) and is_class(expr.binding, Sem.SemBindArg) then
            return Back.BackValId("arg:" .. expr.binding.index .. ":" .. expr.binding.name)
        end
        error("vector_to_back: unsupported invariant expr " .. tostring(expr))
    end

    local function build_offset_vector(cmds, vec_ty, scalar_ty, path, lanes, first_lane)
        local first = Back.BackValId(path .. ".offset.c0")
        local v = Back.BackValId(path .. ".offset.v0")
        cmds[#cmds + 1] = Back.BackCmdConstInt(first, scalar_ty, tostring(first_lane))
        cmds[#cmds + 1] = Back.BackCmdVecSplat(v, vec_ty, first)
        for lane = 1, lanes - 1 do
            local c = Back.BackValId(path .. ".offset.c" .. lane)
            local next_v = Back.BackValId(path .. ".offset.v" .. lane)
            cmds[#cmds + 1] = Back.BackCmdConstInt(c, scalar_ty, tostring(first_lane + lane))
            cmds[#cmds + 1] = Back.BackCmdVecInsertLane(next_v, vec_ty, v, c, lane)
            v = next_v
        end
        return v
    end

    local function invariant_key(fact)
        return fact.id.text .. ":" .. tostring(fact.ty)
    end

    local function lower_vec_invariant(fact, env)
        local key = invariant_key(fact)
        local cached = env.invariant_vecs[key]
        if cached ~= nil then return cached end
        local scalar = make_id(env.path .. ".hoist.scalar", env.next_id())
        local init_vec = make_id(env.path .. ".hoist.vec", env.next_id())
        lower_scalar_invariant(fact.expr, env.scalar_ty, env.pre_cmds, scalar)
        env.pre_cmds[#env.pre_cmds + 1] = Back.BackCmdVecSplat(init_vec, env.vec_ty, scalar)
        local body_vec = env.add_loop_vec_const(init_vec, "invariant")
        env.invariant_vecs[key] = body_vec
        return body_vec
    end

    local function expr_fact(env, id_or_fact)
        local cls = pvm.classof(id_or_fact)
        if cls == Vec.VecExprId then
            local fact = env.exprs[id_or_fact]
            if fact == nil then
                error("vector_to_back: missing vector expr fact for " .. id_or_fact.text)
            end
            return fact
        end
        return id_or_fact
    end

    local function lower_vec_expr(id_or_fact, env)
        local fact = expr_fact(env, id_or_fact)
        local cmds = {}
        local cls = pvm.classof(fact)
        if cls == Vec.VecExprLaneIndex then
            local splat = make_id(env.path, env.next_id())
            local ramp = make_id(env.path, env.next_id())
            cmds[#cmds + 1] = Back.BackCmdVecSplat(splat, env.vec_ty, env.index_value)
            cmds[#cmds + 1] = Back.BackCmdVecIadd(ramp, env.vec_ty, splat, env.offset_vec)
            return cmds, ramp
        elseif cls == Vec.VecExprInvariant or cls == Vec.VecExprConst then
            return cmds, lower_vec_invariant(fact, env)
        elseif cls == Vec.VecExprLocal then
            return lower_vec_expr(fact.value, env)
        elseif cls == Vec.VecExprBin then
            local lhs_cmds, lhs = lower_vec_expr(fact.lhs, env)
            local rhs_cmds, rhs = lower_vec_expr(fact.rhs, env)
            append_all(cmds, lhs_cmds)
            append_all(cmds, rhs_cmds)
            local dst = make_id(env.path, env.next_id())
            cmds[#cmds + 1] = op_cmd(fact.op, dst, env.vec_ty, lhs, rhs, true)
            return cmds, dst
        end
        error("vector_to_back: unsupported vector expr fact " .. tostring(fact))
    end

    local function lower_tail_scalar_expr(id_or_fact, env)
        local fact = expr_fact(env, id_or_fact)
        local cmds = {}
        local cls = pvm.classof(fact)
        if cls == Vec.VecExprLaneIndex then
            return cmds, env.index_value
        elseif cls == Vec.VecExprInvariant or cls == Vec.VecExprConst then
            local scalar = make_id(env.path, env.next_id())
            lower_scalar_invariant(fact.expr, env.scalar_ty, cmds, scalar)
            return cmds, scalar
        elseif cls == Vec.VecExprLocal then
            return lower_tail_scalar_expr(fact.value, env)
        elseif cls == Vec.VecExprBin then
            local lhs_cmds, lhs = lower_tail_scalar_expr(fact.lhs, env)
            local rhs_cmds, rhs = lower_tail_scalar_expr(fact.rhs, env)
            append_all(cmds, lhs_cmds)
            append_all(cmds, rhs_cmds)
            local dst = make_id(env.path, env.next_id())
            cmds[#cmds + 1] = op_cmd(fact.op, dst, env.scalar_ty, lhs, rhs, false)
            return cmds, dst
        end
        error("vector_to_back: unsupported scalar tail expr fact " .. tostring(fact))
    end

    local function stop_arg(plan)
        if is_class(plan.stop, Sem.SemExprBinding) and is_class(plan.stop.binding, Sem.SemBindArg) then
            return plan.stop.binding
        end
        error("vector_to_back: initial vector plan lowering requires stop to be a function argument binding")
    end

    local function lower_add_reduction_plan(self, func_name, unroll)
        unroll = unroll or 1
        if unroll < 1 then error("vector_to_back: unroll must be >= 1") end
        local stop_binding = stop_arg(self)
        local scalar_ty = scalar_of_sem_ty(self.carry.ty)
        local vec_ty = Back.BackVec(scalar_ty, self.lanes)
        local stride = self.lanes * unroll
        local func = Back.BackFuncId(func_name)
        local sig = Back.BackSigId("sig:" .. func_name)
        local entry = Back.BackBlockId(func_name .. ":entry")
        local header = Back.BackBlockId(func_name .. ":vec.header")
        local body = Back.BackBlockId(func_name .. ":vec.body")
        local vec_exit = Back.BackBlockId(func_name .. ":vec.exit")
        local tail_header = Back.BackBlockId(func_name .. ":tail.header")
        local tail_body = Back.BackBlockId(func_name .. ":tail.body")
        local exit = Back.BackBlockId(func_name .. ":exit")
        local n_arg = Back.BackValId("arg:" .. stop_binding.index .. ":" .. stop_binding.name)
        local start_id = Back.BackValId("init.i")
        local acc0 = Back.BackValId("init.acc")
        local count = Back.BackValId("main.count")
        local stride_id = Back.BackValId("const.stride")
        local rem = Back.BackValId("main.rem")
        local main_count = Back.BackValId("main.count.aligned")
        local main_stop = Back.BackValId("main.stop")
        local h_i = Back.BackValId("vec.header.i")
        local b_i = Back.BackValId("vec.body.i")
        local ve_acc = {}
        local h_acc = {}
        local b_acc = {}
        local next_acc = {}
        local init_acc = {}
        local result = Back.BackValId("result")
        local t_i = Back.BackValId("tail.header.i")
        local t_acc = Back.BackValId("tail.header.acc")
        local tb_i = Back.BackValId("tail.body.i")
        local tb_acc = Back.BackValId("tail.body.acc")
        for u = 1, unroll do
            h_acc[u] = Back.BackValId("vec.header.acc" .. u)
            b_acc[u] = Back.BackValId("vec.body.acc" .. u)
            ve_acc[u] = Back.BackValId("vec.exit.acc" .. u)
            next_acc[u] = Back.BackValId("vec.next.acc" .. u)
            init_acc[u] = Back.BackValId("init.vacc" .. u)
        end
        local pre_cmds = {}
        local loop_consts = {}
        local function add_loop_vec_const(init, label)
            local idx = #loop_consts + 1
            local h = Back.BackValId("vec.header.const" .. idx .. "." .. label)
            local b = Back.BackValId("vec.body.const" .. idx .. "." .. label)
            loop_consts[idx] = { init = init, header = h, body = b }
            return b
        end
        local offsets = {}
        for u = 1, unroll do
            local init_offset = build_offset_vector(pre_cmds, vec_ty, scalar_ty, func_name .. ".offset" .. u, self.lanes, (u - 1) * self.lanes)
            offsets[u] = add_loop_vec_const(init_offset, "offset" .. u)
        end

        local counter = 0
        local shared_env = {
            path = func_name .. ".vec",
            lanes = self.lanes,
            scalar_ty = scalar_ty,
            vec_ty = vec_ty,
            pre_cmds = pre_cmds,
            invariant_vecs = {},
            exprs = self.exprs,
            add_loop_vec_const = add_loop_vec_const,
            next_id = function()
                counter = counter + 1
                return counter
            end,
        }
        local group_expr_cmds = {}
        local group_values = {}
        for u = 1, unroll do
            shared_env.index_value = b_i
            shared_env.offset_vec = offsets[u]
            local expr_cmds, vec_value = lower_vec_expr(self.value, shared_env)
            group_expr_cmds[u] = expr_cmds
            group_values[u] = vec_value
        end

        local cmds = {
            Back.BackCmdCreateSig(sig, { scalar_ty }, { scalar_ty }),
            Back.BackCmdDeclareFuncExport(func, sig),
            Back.BackCmdBeginFunc(func),
            Back.BackCmdCreateBlock(entry),
            Back.BackCmdSwitchToBlock(entry),
            Back.BackCmdBindEntryParams(entry, { n_arg }),
            Back.BackCmdCreateBlock(header),
            Back.BackCmdCreateBlock(body),
            Back.BackCmdCreateBlock(vec_exit),
            Back.BackCmdCreateBlock(tail_header),
            Back.BackCmdCreateBlock(tail_body),
            Back.BackCmdCreateBlock(exit),
            Back.BackCmdAppendBlockParam(header, h_i, scalar_ty),
            Back.BackCmdAppendBlockParam(body, b_i, scalar_ty),
        }
        for u = 1, unroll do
            cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(header, h_acc[u], vec_ty)
        end
        for i = 1, #loop_consts do
            cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(header, loop_consts[i].header, vec_ty)
        end
        for u = 1, unroll do
            cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(body, b_acc[u], vec_ty)
        end
        for i = 1, #loop_consts do
            cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(body, loop_consts[i].body, vec_ty)
        end
        for u = 1, unroll do
            cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(vec_exit, ve_acc[u], vec_ty)
        end
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(tail_header, t_i, scalar_ty)
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(tail_header, t_acc, scalar_ty)
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(tail_body, tb_i, scalar_ty)
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(tail_body, tb_acc, scalar_ty)
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit, result, scalar_ty)
        lower_scalar_invariant(self.start, scalar_ty, cmds, start_id)
        lower_scalar_invariant(self.carry.init, scalar_ty, cmds, acc0)
        cmds[#cmds + 1] = Back.BackCmdConstInt(stride_id, scalar_ty, tostring(stride))
        cmds[#cmds + 1] = Back.BackCmdIsub(count, scalar_ty, n_arg, start_id)
        cmds[#cmds + 1] = Back.BackCmdUrem(rem, scalar_ty, count, stride_id)
        cmds[#cmds + 1] = Back.BackCmdIsub(main_count, scalar_ty, count, rem)
        cmds[#cmds + 1] = Back.BackCmdIadd(main_stop, scalar_ty, start_id, main_count)
        for u = 1, unroll do
            cmds[#cmds + 1] = Back.BackCmdVecSplat(init_acc[u], vec_ty, acc0)
        end
        append_all(cmds, pre_cmds)
        local header_args = { start_id }
        for u = 1, unroll do header_args[#header_args + 1] = init_acc[u] end
        for i = 1, #loop_consts do header_args[#header_args + 1] = loop_consts[i].init end
        cmds[#cmds + 1] = Back.BackCmdJump(header, header_args)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(header)
        local cond = Back.BackValId("vec.cond")
        local cond_body_args = { h_i }
        local cond_exit_args = {}
        for u = 1, unroll do
            cond_body_args[#cond_body_args + 1] = h_acc[u]
            cond_exit_args[#cond_exit_args + 1] = h_acc[u]
        end
        for i = 1, #loop_consts do cond_body_args[#cond_body_args + 1] = loop_consts[i].header end
        cmds[#cmds + 1] = Back.BackCmdUIcmpLt(cond, scalar_ty, h_i, main_stop)
        cmds[#cmds + 1] = Back.BackCmdBrIf(cond, body, cond_body_args, vec_exit, cond_exit_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(body)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(body)
        for u = 1, unroll do
            append_all(cmds, group_expr_cmds[u])
            cmds[#cmds + 1] = Back.BackCmdVecIadd(next_acc[u], vec_ty, b_acc[u], group_values[u])
        end
        local next_i = Back.BackValId("vec.next.i")
        cmds[#cmds + 1] = Back.BackCmdIadd(next_i, scalar_ty, b_i, stride_id)
        local back_args = { next_i }
        for u = 1, unroll do back_args[#back_args + 1] = next_acc[u] end
        for i = 1, #loop_consts do back_args[#back_args + 1] = loop_consts[i].body end
        cmds[#cmds + 1] = Back.BackCmdJump(header, back_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(header)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(vec_exit)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(vec_exit)
        local reduced = nil
        for u = 1, unroll do
            for lane = 0, self.lanes - 1 do
                local lane_id = Back.BackValId("reduce.u" .. u .. ".lane." .. lane)
                cmds[#cmds + 1] = Back.BackCmdVecExtractLane(lane_id, scalar_ty, ve_acc[u], lane)
                if reduced == nil then
                    reduced = lane_id
                else
                    local sum_id = Back.BackValId("reduce.u" .. u .. ".sum." .. lane)
                    cmds[#cmds + 1] = Back.BackCmdIadd(sum_id, scalar_ty, reduced, lane_id)
                    reduced = sum_id
                end
            end
        end
        cmds[#cmds + 1] = Back.BackCmdJump(tail_header, { main_stop, reduced })
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(tail_header)
        local tail_cond = Back.BackValId("tail.cond")
        cmds[#cmds + 1] = Back.BackCmdUIcmpLt(tail_cond, scalar_ty, t_i, n_arg)
        cmds[#cmds + 1] = Back.BackCmdBrIf(tail_cond, tail_body, { t_i, t_acc }, exit, { t_acc })
        cmds[#cmds + 1] = Back.BackCmdSealBlock(tail_body)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(tail_body)
        local tail_counter = 0
        local tail_env = {
            path = func_name .. ".tail",
            scalar_ty = scalar_ty,
            index_value = tb_i,
            exprs = self.exprs,
            next_id = function()
                tail_counter = tail_counter + 1
                return tail_counter
            end,
        }
        local tail_expr_cmds, tail_value = lower_tail_scalar_expr(self.value, tail_env)
        append_all(cmds, tail_expr_cmds)
        local tail_next_acc = Back.BackValId("tail.next.acc")
        local one = Back.BackValId("tail.one")
        local tail_next_i = Back.BackValId("tail.next.i")
        cmds[#cmds + 1] = Back.BackCmdIadd(tail_next_acc, scalar_ty, tb_acc, tail_value)
        cmds[#cmds + 1] = Back.BackCmdConstInt(one, scalar_ty, "1")
        cmds[#cmds + 1] = Back.BackCmdIadd(tail_next_i, scalar_ty, tb_i, one)
        cmds[#cmds + 1] = Back.BackCmdJump(tail_header, { tail_next_i, tail_next_acc })
        cmds[#cmds + 1] = Back.BackCmdSealBlock(tail_header)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit)
        cmds[#cmds + 1] = Back.BackCmdReturnValue(result)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(entry)
        cmds[#cmds + 1] = Back.BackCmdFinishFunc(func)
        cmds[#cmds + 1] = Back.BackCmdFinalizeModule
        return Back.BackProgram(cmds)
    end

    local function lower_chunked_i32_add_reduction_plan(self, func_name)
        if self.lanes ~= 4 then error("vector_to_back: chunked i32 lowering requires i32x4") end
        local unroll = self.unroll
        local scalar_ty = scalar_of_sem_ty(self.carry.ty)
        local vec_scalar_ty = Back.BackI32
        local vec_ty = Back.BackVec(vec_scalar_ty, self.lanes)
        local stop_binding = stop_arg(self)
        local stride = self.lanes * unroll
        local chunk_elems = math.floor(self.chunk_elems / stride) * stride
        if chunk_elems < stride then chunk_elems = stride end
        local func = Back.BackFuncId(func_name)
        local sig = Back.BackSigId("sig:" .. func_name)
        local entry = Back.BackBlockId(func_name .. ":entry")
        local outer_header = Back.BackBlockId(func_name .. ":outer.header")
        local outer_body = Back.BackBlockId(func_name .. ":outer.body")
        local inner_header = Back.BackBlockId(func_name .. ":inner.header")
        local inner_body = Back.BackBlockId(func_name .. ":inner.body")
        local inner_exit = Back.BackBlockId(func_name .. ":inner.exit")
        local tail_header = Back.BackBlockId(func_name .. ":tail.header")
        local tail_body = Back.BackBlockId(func_name .. ":tail.body")
        local exit = Back.BackBlockId(func_name .. ":exit")
        local n_arg = Back.BackValId("arg:" .. stop_binding.index .. ":" .. stop_binding.name)
        local start_id = Back.BackValId("init.i")
        local total0 = Back.BackValId("init.total")
        local stride_id = Back.BackValId("const.stride")
        local chunk_id = Back.BackValId("const.chunk")
        local count = Back.BackValId("main.count")
        local rem = Back.BackValId("main.rem")
        local main_count = Back.BackValId("main.count.aligned")
        local main_stop = Back.BackValId("main.stop")
        local zero32 = Back.BackValId("zero.i32")
        local zero_v = {}
        local o_i = Back.BackValId("outer.i")
        local o_total = Back.BackValId("outer.total")
        local raw_chunk_end = Back.BackValId("chunk.raw.end")
        local chunk_lt = Back.BackValId("chunk.lt")
        local chunk_end = Back.BackValId("chunk.end")
        local ih_i = Back.BackValId("inner.header.i")
        local ib_i = Back.BackValId("inner.body.i")
        local ie_acc = {}
        local ih_acc = {}
        local ib_acc = {}
        local next_acc = {}
        local t_i = Back.BackValId("tail.header.i")
        local t_acc = Back.BackValId("tail.header.acc")
        local tb_i = Back.BackValId("tail.body.i")
        local tb_acc = Back.BackValId("tail.body.acc")
        local result = Back.BackValId("result")
        for u = 1, unroll do
            zero_v[u] = Back.BackValId("zero.v" .. u)
            ih_acc[u] = Back.BackValId("inner.header.acc" .. u)
            ib_acc[u] = Back.BackValId("inner.body.acc" .. u)
            ie_acc[u] = Back.BackValId("inner.exit.acc" .. u)
            next_acc[u] = Back.BackValId("inner.next.acc" .. u)
        end

        local pre_cmds = {}
        local loop_consts = {}
        local function add_loop_vec_const(init, label)
            local idx = #loop_consts + 1
            local h = Back.BackValId("inner.header.const" .. idx .. "." .. label)
            local b = Back.BackValId("inner.body.const" .. idx .. "." .. label)
            loop_consts[idx] = { init = init, header = h, body = b }
            return b
        end
        local offsets = {}
        for u = 1, unroll do
            local init_offset = build_offset_vector(pre_cmds, vec_ty, vec_scalar_ty, func_name .. ".i32.offset" .. u, self.lanes, (u - 1) * self.lanes)
            offsets[u] = add_loop_vec_const(init_offset, "offset" .. u)
        end
        local counter = 0
        local shared_env = {
            path = func_name .. ".i32.vec",
            lanes = self.lanes,
            scalar_ty = vec_scalar_ty,
            vec_ty = vec_ty,
            pre_cmds = pre_cmds,
            invariant_vecs = {},
            exprs = self.exprs,
            add_loop_vec_const = add_loop_vec_const,
            next_id = function()
                counter = counter + 1
                return counter
            end,
        }
        local index32 = {}
        local group_expr_cmds = {}
        local group_values = {}
        for u = 1, unroll do
            index32[u] = Back.BackValId("inner.index32." .. u)
            shared_env.index_value = index32[u]
            shared_env.offset_vec = offsets[u]
            local expr_cmds, vec_value = lower_vec_expr(self.value, shared_env)
            group_expr_cmds[u] = expr_cmds
            group_values[u] = vec_value
        end

        local cmds = {
            Back.BackCmdCreateSig(sig, { scalar_ty }, { scalar_ty }),
            Back.BackCmdDeclareFuncExport(func, sig),
            Back.BackCmdBeginFunc(func),
            Back.BackCmdCreateBlock(entry),
            Back.BackCmdSwitchToBlock(entry),
            Back.BackCmdBindEntryParams(entry, { n_arg }),
            Back.BackCmdCreateBlock(outer_header),
            Back.BackCmdCreateBlock(outer_body),
            Back.BackCmdCreateBlock(inner_header),
            Back.BackCmdCreateBlock(inner_body),
            Back.BackCmdCreateBlock(inner_exit),
            Back.BackCmdCreateBlock(tail_header),
            Back.BackCmdCreateBlock(tail_body),
            Back.BackCmdCreateBlock(exit),
            Back.BackCmdAppendBlockParam(outer_header, o_i, scalar_ty),
            Back.BackCmdAppendBlockParam(outer_header, o_total, scalar_ty),
            Back.BackCmdAppendBlockParam(inner_header, ih_i, scalar_ty),
            Back.BackCmdAppendBlockParam(inner_body, ib_i, scalar_ty),
        }
        for u = 1, unroll do cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(inner_header, ih_acc[u], vec_ty) end
        for i = 1, #loop_consts do cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(inner_header, loop_consts[i].header, vec_ty) end
        for u = 1, unroll do cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(inner_body, ib_acc[u], vec_ty) end
        for i = 1, #loop_consts do cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(inner_body, loop_consts[i].body, vec_ty) end
        for u = 1, unroll do cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(inner_exit, ie_acc[u], vec_ty) end
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(tail_header, t_i, scalar_ty)
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(tail_header, t_acc, scalar_ty)
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(tail_body, tb_i, scalar_ty)
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(tail_body, tb_acc, scalar_ty)
        cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(exit, result, scalar_ty)
        lower_scalar_invariant(self.start, scalar_ty, cmds, start_id)
        lower_scalar_invariant(self.carry.init, scalar_ty, cmds, total0)
        cmds[#cmds + 1] = Back.BackCmdConstInt(stride_id, scalar_ty, tostring(stride))
        cmds[#cmds + 1] = Back.BackCmdConstInt(chunk_id, scalar_ty, tostring(chunk_elems))
        cmds[#cmds + 1] = Back.BackCmdIsub(count, scalar_ty, n_arg, start_id)
        cmds[#cmds + 1] = Back.BackCmdUrem(rem, scalar_ty, count, stride_id)
        cmds[#cmds + 1] = Back.BackCmdIsub(main_count, scalar_ty, count, rem)
        cmds[#cmds + 1] = Back.BackCmdIadd(main_stop, scalar_ty, start_id, main_count)
        cmds[#cmds + 1] = Back.BackCmdConstInt(zero32, vec_scalar_ty, "0")
        for u = 1, unroll do cmds[#cmds + 1] = Back.BackCmdVecSplat(zero_v[u], vec_ty, zero32) end
        append_all(cmds, pre_cmds)
        cmds[#cmds + 1] = Back.BackCmdJump(outer_header, { start_id, total0 })
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(outer_header)
        local outer_cond = Back.BackValId("outer.cond")
        cmds[#cmds + 1] = Back.BackCmdUIcmpLt(outer_cond, scalar_ty, o_i, main_stop)
        cmds[#cmds + 1] = Back.BackCmdBrIf(outer_cond, outer_body, {}, tail_header, { main_stop, o_total })
        cmds[#cmds + 1] = Back.BackCmdSealBlock(outer_body)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(outer_body)
        cmds[#cmds + 1] = Back.BackCmdIadd(raw_chunk_end, scalar_ty, o_i, chunk_id)
        cmds[#cmds + 1] = Back.BackCmdUIcmpLt(chunk_lt, scalar_ty, raw_chunk_end, main_stop)
        cmds[#cmds + 1] = Back.BackCmdSelect(chunk_end, scalar_ty, chunk_lt, raw_chunk_end, main_stop)
        local inner_start_args = { o_i }
        for u = 1, unroll do inner_start_args[#inner_start_args + 1] = zero_v[u] end
        for i = 1, #loop_consts do inner_start_args[#inner_start_args + 1] = loop_consts[i].init end
        cmds[#cmds + 1] = Back.BackCmdJump(inner_header, inner_start_args)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(inner_header)
        local inner_cond = Back.BackValId("inner.cond")
        local inner_body_args = { ih_i }
        local inner_exit_args = {}
        for u = 1, unroll do
            inner_body_args[#inner_body_args + 1] = ih_acc[u]
            inner_exit_args[#inner_exit_args + 1] = ih_acc[u]
        end
        for i = 1, #loop_consts do inner_body_args[#inner_body_args + 1] = loop_consts[i].header end
        cmds[#cmds + 1] = Back.BackCmdUIcmpLt(inner_cond, scalar_ty, ih_i, chunk_end)
        cmds[#cmds + 1] = Back.BackCmdBrIf(inner_cond, inner_body, inner_body_args, inner_exit, inner_exit_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(inner_body)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(inner_body)
        for u = 1, unroll do
            cmds[#cmds + 1] = Back.BackCmdIreduce(index32[u], vec_scalar_ty, ib_i)
            append_all(cmds, group_expr_cmds[u])
            cmds[#cmds + 1] = Back.BackCmdVecIadd(next_acc[u], vec_ty, ib_acc[u], group_values[u])
        end
        local inner_next_i = Back.BackValId("inner.next.i")
        cmds[#cmds + 1] = Back.BackCmdIadd(inner_next_i, scalar_ty, ib_i, stride_id)
        local inner_back_args = { inner_next_i }
        for u = 1, unroll do inner_back_args[#inner_back_args + 1] = next_acc[u] end
        for i = 1, #loop_consts do inner_back_args[#inner_back_args + 1] = loop_consts[i].body end
        cmds[#cmds + 1] = Back.BackCmdJump(inner_header, inner_back_args)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(inner_header)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(inner_exit)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(inner_exit)
        local reduced = o_total
        for u = 1, unroll do
            for lane = 0, self.lanes - 1 do
                local lane32 = Back.BackValId("chunk.reduce.u" .. u .. ".lane" .. lane)
                local lane64 = Back.BackValId("chunk.reduce.u" .. u .. ".lane64" .. lane)
                local sum = Back.BackValId("chunk.reduce.u" .. u .. ".sum" .. lane)
                cmds[#cmds + 1] = Back.BackCmdVecExtractLane(lane32, vec_scalar_ty, ie_acc[u], lane)
                cmds[#cmds + 1] = Back.BackCmdUextend(lane64, scalar_ty, lane32)
                cmds[#cmds + 1] = Back.BackCmdIadd(sum, scalar_ty, reduced, lane64)
                reduced = sum
            end
        end
        cmds[#cmds + 1] = Back.BackCmdJump(outer_header, { chunk_end, reduced })
        cmds[#cmds + 1] = Back.BackCmdSealBlock(outer_header)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(tail_header)
        local tail_cond = Back.BackValId("tail.cond")
        cmds[#cmds + 1] = Back.BackCmdUIcmpLt(tail_cond, scalar_ty, t_i, n_arg)
        cmds[#cmds + 1] = Back.BackCmdBrIf(tail_cond, tail_body, { t_i, t_acc }, exit, { t_acc })
        cmds[#cmds + 1] = Back.BackCmdSealBlock(tail_body)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(tail_body)
        local tail_counter = 0
        local tail_env = { path = func_name .. ".tail", scalar_ty = scalar_ty, index_value = tb_i, exprs = self.exprs, next_id = function() tail_counter = tail_counter + 1; return tail_counter end }
        local tail_expr_cmds, tail_value = lower_tail_scalar_expr(self.value, tail_env)
        append_all(cmds, tail_expr_cmds)
        local tail_next_acc = Back.BackValId("tail.next.acc")
        local one = Back.BackValId("tail.one")
        local tail_next_i = Back.BackValId("tail.next.i")
        cmds[#cmds + 1] = Back.BackCmdIadd(tail_next_acc, scalar_ty, tb_acc, tail_value)
        cmds[#cmds + 1] = Back.BackCmdConstInt(one, scalar_ty, "1")
        cmds[#cmds + 1] = Back.BackCmdIadd(tail_next_i, scalar_ty, tb_i, one)
        cmds[#cmds + 1] = Back.BackCmdJump(tail_header, { tail_next_i, tail_next_acc })
        cmds[#cmds + 1] = Back.BackCmdSealBlock(tail_header)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(exit)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(exit)
        cmds[#cmds + 1] = Back.BackCmdReturnValue(result)
        cmds[#cmds + 1] = Back.BackCmdSealBlock(entry)
        cmds[#cmds + 1] = Back.BackCmdFinishFunc(func)
        cmds[#cmds + 1] = Back.BackCmdFinalizeModule
        return Back.BackProgram(cmds)
    end

    local function vec_func_signature(func)
        local params = {}
        for i = 1, #func.params do
            params[i] = scalar_of_sem_ty(func.params[i].ty)
        end
        local results = {}
        if func.result ~= Sem.SemTVoid then
            results[1] = scalar_of_sem_ty(func.result)
        end
        return params, results
    end

    local function lower_vec_block_params(block, cmds, is_entry)
        local ids = {}
        for i = 1, #block.params do
            local param = block.params[i]
            local id = vec_value_id(param.id)
            ids[#ids + 1] = id
            if not is_entry then
                if is_class(param, Vec.VecVectorParam) then
                    cmds[#cmds + 1] = Back.BackCmdAppendVecBlockParam(vec_block_id(block.id), id, Back.BackVec(scalar_of_vec_elem(param.elem), param.lanes))
                else
                    cmds[#cmds + 1] = Back.BackCmdAppendBlockParam(vec_block_id(block.id), id, scalar_of_vec_elem(param.elem))
                end
            end
        end
        return ids
    end

    local function lower_vec_cmd(cmd, out, value_shapes)
        local cls = pvm.classof(cmd)
        if cls == Vec.VecCmdConstInt then
            value_shapes[cmd.dst] = Vec.VecScalarShape(cmd.elem)
            out[#out + 1] = Back.BackCmdConstInt(vec_value_id(cmd.dst), scalar_of_vec_elem(cmd.elem), cmd.raw)
            return
        end
        if cls == Vec.VecCmdSplat then
            value_shapes[cmd.dst] = cmd.shape
            out[#out + 1] = Back.BackCmdVecSplat(vec_value_id(cmd.dst), vec_shape_to_back(cmd.shape), vec_value_id(cmd.scalar))
            return
        end
        if cls == Vec.VecCmdRamp then
            value_shapes[cmd.dst] = cmd.shape
            local scalar_ty = scalar_of_vec_elem(cmd.shape.elem)
            local vec_ty = vec_shape_to_back(cmd.shape)
            local current = Back.BackValId(cmd.dst.text .. ".ramp.splat")
            out[#out + 1] = Back.BackCmdVecSplat(current, vec_ty, vec_value_id(cmd.base))
            for lane = 0, cmd.shape.lanes - 1 do
                local raw = cmd.offsets[lane + 1] or "0"
                if raw ~= "0" then
                    local c = Back.BackValId(cmd.dst.text .. ".ramp.c" .. lane)
                    local v = Back.BackValId(cmd.dst.text .. ".ramp.v" .. lane)
                    out[#out + 1] = Back.BackCmdConstInt(c, scalar_ty, raw)
                    out[#out + 1] = Back.BackCmdIadd(v, scalar_ty, vec_value_id(cmd.base), c)
                    local next_current = (lane == cmd.shape.lanes - 1) and vec_value_id(cmd.dst) or Back.BackValId(cmd.dst.text .. ".ramp.insert" .. lane)
                    out[#out + 1] = Back.BackCmdVecInsertLane(next_current, vec_ty, current, v, lane)
                    current = next_current
                elseif lane == cmd.shape.lanes - 1 then
                    out[#out + 1] = Back.BackCmdAlias(vec_value_id(cmd.dst), current)
                end
            end
            return
        end
        if cls == Vec.VecCmdBin then
            value_shapes[cmd.dst] = cmd.shape
            if is_class(cmd.shape, Vec.VecVectorShape) then
                out[#out + 1] = lower_vector_bin_cmd(cmd.op, vec_value_id(cmd.dst), vec_shape_to_back(cmd.shape), vec_value_id(cmd.lhs), vec_value_id(cmd.rhs))
            else
                out[#out + 1] = lower_scalar_bin_cmd(cmd.op, vec_value_id(cmd.dst), scalar_of_vec_elem(cmd.shape.elem), vec_value_id(cmd.lhs), vec_value_id(cmd.rhs))
            end
            return
        end
        if cls == Vec.VecCmdSelect then
            if is_class(cmd.shape, Vec.VecVectorShape) then
                error("vector_to_back: vector select lowering is not implemented yet")
            end
            value_shapes[cmd.dst] = cmd.shape
            out[#out + 1] = Back.BackCmdSelect(vec_value_id(cmd.dst), scalar_of_vec_elem(cmd.shape.elem), vec_value_id(cmd.cond), vec_value_id(cmd.then_value), vec_value_id(cmd.else_value))
            return
        end
        if cls == Vec.VecCmdLoad then
            value_shapes[cmd.dst] = cmd.shape
            if is_class(cmd.shape, Vec.VecVectorShape) then
                out[#out + 1] = Back.BackCmdVecLoad(vec_value_id(cmd.dst), vec_shape_to_back(cmd.shape), vec_value_id(cmd.addr))
            else
                out[#out + 1] = Back.BackCmdLoad(vec_value_id(cmd.dst), scalar_of_vec_elem(cmd.shape.elem), vec_value_id(cmd.addr))
            end
            return
        end
        if cls == Vec.VecCmdStore then
            if is_class(cmd.shape, Vec.VecVectorShape) then
                out[#out + 1] = Back.BackCmdVecStore(vec_shape_to_back(cmd.shape), vec_value_id(cmd.addr), vec_value_id(cmd.value))
            else
                out[#out + 1] = Back.BackCmdStore(scalar_of_vec_elem(cmd.shape.elem), vec_value_id(cmd.addr), vec_value_id(cmd.value))
            end
            return
        end
        if cls == Vec.VecCmdIreduce then
            value_shapes[cmd.dst] = Vec.VecScalarShape(cmd.narrow_elem)
            out[#out + 1] = Back.BackCmdIreduce(vec_value_id(cmd.dst), scalar_of_vec_elem(cmd.narrow_elem), vec_value_id(cmd.value))
            return
        end
        if cls == Vec.VecCmdUextend then
            value_shapes[cmd.dst] = Vec.VecScalarShape(cmd.wide_elem)
            out[#out + 1] = Back.BackCmdUextend(vec_value_id(cmd.dst), scalar_of_vec_elem(cmd.wide_elem), vec_value_id(cmd.value))
            return
        end
        if cls == Vec.VecCmdExtractLane then
            local shape = value_shapes[cmd.vec]
            if shape == nil or not is_class(shape, Vec.VecVectorShape) then
                error("vector_to_back: extract lane source has no vector shape")
            end
            value_shapes[cmd.dst] = Vec.VecScalarShape(shape.elem)
            out[#out + 1] = Back.BackCmdVecExtractLane(vec_value_id(cmd.dst), scalar_of_vec_elem(shape.elem), vec_value_id(cmd.vec), cmd.lane)
            return
        end
        if cls == Vec.VecCmdHorizontalReduce then
            local reduced = nil
            local elem
            for i = 1, #cmd.vectors do
                local shape = value_shapes[cmd.vectors[i]]
                if shape == nil or not is_class(shape, Vec.VecVectorShape) then
                    error("vector_to_back: horizontal reduce source has no vector shape")
                end
                elem = shape.elem
                for lane = 0, shape.lanes - 1 do
                    local lane_id = Back.BackValId(cmd.dst.text .. ".v" .. i .. ".lane" .. lane)
                    out[#out + 1] = Back.BackCmdVecExtractLane(lane_id, scalar_of_vec_elem(shape.elem), vec_value_id(cmd.vectors[i]), lane)
                    if reduced == nil then
                        reduced = lane_id
                    else
                        local sum = Back.BackValId(cmd.dst.text .. ".v" .. i .. ".sum" .. lane)
                        out[#out + 1] = lower_scalar_bin_cmd(cmd.op, sum, scalar_of_vec_elem(shape.elem), reduced, lane_id)
                        reduced = sum
                    end
                end
            end
            if reduced == nil then
                error("vector_to_back: horizontal reduce needs at least one vector")
            end
            value_shapes[cmd.dst] = Vec.VecScalarShape(elem)
            out[#out + 1] = Back.BackCmdAlias(vec_value_id(cmd.dst), reduced)
            return
        end
        error("vector_to_back: unsupported VecCmd " .. tostring(cmd))
    end

    local function lower_vec_terminator(term, out)
        local cls = pvm.classof(term)
        if cls == Vec.VecJump then
            local args = {}
            for i = 1, #term.args do args[i] = vec_value_id(term.args[i]) end
            out[#out + 1] = Back.BackCmdJump(vec_block_id(term.dest), args)
            return
        end
        if cls == Vec.VecBrIf then
            local then_args, else_args = {}, {}
            for i = 1, #term.then_args do then_args[i] = vec_value_id(term.then_args[i]) end
            for i = 1, #term.else_args do else_args[i] = vec_value_id(term.else_args[i]) end
            out[#out + 1] = Back.BackCmdBrIf(vec_value_id(term.cond), vec_block_id(term.then_block), then_args, vec_block_id(term.else_block), else_args)
            return
        end
        if term == Vec.VecReturnVoid then
            out[#out + 1] = Back.BackCmdReturnVoid
            return
        end
        if cls == Vec.VecReturnValue then
            out[#out + 1] = Back.BackCmdReturnValue(vec_value_id(term.value))
            return
        end
        error("vector_to_back: unsupported VecTerminator " .. tostring(term))
    end

    local function lower_blocks_to_back(func, blocks, func_name)
        if #blocks == 0 then
            error("vector_to_back: no VecBlock skeleton available")
        end
        local name = func_name or func.name
        local fid = Back.BackFuncId(name)
        local sig = Back.BackSigId("sig:" .. name)
        local params, results = vec_func_signature(func)
        local cmds = {
            Back.BackCmdCreateSig(sig, params, results),
        }
        if is_class(func, Sem.SemFuncLocal) then
            cmds[#cmds + 1] = Back.BackCmdDeclareFuncLocal(fid, sig)
        else
            cmds[#cmds + 1] = Back.BackCmdDeclareFuncExport(fid, sig)
        end
        cmds[#cmds + 1] = Back.BackCmdBeginFunc(fid)
        for i = 1, #blocks do
            cmds[#cmds + 1] = Back.BackCmdCreateBlock(vec_block_id(blocks[i].id))
        end
        local value_shapes = {}
        for i = 1, #blocks do
            for j = 1, #blocks[i].params do
                local param = blocks[i].params[j]
                if is_class(param, Vec.VecVectorParam) then
                    value_shapes[param.id] = Vec.VecVectorShape(param.elem, param.lanes)
                else
                    value_shapes[param.id] = Vec.VecScalarShape(param.elem)
                end
            end
        end
        local entry_ids = lower_vec_block_params(blocks[1], cmds, true)
        cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(vec_block_id(blocks[1].id))
        cmds[#cmds + 1] = Back.BackCmdBindEntryParams(vec_block_id(blocks[1].id), entry_ids)
        for i = 2, #blocks do
            lower_vec_block_params(blocks[i], cmds, false)
        end
        for i = 1, #blocks do
            local block = blocks[i]
            if i ~= 1 then
                cmds[#cmds + 1] = Back.BackCmdSwitchToBlock(vec_block_id(block.id))
            end
            for j = 1, #block.cmds do
                lower_vec_cmd(block.cmds[j], cmds, value_shapes)
            end
            lower_vec_terminator(block.terminator, cmds)
        end
        for i = 1, #blocks do
            cmds[#cmds + 1] = Back.BackCmdSealBlock(vec_block_id(blocks[i].id))
        end
        cmds[#cmds + 1] = Back.BackCmdFinishFunc(fid)
        cmds[#cmds + 1] = Back.BackCmdFinalizeModule
        return Back.BackProgram(cmds)
    end

    local function expr_map(graph)
        local out = {}
        for i = 1, #graph.exprs do
            local fact = graph.exprs[i]
            out[fact.id] = fact
        end
        return out
    end

    local function func_name(func)
        return func.name
    end

    local function first_vector_decision(func)
        for i = 1, #func.decisions do
            local chosen = func.decisions[i].chosen
            if is_class(chosen, Vec.VecLoopVector) or is_class(chosen, Vec.VecLoopChunkedNarrowVector) then
                return func.decisions[i]
            end
        end
        return nil
    end

    local function bitand_bound_for(facts, id)
        for i = 1, #facts.ranges do
            local r = facts.ranges[i]
            if is_class(r, Vec.VecRangeBitAnd) and r.expr == id then
                return tonumber(r.max_value) or 0
            end
        end
        local fact = expr_map(facts.exprs)[id]
        if fact ~= nil and is_class(fact, Vec.VecExprLocal) then
            return bitand_bound_for(facts, fact.value)
        end
        return 0
    end

    local function plan_from_decision(decision)
        local chosen = decision.chosen
        if is_class(chosen, Vec.VecLoopScalar) then
            error("vector_to_back: cannot lower scalar vector-loop decision")
        end
        local facts = decision.facts
        if not is_class(facts.domain, Vec.VecDomainCounted) then
            error("vector_to_back: vector decision has no counted domain")
        end
        if #facts.inductions < 1 then
            error("vector_to_back: vector decision has no primary induction")
        end
        if #facts.reductions ~= 1 then
            error("vector_to_back: vector decision requires exactly one reduction")
        end
        local reduction = facts.reductions[1]
        local lanes
        if is_class(chosen, Vec.VecLoopChunkedNarrowVector) then
            lanes = chosen.narrow_shape.lanes
        else
            lanes = chosen.shape.lanes
        end
        return {
            loop_id = facts.loop.text,
            lanes = lanes,
            unroll = chosen.unroll or 1,
            chunk_elems = chosen.chunk_elems,
            index = facts.inductions[1].binding,
            start = facts.domain.start,
            stop = facts.domain.stop,
            carry = reduction.carry,
            value = reduction.value,
            max_term = bitand_bound_for(facts, reduction.value),
            exprs = expr_map(facts.exprs),
        }
    end

    lower_decision = pvm.phase("moonlift_vec_decision_to_back", {
        [Vec.VecLoopDecision] = function(self, name)
            local plan = plan_from_decision(self)
            if is_class(self.chosen, Vec.VecLoopChunkedNarrowVector) then
                return pvm.once(lower_chunked_i32_add_reduction_plan(plan, name))
            end
            return pvm.once(lower_add_reduction_plan(plan, name, plan.unroll))
        end,
    })

    lower_func = pvm.phase("moonlift_vec_func_to_back", {
        [Vec.VecFuncVector] = function(self, name)
            if #self.blocks > 0 then
                return pvm.once(lower_blocks_to_back(self.func, self.blocks, name or func_name(self.func)))
            end
            local decision = first_vector_decision(self)
            if decision == nil then
                error("vector_to_back: VecFuncVector has no vector decision")
            end
            return lower_decision(decision, name or func_name(self.func))
        end,
        [Vec.VecFuncMixed] = function(self, name)
            if #self.blocks > 0 then
                return pvm.once(lower_blocks_to_back(self.func, self.blocks, name or func_name(self.func)))
            end
            local decision = first_vector_decision(self)
            if decision == nil then
                error("vector_to_back: VecFuncMixed has no vector decision")
            end
            return lower_decision(decision, name or func_name(self.func))
        end,
        [Vec.VecFuncScalar] = function()
            error("vector_to_back: scalar VecFunc must use ordinary Sem -> Back lowering")
        end,
    })

    lower_module = pvm.phase("moonlift_vec_module_to_back", {
        [Vec.VecModule] = function(self, name)
            if #self.funcs ~= 1 then
                error("vector_to_back: initial VecModule -> BackProgram lowering expects exactly one vector function")
            end
            return lower_func(self.funcs[1], name)
        end,
    })

    return {
        lower_decision = lower_decision,
        lower_func = lower_func,
        lower_module = lower_module,
    }
end

return M
