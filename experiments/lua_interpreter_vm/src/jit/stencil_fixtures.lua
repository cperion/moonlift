-- Copy-and-patch stencil fixtures and materializer v0.
--
-- A CodeStencilSpec in stencil_library.lua is the semantic contract.  A
-- StencilFixture is the physical byte phrase that implements that contract.
-- This file starts the physical lane with real executable x86-64 snippet
-- fixtures for the straight-line baseline subset.  Fixtures that cannot be
-- executed and checked against the interpreter do not belong here yet.

local stencils = require("experiments.lua_interpreter_vm.src.jit.stencil_library")
local const = require("experiments.lua_interpreter_vm.src.constants")

local M = {}

local VALUE_SIZE = 16
local FIELD = { tag = 0, aux = 4, bits = 8 }

M.VALUE_SIZE = VALUE_SIZE
M.FIELD = FIELD

local function copy_list(xs)
    local out = {}
    for i, v in ipairs(xs or {}) do out[i] = v end
    return out
end

local function stamp_number(n)
    if type(n) == "cdata" then
        local ffi = require("ffi")
        n = tonumber(ffi.cast("uintptr_t", n))
    end
    assert(type(n) == "number", "numeric stamp required")
    return n
end

local function le_bytes(n, width)
    n = stamp_number(n)
    if n < 0 then n = n + 2 ^ (width * 8) end
    local out = {}
    for i = 1, width do
        out[i] = n % 256
        n = math.floor(n / 256)
    end
    return out
end

local function write_le(bytes, offset, width, value)
    local bs = le_bytes(value, width)
    for i = 1, width do bytes[offset + i] = bs[i] end
end

local function read_le(bytes, offset, width)
    local n, mul = 0, 1
    for i = 1, width do
        n = n + (bytes[offset + i] or 0) * mul
        mul = mul * 256
    end
    return n
end

local function bytes_hex(bytes)
    local out = {}
    for i, b in ipairs(bytes or {}) do out[i] = string.format("%02x", b) end
    return table.concat(out, " ")
end

M.le_bytes = le_bytes
M.read_le = read_le
M.bytes_hex = bytes_hex

