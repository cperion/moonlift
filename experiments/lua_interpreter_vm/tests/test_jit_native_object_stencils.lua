-- Native object/table/call-boundary stencil tests.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local S = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local F = require("experiments.lua_interpreter_vm.src.jit.stencil_fixtures")
local N = require("experiments.lua_interpreter_vm.src.jit.native_runner")

if not N.supported then
    print("JIT native object stencils: skipped on " .. tostring(ffi.os) .. "/" .. tostring(ffi.arch))
    os.exit(0)
end

local Tag, Status = S.Tag, N.OutcomeStatus
local pass, fail = 0, 0
local units = {}

local function check(name, cond, detail)
    if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name .. (detail and (" -- " .. detail) or "")) end
end

local function setv(a, i, tag, aux, bits)
    a[i].tag = tag
    a[i].aux = aux or 0
    a[i].bits = bits or 0
end

local function checkv(name, a, i, tag, aux, bits)
    check(name .. ".tag", tonumber(a[i].tag) == tag, tostring(a[i].tag))
    check(name .. ".aux", tonumber(a[i].aux) == (aux or 0), tostring(a[i].aux))
    check(name .. ".bits", tonumber(a[i].bits) == (bits or 0), tostring(a[i].bits))
end

local function run_fixture(spec, stamps, fixups, vals)
    local fx = assert(F.first_fixture(spec), "missing fixture " .. spec)
    local unit = N.build_callable(fx, stamps, fixups)
    units[#units + 1] = unit
    unit.fn(vals)
    return unit
end

local table_id = 0x123456

-- GETFIELD shape IC: guard table identity, copy direct field Value to dst.
do
    local vals = N.new_values(8)
    local field = N.new_values(1)
    setv(vals, 1, Tag.TABLE, 0, table_id)
    setv(field, 0, Tag.INTEGER, 7, 99)
    run_fixture("table.getfield_shape_ic1.sT_kName_to_sA.next_or_slow", { a = 0, t = 1, table_ptr = table_id, value_ptr = field }, { side_exit = 0, side_exit_2 = 0 }, vals)
    checkv("GETFIELD dst", vals, 0, Tag.INTEGER, 7, 99)
end

-- SETFIELD shape IC: store source slot to direct field Value.
do
    local vals = N.new_values(8)
    local field = N.new_values(1)
    setv(vals, 1, Tag.TABLE, 0, table_id)
    setv(vals, 2, Tag.INTEGER, 3, 123)
    run_fixture("table.setfield_shape_ic1.sT_kName_sV.next_or_slow_or_barrier", { t = 1, v = 2, table_ptr = table_id, value_ptr = field }, { side_exit = 0, side_exit_2 = 0 }, vals)
    checkv("SETFIELD field", field, 0, Tag.INTEGER, 3, 123)
end

-- GETTABLE array IC: guard table identity and integer key, copy element.
do
    local vals = N.new_values(8)
    local elem = N.new_values(1)
    setv(vals, 1, Tag.TABLE, 0, table_id)
    setv(vals, 2, Tag.INTEGER, 0, 5)
    setv(elem, 0, Tag.TRUE, 0, 0)
    run_fixture("table.gettable_array_i64_ic1.sT_sK_to_sA.next_or_slow", { a = 0, t = 1, k = 2, table_ptr = table_id, expected_key = 5, value_ptr = elem }, { side_exit = 0, side_exit_2 = 0, side_exit_3 = 0, side_exit_4 = 0 }, vals)
    checkv("GETTABLE dst", vals, 0, Tag.TRUE, 0, 0)
end

-- SETTABLE array IC: guard table/key, store source into element.
do
    local vals = N.new_values(8)
    local elem = N.new_values(1)
    setv(vals, 1, Tag.TABLE, 0, table_id)
    setv(vals, 2, Tag.INTEGER, 0, 5)
    setv(vals, 3, Tag.INTEGER, 9, 321)
    run_fixture("table.settable_array_i64_ic1.sT_sK_sV.next_or_slow_or_barrier", { t = 1, k = 2, v = 3, table_ptr = table_id, expected_key = 5, value_ptr = elem }, { side_exit = 0, side_exit_2 = 0, side_exit_3 = 0, side_exit_4 = 0 }, vals)
    checkv("SETTABLE elem", elem, 0, Tag.INTEGER, 9, 321)
end

-- SELF field IC: copy receiver to A+1 and method to A.
do
    local vals = N.new_values(8)
    local method = N.new_values(1)
    setv(vals, 4, Tag.TABLE, 17, table_id)
    setv(method, 0, Tag.LCLOSURE, 0, 0x77)
    run_fixture("table.self_field_ic1.sObj_kName_to_sFunc_sSelf.next_or_slow", { obj = 4, self = 2, func = 1, table_ptr = table_id, value_ptr = method }, { side_exit = 0, side_exit_2 = 0 }, vals)
    checkv("SELF func", vals, 1, Tag.LCLOSURE, 0, 0x77)
    checkv("SELF receiver", vals, 2, Tag.TABLE, 17, table_id)
end

-- CALL boundary is observable through NativeJitOutcome.
do
    local block = N.build_block_with_outcome {
        { spec = "call.generic.sF_args.boundary", label = "call", fixups = { call_boundary = "boundary" } },
        { spec = "outcome.call_boundary", label = "boundary", stamps = { call_id = 55, resume_pc = 12 } },
    }
    units[#units + 1] = block
    local vals, out = N.new_values(4), N.new_outcome()
    block.fn(vals, out)
    check("CALL boundary status", tonumber(out[0].status) == Status.CALL_BOUNDARY, tostring(out[0].status))
    check("CALL boundary id", tonumber(out[0].exit_id) == 55, tostring(out[0].exit_id))
    check("CALL boundary pc", tonumber(out[0].pc) == 12, tostring(out[0].pc))
end

for _, u in ipairs(units) do N.free(u) end

print(string.format("JIT native object stencils: %d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
