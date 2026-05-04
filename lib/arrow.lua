-- Arrow kernel library: compiled native operations on Arrow columnar arrays.
--
-- Loads and compiles bitmap, primitive, varlen, and nested kernel .mlua modules.
-- Returns a table of callable native function pointers.
--
-- Usage:
--   local arrow = require("arrow")
--   local count = arrow.bitmap_count_nulls(bitmap_ptr, 1024)

local Host = require("moonlift.host_quote")

local function load_kernel(path)
    local mod = Host.dofile(path)
    return mod:compile()
end

local bitmap    = load_kernel("lib/arrow/bitmap.mlua")
local primitive = load_kernel("lib/arrow/primitive.mlua")
local varlen    = load_kernel("lib/arrow/varlen.mlua")
local nested    = load_kernel("lib/arrow/nested.mlua")

local M = {}

-- Bitmap
M.bitmap_is_set       = bitmap:get("bitmap_is_set_fn")
M.bitmap_count_nulls  = bitmap:get("bitmap_count_nulls")
M.bitmap_count_valid  = bitmap:get("bitmap_count_valid")
M.bitmap_any_null     = bitmap:get("bitmap_any_null")

-- Primitive arrays
M.i32_get             = primitive:get("i32_get")
M.i64_get             = primitive:get("i64_get")
M.f64_get             = primitive:get("f64_get")
M.i32_slice           = primitive:get("i32_slice")
M.f64_slice           = primitive:get("f64_slice")
M.i32_filter          = primitive:get("i32_filter")
M.f64_filter          = primitive:get("f64_filter")
M.i32_sum             = primitive:get("i32_sum")
M.f64_sum             = primitive:get("f64_sum")

-- Variable-length arrays
M.varlen_len_i32      = varlen:get("varlen_len_i32")
M.varlen_get_i32      = varlen:get("varlen_get_i32")
M.varlen_copy_i32     = varlen:get("varlen_copy_i32")
M.varlen_total_size_i32 = varlen:get("varlen_total_size_i32")
M.varlen_count_valid_i32 = varlen:get("varlen_count_valid_i32")

-- Nested arrays
M.list_slice_i32      = nested:get("list_slice_i32")
M.struct_is_valid     = nested:get("struct_is_valid")
M.fsl_slice           = nested:get("fsl_slice")

-- Cleanup
function M.free()
    bitmap:free()
    primitive:free()
    varlen:free()
    nested:free()
end

return M
