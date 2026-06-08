package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Run = require("moonlift.mlua_run")

local src = [[
local ExitWithKeywordFields = union mcode(entry: ptr(u8)) | block(yield: i32) | done end

local sentinel = func(): i32
    return 1
end

local c = sentinel:compile()
assert(c() == 1)
c:free()
return "keyword field island ok"
]]

local f = assert(io.open("/tmp/moonlift_keyword_field_island.mlua", "w"))
f:write(src)
f:close()
assert(Run.dofile("/tmp/moonlift_keyword_field_island.mlua") == "keyword field island ok")
print("keyword_field_island ok")
