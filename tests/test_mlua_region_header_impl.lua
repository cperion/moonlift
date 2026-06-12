package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local function run(src)
    return moon.loadstring(src, "test_mlua_region_header_impl.mlua")()
end

local header, impl = run([==[
local scan = region scan(p: ptr(u8), n: i32; hit(pos: i32) | miss) end
local impl = region scan
entry loop(i: i32 = 0)
    if i >= n then jump miss() end
    jump hit(pos = i)
end
end
return scan, impl
]==])

assert(header.kind == "region_header")
assert(impl.kind == "region_frag")
assert(impl.name == "scan")
assert(impl.frag.entry.label.name == "loop")
assert(#impl.frag.params == 2)
assert(#impl.frag.conts == 2)

local body_only = run([==[
local scan = region scan(; done) end
local impl = scan[[
entry start()
    jump done()
end
]]
return impl
]==])

assert(body_only.kind == "region_frag")
assert(body_only.name == "scan")
assert(body_only.frag.entry.label.name == "start")

local reassigned = run([==[
local scan = region scan(; done) end
scan = region scan
entry start()
    jump done()
end
end
return scan
]==])

assert(reassigned.kind == "region_frag")
assert(reassigned.name == "scan")
assert(reassigned.frag.entry.label.name == "start")

local dotted = run([==[
local API = {}
API.scan = region scan(; done) end
local impl = region API.scan
entry start()
    jump done()
end
end
return impl
]==])

assert(dotted.kind == "region_frag")
assert(dotted.name == "scan")

local spliced = run([==[
local T = moon.i32
local limit = 7
local scan = region scan(x: @{T}; done(v: @{T})) end
local impl = region scan
entry start()
    if x == @{limit} then jump done(v = x) end
    jump done(v = x)
end
end
return impl
]==])

assert(spliced.kind == "region_frag")
assert(spliced.name == "scan")
assert(#spliced.frag.params == 1)
assert(#spliced.frag.conts == 1)

print("moonlift .mlua region header implementation ok")
