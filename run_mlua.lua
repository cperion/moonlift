#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.host_quote")

local path = arg and arg[1]
if not path then
    io.stderr:write("usage: luajit run_mlua.lua file.mlua [args...]\n")
    os.exit(2)
end

local pass = {}
for i = 2, #(arg or {}) do pass[#pass + 1] = arg[i] end

local chunk = Host.loadfile(path)
local ok, a, b, c, d, e = pcall(chunk, unpack(pass))
if not ok then
    io.stderr:write(tostring(a), "\n")
    os.exit(1)
end

if a ~= nil then print(a) end
if b ~= nil then print(b) end
if c ~= nil then print(c) end
if d ~= nil then print(d) end
if e ~= nil then print(e) end
