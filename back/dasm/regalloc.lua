-- regalloc.lua — linear-scan register allocator for BackCmd IR
--
-- Operates on a flat BackCmd list.  Computes live intervals,
-- allocates physical x64 registers, inserts spill code.
--
-- Register pool (System V AMD64):
--   Caller-saved (preferred, no save/restore in prologue):
--     0=rax  1=rcx  2=rdx  6=rsi  7=rdi  8=r8  9=r9  10=r10  11=r11
--   Callee-saved (require push/pop in prologue/epilogue):
--     3=rbx  5=rbp  12=r12  13=r13  14=r14  15=r15
--   Reserved:
--     4=rsp (stack pointer)

local bit = require("bit")

local regalloc = {}

local function id_key(val)
    return type(val) == "string" and val or (val and val.text) or nil
end

-- ── register sets ─────────────────────────────────────────────────────

-- r10/r11 are kept as scratch temporaries by isel (not allocatable).
local CALLER_SAVED = {0, 1, 2, 6, 7, 8, 9}
local CALLEE_SAVED = {3, 12, 13, 14, 15}  -- rbp(5) handled specially

-- All allocatable registers in allocation preference order
-- (caller-saved first, then callee-saved)
local ALL_REGS = {}
do
    for _, r in ipairs(CALLER_SAVED) do ALL_REGS[#ALL_REGS + 1] = r end
    for _, r in ipairs(CALLEE_SAVED) do ALL_REGS[#ALL_REGS + 1] = r end
end

local NUM_REGS = #ALL_REGS

-- Physical register number → index in ALL_REGS (for bitmask operations)
local REG_TO_IDX = {}
for idx, r in ipairs(ALL_REGS) do
    REG_TO_IDX[r] = idx
end

-- Bitmask of all registers
local ALL_MASK = bit.lshift(1, NUM_REGS) - 1

-- ── value id extraction from BackCmd ──────────────────────────────────

-- Returns a list of value id texts used by a command
local cmd_uses

-- Returns the value id text defined by a command (or nil)
local cmd_def

-- ── liveness analysis ─────────────────────────────────────────────────

-- Returns intervals: val_id_text → {first_cmd_idx, last_cmd_idx}
local function compute_intervals(cmds)
    local intervals = {}  -- val_id → {first, last}

    for i, cmd in ipairs(cmds) do
        -- collect uses
        for _, val_id in ipairs(cmd_uses(cmd)) do
            local key = id_key(val_id)
            if intervals[key] then
                intervals[key].last = math.max(intervals[key].last, i)
            else
                intervals[key] = {first = i, last = i}
            end
        end

        -- collect def
        local dst = cmd_def(cmd)
        if dst then
            local key = id_key(dst)
            if intervals[key] then
                -- defined after first use means use-before-def (block param, alias)
                -- extend the interval backward
                intervals[key].first = math.min(intervals[key].first, i)
                intervals[key].last  = math.max(intervals[key].last, i)
            else
                intervals[key] = {first = i, last = i}
            end
        end

        -- BindEntryParams defines multiple values at function entry.
        if cmd.kind == "CmdBindEntryParams" then
            for _, val_id in ipairs(cmd.values or {}) do
                local key = id_key(val_id)
                if key then
                    if intervals[key] then
                        intervals[key].first = math.min(intervals[key].first, i)
                        intervals[key].last  = math.max(intervals[key].last, i)
                    else
                        intervals[key] = { first = i, last = i }
                    end
                end
            end
        end
    end

    -- Conservative loop handling for linearized CFG:
    -- if we have a backward edge, any value live at the loop header must
    -- remain live through the end of the tape, otherwise linear scan may
    -- incorrectly reuse its register across iterations.
    local block_pos = {}
    for i, cmd in ipairs(cmds) do
        if cmd.kind == "CmdSwitchToBlock" then
            local bk = id_key(cmd.block)
            if bk and not block_pos[bk] then block_pos[bk] = i end
        end
    end

    local function extend_live_at(header_pos)
        local tail = #cmds
        for _, iv in pairs(intervals) do
            if iv.first <= header_pos and iv.last >= header_pos then
                iv.last = math.max(iv.last, tail)
            end
        end
    end

    for i, cmd in ipairs(cmds) do
        if cmd.kind == "CmdJump" then
            local dest_pos = block_pos[id_key(cmd.dest)]
            if dest_pos and dest_pos <= i then
                extend_live_at(dest_pos)
            end
        elseif cmd.kind == "CmdBrIf" then
            local tpos = block_pos[id_key(cmd.then_block)]
            local epos = block_pos[id_key(cmd.else_block)]
            if tpos and tpos <= i then extend_live_at(tpos) end
            if epos and epos <= i then extend_live_at(epos) end
        elseif cmd.kind == "CmdSwitchInt" then
            local dpos = block_pos[id_key(cmd.default_dest)]
            if dpos and dpos <= i then extend_live_at(dpos) end
            for _, cs in ipairs(cmd.cases or {}) do
                local cpos = block_pos[id_key(cs.dest)]
                if cpos and cpos <= i then extend_live_at(cpos) end
            end
        end
    end

    return intervals
end

-- ── value id extraction from BackCmd ──────────────────────────────────

-- Returns a list of value id texts used by a command
cmd_uses = function(cmd)
    local uses = {}

    local function add(id)
        if id then uses[#uses + 1] = id end
    end

    local function add_addr_base(base)
        if not base or type(base) ~= "table" then return end
        if base.kind == "BackAddrValue" then add(base.value) end
    end

    local kind = cmd.kind
    if kind == "CmdAlias"         then add(cmd.src)
    elseif kind == "CmdUnary"     then add(cmd.value)
    elseif kind == "CmdCompare"   then add(cmd.lhs); add(cmd.rhs)
    elseif kind == "CmdCast"      then add(cmd.value)
    elseif kind == "CmdIntBinary" then add(cmd.lhs); add(cmd.rhs)
    elseif kind == "CmdBitBinary" then add(cmd.lhs); add(cmd.rhs)
    elseif kind == "CmdBitNot"    then add(cmd.value)
    elseif kind == "CmdShift"     then add(cmd.lhs); add(cmd.rhs)
    elseif kind == "CmdRotate"    then add(cmd.lhs); add(cmd.rhs)
    elseif kind == "CmdFloatBinary" then add(cmd.lhs); add(cmd.rhs)
    elseif kind == "CmdSelect"    then add(cmd.cond); add(cmd.then_value); add(cmd.else_value)
    elseif kind == "CmdFma"       then add(cmd.a); add(cmd.b); add(cmd.c)
    elseif kind == "CmdLoadInfo"  then add_addr_base(cmd.addr and cmd.addr.base); add(cmd.addr and cmd.addr.byte_offset)
    elseif kind == "CmdStoreInfo" then add_addr_base(cmd.addr and cmd.addr.base); add(cmd.addr and cmd.addr.byte_offset); add(cmd.value)
    elseif kind == "CmdPtrOffset" then add(cmd.index); add_addr_base(cmd.base)
    elseif kind == "CmdMemcpy"    then add(cmd.dst); add(cmd.src); add(cmd.len)
    elseif kind == "CmdMemset"    then add(cmd.dst); add(cmd.byte); add(cmd.len)
    elseif kind == "CmdBrIf"      then add(cmd.cond)
    elseif kind == "CmdReturnValue" then add(cmd.value)
    elseif kind == "CmdJump"      then
        for _, arg in ipairs(cmd.args or {}) do add(arg) end
    elseif kind == "CmdCall" then
        for _, arg in ipairs(cmd.args or {}) do add(arg) end
        if cmd.target and cmd.target.kind == "BackCallIndirect" then add(cmd.target.callee) end
        if cmd.result and cmd.result.kind == "BackCallValue" then
            -- result dst is a def, not a use
        end
    elseif kind == "CmdSwitchInt" then add(cmd.value)
    elseif kind == "CmdVecSplat"  then add(cmd.value)
    elseif kind == "CmdVecBinary" then add(cmd.lhs); add(cmd.rhs)
    elseif kind == "CmdVecCompare" then add(cmd.lhs); add(cmd.rhs)
    elseif kind == "CmdVecSelect" then add(cmd.mask); add(cmd.then_value); add(cmd.else_value)
    elseif kind == "CmdVecMask" then
        for _, arg in ipairs(cmd.args or {}) do add(arg) end
    elseif kind == "CmdVecInsertLane" then add(cmd.value); add(cmd.lane_value)
    elseif kind == "CmdVecExtractLane" then add(cmd.value)
    elseif kind == "CmdVecLoadInfo" then add(cmd.addr.byte_offset)
    elseif kind == "CmdVecStoreInfo" then add(cmd.addr.byte_offset); add(cmd.value)
    elseif kind == "CmdIntrinsic" then
        for _, arg in ipairs(cmd.args or {}) do add(arg) end
    elseif kind == "CmdStackAddr" then
        -- stack slot, no value use
    elseif kind == "CmdDataAddr" or kind == "CmdFuncAddr" or kind == "CmdExternAddr" then
        -- no value uses (addresses are data/func ids)
    elseif kind == "CmdBindEntryParams" then
        -- these are defs, passed as block params
    elseif kind == "CmdAppendBlockParam" then
        -- def
    end

    return uses
end

-- Returns the value id text defined by a command (or nil)
cmd_def = function(cmd)
    local kind = cmd.kind
    if kind == "CmdConst"    then return cmd.dst
    elseif kind == "CmdAlias" then return cmd.dst
    elseif kind == "CmdUnary" then return cmd.dst
    elseif kind == "CmdCompare" then return cmd.dst
    elseif kind == "CmdCast" then return cmd.dst
    elseif kind == "CmdIntBinary" then return cmd.dst
    elseif kind == "CmdBitBinary" then return cmd.dst
    elseif kind == "CmdBitNot" then return cmd.dst
    elseif kind == "CmdShift" then return cmd.dst
    elseif kind == "CmdRotate" then return cmd.dst
    elseif kind == "CmdFloatBinary" then return cmd.dst
    elseif kind == "CmdSelect" then return cmd.dst
    elseif kind == "CmdFma" then return cmd.dst
    elseif kind == "CmdLoadInfo" then return cmd.dst
    elseif kind == "CmdPtrOffset" then return cmd.dst
    elseif kind == "CmdDataAddr" then return cmd.dst
    elseif kind == "CmdFuncAddr" then return cmd.dst
    elseif kind == "CmdExternAddr" then return cmd.dst
    elseif kind == "CmdStackAddr" then return cmd.dst
    elseif kind == "CmdVecSplat" then return cmd.dst
    elseif kind == "CmdVecBinary" then return cmd.dst
    elseif kind == "CmdVecCompare" then return cmd.dst
    elseif kind == "CmdVecSelect" then return cmd.dst
    elseif kind == "CmdVecMask" then return cmd.dst
    elseif kind == "CmdVecInsertLane" then return cmd.dst
    elseif kind == "CmdVecExtractLane" then return cmd.dst
    elseif kind == "CmdVecLoadInfo" then return cmd.dst
    elseif kind == "CmdIntrinsic" then return cmd.dst
    elseif kind == "CmdCall" then
        if cmd.result and cmd.result.kind == "BackCallValue" then
            return cmd.result.dst
        end
    elseif kind == "CmdBindEntryParams" then
        -- returns the list of val ids bound as params
        return nil  -- multiple defs, handled separately
    elseif kind == "CmdAppendBlockParam" then
        return cmd.value
    end
    return nil
end

-- ── linear scan allocation ────────────────────────────────────────────

-- Returns:
--   regmap: val_id_text → physical_register_number (0-15)
--   spilled: val_id_text → spill_slot_offset
--   used_callee_saved: set of physical register numbers that need save/restore
--   spill_slots_needed: total bytes of spill area needed

function regalloc.allocate(cmds)
    local intervals = compute_intervals(cmds)

    -- Build sorted interval list by start position
    local sorted = {}
    for key, interval in pairs(intervals) do
        interval.key = key
        sorted[#sorted + 1] = interval
    end
    table.sort(sorted, function(a, b) return a.first < b.first end)

    -- Allocation state
    local free_mask = ALL_MASK
    local regmap = {}    -- key → physical register
    local spilled = {}   -- key → spill slot offset
    local active = {}    -- currently live intervals, sorted by last (ascending)
    local used_callee_saved = {}
    local next_spill_offset = 0

    local function alloc_reg(key, at_cmd_idx)
        local interval = intervals[key]
        if not interval then
            -- Value has no interval (shouldn't happen for normal uses).
            -- Assign a temporary spill slot to avoid crashes.
            spilled[key] = next_spill_offset
            next_spill_offset = next_spill_offset + 8
            return nil
        end

        if free_mask == 0 then
            -- No free registers: spill the interval with farthest endpoint
            if #active == 0 then return nil end
            local victim = active[#active]
            active[#active] = nil
            local victim_reg = victim.reg
            spilled[victim.key] = next_spill_offset
            next_spill_offset = next_spill_offset + 8
            regmap[victim.key] = nil
            -- victim_reg is now free; allocate it to the new interval
            regmap[key] = victim_reg
            interval.reg = victim_reg
            interval.spilled = true
            return victim_reg
        end

        -- Take the lowest-numbered free register
        local idx = 0
        local m = free_mask
        while bit.band(m, 1) == 0 do
            m = bit.rshift(m, 1)
            idx = idx + 1
        end
        local reg = ALL_REGS[idx + 1]
        free_mask = bit.band(free_mask, bit.bnot(bit.lshift(1, idx)))
        regmap[key] = reg

        -- Track callee-saved usage
        for _, cs in ipairs(CALLEE_SAVED) do
            if reg == cs then
                used_callee_saved[reg] = true
            end
        end

        -- Mark as active
        interval.reg = reg
        return reg
    end

    local function free_reg(reg)
        local idx = REG_TO_IDX[reg]
        if idx then
            free_mask = bit.bor(free_mask, bit.lshift(1, idx - 1))
        end
    end

    -- Expire intervals whose last use is before current_cmd_idx
    local function expire(limit)
        -- active is sorted by `.last`. Remove from front.
        local kept = {}
        for _, interval in ipairs(active) do
            if interval.last < limit then
                -- Interval ended
                if interval.reg then
                    free_reg(interval.reg)
                end
            else
                kept[#kept + 1] = interval
            end
        end
        active = kept
    end

    -- Insert interval into active, maintaining sort by `.last`
    local function insert_active(interval)
        local pos = 1
        while pos <= #active and active[pos].last < interval.last do
            pos = pos + 1
        end
        table.insert(active, pos, interval)
    end

    -- Pass: linear scan
    for i, cmd in ipairs(cmds) do
        expire(i)

        -- Ensure operands have registers
        for _, val_id in ipairs(cmd_uses(cmd)) do
            local key = id_key(val_id)
            if key and intervals[key] and not regmap[key] and not spilled[key] then
                -- This value is used here but hasn't been allocated yet.
                -- It must be a block parameter or an entry parameter —
                -- allocation happens at BindEntryParams / AppendBlockParam.
                alloc_reg(key, i)
                if regmap[key] then
                    insert_active(intervals[key])
                end
            end
        end

        -- Allocate destination register
        local dst = cmd_def(cmd)
        if dst then
            local key = id_key(dst)
            if key and not regmap[key] and not spilled[key] then
                alloc_reg(key, i)
                if regmap[key] then
                    insert_active(intervals[key])
                end
            end
        end

        -- Handle BindEntryParams: allocate for each bound value
        if cmd.kind == "CmdBindEntryParams" then
            for _, val_id in ipairs(cmd.values or {}) do
                local key = id_key(val_id)
                if key and not regmap[key] and not spilled[key] then
                    alloc_reg(key, i)
                    if regmap[key] then
                        insert_active(intervals[key])
                    end
                end
            end
        end
    end

    -- Determine spill area size (16-byte aligned)
    local spill_area = next_spill_offset
    if spill_area % 16 ~= 0 then
        spill_area = spill_area + (16 - (spill_area % 16))
    end

    return regmap, spilled, used_callee_saved, spill_area
end

-- ── spill code insertion ──────────────────────────────────────────────

-- Given the original cmds and the spilled map, produces a new cmds list
-- with LoadInfo inserted before uses of spilled values and StoreInfo
-- inserted after definitions of spilled values.
--
-- Note: this requires creating new BackValIds for the temporaries and
-- new BackAccessIds / BackMemoryInfo for the loads/stores.
-- For simplicity, we use the stack slot offset as the address (stack_addr
-- of the function's frame), and the spilled value's id as the temp val.

function regalloc.insert_spills(cmds, spilled)
    -- This is intentionally a separate pass for clarity.
    -- For now, we return cmds unchanged and let the isel handle
    -- spills via separate load/store around uses/defs.
    -- Full spill insertion will be added when needed by test failures.
    return cmds
end

return regalloc
