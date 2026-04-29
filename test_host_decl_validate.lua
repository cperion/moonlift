package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")
local HostDeclValidate = require("moonlift.host_decl_validate")

local T = pvm.context()
A.Define(T)
local V = HostDeclValidate.Define(T)
local H = T.Moon2Host
local Ty = T.Moon2Type
local C = T.Moon2Core

local function layout_id(name)
    return H.HostLayoutId("test." .. name, name)
end

local function field_id(owner, name)
    return H.HostFieldId("test." .. owner .. "." .. name, name)
end

local function scalar(s)
    return Ty.TScalar(s)
end

local function field(owner, name, expose_ty, storage)
    return H.HostFieldDecl(field_id(owner, name), name, expose_ty, storage or H.HostStorageSame, {})
end

local function struct_decl(name, fields, repr)
    return H.HostStructDecl(layout_id(name), name, repr or H.HostReprC, fields)
end

local function has_issue(report, cls)
    for i = 1, #report.issues do
        if pvm.classof(report.issues[i]) == cls then return true, report.issues[i] end
    end
    return false, nil
end

local User = struct_decl("User", {
    field("User", "id", scalar(C.ScalarI32)),
    field("User", "age", scalar(C.ScalarI32)),
    field("User", "active", scalar(C.ScalarBool), H.HostStorageBool(H.HostBoolI32, C.ScalarI32)),
})
local ok = V.validate(H.HostDeclSet({ H.HostDeclStruct(User) }))
assert(pvm.classof(ok) == H.HostReport)
assert(#ok.issues == 0)

local dup_fields = struct_decl("DupFields", {
    field("DupFields", "id", scalar(C.ScalarI32)),
    field("DupFields", "id", scalar(C.ScalarI32)),
})
local dup_field_report = V.validate(H.HostDeclSet({ H.HostDeclStruct(dup_fields) }))
assert(has_issue(dup_field_report, H.HostIssueDuplicateField))

local dup_decl_report = V.validate(H.HostDeclSet({ H.HostDeclStruct(User), H.HostDeclStruct(User) }))
assert(has_issue(dup_decl_report, H.HostIssueDuplicateDecl))

local bad_name = struct_decl("bad-name", {
    field("bad-name", "ok", scalar(C.ScalarI32)),
})
local bad_name_report = V.validate(H.HostDeclSet({ H.HostDeclStruct(bad_name) }))
assert(has_issue(bad_name_report, H.HostIssueInvalidName))

local bare_bool = struct_decl("BareBool", {
    field("BareBool", "active", scalar(C.ScalarBool), H.HostStorageSame),
})
local bare_bool_report = V.validate(H.HostDeclSet({ H.HostDeclStruct(bare_bool) }))
assert(has_issue(bare_bool_report, H.HostIssueBareBoolInBoundaryStruct))

local bad_packed = struct_decl("BadPacked", {
    field("BadPacked", "tag", scalar(C.ScalarU8)),
}, H.HostReprPacked(3))
local bad_packed_report = V.validate(H.HostDeclSet({ H.HostDeclStruct(bad_packed) }))
assert(has_issue(bad_packed_report, H.HostIssueInvalidPackedAlign))

local accessor = H.HostAccessorLua("User", "is_adult", "is_adult_impl")
local accessor_report = V.validate(H.HostDeclSet({ H.HostDeclAccessor(accessor) }))
assert(#accessor_report.issues == 0)

local expose = H.HostExposeDecl(
    H.HostExposePtr(Ty.TNamed(Ty.TypeRefGlobal("demo", "User"))),
    "UserRef",
    { H.HostExposeFacet(H.HostExposeLua, H.HostExposeAbiDefault, H.HostExposeProxy(H.HostProxyPtr, H.HostProxyCacheNone, H.HostReadonly, H.HostBoundsChecked)) }
)
local expose_report = V.validate(H.HostDeclSet({ H.HostDeclExpose(expose) }))
assert(#expose_report.issues == 0)
local dup_expose_report = V.validate(H.HostDeclSet({ H.HostDeclExpose(expose), H.HostDeclExpose(expose) }))
assert(has_issue(dup_expose_report, H.HostIssueDuplicateDecl))

print("moonlift host_decl_validate ok")
