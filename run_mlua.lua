#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local path = arg and arg[1]
if not path then
    io.stderr:write("usage: luajit run_mlua.lua file.mlua [args...]\n")
    os.exit(2)
end

local Run = require("moonlift.mlua_run")

local ok, result_or_err = pcall(function()
    return Run.dofile(path)
end)

if not ok then
    io.stderr:write(tostring(result_or_err), "\n")
    os.exit(1)
end

local result = result_or_err

-- If .mlua returned a compiled module, find a main/run/test exported function.
if result ~= nil then
    if type(result) == "table" and result.compile and result.get then
        -- Module-like value: try to get exported entry points.
        local main = result:get("main") or result:get("run") or result:get("test")
        if main then
            local pass = {}
            for i = 2, #(arg or {}) do pass[#pass + 1] = arg[i] end
            local ok_main, r = pcall(function() return main(unpack(pass)) end)
            if not ok_main then
                io.stderr:write(tostring(r), "\n")
                os.exit(1)
            end
            if r ~= nil then print(r) end
        end
    elseif type(result) ~= "string" or not result:match("^Moonlift RESP") then
        -- Print non-string, non-test results for visibility.
        print(result)
    end
end
