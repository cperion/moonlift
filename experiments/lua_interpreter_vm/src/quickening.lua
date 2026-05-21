-- Lua Interpreter VM — Quickening and inline caches

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Tag) do I["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end

-- probe_gettable_cache: check inline cache hit
local probe_gettable_cache = host.region [[
region probe_gettable_cache(t: ptr(Table), key: Value, cache: ptr(InlineCache);
                            hit: cont(slot: index), stale: cont(), miss: cont())
entry start()
    if cache.epoch ~= t.shape_epoch then
        jump stale()
    end
    if cache.key.tag == key.tag and cache.key.bits == key.bits then
        jump hit(slot = as(index, cache.aux0))
    end
    jump miss()
end
end
]]

-- quicken_instruction: patch a generic opcode to quickened form
local quicken_instruction = host.region [[
region quicken_instruction(L: ptr(LuaThread), proto: ptr(Proto), pc: index, observation_kind: u32, obj: Value, key: Value;
                           patched: cont(), keep_generic: cont(), oom: cont())
entry start()
    jump keep_generic()
end
end
]]

-- deopt_instruction: revert to generic opcode
local deopt_instruction = host.region [[
region deopt_instruction(proto: ptr(Proto), pc: index; done: cont())
entry start()
    jump done()
end
end
]]

return {
    probe_gettable_cache = probe_gettable_cache,
    quicken_instruction = quicken_instruction,
    deopt_instruction = deopt_instruction,
}
