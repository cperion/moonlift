-- MoonArrow schema validation: type system, fields, schemas, layouts.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
local schema = Schema.schema(T)

-- Verify MoonArrow module exists
local found = false
for i = 1, #schema.modules do
    if schema.modules[i].name == "MoonArrow" then found = true; break end
end
assert(found, "MoonArrow module is registered")

Schema.Define(T)
local A = T.MoonArrow

-- ===========================================================================
-- Time units
-- ===========================================================================
assert(A.TimeUnitSecond.kind == "TimeUnitSecond")
assert(A.TimeUnitMillisecond.kind == "TimeUnitMillisecond")
assert(A.TimeUnitMicrosecond.kind == "TimeUnitMicrosecond")
assert(A.TimeUnitNanosecond.kind == "TimeUnitNanosecond")

-- ===========================================================================
-- Interval units
-- ===========================================================================
assert(A.IntervalYearMonth.kind == "IntervalYearMonth")
assert(A.IntervalDayTime.kind == "IntervalDayTime")
assert(A.IntervalMonthDayNano.kind == "IntervalMonthDayNano")

-- ===========================================================================
-- Union mode
-- ===========================================================================
assert(A.UnionSparse.kind == "UnionSparse")
assert(A.UnionDense.kind == "UnionDense")

-- ===========================================================================
-- Type constructors (nullary variants)
-- ===========================================================================
assert(A.TypeNull.kind == "TypeNull")
assert(A.TypeBool.kind == "TypeBool")

-- Integers
assert(A.TypeInt8.kind == "TypeInt8")
assert(A.TypeInt16.kind == "TypeInt16")
assert(A.TypeInt32.kind == "TypeInt32")
assert(A.TypeInt64.kind == "TypeInt64")
assert(A.TypeUInt8.kind == "TypeUInt8")
assert(A.TypeUInt16.kind == "TypeUInt16")
assert(A.TypeUInt32.kind == "TypeUInt32")
assert(A.TypeUInt64.kind == "TypeUInt64")

-- Floats
assert(A.TypeFloat16.kind == "TypeFloat16")
assert(A.TypeFloat32.kind == "TypeFloat32")
assert(A.TypeFloat64.kind == "TypeFloat64")

-- Date
assert(A.TypeDate32.kind == "TypeDate32")
assert(A.TypeDate64.kind == "TypeDate64")

-- Binary / Utf8
assert(A.TypeBinary.kind == "TypeBinary")
assert(A.TypeLargeBinary.kind == "TypeLargeBinary")
assert(A.TypeUtf8.kind == "TypeUtf8")
assert(A.TypeLargeUtf8.kind == "TypeLargeUtf8")

-- ===========================================================================
-- Type constructors (parameterized variants)
-- ===========================================================================

-- Decimal(precision, scale, bit_width)
local dec = A.TypeDecimal(38, 9, 128)
assert(dec.precision == 38)
assert(dec.scale == 9)
assert(dec.bit_width == 128)

-- Time32(unit) and Time64(unit)
local t32 = A.TypeTime32(A.TimeUnitMillisecond)
assert(t32.unit == A.TimeUnitMillisecond)
local t64 = A.TypeTime64(A.TimeUnitNanosecond)
assert(t64.unit == A.TimeUnitNanosecond)

-- Timestamp(unit, timezone)
local ts_utc = A.TypeTimestamp(A.TimeUnitMicrosecond, "")
assert(ts_utc.timezone == "")
local ts_ny = A.TypeTimestamp(A.TimeUnitMillisecond, "America/New_York")
assert(ts_ny.timezone == "America/New_York")

-- Duration(unit)
local dur = A.TypeDuration(A.TimeUnitNanosecond)
assert(dur.unit == A.TimeUnitNanosecond)

-- Interval(unit)
local interval = A.TypeInterval(A.IntervalDayTime)
assert(interval.unit == A.IntervalDayTime)

-- FixedSizeBinary(byte_width)
local fsb = A.TypeFixedSizeBinary(16)
assert(fsb.byte_width == 16)