local function byte_builder()
    local b = { bytes = {}, holes = {}, relocs = {} }

    function b:emit(...)
        local xs = { ... }
        for _, x in ipairs(xs) do
            assert(x >= 0 and x <= 255 and x % 1 == 0, "byte expected")
            self.bytes[#self.bytes + 1] = x
        end
        return self
    end

    function b:hole(spec)
        spec = spec or {}
        local width = assert(spec.width, "hole width required")
        local h = {
            name = assert(spec.name, "hole name required"),
            kind = assert(spec.kind, "hole kind required"),
            offset = #self.bytes,
            width = width,
            param = spec.param,
            field = spec.field,
            required = spec.required ~= false,
            note = spec.note or "",
        }
        self.holes[#self.holes + 1] = h
        for _ = 1, width do self.bytes[#self.bytes + 1] = 0 end
        return h
    end

    function b:reloc(spec)
        spec = spec or {}
        local width = assert(spec.width, "reloc width required")
        local r = {
            name = assert(spec.name, "reloc name required"),
            kind = assert(spec.kind, "reloc kind required"),
            offset = #self.bytes,
            width = width,
            required = spec.required ~= false,
            note = spec.note or "",
        }
        self.relocs[#self.relocs + 1] = r
        for _ = 1, width do self.bytes[#self.bytes + 1] = 0 end
        return r
    end

    return b
end

local function slot_hole(b, name, param, field)
    b:hole { name = name, kind = "slot_disp", width = 4, param = param, field = field }
end

local function imm_hole(b, name, kind, width, param)
    b:hole { name = name, kind = kind, width = width, param = param or name }
end

local function make_fixture(spec)
    assert(stencils.by_name[spec.spec_name], "fixture references unknown stencil spec " .. tostring(spec.spec_name))
    local fixture = {
        kind = "StencilFixture",
        name = spec.name or (spec.spec_name .. ".fixture0"),
        spec_name = spec.spec_name,
        executable = spec.executable ~= false,
        abi = spec.abi or "abstract-x64-snippet-v1",
        bytes = copy_list(assert(spec.bytes, "fixture bytes required")),
        holes = copy_list(spec.holes),
        relocs = copy_list(spec.relocs),
        clobbers = spec.clobbers or {},
        note = spec.note or "",
    }
    return fixture
end

M.StencilFixture = make_fixture

local function compute_hole_value(h, stamps)
    if h.kind == "slot_disp" then
        local slot = stamps[h.param]
        assert(slot ~= nil, "missing slot stamp " .. tostring(h.param) .. " for hole " .. h.name)
        return slot * VALUE_SIZE + assert(h.field, "slot field required")
    end
    local key = h.param or h.name
    local v = stamps[key]
    assert(v ~= nil, "missing stamp " .. tostring(key) .. " for hole " .. h.name)
    return v
end

function M.validate_fixture(fixture)
    local errors = {}
    if type(fixture) ~= "table" or fixture.kind ~= "StencilFixture" then
        return false, { "fixture kind must be StencilFixture" }
    end
    if not stencils.by_name[fixture.spec_name] then
        errors[#errors + 1] = "unknown spec_name " .. tostring(fixture.spec_name)
    end
    local used = {}
    local function mark(kind, name, offset, width)
        if type(offset) ~= "number" or type(width) ~= "number" then
            errors[#errors + 1] = kind .. " " .. tostring(name) .. " has nonnumeric offset/width"
            return
        end
        if offset < 0 or width <= 0 or offset + width > #fixture.bytes then
            errors[#errors + 1] = kind .. " " .. tostring(name) .. " out of bounds"
            return
        end
        for i = offset + 1, offset + width do
            if used[i] then errors[#errors + 1] = kind .. " " .. tostring(name) .. " overlaps " .. used[i] end
            used[i] = kind .. ":" .. tostring(name)
        end
    end
    for _, h in ipairs(fixture.holes or {}) do mark("hole", h.name, h.offset, h.width) end
    for _, r in ipairs(fixture.relocs or {}) do mark("reloc", r.name, r.offset, r.width) end
    return #errors == 0, errors
end

function M.materialize(fixture, stamps, fixups)
    local ok, errors = M.validate_fixture(fixture)
    if not ok then error("invalid fixture " .. tostring(fixture and fixture.name) .. ": " .. table.concat(errors, "; ")) end
    stamps = stamps or {}
    fixups = fixups or {}
    local out = copy_list(fixture.bytes)
    for _, h in ipairs(fixture.holes or {}) do
        local value = compute_hole_value(h, stamps)
        write_le(out, h.offset, h.width, value)
    end
    for _, r in ipairs(fixture.relocs or {}) do
        local value = fixups[r.name]
        assert(value ~= nil or not r.required, "missing fixup for reloc " .. tostring(r.name))
        if value ~= nil then write_le(out, r.offset, r.width, value) end
    end
    return {
        kind = "MaterializedStencil",
        fixture = fixture,
        spec_name = fixture.spec_name,
        bytes = out,
        size = #out,
        executable = false,
    }
end

local function fixture_from_builder(spec_name, build, note)
    local b = byte_builder()
    build(b)
    return make_fixture { spec_name = spec_name, bytes = b.bytes, holes = b.holes, relocs = b.relocs, note = note }
end

local function fixed_u32(b, n)
    for _, x in ipairs(le_bytes(n, 4)) do b:emit(x) end
end

local function fixed_disp32(b, n)
    for _, x in ipairs(le_bytes(n, 4)) do b:emit(x) end
end

local function guard_table_identity(b, slot_param)
    b:emit(0x41, 0x83, 0xbe); slot_hole(b, slot_param .. "_tag_disp", slot_param, FIELD.tag); b:emit(const.Tag.TABLE)
    b:emit(0x0f, 0x85); b:reloc { name = "side_exit", kind = "rel32", width = 4 }
    b:emit(0x48, 0xb8); imm_hole(b, slot_param .. "_table_ptr", "ptr64", 8, "table_ptr")
    b:emit(0x49, 0x39, 0x86); slot_hole(b, slot_param .. "_bits_disp", slot_param, FIELD.bits)
    b:emit(0x0f, 0x85); b:reloc { name = "side_exit_2", kind = "rel32", width = 4, required = false }
end

local function guard_int_key(b, slot_param)
    b:emit(0x41, 0x83, 0xbe); slot_hole(b, slot_param .. "_tag_disp", slot_param, FIELD.tag); b:emit(const.Tag.INTEGER)
    b:emit(0x0f, 0x85); b:reloc { name = "side_exit_3", kind = "rel32", width = 4, required = false }
    b:emit(0x48, 0xb8); imm_hole(b, "expected_key", "imm64", 8, "expected_key")
    b:emit(0x49, 0x39, 0x86); slot_hole(b, slot_param .. "_bits_disp", slot_param, FIELD.bits)
    b:emit(0x0f, 0x85); b:reloc { name = "side_exit_4", kind = "rel32", width = 4, required = false }
end

local function load_value_ptr_to_regs(b, ptr_param)
    b:emit(0x48, 0xb8); imm_hole(b, ptr_param, "ptr64", 8, ptr_param)
    b:emit(0x44, 0x8b, 0x00)
    b:emit(0x44, 0x8b, 0x48, 0x04)
    b:emit(0x4c, 0x8b, 0x50, 0x08)
end

local function store_regs_to_slot(b, slot_param, prefix)
    prefix = prefix or "dst"
    b:emit(0x45, 0x89, 0x86); slot_hole(b, prefix .. "_tag_disp", slot_param, FIELD.tag)
    b:emit(0x45, 0x89, 0x8e); slot_hole(b, prefix .. "_aux_disp", slot_param, FIELD.aux)
    b:emit(0x4d, 0x89, 0x96); slot_hole(b, prefix .. "_bits_disp", slot_param, FIELD.bits)
end

local function load_slot_to_regs(b, slot_param, prefix)
    prefix = prefix or "src"
    b:emit(0x45, 0x8b, 0x86); slot_hole(b, prefix .. "_tag_disp", slot_param, FIELD.tag)
    b:emit(0x45, 0x8b, 0x8e); slot_hole(b, prefix .. "_aux_disp", slot_param, FIELD.aux)
    b:emit(0x4d, 0x8b, 0x96); slot_hole(b, prefix .. "_bits_disp", slot_param, FIELD.bits)
end

local function store_regs_to_value_ptr(b, ptr_param)
    b:emit(0x48, 0xb8); imm_hole(b, ptr_param, "ptr64", 8, ptr_param)
    b:emit(0x44, 0x89, 0x00)
    b:emit(0x44, 0x89, 0x48, 0x04)
    b:emit(0x4c, 0x89, 0x50, 0x08)
end

-- These byte phrases are executable x86-64 snippets using the v1 ABI concept
-- that r14 points at the base Value array.  tests/test_jit_native_stencils.lua
-- wraps them in a C-call adapter and checks them against the semantic contract.
local seed = {}

seed[#seed + 1] = fixture_from_builder("value.load_i64.imm_to_sA.fall", function(b)
    b:emit(0x41, 0xc7, 0x86); slot_hole(b, "dst_tag_disp", "a", FIELD.tag); fixed_u32(b, const.Tag.INTEGER)
    b:emit(0x41, 0xc7, 0x86); slot_hole(b, "dst_aux_disp", "a", FIELD.aux); fixed_u32(b, 0)
    b:emit(0x49, 0xb8); imm_hole(b, "imm_i64", "imm_i64", 8, "imm")
    b:emit(0x4d, 0x89, 0x86); slot_hole(b, "dst_bits_disp", "a", FIELD.bits)
end, "LOADI-style stack write fixture")

seed[#seed + 1] = fixture_from_builder("value.load_bool.tag_to_sA.fall", function(b)
    b:emit(0x41, 0xc7, 0x86); slot_hole(b, "dst_tag_disp", "a", FIELD.tag); imm_hole(b, "tag_imm32", "imm32", 4, "tag")
    b:emit(0x41, 0xc7, 0x86); slot_hole(b, "dst_aux_disp", "a", FIELD.aux); fixed_u32(b, 0)
    b:emit(0x49, 0xc7, 0x86); slot_hole(b, "dst_bits_disp", "a", FIELD.bits); fixed_u32(b, 0)
end, "LOADTRUE/LOADFALSE stack write fixture")

seed[#seed + 1] = fixture_from_builder("value.load_k.kB_to_sA.fall", function(b)
    b:emit(0x41, 0xc7, 0x86); slot_hole(b, "dst_tag_disp", "a", FIELD.tag); imm_hole(b, "tag_imm32", "imm32", 4, "tag")
    b:emit(0x41, 0xc7, 0x86); slot_hole(b, "dst_aux_disp", "a", FIELD.aux); imm_hole(b, "aux_imm32", "imm32", 4, "aux")
    b:emit(0x49, 0xb8); imm_hole(b, "bits_imm64", "imm64", 8, "bits")
    b:emit(0x4d, 0x89, 0x86); slot_hole(b, "dst_bits_disp", "a", FIELD.bits)
end, "LOADK literal Value stack write fixture")

seed[#seed + 1] = fixture_from_builder("value.load_nil.sA_count.fall", function(b)
    b:emit(0x49, 0x8d, 0x86); slot_hole(b, "dst_ptr_disp", "a", FIELD.tag)  -- lea rax,[r14+disp]
    b:emit(0xb9); imm_hole(b, "count_imm32", "imm32", 4, "count_plus_one") -- mov ecx,count
    -- loop:
    b:emit(0xc7, 0x00); fixed_u32(b, const.Tag.NIL) -- mov dword [rax], NIL
    b:emit(0xc7, 0x40, 0x04); fixed_u32(b, 0)      -- mov dword [rax+4], 0
    b:emit(0x48, 0xc7, 0x40, 0x08); fixed_u32(b, 0) -- mov qword [rax+8], 0
    b:emit(0x48, 0x83, 0xc0, 0x10)                 -- add rax, 16
    b:emit(0xff, 0xc9)                             -- dec ecx
    b:emit(0x75, 0xe3)                             -- jnz loop
end, "LOADNIL range fixture")

seed[#seed + 1] = fixture_from_builder("value.move.sB_to_sA.fall", function(b)
    b:emit(0x45, 0x8b, 0x86); slot_hole(b, "src_tag_disp", "b", FIELD.tag)
    b:emit(0x45, 0x8b, 0x8e); slot_hole(b, "src_aux_disp", "b", FIELD.aux)
    b:emit(0x4d, 0x8b, 0x96); slot_hole(b, "src_bits_disp", "b", FIELD.bits)
    b:emit(0x45, 0x89, 0x86); slot_hole(b, "dst_tag_disp", "a", FIELD.tag)
    b:emit(0x45, 0x89, 0x8e); slot_hole(b, "dst_aux_disp", "a", FIELD.aux)
    b:emit(0x4d, 0x89, 0x96); slot_hole(b, "dst_bits_disp", "a", FIELD.bits)
end, "MOVE scalar field copy fixture")

seed[#seed + 1] = fixture_from_builder("value.getupval.generic.sU_to_sA.fall", function(b)
    b:emit(0x48, 0xb8); imm_hole(b, "upvalue_ptr", "ptr64", 8, "upvalue_ptr") -- mov rax, Value*
    b:emit(0x44, 0x8b, 0x00)       -- mov r8d, [rax]
    b:emit(0x44, 0x8b, 0x48, 0x04) -- mov r9d, [rax+4]
    b:emit(0x4c, 0x8b, 0x50, 0x08) -- mov r10, [rax+8]
    b:emit(0x45, 0x89, 0x86); slot_hole(b, "dst_tag_disp", "a", FIELD.tag)
    b:emit(0x45, 0x89, 0x8e); slot_hole(b, "dst_aux_disp", "a", FIELD.aux)
    b:emit(0x4d, 0x89, 0x96); slot_hole(b, "dst_bits_disp", "a", FIELD.bits)
end, "GETUPVAL direct Value* copy fixture")

seed[#seed + 1] = fixture_from_builder("table.getfield_shape_ic1.sT_kName_to_sA.next_or_slow", function(b)
    guard_table_identity(b, "t")
    load_value_ptr_to_regs(b, "value_ptr")
    store_regs_to_slot(b, "a", "dst")
end, "GETFIELD shape IC1 direct Value* fixture")

seed[#seed + 1] = fixture_from_builder("table.setfield_shape_ic1.sT_kName_sV.next_or_slow_or_barrier", function(b)
    guard_table_identity(b, "t")
    load_slot_to_regs(b, "v", "val")
    store_regs_to_value_ptr(b, "value_ptr")
end, "SETFIELD shape IC1 direct Value* fixture")

seed[#seed + 1] = fixture_from_builder("table.gettable_array_i64_ic1.sT_sK_to_sA.next_or_slow", function(b)
    guard_table_identity(b, "t")
    guard_int_key(b, "k")
    load_value_ptr_to_regs(b, "value_ptr")
    store_regs_to_slot(b, "a", "dst")
end, "GETTABLE array i64 IC1 direct Value* fixture")

seed[#seed + 1] = fixture_from_builder("table.settable_array_i64_ic1.sT_sK_sV.next_or_slow_or_barrier", function(b)
    guard_table_identity(b, "t")
    guard_int_key(b, "k")
    load_slot_to_regs(b, "v", "val")
    store_regs_to_value_ptr(b, "value_ptr")
end, "SETTABLE array i64 IC1 direct Value* fixture")

seed[#seed + 1] = fixture_from_builder("table.self_field_ic1.sObj_kName_to_sFunc_sSelf.next_or_slow", function(b)
    load_slot_to_regs(b, "obj", "self_src")
    store_regs_to_slot(b, "self", "self_dst")
    guard_table_identity(b, "obj")
    load_value_ptr_to_regs(b, "value_ptr")
    store_regs_to_slot(b, "func", "func_dst")
end, "SELF field IC1 fixture")

seed[#seed + 1] = fixture_from_builder("outcome.call_boundary", function(b)
    b:emit(0x41, 0xc7, 0x85); fixed_disp32(b, 0); fixed_u32(b, 4) -- status = CALL_BOUNDARY
    b:emit(0x41, 0xc7, 0x85); fixed_disp32(b, 4); imm_hole(b, "call_id", "imm32", 4, "call_id")
    b:emit(0x48, 0xb8); imm_hole(b, "resume_pc", "imm64", 8, "resume_pc")
    b:emit(0x49, 0x89, 0x85); fixed_disp32(b, 8)
end, "write CALL_BOUNDARY NativeJitOutcome through r13")

seed[#seed + 1] = fixture_from_builder("call.generic.sF_args.boundary", function(b)
    b:emit(0xe9); b:reloc { name = "call_boundary", kind = "rel32", width = 4 }
end, "CALL boundary transfer fixture")

seed[#seed + 1] = fixture_from_builder("arith.add_i64_guarded.sB_sC_to_sA.next_or_exit", function(b)
    b:emit(0x41, 0x83, 0xbe); slot_hole(b, "lhs_tag_disp", "b", FIELD.tag); b:emit(const.Tag.INTEGER)
    b:emit(0x0f, 0x85); b:reloc { name = "side_exit", kind = "rel32", width = 4 }
    b:emit(0x41, 0x83, 0xbe); slot_hole(b, "rhs_tag_disp", "c", FIELD.tag); b:emit(const.Tag.INTEGER)
    b:emit(0x0f, 0x85); b:reloc { name = "side_exit_2", kind = "rel32", width = 4, required = false }
    b:emit(0x49, 0x8b, 0x86); slot_hole(b, "lhs_bits_disp", "b", FIELD.bits)
    b:emit(0x49, 0x03, 0x86); slot_hole(b, "rhs_bits_disp", "c", FIELD.bits)
    b:emit(0x41, 0xc7, 0x86); slot_hole(b, "dst_tag_disp", "a", FIELD.tag); fixed_u32(b, const.Tag.INTEGER)
    b:emit(0x41, 0xc7, 0x86); slot_hole(b, "dst_aux_disp", "a", FIELD.aux); fixed_u32(b, 0)
    b:emit(0x49, 0x89, 0x86); slot_hole(b, "dst_bits_disp", "a", FIELD.bits)
end, "guarded i64 ADD fixture")

seed[#seed + 1] = fixture_from_builder("arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit", function(b)
    b:emit(0x41, 0x83, 0xbe); slot_hole(b, "lhs_tag_disp", "b", FIELD.tag); b:emit(const.Tag.INTEGER)
    b:emit(0x0f, 0x85); b:reloc { name = "side_exit", kind = "rel32", width = 4 }
    b:emit(0x49, 0x8b, 0x86); slot_hole(b, "lhs_bits_disp", "b", FIELD.bits)
    b:emit(0x48, 0x05); imm_hole(b, "imm_i32", "imm_i32", 4, "imm")
    b:emit(0x41, 0xc7, 0x86); slot_hole(b, "dst_tag_disp", "a", FIELD.tag); fixed_u32(b, const.Tag.INTEGER)
    b:emit(0x41, 0xc7, 0x86); slot_hole(b, "dst_aux_disp", "a", FIELD.aux); fixed_u32(b, 0)
    b:emit(0x49, 0x89, 0x86); slot_hole(b, "dst_bits_disp", "a", FIELD.bits)
end, "guarded i64 ADDI fixture")

seed[#seed + 1] = fixture_from_builder("branch.test.sA.true_or_false", function(b)
    b:emit(0x41, 0x83, 0xbe); slot_hole(b, "src_tag_disp_nil", "a", FIELD.tag); b:emit(const.Tag.NIL)
    b:emit(0x0f, 0x84); b:reloc { name = "false_edge", kind = "rel32", width = 4 }
    b:emit(0x41, 0x83, 0xbe); slot_hole(b, "src_tag_disp_false", "a", FIELD.tag); b:emit(const.Tag.FALSE)
    b:emit(0x0f, 0x84); b:reloc { name = "false_edge_2", kind = "rel32", width = 4, required = false }
    b:emit(0xe9); b:reloc { name = "true_edge", kind = "rel32", width = 4 }
end, "truthiness TEST branch fixture")

seed[#seed + 1] = fixture_from_builder("branch.truthy.sA.true_or_false", function(b)
    b:emit(0x41, 0x83, 0xbe); slot_hole(b, "src_tag_disp_nil", "a", FIELD.tag); b:emit(const.Tag.NIL)
    b:emit(0x0f, 0x84); b:reloc { name = "false_edge", kind = "rel32", width = 4 }
    b:emit(0x41, 0x83, 0xbe); slot_hole(b, "src_tag_disp_false", "a", FIELD.tag); b:emit(const.Tag.FALSE)
    b:emit(0x0f, 0x84); b:reloc { name = "false_edge_2", kind = "rel32", width = 4, required = false }
    b:emit(0xe9); b:reloc { name = "true_edge", kind = "rel32", width = 4 }
end, "truthiness branch fixture")

seed[#seed + 1] = fixture_from_builder("edge.jump_label", function(b)
    b:emit(0xe9); b:reloc { name = "target", kind = "rel32", width = 4 }
end, "local block label jump")

seed[#seed + 1] = fixture_from_builder("outcome.ok", function(b)
    b:emit(0x41, 0xc7, 0x85); fixed_disp32(b, 0); fixed_u32(b, 0) -- status = OK
    b:emit(0x41, 0xc7, 0x85); fixed_disp32(b, 4); fixed_u32(b, 0) -- exit_id = 0
    b:emit(0x48, 0xb8); fixed_u32(b, 0); fixed_u32(b, 0)          -- rax = pc 0
    b:emit(0x49, 0x89, 0x85); fixed_disp32(b, 8)                  -- out.pc = rax
end, "write OK NativeJitOutcome through r13")

seed[#seed + 1] = fixture_from_builder("outcome.side_exit", function(b)
    b:emit(0x41, 0xc7, 0x85); fixed_disp32(b, 0); fixed_u32(b, 1) -- status = SIDE_EXIT
    b:emit(0x41, 0xc7, 0x85); fixed_disp32(b, 4); imm_hole(b, "exit_id", "imm32", 4, "exit_id")
    b:emit(0x48, 0xb8); imm_hole(b, "resume_pc", "imm64", 8, "resume_pc")
    b:emit(0x49, 0x89, 0x85); fixed_disp32(b, 8)
end, "write SIDE_EXIT NativeJitOutcome through r13")

local by_spec_name = {}
for _, f in ipairs(seed) do
    by_spec_name[f.spec_name] = by_spec_name[f.spec_name] or {}
    table.insert(by_spec_name[f.spec_name], f)
end

M.seed_fixtures = seed
M.by_spec_name = by_spec_name

function M.fixtures_for(spec_name)
    return by_spec_name[spec_name] or {}
end

function M.first_fixture(spec_name)
    local xs = M.fixtures_for(spec_name)
    return xs[1]
end

return M
