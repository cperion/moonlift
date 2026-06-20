package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local schema = require("moonlift.asdl")
local T = pvm.context()
schema.Define(T)

local Raw = require("moonlift.lua_raw")
local Model = require("moonlift.lua_bridge_model")
local TC = require("moonlift.tree_typecheck").Define(T)

local Tr = T.MoonTree
local O = T.MoonOpen

local function assert_no_issues(site, issues)
    if #issues == 0 then return end
    error(site .. " failed: " .. tostring(issues[1].message or issues[1]))
end

local raw_module = Raw.module(T)
assert(#raw_module.items == 16, "lua_raw should expose the centralized raw pin set")

local raw_symbols = {}
for i = 1, #raw_module.items do
    local item = raw_module.items[i]
    assert(pvm.classof(item) == Tr.ItemExtern, "lua_raw item must be an extern")
    raw_symbols[item.func.symbol] = item.func
end

for _, symbol in ipairs({
    "moonlift_lua_raw_gettop",
    "moonlift_lua_raw_settop",
    "moonlift_lua_raw_type",
    "moonlift_lua_raw_tolstring",
    "moonlift_lua_raw_toboolean",
    "moonlift_lua_raw_tonumber",
    "moonlift_lua_raw_pushvalue",
    "moonlift_lua_raw_pushnil",
    "moonlift_lua_raw_pushboolean",
    "moonlift_lua_raw_pushnumber",
    "moonlift_lua_raw_pushlstring",
    "moonlift_lua_raw_rawgeti",
    "moonlift_lua_raw_rawseti",
    "moonlift_lua_raw_lref",
    "moonlift_lua_raw_lunref",
    "moonlift_lua_raw_pcall",
}) do
    assert(raw_symbols[symbol] ~= nil, "missing raw LuaJIT pin: " .. symbol)
end

local model_module = Model.module(T)
local checked = TC.check_module(model_module)
assert_no_issues("lua_bridge_model typecheck", checked.issues)
local protocols = Model.protocols(T)
assert(#protocols > 0, "lua_bridge_model should expose parsed protocol declarations")

local seen_regions = {}
local seen_types = {}
for i = 1, #model_module.items do
    local item = model_module.items[i]
    local cls = pvm.classof(item)
    if cls == Tr.ItemType then
        seen_types[item.t.name] = item.t
    end
end
for i = 1, #protocols do
    local proto = protocols[i]
    local name = proto.name
    if pvm.classof(name) == O.NameRefText then
        seen_regions[name.text] = proto
    end
end

for _, type_name in ipairs({
    "LuaStateRecord",
    "LuaRefRecord",
    "LuaErrorRecord",
    "LuaBridgeStore",
    "Core",
    "LuaStateRef",
    "LuaRef",
    "LuaErrorRef",
    "LuaValueKind",
    "LuaStackMark",
    "LuaStackRange",
    "LuaStringBorrow",
    "LuaCallFrame",
}) do
    assert(seen_types[type_name] ~= nil, "missing bridge model type: " .. type_name)
end

for _, region_name in ipairs({
    "lua_state_adopt",
    "lua_state_validate",
    "lua_retain_value",
    "lua_push_ref",
    "lua_release_ref",
    "lua_stack_mark",
    "lua_stack_restore",
    "lua_stack_check",
    "lua_borrow_string",
    "lua_copy_string",
    "lua_call_protected",
    "capture_lua_error",
    "lua_release_error",
    "lua_import_args_table",
    "lua_decode_proxy",
}) do
    assert(seen_regions[region_name] ~= nil, "missing bridge protocol region: " .. region_name)
end

local release_ref = seen_regions.lua_release_ref
local has_owned_failure_ref = false
for i = 1, #release_ref.conts do
    local cont = release_ref.conts[i]
    if cont.pretty_name == "lua_error" then
        has_owned_failure_ref = cont.params[1] and pvm.classof(cont.params[1].ty) == T.MoonType.TOwned
    end
end
assert(has_owned_failure_ref, "lua_release_ref failure exits must preserve owned LuaRef")

local std = require("moonlift.std")
assert(std.lua_raw == Raw, "moonlift.std should expose lua_raw")
assert(std.lua_bridge_model == Model, "moonlift.std should expose lua_bridge_model")

print("moonlift lua_bridge_contract ok")
