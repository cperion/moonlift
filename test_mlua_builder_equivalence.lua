package.path = "./?.lua;./?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;./moonlift/lua/?.lua;./moonlift/lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local Host = require("moonlift.host")
local MluaParse = require("moonlift.mlua_parse")
local HostDeclValidate = require("moonlift.host_decl_validate")

local T = Host.default_session.T
local MP = MluaParse.Define(T)
local Validate = HostDeclValidate.Define(T)
local H = T.Moon2Host

local src = [[
struct User repr(packed(4)) {
    id: i32 readonly
    active: bool32 mutable
    small: bool stored u8 noalias
}

expose view(User) as Users {
    lua readonly checked
    terra
    c
}
]]

local parsed = MP.parse(src, "builder_equivalence.mlua")
assert(#parsed.issues == 0, tostring(parsed.issues[1]))

local built = Host.host_decl_set({
    Host.host_struct("User", {
        Host.host_field("id", Host.i32, { "readonly" }),
        Host.host_field("active", Host.host_bool32, { "mutable" }),
        Host.host_field("small", Host.host_bool_stored(Host.u8), { "noalias" }),
    }, { packed = 4 }),
    Host.host_expose(Host.host_expose_view(Host.host_named("User")), "Users", {
        targets = { "lua", "terra", "c" },
        mutability = "readonly",
        bounds = "checked",
    }),
})

assert(parsed.decls == built)
local report = Validate.validate(built)
assert(#report.issues == 0, tostring(report.issues[1]))

local struct_decl = built.decls[1].decl
assert(struct_decl.repr == H.HostReprPacked(4))
assert(struct_decl.fields[1].attrs[1] == H.HostFieldReadonly)
assert(struct_decl.fields[2].attrs[1] == H.HostFieldMutable)
assert(struct_decl.fields[2].storage == H.HostStorageBool(H.HostBoolI32, T.Moon2Core.ScalarI32))
assert(struct_decl.fields[3].attrs[1] == H.HostFieldNoalias)
assert(struct_decl.fields[3].storage == H.HostStorageBool(H.HostBoolU8, T.Moon2Core.ScalarU8))

print("moonlift mlua builder equivalence ok")
