package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
ffi.cdef [[
    typedef struct lua_State lua_State;
    lua_State* luaL_newstate(void);
    void lua_close(lua_State *L);
    void lua_pushnumber(lua_State *L, double n);
    int lua_gettop(lua_State *L);
    double lua_tonumber(lua_State *L, int idx);
]]

local Host = require("moonlift.mlua_run")

local f = Host.eval [[
local raw = moon.rawptr
local PushNumber = moon.func_type({ raw, moon.f64 }, moon.void)

local push_frag = region push_frag(pushnumber: @{PushNumber}, L: @{raw}; ok: cont())
entry start()
    pushnumber(L, 42.0)
    jump ok()
end
end

return func test(pushnumber: @{PushNumber}, L: @{raw}): i32
    return region: i32
    entry start()
        emit @{push_frag}(pushnumber, L; ok = done)
    end
    block done()
        yield 7
    end
    end
end
]]

local c = f:compile()
local L = ffi.C.luaL_newstate()
assert(c(ffi.cast("void *", ffi.C.lua_pushnumber), L) == 7)
assert(ffi.C.lua_gettop(L) == 1)
assert(tonumber(ffi.C.lua_tonumber(L, 1)) == 42)
ffi.C.lua_close(L)
c:free()

print("moonlift region frag runtime param call ok")
