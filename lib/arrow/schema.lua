-- Clean MoonArrow schema: Apache Arrow type system as ASDL.
--
-- Mirrors the Arrow columnar format specification v24.0.0.
-- Every Arrow data type and layout concept is represented as an explicit ASDL
-- sum variant or product, consumed by Moonlift PVM phases.
--
-- References:
--   https://arrow.apache.org/docs/format/Columnar.html

return function(A)
    return A.module "MoonArrow" {

        -- ===================================================================
        -- Time / date units
        -- ===================================================================

        A.sum "TimeUnit" {
            A.variant "TimeUnitSecond",
            A.variant "TimeUnitMillisecond",
            A.variant "TimeUnitMicrosecond",
            A.variant "TimeUnitNanosecond",
        },

        A.sum "IntervalUnit" {
            A.variant "IntervalYearMonth",
            A.variant "IntervalDayTime",
            A.variant "IntervalMonthDayNano",
        },

        -- ===================================================================
        -- Union mode
        -- ===================================================================

        A.sum "UnionMode" {
            A.variant "UnionSparse",
            A.variant "UnionDense",
        },

        -- ===================================================================
        -- Data types
        -- ===================================================================

        A.sum "Type" {
            -- Null: all values are null, no physical storage
            A.variant "TypeNull",

            -- Boolean: 1-bit values, LSB-packed
            A.variant "TypeBool",

            -- Signed integers
            A.variant "TypeInt8",
            A.variant "TypeInt16",
            A.variant "TypeInt32",
            A.variant "TypeInt64",

            -- Unsigned integers
            A.variant "TypeUInt8",
            A.variant "TypeUInt16",
            A.variant "TypeUInt32",
            A.variant "TypeUInt64",

            -- Floating point (Float16 is 2-byte IEEE 754 half precision)
            A.variant "TypeFloat16",
            A.variant "TypeFloat32",
            A.variant "TypeFloat64",

            -- Decimal: fixed-precision decimal
            A.variant "TypeDecimal" {
                A.field "precision" "number",   -- total digits
                A.field "scale" "number",       -- digits after decimal point
                A.field "bit_width" "number",   -- 128 or 256
                A.variant_unique,
            },

            -- Date types
            A.variant "TypeDate32",             -- days since epoch, i32
            A.variant "TypeDate64",             -- milliseconds since epoch, i64

            -- Time types (time of day, no date)
            A.variant "TypeTime32" {
                A.field "unit" "MoonArrow.TimeUnit",
                A.variant_unique,
            },
            A.variant "TypeTime64" {
                A.field "unit" "MoonArrow.TimeUnit",
                A.variant_unique,
            },

            -- Timestamp: absolute point in time
            A.variant "TypeTimestamp" {
                A.field "unit" "MoonArrow.TimeUnit",
                A.field "timezone" "string",    -- empty string = no timezone (UTC)
                A.variant_unique,
            },

            -- Duration: elapsed time interval
            A.variant "TypeDuration" {
                A.field "unit" "MoonArrow.TimeUnit",
                A.variant_unique,
            },

            -- Interval: calendar interval
            A.variant "TypeInterval" {
                A.field "unit" "MoonArrow.IntervalUnit",
                A.variant_unique,
            },

            -- Binary: variable-length byte arrays
            A.variant "TypeBinary",
            A.variant "TypeLargeBinary",

            -- String: UTF-8 encoded text
            A.variant "TypeUtf8",
            A.variant "TypeLargeUtf8",

            -- Fixed-size binary: N bytes per element
            A.variant "TypeFixedSizeBinary" {
                A.field "byte_width" "number",
                A.variant_unique,
            },

            -- List: variable-length sequence of child type
            A.variant "TypeList" {
                A.field "element" "MoonArrow.Field",
                A.variant_unique,
            },
            A.variant "TypeLargeList" {
                A.field "element" "MoonArrow.Field",
                A.variant_unique,
            },

            -- Fixed-size list: N elements per list
            A.variant "TypeFixedSizeList" {
                A.field "list_size" "number",
                A.field "element" "MoonArrow.Field",
                A.variant_unique,
            },

            -- Struct: ordered collection of typed fields
            A.variant "TypeStruct" {
                A.field "fields" (A.many "MoonArrow.Field"),
                A.variant_unique,
            },

            -- Union: one of several types
            A.variant "TypeUnion" {
                A.field "mode" "MoonArrow.UnionMode",
                A.field "type_ids" (A.many "number"),  -- i8 discriminants
                A.field "fields" (A.many "MoonArrow.Field"),
                A.variant_unique,
            },

            -- Map: list of key-value structs with sorted unique keys
            A.variant "TypeMap" {
                A.field "key" "MoonArrow.Field",
                A.field "value" "MoonArrow.Field",
                A.field "keys_sorted" "boolean",
                A.variant_unique,
            },

            -- Dictionary: dictionary-encoded array
            A.variant "TypeDictionary" {
                A.field "index_type" "MoonArrow.Type",
                A.field "value_type" "MoonArrow.Type",
                A.field "ordered" "boolean",
                A.variant_unique,
            },

            -- Run-end encoded: compressed runs
            A.variant "TypeRunEndEncoded" {
                A.field "run_end_type" "MoonArrow.Type",  -- Int16/32/64
                A.field "value_type" "MoonArrow.Type",
                A.variant_unique,
            },
        },

        -- ===================================================================
        -- Field: a named, typed, nullable column
        -- ===================================================================

        A.product "Field" {
            A.field "name" "string",
            A.field "type" "MoonArrow.Type",
            A.field "nullable" "boolean",
            A.unique,
        },

        -- ===================================================================
        -- Schema: ordered list of fields
        -- ===================================================================

        A.product "Schema" {
            A.field "fields" (A.many "MoonArrow.Field"),
            A.unique,
        },

        -- ===================================================================
        -- Physical layout descriptor
        -- ===================================================================

        A.sum "BufferKind" {
            A.variant "BufferValidity",     -- null bitmap
            A.variant "BufferData",         -- type-specific data
            A.variant "BufferOffsets",      -- variable-length offsets
            A.variant "BufferTypeIds",      -- union type ids
            A.variant "BufferSizes",        -- large list sizes (optional)
        },

        A.product "BufferSpec" {
            A.field "kind" "MoonArrow.BufferKind",
            A.field "index" "number",       -- 0-based index in the array's buffer list
            A.unique,
        },

        A.product "Layout" {
            A.field "buffers" (A.many "MoonArrow.BufferSpec"),
            A.field "children" (A.many "MoonArrow.Layout"),  -- child array layouts
            A.field "variadic" "boolean",   -- true if last buffer is variadic
            A.unique,
        },

        -- ===================================================================
        -- Type metadata: non-semantic key-value annotations
        -- ===================================================================

        A.product "KeyValue" {
            A.field "key" "string",
            A.field "value" "string",
            A.unique,
        },

        -- ===================================================================
        -- Semantic classification helpers (for PVM phase dispatch)
        -- ===================================================================

        A.sum "TypeClass" {
            A.variant "TypeClassNull",
            A.variant "TypeClassBoolean",
            A.variant "TypeClassInteger",       -- all Int*/UInt*
            A.variant "TypeClassFloat",         -- Float16/32/64
            A.variant "TypeClassDecimal",
            A.variant "TypeClassDate",
            A.variant "TypeClassTime",
            A.variant "TypeClassTimestamp",
            A.variant "TypeClassDuration",
            A.variant "TypeClassInterval",
            A.variant "TypeClassBinary",        -- all Binary/Utf8 + FixedSizeBinary
            A.variant "TypeClassList",          -- all List/LargeList/FixedSizeList/Map
            A.variant "TypeClassStruct",
            A.variant "TypeClassUnion",
            A.variant "TypeClassDictionary",
            A.variant "TypeClassRunEndEncoded",
        },

        A.sum "WidthClass" {
            A.variant "Width8",
            A.variant "Width16",
            A.variant "Width32",
            A.variant "Width64",
            A.variant "Width128",
            A.variant "Width256",
            A.variant "WidthVariable",
        },

        -- ===================================================================
        -- IPC message types (for the binary protocol layer)
        -- ===================================================================

        A.sum "IpcMessage" {
            A.variant "IpcSchema" {
                A.field "schema" "MoonArrow.Schema",
                A.variant_unique,
            },
            A.variant "IpcRecordBatch" {
                A.field "row_count" "number",
                A.field "columns" (A.many "MoonArrow.Field"),
                A.variant_unique,
            },
            A.variant "IpcDictionaryBatch",
            A.variant "IpcRecordBatchEnd",
        },

    }
end
