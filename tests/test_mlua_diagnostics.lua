package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local SourceMap = require("moonlift.source_map")
local Diag = require("moonlift.diagnostic")
local Run = require("moonlift.mlua_run")

-- Source index basics.
do
    local idx = SourceMap.index("a\nxyz\n")
    local l, c = SourceMap.line_col(idx, 3) -- 'x'
    assert(l == 2 and c == 1)
    local sn = SourceMap.snippet(idx, 2, 1)
    assert(sn:find("2 | xyz", 1, true) ~= nil)
end

-- Diagnostic parsing + rendering.
do
    local err = "chunk.mlua:12: unexpected symbol near ')'\n--- generated source ---\nprint('x')"
    local d = Diag.from_error(err, { phase = "compile_carrier", file = "chunk.mlua" })
    assert(Diag.is(d))
    assert(d.generated_line == 12)
    assert(d.generated_source and d.generated_source:find("print", 1, true))
    local text = Diag.render(d)
    assert(text:find("phase: compile_carrier", 1, true) ~= nil)
    assert(text:find("generated_line: 12", 1, true) ~= nil)
end

-- End-to-end: parse island error is structured and keeps parse phase.
do
    local bad = "local r = region bad\nentry start()\n  jump x()\n"
    local fn = assert(Run.loadstring(bad, "=(diag_test.mlua)"))
    local ok, err = pcall(fn)
    assert(not ok)
    local text = tostring(err)
    assert(text:find("phase: parse_island", 1, true) ~= nil)
    assert(text:find("source:", 1, true) ~= nil)
    assert(text:find("snippet:", 1, true) ~= nil)
end

print("test_mlua_diagnostics ok")
