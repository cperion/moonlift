package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test protocol/region syntax using the new parse API
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Parse = require("moonlift.parse")

local T = pvm.context()
A.Define(T)
local P = Parse.Define(T)
local C, Ty = T.MoonCore, T.MoonType

-- Union type via parser
local scan1 = Parse.scan_document([[local S = union Scanner hit(pos: i32) | miss(pos: i32) end]])
assert(#scan1.islands == 1)
local parsed1 = P.parse_island(scan1, 1)
assert(#parsed1.issues == 0, tostring(parsed1.issues[1]))
local scanner_decl = parsed1.value.decl
assert(pvm.classof(scanner_decl) == T.MoonTree.TypeDeclTaggedUnionSugar)
assert(scanner_decl.variants[1].name == "hit")
assert(scanner_decl.variants[1].fields[1].field_name == "pos")
print("OK: union type parsed")

-- Region fragment via eval
local Host = require("moonlift.mlua_run")
local scan_until = Host.eval [[
return region scan_until(p: ptr(u8), n: i32, target: i32; hit: cont(pos: i32), miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end
]]
assert(scan_until.name == "scan_until")
assert(#scan_until.frag.params == 3)
assert(#scan_until.frag.conts == 2)
print("OK: region fragment parsed")

-- Function using emit
local fn = Host.eval [[
local scan_until = region scan_until(p: ptr(u8), n: i32, target: i32; hit: cont(pos: i32), miss: cont(pos: i32))
entry loop(i: i32 = 0)
    if i >= n then jump miss(pos = i) end
    if as(i32, p[i]) == target then jump hit(pos = i) end
    jump loop(i = i + 1)
end
end
return func find_byte(p: ptr(u8), n: i32, target: i32) -> i32
    return region -> i32
    entry start()
        emit @{scan_until}(p, n, target; hit = found, miss = not_found)
    end
    block found(pos: i32)
        yield pos
    end
    block not_found(pos: i32)
        yield -1
    end
    end
end
]]
assert(fn.name == "find_byte")
-- Compile (may fail without JIT library)
local ok, compiled = pcall(function() return fn:compile() end)
if ok then
    local ffi = require("ffi")
    local data = ffi.new("uint8_t[3]", 10, 20, 30)
    assert(compiled(data, 3, 10) == 0)
    assert(compiled(data, 3, 99) == -1)
    compiled:free()
    print("OK: emit compiled and ran")
else
    print("OK: emit value constructed (compile skipped - no JIT lib)")
end

print("moonlift protocol syntax ok")
