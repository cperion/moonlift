#!/usr/bin/env luajit
-- materialize.lua — first real SponJIT copy/patch/link executor.
--
-- This is intentionally small and brutal: load GCC-extracted stencil bytes,
-- mmap RWX memory, copy stencils, rewrite stencil-local RETs to fallthrough,
-- patch relocation holes through a literal pool, and call the resulting code.
--
-- It is not the final VM integration. It is the executable boundary that proves
-- the artifact format can become runnable machine code.

local source = debug.getinfo(1, "S").source
local spongejit = source and source:sub(1, 1) == "@" and source:sub(2):match("^(.*)/runtime/materialize%.lua$") or "."
package.path = spongejit .. "/?.lua;" .. spongejit .. "/?/init.lua;" .. package.path

local ffi = require("ffi")

ffi.cdef[[
typedef unsigned long size_t;
typedef long ssize_t;
typedef long intptr_t;
typedef unsigned long uintptr_t;
typedef unsigned long long uint64_t;
typedef long long int64_t;
typedef unsigned int uint32_t;
typedef int int32_t;

void *mmap(void *addr, size_t length, int prot, int flags, int fd, long offset);
int munmap(void *addr, size_t length);
int mprotect(void *addr, size_t len, int prot);

struct LuaFrameMini {
  uint64_t *stack;
  uint64_t *constants;
};

struct StencilCtxMini {
  struct LuaFrameMini *frame;
  uint64_t current;
  int64_t acc;
};
]]

local Util = require("src.util")

local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4
local MAP_PRIVATE, MAP_ANON = 2, 0x20
local MAP_FAILED = ffi.cast("void *", -1)

local M = {}

