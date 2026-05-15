package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local T = pvm.context()
A.Define(T)
local B = T.MoonBack
local C = T.MoonCore

local Tape = require("moonlift.back_command_tape").Define(T)
local Binary = require("moonlift.back_command_binary").Define(T)

ffi.cdef [[
typedef struct moonlift_jit_t moonlift_jit_t;
typedef struct moonlift_artifact_t moonlift_artifact_t;
moonlift_jit_t* moonlift_jit_new(void);
void moonlift_jit_free(moonlift_jit_t*);
moonlift_artifact_t* moonlift_jit_compile_tape(moonlift_jit_t*, const char*);
moonlift_artifact_t* moonlift_jit_compile_binary(moonlift_jit_t*, const uint8_t*, size_t);
void moonlift_artifact_free(moonlift_artifact_t*);
]]

local lib = ffi.load("./target/release/libmoonlift.so")

-- Build a realistic program: 20 blocks, each with arithmetic and control
local function build_program()
    local sig = B.BackSigId("sig")
    local func = B.BackFuncId("f")
    local cmds = {
        B.CmdCreateSig(sig, { B.BackI32, B.BackI32 }, { B.BackI32 }),
        B.CmdDeclareFunc(C.VisibilityExport, func, sig),
        B.CmdBeginFunc(func),
    }
    for i = 1, 20 do
        local b = B.BackBlockId("b"..i)
        cmds[#cmds+1] = B.CmdCreateBlock(b)
        cmds[#cmds+1] = B.CmdSwitchToBlock(b)
        local a = B.BackValId("a"..i)
        local bv = B.BackValId("b"..i)
        local r = B.BackValId("r"..i)
        cmds[#cmds+1] = B.CmdConst(a, B.BackI32, B.BackLitInt(tostring(i*10)))
        cmds[#cmds+1] = B.CmdConst(bv, B.BackI32, B.BackLitInt(tostring(i)))
        cmds[#cmds+1] = B.CmdIntBinary(r, B.BackIntAdd, B.BackI32,
            B.BackIntSemantics(B.BackIntWrap, B.BackIntMayLose), a, bv)
        if i % 2 == 0 then
            cmds[#cmds+1] = B.CmdReturnValue(r)
        end
    end
    cmds[#cmds+1] = B.CmdFinishFunc(func)
    cmds[#cmds+1] = B.CmdFinalizeModule
    return B.BackProgram(cmds)
end

local program = build_program()
local ncmds = #program.cmds

local TEXT_TRIALS = 2000
local BIN_TRIALS = 2000

-- warmup
do
    local jit = lib.moonlift_jit_new()
    local enc = Tape.encode(program)
    local cstr = ffi.new("char[?]", #enc.payload + 1, enc.payload)
    local art = lib.moonlift_jit_compile_tape(jit, cstr)
    lib.moonlift_artifact_free(art)
    lib.moonlift_jit_free(jit)
end
do
    local jit = lib.moonlift_jit_new()
    local enc = Binary.encode(program)
    local buf = ffi.new("uint8_t[?]", #enc)
    ffi.copy(buf, enc, #enc)
    local art = lib.moonlift_jit_compile_binary(jit, buf, #enc)
    lib.moonlift_artifact_free(art)
    lib.moonlift_jit_free(jit)
end

collectgarbage()

-- Text
local t0 = os.clock()
for _ = 1, TEXT_TRIALS do
    local jit = lib.moonlift_jit_new()
    local enc = Tape.encode(program)
    local cstr = ffi.new("char[?]", #enc.payload + 1, enc.payload)
    local art = lib.moonlift_jit_compile_tape(jit, cstr)
    lib.moonlift_artifact_free(art)
    lib.moonlift_jit_free(jit)
end
local t_text = os.clock() - t0

collectgarbage()

-- Binary
local t0 = os.clock()
for _ = 1, BIN_TRIALS do
    local jit = lib.moonlift_jit_new()
    local enc = Binary.encode(program)
    local buf = ffi.new("uint8_t[?]", #enc)
    ffi.copy(buf, enc, #enc)
    local art = lib.moonlift_jit_compile_binary(jit, buf, #enc)
    lib.moonlift_artifact_free(art)
    lib.moonlift_jit_free(jit)
end
local t_bin = os.clock() - t0

print(string.format("Program: %d commands", ncmds))
print(string.format("Text tape:   %d bytes", #Tape.encode(program).payload))
print(string.format("Binary:      %d bytes (%.1f%%)", #Binary.encode(program),
    100 * #Binary.encode(program) / #Tape.encode(program).payload))
print()
print(string.format("Text:   %d trials in %.3fs = %.2f ms/trial", TEXT_TRIALS, t_text, 1000*t_text/TEXT_TRIALS))
print(string.format("Binary: %d trials in %.3fs = %.2f ms/trial", BIN_TRIALS, t_bin, 1000*t_bin/BIN_TRIALS))
print(string.format("Speedup: %.2fx", t_text / t_bin))
