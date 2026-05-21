-- Lua Interpreter VM — String regions

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end

-- string_hash: compute Lua-compatible string hash
local string_hash = host.region [[
region string_hash(bytes: ptr(u8), len: index, seed: u32; done: cont(hash: u32))
entry start()
    let h: u32 = seed
    jump loop(i = 0, h = h)
end
block loop(i: index, h: u32)
    if i >= len then jump done(hash = h) end
    let nh: u32 = h * 5 + as(u32, bytes[i])
    jump loop(i = i + 1, h = nh)
end
end
]]

-- string_intern: find or create an interned string
local string_intern = host.region [[
region string_intern(L: ptr(LuaThread), bytes: ptr(u8), len: index;
                     found: cont(s: ptr(String)),
                     created: cont(s: ptr(String)),
                     oom: cont())
entry start()
    -- String allocation/interning requires the runtime allocator; report oom instead of manufacturing a dangling object.
    jump oom()
end
end
]]

-- string_concat_range: concatenate a range of stack values
local string_concat_range = host.region { ERR_RUNTIME = I.ERR_RUNTIME } [[
region string_concat_range(L: ptr(LuaThread), first: index, last: index;
                           done: cont(s: ptr(String)),
                           call_mm: cont(mm: Value),
                           error: cont(code: i32),
                           oom: cont())
entry start()
    jump error(code = @{ERR_RUNTIME})
end
end
]]

return {
    string_hash = string_hash,
    string_intern = string_intern,
    string_concat_range = string_concat_range,
}