local function hex_to_bytes(hex)
    local t = {}
    for b in tostring(hex or ""):gmatch("%x%x") do
        t[#t + 1] = string.char(tonumber(b, 16))
    end
    return table.concat(t)
end

local function put_u8(p, off, v)
    ffi.cast("uint8_t *", p)[off] = v
end

local function put_i32(p, off, v)
    ffi.cast("int32_t *", ffi.cast("uint8_t *", p) + off)[0] = ffi.cast("int32_t", v)
end

local function put_u64(p, off, v)
    ffi.cast("uint64_t *", ffi.cast("uint8_t *", p) + off)[0] = ffi.cast("uint64_t", v)
end

local function find_ret_offsets(bytes)
    -- GCC can emit both explicit inline-asm RETs and the function epilogue RET
    -- (`return1` is literally `c3 c3 ...`). During materialization all copied
    -- stencil RETs must become fallthrough edges to our single ABI epilogue.
    local out = {}
    for i = 1, #bytes do
        if bytes:byte(i) == 0xC3 then out[#out + 1] = i - 1 end -- zero-based
    end
    return out
end

local function stencil_lookup(lib, name)
    local full = name:match("^stencil_") and name or ("stencil_" .. name)
    local s = lib.stencils and lib.stencils[full]
    if not s then error("missing stencil " .. full) end
    return s
end

local function normalize_patch_key(kind)
    return tostring(kind or "")
        :gsub("^hole_", "")
        :gsub("%-0x%x+$", "")
end

function M.load_library(path)
    return assert(Util.read_json(path), "cannot read stencil library: " .. tostring(path))
end

function M.tagged_i64(i)
    return bit.bor(bit.lshift(0x0300ULL, 48), bit.band(ffi.cast("uint64_t", i), 0xFFFFFFFFFFFFULL))
end

function M.materialize(lib, stencil_names, patches)
    patches = patches or {}
    local parts = {}
    local holes = {}
    local code_size = 0

    local selected = {}
    for _, name in ipairs(stencil_names or {}) do
        selected[#selected + 1] = stencil_lookup(lib, name)
    end

    -- Robust C-stencil trampoline: CALL each copied stencil body, then RET.
    -- Bodies keep GCC's own RETs and internal branch layout intact.
    local tramp = {}
    local function tb(b) tramp[#tramp + 1] = string.char(b) end
    tb(0x48); tb(0x83); tb(0xEC); tb(0x08) -- sub rsp,8
    local call_sites = {}
    for _ = 1, #selected do
        call_sites[#call_sites + 1] = #tramp
        tb(0xE8); tb(0); tb(0); tb(0); tb(0) -- call rel32
    end
    tb(0x48); tb(0x83); tb(0xC4); tb(0x08) -- add rsp,8
    tb(0xC3)
    parts[#parts + 1] = table.concat(tramp)
    code_size = code_size + #parts[#parts]

    local body_offsets = {}
    for si, s in ipairs(selected) do
        local bytes = hex_to_bytes(s.bytes_hex)
        local start = code_size
        body_offsets[si] = start
        parts[#parts + 1] = bytes
        code_size = code_size + #bytes
        for _, h in ipairs(s.holes or {}) do
            assert(h.offset and h.offset >= 0 and h.offset < #bytes,
                string.format("bad hole offset for %s: %s size=%d", s.name, tostring(h.offset), #bytes))
            holes[#holes + 1] = {
                patch_offset = start + h.offset,
                kind = normalize_patch_key(h.kind),
                size = h.size or 4,
                reloc_type = h.reloc_type or "",
                stencil = s.name,
            }
        end
    end

    local patch_holes = {}
    local literal_cells = 0
    for _, h in ipairs(holes) do
        if h.patch_offset then
            h.literal_cells = tostring(h.reloc_type):match("GOTPCREL") and 2 or 1
            literal_cells = literal_cells + h.literal_cells
            patch_holes[#patch_holes + 1] = h
        end
    end
    local literal_size = literal_cells * 8
    local alloc_size = code_size + literal_size + 64

    local mem = ffi.C.mmap(nil, alloc_size, bit.bor(PROT_READ, PROT_WRITE, PROT_EXEC),
                           bit.bor(MAP_PRIVATE, MAP_ANON), -1, 0)
    assert(mem ~= MAP_FAILED, "mmap failed")

    local code = table.concat(parts)
    ffi.copy(mem, code, #code)

    -- Patch trampoline calls now that code is copied.
    for si, call0 in ipairs(call_sites) do
        local target0 = body_offsets[si]
        local rel = target0 - (call0 + 5)
        put_i32(mem, call0 + 1, rel)
    end

    local lit_base = code_size
    local lit_idx = 0
    for _, h in ipairs(patch_holes) do
        local key = h.kind
        local value = patches[key]
        if value == nil then
            -- Good default for guard/residual exits in smoke tests: return via
            -- epilogue by pointing exits at the epilogue address.
            if key == "exit_addr" or key == "target_pc" or key == "resume_pc" then
                value = tonumber(ffi.cast("uintptr_t", ffi.cast("uint8_t *", mem) + code_size - 2))
            else
                error(string.format("missing patch value kind=%s stencil=%s", key, h.stencil))
            end
        end
        local patch_addr = tonumber(ffi.cast("uintptr_t", ffi.cast("uint8_t *", mem) + h.patch_offset))
        local rel_target_addr
        if h.literal_cells == 2 then
            -- PIC external variable load pattern:
            --   mov hole@GOTPCREL(%rip), %reg
            --   ... load/deref through %reg ...
            -- The patched displacement must point at a GOT-like cell whose
            -- contents are the address of the actual per-artifact value cell.
            local got_off = lit_base + lit_idx * 8
            local val_off = got_off + 8
            local val_addr = tonumber(ffi.cast("uintptr_t", ffi.cast("uint8_t *", mem) + val_off))
            put_u64(mem, got_off, val_addr)
            put_u64(mem, val_off, value)
            rel_target_addr = tonumber(ffi.cast("uintptr_t", ffi.cast("uint8_t *", mem) + got_off))
            lit_idx = lit_idx + 2
        else
            local lit_off = lit_base + lit_idx * 8
            put_u64(mem, lit_off, value)
            rel_target_addr = tonumber(ffi.cast("uintptr_t", ffi.cast("uint8_t *", mem) + lit_off))
            lit_idx = lit_idx + 1
        end
        local rel = rel_target_addr - (patch_addr + 4)
        assert(rel >= -2147483648 and rel <= 2147483647, "literal pool too far for rel32")
        put_i32(mem, h.patch_offset, rel)
    end

    return {
        mem = mem,
        size = alloc_size,
        code_size = code_size,
        hole_count = #patch_holes,
        fn0 = ffi.cast("uint64_t (*)()", mem),
        fn_frame = ffi.cast("uint64_t (*)(struct LuaFrameMini *)", mem),
        fn_ctx = ffi.cast("void (*)(struct StencilCtxMini *)", mem),
    }
end

function M.free(inst)
    if inst and inst.mem then ffi.C.munmap(inst.mem, inst.size); inst.mem = nil end
end

local function selftest(lib_path)
    package.path = "src/?.lua;src/?/init.lua;" .. package.path
    local lib = M.load_library(lib_path or "build/stencil_library.json")

    local ctx = ffi.new("struct StencilCtxMini")
    ctx.frame = nil
    ctx.current = 0xffffffffffffffffULL
    ctx.acc = 0

    local nil_inst = M.materialize(lib, { "const_nil" })
    nil_inst.fn_ctx(ctx)
    print(string.format("const_nil => 0x%016x (%s)", tonumber(ctx.current), tonumber(ctx.current) == 0 and "ok" or "BAD"))
    M.free(nil_inst)

    ctx.current = M.tagged_i64(5)
    ctx.acc = 0
    local math_inst = M.materialize(lib, { "unbox_i64", "add_i64", "box_i64" })
    math_inst.fn_ctx(ctx)
    local want = M.tagged_i64(10)
    print(string.format("unbox+add+box => 0x%016x (%s)", tonumber(ctx.current), ctx.current == want and "ok" or "BAD"))
    M.free(math_inst)
end

M.selftest = selftest

local argv0 = arg and arg[0] and tostring(arg[0]) or ""
if argv0 == "materialize.lua" or argv0:match("/materialize%.lua$") then
    selftest(arg[1])
end

return M
