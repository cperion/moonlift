-- Lua Interpreter VM — Sealed C-compatible API functions
-- These are the only places where Lua C API conventions are allowed.

local moon = require("moonlift")
local const = require("experiments.lua_interpreter_vm.src.constants")

-- API functions are Moonlift funcs (not regions) — sealed external boundaries.

-- lua_type_api: return type code for value at index, or -1 for invalid indices.
local lua_type_api = moon.func [[
lua_type_api(L: ptr(LuaThread), idx: i32) -> i32
    if idx > 0 then
        let slot: index = as(index, idx - 1)
        if slot < L.top then return as(i32, L.stack[slot].tag) end
        return -1
    end
    if idx < 0 then
        let n: index = as(index, 0 - idx)
        if n <= L.top then return as(i32, L.stack[L.top - n].tag) end
        return -1
    end
    return -1
end
]]

-- lua_settop_api: set top of stack
local lua_settop_api = moon.func [[
lua_settop_api(L: ptr(LuaThread), idx: i32)
    if idx >= 0 then
        if as(index, idx) <= L.stack_size then
            L.top = as(index, idx)
        end
    else
        let n: index = as(index, 0 - idx)
        if n <= L.top + 1 then
            L.top = L.top - n + 1
        end
    end
end
]]

-- lua_pushvalue_api: push value at index when capacity allows.
local lua_pushvalue_api = moon.func [[
lua_pushvalue_api(L: ptr(LuaThread), idx: i32)
    if L.top >= L.stack_size then return end
    if idx > 0 then
        let slot: index = as(index, idx - 1)
        if slot < L.top then
            L.stack[L.top] = L.stack[slot]
            L.top = L.top + 1
        end
        return
    end
    if idx < 0 then
        let n: index = as(index, 0 - idx)
        if n <= L.top then
            L.stack[L.top] = L.stack[L.top - n]
            L.top = L.top + 1
        end
    end
end
]]

-- lua_tolstring_api: direct string access only; coercive formatting belongs to value_to_string.
local lua_tolstring_api = moon.func [[
lua_tolstring_api(L: ptr(LuaThread), idx: i32, len_out: ptr(index)) -> ptr(u8)
    if len_out ~= nil then len_out[0] = 0 end
    if idx > 0 then
        let slot: index = as(index, idx - 1)
        if slot < L.top then
            let v: Value = L.stack[slot]
            if v.tag == 5 then
                let s: ptr(String) = as(ptr(String), v.bits)
                if len_out ~= nil then len_out[0] = s.len end
                return s.bytes
            end
        end
    end
    if idx < 0 then
        let n: index = as(index, 0 - idx)
        if n <= L.top then
            let v: Value = L.stack[L.top - n]
            if v.tag == 5 then
                let s: ptr(String) = as(ptr(String), v.bits)
                if len_out ~= nil then len_out[0] = s.len end
                return s.bytes
            end
        end
    end
    return nil
end
]]

-- lua_gettable_api: full table lookup may allocate/call metamethods, so reject at this sealed boundary.
local lua_gettable_api = moon.func [[
lua_gettable_api(L: ptr(LuaThread), idx: i32) -> i32
    L.status = 2
    return -1
end
]]

-- lua_settable_api: full table assignment may allocate/call metamethods; mark runtime error instead of no-op.
local lua_settable_api = moon.func [[
lua_settable_api(L: ptr(LuaThread), idx: i32)
    L.status = 2
end
]]

-- lua_call_api: the sealed native call bridge is not wired; mark runtime error instead of no-op.
local lua_call_api = moon.func [[
lua_call_api(L: ptr(LuaThread), nargs: i32, nresults: i32)
    L.status = 2
end
]]

-- lua_pcall_api: protected frames require allocator support; report runtime error.
local lua_pcall_api = moon.func [[
lua_pcall_api(L: ptr(LuaThread), nargs: i32, nresults: i32, errfunc: i32) -> i32
    L.status = 2
    return 1
end
]]

return {
    lua_type_api = lua_type_api,
    lua_settop_api = lua_settop_api,
    lua_pushvalue_api = lua_pushvalue_api,
    lua_tolstring_api = lua_tolstring_api,
    lua_gettable_api = lua_gettable_api,
    lua_settable_api = lua_settable_api,
    lua_call_api = lua_call_api,
    lua_pcall_api = lua_pcall_api,
}
