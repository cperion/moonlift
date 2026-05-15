-- MOM validation: loads MOM schema modules and reports type counts.
--
-- Usage:
--   target/release/moonlift lua/moonlift/mom/validate.mlua

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./experiments/?/?.lua;./experiments/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

local S = Host.dofile("lua/moonlift/mom/schema/init.lua")

local function count_types(mod)
    local n = 0
    for k, v in pairs(mod) do
        if type(k) == "string" and not k:match("^_") then
            n = n + 1
        end
    end
    return n
end

print("MOM schema — type counts")
print()

for name, mod in pairs(S) do
    if type(name) == "string" and not name:match("^_") and type(mod) == "table" then
        local n = count_types(mod)
        print(string.format("  %-16s %3d types", name, n))
    end
end

print()
print("MOM: OK")
