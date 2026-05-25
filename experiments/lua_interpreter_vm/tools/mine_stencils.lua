package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Proper empirical stencil miner foundation.
--
-- This tool deliberately emits a CandidateManifest, not a StencilLibrary.  The
-- manifest is evidence: StateOp pattern, generated kernel, extracted bytes,
-- discovered holes, relocations, and a completeness score.  Human/design review
-- promotes stable candidates into the actual copy-and-patch library later.
--
-- Usage:
--   luajit experiments/lua_interpreter_vm/tools/mine_stencils.lua [out_dir]

local moon = require("moonlift")
local C = require("experiments.lua_interpreter_vm.src.jit.miner_contracts")

local out_dir = arg[1] or "experiments/lua_interpreter_vm/build/stencil_mining"

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function run(cmd)
    local ok = os.execute(cmd)
    if ok ~= true and ok ~= 0 then error("command failed: " .. cmd) end
end

local function read_all(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function write_all(path, s)
    local f = assert(io.open(path, "wb"))
    f:write(s)
    f:close()
end

local function le32(n)
    local b = {}
    for i = 1, 4 do
        b[i] = n % 256
        n = math.floor(n / 256)
    end
    return b
end

local function bytes_to_hex(bs)
    local out = {}
    for i, b in ipairs(bs or {}) do out[i] = string.format("%02x", b) end
    return table.concat(out, " ")
end

local function scan_bytes(haystack, needle)
    local out = {}
    if not needle or #needle == 0 then return out end
    for i = 1, #haystack - #needle + 1 do
        local ok = true
        for j = 1, #needle do
            if haystack[i + j - 1] ~= needle[j] then ok = false; break end
        end
        if ok then out[#out + 1] = i - 1 end -- zero-based offset within symbol
    end
    return out
end

local VALUE_SIZE = 16
local DST_SLOT = 37
local LHS_SLOT = 41
local RHS_SLOT = 43
local ROOT_SLOT = 11

-- Keep the 64-bit marker <= 2^53 so it survives the current Lua-hosted
-- numeric-literal path exactly. Hex: 0x001f2e3d4c5b6a00.
local IMM64_BYTES = { 0x00, 0x6a, 0x5b, 0x4c, 0x3d, 0x2e, 0x1f, 0x00 }
local TAG_MARK_BYTES = le32(0x11223344)
local AUX_MARK_BYTES = le32(0x55667788)
local IMM32_BYTES = le32(0x12345678)

local function slot_disp(slot, field)
    return le32(slot * VALUE_SIZE + field)
end

local function H(name, kind, width, bytes, note, required)
    return C.HoleMarker { name = name, kind = kind, width = width, bytes = bytes, note = note, required = required }
end

local function R(name, symbol, kind, note, required)
    return C.RelocMarker { name = name, symbol = symbol, kind = kind, note = note, required = required }
end

local Op = C.StateOp
local function pattern(name, class, ops, effects, exits, projections, notes)
    return C.StatePattern { name = name, class = class, ops = ops, effects = effects, exits = exits, projections = projections, notes = notes }
end

local candidates = {
    C.StencilCandidate {
        name = "cand_loadi_slot_magic",
        class = "value.write",
        implements = "value.load_i64.imm_to_sA.fall",
        pattern = pattern("loadi_slot", "value.write", {
            Op("ConstInt", { value = "imm_i64" }),
            Op("WriteSlot", { slot = "dst", value = "const" }),
            Op("Jump", { target = "next" }),
        }, { "PURE" }),
        config_axes = { "dst=stack", "imm=stamp64", "cont=fallthrough" },
        holes = {
            H("dst_tag_disp", "slot_disp", 4, slot_disp(DST_SLOT, 0), "dst.tag displacement"),
            H("dst_aux_disp", "slot_disp", 4, slot_disp(DST_SLOT, 4), "dst.aux displacement"),
            H("dst_bits_disp", "slot_disp", 4, slot_disp(DST_SLOT, 8), "dst.bits displacement"),
            H("imm_i64", "imm64", 8, IMM64_BYTES, "integer payload immediate"),
        },
        source = [[
func cand_loadi_slot_magic(base: ptr(Value)) -> void
    let dst: ptr(Value) = base + 37
    dst.tag = 4
    dst.aux = 0
    dst.bits = 8776565086972416
    return
end
]],
    },

    C.StencilCandidate {
        name = "cand_project_slot_value_magic",
        class = "projection",
        implements = "project.slot.value_regs_to_slot",
        pattern = pattern("project_slot_value", "projection", {
            Op("ProjectSlot", { slot = "dst", value = "value" }),
        }, { "MATERIALIZE_VM_STATE" }, nil, { "INTERPRETER" }),
        config_axes = { "dst=stack", "tag=stamp32", "aux=stamp32", "bits=stamp64" },
        holes = {
            H("dst_tag_disp", "slot_disp", 4, slot_disp(DST_SLOT, 0), "dst.tag displacement"),
            H("dst_aux_disp", "slot_disp", 4, slot_disp(DST_SLOT, 4), "dst.aux displacement"),
            H("dst_bits_disp", "slot_disp", 4, slot_disp(DST_SLOT, 8), "dst.bits displacement"),
            H("tag_imm32", "imm32", 4, TAG_MARK_BYTES, "projected Value tag"),
            H("aux_imm32", "imm32", 4, AUX_MARK_BYTES, "projected Value aux"),
            H("bits_imm64", "imm64", 8, IMM64_BYTES, "projected Value bits"),
        },
        source = [[
func cand_project_slot_value_magic(base: ptr(Value)) -> void
    let dst: ptr(Value) = base + 37
    dst.tag = 287454020
    dst.aux = 1432778632
    dst.bits = 8776565086972416
    return
end
]],
    },

    C.StencilCandidate {
        name = "cand_move_slot_magic",
        class = "value.move",
        implements = "value.move.sB_to_sA.fall",
        pattern = pattern("move_slot", "value.move", {
            Op("ReadSlot", { slot = "src" }),
            Op("WriteSlot", { slot = "dst", value = "src" }),
            Op("Jump", { target = "next" }),
        }, { "PURE" }),
        config_axes = { "src=stack", "dst=stack", "cont=fallthrough" },
        holes = {
            H("src_tag_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 0), "src.tag displacement"),
            H("src_aux_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 4), "src.aux displacement"),
            H("src_bits_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 8), "src.bits displacement"),
            H("dst_tag_disp", "slot_disp", 4, slot_disp(DST_SLOT, 0), "dst.tag displacement"),
            H("dst_aux_disp", "slot_disp", 4, slot_disp(DST_SLOT, 4), "dst.aux displacement"),
            H("dst_bits_disp", "slot_disp", 4, slot_disp(DST_SLOT, 8), "dst.bits displacement"),
        },
        source = [[
func cand_move_slot_magic(base: ptr(Value)) -> void
    let src: ptr(Value) = base + 41
    let dst: ptr(Value) = base + 37
    let tag: u32 = src.tag
    let aux: u32 = src.aux
    let bits: u64 = src.bits
    dst.tag = tag
    dst.aux = aux
    dst.bits = bits
    return
end
]],
    },

    C.StencilCandidate {
        name = "cand_guard_int_slot_magic",
        class = "guard",
        pattern = pattern("guard_int_slot", "guard", {
            Op("ReadSlot", { slot = "src" }),
            Op("GuardTag", { tag = "INTEGER", exit = "side_exit" }),
        }, { "MAY_BRANCH" }, { "SIDE_EXIT" }),
        config_axes = { "src=stack", "fail=extern_reloc" },
        holes = {
            H("src_tag_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 0), "src.tag displacement"),
        },
        relocs = { R("side_exit", "jit_side_exit_i32", "side_exit", "cold side-exit target") },
        source = [[
func cand_guard_int_slot_magic(base: ptr(Value)) -> i32
    let src: ptr(Value) = base + 41
    if src.tag == 4 then return 0 end
    return jit_side_exit_i32()
end
]],
    },

    C.StencilCandidate {
        name = "cand_add_int_known_slot_magic",
        class = "arith.known",
        pattern = pattern("add_int_known_slot", "arith.known", {
            Op("ReadSlot", { slot = "lhs", fact = "Int" }),
            Op("ReadSlot", { slot = "rhs", fact = "Int" }),
            Op("AddIntWrap", { lhs = "lhs", rhs = "rhs" }),
            Op("WriteSlot", { slot = "dst", value = "sum" }),
            Op("Jump", { target = "next" }),
        }, { "PURE" }),
        config_axes = { "lhs=stack/int", "rhs=stack/int", "dst=stack", "cont=fallthrough" },
        holes = {
            H("lhs_bits_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 8), "lhs.bits displacement"),
            H("rhs_bits_disp", "slot_disp", 4, slot_disp(RHS_SLOT, 8), "rhs.bits displacement"),
            H("dst_tag_disp", "slot_disp", 4, slot_disp(DST_SLOT, 0), "dst.tag displacement"),
            H("dst_aux_disp", "slot_disp", 4, slot_disp(DST_SLOT, 4), "dst.aux displacement"),
            H("dst_bits_disp", "slot_disp", 4, slot_disp(DST_SLOT, 8), "dst.bits displacement"),
        },
        source = [[
func cand_add_int_known_slot_magic(base: ptr(Value)) -> void
    let lhs: ptr(Value) = base + 41
    let rhs: ptr(Value) = base + 43
    let dst: ptr(Value) = base + 37
    dst.tag = 4
    dst.aux = 0
    dst.bits = lhs.bits + rhs.bits
    return
end
]],
    },

    C.StencilCandidate {
        name = "cand_add_int_guarded_slot_magic",
        class = "arith.guarded",
        implements = "arith.add_i64_guarded.sB_sC_to_sA.next_or_exit",
        pattern = pattern("add_int_guarded_slot", "arith.guarded", {
            Op("ReadSlot", { slot = "lhs" }),
            Op("GuardTag", { value = "lhs", tag = "INTEGER", exit = "side_exit" }),
            Op("ReadSlot", { slot = "rhs" }),
            Op("GuardTag", { value = "rhs", tag = "INTEGER", exit = "side_exit" }),
            Op("AddIntWrap", { lhs = "lhs", rhs = "rhs" }),
            Op("WriteSlot", { slot = "dst", value = "sum" }),
            Op("Jump", { target = "next" }),
        }, { "MAY_BRANCH" }, { "SIDE_EXIT" }),
        config_axes = { "lhs=stack", "rhs=stack", "dst=stack", "fail=extern_reloc" },
        holes = {
            H("lhs_tag_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 0), "lhs.tag displacement"),
            H("rhs_tag_disp", "slot_disp", 4, slot_disp(RHS_SLOT, 0), "rhs.tag displacement"),
            H("lhs_bits_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 8), "lhs.bits displacement"),
            H("rhs_bits_disp", "slot_disp", 4, slot_disp(RHS_SLOT, 8), "rhs.bits displacement"),
            H("dst_tag_disp", "slot_disp", 4, slot_disp(DST_SLOT, 0), "dst.tag displacement"),
            H("dst_aux_disp", "slot_disp", 4, slot_disp(DST_SLOT, 4), "dst.aux displacement"),
            H("dst_bits_disp", "slot_disp", 4, slot_disp(DST_SLOT, 8), "dst.bits displacement"),
        },
        relocs = { R("side_exit", "jit_side_exit_i32", "side_exit", "cold side-exit target") },
        source = [[
func cand_add_int_guarded_slot_magic(base: ptr(Value)) -> i32
    let lhs: ptr(Value) = base + 41
    let rhs: ptr(Value) = base + 43
    let dst: ptr(Value) = base + 37
    if lhs.tag == 4 and rhs.tag == 4 then
        dst.tag = 4
        dst.aux = 0
        dst.bits = lhs.bits + rhs.bits
        return 0
    end
    return jit_side_exit_i32()
end
]],
    },

    C.StencilCandidate {
        name = "cand_addi_int_guarded_slot_magic",
        class = "arith.guarded_imm",
        implements = "arith.addi_i64_guarded.sB_imm_to_sA.next_or_exit",
        pattern = pattern("addi_int_guarded_slot", "arith.guarded_imm", {
            Op("ReadSlot", { slot = "lhs" }),
            Op("GuardTag", { value = "lhs", tag = "INTEGER", exit = "side_exit" }),
            Op("ConstInt", { value = "imm_i32" }),
            Op("AddIntWrap", { lhs = "lhs", rhs = "imm" }),
            Op("WriteSlot", { slot = "dst", value = "sum" }),
            Op("Jump", { target = "next" }),
        }, { "MAY_BRANCH" }, { "SIDE_EXIT" }),
        config_axes = { "lhs=stack", "rhs=imm32", "dst=stack", "fail=extern_reloc" },
        holes = {
            H("lhs_tag_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 0), "lhs.tag displacement"),
            H("lhs_bits_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 8), "lhs.bits displacement"),
            H("dst_tag_disp", "slot_disp", 4, slot_disp(DST_SLOT, 0), "dst.tag displacement"),
            H("dst_aux_disp", "slot_disp", 4, slot_disp(DST_SLOT, 4), "dst.aux displacement"),
            H("dst_bits_disp", "slot_disp", 4, slot_disp(DST_SLOT, 8), "dst.bits displacement"),
            H("imm_i32", "imm32", 4, IMM32_BYTES, "ADDI immediate"),
        },
        relocs = { R("side_exit", "jit_side_exit_i32", "side_exit", "cold side-exit target") },
        source = [[
func cand_addi_int_guarded_slot_magic(base: ptr(Value)) -> i32
    let lhs: ptr(Value) = base + 41
    let dst: ptr(Value) = base + 37
    if lhs.tag == 4 then
        dst.tag = 4
        dst.aux = 0
        dst.bits = lhs.bits + as(u64, 305419896)
        return 0
    end
    return jit_side_exit_i32()
end
]],
    },

    C.StencilCandidate {
        name = "cand_lt_int_guarded_slot_magic",
        class = "compare.guarded",
        pattern = pattern("lt_int_guarded_slot", "compare.guarded", {
            Op("ReadSlot", { slot = "lhs" }),
            Op("GuardTag", { value = "lhs", tag = "INTEGER", exit = "side_exit" }),
            Op("ReadSlot", { slot = "rhs" }),
            Op("GuardTag", { value = "rhs", tag = "INTEGER", exit = "side_exit" }),
            Op("LtInt", { lhs = "lhs", rhs = "rhs" }),
            Op("Branch", { cond = "lt", true_target = "true_edge", false_target = "false_edge" }),
        }, { "MAY_BRANCH" }, { "SIDE_EXIT", "TRUE_EDGE", "FALSE_EDGE" }),
        config_axes = { "lhs=stack", "rhs=stack", "true=extern_reloc", "false=extern_reloc", "fail=extern_reloc" },
        holes = {
            H("lhs_tag_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 0), "lhs.tag displacement"),
            H("rhs_tag_disp", "slot_disp", 4, slot_disp(RHS_SLOT, 0), "rhs.tag displacement"),
            H("lhs_bits_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 8), "lhs.bits displacement"),
            H("rhs_bits_disp", "slot_disp", 4, slot_disp(RHS_SLOT, 8), "rhs.bits displacement"),
        },
        relocs = {
            R("true_edge", "jit_true_edge_i32", "edge", "true continuation"),
            R("false_edge", "jit_false_edge_i32", "edge", "false continuation"),
            R("side_exit", "jit_side_exit_i32", "side_exit", "cold side-exit target"),
        },
        source = [[
func cand_lt_int_guarded_slot_magic(base: ptr(Value)) -> i32
    let lhs: ptr(Value) = base + 41
    let rhs: ptr(Value) = base + 43
    if lhs.tag == 4 and rhs.tag == 4 then
        if as(i64, lhs.bits) < as(i64, rhs.bits) then
            return jit_true_edge_i32()
        end
        return jit_false_edge_i32()
    end
    return jit_side_exit_i32()
end
]],
    },

    C.StencilCandidate {
        name = "cand_truthy_branch_slot_magic",
        class = "branch.truthiness",
        implements = "branch.truthy.sA.true_or_false",
        pattern = pattern("truthy_branch_slot", "branch.truthiness", {
            Op("ReadSlot", { slot = "src" }),
            Op("Truthy", { value = "src" }),
            Op("Branch", { cond = "truthy", true_target = "true_edge", false_target = "false_edge" }),
        }, { "MAY_BRANCH" }, { "TRUE_EDGE", "FALSE_EDGE" }),
        config_axes = { "src=stack", "true=extern_reloc", "false=extern_reloc" },
        holes = { H("src_tag_disp", "slot_disp", 4, slot_disp(LHS_SLOT, 0), "src.tag displacement") },
        relocs = {
            R("true_edge", "jit_true_edge_i32", "edge", "true continuation"),
            R("false_edge", "jit_false_edge_i32", "edge", "false continuation"),
        },
        source = [[
func cand_truthy_branch_slot_magic(base: ptr(Value)) -> i32
    let src: ptr(Value) = base + 41
    if src.tag == 0 then return jit_false_edge_i32() end
    if src.tag == 1 then return jit_false_edge_i32() end
    return jit_true_edge_i32()
end
]],
    },

    C.StencilCandidate {
        name = "cand_project_root_value_magic",
        class = "projection.root",
        pattern = pattern("project_root_value", "projection.root", {
            Op("ProjectRoot", { root = "root", value = "value" }),
        }, { "MATERIALIZE_ROOT" }, nil, { "ROOTS" }),
        config_axes = { "root_area=ptr", "root_index=stamp_disp", "tag=stamp32", "aux=stamp32", "bits=stamp64" },
        holes = {
            H("root_tag_disp", "root_disp", 4, slot_disp(ROOT_SLOT, 0), "root Value.tag displacement"),
            H("root_aux_disp", "root_disp", 4, slot_disp(ROOT_SLOT, 4), "root Value.aux displacement"),
            H("root_bits_disp", "root_disp", 4, slot_disp(ROOT_SLOT, 8), "root Value.bits displacement"),
            H("tag_imm32", "imm32", 4, TAG_MARK_BYTES, "root Value tag"),
            H("aux_imm32", "imm32", 4, AUX_MARK_BYTES, "root Value aux"),
            H("bits_imm64", "imm64", 8, IMM64_BYTES, "root Value bits"),
        },
        source = [[
func cand_project_root_value_magic(root: ptr(Value)) -> void
    let dst: ptr(Value) = root + 11
    dst.tag = 287454020
    dst.aux = 1432778632
    dst.bits = 8776565086972416
    return
end
]],
    },

    C.StencilCandidate {
        name = "cand_edge_load_target",
        class = "edge",
        implements = "edge.jump_indirect",
        pattern = pattern("edge_load_target", "edge", {
            Op("ReadEdgeTarget", { edge = "edge" }),
            Op("JumpIndirect", { target = "edge.target" }),
        }, { "MAY_BRANCH" }, { "EDGE_TARGET" }),
        config_axes = { "edge=reg", "target=memory" },
        source = [[
func cand_edge_load_target(edge: ptr(EdgeCell)) -> ptr(u8)
    return edge.target
end
]],
    },
}

local common_source = [[
extern jit_side_exit_i32() -> i32 end
extern jit_true_edge_i32() -> i32 end
extern jit_false_edge_i32() -> i32 end

struct Value
    tag: u32
    aux: u32
    bits: u64
end

struct EdgeCell
    target: ptr(u8)
    fallback: ptr(u8)
    target_unit: ptr(u8)
    kind: u8
    status: u8
    pad0: u16
    generation: u64
end

]]

local function generate_source()
    local parts = { common_source }
    for _, cand in ipairs(candidates) do
        parts[#parts + 1] = string.format("\n-- candidate: %s\n-- pattern: %s\n", cand.name, cand.pattern.canonical_key)
        parts[#parts + 1] = cand.source
    end
    return table.concat(parts, "\n")
end

local function parse_objdump(text)
    local symbols = {}
    local current = nil
    for line in text:gmatch("[^\n]+") do
        local addr, name = line:match("^%s*([0-9a-fA-F]+)%s+<([^>]+)>:")
        if addr then
            current = { name = name, base = tonumber(addr, 16), bytes = {}, instructions = {}, relocs = {} }
            symbols[name] = current
        elseif current then
            local off_hex, byte_text, asm = line:match("^%s*([0-9a-fA-F]+):%s+([0-9a-fA-F][0-9a-fA-F ]*)%s*(.*)$")
            if off_hex and byte_text then
                local off = tonumber(off_hex, 16)
                local inst_bytes = {}
                for hx in byte_text:gmatch("[0-9a-fA-F][0-9a-fA-F]") do
                    inst_bytes[#inst_bytes + 1] = tonumber(hx, 16)
                end
                local sym_off = off - current.base
                current.instructions[#current.instructions + 1] = { offset = sym_off, bytes = inst_bytes, asm = asm or "" }
                for i, b in ipairs(inst_bytes) do current.bytes[sym_off + i] = b end -- one-based dense by offset+1
            else
                local rel_off_hex, rel_kind, rel_value = line:match("^%s*([0-9a-fA-F]+):%s+(R_[%w_]+)%s+(.+)$")
                if rel_off_hex and rel_kind then
                    local abs = tonumber(rel_off_hex, 16)
                    current.relocs[#current.relocs + 1] = {
                        offset = abs - current.base,
                        type = rel_kind,
                        value = (rel_value:gsub("^%s+", ""):gsub("%s+$", "")),
                    }
                end
            end
        end
    end

    for _, sym in pairs(symbols) do
        local max = 0
        for i in pairs(sym.bytes) do if i > max then max = i end end
        for i = 1, max do sym.bytes[i] = sym.bytes[i] or 0 end
        sym.size = max
    end
    return symbols
end

local function extract_candidate(cand, sym)
    local found_holes, missing_holes = {}, {}
    for _, h in ipairs(cand.holes or {}) do
        local offsets = scan_bytes(sym.bytes, h.bytes)
        local rec = {
            name = h.name,
            kind = h.hole_kind,
            width = h.width,
            marker = bytes_to_hex(h.bytes),
            offsets = offsets,
            required = h.required,
            note = h.note,
        }
        found_holes[#found_holes + 1] = rec
        if h.required and #offsets == 0 then missing_holes[#missing_holes + 1] = h.name end
    end

    local found_relocs, missing_relocs = {}, {}
    for _, r in ipairs(cand.relocs or {}) do
        local matches = {}
        for _, rr in ipairs(sym.relocs or {}) do
            if rr.value:find(r.symbol, 1, true) then
                matches[#matches + 1] = { offset = rr.offset, type = rr.type, value = rr.value }
            end
        end
        found_relocs[#found_relocs + 1] = {
            name = r.name,
            kind = r.reloc_kind,
            symbol = r.symbol,
            matches = matches,
            required = r.required,
            note = r.note,
        }
        if r.required and #matches == 0 then missing_relocs[#missing_relocs + 1] = r.name end
    end

    local status = (#missing_holes == 0 and #missing_relocs == 0) and "complete" or "incomplete"
    local score = C.CandidateScore {
        size = sym.size or #sym.bytes,
        instruction_count = #(sym.instructions or {}),
        expected_holes = #(cand.holes or {}),
        found_holes = (function() local n = 0; for _, h in ipairs(found_holes) do if #h.offsets > 0 then n = n + 1 end end; return n end)(),
        expected_relocs = #(cand.relocs or {}),
        found_relocs = (function() local n = 0; for _, r in ipairs(found_relocs) do if #r.matches > 0 then n = n + 1 end end; return n end)(),
        missing_holes = missing_holes,
        missing_relocs = missing_relocs,
        status = status,
    }

    return {
        symbol = sym.name,
        size = sym.size,
        instruction_count = #(sym.instructions or {}),
        bytes_hex = bytes_to_hex(sym.bytes),
        holes = found_holes,
        relocs = found_relocs,
    }, score
end

local function write_report(path, manifest)
    local lines = {}
    lines[#lines + 1] = "# Stencil Candidate Mining Report"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "This is evidence, not the stencil library."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "| candidate | implements | class | size | insts | holes | relocs | status |"
    lines[#lines + 1] = "|---|---|---:|---:|---:|---:|---:|---|"
    for _, c in ipairs(manifest.candidates) do
        local s = c.score
        lines[#lines + 1] = string.format("| `%s` | `%s` | %s | %d | %d | %d/%d | %d/%d | %s |",
            c.name, c.implements or "", c.class, s.size, s.instruction_count,
            s.found_holes, s.expected_holes, s.found_relocs, s.expected_relocs, s.status)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Incomplete candidates"
    lines[#lines + 1] = ""
    local any = false
    for _, c in ipairs(manifest.candidates) do
        if c.score.status ~= "complete" then
            any = true
            lines[#lines + 1] = "- `" .. c.name .. "`"
            if #c.score.missing_holes > 0 then lines[#lines + 1] = "  - missing holes: " .. table.concat(c.score.missing_holes, ", ") end
            if #c.score.missing_relocs > 0 then lines[#lines + 1] = "  - missing relocs: " .. table.concat(c.score.missing_relocs, ", ") end
        end
    end
    if not any then lines[#lines + 1] = "None." end
    lines[#lines + 1] = ""
    write_all(path, table.concat(lines, "\n"))
end

run("mkdir -p " .. shell_quote(out_dir))

local src_path = out_dir .. "/candidates.mlua"
local obj_path = out_dir .. "/candidates.o"
local asm_path = out_dir .. "/candidates.asm"
local manifest_path = out_dir .. "/candidate_manifest.json"
local report_path = out_dir .. "/candidate_report.md"

local source = generate_source()
write_all(src_path, source)
local obj_bytes = moon.emit_object(source, obj_path, "lua_vm_stencil_candidates")
run(string.format("objdump -dr -Mintel %s > %s", shell_quote(obj_path), shell_quote(asm_path)))

local symbols = parse_objdump(read_all(asm_path))
local manifest_candidates = {}
for _, cand in ipairs(candidates) do
    local sym = symbols[cand.name]
    if not sym then
        manifest_candidates[#manifest_candidates + 1] = {
            name = cand.name,
            class = cand.class,
            pattern_name = cand.pattern.name,
            pattern_key = cand.pattern.canonical_key,
            implements = cand.implements,
            config_axes = cand.config_axes,
            note = cand.note,
            extracted = nil,
            score = C.CandidateScore { status = "missing_symbol", missing_holes = {}, missing_relocs = {} },
        }
    else
        local extracted, score = extract_candidate(cand, sym)
        manifest_candidates[#manifest_candidates + 1] = {
            name = cand.name,
            class = cand.class,
            pattern_name = cand.pattern.name,
            pattern_key = cand.pattern.canonical_key,
            implements = cand.implements,
            config_axes = cand.config_axes,
            semantic_pattern = cand.pattern,
            note = cand.note,
            extracted = extracted,
            score = score,
        }
    end
end

local target = io.popen("uname -m 2>/dev/null"):read("*l") or "unknown"
local manifest = C.CandidateManifest {
    target = target,
    source_path = src_path,
    object_path = obj_path,
    asm_path = asm_path,
    candidates = manifest_candidates,
}
local ok, errors = C.validate_manifest(manifest)
if not ok then error("invalid manifest: " .. table.concat(errors, "; ")) end

write_all(manifest_path, C.encode_json(manifest) .. "\n")
write_report(report_path, manifest)

print("wrote " .. src_path)
print("wrote " .. obj_path .. " (" .. tostring(#obj_bytes) .. " bytes)")
print("wrote " .. asm_path)
print("wrote " .. manifest_path)
print("wrote " .. report_path)
