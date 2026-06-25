-- compile.lua - DynASM backend: ASDL BackProgram → machine code

local ffi      = require("ffi")
local bit      = require("bit")
local encode   = require("back.dasm.encode_x64")
local isel     = require("back.dasm.isel_x64")
local abi      = require("back.dasm.abi_sysv")
local Session  = require("back.dasm.dynasm_session")

local Mx = require("back.dasm.model")
local P_collect = require("back.dasm.phases.collect_module")
local P_normalize = require("back.dasm.phases.normalize_module")
local P_build_cfg = require("back.dasm.phases.build_cfg")
local P_type_values = require("back.dasm.phases.type_values")
local P_vector = require("back.dasm.phases.vector_scalarize")
local P_addr = require("back.dasm.phases.address_normalize")
local P_phi = require("back.dasm.phases.phi_lower")
local P_select = require("back.dasm.phases.select_mir")
local P_extract = require("back.dasm.phases.extract_facts")
local P_lower_facts = require("back.dasm.phases.lower_facts")
local P_abi = require("back.dasm.phases.abi_lower_sysv")
local P_regalloc = require("back.dasm.phases.regalloc_banked")
local P_frame = require("back.dasm.phases.frame_layout")

-- ── libdasm + executable memory ───────────────────────────────────────

local libdasm
ffi.cdef([[
    typedef struct dasm_State dasm_State;
    void dasm_init(dasm_State **Dst, int maxsection);
    void dasm_free(dasm_State **Dst);
    void dasm_setupglobal(dasm_State **Dst, void **gl, unsigned int maxgl);
    void dasm_growpc(dasm_State **Dst, unsigned int maxpc);
    void dasm_setup(dasm_State **Dst, const void *actionlist);
    void dasm_put_array(dasm_State **Dst, int start, const int *args, int nargs);
    int  dasm_link(dasm_State **Dst, size_t *szp);
    int  dasm_encode(dasm_State **Dst, void *buffer);
    void *mmap(void *addr, size_t length, int prot, int flags, int fd, long offset);
    int   munmap(void *addr, size_t length);
    int   mprotect(void *addr, size_t len, int prot);
]])

local PROT_RW  = 3    -- PROT_READ | PROT_WRITE
local PROT_RWX = 7    -- PROT_READ | PROT_WRITE | PROT_EXEC
local PROT_RX  = 5    -- PROT_READ | PROT_EXEC
local MAP_ANON = 0x22 -- MAP_PRIVATE | MAP_ANONYMOUS

local function load_dasm()
    if libdasm then return libdasm end
    local ok, lib = pcall(ffi.load, "./back/libdasm.so")
    if not ok then ok, lib = pcall(ffi.load, "back/libdasm.so") end
    if not ok then error("cannot load libdasm.so: " .. tostring(lib)) end
    libdasm = lib
    return libdasm
end

local function alloc_rw(n)
    local sz = bit.band((n + 4095), bit.bnot(4095))
    local p = ffi.C.mmap(nil, sz, PROT_RW, MAP_ANON, -1, 0)
    if p == ffi.cast("void *", -1) then error("mmap failed") end
    return p, sz
end

local function exec_protect(ptr, n)
    local rc = ffi.C.mprotect(ptr, n, PROT_RX)
    if rc ~= 0 then error("mprotect to RX failed") end
end

-- ── helpers ────────────────────────────────────────────────────────────

local idkey = Mx.idkey
local to_label = Mx.to_label
local scalar_kind = Mx.scalar_kind
local is_float_scalar = Mx.is_float_scalar

local function emit_raw_move(dst_reg, src_reg, kind)
    if dst_reg == src_reg then return end
    if kind == "f32" then
        encode.emit("movss_2", encode.reg(dst_reg, "x"), encode.reg(src_reg, "x"))
    elseif kind == "f64" then
        encode.emit("movsd_2", encode.reg(dst_reg, "x"), encode.reg(src_reg, "x"))
    else
        encode.emit("mov_2", encode.reg(dst_reg, "q"), encode.reg(src_reg, "q"))
    end
end

