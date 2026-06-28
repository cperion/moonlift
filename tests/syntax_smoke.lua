package.path = "../lua/?.lua;../lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local src = [=[
local scale = 4
local copy_scale = fn(dst [ptr [i32]], src [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), bounds(src)(n), disjoint(dst)(src)
  loop i in 0 .. n do
    dst[i] = src[i] * [scale]
  end
end
return copy_scale
]=]

local chunk, compiled_or_err, compiled_if_err = lalin.loadstring(src, "@smoke.lln")
if not chunk then
  error(tostring(compiled_or_err) .. "\nGenerated Lua:\n" .. tostring(compiled_if_err and compiled_if_err.lua or "<none>"))
end
local compiled = compiled_or_err
assert(#compiled.constructors == 1, "expected one parsed constructor")
assert(compiled.lua:match("__llbl_syntax.invoke"), "generated source should invoke parsed constructor")
local f = chunk()
assert(f.tag == "DeclFunc", "expected DeclFunc")
assert(f.name == "copy_scale", "wrong function name")
assert(f.body[1].tag == "StmtRequires", "requires statement missing")
assert(f.body[2].tag == "StmtForRange", "loop statement missing")
assert(f.body[2].body[1].tag == "StmtAssign", "assignment statement missing")
assert(f.body[2].body[1].value.right.resolved == true, "host escape should resolve")
assert(f.body[2].body[1].value.right.value == 4, "host escape resolved wrong value")
print("ok")
