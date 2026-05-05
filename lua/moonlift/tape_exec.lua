-- tape_exec.lua — Execute encoded tape via gen/param/ctrl triplet
-- Table dispatch for O(1) per instruction. Tracer hoists the lookup.

local ffi = require("ffi")
local M = {}

local TAG do
    local T = {
        CONST_INT=1,CONST_FLT=2,CONST_BOOL=3,CONST_NULL=4,
        IADD=10,ISUB=11,IMUL=12,SDIV=13,UDIV=14,SREM=15,UREM=16,
        BAND=20,BOR=21,BXOR=22,BNOT=23,ISHL=24,SSHR=25,USHR=26,ROTL=27,ROTR=28,
        FADD=30,FSUB=31,FMUL=32,FDIV=33,
        ICMP_EQ=40,ICMP_NE=41,SCMP_LT=42,SCMP_LE=43,SCMP_GT=44,SCMP_GE=45,
        UCMP_LT=46,UCMP_LE=47,UCMP_GT=48,UCMP_GE=49,
        FCMP_EQ=50,FCMP_NE=51,FCMP_LT=52,FCMP_LE=53,FCMP_GT=54,FCMP_GE=55,
        BITCAST=60,IREDUCE=61,SEXTEND=62,UEXTEND=63,FPROMOTE=64,FDEMOTE=65,
        STOF=66,UTOF=67,FTOS=68,FTOU=69,
        INEG=70,FNEG=71,BOOLNOT=72,
        POPCOUNT=80,CLZ=81,CTZ=82,BSWAP=83,SQRT=84,
        ABS_I=85,ABS_F=86,FLOOR=87,CEIL=88,TRUNC=89,ROUND=90,
        JUMP=100,BR_IF=101,SWITCH=102,RET_VOID=103,RET_VAL=104,TRAP=105,
        LOAD=110,STORE=111,PTR_OFFSET=112,MEMCPY=113,MEMSET=114,
        STACK_ADDR=120,
        CALL_DIR=130,CALL_EXT=131,CALL_IND=132,
        CALL_DIR_V=133,CALL_EXT_V=134,CALL_IND_V=135,
        ALIAS=140,SELECT_=150,FMA=151,BLOCK_ARG=160,NARROW=161,
    }
    TAG = T
end

local ct = {
    [1]={[true]="int8_t",[false]="uint8_t"},
    [2]={[true]="int16_t",[false]="uint16_t"},
    [4]={[true]="int32_t",[false]="uint32_t"},
    [8]={[true]="int64_t",[false]="uint64_t"},
}

