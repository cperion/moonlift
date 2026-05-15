package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local src_path = "/tmp/moonlift_mom_cli_test.mlua"
local obj_path = "/tmp/moonlift_mom_cli_test.o"
local f = assert(io.open(src_path, "wb"))
f:write([[
func main() -> i32
  return 7
end
func add(x: i32, y: i32) -> i32
  return x + y
end
]])
f:close()
os.remove(obj_path)

local function capture(cmd)
    local p = assert(io.popen(cmd .. " 2>&1", "r"))
    local out = p:read("*a")
    local ok, _, code = p:close()
    return ok, code, out
end

local ok, _, out = capture("./target/release/mom --call add --arg-i32 20 --arg-i32 22 " .. src_path)
assert(ok, out)
assert(out:match("42"), out)

ok, _, out = capture("./target/release/mom " .. src_path)
assert(ok, out)
assert(out:match("7"), out)

ok, _, out = capture("./target/release/mom --emit-object -o " .. obj_path .. " " .. src_path)
assert(ok, out)
local of = assert(io.open(obj_path, "rb"))
local bytes = of:read("*a")
of:close()
assert(#bytes > 0)

print("mom cli ok")
