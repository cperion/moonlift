package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;experiments/llpvm/?.lua;experiments/llpvm/?.mlua;" .. package.path

local ll = require("llpvm")
local Runtime = require("llpvm.runtime_ffi")

local rt = Runtime.build {
    cleanup = true,
}

local vm = rt:open {
    cache_bytes = 4096,
}

local report = vm:report()
assert(report.streams == 0, "fresh VM report should have no streams")

local apply_status, out_stream = vm:apply_phase(0, 0, 0)
assert(apply_status.code == 10, "empty phase apply currently reports failed")
assert(out_stream == 0, "failed apply should not produce a stream")

local drain_status, out_buffer = vm:drain(0)
assert(drain_status.code == 0, "empty stream drain currently succeeds as empty")
assert(out_buffer == 0, "empty drain returns invalid buffer")

local authored = ll.vm {}
local Expr = authored.abi "Expr" { Int = { value = ll.i64 } }
local input = authored.seq(Expr:world()) { Expr.Int { value = 1 } }
local ok, err = pcall(function() vm:drain(input) end)
assert(not ok and tostring(err):match("authored ASDL proxy"), "runtime must reject authored streams that were not loaded as bytecode")

local image = authored.program { input }:bytecode()
local ffi = require("ffi")
local image_buf = ffi.new("uint8_t[?]", #image)
ffi.copy(image_buf, image, #image)
local load_status, loaded_stream = vm:load_program_buffer(image_buf, #image)
assert(load_status.code == 0, "load_program imports bytecode image")
assert(loaded_stream ~= 0, "load_program returns a native root stream")

local loaded_drain_status, loaded_buffer = vm:drain(loaded_stream)
assert(loaded_drain_status.code == 0, "loaded stream drains successfully")
assert(loaded_buffer ~= 0, "loaded stream drains to a native buffer")

local loaded_report = vm:report()
assert(loaded_report.abis >= 1, "loaded image creates ABI records")
assert(loaded_report.worlds >= 1, "loaded image creates world records")
assert(loaded_report.ops == 0, "loaded image keeps authored ops in immutable program image")
assert(loaded_report.streams >= 1, "loaded image creates stream records")

vm:close()
rt:close()

print("llpvm runtime ffi ok")
