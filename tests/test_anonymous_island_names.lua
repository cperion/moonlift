package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Host = require("moonlift.mlua_run")

-- ── Style 1: local X = func(params...) ── inferred name ──
local add = Host.eval [[
local add = func(a: i32, b: i32): i32
    return a + b
end
return add
]]
assert(add.name == "add")
local c_add = add:compile()
assert(c_add(20, 22) == 42)
c_add:free()

-- ── Style 2: return func(params...) ── anonymous ──
local sub = Host.eval [[return func(a: i32, b: i32): i32 return a - b end]]
assert(sub.name:match("^_anon_"))
local c_sub = sub:compile()
assert(c_sub(10, 3) == 7)
c_sub:free()

-- ── Style 3: table.field = func(params...) ── inferred from field name ──
local mul = Host.eval [[
local M = {}
M.mul = func(a: i32, b: i32): i32 return a * b end
return M.mul
]]
assert(mul.name == "mul")
local c_mul = mul:compile()
assert(c_mul(3, 7) == 21)
c_mul:free()

-- ── Region: local X = region(params; ...) ──
local pass, ident = Host.eval [[
local pass = region(p: ptr(u8); ok: cont(next: i32))
entry start()
    jump ok(next = 0)
end
end

local ident = expr(x: i32): i32
    x
end

return pass, ident
]]
assert(pass.name == "pass")
assert(ident.name == "ident")

-- ── Struct: local X = struct ... end ──
local User = Host.eval [[
local User = struct
    id: i32
end
return User
]]
assert(User.source_hint == "User")

-- ── Union: local X = union ... end ──
local Result = Host.eval [[
local Result = union ok(value: i32) | err(code: i32) end
return Result
]]
assert(Result.source_hint == "Result")

-- ── Anonymous struct ──
local Inline = Host.eval [[return struct value: i32 end]]
assert(Inline.source_hint:match("^_anon_struct_"))

-- ── Anonymous union ──
local AnonU = Host.eval [[return union ok(i32) | err(i32) end]]
assert(AnonU.source_hint:match("^_anon_union_"))

-- ── Returned named union split over lines ──
local NamedU = Host.eval [[
return union NamedU
    ok(i32) | err(i32)
end
]]
assert(NamedU.source_hint == "NamedU")
assert(#NamedU.decl.variants == 2)

-- ── Table field struct ──
local M = Host.eval [[
local M = {}
M.Point = struct x: i32; y: i32 end
return M.Point
]]
assert(M.source_hint == "Point")

print("moonlift anonymous_island_names ok")
