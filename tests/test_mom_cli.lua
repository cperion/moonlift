package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local function capture(cmd)
    local p = assert(io.popen(cmd .. " 2>&1", "r"))
    local out = p:read("*a")
    local ok, _, code = p:close()
    return ok, code, out
end

local ok, _, out = capture("./target/release/mom status")
assert(ok, out)
assert(out:match("precompiled native MOM object linked"), out)
assert(out:match("mom_hello:%s*42"), out)
assert(not out:match("tree_to_back"), out)
assert(not out:match("hosted Lua"), out)

print("mom cli status ok")
