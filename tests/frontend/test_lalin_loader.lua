package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local chunk, err = lalin.loadstring([[
local scale = 4
local add = fn(a[i32], b [i32]) [i32]
  return a + b
end

local add_again = add

local widen = fn(x[i32]) [f64]
  return as [f64](x)
end

return {
  add = add_again,
  widen = widen,
  scale = scale,
}
]], "@inline.lln")
assert(chunk ~= nil, tostring(err))

local inline = chunk()
assert(inline.scale == 4, ".lln chunks should return ordinary Lua values")
assert(inline.add.tag == "DeclFunc", "bare fn should be active in .lln chunks")
assert(inline.add.name == "add", "anonymous parsed function should infer its Lua binding name")
assert(inline.widen.name == "widen", "anonymous parsed function should infer no-space Lua binding names")

local compiled = lalin.compile("loader_inline", { inline.add, inline.widen }, { residual = "bc" })
assert(compiled.add(20, 22) == 42, "parsed .lln declarations should feed lalin.compile")
assert(compiled.widen(7) == 7, "parsed casts should feed the shared type escape path")
local compiled_from_api = lalin.compile("loader_inline_api", inline, { residual = "bc" })
assert(compiled_from_api.add(20, 22) == 42, "mixed Lua API tables should contribute parsed declarations to compile")

local named_decls = assert(lalin.loadstring([=[
local Pair = struct Pair
  x[i32]
end

local pair_ty = named("Pair")
local accept = fn(p [ptr [pair_ty]]) [void]
  return
end

return {
  Pair,
  accept,
}
]=], "@named.lln"))()
local named_module = lalin.compile("loader_named_type", named_decls, { residual = "bc" })
assert(named_module.accept ~= nil, "named Lua type values should work in parsed type positions")

local table_api = assert(lalin.loadstring([=[
return {
  inc = fn(x [i32]) [i32]
    return x + 1
  end,
  dec = fn(x [i32]) [i32]
    return x - 1
  end,
}
]=], "@table_api.lln"))()
assert(table_api.inc.name == "inc", "anonymous parsed function should infer table-field keys")
assert(table_api.dec.name == "dec", "anonymous parsed function should infer table-field keys after commas")
local table_module = lalin.compile("loader_table_api", table_api, { residual = "bc" })
assert(table_module.inc(41) == 42, "string-keyed Lua tables should feed lalin.compile")
assert(table_module.dec(43) == 42, "string-keyed Lua tables should preserve public function keys")

local generated_name = assert(lalin.loadstring([=[
return {
  fn(x [i32]) [i32]
    return x * 2
  end,
}
]=], "@generated_name.lln"))()
assert(generated_name[1].name == nil, "unbound anonymous functions should remain source-anonymous")
local generated_module = lalin.compile("loader_generated_name", generated_name, { residual = "bc" })
local generated_key
for k in pairs(generated_module) do
  if k ~= "__lalin_artifact" then generated_key = k end
end
assert(type(generated_key) == "string" and generated_key:match("^__lln_fn_"), "codegen should assign generated compiler names")
assert(generated_module[generated_key](21) == 42, "generated compiler names should be executable")
local inferred_unit = lalin.syntax.to_module({
  double = generated_name[1],
}, "loader_table_to_unit")
assert(inferred_unit.items[1].func.name == "double", "syntax.to_module should infer internal units from keyed Lua tables")

local module_ok = lalin.loadstring([[
module Demo
end
]], "@removed_module.lln")
assert(module_ok == nil, "parsed `module` was hard-yanked from the .lln source surface")

local ok, import_err = pcall(function()
    return lalin.loadstring([[import "lalin.syntax"]], "@bad.lln")
end)
assert(not ok and tostring(import_err):match("import"), ".lln chunks should reject parse-time import")

os.execute("rm -rf " .. shell_quote("target/test_lalin_loader"))
os.execute("mkdir -p " .. shell_quote("target/test_lalin_loader/pkg"))

write("target/test_lalin_loader/pkg/math.lln", [[
local add = fn(a [i32], b [i32]) [i32]
  return a + b
end

return {
  add = add,
  label = "math",
}
]])

write("target/test_lalin_loader/cli.lln", [[
local add = fn(a [i32], b [i32]) [i32]
  return a + b
end

assert(add.tag == "DeclFunc")
]])

lalin.path = "target/test_lalin_loader/?.lln;target/test_lalin_loader/?/init.lln"
package.loaded["pkg.math"] = nil

local math1 = lalin.require("pkg.math")
assert(math1.label == "math", "lalin.require should return the .lln chunk value")
assert(math1.add.tag == "DeclFunc", "required .lln values should preserve parsed declarations")
assert(lalin.require("pkg.math") == math1, "lalin.require should use package.loaded")

package.loaded["pkg.math"] = nil
assert(lalin.install_searcher(), "expected .lln searcher installation")
local math2 = require("pkg.math")
assert(math2.label == "math", "Lua require should discover .lln files after installing the searcher")
assert(package.loaded["pkg.math"] == math2, "Lua require should own package.loaded caching")
assert(lalin.remove_searcher(), "expected .lln searcher removal")

local cli = require("lalin.cli")
assert(cli.main({ "target/test_lalin_loader/cli.lln" }) == 0, "CLI should load .lln files through lalin.loadstring")

io.write("lalin loader ok\n")
