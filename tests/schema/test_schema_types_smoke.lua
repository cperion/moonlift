-- Smoke test: ASDL → Lalin type emissions

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Types = require("lalin.schema_types")

-- Verify the blob is non-empty and contains expected types
local blob = Types.declarations
assert(type(blob) == "string" and #blob > 1000, "declarations blob is non-empty")
assert(blob:match("type LalinCore_Name = struct"), "contains LalinCore_Name")
assert(blob:match("type LalinCore_Scalar = enum"), "contains LalinCore_Scalar enum")
assert(blob:match("type LalinCore_Literal ="), "contains LalinCore_Literal union")
assert(blob:match("type LalinTree_Expr ="), "contains LalinTree_Expr union")
assert(blob:match("type LalinType_Type ="), "contains LalinType_Type union")

-- Verify tags
local tags = Types.tags
assert(tags.LalinCore.Scalar_ScalarVoid == 0, "ScalarVoid is tag 0")
assert(tags.LalinCore.Scalar_ScalarI32 == 4, "ScalarI32 is tag 4")
assert(tags.LalinCore.Scalar_ScalarF64 == 11, "ScalarF64 is tag 11")
assert(tags.LalinCore.BinaryOp_BinAdd == 0, "BinAdd is tag 0")

-- Verify types table has entries
local ty = Types.types
assert(ty.LalinCore ~= nil, "LalinCore module exists")
assert(ty.LalinTree ~= nil, "LalinTree module exists")
assert(ty.LalinTree.Expr ~= nil, "LalinTree.Expr type exists")
assert(ty.LalinTree.ExprHeader ~= nil, "LalinTree.ExprHeader type exists")
assert(ty.LalinType.Type ~= nil, "LalinType.Type type exists")

print("schema_types smoke test ok")
print(string.format("  declarations: %d bytes, %d lines", #blob, select(2, blob:gsub("\n", "\n"))))
print(string.format("  types: %d modules", (function() local n = 0; for _ in pairs(ty) do n = n + 1 end; return n end)()))
