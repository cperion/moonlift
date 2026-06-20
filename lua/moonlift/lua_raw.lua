-- Raw LuaJIT C API pins for LuaBridge implementation.
--
-- This module intentionally contains declarations only.  It has no ownership
-- meaning and should only be imported by LuaBridge implementation modules.

local M = {}

M.source = [[
extern lua_gettop(L: ptr(u8)): i32 as "moonlift_lua_raw_gettop" end
extern lua_settop(L: ptr(u8), idx: i32) as "moonlift_lua_raw_settop" end
extern lua_type(L: ptr(u8), idx: i32): i32 as "moonlift_lua_raw_type" end
extern lua_tolstring(L: ptr(u8), idx: i32, len: ptr(index)): ptr(u8) as "moonlift_lua_raw_tolstring" end
extern lua_toboolean(L: ptr(u8), idx: i32): i32 as "moonlift_lua_raw_toboolean" end
extern lua_tonumber(L: ptr(u8), idx: i32): f64 as "moonlift_lua_raw_tonumber" end
extern lua_pushvalue(L: ptr(u8), idx: i32) as "moonlift_lua_raw_pushvalue" end
extern lua_pushnil(L: ptr(u8)) as "moonlift_lua_raw_pushnil" end
extern lua_pushboolean(L: ptr(u8), b: i32) as "moonlift_lua_raw_pushboolean" end
extern lua_pushnumber(L: ptr(u8), n: f64) as "moonlift_lua_raw_pushnumber" end
extern lua_pushlstring(L: ptr(u8), s: ptr(u8), len: index) as "moonlift_lua_raw_pushlstring" end
extern lua_rawgeti(L: ptr(u8), idx: i32, n: i32) as "moonlift_lua_raw_rawgeti" end
extern lua_rawseti(L: ptr(u8), idx: i32, n: i32) as "moonlift_lua_raw_rawseti" end
extern luaL_ref(L: ptr(u8), t: i32): i32 as "moonlift_lua_raw_lref" end
extern luaL_unref(L: ptr(u8), t: i32, ref: i32) as "moonlift_lua_raw_lunref" end
extern lua_pcall(L: ptr(u8), nargs: i32, nresults: i32, errfunc: i32): i32 as "moonlift_lua_raw_pcall" end
]]

local function parse(T)
    local parsed = require("moonlift.parse").Define(T).parse_module(M.source)
    if #parsed.issues ~= 0 then
        error(parsed.issues[1].message or tostring(parsed.issues[1]), 2)
    end
    return parsed.module
end

function M.module(T)
    return parse(T)
end

function M.items(T)
    return parse(T).items
end

function M.install(bundle)
    local items = M.items(bundle.session.T)
    for i = 1, #items do
        bundle.items[#bundle.items + 1] = items[i]
    end
    return bundle
end

return M
