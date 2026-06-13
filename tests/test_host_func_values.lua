package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Test func values using .mlua eval
local Host = require("moonlift.mlua_run")
local pvm = require("moonlift.pvm")

local add = Host.eval [[return func add(a: i32, b: i32): i32 return a + b end]]
assert(add.kind == "func")
assert(add.name == "add")
local Tr = add.T.MoonTree
assert(pvm.classof(add.func) == Tr.FuncLocal)
assert(#add.func.body == 1)
assert(pvm.classof(add.func.body[1]) == Tr.StmtReturnValue)
local ret = add.func.body[1].value
assert(pvm.classof(ret) == Tr.ExprBinary)
print("OK: func ASDL correct")

local header_body_only = Host.eval [=[
local add = func add(a: i32, b: i32): i32 end
return add[[ return a + b ]]
]=]
assert(header_body_only.kind == "func")
assert(header_body_only.name == "add")
local header_body_only_cls = pvm.classof(header_body_only.func)
assert(header_body_only_cls == Tr.FuncLocal or header_body_only_cls == Tr.FuncExport)
assert(#header_body_only.func.body == 1)
print("OK: func header body-only")

local header_mlua_sugar = Host.eval [=[
local add = func add(a: i32, b: i32): i32 end
local impl = func add
    return a + b
end
return impl
]=]
assert(header_mlua_sugar.kind == "func")
assert(header_mlua_sugar.name == "add")
local header_mlua_sugar_cls = pvm.classof(header_mlua_sugar.func)
assert(header_mlua_sugar_cls == Tr.FuncLocal or header_mlua_sugar_cls == Tr.FuncExport)
assert(#header_mlua_sugar.func.body == 1)
print("OK: func header .mlua sugar")

local dotted_header_mlua_sugar = Host.eval [=[
local API = {}
API.add = func add(a: i32, b: i32): i32 end
local impl = func API.add
    return a + b
end
return impl
]=]
assert(dotted_header_mlua_sugar.kind == "func")
assert(dotted_header_mlua_sugar.name == "add")
assert(#dotted_header_mlua_sugar.func.body == 1)
print("OK: dotted func header .mlua sugar")

-- Compile if JIT available
local ok_c, compiled = pcall(function() return add:compile() end)
if ok_c then
    assert(compiled(2, 3) == 5)
    compiled:free()
    print("OK: compiled")
end

-- Function with block
local sum = Host.eval [[
return func sum(readonly xs: ptr(i32), n: i32): i32
    block loop(i: i32 = 0, acc: i32 = 0)
        if i >= n then return acc end
        jump loop(i = i + 1, acc = acc + xs[i])
    end
end
]]
assert(sum.name == "sum")
assert(#sum.func.params == 2)
print("OK: block function")

-- Multiple functions via loader
local loader = assert(Host.loadstring([[
local add = func(a: i32, b: i32): i32 return a + b end
local sub = func(a: i32, b: i32): i32 return a - b end
return { add = add, sub = sub }
]], "multi.mlua"))
local multi = loader()
assert(multi.add.name == "add")
assert(multi.sub.name == "sub")
print("OK: multiple functions")

print("moonlift host func values ok")
