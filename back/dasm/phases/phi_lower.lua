local pvm = require("lalin.pvm")
local Mx = require("back.dasm.model")

local function sorted_keys(set)
    local ks = {}
    for k in pairs(set) do ks[#ks + 1] = k end
    table.sort(ks)
    return ks
end

local function lower_cfg(cfg)
    local D = Mx.dasm()
    local B = Mx.back()

    local tmp_n = 0
    local function fresh_tmp()
        tmp_n = tmp_n + 1
        return B.BackValId("__phi_tmp_" .. tostring(tmp_n))
    end

    local function mk_alias(dst, src)
        return B.CmdAlias(Mx.back_val_id(dst), Mx.back_val_id(src))
    end

    local function emit_parallel_copy(edge_args)
        local assignments, dst_obj, src_obj = {}, {}, {}

        for i = 1, #(edge_args or {}) do
            local ea = edge_args[i]
            local dk, sk = Mx.idkey(ea.dst_param), Mx.idkey(ea.src)
            if dk and sk and dk ~= sk then
                assignments[#assignments + 1] = { dst = ea.dst_param, src = ea.src }
                dst_obj[dk] = ea.dst_param
                src_obj[sk] = ea.src
            end
        end

        local dst_to_src, remaining = {}, {}
        for i = 1, #assignments do
            local a = assignments[i]
            local dk, sk = Mx.idkey(a.dst), Mx.idkey(a.src)
            dst_to_src[dk] = sk
            remaining[dk] = true
        end

        local out = {}
        while next(remaining) ~= nil do
            local advanced = false
            local batch = {}
            local rem = sorted_keys(remaining)

            for i = 1, #rem do
                local dk = rem[i]
                local blocked = false
                for j = 1, #rem do
                    local ok = rem[j]
                    if dst_to_src[ok] == dk then blocked = true; break end
                end
                if not blocked then batch[#batch + 1] = dk end
            end

            if #batch > 0 then
                table.sort(batch)
                for i = 1, #batch do
                    local dk = batch[i]
                    local sk = dst_to_src[dk]
                    out[#out + 1] = mk_alias(dst_obj[dk] or B.BackValId(dk), src_obj[sk] or B.BackValId(sk))
                    remaining[dk] = nil
                    advanced = true
                end
            end

            if advanced then goto continue end

            local cycle_dst = sorted_keys(remaining)[1]
            local cycle_src = dst_to_src[cycle_dst]
            local tmp = fresh_tmp()
            local tk = Mx.idkey(tmp)
            src_obj[tk] = tmp
            out[#out + 1] = mk_alias(tmp, src_obj[cycle_src] or B.BackValId(cycle_src))
            dst_to_src[cycle_dst] = tk

            ::continue::
        end

        return out
    end

    local existing = {}
    for i = 1, #cfg.blocks do existing[Mx.idkey(cfg.blocks[i].id)] = true end

    local synth_n = 0
    local function fresh_block_id(tag)
        while true do
            synth_n = synth_n + 1
            local raw = "__dasm_phi_" .. tag .. "_" .. tostring(synth_n)
            if not existing[raw] then
                existing[raw] = true
                return B.BackBlockId(raw)
            end
        end
    end

    local function mk_term_jump(dest, args)
        return D.DTermJump(dest, args or {})
    end

    local function mk_term_brif(cond, tdest, targs, edest, eargs)
        return D.DTermBrIf(cond, tdest, targs or {}, edest, eargs or {})
    end

    local new_blocks, synth_blocks = {}, {}

    for bi = 1, #cfg.blocks do
        local block = cfg.blocks[bi]
        local body = {}
        for i = 1, #(block.body or {}) do body[#body + 1] = block.body[i] end

        local term = block.term
        local tk = term and term.kind
        local lowered_term = term

        if tk == "DTermJump" then
            local copies = emit_parallel_copy(term.args)
            for i = 1, #copies do body[#body + 1] = copies[i] end
            lowered_term = mk_term_jump(term.dest, {})

        elseif tk == "DTermBrIf" then
            local then_dest, else_dest = term.then_block, term.else_block

            local then_copies = emit_parallel_copy(term.then_args)
            if #then_copies > 0 then
                local sid = fresh_block_id("then")
                synth_blocks[#synth_blocks + 1] = D.DCfgBlock(sid, {}, then_copies, mk_term_jump(term.then_block, {}))
                then_dest = sid
            end

            local else_copies = emit_parallel_copy(term.else_args)
            if #else_copies > 0 then
                local sid = fresh_block_id("else")
                synth_blocks[#synth_blocks + 1] = D.DCfgBlock(sid, {}, else_copies, mk_term_jump(term.else_block, {}))
                else_dest = sid
            end

            lowered_term = mk_term_brif(term.cond, then_dest, {}, else_dest, {})
        end

        new_blocks[#new_blocks + 1] = D.DCfgBlock(block.id, {}, body, lowered_term)
    end

    for i = 1, #synth_blocks do new_blocks[#new_blocks + 1] = synth_blocks[i] end

    return D.DFuncCFG(cfg.func, cfg.sig, cfg.entry, new_blocks, cfg.stack_slots or {})
end

local PHASE = nil
local function phase()
    if PHASE then return PHASE end
    local D = Mx.dasm()

    PHASE = pvm.phase("lalin_dasm_phi_lower", {
        [D.DFuncCFG] = function(cfg)
            return pvm.once(lower_cfg(cfg))
        end,
    })

    return PHASE
end

return {
    phase = function() return phase() end,
    run = function(cfg)
        return pvm.one(phase()(cfg))
    end,
}
