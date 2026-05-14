#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Run = require("moonlift.mlua_run")
local path = os.tmpname() .. ".mlua"
local f = assert(io.open(path, "w"))
f:write([[
local loop = region(x: i32; done: cont(v: i32))
entry start()
    emit loop(x; done = done)
end
end

local run = func(x: i32) -> i32
    return region -> i32
    entry start()
        emit loop(x; done = out)
    end
    block out(v: i32)
        yield v
    end
    end
end

local c = run:compile()
c:free()
return "should not happen"
]])
f:close()

local ok, err = pcall(function() Run.dofile(path) end)
os.remove(path)
assert(not ok, "recursive region emit should fail")
assert(tostring(err):match("recursive region emit detected"), tostring(err))
print("moonlift region normal form recursive ok")
