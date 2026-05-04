-- host_quote is retired.  The public hosted runner is mlua_run and all hosted
-- islands lower through ASDL templates/values rather than Host.source.

local Run = require("moonlift.mlua_run")

local chunk = assert(Run.loadstring([[
local name = "R"
local r = region @{name}()
entry start()
end
end
return r
]], "test_host_quote_retired.mlua"))
local frag = chunk()
assert(frag.kind == "region_frag")
assert(frag.name == "R")
assert(frag.source == nil)

local HostQuote = require("moonlift.mlua_run")
local ok = pcall(function() HostQuote.source { "x" } end)
assert(not ok, "Host.source must stay removed")

print("moonlift host_quote retired ok")
return "moonlift host_quote retired ok"
