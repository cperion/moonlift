-- encode_x64.lua — x64 action-list builder over dasm_x86.lua

local debug = require("debug")
local bit   = require("bit")
_G.bit = bit

-- dasm_x86.lua reads the global 'x64' to decide 32/64-bit mode.
_G.x64 = true

package.path = package.path .. ";.vendor/LuaJIT/dynasm/?.lua"
local dasm_x86 = require("dasm_x86")

local encode = {}

-- ── hook into dasm_x86 ────────────────────────────────────────────────

local fragments   = {}
local base_offset = 0   -- actlist position at the start of this init()
local actlist
local wflush_fn
local map_global_ref
local map_op, map_def

local function wline_capture(text)
    local off_str, args_str = text:match("dasm_put%(Dst, (%d+),?%s*(.-)%)%;")
    if not off_str then return end
    local abs_offset = tonumber(off_str)
    local args = {}
    if args_str and args_str:match("%S") then
        for a in args_str:gmatch("[^,]+") do
            a = a:match("^%s*(.-)%s*$")
            args[#args + 1] = tonumber(a) or a
        end
    end
    local blist = {}
    for i = abs_offset + 1, #actlist do blist[#blist + 1] = actlist[i] end
    if #blist > 0 then
        fragments[#fragments + 1] = {
            offset = abs_offset - base_offset, -- relative to this compile's action buffer
            args   = args,
            bytes  = string.char(unpack(blist)),
        }
    end
end

local function werr(msg) error("dasm_x86: " .. msg, 0) end
local function wfatal(msg) error("dasm_x86 fatal: " .. msg, 0) end
local function wwarn(msg) io.stderr:write("dasm_x86 warning: " .. msg .. "\n") end

local function locate_map_global()
    local map_op_local = dasm_x86.mergemaps({}, {})
    local label_fn = map_op_local[".label_1"]
    if not label_fn then return nil end
    local _, parseop = debug.getupvalue(label_fn, 4)   -- parseoperand
    if not parseop then return nil end
    local _, immexpr = debug.getupvalue(parseop, 18)   -- immexpr
    if not immexpr then return nil end
    local _, map_global = debug.getupvalue(immexpr, 3)
    return map_global
end

function encode.init()
    if wflush_fn then wflush_fn(false) end

    dasm_x86.setup("x64", {comment = false, cpp = false, maccomment = false})
    wflush_fn = dasm_x86.passcb(wline_capture, werr, wfatal, wwarn)

    -- 1) locate action-list internals
    actlist = nil
    local dedupechunk
    for i = 1, 10 do
        local n, v = debug.getupvalue(wflush_fn, i)
        if not n then break end
        if n == "actlist"     then actlist = v end
        if n == "dedupechunk" then dedupechunk = v end
    end
    if not actlist     then error("encode_x64: cannot find actlist upvalue") end
    if not dedupechunk then error("encode_x64: cannot find dedupechunk upvalue") end

    -- reset dedupe cache so per-compile offsets stay valid
    for i = 1, 10 do
        local n = debug.getupvalue(dedupechunk, i)
        if not n then break end
        if n == "actstr" then
            debug.setupvalue(dedupechunk, i, "")
            break
        end
    end

    -- 2) reset global-label allocator + keep map reference for compile.lua
    map_global_ref = locate_map_global()
    if map_global_ref then
        for k in pairs(map_global_ref) do map_global_ref[k] = nil end
        local mt = getmetatable(map_global_ref)
        local mt_idx = mt and mt.__index
        if mt_idx then
            for i = 1, 10 do
                local n = debug.getupvalue(mt_idx, i)
                if not n then break end
                if n == "next_global" then
                    debug.setupvalue(mt_idx, i, 10)
                    break
                end
            end
        end
    end

    -- force fresh maps after reset
    map_op, map_def = nil, nil

    base_offset = #actlist
    fragments = {}
end

-- ── opcode map ────────────────────────────────────────────────────────

function encode.get_opcode_map()
    if not map_op then map_op, map_def = dasm_x86.mergemaps({}, {}) end
    return map_op, map_def
end

-- ── emit ──────────────────────────────────────────────────────────────

function encode.emit(op_name, ...)
    local mo = encode.get_opcode_map()
    local tmpl = mo[op_name]
    if not tmpl then error("encode_x64: unknown opcode '" .. op_name .. "'") end

    local n = select("#", ...)
    local params = {}
    for i = 1, n do
        local p = tostring(select(i, ...))
        local defs = select(2, encode.get_opcode_map())
        p = p:gsub("[%w_]+", function(w)
            local s = defs[w]
            return s or w
        end)
        params[i] = p
    end
    params.op = op_name

    if type(tmpl) == "string" then
        mo[".template__"](params, tmpl, n)
    else
        tmpl(params)
    end
end

function encode.flush()
    wflush_fn(false)
end

function encode.take_fragments()
    local r = fragments
    fragments = {}
    return r
end

function encode.global_bindings()
    local out = {}
    if not map_global_ref then return out end
    for name, idx in pairs(map_global_ref) do out[name] = idx end
    return out
end

function encode.global_index(name)
    if not map_global_ref then return nil end
    return rawget(map_global_ref, name)
end

-- ── register names ────────────────────────────────────────────────────

function encode.reg(reg, sz)
    sz = sz or "q"
    if sz == "q" then
        local n = {"rax","rcx","rdx","rbx","rsp","rbp","rsi","rdi",
                   "r8","r9","r10","r11","r12","r13","r14","r15"}
        return n[reg + 1] or ("r" .. tostring(reg))
    elseif sz == "d" then
        local n = {"eax","ecx","edx","ebx","esp","ebp","esi","edi",
                   "r8d","r9d","r10d","r11d","r12d","r13d","r14d","r15d"}
        return n[reg + 1] or ("r" .. tostring(reg) .. "d")
    elseif sz == "w" then
        local n = {"ax","cx","dx","bx","sp","bp","si","di",
                   "r8w","r9w","r10w","r11w","r12w","r13w","r14w","r15w"}
        return n[reg + 1] or ("r" .. tostring(reg) .. "w")
    elseif sz == "b" then
        if reg <= 15 then return "r" .. tostring(reg) .. "b" end
        return "r" .. tostring(reg) .. "b"
    elseif sz == "x" then
        local n = {
            "xmm0","xmm1","xmm2","xmm3","xmm4","xmm5","xmm6","xmm7",
            "xmm8","xmm9","xmm10","xmm11","xmm12","xmm13","xmm14","xmm15",
        }
        return n[reg + 1] or ("xmm" .. tostring(reg))
    end
    return "r" .. tostring(reg)
end

function encode.imm(v)
    return tostring(math.floor(tonumber(v) or 0))
end

-- label helpers: use dasm_x86's native ->name / >N / <N syntax
function encode.label_def(name)
    encode.emit(".label_1", name)
end

function encode.label_ref(name)
    return name
end

function encode.mem(base, idx, scale, disp)
    local s = "[" .. encode.reg(base, "q")
    if idx then
        s = s .. "+" .. encode.reg(idx, "q")
        if scale and scale > 1 then s = s .. "*" .. tostring(scale) end
    end
    if disp and disp ~= 0 and not idx then
        s = s .. (disp >= 0 and "+" or "") .. tostring(disp)
    end
    return s .. "]"
end

return encode
