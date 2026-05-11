-- encode_x64.lua — x64 action-list builder over dasm_x86.lua
--
-- Hooks dasm_x86's passcb to capture action-list fragments.
-- Operands are dasm_x86 internal register names (@q0..@q15, @d0..@d15, etc.)
-- because parseoperand expects them after definesubst resolves external names.

local debug = require("debug")
local bit   = require("bit")
_G.bit = bit

-- dasm_x86.lua reads the global 'x64' to decide 32/64-bit mode.
-- dasm_x64.lua does exactly this: x64 = true; return require("dasm_x86")
_G.x64 = true

package.path = package.path .. ";.vendor/LuaJIT/dynasm/?.lua"
local dasm_x86 = require("dasm_x86")

local encode = {}

-- ── hook into dasm_x86 ────────────────────────────────────────────────

local fragments = {}
local actlist
local wflush_fn

local function wline_capture(text)
    local off_str, args_str = text:match("dasm_put%(Dst, (%d+),?%s*(.-)%)%;")
    if not off_str then return end
    local offset = tonumber(off_str)
    local args = {}
    if args_str and args_str:match("%S") then
        for a in args_str:gmatch("[^,]+") do
            a = a:match("^%s*(.-)%s*$")
            args[#args + 1] = tonumber(a) or a
        end
    end
    local blist = {}
    for i = offset + 1, #actlist do blist[#blist + 1] = actlist[i] end
    if #blist > 0 then
        fragments[#fragments + 1] = {
            offset = offset, args = args,
            bytes  = string.char(unpack(blist)),
        }
    end
end

local function werr(msg) error("dasm_x86: " .. msg, 0) end
local function wfatal(msg) error("dasm_x86 fatal: " .. msg, 0) end
local function wwarn(msg) io.stderr:write("dasm_x86 warning: " .. msg .. "\n") end

function encode.init()
    dasm_x86.setup("x64", {comment = false, cpp = false, maccomment = false})
    wflush_fn = dasm_x86.passcb(wline_capture, werr, wfatal, wwarn)
    for i = 1, 60 do
        local n, v = debug.getupvalue(wflush_fn, i)
        if not n then break end
        if n == "actlist" then actlist = v end
    end
    if not actlist then error("encode_x64: cannot extract actlist") end
    fragments = {}
end

-- ── opcode map ────────────────────────────────────────────────────────

local map_op, map_def
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
        -- Apply definesubst to each param: external names like "rbp"
        -- resolve to internal names via map_archdef (metatable of map_def).
        -- dasm_x86's parseoperand expects internal names (@q5, @d0, etc.)
        -- after definesubst has resolved externals.
        local p = select(i, ...)
        local defs = select(2, encode.get_opcode_map())  -- map_def
        -- Simple substitution: split into words and look up in map_def
        p = tostring(p):gsub("[%w_]+", function(w)
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
    local r = fragments; fragments = {}; return r
end

-- ── register names ────────────────────────────────────────────────────

-- register names: dasm_x86 understands external names after definesubst
-- resolves them via map_archdef.  Our encode.emit() does this automatically.
-- So we can use friendly names like "rax", "edx", "rbp", "rsp".

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
        local n = {"al","cl","dl","bl","ah","ch","dh","bh",
                   "r8b","r9b","r10b","r11b","r12b","r13b","r14b","r15b"}
        if reg <= 7 then return n[reg + 1] end
        return "r" .. tostring(reg) .. "b"
    end
    return "r" .. tostring(reg)
end

function encode.imm(v)
    return tostring(math.floor(tonumber(v) or 0))
end

-- label helpers: use dasm_x86's native ->name / >N / <N syntax
function encode.label_def(name)   -- "->add1" or "1"
    encode.emit(".label_1", name)
end

function encode.label_ref(name)   -- "->add1" or ">1" or "<1"
    return name
end

-- memory: "[base]" or "[base+idx]" or "[base+idx*s]" or "[base+disp]"
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