-- TypeStruct(fields)
local struct_ty = A.TypeStruct({
    A.Field("id", A.TypeInt64, false),
    A.Field("name", A.TypeUtf8, true),
})
assert(#struct_ty.fields == 2)
assert(struct_ty.fields[1].name == "id")
assert(struct_ty.fields[1].type == A.TypeInt64)
assert(struct_ty.fields[1].nullable == false)
assert(struct_ty.fields[2].nullable == true)

-- TypeUnion(mode, type_ids, fields)
local union_ty = A.TypeUnion(
    A.UnionSparse,
    { 0, 1 },
    {
        A.Field("int_val", A.TypeInt32, true),
        A.Field("str_val", A.TypeUtf8, true),
    }
)
assert(union_ty.mode == A.UnionSparse)
assert(union_ty.type_ids[1] == 0)
assert(union_ty.type_ids[2] == 1)

-- TypeMap(key, value, keys_sorted)
local map_ty = A.TypeMap(
    A.Field("key", A.TypeUtf8, false),
    A.Field("value", A.TypeInt64, true),
    true
)
assert(map_ty.keys_sorted == true)
assert(map_ty.key.type == A.TypeUtf8)

-- TypeDictionary(index_type, value_type, ordered)
local dict_ty = A.TypeDictionary(A.TypeUInt32, A.TypeUtf8, false)
assert(dict_ty.index_type == A.TypeUInt32)
assert(dict_ty.value_type == A.TypeUtf8)
assert(dict_ty.ordered == false)

-- TypeRunEndEncoded(run_end_type, value_type)
local ree_ty = A.TypeRunEndEncoded(A.TypeInt32, A.TypeFloat64)
assert(ree_ty.run_end_type == A.TypeInt32)
assert(ree_ty.value_type == A.TypeFloat64)

-- ===========================================================================
-- Field and Schema
-- ===========================================================================

local f1 = A.Field("id", A.TypeInt32, false)
assert(f1.name == "id")
assert(f1.nullable == false)

local f2 = A.Field("value", A.TypeFloat64, true)
local schema_val = A.Schema({ f1, f2 })
assert(#schema_val.fields == 2)
assert(schema_val.fields[1].name == "id")
assert(schema_val.fields[2].nullable == true)

-- ===========================================================================
-- Layout
-- ===========================================================================

local buf_val = A.BufferSpec(A.BufferValidity, 0)
assert(buf_val.kind == A.BufferValidity)
assert(buf_val.index == 0)

local primitive_layout = A.Layout(
    { A.BufferSpec(A.BufferValidity, 0), A.BufferSpec(A.BufferData, 1) },
    {},
    false
)
assert(#primitive_layout.buffers == 2)
assert(primitive_layout.buffers[1].kind == A.BufferValidity)
assert(primitive_layout.buffers[2].kind == A.BufferData)
assert(#primitive_layout.children == 0)
assert(primitive_layout.variadic == false)

-- ===========================================================================
-- TypeClass (classification helpers for PVM phase dispatch)
-- ===========================================================================
local cls_int = A.TypeClassInteger
local cls_flt = A.TypeClassFloat
local cls_struct = A.TypeClassStruct
local cls_list = A.TypeClassList
assert(cls_int ~= cls_flt)
assert(cls_struct ~= cls_list)

-- ===========================================================================
-- IPC message types
-- ===========================================================================
local schema_msg = A.IpcSchema(schema_val)
local batch_msg = A.IpcRecordBatch(100, { f1, f2 })
assert(schema_msg.schema == schema_val)
assert(batch_msg.row_count == 100)
assert(#batch_msg.columns == 2)

-- ===========================================================================
-- Value identity (uniques)
-- ===========================================================================
-- Same constructors produce equal values
assert(A.TypeInt32 == A.TypeInt32)
assert(A.TypeFloat64 == A.TypeFloat64)
assert(A.TypeUtf8 == A.TypeUtf8)
-- Parameterized types with same parameters are equal
assert(A.TypeDecimal(38, 9, 128) == A.TypeDecimal(38, 9, 128))
assert(A.TypeDecimal(38, 9, 128) ~= A.TypeDecimal(18, 6, 128))
-- Same fields
assert(A.Field("x", A.TypeInt32, true) == A.Field("x", A.TypeInt32, true))
assert(A.Field("x", A.TypeInt32, true) ~= A.Field("y", A.TypeInt32, true))

io.write("moonlift schema_arrow ok\n")
