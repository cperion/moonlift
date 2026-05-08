package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Run = require("moonlift.mlua_run")

local src = [[
local m = module KeywordFieldIsland

type ExitWithKeywordFields = mcode(entry: ptr(u8)) | block(yield: i32) | done

export func sentinel() -> i32
    return 1
end

end
local c = m:compile()
assert(c:get("sentinel")() == 1)
c:free()
return "keyword field island ok"
]]

local f = assert(io.open("/tmp/moonlift_keyword_field_island.mlua", "w"))
f:write(src)
f:close()
assert(Run.dofile("/tmp/moonlift_keyword_field_island.mlua") == "keyword field island ok")
print("keyword_field_island ok")
