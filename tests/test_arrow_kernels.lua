-- Arrow kernel library: correctness suite.
--
-- Tests bitmap ops, primitive array access, variable-length arrays,
-- nested arrays (list, struct), and IPC buffer layout helpers.

local bit = require("bit")
local ffi = require("ffi")
local arrow = require("arrow")

-- ===========================================================================
-- Helpers: construct Arrow buffers with FFI
-- ===========================================================================

local function alloc_i32(n)
    return ffi.new("int32_t[?]", n)
end

local function alloc_u8(n)
    return ffi.new("uint8_t[?]", n)
end

local function alloc_f64(n)
    return ffi.new("double[?]", n)
end

-- Build a null bitmap: 1 bit per element, LSB-first
-- 'nulls' is a table of indices (0-based) that are null
local function make_bitmap(n, nulls)
    if not nulls or #nulls == 0 then return nil end
    local bytes = math.ceil(n / 8)
    local bm = alloc_u8(bytes)
    for i = 0, bytes - 1 do bm[i] = 0xFF end   -- all valid
    for _, ni in ipairs(nulls) do
        local byte = math.floor(ni / 8)
        local bit = ni % 8
        bm[byte] = bit.band(bm[byte], bit.bnot(bit.lshift(1, bit)))  -- clear = null
    end
    return bm
end

-- ===========================================================================
-- Bitmap tests
-- ===========================================================================

local N = 128
local bm = make_bitmap(N, { 0, 5, 63, 64, 100, 127 })

-- is_valid
local function is_valid_lua(bitmap, n, i)
    if bitmap == nil then return true end
    local byte = math.floor(i / 8)
    local bit = i % 8
    return bit.band(bit.rshift(bitmap[byte], bit), 1) == 1
end

for _, i in ipairs({ 0, 5, 63, 64, 100, 127, 1, 10, 62, 65, 99, 126 }) do
    local out = alloc_i32(1)
    out[0] = -1
    arrow.bitmap_is_set(bm, i, out)
    assert(out[0] == (is_valid_lua(bm, N, i) and 1 or 0),
        string.format("bitmap_is_set failed at i=%d", i))
end

-- null bitmap pointer = nil means all valid
local out = alloc_i32(1)
arrow.bitmap_is_set(nil, 999, out)
assert(out[0] == 1, "nil bitmap should always return valid")

-- count_nulls
assert(arrow.bitmap_count_nulls(bm, N) == 6, "count_nulls should be 6")
assert(arrow.bitmap_count_nulls(nil, N) == 0, "nil bitmap should have 0 nulls")

-- count_valid
assert(arrow.bitmap_count_valid(bm, N) == N - 6, "count_valid should be N - 6")
assert(arrow.bitmap_count_valid(nil, N) == N, "nil bitmap: all valid")

-- any_null
local any = alloc_i32(1)
arrow.bitmap_any_null(bm, 0, N, any)
assert(any[0] == 1, "any_null should find null at index 0")
arrow.bitmap_any_null(bm, 10, 52, any)
assert(any[0] == 1, "any_null should find nulls in [10,62)")
arrow.bitmap_any_null(bm, 65, 34, any)
assert(any[0] == 1, "any_null should find nulls in [65,99)")
arrow.bitmap_any_null(bm, 70, 20, any)
assert(any[0] == 0, "any_null should find no nulls in [70,90)")

io.write("bitmap ok\n")

-- ===========================================================================
-- Primitive array tests
-- ===========================================================================

local N = 100
local i32_vals = alloc_i32(N)
for i = 0, N - 1 do i32_vals[i] = i * 10 end
local i32_bm = make_bitmap(N, { 3, 7, 42 })

-- i32_get
local val = alloc_i32(1)
local valid = alloc_i32(1)
valid[0] = -1

for i = 0, N - 1 do
    arrow.i32_get(i32_bm, i32_vals, i, val, valid)
    if is_valid_lua(i32_bm, N, i) then
        assert(valid[0] == 1 and val[0] == i * 10,
            string.format("i32_get valid failed at i=%d: got %d/%d", i, val[0], valid[0]))
    else
        assert(valid[0] == 0, string.format("i32_get null failed at i=%d", i))
    end
end

-- i32_get with nil bitmap
for i = 0, N - 1 do
    arrow.i32_get(nil, i32_vals, i, val, valid)
    assert(valid[0] == 1 and val[0] == i * 10,
        string.format("i32_get nil bitmap failed at i=%d", i))
end

io.write("primitive get ok\n")

-- i32_sum
assert(arrow.i32_sum(i32_bm, i32_vals, N) == 49500 - 30 - 70 - 420,
    "i32_sum with nulls")
assert(arrow.i32_sum(nil, i32_vals, N) == 49500,
    "i32_sum without nulls")

-- f64_sum
local f64_vals = alloc_f64(50)
for i = 0, 49 do f64_vals[i] = i * 1.5 end
local expected_f64 = 0
for i = 0, 49 do expected_f64 = expected_f64 + i * 1.5 end
local got_f64 = arrow.f64_sum(nil, f64_vals, 50)
assert(math.abs(got_f64 - expected_f64) < 0.001,
    string.format("f64_sum: expected %.1f got %.1f", expected_f64, got_f64))

