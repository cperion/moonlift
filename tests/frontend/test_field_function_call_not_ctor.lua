package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local moon = require("moonlift")

local src = [[
struct Alloc ctx: ptr(u8), alloc: func(ptr(u8), index): ptr(u8) end
extern fallback(size: index): ptr(u8) end

local call_alloc = func(a: ptr(Alloc), size: index): ptr(u8)
    if a == as(ptr(Alloc), 0) then return fallback(size) end
    return a.alloc(a.ctx, size)
end

union Maybe some(i32) | none end
local make_some = func(x: i32): Maybe
    return Maybe.some(x)
end

return {
    call_alloc = call_alloc,
    make_some = make_some,
}
]]

local loaded = assert(moon.loadstring(src, "field_function_call_not_ctor.mlua"))()
assert(loaded.call_alloc ~= nil, "field function call should parse as a call")
assert(loaded.make_some ~= nil, "declared union constructors should still parse")

local c_src = moon.emit_c_artifact(src, { name = "field_function_call_not_ctor" }).source
assert(c_src:find("call_alloc", 1, true), "C emission should include field-call function")

print("moonlift field function call not ctor ok")
