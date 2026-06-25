#!/usr/bin/env luajit

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local opts = { width = 100, indent = 2 }
local mode = "print"
local files = {}

local i = 1
while i <= #arg do
    local a = arg[i]
    if a == "--write" or a == "-w" then
        mode = "write"
    elseif a == "--check" or a == "-c" then
        mode = "check"
    elseif a == "--width" then
        i = i + 1
        opts.width = tonumber(arg[i]) or opts.width
    elseif a == "--indent" then
        i = i + 1
        opts.indent = tonumber(arg[i]) or opts.indent
    elseif a == "--help" or a == "-h" then
        io.write([[
usage: luajit scripts/lalinfmt.lua [--write|--check] [--width N] [--indent N] file.lua...

Formats evaluated Lalin DSL values. This is semantic formatting for
format-owned Lalin Lua files, not a general Lua source formatter.
]])
        os.exit(0)
    else
        files[#files + 1] = a
    end
    i = i + 1
end

if #files == 0 then
    io.stderr:write("lalinfmt: expected at least one file\n")
    os.exit(2)
end

local changed = false

for _, path in ipairs(files) do
    local formatted = lalin.format_file(path, opts)
    if mode == "write" then
        local f = assert(io.open(path, "wb"))
        f:write(formatted)
        f:close()
    elseif mode == "check" then
        local f = assert(io.open(path, "rb"))
        local current = f:read("*a") or ""
        f:close()
        if current ~= formatted then
            changed = true
            io.stderr:write(path .. "\n")
        end
    else
        if #files > 1 then io.write("-- " .. path .. "\n") end
        io.write(formatted)
    end
end

if mode == "check" and changed then os.exit(1) end
