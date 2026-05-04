-- MoonArrow: standalone ASDL schema for Apache Arrow type system.
--
-- Arrow types are an application domain, not part of the Moonlift compiler.
-- This defines its own PVM context and schema independently.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;./lib/?.lua;./lib/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Builder = require("moonlift.asdl_builder")

local T = pvm.context()
local A = Builder.Define(T)

local schema = A.schema {
    require("arrow.schema")(A),
}

-- Verify module exists
local function find_module(name)
    for i = 1, #schema.modules do
        if schema.modules[i].name == name then return schema.modules[i] end
    end
    error("module not found: " .. name)
end
local mod = find_module("MoonArrow")
assert(#mod.decls >= 10, "MoonArrow has at least 10 type declarations")

-- Define in context so we can use T.MoonArrow constructors
local DefineSchema = require("moonlift.context_define_schema")
DefineSchema.define(T, schema)
local A = T.MoonArrow

-- ===========================================================================
-- Type constructors (nullary = simple types)
-- ===========================================================================
assert(A.TypeNull.kind == "TypeNull")
assert(A.TypeBool.kind == "TypeBool")
assert(A.TypeInt32.kind == "TypeInt32")
assert(A.TypeInt64.kind == "TypeInt64")
assert(A.TypeUInt8.kind == "TypeUInt8")
assert(A.TypeFloat64.kind == "TypeFloat64")
assert(A.TypeDate32.kind == "TypeDate32")
assert(A.TypeUtf8.kind == "TypeUtf8")
assert(A.TypeBinary.kind == "TypeBinary")
assert(A.TypeLargeBinary.kind == "TypeLargeBinary")
assert(A.TypeLargeUtf8.kind == "TypeLargeUtf8")

-- ===========================================================================
-- Type constructors (parameterized)
-- ===========================================================================
local dec = A.TypeDecimal(38, 9, 128)
assert(dec.precision == 38 and dec.scale == 9 and dec.bit_width == 128)

local ts = A.TypeTimestamp(A.TimeUnitNanosecond, "UTC")
assert(ts.unit == A.TimeUnitNanosecond and ts.timezone == "UTC")

local fsb = A.TypeFixedSizeBinary(16)
assert(fsb.byte_width == 16)

-- ===========================================================================
-- Struct type
-- ===========================================================================
local struct_ty = A.TypeStruct({
    A.Field("id", A.TypeInt64, false),
    A.Field("name", A.TypeUtf8, true),
})
assert(#struct_ty.fields == 2)
assert(struct_ty.fields[1].name == "id")
assert(struct_ty.fields[2].nullable == true)

-- ===========================================================================
-- Nested types
-- ===========================================================================
local list_ty = A.TypeList(A.Field("item", A.TypeFloat64, true))
assert(list_ty.element.name == "item")

local map_ty = A.TypeMap(
    A.Field("key", A.TypeUtf8, false),
    A.Field("value", A.TypeInt32, true),
    true
)
assert(map_ty.keys_sorted == true)

-- ===========================================================================
-- Union
-- ===========================================================================
local union_ty = A.TypeUnion(
    A.UnionSparse,
    { 0, 1, 2 },
    {
        A.Field("i32", A.TypeInt32, true),
        A.Field("f64", A.TypeFloat64, true),
        A.Field("str", A.TypeUtf8, true),
    }
)
assert(union_ty.mode == A.UnionSparse)
assert(#union_ty.type_ids == 3)

-- ===========================================================================
-- Schema
-- ===========================================================================
local schema_val = A.Schema({
    A.Field("id", A.TypeInt64, false),
    A.Field("name", A.TypeUtf8, true),
    A.Field("score", A.TypeFloat64, true),
})
assert(#schema_val.fields == 3)
assert(schema_val.fields[1].nullable == false)
assert(schema_val.fields[3].type == A.TypeFloat64)

-- ===========================================================================
-- Layout
-- ===========================================================================
local primitive = A.Layout(
    { A.BufferSpec(A.BufferValidity, 0), A.BufferSpec(A.BufferData, 1) },
    {},
    false
)
assert(#primitive.buffers == 2)
assert(primitive.buffers[1].kind == A.BufferValidity)
assert(primitive.buffers[2].kind == A.BufferData)
assert(#primitive.children == 0)

local nested = A.Layout(
    { A.BufferSpec(A.BufferValidity, 0), A.BufferSpec(A.BufferOffsets, 1) },
    { primitive },   -- child array layout
    false
)
assert(#nested.buffers == 2)
assert(#nested.children == 1)

-- ===========================================================================
-- Value identity
-- ===========================================================================
assert(A.TypeInt32 == A.TypeInt32)
assert(A.TypeUtf8 == A.TypeUtf8)
assert(A.TypeDecimal(38, 9, 128) == A.TypeDecimal(38, 9, 128))
assert(A.TypeDecimal(38, 9, 128) ~= A.TypeDecimal(18, 6, 128))
assert(A.Field("x", A.TypeInt32, true) == A.Field("x", A.TypeInt32, true))
assert(A.Field("x", A.TypeInt32, true) ~= A.Field("y", A.TypeInt32, true))

-- ===========================================================================
-- IPC message types
-- ===========================================================================
local msg_schema = A.IpcSchema(schema_val)
local msg_batch = A.IpcRecordBatch(1024, { A.Field("col", A.TypeInt32, true) })
assert(msg_schema.schema == schema_val)
assert(msg_batch.row_count == 1024)

io.write("arrow schema ok\n")
