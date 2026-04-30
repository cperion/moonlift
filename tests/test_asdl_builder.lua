package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Model = require("moonlift.asdl_model")
local Builder = require("moonlift.asdl_builder")
local DefineSchema = require("moonlift.context_define_schema")

local T = pvm.context()
Model.Define(T)
local A = Builder.Define(T)

local schema = A.schema {
    A.module "MoonCore" {
        A.product "Id" {
            A.field "text" "string",
            A.unique,
        },

        A.sum "Scalar" {
            A.variant "ScalarVoid",
            A.variant "ScalarBool",
            A.variant "ScalarI32",
            A.variant "ScalarI64",
        },

        A.sum "Literal" {
            A.variant "LitInt" {
                A.field "raw" "string",
                A.variant_unique,
            },
            A.variant "LitBool" {
                A.field "value" "boolean",
                A.variant_unique,
            },
            A.variant "LitNil",
        },
    },

    A.module "MoonDemo" {
        A.product "Type" {
            A.field "scalar" "MoonCore.Scalar",
            A.unique,
        },

        A.product "Module" {
            A.field "name" "string",
            A.field "types" (A.many "MoonDemo.Type"),
        },
    },
}

assert(pvm.classof(schema) == T.MoonAsdl.Schema)

-- Define directly from schema data (no text round-trip).
DefineSchema.define(T, schema)

local id = T.MoonCore.Id("x")
assert(id.text == "x")
assert(T.MoonCore.ScalarI32.kind == "ScalarI32")
local ty = T.MoonDemo.Type(T.MoonCore.ScalarI32)
assert(ty.scalar == T.MoonCore.ScalarI32)
local mod = T.MoonDemo.Module("demo", { ty })
assert(mod.name == "demo")
assert(#mod.types == 1)
assert(T.MoonCore.LitInt("7") == T.MoonCore.LitInt("7"))

io.write("moonlift asdl_builder ok\n")
