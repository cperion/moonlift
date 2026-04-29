package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local moon = require("moonlift.host")
local AsdlBuilder = require("moonlift.asdl_builder")
local SchemaValues = require("moonlift.pvm_surface_schema_values")

local T = moon.T
local A = AsdlBuilder.Define(T)
local Tr = T.MoonTree

local schema = A.schema {
    A.module "Demo" {
        A.product "Id" {
            A.field "text" "string",
            A.unique,
        },
        A.sum "Type" {
            A.variant "TScalar" {
                A.field "scalar" "Demo.Id",
                A.variant_unique,
            },
            A.variant "TPtr" {
                A.field "elem" "Demo.Type",
                A.variant_unique,
            },
            A.variant "TPair" {
                A.field "lhs" "Demo.Type",
                A.field "rhs" "Demo.Type",
                A.variant_unique,
            },
        },
    },
}

local module_value = SchemaValues.lower_schema(moon, schema, { module_name = "NativePvmSchemaTest" })
local module = module_value:to_asdl()
assert(#module.items >= 8)
local saw_id_struct = false
local saw_type_tagged_union = false
local saw_payload = false
for i = 1, #module.items do
    local item = module.items[i]
    if pvm.classof(item) == Tr.ItemType then
        if pvm.classof(item.t) == Tr.TypeDeclStruct and item.t.name == "Demo_Id" then saw_id_struct = true end
        if pvm.classof(item.t) == Tr.TypeDeclStruct and item.t.name == "Demo_Type_TPairPayload" then saw_payload = true end
        if pvm.classof(item.t) == Tr.TypeDeclTaggedUnionSugar and item.t.name == "Demo_Type" then
            saw_type_tagged_union = true
            assert(item.t.variants[1].name == "TScalar")
            assert(item.t.variants[2].name == "TPtr")
            assert(item.t.variants[3].name == "TPair")
        end
    end
end
assert(saw_id_struct)
assert(saw_payload)
assert(saw_type_tagged_union)

io.write("moonlift pvm_surface_schema_values ok\n")
