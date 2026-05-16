package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

ffi.cdef[[
typedef struct MomWireBuilder { uint8_t *data; size_t len; size_t cap; int32_t string_count; int32_t aux_count; int32_t error; } MomWireBuilder;
typedef struct moonlift_jit_t moonlift_jit_t;
typedef struct moonlift_artifact_t moonlift_artifact_t;
const char* moonlift_last_error_message(void);
moonlift_jit_t* moonlift_jit_new(void);
void moonlift_jit_free(moonlift_jit_t*);
moonlift_artifact_t* moonlift_jit_compile_binary(moonlift_jit_t*, const uint8_t* data, size_t len);
void moonlift_artifact_free(moonlift_artifact_t*);
const void* moonlift_artifact_getpointer(const moonlift_artifact_t*, const char* func);
]]

local lower_mod = Host.dofile("lua/moonlift/mom/driver/lower_wire.mlua"):compile()
local mw_init = lower_mod:get("mw_init")
local mw_finish = lower_mod:get("mw_finish")
local pool_string = lower_mod:get("mw_write_pool_string")
local aux_i32s = lower_mod:get("mw_write_aux_i32s")
local serialize = lower_mod:get("mom_lower_cmd_tape_to_wire")

local wire = ffi.new("uint8_t[4096]")
local wb = ffi.new("MomWireBuilder")
mw_init(wb, wire, 4096)

local sig_s = ffi.new("uint8_t[?]", 8, "sig:ret7")
local func_s = ffi.new("uint8_t[?]", 5, "ret7")
local block_s = ffi.new("uint8_t[?]", 6, "entry")
local val_s = ffi.new("uint8_t[?]", 2, "v")
assert(pool_string(wb, sig_s, 8) == 0)
assert(pool_string(wb, func_s, 4) == 1)
assert(pool_string(wb, block_s, 5) == 2)
assert(pool_string(wb, val_s, 1) == 3)
local empty = ffi.new("int32_t[1]", {0})
local result = ffi.new("int32_t[1]", {4})
assert(aux_i32s(wb, empty, 0) == 0)
assert(aux_i32s(wb, result, 1) == 1)

local stride = 18
local ncmds = 9
local cmds = ffi.new("int32_t[?]", ncmds * stride)
local function cmd(i, tag, ...)
    local base = i * stride
    cmds[base] = tag
    local xs = {...}
    for j = 1, #xs do cmds[base + j] = xs[j] end
end
cmd(0, 3, 0, 0, 0, 1, 1)     -- CreateSig
cmd(1, 10, 1, 1, 0)          -- DeclareFunc export ret7 sig
cmd(2, 12, 1)                -- BeginFunc
cmd(3, 13, 2)                -- CreateBlock
cmd(4, 14, 2)                -- SwitchToBlock
cmd(5, 21, 3, 4, 2, 7, 0)   -- Const i32 7
cmd(6, 58, 3)                -- ReturnValue
cmd(7, 60, 1)                -- FinishFunc
cmd(8, 61)                   -- FinalizeModule
serialize(cmds, ncmds, wb)
local nwire = tonumber(mw_finish(wb))
assert(wb.error == 0, "wire error " .. tonumber(wb.error))

local lib = ffi.load("./target/release/libmoonlift.so")
local jit = lib.moonlift_jit_new()
local artifact = lib.moonlift_jit_compile_binary(jit, wire, nwire)
if artifact == nil or artifact == ffi.NULL then error(ffi.string(lib.moonlift_last_error_message())) end
local ptr = lib.moonlift_artifact_getpointer(artifact, ffi.new("char[?]", 5, "ret7"))
assert(ptr ~= nil and ptr ~= ffi.NULL)
local ret7 = ffi.cast("int32_t (*)()", ptr)
assert(ret7() == 7)
lib.moonlift_artifact_free(artifact)
lib.moonlift_jit_free(jit)

print("mom command tape to wire ok")