io.write("primitive sum ok\n")

-- i32_filter
local mask = make_bitmap(20, { 1, 3, 5, 7, 9, 11, 13, 15, 17, 19 })
local src = alloc_i32(20)
for i = 0, 19 do src[i] = i * 100 end
local dst = alloc_i32(20)
local written = arrow.i32_filter(nil, src, mask, 20, dst)
assert(written == 10, "filter should select 10 elements")
for i = 0, written - 1 do
    assert(dst[i] % 200 == 0, "filter should select even indices only")
end

io.write("primitive filter ok\n")

-- ===========================================================================
-- Variable-length array tests
-- ===========================================================================
-- Build: ["hello", null, "world", "moonlift", null, "arrow"]
local strings = { "hello", "world", "moonlift", "arrow" }
local nulls_varlen = { 1, 4 }

-- offsets array (i32, N+1 = 7 elements)
local offsets = alloc_i32(7)
offsets[0] = 0
local total_bytes = 0
local si = 0
for i = 0, 5 do
    if nulls_varlen[i] ~= i then
        total_bytes = total_bytes + #strings[si + 1]
        si = si + 1
    end
    offsets[i + 1] = total_bytes
end

-- data array
local data = alloc_u8(total_bytes)
local pos = 0
si = 0
for i = 0, 5 do
    if not (nulls_varlen[1] == i or (nulls_varlen[2] and nulls_varlen[2] == i)) then
        local s = strings[si + 1]
        for j = 1, #s do
            data[pos] = string.byte(s, j)
            pos = pos + 1
        end
        si = si + 1
    end
end

local varlen_bm = make_bitmap(6, { 1, 4 })

-- varlen_len_i32
local vlen = alloc_i32(1)
local vvalid = alloc_i32(1)

-- Index 0: "hello", valid
arrow.varlen_len_i32(varlen_bm, offsets, 0, vlen, vvalid)
assert(vvalid[0] == 1 and vlen[0] == 5, string.format("varlen[0]: valid=%d len=%d", vvalid[0], vlen[0]))

-- Index 1: null
arrow.varlen_len_i32(varlen_bm, offsets, 1, vlen, vvalid)
assert(vvalid[0] == 0, "varlen[1] should be null")

-- Index 3: "moonlift", valid
arrow.varlen_len_i32(varlen_bm, offsets, 3, vlen, vvalid)
assert(vvalid[0] == 1 and vlen[0] == 8, string.format("varlen[3]: valid=%d len=%d", vvalid[0], vlen[0]))

-- varlen_get_i32: get pointer and length
local vptr = ffi.new("uint8_t*[1]")
local vlen2 = alloc_i32(1)
local vvalid2 = alloc_i32(1)

arrow.varlen_get_i32(varlen_bm, offsets, data, 0, vptr, vlen2, vvalid2)
assert(vvalid2[0] == 1 and vlen2[0] == 5)
local chars = {}
for j = 0, 4 do chars[#chars + 1] = string.char(vptr[0][j]) end
assert(table.concat(chars) == "hello", "varlen_get[0] content")

-- varlen with nil bitmap (all valid)
arrow.varlen_get_i32(nil, offsets, data, 0, vptr, vlen2, vvalid2)
assert(vvalid2[0] == 1 and vlen2[0] == 5)

io.write("varlen ok\n")

-- ===========================================================================
-- List array tests
-- ===========================================================================
-- List of [i32]: [[10, 20], null, [30, 40, 50]]
local list_offsets = alloc_i32(4)
list_offsets[0] = 0
list_offsets[1] = 2
list_offsets[2] = 2      -- null element, offsets are equal
list_offsets[3] = 5

local list_bm = make_bitmap(3, { 1 })  -- index 1 is null

local lstart = alloc_i32(1)
local llen = alloc_i32(1)
local lvalid = alloc_i32(1)

-- List element 0: [10, 20]
arrow.list_slice_i32(list_bm, list_offsets, 0, lstart, llen, lvalid)
assert(lvalid[0] == 1 and lstart[0] == 0 and llen[0] == 2, "list[0]")

-- List element 1: null
arrow.list_slice_i32(list_bm, list_offsets, 1, lstart, llen, lvalid)
assert(lvalid[0] == 0, "list[1] should be null")

-- List element 2: [30, 40, 50]
arrow.list_slice_i32(list_bm, list_offsets, 2, lstart, llen, lvalid)
assert(lvalid[0] == 1 and lstart[0] == 2 and llen[0] == 3, "list[2]")

io.write("nested list ok\n")

-- ===========================================================================
-- Struct validity tests
-- ===========================================================================
local struct_bm = make_bitmap(5, { 2, 4 })
local svalid = alloc_i32(1)

arrow.struct_is_valid(struct_bm, 0, svalid)
assert(svalid[0] == 1, "struct[0] valid")
arrow.struct_is_valid(struct_bm, 2, svalid)
assert(svalid[0] == 0, "struct[2] null")
arrow.struct_is_valid(nil, 999, svalid)
assert(svalid[0] == 1, "struct nil bitmap = valid")

io.write("nested struct ok\n")

-- ===========================================================================
-- Cleanup
-- ===========================================================================
arrow.free()

return "arrow kernel library ok"
