-- Smoke test: ASDL → Moonlift type emissions

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Types = require("moonlift.schema_types")

-- Verify the blob is non-empty and contains expected types
local blob = Types.declarations
assert(type(blob) == "string" and #blob > 1000, "declarations blob is non-empty")
assert(blob:match("type MoonCore_Name = struct"), "contains MoonCore_Name")
assert(blob:match("type MoonCore_Scalar = enum"), "contains MoonCore_Scalar enum")
assert(blob:match("type MoonCore_Literal ="), "contains MoonCore_Literal union")
assert(blob:match("type MoonTree_Expr ="), "contains MoonTree_Expr union")
assert(blob:match("type MoonType_Type ="), "contains MoonType_Type union")

-- Verify tags
local tags = Types.tags
assert(tags.MoonCore.Scalar_ScalarVoid == 0, "ScalarVoid is tag 0")
assert(tags.MoonCore.Scalar_ScalarI32 == 4, "ScalarI32 is tag 4")
assert(tags.MoonCore.Scalar_ScalarF64 == 11, "ScalarF64 is tag 11")
assert(tags.MoonCore.BinaryOp_BinAdd == 0, "BinAdd is tag 0")

-- Verify types table has entries
local ty = Types.types
assert(ty.MoonCore ~= nil, "MoonCore module exists")
assert(ty.MoonTree ~= nil, "MoonTree module exists")
assert(ty.MoonTree.Expr ~= nil, "MoonTree.Expr type exists")
assert(ty.MoonTree.ExprHeader ~= nil, "MoonTree.ExprHeader type exists")
assert(ty.MoonType.Type ~= nil, "MoonType.Type type exists")

print("schema_types smoke test ok")
print(string.format("  declarations: %d bytes, %d lines", #blob, select(2, blob:gsub("\n", "\n"))))
print(string.format("  types: %d modules", (function() local n = 0; for _ in pairs(ty) do n = n + 1 end; return n end)()))