local function make_gen(tape, slot_infos)
    -- Build dispatch table for O(1) instruction lookup
    local handlers = {}

    handlers[TAG.CONST_INT]  = function(_, regs, cmd) regs[cmd[2]] = tonumber(cmd[3]) end
    handlers[TAG.CONST_FLT]  = function(_, regs, cmd) regs[cmd[2]] = tonumber(cmd[3]) end
    handlers[TAG.CONST_BOOL] = function(_, regs, cmd) regs[cmd[2]] = cmd[3] ~= 0 end
    handlers[TAG.CONST_NULL] = function(_, regs, cmd) regs[cmd[2]] = nil end

    handlers[TAG.IADD] = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] + regs[cmd[4]] end
    handlers[TAG.ISUB] = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] - regs[cmd[4]] end
    handlers[TAG.IMUL] = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] * regs[cmd[4]] end
    handlers[TAG.SDIV] = function(_, regs, cmd) regs[cmd[2]] = math.floor(regs[cmd[3]] / regs[cmd[4]]) end
    handlers[TAG.UDIV] = function(_, regs, cmd) regs[cmd[2]] = math.floor(math.abs(regs[cmd[3]]) / math.abs(regs[cmd[4]])) end
    handlers[TAG.SREM] = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] % regs[cmd[4]] end
    handlers[TAG.UREM] = function(_, regs, cmd) regs[cmd[2]] = math.abs(regs[cmd[3]]) % math.abs(regs[cmd[4]]) end

    handlers[TAG.BAND] = function(_, regs, cmd) regs[cmd[2]] = bit.band(regs[cmd[3]], regs[cmd[4]]) end
    handlers[TAG.BOR]  = function(_, regs, cmd) regs[cmd[2]] = bit.bor(regs[cmd[3]], regs[cmd[4]]) end
    handlers[TAG.BXOR] = function(_, regs, cmd) regs[cmd[2]] = bit.bxor(regs[cmd[3]], regs[cmd[4]]) end
    handlers[TAG.BNOT] = function(_, regs, cmd) regs[cmd[2]] = bit.bnot(regs[cmd[3]]) end
    handlers[TAG.ISHL] = function(_, regs, cmd) regs[cmd[2]] = bit.lshift(regs[cmd[3]], regs[cmd[4]]) end
    handlers[TAG.SSHR] = function(_, regs, cmd) regs[cmd[2]] = bit.arshift(regs[cmd[3]], regs[cmd[4]]) end
    handlers[TAG.USHR] = function(_, regs, cmd) regs[cmd[2]] = bit.rshift(regs[cmd[3]], regs[cmd[4]]) end
    handlers[TAG.ROTL] = function(_, regs, cmd) local l=regs[cmd[3]]; local r=regs[cmd[4]]; regs[cmd[2]] = bit.bor(bit.lshift(l,r), bit.rshift(l,32-r)) end
    handlers[TAG.ROTR] = function(_, regs, cmd) local l=regs[cmd[3]]; local r=regs[cmd[4]]; regs[cmd[2]] = bit.bor(bit.rshift(l,r), bit.lshift(l,32-r)) end

    handlers[TAG.FADD]  = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] + regs[cmd[4]] end
    handlers[TAG.FSUB]  = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] - regs[cmd[4]] end
    handlers[TAG.FMUL]  = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] * regs[cmd[4]] end
    handlers[TAG.FDIV]  = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] / regs[cmd[4]] end

    handlers[TAG.ICMP_EQ] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] == regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.ICMP_NE] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] ~= regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.SCMP_LT] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] < regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.SCMP_LE] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] <= regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.SCMP_GT] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] > regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.SCMP_GE] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] >= regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.UCMP_LT] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] < regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.UCMP_LE] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] <= regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.UCMP_GT] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] > regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.UCMP_GE] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] >= regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.FCMP_EQ] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] == regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.FCMP_NE] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] ~= regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.FCMP_LT] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] < regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.FCMP_LE] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] <= regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.FCMP_GT] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] > regs[cmd[4]]) and 1 or 0 end
    handlers[TAG.FCMP_GE] = function(_, regs, cmd) regs[cmd[2]] = (regs[cmd[3]] >= regs[cmd[4]]) and 1 or 0 end

    handlers[TAG.BITCAST] = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] end
    handlers[TAG.IREDUCE] = function(_, regs, cmd) regs[cmd[2]] = bit.band(regs[cmd[3]], cmd[4]) end
    handlers[TAG.SEXTEND] = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] end
    handlers[TAG.UEXTEND] = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] end
    handlers[TAG.FPROMOTE] = function(_, regs, cmd) regs[cmd[2]] = tonumber(regs[cmd[3]]) end
    handlers[TAG.FDEMOTE]  = function(_, regs, cmd) regs[cmd[2]] = tonumber(regs[cmd[3]]) end
    handlers[TAG.STOF] = function(_, regs, cmd) regs[cmd[2]] = tonumber(regs[cmd[3]]) end
    handlers[TAG.UTOF] = function(_, regs, cmd) regs[cmd[2]] = tonumber(regs[cmd[3]]) end
    handlers[TAG.FTOS] = function(_, regs, cmd) regs[cmd[2]] = math.floor(regs[cmd[3]]) end
    handlers[TAG.FTOU] = function(_, regs, cmd) regs[cmd[2]] = math.floor(math.abs(regs[cmd[3]])) end

    handlers[TAG.INEG]    = function(_, regs, cmd) regs[cmd[2]] = -regs[cmd[3]] end
    handlers[TAG.FNEG]    = function(_, regs, cmd) regs[cmd[2]] = -regs[cmd[3]] end
    handlers[TAG.BOOLNOT] = function(_, regs, cmd) regs[cmd[2]] = not regs[cmd[3]] and 1 or 0 end

    handlers[TAG.POPCOUNT] = function(_, regs, cmd) regs[cmd[2]] = bit.popc(regs[cmd[3]]) end
    handlers[TAG.CLZ]  = function(_, regs, cmd) regs[cmd[2]] = bit.clz32(bit.band(regs[cmd[3]], 0xFFFFFFFF)) end
    handlers[TAG.CTZ]  = function(_, regs, cmd) regs[cmd[2]] = bit.ctz(bit.band(regs[cmd[3]], 0xFFFFFFFF)) end
    handlers[TAG.BSWAP]= function(_, regs, cmd) regs[cmd[2]] = bit.bswap(regs[cmd[3]]) end
    handlers[TAG.SQRT] = function(_, regs, cmd) regs[cmd[2]] = math.sqrt(regs[cmd[3]]) end
    handlers[TAG.ABS_I]= function(_, regs, cmd) regs[cmd[2]] = math.abs(regs[cmd[3]]) end
    handlers[TAG.ABS_F]= function(_, regs, cmd) regs[cmd[2]] = math.abs(regs[cmd[3]]) end
    handlers[TAG.FLOOR]= function(_, regs, cmd) regs[cmd[2]] = math.floor(regs[cmd[3]]) end
    handlers[TAG.CEIL] = function(_, regs, cmd) regs[cmd[2]] = math.ceil(regs[cmd[3]]) end
    handlers[TAG.TRUNC]= function(_, regs, cmd) local i = math.modf(regs[cmd[3]]); regs[cmd[2]] = i end
    handlers[TAG.ROUND]= function(_, regs, cmd) regs[cmd[2]] = math.floor(regs[cmd[3]] + 0.5) end

    -- Control flow: return next PC (or nil for halt)
    handlers[TAG.JUMP]    = function(_, _, cmd) return cmd[2] end
    handlers[TAG.BR_IF]   = function(_, regs, cmd) return regs[cmd[2]] ~= 0 and cmd[3] or cmd[4] end
    handlers[TAG.SWITCH]  = function(_, regs, cmd) local v=regs[cmd[2]]; local t=cmd[3][tostring(v)]; return t or cmd[2] end
    handlers[TAG.RET_VOID]= function(m, _, _) m._result=nil; return false end
    handlers[TAG.RET_VAL] = function(m, regs, cmd) m._result=regs[cmd[2]]; return false end
    handlers[TAG.TRAP]    = function() error("trap") end

    -- Memory
    handlers[TAG.LOAD] = function(_, regs, cmd)
        local base=regs[cmd[3]]; local off=regs[cmd[4]]
        local esz=cmd[5]; local sig=cmd[6]~=0
        local ctbl=ct[esz]
        if ctbl and base then
            regs[cmd[2]] = ffi.cast(ctbl[sig].."*", ffi.cast("uint8_t*",base)+off)[0]
        else regs[cmd[2]]=0 end
    end
    handlers[TAG.STORE] = function(_, regs, cmd)
        local base=regs[cmd[2]]; local off=regs[cmd[3]]; local val=regs[cmd[4]]
        local esz=cmd[5]; local ctbl=ct[esz]
        if ctbl and base then ffi.cast(ctbl[true].."*", ffi.cast("uint8_t*",base)+off)[0]=val end
    end
    handlers[TAG.PTR_OFFSET] = function(_, regs, cmd)
        local base=regs[cmd[3]]; local idx=regs[cmd[4]]; local esz=cmd[5]; local co=cmd[6]
        if base then regs[cmd[2]] = ffi.cast("uint8_t*",base)+(idx*esz)+co else regs[cmd[2]]=nil end
    end
    handlers[TAG.MEMCPY] = function(_, regs, cmd) ffi.copy(regs[cmd[2]], regs[cmd[3]], regs[cmd[4]]) end
    handlers[TAG.MEMSET] = function(_, regs, cmd) ffi.fill(regs[cmd[2]], regs[cmd[3]], regs[cmd[4]]) end

    handlers[TAG.STACK_ADDR] = function(m, regs, cmd) regs[cmd[2]] = m.slots[cmd[3]] end

    -- Calls
    local function call_n(m, regs, cmd, n, has_result)
        local fn, dr = m.funcs[cmd[3]], cmd[2]
        local ra = regs
        if n == 0 then
            local r = fn()
            if has_result then regs[dr] = r end
        elseif n == 1 then
            local r = fn(ra[cmd[4][1]])
            if has_result then regs[dr] = r end
        elseif n == 2 then
            local r = fn(ra[cmd[4][1]], ra[cmd[4][2]])
            if has_result then regs[dr] = r end
        elseif n == 3 then
            local r = fn(ra[cmd[4][1]], ra[cmd[4][2]], ra[cmd[4][3]])
            if has_result then regs[dr] = r end
        else
            local a={}; for i=1,n do a[i]=ra[cmd[4][i]] end
            local r = fn(unpack(a))
            if has_result then regs[dr] = r end
        end
    end
    local function call_ext(m, regs, cmd, n, has_result)
        local fn, dr = m.externs[cmd[3]], cmd[2]
        local ra = regs
        if n == 0 then
            local r = fn(); if has_result then regs[dr] = r end
        elseif n == 1 then
            local r = fn(ra[cmd[4][1]]); if has_result then regs[dr] = r end
        elseif n == 2 then
            local r = fn(ra[cmd[4][1]], ra[cmd[4][2]]); if has_result then regs[dr] = r end
        elseif n == 3 then
            local r = fn(ra[cmd[4][1]], ra[cmd[4][2]], ra[cmd[4][3]]); if has_result then regs[dr] = r end
        else
            local a={}; for i=1,n do a[i]=ra[cmd[4][i]] end
            local r = fn(unpack(a)); if has_result then regs[dr] = r end
        end
    end
    local function call_ind(m, regs, cmd, n, has_result)
        local fp=regs[cmd[3]]; if not fp then return end
        local pt=cmd[5]; local rt=cmd[6]
        local a={}; for i=1,n do a[i]=regs[cmd[4][i]] end
        local sig_str=rt.."(*)"
        if #pt>0 then sig_str=sig_str.."("..table.concat(pt,",")..")" else sig_str=sig_str.."()" end
        local f=ffi.cast(sig_str,fp)
        local r=f(unpack(a))
        if has_result then regs[cmd[2]]=r end
    end

    handlers[TAG.CALL_DIR] = function(m, regs, cmd) call_n(m, regs, cmd, #cmd[4], true); return nil end
    handlers[TAG.CALL_DIR_V]= function(m, regs, cmd) call_n(m, regs, cmd, #cmd[4], false); return nil end
    handlers[TAG.CALL_EXT] = function(m, regs, cmd) call_ext(m, regs, cmd, #cmd[4], true); return nil end
    handlers[TAG.CALL_EXT_V]=function(m, regs, cmd) call_ext(m, regs, cmd, #cmd[4], false); return nil end
    handlers[TAG.CALL_IND] = function(m, regs, cmd) call_ind(m, regs, cmd, #cmd[4], true); return nil end
    handlers[TAG.CALL_IND_V]=function(m, regs, cmd) call_ind(m, regs, cmd, #cmd[4], false); return nil end

    handlers[TAG.ALIAS]     = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] end
    handlers[TAG.BLOCK_ARG] = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] end
    handlers[TAG.NARROW]    = function(_, regs, cmd) regs[cmd[2]] = bit.band(regs[cmd[2]], cmd[3]) end
    handlers[TAG.SELECT_]   = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] ~= 0 and regs[cmd[4]] or regs[cmd[5]] end
    handlers[TAG.FMA]       = function(_, regs, cmd) regs[cmd[2]] = regs[cmd[3]] * regs[cmd[4]] + regs[cmd[5]] end

    return function(machine, pc)
        if pc == nil then return nil end
        local regs = machine.regs
        local cmd = tape[pc]
        local handler = handlers[cmd[1]]
        if handler then
            local next_pc = handler(machine, regs, cmd)
            if next_pc == false then return nil end  -- halt
            return next_pc or (pc + 1)
        end
        return nil
    end
end

function M.make_module(encoded)
    local externs = {}
    for _, decl in pairs(encoded.externs) do
        local sym = decl.symbol
        externs[sym] = ffi.C[sym] or function(...) error("unresolved: " .. sym) end
    end

    local funcs = {}
    for fid, fb in pairs(encoded.funcs) do
        local tape = fb.tape
        local entry_pc = fb.entry_pc or 1
        local entry_params = fb.entry_params
        local slot_infos = {}

        local gen = make_gen(tape, slot_infos)

        local ep_regs = {}
        for i, pid in ipairs(entry_params) do
            ep_regs[i] = encoded.reg_map[pid] or i
        end

        funcs[fid] = function(...)
            local regs = {}
            for i, rid in ipairs(ep_regs) do regs[rid] = select(i, ...) end

            local machine = {
                regs = regs, funcs = funcs, externs = externs,
                slots = {}, _result = nil,
            }

            for sid, info in pairs(slot_infos) do
                machine.slots[sid] = ffi.new("uint8_t[?]", info.size)
            end

            for _ in gen, machine, entry_pc do end
            return machine._result
        end
    end

    local result = {}
    for fid, _ in pairs(encoded.exported or {}) do
        if funcs[fid] then result[fid] = funcs[fid] end
    end
    for fid, fn in pairs(funcs) do result[fid] = fn end
    return result
end

return M
