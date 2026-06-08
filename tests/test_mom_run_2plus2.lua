local function capture(cmd)
    local p = assert(io.popen(cmd .. " 2>&1", "r"))
    local out = p:read("*a")
    local ok, _, code = p:close()
    return ok, code, out
end

local src_path = "/tmp/moonlift_mom_run_2plus2.mlua"
local f = assert(io.open(src_path, "wb"))
f:write([[func main(): i32
  return 2 + 2
end
]])
f:close()

local ok, _, out = capture("./target/release/mom " .. src_path)
assert(ok, out)
assert(out:match("^%s*4%s*$"), out)

local add_path = "/tmp/moonlift_mom_run_add_args.mlua"
f = assert(io.open(add_path, "wb"))
f:write([[func add(a: i32, b: i32): i32
  return a + b
end
]])
f:close()

ok, _, out = capture("./target/release/mom run --call add --arg-i32 20 --arg-i32 22 " .. add_path)
assert(ok, out)
assert(out:match("^%s*42%s*$"), out)

print("mom run 2+2/add args ok")
