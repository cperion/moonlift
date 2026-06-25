package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function list_shards(dir)
    local cmd = "find " .. shell_quote(dir) .. " -maxdepth 1 -type f -name 'bank_shard_*.c' | sort"
    local p = assert(io.popen(cmd, "r"))
    local out = {}
    for path in p:lines() do out[#out + 1] = path end
    p:close()
    return out
end

local dir = "target/test_artifacts/test_lalin_mc_bank_generator"
local c_path = dir .. "/bank.c"
local h_path = dir .. "/bank.h"

assert(command_ok("mkdir -p " .. shell_quote(dir)))
assert(command_ok(
    "LALIN_MC_BANK_TARGET_BYTES=1048576 LALIN_MC_BANK_JOBS=4 "
        .. "luajit tools/gen_lalin_mc_bank.lua "
        .. shell_quote(c_path) .. " " .. shell_quote(h_path)
        .. " 2> " .. shell_quote(dir .. "/generator.log")
), "expected sharded MC bank generator to emit an explicitly targeted default-shape bank")

local c = read_file(c_path)
local h = read_file(h_path)
local log = read_file(dir .. "/generator.log")
local payload = tonumber(log:match("(%d+) payload bytes"))
local shards = list_shards(dir)

assert(#shards == 4, "expected targeted sharded MC bank to emit one source per worker")
assert(payload ~= nil and payload <= 1024 * 1024, "expected explicit target bytes to bound compiled MC payload")
assert(c:find('#include "bank.h"', 1, true), "expected generated source to include the requested header basename")
assert(c:find("lalin_embedded_mc_bank_shards", 1, true), "expected generated source to expose shard table")
assert(c:find("lalin_embedded_mc_bank_count", 1, true), "expected generated source to expose aggregate count")
assert(read_file(shards[1]):find("static const unsigned char lalin_mc_", 1, true), "expected generated MC byte arrays in shard source")
assert(read_file(shards[1]):find("static const LalinEmbeddedMCEntry lalin_mc_shard_", 1, true), "expected generated MC entry table in shard source")
assert(h:find("LalinEmbeddedMCEntry", 1, true), "expected generated MC bank header declarations")
assert(h:find("LalinEmbeddedMCShard", 1, true), "expected generated MC bank shard declarations")

if command_ok("command -v cc >/dev/null 2>&1") then
    local sources = { shell_quote(c_path) }
    for _, shard in ipairs(shards) do sources[#sources + 1] = shell_quote(shard) end
    assert(command_ok("cc -I.vendor/LuaJIT/src -I" .. shell_quote(dir) .. " -fsyntax-only " .. table.concat(sources, " ")), "expected generated MC bank C shards to be syntactically valid")
end

io.write("lalin mc bank generator ok\n")
