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

local dir = "target/test_artifacts/test_lalin_mc_bank_generator"
local c_path = dir .. "/bank.c"
local h_path = dir .. "/bank.h"

assert(command_ok("mkdir -p " .. shell_quote(dir)))
assert(command_ok(
    "LALIN_MC_BANK_MAX_TEMPLATES=32 "
        .. "luajit tools/gen_lalin_mc_bank.lua "
        .. shell_quote(c_path) .. " " .. shell_quote(h_path)
        .. " 2> " .. shell_quote(dir .. "/generator.log")
), "expected MC bank generator to emit a patch-template manifest")

local log = read_file(dir .. "/generator.log")
local header = read_file(h_path)
local source = read_file(c_path)

assert(log:find("32 Lalin MC patch%-template bank entries"), "expected generator log to report template entries")
assert(header:find("LalinEmbeddedMCTemplateEntry", 1, true), "expected template entry C type in header")
assert(source:find("lalin_mc_template_entries", 1, true), "expected template manifest entries in source")
assert(source:find("family(", 1, true), "expected semantic patch-template family keys in source")
assert(not source:find("static const unsigned char lalin_mc_", 1, true), "generator must not emit exact MC byte arrays")

io.write("lalin mc bank generator ok\n")