local function sorted_keys(set)
    local ks = {}
    for k in pairs(set) do ks[#ks + 1] = k end
    table.sort(ks)
    return ks
end

-- Parallel-copy resolver for physical register moves.
-- moves: { {dst=<reg>, src=<reg>, kind="int"|"f32"|"f64"}, ... }
local function emit_parallel_moves(moves, temp_reg)
    local dst_to_move = {}
    local remaining = {}

    for _, mv in ipairs(moves) do
        if mv.dst ~= nil and mv.src ~= nil and mv.dst ~= mv.src then
            dst_to_move[mv.dst] = { dst = mv.dst, src = mv.src, kind = mv.kind }
            remaining[mv.dst] = true
        end
    end

    while next(remaining) ~= nil do
        local advanced = false
        local batch = {}

        for _, dk in ipairs(sorted_keys(remaining)) do
            local blocked = false
            for _, ok in ipairs(sorted_keys(remaining)) do
                if dst_to_move[ok].src == dk then
                    blocked = true
                    break
                end
            end
            if not blocked then batch[#batch + 1] = dk end
        end

        if #batch > 0 then
            for _, dk in ipairs(batch) do
                local mv = dst_to_move[dk]
                emit_raw_move(mv.dst, mv.src, mv.kind)
                remaining[dk] = nil
                advanced = true
            end
        end

        if advanced then goto continue end

        local cycle_dst = sorted_keys(remaining)[1]
        local cycle_mv = dst_to_move[cycle_dst]
        emit_raw_move(temp_reg, cycle_mv.src, cycle_mv.kind)
        cycle_mv.src = temp_reg

        ::continue::
    end
end

-- ── compile ────────────────────────────────────────────────────────────

local function compile(program, symbols)
    symbols = symbols or {}
    local lib = load_dasm()
    local session = Session.new()

    local collected = P_collect.run(program)
    local normalized = P_normalize.run(collected)
    local mod = Mx.phase_module_maps(normalized)

    local sigs = mod.sigs
    local funcs = mod.funcs
    local externs = mod.externs
    local datas = mod.datas

    local fkeys = mod.fkeys
    local ekeys = mod.ekeys
    local dkeys = mod.dkeys

    isel.func_labels = mod.labels.funcs
    isel.extern_labels = mod.labels.externs
    isel.data_labels = mod.labels.datas

    -- compile each function
    for fi, fk in ipairs(fkeys) do
        local fd = funcs[fk]
        local bd = fd.body
        if not bd or #bd == 0 then goto continue end

        bd = P_vector.run(bd)
        bd = P_addr.run(bd)
        local cfg = P_build_cfg.run(Mx.make_phase_func(bd, Mx.back_func_id(fk)), Mx.back_sig_id(fd.sig))
        cfg = P_phi.run(cfg)
        local selected_pf = P_select.run(cfg)
        bd = Mx.phase_func_cmds(selected_pf)
        bd = P_abi.run(bd)

        local sig = sigs[fd.sig] or {params = {}, results = {}}
        local lowered_pf = Mx.make_phase_func(bd, Mx.back_func_id(fk))
        local typed_pf = P_type_values.run(lowered_pf, sig)
        local value_scalars = Mx.scalar_map_from_entries(typed_pf.value_scalars)

        -- LalinBack fact extraction + family-based lowering decisions.
        -- LalinBack remains the semantic source; this phase stack reflects
        -- and selects target shapes without changing semantics.
        local fact_set = P_extract.run(lowered_pf, value_scalars)
        local lowered = P_lower_facts.run(fact_set)
        local lower_rule_by_index = {}
        for i = 1, #(lowered.decisions or {}) do
            local d = lowered.decisions[i]
            lower_rule_by_index[d.cmd_index] = d.rule
        end
        bd = lowered.cmds
        isel.value_scalars = value_scalars
        isel.lower_rule_by_index = lower_rule_by_index
        local const_i64_by_val = {}
        for ci = 1, #bd do
            local c = bd[ci]
            if c.kind == "CmdConst" and c.value and c.value.kind == "BackLitInt" then
                const_i64_by_val[idkey(c.dst)] = tonumber(c.value.raw)
            end
        end
        isel.const_i64_by_val = const_i64_by_val

        local alloc = P_regalloc.run(Mx.make_phase_func(bd, Mx.back_func_id(fk)), value_scalars)
        local regmap = {}
        for i = 1, #(alloc.allocs or {}) do
            local a = alloc.allocs[i]
            if a.loc.kind == "DLocReg" then
                regmap[a.vreg.text] = a.loc.preg.number
            end
        end
        local ucs = {}
        for i = 1, #(alloc.used_callee_saved or {}) do
            ucs[alloc.used_callee_saved[i].number] = true
        end
        local spill_sa = alloc.spill_size or 0

        isel.block_labels = {}
        isel.stack_slots = {}
        isel.next_slot = 0

        -- pass 1: labels + stack slots
        local bi = 0
        for _, cmd in ipairs(bd) do
            if cmd.kind == "CmdCreateBlock" then
                local bk = idkey(cmd.block)
                if not isel.block_labels[bk] then
                    bi = bi + 1
                    isel.block_labels[bk] = "->B_" .. tostring(fi) .. "_" .. tostring(bi) .. "_" .. to_label(bk)
                end
            elseif cmd.kind == "CmdCreateStackSlot" then
                isel.alloc_slot(cmd.slot, cmd.size, cmd.align)
            end
        end

        local slot_sa = isel.next_slot
        local frame = P_frame.run(alloc, slot_sa)
        isel.set_frame(ucs, frame.stack_size)

        encode.label_def(isel.func_labels[fk])
        isel.emit_prologue()

        local ci = 1
        while ci <= #bd do
            local cmd = bd[ci]
            local k = cmd.kind

            if k == "CmdSwitchToBlock" then
                local bl = isel.block_labels[idkey(cmd.block)]
                if bl then encode.label_def(bl) end
            end

            if k == "CmdBindEntryParams" then
                -- Keep regalloc decisions intact; move ABI incoming registers
                -- into the allocated virtual-value registers with proper
                -- parallel-copy semantics.
                local int_moves, float_moves = {}, {}
                local gi, xi = 1, 1

                for i, vid in ipairs(cmd.values or {}) do
                    local key = idkey(vid)
                    local dst = regmap[key]
                    local sk = value_scalars[key] or scalar_kind(sig.params[i])

                    if is_float_scalar(sk) then
                        local src = abi.float_param_regs[xi]
                        xi = xi + 1
                        if dst ~= nil and src ~= nil and dst ~= src then
                            float_moves[#float_moves + 1] = {
                                dst = dst,
                                src = src,
                                kind = (sk == "BackF32") and "f32" or "f64",
                            }
                        end
                    else
                        local src = abi.param_regs[gi]
                        gi = gi + 1
                        if dst ~= nil and src ~= nil and dst ~= src then
                            int_moves[#int_moves + 1] = { dst = dst, src = src, kind = "int" }
                        end
                    end
                end

                -- r10/r11 are intentionally kept out of regalloc and are safe
                -- scratch registers for cycle breaking.
                emit_parallel_moves(int_moves, 10)
                emit_parallel_moves(float_moves, 10) -- xmm10 scratch
            end

            if k == "CmdReturnVoid" then
                isel.emit_epilogue()
                ci = ci + 1
                goto next_cmd
            end

            if k == "CmdCompare" and lower_rule_by_index[ci] == "cmp.fused-branch" then
                local nxt = bd[ci + 1]
                if nxt and nxt.kind == "CmdBrIf" and idkey(nxt.cond) == idkey(cmd.dst) then
                    local ok, err = pcall(isel.cmp_brif_, cmd, nxt, regmap)
                    if not ok then error("compile.lua: in '" .. fk .. "': " .. tostring(err), 0) end
                    ci = ci + 2
                    goto next_cmd
                end
            end

            if k == "CmdCreateBlock" or k == "CmdSwitchToBlock"
                or k == "CmdSealBlock" or k == "CmdBindEntryParams"
                or k == "CmdAppendBlockParam" or k == "CmdCreateStackSlot"
                or k == "CmdAliasFact" or k == "CmdTargetModel" then
                ci = ci + 1
                goto next_cmd
            end

            do
                local ok, err = pcall(isel.lower_cmd, cmd, regmap, ci)
                if not ok then error("compile.lua: in '" .. fk .. "': " .. tostring(err), 0) end
            end
            ci = ci + 1

            ::next_cmd::
        end

        ::continue::
    end

    -- build action list
    local fragments = session:flush_fragments()
    local parts = {}
    for _, f in ipairs(fragments) do parts[#parts + 1] = f.bytes end
    local alist = table.concat(parts)
    if #alist == 0 then error("compile.lua: empty action list") end

    local albuf = ffi.new("uint8_t[?]", #alist)
    ffi.copy(albuf, alist, #alist)

    -- resolve global label slots from DynASM's own label map
    local gmap = session:globals()
    local max_global_idx = 0
    for _, idx in pairs(gmap) do
        if type(idx) == "number" and idx > max_global_idx then max_global_idx = idx end
    end
    local nglobals = (max_global_idx >= 10) and (max_global_idx - 9) or 0

    local function slot_for_label(lbl)
        local key = tostring(lbl or "")
        if key:sub(1, 2) == "->" then key = key:sub(3) end
        local idx = gmap[key] or gmap[lbl]
        if type(idx) ~= "number" then return nil end
        if idx < 10 then return nil end
        return idx - 10
    end

    -- dasm state
    local Dst = ffi.new("dasm_State*[1]")
    lib.dasm_init(Dst, 1)
    local globals = ffi.new("void*[?]", math.max(nglobals, 1))

    -- seed globals for externs + data according to actual DynASM slot indices
    for _, ek in ipairs(ekeys) do
        local slot = slot_for_label(isel.extern_labels[ek])
        if slot ~= nil then
            local ext = externs[ek]
            if ext then
                local sym = symbols[ext.symbol]
                if sym then globals[slot] = ffi.cast("void *", sym) end
            end
        end
    end
    for _, dk in ipairs(dkeys) do
        local slot = slot_for_label(isel.data_labels[dk])
        if slot ~= nil then
            local d = datas[dk]
            if d then globals[slot] = d.buf end
        end
    end

    lib.dasm_setupglobal(Dst, globals, nglobals)
    lib.dasm_growpc(Dst, 0)
    lib.dasm_setup(Dst, albuf)

    -- feed fragments
    for _, f in ipairs(fragments) do
        local n = #f.args
        if n > 0 then
            local ab = ffi.new("int[?]", n)
            for i = 1, n do ab[i - 1] = math.floor(tonumber(f.args[i]) or 0) end
            lib.dasm_put_array(Dst, f.offset, ab, n)
        else
            lib.dasm_put_array(Dst, f.offset, nil, 0)
        end
    end

    -- link + encode
    local sz = ffi.new("size_t[1]")
    local lrc = lib.dasm_link(Dst, sz)
    if lrc ~= 0 then error("dasm_link failed 0x" .. bit.tohex(lrc)) end

    local code_size = tonumber(sz[0])
    local exec_ptr, exec_sz = alloc_rw(code_size)
    local erc = lib.dasm_encode(Dst, exec_ptr)
    exec_protect(exec_ptr, exec_sz)
    if erc ~= 0 then error("dasm_encode failed 0x" .. bit.tohex(erc)) end

    -- extract pointers
    local fptrs = {}
    for _, fk in ipairs(fkeys) do
        local slot = slot_for_label(isel.func_labels[fk])
        if slot ~= nil then
            local ptr = globals[slot]
            if ptr ~= nil then fptrs[fk] = ptr end
        end
    end
    for _, ek in ipairs(ekeys) do
        local slot = slot_for_label(isel.extern_labels[ek])
        if slot ~= nil then fptrs[ek] = globals[slot] end
    end
    for _, dk in ipairs(dkeys) do
        local slot = slot_for_label(isel.data_labels[dk])
        if slot ~= nil then fptrs[dk] = globals[slot] end
    end

    return {
        getpointer = function(_, fid)
            local k = idkey(fid) or fid
            local p = fptrs[k]
            if not p then error("compile: no code for '" .. tostring(k) .. "'") end
            return ffi.cast("const void *", p)
        end,
        free = function()
            lib.dasm_free(Dst)
            ffi.C.munmap(exec_ptr, exec_sz)
        end,
    }
end

return { compile = compile }
