package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("pvm")
local A = require("moonlift.asdl")
local T = pvm.context()
A.Define(T)
local S = require("moonlift.source").Define(T)

local authored = [[
type Color = enum { red, green, blue }
type Result = ok(i32) | err(i32)
type Bits = union { i: i32, f: f32 }
type Pair = struct { left: i32, right: i32 }

export func enum_value() -> i32
return green + blue
end

export func tagged_tag() -> i32
let r: Result = Result { tag = Result_tag_err, _0 = 0, _1 = 7 }
return r.tag
end

export func array_index() -> i32
let xs: [3]i32 = []i32 { 10, 20, 30 }
return xs[1]
end

export func struct_field() -> i32
let p: Pair = Pair { left = 4, right = 5 }
return p.left + p.right
end

export func closure_frontdoor() -> i32
let bias: i32 = 9
let f: closure(i32) -> i32 = fn(x: i32) -> i32
return x + bias
end
return 0
end
]]

local lowered, lower_err = S.try_lower_module(authored)
assert(lowered, tostring(lower_err))

local pipe = assert(S.pipeline(authored))
assert(#pipe.elab.items >= 8)
local consts = {}
for i = 1, #pipe.elab.items do
    if pipe.elab.items[i].c ~= nil then consts[pipe.elab.items[i].c.name] = pipe.elab.items[i].c end
end
assert(consts.red ~= nil)
assert(consts.green ~= nil)
assert(consts.blue ~= nil)
assert(consts.Result_tag_ok ~= nil)
assert(consts.Result_tag_err ~= nil)

local sem, sem_err = S.try_sem_module(authored)
assert(sem, tostring(sem_err))
local resolved, resolve_err = S.try_resolve_module(authored)
assert(resolved, tostring(resolve_err))

local back, back_err = S.try_back(authored)
assert(back, tostring(back_err))
assert(#back.cmds > 0)
local saw_func_addr = false
for i = 1, #back.cmds do
    if back.cmds[i].kind == "BackCmdFuncAddr" then saw_func_addr = true end
end
assert(saw_func_addr)

local artifact, jit, compile_err = S.try_compile(authored)
assert(artifact, tostring(compile_err))
artifact:free()
jit:free()

print("moonlift authored language smoke ok")
