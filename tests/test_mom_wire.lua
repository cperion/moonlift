package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local Host = require("moonlift.mlua_run")

ffi.cdef[[
typedef struct MomWireBuilder {
    uint8_t *data;
    size_t len;
    size_t cap;
    int32_t string_count;
    int32_t aux_count;
    int32_t error;
} MomWireBuilder;
]]

local function compile(path)
    local mod = Host.dofile(path)
    return mod:compile()
end

local function cstring(text)
    return ffi.new("char[?]", #text + 1, text)
end

local function u8str(text)
    return ffi.new("uint8_t[?]", #text + 1, text), #text
end

local wire = compile("lua/moonlift/mom/driver/wire.mlua")
local backend = compile("lua/moonlift/mom/driver/backend_ffi.mlua")

local init = wire:get("mw_init")
local finish = wire:get("mw_finish")
local ok = wire:get("mw_ok")
local pool = wire:get("mw_write_pool_string")
local aux = wire:get("mw_write_aux_i32s")
local cmd0 = wire:get("mw_write_cmd0")
local cmd1 = wire:get("mw_write_cmd1")
local cmd3 = wire:get("mw_write_cmd3")
local cmd5 = wire:get("mw_write_cmd5")

local compile_binary = backend:get("mom_backend_compile_binary")
local getpointer = backend:get("mom_backend_getpointer")
local free_artifact = backend:get("mom_backend_free_artifact")

local storage = ffi.new("uint8_t[1024]")
local w = ffi.new("MomWireBuilder")
init(w, storage, 1024)

local sig_s, sig_n = u8str("sig:ret7")
local func_s, func_n = u8str("ret7")
local entry_s, entry_n = u8str("entry.ret7")
local value_s, value_n = u8str("v")

assert(pool(w, sig_s, sig_n) == 0)
assert(pool(w, func_s, func_n) == 1)
assert(pool(w, entry_s, entry_n) == 2)
assert(pool(w, value_s, value_n) == 3)

local empty = ffi.new("int32_t[1]", {0})
local result = ffi.new("int32_t[1]", {4}) -- BackI32
assert(aux(w, empty, 0) == 0)
assert(aux(w, result, 1) == 1)

-- MLBT commands for:
--   export func ret7(): i32 { return 7 }
cmd5(w, 3, 0, 0, 0, 1, 1)     -- CmdCreateSig(sig=0, params_aux=0, n_params=0, results_aux=1, n_results=1)
cmd3(w, 10, 1, 1, 0)           -- CmdDeclareFunc(export, func=1, sig=0)
cmd1(w, 12, 1)                 -- CmdBeginFunc(func=1)
cmd1(w, 13, 2)                 -- CmdCreateBlock(entry=2)
cmd1(w, 14, 2)                 -- CmdSwitchToBlock(entry=2)
cmd5(w, 21, 3, 4, 2, 7, 0)    -- CmdConst(v=3, BackI32, int, 7, 0)
cmd1(w, 58, 3)                 -- CmdReturnValue(v=3)
cmd1(w, 60, 1)                 -- CmdFinishFunc(func=1)
cmd0(w, 61)                    -- CmdFinalizeModule

local byte_len = tonumber(finish(w))
assert(ok(w) == true)
assert(byte_len > 16)
assert(w.string_count == 4)
assert(w.aux_count == 2)
assert(storage[0] == 0x54 and storage[1] == 0x42 and storage[2] == 0x4c and storage[3] == 0x4d)
assert(storage[8] == 4 and storage[12] == 2)

local artifact = compile_binary(storage, byte_len)
assert(artifact ~= nil and artifact ~= ffi.NULL)
local ptr = getpointer(artifact, cstring("ret7"))
assert(ptr ~= nil and ptr ~= ffi.NULL)
local ret7 = ffi.cast("int32_t (*)()", ptr)
assert(ret7() == 7)
free_artifact(artifact)

print("mom wire ok")
