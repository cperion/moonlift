#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local path = arg and arg[1]
if not path then
    io.stderr:write("usage: luajit run_mlua.lua file.mlua [args...]\n")
    os.exit(2)
end

local Run = require("moonlift.mlua_run")
local result = Run.dofile(path)

-- If .mlua returned a compiled module, find a main/run/test exported function.
if result ~= nil then
    if type(result) == "table" and result.compile then
        -- ModuleQuote-like: try to get exported functions
        local main = result:get("main") or result:get("run") or result:get("test")
        if main then
            local pass = {}
            for i = 2, #(arg or {}) do pass[#pass + 1] = arg[i] end
            local r = main(unpack(pass))
            if r ~= nil then print(r) end
        end
    elseif type(result) ~= "string" or not result:match("^Moonlift RESP") then
        -- Print non-string, non-test results for visibility
        print(result)
    end
end
